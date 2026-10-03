import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/agenda_day_list_mode.dart';

import 'support/day_list_robot.dart';
import 'support/layout_errors.dart';

/// The sheet renders a pre-resolved list — it reads no facade and localizes
/// only its own chrome — so what is worth pinning is exactly that contract: it
/// draws what it was handed, in order, dates its groups itself, and hands back
/// the day that was tapped.
///
/// Every case drives the sheet through [DayListRobot] (`support/`), so a
/// rebuild of the chrome rewrites the robot and leaves these bodies alone.
void main() {
  /// Far from any real "today", so a header can never read Today/Tomorrow.
  final today = DateTime.utc(2026, 8, 1);

  final entries = [
    AgendaDayListEntry(
      day: DateTime.utc(2026, 8, 15),
      icon: Icons.celebration_rounded,
      color: const Color(0xFFFFB300),
      title: 'Assumption of Mary',
    ),
    AgendaDayListEntry(
      day: DateTime.utc(2026, 12, 25),
      icon: Icons.celebration_rounded,
      color: const Color(0xFFFFB300),
      title: 'Christmas Day',
    ),
  ];

  final list = AgendaDayList(
    title: 'Holidays',
    subtitle: '2 holidays · Aug 15 – Dec 25',
    source: const AgendaDayListHolidaySource(),
    color: const Color(0xFFFFB300),
    entries: entries,
  );

  /// Opens the sheet the way the agenda does and captures its result.
  Future<DayListOutcome> openSheet(DayListRobot robot, AgendaDayList list) {
    return robot.show(
      list,
      resolve: (_, _) => const [],
      today: today,
      windowStart: DateTime.utc(2026, 8, 1),
      windowEnd: DateTime.utc(2026, 12, 31),
    );
  }

  // --- Fixtures for the list/month/year mode group below. ---

  /// Same "today" and window as `list` above, spread across 3 of the 5 window
  /// months (Aug, Oct, Dec) with two of them (Aug) sharing a month, so the
  /// month grid, the year tiles and the marked/unmarked day split all have
  /// something to show.
  final modesEntries = [
    AgendaDayListEntry(
      day: DateTime.utc(2026, 8, 5),
      icon: Icons.fitness_center,
      color: const Color(0xFF1E88E5),
      title: 'Task A',
    ),
    AgendaDayListEntry(
      day: DateTime.utc(2026, 8, 20),
      icon: Icons.fitness_center,
      color: const Color(0xFF1E88E5),
      title: 'Task B',
    ),
    AgendaDayListEntry(
      day: DateTime.utc(2026, 10, 10),
      icon: Icons.fitness_center,
      color: const Color(0xFF1E88E5),
      title: 'Task C',
    ),
    AgendaDayListEntry(
      day: DateTime.utc(2026, 12, 25),
      icon: Icons.fitness_center,
      color: const Color(0xFF1E88E5),
      title: 'Task D',
    ),
  ];

  const gymColor = Color(0xFF1E88E5);

  final modesList = AgendaDayList(
    title: 'Gym',
    subtitle: '4 events',
    source: const AgendaDayListCategorySource('gym'),
    color: gymColor,
    entries: modesEntries,
  );

  /// Everything the card's own scan would find over the whole browsable range,
  /// window included — what a real resolver rebuilds from the source. The two
  /// entries before the window are what month mode and the This-year tiles are
  /// supposed to reach and the window index cannot.
  final resolverPool = [
    AgendaDayListEntry(
      day: DateTime.utc(2025, 12, 3),
      icon: Icons.fitness_center,
      color: const Color(0xFF1E88E5),
      title: 'Task Older',
    ),
    AgendaDayListEntry(
      day: DateTime.utc(2026, 2, 14),
      icon: Icons.fitness_center,
      color: const Color(0xFF1E88E5),
      title: 'Task Past',
    ),
    ...modesEntries,
  ];

  /// Opens the sheet on the mode-testing fixture, optionally in a given
  /// locale, with an `onModeChanged` spy and with a resolver spy standing in
  /// for the agenda's own re-scan.
  Future<DayListOutcome> openModesSheet(
    DayListRobot robot, {
    Locale locale = const Locale('en'),
    ValueChanged<AgendaDayListMode>? onModeChanged,
    ResolverSpy? spy,
    AgendaDayList? list,
    AgendaDayListMode initialMode = AgendaDayListMode.list,
    DateTime? windowStart,
    DateTime? windowEnd,
    bool settle = true,
    AgendaDayMarkResolver? resolveMarks,
    AgendaYearBounds? yearBounds,
    double? textScale,
    Size? surface,
  }) {
    final resolve = spy ?? ResolverSpy(resolverPool);
    return robot.show(
      list ?? modesList,
      resolve: resolve.resolve,
      resolveMarks: resolveMarks,
      yearBounds: yearBounds,
      today: today,
      windowStart: windowStart ?? DateTime.utc(2026, 8, 1),
      windowEnd: windowEnd ?? DateTime.utc(2026, 12, 31),
      initialMode: initialMode,
      onModeChanged: onModeChanged,
      locale: locale,
      textScale: textScale,
      surface: surface,
      settle: settle,
    );
  }

  group('list / month / year modes', () {
    testWidgets('switching modes via the segmented button changes the body', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);

      expect(robot.drawnMode, AgendaDayListMode.list);

      await robot.pickMode(AgendaDayListMode.month);
      expect(robot.drawnMode, AgendaDayListMode.month);

      await robot.pickMode(AgendaDayListMode.year);
      expect(robot.drawnMode, AgendaDayListMode.year);

      await robot.pickMode(AgendaDayListMode.list);
      expect(robot.drawnMode, AgendaDayListMode.list);
    });

    testWidgets('year mode shows one tile per window month with counts', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);

      expect(robot.announcesTile('Aug 2026, 2 entries'), isTrue);
      expect(robot.announcesTile('Sep 2026, 0 entries'), isTrue);
      expect(robot.announcesTile('Oct 2026, 1 entry'), isTrue);
      expect(robot.announcesTile('Nov 2026, 0 entries'), isTrue);
      expect(robot.announcesTile('Dec 2026, 1 entry'), isTrue);
    });

    testWidgets(
      'tapping a year tile opens that month in month mode with a back arrow',
      (tester) async {
        final robot = DayListRobot(tester);
        await openModesSheet(robot);
        await robot.pickMode(AgendaDayListMode.year);
        expect(robot.showsBack, isFalse);

        await robot.tapTile('Oct 2026');

        expect(robot.drawnMode, AgendaDayListMode.month);
        expect(robot.shows('October 2026'), isTrue);
        expect(robot.showsBack, isTrue);
      },
    );

    testWidgets('the back arrow returns to year mode', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.tapTile('Oct 2026');

      await robot.back();

      expect(robot.drawnMode, AgendaDayListMode.year);
      expect(robot.showsBack, isFalse);
    });

    testWidgets('system back closes the sheet even while drilled', (
      tester,
    ) async {
      // The arrow is the only "back to the year overview" affordance. Back
      // means dismiss here exactly as it does on every sibling sheet, and the
      // caller gets the same null a scrim tap gives it.
      final robot = DayListRobot(tester);
      final picked = await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.tapTile('Oct 2026');

      await robot.systemBack();

      expect(robot.isOpen, isFalse);
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);
    });

    testWidgets('a scrim tap while drilled dismisses the sheet', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final picked = await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.tapTile('Oct 2026');

      await robot.tapBarrier();

      expect(robot.isOpen, isFalse);
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);
    });

    testWidgets(
      'tapping a marked day narrows the rows; whole month restores them',
      (tester) async {
        final robot = DayListRobot(tester);
        await openModesSheet(robot);
        await robot.pickMode(AgendaDayListMode.month);

        // Day 5 is marked (Task A); narrow to it. The grid is still at the
        // top here (no scroll happened yet), so its day numbers are on
        // screen without scrolling.
        await robot.tapDay(5);

        // Selecting a day scrolls the body back to the top, so the section
        // header and the (now single) row need a scroll to come into view.
        await robot.scrollMonthBody();
        expect(robot.shows('Task A'), isTrue);
        expect(robot.shows('Task B'), isFalse);
        expect(robot.wholeMonthActive, isTrue);

        await robot.wholeMonth();

        await robot.scrollMonthBody();
        expect(robot.shows('Task A'), isTrue);
        expect(robot.shows('Task B'), isTrue);
        expect(robot.wholeMonthActive, isFalse);
      },
    );

    testWidgets('tapping an unmarked day leaves the rows unchanged', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);

      // Day 6 carries no entry, so table_calendar treats it as disabled
      // (`enabledDayPredicate`) and the tap is a no-op: no selection, no
      // scroll-to-top, no "Whole month" action becoming usable.
      await robot.tapDay(6);

      await robot.scrollMonthBody();
      expect(robot.shows('Task A'), isTrue);
      expect(robot.shows('Task B'), isTrue);
      expect(robot.wholeMonthActive, isFalse);
    });

    testWidgets('tapping a row in month mode pops with that day', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final picked = await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);

      await robot.scrollMonthBody();
      await robot.tapEntry('Task A');

      expect(picked.result?.focusDay, DateTime.utc(2026, 8, 5));
      expect(picked.result?.edit, isNull);
    });

    testWidgets('the month chevrons page across a year boundary', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);

      // The whole navigable calendar is browsable — a tile of any year has
      // to open its month — so neither chevron ever disables near the window.
      await robot.previous(times: 8);
      expect(robot.navTitle, 'December 2025');
      expect(robot.canGoPrevious, isTrue);

      await robot.next(times: 13);
      expect(robot.navTitle, 'January 2027');
      expect(robot.canGoNext, isTrue);
    });

    testWidgets('the today button jumps back and is inert on today\'s month', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);

      // The selector opens month mode on today's month, so the jump is
      // already where it would take you.
      expect(robot.canJumpToToday, isFalse);

      await robot.previous(times: 3);
      expect(robot.navTitle, 'May 2026');
      expect(robot.canJumpToToday, isTrue);

      await robot.jumpToToday();
      expect(robot.navTitle, 'August 2026');
      expect(robot.canJumpToToday, isFalse);
    });

    testWidgets('onModeChanged fires only from the segmented button', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final calls = <AgendaDayListMode>[];
      await openModesSheet(robot, onModeChanged: calls.add);

      await robot.pickMode(AgendaDayListMode.year);
      expect(calls, [AgendaDayListMode.year]);

      // Drilling into a month from a year tile is navigation, not a mode
      // pick, so it must not fire a second time.
      await robot.tapTile('Oct 2026');
      expect(calls, [AgendaDayListMode.year]);

      // Nor does the back arrow that undoes it.
      await robot.back();
      expect(calls, [AgendaDayListMode.year]);
    });

    testWidgets(
      'list mode shows no month header for entries within one month',
      (tester) async {
        final singleMonthList = AgendaDayList(
          title: 'Gym',
          subtitle: '2 events',
          source: const AgendaDayListCategorySource('gym'),
          color: gymColor,
          entries: [
            AgendaDayListEntry(
              day: DateTime.utc(2026, 9, 5),
              icon: Icons.fitness_center,
              color: const Color(0xFF1E88E5),
              title: 'Task E',
            ),
            AgendaDayListEntry(
              day: DateTime.utc(2026, 9, 20),
              icon: Icons.fitness_center,
              color: const Color(0xFF1E88E5),
              title: 'Task F',
            ),
          ],
        );

        final robot = DayListRobot(tester);
        await openSheet(robot, singleMonthList);

        expect(robot.shows('Task E'), isTrue);
        expect(robot.shows('Task F'), isTrue);
        expect(robot.countOf('September'), 0);
      },
    );

    for (final size in [const Size(360, 640), const Size(320, 568)]) {
      for (final localeCode in ['en', 'de', 'ro']) {
        testWidgets('every mode and scope renders at '
            '${size.width.toInt()}x${size.height.toInt()} with no exceptions '
            '($localeCode)', (tester) async {
          addTearDown(tester.view.reset);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;

          final robot = DayListRobot(tester);
          await openModesSheet(robot, locale: Locale(localeCode));
          expect(tester.takeException(), isNull);

          await robot.pickMode(AgendaDayListMode.month);
          expect(tester.takeException(), isNull);

          await robot.pickMode(AgendaDayListMode.year);
          expect(tester.takeException(), isNull);

          await robot.pickScope(AgendaDayListYearScope.calendarYear);
          expect(tester.takeException(), isNull);

          await robot.pickScope(AgendaDayListYearScope.upcoming);
          expect(tester.takeException(), isNull);

          await robot.pickMode(AgendaDayListMode.list);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the year scope chips keep their labels whole in 48 dp runs '
        'at 320dp, and share one row where the font allows', (tester) async {
      // The segmented button this replaced (itself replacing a ChoiceChip
      // pair that wrapped in every locale) ellipsized its labels to fit one
      // row; a FormChip never cuts a label — it wraps to a second 48 dp run
      // instead (Tier 3 D1). The test font draws every glyph a full em wide,
      // about twice a phone's, so how many runs "Demnächst" and
      // "Kalenderjahr" take at 320 is the font's to say: what holds at any
      // font is whole labels in whole runs, and the one row shows on a
      // surface wide enough for the test font's chips.
      final robot = DayListRobot(tester);
      await openModesSheet(
        robot,
        locale: const Locale('de'),
        surface: const Size(320, 568),
      );
      await robot.pickMode(AgendaDayListMode.year);

      expect(robot.scopeLabelRects, hasLength(2));
      expect(robot.scopeChipsWhole, isTrue);
      expect(robot.scopeControlRect.height % FormMetrics.rowMinHeight, 0);
      expect(tester.takeException(), isNull);

      await robot.close();
      await openModesSheet(
        robot,
        locale: const Locale('de'),
        surface: const Size(400, 568),
      );
      await robot.pickMode(AgendaDayListMode.year);

      final labels = robot.scopeLabelRects;
      expect(labels[0].top, labels[1].top);
      expect(robot.scopeControlRect.height, FormMetrics.rowMinHeight);
      expect(
        robot.scopeChipsRect.width,
        lessThanOrEqualTo(
          400 - RowMetrics.groupInset - FormMetrics.rowEndPadding,
        ),
      );
    });

    testWidgets('the fixed header never moves between modes or states', (
      tester,
    ) async {
      // The mode selector is the bottom of the fixed header, so its rect is
      // the header's own. Every mode, and both back-arrow states, must place
      // it identically or the sheet twitches under the finger that switched
      // it.
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;

      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      final inList = robot.pinnedHeaderRect;
      // Pinned so a future padding change has to be deliberate; what matters
      // is that the three assertions below see this same rect. The mode chip
      // row spans the sheet (Tier 3 D1) under the handle, the 48 dp header
      // and the card's one-line caption with its 8 dp of air.
      expect(inList.left, closeTo(0, 0.5));
      expect(inList.top, closeTo(147.2, 0.5));
      expect(inList.right, closeTo(360, 0.5));
      expect(inList.bottom, closeTo(195.2, 0.5));

      await robot.pickMode(AgendaDayListMode.month);
      expect(robot.pinnedHeaderRect, inList);

      await robot.pickMode(AgendaDayListMode.year);
      expect(robot.pinnedHeaderRect, inList);

      await robot.tapTile('Oct 2026');
      expect(robot.showsBack, isTrue);
      expect(robot.pinnedHeaderRect, inList);
    });

    testWidgets('the back arrow and today button are full touch targets', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.tapTile('Oct 2026');

      expect(robot.backGlyphSize, const Size(24, 24));
      for (final button in [robot.backTargetSize, robot.todayTargetSize]) {
        expect(button.width, greaterThanOrEqualTo(48));
        expect(button.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('an empty day is faded and today never is', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);

      // Day 5 carries Task A; day 6 carries nothing; day 1 is `today` and
      // carries nothing either — and must still read as the day it is.
      expect(robot.isDayFaded(5), isFalse);
      expect(robot.isDayFaded(6), isTrue);
      expect(robot.isDayToday(1), isTrue);
      expect(robot.isDayFaded(1), isFalse);
    });
  });

  group('earlier months', () {
    testWidgets('list mode and the Upcoming tiles never resolve', (
      tester,
    ) async {
      // Both are the window's own scope, and the window arrived pre-resolved:
      // reaching for the resolver here would be work with nothing to show for
      // it.
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      expect(spy.calls, isEmpty);

      await robot.pickMode(AgendaDayListMode.year);
      expect(spy.calls, isEmpty);
      expect(robot.tileLabels, [
        'Aug 2026',
        'Sep 2026',
        'Oct 2026',
        'Nov 2026',
        'Dec 2026',
      ]);
    });

    testWidgets('month mode resolves once per month and caches it', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);

      await robot.pickMode(AgendaDayListMode.month);
      expect(spy.calls, [
        (DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 31)),
      ]);

      await robot.previous(times: 6);
      expect(robot.navTitle, 'February 2026');
      // One call per month stepped through, and only one.
      expect(spy.calls, hasLength(7));
      expect(spy.calls.last, (
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 2, 28),
      ));

      await robot.next(times: 6);
      expect(robot.navTitle, 'August 2026');
      expect(spy.calls, hasLength(7));
    });

    testWidgets('a past month shows the resolver rows and counts them all', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.month);
      await robot.previous(times: 6);

      // February is entirely outside the window the card counted, so the
      // window index knows nothing about it — the row and the count above it
      // can only have come from the resolver.
      expect(robot.navTitle, 'February 2026');
      expect(robot.navCount, '1 entry');
      await robot.scrollMonthBody();
      expect(robot.shows('Task Past'), isTrue);
    });

    testWidgets('the first window month shows all of itself, not the slice', (
      tester,
    ) async {
      // A window starting mid-month is the case month mode must not inherit:
      // the month header counts the calendar month, so the days before the
      // window's first day are real days with real rows.
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await robot.show(
        AgendaDayList(
          title: 'Gym',
          subtitle: '1 event',
          source: const AgendaDayListCategorySource('gym'),
          color: gymColor,
          entries: [modesEntries[1]],
        ),
        resolve: spy.resolve,
        today: DateTime.utc(2026, 8, 18),
        windowStart: DateTime.utc(2026, 8, 18),
        windowEnd: DateTime.utc(2026, 9, 30),
      );
      await robot.pickMode(AgendaDayListMode.month);

      // Aug 5 falls before the window's Aug 18 start; the card counted one
      // August entry, the month counts two.
      expect(robot.navTitle, 'August 2026');
      expect(robot.navCount, '2 entries');
      await robot.scrollMonthBody();
      expect(robot.shows('Task A'), isTrue);
      expect(robot.shows('Task B'), isTrue);
    });

    testWidgets('This year resolves the whole year in one call, then warms '
        'its neighbours', (tester) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.year);

      await robot.pickScope(AgendaDayListYearScope.calendarYear);
      // The shown year first, in one call; the two neighbours once the page
      // has settled, so the next swipe finds them ready.
      expect(spy.calls, [
        (DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31)),
        (DateTime.utc(2025, 1, 1), DateTime.utc(2025, 12, 31)),
        (DateTime.utc(2027, 1, 1), DateTime.utc(2027, 12, 31)),
      ]);
      expect(robot.tileLabels, [
        'Jan 2026',
        'Feb 2026',
        'Mar 2026',
        'Apr 2026',
        'May 2026',
        'Jun 2026',
        'Jul 2026',
        'Aug 2026',
        'Sep 2026',
        'Oct 2026',
        'Nov 2026',
        'Dec 2026',
      ]);

      expect(robot.announcesTile('Jan 2026, 0 entries'), isTrue);
      expect(robot.announcesTile('Feb 2026, 1 entry'), isTrue);
      expect(robot.announcesTile('Aug 2026, 2 entries'), isTrue);
      expect(robot.announcesTile('Dec 2026, 1 entry'), isTrue);

      // Going back is a pure re-render of the window index — no further
      // call, and the card's own months again.
      await robot.pickScope(AgendaDayListYearScope.upcoming);
      expect(spy.calls, hasLength(3));
      expect(robot.tileLabels, [
        'Aug 2026',
        'Sep 2026',
        'Oct 2026',
        'Nov 2026',
        'Dec 2026',
      ]);
    });

    testWidgets('paging to a warm year costs nothing and warms the next', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);
      expect(robot.navTitle, '2026');
      List<int> resolvedYears() => [for (final c in spy.calls) c.$1.year];

      await robot.previous();
      expect(robot.navTitle, '2025');
      // 2025 was warm; settling on it warms 2024 and nothing else.
      expect(resolvedYears(), [2026, 2025, 2027, 2024]);
      expect(robot.tileLabels.first, 'Jan 2025');
      expect(robot.tileLabels, hasLength(12));

      await robot.next();
      expect(robot.navTitle, '2026');
      expect(resolvedYears(), [2026, 2025, 2027, 2024]);
    });

    testWidgets('a swipe pages the years too', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);

      await robot.flingYears(const Offset(-300, 0));
      expect(robot.navTitle, '2027');

      await robot.flingYears(const Offset(300, 0));
      expect(robot.navTitle, '2026');
    });

    testWidgets('the year bounds stop the chevrons and the pager', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot, yearBounds: (first: 2025, last: 2026));
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);

      expect(robot.canGoNext, isFalse);
      await robot.previous();
      expect(robot.navTitle, '2025');
      expect(robot.canGoPrevious, isFalse);

      // A fling past the first page goes nowhere.
      await robot.flingYears(const Offset(300, 0));
      expect(robot.navTitle, '2025');
    });

    testWidgets('a marks resolver feeds the year pages and no rows resolve', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      final marks = <(DateTime, DateTime)>[];
      await openModesSheet(
        robot,
        spy: spy,
        resolveMarks: (start, end) {
          marks.add((start, end));
          return [
            for (final entry in resolverPool)
              if (!entry.day.isBefore(start) && !entry.day.isAfter(end))
                AgendaDayMark(
                  day: entry.day,
                  color: entry.color,
                  missed: entry.missed,
                ),
          ];
        },
      );
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);

      // The tiles came from marks alone: one call for the year, the row
      // resolver untouched.
      expect(marks.first, (DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31)));
      expect(spy.calls, isEmpty);
      expect(robot.announcesTile('Feb 2026, 1 entry'), isTrue);

      // Opening a month is the first time rows are needed.
      await robot.tapTile('Feb 2026');
      expect(spy.calls, [
        (DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 28)),
      ]);
    });

    testWidgets('the year title opens the jump picker', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);

      await robot.pickDate();
      expect(robot.jumpPickerOpen, isTrue);
    });

    testWidgets('the year nav\'s this-year button returns to today\'s year', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);
      expect(robot.canJumpToToday, isFalse);

      await robot.previous(times: 2);
      expect(robot.navTitle, '2024');
      expect(robot.canJumpToToday, isTrue);

      await robot.jumpToToday();
      expect(robot.navTitle, '2026');
      expect(robot.canJumpToToday, isFalse);
    });

    testWidgets('a tile of another year opens that month', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);
      await robot.previous();

      await robot.tapTile('Feb 2025');

      expect(robot.navTitle, 'February 2025');
      expect(robot.showsBack, isTrue);
    });

    testWidgets('a This year tile opens that month, already resolved', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);

      await robot.tapTile('Feb 2026');

      expect(robot.navTitle, 'February 2026');
      expect(robot.navCount, '1 entry');
      // Drilled into, not switched to: the back arrow returns to the tiles.
      expect(robot.showsBack, isTrue);
      // The whole year was resolved by the scope switch (and its neighbours
      // warmed), so the tile tap adds nothing.
      expect(spy.calls, hasLength(3));
    });

    testWidgets('the scope survives a drill-down and back', (tester) async {
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.pickScope(AgendaDayListYearScope.calendarYear);

      await robot.tapTile('Feb 2026');
      await robot.back();

      expect(robot.tileLabels, hasLength(12));
      expect(spy.calls, hasLength(3));
    });

    testWidgets('a sheet always opens on the card\'s own scope', (
      tester,
    ) async {
      // The number on the card is the window's, so the first thing the sheet
      // shows must be that number — the scope is session-only.
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.year);

      expect(robot.currentScope, AgendaDayListYearScope.upcoming);
    });

    testWidgets('a sheet opened in month mode resolves that month before its '
        'first frame', (tester) async {
      // The persisted mode can be `month`, and a month that resolved a frame
      // late would show an empty grid and a zero count first.
      final robot = DayListRobot(tester);
      final spy = ResolverSpy(resolverPool);
      await openModesSheet(
        robot,
        spy: spy,
        initialMode: AgendaDayListMode.month,
        settle: false,
      );

      expect(spy.calls, [
        (DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 31)),
      ]);

      await tester.pumpAndSettle();
      expect(robot.navTitle, 'August 2026');
      expect(robot.navCount, '2 entries');
      await robot.scrollMonthBody();
      expect(robot.shows('Task A'), isTrue);
    });

    testWidgets('month mode opens on a month the card actually covered', (
      tester,
    ) async {
      // A window pinned to 2020 with today six years later: the browsable
      // bounds reach today's month, but the card has nothing to say there, so
      // the sheet lands on the window's own last month instead.
      final pinned = AgendaDayList(
        title: 'Gym',
        subtitle: '1 event',
        source: const AgendaDayListCategorySource('gym'),
        color: gymColor,
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2020, 3, 9),
            icon: Icons.fitness_center,
            color: gymColor,
            title: 'Task 2020',
          ),
        ],
      );
      final robot = DayListRobot(tester);
      await openModesSheet(
        robot,
        list: pinned,
        spy: ResolverSpy(const []),
        windowStart: DateTime.utc(2020, 1, 1),
        windowEnd: DateTime.utc(2020, 12, 31),
      );

      await robot.pickMode(AgendaDayListMode.month);
      expect(robot.navTitle, 'December 2020');
    });

    testWidgets('a mid-swipe frame keeps both months\' bars', (tester) async {
      // The marker builder answers for the cell's **own** month, read from the
      // cache — during a page animation two months are on screen at once, and
      // keying the bars off the focused month alone blanked one of them.
      final robot = DayListRobot(tester);
      final spy = ResolverSpy([
        ...resolverPool,
        AgendaDayListEntry(
          day: DateTime.utc(2026, 9, 8),
          icon: Icons.fitness_center,
          color: gymColor,
          title: 'Task September',
        ),
      ]);
      await openModesSheet(robot, spy: spy);
      await robot.pickMode(AgendaDayListMode.month);
      expect(robot.dayBarCount, 2);

      await robot.dragGrid(const Offset(-400, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // August's two and September's one, all drawn from the cache: the
      // outgoing month did not go blank when the page index changed.
      expect(robot.dayBarCount, 3);

      await tester.pumpAndSettle();
      expect(robot.navTitle, 'September 2026');
    });
  });

  group('presence', () {
    /// August holds one attended occurrence and one missed one; the missed one
    /// is alone on its day, so that day is missed outright.
    final missedEntries = [
      AgendaDayListEntry(
        day: DateTime.utc(2026, 8, 5),
        icon: Icons.fitness_center,
        color: gymColor,
        title: 'Task A',
      ),
      AgendaDayListEntry(
        day: DateTime.utc(2026, 8, 20),
        icon: Icons.fitness_center,
        color: gymColor,
        title: 'Task B',
        missed: true,
      ),
    ];

    final missedList = AgendaDayList(
      title: 'Gym',
      subtitle: '2 events',
      source: const AgendaDayListCategorySource('gym'),
      color: gymColor,
      entries: missedEntries,
    );

    Future<void> openMissed(DayListRobot robot) async {
      await openModesSheet(
        robot,
        list: missedList,
        spy: ResolverSpy(missedEntries),
      );
    }

    testWidgets('a missed occurrence is dimmed rather than dropped', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);

      expect(robot.entryOpacity('Task B'), CalendarColors.missedEventAlpha);
      expect(robot.entryOpacity('Task A'), isNull);
    });

    testWidgets('a day header counts what was attended', (tester) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);

      // Aug 5 was attended, Aug 20 was not — and the day it was on still gets
      // its header and its faded row.
      expect(robot.countOf('Saturday, August 15'), 0);
      expect(robot.shows('1 entry'), isTrue);
      expect(robot.shows('0 entries · 1 missed'), isTrue);
    });

    testWidgets('the month count names the missed occurrences beside it', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);
      await robot.pickMode(AgendaDayListMode.month);

      // The nav row above the grid carries the month's; the section header
      // that repeated it under the grid is gone (Tier 3 D8), so a day's own
      // count is read off its read row once the day is picked — a row that
      // only comes into view once the body is scrolled.
      expect(robot.navTitle, 'August 2026');
      expect(robot.navCount, '1 entry · 1 missed');
      await robot.tapDay(20);
      await robot.scrollMonthBody();
      expect(robot.pickedDayCount, '0 entries · 1 missed');
    });

    testWidgets('a selected missed day counts zero and says why', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);
      await robot.pickMode(AgendaDayListMode.month);

      await robot.tapDay(20);
      await robot.scrollMonthBody();

      expect(robot.shows('0 entries · 1 missed'), isTrue);
      expect(robot.shows('Task B'), isTrue);
    });

    testWidgets('a missed day is still openable', (tester) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);
      await robot.pickMode(AgendaDayListMode.month);

      expect(robot.isDayFaded(20), isFalse);
    });

    testWidgets('a year tile counts attendance and announces the rest', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);
      await robot.pickMode(AgendaDayListMode.year);

      expect(robot.announcesTile('Aug 2026, 1 entry · 1 missed'), isTrue);
      // The bare number beside the label is the attendance count alone.
      expect(robot.tileCounts.where((count) => count == '1'), hasLength(1));
    });

    testWidgets('the dot matrix marks a missed day apart from a kept one', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openMissed(robot);
      await robot.pickMode(AgendaDayListMode.year);

      final matrix = robot.matrixOf('Aug 2026');
      // Both days are marked; only the 20th — nothing kept on it — is missed.
      expect(matrix.markedMask, (1 << 4) | (1 << 19));
      expect(matrix.missedMask, 1 << 19);
      expect(
        matrix.missedColor,
        gymColor.withValues(alpha: CalendarColors.missedEventAlpha),
      );
    });

    for (final localeCode in ['en', 'de', 'ro']) {
      testWidgets('the missed suffix fits every mode at 320x568 '
          '($localeCode)', (tester) async {
        // The longest line the sheet draws: "N entries · N missed" under the
        // month title, in the narrowest supported width.
        addTearDown(tester.view.reset);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;

        final robot = DayListRobot(tester);
        await openModesSheet(
          robot,
          locale: Locale(localeCode),
          list: missedList,
          spy: ResolverSpy(missedEntries),
        );
        expect(tester.takeException(), isNull);

        await robot.pickMode(AgendaDayListMode.month);
        expect(tester.takeException(), isNull);

        await robot.pickMode(AgendaDayListMode.year);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a day with one kept entry among missed ones is not missed', (
      tester,
    ) async {
      final mixed = [
        missedEntries[1],
        AgendaDayListEntry(
          day: DateTime.utc(2026, 8, 20),
          icon: Icons.fitness_center,
          color: gymColor,
          title: 'Task C',
        ),
      ];
      final robot = DayListRobot(tester);
      await openModesSheet(
        robot,
        list: AgendaDayList(
          title: 'Gym',
          subtitle: '2 events',
          source: const AgendaDayListCategorySource('gym'),
          color: gymColor,
          entries: mixed,
        ),
        spy: ResolverSpy(mixed),
      );
      await robot.pickMode(AgendaDayListMode.year);

      final matrix = robot.matrixOf('Aug 2026');
      expect(matrix.markedMask, 1 << 19);
      expect(matrix.missedMask, 0);
    });
  });

  testWidgets('the header repeats the card that opened it', (tester) async {
    final robot = DayListRobot(tester);
    await openSheet(robot, list);

    // Same title and same subtitle as the card, so the count the user tapped
    // is the count they are now looking at.
    expect(robot.headerTitle, 'Holidays');
    expect(robot.headerSubtitle, '2 holidays · Aug 15 – Dec 25');
  });

  testWidgets('every entry is drawn, title and subtitle', (tester) async {
    final robot = DayListRobot(tester);
    await openSheet(
      robot,
      AgendaDayList(
        title: 'Gym',
        subtitle: '2 events · Aug 15 – Dec 25',
        source: const AgendaDayListCategorySource('gym'),
        color: gymColor,
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2026, 8, 15),
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: 'Leg day',
            subtitle: 'Weekly · 07:00 – 08:00',
          ),
          AgendaDayListEntry(
            day: DateTime.utc(2026, 12, 25),
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: 'Pull day',
            subtitle: 'Weekly · 18:00 – 19:00',
          ),
        ],
      ),
    );

    expect(robot.shows('Leg day'), isTrue);
    expect(robot.shows('Weekly · 07:00 – 08:00'), isTrue);
    expect(robot.shows('Pull day'), isTrue);
    expect(robot.shows('Weekly · 18:00 – 19:00'), isTrue);
  });

  testWidgets('the date leaves the rows and heads a group', (tester) async {
    // The row content is now the agenda row's content, so the sheet is what
    // dates it — one header per day, under a month separator when the entries
    // span more than one.
    final robot = DayListRobot(tester);
    await openSheet(robot, list);

    expect(robot.shows('Saturday, August 15'), isTrue);
    expect(robot.shows('Friday, December 25'), isTrue);
    expect(robot.shows('August'), isTrue);
    expect(robot.shows('December'), isTrue);
    expect(robot.countOf('1 entry'), 2);
  });

  testWidgets('tapping an entry returns its day', (tester) async {
    final robot = DayListRobot(tester);
    final picked = await openSheet(robot, list);

    await robot.tapEntry('Christmas Day');

    expect(picked.result?.focusDay, DateTime.utc(2026, 12, 25));
  });

  testWidgets('dismissing returns null rather than a day', (tester) async {
    final robot = DayListRobot(tester);
    final picked = await openSheet(robot, list);

    // Tapping the scrim is how a user backs out; the caller must be able to
    // tell that apart from a pick, or it would focus a day nobody chose.
    await robot.tapBarrier();

    expect(picked.returned, isTrue);
    expect(picked.result, isNull);
  });

  testWidgets('an entry with no subtitle still renders', (tester) async {
    final robot = DayListRobot(tester);
    await openSheet(
      robot,
      AgendaDayList(
        title: 'Holidays',
        subtitle: '1 holiday',
        source: const AgendaDayListHolidaySource(),
        color: const Color(0xFFFFB300),
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2026, 8, 15),
            icon: Icons.celebration_rounded,
            color: const Color(0xFFFFB300),
            title: 'Assumption of Mary',
          ),
        ],
      ),
    );

    expect(robot.shows('Assumption of Mary'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row without an action carries no trailing widget', (
    tester,
  ) async {
    // Holiday and fasting days have no editor to open, so their rows must not
    // grow an empty action strip.
    final robot = DayListRobot(tester);
    await openSheet(robot, list);

    expect(robot.editButtonCount, 0);
  });

  testWidgets('a row with an action offers it and resolves it', (tester) async {
    // Collapsing the events layer must never put editing further away than it
    // was in the list it replaced.
    var ran = 0;
    final robot = DayListRobot(tester);
    final picked = await openSheet(
      robot,
      AgendaDayList(
        title: 'Gym',
        subtitle: '1 event · Aug 15',
        source: const AgendaDayListCategorySource('gym'),
        color: gymColor,
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2026, 8, 15),
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: 'Leg day',
            subtitle: 'Weekly · 07:00 – 08:00',
            onEdit: () => ran++,
          ),
        ],
      ),
    );

    await robot.tapEdit('Leg day');

    // The sheet resolves the intent rather than running it, so the caller can
    // open the editor after this sheet is gone instead of stacked on it.
    expect(ran, 0);
    expect(picked.result?.focusDay, isNull);
    expect(picked.result?.edit, isNotNull);

    picked.result!.edit!();
    expect(ran, 1);
  });

  testWidgets('list mode with no entries says so and keeps its chrome', (
    tester,
  ) async {
    // A card can outlive what it counted — a removed holiday, a reconfigured
    // fasting schedule, an occurrence hidden as missed — and list mode has no
    // month grid or year tiles to explain an empty body on its own. A blank
    // 88%-tall sheet reads as a broken app, which is the bug this closes.
    final robot = DayListRobot(tester);
    await openSheet(
      robot,
      AgendaDayList(
        title: 'Holidays',
        subtitle: '2 holidays · Aug 15 – Dec 25',
        source: const AgendaDayListHolidaySource(),
        color: const Color(0xFFFFB300),
        entries: const [],
      ),
    );

    expect(robot.emptyCaption, 'Nothing in this range');
    // The header and the mode switch survive, so the other two scopes stay
    // reachable from an empty window.
    expect(robot.headerTitle, 'Holidays');
    expect(robot.modeControlShown, isTrue);
  });

  testWidgets('a second tap on a row pops nothing more', (tester) async {
    // Two taps can be delivered in one frame, before anything has rebuilt —
    // and the second pop would take the page underneath the sheet with it.
    // Fired straight at the row's callback because that is exactly what a
    // same-frame double tap does; a second `tester.tap` cannot reproduce it,
    // since the route stops hit-testing the instant the first pop starts.
    final robot = DayListRobot(tester);
    final picked = await openSheet(robot, list);

    robot.tapEntryTwiceInOneFrame('Christmas Day');
    await tester.pumpAndSettle();

    expect(picked.result?.focusDay, DateTime.utc(2026, 12, 25));
    // The page the sheet was opened from is still there.
    expect(robot.hostVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second tap on a row action pops nothing more', (tester) async {
    var ran = 0;
    final robot = DayListRobot(tester);
    final picked = await openSheet(
      robot,
      AgendaDayList(
        title: 'Gym',
        subtitle: '1 event · Aug 15',
        source: const AgendaDayListCategorySource('gym'),
        color: gymColor,
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2026, 8, 15),
            icon: Icons.fitness_center,
            color: gymColor,
            title: 'Leg day',
            onEdit: () => ran++,
          ),
        ],
      ),
    );

    robot.tapEditTwiceInOneFrame('Leg day');
    await tester.pumpAndSettle();

    expect(picked.result?.edit, isNotNull);
    expect(robot.hostVisible, isTrue);
    expect(tester.takeException(), isNull);
    // Still an intent, resolved once by the caller.
    expect(ran, 0);
  });

  group('the chrome of the language', () {
    // Tier 3, slice 2 (`docs/calendar-language-tier-3-roadmap.md` §3.2): the
    // filler shape with the ✕ it never had, the mode and scope chips, the
    // rows of the language, and the large-text matrix the device walk of
    // 2026-10-03 found cut.

    /// A card with one editable entry, the shape every event card opens.
    final editableList = AgendaDayList(
      title: 'Gym',
      subtitle: '1 event · Aug 15',
      source: const AgendaDayListCategorySource('gym'),
      color: gymColor,
      entries: [
        AgendaDayListEntry(
          day: DateTime.utc(2026, 8, 15),
          icon: Icons.fitness_center,
          color: gymColor,
          title: 'Leg day',
          subtitle: 'Weekly · 07:00 – 08:00',
          onEdit: () {},
        ),
      ],
    );

    testWidgets('the ✕ returns null: from the list, from a month opened by '
        'its chip, and once ← has returned from a drilled month', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      var picked = await openModesSheet(robot);
      expect(robot.showsClose, isTrue);
      await robot.close();
      expect(robot.isOpen, isFalse);
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);

      picked = await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);
      await robot.close();
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);

      picked = await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.year);
      await robot.tapTile('Oct 2026');
      await robot.back();
      await robot.close();
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);
    });

    testWidgets('← takes the header\'s leading slot while drilled, replacing '
        'the ✕, and the ✕ is back after it', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      expect(robot.headerLeadingIdentifier, SemanticsIds.dayListClose);
      expect(robot.showsClose, isTrue);
      expect(robot.showsBack, isFalse);

      await robot.pickMode(AgendaDayListMode.year);
      await robot.tapTile('Oct 2026');
      expect(robot.headerLeadingIdentifier, SemanticsIds.dayListBack);
      expect(robot.showsBack, isTrue);
      expect(robot.showsClose, isFalse);

      await robot.back();
      expect(robot.headerLeadingIdentifier, SemanticsIds.dayListClose);
      expect(robot.showsClose, isTrue);
      expect(robot.showsBack, isFalse);
    });

    testWidgets('the mode and scope chips carry their ids and announce the '
        'selection, and the body carries its own', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      expect(robot.bodyNodeShown, isTrue);
      for (final mode in AgendaDayListMode.values) {
        expect(
          robot.modeChipSelected(mode, announced: true),
          mode == AgendaDayListMode.list,
          reason: '$mode',
        );
      }

      await robot.pickMode(AgendaDayListMode.year);
      for (final mode in AgendaDayListMode.values) {
        expect(
          robot.modeChipSelected(mode, announced: true),
          mode == AgendaDayListMode.year,
          reason: '$mode',
        );
      }
      for (final scope in AgendaDayListYearScope.values) {
        expect(
          robot.scopeChipSelected(scope, announced: true),
          scope == AgendaDayListYearScope.upcoming,
          reason: '$scope',
        );
      }

      await robot.pickScope(AgendaDayListYearScope.calendarYear);
      for (final scope in AgendaDayListYearScope.values) {
        expect(
          robot.scopeChipSelected(scope, announced: true),
          scope == AgendaDayListYearScope.calendarYear,
          reason: '$scope',
        );
      }
      expect(robot.currentMode, AgendaDayListMode.year);
      expect(robot.currentScope, AgendaDayListYearScope.calendarYear);
    });

    testWidgets('a picked day\'s read row carries the ✕, and tapping it '
        'restores the month\'s groups', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(robot);
      await robot.pickMode(AgendaDayListMode.month);
      expect(robot.wholeMonthActive, isFalse);

      await robot.tapDay(5);
      await robot.scrollMonthBody();
      expect(robot.wholeMonthActive, isTrue);
      expect(robot.showsReadRow('Wednesday, August 5'), isTrue);
      expect(robot.pickedDayCount, '1 entry');
      expect(robot.showsReadRow('Thursday, August 20'), isFalse);

      await robot.wholeMonth();
      await robot.scrollMonthBody();
      expect(robot.wholeMonthActive, isFalse);
      expect(robot.showsReadRow('Wednesday, August 5'), isTrue);
      expect(robot.showsReadRow('Thursday, August 20'), isTrue);
    });

    testWidgets('a day\'s read row is inert, has no chevron and is one node', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openSheet(robot, list);

      const label = 'Saturday, August 15';
      expect(robot.readRowInert(label), isTrue);
      expect(robot.readRowShowsChevron(label), isFalse);
      final node = robot.readRowNode(label);
      expect(node.label, contains(label));
      expect(node.label, contains('1 entry'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('an entry row is one node that taps, plus the pencil\'s', (
      tester,
    ) async {
      final robot = DayListRobot(tester);
      await openSheet(robot, editableList);

      expect(robot.entryShowsChevron('Leg day'), isFalse);
      final row = robot.entryNode('Leg day');
      expect(row.label, contains('Leg day'));
      expect(row.label, contains('Weekly · 07:00 – 08:00'));
      expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final pencil = robot.pencilNode('Leg day');
      expect(pencil.id, isNot(row.id));
      expect(pencil.tooltip, 'Edit event');
      expect(pencil.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    });

    testWidgets('German at text scale 2.0 on 360 × 780 lays out every mode '
        'and scope with no error, and nothing is cut', (tester) async {
      // What the device walk of 2026-10-03 found cut at this scale: the
      // weekday row, two-digit day numbers, the month title, the card's line
      // and a day label. The test font draws every glyph a full em wide,
      // about twice a phone's, so a month title the device fits on two lines
      // needs three here and ellipsizes; what holds at any font is the two
      // lines it may take and the row they are measured for.
      const subtitle = '2 Termine · 12× im Zeitraum · 3. Okt. – 1. Nov.';
      const dayLabel = 'Mittwoch, 5. August';
      final robot = DayListRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await openModesSheet(
          robot,
          locale: const Locale('de'),
          list: AgendaDayList(
            title: 'Training',
            subtitle: subtitle,
            source: const AgendaDayListCategorySource('gym'),
            color: gymColor,
            entries: modesEntries,
          ),
          textScale: 2.0,
          surface: const Size(360, 780),
        );
        expect(robot.headerSubtitleWrapsFreely, isTrue);
        expect(robot.headerSubtitleWhole, isTrue);
        expect(robot.headerSubtitleLines, greaterThan(1));
        expect(robot.textWhole(dayLabel), isTrue);
        expect(robot.textLines(dayLabel), greaterThan(1));
        expect(robot.modeChipsWhole, isTrue);

        await robot.pickMode(AgendaDayListMode.month);
        expect(robot.navTitle, 'August 2026');
        expect(robot.navTitleMayWrap, isTrue);
        expect(robot.navTitleLines, FormMetrics.periodTitleMaxLines);
        final monday = DateFormat.E('de').format(DateTime(2026, 8, 3));
        expect(robot.weekdayShown(monday), isTrue);
        expect(robot.dayNumberWhole(20), isTrue);
        expect(robot.dayNumberWhole(5), isTrue);

        await robot.pickMode(AgendaDayListMode.year);
        expect(robot.scopeChipsWhole, isTrue);
        await robot.pickScope(AgendaDayListYearScope.calendarYear);
        expect(robot.navTitle, '2026');
        expect(robot.navTitleLines, 1);
        await robot.pickScope(AgendaDayListYearScope.upcoming);
        await robot.pickMode(AgendaDayListMode.list);
      });
      expect(errors, isEmpty);
    });

    testWidgets('at text scale 2.0 the pinned chrome keeps its rect across '
        'modes and the back state too', (tester) async {
      final robot = DayListRobot(tester);
      await openModesSheet(
        robot,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(360, 780),
      );
      final header = robot.headerRect;
      final chips = robot.pinnedHeaderRect;

      await robot.pickMode(AgendaDayListMode.month);
      expect(robot.headerRect, header);
      expect(robot.pinnedHeaderRect, chips);

      await robot.pickMode(AgendaDayListMode.year);
      expect(robot.headerRect, header);
      expect(robot.pinnedHeaderRect, chips);

      await robot.tapTile(DateFormat.yMMM('de').format(DateTime(2026, 10)));
      expect(robot.showsBack, isTrue);
      expect(robot.headerRect, header);
      expect(robot.pinnedHeaderRect, chips);
    });
  });
}
