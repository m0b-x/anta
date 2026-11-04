import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/utils/calendar_report_builder.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_body.dart';
import 'package:anta/widgets/report_group_stack.dart';
import 'package:anta/widgets/report_totals_card.dart';

import '../goldens/support/golden_fonts.dart';

/// Counts the routes pushed over the body, so a case can prove a tap opened
/// nothing.
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushes++;
  }
}

/// `ReportBody` and `ReportBand` over a report folded the pure way, with
/// every callback null — as the guide's screen stage draws them (D74): the
/// cards are drawn, nothing a tap reaches leaves the body, the folds stay
/// live.
void main() {
  setUpAll(loadGoldenFonts);

  /// The suite's clock: no case reads the wall clock.
  DateTime clock() => DateTime(2026, 10, 30, 10);
  final today = EventAgenda.dateOnly(clock());
  const october = OverviewMonthPeriod(2026, 10);
  const years = (first: 2020, last: 2026);

  /// Tracked, timed, Tuesdays and Thursdays; the week of the 13th missed.
  final gym = CalendarEvent(
    id: 'e-gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 1),
    rule: const WeeklyRecurrence(weekdays: {2, 4}),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    tracksPresence: true,
  );

  /// One time, timed.
  final dentist = CalendarEvent(
    id: 'e-dentist',
    title: 'Dentist',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 10, 9),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 9 * 60, durationMinutes: 30),
  );

  /// All day, every year.
  final birthday = CalendarEvent(
    id: 'e-birthday',
    title: 'Ana',
    categoryId: 'birthday',
    startDate: DateTime.utc(2020, 10, 21),
    rule: const YearlyRecurrence(),
  );

  late CalendarReport report;
  late ReportGroupFolds folds;
  late _PushCounter pushes;

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
    EventPresence.updateCache(
      byEvent: {
        gym.id: {DateTime.utc(2026, 10, 13): PresenceStatus.missed},
      },
    );
    report = CalendarReportBuilder.fold(
      CalendarReportService.sampleInput(
        ReportRequest(
          span: october.resolve(today: today, yearBounds: years),
          previousSpan: october
              .stepped(direction: -1, today: today, yearBounds: years)
              ?.resolve(today: today, yearBounds: years),
          events: [gym, dentist, birthday],
          today: today,
          weekStart: CalendarWeekStart.monday,
        ),
      ),
    );
    folds = ReportGroupFolds();
    pushes = _PushCounter();
  });

  tearDown(() {
    EventPresence.resetCache();
    CalendarCategories.updateCache(const []);
    AppNavigator.pendingOverviewLook.value = null;
  });

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  /// The body's padded sliver group as words: a section label by its text,
  /// a boxed child by its type through its repaint boundary, any other
  /// sliver by its own type — what an unprofiled page must keep and the
  /// new cards insert into.
  List<String> sliverSequence(WidgetTester tester) {
    final group = tester.widget<SliverMainAxisGroup>(
      find
          .descendant(
            of: byId(SemanticsIds.reportBody),
            matching: find.byType(SliverMainAxisGroup),
          )
          .first,
    );
    return [
      for (final sliver in group.children)
        switch (sliver) {
          SliverToBoxAdapter(child: FormSectionLabel(:final text)) =>
            'label $text',
          SliverToBoxAdapter(child: RepaintBoundary(:final child?)) =>
            '${child.runtimeType}',
          SliverToBoxAdapter(:final child?) => '${child.runtimeType}',
          _ => '${sliver.runtimeType}',
        },
    ];
  }

  /// The section label whose text is [text], found by the widget's own
  /// field: the label draws its words uppercase.
  Finder sectionLabel(String text) => find.byWidgetPredicate(
    (widget) => widget is FormSectionLabel && widget.text == text,
  );

  /// [shown] over [period] in place of the October fixture; [bandPeriod] the
  /// band's title alone, its home staying [period].
  Future<void> pumpBody(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1,
    Size surface = const Size(360, 780),
    CalendarReport? shown,
    OverviewPeriod period = october,
    Set<String> categoryIds = const {},
    OverviewPeriod? bandPeriod,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        navigatorObservers: [pushes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            final labels = ReportLabels(AppLocalizations.of(context)!);
            return Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReportBand(
                    period: bandPeriod ?? period,
                    home: period,
                    report: shown ?? report,
                    today: today,
                    years: years,
                    labels: labels,
                  ),
                  Expanded(
                    child: ReportBody(
                      report: shown ?? report,
                      period: period,
                      categoryIds: categoryIds,
                      today: today,
                      years: years,
                      weekStart: CalendarWeekStart.monday,
                      labels: labels,
                      folds: folds,
                      bottomClearance: 0,
                      use24Hour: true,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the body down a screen at a time to its end, handing each
  /// frame to [atEach].
  Future<void> scrollThrough(
    WidgetTester tester,
    void Function() atEach,
  ) async {
    final scrollable = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(Scrollable),
    );
    atEach();
    for (var i = 0; i < 20; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
      atEach();
    }
  }

  test('the fold holds what the cases read', () {
    expect(report.trend, isNotNull);
    expect(report.categories, isNotEmpty);
    expect(report.missed, isNotEmpty);
  });

  testWidgets('draws the totals, the trend and the groups under their ids', (
    tester,
  ) async {
    await pumpBody(tester);
    expect(byId(SemanticsIds.reportBody), findsOneWidget);
    expect(byId(SemanticsIds.reportTile('events')), findsOneWidget);
    expect(byId(SemanticsIds.reportNavTitle), findsOneWidget);
    expect(byId(SemanticsIds.reportGroup('categories', 'gym')), findsOneWidget);
    final seen = <String>{};
    await scrollThrough(tester, () {
      for (final id in [
        SemanticsIds.reportTrend,
        SemanticsIds.reportGroup('missed', 'gym'),
        SemanticsIds.reportRow(gym.id, DateTime.utc(2026, 10, 13)),
        SemanticsIds.reportShowList,
        SemanticsIds.reportShare,
        SemanticsIds.reportSend,
      ]) {
        if (byId(id).evaluate().isNotEmpty) seen.add(id);
      }
    });
    expect(seen, hasLength(6));
  });

  testWidgets('an unprofiled report inserts no sliver and moves nothing: the '
      'sequence, the Totals label and the scroll extent as before S4', (
    tester,
  ) async {
    await pumpBody(tester);
    expect(report.goals, isEmpty);
    expect(report.insights, isEmpty);
    expect(report.dueSoon, isEmpty);
    expect(sliverSequence(tester), [
      'label Totals',
      'ReportTotalsCard',
      'FormCaption',
      'SizedBox',
      'label Categories',
      'ReportGroupStack',
      'SizedBox',
      'label Over time',
      'ReportTrendChart',
      'SizedBox',
      'label Missed',
      'ReportGroupStack',
      'SizedBox',
      'FormRowGroup',
    ]);
    expect(tester.getTopLeft(sectionLabel('Totals')), const Offset(16, 82));
    expect(
      tester.getTopLeft(find.byType(ReportTotalsCard)),
      const Offset(16, 102),
    );
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: byId(SemanticsIds.reportBody),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(position.maxScrollExtent, 574);
  });

  group('the analytics cards above Totals (§2.1)', () {
    const sep = ReportLabels.separator;

    /// [report] with the analytics a profiled calendar carries; the rest
    /// of the fold as it came.
    CalendarReport profiled({
      ReportTense? tense,
      List<ReportGoal> goals = const [],
      List<ReportDueRow> dueSoon = const [],
      List<ReportInsight> insights = const [],
      Map<String, ReportMeasures>? measures,
      List<ReportCategoryGroup>? missed,
    }) => CalendarReport(
      span: report.span,
      today: report.today,
      tense: tense ?? report.tense,
      countedTo: report.countedTo,
      previousSpan: report.previousSpan,
      previousCounted: report.previousCounted,
      events: report.events,
      tiles: report.tiles,
      skippedDays: report.skippedDays,
      aheadCount: report.aheadCount,
      categories: report.categories,
      trend: report.trend,
      missed: missed ?? report.missed,
      ahead: report.ahead,
      measures: measures ?? report.measures,
      goals: goals,
      dueSoon: dueSoon,
      insights: insights,
    );
    final gymGoal = ReportGoal(
      categoryId: 'gym',
      measure: ReportMeasure.count,
      target: const ReportTarget(
        kind: TargetKind.atLeast,
        value: 2,
        period: TargetPeriod.week,
      ),
      periods: [
        ReportGoalPeriod(
          start: DateTime.utc(2026, 10, 26),
          end: DateTime.utc(2026, 11, 1),
          value: 1,
          expected: 1,
          state: GoalState.onPace,
        ),
      ],
    );
    final gymDue = ReportDueRow(
      categoryId: 'gym',
      eventId: gym.id,
      day: DateTime.utc(2026, 10, 29),
      kind: ReportDueKind.unmarked,
      state: ReportDueState.unmarked,
      days: 1,
    );
    const trend = ReportInsight(
      rule: InsightRule.t1,
      severity: 1,
      categoryId: 'gym',
      target: InsightTarget.categoryGroup,
      n1: 8,
      n2: 5,
      ratio: 0.6,
    );
    // The Goals card says this one already, so the page drops it (H).
    const behind = ReportInsight(
      rule: InsightRule.g1,
      severity: 3,
      categoryId: 'gym',
      target: InsightTarget.categoryGroup,
    );
    const totalsOn = [
      'label Totals',
      'ReportTotalsCard',
      'FormCaption',
      'SizedBox',
      'label Categories',
    ];

    testWidgets('Goals, Insights and Due soon lead, a gap between each and '
        'before Totals', (tester) async {
      await pumpBody(
        tester,
        shown: profiled(
          goals: [gymGoal],
          dueSoon: [gymDue],
          insights: const [trend],
        ),
      );
      expect(sliverSequence(tester).take(14), [
        'label Goals',
        'ReportGoalsCard',
        'SizedBox',
        'label Insights',
        'ReportInsightsCard',
        'SizedBox',
        'label Due soon',
        'ReportDueSoonCard',
        'SizedBox',
        ...totalsOn,
      ]);
      expect(tester.getTopLeft(sectionLabel('Goals')).dy, 82);
      expect(
        tester.getTopLeft(sectionLabel('Totals')).dy,
        greaterThan(tester.getTopLeft(sectionLabel('Due soon')).dy),
      );
      // Plain labels: the page's headings stay the bar's (U).
      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        final label = tester
            .getSemantics(find.text('GOALS'))
            .getSemanticsData();
        expect(label.headingLevel, 0);
      } finally {
        handle.dispose();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card with nothing to show is absent with its label, and '
        'the first card has no gap above it', (tester) async {
      await pumpBody(
        tester,
        shown: profiled(dueSoon: [gymDue], insights: const [trend]),
      );
      expect(sliverSequence(tester).take(11), [
        'label Insights',
        'ReportInsightsCard',
        'SizedBox',
        'label Due soon',
        'ReportDueSoonCard',
        'SizedBox',
        ...totalsOn,
      ]);

      await pumpBody(tester, shown: profiled(goals: [gymGoal]));
      expect(sliverSequence(tester).take(8), [
        'label Goals',
        'ReportGoalsCard',
        'SizedBox',
        ...totalsOn,
      ]);

      // The one insight is the goal's own news: Insights is absent (H).
      await pumpBody(
        tester,
        shown: profiled(goals: [gymGoal], insights: const [behind]),
      );
      expect(sliverSequence(tester).take(8), [
        'label Goals',
        'ReportGoalsCard',
        'SizedBox',
        ...totalsOn,
      ]);
      expect(sectionLabel('Insights'), findsNothing);
    });

    testWidgets('a plan shows Goals then Due soon, and no Insights', (
      tester,
    ) async {
      await pumpBody(
        tester,
        shown: profiled(
          tense: ReportTense.future,
          goals: [gymGoal],
          dueSoon: [gymDue],
          insights: const [trend],
        ),
      );
      expect(sliverSequence(tester).take(7), [
        'label Goals',
        'ReportGoalsCard',
        'SizedBox',
        'label Due soon',
        'ReportDueSoonCard',
        'SizedBox',
        'label Totals',
      ]);
      expect(sectionLabel('Insights'), findsNothing);
    });

    testWidgets('a profiled Categories header leads with its primary; '
        'Missed keeps its facts', (tester) async {
      final group = report.categories.firstWhere(
        (group) => group.categoryId == 'gym',
      );
      await pumpBody(
        tester,
        shown: profiled(
          measures: {
            'gym': const ReportMeasures(
              categoryId: 'gym',
              primary: ReportMeasure.hours,
              profiled: true,
              minutes: 31 * 60,
            ),
          },
        ),
      );
      final header = tester.widget<FormMeterRow>(
        find
            .ancestor(
              of: byId(SemanticsIds.reportGroup('categories', 'gym')),
              matching: find.byType(FormMeterRow),
            )
            .first,
      );
      expect(
        header.caption,
        [
          '31 h',
          '${group.count}',
          if (group.missed > 0) '${group.missed} missed',
        ].join(sep),
      );
      expect(
        header.semanticsLabel,
        endsWith(
          [
            '31 hours',
            '${group.count} events',
            if (group.missed > 0) '${group.missed} missed',
          ].join(', '),
        ),
      );
      final missed = report.missed.firstWhere(
        (group) => group.categoryId == 'gym',
      );
      final scrollable = find.descendant(
        of: byId(SemanticsIds.reportBody),
        matching: find.byType(Scrollable),
      );
      final missedHeader = byId(SemanticsIds.reportGroup('missed', 'gym'));
      await tester.scrollUntilVisible(
        missedHeader,
        300,
        scrollable: scrollable,
      );
      final missedRow = tester.widget<FormMeterRow>(
        find
            .ancestor(of: missedHeader, matching: find.byType(FormMeterRow))
            .first,
      );
      expect(missedRow.caption, '${missed.missed} missed');
    });

    /// The body's one scroll position.
    ScrollPosition bodyScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: byId(SemanticsIds.reportBody),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    double bodyTop(WidgetTester tester) =>
        tester.getTopLeft(byId(SemanticsIds.reportBody)).dy;

    /// The Totals label's top on screen; above the viewport once scrolled
    /// past, so offstage to a plain finder.
    double totalsTop(WidgetTester tester) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (widget) => widget is FormSectionLabel && widget.text == 'Totals',
            skipOffstage: false,
          ),
        )
        .dy;

    const short = Size(360, 520);

    /// [first] on the short phone, scrolled until the viewport's top lies
    /// [past] below the Totals label's top.
    Future<void> pastTotals(
      WidgetTester tester,
      CalendarReport first, {
      double past = 60,
    }) async {
      await pumpBody(tester, surface: short, shown: first);
      bodyScroll(tester).jumpTo(totalsTop(tester) - bodyTop(tester) + past);
      await tester.pump();
      expect(totalsTop(tester), closeTo(bodyTop(tester) - past, 0.01));
    }

    const another = ReportInsight(
      rule: InsightRule.t1,
      severity: 1,
      categoryId: 'birthday',
      target: InsightTarget.categoryGroup,
      n1: 3,
      n2: 1,
      ratio: 2,
    );

    for (final (name, insights, missed) in [
      ('the insights gone, Missed kept', const <ReportInsight>[], null),
      (
        'the insights gone and Missed gone',
        const <ReportInsight>[],
        const <ReportCategoryGroup>[],
      ),
      (
        'the insights kept and Missed gone',
        const [trend],
        const <ReportCategoryGroup>[],
      ),
    ]) {
      testWidgets('a refold with $name holds the Totals label past the '
          'viewport\'s top (R): the anchor keeps its memory', (tester) async {
        await pastTotals(
          tester,
          profiled(dueSoon: [gymDue], insights: const [trend]),
        );
        final label = totalsTop(tester);
        await pumpBody(
          tester,
          surface: short,
          shown: profiled(
            dueSoon: [gymDue],
            insights: insights,
            missed: missed,
          ),
        );
        expect(
          find.byWidgetPredicate(
            (widget) => widget is FormSectionLabel && widget.text == 'Insights',
            skipOffstage: false,
          ),
          insights.isEmpty ? findsNothing : findsOneWidget,
        );
        expect(sliverSequence(tester).contains('label Missed'), missed == null);
        expect(totalsTop(tester), closeTo(label, 0.01));
        final position = bodyScroll(tester);
        expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a refold that shrinks the cards above Totals corrects the '
        'offset down and holds the label (R)', (tester) async {
      await pastTotals(
        tester,
        profiled(dueSoon: [gymDue], insights: const [trend, another]),
      );
      final label = totalsTop(tester);
      final offset = bodyScroll(tester).pixels;
      await pumpBody(
        tester,
        surface: short,
        shown: profiled(dueSoon: [gymDue], insights: const [trend]),
      );
      expect(bodyScroll(tester).pixels, lessThan(offset));
      expect(totalsTop(tester), closeTo(label, 0.01));
    });

    testWidgets('a label only partly scrolled off is held too (R)', (
      tester,
    ) async {
      await pastTotals(
        tester,
        profiled(dueSoon: [gymDue], insights: const [trend]),
        past: 4,
      );
      final label = totalsTop(tester);
      await pumpBody(
        tester,
        surface: short,
        shown: profiled(dueSoon: [gymDue], insights: const [trend, another]),
      );
      expect(totalsTop(tester), closeTo(label, 0.01));
    });

    testWidgets('a step, a pick or a category change is not a refold: past '
        'Totals the offset stays as it was and the label moves', (
      tester,
    ) async {
      const september = OverviewMonthPeriod(2026, 9);
      await pastTotals(
        tester,
        profiled(dueSoon: [gymDue], insights: const [trend]),
      );
      final offset = bodyScroll(tester).pixels;
      final label = totalsTop(tester);
      await pumpBody(
        tester,
        surface: short,
        period: september,
        shown: profiled(dueSoon: [gymDue], insights: const [trend, another]),
      );
      expect(bodyScroll(tester).pixels, offset);
      expect(totalsTop(tester), greaterThan(label));

      final moved = totalsTop(tester);
      await pumpBody(
        tester,
        surface: short,
        period: september,
        categoryIds: const {'gym'},
        shown: profiled(dueSoon: [gymDue], insights: const [trend]),
      );
      expect(bodyScroll(tester).pixels, offset);
      expect(totalsTop(tester), lessThan(moved));
    });

    testWidgets('revealAtTop on a header already at the top moves nothing '
        'and throws nothing', (tester) async {
      await pumpBody(tester, surface: short);
      final header = byId(SemanticsIds.reportGroup('categories', 'gym'));
      final position = bodyScroll(tester);
      position.jumpTo(tester.getTopLeft(header).dy - bodyTop(tester));
      await tester.pump();
      expect(tester.getTopLeft(header).dy, closeTo(bodyTop(tester), 0.01));
      final offset = position.pixels;
      final scroll = tester
          .widget<CustomScrollView>(
            find.descendant(
              of: byId(SemanticsIds.reportBody),
              matching: find.byType(CustomScrollView),
            ),
          )
          .controller!;

      revealAtTop(scroll, () => tester.renderObject(header));
      await tester.pump();
      await tester.pump();
      expect(position.pixels, offset);
      expect(tester.getTopLeft(header).dy, closeTo(bodyTop(tester), 0.01));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('with every callback null no tap opens a route or leaves the '
      'body, and the Missed row has no presence button', (tester) async {
    await pumpBody(tester);
    // An inert row is no button and offers no tap: a routine aggregate and a
    // dated row (the reviewer's probe read `tap=false button=false`). The
    // handle goes in a `finally`: flutter_test checks for a live one before
    // any `addTearDown` runs.
    final handle = tester.ensureSemantics();
    try {
      await tester.pump();
      for (final id in [
        SemanticsIds.reportRoutine(gym.id),
        SemanticsIds.reportRow(dentist.id, DateTime.utc(2026, 10, 9)),
      ]) {
        final data = tester.getSemantics(byId(id).first).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isFalse, reason: id);
        expect(data.flagsCollection.isButton, isFalse, reason: id);
      }
    } finally {
      handle.dispose();
    }
    final scrollable = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(Scrollable),
    );
    // Every row and tile on screen tapped, a screen at a time to the end.
    var tapped = 0;
    for (var i = 0; i < 20; i++) {
      final rows = [
        ...find.byType(FormPickerRow).evaluate(),
        ...find.byType(FormActionRow).evaluate(),
        ...find.byType(ReportTotalsCard).evaluate(),
      ];
      for (final row in rows) {
        if (!row.mounted) continue;
        final box = row.renderObject;
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final centre = box.localToGlobal(box.size.center(Offset.zero));
        if (centre.dy < 0 || centre.dy >= 780) continue;
        await tester.tapAt(centre);
        await tester.pumpAndSettle();
        tapped++;
      }
      final position = tester.state<ScrollableState>(scrollable).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(tapped, greaterThan(0));
    expect(pushes.pushes, 0);
    expect(AppNavigator.pendingOverviewLook.value, isNull);
    expect(tester.takeException(), isNull);
    expect(
      byId(SemanticsIds.reportRowPresence(gym.id, DateTime.utc(2026, 10, 13))),
      findsNothing,
    );
    for (final id in [
      SemanticsIds.reportShowList,
      SemanticsIds.reportShare,
      SemanticsIds.reportSend,
    ]) {
      final row = tester.widget<FormActionRow>(
        find.ancestor(of: byId(id), matching: find.byType(FormActionRow)).first,
      );
      expect(row.onTap, isNull, reason: id);
    }
  });

  testWidgets('a header tap folds its group and opens it again', (
    tester,
  ) async {
    await pumpBody(tester);
    final header = byId(SemanticsIds.reportGroup('categories', 'gym'));
    final rowsBelow = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(FormPickerRow),
    );
    final open = rowsBelow.evaluate().length;
    expect(folds.isOpen(ReportCard.categories, 'gym'), isTrue);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(folds.isOpen(ReportCard.categories, 'gym'), isFalse);
    expect(rowsBelow.evaluate().length, lessThan(open));

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(folds.isOpen(ReportCard.categories, 'gym'), isTrue);
    expect(rowsBelow.evaluate().length, open);
  });

  testWidgets('de at 2.0 on 360 × 780 lays the band and the body out with no '
      'overflow', (tester) async {
    await pumpBody(tester, locale: const Locale('de'), textScale: 2);
    await scrollThrough(tester, () => expect(tester.takeException(), isNull));
  });

  testWidgets('the band with no callbacks draws every control disabled', (
    tester,
  ) async {
    // Away from the home, so only the missing `onHome` can null Today.
    await pumpBody(
      tester,
      bandPeriod: october.stepped(
        direction: -1,
        today: today,
        yearBounds: years,
      ),
    );
    final nav = tester.widget<AgendaPeriodNav>(find.byType(AgendaPeriodNav));
    expect(nav.onTitleTap, isNull);
    expect(nav.onPrevious, isNull);
    expect(nav.onNext, isNull);
    expect(nav.onToday, isNull);
    expect(byId(SemanticsIds.reportNavPrevious), findsOneWidget);
    expect(byId(SemanticsIds.reportNavNext), findsOneWidget);
    expect(byId(SemanticsIds.reportNavToday), findsOneWidget);
  });

  group('a wide year', () {
    // Every built-in category with an event, so the card caps at seven; a
    // daily routine assumed absent, so its Missed group runs past the
    // expansion's cap.
    const year = OverviewYearPeriod(2026);
    late CalendarReport wide;
    late String dailyCategory;

    setUp(() {
      final seeds = CalendarCategories.builtInSeeds;
      dailyCategory = seeds.first.id;
      final daily = CalendarEvent(
        id: 'e-daily',
        title: 'Stretch',
        categoryId: dailyCategory,
        startDate: DateTime.utc(2025, 1, 1),
        rule: const DailyRecurrence(),
        tracksPresence: true,
        assumeAbsent: true,
      );
      wide = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(
          ReportRequest(
            span: year.resolve(today: today, yearBounds: years),
            events: [
              for (final (index, seed) in seeds.indexed)
                CalendarEvent(
                  id: 'e-$index',
                  title: 'Event $index',
                  categoryId: seed.id,
                  startDate: DateTime.utc(2026, 3, 1 + index),
                ),
              daily,
            ],
            today: today,
            weekStart: CalendarWeekStart.monday,
          ),
        ),
      );
    });

    test('the fold holds what the cases read', () {
      expect(
        wide.categories.length,
        greaterThan(ReportMetrics.maxCategoryRows),
      );
      expect(
        wide.missed.first.rows.length,
        greaterThan(ReportMetrics.maxListRows),
      );
    });

    testWidgets('"n more categories" and a capped group\'s Show as list are '
        'drawn disabled, never hidden', (tester) async {
      await pumpBody(tester, shown: wide, period: year);
      final scrollable = find
          .descendant(
            of: byId(SemanticsIds.reportBody),
            matching: find.byType(Scrollable),
          )
          .first;
      // The handle in a `finally`, as in the no-tap case.
      Future<void> expectDisabled(String id) async {
        final row = tester.widget<FormActionRow>(
          find
              .ancestor(of: byId(id), matching: find.byType(FormActionRow))
              .first,
        );
        expect(row.onTap, isNull, reason: id);
        final handle = tester.ensureSemantics();
        try {
          await tester.pump();
          final data = tester.getSemantics(byId(id).first).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isFalse, reason: id);
        } finally {
          handle.dispose();
        }
      }

      await tester.scrollUntilVisible(
        byId(SemanticsIds.reportCategoriesMore),
        300,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await expectDisabled(SemanticsIds.reportCategoriesMore);

      // The Missed group's "n more" is the body's own: it opens in place.
      final more = byId(SemanticsIds.reportGroupMore('missed', dailyCategory));
      await tester.scrollUntilVisible(more, 300, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(folds.isExpanded(ReportCard.missed, dailyCategory), isTrue);
      final list = byId(SemanticsIds.reportGroupList('missed', dailyCategory));
      await tester.scrollUntilVisible(list, 600, scrollable: scrollable);
      await tester.pumpAndSettle();
      await expectDisabled(
        SemanticsIds.reportGroupList('missed', dailyCategory),
      );
      expect(pushes.pushes, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
