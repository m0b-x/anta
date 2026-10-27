import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `CalendarEventDao.mergeRemoteEvent`: the shared contract, a newer
/// event landing column for column, and a remote tombstone that cascades to
/// nothing — not the day rows, not the alerts, not the device-local
/// `alert_registrations`.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  CalendarEventsCompanion local(String id) {
    return CalendarEventsCompanion.insert(
      id: id,
      title: 'Leg day',
      category: 'gym',
      startDate: DateTime.utc(2026, 1, 1),
      ruleKind: 'daily',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
  }

  CalendarEventRow remote(String id, String hlc, {bool deleted = false}) {
    return CalendarEventRow(
      id: id,
      title: 'Pulled',
      category: 'climb',
      startDate: DateTime.utc(2026, 4, 1).toLocal(),
      allDay: false,
      iconKey: 'bolt',
      ruleKind: 'weekly',
      rulePayload: '{"weekdays":[2]}',
      endDate: DateTime.utc(2026, 9, 1).toLocal(),
      startMinute: 600,
      durationMinutes: 45,
      description: 'Bring chalk',
      noteId: 'n1',
      colorValue: 0xFF778899,
      tintIcon: false,
      priority: 2,
      retroactive: true,
      countOccurrences: true,
      countStyle: 'ordinal',
      tracksPresence: true,
      perOccurrenceDescriptions: true,
      showInDayRail: false,
      assumeAbsent: true,
      assumeAbsentFrom: DateTime.utc(2026, 5, 1).toLocal(),
      removeAfterAlert: true,
      categoryAlerts: false,
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
    MergeContract<CalendarEventRow>(
      table: 'calendar_events',
      freshKey: 'pulled',
      seedLocal: (db) async {
        await db.calendarEventDao.upsert(local('e1'));
        return 'e1';
      },
      remote: remote,
      merge: (db, row, {floor}) =>
          db.calendarEventDao.mergeRemoteEvent(row, floor: floor),
      markerColumn: 'title',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer event overwrites every data column', () async {
    await db.calendarEventDao.upsert(local('e1'));

    await db.calendarEventDao.mergeRemoteEvent(remote('e1', newerHlc));

    expect(
      await db.select(db.calendarEvents).getSingle(),
      remote('e1', newerHlc),
    );
  });

  test(
    'a tombstone leaves the day rows, alerts and registrations alone',
    () async {
      final day = DateTime.utc(2026, 3, 29);
      await db.calendarEventDao.upsert(local('e1'));
      await db.eventAbsenceDao.setStatus('e1', day, PresenceStatus.missed);
      await db.eventSkipDao.markSkipped('e1', DateTime.utc(2026, 3, 30));
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: day,
          description: 'Felt strong',
          createdAt: day,
          updatedAt: day,
        ),
      );
      await db.eventAlertDao.replaceForEvent('e1', [
        const EventAlertsCompanion(id: Value('a1'), eventId: Value('e1')),
      ]);
      await db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: const Value(7),
          alertId: const Value('a1'),
          eventId: const Value('e1'),
          day: Value(day.millisecondsSinceEpoch),
          fireAt: Value(day.millisecondsSinceEpoch),
          backend: const Value('alarm'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final queuedBefore = await db.syncOutboxDao.count();

      await db.calendarEventDao.mergeRemoteEvent(
        remote('e1', newerHlc, deleted: true),
      );

      expect(
        (await db.select(db.calendarEvents).getSingle()).isDeleted,
        isTrue,
      );
      expect(
        (await db.select(db.eventAbsences).getSingle()).isDeleted,
        isFalse,
      );
      expect((await db.select(db.eventSkips).getSingle()).isDeleted, isFalse);
      expect(
        (await db.select(db.eventOccurrenceDescriptions).getSingle()).isDeleted,
        isFalse,
      );
      expect((await db.select(db.eventAlerts).getSingle()).isDeleted, isFalse);
      expect(await db.alertRegistrationDao.forEvent('e1'), hasLength(1));
      expect(
        await db.syncOutboxDao.count(),
        queuedBefore - 1,
        reason: 'the event\'s own entry retired, nothing queued',
      );
    },
  );

  test('a merged tombstone dates updated_at at the delete', () async {
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'e1',
        title: 'Boulder',
        category: 'climb',
        startDate: DateTime.utc(2026, 1, 1),
        ruleKind: 'daily',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    final tombstone = remote('e1', newerHlc, deleted: true);

    await db.calendarEventDao.mergeRemoteEvent(tombstone);

    // The deleting device stored the delete time; before this the merging
    // one kept the last edit's, on all eleven tables (A7 R81).
    expect(
      (await db.select(db.calendarEvents).getSingle()).updatedAt,
      tombstone.deletedAt,
    );
  });
}
