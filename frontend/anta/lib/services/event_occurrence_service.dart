import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/occurrence_descriptions.dart';
import '../database/daos/event_occurrence_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';

/// Owns per-occurrence description overrides in `calendar_event_occurrences`
/// and publishes them to the synchronous [OccurrenceDescriptions] facade.
///
/// The table holds **only user deltas**, exactly like `public_holidays` since
/// v22: a row exists for an `(eventId, day)` pair only once that day has been
/// written on or ticked. Every other day resolves to the event's own
/// `description`, which acts as a template. That is what keeps the table
/// sparse and makes the whole feature reversible — turning an event's flag off
/// leaves its rows dormant rather than deleting them.
///
/// Scope is opted into **per event** via
/// `CalendarEvent.perOccurrenceDescriptions` (v28), the way presence is; the
/// single global switch v24 shipped is gone, and with it the flag machinery
/// this service used to carry. What survives from it is the
/// [PublicHolidayService] shape: the data is loaded at [getInstance] and
/// published with it, never configured from a page after the first frame.
///
/// All CRDT stamping lives in [EventOccurrenceDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live overrides only.
class EventOccurrenceService {
  static EventOccurrenceService? _instance;

  late EventOccurrenceDao _dao;

  EventOccurrenceService._();

  static Future<EventOccurrenceService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO, the real CRDT stamping and the
  /// real facade against `NativeDatabase.memory()`. Never use it in app code —
  /// the singleton is what the [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<EventOccurrenceService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<EventOccurrenceService> _create(AppDatabase db) async {
    final service = EventOccurrenceService._();
    service._dao = db.eventOccurrenceDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static facade, so overrides
  /// from a closed database cannot leak into render paths before the next
  /// [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    OccurrenceDescriptions.resetCache();
  }

  Future<void> reload() => _load();

  /// Mutable working copy behind the published facade. Single-row mutations
  /// patch this and republish rather than re-reading the table, mirroring
  /// `CalendarEventService.upsert` — a checkbox tick should not cost a full
  /// `SELECT` and map rebuild.
  final Map<String, Map<DateTime, String>> _byEvent = {};

  Future<void> _load() async {
    _byEvent.clear();
    try {
      final rows = await _dao.getActive();
      for (final row in rows) {
        (_byEvent[row.eventId] ??= {})[_dateOnlyUtc(row.day)] = row.description;
      }
    } catch (e) {
      debugPrint('[EventOccurrenceService] Load error: $e');
      _byEvent.clear();
    }
    _publish();
  }

  /// Hands the facade an unmodifiable snapshot. Copied per publish so a later
  /// in-place patch can never mutate what render paths are already reading.
  void _publish() {
    OccurrenceDescriptions.updateCache(
      byEvent: {
        for (final entry in _byEvent.entries)
          entry.key: Map.unmodifiable(Map<DateTime, String>.of(entry.value)),
      },
    );
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Materializes (or rewrites) one day's description. Storing `''` is
  /// meaningful — it blanks that day without falling back to the template.
  /// Use [clearDescription] to go back to the template.
  Future<void> setDescription(
    String eventId,
    DateTime day,
    String description,
  ) async {
    final now = DateTime.now();
    final key = _dateOnlyUtc(day);
    await _dao.upsert(
      EventOccurrenceDescriptionsCompanion(
        eventId: Value(eventId),
        day: Value(key),
        description: Value(description),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    (_byEvent[eventId] ??= {})[key] = description;
    _publish();
  }

  /// Returns one day to the template. The row survives as a tombstone — it is
  /// the ordered record of the reset — but drops out of the cache and the
  /// facade immediately. Distinct from writing `''`, which is a deliberately
  /// blank day.
  Future<void> clearDescription(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.tombstone(eventId, key);
    final forEvent = _byEvent[eventId];
    if (forEvent != null) {
      forEvent.remove(key);
      if (forEvent.isEmpty) _byEvent.remove(eventId);
    }
    _publish();
  }

  /// Cascade for a deleted event. Called inside the event service's delete
  /// transaction, so this only refreshes the published cache.
  Future<void> refreshAfterEventRemoval() => _load();

  Future<void> deleteAll() async {
    await _dao.deleteAll();
    await _load();
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live overrides only, without CRDT identity. Backups are not a sync
  /// channel: `BackupService` already excludes tombstones and identity for
  /// notes/folders, and identity is regenerated on restore.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getActive();
    return [
      for (final row in rows)
        {
          'eventId': row.eventId,
          'dayMs': row.day.millisecondsSinceEpoch,
          'description': row.description,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring [CalendarEventService.importData]. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by the
  /// DAO, so a tombstone never round-trips a restore.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final eventId = map['eventId'];
        final dayMs = map['dayMs'];
        final description = map['description'];
        if (eventId is! String || dayMs is! int || description is! String) {
          continue;
        }
        final createdAtMs = map['createdAtMs'];
        final updatedAtMs = map['updatedAtMs'];
        final now = DateTime.now();
        await _dao.importOccurrence(
          EventOccurrenceDescriptionsCompanion(
            eventId: Value(eventId),
            day: Value(
              _dateOnlyUtc(
                DateTime.fromMillisecondsSinceEpoch(dayMs, isUtc: true),
              ),
            ),
            description: Value(description),
            createdAt: Value(
              createdAtMs is int
                  ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
                  : now,
            ),
            updatedAt: Value(
              updatedAtMs is int
                  ? DateTime.fromMillisecondsSinceEpoch(updatedAtMs)
                  : now,
            ),
          ),
        );
      } catch (e) {
        debugPrint('[EventOccurrenceService] Import row error: $e');
      }
    }
    await _load();
  }

  /// Clears every override. Used when restoring a backup that carried events
  /// but no occurrence key: the event import wipes and reinserts, so keeping
  /// the previous database's overrides would strand them against unrelated
  /// event ids.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    await _load();
  }

  /// Drift returns `DateTime` in local time when reading an int-epoch column,
  /// so naive `.year/.month/.day` extraction after we wrote `DateTime.utc(...)`
  /// can shift the date by one day in non-UTC zones. Recover the original UTC
  /// date via the epoch milliseconds — same helper shape as
  /// `CalendarEventService._dateOnlyUtc`.
  static DateTime _dateOnlyUtc(DateTime value) {
    final asUtc = DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
    return DateTime.utc(asUtc.year, asUtc.month, asUtc.day);
  }
}
