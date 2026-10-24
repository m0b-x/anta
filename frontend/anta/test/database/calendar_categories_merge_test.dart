// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `CalendarCategoryDao.mergeRemoteCategory`: the shared contract, a
/// built-in's fixed id merging like any row, and a remote tombstone that
/// reassigns no event.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  final at = DateTime.utc(2026, 10, 1);

  CalendarCategoriesCompanion local(String id, {bool builtIn = false}) {
    return CalendarCategoriesCompanion(
      id: Value(id),
      name: const Value('Climb'),
      colorValue: const Value(0xFF00FF00),
      iconKey: const Value('event'),
      isBuiltIn: Value(builtIn),
      createdAt: Value(at),
      updatedAt: Value(at),
    );
  }

  CalendarCategoryRow remote(String id, String hlc, {bool deleted = false}) {
    return CalendarCategoryRow(
      id: id,
      name: 'Pulled',
      colorValue: 0xFF112233,
      iconKey: 'star',
      sortOrder: 4,
      isBuiltIn: false,
      isHidden: true,
      createdAt: DateTime.utc(2026, 3, 1).toLocal(),
      updatedAt: DateTime.utc(2026, 3, 2).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 3, 3).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  runMergeContract(
    MergeContract<CalendarCategoryRow>(
      table: 'calendar_categories',
      freshKey: 'pulled',
      seedLocal: (db) async {
        await db.calendarCategoryDao.insertCategory(local('climb'));
        return 'climb';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.calendarCategoryDao.mergeRemoteCategory(row, floor: floor),
      markerColumn: 'name',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  Future<CalendarCategoryRow> storedRow(String id) => (db.select(
    db.calendarCategories,
  )..where((c) => c.id.equals(id))).getSingle();

  test('a newer category overwrites every data column', () async {
    await db.calendarCategoryDao.insertCategory(local('climb'));

    await db.calendarCategoryDao.mergeRemoteCategory(remote('climb', newerHlc));

    expect(await storedRow('climb'), remote('climb', newerHlc));
  });

  test('a built-in id merges like any row, and its tombstone is seeded '
      'back', () async {
    await db.calendarCategoryDao.seedMissing([local('other', builtIn: true)]);
    final builtIn = remote(
      'other',
      newerHlc,
    ).copyWith(name: 'Fallback', isBuiltIn: true);

    final outcome = await db.calendarCategoryDao.mergeRemoteCategory(builtIn);

    expect(outcome.result, MergeResult.applied);
    expect(await storedRow('other'), builtIn);

    await db.calendarCategoryDao.mergeRemoteCategory(
      remote('other', 'ffffffffffff:0002:remote', deleted: true),
    );
    expect((await storedRow('other')).isDeleted, isTrue);

    await db.calendarCategoryDao.seedMissing([local('other', builtIn: true)]);
    final back = await storedRow('other');
    expect(back.isDeleted, isFalse);
    expect(back.isBuiltIn, isTrue);
  });

  test('a tombstone reassigns no event', () async {
    await db.calendarCategoryDao.insertCategory(local('climb'));
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'e1',
        title: 'Boulder',
        category: 'climb',
        startDate: DateTime.utc(2026, 1, 1),
        ruleKind: 'daily',
        createdAt: at,
        updatedAt: at,
      ),
    );

    await db.calendarCategoryDao.mergeRemoteCategory(
      remote('climb', newerHlc, deleted: true),
    );

    final event = await db.select(db.calendarEvents).getSingle();
    expect(event.category, 'climb');
    expect((await storedRow('climb')).name, 'Climb', reason: 'no data');
  });
}
