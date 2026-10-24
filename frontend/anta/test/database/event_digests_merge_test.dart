import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `EventDigestDao.mergeRemoteDigest`: the shared contract and the
/// payload landing verbatim, a field this build does not know included.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  const payload = '{"cadence":"weekly","lead":1,"fromTheFuture":true}';

  EventDigestRow remote(String id, String hlc, {bool deleted = false}) {
    return EventDigestRow(
      id: id,
      name: 'Pulled',
      payload: payload,
      enabled: false,
      sortOrder: 3,
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

  Future<void> seed() => db.eventDigestDao.upsertDigest(
    const EventDigestsCompanion(
      id: Value('d1'),
      name: Value('Mine'),
      payload: Value('{"cadence":"monthly"}'),
    ),
  );

  runMergeContract(
    MergeContract<EventDigestRow>(
      table: 'event_digests',
      freshKey: 'pulled',
      seedLocal: (_) async {
        await seed();
        return 'd1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.eventDigestDao.mergeRemoteDigest(row, floor: floor),
      markerColumn: 'payload',
      markerValue: payload,
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer digest lands every column, its payload verbatim', () async {
    await seed();

    await db.eventDigestDao.mergeRemoteDigest(remote('d1', newerHlc));

    expect(
      await db.select(db.eventDigests).getSingle(),
      remote('d1', newerHlc),
    );
  });
}
