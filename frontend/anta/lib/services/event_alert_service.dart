import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/event_alerts.dart';
import '../database/daos/event_alert_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/event_alert.dart';

/// Owns the rows of `calendar_event_alerts` and publishes them to the
/// synchronous [EventAlerts] facade.
///
/// The [EventSkipService] shape verbatim — loaded at [getInstance] and
/// published with it, never configured from a page after the first frame —
/// because the same thing is true here as there: the facade is read
/// synchronously while rows are being built, and an unconfigured read is
/// *silent*. An event with an alarm would simply draw as an event without
/// one, and the scheduler would plan nothing for it.
///
/// That is why this joins the calendar's `Future.wait` rather than sitting in
/// GetIt: GetIt holds the *object*, so after a database switch it would hand
/// back one bound to a closed database, while `getInstance()` is self-healing.
///
/// All CRDT stamping lives in [EventAlertDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live alerts only.
class EventAlertService {
  static EventAlertService? _instance;

  late EventAlertDao _dao;

  EventAlertService._();

  static Future<EventAlertService> getInstance() async {
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
  static Future<EventAlertService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<EventAlertService> _create(AppDatabase db) async {
    final service = EventAlertService._();
    service._dao = db.eventAlertDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static facade, so alerts from a
  /// closed database cannot leak into render paths — or into a plan — before
  /// the next [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    EventAlerts.resetCache();
  }

  /// Mutable working copy behind the published facade. A single event's edit
  /// patches this and republishes rather than re-reading the table.
  final Map<String, List<EventAlert>> _byEvent = {};

  Future<void> reload() => _load();

  Future<void> _load() async {
    _byEvent.clear();
    try {
      final rows = await _dao.getAllActive();
      for (final row in rows) {
        (_byEvent[row.eventId] ??= <EventAlert>[]).add(_rowToAlert(row));
      }
    } catch (e) {
      debugPrint('[EventAlertService] Load error: $e');
      _byEvent.clear();
    }
    _publish();
  }

  /// The snapshot the facade is currently serving. Held so [_publishFor] can
  /// **share** the entries it did not touch: every inner list here is already
  /// unmodifiable and is never rebuilt in place, so handing the same instance
  /// to the next snapshot is safe.
  Map<String, List<EventAlert>> _published = const {};

  /// The full rebuild, for [_load] and the bulk paths — where every event
  /// changed anyway, so a targeted republish would be strictly more work.
  void _publish() {
    _published = {
      for (final entry in _byEvent.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    EventAlerts.updateCache(byEvent: _published);
  }

  /// Republish after a change confined to one event: only [eventId]'s list is
  /// rebuilt and the outer map is a pointer copy, so the cost follows the
  /// event that changed rather than the size of the store.
  void _publishFor(String eventId) {
    final next = Map<String, List<EventAlert>>.of(_published);
    final alerts = _byEvent[eventId];
    if (alerts == null || alerts.isEmpty) {
      next.remove(eventId);
    } else {
      next[eventId] = List.unmodifiable(alerts);
    }
    _published = next;
    EventAlerts.updateCache(byEvent: next);
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Makes [alerts] the complete set for [eventId]: removed alerts are
  /// tombstoned, kept ones re-stamped, new ones inserted — one transaction in
  /// the DAO, one republish here.
  ///
  /// The single write path for the editor, so there is exactly one place a
  /// saved event's alerts can diverge from what the sheet showed.
  Future<void> replaceForEvent(String eventId, List<EventAlert> alerts) async {
    final owned = [
      for (final alert in alerts)
        alert.eventId == eventId ? alert : alert.copyWith(eventId: eventId),
    ];
    await _dao.replaceForEvent(eventId, [
      for (final alert in owned) _toCompanion(alert),
    ]);
    if (owned.isEmpty) {
      _byEvent.remove(eventId);
    } else {
      _byEvent[eventId] = owned;
    }
    _publishFor(eventId);
  }

  /// Cascade for a deleted event. Called after the event service's delete
  /// transaction, so this only refreshes the published cache.
  Future<void> refreshAfterEventRemoval() => _load();

  Future<void> deleteAll() async {
    await _dao.deleteAll();
    await _load();
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live alerts only, without CRDT identity. Backups are not a sync channel:
  /// identity is regenerated on restore, exactly as it is for notes, folders
  /// and skips.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAllActive();
    return [
      for (final row in rows)
        {
          ..._rowToAlert(row).toJson(),
          EventAlertKeys.createdAtMs: row.createdAt.millisecondsSinceEpoch,
          EventAlertKeys.updatedAtMs: row.updatedAt.millisecondsSinceEpoch,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring `CalendarEventService.importData`. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by
  /// the DAO, so a tombstone never round-trips a restore.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    // Parsed first, written once: the per-row guard still skips one malformed
    // archive row, but the write is a single batched transaction rather than
    // one awaited insert — and one WAL commit — per restored alert.
    final companions = <EventAlertsCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final alert = EventAlert.fromJson(map);
        if (alert == null) continue;
        final now = DateTime.now();
        final createdMs = map[EventAlertKeys.createdAtMs];
        final updatedMs = map[EventAlertKeys.updatedAtMs];
        companions.add(
          _toCompanion(
            alert,
            createdAt: createdMs is int
                ? DateTime.fromMillisecondsSinceEpoch(createdMs)
                : now,
            updatedAt: updatedMs is int
                ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
                : now,
          ),
        );
      } catch (e) {
        debugPrint('[EventAlertService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _load();
  }

  /// Clears every alert. Used when restoring a backup that carried events but
  /// no alert key: the event import wipes and reinserts, so keeping the
  /// previous database's alerts would strand them against unrelated event ids
  /// — and a stranded alert does not merely render wrong, it *rings*.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    await _load();
  }

  // ── Row ↔ Domain mapping ─────────────────────────────────────────────

  static EventAlert _rowToAlert(EventAlertRow row) {
    return EventAlert(
      id: row.id,
      eventId: row.eventId,
      mode: AlertMode.fromName(row.mode),
      offsetMinutes: row.offsetMinutes,
      daysBefore: row.daysBefore,
      dayMinute: row.dayMinute,
      sound: row.sound,
      enabled: row.enabled,
    );
  }

  static EventAlertsCompanion _toCompanion(
    EventAlert alert, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EventAlertsCompanion(
      id: Value(alert.id),
      eventId: Value(alert.eventId),
      mode: Value(alert.mode.name),
      offsetMinutes: Value(alert.offsetMinutes),
      daysBefore: Value(alert.daysBefore),
      dayMinute: Value(alert.dayMinute),
      sound: Value(alert.sound),
      enabled: Value(alert.enabled),
      createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
      updatedAt: updatedAt == null ? const Value.absent() : Value(updatedAt),
    );
  }
}
