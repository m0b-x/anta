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

  late EventDigestDao _dao;

  EventDigestService._();

  static Future<EventDigestService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase] so tests run the real
  /// DAO against `NativeDatabase.memory()`. Never use it in app code.
  @visibleForTesting
  static Future<EventDigestService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<EventDigestService> _create(AppDatabase db) async {
    final service = EventDigestService._();
    service._dao = db.eventDigestDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the facade, so a digest from a
  /// closed database can neither list nor arm before the next [getInstance]
  /// republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    EventDigests.resetCache();
  }

  List<EventDigest> _cache = const [];

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

  Future<void> _load() async {
    try {
      final rows = await _dao.getAll();
      _cache = List.unmodifiable(rows.map(_rowToDigest));
    } catch (e) {
      debugPrint('[EventDigestService] Load error: $e');
      _cache = const [];
    }
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
  @override
  Future<void> update(EventDigest digest) {
    return _serialize(() async {
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
