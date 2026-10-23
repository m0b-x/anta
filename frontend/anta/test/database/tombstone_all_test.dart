import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

import 'support/db_test_support.dart';

/// Guards "Delete all events" as a tombstoning wipe (D13): every live row this
/// device may delete tombstones under one HLC and is queued once, so the wipe
/// reaches the other device; rows of another account stay; a repeat writes
/// nothing.
void main() {
  late StatementCounter counter;
  late AppDatabase db;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });
  tearDown(() async => db.close());

  const childTables = [
    'calendar_event_absences',
    'calendar_event_occurrences',
    'calendar_event_skips',
    'calendar_event_alerts',
  ];
  final day = DateTime.utc(2026, 3, 29);

  CalendarEventsCompanion event(String id) => CalendarEventsCompanion.insert(
    id: id,
    title: 'Leg day',
    category: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    ruleKind: 'daily',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  /// An event with one row in each of the four child tables.
  Future<void> seed(String id) async {
    final now = DateTime.now();
    await db.calendarEventDao.upsert(event(id));
    await db.eventAbsenceDao.importAll([
      EventAbsencesCompanion.insert(
        eventId: id,
        day: day,
        createdAt: now,
        updatedAt: now,
        hlcTimestamp: '',
        deviceId: '',
      ),
    ]);
    await db.eventSkipDao.importAll([
      EventSkipsCompanion.insert(
        eventId: id,
        day: day,
        createdAt: now,
        updatedAt: now,
        hlcTimestamp: '',
        deviceId: '',
      ),
    ]);
    await db.eventOccurrenceDao.importAll([
      EventOccurrenceDescriptionsCompanion.insert(
        eventId: id,
        day: day,
        description: 'notes',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    await db.eventAlertDao.importAll([
      EventAlertsCompanion(
        id: Value('alert-$id'),
        eventId: Value(id),
        offsetMinutes: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    ]);
  }

  Future<void> ownBy(String eventId, String owner) async {
    await db.customStatement(
      'UPDATE calendar_events SET owner_id = ? WHERE id = ?',
      [owner, eventId],
    );
    for (final table in childTables) {
      await db.customStatement(
        'UPDATE $table SET owner_id = ? WHERE event_id = ?',
        [owner, eventId],
      );
    }
  }

  Future<Set<(String, String, String, String)>> outbox() async {
    final rows = await db.syncOutboxDao.pending();
    return {for (final r in rows) (r.syncedTable, r.rowKey, r.op, r.hlc)};
  }

  /// `(is_deleted, hlc, version)` of every row of [eventId] in all five
  /// tables.
  Future<List<(bool, String, int)>> rowsOf(String eventId) async {
    final rows = await db
        .customSelect(
          [
            "SELECT is_deleted, hlc_timestamp, version FROM calendar_events "
                "WHERE id = '$eventId'",
            for (final table in childTables)
              'SELECT is_deleted, hlc_timestamp, version FROM $table '
                  "WHERE event_id = '$eventId'",
          ].join(' UNION ALL '),
        )
        .get();
    return [
      for (final row in rows)
        (
          row.read<bool>('is_deleted'),
          row.read<String>('hlc_timestamp'),
          row.read<int>('version'),
        ),
    ];
  }

  Set<(String, String)> keysOf(String eventId) => {
    ('calendar_events', eventId),
    ('calendar_event_absences', dayRowKey(eventId, day)),
    ('calendar_event_occurrences', dayRowKey(eventId, day)),
    ('calendar_event_skips', dayRowKey(eventId, day)),
    ('calendar_event_alerts', 'alert-$eventId'),
  };

  test('every live row tombstones under one HLC, each queued once', () async {
    await seed('e1');
    await seed('e2');
    await seed('gone');
    await db.syncOutboxDao.clear();
    await db.calendarEventDao.tombstoneEventCascade('gone');
    final goneRows = await rowsOf('gone');
    final goneQueue = await outbox();
    expect(goneQueue, hasLength(5));

    await db.calendarEventDao.tombstoneAll(ownerUid: null);

    expect(await db.calendarEventDao.getAll(), isEmpty);
    final wiped = [...await rowsOf('e1'), ...await rowsOf('e2')];
    expect(wiped, hasLength(10));
    expect(wiped.every((r) => r.$1), isTrue);
    final stamps = {for (final r in wiped) r.$2};
    expect(stamps, hasLength(1));
    final stamp = stamps.single;
    expect(stamp.compareTo(goneQueue.first.$4), greaterThan(0));

    // The earlier tombstones and their entries are untouched.
    expect(await rowsOf('gone'), goneRows);
    final queue = await outbox();
    expect(queue.containsAll(goneQueue), isTrue);
    expect(queue.difference(goneQueue), {
      for (final (table, key) in {...keysOf('e1'), ...keysOf('e2')})
        (table, key, OutboxOp.tombstone.name, stamp),
    });
  });

  test('only the bound account\'s rows and unowned ones go', () async {
    await seed('plain');
    await seed('mine');
    await seed('theirs');
    await ownBy('mine', 'me');
    await ownBy('theirs', 'them');
    await db.syncOutboxDao.clear();

    // Unbound: only the rows no account owns.
    await db.calendarEventDao.tombstoneAll(ownerUid: null);
    expect(
      (await db.calendarEventDao.getAll()).map((e) => e.id),
      unorderedEquals(['mine', 'theirs']),
    );

    await db.calendarEventDao.tombstoneAll(ownerUid: 'me');

    expect((await db.calendarEventDao.getAll()).map((e) => e.id), ['theirs']);
    expect((await rowsOf('theirs')).every((r) => !r.$1), isTrue);
    expect((await rowsOf('mine')).every((r) => r.$1), isTrue);
    final queued = {for (final e in await outbox()) (e.$1, e.$2)};
    expect(queued, {...keysOf('plain'), ...keysOf('mine')});
  });

  test('a repeat writes nothing', () async {
    await seed('e1');
    await db.calendarEventDao.tombstoneAll(ownerUid: null);
    final rows = await rowsOf('e1');
    final queue = await outbox();
    counter.reset();

    await db.calendarEventDao.tombstoneAll(ownerUid: null);

    expect(counter.matching('INSERT'), isEmpty);
    expect(await rowsOf('e1'), rows);
    expect(await outbox(), queue);
  });

  group('CalendarEventService.tombstoneAll', () {
    tearDown(() {
      CalendarEventService.reset();
      EventOccurrenceService.reset();
      EventPresenceService.reset();
      EventSkipService.reset();
      EventAlertService.reset();
      SyncBindingService.reset();
      SettingsService.reset();
    });

    Future<void> register(String eventId, int osId) {
      return db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: Value(osId),
          alertId: Value('alert-$eventId'),
          eventId: Value(eventId),
          day: Value(day.millisecondsSinceEpoch),
          fireAt: Value(day.millisecondsSinceEpoch),
          backend: const Value('alarm'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    Future<List<String>> registeredEvents() async => [
      for (final row in await db.select(db.alertRegistrations).get())
        row.eventId,
    ];

    test('leaves no event, export or registration behind', () async {
      await seed('e1');
      await seed('e2');
      await register('e1', 7);
      SyncBindingService.forTesting(db, SettingsService.forTesting(db));
      final occurrences = await EventOccurrenceService.forTesting(db);
      final presence = await EventPresenceService.forTesting(db);
      final skips = await EventSkipService.forTesting(db);
      final alerts = await EventAlertService.forTesting(db);
      final service = await CalendarEventService.forTesting(db);
      expect(service.events, hasLength(2));

      await service.tombstoneAll();

      expect(service.events, isEmpty);
      expect(await service.exportData(), isEmpty);
      expect(await occurrences.exportData(), isEmpty);
      expect(await presence.exportData(), isEmpty);
      expect(await skips.exportData(), isEmpty);
      expect(await alerts.exportData(), isEmpty);
      expect(await db.select(db.alertRegistrations).get(), isEmpty);
    });

    test('another account\'s event stays shown, exported and armed', () async {
      await seed('e1');
      await seed('e2');
      await ownBy('e2', 'them');
      await register('e1', 7);
      await register('e2', 8);
      SyncBindingService.forTesting(db, SettingsService.forTesting(db));
      final occurrences = await EventOccurrenceService.forTesting(db);
      final presence = await EventPresenceService.forTesting(db);
      final skips = await EventSkipService.forTesting(db);
      final alerts = await EventAlertService.forTesting(db);
      final service = await CalendarEventService.forTesting(db);

      await service.tombstoneAll();

      expect(service.events.map((e) => e.id), ['e2']);
      expect((await service.exportData()).map((r) => r['id']), ['e2']);
      for (final rows in [
        await occurrences.exportData(),
        await presence.exportData(),
        await skips.exportData(),
        await alerts.exportData(),
      ]) {
        expect(rows.map((r) => r['eventId']), ['e2']);
      }
      expect(await registeredEvents(), ['e2']);
    });

    test('bound, the account\'s and the unowned events go', () async {
      await seed('plain');
      await seed('mine');
      await seed('theirs');
      await ownBy('mine', 'me');
      await ownBy('theirs', 'them');
      final settings = SettingsService.forTesting(db);
      await settings.setSyncBinding(
        const SyncBinding(spaceId: 's', ownerUid: 'me', accountUid: 'me'),
      );
      SyncBindingService.forTesting(db, settings);
      await EventOccurrenceService.forTesting(db);
      await EventPresenceService.forTesting(db);
      await EventSkipService.forTesting(db);
      await EventAlertService.forTesting(db);
      final service = await CalendarEventService.forTesting(db);

      await service.tombstoneAll();

      expect(service.events.map((e) => e.id), ['theirs']);
      expect((await db.calendarEventDao.getAll()).map((e) => e.id), ['theirs']);
    });
  });
}
