import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `CategoryAlertDao.mergeRemoteCategoryAlert`: the shared contract,
/// every payload column landing as received, and a newer row moving an alert
/// to another category — the stamp decides, where `replaceForCategory`
/// refuses an id another category owns.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  CategoryAlertRow remote(String id, String hlc, {bool deleted = false}) {
    return CategoryAlertRow(
      id: id,
      categoryId: 'climb',
      mode: 'ring',
      offsetMinutes: 30,
      daysBefore: 2,
      dayMinute: 1200,
      sound: 'bell',
      enabled: false,
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

  Future<void> seed() => db.categoryAlertDao.replaceForCategory('climb', [
    const CalendarCategoryAlertsCompanion(
      id: Value('ca1'),
      categoryId: Value('climb'),
    ),
  ]);

  runMergeContract(
    MergeContract<CategoryAlertRow>(
      table: 'calendar_category_alerts',
      freshKey: 'pulled',
      seedLocal: (_) async {
        await seed();
        return 'ca1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.categoryAlertDao.mergeRemoteCategoryAlert(row, floor: floor),
      markerColumn: 'mode',
      markerValue: 'ring',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer alert lands every payload column as received', () async {
    await seed();

    await db.categoryAlertDao.mergeRemoteCategoryAlert(remote('ca1', newerHlc));

    expect(
      await db.select(db.calendarCategoryAlerts).getSingle(),
      remote('ca1', newerHlc),
    );
  });

  test('a newer row moves the alert to another category', () async {
    await seed();
    final moved = remote('ca1', newerHlc).copyWith(categoryId: 'gym');

    final outcome = await db.categoryAlertDao.mergeRemoteCategoryAlert(moved);

    expect(outcome.result, MergeResult.applied);
    expect(
      (await db.select(db.calendarCategoryAlerts).getSingle()).categoryId,
      'gym',
    );
  });
}
