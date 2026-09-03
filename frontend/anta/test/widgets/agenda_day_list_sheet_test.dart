import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/widgets/agenda_day_list_sheet.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/month_dot_matrix.dart';

/// The sheet renders a pre-resolved list — it reads no facade and localizes
/// only its own chrome — so what is worth pinning is exactly that contract: it
/// draws what it was handed, in order, dates its groups itself, and hands back
/// the day that was tapped.
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
  Future<_Picked> openSheet(WidgetTester tester, AgendaDayList list) async {
    final picked = _Picked();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked.result = await AgendaDayListSheet.show(
                  context,
                  list,
                  resolve: (_, _) => const [],
                  appearance: const CalendarAppearance(),
                  today: today,
                  windowStart: DateTime.utc(2026, 8, 1),
                  windowEnd: DateTime.utc(2026, 12, 31),
                );
                picked.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  // --- Fixtures and helpers for the list/month/year mode group below. ---

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

  /// The segmented button that switches modes, scoped so a tap can never land
  /// on some other same-named control the sheet might grow later.
  final modeControl = find.byWidgetPredicate(
    (w) => w is SegmentedButton<AgendaDayListMode>,
  );

  /// Switches mode by the segment's icon rather than its label, so the same
  /// helper works whatever locale the sheet was opened in.
  Future<void> tapMode(WidgetTester tester, IconData icon) async {
    await tester.tap(
      find.descendant(of: modeControl, matching: find.byIcon(icon)),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the month body's `CustomScrollView` to its end directly on the
  /// `ScrollPosition`, so the rows below the nav row and grid come into the
  /// lazy sliver's build range — `find.text` cannot see a `SliverList` item
  /// that has never been laid out. A position jump rather than a drag
  /// gesture: a drag's synthetic pointer travels across the day grid on the
  /// way down, and this sheet's grid is interactive.
  Future<void> scrollMonthBody(WidgetTester tester) async {
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable.first);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  /// Whether the "Whole month" action is currently usable. The button stays
  /// in the tree even with no day selected (`Visibility(maintainState:
  /// true)`, so the section header never resizes when a day is picked) —
  /// merely invisible and disabled — so `find.text('Whole month')` alone
  /// cannot tell "selected" from "not selected"; its `onPressed` can.
  bool wholeMonthActive(WidgetTester tester) {
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Whole month'),
        matching: find.byType(TextButton),
      ),
    );
    return button.onPressed != null;
  }

  /// Opens the sheet on the mode-testing fixture, optionally in a given
  /// locale, with an `onModeChanged` spy and with a resolver spy standing in
  /// for the agenda's own re-scan.
  Future<_Picked> openModesSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ValueChanged<AgendaDayListMode>? onModeChanged,
    _ResolverSpy? spy,
    AgendaDayList? list,
    AgendaDayListMode initialMode = AgendaDayListMode.list,
    DateTime? windowStart,
    DateTime? windowEnd,
    bool settle = true,
  }) async {
    final picked = _Picked();
    final resolve = spy ?? _ResolverSpy(resolverPool);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked.result = await AgendaDayListSheet.show(
                  context,
                  list ?? modesList,
                  resolve: resolve.resolve,
                  appearance: const CalendarAppearance(),
                  today: today,
                  windowStart: windowStart ?? DateTime.utc(2026, 8, 1),
                  windowEnd: windowEnd ?? DateTime.utc(2026, 12, 31),
                  initialMode: initialMode,
                  onModeChanged: onModeChanged,
                );
                picked.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return picked;
  }

  /// Steps the month navigation. Addressed by icon so the helper survives a
  /// locale change, and settled so the resolver has run before the assertion.
  Future<void> tapNav(
    WidgetTester tester,
    IconData icon, {
    int times = 1,
  }) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.widgetWithIcon(IconButton, icon));
      await tester.pumpAndSettle();
    }
  }

  IconButton navButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  /// The month nav row's two lines. It is the first sliver of the month body,
  /// so its texts lead the `CustomScrollView`'s in tree order — the title
  /// first, its whole-month count second.
  List<String> monthNav(WidgetTester tester) {
    return tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Text),
          ),
        )
        .take(2)
        .map((text) => text.data ?? '')
        .toList();
  }

  /// The year tiles' month labels, in grid order. The count beside each label
  /// is a bare number, so anything unparseable is a label.
  List<String> yearTileLabels(WidgetTester tester) {
    return [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byType(GridView), matching: find.byType(Text)),
      ))
        if (int.tryParse(text.data ?? '') == null) text.data ?? '',
    ];
  }

  /// The year overview's scope selector — typed, so it can never be confused
  /// with the mode selector in the header above it.
  final scopeControl = find.byWidgetPredicate(
    (w) => w is SegmentedButton<AgendaDayListYearScope>,
  );

  /// Switches the year overview's scope by position rather than by label, so
  /// the helper works in every locale.
  Future<void> tapScope(WidgetTester tester, int index) async {
    await tester.tap(
      find.descendant(of: scopeControl, matching: find.byType(Text)).at(index),
    );
    await tester.pumpAndSettle();
  }

  /// The dot matrix of a year tile, addressed by the month label beside it.
  /// `find.ancestor` walks outward from the label, so the first `Material` is
  /// the tile's own.
  MonthDotMatrix matrixFor(WidgetTester tester, String label) {
    return tester.widget<MonthDotMatrix>(
      find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
        matching: find.byType(MonthDotMatrix),
      ),
    );
  }

  group('list / month / year modes', () {
    testWidgets('switching modes via the segmented button changes the body', (
      tester,
    ) async {
      await openModesSheet(tester);

      expect(find.byType(ListView), findsOneWidget);

      await tapMode(tester, Icons.calendar_view_month_rounded);
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);

      await tapMode(tester, Icons.grid_view_rounded);
      expect(find.byType(CustomScrollView), findsNothing);
      expect(find.byType(GridView), findsOneWidget);

      await tapMode(tester, Icons.format_list_bulleted_rounded);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('year mode shows one tile per window month with counts', (
      tester,
    ) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.grid_view_rounded);

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Aug 2026, 2 entries'), findsOneWidget);
      expect(find.bySemanticsLabel('Sep 2026, 0 entries'), findsOneWidget);
      expect(find.bySemanticsLabel('Oct 2026, 1 entry'), findsOneWidget);
      expect(find.bySemanticsLabel('Nov 2026, 0 entries'), findsOneWidget);
      expect(find.bySemanticsLabel('Dec 2026, 1 entry'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'tapping a year tile opens that month in month mode with a back arrow',
      (tester) async {
        await openModesSheet(tester);
        await tapMode(tester, Icons.grid_view_rounded);
        expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

        await tester.tap(find.text('Oct 2026'));
        await tester.pumpAndSettle();

        expect(find.byType(CustomScrollView), findsOneWidget);
        expect(find.text('October 2026'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      },
    );

    testWidgets('the back arrow returns to year mode', (tester) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.grid_view_rounded);
      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });

    testWidgets('system back closes the sheet even while drilled', (
      tester,
    ) async {
      // The arrow is the only "back to the year overview" affordance. Back
      // means dismiss here exactly as it does on every sibling sheet, and the
      // caller gets the same null a scrim tap gives it.
      final picked = await openModesSheet(tester);
      await tapMode(tester, Icons.grid_view_rounded);
      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(AgendaDayListSheet), findsNothing);
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);
    });

    testWidgets('a scrim tap while drilled dismisses the sheet', (
      tester,
    ) async {
      final picked = await openModesSheet(tester);
      await tapMode(tester, Icons.grid_view_rounded);
      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();

      expect(find.byType(AgendaDayListSheet), findsNothing);
      expect(picked.returned, isTrue);
      expect(picked.result, isNull);
    });

    testWidgets(
      'tapping a marked day narrows the rows; whole month restores them',
      (tester) async {
        await openModesSheet(tester);
        await tapMode(tester, Icons.calendar_view_month_rounded);

        // Day 5 is marked (Task A); narrow to it. The grid is still at the
        // top here (no scroll happened yet), so its day numbers are on
        // screen without scrolling.
        await tester.tap(find.text('5'));
        await tester.pumpAndSettle();

        // Selecting a day scrolls the body back to the top, so the section
        // header and the (now single) row need a scroll to come into view.
        await scrollMonthBody(tester);
        expect(find.text('Task A'), findsOneWidget);
        expect(find.text('Task B'), findsNothing);
        expect(wholeMonthActive(tester), isTrue);

        await tester.tap(find.text('Whole month'));
        await tester.pumpAndSettle();

        await scrollMonthBody(tester);
        expect(find.text('Task A'), findsOneWidget);
        expect(find.text('Task B'), findsOneWidget);
        expect(wholeMonthActive(tester), isFalse);
      },
    );

    testWidgets('tapping an unmarked day leaves the rows unchanged', (
      tester,
    ) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      // Day 6 carries no entry, so table_calendar treats it as disabled
      // (`enabledDayPredicate`) and the tap is a no-op: no selection, no
      // scroll-to-top, no "Whole month" action becoming usable.
      await tester.tap(find.text('6'));
      await tester.pumpAndSettle();

      await scrollMonthBody(tester);
      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
      expect(wholeMonthActive(tester), isFalse);
    });

    testWidgets('tapping a row in month mode pops with that day', (
      tester,
    ) async {
      final picked = await openModesSheet(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      await scrollMonthBody(tester);
      await tester.tap(find.text('Task A'));
      await tester.pumpAndSettle();

      expect(picked.result?.focusDay, DateTime.utc(2026, 8, 5));
      expect(picked.result?.edit, isNull);
    });

    testWidgets('the month chevrons stop at the browsable bounds', (
      tester,
    ) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      // Today is Aug 2026 and the window is Aug–Dec 2026, so the bounds are a
      // year back from August (Aug 2025) and December of this year.
      expect(
        navButton(tester, Icons.chevron_left_rounded).onPressed,
        isNotNull,
      );
      expect(
        navButton(tester, Icons.chevron_right_rounded).onPressed,
        isNotNull,
      );

      await tapNav(tester, Icons.chevron_left_rounded, times: 12);
      expect(monthNav(tester).first, 'August 2025');
      expect(navButton(tester, Icons.chevron_left_rounded).onPressed, isNull);
      expect(
        navButton(tester, Icons.chevron_right_rounded).onPressed,
        isNotNull,
      );

      await tapNav(tester, Icons.chevron_right_rounded, times: 16);
      expect(monthNav(tester).first, 'December 2026');
      expect(navButton(tester, Icons.chevron_right_rounded).onPressed, isNull);
      expect(
        navButton(tester, Icons.chevron_left_rounded).onPressed,
        isNotNull,
      );
    });

    testWidgets('the today button jumps back and is inert on today\'s month', (
      tester,
    ) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      // The selector opens month mode on today's month, so the jump is
      // already where it would take you.
      expect(navButton(tester, Icons.today_rounded).onPressed, isNull);

      await tapNav(tester, Icons.chevron_left_rounded, times: 3);
      expect(monthNav(tester).first, 'May 2026');
      expect(navButton(tester, Icons.today_rounded).onPressed, isNotNull);

      await tapNav(tester, Icons.today_rounded);
      expect(monthNav(tester).first, 'August 2026');
      expect(navButton(tester, Icons.today_rounded).onPressed, isNull);
    });

    testWidgets('onModeChanged fires only from the segmented button', (
      tester,
    ) async {
      final calls = <AgendaDayListMode>[];
      await openModesSheet(tester, onModeChanged: calls.add);

      await tapMode(tester, Icons.grid_view_rounded);
      expect(calls, [AgendaDayListMode.year]);

      // Drilling into a month from a year tile is navigation, not a mode
      // pick, so it must not fire a second time.
      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();
      expect(calls, [AgendaDayListMode.year]);

      // Nor does the back arrow that undoes it.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
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

        await openSheet(tester, singleMonthList);

        expect(find.text('Task E'), findsOneWidget);
        expect(find.text('Task F'), findsOneWidget);
        expect(find.text('September'), findsNothing);
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

          await openModesSheet(tester, locale: Locale(localeCode));
          expect(tester.takeException(), isNull);

          await tapMode(tester, Icons.calendar_view_month_rounded);
          expect(tester.takeException(), isNull);

          await tapMode(tester, Icons.grid_view_rounded);
          expect(tester.takeException(), isNull);

          await tapScope(tester, 1);
          expect(tester.takeException(), isNull);

          await tapScope(tester, 0);
          expect(tester.takeException(), isNull);

          await tapMode(tester, Icons.format_list_bulleted_rounded);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the year scope selector fits on one row at 320dp', (
      tester,
    ) async {
      // The chip pair this replaced measured 336-378dp against 288-328dp of
      // usable width and wrapped in every locale.
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;

      await openModesSheet(tester, locale: const Locale('de'));
      await tapMode(tester, Icons.grid_view_rounded);

      final labels = find.descendant(
        of: scopeControl,
        matching: find.byType(Text),
      );
      expect(labels, findsNWidgets(2));
      expect(
        tester.getRect(labels.at(0)).top,
        tester.getRect(labels.at(1)).top,
      );
      expect(tester.getRect(scopeControl).width, lessThanOrEqualTo(288));
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

      await openModesSheet(tester);
      final inList = tester.getRect(modeControl);
      // Pinned so a future padding change has to be deliberate; what matters
      // is that the three assertions below see this same rect.
      expect(inList.left, closeTo(16, 0.5));
      expect(inList.top, closeTo(179, 0.5));
      expect(inList.right, closeTo(344, 0.5));
      expect(inList.bottom, closeTo(227, 0.5));

      await tapMode(tester, Icons.calendar_view_month_rounded);
      expect(tester.getRect(modeControl), inList);

      await tapMode(tester, Icons.grid_view_rounded);
      expect(tester.getRect(modeControl), inList);

      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(tester.getRect(modeControl), inList);
    });

    testWidgets('the back arrow and today button are full touch targets', (
      tester,
    ) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.grid_view_rounded);
      await tester.tap(find.text('Oct 2026'));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byIcon(Icons.arrow_back_rounded).hitTestable()),
        const Size(24, 24),
      );
      for (final icon in [Icons.arrow_back_rounded, Icons.today_rounded]) {
        final button = tester.getSize(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.width, greaterThanOrEqualTo(48));
        expect(button.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('an empty day is faded and today never is', (tester) async {
      await openModesSheet(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      CalendarDayCell cellFor(String day) => tester.widget<CalendarDayCell>(
        find.ancestor(
          of: find.text(day),
          matching: find.byType(CalendarDayCell),
        ),
      );

      // Day 5 carries Task A; day 6 carries nothing; day 1 is `today` and
      // carries nothing either — and must still read as the day it is.
      expect(cellFor('5').isOutside, isFalse);
      expect(cellFor('6').isOutside, isTrue);
      expect(cellFor('1').isToday, isTrue);
      expect(cellFor('1').isOutside, isFalse);
    });
  });

  group('earlier months', () {
    testWidgets('list mode and the Upcoming tiles never resolve', (
      tester,
    ) async {
      // Both are the window's own scope, and the window arrived pre-resolved:
      // reaching for the resolver here would be work with nothing to show for
      // it.
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);
      expect(spy.calls, isEmpty);

      await tapMode(tester, Icons.grid_view_rounded);
      expect(spy.calls, isEmpty);
      expect(yearTileLabels(tester), [
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
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);

      await tapMode(tester, Icons.calendar_view_month_rounded);
      expect(spy.calls, [
        (DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 31)),
      ]);

      await tapNav(tester, Icons.chevron_left_rounded, times: 6);
      expect(monthNav(tester).first, 'February 2026');
      // One call per month stepped through, and only one.
      expect(spy.calls, hasLength(7));
      expect(spy.calls.last, (
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 2, 28),
      ));

      await tapNav(tester, Icons.chevron_right_rounded, times: 6);
      expect(monthNav(tester).first, 'August 2026');
      expect(spy.calls, hasLength(7));
    });

    testWidgets('a past month shows the resolver rows and counts them all', (
      tester,
    ) async {
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);
      await tapMode(tester, Icons.calendar_view_month_rounded);
      await tapNav(tester, Icons.chevron_left_rounded, times: 6);

      // February is entirely outside the window the card counted, so the
      // window index knows nothing about it — the row and the count above it
      // can only have come from the resolver.
      expect(monthNav(tester), ['February 2026', '1 entry']);
      await scrollMonthBody(tester);
      expect(find.text('Task Past'), findsOneWidget);
    });

    testWidgets('the first window month shows all of itself, not the slice', (
      tester,
    ) async {
      // A window starting mid-month is the case month mode must not inherit:
      // the month header counts the calendar month, so the days before the
      // window's first day are real days with real rows.
      final spy = _ResolverSpy(resolverPool);
      final picked = _Picked();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked.result = await AgendaDayListSheet.show(
                    context,
                    AgendaDayList(
                      title: 'Gym',
                      subtitle: '1 event',
                      source: const AgendaDayListCategorySource('gym'),
                      color: gymColor,
                      entries: [modesEntries[1]],
                    ),
                    resolve: spy.resolve,
                    appearance: const CalendarAppearance(),
                    today: DateTime.utc(2026, 8, 18),
                    windowStart: DateTime.utc(2026, 8, 18),
                    windowEnd: DateTime.utc(2026, 9, 30),
                  );
                  picked.returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tapMode(tester, Icons.calendar_view_month_rounded);

      // Aug 5 falls before the window's Aug 18 start; the card counted one
      // August entry, the month counts two.
      expect(monthNav(tester), ['August 2026', '2 entries']);
      await scrollMonthBody(tester);
      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
    });

    testWidgets('This year resolves the whole year in one call', (
      tester,
    ) async {
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);
      await tapMode(tester, Icons.grid_view_rounded);

      await tapScope(tester, 1);
      expect(spy.calls, [
        (DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31)),
      ]);
      expect(yearTileLabels(tester), [
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

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Jan 2026, 0 entries'), findsOneWidget);
      expect(find.bySemanticsLabel('Feb 2026, 1 entry'), findsOneWidget);
      expect(find.bySemanticsLabel('Aug 2026, 2 entries'), findsOneWidget);
      expect(find.bySemanticsLabel('Dec 2026, 1 entry'), findsOneWidget);
      handle.dispose();

      // Going back is a pure re-render of the window index — no second call,
      // and the card's own months again.
      await tapScope(tester, 0);
      expect(spy.calls, hasLength(1));
      expect(yearTileLabels(tester), [
        'Aug 2026',
        'Sep 2026',
        'Oct 2026',
        'Nov 2026',
        'Dec 2026',
      ]);
    });

    testWidgets('a This year tile opens that month, already resolved', (
      tester,
    ) async {
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);
      await tapMode(tester, Icons.grid_view_rounded);
      await tapScope(tester, 1);

      await tester.tap(find.text('Feb 2026'));
      await tester.pumpAndSettle();

      expect(monthNav(tester), ['February 2026', '1 entry']);
      // Drilled into, not switched to: the back arrow returns to the tiles.
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      // The whole year was resolved by the scope switch, so the tile tap adds
      // nothing.
      expect(spy.calls, hasLength(1));
    });

    testWidgets('the scope survives a drill-down and back', (tester) async {
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);
      await tapMode(tester, Icons.grid_view_rounded);
      await tapScope(tester, 1);

      await tester.tap(find.text('Feb 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(yearTileLabels(tester), hasLength(12));
      expect(spy.calls, hasLength(1));
    });

    testWidgets('a sheet always opens on the card\'s own scope', (
      tester,
    ) async {
      // The number on the card is the window's, so the first thing the sheet
      // shows must be that number — the scope is session-only.
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(tester, spy: spy);
      await tapMode(tester, Icons.grid_view_rounded);

      final scope = tester.widget<SegmentedButton<AgendaDayListYearScope>>(
        scopeControl,
      );
      expect(scope.selected, {AgendaDayListYearScope.upcoming});
    });

    testWidgets('a sheet opened in month mode resolves that month before its '
        'first frame', (tester) async {
      // The persisted mode can be `month`, and a month that resolved a frame
      // late would show an empty grid and a zero count first.
      final spy = _ResolverSpy(resolverPool);
      await openModesSheet(
        tester,
        spy: spy,
        initialMode: AgendaDayListMode.month,
        settle: false,
      );

      expect(spy.calls, [
        (DateTime.utc(2026, 8, 1), DateTime.utc(2026, 8, 31)),
      ]);

      await tester.pumpAndSettle();
      expect(monthNav(tester), ['August 2026', '2 entries']);
      await scrollMonthBody(tester);
      expect(find.text('Task A'), findsOneWidget);
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
      await openModesSheet(
        tester,
        list: pinned,
        spy: _ResolverSpy(const []),
        windowStart: DateTime.utc(2020, 1, 1),
        windowEnd: DateTime.utc(2020, 12, 31),
      );

      await tapMode(tester, Icons.calendar_view_month_rounded);
      expect(monthNav(tester).first, 'December 2020');
    });

    testWidgets('a mid-swipe frame keeps both months\' bars', (tester) async {
      // The marker builder answers for the cell's **own** month, read from the
      // cache — during a page animation two months are on screen at once, and
      // keying the bars off the focused month alone blanked one of them.
      final spy = _ResolverSpy([
        ...resolverPool,
        AgendaDayListEntry(
          day: DateTime.utc(2026, 9, 8),
          icon: Icons.fitness_center,
          color: gymColor,
          title: 'Task September',
        ),
      ]);
      await openModesSheet(tester, spy: spy);
      await tapMode(tester, Icons.calendar_view_month_rounded);
      expect(find.byType(CalendarDayBars), findsNWidgets(2));

      await tester.drag(
        find.byType(TableCalendar<void>),
        const Offset(-400, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // August's two and September's one, all drawn from the cache: the
      // outgoing month did not go blank when the page index changed.
      expect(find.byType(CalendarDayBars), findsNWidgets(3));

      await tester.pumpAndSettle();
      expect(monthNav(tester).first, 'September 2026');
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

    Future<void> openMissed(WidgetTester tester) async {
      await openModesSheet(
        tester,
        list: missedList,
        spy: _ResolverSpy(missedEntries),
      );
    }

    testWidgets('a missed occurrence is dimmed rather than dropped', (
      tester,
    ) async {
      await openMissed(tester);

      final faded = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Task B'), matching: find.byType(Opacity))
            .first,
      );
      expect(faded.opacity, CalendarColors.missedEventAlpha);
      expect(
        find.ancestor(of: find.text('Task A'), matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('a day header counts what was attended', (tester) async {
      await openMissed(tester);

      // Aug 5 was attended, Aug 20 was not — and the day it was on still gets
      // its header and its faded row.
      expect(find.text('Saturday, August 15'), findsNothing);
      expect(find.text('1 entry'), findsOneWidget);
      expect(find.text('0 entries · 1 missed'), findsOneWidget);
    });

    testWidgets('the month count names the missed occurrences beside it', (
      tester,
    ) async {
      await openMissed(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      // The nav row above the grid and the section header below it both carry
      // it; the header only comes into view once the body is scrolled.
      expect(monthNav(tester), ['August 2026', '1 entry · 1 missed']);
      await scrollMonthBody(tester);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Whole month'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.text('1 entry · 1 missed'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a selected missed day counts zero and says why', (
      tester,
    ) async {
      await openMissed(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await scrollMonthBody(tester);

      expect(find.text('0 entries · 1 missed'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
    });

    testWidgets('a missed day is still openable', (tester) async {
      await openMissed(tester);
      await tapMode(tester, Icons.calendar_view_month_rounded);

      final cell = tester.widget<CalendarDayCell>(
        find.ancestor(
          of: find.text('20'),
          matching: find.byType(CalendarDayCell),
        ),
      );
      expect(cell.isOutside, isFalse);
    });

    testWidgets('a year tile counts attendance and announces the rest', (
      tester,
    ) async {
      await openMissed(tester);
      await tapMode(tester, Icons.grid_view_rounded);

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Aug 2026, 1 entry · 1 missed'),
        findsOneWidget,
      );
      handle.dispose();
      // The bare number beside the label is the attendance count alone.
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('the dot matrix marks a missed day apart from a kept one', (
      tester,
    ) async {
      await openMissed(tester);
      await tapMode(tester, Icons.grid_view_rounded);

      final matrix = matrixFor(tester, 'Aug 2026');
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

        await openModesSheet(
          tester,
          locale: Locale(localeCode),
          list: missedList,
          spy: _ResolverSpy(missedEntries),
        );
        expect(tester.takeException(), isNull);

        await tapMode(tester, Icons.calendar_view_month_rounded);
        expect(tester.takeException(), isNull);

        await tapMode(tester, Icons.grid_view_rounded);
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
      await openModesSheet(
        tester,
        list: AgendaDayList(
          title: 'Gym',
          subtitle: '2 events',
          source: const AgendaDayListCategorySource('gym'),
          color: gymColor,
          entries: mixed,
        ),
        spy: _ResolverSpy(mixed),
      );
      await tapMode(tester, Icons.grid_view_rounded);

      final matrix = matrixFor(tester, 'Aug 2026');
      expect(matrix.markedMask, 1 << 19);
      expect(matrix.missedMask, 0);
    });
  });

  testWidgets('the header repeats the card that opened it', (tester) async {
    await openSheet(tester, list);

    // Same title and same subtitle as the card, so the count the user tapped
    // is the count they are now looking at.
    expect(find.text('Holidays'), findsOneWidget);
    expect(find.text('2 holidays · Aug 15 – Dec 25'), findsOneWidget);
  });

  testWidgets('every entry is drawn, title and subtitle', (tester) async {
    await openSheet(
      tester,
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

    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Weekly · 07:00 – 08:00'), findsOneWidget);
    expect(find.text('Pull day'), findsOneWidget);
    expect(find.text('Weekly · 18:00 – 19:00'), findsOneWidget);
  });

  testWidgets('the date leaves the rows and heads a group', (tester) async {
    // The row content is now the agenda row's content, so the sheet is what
    // dates it — one header per day, under a month separator when the entries
    // span more than one.
    await openSheet(tester, list);

    expect(find.text('Saturday, August 15'), findsOneWidget);
    expect(find.text('Friday, December 25'), findsOneWidget);
    expect(find.text('August'), findsOneWidget);
    expect(find.text('December'), findsOneWidget);
    expect(find.text('1 entry'), findsNWidgets(2));
  });

  testWidgets('tapping an entry returns its day', (tester) async {
    final picked = await openSheet(tester, list);

    await tester.tap(find.text('Christmas Day'));
    await tester.pumpAndSettle();

    expect(picked.result?.focusDay, DateTime.utc(2026, 12, 25));
  });

  testWidgets('dismissing returns null rather than a day', (tester) async {
    final picked = await openSheet(tester, list);

    // Tapping the scrim is how a user backs out; the caller must be able to
    // tell that apart from a pick, or it would focus a day nobody chose.
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();

    expect(picked.returned, isTrue);
    expect(picked.result, isNull);
  });

  testWidgets('an entry with no subtitle still renders', (tester) async {
    await openSheet(
      tester,
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

    expect(find.text('Assumption of Mary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row without an action carries no trailing widget', (
    tester,
  ) async {
    // Holiday and fasting days have no editor to open, so their rows must not
    // grow an empty action strip.
    await openSheet(tester, list);

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('a row with an action offers it and resolves it', (tester) async {
    // Collapsing the events layer must never put editing further away than it
    // was in the list it replaced.
    var ran = 0;
    final picked = await openSheet(
      tester,
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

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

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
    await openSheet(
      tester,
      AgendaDayList(
        title: 'Holidays',
        subtitle: '2 holidays · Aug 15 – Dec 25',
        source: const AgendaDayListHolidaySource(),
        color: const Color(0xFFFFB300),
        entries: const [],
      ),
    );

    expect(find.text('Nothing in this range'), findsOneWidget);
    // The header and the mode switch survive, so the other two scopes stay
    // reachable from an empty window.
    expect(find.text('Holidays'), findsOneWidget);
    expect(modeControl, findsOneWidget);
  });

  testWidgets('a second tap on a row pops nothing more', (tester) async {
    // Two taps can be delivered in one frame, before anything has rebuilt —
    // and the second pop would take the page underneath the sheet with it.
    // Fired straight at the tile's callback because that is exactly what a
    // same-frame double tap does; a second `tester.tap` cannot reproduce it,
    // since the route stops hit-testing the instant the first pop starts.
    final picked = await openSheet(tester, list);
    final tile = tester.widget<ListTile>(
      find
          .ancestor(
            of: find.text('Christmas Day'),
            matching: find.byType(ListTile),
          )
          .first,
    );

    tile.onTap!();
    tile.onTap!();
    await tester.pumpAndSettle();

    expect(picked.result?.focusDay, DateTime.utc(2026, 12, 25));
    // The page the sheet was opened from is still there.
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second tap on a row action pops nothing more', (tester) async {
    var ran = 0;
    final picked = await openSheet(
      tester,
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
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
    );

    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();

    expect(picked.result?.edit, isNotNull);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Still an intent, resolved once by the caller.
    expect(ran, 0);
  });
}

/// Mutable holder for the sheet's result — it is awaited inside a button
/// callback, so the value arrives after the tap that dismissed the sheet.
class _Picked {
  AgendaDayListResult? result;
  bool returned = false;
}

/// Stands in for the agenda's own widened re-scan, recording every range the
/// sheet asks for so the tests can pin *when* resolution happens as well as
/// what it returns.
class _ResolverSpy {
  final List<(DateTime, DateTime)> calls = [];
  final List<AgendaDayListEntry> pool;

  _ResolverSpy(this.pool);

  List<AgendaDayListEntry> resolve(DateTime start, DateTime end) {
    calls.add((start, end));
    return [
      for (final entry in pool)
        if (!entry.day.isBefore(start) && !entry.day.isAfter(end)) entry,
    ];
  }
}
