import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/liturgical_computus.dart';
import 'package:anta/widgets/agenda_list_view.dart';

/// `buildAgendaRows` is the single place the agenda decides what exists: the
/// list draws these rows and the panel header counts them. So the property
/// worth pinning is not "hidden mode dims something" but that **the count and
/// the rows come out of the same pass** — the bug that made the header promise
/// entries the list had already dropped.
///
/// Driven directly against `AppLocalizationsEn()`, with no widget tree: the
/// function is pure given the static presence/description facades, which is
/// exactly what makes it testable this way.
void main() {
  final l10n = AppLocalizationsEn();

  // A collapsed fasting period formats its span while the rows are built. In
  // the app the localization delegates have already loaded the locale data by
  // then; driving the function bare has to do it explicitly.
  setUpAll(() => initializeDateFormatting('en'));

  final day1 = DateTime.utc(2026, 8, 10);
  final day2 = DateTime.utc(2026, 8, 11);

  /// New Year resolves through the uninitialized fixed-date fallback, so a
  /// holiday day needs no profile configured here.
  final holiday = DateTime.utc(2026, 1, 1);

  /// Tracked, so its occurrences can be marked missed.
  final tracked = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
    tracksPresence: true,
  );

  /// Untracked: never droppable, so it proves hiding narrows to the marks.
  final untracked = CalendarEvent(
    id: 'e2',
    title: 'Mobility',
    categoryId: 'mobility',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
  );

  List<AgendaRow> build({
    List<EventOccurrence> occurrences = const [],
    List<DateTime> holidayDays = const [],
    List<DateTime> fastingDays = const [],
    List<FastingRun> fastingRuns = const [],
    List<FastingSummary> fastingSummaries = const [],
    AgendaHolidayDisplay holidayDisplay = AgendaHolidayDisplay.everyDay,
    List<EventCategorySummary> eventSummaries = const [],
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) {
    return buildAgendaRows(
      occurrences: occurrences,
      holidayDays: holidayDays,
      fastingDays: fastingDays,
      fastingRuns: fastingRuns,
      fastingSummaries: fastingSummaries,
      holidayDisplay: holidayDisplay,
      eventSummaries: eventSummaries,
      l10n: l10n,
      showRecurrenceLabels: true,
      missedDisplay: missedDisplay,
    );
  }

  /// Day 1 carries both events, day 2 only the tracked one — which is marked
  /// missed, so hiding empties that day completely.
  final occurrences = [
    EventOccurrence(event: tracked, day: day1),
    EventOccurrence(event: untracked, day: day1),
    EventOccurrence(event: tracked, day: day2),
  ];

  setUp(() {
    EventPresence.updateCache(
      byEvent: {
        'e1': {day2},
      },
    );
  });

  // The facade is process-wide static state; leaving a mark behind would
  // silently change what a later test — in any file — renders.
  tearDown(EventPresence.resetCache);

  test('hidden mode drops a missed entry and the header it emptied', () {
    final rows = build(
      occurrences: occurrences,
      missedDisplay: CalendarMissedDisplay.hidden,
    );

    expect(rows.whereType<AgendaDayHeaderRow>().map((r) => r.day), [day1]);
    expect(rows.whereType<AgendaEntryRow>().map((r) => r.entry.title), [
      'Leg day',
      'Mobility',
    ]);
  });

  test('faded mode keeps the missed entry and its day', () {
    final rows = build(occurrences: occurrences);

    expect(rows.whereType<AgendaDayHeaderRow>().map((r) => r.day), [
      day1,
      day2,
    ]);
    final missed = rows.whereType<AgendaEntryRow>().where((r) => r.day == day2);
    expect(missed.single.entry.title, 'Leg day');
    expect(missed.single.entry.missed, isTrue);
  });

  test('every header count equals the entry rows that follow it', () {
    for (final display in CalendarMissedDisplay.values) {
      final rows = build(
        occurrences: occurrences,
        holidayDays: [holiday],
        missedDisplay: display,
      );

      final perDay = <DateTime, int>{};
      for (final row in rows.whereType<AgendaEntryRow>()) {
        perDay.update(row.day, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final header in rows.whereType<AgendaDayHeaderRow>()) {
        expect(header.count, perDay[header.day], reason: display.name);
      }
      // The panel header's number: totalling the per-day counts and counting
      // the rows must be the same arithmetic, or the two disagree again.
      expect(
        rows.whereType<AgendaEntryRow>().length,
        rows.whereType<AgendaDayHeaderRow>().fold<int>(
          0,
          (sum, header) => sum + header.count,
        ),
        reason: display.name,
      );
    }
  });

  test('a holiday day with no events still produces an entry row', () {
    expect(PublicHolidays.isHoliday(holiday), isTrue);

    final rows = build(holidayDays: [holiday]);

    expect(rows.whereType<AgendaDayHeaderRow>().single.count, 1);
    final entry = rows.whereType<AgendaEntryRow>().single;
    expect(entry.day, holiday);
    expect(entry.entry.title, l10n.publicHolidayNewYear);
    // No event behind it, which is what strips the row's edit/note actions.
    expect(entry.entry.event, isNull);
  });

  test('a holiday shares its day with the events, after them', () {
    final rows = build(
      occurrences: [EventOccurrence(event: untracked, day: holiday)],
      holidayDays: [holiday],
    );

    expect(rows.whereType<AgendaDayHeaderRow>().single.count, 2);
    expect(rows.whereType<AgendaEntryRow>().map((r) => r.entry.key), [
      'event:e2',
      'holiday',
    ]);
  });

  test('an occurrence carries its collapsed count onto the row', () {
    final rows = build(
      occurrences: [
        EventOccurrence(event: tracked, day: day1, occurrenceCountInWindow: 12),
        EventOccurrence(event: untracked, day: day1),
      ],
    );

    final byTitle = {
      for (final row in rows.whereType<AgendaEntryRow>())
        row.entry.title: row.occurrenceCount,
    };
    // Only the collapsed one stands for more than itself; the badge is what
    // stops it passing as a single event.
    expect(byTitle, {'Leg day': 12, 'Mobility': 1});
  });

  group('month separators', () {
    test('a single-month window emits none', () {
      final rows = build(
        occurrences: [
          EventOccurrence(event: untracked, day: day1),
          EventOccurrence(event: untracked, day: day2),
        ],
      );

      expect(rows.whereType<AgendaMonthHeaderRow>(), isEmpty);
    });

    test('a window spanning months opens each one', () {
      final september = DateTime.utc(2026, 9, 3);
      final rows = build(
        occurrences: [
          EventOccurrence(event: untracked, day: day1),
          EventOccurrence(event: untracked, day: september),
        ],
      );

      final months = rows.whereType<AgendaMonthHeaderRow>().toList();
      expect(months.map((m) => m.month), [
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 9, 1),
      ]);
      // Both months sit in 2026, so a bare month name is unambiguous.
      expect(months.every((m) => !m.showYear), isTrue);
      // Each separator immediately precedes its month's first day header.
      expect(rows.first, isA<AgendaMonthHeaderRow>());
      expect(rows[1], isA<AgendaDayHeaderRow>());
    });

    test('a window crossing a year asks for the year too', () {
      final rows = build(
        occurrences: [
          EventOccurrence(event: untracked, day: DateTime.utc(2026, 12, 20)),
          EventOccurrence(event: untracked, day: DateTime.utc(2027, 1, 5)),
        ],
      );

      expect(
        rows.whereType<AgendaMonthHeaderRow>().every((m) => m.showYear),
        isTrue,
      );
    });
  });

  group('collapsed fasting periods', () {
    setUp(
      () => FastingCalendar.configure(traditions: {FastingTradition.orthodox}),
    );
    tearDown(FastingCalendar.resetConfiguration);

    test('a run becomes one row carrying the period span', () {
      final run = EventAgenda.fastingRunsInRange(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 12, 5),
      ).single;

      final rows = build(fastingRuns: [run]);

      // Sixteen fasting days in the window, one row for the period.
      final entries = rows.whereType<AgendaEntryRow>().toList();
      expect(entries, hasLength(1));
      expect(entries.single.day, run.day);
      expect(entries.single.entry.event, isNull);
      // The subtitle carries the run's real extent and length, not the day's
      // regime and not the window's bounds.
      expect(entries.single.entry.subtitle, contains('Nov 15'));
      expect(entries.single.entry.subtitle, contains('Dec 24'));
      expect(entries.single.entry.subtitle, contains('40 days'));
    });

    test('the collapsed row counts once toward the day header', () {
      final run = EventAgenda.fastingRunsInRange(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 12, 5),
      ).single;

      final rows = build(fastingRuns: [run]);

      expect(rows.whereType<AgendaDayHeaderRow>().single.count, 1);
    });

    test('a one-day run keeps the day regime as its subtitle', () {
      // An isolated Wednesday abstinence: a "Sep 9 – Sep 9 · 1 day" subtitle
      // would say less than the regime it replaced.
      final runs = EventAgenda.fastingRunsInRange(
        from: DateTime.utc(2026, 9, 7),
        to: DateTime.utc(2026, 9, 20),
      );
      final single = runs.firstWhere((r) => r.dayCount == 1);

      final rows = build(fastingRuns: [single]);
      final entry = rows.whereType<AgendaEntryRow>().single.entry;

      expect(entry.subtitle, isNot(contains('1 day')));
    });

    test('a sparse run shows its true extent and its kept-day count', () {
      // Wednesday/Friday applied to every fast: the Nativity Fast keeps
      // eleven of its forty days, and the row has to say eleven — the extent
      // alone would read as a fast the user is not actually keeping.
      FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.wednesday, DateTime.friday},
          weekdayScope: FastingWeekdayScope.allFasts,
        ),
      );
      final run = EventAgenda.fastingRunsInRange(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 12, 5),
      ).single;

      final rows = build(fastingRuns: [run]);
      final entry = rows.whereType<AgendaEntryRow>().single.entry;

      expect(entry.subtitle, contains('Nov 18'));
      expect(entry.subtitle, contains('Dec 23'));
      expect(entry.subtitle, contains('11 days'));
    });

    test('per-day fasting still emits one row per day', () {
      final rows = build(fastingDays: [day1, day2]);

      expect(rows.whereType<AgendaEntryRow>(), hasLength(2));
      expect(rows.whereType<AgendaDayHeaderRow>(), hasLength(2));
    });
  });

  group('fasting summary cards', () {
    setUp(
      () => FastingCalendar.configure(traditions: {FastingTradition.orthodox}),
    );
    tearDown(FastingCalendar.resetConfiguration);

    List<FastingSummary> summariesIn(DateTime from, DateTime to) =>
        EventAgenda.fastingSummariesInRange(from: from, to: to);

    /// The whole Nativity Fast: one span period, every weekday marked.
    List<FastingSummary> nativity() =>
        summariesIn(DateTime.utc(2026, 11, 15), DateTime.utc(2026, 12, 24));

    test('the card leads the list, above the first header', () {
      final rows = build(
        occurrences: [EventOccurrence(event: untracked, day: day1)],
        fastingSummaries: nativity(),
      );

      expect(rows.first, isA<AgendaFastingSummaryRow>());
      expect(rows[1], isA<AgendaDayHeaderRow>());
    });

    test('it stays above a month separator too', () {
      final rows = build(
        occurrences: [
          EventOccurrence(event: untracked, day: day1),
          EventOccurrence(event: untracked, day: DateTime.utc(2026, 9, 3)),
        ],
        fastingSummaries: nativity(),
      );

      expect(rows.first, isA<AgendaFastingSummaryRow>());
      expect(rows[1], isA<AgendaMonthHeaderRow>());
    });

    test('it is not an entry, so no count claims it', () {
      final rows = build(
        occurrences: [EventOccurrence(event: untracked, day: day1)],
        fastingSummaries: nativity(),
      );

      // The panel header counts `AgendaEntryRow`s; a card summarizes entries
      // rather than being one, so it has to stay out of both totals.
      expect(rows.whereType<AgendaEntryRow>(), hasLength(1));
      expect(rows.whereType<AgendaDayHeaderRow>().single.count, 1);
    });

    test('a summary-only window still renders its cards', () {
      final rows = build(fastingSummaries: nativity());

      expect(rows, hasLength(1));
      expect(rows.single, isA<AgendaFastingSummaryRow>());
      expect(rows.whereType<AgendaDayHeaderRow>(), isEmpty);
    });

    test('one named fast in the window titles the card', () {
      final row = build(
        fastingSummaries: nativity(),
      ).whereType<AgendaFastingSummaryRow>().single;

      expect(row.entry.title, 'Nativity Fast');
    });

    test('several named fasts fall back to the tradition name', () {
      // Cheesefare week then Great Lent: naming the card after either would
      // misdescribe the other.
      final pascha = LiturgicalComputus.easterSundayOrthodox(2026);
      final row = build(
        fastingSummaries: summariesIn(
          pascha.subtract(const Duration(days: 55)),
          pascha.subtract(const Duration(days: 40)),
        ),
      ).whereType<AgendaFastingSummaryRow>().single;

      expect(row.entry.title, 'Orthodox');
    });

    test('a custom title overrides even a single named fast', () {
      FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
        appearance: const FastingAppearance().withStyle(
          FastingTradition.orthodox,
          const FastingTraditionStyle(titleOverride: 'Post'),
        ),
      );
      final row = build(
        fastingSummaries: nativity(),
      ).whereType<AgendaFastingSummaryRow>().single;

      expect(row.entry.title, 'Post');
    });

    test('a contiguous fast reads as daily over an exact range', () {
      final row = build(
        fastingSummaries: nativity(),
      ).whereType<AgendaFastingSummaryRow>().single;

      expect(row.entry.subtitle, 'Daily · 40 days');
      expect(row.rangeLabel, 'Nov 15 – Dec 24');
    });

    test('a sparse practice names the weekdays it keeps', () {
      FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.wednesday, DateTime.friday},
          weekdayScope: FastingWeekdayScope.allFasts,
        ),
      );
      final row = build(
        fastingSummaries: summariesIn(
          DateTime.utc(2026, 11, 20),
          DateTime.utc(2026, 12, 5),
        ),
      ).whereType<AgendaFastingSummaryRow>().single;

      // Monday-first, joined with a comma - no conjunction, whose placement
      // would be locale-dependent.
      expect(row.entry.subtitle, startsWith('Wed, Fri · '));
      expect(row.entry.subtitle, endsWith(' · 5 days'));
    });

    test('a span past two months switches to a month range', () {
      // Exact dates stop being a shape somewhere around two months; beyond
      // that the month is the unit worth printing.
      final row = build(
        fastingSummaries: summariesIn(
          DateTime.utc(2026, 9, 1),
          DateTime.utc(2026, 12, 24),
        ),
      ).whereType<AgendaFastingSummaryRow>().single;

      expect(row.rangeLabel, 'Sep – Dec');
      expect(row.entry.subtitle, isNot(contains('Sep')));
      expect(row.entry.subtitle, isNot(contains('Dec 24')));
    });

    test('the card taps through to its first in-window day', () {
      final row = build(
        fastingSummaries: summariesIn(
          DateTime.utc(2026, 11, 20),
          DateTime.utc(2026, 12, 5),
        ),
      ).whereType<AgendaFastingSummaryRow>().single;

      expect(row.summary.first, DateTime.utc(2026, 11, 20));
    });

    test('no summaries leaves the per-run rows exactly as they were', () {
      final run = EventAgenda.fastingRunsInRange(
        from: DateTime.utc(2026, 11, 20),
        to: DateTime.utc(2026, 12, 5),
      ).single;

      final rows = build(fastingRuns: [run]);

      expect(rows.whereType<AgendaFastingSummaryRow>(), isEmpty);
      expect(rows.whereType<AgendaEntryRow>(), hasLength(1));
    });
  });

  group('holiday summary card', () {
    /// New Year and Christmas Day both resolve through the uninitialized
    /// fixed-date fallback, so no profile has to be configured here.
    final newYear = DateTime.utc(2026, 1, 1);
    final christmas = DateTime.utc(2026, 12, 25);

    List<AgendaRow> summaryBuild({
      List<EventOccurrence> occurrences = const [],
      List<DateTime> holidayDays = const [],
      List<FastingSummary> fastingSummaries = const [],
    }) {
      return build(
        occurrences: occurrences,
        holidayDays: holidayDays,
        fastingSummaries: fastingSummaries,
        holidayDisplay: AgendaHolidayDisplay.summary,
      );
    }

    test('every-day mode still interleaves one row per holiday', () {
      final rows = build(holidayDays: [newYear, christmas]);

      expect(rows.whereType<AgendaHolidaySummaryRow>(), isEmpty);
      expect(rows.whereType<AgendaDayHeaderRow>(), hasLength(2));
      expect(rows.whereType<AgendaEntryRow>(), hasLength(2));
    });

    test('summary mode replaces those rows with one card', () {
      final rows = summaryBuild(holidayDays: [newYear, christmas]);

      expect(rows, hasLength(1));
      expect(rows.single, isA<AgendaHolidaySummaryRow>());
      // The days left the walk entirely — no header, no entry row.
      expect(rows.whereType<AgendaDayHeaderRow>(), isEmpty);
      expect(rows.whereType<AgendaEntryRow>(), isEmpty);
    });

    test('the card leads the list and is not an entry', () {
      final rows = summaryBuild(
        occurrences: [EventOccurrence(event: untracked, day: day1)],
        holidayDays: [newYear, christmas],
      );

      expect(rows.first, isA<AgendaHolidaySummaryRow>());
      expect(rows[1], isA<AgendaDayHeaderRow>());
      // The event is the only entry; the card summarizes rather than being one.
      expect(rows.whereType<AgendaEntryRow>(), hasLength(1));
      expect(rows.whereType<AgendaDayHeaderRow>().single.count, 1);
    });

    test('it carries the count and the range it stands for', () {
      final row = summaryBuild(
        holidayDays: [newYear, christmas],
      ).whereType<AgendaHolidaySummaryRow>().single;

      expect(row.entry.title, 'Holidays');
      expect(row.entry.subtitle, '2 holidays');
      expect(row.rangeLabel, 'Jan 1 – Dec 25');
      // The card's days are the exact list its drill-down will show.
      expect(row.days, [newYear, christmas]);
    });

    test('no holidays in the window means no card', () {
      final rows = summaryBuild(
        occurrences: [EventOccurrence(event: untracked, day: day1)],
      );

      expect(rows.whereType<AgendaHolidaySummaryRow>(), isEmpty);
    });

    group('beside a fasting card', () {
      setUp(
        () =>
            FastingCalendar.configure(traditions: {FastingTradition.orthodox}),
      );
      tearDown(FastingCalendar.resetConfiguration);

      List<FastingSummary> nativity() => EventAgenda.fastingSummariesInRange(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 12, 24),
      );

      test('the holiday card leads by default', () {
        // Public holiday priority 150 against fasting's default placement 160,
        // matching the order the day panel already ranks them in.
        final rows = summaryBuild(
          holidayDays: [newYear],
          fastingSummaries: nativity(),
        );

        expect(rows[0], isA<AgendaHolidaySummaryRow>());
        expect(rows[1], isA<AgendaFastingSummaryRow>());
      });

      test('a tradition placed first outranks it', () {
        // The user's day-panel placement choice reaches the cards for free,
        // because they sort by the entry priority it already sets.
        FastingCalendar.configure(
          traditions: const {FastingTradition.orthodox},
          appearance: const FastingAppearance().withStyle(
            FastingTradition.orthodox,
            const FastingTraditionStyle(placement: FastingRowPlacement.first),
          ),
        );

        final rows = summaryBuild(
          holidayDays: [newYear],
          fastingSummaries: nativity(),
        );

        expect(rows[0], isA<AgendaFastingSummaryRow>());
        expect(rows[1], isA<AgendaHolidaySummaryRow>());
      });
    });
  });

  group('event summary cards', () {
    List<EventCategorySummary> summariesFor(List<EventOccurrence> occ) =>
        EventAgenda.categorySummariesOf(occ);

    /// `untracked` is a `mobility` event; `tracked` is `gym`.
    final mixed = [
      EventOccurrence(event: tracked, day: day1),
      EventOccurrence(event: untracked, day: day1),
      EventOccurrence(event: tracked, day: day2),
    ];

    test('one card per category, and none of them an entry', () {
      final rows = build(eventSummaries: summariesFor(mixed));

      final cards = rows.whereType<AgendaEventSummaryRow>().toList();
      expect(cards, hasLength(2));
      // The cards summarize entries rather than being them, so nothing counts
      // them — there are no day groups left at all here.
      expect(rows.whereType<AgendaEntryRow>(), isEmpty);
      expect(rows.whereType<AgendaDayHeaderRow>(), isEmpty);
    });

    test('the card counts distinct events, then occurrences', () {
      final rows = build(eventSummaries: summariesFor(mixed));
      final gym = rows.whereType<AgendaEventSummaryRow>().firstWhere(
        (r) => r.summary.categoryId == 'gym',
      );

      // One event across two days: "1 event · 2× in window", range on its
      // own line.
      expect(gym.entry.subtitle, startsWith('1 event · '));
      expect(gym.entry.subtitle, contains('2'));
      expect(gym.rangeLabel, AgendaListView.rangeLabel('en', day1, day2));
    });

    test('a category with no repeats omits the occurrence tally', () {
      // One event, one occurrence — repeating the number would say nothing.
      final rows = build(
        eventSummaries: summariesFor([
          EventOccurrence(event: untracked, day: day1),
        ]),
      );
      final card = rows.whereType<AgendaEventSummaryRow>().single;

      expect(card.entry.subtitle, '1 event');
      expect(card.entry.subtitle, isNot(contains('×')));
      expect(card.rangeLabel, AgendaListView.rangeLabel('en', day1, day1));
    });

    test('cards lead the list, above every header', () {
      // Holidays stay in the day walk here, so there is a header for the cards
      // to lead. Events and their summaries are mutually exclusive at the call
      // site — passing both would be the caller contradicting itself.
      final rows = build(
        holidayDays: [DateTime.utc(2026, 1, 1)],
        eventSummaries: summariesFor(mixed),
      );

      expect(rows.first, isA<AgendaEventSummaryRow>());
      expect(rows.whereType<AgendaDayHeaderRow>(), hasLength(1));
      // The header's one entry is the holiday, never a card.
      expect(rows.whereType<AgendaEntryRow>(), hasLength(1));
      expect(rows.indexWhere((r) => r is AgendaDayHeaderRow), greaterThan(1));
    });

    test('summary mode takes the occurrences out of the day walk', () {
      // The cards are a fold of the very same list, so leaving the rows in
      // would show every occurrence twice.
      final rows = build(
        occurrences: mixed,
        eventSummaries: summariesFor(mixed),
      );

      expect(rows.whereType<AgendaEventSummaryRow>(), hasLength(2));
      expect(rows.whereType<AgendaEntryRow>(), isEmpty);
      expect(rows.whereType<AgendaDayHeaderRow>(), isEmpty);
    });

    test('events outrank the holiday and fasting cards', () {
      final rows = build(
        holidayDays: [DateTime.utc(2026, 1, 1)],
        holidayDisplay: AgendaHolidayDisplay.summary,
        eventSummaries: summariesFor(mixed),
      );

      // Event band (0) before the public holiday (150) — the same order the
      // day panel ranks these in.
      expect(rows.first, isA<AgendaEventSummaryRow>());
      expect(rows.last, isA<AgendaHolidaySummaryRow>());
    });

    test('cards at equal priority keep a stable order across builds', () {
      // `List.sort` is not stable in Dart, and every category card shares the
      // event band — without an insertion-order tie-break the cards could
      // reshuffle between two builds of identical input.
      final summaries = summariesFor(mixed);
      List<String> orderOf() => build(eventSummaries: summaries)
          .whereType<AgendaEventSummaryRow>()
          .map((r) => r.summary.categoryId)
          .toList();

      final first = orderOf();
      for (var i = 0; i < 5; i++) {
        expect(orderOf(), first);
      }
      // And it is the scan's own order: gym occurs first in `mixed`.
      expect(first, ['gym', 'mobility']);
    });

    test('no summaries leaves the ordinary rows exactly as they were', () {
      final rows = build(occurrences: mixed);

      expect(rows.whereType<AgendaEventSummaryRow>(), isEmpty);
      expect(rows.whereType<AgendaEntryRow>(), hasLength(3));
    });

    /// The card and its drill-down fold the same occurrences twice, so the
    /// hidden-missed rule has to reach both: a card counting an occurrence the
    /// drill-down drops opens an empty sheet on a number it printed itself.
    group('hidden missed occurrences', () {
      /// `tracked` is the only `gym` event; its day2 occurrence is marked
      /// missed, day1 is attended.
      final gymOnly = [
        EventOccurrence(event: tracked, day: day1),
        EventOccurrence(event: tracked, day: day2),
      ];
      final missedOnly = [EventOccurrence(event: tracked, day: day2)];

      int drillDownLength(List<EventOccurrence> occ) {
        return AgendaListView.eventDayEntries(
          occ,
          l10n,
          (_, _) {},
          showRecurrenceLabels: true,
          missedDisplay: CalendarMissedDisplay.hidden,
        ).length;
      }

      test('the count drops exactly what the drill-down drops', () {
        final summary = EventAgenda.categorySummariesOf(
          gymOnly,
          hideMissed: true,
        ).single;

        expect(summary.categoryId, 'gym');
        expect(summary.occurrenceCount, 1);
        expect(summary.eventCount, 1);
        // The advertised range shrinks with it, so the card cannot name a day
        // its drill-down holds nothing for.
        expect(summary.first, day1);
        expect(summary.last, day1);
        expect(summary.occurrenceCount, drillDownLength(gymOnly));
      });

      test('a category left with nothing gets no card at all', () {
        final summaries = EventAgenda.categorySummariesOf(
          missedOnly,
          hideMissed: true,
        );

        expect(summaries, isEmpty);
        expect(drillDownLength(missedOnly), 0);
        expect(
          build(
            eventSummaries: summaries,
            missedDisplay: CalendarMissedDisplay.hidden,
          ).whereType<AgendaEventSummaryRow>(),
          isEmpty,
        );
      });

      test('faded still shows the card and still counts the miss', () {
        final summary = EventAgenda.categorySummariesOf(missedOnly).single;

        expect(summary.categoryId, 'gym');
        expect(summary.occurrenceCount, 1);
        final cards = build(
          eventSummaries: [summary],
        ).whereType<AgendaEventSummaryRow>();
        expect(cards.single.summary.categoryId, 'gym');
      });

      test('an untracked category is untouched by hiding', () {
        // Hiding narrows to the marks alone: `mobility` tracks no presence, so
        // no card of its can ever thin out.
        final summaries = EventAgenda.categorySummariesOf(
          mixed,
          hideMissed: true,
        );

        expect(summaries.map((s) => s.categoryId), ['gym', 'mobility']);
        for (final summary in summaries) {
          expect(summary.occurrenceCount, 1, reason: summary.categoryId);
        }
      });
    });
  });

  /// The summary card's drill-down converts the very same occurrences a second
  /// time, so it has to apply the very same presence rule — dropping it is
  /// what made a daily gym event read as attended every day of the month.
  group('eventDayEntries presence', () {
    List<AgendaDayListEntry> convert(CalendarMissedDisplay display) {
      return AgendaListView.eventDayEntries(
        occurrences,
        l10n,
        (_, _) {},
        showRecurrenceLabels: true,
        missedDisplay: display,
      );
    }

    test('faded keeps a missed occurrence and flags it', () {
      final entries = convert(CalendarMissedDisplay.faded);

      expect(entries, hasLength(3));
      final onDay2 = entries.where((entry) => entry.day == day2).single;
      expect(onDay2.title, 'Leg day');
      expect(onDay2.missed, isTrue);
      // The attended ones are not flagged, so nothing else dims.
      expect(
        entries.where((entry) => entry.day == day1).every((e) => !e.missed),
        isTrue,
      );
    });

    test('hidden drops it before it becomes a row', () {
      final entries = convert(CalendarMissedDisplay.hidden);

      expect(entries.map((entry) => entry.day), [day1, day1]);
      expect(entries.every((entry) => !entry.missed), isTrue);
    });

    test('an untracked event is never dropped or flagged', () {
      final entries = convert(CalendarMissedDisplay.hidden);

      expect(
        entries.map((entry) => entry.title),
        containsAll(<String>['Leg day', 'Mobility']),
      );
    });
  });
}
