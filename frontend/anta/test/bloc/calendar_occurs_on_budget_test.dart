import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/utils/event_agenda.dart';

/// Work budget for recurrence expansion, in the register of
/// `test/database/query_count_test.dart`: it counts calls, not milliseconds,
/// so it belongs in the default suite rather than behind the `benchmark` tag.
///
/// Painting a month costs one `occursOn` per (event, day) pair the window
/// partition could not prune away. `CalendarBloc` shares
/// `EventAgenda.partitionForWindow` with the agenda scan, and that split has
/// three buckets:
///
///   * **one-time** (3.2a) — bucketed by their single occurrence day, so they
///     never enter the per-day scan at all;
///   * **sparse** (3.2b) — the rule named its candidate days through
///     `RecurrenceRule.candidateDaysIn`, so the event is only validated on
///     those. A weekly Monday event costs one call per Monday, not 42;
///   * **dense** (3.2b) — the rule returned `null` because it cannot usefully
///     prune itself. `DailyRecurrence(interval: 1)` fires every day, so it
///     stays on exactly the pre-3.2b full scan: 42 calls per visible month.
///
/// The counts are exact, not ceilings, because every term is a contract: the
/// first case pins the dense/sparse split and the fact that a repeat lookup of
/// the same day is free, and the second pins the deliberate non-trigger that
/// keeps presence writes from dropping the day cache.
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
    // Pin the focus inside the painted window. `_dayCandidates` prunes only
    // days inside the focused month +/- 3 months, so leaving focus wherever
    // `DateTime.now()` put it would make every count below depend on the date
    // the suite runs: outside roughly June-October 2026 the painted days fall
    // out of that window and back onto the unpruned scan.
    final anchor = DateTime.utc(2026, 8, 15);
    if ((bloc.state as CalendarPageLoaded).focusedDay != anchor) {
      await dispatch(ChangeFocusedDay(focusedDay: anchor));
    }
  });

  tearDown(() async {
    await bloc.close();
  });

  // The painted window is 2026-07-27 .. 2026-09-06: July 27-31, all of August,
  // September 1-6.
  //
  // Dense — the 40 `DailyRecurrence(interval: 1)` events return `null` from
  // `candidateDaysIn`, so each is still tested on all 42 days.
  const denseDailyCalls = 42 * 40;
  // Sparse — the 40 weekly events fire on Mondays, of which the window holds
  // six (Jul 27, Aug 3/10/17/24/31).
  const weeklyCalls = 6 * 40;
  // Sparse — each of the 40 monthly events has one candidate per month, so it
  // is validated twice when its start day-of-month falls in the window's July
  // (27-31) or September (1-6) overhang and once otherwise. Seeded starts put
  // 7 events on days 1-6 and 6 on days 27-31; the other 27 land in 7-26.
  const monthlyCalls = (7 + 6) * 2 + 27;
  // Sparse — every yearly anchor is between Jan 5 and Jul 19 2026, so none of
  // them comes round again before 2027. One-time events were already bucketed
  // out of the scan by 3.2a, and their anchors are outside the window too.
  const coldMonthCalls = denseDailyCalls + weeklyCalls + monthlyCalls;

  test(
    'a cold month tests each event only on days its rule can fire',
    () async {
      CalendarEvent.debugOccursOnCalls = 0;

      for (final day in month) {
        bloc.eventsForDay(day);
      }

      expect(CalendarEvent.debugOccursOnCalls, coldMonthCalls);
    },
  );

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

    // Same partition as the cold-month case above, rebuilt from scratch.
    expect(CalendarEvent.debugOccursOnCalls, coldMonthCalls);
  });

  test('an agenda scan prunes the days each rule cannot fall on', () async {
    final events = (bloc.state as CalendarPageLoaded).allEvents;

    const windowDays = 30;

    CalendarEvent.debugOccursOnCalls = 0;
    // August 1-30 is after every seeded start date (Jan–Jul), so all one-time
    // events fall outside the window and cost zero `occursOn`, and no yearly
    // anchor comes round inside it. The 40 daily events are dense and scanned
    // on all 30 days; the 40 weekly events cost one call per Monday, of which
    // this window holds four; each of the 40 monthly events has exactly one
    // August candidate, since every seeded start day-of-month is at most 30.
    // Without any pruning this would be `eventCount * windowDays` = 6000.
    const agendaCalls = 30 * 40 + 4 * 40 + 1 * 40;
    EventAgenda.occurrencesInRange(
      events: events,
      from: DateTime.utc(2026, 8, 1),
      to: DateTime.utc(2026, 8, windowDays),
    );

    expect(CalendarEvent.debugOccursOnCalls, agendaCalls);
  });
}
