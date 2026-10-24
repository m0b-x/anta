// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `CounterDao.mergeRemoteCounter` and `mergeRemoteCounterValue`:
/// the shared contract on both tables, the composite `counterId|noteId` key
/// with the global value's `noteId == ''`, and values stored as received
/// under a counter tombstoned here.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  CountersCompanion local(String id) {
    return CountersCompanion(
      id: Value(id),
      name: const Value('Sets'),
      createdAt: Value(DateTime.utc(2026, 10, 1)),
    );
  }

  CounterRow remoteCounter(String id, String hlc, {bool deleted = false}) {
    return CounterRow(
      id: id,
      name: 'Pulled',
      startValue: 5,
      step: 2,
      scope: 'perNote',
      position: 3,
      isPinned: true,
      createdAt: DateTime.utc(2026, 3, 1).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 3, 2).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  CounterValueRow remoteValue(String key, String hlc, {bool deleted = false}) {
    final split = key.indexOf('|');
    return CounterValueRow(
      counterId: key.substring(0, split),
      noteId: key.substring(split + 1),
      value: 42,
      position: 2,
      isPinned: true,
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 3, 2).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  runMergeContract(
    MergeContract<CounterRow>(
      table: 'counters',
      freshKey: 'pulled',
      seedLocal: (db) async {
        await db.counterDao.insertCounter(local('c1'));
        return 'c1';
      },
      remote: remoteCounter,
      merge: (db, row, {floor}) =>
          db.counterDao.mergeRemoteCounter(row, floor: floor),
      markerColumn: 'name',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  runMergeContract(
    MergeContract<CounterValueRow>(
      table: 'counter_values',
      freshKey: 'c9|note-1',
      seedLocal: (db) async {
        await db.counterDao.insertCounterWithValue(local('c1'), 3);
        return 'c1|';
      },
      remote: remoteValue,
      merge: (db, row, {floor}) =>
          db.counterDao.mergeRemoteCounterValue(row, floor: floor),
      markerColumn: 'value',
      markerValue: 42,
    ),
    db: () => db,
    statements: () => statements,
  );

  test('the global value merges under its empty note id', () async {
    await db.counterDao.insertCounterWithValue(local('c1'), 3);

    final outcome = await db.counterDao.mergeRemoteCounterValue(
      remoteValue('c1|', newerHlc),
    );

    expect(outcome.result, MergeResult.applied);
    expect(await db.counterDao.getValuesForNote(''), {'c1': 42});
    expect(await db.syncOutboxDao.count(), 1, reason: 'the counter only');
  });

  test('a per-note value keeps its note apart from the global one', () async {
    await db.counterDao.insertCounterWithValue(local('c1'), 3);

    final outcome = await db.counterDao.mergeRemoteCounterValue(
      remoteValue('c1|note-1', newerHlc),
    );

    expect(outcome.result, MergeResult.inserted);
    expect(await db.counterDao.getValuesForNote(''), {'c1': 3});
    expect(await db.counterDao.getValuesForNote('note-1'), {'c1': 42});
  });

  test('a value under a counter tombstoned here is stored', () async {
    await db.counterDao.insertCounter(local('c1'));
    await db.counterDao.deleteCounter('c1');

    final outcome = await db.counterDao.mergeRemoteCounterValue(
      remoteValue('c1|note-1', newerHlc),
    );

    expect(outcome.result, MergeResult.inserted);
    final row =
        await (db.select(db.counterValues)..where(
              (v) => v.counterId.equals('c1') & v.noteId.equals('note-1'),
            ))
            .getSingle();
    expect(row.value, 42);
    expect(row.isDeleted, isFalse);
  });

  test('a counter tombstone cascades to no value', () async {
    await db.counterDao.insertCounterWithValue(local('c1'), 3);

    await db.counterDao.mergeRemoteCounter(
      remoteCounter('c1', newerHlc, deleted: true),
    );

    final value = await db.select(db.counterValues).getSingle();
    expect(value.isDeleted, isFalse);
    final counter = await db.select(db.counters).getSingle();
    expect(counter.isDeleted, isTrue);
    expect(counter.name, 'Sets', reason: 'a tombstone carries no data');
  });

  test('a newer counter overwrites every data column', () async {
    await db.counterDao.insertCounter(local('c1'));

    await db.counterDao.mergeRemoteCounter(remoteCounter('c1', newerHlc));

    final row = await db.select(db.counters).getSingle();
    final expected = remoteCounter('c1', newerHlc);
    expect(row, expected);
  });
}
