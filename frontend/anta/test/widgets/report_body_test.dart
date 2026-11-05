import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/analytics_metrics.dart';
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
import 'package:anta/models/date_range.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/overview_view.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/utils/calendar_report_builder.dart';
import 'package:anta/utils/date_span_label.dart';
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

  /// The body's padded sliver group, the Totals block's own slivers in its
  /// builder's place: the builder reads the width alone, the slivers it
  /// builds are the page's.
  List<Widget> bodySlivers(WidgetTester tester) {
    List<Widget> children(Finder of) => tester
        .widget<SliverMainAxisGroup>(
          find
              .descendant(of: of, matching: find.byType(SliverMainAxisGroup))
              .first,
        )
        .children;
    return [
      for (final sliver in children(byId(SemanticsIds.reportBody)))
        if (sliver is SliverLayoutBuilder)
          ...children(find.byWidget(sliver))
        else
          sliver,
    ];
  }

  /// The body's slivers as words: a section label by its text, a boxed
  /// child by its type through its repaint boundary, any other sliver by
  /// its own type — what an unprofiled page must keep and the new cards
  /// insert into.
  List<String> sliverSequence(WidgetTester tester) {
    return [
      for (final sliver in bodySlivers(tester))
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
    ({int first, int last}) yearBounds = years,
    ReportCompare compare = ReportCompare.previous,
    OverviewView? compareView,
    OverviewView? foldedCompareView,
    List<OverviewView> views = const [],
    void Function(ReportCompare compare, OverviewView? view)? onCompare,
    ReportShowAsList? onShowAsList,
    VoidCallback? onReveal,
    void Function(
      CalendarReport report, {
      required int largest,
      required bool spansMonths,
    })?
    onMoreCategories,
    void Function(
      CalendarReport report, {
      required String periodName,
      required String? against,
      required String? beside,
    })?
    onShare,
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
                    years: yearBounds,
                    labels: labels,
                  ),
                  Expanded(
                    child: ReportBody(
                      report: shown ?? report,
                      period: period,
                      categoryIds: categoryIds,
                      today: today,
                      years: yearBounds,
                      weekStart: CalendarWeekStart.monday,
                      labels: labels,
                      folds: folds,
                      bottomClearance: 0,
                      use24Hour: true,
                      compare: compare,
                      compareView: compareView,
                      // Ready: the report drawn is the asked one's.
                      foldedCompareView: foldedCompareView ?? compareView,
                      views: views,
                      onCompare: onCompare,
                      onShowAsList: onShowAsList,
                      onReveal: onReveal,
                      onMoreCategories: onMoreCategories,
                      onShare: onShare,
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

    testWidgets('a refold read inside the leading Insights card that drops '
        'it stops at the scroll\'s start: the next label held never pulls '
        'the offset under 0', (tester) async {
      await pumpBody(
        tester,
        surface: short,
        shown: profiled(dueSoon: [gymDue], insights: const [trend, another]),
      );
      final position = bodyScroll(tester);
      position.jumpTo(40);
      await tester.pump();
      expect(
        tester.getTopLeft(sectionLabel('Due soon')).dy,
        greaterThan(bodyTop(tester)),
      );
      // A correction moves the offset silently; a spring back from under 0
      // would be heard frame by frame.
      final heard = <double>[];
      void hear() => heard.add(position.pixels);
      position.addListener(hear);
      addTearDown(() => position.removeListener(hear));

      await pumpBody(
        tester,
        surface: short,
        shown: profiled(dueSoon: [gymDue]),
      );
      expect(sectionLabel('Insights'), findsNothing);
      expect(position.pixels, 0);
      expect(heard, everyElement(greaterThanOrEqualTo(0)));
      expect(tester.takeException(), isNull);
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

    testWidgets('a strip whose category is past the Categories cap opens the '
        'More categories sheet, handed the report (S4 G)', (tester) async {
      final past = wide.categories[ReportMetrics.maxCategoryRows].categoryId;
      expect(ReportBody.stripIds(wide), contains(past));
      // The Months card caps its strips too: open, so the strip is drawn.
      folds.setMonthsExpanded(true);
      final handed = <({CalendarReport report, int largest, bool months})>[];
      await pumpBody(
        tester,
        shown: wide,
        period: year,
        onMoreCategories: (report, {required largest, required spansMonths}) =>
            handed.add((report: report, largest: largest, months: spansMonths)),
      );
      final strip = byId(SemanticsIds.reportYearMonths(past));
      await tester.scrollUntilVisible(
        strip,
        200,
        scrollable: find
            .descendant(
              of: byId(SemanticsIds.reportBody),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(strip);
      await tester.pumpAndSettle();
      expect(handed, hasLength(1));
      expect(handed.single.report, same(wide));
      expect(handed.single.largest, wide.categories.first.count);
      expect(handed.single.months, isTrue);
      expect(pushes.pushes, 0);
      expect(tester.takeException(), isNull);
    });

    /// The strip of [categoryId], scrolled on screen, and its row.
    Future<(Finder, FormMeterRow)> stripOf(
      WidgetTester tester,
      String categoryId,
    ) async {
      // Either way from where the last tap left the scroll.
      final strip = find.bySemanticsIdentifier(
        SemanticsIds.reportYearMonths(categoryId),
        skipOffstage: false,
      );
      await tester.ensureVisible(strip);
      await tester.pumpAndSettle();
      final row = tester.widget<FormMeterRow>(
        find.ancestor(of: strip, matching: find.byType(FormMeterRow)).first,
      );
      return (strip, row);
    }

    testWidgets('with only onMoreCategories a strip inside the Categories cap '
        'is a read row, and one past it still opens the sheet', (tester) async {
      final inside = wide.categories.first.categoryId;
      final past = wide.categories[ReportMetrics.maxCategoryRows].categoryId;
      folds.setMonthsExpanded(true);
      var sheets = 0;
      await pumpBody(
        tester,
        shown: wide,
        period: year,
        onMoreCategories: (_, {required largest, required spansMonths}) =>
            sheets++,
      );
      final (insideStrip, insideRow) = await stripOf(tester, inside);
      expect(insideRow.onTap, isNull);
      await tester.tap(insideStrip);
      await tester.pumpAndSettle();
      expect(sheets, 0);

      final (pastStrip, pastRow) = await stripOf(tester, past);
      expect(pastRow.onTap, isNotNull);
      await tester.tap(pastStrip);
      await tester.pumpAndSettle();
      expect(sheets, 1);
      expect(pushes.pushes, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with only onReveal a strip inside the Categories cap opens '
        'its group, and one past it is a read row', (tester) async {
      final inside = wide.categories.first.categoryId;
      final past = wide.categories[ReportMetrics.maxCategoryRows].categoryId;
      folds.setMonthsExpanded(true);
      var reveals = 0;
      await pumpBody(
        tester,
        shown: wide,
        period: year,
        onReveal: () => reveals++,
      );
      final (pastStrip, pastRow) = await stripOf(tester, past);
      expect(pastRow.onTap, isNull);
      await tester.tap(pastStrip);
      await tester.pumpAndSettle();
      expect(reveals, 0);

      final (insideStrip, insideRow) = await stripOf(tester, inside);
      expect(insideRow.onTap, isNotNull);
      await tester.tap(insideStrip);
      await tester.pumpAndSettle();
      expect(reveals, 1);
      expect(pushes.pushes, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('the year in review (S6 §2.1)', () {
    const year2025 = OverviewYearPeriod(2025);

    /// Tuesdays and Thursdays through 2025.
    final lift = CalendarEvent(
      id: 'e-lift',
      title: 'Lifting',
      categoryId: 'gym',
      startDate: DateTime.utc(2025, 1, 7),
      rule: const WeeklyRecurrence(weekdays: {2, 4}),
      time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    );

    /// One time, in June.
    final checkup = CalendarEvent(
      id: 'e-checkup',
      title: 'Checkup',
      categoryId: 'other',
      startDate: DateTime.utc(2025, 6, 12),
      rule: const OneTimeRecurrence(),
    );

    late CalendarReport folded;

    setUp(() {
      folded = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(
          ReportRequest(
            span: year2025.resolve(today: today, yearBounds: years),
            previousSpan: year2025
                .stepped(direction: -1, today: today, yearBounds: years)
                ?.resolve(today: today, yearBounds: years),
            events: [lift, checkup, birthday],
            today: today,
            weekStart: CalendarWeekStart.monday,
          ),
        ),
      );
    });

    final busiestMonth = ReportRecord(
      kind: ReportRecordKind.busiestMonth,
      value: 10,
      start: DateTime.utc(2025, 7, 1),
      end: DateTime.utc(2025, 7, 31),
    );
    final busiestWeek = ReportRecord(
      kind: ReportRecordKind.busiestWeek,
      value: 2,
      start: DateTime.utc(2025, 1, 6),
      end: DateTime.utc(2025, 1, 12),
    );
    final socialMonth = ReportRecord(
      kind: ReportRecordKind.socialMonth,
      value: 1,
      start: DateTime.utc(2025, 10, 1),
      end: DateTime.utc(2025, 10, 31),
    );

    /// Twelve months for Gym and Other, each with its kept span; [strips]
    /// false keys them to Cardio alone, a category the report has no group
    /// for, so the card has nothing to draw.
    ReportYear yearOf({List<ReportRecord>? records, bool strips = true}) =>
        ReportYear(
          records: records ?? [busiestMonth, busiestWeek],
          months: strips
              ? const {
                  'gym': [9, 8, 9, 9, 8, 9, 10, 8, 9, 9, 8, 9],
                  'other': [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
                }
              : const {
                  'cardio': [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
                },
          spans: strips
              ? {
                  'gym': (
                    first: DateTime.utc(2025, 1, 7),
                    last: DateTime.utc(2025, 12, 30),
                  ),
                  'other': (
                    first: DateTime.utc(2025, 6, 12),
                    last: DateTime.utc(2025, 6, 12),
                  ),
                }
              : {
                  'cardio': (
                    first: DateTime.utc(2025, 1, 2),
                    last: DateTime.utc(2025, 12, 30),
                  ),
                },
          goalTallies: const {
            'gym': ReportGoalTally(met: 41, closed: 52, longestStreak: 11),
          },
        );

    /// A weekly goal on [categoryId], its last week met.
    ReportGoal weekly(String categoryId) => ReportGoal(
      categoryId: categoryId,
      measure: ReportMeasure.count,
      target: const ReportTarget(
        kind: TargetKind.atLeast,
        value: 2,
        period: TargetPeriod.week,
      ),
      periods: [
        ReportGoalPeriod(
          start: DateTime.utc(2025, 12, 22),
          end: DateTime.utc(2025, 12, 28),
          value: 2,
          expected: 2,
          state: GoalState.met,
        ),
      ],
    );

    /// [folded] — 2025 seen from 30 October 2026 — with [year] in place of
    /// the fold's own and [goals]; the rest as it came.
    CalendarReport wholeYear({ReportYear? year, List<ReportGoal>? goals}) =>
        CalendarReport(
          span: folded.span,
          today: folded.today,
          tense: folded.tense,
          countedTo: folded.countedTo,
          previousSpan: folded.previousSpan,
          previousCounted: folded.previousCounted,
          events: folded.events,
          tiles: folded.tiles,
          skippedDays: folded.skippedDays,
          aheadCount: folded.aheadCount,
          categories: folded.categories,
          trend: folded.trend,
          missed: folded.missed,
          ahead: folded.ahead,
          measures: folded.measures,
          goals: goals ?? [weekly('gym')],
          year: year ?? yearOf(),
        );

    Finder bodyScrollable() => find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(Scrollable),
    );

    ScrollPosition scrollOf(WidgetTester tester) =>
        tester.state<ScrollableState>(bodyScrollable()).position;

    double bodyTop(WidgetTester tester) =>
        tester.getTopLeft(byId(SemanticsIds.reportBody)).dy;

    /// The section labels' slivers that are refold anchors, by their text.
    List<String> anchoredLabels(WidgetTester tester) => [
      for (final sliver in bodySlivers(tester))
        if ('${sliver.runtimeType}' == '_AnchoredLabel' &&
            sliver is SliverToBoxAdapter &&
            sliver.child is FormSectionLabel)
          (sliver.child! as FormSectionLabel).text,
    ];

    test('the fold holds what the cases read', () {
      expect(folded.tense, ReportTense.past);
      expect(folded.year, isNotNull);
      expect([
        for (final group in folded.categories) group.categoryId,
      ], containsAll(['gym', 'other']));
    });

    testWidgets('Records and Months sit between the Totals caption and '
        'Categories, each under its label, both anchors, in one scroll', (
      tester,
    ) async {
      await pumpBody(tester, period: year2025, shown: wholeYear());
      expect(sliverSequence(tester).take(16), [
        'label Goals',
        'ReportGoalsCard',
        'SizedBox',
        'label Totals',
        'ReportTotalsCard',
        'FormCaption',
        'SizedBox',
        'label Records',
        'ReportRecordsCard',
        'SizedBox',
        'label Months',
        'ReportMonthsCard',
        'SizedBox',
        'label Categories',
        'ReportGroupStack',
        'SizedBox',
      ]);
      expect(
        anchoredLabels(tester),
        containsAllInOrder(['Goals', 'Totals', 'Records', 'Months']),
      );
      expect(
        byId(SemanticsIds.reportYearRecord('busiest-month')),
        findsOneWidget,
      );
      expect(bodyScrollable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Records is absent with no record, Months with no strip — '
        'each with its label and its gap', (tester) async {
      await pumpBody(tester, period: year2025, shown: wholeYear());
      final full = sliverSequence(tester);

      await pumpBody(
        tester,
        period: year2025,
        shown: wholeYear(year: yearOf(records: const [])),
      );
      var sequence = sliverSequence(tester);
      expect(sequence, isNot(contains('label Records')));
      expect(sequence, contains('label Months'));
      expect(sequence, hasLength(full.length - 3));

      // Months keyed to a category with no group: the card draws nothing,
      // so its label stays away too.
      await pumpBody(
        tester,
        period: year2025,
        shown: wholeYear(year: yearOf(strips: false)),
      );
      sequence = sliverSequence(tester);
      expect(sequence, contains('label Records'));
      expect(sequence, isNot(contains('label Months')));
      expect(sequence, hasLength(full.length - 3));

      await pumpBody(
        tester,
        period: year2025,
        shown: wholeYear(year: yearOf(records: const [], strips: false)),
      );
      sequence = sliverSequence(tester);
      expect(sequence, isNot(contains('label Records')));
      expect(sequence, isNot(contains('label Months')));
      expect(sequence, hasLength(full.length - 6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a month and a plan year fold no year and insert nothing; '
        'the October pins hold', (tester) async {
      const plan = OverviewYearPeriod(2027);
      const planYears = (first: 2020, last: 2027);
      final planned = CalendarReportBuilder.fold(
        CalendarReportService.sampleInput(
          ReportRequest(
            span: plan.resolve(today: today, yearBounds: planYears),
            events: [lift, checkup, birthday],
            today: today,
            weekStart: CalendarWeekStart.monday,
          ),
        ),
      );
      expect(planned.tense, ReportTense.future);
      expect(planned.year, isNull);
      await pumpBody(
        tester,
        period: plan,
        yearBounds: planYears,
        shown: planned,
      );
      expect(sectionLabel('Records'), findsNothing);
      expect(sectionLabel('Months'), findsNothing);
      expect(find.bySemanticsIdentifier(RegExp('^report-year-')), findsNothing);

      expect(report.year, isNull);
      await pumpBody(tester);
      expect(sliverSequence(tester).take(5), [
        'label Totals',
        'ReportTotalsCard',
        'FormCaption',
        'SizedBox',
        'label Categories',
      ]);
      expect(tester.getTopLeft(sectionLabel('Totals')), const Offset(16, 82));
      expect(scrollOf(tester).maxScrollExtent, 574);
    });

    testWidgets('a strip\'s tap opens its Categories group and lands its '
        'header at the top (S4 G)', (tester) async {
      var reveals = 0;
      // Closed by its header on an earlier visit.
      folds.setOpen(ReportCard.categories, 'other', false);
      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(),
        onReveal: () => reveals++,
      );
      final strip = byId(SemanticsIds.reportYearMonths('other'));
      await tester.scrollUntilVisible(strip, 200, scrollable: bodyScrollable());
      await tester.pumpAndSettle();
      await tester.tap(strip);
      await tester.pumpAndSettle();
      expect(reveals, 1);
      expect(folds.isOpen(ReportCard.categories, 'other'), isTrue);
      expect(
        tester
            .getTopLeft(byId(SemanticsIds.reportGroup('categories', 'other')))
            .dy,
        closeTo(bodyTop(tester), 1),
      );
      expect(pushes.pushes, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with onReveal null a strip is a read row', (tester) async {
      await pumpBody(tester, period: year2025, shown: wholeYear());
      final strip = byId(SemanticsIds.reportYearMonths('gym'));
      await tester.scrollUntilVisible(strip, 200, scrollable: bodyScrollable());
      await tester.pumpAndSettle();
      final row = tester.widget<FormMeterRow>(
        find.ancestor(of: strip, matching: find.byType(FormMeterRow)).first,
      );
      expect(row.onTap, isNull);
      final offset = scrollOf(tester).pixels;
      await tester.tap(strip);
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, offset);
      expect(pushes.pushes, 0);
    });

    testWidgets('a refold that grows the Goals and Records cards holds the '
        'Months label under the viewport\'s top (S6 H)', (tester) async {
      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(),
      );
      double monthsTop() => tester
          .getTopLeft(
            find.byWidgetPredicate(
              (widget) => widget is FormSectionLabel && widget.text == 'Months',
              skipOffstage: false,
            ),
          )
          .dy;
      scrollOf(tester).jumpTo(monthsTop() - bodyTop(tester) + 20);
      await tester.pump();
      final label = monthsTop();
      expect(label, closeTo(bodyTop(tester) - 20, 0.01));
      final offset = scrollOf(tester).pixels;

      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(
          goals: [weekly('gym'), weekly('other')],
          year: yearOf(records: [busiestMonth, busiestWeek, socialMonth]),
        ),
      );
      expect(scrollOf(tester).pixels, greaterThan(offset));
      expect(monthsTop(), closeTo(label, 0.01));
      expect(tester.takeException(), isNull);
    });

    /// The top of the section label [text], scrolled off or not.
    double labelTop(WidgetTester tester, String text) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (widget) => widget is FormSectionLabel && widget.text == text,
            skipOffstage: false,
          ),
        )
        .dy;

    testWidgets('a refold read inside the Records card holds its rows under '
        'the viewport\'s top: Records is the anchor (S6 H)', (tester) async {
      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(),
      );
      scrollOf(
        tester,
      ).jumpTo(labelTop(tester, 'Records') - bodyTop(tester) + 20);
      await tester.pump();
      final week = byId(SemanticsIds.reportYearRecord('busiest-week'));
      final row = tester.getTopLeft(week).dy;
      expect(row, greaterThan(bodyTop(tester)));
      final offset = scrollOf(tester).pixels;

      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(
          goals: [weekly('gym'), weekly('other')],
          year: yearOf(records: [busiestMonth, busiestWeek, socialMonth]),
        ),
      );
      expect(scrollOf(tester).pixels, greaterThan(offset));
      expect(tester.getTopLeft(week).dy, closeTo(row, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refold read inside the Months card while Records and '
        'Months both leave holds the Categories label still: the anchor '
        'falls to the next label that stays', (tester) async {
      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(),
      );
      scrollOf(
        tester,
      ).jumpTo(labelTop(tester, 'Months') - bodyTop(tester) + 20);
      await tester.pump();
      final categories = labelTop(tester, 'Categories');
      expect(categories, greaterThan(bodyTop(tester)));
      final offset = scrollOf(tester).pixels;

      // Goals grow above while the year block leaves: no label above the
      // reader stays put, only the one after the leaving card.
      await pumpBody(
        tester,
        surface: const Size(360, 520),
        period: year2025,
        shown: wholeYear(
          goals: [weekly('gym'), weekly('other')],
          year: yearOf(records: const [], strips: false),
        ),
      );
      expect(sectionLabel('Records'), findsNothing);
      expect(sectionLabel('Months'), findsNothing);
      expect(scrollOf(tester).pixels, lessThan(offset));
      expect(labelTop(tester, 'Categories'), closeTo(categories, 0.01));
      final pixels = scrollOf(tester).pixels;
      await tester.pumpAndSettle();
      expect(scrollOf(tester).pixels, pixels);
      expect(tester.takeException(), isNull);
    });

    testWidgets('de at 2.0 on 360 × 780 lays the year block out with no '
        'exception, in one scroll', (tester) async {
      await pumpBody(
        tester,
        locale: const Locale('de'),
        textScale: 2,
        period: year2025,
        shown: wholeYear(),
      );
      expect(bodyScrollable(), findsOneWidget);
      await scrollThrough(tester, () => expect(tester.takeException(), isNull));
    });
  });

  group('report cards II and Compare with (S5 §2.1, §2.5)', () {
    final en = lookupAppLocalizations(const Locale('en'));
    // Late: the date formats load with the first test.
    late final words = ReportLabels(en);

    /// [base] — the October fold unless given — with S5's content; the
    /// rest of the fold as it came.
    CalendarReport s5({
      CalendarReport? base,
      List<ReportTag> tags = const [],
      ReportWhen? when,
      Map<LifeArea, int> balance = const {},
      List<ReportInsight> insights = const [],
      List<ReportTileValue>? tiles,
      ReportCompare compare = ReportCompare.previous,
      CalendarReport? compared,
      DateRange? previousSpan,
      DateRange? previousCounted,
    }) {
      final from = base ?? report;
      return CalendarReport(
        span: from.span,
        today: from.today,
        tense: from.tense,
        countedTo: from.countedTo,
        previousSpan: previousSpan ?? from.previousSpan,
        previousCounted:
            previousCounted ?? previousSpan ?? from.previousCounted,
        events: from.events,
        tiles: tiles ?? from.tiles,
        skippedDays: from.skippedDays,
        aheadCount: from.aheadCount,
        categories: from.categories,
        trend: from.trend,
        missed: from.missed,
        ahead: from.ahead,
        measures: from.measures,
        tags: tags,
        when: when,
        balance: balance,
        insights: insights,
        compare: compare,
        compared: compared,
      );
    }

    /// Eight tags, the most seen first, each with two of Gym's days.
    final eightTags = [
      for (var i = 0; i < AnalyticsMetrics.tagRows; i++)
        ReportTag(
          key: 'tag$i',
          label: 'tag$i',
          events: 1,
          count: AnalyticsMetrics.tagRows - i,
          minutes: 60 * (AnalyticsMetrics.tagRows - i),
          categoryIds: const ['gym'],
          rows: [
            ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 10, 1)),
            ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 10, 6)),
          ],
        ),
    ];

    /// 34 timed days, Tuesday at six the busiest.
    final when = ReportWhen(
      cells: [
        for (var i = 0; i < ReportWhen.cellCount; i++)
          i % ReportWhen.hoursPerDay == 18 ? 60 : 0,
      ],
      timedDays: 34,
      busiestWeekday: 1,
      busiestHour: 18,
    );
    const threeAreas = {
      LifeArea.health: 900,
      LifeArea.work: 2400,
      LifeArea.people: 300,
    };
    const work = OverviewView(id: 'v-work', name: 'Work', period: october);
    const life = OverviewView(id: 'v-life', name: 'Life', period: october);

    Finder bodyScrollable() => find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(Scrollable),
    );

    ScrollPosition scrollOf(WidgetTester tester) =>
        tester.state<ScrollableState>(bodyScrollable()).position;

    Future<void> toEnd(WidgetTester tester) async {
      // Twice: the first jump lays out lists below at their real extents.
      for (var i = 0; i < 2; i++) {
        final position = scrollOf(tester);
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
    }

    double footerHeight(WidgetTester tester) => tester
        .getSize(
          find
              .ancestor(
                of: byId(SemanticsIds.reportShowList),
                matching: find.byType(FormRowGroup),
              )
              .first,
        )
        .height;

    String captionText(WidgetTester tester) => tester
        .widget<FormCaption>(
          find
              .descendant(
                of: byId(SemanticsIds.reportBody),
                matching: find.byType(FormCaption),
              )
              .first,
        )
        .text;

    FormMenuRow<_CompareChoice> compareRow(WidgetTester tester) =>
        tester.widget<FormMenuRow<_CompareChoice>>(
          find.byWidgetPredicate((widget) => widget is FormMenuRow),
        );

    testWidgets('every card in §2.1\'s order, one scroll; each new card is '
        'absent with its label when it has nothing to show', (tester) async {
      await pumpBody(
        tester,
        shown: s5(tags: eightTags, when: when, balance: threeAreas),
      );
      const full = [
        'label Totals',
        'ReportTotalsCard',
        'FormCaption',
        'SizedBox',
        'label Categories',
        'ReportGroupStack',
        'SizedBox',
        'label By tag',
        'ReportGroupStack',
        'SizedBox',
        'label Over time',
        'ReportTrendChart',
        'SizedBox',
        'label When',
        'ReportWhenChart',
        'SizedBox',
        'label Balance',
        'ReportBalanceCard',
        'SizedBox',
        'label Missed',
        'ReportGroupStack',
        'SizedBox',
        'FormRowGroup',
      ];
      expect(sliverSequence(tester), full);
      expect(bodyScrollable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final (shown, label) in [
        (s5(when: when, balance: threeAreas), 'By tag'),
        (
          s5(
            tags: eightTags,
            balance: threeAreas,
            when: ReportWhen(cells: when.cells, timedDays: 9),
          ),
          'When',
        ),
        (
          s5(tags: eightTags, when: when, balance: const {LifeArea.work: 2400}),
          'Balance',
        ),
      ]) {
        await pumpBody(tester, shown: shown);
        final sequence = sliverSequence(tester);
        expect(sequence, isNot(contains('label $label')), reason: label);
        expect(sequence, hasLength(full.length - 3), reason: label);
      }
    });

    testWidgets('with Compare offered the unprofiled page changes by the '
        'footer\'s row alone; without it there is no row', (tester) async {
      await pumpBody(tester);
      final sequence = sliverSequence(tester);
      final extent = scrollOf(tester).maxScrollExtent;
      await toEnd(tester);
      final plain = footerHeight(tester);
      expect(byId(SemanticsIds.reportCompare), findsNothing);

      await pumpBody(tester, onCompare: (_, _) {});
      scrollOf(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(sliverSequence(tester), sequence);
      expect(tester.getTopLeft(sectionLabel('Totals')), const Offset(16, 82));
      final grown = scrollOf(tester).maxScrollExtent;
      await toEnd(tester);
      final withRow = footerHeight(tester);
      expect(byId(SemanticsIds.reportCompare), findsOneWidget);
      expect(withRow - plain, closeTo(48, 1));
      expect(grown - extent, closeTo(withRow - plain, 0.01));
    });

    testWidgets('the Compare with row names the choice asked for, lists '
        'every saved view by name and hands a pick over', (tester) async {
      final picks = <(ReportCompare, OverviewView?)>[];
      await pumpBody(
        tester,
        views: const [work, life],
        onCompare: (compare, view) => picks.add((compare, view)),
      );
      await toEnd(tester);
      var row = compareRow(tester);
      expect(row.label, 'Compare with');
      expect(row.value, 'Previous period');
      expect(row.selected, (compare: ReportCompare.previous, viewId: null));
      expect(
        [for (final item in row.items) item.identifier],
        [
          SemanticsIds.reportComparePrevious,
          SemanticsIds.reportCompareLastYear,
          SemanticsIds.reportCompareView(work.id),
          SemanticsIds.reportCompareView(life.id),
        ],
      );
      expect(
        [for (final item in row.items) item.label],
        ['Previous period', 'Same period last year', 'Work', 'Life'],
      );
      expect([for (final item in row.items) item.enabled], everyElement(true));

      await tester.tap(byId(SemanticsIds.reportCompare));
      await tester.pumpAndSettle();
      for (final item in row.items) {
        expect(byId(item.identifier!), findsOneWidget);
      }
      await tester.tap(byId(SemanticsIds.reportCompareView(life.id)));
      await tester.pumpAndSettle();
      expect(picks, [(ReportCompare.view, life)]);

      await tester.tap(byId(SemanticsIds.reportCompare));
      await tester.pumpAndSettle();
      await tester.tap(byId(SemanticsIds.reportCompareLastYear));
      await tester.pumpAndSettle();
      expect(picks.last, (ReportCompare.lastYear, null));

      // The asked choice is the row's value, whatever the fold drew.
      await pumpBody(
        tester,
        compare: ReportCompare.view,
        compareView: work,
        views: const [work, life],
        onCompare: (_, _) {},
      );
      await toEnd(tester);
      row = compareRow(tester);
      expect(row.value, 'Work');
      expect(row.selected, (compare: ReportCompare.view, viewId: work.id));
      await pumpBody(
        tester,
        compare: ReportCompare.lastYear,
        onCompare: (_, _) {},
      );
      await toEnd(tester);
      expect(compareRow(tester).value, 'Same period last year');
      expect(tester.takeException(), isNull);
    });

    testWidgets('with no saved view one disabled "No saved views" item, and '
        'Last year disabled before the first year', (tester) async {
      await pumpBody(
        tester,
        yearBounds: (first: 2026, last: 2026),
        onCompare: (_, _) {},
      );
      await toEnd(tester);
      final row = compareRow(tester);
      expect(
        [for (final item in row.items) item.identifier],
        [
          SemanticsIds.reportComparePrevious,
          SemanticsIds.reportCompareLastYear,
          SemanticsIds.reportCompareNone,
        ],
      );
      expect(row.items.last.label, 'No saved views');
      expect(
        [for (final item in row.items) item.enabled],
        [true, false, false],
      );
      await tester.tap(byId(SemanticsIds.reportCompare));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      try {
        await tester.pump();
        for (final (id, enabled) in [
          (SemanticsIds.reportComparePrevious, true),
          (SemanticsIds.reportCompareLastYear, false),
          (SemanticsIds.reportCompareNone, false),
        ]) {
          final data = tester.getSemantics(byId(id)).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), enabled, reason: id);
        }
      } finally {
        handle.dispose();
      }

      // One year back is reachable from 2025 on.
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await pumpBody(tester, onCompare: (_, _) {});
      await toEnd(tester);
      expect(compareRow(tester).items[1].enabled, isTrue);
    });

    group('the caption\'s "against"', () {
      testWidgets('the previous period names the whole previous month', (
        tester,
      ) async {
        await pumpBody(tester);
        expect(captionText(tester), contains('against September 2026'));
      });

      testWidgets('last year names the same whole month a year back', (
        tester,
      ) async {
        const september = OverviewMonthPeriod(2026, 9);
        final lastSeptember = (
          start: DateTime.utc(2025, 9, 1),
          end: DateTime.utc(2025, 9, 30),
        );
        // A past month, as the service folds it: counted whole, so the
        // compared span is last year's whole month.
        final past = CalendarReportBuilder.fold(
          CalendarReportService.sampleInput(
            ReportRequest(
              span: september.resolve(today: today, yearBounds: years),
              previousSpan: lastSeptember,
              events: [gym, dentist, birthday],
              today: today,
              weekStart: CalendarWeekStart.monday,
            ),
          ),
        );
        expect(past.tense, ReportTense.past);
        expect(past.previousCounted, lastSeptember);
        await pumpBody(
          tester,
          period: september,
          shown: s5(
            base: past,
            compare: ReportCompare.lastYear,
            previousSpan: lastSeptember,
          ),
        );
        expect(captionText(tester), contains('against September 2025'));
        expect(captionText(tester), isNot(contains('August')));
      });

      testWidgets('last year under a month so far names the counted days, '
          'never the whole month (D28)', (tester) async {
        await pumpBody(
          tester,
          shown: s5(
            compare: ReportCompare.lastYear,
            previousSpan: (
              start: DateTime.utc(2025, 10, 1),
              end: DateTime.utc(2025, 10, 31),
            ),
            // October 1 to 30 so far: last year counted to the same length.
            previousCounted: (
              start: DateTime.utc(2025, 10, 1),
              end: DateTime.utc(2025, 10, 30),
            ),
          ),
        );
        expect(report.countedTo, DateTime.utc(2026, 10, 30));
        expect(
          captionText(tester),
          contains(
            'against '
            '${dateSpanLabel(en, DateTime.utc(2025, 10, 1), DateTime.utc(2025, 10, 30))}',
          ),
        );
        expect(captionText(tester), isNot(contains('October 2025')));
      });

      for (final (name, period, previousSpan) in [
        (
          'a week',
          OverviewWeekPeriod(DateTime.utc(2026, 10, 26)),
          (start: DateTime.utc(2025, 10, 27), end: DateTime.utc(2025, 11, 2)),
        ),
        (
          'a custom span',
          OverviewCustomPeriod(
            DateTime.utc(2026, 10, 5),
            DateTime.utc(2026, 10, 20),
          ),
          (start: DateTime.utc(2025, 10, 5), end: DateTime.utc(2025, 10, 20)),
        ),
      ]) {
        testWidgets('last year over $name names its counted days', (
          tester,
        ) async {
          await pumpBody(
            tester,
            period: period,
            shown: s5(
              compare: ReportCompare.lastYear,
              previousSpan: previousSpan,
            ),
          );
          expect(
            captionText(tester),
            contains(
              'against '
              '${dateSpanLabel(en, previousSpan.start, previousSpan.end)}',
            ),
          );
        });
      }
    });

    group('a saved view', () {
      /// The view's fold: its own tiles, with deltas the card must drop.
      CalendarReport viewFold() => CalendarReport(
        span: report.span,
        today: report.today,
        tense: report.tense,
        countedTo: report.countedTo,
        events: const {},
        tiles: [
          for (final tile in report.tiles)
            ReportTileValue(
              tile: tile.tile,
              value: tile.value + 2,
              of: tile.of,
              previous: tile.value,
            ),
        ],
        skippedDays: 0,
        aheadCount: 0,
        categories: const [],
        missed: const [],
        ahead: const [],
      );

      /// The page's fold beside [viewFold], its tiles carrying deltas too.
      CalendarReport besideView() => s5(
        tiles: [
          for (final tile in report.tiles)
            ReportTileValue(
              tile: tile.tile,
              value: tile.value,
              of: tile.of,
              previous: tile.previous ?? 0,
              previousOf: tile.of,
            ),
        ],
        compare: ReportCompare.view,
        compared: viewFold(),
      );

      Future<void> pumpView(WidgetTester tester, Size surface) => pumpBody(
        tester,
        surface: surface,
        shown: besideView(),
        compare: ReportCompare.view,
        compareView: work,
        views: const [work],
        onCompare: (_, _) {},
      );

      /// Both cards draw no delta: every tile they were handed has none.
      void expectNoDeltas(WidgetTester tester) {
        final cards = tester
            .widgetList<ReportTotalsCard>(find.byType(ReportTotalsCard))
            .toList();
        expect(cards, hasLength(2));
        for (final card in cards) {
          expect(card.against, isNull);
          for (final tile in card.tiles) {
            expect(words.delta(tile), isNull, reason: '${tile.tile}');
          }
        }
      }

      /// The Totals label's sliver is still a refold anchor, and so is the
      /// view's where it stands alone (S6 H): [labels] anchors above the
      /// caption.
      void expectAnchored(WidgetTester tester, {required int labels}) {
        final anchored = bodySlivers(tester)
            .takeWhile(
              (sliver) =>
                  !(sliver is SliverToBoxAdapter &&
                      sliver.child is FormCaption),
            )
            .where((sliver) => '${sliver.runtimeType}' == '_AnchoredLabel')
            .toList();
        expect(anchored, hasLength(labels));
        expect(
          find.descendant(
            of: find.byWidget(anchored.first),
            matching: sectionLabel('Totals'),
          ),
          findsOneWidget,
        );
      }

      testWidgets('at 360 the two cards stack under their labels, the '
          'caption once under the second', (tester) async {
        await pumpView(tester, const Size(360, 780));
        expect(sliverSequence(tester).take(7), [
          'label Totals',
          'ReportTotalsCard',
          'SizedBox',
          'label Work',
          'ReportTotalsCard',
          'FormCaption',
          'SizedBox',
        ]);
        expectAnchored(tester, labels: 2);
        expectNoDeltas(tester);
        expect(byId(SemanticsIds.reportTile('events')), findsOneWidget);
        expect(byId(SemanticsIds.reportViewTile('events')), findsOneWidget);
        expect(byId(SemanticsIds.reportViewTile('hours')), findsOneWidget);
        expect(find.textContaining('beside Work'), findsOneWidget);
        expect(captionText(tester), isNot(contains('against')));
        final cards = find.byType(ReportTotalsCard);
        expect(
          tester.getTopLeft(sectionLabel('Work')).dy,
          greaterThan(tester.getBottomLeft(cards.first).dy),
        );
        expect(
          tester.getTopLeft(find.byType(FormCaption).first).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(cards.last).dy),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('at 600 the two cards stand side by side in one row, the '
          'caption under both', (tester) async {
        await pumpView(tester, const Size(600, 780));
        expect(sliverSequence(tester).take(4), [
          'Row',
          'Row',
          'FormCaption',
          'SizedBox',
        ]);
        expectAnchored(tester, labels: 1);
        expectNoDeltas(tester);
        final cards = find.byType(ReportTotalsCard);
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Expanded && widget.child is ReportTotalsCard,
          ),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: find
                .ancestor(of: cards.first, matching: find.byType(Row))
                .first,
            matching: find.byType(ReportTotalsCard),
          ),
          findsNWidgets(2),
        );
        final page = tester.getRect(cards.first);
        final view = tester.getRect(cards.last);
        expect(view.top, page.top);
        expect(view.left, greaterThan(page.right));
        expect(
          tester.getTopLeft(sectionLabel('Work')).dx,
          closeTo(view.left, 0.01),
        );
        expect(
          tester.getBottomLeft(sectionLabel('Work')).dy,
          lessThanOrEqualTo(view.top),
        );
        expect(find.textContaining('beside Work'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(FormCaption).first).dy,
          greaterThanOrEqualTo(math.max(page.bottom, view.bottom)),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the card and the caption name the view folded; the row '
          'names the one asked for (D36.9)', (tester) async {
        await pumpBody(
          tester,
          shown: besideView(),
          compare: ReportCompare.view,
          compareView: life,
          foldedCompareView: work,
          views: const [work, life],
          onCompare: (_, _) {},
        );
        expect(sectionLabel('Work'), findsOneWidget);
        expect(sectionLabel('Life'), findsNothing);
        expect(captionText(tester), contains('beside Work'));
        await toEnd(tester);
        expect(compareRow(tester).value, 'Life');

        // No view folded to name: the row's no-view word, as before.
        await pumpBody(
          tester,
          shown: besideView(),
          compare: ReportCompare.view,
          onCompare: (_, _) {},
        );
        scrollOf(tester).jumpTo(0);
        await tester.pumpAndSettle();
        expect(sectionLabel('No saved views'), findsOneWidget);
      });

      testWidgets('Share hands the caption\'s "beside" and no "against"', (
        tester,
      ) async {
        final shares = <({String? against, String? beside})>[];
        await pumpBody(
          tester,
          shown: besideView(),
          compare: ReportCompare.view,
          compareView: work,
          views: const [work],
          onCompare: (_, _) {},
          onShare:
              (_, {required periodName, required against, required beside}) =>
                  shares.add((against: against, beside: beside)),
        );
        await toEnd(tester);
        await tester.tap(byId(SemanticsIds.reportShare));
        await tester.pumpAndSettle();
        expect(shares, [(against: null, beside: 'Work')]);

        await pumpBody(
          tester,
          onCompare: (_, _) {},
          onShare:
              (_, {required periodName, required against, required beside}) =>
                  shares.add((against: against, beside: beside)),
        );
        await toEnd(tester);
        await tester.tap(byId(SemanticsIds.reportShare));
        await tester.pumpAndSettle();
        expect(shares.last, (against: 'September 2026', beside: null));
      });

      testWidgets('a view picked at the scroll\'s end keeps the Compare row '
          'under the finger, and so does the way back (S6 H)', (tester) async {
        await pumpBody(tester, views: const [work], onCompare: (_, _) {});
        await toEnd(tester);
        final row = tester.getTopLeft(byId(SemanticsIds.reportCompare)).dy;
        final offset = scrollOf(tester).pixels;
        expect(offset, scrollOf(tester).maxScrollExtent);

        await pumpBody(
          tester,
          shown: besideView(),
          compare: ReportCompare.view,
          compareView: work,
          views: const [work],
          onCompare: (_, _) {},
        );
        expect(
          find.byType(ReportTotalsCard, skipOffstage: false),
          findsNWidgets(2),
        );
        expect(
          tester.getTopLeft(byId(SemanticsIds.reportCompare)).dy,
          closeTo(row, 1),
        );
        final grown = scrollOf(tester);
        expect(grown.pixels, greaterThan(offset + 200));
        expect(grown.pixels, lessThanOrEqualTo(grown.maxScrollExtent));

        await pumpBody(tester, views: const [work], onCompare: (_, _) {});
        expect(
          tester.getTopLeft(byId(SemanticsIds.reportCompare)).dy,
          closeTo(row, 1),
        );
        expect(scrollOf(tester).pixels, closeTo(offset, 1));
        expect(tester.takeException(), isNull);
      });

      testWidgets('one scroll keeps its offset across a 360 ↔ 600 resize and '
          'a compare switch', (tester) async {
        await pumpView(tester, const Size(360, 780));
        scrollOf(tester).jumpTo(100);
        await tester.pumpAndSettle();
        final scrollable = tester.state<ScrollableState>(bodyScrollable());

        tester.view.physicalSize = const Size(600, 780);
        await tester.pumpAndSettle();
        expect(sliverSequence(tester).first, 'Row');
        expect(
          tester.state<ScrollableState>(bodyScrollable()),
          same(scrollable),
        );
        expect(scrollOf(tester).pixels, 100);

        tester.view.physicalSize = const Size(360, 780);
        await tester.pumpAndSettle();
        expect(sliverSequence(tester).first, 'label Totals');
        expect(
          tester.state<ScrollableState>(bodyScrollable()),
          same(scrollable),
        );
        expect(scrollOf(tester).pixels, 100);

        // Back to Previous: the view's card leaves below the Totals label,
        // which holds the top.
        await pumpBody(tester, views: const [work], onCompare: (_, _) {});
        expect(find.byType(ReportTotalsCard), findsOneWidget);
        expect(
          tester.state<ScrollableState>(bodyScrollable()),
          same(scrollable),
        );
        expect(scrollOf(tester).pixels, 100);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a tag\'s Show as list hands over the span and the tag\'s '
        'categories', (tester) async {
      final big = ReportTag(
        key: 'big',
        label: 'big',
        events: 1,
        count: ReportMetrics.maxListRows + 1,
        minutes: 0,
        categoryIds: const ['gym', 'other'],
        rows: [
          for (var day = 0; day <= ReportMetrics.maxListRows; day++)
            ReportDatedRow(
              eventId: gym.id,
              day: DateTime.utc(2025, 1, 1 + day),
            ),
        ],
      );
      folds
        ..setOpen(ReportCard.tags, big.key, true)
        ..setExpanded(ReportCard.tags, big.key, true);
      final lists = <({DateTime start, DateTime end, Set<String> ids})>[];
      await pumpBody(
        tester,
        shown: s5(tags: [big]),
        onShowAsList: ({required start, required end, required categoryIds}) =>
            lists.add((start: start, end: end, ids: categoryIds)),
      );
      final list = byId(SemanticsIds.reportTagList(big.key));
      await tester.scrollUntilVisible(list, 600, scrollable: bodyScrollable());
      await tester.pumpAndSettle();
      await tester.tap(list);
      await tester.pumpAndSettle();
      expect(lists, hasLength(1));
      expect(lists.single.start, report.span.start);
      expect(lists.single.end, report.span.end);
      expect(lists.single.ids, {'gym', 'other'});
    });

    testWidgets('an insight about a tag opens its header past the preview '
        'and scrolls it to the top', (tester) async {
      const about = ReportInsight(
        rule: InsightRule.r2,
        severity: 0,
        categoryId: 'gym',
        tagKey: 'tag5',
        target: InsightTarget.tagRows,
        n1: 3,
      );
      var reveals = 0;
      await pumpBody(
        tester,
        shown: s5(
          tags: eightTags,
          when: when,
          balance: threeAreas,
          insights: const [about],
        ),
        onReveal: () => reveals++,
      );
      expect(folds.isTagsExpanded, isFalse);
      expect(folds.isOpen(ReportCard.tags, 'tag5'), isFalse);
      await tester.tap(
        find.bySemanticsIdentifier(RegExp('^report-insight-')).first,
      );
      await tester.pumpAndSettle();
      expect(reveals, 1);
      expect(folds.isTagsExpanded, isTrue);
      expect(folds.isOpen(ReportCard.tags, 'tag5'), isTrue);
      expect(
        tester.getTopLeft(byId(SemanticsIds.reportTag('tag5'))).dy,
        closeTo(tester.getTopLeft(byId(SemanticsIds.reportBody)).dy, 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an insight about a tag past the card\'s eight reads its '
        'category\'s group', (tester) async {
      final nine = [
        ...eightTags,
        ReportTag(
          key: 'tag8',
          label: 'tag8',
          events: 1,
          count: 1,
          minutes: 0,
          categoryIds: const ['gym'],
          rows: [
            ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 10, 1)),
          ],
        ),
      ];
      const about = ReportInsight(
        rule: InsightRule.r2,
        severity: 0,
        categoryId: 'gym',
        tagKey: 'tag8',
        target: InsightTarget.tagRows,
        n1: 1,
      );
      var reveals = 0;
      await pumpBody(
        tester,
        surface: const Size(360, 520),
        shown: s5(tags: nine, insights: const [about]),
        onReveal: () => reveals++,
      );
      final gymHeader = byId(SemanticsIds.reportGroup('categories', 'gym'));
      expect(
        tester.getTopLeft(gymHeader).dy,
        greaterThan(tester.getTopLeft(byId(SemanticsIds.reportBody)).dy + 1),
      );
      await tester.tap(byId(SemanticsIds.reportInsight(0)));
      await tester.pumpAndSettle();
      expect(reveals, 1);
      expect(folds.isOpen(ReportCard.categories, 'gym'), isTrue);
      expect(folds.isOpen(ReportCard.tags, 'tag8'), isFalse);
      expect(
        tester.getTopLeft(gymHeader).dy,
        closeTo(tester.getTopLeft(byId(SemanticsIds.reportBody)).dy, 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('with onReveal null an insight about a tag is inert, inside '
        'the card\'s eight or past them', (tester) async {
      for (final key in ['tag5', 'tag8']) {
        await pumpBody(
          tester,
          shown: s5(
            tags: [
              ...eightTags,
              ReportTag(
                key: 'tag8',
                label: 'tag8',
                events: 1,
                count: 1,
                minutes: 0,
                categoryIds: const ['gym'],
                rows: [
                  ReportDatedRow(
                    eventId: gym.id,
                    day: DateTime.utc(2026, 10, 1),
                  ),
                ],
              ),
            ],
            insights: [
              ReportInsight(
                rule: InsightRule.r2,
                severity: 0,
                categoryId: 'gym',
                tagKey: key,
                target: InsightTarget.tagRows,
                n1: 1,
              ),
            ],
          ),
        );
        final row = tester.widget<FormPickerRow>(
          find.byWidgetPredicate(
            (widget) =>
                widget is FormPickerRow &&
                widget.identifier == SemanticsIds.reportInsight(0),
          ),
        );
        expect(row.onTap, isNull, reason: key);
      }
    });

    for (final (scale, height) in [(1.0, 195.0), (1.3, 213.0), (2.0, 293.0)]) {
      testWidgets('the footer with Compare is $height at en $scale', (
        tester,
      ) async {
        await pumpBody(tester, textScale: scale, onCompare: (_, _) {});
        await toEnd(tester);
        expect(footerHeight(tester), closeTo(height, 1));
        expect(tester.takeException(), isNull);
      });
    }

    // The design review's measures: the longer de and ro words wrap the
    // footer's rows sooner than en's.
    for (final locale in ['de', 'ro']) {
      for (final (scale, height) in [
        (1.0, 201.0),
        (1.3, 213.0),
        (2.0, 333.0),
      ]) {
        testWidgets('the footer with Compare is $height at $locale $scale', (
          tester,
        ) async {
          await pumpBody(
            tester,
            locale: Locale(locale),
            textScale: scale,
            onCompare: (_, _) {},
          );
          await toEnd(tester);
          expect(footerHeight(tester), closeTo(height, 1));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('de at 2.0 on 360 × 780 lays every card and the Compare row '
        'out with no exception, in one scroll', (tester) async {
      await pumpBody(
        tester,
        locale: const Locale('de'),
        textScale: 2,
        shown: s5(tags: eightTags, when: when, balance: threeAreas),
        views: const [work, life],
        onCompare: (_, _) {},
      );
      expect(bodyScrollable(), findsOneWidget);
      await scrollThrough(tester, () => expect(tester.takeException(), isNull));
      expect(byId(SemanticsIds.reportCompare), findsOneWidget);
    });
  });
}

/// The Compare with menu's value: the mode, and a saved view's id.
typedef _CompareChoice = ({ReportCompare compare, String? viewId});
