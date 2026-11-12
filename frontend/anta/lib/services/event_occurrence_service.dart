import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../constants/json_keys.dart';
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

  /// The construction [_create] has in flight, so concurrent callers share
  /// one load and an event delete can patch an instance still reading the
  /// table instead of missing it.
  static Future<EventOccurrenceService>? _creating;

  static Future<EventOccurrenceService> _create(AppDatabase db) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _creating;
    if (pending != null) return pending;
    final completer = Completer<EventOccurrenceService>();
    final creating = _creating = completer.future;
    completer.complete(() async {
      try {
        final service = EventOccurrenceService._();
        service._dao = db.eventOccurrenceDao;
        await service._load();
        _instance = service;
        DatabaseLifecycle.registerResetHandler(reset);
        return service;
      } finally {
        if (identical(_creating, creating)) _creating = null;
      }
    }());
    return creating;
  }

  /// Drops the cached singleton and clears the static facade, so overrides
  /// from a closed database cannot leak into render paths before the next
  /// [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    _creating = null;
    OccurrenceDescriptions.resetCache();
  }

  /// The live instance, or the one [_create] is still reading; never a new
  /// one — with neither, nothing is published, and the next [getInstance]
  /// reads the table as the caller's write left it.
  static Future<EventOccurrenceService?> _liveOrCreating() async {
    final pending = _creating;
    if (_instance != null || pending == null) return _instance;
    try {
      // A reset while it was awaited retired it: its days must not reach
      // the facade the reset cleared.
      final built = await pending;
      return identical(_instance, built) ? built : null;
    } catch (_) {
      // The construction's failure is its own caller's to report.
      return null;
    }
  }

  /// Drops [eventId]'s day descriptions from the facade after the event's
  /// delete tombstoned them in its own transaction — that event alone, where
  /// the whole table used to be read again for one delete.
  static Future<void> forgetEvent(String eventId) async =>
      (await _liveOrCreating())?._patchEvent(eventId, null);

  /// Adds [eventId]'s [descriptions] back after `restoreCascade` revived
  /// them, from the set it was handed rather than a read.
  static Future<void> restoreEvent(
    String eventId,
    Map<DateTime, String> descriptions,
  ) async => (await _liveOrCreating())?._patchEvent(eventId, {
    for (final MapEntry(key: day, value: text) in descriptions.entries)
      _dateOnlyUtc(day): text,
  });

  /// One event's days dropped ([days] null) or added to. Counted as a write,
  /// so a load whose rows may predate the cascade reads again rather than
  /// publishing them over this.
  void _patchEvent(String eventId, Map<DateTime, String>? days) {
    _writes++;
    if (days == null) {
      _byEvent.remove(eventId);
    } else if (days.isNotEmpty) {
      (_byEvent[eventId] ??= {}).addAll(days);
    }
    _publishFor(eventId);
  }

  Future<void> reload() => _load();

  /// Mutable working copy behind the published facade. Single-row mutations
  /// patch this and republish rather than re-reading the table, mirroring
  /// `CalendarEventService.upsert` — a checkbox tick should not cost a full
  /// `SELECT` and map rebuild.
  Map<String, Map<DateTime, String>> _byEvent = {};

  /// How many [_load]s are still waiting on their rows.
  int _loadsInFlight = 0;

  /// Bumped by each single-row write once it has committed, so [_load] can
  /// tell that the rows it is holding predate one.
  int _writes = 0;

  /// Re-reads the whole delta into a fresh map, twice at most — the skip
  /// service's shape, for the same race.
  ///
  /// Built locally and swapped in only once the rows are in: the cache used to
  /// be emptied before the `await`, so a write landing inside that window — a
  /// sync reload racing a quick description edit — republished the one event it
  /// patched out of an empty map and every other day's text of that event fell
  /// back to the template until the load finished. [_publishFor] stays quiet
  /// for the same window, and a write that commits while the rows are in
  /// flight is not in them, so they are re-read once rather than published
  /// without the text the user just typed.
  Future<void> _load() async {
    _loadsInFlight++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final writes = _writes;
        final next = <String, Map<DateTime, String>>{};
        try {
          final rows = await _dao.getActive();
          for (final row in rows) {
            (next[row.eventId] ??= {})[_dateOnlyUtc(row.day)] = row.description;
          }
        } catch (e) {
          debugPrint('[EventOccurrenceService] Load error: $e');
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
  /// **share** the entries it did not touch: every inner map here is already
  /// unmodifiable and is never rebuilt in place, so handing the same instance
  /// to the next snapshot is safe.
  Map<String, Map<DateTime, String>> _published = const {};

  /// Hands the facade an unmodifiable snapshot. Copied per publish so a later
  /// in-place patch can never mutate what render paths are already reading.
  ///
  /// The full rebuild, for [_load] and the bulk paths — where every event
  /// changed anyway, so a targeted republish would be strictly more work.
  void _publish() {
    _published = {
      for (final entry in _byEvent.entries)
        entry.key: Map.unmodifiable(Map<DateTime, String>.of(entry.value)),
    };
    OccurrenceDescriptions.updateCache(byEvent: _published);
  }

  /// Republish after a change confined to one event (**5.5**).
  ///
  /// Editing a single day's text used to deep-copy **every** event's whole
  /// override map — the most expensive of the three overlays, since the values
  /// are description strings. Now only [eventId]'s map is rebuilt and the
  /// outer map is a pointer copy, so the cost follows the event that changed
  /// rather than the size of the store. The published-snapshots-are-immutable
  /// invariant is what makes the sharing safe, and it is unchanged: nothing
  /// here mutates a collection that has already been handed out, so a render
  /// path mid-read cannot see one shift underneath it.
  void _publishFor(String eventId) {
    if (_loadsInFlight > 0) return;
    final next = Map<String, Map<DateTime, String>>.of(_published);
    final days = _byEvent[eventId];
    if (days == null || days.isEmpty) {
      next.remove(eventId);
    } else {
      next[eventId] = Map.unmodifiable(Map<DateTime, String>.of(days));
    }
    _published = next;
    OccurrenceDescriptions.updateCache(byEvent: next);
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
    _writes++;
    (_byEvent[eventId] ??= {})[key] = description;
    _publishFor(eventId);
  }

  /// Returns one day to the template. The row survives as a tombstone — it is
  /// the ordered record of the reset — but drops out of the cache and the
  /// facade immediately. Distinct from writing `''`, which is a deliberately
  /// blank day.
  Future<void> clearDescription(String eventId, DateTime day) async {
    final key = _dateOnlyUtc(day);
    await _dao.tombstone(eventId, key);
    _writes++;
    final forEvent = _byEvent[eventId];
    if (forEvent != null) {
      forEvent.remove(key);
      if (forEvent.isEmpty) _byEvent.remove(eventId);
    }
    _publishFor(eventId);
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
  ///
  /// The person's own only — never a day's text of an event another account
  /// shares with this one (`docs/cloud-sharing-foundations.md` §8).
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getActive();
    final shared = await _dao.attachedDatabase.sharedRowDao.owner();
    return [
      for (final row in rows)
        if (shared == null || row.ownerId != shared)
          {
            'eventId': row.eventId,
            'dayMs': row.day.millisecondsSinceEpoch,
            'description': row.description,
            'createdAtMs': row.createdAt.millisecondsSinceEpoch,
            'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
            if (row.ownerId != null) 'ownerId': row.ownerId,
          },
    ];
  }

  /// Wipe-then-reinsert, mirroring [CalendarEventService.importData]. Audit
  /// timestamps are preserved from the backup; identity is stamped fresh by the
  /// DAO, so a tombstone never round-trips a restore.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    // Parsed first, written once (**5.1**): the per-row `try` still guards
    // parsing, but the write is one batched transaction instead of one
    // awaited insert — and one WAL commit — per archived row.
    final companions = <EventOccurrenceDescriptionsCompanion>[];
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
        companions.add(
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
            ownerId: Value(JsonKeys.ownerIdOf(map)),
          ),
        );
      } catch (e) {
        debugPrint('[EventOccurrenceService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
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
