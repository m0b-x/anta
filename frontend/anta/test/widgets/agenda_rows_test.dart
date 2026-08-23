import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
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
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) {
    return buildAgendaRows(
      occurrences: occurrences,
      holidayDays: holidayDays,
      fastingDays: fastingDays,
      fastingRuns: fastingRuns,
      fastingSummaries: fastingSummaries,
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

      expect(row.entry.subtitle, 'Daily · Nov 15 – Dec 24 · 40 days');
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

      expect(row.entry.subtitle, contains('Sep – Dec'));
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
}
