import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/alert_skip_action.dart';
import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/database/daos/shared_row_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

/// Nothing answers "saved" for a partner's event (share surfaces §6.10).
///
/// The database fences turn every write of a partner's row into nothing,
/// silently; what this suite pins is the layer above them — that no handler
/// emits, publishes or reconciles as if the write had landed, so a screen has
/// nothing to show a change with and nothing to offer an Undo for. Each
/// write is tried on the partner's event and, as the pin, on my own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late CalendarEventService service;
  late CalendarBloc bloc;
  late List<String> reconciled;
  late List<String> alertWrites;
  late List<CalendarPageState> emitted;

  final cancelled = DateTime.utc(2026, 9, 22);
  final texted = DateTime.utc(2026, 9, 23);
  final open = DateTime.utc(2026, 9, 24);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_partner_writes');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  CalendarEvent eventOf(String id) => CalendarEvent(
    id: id,
    title: 'Night shift',
    categoryId: 'work',
    startDate: DateTime.utc(2026, 9, 20),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 22 * 60),
    perOccurrenceDescriptions: true,
  );

  /// Both events with a cancelled day and a day's text each, then
  /// `theirs` handed to the partner as the shared reader would hold it.
  Future<void> seed() async {
    final skips = await EventSkipService.forTesting(db);
    final texts = await EventOccurrenceService.forTesting(db);
    for (final id in ['theirs', 'mine']) {
      await service.upsert(eventOf(id));
      await skips.markSkipped(id, cancelled);
      await texts.setDescription(id, texted, 'Bring keys');
    }
    await db.customStatement(
      "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
    );
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
    await service.reload();
  }

  setUp(() async {
    CalendarEventService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    db = await openTestDatabase();
    service = await CalendarEventService.forTesting(db);
    await seed();
    reconciled = [];
    alertWrites = [];
    emitted = [];
    bloc = CalendarBloc(
      service: service,
      alertReconciler: (eventId, reason) async => reconciled.add(eventId),
      alertWriter: (eventId, alerts, {knownIds}) async =>
          alertWrites.add(eventId),
      allAlertsReconciler: (reason) async {},
    );
    final loaded = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(const LoadCalendarEvents());
    await loaded;
    bloc.stream.listen(emitted.add);
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    await db.close();
  });

  CalendarEvent stored(String id) =>
      service.events.firstWhere((event) => event.id == id);

  /// Dispatches [event] and lets every handler run to its end. Nothing on
  /// a refused path waits on the database, so the queue drains it.
  Future<void> settle(CalendarPageEvent event) async {
    bloc.add(event);
    await pumpEventQueue(times: 100);
  }

  /// Dispatches [event] and waits for the state it emits.
  Future<void> landed(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  /// The quiet every refused write ends in: no state, no pass, no alerts.
  void expectNothingSaid() {
    expect(emitted, isEmpty, reason: 'no state may pretend');
    expect(reconciled, isEmpty);
    expect(alertWrites, isEmpty);
  }

  test('the load holds the partner\'s event as theirs, mine as mine', () {
    expect(stored('theirs').fromPartner, isTrue);
    expect(stored('mine').fromPartner, isFalse);
    final loaded = bloc.state as CalendarPageLoaded;
    expect(
      loaded.allEvents.firstWhere((e) => e.id == 'theirs').fromPartner,
      isTrue,
    );
    expect(loaded.holdsPartnerEvents, isTrue);
  });

  test('the state says whether it holds a partner\'s event, list by '
      'list', () async {
    // The share ends: the row is mine again, as a pull would leave it.
    await db.sharedRowDao.writing(
      () => db.customStatement(
        "UPDATE calendar_events SET owner_id = NULL WHERE id = 'theirs'",
      ),
    );
    await db.syncDao.deleteValue(SyncDao.keySharedOwner);
    await service.reload();
    await landed(const RefreshCalendarView());

    expect((bloc.state as CalendarPageLoaded).holdsPartnerEvents, isFalse);
  });

  group("on a partner's event every write does nothing and says nothing", () {
    test('an edit — a rename, a moved date, an added date', () async {
      final theirs = stored('theirs');
      for (final edited in [
        theirs.copyWith(title: 'Renamed'),
        theirs.copyWith(startDate: DateTime.utc(2026, 9, 25)),
        theirs.withExplicitDates({
          DateTime.utc(2026, 9, 20),
          DateTime.utc(2026, 9, 27),
        }),
      ]) {
        await settle(
          UpdateCalendarEvent(event: edited, alerts: const <EventAlert>[]),
        );
      }

      expectNothingSaid();
      expect(stored('theirs'), theirs);
      final row = await db.calendarEventDao.getByIdsIncludingDeleted([
        'theirs',
      ]);
      expect(row.single.title, 'Night shift');
    });

    test('a delete', () async {
      await settle(const DeleteCalendarEvent(eventId: 'theirs'));

      expectNothingSaid();
      expect(service.events.map((e) => e.id), contains('theirs'));
      expect(EventSkips.isSkipped('theirs', cancelled), isTrue);
      expect(OccurrenceDescriptions.overrideFor('theirs', texted), isNotNull);
    });

    test("skip this day — a one-off's cancel is the same write", () async {
      await settle(SetOccurrenceSkipped(eventId: 'theirs', day: open));

      expectNothingSaid();
      expect(EventSkips.isSkipped('theirs', open), isFalse);
    });

    test('restoring a cancelled day', () async {
      await settle(ClearOccurrenceSkipped(eventId: 'theirs', day: cancelled));

      expectNothingSaid();
      expect(EventSkips.isSkipped('theirs', cancelled), isTrue);
    });

    test("the editor's cancelled-days set", () async {
      await settle(const SetOccurrenceSkips(eventId: 'theirs', days: {}));

      expectNothingSaid();
      expect(EventSkips.isSkipped('theirs', cancelled), isTrue);
    });

    test("a day's text, a checkbox tick included", () async {
      await settle(
        SetOccurrenceDescription(
          eventId: 'theirs',
          day: texted,
          description: '- [x] Bring keys',
        ),
      );
      await settle(
        SetOccurrenceDescription(
          eventId: 'theirs',
          day: open,
          description: 'A day of mine',
        ),
      );

      expectNothingSaid();
      expect(
        OccurrenceDescriptions.overrideFor('theirs', texted),
        'Bring keys',
      );
      expect(OccurrenceDescriptions.overrideFor('theirs', open), isNull);
    });

    test("a day's text reset to the template", () async {
      await settle(ClearOccurrenceDescription(eventId: 'theirs', day: texted));

      expectNothingSaid();
      expect(
        OccurrenceDescriptions.overrideFor('theirs', texted),
        'Bring keys',
      );
    });

    test('"remove after it rings" switched by an edit', () async {
      await settle(
        UpdateCalendarEvent(
          event: stored('theirs').copyWith(removeAfterAlert: true),
        ),
      );

      expectNothingSaid();
      expect(stored('theirs').removeAfterAlert, isFalse);
    });
  });

  // The read sheet of a partner's event writes my alerts on it at once
  // (§6.9): an alert row of my own, never the event.
  test(
    "my alerts on a partner's event are written, the event is not",
    () async {
      final theirs = stored('theirs');
      Future<int> rowVersion() async =>
          (await db.calendarEventDao.getByIdsIncludingDeleted([
            'theirs',
          ])).single.version;
      final version = await rowVersion();
      const alert = EventAlert(id: 'a1', eventId: 'theirs', offsetMinutes: 60);

      await landed(
        const SetEventAlerts(
          eventId: 'theirs',
          alerts: [alert],
          knownIds: <String>{},
        ),
      );

      expect(alertWrites, ['theirs']);
      expect(reconciled, ['theirs']);
      expect(stored('theirs'), theirs);
      expect(await rowVersion(), version);
    },
  );

  test('my alerts on one event land in the order they were sent', () async {
    // The editor's replace: the set upserted, the shown ids it no longer
    // holds removed. The first write is the slower one, so handlers that
    // overlapped would let it land last and bring `a2` back.
    final stored = <String, EventAlert>{
      for (final id in ['a1', 'a2'])
        id: EventAlert(id: id, eventId: 'theirs', offsetMinutes: 60),
    };
    var calls = 0;
    final ordered = CalendarBloc(
      service: service,
      alertReconciler: (eventId, reason) async {},
      alertWriter: (eventId, alerts, {knownIds}) async {
        final delay = calls++ == 0 ? 50 : 0;
        await Future<void>.delayed(Duration(milliseconds: delay));
        for (final alert in alerts) {
          stored[alert.id] = alert;
        }
        for (final id in knownIds ?? const <String>{}) {
          if (!alerts.any((alert) => alert.id == id)) stored.remove(id);
        }
      },
      allAlertsReconciler: (reason) async {},
    );
    addTearDown(ordered.close);
    final loaded = ordered.stream.first.timeout(const Duration(seconds: 30));
    ordered.add(const LoadCalendarEvents());
    await loaded;

    ordered
      ..add(
        SetEventAlerts(
          eventId: 'theirs',
          alerts: [stored['a2']!],
          knownIds: const {'a1', 'a2'},
        ),
      )
      ..add(
        const SetEventAlerts(
          eventId: 'theirs',
          alerts: [],
          knownIds: {'a2'},
        ),
      );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(calls, 2);
    expect(stored, isEmpty);
  });

  // Copy to my calendar is a create of my own (§6.9), handled as one.
  group("a copy of a partner's event", () {
    tearDown(EventAlerts.resetCache);

    Future<CalendarEvent?> copy() async {
      final done = Completer<CalendarEvent?>();
      bloc.add(CopySharedEvent(event: stored('theirs'), day: open, done: done));
      return done.future.timeout(const Duration(seconds: 30));
    }

    test('is held by the bloc when it is answered, and its inherited alert '
        'is armed', () async {
      final made = (await copy())!;
      // The category the copy landed in — `other` when this database has no
      // `work` of its own — with an alert of its own.
      EventAlerts.updateCategoryCache(
        byCategory: {
          made.categoryId: List.unmodifiable([
            CategoryAlert(
              id: 'c1',
              categoryId: made.categoryId,
              offsetMinutes: 30,
            ),
          ]),
        },
      );

      expect(made.fromPartner, isFalse);
      final held = (bloc.state as CalendarPageLoaded).allEvents;
      expect(held.map((event) => event.id), contains(made.id));
      expect(
        EventAlerts.inheritedFor(made, own: const []),
        isNotEmpty,
        reason: 'the copy inherits its category alert',
      );
      expect(reconciled, [made.id], reason: 'and the pass arms it');
      expect(stored('theirs').fromPartner, isTrue);
    });

    test('before the calendar has loaded it answers null and copies '
        'nothing', () async {
      final theirs = stored('theirs');
      await bloc.close();
      bloc = CalendarBloc(
        service: service,
        alertReconciler: (eventId, reason) async => reconciled.add(eventId),
      );

      final done = Completer<CalendarEvent?>();
      bloc.add(CopySharedEvent(event: theirs, day: open, done: done));

      expect(await done.future, isNull);
      expect(service.events, hasLength(2));
      expect(reconciled, isEmpty);
    });
  });

  group('my own event writes exactly as before', () {
    test('an edit lands, emits and reconciles', () async {
      await landed(
        UpdateCalendarEvent(event: stored('mine').copyWith(title: 'Renamed')),
      );

      expect(stored('mine').title, 'Renamed');
      expect(reconciled, ['mine']);
    });

    test('skip this day and its restore land', () async {
      await landed(SetOccurrenceSkipped(eventId: 'mine', day: open));
      expect(EventSkips.isSkipped('mine', open), isTrue);

      await landed(ClearOccurrenceSkipped(eventId: 'mine', day: cancelled));
      expect(EventSkips.isSkipped('mine', cancelled), isFalse);
    });

    test("a day's text lands, and its reset", () async {
      await landed(
        SetOccurrenceDescription(eventId: 'mine', day: open, description: 'x'),
      );
      expect(OccurrenceDescriptions.overrideFor('mine', open), 'x');

      await landed(ClearOccurrenceDescription(eventId: 'mine', day: open));
      expect(OccurrenceDescriptions.overrideFor('mine', open), isNull);
    });

    test('a delete lands', () async {
      await landed(const DeleteCalendarEvent(eventId: 'mine'));

      expect(service.events.map((e) => e.id), ['theirs']);
    });
  });

  group('the service refuses on its own, for the callers past the bloc', () {
    test('a save, a delete and a restore throw before anything is '
        'cached', () async {
      final theirs = stored('theirs');
      final before = service.events;

      await expectLater(
        service.upsert(theirs.copyWith(title: 'Renamed')),
        throwsA(isA<SharedRowException>()),
      );
      await expectLater(
        service.deleteById('theirs'),
        throwsA(isA<SharedRowException>()),
      );
      await expectLater(
        service.restoreCascade(
          theirs,
          marks: const {},
          descriptions: const {},
          skips: const {},
          alerts: const [],
        ),
        throwsA(isA<SharedRowException>()),
      );
      expect(service.events, same(before));
      expect(EventSkips.isSkipped('theirs', cancelled), isTrue);
    });

    test("a model that says it is the partner's is refused under any "
        'id', () async {
      await expectLater(
        service.upsert(stored('theirs').copyWith(id: 'fresh')),
        throwsA(isA<SharedRowException>()),
      );
      expect(service.events.map((e) => e.id), isNot(contains('fresh')));
    });
  });

  group("an upcoming notice's Skip (D21)", () {
    tearDown(EventAlerts.resetCache);

    AlertPayload noticeOf(String eventId) => AlertPayload(
      database: 'gym_notes',
      eventId: eventId,
      alertId: '$eventId-a',
      dayUtcMs: open.millisecondsSinceEpoch,
      osId: 7,
      mode: AlertMode.ring,
      title: 'Night shift',
      timeLabel: '22:00',
      categoryId: 'work',
      notice: true,
    );

    test('resolves to nothing on a partner\'s event, series or one-off, my '
        'own alert on it included', () {
      final series = stored('theirs');
      final oneOff = series.copyWith(rule: const OneTimeRecurrence());
      EventAlerts.updateCache(
        byEvent: {
          'theirs': [
            const EventAlert(
              id: 'theirs-a',
              eventId: 'theirs',
              mode: AlertMode.ring,
            ),
          ],
        },
      );

      for (final event in [series, oneOff]) {
        expect(
          AlertSkipAction.resolve(
            event: event,
            payload: noticeOf('theirs'),
            today: open,
          ),
          isNull,
        );
      }
    });

    test('still cancels the day of my own event', () {
      EventAlerts.updateCache(
        byEvent: {
          'mine': [
            const EventAlert(
              id: 'mine-a',
              eventId: 'mine',
              mode: AlertMode.ring,
            ),
          ],
        },
      );

      final action = AlertSkipAction.resolve(
        event: stored('mine'),
        payload: noticeOf('mine'),
        today: open,
      );

      expect(action?.apply, SetOccurrenceSkipped(eventId: 'mine', day: open));
    });
  });
}
