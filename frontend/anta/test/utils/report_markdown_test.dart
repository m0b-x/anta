import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
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
  }) => ReportMarkdown.render(
    report,
    labelsIn(locale),
    use24Hour: true,
    periodName: periodName,
    against: against,
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
