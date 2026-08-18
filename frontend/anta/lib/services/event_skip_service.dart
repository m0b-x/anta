import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/event_skips.dart';
import '../database/daos/event_skip_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import 'event_presence_service.dart';

/// Owns cancelled occurrences in `calendar_event_skips` and publishes them to
/// the synchronous [EventSkips] facade.
///
/// The table holds **only user deltas**: a live row means that occurrence does
/// not exist, and every other day of the rule occurs normally. A daily event
/// therefore costs zero rows until a day is actually cancelled, exactly like
/// `calendar_event_occurrences` since v24.
///
/// No opt-in flag, unlike presence: any recurring event has occurrences to
/// cancel. What does carry over is the [PublicHolidayService] shape — the data
/// is loaded at [getInstance] and published with it, never configured from a
/// page after the first frame — which matters more here, because
/// [CalendarEvent.occursOn] reads the facade synchronously during layout.
///
/// All CRDT stamping lives in [EventSkipDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live skips only.
class EventSkipService {
  static EventSkipService? _instance;

  late EventSkipDao _dao;

  EventSkipService._();

  static Future<EventSkipService> getInstance() async {
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
  static Future<EventSkipService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<EventSkipService> _create(AppDatabase db) async {
    final service = EventSkipService._();
    service._dao = db.eventSkipDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static facade, so marks from a
  /// closed database cannot leak into render paths before the next
  /// [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    EventSkips.resetCache();
  }

  /// Mutable working copy behind the published facade. Single-day mutations
  /// patch this and republish rather than re-reading the table — a toggle
  /// should not cost a full `SELECT` and map rebuild.
  final Map<String, Set<DateTime>> _byEvent = {};

  Future<void> reload() => _load();

  Future<void> _load() async {
    _byEvent.clear();
    try {
      final rows = await _dao.getActive();
      for (final row in rows) {
        (_byEvent[row.eventId] ??= <DateTime>{}).add(_dateOnlyUtc(row.day));
      }
    } catch (e) {
      debugPrint('[EventSkipService] Load error: $e');
      _byEvent.clear();
    }
    _publish();
  }

  /// Hands the facade an unmodifiable snapshot. Copied per publish so a later
  /// in-place patch can never mutate what render paths are already reading.
  void _publish() {
    EventSkips.updateCache(
      byEvent: {
        for (final entry in _byEvent.entries)
          entry.key: Set.unmodifiable(Set<DateTime>.of(entry.value)),
      },
    );
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Cancels this occurrence. Idempotent: the DAO no-ops on an already-live
  /// skip rather than churning the version.
  ///
  /// Also clears any absence mark on the same day, through the presence
  /// service so its own facade stays in step: an occurrence that does not
  /// exist cannot have been missed, and leaving the mark behind would resurface
  /// it the moment the skip is undone.
  Future<void> markSkipped(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.markSkipped(eventId, key);
    (_byEvent[eventId] ??= <DateTime>{}).add(key);
    _publish();
    try {
      final presence = await EventPresenceService.getInstance();
      await presence.unmark(eventId, key);
    } catch (e) {
      debugPrint('[EventSkipService] Presence clear error: $e');
    }
  }

  /// Restores this occurrence. The row survives as a tombstone — it is the
  /// ordered record of the toggle — but drops out of the cache and the facade
  /// immediately.
  Future<void> unskip(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.unskip(eventId, key);
    final forEvent = _byEvent[eventId];
    if (forEvent != null) {
      forEvent.remove(key);
      if (forEvent.isEmpty) _byEvent.remove(eventId);
    }
    _publish();
  }

  /// Cascade for a deleted event. Called after the event service's delete
  /// transaction, so this only refreshes the published cache.
  Future<void> refreshAfterEventRemoval() => _load();

  Future<void> deleteAll() async {
    await _dao.deleteAll();
    await _load();
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live skips only, without CRDT identity. Backups are not a sync channel:
  /// `BackupService` already excludes tombstones and identity for
  /// notes/folders, and identity is regenerated on restore.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getActive();
    return [
      for (final row in rows)
        {
          'eventId': row.eventId,
          'dayMs': row.day.millisecondsSinceEpoch,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring [CalendarEventService.importData]. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by
  /// the DAO, so a tombstone never round-trips a restore.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final eventId = map['eventId'];
        final dayMs = map['dayMs'];
        if (eventId is! String || dayMs is! int) continue;
        final createdAtMs = map['createdAtMs'];
        final updatedAtMs = map['updatedAtMs'];
        final now = DateTime.now();
        await _dao.importSkip(
          EventSkipsCompanion(
            eventId: Value(eventId),
            day: Value(
              _dateOnlyUtc(
                DateTime.fromMillisecondsSinceEpoch(dayMs, isUtc: true),
              ),
            ),
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
        debugPrint('[EventSkipService] Import row error: $e');
      }
    }
    await _load();
  }

  /// Clears every skip. Used when restoring a backup that carried events but
  /// no skip key: the event import wipes and reinserts, so keeping the
  /// previous database's skips would strand them against unrelated event ids.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    await _load();
  }

  /// Drift returns `DateTime` in local time when reading an int-epoch column,
  /// so naive `.year/.month/.day` extraction after we wrote `DateTime.utc(...)`
  /// can shift the date by one day in non-UTC zones. Recover the original UTC
  /// date via the epoch milliseconds — same helper shape as
  /// `EventOccurrenceService._dateOnlyUtc`.
  static DateTime _dateOnlyUtc(DateTime value) {
    final asUtc = DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
    return DateTime.utc(asUtc.year, asUtc.month, asUtc.day);
  }
}
