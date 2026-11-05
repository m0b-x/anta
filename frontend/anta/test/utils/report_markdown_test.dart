import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/utils/report_markdown.dart';

/// Share report (K): the report as Markdown, every word through the
/// report's labels, every group and row, in the page's order.
void main() {
  setUpAll(initializeDateFormatting);

  setUp(() {
    CalendarCategories.updateCache([
      for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: seed.kind.name,
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: index,
          isBuiltIn: true,
        ),
    ]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  ReportLabels labelsIn(String locale) =>
      ReportLabels(lookupAppLocalizations(Locale(locale)));

  final today = DateTime.utc(2026, 10, 30);

  final gym = CalendarEvent(
    id: 'e-gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    tracksPresence: true,
  );
  final pt = CalendarEvent(
    id: 'e-pt',
    title: 'PT session',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 10),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 17 * 60, durationMinutes: 60),
  );
  final party = CalendarEvent(
    id: 'e-party',
    title: 'Ana\'s party',
    categoryId: 'birthday',
    startDate: DateTime.utc(2026, 9, 24),
    rule: const OneTimeRecurrence(),
  );
  final todo = CalendarEvent(
    id: 'e-todo',
    title: 'Tax form',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 9, 15),
    rule: const OneTimeRecurrence(),
    description: '- [x] one\n- [x] two\n- [ ] three',
  );
  final events = {
    for (final e in [gym, pt, party, todo]) e.id: e,
  };

  /// September 2026, folded on October 30: graded whole, against August.
  final september = CalendarReport(
    span: (start: DateTime.utc(2026, 9, 1), end: DateTime.utc(2026, 9, 30)),
    today: today,
    tense: ReportTense.past,
    countedTo: DateTime.utc(2026, 9, 30),
    previousSpan: (
      start: DateTime.utc(2026, 8, 1),
      end: DateTime.utc(2026, 8, 31),
    ),
    previousCounted: (
      start: DateTime.utc(2026, 8, 1),
      end: DateTime.utc(2026, 8, 31),
    ),
    events: events,
    tiles: const [
      ReportTileValue(tile: ReportTile.events, value: 31, previous: 29),
      ReportTileValue(
        tile: ReportTile.attended,
        value: 21,
        of: 24,
        previous: 19,
        previousOf: 22,
      ),
      ReportTileValue(tile: ReportTile.missed, value: 3, previous: 5),
      ReportTileValue(tile: ReportTile.hours, value: 1110, previous: 1020),
      ReportTileValue(
        tile: ReportTile.tasks,
        value: 2,
        of: 3,
        previous: 2,
        previousOf: 2,
      ),
    ],
    skippedDays: 2,
    aheadCount: 0,
    categories: [
      ReportCategoryGroup(
        categoryId: 'gym',
        count: 14,
        minutes: 790,
        missed: 2,
        rows: [
          ReportRoutineRow(
            eventId: gym.id,
            attended: 8,
            total: 10,
            minutes: 480,
            latestDay: DateTime.utc(2026, 9, 29),
          ),
          ReportDatedRow(eventId: pt.id, day: DateTime.utc(2026, 9, 10)),
        ],
      ),
      ReportCategoryGroup(
        categoryId: 'other',
        count: 1,
        minutes: 0,
        missed: 0,
        rows: [
          ReportDatedRow(
            eventId: todo.id,
            day: DateTime.utc(2026, 9, 15),
            tasks: const ReportTaskCount(2, 3),
          ),
        ],
      ),
      ReportCategoryGroup(
        categoryId: 'birthday',
        count: 1,
        minutes: 0,
        missed: 0,
        rows: [
          ReportDatedRow(eventId: party.id, day: DateTime.utc(2026, 9, 24)),
        ],
      ),
    ],
    trend: const ReportTrend(
      unit: ReportTrendUnit.day,
      buckets: [],
      busiestWeekday: 1,
      usualStartMinute: 18 * 60,
      usualEndMinute: 19 * 60 + 30,
    ),
    missed: [
      ReportCategoryGroup(
        categoryId: 'gym',
        count: 0,
        minutes: 0,
        missed: 2,
        rows: [
          ReportDatedRow(
            eventId: gym.id,
            day: DateTime.utc(2026, 9, 3),
            missed: true,
          ),
          ReportDatedRow(
            eventId: gym.id,
            day: DateTime.utc(2026, 9, 17),
            missed: true,
          ),
        ],
      ),
    ],
    ahead: const [],
  );

  String render(
    CalendarReport report, {
    String locale = 'en',
    required String periodName,
    String? against,
    String? beside,
  }) => ReportMarkdown.render(
    report,
    labelsIn(locale),
    use24Hour: true,
    periodName: periodName,
    against: against,
    beside: beside,
  );

  /// The labels' separator: a no-break space, the dot, a space.
  const s = ReportLabels.separator;

  test('a past month: the whole report, every section, in page order', () {
    expect(
      render(september, periodName: 'September 2026', against: 'August 2026'),
      '# Report${s}September 2026\n'
      '\n'
      '31 events${s}3 missed\n'
      '\n'
      '*To September 30${s}against August 2026${s}2 skipped*\n'
      '\n'
      '## Totals\n'
      '\n'
      '- Events: 31$s+2\n'
      '- Attended: 21 of 24${s}88 %$s+2\n'
      '- Missed: 3$s−2\n'
      '- Hours: 18.5 h$s+1.5 h\n'
      '- Tasks: 2 of 3${s}1 open$s±0\n'
      '\n'
      '## Categories\n'
      '\n'
      '### Gym${s}14${s}13.2 h${s}2 missed\n'
      '\n'
      '- Gym${s}8 of 10 attended${s}8 h\n'
      '- PT session${s}Thu 10${s}17:00${s}1 h\n'
      '\n'
      '### Other${s}1 event\n'
      '\n'
      '- Tax form${s}Tue 15${s}2 of 3 tasks\n'
      '\n'
      '### Birthday${s}1 event\n'
      '\n'
      '- Ana\'s party${s}Thu 24\n'
      '\n'
      '## Over time\n'
      '\n'
      'Most on Monday${s}usually 18:00 – 19:30\n'
      '\n'
      '## Missed\n'
      '\n'
      '### Gym${s}2 missed\n'
      '\n'
      '- Gym${s}Thu 3${s}18:00${s}1 h\n'
      '- Gym${s}Thu 17${s}18:00${s}1 h\n',
    );
  });

  test('beside a saved view the caption names the view and the tiles '
      'carry no delta, as the page draws them (S5 I)', () {
    final out = render(
      september,
      periodName: 'September 2026',
      beside: 'Work / Life',
    );
    expect(
      out,
      contains('*To September 30${s}beside Work / Life${s}2 skipped*\n'),
    );
    expect(out, isNot(contains('against')));
    expect(
      out,
      contains(
        '## Totals\n'
        '\n'
        '- Events: 31\n'
        '- Attended: 21 of 24${s}88 %\n'
        '- Missed: 3\n'
        '- Hours: 18.5 h\n'
        '- Tasks: 2 of 3${s}1 open\n'
        '\n'
        '## Categories\n',
      ),
    );
    // Everything below Totals is the page's own report, as without a view.
    final plain = render(september, periodName: 'September 2026');
    expect(
      out.substring(out.indexOf('## Categories')),
      plain.substring(plain.indexOf('## Categories')),
    );
  });

  test('a future month is a plan: Totals and Categories only, no caption', () {
    final december = CalendarReport(
      span: (start: DateTime.utc(2026, 12, 1), end: DateTime.utc(2026, 12, 31)),
      today: today,
      tense: ReportTense.future,
      countedTo: DateTime.utc(2026, 12, 31),
      events: events,
      tiles: const [
        ReportTileValue(tile: ReportTile.planned, value: 10),
        ReportTileValue(tile: ReportTile.hours, value: 570),
      ],
      skippedDays: 0,
      aheadCount: 0,
      categories: [
        ReportCategoryGroup(
          categoryId: 'gym',
          count: 4,
          minutes: 240,
          missed: 0,
          rows: [
            ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 12, 1)),
            ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 12, 3)),
          ],
        ),
      ],
      // Never drawn for a plan, whatever the fold hands over (T).
      trend: september.trend,
      missed: september.missed,
      ahead: september.categories,
    );
    expect(
      render(december, periodName: 'December 2026'),
      '# Report${s}December 2026\n'
      '\n'
      '10 planned${s}9.5 h\n'
      '\n'
      '## Totals\n'
      '\n'
      '- Planned: 10\n'
      '- Hours: 9.5 h\n'
      '\n'
      '## Categories\n'
      '\n'
      '### Gym${s}4${s}4 h\n'
      '\n'
      '- Gym${s}Tue 1${s}18:00${s}1 h\n'
      '- Gym${s}Thu 3${s}18:00${s}1 h\n',
    );
  });

  test('an empty period: the caption says so, Totals only', () {
    final june = CalendarReport(
      span: (start: DateTime.utc(2025, 6, 1), end: DateTime.utc(2025, 6, 30)),
      today: today,
      tense: ReportTense.past,
      countedTo: DateTime.utc(2025, 6, 30),
      events: const {},
      tiles: const [
        ReportTileValue(tile: ReportTile.events, value: 0, previous: 0),
        ReportTileValue(tile: ReportTile.hours, value: 0, previous: 0),
      ],
      skippedDays: 0,
      aheadCount: 0,
      categories: const [],
      missed: const [],
      ahead: const [],
    );
    expect(june.isEmpty, isTrue);
    expect(
      render(june, periodName: 'June 2025'),
      '# Report${s}June 2025\n'
      '\n'
      '0 events\n'
      '\n'
      '*June 2025${s}Nothing happened*\n'
      '\n'
      '## Totals\n'
      '\n'
      '- Events: —\n'
      '- Hours: —\n',
    );
  });

  test('German words every line, the group header included', () {
    final out = render(september, locale: 'de', periodName: 'September 2026');
    expect(out, startsWith('# Bericht${s}September 2026\n'));
    expect(out, contains('\n### Training${s}14${s}13,2 Std.${s}2 verpasst\n'));
    expect(out, contains('\n### Sonstiges${s}1 Termin\n'));
    expect(out, contains('\n- Termine: 31$s+2\n'));
    expect(out, contains('\n- PT session${s}Do., 10.${s}17:00${s}1 Std.\n'));
  });

  /// Four weeks to November 1, on October 30: a span over two months, so a
  /// row's day names its month (U), with the last two days ahead.
  CalendarReport fourWeeks({ReportTrend? trend}) => CalendarReport(
    span: (start: DateTime.utc(2026, 10, 5), end: DateTime.utc(2026, 11, 1)),
    today: today,
    tense: ReportTense.current,
    countedTo: today,
    events: events,
    tiles: const [],
    skippedDays: 0,
    aheadCount: 2,
    categories: [
      ReportCategoryGroup(
        categoryId: 'gym',
        count: 1,
        minutes: 60,
        missed: 0,
        rows: [ReportDatedRow(eventId: pt.id, day: DateTime.utc(2026, 10, 8))],
      ),
    ],
    trend: trend,
    missed: const [],
    ahead: [
      ReportCategoryGroup(
        categoryId: 'gym',
        count: 2,
        minutes: 120,
        missed: 0,
        rows: [
          ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 10, 31)),
          ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 11, 1)),
        ],
      ),
    ],
  );

  test('Ahead closes the share; a cross-month day names its month and a '
      '12-hour clock reads as the phone does', () {
    final out = ReportMarkdown.render(
      fourWeeks(),
      labelsIn('en'),
      use24Hour: false,
      periodName: 'Last 4 weeks',
    );
    expect(
      out,
      contains(
        '\n## Categories\n'
        '\n'
        '### Gym${s}1${s}1 h\n'
        '\n'
        '- PT session${s}Thu 8 Oct${s}5:00 PM${s}1 h\n',
      ),
    );
    expect(
      out,
      endsWith(
        '\n## Ahead\n'
        '\n'
        '### Gym${s}2${s}2 h\n'
        '\n'
        '- Gym${s}Sat 31 Oct${s}6:00 PM${s}1 h\n'
        '- Gym${s}Sun 1 Nov${s}6:00 PM${s}1 h\n',
      ),
    );
  });

  test('a trend with nothing to caption leaves Over time out', () {
    const quiet = ReportTrend(unit: ReportTrendUnit.day, buckets: []);
    expect(labelsIn('en').trendWords(quiet, use24Hour: true).caption, isNull);
    final out = render(fourWeeks(trend: quiet), periodName: 'Last 4 weeks');
    expect(out, isNot(contains('## Over time')));
    expect(out, contains('\n## Categories\n'));
    expect(out, contains('\n## Ahead\n'));
  });

  group('escapeMarkdown', () {
    final cases = {
      '# Plan': r'\# Plan',
      '*Leg* day': r'\*Leg\* day',
      '[ ] Call': r'\[ \] Call',
      '1. Squats': r'1\. Squats',
      '12) Rows': r'12\) Rows',
      '- Rest': r'\- Rest',
      '+ Rest': r'\+ Rest',
      '_Lifts_': r'\_Lifts\_',
      '`swim` <b>': r'\`swim\` \<b\>',
      r'a\b': r'a\\b',
      // Only a marker at the start is one.
      'Day 1. Squats': 'Day 1. Squats',
      'PT - session + core': 'PT - session + core',
      '5 km': '5 km',
    };
    for (final MapEntry(key: text, value: escaped) in cases.entries) {
      test(
        '"$text"',
        () => expect(ReportMarkdown.escapeMarkdown(text), escaped),
      );
    }
  });

  test('event titles and category names are escaped, the labels are not', () {
    CalendarCategories.updateCache([
      ...CalendarCategories.all,
      const CalendarCategory(
        id: 'c-lifts',
        name: '*Lifts*',
        colorValue: 0xFF3F51B5,
        iconKey: 'gym',
        sortOrder: 99,
        isBuiltIn: false,
      ),
    ]);
    final plan = CalendarEvent(
      id: 'e-plan',
      title: '# Plan',
      categoryId: 'c-lifts',
      startDate: DateTime.utc(2026, 9, 10),
      rule: const OneTimeRecurrence(),
    );
    final report = CalendarReport(
      span: september.span,
      today: today,
      tense: ReportTense.past,
      countedTo: september.countedTo,
      events: {plan.id: plan},
      tiles: const [],
      skippedDays: 0,
      aheadCount: 0,
      categories: [
        ReportCategoryGroup(
          categoryId: 'c-lifts',
          count: 1,
          minutes: 0,
          missed: 0,
          rows: [
            ReportDatedRow(eventId: plan.id, day: DateTime.utc(2026, 9, 10)),
          ],
        ),
      ],
      missed: const [],
      ahead: const [],
    );
    final out = render(report, periodName: 'September 2026');
    expect(out, startsWith('# Report${s}September 2026\n'));
    expect(
      out,
      contains(
        '\n### \\*Lifts\\*${s}1 event\n'
        '\n'
        '- \\# Plan${s}Thu 10\n',
      ),
    );
  });

  test('a row whose event is not in the report is a builder bug', () {
    final orphan = CalendarReport(
      span: september.span,
      today: today,
      tense: ReportTense.past,
      countedTo: september.countedTo,
      events: events,
      tiles: const [],
      skippedDays: 0,
      aheadCount: 0,
      categories: [
        ReportCategoryGroup(
          categoryId: 'birthday',
          count: 1,
          minutes: 0,
          missed: 0,
          rows: [
            ReportDatedRow(eventId: 'e-gone', day: DateTime.utc(2026, 9, 25)),
          ],
        ),
      ],
      missed: const [],
      ahead: const [],
    );
    expect(
      () => render(orphan, periodName: 'September 2026'),
      throwsAssertionError,
    );
  });

  group('the analytics sections (S7)', () {
    late final en = labelsIn('en');
    String name(String categoryId) => CalendarCategories.labelOf(
      CalendarCategories.resolve(categoryId),
      en.l10n,
    );

    final trip = CalendarEvent(
      id: 'e-trip',
      title: '*Sibiu*',
      categoryId: 'other',
      startDate: DateTime.utc(2026, 7, 10),
      rule: const OneTimeRecurrence(),
    );
    final call = CalendarEvent(
      id: 'e-call',
      title: '[ ] Call',
      categoryId: 'other',
      startDate: DateTime.utc(2026, 9, 20),
      rule: const OneTimeRecurrence(),
    );
    final all = {...events, trip.id: trip, call.id: call};

    final monthly = ReportGoal(
      categoryId: 'gym',
      measure: ReportMeasure.count,
      target: const ReportTarget(
        kind: TargetKind.atLeast,
        value: 12,
        period: TargetPeriod.month,
      ),
      periods: [
        ReportGoalPeriod(
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 30),
          value: 14,
          expected: 12,
          state: GoalState.met,
        ),
      ],
    );
    const gap = ReportGoal(
      categoryId: 'birthday',
      measure: ReportMeasure.lastSeen,
      target: ReportTarget(kind: TargetKind.maxGap, value: 14),
      gap: ReportGapState(daysSince: 23, limit: 14, state: GapState.overdue),
    );

    const weekdays = ReportInsight(
      rule: InsightRule.p1,
      severity: 1,
      categoryId: 'gym',
      target: InsightTarget.categoryGroup,
      n1: 5,
      n2: 1,
      n3: 0,
      n4: 4,
    );
    // Said on Due soon's gap row of the same category: the page drops it.
    const shownAbove = ReportInsight(
      rule: InsightRule.d2,
      severity: 2,
      categoryId: 'gym',
      target: InsightTarget.dueSoon,
      n1: 3,
    );
    const tagged = ReportInsight(
      rule: InsightRule.r1,
      severity: 2,
      tagKey: 'leg_day',
      target: InsightTarget.tagRows,
      n1: 30,
      n2: 21,
    );
    const lead = ReportInsight(
      rule: InsightRule.l1,
      severity: 0,
      categoryId: 'other',
      target: InsightTarget.categoryGroup,
      n1: 12,
    );
    // Past the page's cap of three.
    const capped = ReportInsight(
      rule: InsightRule.p5,
      severity: 0,
      categoryId: 'birthday',
      target: InsightTarget.categoryGroup,
      n1: 2,
      n2: 5,
    );
    const insights = [weekdays, shownAbove, tagged, lead, capped];

    final dueGap = ReportDueRow(
      categoryId: 'gym',
      eventId: gym.id,
      day: DateTime.utc(2026, 10, 2),
      kind: ReportDueKind.gap,
      state: ReportDueState.due,
      days: 3,
    );
    final dueCall = ReportDueRow(
      categoryId: 'other',
      eventId: call.id,
      day: DateTime.utc(2026, 9, 20),
      kind: ReportDueKind.unmarked,
      state: ReportDueState.unmarked,
      days: 10,
    );

    final ptRow = ReportDatedRow(
      eventId: pt.id,
      day: DateTime.utc(2026, 9, 10),
    );
    final legDay = ReportTag(
      key: 'leg_day',
      label: 'leg_day',
      events: 1,
      count: 1,
      minutes: 60,
      lastSeenDay: DateTime.utc(2026, 9, 10),
      categoryIds: const ['gym'],
      rows: [ptRow],
    );

    final busiest = ReportWhen(
      cells: List.filled(ReportWhen.cellCount, 0),
      timedDays: 12,
      busiestWeekday: 1,
      busiestHour: 18,
    );
    const balance = {LifeArea.work: 38 * 60, LifeArea.health: 19 * 60};

    final wholeYear = (
      start: DateTime.utc(2026, 1, 1),
      end: DateTime.utc(2026, 12, 31),
    );
    final busiestMonth = ReportRecord(
      kind: ReportRecordKind.busiestMonth,
      value: 31,
      start: DateTime.utc(2026, 6, 1),
    );
    final longestTrip = ReportRecord(
      kind: ReportRecordKind.longestTrip,
      eventId: trip.id,
      value: 6,
      start: DateTime.utc(2026, 7, 10),
      end: DateTime.utc(2026, 7, 15),
    );
    const gymMonths = [9, 8, 0, 1, 2, 3, 4, 5, 6, 7, 1, 0];
    final gymSpan = (
      first: DateTime.utc(2026, 1, 2),
      last: DateTime.utc(2026, 10, 29),
    );
    final year = ReportYear(
      records: [busiestMonth, longestTrip],
      // Other has months but no kept span: the page draws no strip for it.
      months: {'gym': gymMonths, 'other': List.filled(12, 1)},
      spans: {'gym': gymSpan},
    );

    /// September's report, or [span]'s on [on], with the analytics parts.
    CalendarReport profiled({
      DateRange? span,
      DateTime? on,
      List<ReportGoal> goals = const [],
      List<ReportInsight> insights = const [],
      List<ReportDueRow> dueSoon = const [],
      List<ReportTag> tags = const [],
      ReportWhen? when,
      Map<LifeArea, int> balance = const {},
      Map<LifeArea, int>? balanceLastYear,
      ReportYear? year,
      ReportCompare compare = ReportCompare.previous,
      CalendarReport? compared,
      List<ReportCategoryGroup> ahead = const [],
    }) {
      final shown = span ?? september.span;
      final day = on ?? today;
      return CalendarReport(
        span: shown,
        today: day,
        tense: CalendarReport.tenseOf(span: shown, today: day),
        countedTo: CalendarReport.countedToOf(span: shown, today: day),
        previousSpan: september.previousSpan,
        previousCounted: september.previousCounted,
        events: all,
        tiles: september.tiles,
        skippedDays: september.skippedDays,
        aheadCount: ahead.length,
        categories: september.categories,
        trend: september.trend,
        missed: september.missed,
        ahead: ahead,
        goals: goals,
        insights: insights,
        dueSoon: dueSoon,
        tags: tags,
        when: when,
        balance: balance,
        balanceLastYear: balanceLastYear,
        year: year,
        compare: compare,
        compared: compared,
      );
    }

    String insightLine(
      ReportInsight insight,
      CalendarReport report, {
      CalendarWeekStart weekStart = CalendarWeekStart.monday,
    }) {
      final category = insight.categoryId == null
          ? ''
          : name(insight.categoryId!);
      final detail = en.insightDetail(
        insight,
        report,
        category: category,
        weekStart: weekStart,
      );
      return '- ${en.insightSubject(insight, report, category: category)}: '
          '$detail';
    }

    test('Goals, Insights and Due soon open the share above Totals, each '
        'in the card\'s words', () {
      final report = profiled(
        goals: [monthly, gap],
        insights: insights,
        dueSoon: [dueGap, dueCall],
        tags: [legDay],
      );
      expect(
        render(report, periodName: 'September 2026', against: 'August 2026'),
        contains(
          '${en.caption(report, periodName: 'September 2026', against: 'August 2026')}*\n'
          '\n'
          '## Goals\n'
          '\n'
          '- ${name('gym')}: ${en.goalSharedCaption(monthly, report)}\n'
          '- ${name('birthday')}: ${en.goalSharedCaption(gap, report)}\n'
          '\n'
          '## Insights\n'
          '\n'
          '${insightLine(weekdays, report)}\n'
          // The tag the user typed is escaped; the '#' mid-line is no
          // heading and stays bare.
          '${insightLine(tagged, report).replaceFirst('_', r'\_')}\n'
          '${insightLine(lead, report)}\n'
          '\n'
          '## Due soon\n'
          '\n'
          '- Gym: ${en.dueCaption(dueGap, report)}\n'
          '- \\[ \\] Call: ${en.dueCaption(dueCall, report)}\n'
          '\n'
          '## Totals\n',
        ),
      );
      // A shared text has no glyph: the gap goal's state is said.
      expect(
        en.goalSharedCaption(gap, report),
        endsWith('$s${en.goalStateWord(gap, report)}'),
      );
    });

    test('Insights name weekdays from the week start the page reads', () {
      final report = profiled(insights: const [weekdays]);
      final sunday = ReportMarkdown.render(
        report,
        en,
        use24Hour: true,
        periodName: 'September 2026',
        weekStart: CalendarWeekStart.sunday,
      );
      expect(
        sunday,
        contains(
          '${insightLine(weekdays, report, weekStart: CalendarWeekStart.sunday)}\n',
        ),
      );
      expect(
        sunday,
        isNot(contains(insightLine(weekdays, report))),
        reason: 'the week start moves the weekdays',
      );
    });

    test('a plan writes Goals and Due soon but no Insights', () {
      final december = profiled(
        span: (
          start: DateTime.utc(2026, 12, 1),
          end: DateTime.utc(2026, 12, 31),
        ),
        goals: [gap],
        insights: const [lead],
        dueSoon: [dueCall],
      );
      expect(december.tense, ReportTense.future);
      final out = render(december, periodName: 'December 2026');
      expect(out, contains('\n## Goals\n'));
      expect(out, contains('\n## Due soon\n'));
      expect(out, isNot(contains('## Insights')));
      expect(out, isNot(contains('## Over time')));
      expect(out, isNot(contains('## Missed')));
    });

    test('a whole year writes Records and Months between Totals and '
        'Categories, the months ahead left out', () {
      final report = profiled(span: wholeYear, year: year);
      final months = en.yearMonthsLine(
        months: gymMonths,
        primary: ReportMeasure.count,
        aheadFrom: 11,
      );
      expect(
        render(report, periodName: '2026'),
        contains(
          '\n'
          '## Records\n'
          '\n'
          '- ${en.recordName(busiestMonth.kind)}: '
          '${en.recordWords(busiestMonth, report).caption}\n'
          // The trip's title is the user's text, escaped mid-line.
          '- ${en.recordName(longestTrip.kind)}: '
          '${en.recordWords(longestTrip, report).caption.replaceAll('*', r'\*')}\n'
          '\n'
          '## Months\n'
          '\n'
          '- Gym: ${en.yearSpan(gymSpan.first, gymSpan.last)}$s$months\n'
          '\n'
          '## Categories\n',
        ),
      );
      expect(months, contains('Oct'));
      expect(months, isNot(contains('Nov')));
    });

    test('a past year writes all twelve months', () {
      final report = profiled(
        span: wholeYear,
        on: DateTime.utc(2027, 2, 1),
        year: year,
      );
      expect(
        render(report, periodName: '2026'),
        contains(
          '- Gym: ${en.yearSpan(gymSpan.first, gymSpan.last)}$s'
          '${en.yearMonthsLine(months: gymMonths, primary: ReportMeasure.count)}\n',
        ),
      );
    });

    test('a month has no year sections', () {
      final out = render(profiled(goals: [gap]), periodName: 'September 2026');
      expect(out, isNot(contains('## Records')));
      expect(out, isNot(contains('## Months')));
    });

    test('By tag follows Categories: the tag\'s header and its dated rows', () {
      final report = profiled(tags: [legDay]);
      final caption = en
          .tagWords(legDay, spansMonths: false, today: today)
          .caption;
      final row = en.rowSubtitle(
        ptRow,
        event: pt,
        use24Hour: true,
        spansMonths: false,
      );
      expect(
        render(report, periodName: 'September 2026'),
        contains(
          '- Ana\'s party${s}Thu 24\n'
          '\n'
          '## By tag\n'
          '\n'
          '### #leg\\_day$s$caption\n'
          '\n'
          '- PT session$s$row\n'
          '\n'
          '## Over time\n',
        ),
      );
    });

    test('When follows Over time and Balance follows When, before Missed', () {
      final report = profiled(when: busiest, balance: balance);
      final shares = ReportLabels.shares([38 * 60, 19 * 60]);
      expect(
        render(report, periodName: 'September 2026'),
        contains(
          '## When\n'
          '\n'
          '${en.whenWords(busiest, weekStart: CalendarWeekStart.monday, use24Hour: true)!.caption}\n'
          '\n'
          '## Balance\n'
          '\n'
          '- ${en.areaName(LifeArea.work)}: '
          '${en.balanceWords(LifeArea.work, 38 * 60, percent: shares[0]).caption}\n'
          '- ${en.areaName(LifeArea.health)}: '
          '${en.balanceWords(LifeArea.health, 19 * 60, percent: shares[1]).caption}\n'
          '\n'
          '## Missed\n',
        ),
      );
    });

    test('no busiest day writes no When; one area writes no Balance', () {
      final out = render(
        profiled(
          when: ReportWhen(
            cells: List.filled(ReportWhen.cellCount, 0),
            timedDays: 2,
          ),
          balance: const {LifeArea.work: 60},
        ),
        periodName: 'September 2026',
      );
      expect(out, isNot(contains('## When')));
      expect(out, isNot(contains('## Balance')));
    });

    test('Balance under Compare: last year reads both spans\' hours', () {
      const lastYear = {LifeArea.work: 30 * 60, LifeArea.home: 5 * 60};
      final report = profiled(
        balance: balance,
        balanceLastYear: lastYear,
        compare: ReportCompare.lastYear,
      );
      String line(LifeArea area) =>
          '- ${en.areaName(area)}: '
          '${en.balanceLastYearWords(area, balance[area] ?? 0, lastYear[area] ?? 0).caption}';
      expect(
        render(report, periodName: 'September 2026'),
        contains(
          '## Balance\n'
          '\n'
          '${line(LifeArea.work)}\n'
          '${line(LifeArea.health)}\n'
          '${line(LifeArea.home)}\n'
          '\n',
        ),
      );
    });

    test('beside a saved view its own Totals column follows the page\'s, '
        'under its name and without deltas (S5 I)', () {
      final view = CalendarReport(
        span: september.span,
        today: today,
        tense: ReportTense.past,
        countedTo: september.countedTo,
        events: const {},
        tiles: const [
          ReportTileValue(tile: ReportTile.events, value: 20, previous: 18),
          ReportTileValue(tile: ReportTile.hours, value: 720, previous: 600),
        ],
        skippedDays: 0,
        aheadCount: 0,
        categories: const [],
        missed: const [],
        ahead: const [],
      );
      final report = profiled(compare: ReportCompare.view, compared: view);
      String bare(ReportTileValue tile) {
        final value = ReportTileValue(
          tile: tile.tile,
          value: tile.value,
          of: tile.of,
        );
        expect(en.detail(value), isEmpty);
        return '- ${en.tileLabel(tile.tile)}: ${en.tileValue(value)}';
      }

      final out = render(
        report,
        periodName: 'September 2026',
        beside: 'Work / Life',
      );
      expect(
        out,
        contains(
          '*${en.caption(report, periodName: 'September 2026', beside: 'Work / Life')}*\n',
        ),
      );
      expect(
        out,
        contains(
          '- Tasks: 2 of 3${s}1 open\n'
          '\n'
          '### Work / Life\n'
          '\n'
          '${bare(view.tiles[0])}\n'
          '${bare(view.tiles[1])}\n'
          '\n'
          '## Categories\n',
        ),
      );
      // Against a period there is no view column, whatever was folded.
      expect(
        render(report, periodName: 'September 2026', against: 'August 2026'),
        isNot(contains('### Work / Life')),
      );
    });

    /// Every section with content: a whole year on October 30, with Ahead.
    CalendarReport everything() => profiled(
      span: wholeYear,
      goals: [gap],
      insights: insights,
      dueSoon: [dueGap],
      tags: [legDay],
      when: busiest,
      balance: balance,
      year: year,
      ahead: fourWeeks().ahead,
    );

    List<String> headings(AppLocalizations l10n) => [
      l10n.reportSectionGoals,
      l10n.reportSectionInsights,
      l10n.reportSectionDueSoon,
      l10n.reportSectionTotals,
      l10n.reportSectionRecords,
      l10n.reportSectionMonths,
      l10n.reportSectionCategories,
      l10n.reportSectionTags,
      l10n.reportSectionOverTime,
      l10n.reportSectionWhen,
      l10n.reportSectionBalance,
      l10n.reportSectionMissed,
      l10n.reportSectionAhead,
    ];

    for (final locale in ['en', 'de', 'ro']) {
      test('every section in the page\'s order, headed in $locale', () {
        final out = render(everything(), locale: locale, periodName: '2026');
        final at = [
          for (final heading in headings(labelsIn(locale).l10n))
            out.indexOf('\n## $heading\n'),
        ];
        expect(at, everyElement(greaterThan(0)), reason: out);
        for (var i = 1; i < at.length; i++) {
          expect(
            at[i],
            greaterThan(at[i - 1]),
            reason: headings(labelsIn(locale).l10n)[i],
          );
        }
      });
    }
  });

  test('the file is named for the span, in the Markdown extension', () {
    expect(
      ReportMarkdown.fileName(september.span),
      'anta_report_20260901-20260930.md',
    );
    expect(
      ReportMarkdown.fileName((
        start: DateTime.utc(2026, 10, 26),
        end: DateTime.utc(2026, 11, 1),
      )),
      'anta_report_20261026-20261101.md',
    );
  });
}
