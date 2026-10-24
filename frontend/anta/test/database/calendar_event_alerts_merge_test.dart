import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `EventAlertDao.mergeRemoteAlert`: the shared contract, every
/// payload column landing as received — a mode this build does not know
/// included — and the device-local `alert_registrations` untouched.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  EventAlertRow remote(String id, String hlc, {bool deleted = false}) {
    return EventAlertRow(
      id: id,
      eventId: 'e1',
      mode: 'ring',
      offsetMinutes: 15,
      daysBefore: 1,
      dayMinute: 480,
      sound: 'chime',
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

  Future<void> seed() => db.eventAlertDao.replaceForEvent('e1', [
    const EventAlertsCompanion(id: Value('a1'), eventId: Value('e1')),
  ]);

  runMergeContract(
    MergeContract<EventAlertRow>(
      table: 'calendar_event_alerts',
      freshKey: 'pulled',
      seedLocal: (_) async {
        await seed();
        return 'a1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.eventAlertDao.mergeRemoteAlert(row, floor: floor),
      markerColumn: 'mode',
      markerValue: 'ring',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer alert lands every payload column as received', () async {
    await seed();
    final future = remote('a1', newerHlc).copyWith(mode: 'futureMode');

    await db.eventAlertDao.mergeRemoteAlert(future);

    expect(await db.select(db.eventAlerts).getSingle(), future);
  });

  test('a merge leaves the device-local registrations alone', () async {
    await seed();
    final day = DateTime.utc(2026, 9, 15).millisecondsSinceEpoch;
    await db.alertRegistrationDao.put(
      AlertRegistrationsCompanion(
        osId: const Value(7),
        alertId: const Value('a1'),
        eventId: const Value('e1'),
        day: Value(day),
        fireAt: Value(day),
        backend: const Value('alarm'),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await db.eventAlertDao.mergeRemoteAlert(
      remote('a1', newerHlc, deleted: true),
    );

    final registrations = await db.alertRegistrationDao.forEvent('e1');
    expect(registrations.single.osId, 7);
    expect(registrations.single.state, 'pending');
  });
}
