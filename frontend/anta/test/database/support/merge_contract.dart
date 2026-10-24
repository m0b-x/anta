// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';

import 'db_test_support.dart';

/// A remote stamp later than anything the test clock mints.
const String newerHlc = 'ffffffffffff:0001:remote';

/// A remote stamp earlier than anything the test clock mints.
const String olderHlc = '000000000001:0000:remote';

/// One table's remote merge, described for [runMergeContract].
class MergeContract<R> {
  /// The SQL table, read back through its `syncedTables` key expression.
  final String table;

  /// A key no seeded row uses, in the table's key shape.
  final String freshKey;

  /// Writes one live row through the DAO's own write path — stamped by the
  /// local clock, queued in the outbox — and returns its key.
  final Future<String> Function(AppDatabase db) seedLocal;

  /// A remote row under [key] stamped [hlc], live or a tombstone.
  final R Function(String key, String hlc, {bool deleted}) remote;

  final Future<MergeOutcome> Function(AppDatabase db, R row, {String? floor})
  merge;

  /// A data column whose remote value differs from the seeded one, and that
  /// remote value as SQLite stores it.
  final String markerColumn;
  final Object markerValue;

  const MergeContract({
    required this.table,
    required this.freshKey,
    required this.seedLocal,
    required this.remote,
    required this.merge,
    required this.markerColumn,
    required this.markerValue,
  });
}

