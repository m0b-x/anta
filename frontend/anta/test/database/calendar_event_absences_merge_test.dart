import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/calendar_event_absences_binding.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `EventAbsenceDao.mergeRemoteAbsence`: the shared contract on the
/// `eventId|dayMs` key, a newer mark landing column for column, and a day key
/// that round-trips through the wire to the same stored day.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  // The EU fall-back day, where a local-midnight read lands an hour off.
  final day = DateTime.utc(2026, 10, 25);

  EventAbsenceRow remote(String key, String hlc, {bool deleted = false}) {
    final split = key.lastIndexOf('|');
    return EventAbsenceRow(
      eventId: key.substring(0, split),
      day: DateTime.fromMillisecondsSinceEpoch(
        int.parse(key.substring(split + 1)),
      ),
      status: 'present',
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

  Future<void> seed() =>
      db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.missed);

  runMergeContract(
    MergeContract<EventAbsenceRow>(
      table: 'calendar_event_absences',
      freshKey: dayRowKey('e9', DateTime.utc(2026, 3, 29)),
      seedLocal: (_) async {
        await seed();
        return dayRowKey('e1', day);
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.eventAbsenceDao.mergeRemoteAbsence(row, floor: floor),
      markerColumn: 'status',
      markerValue: 'present',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer mark overwrites every data column', () async {
    await seed();
    final key = dayRowKey('e1', day);

    await db.eventAbsenceDao.mergeRemoteAbsence(remote(key, newerHlc));

    expect(
      await db.select(db.eventAbsences).getSingle(),
      remote(key, newerHlc),
    );
  });

  test('a day key crosses the wire to the same stored day', () async {
    const binding = CalendarEventAbsencesBinding();
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
        .customSelect('SELECT day FROM calendar_event_absences')
        .getSingle();
    expect(raw.read<int>('day'), day.millisecondsSinceEpoch ~/ 1000);
  });
}
