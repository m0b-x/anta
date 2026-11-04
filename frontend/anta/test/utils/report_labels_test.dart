import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/report_labels.dart';

/// The report's words about its numbers (D36): durations under an hour,
/// what "against …" names, the composed empty caption, and the counts the
/// review re-worded in German and Romanian.
void main() {
  setUpAll(initializeDateFormatting);

  ReportLabels labelsIn(String locale) =>
      ReportLabels(lookupAppLocalizations(Locale(locale)));

  final september = (
    start: DateTime.utc(2026, 9, 1),
    end: DateTime.utc(2026, 9, 30),
  );

  CalendarReport report({
    required DateRange span,
    required DateTime today,
    DateRange? previousSpan,
    DateRange? previousCounted,
    List<ReportTileValue> tiles = const [],
    int aheadCount = 0,
  }) => CalendarReport(
    span: span,
    today: today,
    tense: CalendarReport.tenseOf(span: span, today: today),
    countedTo: CalendarReport.countedToOf(span: span, today: today),
    previousSpan: previousSpan,
    previousCounted: previousCounted,
    events: const {},
    tiles: tiles,
    skippedDays: 0,
    aheadCount: aheadCount,
    categories: const [],
    missed: const [],
    ahead: const [],
  );

  group('durations (D36.5)', () {
    late ReportLabels labels;
    setUp(() => labels = labelsIn('en'));

    test('under an hour in minutes, from an hour in decimal hours', () {
      expect(labels.hours(40), '40 min');
      expect(labels.hours(60), '1 h');
      expect(labels.hours(90), '1.5 h');
    });

    test('an hours delta under an hour reads in minutes', () {
      expect(
        labels.delta(
          const ReportTileValue(
            tile: ReportTile.hours,
            value: 45,
            previous: 40,
          ),
        ),
        '+5 min',
      );
      expect(
        labels.delta(
          const ReportTileValue(
            tile: ReportTile.hours,
            value: 30,
            previous: 42,
          ),
        ),
        '−12 min',
      );
      expect(
        labels.tileValue(
          const ReportTileValue(tile: ReportTile.hours, value: 40),
        ),
        '40 min',
      );
    });
  });

  group('the comparison (D36.3)', () {
    late ReportLabels labels;
    setUp(() => labels = labelsIn('en'));

    test('the whole previous period is named by its own name', () {
      final past = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 11, 5),
        previousSpan: september,
        previousCounted: september,
      );
      expect(
        labels.comparisonName(
          past,
          previous: const OverviewMonthPeriod(2026, 9),
        ),
        'September 2026',
      );
    });

    test('a counted part is named by its span', () {
      final current = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 10, 15),
        previousSpan: september,
        previousCounted: (
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 15),
        ),
      );
      expect(
        labels.comparisonName(
          current,
          previous: const OverviewMonthPeriod(2026, 9),
        ),
        'Sep 1 – Sep 15, 2026',
      );
    });

    test('no previous period, no name', () {
      final first = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 11, 5),
      );
      expect(labels.comparisonName(first), isNull);
    });
  });

  group('copy (D36.4, the review)', () {
    test('the empty caption is composed after the period\'s name', () {
      final empty = report(
        span: (start: DateTime.utc(2025, 6, 1), end: DateTime.utc(2025, 6, 30)),
        today: DateTime.utc(2026, 10, 30),
      );
      expect(
        labelsIn('en').caption(empty, periodName: 'June 2025'),
        'June 2025${ReportLabels.separator}Nothing happened',
      );
      expect(
        labelsIn('de').caption(empty, periodName: 'Juni 2025'),
        'Juni 2025${ReportLabels.separator}Nichts passiert',
      );
      expect(
        labelsIn('ro').caption(empty, periodName: 'iunie 2025'),
        'iunie 2025${ReportLabels.separator}Nu s-a întâmplat nimic',
      );
    });

    test('German counts events as Termine, Romanian what is ahead in the '
        'neuter', () {
      final past = report(
        span: (start: DateTime.utc(2026, 9, 1), end: DateTime.utc(2026, 9, 30)),
        today: DateTime.utc(2026, 10, 30),
        tiles: const [ReportTileValue(tile: ReportTile.events, value: 3)],
      );
      expect(labelsIn('de').subtitle(past), '3 Termine');

      final current = report(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        today: DateTime.utc(2026, 10, 30),
        aheadCount: 1,
      );
      expect(
        labelsIn('ro').caption(current, periodName: 'octombrie 2026'),
        // The count is bound to its word with a no-break space.
        endsWith('1 rămas'),
      );
    });
  });

  group('spoken hours (the S3a review)', () {
    // 537 min draws "8.9 h", 123 "2 h", 1203 "20.1 h", 1202 "20 h": what is
    // heard is the figure drawn — the old tenths test said "9 hours" for
    // 537 — and a whole figure takes the plural grammar.
    for (final (locale, cases) in [
      (
        'en',
        {
          537: '8.9 hours',
          123: '2 hours',
          1203: '20.1 hours',
          1202: '20 hours',
          40: '40 minutes',
          60: '1 hour',
        },
      ),
      (
        'ro',
        {
          537: '8,9 ore',
          123: '2 ore',
          1203: '20,1 ore',
          1202: '20 de ore',
          40: '40 de minute',
          60: '1 oră',
        },
      ),
    ]) {
      test('$locale reads the figure it draws', () {
        final labels = labelsIn(locale);
        for (final MapEntry(key: minutes, value: spoken) in cases.entries) {
          expect(labels.hoursSpoken(minutes), spoken, reason: '$minutes min');
        }
      });
    }

    test('the drawn figures the spoken ones follow', () {
      final labels = labelsIn('en');
      expect(labels.hours(537), '8.9 h');
      expect(labels.hours(123), '2 h');
      expect(labels.hours(1203), '20.1 h');
      expect(labels.hours(1202), '20 h');
    });
  });

  group('group rows (the S3a review)', () {
    ReportRoutineRow routine(int attended, int total) => ReportRoutineRow(
      eventId: 'e',
      attended: attended,
      total: total,
      minutes: 0,
      latestDay: DateTime.utc(2026, 10, 8),
    );

    test('Romanian counts what was attended in its plural', () {
      final labels = labelsIn('ro');
      expect(labels.routineCaption(routine(5, 8)), '5 din 8 prezențe');
      expect(labels.routineCaption(routine(20, 25)), '20 din 25 de prezențe');
      expect(labels.routineCaption(routine(1, 1)), '1 din 1 prezență');
      expect(labelsIn('en').routineCaption(routine(8, 10)), '8 of 10 attended');
      expect(
        labelsIn('de').routineCaption(routine(8, 10)),
        '8 von 10 anwesend',
      );
    });

    final untimed = CalendarEvent(
      id: 'e',
      title: 'Groceries',
      categoryId: 'other',
      startDate: DateTime.utc(2026, 10, 8),
      rule: const OneTimeRecurrence(),
    );

    for (final (locale, day, dayMonth) in [
      ('en', 'Thu 8', 'Thu 8 Oct'),
      ('de', 'Do., 8.', 'Do., 8. Okt.'),
      ('ro', 'joi 8', 'joi 8 oct.'),
    ]) {
      test('$locale writes a row\'s day "$day", across months "$dayMonth"', () {
        final labels = labelsIn(locale);
        final row = ReportDatedRow(
          eventId: untimed.id,
          day: DateTime.utc(2026, 10, 8),
        );
        String subtitle({required bool spansMonths}) => labels.rowSubtitle(
          row,
          event: untimed,
          use24Hour: true,
          spansMonths: spansMonths,
        );
        expect(subtitle(spansMonths: false), day);
        expect(subtitle(spansMonths: true), dayMonth);
      });
    }

    test('a timed row\'s start follows the phone\'s clock', () {
      final timed = CalendarEvent(
        id: 'e',
        title: 'PT session',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 10, 8),
        rule: const OneTimeRecurrence(),
        time: const EventTime(startMinute: 17 * 60, durationMinutes: 40),
      );
      final row = ReportDatedRow(
        eventId: timed.id,
        day: DateTime.utc(2026, 10, 8),
      );
      final labels = labelsIn('en');
      expect(
        labels.rowSubtitle(
          row,
          event: timed,
          use24Hour: true,
          spansMonths: false,
        ),
        ['Thu 8', '17:00', '40 min'].join(ReportLabels.separator),
      );
      expect(
        labels.rowSubtitle(
          row,
          event: timed,
          use24Hour: false,
          spansMonths: false,
        ),
        allOf(contains('PM'), isNot(contains('17:00'))),
      );
    });
  });

  group('the design review (D44)', () {
    test('the Hours tile speaks hours, its value and its change', () {
      const grew = ReportTileValue(
        tile: ReportTile.hours,
        value: 45 * 60,
        previous: 42 * 60,
      );
      expect(
        labelsIn('en').tileSemantics(grew, against: 'September 2026'),
        'Hours, 45 hours, 3 hours more than September 2026',
      );
      expect(
        labelsIn('de').tileSemantics(grew, against: 'September 2026'),
        'Stunden, 45 Stunden, 3 Stunden mehr als September 2026',
      );
      const shrank = ReportTileValue(
        tile: ReportTile.hours,
        value: 90,
        previous: 120,
      );
      expect(
        labelsIn('en').tileSemantics(shrank, against: 'September 2026'),
        'Hours, 1.5 hours, 30 minutes less than September 2026',
      );
    });

    test('a count shrinks by "fewer", hours by "less"', () {
      final labels = labelsIn('en');
      for (final tile in [ReportTile.events, ReportTile.missed]) {
        expect(
          labels.tileSemantics(
            ReportTileValue(tile: tile, value: 4, previous: 10),
            against: 'September 2026',
          ),
          endsWith('6 fewer than September 2026'),
        );
      }
      expect(
        labels.tileSemantics(
          const ReportTileValue(
            tile: ReportTile.attended,
            value: 4,
            of: 5,
            previous: 10,
          ),
          against: 'September 2026',
        ),
        endsWith('6 fewer than September 2026'),
      );
      expect(
        labels.tileSemantics(
          const ReportTileValue(
            tile: ReportTile.tasks,
            value: 1,
            of: 3,
            previous: 3,
          ),
          against: 'September 2026',
        ),
        endsWith('2 fewer than September 2026'),
      );
    });

    test('de says "Termine" on the Events tile, as everywhere else', () {
      final labels = labelsIn('de');
      expect(labels.tileLabel(ReportTile.events), 'Termine');
      expect(labels.l10n.reportEventCount(2), '2 Termine');
    });

    test('a group whose facts are a bare count says its noun', () {
      const bare = ReportCategoryGroup(
        categoryId: 'other',
        count: 1,
        minutes: 0,
        missed: 0,
        rows: [],
      );
      expect(labelsIn('en').groupFacts(ReportCard.categories, bare), '1 event');
      expect(labelsIn('en').groupFacts(ReportCard.ahead, bare), '1 event');
      expect(labelsIn('de').groupFacts(ReportCard.ahead, bare), '1 Termin');
      const timed = ReportCategoryGroup(
        categoryId: 'gym',
        count: 14,
        minutes: 60,
        missed: 2,
        rows: [],
      );
      expect(
        labelsIn('en').groupFacts(ReportCard.categories, timed),
        ['14', '1 h', '2 missed'].join(ReportLabels.separator),
      );
    });
  });

  group('the S5a review (D46)', () {
    test('a tile and a group header group a count as the subtitle does', () {
      const events = ReportTileValue(tile: ReportTile.events, value: 1234);
      const attended = ReportTileValue(
        tile: ReportTile.attended,
        value: 1234,
        of: 2345,
      );
      const group = ReportCategoryGroup(
        categoryId: 'gym',
        count: 1234,
        minutes: 60,
        missed: 0,
        rows: [],
      );
      final en = labelsIn('en');
      expect(en.tileValue(events), '1,234');
      expect(en.tileValue(attended), '1,234 of 2,345');
      expect(en.tileValue(attended, ofInDetail: true), '1,234');
      expect(en.detail(attended, ofInDetail: true), startsWith('of 2,345'));
      expect(
        en.groupFacts(ReportCard.categories, group),
        ['1,234', '1 h'].join(ReportLabels.separator),
      );
      expect(
        en.subtitle(
          report(
            span: september,
            today: DateTime.utc(2026, 10, 30),
            tiles: const [events],
          ),
        ),
        startsWith('1,234 events'),
      );
      final de = labelsIn('de');
      expect(de.tileValue(events), '1.234');
      expect(
        de.groupFacts(ReportCard.categories, group),
        ['1.234', '1 Std.'].join(ReportLabels.separator),
      );
    });

    test('a count\'s change agrees with its number; hours keep the mass '
        'forms', () {
      String spoken(String locale, int value, int previous, ReportTile tile) =>
          labelsIn(locale).tileSemantics(
            ReportTileValue(tile: tile, value: value, previous: previous),
            against: 'X',
          );
      expect(spoken('en', 5, 4, ReportTile.events), endsWith('1 more than X'));
      expect(spoken('en', 6, 4, ReportTile.events), endsWith('2 more than X'));
      expect(spoken('en', 3, 4, ReportTile.missed), endsWith('1 fewer than X'));
      expect(spoken('en', 2, 4, ReportTile.missed), endsWith('2 fewer than X'));
      expect(
        spoken('ro', 5, 4, ReportTile.events),
        endsWith('cu 1 mai mult decât X'),
      );
      expect(
        spoken('ro', 6, 4, ReportTile.events),
        endsWith('cu 2 mai multe decât X'),
      );
      expect(
        spoken('ro', 3, 4, ReportTile.missed),
        endsWith('cu 1 mai puțin decât X'),
      );
      expect(
        spoken('ro', 2, 4, ReportTile.missed),
        endsWith('cu 2 mai puține decât X'),
      );
      expect(
        spoken('ro', 4, 24, ReportTile.missed),
        endsWith('cu 20 mai puține decât X'),
      );
      expect(
        spoken('ro', 120, 60, ReportTile.hours),
        endsWith('cu 1 oră mai mult decât X'),
      );
    });
  });

  // S4a: the words of the Goals, Insights and Due soon cards and the
  // touches to the existing ones. 4 November 2026 is a Wednesday; its week
  // runs Monday 2 to Sunday 8.
  const nb = ' ';
  const sep = ReportLabels.separator;
  final today = DateTime.utc(2026, 11, 4);
  final thisWeek = (
    start: DateTime.utc(2026, 11, 2),
    end: DateTime.utc(2026, 11, 8),
  );
  final lastWeek = (
    start: DateTime.utc(2026, 10, 26),
    end: DateTime.utc(2026, 11, 1),
  );
  final november = (
    start: DateTime.utc(2026, 11, 1),
    end: DateTime.utc(2026, 11, 30),
  );
  const someGroup = ReportCategoryGroup(
    categoryId: 'gym',
    count: 1,
    minutes: 0,
    missed: 0,
    rows: [],
  );

  CalendarReport analytics({
    DateRange? span,
    List<ReportGoal> goals = const [],
    List<ReportTileValue> tiles = const [],
    Map<String, CalendarEvent> events = const {},
    List<ReportTag> tags = const [],
    int workingDays = 0,
    int publicHolidays = 0,
    int nominalMinutes = 0,
    DateTime? on,
  }) {
    final shown = span ?? thisWeek;
    final day = on ?? today;
    return CalendarReport(
      span: shown,
      today: day,
      tense: CalendarReport.tenseOf(span: shown, today: day),
      countedTo: CalendarReport.countedToOf(span: shown, today: day),
      events: events,
      tiles: tiles,
      skippedDays: 0,
      aheadCount: 0,
      categories: const [someGroup],
      missed: const [],
      ahead: const [],
      goals: goals,
      tags: tags,
      workingDays: workingDays,
      publicHolidays: publicHolidays,
      nominalMinutes: nominalMinutes,
    );
  }

  ReportGoalPeriod period(DateRange range, int value, GoalState state) =>
      ReportGoalPeriod(
        start: range.start,
        end: range.end,
        value: value,
        expected: 0,
        state: state,
      );

  ReportGoal atLeast(
    List<ReportGoalPeriod> periods, {
    int target = 3,
    TargetPeriod per = TargetPeriod.week,
    int streak = 0,
  }) => ReportGoal(
    categoryId: 'gym',
    measure: ReportMeasure.count,
    target: ReportTarget(kind: TargetKind.atLeast, value: target, period: per),
    periods: periods,
    streak: streak,
  );

  ReportGoal atMostHours(List<ReportGoalPeriod> periods) => ReportGoal(
    categoryId: 'work',
    measure: ReportMeasure.hours,
    target: const ReportTarget(
      kind: TargetKind.atMost,
      value: 40 * 60,
      period: TargetPeriod.week,
    ),
    periods: periods,
  );

  ReportGoal maxGap(ReportGapState? gap) => ReportGoal(
    categoryId: 'car',
    measure: ReportMeasure.lastSeen,
    target: const ReportTarget(kind: TargetKind.maxGap, value: 14),
    gap: gap,
  );

  group('goal captions (§2.2)', () {
    late final en = labelsIn('en');

    test('an at-least goal still open says what is left by the period end', () {
      final goal = atLeast([period(thisWeek, 2, GoalState.onPace)]);
      expect(
        en.goalCaption(goal, analytics()),
        '2${nb}of${nb}3${sep}one more by Sunday',
      );
      expect(
        en.goalCaption(
          atLeast([period(thisWeek, 1, GoalState.behind)]),
          analytics(),
        ),
        '1${nb}of${nb}3${sep}2${nb}more by Sunday',
      );
    });

    test('a day goal says today; a met one is done for its period', () {
      final day = (start: today, end: today);
      expect(
        en.goalCaption(
          atLeast(
            [period(day, 0, GoalState.notDue)],
            target: 1,
            per: TargetPeriod.day,
          ),
          analytics(span: day),
        ),
        '0${nb}of${nb}1${sep}one more today',
      );
      expect(
        en.goalCaption(
          atLeast([period(thisWeek, 3, GoalState.met)]),
          analytics(),
        ),
        '3${nb}of${nb}3${sep}done for the week',
      );
    });

    test('the streak is the last segment (B)', () {
      final goal = atLeast([period(thisWeek, 2, GoalState.onPace)], streak: 4);
      expect(
        en.goalCaption(goal, analytics()),
        endsWith('${sep}4${nb}in a row'),
      );
      expect(
        en.goalSpoken('Gym', goal, analytics()),
        'Gym, 2 of 3, one more by Sunday, on pace, 4 weeks in a row',
      );
      expect(
        en.goalCaption(maxGap(null), analytics()),
        isNot(contains('in a row')),
      );
    });

    test('an at-most goal says what is left, its period only when the span '
        'is another unit (E)', () {
      final week = atMostHours([period(thisWeek, 31 * 60, GoalState.onPace)]);
      expect(
        en.goalCaption(week, analytics()),
        '31${nb}h of${nb}40${sep}9${nb}h left',
      );
      // A month report reads the week holding today (F).
      final month = atMostHours([
        period(lastWeek, 50 * 60, GoalState.over),
        period(thisWeek, 31 * 60, GoalState.onPace),
        period(
          (start: DateTime.utc(2026, 11, 9), end: DateTime.utc(2026, 11, 15)),
          0,
          GoalState.future,
        ),
      ]);
      expect(
        en.goalCaption(month, analytics(span: november)),
        '31${nb}h of${nb}40${sep}9${nb}h left this week',
      );
      expect(
        ReportLabels.goalPeriod(month, analytics(span: november))!.start,
        thisWeek.start,
      );
    });

    test('over a limit says by how much, in hours and in money', () {
      expect(
        en.goalCaption(
          atMostHours([period(thisWeek, 44 * 60, GoalState.over)]),
          analytics(),
        ),
        '44${nb}h of${nb}40${sep}4${nb}h over',
      );
      final budget = ReportGoal(
        categoryId: 'groceries',
        measure: ReportMeasure.money,
        target: const ReportTarget(
          kind: TargetKind.budget,
          value: 120000,
          period: TargetPeriod.week,
        ),
        periods: [period(thisWeek, 134000, GoalState.over)],
      );
      expect(
        ReportLabels(
          lookupAppLocalizations(const Locale('en')),
          currencySymbol: '€',
        ).goalCaption(budget, analytics()),
        '€1,340${nb}of${nb}1,200${sep}140${nb}over',
      );
      expect(
        labelsIn('en').goalCaption(budget, analytics()),
        startsWith('1,340'),
      );
      // Whole units, rounded, grouped by the locale; a suffix symbol bound.
      final lei = ReportLabels(
        lookupAppLocalizations(const Locale('ro')),
        currencySymbol: 'lei',
        currencySuffix: true,
      );
      expect(lei.money(134050), '1.341${nb}lei');
      expect(
        lei.goalCaption(budget, analytics()),
        '1.340${nb}lei din${nb}1.200${sep}depășit cu${nb}140',
      );
      expect(labelsIn('de').money(-1234500), '-12.345');
    });

    test('a gap goal says the days since, none yet, or over a year', () {
      expect(
        en.goalCaption(
          maxGap(
            const ReportGapState(
              daysSince: 23,
              limit: 14,
              state: GapState.overdue,
            ),
          ),
          analytics(),
        ),
        '23${nb}days${sep}limit${nb}14',
      );
      expect(
        en.goalCaption(maxGap(null), analytics()),
        'None yet${sep}limit${nb}14',
      );
      expect(
        en.goalCaption(
          maxGap(
            const ReportGapState(
              daysSince: 366,
              limit: 14,
              state: GapState.overdue,
              beyondLookback: true,
            ),
          ),
          analytics(),
        ),
        'Over a year${sep}limit${nb}14',
      );
    });

    test('a closed period says one word (K)', () {
      final past = analytics(span: lastWeek);
      expect(
        en.goalCaption(atLeast([period(lastWeek, 3, GoalState.met)]), past),
        '3${nb}of${nb}3${sep}Met',
      );
      expect(
        en.goalCaption(atLeast([period(lastWeek, 2, GoalState.missed)]), past),
        '2${nb}of${nb}3${sep}Missed',
      );
      expect(
        en.goalCaption(
          atMostHours([period(lastWeek, 38 * 60, GoalState.met)]),
          past,
        ),
        '38${nb}h of${nb}40${sep}Within',
      );
      expect(
        en.goalCaption(
          atMostHours([period(lastWeek, 44 * 60, GoalState.over)]),
          past,
        ),
        '44${nb}h of${nb}40${sep}Over',
      );
    });

    test('a past span of several periods counts the periods met (F)', () {
      final october = (
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 31),
      );
      DateRange week(int day) => (
        start: DateTime.utc(2026, 10, day),
        end: DateTime.utc(2026, 10, day + 6),
      );
      final goal = atLeast([
        period(week(5), 3, GoalState.met),
        period(week(12), 3, GoalState.met),
        period(week(19), 1, GoalState.missed),
        period(week(26), 4, GoalState.met),
      ]);
      final report = analytics(span: october);
      expect(en.goalCaption(goal, report), '3${nb}of${nb}4${nb}weeks met');
      expect(en.goalStateWord(goal, report), 'missed');
      expect(
        labelsIn('de').goalCaption(goal, report),
        '3${nb}von${nb}4${nb}Wochen erreicht',
      );
      expect(
        labelsIn('ro').goalCaption(goal, report),
        'atins în${nb}3${nb}din${nb}4${nb}săptămâni',
      );
    });

    test('a plan says what is planned', () {
      final next = (
        start: DateTime.utc(2026, 11, 9),
        end: DateTime.utc(2026, 11, 15),
      );
      final goal = atLeast([period(next, 2, GoalState.future)]);
      final plan = analytics(span: next);
      expect(en.goalCaption(goal, plan), '2${nb}of${nb}3${nb}planned');
      expect(en.goalStateWord(goal, plan), 'planned');
    });

    test('a past span reads an open period as current: the closed word '
        'needs a closed period (the review\'s probe)', () {
      // 12 November: the past week of 2–8 November under a monthly goal
      // whose month runs on.
      final monthly = atLeast(
        [period(november, 3, GoalState.onPace)],
        target: 8,
        per: TargetPeriod.month,
      );
      final past = analytics(span: thisWeek, on: DateTime.utc(2026, 11, 12));
      expect(past.tense, ReportTense.past);
      expect(ReportLabels.goalPeriod(monthly, past)!.start, november.start);
      expect(ReportLabels.closedPeriods(monthly, past), isEmpty);
      expect(
        en.goalCaption(monthly, past),
        '3${nb}of${nb}8${sep}5${nb}more by Nov${nb}30',
      );
      expect(en.goalStateWord(monthly, past), 'on pace');
      expect(
        en.goalSpoken('Gym', monthly, past),
        'Gym, 3 of 8, 5 more by Nov 30, on pace',
      );
    });

    test('a past month whose last week runs into today counts only the '
        'closed weeks', () {
      // 1 November is a Sunday: October is past, its last week is not.
      DateRange week(int day) => (
        start: DateTime.utc(2026, 10, day),
        end: DateTime.utc(2026, 10, day + 6),
      );
      final october = analytics(
        span: (
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        on: DateTime.utc(2026, 11, 1),
      );
      final allMet = atLeast([
        period(week(5), 3, GoalState.met),
        period(week(12), 3, GoalState.met),
        period(week(19), 4, GoalState.met),
        period(week(26), 1, GoalState.behind),
      ]);
      expect(ReportLabels.closedPeriods(allMet, october).map((p) => p.start), [
        week(5).start,
        week(12).start,
        week(19).start,
      ]);
      expect(ReportLabels.goalPeriod(allMet, october)!.start, week(19).start);
      expect(en.goalCaption(allMet, october), '3${nb}of${nb}3${nb}weeks met');
      // The open week's "behind" is not the month's word.
      expect(en.goalStateWord(allMet, october), 'met');
      final lastOpen = atLeast([
        period(week(5), 3, GoalState.met),
        period(week(12), 1, GoalState.missed),
        period(week(19), 3, GoalState.met),
        period(week(26), 2, GoalState.onPace),
      ], streak: 1);
      expect(
        en.goalCaption(lastOpen, october),
        '2${nb}of${nb}3${nb}weeks met${sep}1${nb}in a row',
      );
      expect(en.goalStateWord(lastOpen, october), 'missed');
      expect(
        en.goalSpoken('Gym', lastOpen, october),
        'Gym, 2 of 3 weeks met, 1 week in a row',
      );
    });

    test('the spoken label leaves out a state the caption already says', () {
      final past = analytics(span: lastWeek);
      expect(
        en.goalSpoken(
          'Gym',
          atLeast([period(lastWeek, 3, GoalState.met)], streak: 4),
          past,
        ),
        'Gym, 3 of 3, Met, 4 weeks in a row',
      );
      expect(
        en.goalSpoken(
          'Gym',
          atLeast([period(lastWeek, 2, GoalState.missed)]),
          past,
        ),
        'Gym, 2 of 3, Missed',
      );
      expect(
        en.goalSpoken(
          'Work',
          atMostHours([period(lastWeek, 38 * 60, GoalState.met)]),
          past,
        ),
        'Work, 38 h of 40, Within',
      );
      expect(
        labelsIn('de').goalSpoken(
          'Sport',
          atLeast([period(lastWeek, 3, GoalState.met)]),
          past,
        ),
        'Sport, 3 von 3, Erreicht',
      );
      // An open period's caption says no state word, so it is heard.
      expect(
        en.goalSpoken(
          'Gym',
          atLeast([period(thisWeek, 3, GoalState.met)]),
          analytics(),
        ),
        'Gym, 3 of 3, done for the week, met',
      );
    });

    test('de and ro spot-check the open shapes', () {
      final goal = atLeast([period(thisWeek, 2, GoalState.onPace)]);
      expect(
        labelsIn('de').goalCaption(goal, analytics()),
        '2${nb}von${nb}3${sep}noch${nb}1${nb}bis Sonntag',
      );
      expect(
        labelsIn('ro').goalCaption(goal, analytics()),
        '2${nb}din${nb}3$sepîncă${nb}1${nb}până la duminică',
      );
      final hours = atMostHours([period(thisWeek, 31 * 60, GoalState.onPace)]);
      expect(
        labelsIn('de').goalCaption(hours, analytics()),
        '31${nb}Std. von${nb}40${sep}9${nb}Std. übrig',
      );
      expect(
        labelsIn('ro').goalCaption(hours, analytics()),
        '31${nb}h din${nb}40${sep}rămân${nb}9${nb}h',
      );
    });

    test('no figure in a caption sits beside a breaking space (W)', () {
      // The separator's own space is a break on purpose, after its dot.
      final digitBesideSpace = RegExp(r'\d | \d');
      Matcher bound() => isNot(
        predicate<String>(
          (text) => digitBesideSpace.hasMatch(text.replaceAll(sep, '|')),
        ),
      );
      for (final locale in ['en', 'de', 'ro']) {
        final labels = labelsIn(locale);
        for (final goal in [
          atLeast([period(thisWeek, 1, GoalState.behind)], streak: 12),
          atMostHours([period(thisWeek, 44 * 60, GoalState.over)]),
          maxGap(
            const ReportGapState(
              daysSince: 23,
              limit: 14,
              state: GapState.overdue,
            ),
          ),
        ]) {
          expect(
            labels.goalCaption(goal, analytics()),
            bound(),
            reason: locale,
          );
          for (final template in labels.goalTemplates(goal, analytics())) {
            expect(template, bound(), reason: locale);
          }
        }
      }
    });
  });

  group('goal state words', () {
    late final en = labelsIn('en');

    test('each state has its spoken word', () {
      for (final (state, word) in [
        (GoalState.met, 'met'),
        (GoalState.onPace, 'on pace'),
        (GoalState.behind, 'behind'),
        (GoalState.over, 'over'),
        (GoalState.notDue, 'not started'),
      ]) {
        expect(
          en.goalStateWord(atLeast([period(thisWeek, 1, state)]), analytics()),
          word,
        );
      }
      expect(
        en.goalStateWord(
          atLeast([period(lastWeek, 1, GoalState.missed)]),
          analytics(span: lastWeek),
        ),
        'missed',
      );
      for (final (state, word) in [
        (GapState.within, 'within the limit'),
        (GapState.due, 'due soon'),
        (GapState.overdue, 'past the limit'),
      ]) {
        expect(
          en.goalStateWord(
            maxGap(ReportGapState(daysSince: 5, limit: 14, state: state)),
            analytics(),
          ),
          word,
        );
      }
      expect(
        labelsIn('de').goalStateWord(maxGap(null), analytics()),
        'nicht begonnen',
      );
      expect(
        labelsIn('ro').goalStateWord(
          atLeast([period(thisWeek, 1, GoalState.onPace)]),
          analytics(),
        ),
        'în ritm',
      );
    });

    test('the spoken streak follows its plural', () {
      ReportGoal streak(int n) =>
          atLeast([period(thisWeek, 2, GoalState.onPace)], streak: n);
      expect(
        en.goalSpoken('Gym', streak(1), analytics()),
        endsWith('1 week in a row'),
      );
      expect(
        labelsIn('de').goalSpoken('Gym', streak(5), analytics()),
        endsWith('5 Wochen in Folge'),
      );
      final ro = labelsIn('ro');
      expect(
        ro.goalSpoken('Sală', streak(1), analytics()),
        endsWith('1 săptămână la rând'),
      );
      expect(
        ro.goalSpoken('Sală', streak(5), analytics()),
        endsWith('5 săptămâni la rând'),
      );
      expect(
        ro.goalSpoken('Sală', streak(20), analytics()),
        endsWith('20 de săptămâni la rând'),
      );
    });
  });

  group('goal templates in 8s (D)', () {
    final streak = '$sep${ReportMetrics.goalTemplateStreak}${nb}in a row';

    test('an open at-least goal: its pace, "one more" among it, and done, '
        'one digit more when met', () {
      final templates = labelsIn('en').goalTemplates(
        atLeast([period(thisWeek, 0, GoalState.notDue)]),
        analytics(),
      );
      expect(templates, [
        '8${nb}of${nb}8${sep}8${nb}more by Sunday$streak',
        '8${nb}of${nb}8${sep}one more by Sunday$streak',
        '88${nb}of${nb}8${sep}done for the week$streak',
      ]);
      expect(
        labelsIn('en').goalTemplates(
          atLeast(
            [period((start: today, end: today), 0, GoalState.notDue)],
            target: 1,
            per: TargetPeriod.day,
          ),
          analytics(span: (start: today, end: today)),
        ),
        contains('8${nb}of${nb}8${sep}one more today$streak'),
      );
    });

    test('the set narrows to the reading: closed, periods met, planned', () {
      final en = labelsIn('en');
      expect(
        en.goalTemplates(
          atLeast([period(lastWeek, 3, GoalState.met)]),
          analytics(span: lastWeek),
        ),
        [
          '88${nb}of${nb}8${sep}Met$streak',
          '8${nb}of${nb}8${sep}Missed$streak',
        ],
      );
      expect(
        en.goalTemplates(
          atMostHours([period(lastWeek, 44 * 60, GoalState.over)]),
          analytics(span: lastWeek),
        ),
        [
          '88.8${nb}h of${nb}88.8${sep}Within$streak',
          '888.8${nb}h of${nb}88.8${sep}Over$streak',
        ],
      );
      DateRange week(int day) => (
        start: DateTime.utc(2026, 10, day),
        end: DateTime.utc(2026, 10, day + 6),
      );
      expect(
        en.goalTemplates(
          atLeast([
            period(week(5), 3, GoalState.met),
            period(week(12), 3, GoalState.met),
          ]),
          analytics(
            span: (
              start: DateTime.utc(2026, 10, 1),
              end: DateTime.utc(2026, 10, 31),
            ),
          ),
        ),
        ['88${nb}of${nb}88${nb}weeks met$streak'],
      );
      final next = (
        start: DateTime.utc(2026, 11, 9),
        end: DateTime.utc(2026, 11, 15),
      );
      expect(
        en.goalTemplates(
          atLeast([period(next, 2, GoalState.future)]),
          analytics(span: next),
        ),
        ['88${nb}of${nb}8${nb}planned$streak'],
      );
      // The review's probe: an open period in a past span reads its pace.
      expect(
        en.goalTemplates(
          atLeast(
            [period(november, 3, GoalState.onPace)],
            target: 8,
            per: TargetPeriod.month,
          ),
          analytics(span: thisWeek, on: DateTime.utc(2026, 11, 12)),
        ),
        hasLength(3),
      );
    });

    test('a day goal in a long span counts its streak and its days in '
        'three digits', () {
      final year = (
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 12, 31),
      );
      final daily = atLeast(
        [period((start: today, end: today), 0, GoalState.notDue)],
        target: 1,
        per: TargetPeriod.day,
      );
      expect(
        labelsIn('en').goalTemplates(daily, analytics(span: year)),
        everyElement(endsWith('${sep}888${nb}in a row')),
      );
      final lastYear = (
        start: DateTime.utc(2025, 1, 1),
        end: DateTime.utc(2025, 12, 31),
      );
      expect(
        labelsIn('en').goalTemplates(
          atLeast(
            [
              period(
                (
                  start: DateTime.utc(2025, 1, 1),
                  end: DateTime.utc(2025, 1, 1),
                ),
                1,
                GoalState.met,
              ),
              period(
                (
                  start: DateTime.utc(2025, 1, 2),
                  end: DateTime.utc(2025, 1, 2),
                ),
                0,
                GoalState.missed,
              ),
            ],
            target: 1,
            per: TargetPeriod.day,
          ),
          analytics(span: lastYear),
        ),
        ['888${nb}of${nb}888${nb}days met${sep}888${nb}in a row'],
      );
      // A week's day goal keeps two.
      expect(
        labelsIn('en').goalTemplates(daily, analytics()),
        everyElement(endsWith(streak)),
      );
    });

    test('hours carry the locale decimal; a month ends on its date', () {
      final goal = ReportGoal(
        categoryId: 'work',
        measure: ReportMeasure.hours,
        target: const ReportTarget(
          kind: TargetKind.atMost,
          value: 160 * 60,
          period: TargetPeriod.month,
        ),
        periods: [period(november, 0, GoalState.notDue)],
      );
      final en = labelsIn('en').goalTemplates(goal, analytics(span: november));
      expect(
        en[0],
        startsWith('888.8${nb}h of${nb}888.8${sep}888.8${nb}h left'),
      );
      expect(
        en[1],
        startsWith('8888.8${nb}h of${nb}888.8${sep}8888.8${nb}h over'),
      );
      final de = labelsIn('de').goalTemplates(goal, analytics(span: november));
      expect(de.first, startsWith('888,8${nb}Std. von${nb}888,8'));
      final monthly = atLeast([
        period(november, 0, GoalState.notDue),
      ], per: TargetPeriod.month);
      expect(
        labelsIn('en').goalTemplates(monthly, analytics(span: november)).first,
        contains('more by Nov${nb}30'),
      );
    });

    test('a gap goal templates its three readings, with no streak', () {
      expect(labelsIn('en').goalTemplates(maxGap(null), analytics()), [
        '888${nb}days${sep}limit${nb}88',
        'None yet${sep}limit${nb}88',
        'Over a year${sep}limit${nb}88',
      ]);
    });

    testWidgets('the real caption is never wider than the widest template', (
      tester,
    ) async {
      double width(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: const TextStyle(fontSize: 13)),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = painter.width;
        painter.dispose();
        return w;
      }

      DateRange week(int day) => (
        start: DateTime.utc(2026, 10, day),
        end: DateTime.utc(2026, 10, day + 6),
      );
      final october = (
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 31),
      );
      final next = (
        start: DateTime.utc(2026, 11, 9),
        end: DateTime.utc(2026, 11, 15),
      );
      final day = (start: today, end: today);
      final year = (
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 12, 31),
      );
      ReportGoal budget(int cents, GoalState state) => ReportGoal(
        categoryId: 'groceries',
        measure: ReportMeasure.money,
        target: const ReportTarget(
          kind: TargetKind.budget,
          value: 120000,
          period: TargetPeriod.week,
        ),
        periods: [period(thisWeek, cents, state)],
      );
      final cases = <(ReportGoal, CalendarReport)>[
        for (final (value, state) in [
          (0, GoalState.notDue),
          (1, GoalState.behind),
          (2, GoalState.onPace),
          (3, GoalState.met),
          (9, GoalState.met),
        ])
          for (final streak in [0, 1, 12, 52])
            (
              atLeast([period(thisWeek, value, state)], streak: streak),
              analytics(),
            ),
        for (final (value, state) in [
          (0, GoalState.notDue),
          (1, GoalState.met),
        ])
          (
            atLeast(
              [period(day, value, state)],
              target: 1,
              per: TargetPeriod.day,
              streak: 31,
            ),
            analytics(span: day),
          ),
        (
          atLeast(
            [period(day, 0, GoalState.notDue)],
            target: 1,
            per: TargetPeriod.day,
            streak: 120,
          ),
          analytics(span: year),
        ),
        for (final (minutes, state) in [
          (0, GoalState.notDue),
          (31 * 60 + 30, GoalState.onPace),
          (39 * 60, GoalState.behind),
          (44 * 60, GoalState.over),
          (99 * 60, GoalState.over),
        ])
          (atMostHours([period(thisWeek, minutes, state)]), analytics()),
        (
          atMostHours([
            period(lastWeek, 50 * 60, GoalState.over),
            period(thisWeek, 31 * 60, GoalState.onPace),
          ]),
          analytics(span: november),
        ),
        (budget(95000, GoalState.onPace), analytics()),
        (budget(134000, GoalState.over), analytics()),
        for (final (value, state) in [
          (3, GoalState.met),
          (12, GoalState.met),
          (2, GoalState.missed),
        ])
          (
            atLeast([period(lastWeek, value, state)], streak: 9),
            analytics(span: lastWeek),
          ),
        for (final (minutes, state) in [
          (38 * 60, GoalState.met),
          (44 * 60, GoalState.over),
        ])
          (
            atMostHours([period(lastWeek, minutes, state)]),
            analytics(span: lastWeek),
          ),
        (
          atLeast([
            period(week(5), 3, GoalState.met),
            period(week(12), 1, GoalState.missed),
            period(week(19), 3, GoalState.met),
            period(week(26), 4, GoalState.met),
          ], streak: 2),
          analytics(span: october),
        ),
        (
          atLeast(
            [period(november, 3, GoalState.onPace)],
            target: 8,
            per: TargetPeriod.month,
          ),
          analytics(span: thisWeek, on: DateTime.utc(2026, 11, 12)),
        ),
        (
          atLeast([period(next, 2, GoalState.future)], streak: 4),
          analytics(span: next),
        ),
        for (final gap in [
          null,
          const ReportGapState(daysSince: 1, limit: 14, state: GapState.within),
          const ReportGapState(
            daysSince: 23,
            limit: 14,
            state: GapState.overdue,
          ),
          const ReportGapState(
            daysSince: 366,
            limit: 14,
            state: GapState.overdue,
            beyondLookback: true,
          ),
        ])
          (maxGap(gap), analytics()),
      ];
      for (final locale in ['en', 'de', 'ro']) {
        final labels = labelsIn(locale);
        for (final (goal, report) in cases) {
          final caption = labels.goalCaption(goal, report);
          final widest = labels
              .goalTemplates(goal, report)
              .map(width)
              .reduce(math.max);
          expect(
            width(caption),
            lessThanOrEqualTo(widest),
            reason: '$locale: $caption',
          );
        }
      }
    });
  });

  group('insights (§6.7)', () {
    late final en = labelsIn('en');
    const weekStart = CalendarWeekStart.monday;
    final trip = CalendarEvent(
      id: 'trip',
      title: 'Sibiu',
      categoryId: 'travel',
      startDate: DateTime.utc(2026, 11, 16),
      rule: const OneTimeRecurrence(),
    );
    final report = analytics(
      goals: [
        atLeast([period(thisWeek, 1, GoalState.behind)]),
        atMostHours([period(thisWeek, 44 * 60, GoalState.over)]),
      ],
      events: {trip.id: trip},
      tags: const [
        ReportTag(
          key: 'ana',
          label: 'Ana',
          events: 1,
          count: 1,
          minutes: 0,
          categoryIds: ['friends'],
          rows: [],
        ),
      ],
    );
    String detail(ReportInsight insight, {ReportLabels? labels}) =>
        (labels ?? en).insightDetail(
          insight,
          report,
          category: 'Gym',
          weekStart: weekStart,
        );

    test('the severity words (J)', () {
      expect(
        [
          for (final s in [3, 2, 1, 0]) en.insightSeverityWord(s),
        ],
        ['Needs attention', 'Worth a look', 'Worth knowing', 'For information'],
      );
      expect(labelsIn('de').insightSeverityWord(1), 'Gut zu wissen');
      expect(labelsIn('ro').insightSeverityWord(3), 'Necesită atenție');
    });

    test('the goal rules read the goal they are about', () {
      expect(
        detail(
          ReportInsight(
            rule: InsightRule.g1,
            severity: 3,
            categoryId: 'gym',
            target: InsightTarget.categoryGroup,
            day: thisWeek.start,
            dayEnd: thisWeek.end,
            n1: 1,
            n2: 3,
            n3: 2,
          ),
        ),
        '1${nb}of${nb}3, 2${nb}more by Sunday',
      );
      expect(
        detail(
          ReportInsight(
            rule: InsightRule.g2,
            severity: 2,
            categoryId: 'work',
            target: InsightTarget.categoryGroup,
            day: thisWeek.start,
            dayEnd: thisWeek.end,
            n1: 44 * 60,
            n2: 40 * 60,
            n3: 4 * 60,
          ),
        ),
        '44${nb}h of${nb}40${nb}this week, 4${nb}h over',
      );
      expect(
        detail(
          const ReportInsight(
            rule: InsightRule.g4,
            severity: 2,
            categoryId: 'gym',
            target: InsightTarget.categoryGroup,
            n1: 8,
          ),
        ),
        '8${nb}weeks in a row',
      );
      expect(
        detail(
          const ReportInsight(
            rule: InsightRule.g4,
            severity: 1,
            categoryId: 'gym',
            target: InsightTarget.categoryGroup,
            n1: 5,
            alternate: true,
          ),
        ),
        'the${nb}5-week streak ended',
      );
    });

    test('D1 says the days or over a year; the spoken form leads with the '
        'severity', () {
      const overdue = ReportInsight(
        rule: InsightRule.d1,
        severity: 3,
        categoryId: 'car',
        target: InsightTarget.dueSoon,
        n1: 212,
        n2: 180,
      );
      expect(
        detail(overdue),
        '212${nb}days since the last, the limit is${nb}180',
      );
      expect(
        detail(
          const ReportInsight(
            rule: InsightRule.d1,
            severity: 3,
            categoryId: 'car',
            target: InsightTarget.dueSoon,
            n1: 366,
            n2: 180,
            beyondLookback: true,
          ),
        ),
        'over a year since the last, the limit is${nb}180',
      );
      expect(
        en.insightSpoken(
          overdue,
          report,
          category: 'Car service',
          weekStart: weekStart,
        ),
        'Needs attention. Car service, '
        '212${nb}days since the last, the limit is${nb}180',
      );
      expect(
        detail(overdue, labels: labelsIn('de')),
        '212${nb}Tage seit dem letzten Mal, das Limit ist${nb}180',
      );
      final ro = labelsIn('ro');
      String roDays(int n) => detail(
        ReportInsight(
          rule: InsightRule.d1,
          severity: 3,
          target: InsightTarget.dueSoon,
          n1: n,
          n2: 180,
        ),
        labels: ro,
      );
      expect(roDays(1), startsWith('1${nb}zi de la'));
      expect(roDays(5), startsWith('5${nb}zile de la'));
      expect(roDays(212), startsWith('212${nb}zile de la'));
      expect(roDays(220), startsWith('220${nb}de zile de la'));
    });

    test('the subject is the category, the tag as typed or the rule noun', () {
      String subject(InsightRule rule) => en.insightSubject(
        ReportInsight(
          rule: rule,
          severity: 0,
          categoryId: 'friends',
          tagKey: 'ana',
          target: InsightTarget.tagRows,
        ),
        report,
        category: 'Friends',
      );
      expect(subject(InsightRule.r1), '#Ana');
      expect(subject(InsightRule.r2), '#Ana');
      expect(subject(InsightRule.m1), 'Bills');
      expect(subject(InsightRule.a2), 'Next trip');
      expect(subject(InsightRule.a1), 'Friends');
      expect(subject(InsightRule.p5), 'Friends');
    });

    test('D3 and D4 are about one event: its title is the subject, the '
        'detail does not repeat it', () {
      final bill = CalendarEvent(
        id: 'bill',
        title: 'Electricity bill',
        categoryId: 'other',
        startDate: DateTime.utc(2026, 10, 1),
        rule: const OneTimeRecurrence(),
      );
      final dated = analytics(events: {bill.id: bill});
      ReportInsight insight(
        InsightRule rule,
        int n1, {
        bool alternate = false,
      }) => ReportInsight(
        rule: rule,
        severity: 3,
        categoryId: 'other',
        eventId: 'bill',
        target: InsightTarget.dueSoon,
        day: DateTime.utc(2026, 11, 1),
        n1: n1,
        alternate: alternate,
      );
      String words(ReportInsight insight, [String locale = 'en']) {
        final labels = labelsIn(locale);
        return [
          labels.insightSubject(insight, dated, category: 'Other'),
          labels.insightDetail(
            insight,
            dated,
            category: 'Other',
            weekStart: weekStart,
          ),
        ].join(' | ');
      }

      expect(
        words(insight(InsightRule.d4, 3)),
        'Electricity bill | 3${nb}days not marked, the latest Nov${nb}1',
      );
      expect(
        words(insight(InsightRule.d4, 1)),
        'Electricity bill | not marked on Nov${nb}1',
      );
      expect(
        words(insight(InsightRule.d3, 42)),
        'Electricity bill | expires in${nb}42${nb}days',
      );
      expect(
        words(insight(InsightRule.d3, 3, alternate: true)),
        'Electricity bill | expired${nb}3${nb}days ago',
      );
      expect(
        words(insight(InsightRule.d3, 0)),
        'Electricity bill | expires today',
      );
      expect(
        words(insight(InsightRule.d4, 3), 'de'),
        'Electricity bill | 3${nb}Tage nicht markiert, zuletzt${nb}1.${nb}Nov.',
      );
      expect(
        words(insight(InsightRule.d4, 25), 'ro'),
        'Electricity bill | 25${nb}de zile nemarcate, ultima pe${nb}1${nb}nov.',
      );
      expect(
        en.insightSpoken(
          insight(InsightRule.d4, 3),
          dated,
          category: 'Other',
          weekStart: weekStart,
        ),
        'Needs attention. Electricity bill, '
        '3${nb}days not marked, the latest Nov${nb}1',
      );
    });

    test('P1 names its weekdays from the week start', () {
      const weekdays = ReportInsight(
        rule: InsightRule.p1,
        severity: 1,
        categoryId: 'gym',
        target: InsightTarget.categoryGroup,
        n1: 90,
        n2: 40,
        n3: 1,
        n4: 4,
      );
      expect(detail(weekdays), 'Tuesday${nb}90$nb%, Friday${nb}40$nb%');
      expect(
        en.insightDetail(
          weekdays,
          report,
          category: 'Gym',
          weekStart: CalendarWeekStart.sunday,
        ),
        'Monday${nb}90$nb%, Thursday${nb}40$nb%',
      );
    });

    test('the dated and the counted rules', () {
      expect(
        detail(
          ReportInsight(
            rule: InsightRule.a2,
            severity: 0,
            eventId: 'trip',
            target: InsightTarget.overviewDays,
            day: DateTime.utc(2026, 11, 16),
            n1: 12,
          ),
        ),
        'Sibiu in${nb}12${nb}days',
      );
      expect(
        detail(
          const ReportInsight(
            rule: InsightRule.p5,
            severity: 2,
            target: InsightTarget.categoryGroup,
            n1: 3,
            n2: 8,
          ),
        ),
        '3${nb}of${nb}8${nb}cancelled',
      );
      expect(
        detail(
          const ReportInsight(
            rule: InsightRule.l1,
            severity: 0,
            target: InsightTarget.categoryGroup,
            n1: 1,
            n2: 5,
          ),
        ),
        'usually booked a day ahead',
      );
    });

    test('every rule has a sentence in every language', () {
      for (final locale in ['en', 'de', 'ro']) {
        final labels = labelsIn(locale);
        for (final rule in InsightRule.values) {
          for (final alternate in [false, true]) {
            final text = detail(
              ReportInsight(
                rule: rule,
                severity: 1,
                categoryId: 'gym',
                tagKey: 'ana',
                eventId: 'trip',
                target: InsightTarget.categoryGroup,
                day: today,
                dayEnd: thisWeek.end,
                n1: 3,
                n2: 5,
                n3: 2,
                n4: 6,
                minutes: 120,
                cents: 12345,
                ratio: 0.54,
                alternate: alternate,
              ),
              labels: labels,
            );
            expect(text, isNotEmpty, reason: '$locale $rule');
            expect(text, isNot(contains('{')), reason: '$locale $rule');
          }
        }
      }
    });
  });

  group('due phrases (§2.4)', () {
    late final en = labelsIn('en');
    final report = analytics();
    ReportDueRow row(
      ReportDueKind kind,
      ReportDueState state,
      int days, {
      DateTime? day,
      bool beyondLookback = false,
    }) => ReportDueRow(
      categoryId: 'car',
      eventId: 'e',
      day: day ?? today,
      kind: kind,
      state: state,
      days: days,
      beyondLookback: beyondLookback,
    );

    test('each kind and state in en', () {
      expect(
        en.dueCaption(
          row(ReportDueKind.gap, ReportDueState.overdue, 32),
          report,
        ),
        'Overdue${nb}32${nb}days',
      );
      expect(
        en.dueCaption(row(ReportDueKind.gap, ReportDueState.due, 18), report),
        'Due in${nb}18${nb}days',
      );
      expect(
        en.dueCaption(
          row(ReportDueKind.expiry, ReportDueState.upcoming, 42),
          report,
        ),
        'Expires in${nb}42${nb}days',
      );
      expect(
        en.dueCaption(
          row(ReportDueKind.expiry, ReportDueState.overdue, 3),
          report,
        ),
        'Expired${nb}3${nb}days ago',
      );
      expect(
        en.dueCaption(
          row(
            ReportDueKind.unmarked,
            ReportDueState.unmarked,
            3,
            day: DateTime.utc(2026, 11, 1),
          ),
          report,
        ),
        'Nov${nb}1${sep}not marked',
      );
      expect(
        en.dueCaption(
          row(
            ReportDueKind.upcoming,
            ReportDueState.upcoming,
            12,
            day: DateTime.utc(2026, 12, 1),
          ),
          report,
        ),
        'Dec${nb}1${sep}in${nb}12${nb}days',
      );
      expect(
        en.dueCaption(
          row(
            ReportDueKind.gap,
            ReportDueState.overdue,
            200,
            beyondLookback: true,
          ),
          report,
        ),
        'Over a year ago',
      );
      expect(
        en.dueSpoken(
          'Car service',
          row(ReportDueKind.gap, ReportDueState.overdue, 1),
          report,
        ),
        'Car service, Overdue${nb}1${nb}day',
      );
    });

    test('a day of 0 says today, in every language', () {
      List<String> today(ReportLabels labels) => [
        for (final (kind, state) in [
          (ReportDueKind.gap, ReportDueState.overdue),
          (ReportDueKind.gap, ReportDueState.due),
          (ReportDueKind.expiry, ReportDueState.upcoming),
          (ReportDueKind.expiry, ReportDueState.overdue),
        ])
          labels.dueCaption(row(kind, state, 0), report),
      ];
      expect(today(en), [
        'Overdue today',
        'Due today',
        'Expires today',
        'Expired today',
      ]);
      expect(today(labelsIn('de')), [
        'Heute überfällig',
        'Heute fällig',
        'Läuft heute ab',
        'Heute abgelaufen',
      ]);
      expect(today(labelsIn('ro')), [
        'Termen depășit azi',
        'Scadent azi',
        'Expiră azi',
        'Expirat azi',
      ]);
    });

    test('de and ro put the number first, in their plurals', () {
      final overdue = [
        for (final days in [1, 5, 32])
          row(ReportDueKind.gap, ReportDueState.overdue, days),
      ];
      expect(
        [for (final r in overdue) labelsIn('de').dueCaption(r, report)],
        [
          '1${nb}Tag überfällig',
          '5${nb}Tage überfällig',
          '32${nb}Tage überfällig',
        ],
      );
      expect(
        [for (final r in overdue) labelsIn('ro').dueCaption(r, report)],
        [
          '1${nb}zi întârziere',
          '5${nb}zile întârziere',
          '32${nb}de zile întârziere',
        ],
      );
      expect(
        [
          for (final days in [1, 32])
            labelsIn('de').dueCaption(
              row(ReportDueKind.expiry, ReportDueState.overdue, days),
              report,
            ),
        ],
        ['1${nb}Tag abgelaufen', '32${nb}Tage abgelaufen'],
      );
    });
  });

  group('profiled headers (§2.5, N)', () {
    late final en = labelsIn('en');
    const group = ReportCategoryGroup(
      categoryId: 'work',
      count: 12,
      minutes: 31 * 60,
      missed: 1,
      rows: [],
    );
    ReportMeasures measures(
      ReportMeasure primary, {
      bool profiled = true,
      int spent = 0,
      int received = 0,
      int? lastSeen,
    }) => ReportMeasures(
      categoryId: 'work',
      primary: primary,
      profiled: profiled,
      count: 12,
      events: 6,
      minutes: 31 * 60,
      attended: 8,
      tracked: 10,
      cancelled: 3,
      planned: 15,
      tasksTicked: 9,
      tasksTotal: 12,
      spentCents: spent,
      receivedCents: received,
      lastSeenDays: lastSeen,
      leadTimeDays: 3,
      medianStartMinute: 18 * 60,
      daysUntil: 12,
    );
    final unprofiled = ['12', '31 h', '1 missed'].join(sep);

    test('the primary leads, then the count and what was missed', () {
      for (final (primary, lead) in [
        (ReportMeasure.hours, '31 h'),
        (ReportMeasure.events, '6 events'),
        (ReportMeasure.attendance, '8 of 10 attended'),
        (ReportMeasure.cancelled, '3 cancelled'),
        (ReportMeasure.tasks, '9 of 12 tasks'),
        (ReportMeasure.leadTime, 'booked 3 days ahead'),
        (ReportMeasure.timing, 'usually at 18:00'),
        (ReportMeasure.daysUntil, 'in 12 days'),
      ]) {
        expect(
          en.groupFacts(
            ReportCard.categories,
            group,
            measures: measures(primary),
          ),
          [lead, '12', '1 missed'].join(sep),
          reason: '$primary',
        );
      }
      String facts(ReportMeasures m) =>
          en.groupFacts(ReportCard.categories, group, measures: m);
      expect(
        facts(measures(ReportMeasure.money, spent: 180000)),
        startsWith('1,800$sep'),
      );
      expect(
        facts(measures(ReportMeasure.money, received: 180000)),
        startsWith('+1,800$sep'),
      );
      expect(
        facts(measures(ReportMeasure.lastSeen, lastSeen: 23)),
        startsWith('23 days ago$sep'),
      );
      expect(
        facts(measures(ReportMeasure.lastSeen, lastSeen: 0)),
        startsWith('today$sep'),
      );
      expect(
        facts(measures(ReportMeasure.lastSeen, lastSeen: 1)),
        startsWith('yesterday$sep'),
      );
      expect(
        en.groupFacts(
          ReportCard.categories,
          group,
          measures: measures(ReportMeasure.timing),
          use24Hour: false,
        ),
        startsWith('usually at 6:00'),
      );
      expect(
        labelsIn('ro').groupFacts(
          ReportCard.categories,
          group,
          measures: measures(ReportMeasure.lastSeen, lastSeen: 23),
        ),
        startsWith('acum 23 de zile$sep'),
      );
    });

    test('the spoken header says the primary first', () {
      expect(
        en.groupSpoken(
          ReportCard.categories,
          group,
          category: 'Work',
          measures: measures(ReportMeasure.hours),
        ),
        'Work, 31 hours, 12 events, 1 missed',
      );
    });

    test('an unprofiled header, a Count primary, a primary with no value and '
        'the other cards keep today\'s words', () {
      for (final m in [
        null,
        measures(ReportMeasure.hours, profiled: false),
        measures(ReportMeasure.count),
        measures(ReportMeasure.lastSeen),
      ]) {
        expect(
          en.groupFacts(ReportCard.categories, group, measures: m),
          unprofiled,
        );
        expect(
          en.groupSpoken(
            ReportCard.categories,
            group,
            category: 'Work',
            measures: m,
          ),
          'Work, 12 events, 31 hours, 1 missed',
        );
      }
      expect(
        en.groupFacts(
          ReportCard.missed,
          group,
          measures: measures(ReportMeasure.hours),
        ),
        '1 missed',
      );
      expect(
        en.groupFacts(
          ReportCard.ahead,
          group,
          measures: measures(ReportMeasure.hours),
        ),
        unprofiled,
      );
    });
  });

  group('the Totals caption, the Hours tile and the band (§2.5)', () {
    late final en = labelsIn('en');

    test('working days and the counts-as part close the caption (O, P)', () {
      final plain = en.caption(analytics(), periodName: 'This week')!;
      expect(
        en.caption(
          analytics(workingDays: 22, publicHolidays: 1, nominalMinutes: 360),
          periodName: 'This week',
        ),
        [
          plain,
          '22${nb}working${nb}days',
          '1${nb}public${nb}holiday',
          'Hours incl. 6${nb}h counted as',
        ].join(sep),
      );
      expect(
        en.caption(analytics(workingDays: 22), periodName: 'This week'),
        [plain, '22${nb}working${nb}days'].join(sep),
      );
      expect(
        en.caption(analytics(publicHolidays: 1), periodName: 'This week'),
        plain,
      );
      expect(
        labelsIn('ro').caption(
          analytics(workingDays: 20, publicHolidays: 2),
          periodName: 'x',
        ),
        endsWith(
          '20${nb}de${nb}zile${nb}lucrătoare'
          '${sep}2${nb}sărbători${nb}legale',
        ),
      );
      final next = (
        start: DateTime.utc(2026, 12, 1),
        end: DateTime.utc(2026, 12, 31),
      );
      expect(
        en.caption(analytics(span: next, workingDays: 21), periodName: 'x'),
        '21${nb}working${nb}days',
      );
      expect(en.caption(analytics(span: next), periodName: 'x'), isNull);
    });

    test('the Hours tile says the counts-as part', () {
      const value = ReportTileValue(tile: ReportTile.hours, value: 510);
      final plain = en.tileSemantics(value);
      expect(
        en.tileSemantics(value, nominalMinutes: 360),
        '$plain, including 6 hours counted as',
      );
      expect(en.tileSemantics(value, nominalMinutes: 0), plain);
    });

    test('with goals the band counts them in place of the missed (Q)', () {
      const tiles = [
        ReportTileValue(tile: ReportTile.events, value: 31),
        ReportTileValue(tile: ReportTile.missed, value: 3),
      ];
      final goals = [
        atLeast([period(thisWeek, 2, GoalState.onPace)]),
        atLeast([period(thisWeek, 0, GoalState.behind)]),
        atMostHours([period(thisWeek, 10, GoalState.notDue)]),
      ];
      expect(en.subtitle(analytics(tiles: tiles)), '31 events${sep}3 missed');
      expect(
        en.subtitle(analytics(tiles: tiles, goals: goals)),
        '31 events${sep}2 of 3 goals on pace',
      );
      expect(
        en.subtitle(analytics(tiles: tiles, goals: [goals.first])),
        '31 events${sep}1 of 1 goal on pace',
      );
      expect(
        labelsIn('de').subtitle(analytics(tiles: tiles, goals: goals)),
        '31 Termine${sep}2/3 Ziele im Plan',
      );
      expect(
        labelsIn('de').subtitle(analytics(tiles: tiles, goals: [goals.first])),
        '31 Termine${sep}1/1 Ziel im Plan',
      );
      expect(
        labelsIn('ro').subtitle(analytics(tiles: tiles, goals: goals)),
        '31 de evenimente${sep}2/3 obiective în ritm',
      );
      final past = analytics(
        span: lastWeek,
        tiles: tiles,
        goals: [
          atLeast([period(lastWeek, 3, GoalState.met)]),
          atLeast([period(lastWeek, 1, GoalState.missed)]),
          maxGap(
            const ReportGapState(
              daysSince: 3,
              limit: 14,
              state: GapState.within,
            ),
          ),
        ],
      );
      expect(en.subtitle(past), '31 events${sep}2 of 3 goals met');
    });

    test('de and ro spot-check every other shape', () {
      final past = analytics(span: lastWeek);
      final pastGoals = analytics(
        span: lastWeek,
        tiles: const [ReportTileValue(tile: ReportTile.events, value: 31)],
        goals: [
          atLeast([period(lastWeek, 3, GoalState.met)]),
          atLeast([period(lastWeek, 3, GoalState.met)]),
          atLeast([period(lastWeek, 1, GoalState.missed)]),
        ],
      );
      ReportDueRow due(
        ReportDueKind kind,
        ReportDueState state,
        int days, {
        DateTime? day,
        bool long = false,
      }) => ReportDueRow(
        categoryId: 'car',
        eventId: 'e',
        day: day ?? today,
        kind: kind,
        state: state,
        days: days,
        beyondLookback: long,
      );
      const group = ReportCategoryGroup(
        categoryId: 'work',
        count: 12,
        minutes: 31 * 60,
        missed: 1,
        rows: [],
      );
      const hoursPrimary = ReportMeasures(
        categoryId: 'work',
        primary: ReportMeasure.hours,
        profiled: true,
        minutes: 31 * 60,
      );
      List<String> shapes(ReportLabels labels) => [
        labels.goalCaption(
          atLeast([period(thisWeek, 3, GoalState.met)]),
          analytics(),
        ),
        labels.goalCaption(
          atMostHours([period(thisWeek, 44 * 60, GoalState.over)]),
          analytics(),
        ),
        labels.goalCaption(atLeast([period(lastWeek, 3, GoalState.met)]), past),
        labels.goalCaption(
          maxGap(
            const ReportGapState(
              daysSince: 23,
              limit: 14,
              state: GapState.overdue,
            ),
          ),
          analytics(),
        ),
        labels.goalCaption(
          atLeast([
            period(
              (
                start: DateTime.utc(2026, 11, 9),
                end: DateTime.utc(2026, 11, 15),
              ),
              2,
              GoalState.future,
            ),
          ]),
          analytics(
            span: (
              start: DateTime.utc(2026, 11, 9),
              end: DateTime.utc(2026, 11, 15),
            ),
          ),
        ),
        labels.dueCaption(due(ReportDueKind.gap, ReportDueState.due, 18), past),
        labels.dueCaption(
          due(ReportDueKind.expiry, ReportDueState.upcoming, 42),
          past,
        ),
        labels.dueCaption(
          due(ReportDueKind.expiry, ReportDueState.overdue, 3),
          past,
        ),
        labels.dueCaption(
          due(
            ReportDueKind.unmarked,
            ReportDueState.unmarked,
            3,
            day: DateTime.utc(2026, 11, 1),
          ),
          past,
        ),
        labels.dueCaption(
          due(
            ReportDueKind.upcoming,
            ReportDueState.upcoming,
            12,
            day: DateTime.utc(2026, 12, 1),
          ),
          past,
        ),
        labels.dueCaption(
          due(ReportDueKind.gap, ReportDueState.overdue, 9, long: true),
          past,
        ),
        labels.groupFacts(ReportCard.categories, group, measures: hoursPrimary),
        labels
            .caption(
              analytics(workingDays: 22, nominalMinutes: 360),
              periodName: 'x',
            )!
            .split(sep)
            .skip(1)
            .join(sep),
        labels
            .tileSemantics(
              const ReportTileValue(tile: ReportTile.hours, value: 510),
              nominalMinutes: 360,
            )
            .split(', ')
            .last,
        labels.subtitle(pastGoals),
      ];
      expect(shapes(labelsIn('de')), [
        '3${nb}von${nb}3${sep}für die Woche erledigt',
        '44${nb}Std. von${nb}40${sep}4${nb}Std. darüber',
        '3${nb}von${nb}3${sep}Erreicht',
        '23${nb}Tage${sep}max.${nb}14',
        '2${nb}von${nb}3${nb}geplant',
        'In${nb}18${nb}Tagen fällig',
        'Läuft in${nb}42${nb}Tagen ab',
        '3${nb}Tage abgelaufen',
        '1.${nb}Nov.${sep}offen',
        '1.${nb}Dez.${sep}in${nb}12${nb}Tagen',
        'Vor über${nb}1${nb}Jahr',
        '31 Std.${sep}12${sep}1 verpasst',
        '22${nb}Arbeitstage${sep}Stunden inkl. 6${nb}Std. pauschal gezählt',
        'einschließlich 6 Stunden pauschal gezählt',
        '31 Termine${sep}2/3 Ziele erreicht',
      ]);
      expect(shapes(labelsIn('ro')), [
        '3${nb}din${nb}3${sep}gata pe săptămâna asta',
        '44${nb}h din${nb}40${sep}depășit cu${nb}4${nb}h',
        '3${nb}din${nb}3${sep}Atins',
        '23${nb}de zile${sep}limită${nb}14',
        '2${nb}din${nb}3$nbîn plan',
        'Scadent în${nb}18${nb}zile',
        'Expiră în${nb}42${nb}de zile',
        'Expirat de${nb}3${nb}zile',
        '1${nb}nov.${sep}nemarcat',
        '1${nb}dec.${sep}peste${nb}12${nb}zile',
        'Acum peste un an',
        '31 h${sep}12${sep}1 ratată',
        '22${nb}de${nb}zile${nb}lucrătoare${sep}Ore incl. 6${nb}h socotite fix',
        'inclusiv 6 ore socotite fix',
        '31 de evenimente${sep}2/3 obiective atinse',
      ]);
    });

    test('the template is the widest goals subtitle', () {
      expect(en.subtitleTemplate(3), '888 events${sep}3 of 3 goals on pace');
      expect(
        en.subtitleTemplate(3, past: true),
        '888 events${sep}3 of 3 goals met',
      );
    });

    test('without its goals the subtitle keeps the missed form', () {
      const tiles = [
        ReportTileValue(tile: ReportTile.events, value: 31),
        ReportTileValue(tile: ReportTile.missed, value: 3),
      ];
      final report = analytics(
        tiles: tiles,
        goals: [
          atLeast([period(thisWeek, 2, GoalState.onPace)]),
        ],
      );
      expect(en.subtitle(report, goals: false), '31 events${sep}3 missed');
      expect(en.subtitle(report), '31 events${sep}1 of 1 goal on pace');
    });
  });

  group('the trend rules (T1–T3)', () {
    // October is past on 4 November; it compares with September, or under
    // last year with October 2025.
    final october = (
      start: DateTime.utc(2026, 10, 1),
      end: DateTime.utc(2026, 10, 31),
    );
    final september = (
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 9, 30),
    );
    CalendarReport compared({
      ReportMeasure primary = ReportMeasure.hours,
      DateRange? previous,
      DateRange? counted,
    }) => CalendarReport(
      span: october,
      today: today,
      tense: ReportTense.past,
      countedTo: october.end,
      previousSpan: previous ?? september,
      previousCounted: counted ?? previous ?? september,
      events: const {},
      tiles: const [],
      skippedDays: 0,
      aheadCount: 0,
      categories: const [],
      missed: const [],
      ahead: const [],
      measures: {'work': ReportMeasures(categoryId: 'work', primary: primary)},
    );
    ReportInsight trend(
      InsightRule rule, {
      int n1 = 0,
      int n2 = 0,
      int cents = 0,
      double? ratio,
    }) => ReportInsight(
      rule: rule,
      severity: 1,
      categoryId: 'work',
      target: InsightTarget.categoryGroup,
      n1: n1,
      n2: n2,
      cents: cents,
      ratio: ratio,
    );
    String detail(
      ReportInsight insight,
      CalendarReport report, {
      String locale = 'en',
      ReportLabels? labels,
    }) => (labels ?? labelsIn(locale)).insightDetail(
      insight,
      report,
      category: 'Work',
      weekStart: CalendarWeekStart.monday,
    );

    test('T1 words the primary in its unit, up and down, on the compared '
        'period', () {
      expect(
        detail(
          trend(InsightRule.t1, n1: 31 * 60, n2: 23 * 60, ratio: 8 / 23),
          compared(),
        ),
        '31${nb}h, up${nb}35$nb% on September${nb}2026',
      );
      expect(
        detail(
          trend(InsightRule.t1, n1: 4, n2: 8, ratio: -0.5),
          compared(primary: ReportMeasure.count),
        ),
        '4, down${nb}50$nb% on September${nb}2026',
      );
      expect(
        detail(
          trend(InsightRule.t1, n1: 8, n2: 5, ratio: 0.6),
          compared(primary: ReportMeasure.attendance),
        ),
        '8, up${nb}60$nb% on September${nb}2026',
      );
      final euro = ReportLabels(
        lookupAppLocalizations(const Locale('en')),
        currencySymbol: '€',
      );
      expect(
        detail(
          trend(InsightRule.t1, n1: 180000, n2: 120000, ratio: 0.5),
          compared(primary: ReportMeasure.money),
          labels: euro,
        ),
        '${euro.money(180000)}, up${nb}50$nb% on September${nb}2026',
      );
      // No ratio: the values say the direction.
      expect(
        detail(trend(InsightRule.t1, n1: 3, n2: 9), compared()),
        startsWith('3${nb}min, down'),
      );
    });

    test('T2 names last year\'s span; a part of a span reads its dates', () {
      final lastYear = (
        start: DateTime.utc(2025, 10, 1),
        end: DateTime.utc(2025, 10, 31),
      );
      expect(
        detail(
          trend(InsightRule.t2, n1: 6, n2: 4, ratio: 0.5),
          compared(primary: ReportMeasure.events, previous: lastYear),
        ),
        '6, up${nb}50$nb% on October${nb}2025',
      );
      final part = (
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 9, 15),
      );
      final words = detail(
        trend(InsightRule.t1, n1: 6, n2: 4, ratio: 0.5),
        compared(primary: ReportMeasure.events, counted: part),
      );
      expect(words, startsWith('6, up${nb}50$nb% on '));
      expect(words, isNot(contains('September${nb}2026')));
      final year = (
        start: DateTime.utc(2025, 1, 1),
        end: DateTime.utc(2025, 12, 31),
      );
      expect(
        detail(
          trend(InsightRule.t1, n1: 6, n2: 4, ratio: 0.5),
          compared(primary: ReportMeasure.events, previous: year),
        ),
        '6, up${nb}50$nb% on${nb}2025',
      );
    });

    test('T3 words the spent money', () {
      final euro = ReportLabels(
        lookupAppLocalizations(const Locale('en')),
        currencySymbol: '€',
      );
      expect(
        detail(
          trend(InsightRule.t3, cents: 31200, n1: 26400, ratio: 4800 / 26400),
          compared(),
          labels: euro,
        ),
        '${euro.money(31200)}, up${nb}18$nb% on September${nb}2026',
      );
      expect(
        detail(
          trend(InsightRule.t3, cents: 20000, n1: 25000, ratio: -0.2),
          compared(),
          labels: euro,
        ),
        '${euro.money(20000)}, down${nb}20$nb% on September${nb}2026',
      );
    });

    test('de and ro spot-checks', () {
      final down = trend(InsightRule.t1, n1: 4, n2: 8, ratio: -0.5);
      final report = compared(primary: ReportMeasure.count);
      expect(
        detail(down, report, locale: 'de'),
        '4, 50$nb% weniger gegenüber September${nb}2026',
      );
      expect(
        detail(down, report, locale: 'ro'),
        '4, cu${nb}50$nb% mai puțin față de septembrie${nb}2026',
      );
    });
  });
}
