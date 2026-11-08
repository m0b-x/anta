// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/crdt/pn_counter.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/counter_values_binding.dart';

import 'support/db_test_support.dart';

/// Guards the counter value as a PN-counter (scalability record S20, D8 A):
/// two devices' offline taps add up through the real wire, an echo writes
/// nothing, a join neither side holds is stored and queued, a newer epoch
/// supersedes concurrent taps, an older build's envelope merges as an
/// absolute state, the bind floor yields whole, and a resurrecting tap
/// starts from the tombstone's epoch.
void main() {
  const binding = CounterValuesBinding();
  late AppDatabase a;
  late AppDatabase b;
  late StatementCounter bStatements;

  setUp(() async {
    bStatements = StatementCounter();
    a = AppDatabase.forTesting(NativeDatabase.memory(), deviceId: 'A');
    b = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(bStatements),
      deviceId: 'B',
    );
    await a.customSelect('SELECT 1').get();
    await b.customSelect('SELECT 1').get();
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<CounterValueRow> rowOf(AppDatabase db, [String noteId = '']) {
    return (db.select(db.counterValues)
          ..where((v) => v.counterId.equals('c1') & v.noteId.equals(noteId)))
        .getSingle();
  }

  /// The row of [from] as its push sends it, through [binding]'s codec.
  Future<SyncEnvelope> envelopeOf(AppDatabase from, [String noteId = '']) {
    return rowOf(
      from,
      noteId,
    ).then((row) => binding.encode(from, row, boundUid: 'uid-1'));
  }

  Future<MergeOutcome> ship(
    AppDatabase from,
    AppDatabase to, {
    String noteId = '',
    String? floor,
  }) async {
    return binding.mergeRemote(
      to,
      await envelopeOf(from, noteId),
      floor: floor,
    );
  }

  Future<int?> tap(AppDatabase db, int delta) =>
      db.counterDao.applyCount('c1', '', delta: delta, startValue: 0);

  Future<String?> queuedAt(AppDatabase db, [String noteId = '']) async {
    final row =
        await (db.select(db.syncOutbox)..where(
              (o) =>
                  o.syncedTable.equals('counter_values') &
                  o.rowKey.equals(counterValueRowKey('c1', noteId)),
            ))
            .getSingleOrNull();
    return row?.hlc;
  }

  /// Both devices hold the counter's first value, 0, under A's stamp.
  Future<void> shareFirstValue() async {
    await a.counterDao.insertCounterWithValue(
      CountersCompanion(
        id: const Value('c1'),
        name: const Value('Sets'),
        createdAt: Value(DateTime.utc(2026, 11, 1)),
      ),
      0,
    );
    expect((await ship(a, b)).result, MergeResult.inserted);
  }

  test(
    'two devices tapping one value offline add up after both merges',
    () async {
      await shareFirstValue();
      expect(await tap(a, 2), 2);
      expect(await tap(b, 3), 3);
      expect(await tap(b, -1), 2);

      expect((await ship(a, b)).result, MergeResult.applied);
      expect((await ship(b, a)).result, MergeResult.applied);
      expect((await ship(a, b)).result, MergeResult.unchanged);

      expect((await rowOf(a)).value, 4);
      expect((await rowOf(b)).value, 4);
      expect((await rowOf(a)).shards, (await rowOf(b)).shards);
    },
  );

  test('a join neither side holds is stored under a fresh stamp above the '
      'remote and queued, so the other device receives it', () async {
    await shareFirstValue();
    await tap(a, 2);
    await tap(b, 3);
    final remote = await rowOf(a);

    await ship(a, b);

    final joined = await rowOf(b);
    expect(joined.value, 5);
    expect(joined.hlcTimestamp.compareTo(remote.hlcTimestamp), greaterThan(0));
    expect(joined.version, greaterThan(remote.version));
    expect(await queuedAt(b), joined.hlcTimestamp);
  });

  test('an echo — the same join under the other device\'s stamp — writes '
      'nothing', () async {
    await shareFirstValue();
    await tap(a, 2);
    await tap(b, 3);
    // Each device merges the other's taps before hearing of its join, so
    // both store the same state under their own stamps.
    final fromA = await envelopeOf(a);
    final fromB = await envelopeOf(b);
    await binding.mergeRemote(b, fromA);
    await binding.mergeRemote(a, fromB);
    expect((await rowOf(a)).hlcTimestamp, isNot((await rowOf(b)).hlcTimestamp));
    bStatements.reset();

    final outcome = await ship(a, b);

    expect(outcome.result, MergeResult.unchanged);
    expect(bStatements.captured.where((c) => !c.isSelect), isEmpty);
    expect((await rowOf(b)).value, 5);
  });

  test('a remote holding less than the local join keeps local and requeues '
      'it, repairing a push that landed over it', () async {
    await shareFirstValue();
    await tap(a, 2);
    final stale = await envelopeOf(a);
    await tap(a, 1);
    await b.syncOutboxDao.clear();
    await ship(a, b);
    await b.syncOutboxDao.clear();

    final outcome = await binding.mergeRemote(b, stale);

    expect(outcome.result, MergeResult.keptLocal);
    expect((await rowOf(b)).value, 3);
    expect(await queuedAt(b), (await rowOf(b)).hlcTimestamp);
  });

  test(
    'a newer epoch supersedes taps made concurrently under the older one',
    () async {
      await shareFirstValue();
      await tap(a, 4);
      await ship(a, b);
      // A resets while B, not yet told, keeps tapping.
      await a.counterDao.applyCount('c1', '', absolute: 0, startValue: 0);
      await tap(b, 5);

      await ship(a, b);
      await ship(b, a);

      expect((await rowOf(b)).value, 0);
      expect((await rowOf(a)).value, 0);
      expect((await rowOf(b)).epochHlc, (await rowOf(a)).epochHlc);
      expect((await rowOf(b)).shards, '');
    },
  );

  group('an envelope from an older build', () {
    /// [envelope] as an older build sends it — no PN-counter keys — under
    /// [hlc] and [version] when given.
    SyncEnvelope legacyOf(SyncEnvelope envelope, {String? hlc, int? version}) {
      return SyncEnvelope(
        table: envelope.table,
        rowKey: envelope.rowKey,
        hlc: hlc ?? envelope.hlc,
        deviceId: 'OLD',
        version: version ?? envelope.version,
        op: envelope.op,
        ownerId: envelope.ownerId,
        data: {...envelope.data!}
          ..remove('epochHlc')
          ..remove('epochValue')
          ..remove('shards'),
      );
    }

    test('stamped strictly above the local row wins whole as an absolute '
        'state of its own stamp', () async {
      await shareFirstValue();
      await tap(b, 3);
      await tap(a, 2);
      final envelope = await envelopeOf(a);

      await binding.mergeRemote(b, legacyOf(envelope));

      final row = await rowOf(b);
      expect(row.value, 2, reason: 'the pre-S20 rule: the newer write wins');
      expect((row.epochHlc, row.epochValue, row.shards), (envelope.hlc, 2, ''));
    });

    test(
      're-sending a row at its original stamp loses to the taps since',
      () async {
        await shareFirstValue();
        await tap(a, 2);
        final sent = await envelopeOf(a);
        await tap(a, 3);

        final outcome = await binding.mergeRemote(a, legacyOf(sent));

        expect(outcome.result, MergeResult.keptLocal);
        expect((await rowOf(a)).value, 5);
      },
    );

    test('an echo stamped above the epoch but below the local row never '
        'joins as an epoch', () async {
      await shareFirstValue();
      await tap(a, 2);
      final mid = await envelopeOf(a);
      await tap(a, 4);
      // Same wall time and counter as the tap of 2, another node: above that
      // stamp, below the tap of 4.
      final above = '${mid.hlc.substring(0, mid.hlc.lastIndexOf(':'))}:OLD';
      expect(above.compareTo(mid.hlc), greaterThan(0));

      final outcome = await binding.mergeRemote(
        a,
        legacyOf(mid, hlc: above, version: mid.version + 1),
      );

      expect(outcome.result, MergeResult.keptLocal);
      expect((await rowOf(a)).value, 6);
    });
  });

  test(
    'under the bind floor the space\'s state wins whole, taps or not',
    () async {
      await shareFirstValue();
      await tap(a, 1);
      final older = await envelopeOf(a);
      await tap(b, 6);
      final floor = (await rowOf(b)).hlcTimestamp;

      final outcome = await binding.mergeRemote(b, older, floor: floor);

      expect(outcome.result, MergeResult.applied);
      final row = await rowOf(b);
      expect(row.value, 1);
      expect(row.hlcTimestamp, older.hlc);
    },
  );

  test('a tap on a tombstoned value starts from the tombstone\'s epoch, so '
      'the taps before the delete never return', () async {
    await shareFirstValue();
    await tap(a, 7);
    await ship(a, b);
    await a.counterDao.deleteValue('c1', '');
    final tombstone = await rowOf(a);

    expect(await tap(a, 1), 1);

    final resurrected = await rowOf(a);
    expect(resurrected.isDeleted, isFalse);
    expect(resurrected.epochHlc, tombstone.hlcTimestamp);
    expect(resurrected.epochValue, 0);
    // B still holds the 7 taps under the first epoch and taps on.
    await tap(b, 2);
    await ship(a, b);
    await ship(b, a);
    expect((await rowOf(b)).value, 1);
    expect((await rowOf(a)).value, 1);
  });

  test('the stored value always adds up from its state', () async {
    await shareFirstValue();
    await tap(a, 3);
    await tap(a, -5);
    await ship(a, b);
    await tap(b, 4);

    for (final db in [a, b]) {
      final row = await rowOf(db);
      final state = PnCounterState(
        epochHlc: row.epochHlc,
        epochValue: row.epochValue,
        shards: PnCounterState.shardsOfColumn(row.shards),
      );
      expect(state.value, row.value);
    }
  });
}
