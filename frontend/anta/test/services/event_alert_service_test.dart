// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real CRDT stamping and the real facade against
/// `NativeDatabase.memory()`, the way the skip and presence suites do.
///
/// What earns its place here over those two: `replaceForEvent` is the only
/// write path in the calendar that has to *diff* a set rather than toggle one
/// key, and the delete cascade is the one where a stranded row does not draw
/// wrong — it wakes the phone up for an event that no longer exists.
void main() {
  late AppDatabase db;
  late EventAlertService service;

  setUp(() async {
    EventAlertService.reset();
    CalendarEventService.reset();
    db = await openTestDatabase();
    service = await EventAlertService.forTesting(db);
  });

  tearDown(() async {
    EventAlertService.reset();
    CalendarEventService.reset();
    await db.close();
  });

  EventAlert alertOf(
    String id, {
    String eventId = 'e1',
    AlertMode mode = AlertMode.notify,
    int offsetMinutes = 10,
    int daysBefore = 0,
    int? dayMinute,
    String? sound,
    bool enabled = true,
  }) => EventAlert(
    id: id,
    eventId: eventId,
    mode: mode,
    offsetMinutes: offsetMinutes,
    daysBefore: daysBefore,
    dayMinute: dayMinute,
    sound: sound,
    enabled: enabled,
  );

  CalendarEvent eventOf(String id) => CalendarEvent(
    id: id,
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 14),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 18 * 60),
  );

  Future<List<EventAlertRow>> allRows() => db.select(db.eventAlerts).get();

  Future<EventAlertRow> rowFor(String id) {
    return (db.select(
      db.eventAlerts,
    )..where((a) => a.id.equals(id))).getSingle();
  }

  group('replaceForEvent', () {
    test('publishes to the facade', () async {
      await service.replaceForEvent('e1', [
        alertOf('a1'),
        alertOf('a2', mode: AlertMode.ring, offsetMinutes: 0),
      ]);

      expect(EventAlerts.alertsFor('e1'), hasLength(2));
      expect(EventAlerts.hasAlarm(eventOf('e1')), isTrue);
      expect(EventAlerts.hasReminder(eventOf('e1')), isTrue);
      expect(EventAlerts.alertsFor('e2'), isEmpty);
    });

    test(
      'a first save is a live version-1 row with stamped identity',
      () async {
        await service.replaceForEvent('e1', [alertOf('a1')]);

        final row = await rowFor('a1');
        expect(row.version, 1);
        expect(row.isDeleted, isFalse);
        expect(row.hlcTimestamp, isNotEmpty);
        expect(row.deviceId, 'test-device');
      },
    );

    test('a removed alert is tombstoned, not deleted', () async {
      await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);

      await service.replaceForEvent('e1', [alertOf('a1')]);

      expect(EventAlerts.alertsFor('e1').map((a) => a.id), ['a1']);
      final gone = await rowFor('a2');
      expect(gone.isDeleted, isTrue);
      expect(gone.deletedAt, isNotNull);
      expect(gone.version, 2);
      expect(await allRows(), hasLength(2));
    });

    test(
      'an alert the save never saw survives it, a dropped one does not',
      () async {
        // The two rows the editor opened on, and the ids it seeded from.
        await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);
        final seeded = {
          for (final alert in EventAlerts.alertsFor('e1')) alert.id,
        };
        // A pull adds a third while the form is open, and the app reloads.
        await service.replaceForEvent('e1', [
          alertOf('a1'),
          alertOf('a2'),
          alertOf('a3'),
        ]);
        await service.reload();

        // Save: the form's own set, bounded by what it was showing.
        await service.replaceForEvent('e1', [alertOf('a1')], knownIds: seeded);

        expect(EventAlerts.alertsFor('e1').map((a) => a.id), ['a1', 'a3']);
        expect((await rowFor('a3')).isDeleted, isFalse);
        expect(
          (await rowFor('a2')).isDeleted,
          isTrue,
          reason: 'an id the form was showing and dropped is still a removal',
        );
      },
    );

    test('a delete that landed under the open sheet is not resurrected',
        () async {
      // C150: `_sameContent` is false for a tombstone, so every id the caller
      // still lists fell into the update branch, which clears `is_deleted`
      // under a fresh stamp — a pull's delete, re-upserted live by a Save
      // that was only showing its mount-time snapshot, lost on every paired
      // device. `knownIds` makes it exact: the caller opened on `a2`.
      await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);
      final seeded = {for (final alert in EventAlerts.alertsFor('e1')) alert.id};
      // The pull: `a2` is tombstoned elsewhere and the app reloads.
      await service.replaceForEvent('e1', [alertOf('a1')]);
      await service.reload();
      final tombstone = await rowFor('a2');

      // Save: the form's own set, still carrying `a2`.
      await service.replaceForEvent('e1', [
        alertOf('a1'),
        alertOf('a2'),
      ], knownIds: seeded);

      final row = await rowFor('a2');
      expect(row.isDeleted, isTrue);
      expect(row.version, tombstone.version);
      expect(row.hlcTimestamp, tombstone.hlcTimestamp);
    });

    test('an empty list tombstones every alert of the event', () async {
      await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);

      await service.replaceForEvent('e1', const []);

      expect(EventAlerts.alertsFor('e1'), isEmpty);
      expect(EventAlerts.hasReminder(eventOf('e1')), isFalse);
      expect((await allRows()).every((r) => r.isDeleted), isTrue);
    });

    test('a kept alert bumps its version and keeps createdAt', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);
      final created = (await rowFor('a1')).createdAt;

      await service.replaceForEvent('e1', [
        alertOf('a1', mode: AlertMode.ring, offsetMinutes: 30),
      ]);

      final row = await rowFor('a1');
      expect(row.version, 2);
      expect(row.createdAt, created);
      expect(row.mode, 'ring');
      expect(row.offsetMinutes, 30);
    });

    test('an untouched alert is not re-stamped', () async {
      // The editor and the hub switch both hand over the whole set on every
      // save. A fresh HLC on an alert nobody edited would beat a genuine edit
      // made on another device once the two merge.
      await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);
      final before = await rowFor('a1');

      await service.replaceForEvent('e1', [
        alertOf('a1'),
        alertOf('a2', offsetMinutes: 30),
      ]);

      final kept = await rowFor('a1');
      expect(kept.version, 1);
      expect(kept.hlcTimestamp, before.hlcTimestamp);
      expect(kept.updatedAt, before.updatedAt);
      expect((await rowFor('a2')).version, 2);
    });

    test('re-adding a removed id resurrects its row', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);
      await service.replaceForEvent('e1', const []);

      await service.replaceForEvent('e1', [alertOf('a1')]);

      final row = await rowFor('a1');
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, isNull);
      expect(await allRows(), hasLength(1));
      expect(EventAlerts.alertsFor('e1'), hasLength(1));
    });

    test('another event is untouched by the diff', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);
      await service.replaceForEvent('e2', [alertOf('b1', eventId: 'e2')]);

      await service.replaceForEvent('e1', const []);

      expect(EventAlerts.alertsFor('e2'), hasLength(1));
      expect((await rowFor('b1')).isDeleted, isFalse);
    });

    test(
      'an alert carrying the wrong event id is re-homed, not stranded',
      () async {
        await service.replaceForEvent('e1', [alertOf('a1', eventId: 'other')]);

        expect(EventAlerts.alertsFor('e1').single.eventId, 'e1');
        expect((await rowFor('a1')).eventId, 'e1');
      },
    );
  });

  group('the facade', () {
    test('a disabled alert is kept but promises nothing', () async {
      await service.replaceForEvent('e1', [
        alertOf('a1', mode: AlertMode.ring, enabled: false),
      ]);

      expect(EventAlerts.alertsFor('e1'), hasLength(1));
      expect(
        EventAlerts.hasAlarm(eventOf('e1')),
        isFalse,
        reason: 'a disabled alert registers nothing, so it badges nothing',
      );
      expect((await rowFor('a1')).enabled, isFalse);
    });

    test('hands out an unmodifiable list', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);

      expect(
        () => EventAlerts.alertsFor('e1').add(alertOf('a2')),
        throwsUnsupportedError,
      );
    });

    test('the revision moves on every republish', () async {
      final before = EventAlerts.revision;
      await service.replaceForEvent('e1', [alertOf('a1')]);
      expect(EventAlerts.revision, greaterThan(before));
    });

    test('reset clears it so another database cannot badge wrongly', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);

      EventAlertService.reset();

      expect(EventAlerts.alertsFor('e1'), isEmpty);
      expect(EventAlerts.hasReminder(eventOf('e1')), isFalse);
    });

    test('a reload republishes what the table holds', () async {
      await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);
      EventAlerts.resetCache();

      await service.reload();

      expect(EventAlerts.alertsFor('e1'), hasLength(2));
    });
  });

  group('cascade on deleteById', () {
    late CalendarEventService events;

    setUp(() async {
      events = await CalendarEventService.forTesting(db);
    });

    Future<void> registerFor(String eventId, int osId) {
      return db.alertRegistrationDao.put(
        AlertRegistrationsCompanion(
          osId: Value(osId),
          alertId: const Value('a1'),
          eventId: Value(eventId),
          day: Value(DateTime.utc(2026, 9, 15).millisecondsSinceEpoch),
          fireAt: Value(DateTime(2026, 9, 15, 17, 50).millisecondsSinceEpoch),
          backend: const Value('alarm'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    test('deleting an event tombstones its alerts', () async {
      await events.upsert(eventOf('e1'));
      await service.replaceForEvent('e1', [alertOf('a1')]);

      await events.deleteById('e1');

      expect(EventAlerts.alertsFor('e1'), isEmpty);
      final row = await rowFor('a1');
      expect(row.isDeleted, isTrue);
      expect(row.version, 2);
    });

    test('and hard-deletes its registrations', () async {
      await events.upsert(eventOf('e1'));
      await service.replaceForEvent('e1', [alertOf('a1')]);
      await registerFor('e1', 101);
      await registerFor('e2', 202);

      await events.deleteById('e1');

      final left = await db.alertRegistrationDao.pending();
      expect(
        left.map((r) => r.osId),
        [202],
        reason:
            'a registration describes this phone\'s scheduler, so it is '
            'hard-deleted while the alert it came from tombstones',
      );
    });

    test('another event keeps its alerts', () async {
      await events.upsert(eventOf('e1'));
      await events.upsert(eventOf('e2'));
      await service.replaceForEvent('e1', [alertOf('a1')]);
      await service.replaceForEvent('e2', [alertOf('b1', eventId: 'e2')]);

      await events.deleteById('e1');

      expect(EventAlerts.alertsFor('e2'), hasLength(1));
    });
  });

  group('backup', () {
    test('export/import round-trips live alerts only', () async {
      await service.replaceForEvent('e1', [
        alertOf('a1', mode: AlertMode.ring, sound: 'chime'),
        alertOf('a2'),
      ]);
      await service.replaceForEvent('e1', [
        alertOf('a1', mode: AlertMode.ring, sound: 'chime'),
      ]);
      final exported = await service.exportData();

      expect(exported, hasLength(1));

      await service.clearAllForImport();
      expect(EventAlerts.alertsFor('e1'), isEmpty);
      await service.importData(exported);

      final restored = EventAlerts.alertsFor('e1').single;
      expect(restored.id, 'a1');
      expect(restored.mode, AlertMode.ring);
      expect(restored.sound, 'chime');
    });

    test('the export carries no CRDT identity', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);

      final exported = (await service.exportData()).single;

      expect(exported.keys, isNot(contains('hlcTimestamp')));
      expect(exported.keys, isNot(contains('deviceId')));
      expect(exported.keys, isNot(contains('version')));
      expect(exported.keys, isNot(contains('isDeleted')));
    });

    test(
      'import preserves audit timestamps but stamps fresh identity',
      () async {
        final created = DateTime.fromMillisecondsSinceEpoch(1600000000000);
        await service.importData([
          {
            EventAlertKeys.id: 'a1',
            EventAlertKeys.eventId: 'e1',
            EventAlertKeys.createdAtMs: created.millisecondsSinceEpoch,
            EventAlertKeys.updatedAtMs: created.millisecondsSinceEpoch,
          },
        ]);

        final row = await rowFor('a1');
        expect(
          row.createdAt.millisecondsSinceEpoch,
          created.millisecondsSinceEpoch,
        );
        expect(row.deviceId, 'test-device');
        expect(row.version, 1);
        expect(row.isDeleted, isFalse);
      },
    );

    test('a malformed row is skipped and the rest still imports', () async {
      await service.importData([
        'not a map',
        {EventAlertKeys.eventId: 'e1'},
        {EventAlertKeys.id: 'a2', EventAlertKeys.eventId: 'e1'},
      ]);

      expect(EventAlerts.alertsFor('e1').map((a) => a.id), ['a2']);
    });

    test('an import wipes what was there, tombstones included', () async {
      await service.replaceForEvent('e1', [alertOf('a1'), alertOf('a2')]);
      await service.replaceForEvent('e1', [alertOf('a1')]);

      await service.importData(const []);

      expect(await allRows(), isEmpty);
      expect(EventAlerts.alertsFor('e1'), isEmpty);
    });

    test(
      'clearAllForImport is the strand rule, and it empties the table',
      () async {
        await service.replaceForEvent('e1', [alertOf('a1')]);

        await service.clearAllForImport();

        // An alert left against an id the event import has just handed to a
        // different event does not draw a stale badge — it rings.
        expect(await allRows(), isEmpty);
        expect(EventAlerts.alertsFor('e1'), isEmpty);
      },
    );
  });

  group('removeAfterAlert on the event', () {
    late CalendarEventService events;

    setUp(() async {
      events = await CalendarEventService.forTesting(db);
    });

    test('round-trips through the DAO', () async {
      await events.upsert(eventOf('e1').copyWith(removeAfterAlert: true));
      await events.reload();

      expect(events.events.single.removeAfterAlert, isTrue);
    });

    test('defaults to false and rides the event backup key', () async {
      await events.upsert(eventOf('e1'));
      final exported = await events.exportData();

      expect(exported.single['removeAfterAlert'], isFalse);

      await events.importData([
        {...exported.single, 'removeAfterAlert': true},
      ]);
      expect(events.events.single.removeAfterAlert, isTrue);
    });

    test('an archive without the key imports as false', () async {
      await events.upsert(eventOf('e1'));
      final legacy = Map<String, dynamic>.of((await events.exportData()).single)
        ..remove('removeAfterAlert');

      await events.importData([legacy]);

      expect(events.events.single.removeAfterAlert, isFalse);
    });
  });

  group('categoryAlerts on the event (v42)', () {
    late CalendarEventService events;

    setUp(() async {
      events = await CalendarEventService.forTesting(db);
    });

    test('defaults to on; the opt-out round-trips the DAO', () async {
      await events.upsert(eventOf('e1'));
      await events.upsert(eventOf('e2').copyWith(categoryAlerts: false));
      await events.reload();

      final byId = {for (final e in events.events) e.id: e};
      expect(byId['e1']!.categoryAlerts, isTrue);
      expect(byId['e2']!.categoryAlerts, isFalse);
    });

    test('rides the event backup key, and its absence imports as on', () async {
      await events.upsert(eventOf('e1').copyWith(categoryAlerts: false));
      final exported = (await events.exportData()).single;
      expect(exported['categoryAlerts'], isFalse);

      await events.importData([exported]);
      expect(events.events.single.categoryAlerts, isFalse);

      await events.importData([
        Map<String, dynamic>.of(exported)..remove('categoryAlerts'),
      ]);
      expect(
        events.events.single.categoryAlerts,
        isTrue,
        reason: 'before v42 no category had an alert, so every event inherited',
      );
    });
  });

  group('category alerts (v42)', () {
    CategoryAlert categoryAlertOf(
      String id, {
      String categoryId = 'birthday',
      AlertMode mode = AlertMode.notify,
      int daysBefore = 1,
      bool enabled = true,
    }) => CategoryAlert(
      id: id,
      categoryId: categoryId,
      mode: mode,
      daysBefore: daysBefore,
      enabled: enabled,
    );

    Future<CategoryAlertRow> categoryRow(String id) {
      return (db.select(
        db.calendarCategoryAlerts,
      )..where((a) => a.id.equals(id))).getSingle();
    }

    test('replaceForCategory publishes and bumps the revision', () async {
      final before = EventAlerts.revision;

      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2', mode: AlertMode.ring),
      ]);

      expect(EventAlerts.revision, greaterThan(before));
      expect(service.categoryAlertsFor('birthday').map((a) => a.id), [
        'c1',
        'c2',
      ]);
      expect(EventAlerts.categoryAlertsFor('gym'), isEmpty);
    });

    test('a removed alert is tombstoned and a kept one upserted', () async {
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
      ]);

      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1', daysBefore: 7),
        categoryAlertOf('c3'),
      ]);

      expect(EventAlerts.categoryAlertsFor('birthday').map((a) => a.id), [
        'c1',
        'c3',
      ]);
      final gone = await categoryRow('c2');
      expect(gone.isDeleted, isTrue);
      expect(gone.deletedAt, isNotNull);
      expect(gone.version, 2);
      final kept = await categoryRow('c1');
      expect(kept.daysBefore, 7);
      expect(kept.version, 2);
      final added = await categoryRow('c3');
      expect(added.version, 1);
      expect(added.deviceId, 'test-device');
    });

    test('a category alert the save never saw survives it', () async {
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
      ]);
      final seeded = {
        for (final alert in EventAlerts.categoryAlertsFor('birthday')) alert.id,
      };
      // Another device's alert for the same category, applied under the open
      // sheet.
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
        categoryAlertOf('c3'),
      ]);
      await service.reload();

      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
      ], knownIds: seeded);

      expect(EventAlerts.categoryAlertsFor('birthday').map((a) => a.id), [
        'c1',
        'c3',
      ]);
      expect((await categoryRow('c3')).isDeleted, isFalse);
      expect((await categoryRow('c2')).isDeleted, isTrue);
    });

    test('a category delete under the open sheet is not resurrected',
        () async {
      // C150's category half: the same update branch, one table over.
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
      ]);
      final seeded = {
        for (final alert in EventAlerts.categoryAlertsFor('birthday')) alert.id,
      };
      await service.replaceForCategory('birthday', [categoryAlertOf('c1')]);
      await service.reload();
      final tombstone = await categoryRow('c2');

      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
      ], knownIds: seeded);

      final row = await categoryRow('c2');
      expect(row.isDeleted, isTrue);
      expect(row.version, tombstone.version);
      expect(row.hlcTimestamp, tombstone.hlcTimestamp);
    });

    test('an unchanged alert is not re-stamped', () async {
      await service.replaceForCategory('birthday', [categoryAlertOf('c1')]);
      final first = await categoryRow('c1');

      await service.replaceForCategory('birthday', [categoryAlertOf('c1')]);

      final second = await categoryRow('c1');
      expect(second.version, first.version);
      expect(second.hlcTimestamp, first.hlcTimestamp);
    });

    test('the tombstones and the upserts are one transaction', () async {
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
      ]);
      await service.replaceForCategory('gym', [
        categoryAlertOf('g1', categoryId: 'gym'),
      ]);

      // `g1` belongs to another category, so this set reads it as new and the
      // insert collides on the primary key — after `c2` was already
      // tombstoned in the same call.
      await expectLater(
        db.categoryAlertDao.replaceForCategory('birthday', [
          CalendarCategoryAlertsCompanion(id: const Value('c1')),
          CalendarCategoryAlertsCompanion(id: const Value('g1')),
        ]),
        throwsA(anything),
      );

      expect(
        (await categoryRow('c2')).isDeleted,
        isFalse,
        reason: 'a failed write must roll the whole set back',
      );
      expect((await categoryRow('g1')).categoryId, 'gym');
    });

    test('an alert handed in under another category is re-owned', () async {
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1', categoryId: 'gym'),
      ]);

      expect((await categoryRow('c1')).categoryId, 'birthday');
      expect(
        EventAlerts.categoryAlertsFor('birthday').single.categoryId,
        'birthday',
      );
    });

    test('tombstoneForCategory tombstones only that category', () async {
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1'),
        categoryAlertOf('c2'),
      ]);
      await service.replaceForCategory('gym', [
        categoryAlertOf('g1', categoryId: 'gym'),
      ]);
      final before = EventAlerts.revision;

      await service.tombstoneForCategory('birthday');

      expect(EventAlerts.revision, greaterThan(before));
      expect(EventAlerts.categoryAlertsFor('birthday'), isEmpty);
      expect(EventAlerts.categoryAlertsFor('gym'), hasLength(1));
      expect((await categoryRow('c1')).isDeleted, isTrue);
      expect((await categoryRow('c2')).version, 2);
      expect((await categoryRow('g1')).isDeleted, isFalse);

      await service.tombstoneForCategory('birthday');
      expect(
        (await categoryRow('c2')).version,
        2,
        reason: 'a repeat must not churn versions',
      );
    });

    test('getInstance loads both tables, and reset clears both', () async {
      await service.replaceForEvent('e1', [alertOf('a1')]);
      await service.replaceForCategory('birthday', [categoryAlertOf('c1')]);

      EventAlertService.reset();
      expect(EventAlerts.categoryAlertsFor('birthday'), isEmpty);
      expect(EventAlerts.alertsFor('e1'), isEmpty);

      await EventAlertService.forTesting(db);
      expect(EventAlerts.categoryAlertsFor('birthday').single.id, 'c1');
      expect(EventAlerts.alertsFor('e1').single.id, 'a1');
    });

    test('refreshAfterCategoryRemoval republishes a live instance', () async {
      await service.replaceForCategory('birthday', [categoryAlertOf('c1')]);
      await db.categoryAlertDao.tombstoneForCategory('birthday');

      await EventAlertService.refreshAfterCategoryRemoval();

      expect(EventAlerts.categoryAlertsFor('birthday'), isEmpty);
    });

    test('racing constructions share one instance', () async {
      EventAlertService.reset();

      final first = EventAlertService.forTesting(db);
      final second = EventAlertService.forTesting(db);

      expect(identical(await first, await second), isTrue);
    });

    test('refreshAfterCategoryRemoval waits for a loading instance', () async {
      await service.replaceForCategory('birthday', [categoryAlertOf('c1')]);
      EventAlertService.reset();
      expect(EventAlerts.categoryAlertsFor('birthday'), isEmpty);

      final loading = EventAlertService.forTesting(db);
      await EventAlertService.refreshAfterCategoryRemoval();

      expect(
        EventAlerts.categoryAlertsFor('birthday').map((a) => a.id),
        ['c1'],
        reason:
            'the refresh must not return before the instance it found '
            'still loading has published',
      );
      await loading;
    });

    test('replaceForEvent never stores a projected alert', () async {
      final projected = categoryAlertOf('c1').toEventAlert('e1');

      await expectLater(
        service.replaceForEvent('e1', [alertOf('a1'), projected]),
        throwsA(isA<AssertionError>()),
      );

      expect(await allRows(), isEmpty);
      expect(EventAlerts.alertsFor('e1'), isEmpty);
    });

    test('export and import round-trip without CRDT identity', () async {
      await service.replaceForCategory('birthday', [
        categoryAlertOf('c1', mode: AlertMode.ring, enabled: false),
      ]);
      final exported = await service.exportCategoryAlerts();
      expect(exported.single.keys, isNot(contains('hlcTimestamp')));
      expect(exported.single[EventAlertKeys.categoryId], 'birthday');

      await service.clearCategoryAlertsForImport();
      expect(EventAlerts.categoryAlertsFor('birthday'), isEmpty);
      expect(await db.select(db.calendarCategoryAlerts).get(), isEmpty);

      await service.importCategoryAlerts([
        ...exported,
        {'id': 'broken'},
        'not a map',
      ]);

      final restored = EventAlerts.categoryAlertsFor('birthday').single;
      expect(restored.id, 'c1');
      expect(restored.mode, AlertMode.ring);
      expect(restored.enabled, isFalse);
      expect((await categoryRow('c1')).version, 1);
    });
  });
}
