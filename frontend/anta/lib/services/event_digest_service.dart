import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/alert_constants.dart';
import '../constants/event_digests.dart';
import '../constants/json_keys.dart';
import '../database/daos/event_digest_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/event_digest.dart';

/// The digest writes `CalendarBloc` makes — [EventDigestService]'s, as an
/// interface so a bloc or widget test can hand the bloc a fake and never
/// open a database ([AlertWriter]'s reason).
abstract interface class DigestWriter {
  Future<EventDigest?> create(EventDigest draft);
  Future<void> update(EventDigest digest);
  Future<void> setEnabled(String id, bool enabled);
  Future<void> delete(String id);
}

/// Owns `event_digests` (**v42**) and publishes it to the synchronous
/// [EventDigests] facade.
///
/// [OverviewViewService] cloned on purpose — a cache of live rows, one
/// serialized write chain, a cap enforced at [create] — plus the facade,
/// because the Alerts hub reads digests while it builds and the scheduler
/// plans from them. All CRDT stamping lives in [EventDigestDao].
class EventDigestService implements DigestWriter {
  static EventDigestService? _instance;
  static const Uuid _uuid = Uuid();

  /// The first construction while it is in flight ([EventAlertService]'s
  /// pair), so two callers racing it share one load rather than each
  /// publishing its own.
  static Future<EventDigestService>? _initializing;

  /// Bumped by every [reset]. With [DatabaseLifecycle.generation] it is how a
  /// construction tells, past each of its awaits, that it has been overtaken:
  /// this counter covers a switch that reached this service (and a restore's
  /// deliberate re-init), the lifecycle's covers a switch that landed before
  /// the construction had registered its handler and so never called [reset]
  /// here at all.
  static int _generation = 0;

  late EventDigestDao _dao;

  EventDigestService._();

  static Future<EventDigestService> getInstance() =>
      _createOnce(AppDatabase.getInstance);

  /// Binds the singleton to an arbitrary [AppDatabase] so tests run the real
  /// DAO against `NativeDatabase.memory()`. Never use it in app code.
  @visibleForTesting
  static Future<EventDigestService> forTesting(AppDatabase db) =>
      _createOnce(() async => db);