/// The record §3.4 contract every synced table's merge keeps: verbatim
/// inserts, last-writer-wins by stamp with the stale entry retired, the
/// newer local row re-queued, the bind floor, tombstones and resurrection,
/// and never a stamp minted.
void runMergeContract<R>(
  MergeContract<R> c, {
  required AppDatabase Function() db,
  required StatementCounter Function() statements,
}) {
  final synced = syncedTables.singleWhere((t) => t.name == c.table);

  Future<Map<String, Object?>?> stored(String key) async {
    final row = await db()
        .customSelect(
          'SELECT * FROM ${c.table} WHERE ${synced.rowKeySql} = ?',
          variables: [Variable<String>(key)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  Future<List<SyncOutboxRow>> entries(String key) {
    return (db().select(db().syncOutbox)
          ..where((o) => o.syncedTable.equals(c.table) & o.rowKey.equals(key)))
        .get();
  }

  Future<String> localStamp(String key) async =>
      (await stored(key))!['hlc_timestamp']! as String;

  group('the merge contract on ${c.table}', () {
    test('an unknown row is inserted verbatim and queued nowhere', () async {
      final outcome = await c.merge(db(), c.remote(c.freshKey, newerHlc));

      expect(outcome, const MergeOutcome(MergeResult.inserted));
      final row = (await stored(c.freshKey))!;
      expect(row['hlc_timestamp'], newerHlc);
      expect(row['device_id'], 'remote');
      expect(row['version'], 7);
      expect(row['is_deleted'], 0);
      expect(row['owner_id'], 'uid-1');
      expect(row[c.markerColumn], c.markerValue);
      expect(await db().syncOutboxDao.count(), 0);
    });

    test('a newer remote wins and retires the pending entry', () async {
      final key = await c.seedLocal(db());

      final outcome = await c.merge(db(), c.remote(key, newerHlc));

      expect(outcome.result, MergeResult.applied);
      expect(outcome.localHadPendingPush, isTrue);
      final row = (await stored(key))!;
      expect(row['hlc_timestamp'], newerHlc);
      expect(row['owner_id'], 'uid-1');
      expect(row[c.markerColumn], c.markerValue);
      expect(await entries(key), isEmpty);
    });

    test('a newer remote over a pushed row reports no pending push', () async {
      final key = await c.seedLocal(db());
      await db().syncOutboxDao.clear();

      final outcome = await c.merge(db(), c.remote(key, newerHlc));

      expect(outcome, const MergeOutcome(MergeResult.applied));
    });

    test('an older remote keeps the local row and re-queues it', () async {
      final key = await c.seedLocal(db());
      final before = await stored(key);
      final stamp = await localStamp(key);
      await db().syncOutboxDao.clear();
      final clock = db().hlc.last.toString();

      final outcome = await c.merge(db(), c.remote(key, olderHlc));

      expect(outcome, const MergeOutcome(MergeResult.keptLocal));
      expect(await stored(key), before);
      final queued = await entries(key);
      expect(queued.single.hlc, stamp, reason: 'its own stamp, none minted');
      expect(db().hlc.last.toString(), clock);
    });

    test('an older remote never lowers a newer pending entry', () async {
      final key = await c.seedLocal(db());
      await db().syncOutboxDao.clear();
      const ahead = 'fffffffffff0:0000:local';
      await db().customStatement(
        'INSERT INTO sync_outbox (table_name, row_key, hlc, op, enqueued_at) '
        "VALUES (?, ?, ?, 'upsert', 0)",
        [c.table, key, ahead],
      );

      await c.merge(db(), c.remote(key, olderHlc));

      expect((await entries(key)).single.hlc, ahead);
    });

    test('the same stamp again is unchanged and writes nothing', () async {
      final key = await c.seedLocal(db());
      final before = await stored(key);
      final stamp = await localStamp(key);
      statements().reset();

      final outcome = await c.merge(db(), c.remote(key, stamp));

      expect(outcome, const MergeOutcome(MergeResult.unchanged));
      expect([
        for (final s in statements().captured)
          if (!s.isSelect) s.sql,
      ], isEmpty);
      expect(await stored(key), before);
    });

    test('a tombstone applies, and a newer upsert resurrects', () async {
      final key = await c.seedLocal(db());

      final deleted = await c.merge(
        db(),
        c.remote(key, 'ffffffffffff:0000:remote', deleted: true),
      );
      expect(deleted.result, MergeResult.applied);
      final tombstone = (await stored(key))!;
      expect(tombstone['is_deleted'], 1);
      expect(tombstone['deleted_at'], isNotNull);
      expect(tombstone['hlc_timestamp'], 'ffffffffffff:0000:remote');
      expect(tombstone['owner_id'], 'uid-1');
      expect(tombstone['device_id'], 'remote');
      expect(tombstone['version'], 7);

      final back = await c.merge(db(), c.remote(key, newerHlc));
      expect(back.result, MergeResult.applied);
      final row = (await stored(key))!;
      expect(row['is_deleted'], 0);
      expect(row['deleted_at'], isNull);
      expect(row[c.markerColumn], c.markerValue);
    });

    test('an unknown row\'s tombstone is stored and out-stamps an older '
        'upsert', () async {
      await c.merge(db(), c.remote(c.freshKey, newerHlc, deleted: true));
      expect((await stored(c.freshKey))!['is_deleted'], 1);

      final outcome = await c.merge(db(), c.remote(c.freshKey, olderHlc));

      expect(outcome.result, MergeResult.keptLocal);
      expect((await stored(c.freshKey))!['is_deleted'], 1);
    });

    test('a local stamp at the floor yields to an older remote', () async {
      final key = await c.seedLocal(db());
      final stamp = await localStamp(key);

      final outcome = await c.merge(
        db(),
        c.remote(key, olderHlc),
        floor: stamp,
      );

      expect(outcome.result, MergeResult.applied);
      expect(outcome.localHadPendingPush, isTrue);
      expect((await stored(key))!['hlc_timestamp'], olderHlc);
      expect(await entries(key), isEmpty);
    });

    test('a local stamp above the floor keeps last-writer-wins', () async {
      final key = await c.seedLocal(db());
      final stamp = await localStamp(key);

      final outcome = await c.merge(
        db(),
        c.remote(key, olderHlc),
        floor: '000000000002:0000:floor',
      );

      expect(outcome.result, MergeResult.keptLocal);
      expect((await stored(key))!['hlc_timestamp'], stamp);
    });

    /// Ten minutes ahead of the wall clock: past anything the test clock has
    /// minted, inside the drift guard, so the clock adopts it whole.
    HlcTimestamp soon() => HlcTimestamp(
      wallTime: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      logicalCounter: 3,
      nodeId: 'remote',
    );

    Future<void> expectClockAt(HlcTimestamp remote) async {
      final last = db().hlc.last;
      expect((last.wallTime, last.logicalCounter), (
        remote.wallTime,
        remote.logicalCounter,
      ));
      await db().persistClock();
      final stored = HlcTimestamp.parse(
        (await db().syncDao.getValue(SyncDao.keyLastHlc))!,
      );
      expect((stored.wallTime, stored.logicalCounter), (
        remote.wallTime,
        remote.logicalCounter,
      ));
    }

    test('an inserted row moves the clock to its stamp', () async {
      final remote = soon();

      final outcome = await c.merge(
        db(),
        c.remote(c.freshKey, remote.toString()),
      );

      expect(outcome.result, MergeResult.inserted);
      await expectClockAt(remote);
    });

    test('an applied row moves the clock to its stamp', () async {
      final key = await c.seedLocal(db());
      final remote = soon();

      final outcome = await c.merge(db(), c.remote(key, remote.toString()));

      expect(outcome.result, MergeResult.applied);
      await expectClockAt(remote);
    });

    test('a merge moves the clock only through the remote stamp', () async {
      final key = await c.seedLocal(db());
      final clock = db().hlc.last.toString();

      await c.merge(db(), c.remote(key, olderHlc), floor: newerHlc);

      expect(db().hlc.last.toString(), clock);
      expect(await entries(key), isEmpty);
    });
  });
}
