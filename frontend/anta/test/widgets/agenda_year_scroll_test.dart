import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/overview_list_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/widgets/agenda_year_grid.dart';
import 'package:anta/widgets/agenda_year_scroll.dart';
import 'package:anta/widgets/list_scrubber.dart';
import 'package:anta/widgets/year_month_tile.dart';

import 'support/layout_errors.dart';

/// The overview's year scroll on its own: its geometry against the grid it
/// replaces, the controller's arithmetic, what a long span builds, where the
/// first frame opens, what a width change keeps, and its semantics.
void main() {
  final today = DateTime.utc(2026, 10, 15);

  /// A resolved year: one entry on the first day of every month, the
  /// second month's missed.
  List<AgendaYearTile> resolved(int year) => [
    for (var month = 1; month <= 12; month++)
      AgendaYearTile(
        month: DateTime.utc(year, month, 1),
        daysInMonth: DateTime.utc(year, month + 1, 0).day,
        count: month == 2 ? 0 : 1,
        missedCount: month == 2 ? 1 : 0,
        markedMask: 1,
        missedMask: month == 2 ? 1 : 0,
        windowMask: (1 << DateTime.utc(year, month + 1, 0).day) - 1,
      ),
  ];

  /// A source holding [years] resolved, counting every question a section
  /// asks it.
  AgendaYearTileSource sourceOf(Set<int> years, {VoidCallback? onTilesFor}) {
    final source = _CountingTiles(onTilesFor);
    for (final year in years) {
      source.put(year, resolved(year));
    }
    addTearDown(source.dispose);
    return source;
  }

  Widget scroll(
    AgendaYearScrollController controller, {
    int firstYear = 2000,
    int lastYear = 2050,
    Set<int> resolvedYears = const {2026},
    AgendaYearTileSource? tiles,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    ThemeData? theme,
    VoidCallback? onTilesFor,
    AgendaYearScrubber? scrubber,
  }) {
    return MaterialApp(
      theme: theme ?? AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: AgendaYearScroll(
          controller: controller,
          firstYear: firstYear,
          lastYear: lastYear,
          tiles: tiles ?? sourceOf(resolvedYears, onTilesFor: onTilesFor),
          color: Colors.blue,
          appearance: const CalendarAppearance(),
          today: today,
          onOpenMonth: (_) {},
          padding: OverviewListMetrics.yearScrollPadding,
          scrubber: scrubber,
        ),
      ),
    );
  }

  void setSurface(WidgetTester tester, Size size) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
  }

  Finder header(int year) => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.identifier == SemanticsIds.overviewYearHeader(year),
  );

  /// Every year whose header is built.
  List<int> builtYears(WidgetTester tester) => [
    for (final widget in tester.widgetList<Semantics>(find.byType(Semantics)))
      if (widget.properties.identifier case final id?
          when id.startsWith('overview-year-'))
        int.parse(id.substring('overview-year-'.length)),
  ];

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(AgendaYearScroll),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  double scrollTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(AgendaYearScroll)).dy;

  group('geometry', () {
    SliverGridRegularTileLayout gridLayout(double crossAxisExtent) =>
        YearMonthTile.gridDelegate.getLayout(
              SliverConstraints(
                axisDirection: AxisDirection.down,
                growthDirection: GrowthDirection.forward,
                userScrollDirection: ScrollDirection.idle,
                scrollOffset: 0,
                precedingScrollExtent: 0,
                overlap: 0,
                remainingPaintExtent: 1000,
                crossAxisExtent: crossAxisExtent,
                crossAxisDirection: AxisDirection.right,
                viewportMainAxisExtent: 1000,
                remainingCacheExtent: 1000,
                cacheOrigin: 0,
              ),
            )
            as SliverGridRegularTileLayout;

    for (final crossAxis in const [328.0, 580.0]) {
      testWidgets('at $crossAxis the columns, the section and each tile are '
          'the grid delegate\'s own', (tester) async {
        final layout = gridLayout(crossAxis);
        final columns = YearMonthTile.columnsFor(crossAxis);
        expect(columns, layout.crossAxisCount);

        // The grid's twelve tiles end where the section's last row does.
        final gridHeight = layout.computeMaxScrollOffset(12);
        expect(
          AgendaYearScroll.sectionExtent(
            columns: columns,
            headerHeight: OverviewListMetrics.yearHeaderHeight,
          ),
          OverviewListMetrics.yearHeaderHeight +
              gridHeight +
              OverviewListMetrics.yearSectionGap,
        );

        setSurface(
          tester,
          Size(
            crossAxis + OverviewListMetrics.yearScrollPadding.horizontal,
            800,
          ),
        );
        final controller = AgendaYearScrollController(initialYear: 2026);
        await tester.pumpWidget(scroll(controller));
        final tile = tester.getSize(find.byType(YearMonthTile).first);
        expect(tile.width, moreOrLessEquals(layout.childCrossAxisExtent));
        expect(tile.height, layout.childMainAxisExtent);
        expect(
          controller.extent,
          AgendaYearScroll.sectionExtent(
            columns: columns,
            headerHeight: OverviewListMetrics.yearHeaderHeight,
          ),
        );
      });
    }

    test('a crossAxis narrower than one tile still lays one column', () {
      expect(YearMonthTile.columnsFor(0), 1);
      expect(YearMonthTile.columnsFor(100), 1);
    });
  });

  testWidgets('offsetOfYear and yearAtOffset round-trip, and the next year '
      'takes the top once its header is half a header from it', (tester) async {
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2026);
    await tester.pumpWidget(scroll(controller));

    for (var year = 2000; year <= 2050; year++) {
      expect(controller.yearAtOffset(controller.offsetOfYear(year)), year);
    }
    final half = controller.headerHeight! / 2;
    final next = controller.offsetOfYear(2027);
    expect(controller.yearAtOffset(next - half - 0.5), 2026);
    expect(controller.yearAtOffset(next - half + 0.5), 2027);
    // Clamped to the span at both ends.
    expect(controller.yearAtOffset(-500), 2000);
    expect(controller.yearAtOffset(1e9), 2050);
  });

  testWidgets('a hundred-year span builds only the sections in view', (
    tester,
  ) async {
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2000);
    await tester.pumpWidget(
      scroll(controller, firstYear: 1950, lastYear: 2049),
    );

    expect(builtYears(tester), hasLength(lessThanOrEqualTo(3)));
    expect(builtYears(tester), contains(2000));

    controller.jumpToYear(2040);
    await tester.pump();
    expect(builtYears(tester), hasLength(lessThanOrEqualTo(3)));
    expect(builtYears(tester), contains(2040));
    expect(builtYears(tester), isNot(contains(2000)));
  });

  testWidgets('the first frame opens with the initial year\'s header at the '
      'top; no jump follows', (tester) async {
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2026);
    await tester.pumpWidget(scroll(controller));

    expect(tester.getTopLeft(header(2026)).dy, scrollTop(tester));
    expect(controller.topYear, 2026);
    final pixels = position(tester).pixels;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(position(tester).pixels, pixels);
  });

  testWidgets('a year asked for before the first layout is the first '
      'frame\'s', (tester) async {
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2026);
    controller.jumpToYear(2031);
    await tester.pumpWidget(scroll(controller));

    expect(tester.getTopLeft(header(2031)).dy, scrollTop(tester));
  });

  testWidgets('the last year\'s header can reach the top of a viewport '
      'taller than a section', (tester) async {
    setSurface(tester, const Size(900, 1200));
    final controller = AgendaYearScrollController(initialYear: 2050);
    await tester.pumpWidget(scroll(controller));

    expect(tester.getTopLeft(header(2050)).dy, scrollTop(tester));
    expect(controller.topYear, 2050);
  });

  testWidgets('the top year is reported once per change, never per pixel', (
    tester,
  ) async {
    setSurface(tester, const Size(360, 780));
    final reports = <int>[];
    final controller = AgendaYearScrollController(
      initialYear: 2026,
      onTopYearChanged: reports.add,
    );
    await tester.pumpWidget(scroll(controller));

    final start = position(tester).pixels;
    for (var step = 1; step <= 10; step++) {
      position(tester).jumpTo(start + step * 10);
    }
    expect(reports, isEmpty);
    controller.jumpToYear(2030);
    expect(reports, [2030], reason: 'a landing reports in the same turn');
    unawaited(controller.animateToYear(2028));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Each year the animation brings to the top, once, ending on the target.
    expect(reports, [2030, 2029, 2028]);
  });

  testWidgets('a width change keeps the top year, as far into it as it was', (
    tester,
  ) async {
    setSurface(tester, const Size(360, 780));
    final reports = <int>[];
    final controller = AgendaYearScrollController(
      initialYear: 2026,
      onTopYearChanged: reports.add,
    );
    await tester.pumpWidget(scroll(controller));
    final narrow = controller.extent!;
    position(tester).jumpTo(controller.offsetOfYear(2030) + narrow / 2);
    await tester.pump();
    reports.clear();

    tester.view.physicalSize = const Size(700, 780);
    await tester.pump();

    expect(controller.extent, lessThan(narrow), reason: 'more columns');
    expect(controller.topYear, 2030);
    expect(controller.yearAtOffset(position(tester).pixels), 2030);
    expect(
      position(tester).pixels - controller.offsetOfYear(2030),
      moreOrLessEquals(controller.extent! / 2),
    );
    expect(reports, isEmpty);
  });

  testWidgets('a text-scale change keeps the top year, as far into it as it '
      'was', (tester) async {
    setSurface(tester, const Size(360, 780));
    final reports = <int>[];
    final controller = AgendaYearScrollController(
      initialYear: 2026,
      onTopYearChanged: reports.add,
    );
    await tester.pumpWidget(scroll(controller));
    final before = controller.extent!;
    position(tester).jumpTo(controller.offsetOfYear(2030) + before / 3);
    await tester.pump();
    reports.clear();

    await tester.pumpWidget(scroll(controller, textScale: 2.0));

    expect(controller.extent, greaterThan(before), reason: 'a taller header');
    expect(controller.topYear, 2030);
    expect(controller.yearAtOffset(position(tester).pixels), 2030);
    expect(
      position(tester).pixels - controller.offsetOfYear(2030),
      moreOrLessEquals(controller.extent! / 3),
    );
    expect(reports, isEmpty);
  });

  testWidgets('the keyboard resizing the page frame by frame asks tilesFor '
      'nothing and rebuilds no section', (tester) async {
    setSurface(tester, const Size(360, 780));
    var asked = 0;
    final controller = AgendaYearScrollController(initialYear: 2026);
    await tester.pumpWidget(scroll(controller, onTilesFor: () => asked++));
    expect(asked, greaterThan(0), reason: 'the first frame builds sections');
    final built = builtYears(tester);
    final pixels = position(tester).pixels;

    asked = 0;
    var tileBuilds = 0;
    var headerBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      final widget = element.widget;
      if (widget is YearMonthTile) tileBuilds++;
      if (widget.runtimeType.toString() == '_YearHeader') headerBuilds++;
    };
    try {
      for (var frame = 1; frame <= 8; frame++) {
        tester.view.viewInsets = FakeViewPadding(bottom: 40.0 * frame);
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }

    expect(asked, 0);
    expect(tileBuilds, 0);
    expect(headerBuilds, 0);
    // A shorter viewport may drop a section below; it builds none anew.
    expect(built, containsAll(builtYears(tester)));
    expect(position(tester).pixels, pixels);
    expect(tester.getTopLeft(header(2026)).dy, scrollTop(tester));
  });

  testWidgets('a year written into the source rebuilds its own section alone: '
      'twelve tiles and one header (R8)', (tester) async {
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2026);
    final tiles = sourceOf(const {});
    await tester.pumpWidget(scroll(controller, tiles: tiles));
    expect(builtYears(tester), containsAll([2026, 2027]));

    var tileBuilds = 0;
    var headerBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      final widget = element.widget;
      if (widget is YearMonthTile) tileBuilds++;
      if (widget.runtimeType.toString() == '_YearHeader') headerBuilds++;
    };
    try {
      tiles
        ..put(2027, resolved(2027))
        ..notify();
      await tester.pump();
      expect(tileBuilds, 12);
      expect(headerBuilds, 1);

      // A year no section shows rebuilds nothing.
      tileBuilds = headerBuilds = 0;
      tiles
        ..put(1950, resolved(1950))
        ..notify();
      await tester.pump();
      expect(tileBuilds, 0);
      expect(headerBuilds, 0);
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    final january = tester.widget<YearMonthTile>(
      find.widgetWithText(YearMonthTile, 'Jan 2027'),
    );
    expect(january.count, '1');
  });

  testWidgets('a span change mid-landing still lands on the target\'s header '
      '(R4)', (tester) async {
    setSurface(tester, const Size(360, 780));
    var landed = 0;
    final controller = AgendaYearScrollController(
      initialYear: 2026,
      onLanded: () => landed++,
    );
    final tiles = sourceOf(const {2026});
    await tester.pumpWidget(scroll(controller, tiles: tiles));

    unawaited(controller.animateToYear(2030));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.landingYear, 2030);
    // Ten years more above: every year's offset moves by ten sections under
    // the running animation.
    await tester.pumpWidget(scroll(controller, firstYear: 1990, tiles: tiles));
    await tester.pumpAndSettle();

    expect(controller.topYear, 2030);
    expect(tester.getTopLeft(header(2030)).dy, scrollTop(tester));
    expect(controller.isLanding, isFalse);
    expect(controller.landingYear, isNull);
    expect(landed, 1);
  });

  testWidgets('an animated landing reads as landing until it ends — reached '
      'or cut short — and reports its end once', (tester) async {
    setSurface(tester, const Size(360, 780));
    var landed = 0;
    final controller = AgendaYearScrollController(
      initialYear: 2026,
      onLanded: () => landed++,
    );
    await tester.pumpWidget(scroll(controller));
    expect(controller.isLanding, isFalse);

    unawaited(controller.animateToYear(2030));
    expect(controller.isLanding, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isLanding, isTrue);
    expect(landed, 0);
    await tester.pumpAndSettle();
    expect(controller.isLanding, isFalse);
    expect(landed, 1);
    expect(controller.topYear, 2030);

    unawaited(controller.animateToYear(2040));
    await tester.pump(const Duration(milliseconds: 50));
    controller.jumpToYear(2010);
    await tester.pump();
    expect(controller.isLanding, isFalse);
    expect(landed, 2);
    expect(controller.topYear, 2010);

    // A jump is no landing.
    controller.jumpToYear(2012);
    await tester.pump();
    expect(landed, 2);
  });

  group('the scrubber lane (D29)', () {
    /// The lane as the page wires it, its steps landing through [controller]
    /// — the page resolves the target first, which this suite has no store
    /// for. [steps] records each step's target.
    AgendaYearScrubber lane(
      AgendaYearScrollController controller, {
      List<int>? steps,
    }) => AgendaYearScrubber(
      semanticsLabel: 'Scroll by year',
      identifier: SemanticsIds.overviewScrubber,
      onStep: (year) {
        steps?.add(year);
        unawaited(controller.animateToYear(year));
      },
    );

    Finder laneFinder() => find.byType(ListScrubber);

    String? bubble(WidgetTester tester) {
      final text = find.descendant(
        of: find.descendant(
          of: laneFinder(),
          matching: find.byType(CustomSingleChildLayout),
        ),
        matching: find.byType(Text),
      );
      if (text.evaluate().isEmpty) return null;
      return tester.widget<Text>(text).data;
    }

    testWidgets('a span of two years wears the lane, one year none; the '
        'scroll keeps its year as the lane comes and goes', (tester) async {
      setSurface(tester, const Size(360, 780));
      final controller = AgendaYearScrollController(initialYear: 2026);
      await tester.pumpWidget(
        scroll(
          controller,
          firstYear: 2026,
          lastYear: 2026,
          scrubber: lane(controller),
        ),
      );
      expect(laneFinder(), findsNothing);

      await tester.pumpWidget(
        scroll(
          controller,
          firstYear: 2025,
          lastYear: 2026,
          scrubber: lane(controller),
        ),
      );
      expect(laneFinder(), findsOneWidget);
      expect(tester.getTopLeft(header(2026)).dy, scrollTop(tester));
      expect(controller.topYear, 2026);

      await tester.pumpWidget(
        scroll(controller, firstYear: 2025, lastYear: 2026),
      );
      expect(laneFinder(), findsNothing, reason: 'no configuration');
    });

    testWidgets('the lane is one node with its id, its label and a step '
        'each way', (tester) async {
      final handle = tester.ensureSemantics();
      setSurface(tester, const Size(360, 780));
      final controller = AgendaYearScrollController(initialYear: 2026);
      await tester.pumpWidget(scroll(controller, scrubber: lane(controller)));

      final node = find.bySemanticsIdentifier(SemanticsIds.overviewScrubber);
      expect(node, findsOneWidget);
      final data = tester.getSemantics(node).getSemanticsData();
      expect(data.label, 'Scroll by year');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      handle.dispose();
    });

    testWidgets('the bubble names the year the drag brought to the top', (
      tester,
    ) async {
      setSurface(tester, const Size(360, 780));
      final controller = AgendaYearScrollController(initialYear: 2026);
      await tester.pumpWidget(scroll(controller, scrubber: lane(controller)));

      final box = tester.getRect(laneFinder());
      final x = box.right - FormMetrics.scrubberLaneWidth / 2;
      Offset at(double share) => Offset(x, box.top + box.height * share);
      final gesture = await tester.startGesture(at(0.1));
      await gesture.moveTo(at(0.1) + const Offset(0, 40));
      await gesture.moveTo(at(0.5));
      await tester.pump();

      final pixels = position(tester).pixels;
      expect(pixels, moreOrLessEquals(position(tester).maxScrollExtent / 2));
      final shown = controller.yearAtOffset(pixels);
      expect(shown, inInclusiveRange(2020, 2030));
      expect(bubble(tester), '$shown');
      expect(controller.topYear, shown);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a step lands one year on or back, animated, and stops at the '
        'span\'s ends; a step during a landing goes on from its target', (
      tester,
    ) async {
      setSurface(tester, const Size(360, 780));
      var landed = 0;
      final steps = <int>[];
      final controller = AgendaYearScrollController(
        initialYear: 2026,
        onLanded: () => landed++,
      );
      await tester.pumpWidget(
        scroll(controller, scrubber: lane(controller, steps: steps)),
      );
      void step(int direction) =>
          tester.widget<ListScrubber>(laneFinder()).onStep!(direction);

      step(1);
      expect(steps, [2027]);
      expect(controller.isLanding, isTrue);
      await tester.pumpAndSettle();
      expect(controller.topYear, 2027);
      expect(tester.getTopLeft(header(2027)).dy, scrollTop(tester));
      expect(landed, 1);

      // R3: the second increase hands the year after the landing's target,
      // whatever year is passing the top.
      step(1);
      await tester.pump(const Duration(milliseconds: 16));
      step(1);
      expect(steps, [2027, 2028, 2029]);
      await tester.pumpAndSettle();
      expect(controller.topYear, 2029);
      step(-1);
      await tester.pumpAndSettle();
      step(-1);
      await tester.pumpAndSettle();
      expect(controller.topYear, 2027);

      step(-1);
      await tester.pumpAndSettle();
      step(-1);
      await tester.pumpAndSettle();
      expect(controller.topYear, 2025);

      controller.jumpToYear(2050);
      await tester.pump();
      step(1);
      await tester.pumpAndSettle();
      expect(controller.topYear, 2050);
    });
  });

  testWidgets('a span that grows above the top year keeps it at the top', (
    tester,
  ) async {
    setSurface(tester, const Size(360, 780));
    final reports = <(int, SchedulerPhase)>[];
    final controller = AgendaYearScrollController(
      initialYear: 2026,
      onTopYearChanged: (year) =>
          reports.add((year, SchedulerBinding.instance.schedulerPhase)),
    );
    await tester.pumpWidget(
      scroll(controller, firstYear: 2026, lastYear: 2027),
    );
    expect(tester.getTopLeft(header(2026)).dy, scrollTop(tester));

    await tester.pumpWidget(
      scroll(controller, firstYear: 1990, lastYear: 2027),
    );
    expect(tester.getTopLeft(header(2026)).dy, scrollTop(tester));
    expect(controller.topYear, 2026);
    expect(reports, isEmpty);

    // A span that leaves the top year out clamps it inside the frame's
    // layout, where the page could not rebuild: the report waits for the
    // frame's end, then comes once.
    await tester.pumpWidget(
      scroll(controller, firstYear: 1990, lastYear: 2010),
    );
    expect(controller.topYear, 2010);
    expect(reports, [(2010, SchedulerPhase.postFrameCallbacks)]);
    await tester.pump();
    expect(reports, hasLength(1));
  });

  testWidgets('one heading node per year: its year and count, its id; the '
      'scroll carries overview-years; an unresolved year reads its year and '
      'blank tiles', (tester) async {
    final handle = tester.ensureSemantics();
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2026);
    await tester.pumpWidget(scroll(controller));

    expect(find.bySemanticsIdentifier(SemanticsIds.overviewYears), findsOne);
    final data = tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.overviewYearHeader(2026)),
        )
        .getSemanticsData();
    expect(data.label, '2026, 11 entries · 1 missed');
    expect(data.flagsCollection.isHeader, isTrue);

    final unresolved = tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.overviewYearHeader(2027)),
        )
        .getSemanticsData();
    expect(unresolved.label, '2027');
    expect(find.bySemanticsLabel('Jan 2027'), findsOneWidget);
    final placeholder = tester.widget<YearMonthTile>(
      find.widgetWithText(YearMonthTile, 'Jan 2027'),
    );
    expect(placeholder.count, '');
    handle.dispose();
  });

  for (final surface in const [Size(360, 780), Size(412, 915)]) {
    testWidgets('German at 200 % on ${surface.width.round()} × '
        '${surface.height.round()} lays out without an overflow', (
      tester,
    ) async {
      setSurface(tester, surface);
      final controller = AgendaYearScrollController(initialYear: 2026);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          scroll(controller, locale: const Locale('de'), textScale: 2.0),
        );
        controller.jumpToYear(2027);
        await tester.pump();
      });
      expect(errors, isEmpty);
      expect(
        controller.headerHeight,
        greaterThan(OverviewListMetrics.yearHeaderHeight),
        reason: 'the scaled year line outgrows the default height',
      );
    });
  }

  testWidgets('dark theme renders the year in its onSurface', (tester) async {
    setSurface(tester, const Size(360, 780));
    final controller = AgendaYearScrollController(initialYear: 2026);
    await tester.pumpWidget(scroll(controller, theme: AppTheme.dark()));

    expect(tester.takeException(), isNull);
    final year = tester.widget<Text>(
      find.descendant(of: header(2026), matching: find.text('2026')),
    );
    expect(year.style?.color, AppTheme.dark().colorScheme.onSurface);
  });
}

/// Counts every question a section asks of its tiles.
class _CountingTiles extends AgendaYearTileSource {
  _CountingTiles(this.onTilesFor);

  final VoidCallback? onTilesFor;

  @override
  List<AgendaYearTile>? tilesFor(int year) {
    onTilesFor?.call();
    return super.tilesFor(year);
  }
}
