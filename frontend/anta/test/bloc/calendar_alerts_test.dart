import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/alert_skip_action.dart';
import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_skip_service.dart';

import '../database/support/db_test_support.dart';

/// Every handler that changes what the phone should do about an event has to
/// say so **exactly once**, with the right id.
///
/// Once, because reconcile is a full pass over the horizon and a second call
/// is pure cost; with the right id, because the delete handler's event is gone
/// by the time it runs and the skip handlers never hold an event at all — the
/// three places the id is easiest to get wrong.
///
/// The bloc takes the reconciler as a seam, so none of this needs a scheduler,
/// a gateway or a registry: the bloc's entire responsibility is knowing *that*
/// alerts must be reconciled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late CalendarBloc bloc;
  late List<({String eventId, AlertReconcileReason reason})> calls;
  late List<({String eventId, List<EventAlert> alerts})> writes;

  /// Both seams appending to one list, so "the rows are written **before** the
  /// platform is asked to plan from them" is a property the suite can state
  /// rather than one the reader has to trust.
  late List<String> order;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_alerts');
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

  setUp(() async {
    CalendarEventService.reset();
    EventSkipService.reset();
    db = await openTestDatabase();
    await EventSkipService.forTesting(db);
    calls = [];
    writes = [];
    order = [];
    bloc = CalendarBloc(
      service: CalendarEventService.forTesting(db),
      alertReconciler: (eventId, reason) async {
        calls.add((eventId: eventId, reason: reason));
        order.add('reconcile');
      },
      alertWriter: (eventId, alerts) async {
        writes.add((eventId: eventId, alerts: alerts));
        order.add('write');
      },
    );
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    EventSkipService.reset();
    await db.close();
  });

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  CalendarEvent eventOf({
    String id = 'e1',
    String title = 'Leg day',
    RecurrenceRule rule = const OneTimeRecurrence(),
  }) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 20),
    rule: rule,
    time: const EventTime(startMinute: 18 * 60),
  );

  group("an upcoming notice's Skip (OS-3)", () {
    tearDown(EventAlerts.resetCache);

    AlertPayload payloadFor(CalendarEvent event, DateTime day) => AlertPayload(
      database: 'gym_notes',
      eventId: event.id,
      alertId: 'a1',
      dayUtcMs: day.millisecondsSinceEpoch,
      osId: 7,
      mode: AlertMode.ring,
      title: event.title,
      timeLabel: '18:00',
      categoryId: 'gym',
    );

    test('cancels one occurrence of a recurring event, and Undo restores it',
        () async {
      await dispatch(const LoadCalendarEvents());
      final event = eventOf(rule: const DailyRecurrence());
      await dispatch(CreateCalendarEvent(event: event));
      calls.clear();
      final day = DateTime.utc(2026, 9, 22);
      final action = AlertSkipAction.resolve(
        event: event,
        payload: payloadFor(event, day),
        today: DateTime.utc(2026, 9, 22),
      )!;
      expect(action.apply, isA<SetOccurrenceSkipped>());

      await dispatch(action.apply);

      expect(EventSkips.isSkipped(event.id, day), isTrue);
      expect(EventSkips.isSkipped(event.id, DateTime.utc(2026, 9, 23)), isFalse);
      // Exactly one reconcile, for this event: that is what takes the
      // alarm off the platform.
      expect(calls, hasLength(1));
      expect(calls.single.eventId, event.id);
      expect(writes, isEmpty);

      await dispatch(action.undo);
      expect(EventSkips.isSkipped(event.id, day), isFalse);
      expect(calls, hasLength(2));
    });

    test('switches a one-time event\'s alert off, and Undo switches it on',
        () async {
      await dispatch(const LoadCalendarEvents());
      final event = eventOf();
      final alert = EventAlert(id: 'a1', eventId: event.id, mode: AlertMode.ring);
      await dispatch(CreateCalendarEvent(event: event, alerts: [alert]));
      EventAlerts.updateCache(byEvent: {event.id: [alert]});
      calls.clear();
      writes.clear();
      final action = AlertSkipAction.resolve(
        event: event,
        payload: payloadFor(event, DateTime.utc(2026, 9, 20)),
        today: DateTime.utc(2026, 9, 19),
      )!;
      expect(action.apply, isA<ToggleEventAlert>());

      await dispatch(action.apply);

      expect(writes, hasLength(1));
      expect(writes.single.alerts.single.enabled, isFalse);
      expect(calls, hasLength(1));
      // A one-time event cannot be skipped — a cancelled occurrence of one
      // would be a deletion — so nothing reached the skip table.
      expect(EventSkips.isSkipped(event.id, DateTime.utc(2026, 9, 20)), isFalse);

      EventAlerts.updateCache(
        byEvent: {event.id: [alert.copyWith(enabled: false)]},
      );
      await dispatch(action.undo);
      expect(writes, hasLength(2));
      expect(writes.last.alerts.single.enabled, isTrue);
    });

    test('resolves to nothing for a day already gone', () {
      // A notice that outlived its alarm (review): its Skip must not cancel
      // an occurrence that already happened.
      final event = eventOf(rule: const DailyRecurrence());
      expect(
        AlertSkipAction.resolve(
          event: event,
          payload: payloadFor(event, DateTime.utc(2026, 9, 21)),
          today: DateTime.utc(2026, 9, 22),
        ),
        isNull,
      );
    });

    test("resolves to nothing when a one-time event's alert is gone or off",
        () {
      final event = eventOf();
      final alert = EventAlert(id: 'a1', eventId: event.id, mode: AlertMode.ring);
      final payload = payloadFor(event, DateTime.utc(2026, 9, 20));
      final today = DateTime.utc(2026, 9, 19);

      EventAlerts.updateCache(byEvent: const {});
      expect(
        AlertSkipAction.resolve(event: event, payload: payload, today: today),
        isNull,
      );
      EventAlerts.updateCache(
        byEvent: {event.id: [alert.copyWith(enabled: false)]},
      );
      expect(
        AlertSkipAction.resolve(event: event, payload: payload, today: today),
        isNull,
      );
      EventAlerts.updateCache(byEvent: {event.id: [alert]});
      expect(
        AlertSkipAction.resolve(event: event, payload: payload, today: today),
        isNotNull,
      );
    });
  });

  test('creating an event reconciles it once', () async {
    await dispatch(const LoadCalendarEvents());
    calls.clear();

    await dispatch(CreateCalendarEvent(event: eventOf()));

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
    expect(calls.single.reason, AlertReconcileReason.eventChanged);
  });

  test('updating an event reconciles it once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    calls.clear();

    await dispatch(
      UpdateCalendarEvent(event: eventOf(title: 'Leg day, later')),
    );

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
  });

  test('deleting an event reconciles it once, by id', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    calls.clear();

    await dispatch(const DeleteCalendarEvent(eventId: 'e1'));

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
  });

  test('deleting an event the bloc does not hold reconciles nothing', () async {
    await dispatch(const LoadCalendarEvents());
    calls.clear();

    bloc.add(const DeleteCalendarEvent(eventId: 'ghost'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls, isEmpty);
  });

  test('skipping an occurrence reconciles the event once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: eventOf(rule: const WeeklyRecurrence(weekdays: {1, 3, 5})),
      ),
    );
    calls.clear();

    await dispatch(
      SetOccurrenceSkipped(eventId: 'e1', day: DateTime.utc(2026, 9, 21)),
    );

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
    expect(calls.single.reason, AlertReconcileReason.occurrenceChanged);
  });

  test('unskipping an occurrence reconciles the event once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: eventOf(rule: const WeeklyRecurrence(weekdays: {1, 3, 5})),
      ),
    );
    await dispatch(
      SetOccurrenceSkipped(eventId: 'e1', day: DateTime.utc(2026, 9, 21)),
    );
    calls.clear();

    await dispatch(
      ClearOccurrenceSkipped(eventId: 'e1', day: DateTime.utc(2026, 9, 21)),
    );

    expect(calls, hasLength(1));
    expect(calls.single.eventId, 'e1');
  });

  test('handlers that change nothing the phone owes never reconcile', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    calls.clear();

    // A day tap, a month page and a description edit are all rendering: the
    // plan is untouched, so the platform must not be asked to do anything.
    await dispatch(
      SelectCalendarDay(
        day: DateTime.utc(2026, 9, 21),
        focusedDay: DateTime.utc(2026, 9, 21),
        source: CalendarSelectionSource.grid,
      ),
    );
    await dispatch(
      SetOccurrenceDescription(
        eventId: 'e1',
        day: DateTime.utc(2026, 9, 20),
        description: 'squats',
      ),
    );

    expect(calls, isEmpty);
  });

  const alert = EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 10);

  test('an edited alert list reaches the writer exactly once', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: eventOf()));
    writes.clear();
    order.clear();

    await dispatch(
      UpdateCalendarEvent(
        event: eventOf(title: 'Leg day, later'),
        alerts: const [alert],
      ),
    );

    expect(writes, hasLength(1));
    expect(writes.single.eventId, 'e1');
    expect(writes.single.alerts, const [alert]);
  });

  test('a new event writes its alerts before the platform is asked', () async {
    await dispatch(const LoadCalendarEvents());
    order.clear();

    await dispatch(
      CreateCalendarEvent(event: eventOf(), alerts: const [alert]),
    );

    // The reconcile plans from the rows, so a pass that overtook the write
    // would arm the previous set and only correct itself at the next launch.
    expect(order, ['write', 'reconcile']);
  });

  test('an empty list is a removal, and null is silence', () async {
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(event: eventOf(), alerts: const [alert]),
    );
    writes.clear();

    await dispatch(
      UpdateCalendarEvent(event: eventOf(title: 'Leg day, later')),
    );
    expect(writes, isEmpty, reason: 'null means the caller never showed them');

    await dispatch(
      UpdateCalendarEvent(event: eventOf(), alerts: const []),
    );
    expect(writes, hasLength(1));
    expect(writes.single.alerts, isEmpty);
  });

  test('a write that throws still lets the event save', () async {
    await bloc.close();
    bloc = CalendarBloc(
      service: CalendarEventService.forTesting(db),
      alertReconciler: (eventId, reason) async {
        calls.add((eventId: eventId, reason: reason));
      },
      alertWriter: (eventId, alerts) async => throw StateError('no database'),
    );
    await dispatch(const LoadCalendarEvents());
    calls.clear();

    await dispatch(
      CreateCalendarEvent(event: eventOf(), alerts: const [alert]),
    );

    final state = bloc.state as CalendarPageLoaded;
    expect(state.allEvents.map((e) => e.id), contains('e1'));
    expect(calls, hasLength(1));
  });

  group('ToggleEventAlert', () {
    const reminder = EventAlert(
      id: 'a1',
      eventId: 'e1',
      mode: AlertMode.notify,
      offsetMinutes: 10,
    );
    const alarm = EventAlert(id: 'a2', eventId: 'e1', mode: AlertMode.ring);

    Future<void> seed() async {
      await dispatch(const LoadCalendarEvents());
      await dispatch(CreateCalendarEvent(event: eventOf()));
      EventAlerts.updateCache(
        byEvent: {
          'e1': List.unmodifiable(const [reminder, alarm]),
        },
      );
      calls.clear();
      writes.clear();
      order.clear();
    }

    tearDown(EventAlerts.resetCache);

    test('writes the whole set with one alert flipped, then reconciles once',
        () async {
      await seed();
      final before = (bloc.state as CalendarPageLoaded).occurrenceRevision;

      await dispatch(
        const ToggleEventAlert(eventId: 'e1', alertId: 'a2', enabled: false),
      );

      expect(writes, hasLength(1));
      expect(writes.single.eventId, 'e1');
      expect(writes.single.alerts, [reminder, alarm.copyWith(enabled: false)]);
      expect(calls, hasLength(1));
      expect(calls.single.eventId, 'e1');
      expect(order, ['write', 'reconcile']);
      expect(
        (bloc.state as CalendarPageLoaded).occurrenceRevision,
        before + 1,
        reason: 'the row badges re-render on this revision',
      );
    });

    test('setting the value an alert already has does nothing', () async {
      await seed();

      bloc.add(
        const ToggleEventAlert(eventId: 'e1', alertId: 'a2', enabled: true),
      );
      bloc.add(
        const ToggleEventAlert(eventId: 'e1', alertId: 'gone', enabled: false),
      );
      await pumpEventQueue();

      expect(writes, isEmpty);
      expect(calls, isEmpty);
    });
  });
}

