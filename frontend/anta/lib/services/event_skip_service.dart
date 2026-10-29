import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/event_skips.dart';
import '../constants/json_keys.dart';
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

  /// The first construction while it is in flight ([EventAlertService]'s
  /// pair), so two callers racing it share one load rather than each
  /// publishing its own.
  static Future<EventSkipService>? _initializing;

  /// Bumped by every [reset]. With [DatabaseLifecycle.generation] it is how a
  /// construction tells, past each of its awaits, that it has been overtaken:
  /// this counter covers a switch that reached this service (and a restore's
  /// deliberate re-init), the lifecycle's covers a switch that landed before
  /// the construction had registered its handler and so never called [reset]
  /// here at all.
  static int _generation = 0;

  late EventSkipDao _dao;

  EventSkipService._();

  static Future<EventSkipService> getInstance() =>
      _createOnce(AppDatabase.getInstance);

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO, the real CRDT stamping and the
  /// real facade against `NativeDatabase.memory()`. Never use it in app code —
  /// the singleton is what the [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<EventSkipService> forTesting(AppDatabase db) =>
      _createOnce(() async => db);

  /// One construction at a time, and never one a database switch overtook.
  ///
  /// A construction the switch overtook read the database that was just
  /// closed, so it discards itself and hands its caller the one the new
  /// database installs — otherwise [_instance] would hold a dead handle for
  /// the rest of the session while [CalendarEvent.occursOn] read the closed
  /// database's cancelled days.
  static Future<EventSkipService> _createOnce(
    Future<AppDatabase> Function() open,
  ) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<EventSkipService> creating;
    creating = () async {
      final generation = _generation;
      final lifecycle = DatabaseLifecycle.generation;
      bool overtaken() =>
          generation != _generation ||
          lifecycle != DatabaseLifecycle.generation;

      Future<EventSkipService> restart() async {
        if (identical(_initializing, creating)) _initializing = null;
        final service = await _createOnce(open);
        // This construction may already have published the closing
        // database's skips on its way through `_load`.
        service._publish();
        return service;
      }

      try {
        final db = await open();
        if (overtaken()) return await restart();
        final service = EventSkipService._();
        service._dao = db.eventSkipDao;
        await service._load();
        if (overtaken()) return await restart();
        _instance = service;
        DatabaseLifecycle.registerResetHandler(reset);
        return service;
      } finally {
        if (identical(_initializing, creating)) _initializing = null;
      }
    }();
    return _initializing = creating;
  }

  /// Drops the cached singleton and clears the static facade, so marks from a
  /// closed database cannot leak into render paths before the next
  /// [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
    EventSkips.resetCache();
  }

  /// Mutable working copy behind the published facade. Single-day mutations
  /// patch this and republish rather than re-reading the table — a toggle
  /// should not cost a full `SELECT` and map rebuild.
  Map<String, Set<DateTime>> _byEvent = {};

  /// How many [_load]s are still waiting on their rows.
  int _loadsInFlight = 0;

  /// Bumped by each single-day write once it has committed, so [_load] can
  /// tell that the rows it is holding predate one.
  int _writes = 0;

  Future<void> reload() => _load();

  /// Re-reads the whole delta into a fresh map, twice at most.
  ///
  /// Built locally and swapped in only once the rows are in: the cache used to
  /// be emptied before the `await`, so a single-day write landing inside that
  /// window — the sync pull's reload racing a Skip tap — republished the one
  /// event it patched out of an empty map, and every other skipped day of that
  /// event dropped out of `occursOn` until the load finished. [_publishFor]
  /// stays quiet for the same window, because the load's own publish is a
  /// microtask away. A write that commits while the rows are in flight is not
  /// in them, so they are re-read once rather than published without the day
  /// the user just cancelled.
  Future<void> _load() async {
    _loadsInFlight++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final writes = _writes;
        final next = <String, Set<DateTime>>{};
        try {
          final rows = await _dao.getActiveKeys();
          for (final row in rows) {
            (next[row.eventId] ??= <DateTime>{}).add(_dateOnlyUtc(row.day));
          }
        } catch (e) {
          debugPrint('[EventSkipService] Load error: $e');
          next.clear();
        }
        _byEvent = next;
        if (_writes == writes) break;
      }
    } finally {
      _loadsInFlight--;
    }
    _publish();
  }

  /// The snapshot the facade is currently serving. Held so [_publishFor] can
  /// **share** the entries it did not touch: every inner set here is already
  /// unmodifiable and is never rebuilt in place, so handing the same instance
  /// to the next snapshot is safe.
  Map<String, Set<DateTime>> _published = const {};

  /// Hands the facade an unmodifiable snapshot. Copied per publish so a later
  /// in-place patch can never mutate what render paths are already reading.
  ///
  /// The full rebuild, for [_load] and the bulk paths — where every event
  /// changed anyway, so a targeted republish would be strictly more work.
  void _publish() {
    _published = {
      for (final entry in _byEvent.entries)
        entry.key: Set.unmodifiable(Set<DateTime>.of(entry.value)),
    };
    EventSkips.updateCache(byEvent: _published);
  }

  /// Republish after a change confined to one event (**5.5**).
  ///
  /// Skipping a single day used to deep-copy **every** event's whole set; now
  /// only [eventId]'s set is rebuilt and the outer map is a pointer copy, so
  /// the cost follows the event that changed rather than the size of the
  /// store. The published-snapshots-are-immutable invariant is what makes the
  /// sharing safe, and it is unchanged: nothing here mutates a collection that
  /// has already been handed out, so a render path mid-read cannot see one
  /// shift underneath it.
  void _publishFor(String eventId) {
    if (_loadsInFlight > 0) return;
    final next = Map<String, Set<DateTime>>.of(_published);
    final days = _byEvent[eventId];
    if (days == null || days.isEmpty) {
      next.remove(eventId);
    } else {
      next[eventId] = Set.unmodifiable(Set<DateTime>.of(days));
    }
    _published = next;
    EventSkips.updateCache(byEvent: next);
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Cancels this occurrence. Idempotent: the DAO no-ops on an already-live
  /// skip rather than churning the version.
  ///
  /// Also clears any presence mark on the same day, through the presence
  /// service so its own facade stays in step: an occurrence that does not
  /// exist cannot have been attended or missed, and leaving the mark behind
  /// would resurface it the moment the skip is undone. This is the one caller
  /// of the tombstoning path.
  Future<void> markSkipped(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.markSkipped(eventId, key);
    _writes++;
    (_byEvent[eventId] ??= <DateTime>{}).add(key);
    _publishFor(eventId);
    try {
      final presence = await EventPresenceService.getInstance();
      await presence.clearMark(eventId, key);
    } catch (e) {
      debugPrint('[EventSkipService] Presence clear error: $e');
    }
  }

  /// Makes [next] the event's whole set of cancelled days, in **one** write.
  ///
  /// What the editor's Skipped days picker left behind, diffed against the
  /// cache here rather than day by day at the caller: a term's worth of days
  /// used to cost one transaction, one HLC, one outbox row, one day-cache
  /// rescan and one state emit each. Returns whether anything changed, so the
  /// bloc can skip all of that when an unchanged Save lands.
  ///
  /// Presence is cleared exactly as [markSkipped] clears it, one newly
  /// cancelled day at a time: those writes are no-ops for a day carrying no
  /// mark, and narrowing them on a published facade would miss a mark a pull
  /// has merged but not yet republished.
  Future<bool> setSkips(String eventId, Set<DateTime> next) async {
    final wanted = {for (final day in next) _dateOnlyUtc(day)};
    final current = _byEvent[eventId] ?? const <DateTime>{};
    final add = wanted.difference(current);
    final remove = current.difference(wanted);
    if (!await _dao.applySkipDiff(eventId, add: add, remove: remove)) {
      return false;
    }
    _writes++;
    final days = _byEvent[eventId] ??= <DateTime>{};
    days.addAll(add);
    days.removeAll(remove);
    if (days.isEmpty) _byEvent.remove(eventId);
    _publishFor(eventId);
    try {
      final presence = await EventPresenceService.getInstance();
      for (final day in add) {
        await presence.clearMark(eventId, day);
      }
    } catch (e) {
      debugPrint('[EventSkipService] Presence clear error: $e');
    }
    return true;
  }

  /// Restores this occurrence. The row survives as a tombstone — it is the
  /// ordered record of the toggle — but drops out of the cache and the facade
  /// immediately.
  Future<void> unskip(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.unskip(eventId, key);
    _writes++;
    final forEvent = _byEvent[eventId];
    if (forEvent != null) {
      forEvent.remove(key);
      if (forEvent.isEmpty) _byEvent.remove(eventId);
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
          if (row.ownerId != null) 'ownerId': row.ownerId,
        },
    ];
  }

  /// Wipe-then-reinsert, mirroring [CalendarEventService.importData]. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by
  /// the DAO, so a tombstone never round-trips a restore.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    // Parsed first, written once (**5.1**): the per-row `try` still guards
    // parsing, but the write is one batched transaction instead of one
    // awaited insert — and one WAL commit — per archived row.
    final companions = <EventSkipsCompanion>[];
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
        companions.add(
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
            ownerId: Value(JsonKeys.ownerIdOf(map)),
          ),
        );
      } catch (e) {
        debugPrint('[EventSkipService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
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
