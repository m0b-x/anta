import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

import '../database/support/db_test_support.dart';

/// `eventsForDay` reads `state` and memoizes into `_dayCache`, so a grid
/// rebuild that lands between a handler's cache invalidation and its emit
/// re-warms the cache from the list *without* the written event, and the
/// emit then serves stale days — seen on device on 2026-09-25, where a
/// freshly saved event reached the agenda but not the grid or the day panel.
/// The invalidation must therefore sit in the same synchronous turn as the
/// emit, after the last await. These tests play the rebuild: they read the
/// day at every microtask hop while the handler runs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CalendarEventService service;
  late CalendarBloc bloc;

  final day = DateTime.utc(2026, 8, 1);

  CalendarEvent event(String title) => CalendarEvent(
    id: 'e1',
    title: title,
    categoryId: 'gym',
    startDate: day,
    rule: const OneTimeRecurrence(),
  );

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  /// Dispatches [event] and reads [day] through the cache at every
  /// microtask hop, yielding to timers now and then, until the bloc emits.
  Future<void> dispatchWhileReading(CalendarPageEvent event) async {
    final before = bloc.state;
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    var rounds = 0;
    while (identical(bloc.state, before) && rounds < 200) {
      for (var i = 0; i < 50 && identical(bloc.state, before); i++) {
        bloc.eventsForDay(day);
        await null;
      }
      await Future<void>.delayed(Duration.zero);
      rounds++;
    }
    await next;
  }

  setUp(() async {
    CalendarEventService.reset();
    db = await openTestDatabase();
    service = await CalendarEventService.forTesting(db);
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    await db.close();
  });

  test('a day read during the create never leaves that day stale', () async {
    expect(bloc.eventsForDay(day), isEmpty);

    await dispatchWhileReading(CreateCalendarEvent(event: event('Physio')));

    expect(bloc.eventsForDay(day).map((e) => e.id), ['e1']);
  });

  test('a day read during a reload never leaves that day stale', () async {
    await dispatch(CreateCalendarEvent(event: event('Physio')));
    expect(bloc.eventsForDay(day).map((e) => e.id), ['e1']);

    // Written behind the service's cache, the way a restore or a category
    // delete lands, so only the reload can surface it.
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'e2',
        title: 'Stretch',
        category: 'gym',
        startDate: day,
        ruleKind: 'oneTime',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await dispatchWhileReading(const LoadCalendarEvents());

    expect(bloc.eventsForDay(day).map((e) => e.id), containsAll(['e1', 'e2']));
  });

  test('a day read during the update never leaves that day stale', () async {
    await dispatch(CreateCalendarEvent(event: event('Physio')));
    expect(bloc.eventsForDay(day).single.title, 'Physio');

    await dispatchWhileReading(UpdateCalendarEvent(event: event('Physio 2')));

    expect(bloc.eventsForDay(day).single.title, 'Physio 2');
  });
}
