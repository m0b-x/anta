import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
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
}