  /// One construction at a time, and never one a database switch overtook.
  ///
  /// A construction the switch overtook read the database that was just
  /// closed, so it discards itself and hands its caller the one the new
  /// database installs — otherwise [_instance] would hold a dead handle for
  /// the rest of the session, the hub listing nothing and every write
  /// throwing until the next switch.
  static Future<EventDigestService> _createOnce(
    Future<AppDatabase> Function() open,
  ) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<EventDigestService> creating;
    creating = () async {
      final generation = _generation;
      final lifecycle = DatabaseLifecycle.generation;
      bool overtaken() =>
          generation != _generation ||
          lifecycle != DatabaseLifecycle.generation;

      Future<EventDigestService> restart() async {
        if (identical(_initializing, creating)) _initializing = null;
        final service = await _createOnce(open);
        // This construction may already have published the closing
        // database's digests on its way through `_load` — but only what the
        // replacement actually read is worth publishing over them. A
        // replacement whose own read failed holds the initial empty list, and
        // publishing that is the empty facade [_load] refuses to publish for
        // the same reason: the next reconcile would read it as "no digests
        // configured" and disarm every standing one.
        if (service._published) EventDigests.updateCache(service._cache);
        return service;
      }

      try {
        final db = await open();
        if (overtaken()) return await restart();
        final service = EventDigestService._();
        service._dao = db.eventDigestDao;
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

  /// Drops the cached singleton and clears the facade, so a digest from a
  /// closed database can neither list nor arm before the next [getInstance]
  /// republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
    EventDigests.resetCache();
  }

  List<EventDigest> _cache = const [];

  /// Whether [_cache] reflects a read that succeeded, so a `restart()` can
  /// tell this instance's digests from the empty list it starts with.
  bool _published = false;

  /// The tail of the write chain — `null` while idle (see [_serialize]).
  Future<void>? _writes;

  List<EventDigest> get digests => _cache;

  bool get isFull => _cache.length >= kDigestHorizon.maxDigests;

  Future<void> reload() => _load();

  /// [OverviewViewService]'s write chain: every mutation waits for the one
  /// before it, a failed link is swallowed for the chain only, and the tail
  /// starts `null` so no future is built in a widget test's `FakeAsync` zone.
  Future<T> _serialize<T>(Future<T> Function() write) async {
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Already surfaced to whoever issued it; one failure must not stop
        // the queue.
      }
    }
    try {
      return await write();
    } finally {
      done.complete();
    }
  }

  /// Re-reads the table and publishes it. A read that fails publishes
  /// **nothing** and keeps the cache it had: an empty facade is not "no
  /// digests configured" to the reconcile that follows a pull — it plans zero
  /// digests, finds every armed row absent from what it wants and cancels it
  /// on the platform. A transient lock would therefore disarm every standing
  /// digest, and the next healthy pass would re-arm them under new os ids.
  /// Silence leaves the last good answer standing instead.
  Future<void> _load() async {
    final List<EventDigestRow> rows;
    try {
      rows = await _dao.getAll();
    } catch (e) {
      debugPrint('[EventDigestService] Load error: $e');
      return;
    }
    _cache = List.unmodifiable(rows.map(_rowToDigest));
    _published = true;
    EventDigests.updateCache(_cache);
  }

  /// Saves [draft] as a new digest under a fresh id, appended to the end of
  /// the display order; the draft's own id and position are ignored.
  ///
  /// Returns `null` when the table is already at
  /// [DigestHorizon.maxDigests] — a refusal the caller reports.
  @override
  Future<EventDigest?> create(EventDigest draft) {
    return _serialize(() async {
      if (isFull) return null;
      final id = _uuid.v4();
      final digest = draft.copyWith(
        id: id,
        name: draft.name.trim(),
        sortOrder: await _dao.nextSortOrder(),
      );
      await _dao.upsertDigest(_toCompanion(digest));
      await _load();
      return EventDigests.byId(id) ?? digest;
    });
  }

  /// Writes [digest] back in place — an edit from the sheet. Keeps its
  /// `created_at` and its position.
  ///
  /// A digest no longer live is **refused**, [setEnabled]'s rule: the sheet
  /// is open on a row a pull can tombstone from another device underneath it,
  /// and [EventDigestDao.upsertDigest] would resurrect that tombstone under a
  /// fresh local stamp — back permanently, re-armed, and one over the
  /// planner's horizon, which then silently drops a digest from every pass.
  @override
  Future<void> update(EventDigest digest) {
    return _serialize(() async {
      if (!_cache.any((live) => live.id == digest.id)) return;
      await _dao.upsertDigest(_toCompanion(digest));
      await _load();
    });
  }

  /// The hub switch: the `enabled` column alone, never the payload, so a
  /// digest a newer build wrote keeps every field this build cannot read.
  @override
  Future<void> setEnabled(String id, bool enabled) {
    return _serialize(() async {
      await _dao.setEnabled(id, enabled);
      await _load();
    });
  }

  @override
  Future<void> delete(String id) {
    return _serialize(() async {
      await _dao.softDeleteById(id);
      await _load();
    });
  }

  /// Persists a new display order, given every live id in the order it
  /// should appear — the whole list, never a delta.
  Future<void> reorder(List<String> idsInOrder) {
    return _serialize(() async {
      await _dao.reorder(idsInOrder);
      await _load();
    });
  }

  // ── Backup export / import ───────────────────────────────────────────

  /// Live digests only, without CRDT identity — a backup is not a sync
  /// channel. The payload is exported **verbatim**, never re-encoded from a
  /// decoded model, so a field a newer build wrote survives the trip.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'name': row.name,
          'payload': row.payload,
          'enabled': row.enabled,
          'sortOrder': row.sortOrder,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
          if (row.ownerId != null) 'ownerId': row.ownerId,
        },
    ];
  }

  /// Wipe-then-reinsert, [OverviewViewService.importData]'s shape: audit
  /// timestamps preserved, identity stamped fresh by the DAO, malformed rows
  /// skipped. A payload that no longer parses is stored as written and reads
  /// as the default digest, which keeps the user's named row alive.
  Future<void> importData(List<dynamic> data) {
    return _serialize(() => _importData(data));
  }

  Future<void> _importData(List<dynamic> data) async {
    await _dao.deleteAll();
    final companions = <EventDigestsCompanion>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'];
        if (id is! String || id.isEmpty) continue;
        final name = map['name'];
        final enabled = map['enabled'];
        final now = DateTime.now();
        final createdAtMs = map['createdAtMs'];
        final updatedAtMs = map['updatedAtMs'];
        companions.add(
          EventDigestsCompanion(
            id: Value(id),
            name: Value(name is String ? name : ''),
            payload: Value(map['payload'] is String ? map['payload'] : ''),
            enabled: Value(enabled is bool ? enabled : true),
            sortOrder: Value(map['sortOrder'] is int ? map['sortOrder'] : 0),
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
        debugPrint('[EventDigestService] Import row error: $e');
      }
    }
    await _dao.importAll(companions);
    await _load();
  }

  static EventDigest _rowToDigest(EventDigestRow row) {
    return EventDigest.fromRow(
      id: row.id,
      name: row.name,
      payload: row.payload,
      enabled: row.enabled,
      sortOrder: row.sortOrder,
    );
  }

  static EventDigestsCompanion _toCompanion(EventDigest digest) {
    return EventDigestsCompanion(
      id: Value(digest.id),
      name: Value(digest.name),
      payload: Value(digest.encodePayload()),
      enabled: Value(digest.enabled),
      sortOrder: Value(digest.sortOrder),
    );
  }
}
