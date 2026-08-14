import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/occurrence_descriptions.dart';
import '../constants/settings_keys.dart';
import '../database/daos/event_occurrence_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';

/// Owns per-occurrence description overrides in `calendar_event_occurrences`
/// and publishes them to the synchronous [OccurrenceDescriptions] facade.
///
/// The table holds **only user deltas**, exactly like `public_holidays` since
/// v22: a row exists for a `(eventId, day)` pair only once that day has been
/// written on or ticked. Every other day resolves to the event's own
/// `description`, which acts as a template. That is what keeps the table
/// sparse and makes the whole feature reversible — turning the setting off
/// leaves the rows dormant rather than deleting them.
///
/// The enabled flag is read here at [getInstance] and published *with* the
/// data, following [PublicHolidayService] rather than `FastingCalendar`: the
/// latter is configured from `CalendarPage._loadSettings` after the first
/// frame, which on a cold start into the calendar would render templates for
/// one frame and then flip every row.
class EventOccurrenceService {
  static EventOccurrenceService? _instance;

  late AppDatabase _db;
  late EventOccurrenceDao _dao;
  bool _enabled = SettingsKeys.defaultEventPerOccurrenceDescriptions;

  EventOccurrenceService._();

  static Future<EventOccurrenceService> getInstance() async {
    if (_instance != null) return _instance!;
    final service = EventOccurrenceService._();
    service._db = await AppDatabase.getInstance();
    service._dao = service._db.eventOccurrenceDao;
    service._enabled = await service._readEnabled();
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

  bool get enabled => _enabled;

  /// Turns per-occurrence descriptions on or off. Writes the setting and
  /// republishes in one step — the only supported way to change the flag, so
  /// the facade can never disagree with `user_settings`. Rows are never
  /// touched: switching off makes them dormant, switching back on restores
  /// exactly what was there.
  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    await _db.userSettingsDao.setValue(
      SettingsKeys.eventPerOccurrenceDescriptions,
      value.toString(),
    );
    _enabled = value;
    await _load();
  }

  Future<bool> _readEnabled() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.eventPerOccurrenceDescriptions,
    );
    if (raw == null) return SettingsKeys.defaultEventPerOccurrenceDescriptions;
    return raw == 'true';
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
      final rows = await _dao.getAll();
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
      enabled: _enabled,
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

  /// Deletes one day's override, returning that day to the template. Distinct
  /// from writing `''`, which is a deliberately blank day.
  Future<void> clearDescription(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.deleteFor(eventId, key);
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

  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
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

  /// Wipe-then-reinsert, mirroring [CalendarEventService.importData]. Also
  /// re-reads the enabled flag: `BackupService.importFromJson` replays the
  /// backup's `settings` map straight into `user_settings` and republishes
  /// nothing, so without this the facade would keep the pre-import flag.
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
        await _dao.upsert(
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
    _enabled = await _readEnabled();
    await _load();
  }

  /// Clears every override without touching the setting. Used when restoring
  /// a backup that carried events but no occurrence key: the event import
  /// wipes and reinserts, so keeping the previous database's overrides would
  /// strand them against unrelated event ids.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    _enabled = await _readEnabled();
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
