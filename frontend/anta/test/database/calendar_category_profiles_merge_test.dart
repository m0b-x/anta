import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `CategoryProfileDao.mergeRemoteCategoryProfile`: the shared
/// contract, every payload column landing as received, a newer row moving a
/// profile to another category, and a second live profile for one category
/// kept rather than refused — the local upsert is what converges them.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  CategoryProfileRow remote(String id, String hlc, {bool deleted = false}) {
    return CategoryProfileRow(
      id: id,
      categoryId: 'climb',
      kind: 'workout',
      area: 'body',
      measure: 'count',
      nominalMinutes: 90,
      markVerb: '',
      marksNew: true,
      assumeAbsentNew: false,
      countsHours: true,
      targetKind: 'atLeast',
      targetValue: 3,
      targetPeriod: 'week',
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

  Future<void> seed() => db.categoryProfileDao.upsertForCategory(
    const CalendarCategoryProfilesCompanion(
      id: Value('cp1'),
      categoryId: Value('climb'),
    ),
  );

  runMergeContract(
    MergeContract<CategoryProfileRow>(
      table: 'calendar_category_profiles',
      freshKey: 'pulled',
      seedLocal: (_) async {
        await seed();
        return 'cp1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.categoryProfileDao.mergeRemoteCategoryProfile(row, floor: floor),
      markerColumn: 'kind',
      markerValue: 'workout',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer profile lands every payload column as received', () async {
    await seed();

    await db.categoryProfileDao.mergeRemoteCategoryProfile(
      remote('cp1', newerHlc),
    );

    expect(
      await db.select(db.calendarCategoryProfiles).getSingle(),
      remote('cp1', newerHlc),
    );
  });

  test('a newer row moves the profile to another category', () async {
    await seed();
    final moved = remote('cp1', newerHlc).copyWith(categoryId: 'gym');

    final outcome = await db.categoryProfileDao.mergeRemoteCategoryProfile(
      moved,
    );

    expect(outcome.result, MergeResult.applied);
    expect(
      (await db.select(db.calendarCategoryProfiles).getSingle()).categoryId,
      'gym',
    );
  });

  test('another device\'s profile for the same category is kept', () async {
    await seed();

    final outcome = await db.categoryProfileDao.mergeRemoteCategoryProfile(
      remote('cp-elsewhere', newerHlc),
    );

    expect(outcome.result, MergeResult.inserted);
    final live = await db.categoryProfileDao.getAllActive();
    expect(live.map((p) => p.id), ['cp1', 'cp-elsewhere']);
    expect(
      (await db.categoryProfileDao.getActiveForCategory('climb'))!.id,
      'cp-elsewhere',
      reason: 'the newest stamp is the one a category reads',
    );
  });
}
