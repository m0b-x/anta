import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// Work budget for recurrence expansion, in the register of
/// `test/database/query_count_test.dart`: it counts calls, not milliseconds,
/// so it belongs in the default suite rather than behind the `benchmark` tag.
///
/// Painting a month is O(42 x N) today, with no rule-level pruning — a yearly
/// birthday is tested against all 42 visible days. The counts below are exact,
/// not ceilings, because both halves of that product are contracts: the first
/// case pins the O(42 x N) shape and the fact that a repeat lookup of the same
/// day is free, and the second pins the deliberate non-trigger that keeps
/// presence writes from dropping the day cache.
///
/// Only rules with no external input are seeded. `workdays` and
/// `holidaysOnly` consult `PublicHolidays`, whose static state is
/// process-wide, which would make a call count depend on test ordering.
///
/// `CalendarEventService` is a `getInstance()` singleton over `AppDatabase`
/// with no injection seam, so this drives the real stack over a throwaway
/// database rather than a fake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventCount = 200;

  late Directory tempDir;
  late CalendarBloc bloc;

  final month = [
    for (var i = 0; i < 42; i++)
      DateTime.utc(2026, 7, 27).add(Duration(days: i)),
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_occurs_on_budget');
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

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  RecurrenceRule ruleFor(int i) {
    switch (i % 5) {
      case 0:
        return const OneTimeRecurrence();
      case 1:
        return const DailyRecurrence();
      case 2:
        return const WeeklyRecurrence(weekdays: {DateTime.monday});
      case 3:
        return const MonthlyRecurrence();
      default:
        return const YearlyRecurrence();
    }
  }

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    for (var i = 0; i < eventCount; i++) {
      await service.upsert(
        CalendarEvent(
          id: 'e$i',
          title: 'Event $i',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          rule: ruleFor(i),
          tracksPresence: true,
        ),
      );
    }
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    expect((bloc.state as CalendarPageLoaded).allEvents, hasLength(eventCount));
  });

  tearDown(() async {
    await bloc.close();
  });

  test('a cold month costs one occursOn per event per visible day', () async {
    CalendarEvent.debugOccursOnCalls = 0;

    for (final day in month) {
      bloc.eventsForDay(day);
    }

    expect(CalendarEvent.debugOccursOnCalls, 42 * eventCount);
  });

  test('a second lookup of the same day is free', () async {
    for (final day in month) {
      bloc.eventsForDay(day);
    }

    CalendarEvent.debugOccursOnCalls = 0;

    // Each cell hits the cache twice per paint — `eventLoader` and the cell
    // builder — so the second pass over the same 42 days must cost nothing.
    for (final day in month) {
      bloc.eventsForDay(day);
    }

    expect(CalendarEvent.debugOccursOnCalls, 0);
  });

  test('marking an occurrence missed does not re-expand the month', () async {
    for (final day in month) {
      bloc.eventsForDay(day);
    }

    await dispatch(SetOccurrenceMissed(eventId: 'e1', day: month.first));

    CalendarEvent.debugOccursOnCalls = 0;

    for (final day in month) {
      bloc.eventsForDay(day);
    }

    expect(CalendarEvent.debugOccursOnCalls, 0);
  });

  test('cancelling an occurrence does re-expand the month', () async {
    for (final day in month) {
      bloc.eventsForDay(day);
    }

    await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: month.first));

    CalendarEvent.debugOccursOnCalls = 0;

    for (final day in month) {
      bloc.eventsForDay(day);
    }

    expect(CalendarEvent.debugOccursOnCalls, 42 * eventCount);
  });
}
