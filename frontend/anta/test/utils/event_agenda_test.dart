import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/liturgical_computus.dart';

/// Pure coverage for the agenda scan's event-type axis and the fasting-day
/// scan — no widget tree, no database. `SpecificDatesRecurrence` counts as
/// recurring everywhere in the codebase, so the filter must agree.
void main() {
  final windowStart = DateTime.utc(2026, 8, 10);
  final windowEnd = DateTime.utc(2026, 8, 12);

  final oneTime = CalendarEvent(
    id: 'ot',
    title: 'Dentist',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 8, 11),
    rule: const OneTimeRecurrence(),
  );
  final daily = CalendarEvent(
    id: 'd',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
  );
  final specific = CalendarEvent(
    id: 'sp',
    title: 'Pinned',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 8, 10),
    rule: SpecificDatesRecurrence(dates: {DateTime.utc(2026, 8, 10)}),
  );

  final events = [oneTime, daily, specific];

  Set<String> idsFor(AgendaEventType eventType) {
    return EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      eventType: eventType,
    ).map((o) => o.event.id).toSet();
  }

  Set<String> idsForCategories(
    Set<String> categoryIds, {
    Set<String> hiddenCategoryIds = const {},
  }) {
    return EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      categoryIds: categoryIds,
      hiddenCategoryIds: hiddenCategoryIds,
    ).map((o) => o.event.id).toSet();
  }

  test('all admits every event kind', () {
    expect(idsFor(AgendaEventType.all), {'ot', 'd', 'sp'});
  });

  test('recurring drops one-time but keeps specific-dates', () {
    expect(idsFor(AgendaEventType.recurring), {'d', 'sp'});
  });

  test('oneTime keeps only single-occurrence events', () {
    expect(idsFor(AgendaEventType.oneTime), {'ot'});
  });

  test('none short-circuits to no event occurrences', () {
    expect(
      EventAgenda.occurrencesInRange(
        events: events,
        from: windowStart,
        to: windowEnd,
        eventType: AgendaEventType.none,
      ),
      isEmpty,
    );
  });

  test('fastingDaysInRange is empty when no tradition is configured', () {
    // FastingCalendar is unconfigured in a bare test, so the scan pays nothing.
    expect(
      EventAgenda.fastingDaysInRange(from: windowStart, to: windowEnd),
      isEmpty,
    );
  });

  test('category allowlist keeps only the selected categories', () {
    expect(idsForCategories({'gym'}), {'d'});
    expect(idsForCategories({'other'}), {'ot', 'sp'});
  });

  test('an empty category allowlist shows every category', () {
    expect(idsForCategories(const {}), {'ot', 'd', 'sp'});
  });

  test('the category allowlist composes with the hidden set', () {
    // Both apply: 'other' stays hidden even though it is in the allowlist.
    expect(idsForCategories({'gym', 'other'}, hiddenCategoryIds: {'other'}), {
      'd',
    });
  });

  test('collapseRecurring shows each recurring event once', () {
    final occ = EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      collapseRecurring: true,
    );
    final counts = <String, int>{};
    for (final o in occ) {
      counts[o.event.id] = (counts[o.event.id] ?? 0) + 1;
    }
    // Daily collapses from 3 rows to 1; one-time and specific stay at 1.
    expect(counts, {'ot': 1, 'd': 1, 'sp': 1});
    // The kept row is the recurring event's first in-window occurrence.
    expect(occ.firstWhere((o) => o.event.id == 'd').day, windowStart);
  });

  test('without collapseRecurring a daily event shows on every day', () {
    final occ = EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
    );
    expect(occ.where((o) => o.event.id == 'd').length, 3);
    // Nothing was folded, so no row stands in for more than itself.
    expect(occ.every((o) => o.occurrenceCountInWindow == 1), isTrue);
  });

  test('a collapsed row carries how many occurrences it stands for', () {
    final occ = EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      collapseRecurring: true,
    );
    final byId = {for (final o in occ) o.event.id: o.occurrenceCountInWindow};
    // The daily event occurs on all three days of the window; the other two
    // occur once each and must not claim otherwise.
    expect(byId, {'ot': 1, 'd': 3, 'sp': 1});
  });

  test('collapsing does not change how often occursOn is asked', () {
    // The count is a post-filter over an already-built list, never a
    // short-circuit of the scan — the occursOn budget tests depend on it.
    CalendarEvent.debugOccursOnCalls = 0;
    EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
    );
    final plain = CalendarEvent.debugOccursOnCalls;

    CalendarEvent.debugOccursOnCalls = 0;
    EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      collapseRecurring: true,
    );
    expect(CalendarEvent.debugOccursOnCalls, plain);
  });

  group('fastingRunsInRange', () {
    // Orthodox Wednesday/Friday abstinence gives a predictable sparse pattern,
    // and the Nativity Fast a long contiguous one.
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    List<FastingRun> runsIn(DateTime from, DateTime to) =>
        EventAgenda.fastingRunsInRange(from: from, to: to);

    test('is empty when no tradition is configured', () {
      FastingCalendar.resetConfiguration();
      expect(
        runsIn(DateTime.utc(2026, 11, 20), DateTime.utc(2026, 12, 5)),
        isEmpty,
      );
    });

    test('groups a contiguous period into one run', () {
      // Mid-Nativity-Fast: every day fasts, so the whole window is one run.
      final runs = runsIn(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 12, 5),
      );

      expect(runs, hasLength(1));
      expect(runs.single.day, DateTime.utc(2026, 11, 20));
      expect(runs.single.period, FastingPeriod.nativityFast);
      expect(runs.single.tradition, FastingTradition.orthodox);
    });

    test('a clipped run reports its true extent, not the window', () {
      final runs = runsIn(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 12, 5),
      );
      final run = runs.single;

      // The fast starts on 15 November and runs to Christmas Eve, both outside
      // the queried window — the label must say so, or a collapsed row would
      // claim the window's own bounds.
      expect(run.start, DateTime.utc(2026, 11, 15));
      expect(run.end, DateTime.utc(2026, 12, 24));
      // Contiguous, so the marked-day count and the calendar extent agree.
      expect(run.dayCount, 40);
      expect(run.end.difference(run.start).inDays + 1, run.dayCount);
      // Placement stays inside the window so the row merges in day order.
      expect(run.day.isBefore(run.start), isFalse);
    });

    test('a sparse period is still one run, counted by marked days', () {
      // The user's own practice is Wednesday and Friday, applied to every
      // fast: the Nativity Fast keeps only its Wednesdays and Fridays, and a
      // day-contiguity grouping would emit eleven one-day rows instead of the
      // one period the user is actually keeping.
      FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.wednesday, DateTime.friday},
          weekdayScope: FastingWeekdayScope.allFasts,
        ),
      );

      final runs = runsIn(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 12, 5),
      );

      expect(runs, hasLength(1));
      final run = runs.single;
      expect(run.period, FastingPeriod.nativityFast);
      expect(run.day, DateTime.utc(2026, 11, 20));
      // First and last *marked* days of the fast, both outside the window.
      expect(run.start, DateTime.utc(2026, 11, 18));
      expect(run.end, DateTime.utc(2026, 12, 23));
      // Eleven kept days, not the forty the calendar distance would claim.
      expect(run.dayCount, 11);
    });

    test('the weekly fast never bridges — one run per marked day', () {
      // Bridging the year-round rule would fuse a whole window into a single
      // span that means nothing, so only named multi-day periods bridge.
      final runs = runsIn(DateTime.utc(2026, 9, 7), DateTime.utc(2026, 9, 20));
      final weekly = runs
          .where((run) => run.period == FastingPeriod.weekdayFast)
          .toList();

      expect(weekly.map((run) => run.day), [
        DateTime.utc(2026, 9, 9),
        DateTime.utc(2026, 9, 11),
        DateTime.utc(2026, 9, 16),
        DateTime.utc(2026, 9, 18),
      ]);
      expect(weekly.every((run) => run.dayCount == 1), isTrue);
      expect(weekly.every((run) => run.start == run.end), isTrue);
    });

    test('two periods that touch in time stay two runs', () {
      // Cheesefare week's Friday sits three days before Clean Monday: close
      // enough for the bridge, but a different period — merging them would
      // invent a fast nobody keeps.
      final pascha = LiturgicalComputus.easterSundayOrthodox(2026);
      final runs = runsIn(
        pascha.subtract(const Duration(days: 55)),
        pascha.subtract(const Duration(days: 40)),
      );

      expect(runs.map((run) => run.period), [
        FastingPeriod.cheesefareWeek,
        FastingPeriod.greatLent,
      ]);
      // Cheesefare is Wednesday/Friday by its own rule — sparse from birth.
      expect(runs.first.dayCount, 2);
    });

    test('separate stretches stay separate runs', () {
      // An ordinary stretch of Ordinary Time: only Wednesdays and Fridays
      // fast, so a two-week window yields several short runs rather than one.
      final runs = runsIn(DateTime.utc(2026, 9, 7), DateTime.utc(2026, 9, 20));

      expect(runs.length, greaterThan(1));
      for (final run in runs) {
        expect(run.start.isAfter(run.end), isFalse);
      }
      // Runs come out in ascending order, and none of them touch.
      for (var i = 1; i < runs.length; i++) {
        expect(runs[i].day.isAfter(runs[i - 1].day), isTrue);
      }
    });

    test('a day filter narrows the runs and their extent', () {
      // A filter nothing satisfies must produce no runs at all — the outward
      // walk has to honour it too, or a run would grow past its own days.
      final runs = EventAgenda.fastingRunsInRange(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 12, 5),
        dayFilter: (_) => false,
      );

      expect(runs, isEmpty);
    });

    test('runs never cost an occursOn call', () {
      CalendarEvent.debugOccursOnCalls = 0;
      runsIn(DateTime.utc(2026, 11, 20), DateTime.utc(2026, 12, 5));
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });
  });

  group('fastingSummariesInRange', () {
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    List<FastingSummary> summariesIn(DateTime from, DateTime to) =>
        EventAgenda.fastingSummariesInRange(from: from, to: to);

    test('is empty when no tradition is configured', () {
      FastingCalendar.resetConfiguration();
      expect(
        summariesIn(DateTime.utc(2026, 11, 20), DateTime.utc(2026, 12, 5)),
        isEmpty,
      );
    });

    test('a fully-contained fast is digested to its own numbers', () {
      // The whole Nativity Fast, window and fast coinciding: every day marked,
      // so the pattern is "every weekday" and the count is the fast's length.
      final summary = summariesIn(
        DateTime.utc(2026, 11, 15),
        DateTime.utc(2026, 12, 24),
      ).single;

      expect(summary.tradition, FastingTradition.orthodox);
      expect(summary.first, DateTime.utc(2026, 11, 15));
      expect(summary.last, DateTime.utc(2026, 12, 24));
      expect(summary.dayCount, 40);
      expect(summary.weekdays, {1, 2, 3, 4, 5, 6, 7});
      expect(summary.spanPeriods, [FastingPeriod.nativityFast]);
    });

    test('the numbers are window-scoped, unlike a run\x27s', () {
      // The same fast seen through a narrower window. A run reports the fast\x27s
      // true extent (Nov 15 - Dec 24, forty days) because it *is* the fast; a
      // summary describes fasting **here**, so claiming days the list below it
      // does not show would make the card disagree with its own list.
      final from = DateTime.utc(2026, 11, 20);
      final to = DateTime.utc(2026, 12, 5);
      final summary = summariesIn(from, to).single;
      final run = EventAgenda.fastingRunsInRange(from: from, to: to).single;

      expect(summary.first, from);
      expect(summary.last, to);
      expect(summary.dayCount, 16);
      expect(run.start, DateTime.utc(2026, 11, 15));
      expect(run.dayCount, 40);
    });

    test('a sparse practice reports the weekdays it actually keeps', () {
      FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.wednesday, DateTime.friday},
          weekdayScope: FastingWeekdayScope.allFasts,
        ),
      );

      final summary = summariesIn(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 12, 5),
      ).single;

      expect(summary.weekdays, {DateTime.wednesday, DateTime.friday});
      // Nov 20, 25, 27 and Dec 2, 4 - the kept days inside the window, never
      // the calendar distance between the ends.
      expect(summary.first, DateTime.utc(2026, 11, 20));
      expect(summary.last, DateTime.utc(2026, 12, 4));
      expect(summary.dayCount, 5);
    });

    test('each named fast in the window is listed once', () {
      // Cheesefare week then Great Lent: two span periods, so the card can no
      // longer name itself after one of them.
      final pascha = LiturgicalComputus.easterSundayOrthodox(2026);
      final summary = summariesIn(
        pascha.subtract(const Duration(days: 55)),
        pascha.subtract(const Duration(days: 40)),
      ).single;

      expect(summary.spanPeriods, [
        FastingPeriod.cheesefareWeek,
        FastingPeriod.greatLent,
      ]);
    });

    test('single-day fasts add a weekday but never a named period', () {
      // Ordinary time: the year-round Wednesday/Friday rule, plus the
      // Exaltation of the Cross falling on a Monday. Only multi-day periods
      // are span periods, so the card has nothing to name itself after - but
      // the Monday is a day the user fasts, so the pattern must say so.
      final summary = summariesIn(
        DateTime.utc(2026, 9, 7),
        DateTime.utc(2026, 9, 20),
      ).single;

      expect(summary.spanPeriods, isEmpty);
      expect(summary.weekdays, {
        DateTime.monday,
        DateTime.wednesday,
        DateTime.friday,
      });
    });

    test('one summary per tradition, in declaration order', () {
      FastingCalendar.configure(
        traditions: const {
          FastingTradition.catholic,
          FastingTradition.orthodox,
        },
      );

      final summaries = summariesIn(
        DateTime.utc(2026, 9, 7),
        DateTime.utc(2026, 9, 20),
      );

      // Declaration order, matching what `FastingCalendar.on` emits - never
      // the order the configured set happens to iterate in.
      expect(summaries.map((s) => s.tradition), [
        FastingTradition.orthodox,
        FastingTradition.catholic,
      ]);
    });

    test('a day filter that matches nothing yields no summaries', () {
      expect(
        EventAgenda.fastingSummariesInRange(
          from: DateTime.utc(2026, 11, 20),
          to: DateTime.utc(2026, 12, 5),
          dayFilter: (_) => false,
        ),
        isEmpty,
      );
    });

    test('the day list is exactly what the count counts', () {
      // The card prints `dayCount` and its drill-down lists `days`; the two
      // disagreeing is the one way that surface can lie, so they are the same
      // list by construction and this pins it.
      final summary = summariesIn(
        DateTime.utc(2026, 11, 20),
        DateTime.utc(2026, 12, 5),
      ).single;

      expect(summary.days, hasLength(summary.dayCount));
      expect(summary.days.first, summary.first);
      expect(summary.days.last, summary.last);
      expect(summary.days.toSet(), hasLength(summary.dayCount));
      for (var i = 1; i < summary.days.length; i++) {
        expect(summary.days[i].isAfter(summary.days[i - 1]), isTrue);
      }
    });

    test('a day filter narrows the day list, not just the count', () {
      // A filtered-out day must not survive in the list a drill-down shows,
      // or the sheet would offer days the agenda deliberately excluded.
      final summary = EventAgenda.fastingSummariesInRange(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 12, 5),
        dayFilter: (day) => day.weekday == DateTime.wednesday,
      ).single;

      expect(summary.days, isNotEmpty);
      expect(
        summary.days.every((day) => day.weekday == DateTime.wednesday),
        isTrue,
      );
      expect(summary.days, hasLength(summary.dayCount));
    });

    test('summaries never cost an occursOn call', () {
      CalendarEvent.debugOccursOnCalls = 0;
      summariesIn(DateTime.utc(2026, 11, 20), DateTime.utc(2026, 12, 5));
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });
  });

  group('categorySummariesOf', () {
    final gym = CalendarEvent(
      id: 'g1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: const DailyRecurrence(),
    );
    final gymOnce = CalendarEvent(
      id: 'g2',
      title: 'Assessment',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 11),
      rule: const OneTimeRecurrence(),
    );
    final dentist = CalendarEvent(
      id: 'o1',
      title: 'Dentist',
      categoryId: 'other',
      startDate: DateTime.utc(2026, 8, 12),
      rule: const OneTimeRecurrence(),
    );

    List<EventCategorySummary> summarize(List<CalendarEvent> events) {
      return EventAgenda.categorySummariesOf(
        EventAgenda.occurrencesInRange(
          events: events,
          from: windowStart,
          to: windowEnd,
        ),
      );
    }

    test('an empty scan produces nothing', () {
      expect(EventAgenda.categorySummariesOf(const []), isEmpty);
    });

    test('one summary per category, ordered by first occurrence', () {
      final summaries = summarize([gym, gymOnce, dentist]);

      // Gym occurs on the window's first day; 'other' not until the 12th.
      expect(summaries.map((s) => s.categoryId), ['gym', 'other']);
    });

    test('the count leads with distinct events, not occurrences', () {
      // A daily event across the window is one event, not three — that is the
      // number worth putting on a digest card.
      final summary = summarize([gym, gymOnce]).single;

      expect(summary.categoryId, 'gym');
      expect(summary.eventCount, 2);
      expect(summary.occurrenceCount, 4);
      expect(summary.occurrences, hasLength(4));
    });

    test('first and last bracket the occurrences it holds', () {
      final summary = summarize([gym, gymOnce]).single;

      expect(summary.first, summary.occurrences.first.day);
      expect(summary.last, summary.occurrences.last.day);
      expect(summary.first, windowStart);
      expect(summary.last, windowEnd);
    });

    test('it is a post-pass, so it costs no occursOn call', () {
      // The whole point of folding the scan's output rather than re-walking:
      // the card is free, and it can only describe days the scan produced.
      final occurrences = EventAgenda.occurrencesInRange(
        events: [gym, gymOnce, dentist],
        from: windowStart,
        to: windowEnd,
      );

      CalendarEvent.debugOccursOnCalls = 0;
      EventAgenda.categorySummariesOf(occurrences);
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });

    test('it inherits whatever the scan already filtered out', () {
      // A category the allowlist excluded never reaches the fold, so no card
      // can claim it.
      final summaries = EventAgenda.categorySummariesOf(
        EventAgenda.occurrencesInRange(
          events: [gym, dentist],
          from: windowStart,
          to: windowEnd,
          categoryIds: {'gym'},
        ),
      );

      expect(summaries.map((s) => s.categoryId), ['gym']);
    });
  });

  group('the window partition drops no occurrence', () {
    /// The scan with the 3.2b partition removed: every event tested on every
    /// day, through the same sole arbiter (`occursOnUtcDay`) and sorted by the
    /// same comparator. Whatever pruning `partitionForWindow` does, the two
    /// must agree exactly — that is the whole safety claim, checked rather
    /// than argued.
    List<String> reference(
      List<CalendarEvent> events,
      DateTime from,
      DateTime to,
    ) {
      final rows = <String>[];
      for (
        var day = from;
        !day.isAfter(to);
        day = day.add(const Duration(days: 1))
      ) {
        final onDay = [
          for (final event in events)
            if (event.occursOnUtcDay(day)) event,
        ]..sort(EventAgenda.compareWithinDay);
        for (final event in onDay) {
          rows.add('${event.id}@${day.toIso8601String()}');
        }
      }
      return rows;
    }

    List<String> scanned(
      List<CalendarEvent> events,
      DateTime from,
      DateTime to,
    ) => EventAgenda.occurrencesInRange(
      events: events,
      from: from,
      to: to,
    ).map((o) => '${o.event.id}@${o.day.toIso8601String()}').toList();

    CalendarEvent build(
      String id,
      RecurrenceRule rule,
      DateTime start, {
      DateTime? endDate,
      bool retroactive = false,
    }) => CalendarEvent(
      id: id,
      title: id,
      categoryId: 'gym',
      startDate: start,
      rule: rule,
      endDate: endDate,
      retroactive: retroactive,
    );

    final oneJan = DateTime.utc(2019, 1, 1);

    // One event per rule shape the generator handles differently, plus the two
    // clamps that live outside the rule: `endDate` and `retroactive`. The
    // holiday-backed rules are included deliberately — both sides read the same
    // process-wide `PublicHolidays` state, so the comparison stays valid.
    final mixed = <CalendarEvent>[
      build('daily1', const DailyRecurrence(), DateTime.utc(2026, 1, 15)),
      build(
        'daily4',
        const DailyRecurrence(interval: 4),
        DateTime.utc(2026, 2, 3),
      ),
      build(
        'weekMonFri',
        const WeeklyRecurrence(weekdays: {DateTime.monday, DateTime.friday}),
        DateTime.utc(2026, 3, 5),
      ),
      build(
        'weekEvery2',
        const WeeklyRecurrence(weekdays: {DateTime.thursday}, interval: 2),
        DateTime.utc(2026, 4, 2),
      ),
      build('weekNone', const WeeklyRecurrence(weekdays: <int>{}), oneJan),
      build('month31', const MonthlyRecurrence(), DateTime.utc(2026, 1, 31)),
      build(
        'month3',
        const MonthlyRecurrence(interval: 3),
        DateTime.utc(2026, 2, 14),
      ),
      build('yearFeb29', const YearlyRecurrence(), DateTime.utc(2024, 2, 29)),
      build('yearly', const YearlyRecurrence(), DateTime.utc(2020, 9, 3)),
      build('workdays', const WorkdaysRecurrence(), oneJan),
      build('weekends', const WeekendsRecurrence(), oneJan),
      build('holidays', const PublicHolidaysOnlyRecurrence(), oneJan),
      build('once', const OneTimeRecurrence(), DateTime.utc(2026, 8, 20)),
      build(
        'pinned',
        SpecificDatesRecurrence(
          dates: {
            DateTime.utc(2026, 9, 4),
            DateTime.utc(2025, 12, 1),
            DateTime.utc(2026, 7, 7),
          },
        ),
        DateTime.utc(2026, 9, 4),
      ),
      build(
        'ended',
        const WeeklyRecurrence(weekdays: {DateTime.wednesday}),
        DateTime.utc(2026, 1, 7),
        endDate: DateTime.utc(2026, 8, 19),
      ),
      build(
        'retroMonthly',
        const MonthlyRecurrence(interval: 2),
        DateTime.utc(2027, 5, 21),
        retroactive: true,
      ),
      build(
        'retroYearly',
        const YearlyRecurrence(),
        DateTime.utc(2030, 2, 29),
        retroactive: true,
      ),
    ];

    for (final window in <(String, DateTime, DateTime)>[
      (
        'a grid-sized window',
        DateTime.utc(2026, 7, 27),
        DateTime.utc(2026, 9, 6),
      ),
      (
        'the full 366-day cap',
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      ),
      (
        'a window before every anchor',
        DateTime.utc(2019, 3, 1),
        DateTime.utc(2019, 6, 30),
      ),
      ('a single day', DateTime.utc(2026, 8, 20), DateTime.utc(2026, 8, 20)),
    ]) {
      test('matches an unpruned scan over ${window.$1}', () {
        expect(
          scanned(mixed, window.$2, window.$3),
          reference(mixed, window.$2, window.$3),
        );
      });
    }

    test('endDate still clamps a bucketed sparse rule', () {
      final ids = scanned(
        [mixed.firstWhere((e) => e.id == 'ended')],
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 8, 31),
      );
      // Wednesdays in August 2026 are the 5th, 12th, 19th and 26th; endDate
      // is the 19th, so the 26th must not survive the bucket.
      expect(ids, [
        'ended@2026-08-05T00:00:00.000Z',
        'ended@2026-08-12T00:00:00.000Z',
        'ended@2026-08-19T00:00:00.000Z',
      ]);
    });

    test('a retroactive rule still fires before its anchor', () {
      final ids = scanned(
        [mixed.firstWhere((e) => e.id == 'retroMonthly')],
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 6, 30),
      );
      // Anchored 2027-05-21 every two months, retroactive: the phase runs
      // backwards through the odd-month offsets, never by rebuilding the
      // anchor in an earlier month.
      expect(ids, [
        'retroMonthly@2026-01-21T00:00:00.000Z',
        'retroMonthly@2026-03-21T00:00:00.000Z',
        'retroMonthly@2026-05-21T00:00:00.000Z',
      ]);
    });
  });
}
