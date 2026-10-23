// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/migrations.dart';

import 'support/db_test_support.dart';
import 'support/v42_shapes.dart';

/// Guards the v43 CRDT block on `counters` and `counter_values`.
///
/// Nothing here is visible in the app: a tombstoned counter and a deleted one
/// look the same, and a version that never moves changes no screen. They are
/// what a merge will read once counters sync, which is why the shape lands
/// before the transport.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  CountersCompanion counter(String id, {String name = 'Sets', int pos = 0}) {
    return CountersCompanion(
      id: Value(id),
      name: Value(name),
      position: Value(pos),
      createdAt: Value(DateTime.utc(2026, 10, 1)),
    );
  }

  Future<CounterRow> counterRow(String id) {
    return (db.select(db.counters)..where((c) => c.id.equals(id))).getSingle();
  }

  Future<CounterValueRow> valueRow(String counterId, String noteId) {
    return (db.select(db.counterValues)..where(
          (v) => v.counterId.equals(counterId) & v.noteId.equals(noteId),
        ))
        .getSingle();
  }

  group('stamping', () {
    test(
      'an insert is a live version-1 row stamped with this device',
      () async {
        await db.counterDao.insertCounter(counter('c1'));

        final row = await counterRow('c1');
        expect(row.version, 1);
        expect(row.isDeleted, isFalse);
        expect(row.deletedAt, isNull);
        expect(row.hlcTimestamp, isNotEmpty);
        expect(row.deviceId, 'test-device');
        expect(row.ownerId, isNull);
      },
    );

    test('an edit bumps the version and moves the HLC', () async {
      await db.counterDao.insertCounter(counter('c1'));
      final before = await counterRow('c1');

      await db.counterDao.updateCounter(counter('c1', name: 'Reps'));
      final after = await counterRow('c1');

      expect(after.name, 'Reps');
      expect(after.version, before.version + 1);
      expect(after.hlcTimestamp.compareTo(before.hlcTimestamp), greaterThan(0));
    });

    test('the global value keeps its empty note id', () async {
      await db.counterDao.insertCounter(counter('c1'));
      await db.counterDao.upsertValue('c1', '', 5);

      final row = await valueRow('c1', '');
      expect(row.value, 5);
      expect(row.version, 1);
      expect(row.deviceId, 'test-device');
      expect(await db.counterDao.getValuesForNote(''), {'c1': 5});
    });

    test(
      'a value update bumps the version and keeps pin and position',
      () async {
        await db.counterDao.upsertValue('c1', 'n1', 1);
        await db.counterDao.setNoteValuePinned('c1', 'n1', true);
        await db.counterDao.updateNoteValuePositions('c1', {'n1': 3});
        final before = await valueRow('c1', 'n1');

        await db.counterDao.upsertValue('c1', 'n1', 2);
        final after = await valueRow('c1', 'n1');

        expect(after.value, 2);
        expect(after.version, before.version + 1);
        expect(after.isPinned, isTrue);
        expect(after.position, 3);
      },
    );

    test('pin and position writes each bump the version', () async {
      await db.counterDao.insertCounter(counter('c1'));
      await db.counterDao.setCounterPinned('c1', true);
      await db.counterDao.updatePositions({'c1': 4});

      final row = await counterRow('c1');
      expect(row.isPinned, isTrue);
      expect(row.position, 4);
      expect(row.version, 3);
    });

    test('a reorder writes only the rows it moves, under one HLC', () async {
      for (var i = 0; i < 3; i++) {
        await db.counterDao.insertCounter(counter('c$i', pos: i));
      }
      final untouched = await counterRow('c0');

      await db.counterDao.updatePositions({'c0': 0, 'c1': 2, 'c2': 1});

      final c0 = await counterRow('c0');
      final c1 = await counterRow('c1');
      final c2 = await counterRow('c2');
      expect(c0.version, untouched.version);
      expect(c0.hlcTimestamp, untouched.hlcTimestamp);
      expect([c1.position, c2.position], [2, 1]);
      expect(c1.hlcTimestamp, c2.hlcTimestamp);
    });

    test('a value write that changes nothing writes nothing', () async {
      await db.counterDao.upsertValue('c1', 'n1', 4);
      final before = await valueRow('c1', 'n1');

      await db.counterDao.upsertValue('c1', 'n1', 4);

      final after = await valueRow('c1', 'n1');
      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test('an edit that changes nothing writes nothing', () async {
      await db.counterDao.insertCounter(counter('c1'));
      final before = await counterRow('c1');

      // The model's copy of created_at carries milliseconds the column never
      // stored; that difference alone is not an edit.
      await db.counterDao.updateCounter(
        counter(
          'c1',
        ).copyWith(createdAt: Value(DateTime.utc(2026, 10, 1, 0, 0, 0, 250))),
      );

      final after = await counterRow('c1');
      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
    });

    test(
      'adding a counter stamps it and its global value under one HLC',
      () async {
        await db.counterDao.insertCounterWithValue(counter('c1'), 3);

        final parent = await counterRow('c1');
        final value = await valueRow('c1', '');
        expect(value.value, 3);
        expect(value.version, 1);
        expect(value.hlcTimestamp, parent.hlcTimestamp);
      },
    );

    test('a pin toggle writes each touched row once, under one HLC', () async {
      for (var i = 0; i < 3; i++) {
        await db.counterDao.insertCounter(counter('c$i', pos: i));
      }
      final unmoved = await counterRow('c0');

      // c2 is pinned and moves to the front; the map is the whole new order,
      // as `CounterService.toggleCounterPin` passes it.
      await db.counterDao.setCounterPinned(
        'c2',
        true,
        positions: {'c2': 0, 'c0': 1, 'c1': 2},
      );

      final c0 = await counterRow('c0');
      final c1 = await counterRow('c1');
      final c2 = await counterRow('c2');
      expect(c2.isPinned, isTrue);
      expect([c2.position, c0.position, c1.position], [0, 1, 2]);
      expect(c2.version, 2, reason: 'pin and position are one write');
      expect(c0.version, unmoved.version + 1);
      expect(c1.version, 2);
      expect({c0.hlcTimestamp, c1.hlcTimestamp, c2.hlcTimestamp}, hasLength(1));
    });
  });

  group('tombstoning', () {
    Future<void> seed() async {
      await db.counterDao.insertCounter(counter('c1'));
      await db.counterDao.insertCounter(counter('c2', pos: 1));
      await db.counterDao.upsertValue('c1', '', 7);
      await db.counterDao.upsertValue('c1', 'n1', 2);
      await db.counterDao.upsertValue('c1', 'n2', 3);
      await db.counterDao.upsertValue('c2', 'n1', 9);
    }

    test(
      'deleting a counter tombstones it and its values as one act',
      () async {
        await seed();

        await db.counterDao.deleteCounter('c1');

        final parent = await counterRow('c1');
        expect(parent.isDeleted, isTrue);
        expect(parent.deletedAt, isNotNull);
        expect(parent.version, 2);
        final values = await (db.select(
          db.counterValues,
        )..where((v) => v.counterId.equals('c1'))).get();
        expect(values, hasLength(3), reason: 'tombstoned, not deleted');
        for (final value in values) {
          expect(value.isDeleted, isTrue);
          expect(value.version, 2);
          expect(value.hlcTimestamp, parent.hlcTimestamp);
        }
        // The other counter's value is not part of the act.
        expect((await valueRow('c2', 'n1')).isDeleted, isFalse);
      },
    );

    test('the cascade is two statements for any number of values', () async {
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);
      await counted.counterDao.insertCounter(
        CountersCompanion(
          id: const Value('c1'),
          name: const Value('Sets'),
          createdAt: Value(DateTime.utc(2026)),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await counted.counterDao.upsertValue('c1', 'n$i', i);
      }
      counter.reset();

      await counted.counterDao.deleteCounter('c1');

      expect(counter.selects, isEmpty);
      expect(counter.count, 2, reason: counter.statements.join('\n'));
    });

    test('deleting twice does not churn the version', () async {
      await seed();
      await db.counterDao.deleteCounter('c1');
      final once = await counterRow('c1');

      await db.counterDao.deleteCounter('c1');

      expect((await counterRow('c1')).version, once.version);
      expect((await valueRow('c1', 'n1')).version, 2);
    });

    test('every read hides tombstones', () async {
      await seed();
      await db.counterDao.deleteCounter('c1');
      await db.counterDao.deleteValue('c2', 'n1');

      expect((await db.counterDao.getAllCounters()).map((c) => c.id), ['c2']);
      expect(await db.counterDao.getValue('c1', ''), isNull);
      expect(await db.counterDao.getValuesForNote(''), isEmpty);
      expect(await db.counterDao.getValuesForNote('n1'), isEmpty);
      expect(await db.counterDao.getAllValues(), isEmpty);
      expect(await db.counterDao.getValuesForCounter('c1'), isEmpty);
      expect(await db.counterDao.getValuesForCounterOrdered('c1'), isEmpty);
    });

    test(
      'a value write over a tombstone resurrects it as a fresh row',
      () async {
        await seed();
        await db.counterDao.setNoteValuePinned('c2', 'n1', true);
        await db.counterDao.updateNoteValuePositions('c2', {'n1': 5});
        await db.counterDao.deleteValue('c2', 'n1');
        final tombstone = await valueRow('c2', 'n1');

        await db.counterDao.upsertValue('c2', 'n1', 1);

        final row = await valueRow('c2', 'n1');
        expect(row.isDeleted, isFalse);
        expect(row.deletedAt, isNull);
        expect(row.version, tombstone.version + 1);
        expect(row.value, 1);
        // Deleted then counted again used to be a fresh row; it still reads so.
        expect(row.isPinned, isFalse);
        expect(row.position, 0);
        expect(await db.counterDao.getValuesForNote('n1'), {'c1': 2, 'c2': 1});
      },
    );

    test('a value write under a tombstoned counter is dropped', () async {
      await seed();
      await db.counterDao.deleteCounter('c1');

      await db.counterDao.upsertValue('c1', 'n1', 40);
      await db.counterDao.upsertValue('c1', 'n9', 1);

      final row = await valueRow('c1', 'n1');
      expect(row.isDeleted, isTrue);
      expect(row.value, 2);
      final strays = await (db.select(
        db.counterValues,
      )..where((v) => v.counterId.equals('c1') & v.noteId.equals('n9'))).get();
      expect(strays, isEmpty);
    });

    test('edits leave a tombstoned counter alone', () async {
      await seed();
      await db.counterDao.deleteCounter('c1');
      final tombstone = await counterRow('c1');

      await db.counterDao.updateCounter(counter('c1', name: 'Back'));
      await db.counterDao.setCounterPinned('c1', true);
      await db.counterDao.updatePositions({'c1': 9});
      await db.counterDao.setNoteValuePinned('c1', 'n1', true);

      final row = await counterRow('c1');
      expect(row.isDeleted, isTrue);
      expect(row.version, tombstone.version);
      expect(row.name, 'Sets');
      expect((await valueRow('c1', 'n1')).isPinned, isFalse);
    });

    test('the import wipe stays hard, tombstones included', () async {
      await seed();
      await db.counterDao.deleteCounter('c1');

      await db.counterDao.deleteAll();

      expect(await db.select(db.counters).get(), isEmpty);
      expect(await db.select(db.counterValues).get(), isEmpty);
    });
  });

  group('v42 → v43 migration', () {
    /// Both tables at their v42 shape with the full v6 index v43 replaces,
    /// plus a counter and its global and per-note values.
    Future<void> rebuildAtV42() async {
      await rebuildCountersAtV42(db);
      await db.customStatement(
        'INSERT INTO counters (id, name, created_at, is_pinned) '
        "VALUES ('legacy', 'Sets', 0, 1)",
      );
      await db.customStatement(
        'INSERT INTO counter_values (counter_id, note_id, value) '
        "VALUES ('legacy', '', 12), ('legacy', 'n1', 4)",
      );
    }

    Future<void> runV43() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v42CategoryAlertsAndDigests,
        DatabaseSchema.v43SyncReadiness,
      );
    }

    /// Untyped, so a later migration cannot break this group for reasons that
    /// have nothing to do with v43.
    Future<List<QueryRow>> rows(String table) {
      return db.customSelect('SELECT * FROM $table ORDER BY 1, 2').get();
    }

    test('backfills real identity onto every pre-existing row', () async {
      await rebuildAtV42();
      await runV43();

      for (final table in ['counters', 'counter_values']) {
        final all = await rows(table);
        expect(all, isNotEmpty);
        for (final row in all) {
          expect(row.read<String>('hlc_timestamp'), isNotEmpty, reason: table);
          expect(row.read<String>('device_id'), 'test-device', reason: table);
          expect(row.read<int>('version'), 1, reason: table);
          expect(row.read<int>('is_deleted'), 0, reason: table);
          expect(row.readNullable<int>('deleted_at'), isNull, reason: table);
          expect(row.readNullable<String>('owner_id'), isNull, reason: table);
        }
      }
      final values = await rows('counter_values');
      expect(values.map((r) => r.read<String>('note_id')), ['', 'n1']);
      expect(values.first.read<int>('value'), 12);
      // Through the DAO: the rows a v42 install had are the live ones now.
      expect((await db.counterDao.getAllCounters()).single.isPinned, isTrue);
      expect(await db.counterDao.getValuesForNote(''), {'legacy': 12});
    });

    test('replaces the full counter-values index with the partial one', () async {
      await rebuildAtV42();
      await runV43();

      final sql = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND name IN ('idx_counter_values_counter', 'idx_counters_active')",
          )
          .get();
      expect(sql, hasLength(2));
      for (final row in sql) {
        // Skipping the DROP would satisfy `IF NOT EXISTS` and leave upgraders
        // on the v6 full index under the name fresh installs use for the
        // partial one.
        expect(
          row.read<String>('sql'),
          endsWith('WHERE is_deleted = 0'),
          reason: row.read<String>('name'),
        );
      }
    });

    test('re-running it changes nothing', () async {
      await rebuildAtV42();
      await runV43();
      final once = await rows('counter_values');

      await runV43();
      final twice = await rows('counter_values');

      for (var i = 0; i < once.length; i++) {
        expect(
          twice[i].read<String>('hlc_timestamp'),
          once[i].read<String>('hlc_timestamp'),
        );
        expect(twice[i].read<int>('version'), once[i].read<int>('version'));
      }
    });
  });

  group('query plans', () {
    test('the counter list reads the partial index in order', () async {
      final counter = StatementCounter();
      final planned = await openTestDatabase(interceptor: counter);
      addTearDown(planned.close);
      counter.reset();

      await planned.counterDao.getAllCounters();

      final plan = await explainCaptured(planned, counter.selects.single);
      expect(plan.join('\n'), contains('idx_counters_active'));
      expect(plan.join('\n'), isNot(contains('TEMP B-TREE')));
    });

    test('a counter\'s per-note values read the partial index', () async {
      final counter = StatementCounter();
      final planned = await openTestDatabase(interceptor: counter);
      addTearDown(planned.close);
      counter.reset();

      await planned.counterDao.getValuesForCounter('c1');
      await planned.counterDao.getValuesForCounterOrdered('c1');

      expect(counter.selects, hasLength(2));
      for (final select in counter.selects) {
        final plan = (await explainCaptured(planned, select)).join('\n');
        expect(
          plan,
          contains('idx_counter_values_counter'),
          reason: select.sql,
        );
        expect(plan, isNot(contains('TEMP B-TREE')), reason: select.sql);
      }
    });
  });
}
