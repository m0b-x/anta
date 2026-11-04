// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `CategoryProfileDao`'s local writes: one live profile per category,
/// updated in place under its first id, converged when a merge left two, an
/// unchanged save stamping nothing, the delete cascade and the import path —
/// each write stamped and queued as the category alert DAO's are.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Map<String, String>> queued() async => {
    for (final row in await db.syncOutboxDao.pending())
      if (row.syncedTable == 'calendar_category_profiles') row.rowKey: row.op,
  };

  Future<CategoryProfileRow> stored(String id) {
    return (db.select(
      db.calendarCategoryProfiles,
    )..where((p) => p.id.equals(id))).getSingle();
  }

  CalendarCategoryProfilesCompanion draft(
    String id,
    String categoryId, {
    String kind = 'workout',
    int? targetValue,
  }) {
    return CalendarCategoryProfilesCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      kind: Value(kind),
      targetValue: Value(targetValue),
    );
  }

  group('upsertForCategory', () {
    test('inserts the first profile under the draft\'s id', () async {
      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym', targetValue: 3),
      );

      final row = await stored('p1');
      expect(row.categoryId, 'gym');
      expect(row.kind, 'workout');
      expect(row.targetValue, 3);
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deviceId, 'test-device');
      expect(await queued(), {'p1': 'upsert'});
    });

    test('an insert keeps a createdAt the draft carries', () async {
      final created = DateTime(2024, 3, 5, 9, 30);
      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym').copyWith(createdAt: Value(created)),
      );

      expect((await stored('p1')).createdAt, created);
    });

    test('a save after a delete revives the tombstoned id', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
      await db.categoryProfileDao.tombstoneForCategory('gym');
      final buried = await stored('p1');
      await db.syncOutboxDao.clear();

      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym', kind: 'class', targetValue: 2),
      );

      final row = await stored('p1');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(row.kind, 'class');
      expect(row.targetValue, 2);
      expect(row.version, buried.version + 1);
      expect(row.hlcTimestamp.compareTo(buried.hlcTimestamp), greaterThan(0));
      expect(row.createdAt, buried.createdAt);
      expect((await db.categoryProfileDao.getAllActive()).map((p) => p.id), [
        'p1',
      ]);
      expect(await queued(), {'p1': 'upsert'});
    });

    test('a revival keeps a createdAt the draft carries', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
      await db.categoryProfileDao.tombstoneForCategory('gym');
      final created = DateTime(2024, 3, 5, 9, 30);

      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym').copyWith(createdAt: Value(created)),
      );

      expect((await stored('p1')).createdAt, created);
    });

    /// The id is the service's to mint, so a clash is a caller's bug: named,
    /// rather than SQLite's primary-key failure or a profile moved to
    /// another category.
    test('a draft id another category holds live is refused', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'run'));
      final run = await stored('p1');
      await db.syncOutboxDao.clear();

      await expectLater(
        db.categoryProfileDao.upsertForCategory(draft('p1', 'gym')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('"run"'), contains('"gym"')),
          ),
        ),
      );

      expect(await stored('p1'), run);
      expect(await db.categoryProfileDao.getActiveForCategory('gym'), isNull);
      expect(await queued(), isEmpty);
    });

    test('the unchanged check tells a null verb from an empty one', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
      final first = await stored('p1');
      expect(first.markVerb, isNull);
      await db.syncOutboxDao.clear();

      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym').copyWith(markVerb: const Value('')),
      );

      final row = await stored('p1');
      expect(row.markVerb, '');
      expect(row.version, first.version + 1);
      expect(await queued(), {'p1': 'upsert'});
    });

    test('a second save updates in place, keeping the first id', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
      final first = await stored('p1');

      await db.categoryProfileDao.upsertForCategory(
        draft('p2', 'gym', kind: 'class', targetValue: 2),
      );

      final rows = await db.select(db.calendarCategoryProfiles).get();
      expect(rows.map((r) => r.id), ['p1']);
      final row = rows.single;
      expect(row.kind, 'class');
      expect(row.targetValue, 2);
      expect(row.version, first.version + 1);
      expect(row.hlcTimestamp.compareTo(first.hlcTimestamp), greaterThan(0));
      expect(row.createdAt, first.createdAt);
      expect(await queued(), {'p1': 'upsert'});
    });

    test('an unchanged save stamps and queues nothing', () async {
      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym', targetValue: 3),
      );
      final first = await stored('p1');
      await db.syncOutboxDao.clear();

      await db.categoryProfileDao.upsertForCategory(
        draft('p1', 'gym', targetValue: 3),
      );

      final row = await stored('p1');
      expect(row.version, first.version);
      expect(row.hlcTimestamp, first.hlcTimestamp);
      expect(await queued(), isEmpty);
    });

    test('a save converges two live profiles of one category to one', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
      // Another device made its own before the two met; the merge keeps both.
      final elsewhere = (await stored('p1')).copyWith(
        id: 'p-elsewhere',
        kind: 'class',
        hlcTimestamp: newerHlc,
        deviceId: 'remote',
      );
      await db.categoryProfileDao.mergeRemoteCategoryProfile(elsewhere);
      expect(await db.categoryProfileDao.getAllActive(), hasLength(2));
      await db.syncOutboxDao.clear();

      await db.categoryProfileDao.upsertForCategory(
        draft('p-new', 'gym', kind: 'workout', targetValue: 4),
      );

      final live = await db.categoryProfileDao.getAllActive();
      expect(live.map((p) => p.id), ['p-elsewhere']);
      expect(live.single.targetValue, 4);
      expect(live.single.kind, 'workout');
      final gone = await stored('p1');
      expect(gone.isDeleted, isTrue);
      expect(gone.deletedAt, isNotNull);
      expect(gone.hlcTimestamp, live.single.hlcTimestamp);
      expect(await queued(), {'p1': 'tombstone', 'p-elsewhere': 'upsert'});
    });

    test(
      'a category\'s save leaves another category\'s profile alone',
      () async {
        await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
        await db.categoryProfileDao.upsertForCategory(draft('p2', 'swim'));

        final live = await db.categoryProfileDao.getAllActive();
        expect(live.map((p) => (p.id, p.categoryId)), [
          ('p1', 'gym'),
          ('p2', 'swim'),
        ]);
      },
    );
  });

  group('tombstoneForCategory', () {
    test(
      'tombstones every live row of the category and returns them',
      () async {
        await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
        await db.categoryProfileDao.mergeRemoteCategoryProfile(
          (await stored('p1')).copyWith(id: 'p2', hlcTimestamp: newerHlc),
        );
        await db.categoryProfileDao.upsertForCategory(draft('p3', 'swim'));
        await db.syncOutboxDao.clear();

        final ids = await db.categoryProfileDao.tombstoneForCategory('gym');

        expect(ids, unorderedEquals(['p1', 'p2']));
        expect((await stored('p1')).isDeleted, isTrue);
        expect((await stored('p2')).isDeleted, isTrue);
        expect((await stored('p1')).version, 2);
        expect((await db.categoryProfileDao.getAllActive()).map((p) => p.id), [
          'p3',
        ]);
        expect(await queued(), {'p1': 'tombstone', 'p2': 'tombstone'});
      },
    );

    test('a repeat touches nothing', () async {
      await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
      await db.categoryProfileDao.tombstoneForCategory('gym');
      final first = await stored('p1');
      await db.syncOutboxDao.clear();

      expect(await db.categoryProfileDao.tombstoneForCategory('gym'), isEmpty);
      expect((await stored('p1')).version, first.version);
      expect(await queued(), isEmpty);
    });
  });

  test('getAllActive and getActiveForCategory skip tombstones', () async {
    await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
    await db.categoryProfileDao.upsertForCategory(draft('p2', 'swim'));
    await db.categoryProfileDao.tombstoneForCategory('gym');

    expect((await db.categoryProfileDao.getAllActive()).map((p) => p.id), [
      'p2',
    ]);
    expect(await db.categoryProfileDao.getActiveForCategory('gym'), isNull);
    expect(
      await db.categoryProfileDao.getByIdsIncludingDeleted(['p1', 'p2']),
      hasLength(2),
    );
  });

  test('importAll keeps the archive\'s fields and stamps fresh', () async {
    final created = DateTime.utc(2025, 1, 2, 3, 4, 5).toLocal();
    final updated = DateTime.utc(2025, 6, 7, 8, 9, 10).toLocal();
    await db.categoryProfileDao.importAll([
      CalendarCategoryProfilesCompanion.insert(
        id: 'p1',
        categoryId: 'gym',
        kind: const Value('workout'),
        markVerb: const Value(''),
        marksNew: const Value(false),
        targetKind: const Value('atLeast'),
        targetValue: const Value(3),
        targetPeriod: const Value('week'),
        createdAt: created,
        updatedAt: updated,
        hlcTimestamp: 'from-the-archive',
        deviceId: 'archive-device',
      ),
    ]);

    final row = await stored('p1');
    expect(row.createdAt, created);
    expect(row.updatedAt, updated);
    expect(row.markVerb, '', reason: 'marking off is a value, not absence');
    expect(row.marksNew, isFalse);
    expect(
      (row.targetKind, row.targetValue, row.targetPeriod),
      ('atLeast', 3, 'week'),
    );
    expect(row.hlcTimestamp, isNot('from-the-archive'));
    expect(row.deviceId, 'test-device');
    expect(row.version, 1);
    expect(await queued(), {'p1': 'upsert'});
  });

  test('deleteAll wipes tombstones too', () async {
    await db.categoryProfileDao.upsertForCategory(draft('p1', 'gym'));
    await db.categoryProfileDao.tombstoneForCategory('gym');

    await db.categoryProfileDao.deleteAll();

    expect(await db.select(db.calendarCategoryProfiles).get(), isEmpty);
  });

  test('the category delete cascade tombstones its profile', () async {
    final at = DateTime.utc(2026, 10, 1);
    await db.calendarCategoryDao.insertCategory(
      CalendarCategoriesCompanion(
        id: const Value('climb'),
        name: const Value('Climb'),
        colorValue: const Value(0xFF00FF00),
        iconKey: const Value('event'),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
    await db.categoryProfileDao.upsertForCategory(draft('p1', 'climb'));
    await db.categoryProfileDao.upsertForCategory(draft('p2', 'gym'));
    await db.syncOutboxDao.clear();

    final deleted = await db.calendarCategoryDao.tombstoneCascade(
      'climb',
      reassignTo: 'other',
    );

    expect(deleted, isTrue);
    final profile = await stored('p1');
    final category = await (db.select(
      db.calendarCategories,
    )..where((c) => c.id.equals('climb'))).getSingle();
    expect(profile.isDeleted, isTrue);
    expect(profile.hlcTimestamp, category.hlcTimestamp);
    expect((await stored('p2')).isDeleted, isFalse);
    expect(await queued(), {'p1': 'tombstone'});
  });
}
