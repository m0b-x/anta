import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/calendar_event_skips_binding.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `EventSkipDao.mergeRemoteSkip`: the shared contract on the
/// `eventId|dayMs` key, a newer skip landing column for column, and a day key
/// that round-trips through the wire to the same stored day. A skip carries
/// no data column of its own, so the contract's marker is `created_at`.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  // The US spring-forward day, where a local-midnight read lands an hour off.
  final day = DateTime.utc(2026, 3, 8);
  final remoteCreated = DateTime.utc(2026, 3, 1);

  EventSkipRow remote(String key, String hlc, {bool deleted = false}) {
    final split = key.lastIndexOf('|');
    return EventSkipRow(
      eventId: key.substring(0, split),
      day: DateTime.fromMillisecondsSinceEpoch(
        int.parse(key.substring(split + 1)),
      ),
      createdAt: remoteCreated.toLocal(),
      updatedAt: DateTime.utc(2026, 3, 2).toLocal(),
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 3, 3).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  Future<void> seed() => db.eventSkipDao.markSkipped('e1', day);

  runMergeContract(
    MergeContract<EventSkipRow>(
      table: 'calendar_event_skips',
      freshKey: dayRowKey('e9', DateTime.utc(2026, 11, 1)),
      seedLocal: (_) async {
        await seed();
        return dayRowKey('e1', day);
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.eventSkipDao.mergeRemoteSkip(row, floor: floor),
      markerColumn: 'created_at',
      markerValue: remoteCreated.millisecondsSinceEpoch ~/ 1000,
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer skip overwrites every data column', () async {
    await seed();
    final key = dayRowKey('e1', day);

    await db.eventSkipDao.mergeRemoteSkip(remote(key, newerHlc));

    expect(await db.select(db.eventSkips).getSingle(), remote(key, newerHlc));
  });

  test('a day key crosses the wire to the same stored day', () async {
    const binding = CalendarEventSkipsBinding();
    final key = dayRowKey('e1', day);

    await binding.mergeRemote(
      db,
      SyncEnvelope(
        table: binding.table,
        rowKey: key,
        hlc: newerHlc,
        deviceId: 'remote',
        version: 1,
        op: OutboxOp.tombstone,
        ownerId: 'uid-1',
      ),
    );

    final row = (await binding.loadByKeys(db, [key])).single;
    expect(binding.rowKeyOf(row), key);
    expect(row.day.millisecondsSinceEpoch, day.millisecondsSinceEpoch);
    final raw = await db
        .customSelect('SELECT day FROM calendar_event_skips')
        .getSingle();
    expect(raw.read<int>('day'), day.millisecondsSinceEpoch ~/ 1000);
  });
}
