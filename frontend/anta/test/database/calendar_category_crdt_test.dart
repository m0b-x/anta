// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/migrations.dart';

import 'support/db_test_support.dart';
import 'support/v42_shapes.dart';

/// Guards the v43 CRDT block on `calendar_categories`.
///
/// Every event names its category by id, so a calendar synced without its
/// categories points at nothing on the other device. None of this is visible
/// in the app — a tombstoned category and a deleted one look the same — which
/// is why it is pinned here before the transport exists.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  CalendarCategoriesCompanion category(
    String id, {
    String name = 'Climbing',
    int order = 0,
    bool builtIn = false,
  }) {
    final at = DateTime.utc(2026, 10, 1);
    return CalendarCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: const Value(0xFF00FF00),
      iconKey: const Value('event'),
      sortOrder: Value(order),
      isBuiltIn: Value(builtIn),
      createdAt: Value(at),
      updatedAt: Value(at),
    );
  }

  Future<CalendarCategoryRow> rowFor(String id) {
    return (db.select(
      db.calendarCategories,
    )..where((c) => c.id.equals(id))).getSingle();
  }

  group('stamping', () {
    test(
      'an insert is a live version-1 row stamped with this device',
      () async {
        await db.calendarCategoryDao.insertCategory(category('c1'));

        final row = await rowFor('c1');
        expect(row.version, 1);
        expect(row.isDeleted, isFalse);
        expect(row.deletedAt, isNull);
        expect(row.hlcTimestamp, isNotEmpty);
        expect(row.deviceId, 'test-device');
        expect(row.ownerId, isNull);
      },
    );

    test(
      'an edit bumps the version, keeps createdAt and moves the HLC',
      () async {
        await db.calendarCategoryDao.insertCategory(category('c1'));
        final before = await rowFor('c1');

        await db.calendarCategoryDao.updateCategory(
          CalendarCategoriesCompanion(
            id: const Value('c1'),
            name: const Value('Bouldering'),
            createdAt: Value(DateTime.utc(2030)),
            updatedAt: Value(DateTime.utc(2026, 10, 2)),
          ),
        );
        final after = await rowFor('c1');

        expect(after.name, 'Bouldering');
        expect(after.createdAt, before.createdAt);
        expect(after.version, before.version + 1);
        expect(
          after.hlcTimestamp.compareTo(before.hlcTimestamp),
          greaterThan(0),
        );
      },
    );

    test('an edit that changes nothing writes nothing', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));
      final before = await rowFor('c1');

      // What the editor sheet saves when nothing was touched: the same name,
      // colour and icon under a fresh `updated_at`.
      await db.calendarCategoryDao.updateCategory(
        CalendarCategoriesCompanion(
          id: const Value('c1'),
          name: const Value('Climbing'),
          colorValue: const Value(0xFF00FF00),
          iconKey: const Value('event'),
          updatedAt: Value(DateTime.utc(2026, 10, 9)),
        ),
      );

      final after = await rowFor('c1');
      expect(after.version, before.version);
      expect(after.hlcTimestamp, before.hlcTimestamp);
      expect(after.updatedAt, before.updatedAt);
    });

    test('hiding stamps like any other edit', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));

      await db.calendarCategoryDao.updateCategory(
        const CalendarCategoriesCompanion(
          id: Value('c1'),
          isHidden: Value(true),
        ),
      );

      final row = await rowFor('c1');
      expect(row.isHidden, isTrue);
      expect(row.version, 2);
    });

    test('a reorder bumps only the rows it moves, under one HLC', () async {
      for (var i = 0; i < 3; i++) {
        await db.calendarCategoryDao.insertCategory(category('c$i', order: i));
      }
      final unmoved = await rowFor('c0');

      await db.calendarCategoryDao.reorder(['c0', 'c2', 'c1']);

      final c0 = await rowFor('c0');
      final c1 = await rowFor('c1');
      final c2 = await rowFor('c2');
      expect(c0.version, unmoved.version);
      expect(c0.hlcTimestamp, unmoved.hlcTimestamp);
      expect([c1.sortOrder, c2.sortOrder], [2, 1]);
      expect([c1.version, c2.version], [2, 2]);
      expect(c1.hlcTimestamp, c2.hlcTimestamp);
    });

    test('an import stamps fresh live identity', () async {
      await db.calendarCategoryDao.importAll([category('c1')]);

      final row = await rowFor('c1');
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deviceId, 'test-device');
      expect(row.hlcTimestamp, isNotEmpty);
    });
  });

  group('seeding', () {
    test('seeds missing built-ins stamped, and leaves existing rows', () async {
      await db.calendarCategoryDao.seedMissing([
        category('gym', name: 'Gym', builtIn: true),
      ]);
      await db.calendarCategoryDao.updateCategory(
        const CalendarCategoriesCompanion(
          id: Value('gym'),
          name: Value('Lift'),
        ),
      );
      final edited = await rowFor('gym');

      await db.calendarCategoryDao.seedMissing([
        category('gym', name: 'Gym', builtIn: true),
        category('cardio', name: 'Cardio', order: 1, builtIn: true),
      ]);

      final gym = await rowFor('gym');
      expect(gym.name, 'Lift');
      expect(gym.version, edited.version);
      expect(gym.hlcTimestamp, edited.hlcTimestamp);
      final cardio = await rowFor('cardio');
      expect(cardio.version, 1);
      expect(cardio.deviceId, 'test-device');
      expect(cardio.hlcTimestamp, isNotEmpty);
    });

    test('a tombstoned built-in is resurrected, keeping its edits', () async {
      // The way one can exist: restored as custom by an older archive, then
      // tombstoned, or merged in from another device.
      await db.calendarCategoryDao.insertCategory(
        category('other', name: 'Misc'),
      );
      await db.customStatement(
        "UPDATE calendar_categories SET is_deleted = 1, deleted_at = 0, "
        "version = 2 WHERE id = 'other'",
      );

      await db.calendarCategoryDao.seedMissing([
        category('other', name: 'Other', builtIn: true),
      ]);

      final row = await rowFor('other');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.isBuiltIn, isTrue);
      expect(row.version, 3);
      expect(row.deviceId, 'test-device');
      expect(row.name, 'Misc', reason: 'the user\'s last edit survives');
      expect(
        (await db.calendarCategoryDao.getAll()).map((c) => c.id),
        contains('other'),
      );
    });

    test('a launch with nothing to seed is still one batched insert', () async {
      final counter = StatementCounter();
      final counted = await openTestDatabase(interceptor: counter);
      addTearDown(counted.close);
      final seeds = [
        for (var i = 0; i < 9; i++) category('b$i', order: i, builtIn: true),
      ];
      await counted.calendarCategoryDao.seedMissing(seeds);
      counter.reset();

      await counted.calendarCategoryDao.seedMissing(seeds);

      expect(counter.selects, isEmpty);
      expect(counter.count, 1, reason: counter.statements.join('\n'));
    });
  });

  group('tombstoning', () {
    test('a delete keeps the row and marks it deleted', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));

      await db.calendarCategoryDao.softDeleteById('c1');

      final row = await rowFor('c1');
      expect(row.isDeleted, isTrue);
      expect(row.deletedAt, isNotNull);
      expect(row.version, 2);
    });

    test('a built-in is refused, by flag and by id', () async {
      await db.calendarCategoryDao.insertCategory(
        category('gym', builtIn: true),
      );
      // A built-in id an older archive restored as custom.
      await db.calendarCategoryDao.insertCategory(category('other'));
      await db.calendarCategoryDao.insertCategory(category('c1'));

      expect(await db.calendarCategoryDao.softDeleteById('gym'), isFalse);
      expect(await db.calendarCategoryDao.softDeleteById('other'), isFalse);
      expect(await db.calendarCategoryDao.softDeleteById('c1'), isTrue);

      expect((await rowFor('gym')).isDeleted, isFalse);
      expect((await rowFor('other')).isDeleted, isFalse);
      expect((await rowFor('other')).version, 1);
    });

    test('deleting twice does not churn the version', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));
      await db.calendarCategoryDao.softDeleteById('c1');

      await db.calendarCategoryDao.softDeleteById('c1');

      expect((await rowFor('c1')).version, 2);
    });

    test('reads hide tombstones', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));
      await db.calendarCategoryDao.insertCategory(category('c2', order: 1));
      await db.calendarCategoryDao.softDeleteById('c1');

      expect((await db.calendarCategoryDao.getAll()).map((c) => c.id), ['c2']);
    });

    test('an edit or a hide after the delete does not resurrect it', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));
      await db.calendarCategoryDao.softDeleteById('c1');

      await db.calendarCategoryDao.updateCategory(
        const CalendarCategoriesCompanion(
          id: Value('c1'),
          name: Value('Back'),
          isHidden: Value(true),
        ),
      );
      await db.calendarCategoryDao.reorder(['c1']);

      final row = await rowFor('c1');
      expect(row.isDeleted, isTrue);
      expect(row.version, 2);
      expect(row.name, 'Climbing');
    });

    test('an import over a tombstone resurrects the row', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));
      await db.calendarCategoryDao.softDeleteById('c1');

      await db.calendarCategoryDao.importAll([category('c1', name: 'Back')]);

      final row = await rowFor('c1');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.name, 'Back');
      expect((await db.calendarCategoryDao.getAll()).single.id, 'c1');
    });

    test('the import wipe stays hard, tombstones included', () async {
      await db.calendarCategoryDao.insertCategory(category('c1'));
      await db.calendarCategoryDao.softDeleteById('c1');

      await db.calendarCategoryDao.deleteAll();

      expect(await db.select(db.calendarCategories).get(), isEmpty);
    });
  });

  group('v42 → v43 migration', () {
    /// The table at its v42 shape, holding a hidden built-in and a custom
    /// category.
    Future<void> rebuildAtV42() async {
      await rebuildCategoriesAtV42(db);
      await db.customStatement(
        'INSERT INTO calendar_categories '
        '(id, name, color_value, icon_key, sort_order, is_built_in, '
        'created_at, updated_at, is_hidden) '
        "VALUES ('gym', 'Gym', 1, 'event', 0, 1, 0, 0, 1), "
        "('custom', 'Climbing', 2, 'event', 1, 0, 0, 0, 0)",
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
    Future<List<QueryRow>> rows() {
      return db
          .customSelect('SELECT * FROM calendar_categories ORDER BY id')
          .get();
    }

    test('v43 is the current version', () {
      expect(DatabaseSchema.v43SyncReadiness, 43);
      expect(DatabaseSchema.currentVersion, DatabaseSchema.v43SyncReadiness);
    });

    test('backfills real identity onto every pre-existing row', () async {
      await rebuildAtV42();
      await runV43();

      final all = await rows();
      expect(all.map((r) => r.read<String>('id')), ['custom', 'gym']);
      for (final row in all) {
        expect(row.read<String>('hlc_timestamp'), isNotEmpty);
        expect(row.read<String>('device_id'), 'test-device');
        expect(row.read<int>('version'), 1);
        expect(row.read<int>('is_deleted'), 0);
        expect(row.readNullable<int>('deleted_at'), isNull);
        expect(row.readNullable<String>('owner_id'), isNull);
      }
      // The archive flag a v42 install set survives the conversion.
      expect(all.last.read<int>('is_hidden'), 1);
    });

    test('creates the partial catalog index', () async {
      await rebuildAtV42();
      await runV43();

      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_calendar_categories_active'",
          )
          .getSingle();
      expect(sql.read<String>('sql'), endsWith('WHERE is_deleted = 0'));
    });

    test('re-running it changes nothing', () async {
      await rebuildAtV42();
      await runV43();
      final once = await rows();

      await runV43();
      final twice = await rows();

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
    test('the catalog reads the partial index in order', () async {
      final counter = StatementCounter();
      final planned = await openTestDatabase(interceptor: counter);
      addTearDown(planned.close);
      counter.reset();

      await planned.calendarCategoryDao.getAll();

      final plan = await explainCaptured(planned, counter.selects.single);
      expect(plan.join('\n'), contains('idx_calendar_categories_active'));
      expect(plan.join('\n'), isNot(contains('TEMP B-TREE')));
    });
  });
}
