import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `OverviewViewDao.mergeRemoteView`: the shared contract and the
/// payload landing verbatim, a field this build does not know included.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  const payload = '{"period":{"kind":"thisYear"},"fromTheFuture":1}';

  OverviewViewRow remote(String id, String hlc, {bool deleted = false}) {
    return OverviewViewRow(
      id: id,
      name: 'Pulled',
      payload: payload,
      sortOrder: 6,
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

  Future<void> seed() => db.overviewViewDao.upsertView(
    const OverviewViewsCompanion(
      id: Value('v1'),
      name: Value('Mine'),
      payload: Value('{}'),
    ),
  );

  runMergeContract(
    MergeContract<OverviewViewRow>(
      table: 'overview_views',
      freshKey: 'pulled',
      seedLocal: (_) async {
        await seed();
        return 'v1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.overviewViewDao.mergeRemoteView(row, floor: floor),
      markerColumn: 'payload',
      markerValue: payload,
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer view lands every column, its payload verbatim', () async {
    await seed();

    await db.overviewViewDao.mergeRemoteView(remote('v1', newerHlc));

    expect(
      await db.select(db.overviewViews).getSingle(),
      remote('v1', newerHlc),
    );
  });
}
