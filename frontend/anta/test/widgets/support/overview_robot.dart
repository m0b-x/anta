import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverMultiBoxAdaptor;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/pages/calendar_overview_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/agenda_month_store.dart';
import 'package:anta/widgets/agenda_day_list_rows.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/agenda_year_scroll.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/list_scrubber.dart';
import 'package:anta/widgets/month_dot_matrix.dart';
import 'package:anta/widgets/year_month_tile.dart';

import 'overview_options_robot.dart';
import 'overview_view_robot.dart';

/// Drives the calendar overview — [CalendarOverviewPage] — for the suites:
/// they say what the user does and read what the page shows.
///
/// The seam the List mode rework (`docs/calendar-overview-list-roadmap.md`)
/// lands under: slice 0 pinned the page as it was through this file, and a
/// later slice that changes the chrome rewrites the robot and leaves the
/// bodies alone, but for the behaviour the record changes on purpose.
///
/// Slice 3a's chrome: the mode was the view menu's second group, picked by
/// id, until slice 8a's chips below. Since slice 10a the Search row comes
/// from a button at the end of the chip row, the period is set by the nav
/// title's Period menu and the Dates sheet's range mode, and the categories,
/// the order, the rows and Missed live in the options sheet behind the bar's
/// tune button. Every mode draws a period nav, which [navTitle] and
/// [navCount] read, over the per-category [totals] (slice 9a).
///
/// Slice 3b's body: the list and month mode draw the day list's rows —
/// section labels, read rows, entry rows — so the list is read off those
/// rows' own fields ([listTexts]), never off the capitals a section label
/// paints; the list's rows sit on exact extents under a pinned label
/// ([pinnedLabel]).
///
/// Slice 5's scrubber: a lane along the list's right edge ([hasScrubber],
/// [scrub]) and its bubble ([scrubberBubble]).
///
/// Slice 8a's chips: the mode left the view menu for a chip row on the page
/// ([modeChips], [currentMode], [selectMode]), and the period is live in
/// every mode.
///
/// Slice 8b's detail sheet: a row tap opens the occurrence's detail sheet
/// over the list instead of a calendar ([detailSheet], [tapInDetail]).
///
/// Slice 9c's saved views: a bookmarks button in the bar ([viewsSelected])
/// opens their sheet, driven through [views].
///
/// Slice 10a's chrome (D19–D25): the filter group left the page. The nav's
/// title is the Period menu in every mode ([openPeriodMenu], [periodValue],
/// [periodChoice]); the Search row is summoned by the button ending the chip
/// row ([openSearch], [closeSearch]); the categories are the options sheet's
/// first row ([pickCategories], [categoriesValue]); the jump picker is gone.
///
/// Slice 11's year scroll (D26–D30): Year mode is one continuous scroll of
/// year sections ([yearHeader], [yearTiles], [builtYears], [jumpYearsTo],
/// [dragYears], [holdYears]); the chevrons scroll it and the nav's title
/// follows the year at its top.
class OverviewRobot {
  const OverviewRobot(this.tester);

  final WidgetTester tester;

  Finder get _page => find.byType(CalendarOverviewPage);

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_page))!;

  AgendaPeriodNav get _nav => tester.widget(find.byType(AgendaPeriodNav));

  /// The list mode's body: the rows' scroll view, or the empty state's.
  Finder get _list =>
      find.descendant(of: _page, matching: _carrier(SemanticsIds.overviewList));

  Finder get _listScrollable =>
      find.descendant(of: _list, matching: find.byType(Scrollable)).first;

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  /// The widget that puts [id] on a control, found with no semantics handle
  /// in play.
  Finder _carrier(String id) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.identifier == id,
  );

  Future<void> _tap(Finder target, {bool settle = true}) async {
    await tester.tap(target);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  // --- Opening ---------------------------------------------------------------

  static Widget _app({
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    required Widget home,
    GlobalKey<NavigatorState>? navigatorKey,
    List<NavigatorObserver> observers = const [],
    Locale locale = const Locale('en'),
    double? textScale,
    MarkdownBarBloc? markdownBar,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CalendarBloc>.value(value: bloc),
        BlocProvider<ImportExportBloc>.value(value: importExport),
        if (markdownBar != null)
          BlocProvider<MarkdownBarBloc>.value(value: markdownBar),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        navigatorObservers: [AppNavigator.routeObserver, ...observers],
        builder: textScale == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: home,
      ),
    );
  }

  void _setSurface(Size? surface) {
    if (surface == null) return;
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
  }

  static Future<void> _persist({
    AgendaDayListMode? mode,
    OverviewPeriod? period,
    OverviewListOptions? options,
  }) async {
    final settings = await SettingsService.getInstance();
    if (mode != null) await settings.setCalendarOverviewMode(mode);
    if (period != null) await settings.setCalendarOverviewPeriod(period);
    if (options != null) await settings.setCalendarOverviewListOptions(options);
  }

  /// The settings read is a real async gap; pump a bounded number of short
  /// frames until the body replaces its spinner, so the page has resolved
  /// and painted but the 250 ms prewarm has not fired yet.
  Future<void> _pumpUntilLoaded() async {
    for (var i = 0; i < 20; i++) {
      final spinner = find.descendant(
        of: _page,
        matching: find.byType(CircularProgressIndicator),
      );
      if (spinner.evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  /// Pumps the page with its test seam. [mode], [period] and [options] are
  /// persisted first, as a previous visit would have left them; [textScale]
  /// and [surface] stand in for a phone's accessibility setting and size;
  /// [onStore] is handed every month store the page resolves into;
  /// [markdownBar] is for the cases that go on from a row's detail sheet into
  /// the event editor, which reads that bloc as it mounts.
  Future<void> open({
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    AgendaDayListMode? mode,
    OverviewPeriod? period,
    OverviewListOptions? options,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
    ValueChanged<AgendaMonthStore>? onStore,
    MarkdownBarBloc? markdownBar,
  }) async {
    _setSurface(surface);
    await _persist(mode: mode, period: period, options: options);
    await tester.pumpWidget(
      _app(
        bloc: bloc,
        importExport: importExport,
        locale: locale,
        textScale: textScale,
        markdownBar: markdownBar,
        home: CalendarOverviewPage.forTesting(onStore: onStore),
      ),
    );
    await _pumpUntilLoaded();
  }

  /// Pumps the app [open] built anew under [locale], as a language picked on
  /// the settings page does: the page keeps its state, and any route pushed
  /// over it stays. Draws the one frame the change takes.
  Future<void> switchLocale(
    Locale locale, {
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    ValueChanged<AgendaMonthStore>? onStore,
  }) => tester.pumpWidget(
    _app(
      bloc: bloc,
      importExport: importExport,
      locale: locale,
      home: CalendarOverviewPage.forTesting(onStore: onStore),
    ),
  );

  /// Draws what a bloc emit just changed without letting the clock move: the
  /// listener runs and its frame is laid out, but no timer fires — so the
  /// list's later runs, one per event-loop turn, are still to come.
  Future<void> pumpWithoutTurns() async {
    await tester.pump();
    await tester.pump();
  }

  /// Lets every pending event-loop turn run — the list's runs, each
  /// scheduling the next — and draws enough frames for the year runs, one
  /// at the end of each frame (slice 12), then the frame they asked for.
  Future<void> finishResolving() async {
    for (var frame = 0; frame < _yearRunFrames; frame++) {
      await tester.pump(Duration.zero);
    }
    await tester.pump();
  }

  /// More frames than the year runs ever queue: the viewport's years and
  /// the top year's two neighbours.
  static const _yearRunFrames = 8;

  /// Draws one frame after the turns already due: at most one year run lands
  /// at its end.
  Future<void> pumpYearRun() => tester.pump(Duration.zero);

  /// Opens the real page — no test seam — over a calendar route stamped the
  /// way the view menu leaves one beneath it: a stand-in, or [calendar], the
  /// real page. [observers] join the navigator's, as launch restore's
  /// history observer does in the app.
  Future<void> openAboveCalendar({
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    AgendaDayListMode? mode,
    List<NavigatorObserver> observers = const [],
    Widget calendar = const Scaffold(body: Text(calendarBeneathLabel)),
  }) => _openAsRoute(
    bloc: bloc,
    importExport: importExport,
    mode: mode,
    observers: observers,
    calendar: calendar,
  );

  /// Opens the real page as the drawer does: stamped, over the root, with no
  /// calendar beneath it.
  Future<void> openFromDrawer({
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    AgendaDayListMode? mode,
    List<NavigatorObserver> observers = const [],
  }) => _openAsRoute(
    bloc: bloc,
    importExport: importExport,
    mode: mode,
    observers: observers,
  );

  Future<void> _openAsRoute({
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    AgendaDayListMode? mode,
    List<NavigatorObserver> observers = const [],
    Widget? calendar,
  }) async {
    await _persist(mode: mode);
    final navigatorKey = AppNavigator.navigatorKey;
    await tester.pumpWidget(
      _app(
        bloc: bloc,
        importExport: importExport,
        navigatorKey: navigatorKey,
        observers: observers,
        home: const Scaffold(body: Text('root')),
      ),
    );
    if (calendar != null) {
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => calendar,
            settings: const RouteSettings(
              name: 'calendar',
              arguments: NavDestination(NavDestinationKind.calendar),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const CalendarOverviewPage(),
          settings: const RouteSettings(
            name: 'calendarOverview',
            arguments: NavDestination(NavDestinationKind.calendarOverview),
          ),
        ),
      ),
    );
    await _pumpUntilLoaded();
    await tester.pumpAndSettle();
  }

  /// What the stand-in calendar route under [openAboveCalendar] shows.
  static const String calendarBeneathLabel = 'calendar beneath';

  /// Whether the page is on screen.
  bool get isOpen => _page.evaluate().isNotEmpty;

  /// Whether the page is still mounted, on screen or covered by a route.
  bool get isAlive => find
      .byType(CalendarOverviewPage, skipOffstage: false)
      .evaluate()
      .isNotEmpty;

  bool get calendarBeneathVisible =>
      find.text(calendarBeneathLabel).evaluate().isNotEmpty;

  /// Pushes a plain route over the page, as an alert's calendar or a linked
  /// note does, and pops it again with [uncover].
  Future<void> cover() async {
    unawaited(
      Navigator.of(tester.element(_page)).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covering')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pops the route [cover] pushed. [settle] false returns right after the
  /// pop, before the transition has run a frame.
  Future<void> uncover({bool settle = true}) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// The system back gesture.
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  // --- The mode --------------------------------------------------------------

  static String _modeId(AgendaDayListMode mode) => switch (mode) {
    AgendaDayListMode.year => SemanticsIds.overviewViewYear,
    AgendaDayListMode.month => SemanticsIds.overviewViewMonth,
    AgendaDayListMode.list => SemanticsIds.overviewViewList,
  };

  Iterable<FormChip> get _modeChips => tester.widgetList<FormChip>(
    find.descendant(of: _page, matching: find.byType(FormChip)),
  );

  /// The selected chip's mode.
  AgendaDayListMode get currentMode =>
      _modeOf(_modeChips.singleWhere((chip) => chip.selected).identifier);

  /// The modes the chip row offers, in its order.
  List<AgendaDayListMode> get modeChips => [
    for (final chip in _modeChips) _modeOf(chip.identifier),
  ];

  /// The chip row's height as the keyboard has folded it: the box that clips
  /// it, which holds its gap under the bar and its chips.
  double get modeChipRowExtent => tester
      .getSize(
        find
            .ancestor(
              of: find.descendant(
                of: _page,
                matching: find.byType(FormChipRow),
              ),
              matching: find.byType(Align),
            )
            .first,
      )
      .height;

  static AgendaDayListMode _modeOf(String? id) =>
      AgendaDayListMode.values.singleWhere((mode) => _modeId(mode) == id);

  /// Taps the mode's chip. [settle] false pumps one frame, leaving the
  /// 150 ms cross-fade (and the prewarm, and any running fling) to the
  /// caller.
  Future<void> selectMode(AgendaDayListMode mode, {bool settle = true}) =>
      _tap(_byId(_modeId(mode)), settle: settle);

  // --- The period nav (every mode since slice 9a) ----------------------------

  /// The period's title on the nav.
  String get navTitle => _nav.title;

  /// The period's count, the nav's subtitle.
  String? get navCount => _nav.subtitle;

  /// The Today slot's tooltip, which names the list nav's home period.
  String get navTodayTooltip => _nav.todayTooltip;

  /// The nav's title box: the row the chevrons and the title share.
  Size get navSize => tester.getSize(find.byType(AgendaPeriodNav));

  /// The nav's top edge: where the band under the filter group starts.
  double get navTop => tester.getTopLeft(find.byType(AgendaPeriodNav)).dy;

  Future<void> tapNavTitle({bool settle = true}) =>
      _tap(_byId(SemanticsIds.overviewNavTitle), settle: settle);

  bool get canGoPrevious => _nav.onPrevious != null;

  bool get canGoNext => _nav.onNext != null;

  bool get canJumpToToday => _nav.onToday != null;

  Finder _navButton(IconData icon) => find.descendant(
    of: find.byType(AgendaPeriodNav),
    matching: find.widgetWithIcon(IconButton, icon),
  );

  Future<void> previous({bool settle = true}) =>
      _tap(_navButton(Icons.chevron_left_rounded), settle: settle);

  Future<void> next({bool settle = true}) =>
      _tap(_navButton(Icons.chevron_right_rounded), settle: settle);

  /// The fixed slot beside the title: back to this year.
  Future<void> today({bool settle = true}) =>
      _tap(_navButton(Icons.today_rounded), settle: settle);

  /// Pages month mode's nav to [month] with its chevrons: the jump picker
  /// left the overview (D25).
  Future<void> pageMonthTo(DateTime month) async {
    final target = AgendaMonthStore.monthOrder(month);
    while (true) {
      final shown = AgendaMonthStore.monthOrder(_nav.month!);
      if (shown == target) return;
      shown < target ? await next() : await previous();
    }
  }

  // --- Year mode's scroll (slice 11, D26–D30) --------------------------------

  Finder get _yearScroll =>
      find.descendant(of: _page, matching: find.byType(AgendaYearScroll));

  Finder get _yearScrollable =>
      find.descendant(of: _yearScroll, matching: find.byType(Scrollable)).first;

  ScrollPosition get _yearPosition =>
      tester.state<ScrollableState>(_yearScrollable).position;

  /// The span the year scroll lays out.
  ({int first, int last}) get yearSpan {
    final scroll = tester.widget<AgendaYearScroll>(_yearScroll);
    return (first: scroll.firstYear, last: scroll.lastYear);
  }

  /// [year]'s section header — the node that names it and its count.
  Finder yearHeader(int year) =>
      _carrier(SemanticsIds.overviewYearHeader(year));

  /// The years whose sections are built, oldest first.
  List<int> get builtYears => [
    for (final widget in tester.widgetList<Semantics>(
      find.descendant(of: _yearScroll, matching: find.byType(Semantics)),
    ))
      if (widget.properties.identifier case final id?
          when id.startsWith('overview-year-'))
        int.parse(id.substring('overview-year-'.length)),
  ];

  /// [year]'s twelve tiles while its section is built — a tile's label
  /// names its year.
  Finder yearTiles(int year) => find.descendant(
    of: _yearScroll,
    matching: find.byWidgetPredicate(
      (w) => w is YearMonthTile && w.label.endsWith('$year'),
    ),
  );

  /// [year]'s tiles' dot matrices, January first.
  List<MonthDotMatrix> yearMatrices(int year) => [
    for (final tile in tester.widgetList<YearMonthTile>(yearTiles(year)))
      tile.matrix as MonthDotMatrix,
  ];

  /// How far below the scroll's top edge [year]'s header starts; null while
  /// its section is not built.
  double? yearHeaderTop(int year) {
    final header = yearHeader(year);
    if (header.evaluate().isEmpty) return null;
    return tester.getTopLeft(header).dy - tester.getTopLeft(_yearScroll).dy;
  }

  double get yearsOffset => _yearPosition.pixels;

  /// The year scroll's position, for a benchmark that drives it frame by
  /// frame.
  ScrollPosition get yearsPosition => _yearPosition;

  /// The year scroll's viewport height.
  double get yearsViewportExtent => _yearPosition.viewportDimension;

  /// The years whose sections show any part in the viewport at [offset]
  /// (the scroll's own offset by default), oldest first.
  List<int> visibleYearsAt([double? offset]) {
    final extent = yearSectionExtent;
    final top = offset ?? yearsOffset;
    final span = yearSpan;
    final first = span.first + (top / extent).floor();
    final last =
        span.first + ((top + yearsViewportExtent - 0.5) / extent).floor();
    return [
      for (var year = first; year <= last; year++)
        if (year >= span.first && year <= span.last) year,
    ];
  }

  /// A section's height: the distance between two headers.
  double get yearSectionExtent {
    final years = builtYears;
    if (years.length > 1) {
      return tester.getTopLeft(yearHeader(years[1])).dy -
          tester.getTopLeft(yearHeader(years[0])).dy;
    }
    return tester.getSize(_yearScroll).height;
  }

  /// A section header's height.
  double get yearHeaderHeight =>
      tester.getSize(yearHeader(builtYears.first)).height;

  /// Jumps the year scroll to [offset]. [settle] false draws one frame
  /// without moving the clock, so a year run scheduled meanwhile stays
  /// pending.
  Future<void> jumpYearsTo(double offset, {bool settle = true}) async {
    _yearPosition.jumpTo(offset);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// Drags the year scroll by [sections] sections with a finger — positive
  /// toward later years — and lets it settle.
  Future<void> dragYears(double sections) async {
    await tester.drag(
      _yearScrollable,
      Offset(0, -sections * yearSectionExtent),
    );
    await tester.pumpAndSettle();
  }

  /// A finger on the year scroll, already past the touch slop, for a case
  /// that moves it pixel by pixel; [TestGesture.up] lifts it.
  Future<TestGesture> holdYears() async {
    final gesture = await tester.startGesture(
      tester.getCenter(_yearScrollable),
    );
    await gesture.moveBy(const Offset(0, -(kDragSlopDefault + 1)));
    await tester.pump();
    return gesture;
  }

  // --- The Period menu: the nav's title (slice 10a, D19) ---------------------

  /// What the nav's title reads: a year, a month, a preset's name, or a span.
  String get periodValue => _nav.title;

  /// The Period menu's checked item: opens the menu from the title, reads
  /// the item wearing the check, and dismisses the menu.
  Future<OverviewPeriodChoice> periodChoice() async {
    await openPeriodMenu();
    final checked = tester
        .widgetList<FormMenuItemRow>(find.byType(FormMenuItemRow))
        .where((row) => row.checked)
        .single;
    final choice = OverviewPeriodChoice.values.singleWhere(
      (choice) => _periodItemId(choice) == checked.identifier,
    );
    Navigator.of(tester.element(find.byType(FormMenuItemRow).first)).pop();
    await tester.pumpAndSettle();
    return choice;
  }

  /// False while the title opens nothing; since slice 10a it always opens
  /// the menu.
  bool get periodEnabled => _nav.onTitleTap != null;

  static String _periodItemId(OverviewPeriodChoice choice) => switch (choice) {
    OverviewPeriodChoice.thisYear => SemanticsIds.overviewPeriodThisYear,
    OverviewPeriodChoice.last12Months =>
      SemanticsIds.overviewPeriodLast12Months,
    OverviewPeriodChoice.last90Days => SemanticsIds.overviewPeriodLast90Days,
    OverviewPeriodChoice.allTime => SemanticsIds.overviewPeriodAllTime,
    OverviewPeriodChoice.custom => SemanticsIds.overviewPeriodCustom,
  };

  /// Picks [choice] from the title's Period menu. Custom range… leaves the
  /// Dates sheet up.
  Future<void> pickPeriod(OverviewPeriodChoice choice) async {
    await openPeriodMenu();
    await pickOpenPeriod(choice);
  }

  /// Opens the Period menu from the nav's title and leaves it up.
  Future<void> openPeriodMenu() => tapNavTitle();

  /// Picks [choice] in the menu [openPeriodMenu] left up. [settle] false
  /// pumps one frame without moving the clock, so nothing the pick
  /// scheduled has run yet.
  Future<void> pickOpenPeriod(
    OverviewPeriodChoice choice, {
    bool settle = true,
  }) => _tap(_byId(_periodItemId(choice)), settle: settle);

  bool get menuOpen =>
      find.byWidgetPredicate((w) => w is PopupMenuItem).evaluate().isNotEmpty;

  // --- The custom span: the Dates sheet's range mode -------------------------

  Finder get _rangeSheet => find.byType(CalendarDatePickerSheet);

  bool get rangePickerOpen => _rangeSheet.evaluate().isNotEmpty;

  Finder _inRange(Finder matching) =>
      find.descendant(of: _rangeSheet, matching: matching);

  Future<void> _showRangeView(String label) => _tap(
    _inRange(
      find.descendant(
        of: find.byType(SegmentedButton<CalendarDatePickerView>),
        matching: find.text(label),
      ),
    ),
  );

  Finder _rangeTile(DateTime month) => _inRange(
    find.widgetWithText(
      YearMonthTile,
      DateFormat.yMMM(_l10n.localeName).format(month),
    ),
  );

  /// Pages the range sheet's year view until [year]'s tiles show.
  Future<void> _pageRangeYearTo(int year) async {
    final january = _rangeTile(DateTime.utc(year, 1, 1));
    final back = year < DateTime.now().year;
    for (var i = 0; i < 20 && january.evaluate().isEmpty; i++) {
      await _tap(
        _inRange(
          find.byTooltip(
            back ? _l10n.datePickerPreviousYear : _l10n.datePickerNextYear,
          ),
        ),
      );
    }
  }

  Future<void> _applyRange() => _tap(_byId(SemanticsIds.datePickerSave));

  /// Custom range… for the whole of [month] on the sheet's year view: one
  /// tile, then Apply.
  Future<void> pickCustomMonth(DateTime month) async {
    await pickPeriod(OverviewPeriodChoice.custom);
    await _showRangeView(_l10n.dayListModeYear);
    await _pageRangeYearTo(month.year);
    await _tap(_rangeTile(month));
    await _applyRange();
  }

  /// Custom range… for the whole of [year] on the sheet's year view: two
  /// tiles — January makes the span its whole month, December extends it to
  /// the 31st — then Apply.
  Future<void> pickCustomYear(int year) async {
    await pickPeriod(OverviewPeriodChoice.custom);
    await _showRangeView(_l10n.dayListModeYear);
    await _pageRangeYearTo(year);
    await _tap(_rangeTile(DateTime.utc(year, 1, 1)));
    await _tap(_rangeTile(DateTime.utc(year, 12, 1)));
    await _applyRange();
  }

  /// ✕ on the open range sheet: nothing changes.
  Future<void> cancelRange() => _tap(_byId(SemanticsIds.datePickerCancel));

  // --- The options -----------------------------------------------------------

  Finder get _optionsButton => _byId(SemanticsIds.overviewOptionsOpen);

  /// The sheet's own handle, once [openOptions] has it up.
  OverviewOptionsRobot get options => OverviewOptionsRobot(tester);

  Future<void> openOptions() => _tap(_optionsButton);

  Future<void> setOrder(OverviewOrder order) async {
    await openOptions();
    await options.pickOrder(order);
    await options.close();
  }

  Future<void> setRows(OverviewRows rows) async {
    await openOptions();
    await options.pickRows(rows);
    await options.close();
  }

  Future<void> setMissedOnly(bool value) async {
    await openOptions();
    if (options.missedOnly != value) await options.toggleMissedOnly();
    await options.close();
  }

  Future<void> setMarkPresence(bool value) async {
    await openOptions();
    if (options.markPresence != value) await options.toggleMarkPresence();
    await options.close();
  }

  /// Whether the tune button reads selected — a restriction or Mark
  /// presence (D18).
  bool get optionsSelected => tester
      .widget<IconButton>(
        find.descendant(of: _optionsButton, matching: find.byType(IconButton)),
      )
      .isSelected!;

  Badge get _optionsBadge => tester.widget(
    find.ancestor(of: _optionsButton, matching: find.byType(Badge)).first,
  );

  /// The number on the tune button, or null while it wears none.
  String? get optionsBadge {
    final badge = _optionsBadge;
    if (!badge.isLabelVisible) return null;
    return (badge.label! as Text).data;
  }

  // --- The saved views (slice 9c) --------------------------------------------

  Finder get _viewsButton => _byId(SemanticsIds.overviewViewsOpen);

  IconButton get _viewsIconButton => tester.widget(
    find.descendant(of: _viewsButton, matching: find.byType(IconButton)),
  );

  bool get hasViewsButton => _viewsButton.evaluate().isNotEmpty;

  /// Whether the bookmarks button reads selected — the list shown is a
  /// saved view.
  bool get viewsSelected => _viewsIconButton.isSelected!;

  bool get viewsEnabled => _viewsIconButton.onPressed != null;

  /// The bar's buttons left to right by id, for the button's place.
  double barButtonLeft(String id) => tester.getTopLeft(_byId(id)).dx;

  /// The sheet's own handle, once [openViews] has it up.
  OverviewViewRobot get views => OverviewViewRobot(tester);

  Future<void> openViews() => _tap(_viewsButton);

  /// Opens the saved views and applies the view [viewId].
  Future<void> applyView(String viewId) async {
    await openViews();
    await views.apply(viewId);
  }

  // --- The search (summoned by the chip row's button since slice 10a) ------

  Finder get _searchButton => _byId(SemanticsIds.overviewSearchOpen);

  IconButton get _searchIconButton => tester.widget(
    find.descendant(of: _searchButton, matching: find.byType(IconButton)),
  );

  /// Whether the Search row is on the page.
  bool get searchOpen => find.byType(FormSearchRow).evaluate().isNotEmpty;

  /// Whether the search button reads selected — a query is set.
  bool get searchSelected => _searchIconButton.isSelected!;

  /// The chip row's search button, whatever the row's state.
  Future<void> tapSearchButton({bool settle = true}) =>
      _tap(_searchButton, settle: settle);

  /// Reveals the Search row through the chip row's button; it comes focused.
  Future<void> openSearch() async {
    if (searchOpen) return;
    await tapSearchButton();
  }

  /// Closes the Search row through the same button, which drops the query.
  Future<void> closeSearch() async {
    if (!searchOpen) return;
    await tapSearchButton();
  }

  /// What the search field holds, applied or not; empty while it is closed.
  String get searchText =>
      searchOpen ? tester.widget<TextField>(_searchField).controller!.text : '';

  Finder get _searchField => find.descendant(
    of: find.byType(FormSearchRow),
    matching: find.byType(TextField),
  );

  /// Types [text] into the search — revealing it first — and waits out the
  /// 200 ms debounce, so the query has been applied when this returns — and
  /// nothing past it. [wait] false returns inside the debounce.
  Future<void> typeQuery(String text, {bool wait = true}) async {
    await openSearch();
    await tester.enterText(_searchField, text);
    if (!wait) return;
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  Future<void> clearQuery() => _tap(find.byTooltip(_l10n.upcomingClearSearch));

  /// Puts the caret in the search — revealing it first — raising the
  /// keyboard.
  Future<void> focusSearch() async {
    await openSearch();
    await tester.tap(_searchField);
    await tester.pump();
  }

  bool get searchFocused =>
      searchOpen &&
      tester
          .widget<EditableText>(
            find.descendant(
              of: _searchField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus;

  // --- The categories (the options sheet's first row since slice 10a) -------

  /// What the options sheet's Categories row reads back: opens the sheet,
  /// reads the row, closes the sheet.
  Future<String> categoriesValue() async {
    await openOptions();
    final value = options.categoriesValue;
    await options.close();
    return value;
  }

  /// Narrows the allowlist to [ids] through the options sheet's Categories
  /// row and the multi picker: none first, then each id ticked, then Done,
  /// then the sheet closed.
  Future<void> pickCategories(Set<String> ids) async {
    await openOptions();
    await options.pickCategories(ids);
    await options.close();
  }

  // --- The list --------------------------------------------------------------

  Finder get _totalsSlot =>
      find.descendant(of: _page, matching: find.byType(FormCaptionSlot));

  /// The per-category totals under the nav, in every mode (D16).
  String get totals {
    final slot = tester.widget<FormCaptionSlot>(_totalsSlot);
    return ((slot.child as Semantics).child! as FormCaption).text;
  }

  /// The totals slot's height, which no text may change.
  double get totalsHeight => tester.getSize(_totalsSlot).height;

  /// Whether the totals caption is a semantics node of its own: the node
  /// nearest it spans the caption exactly. Needs semantics enabled.
  bool get totalsHasNode {
    final caption = find.descendant(
      of: find.byWidget(tester.widget<FormCaptionSlot>(_totalsSlot).child),
      matching: find.byType(FormCaption),
    );
    return tester.getSemantics(caption).rect.size == tester.getSize(caption);
  }

  /// Every text the list's rows carry, in row order — a section label's text
  /// and count, a row's label, value and caption — for the rows built so
  /// far, which is the ones in and just past the viewport. The empty state's
  /// caption counts as a row.
  List<String> get listTexts {
    final rows = find.descendant(
      of: _list,
      matching: find.byWidgetPredicate(
        (w) => w is FormSectionLabel || w is FormPickerRow || w is FormCaption,
      ),
    );
    return [
      for (final element in rows.evaluate())
        // A row's caption is read with its row.
        if (element.widget is! FormCaption || !_inPickerRow(element))
          ..._textsOf(element.widget),
    ];
  }

  static bool _inPickerRow(Element element) {
    var inside = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is FormPickerRow) inside = true;
      return !inside && ancestor.widget is! Scrollable;
    });
    return inside;
  }

  static List<String> _textsOf(Widget row) => switch (row) {
    FormSectionLabel(:final text, :final trailing) => [text, ?trailing],
    FormPickerRow(:final label, :final value, :final caption) => [
      label,
      ?value,
      ?caption,
    ],
    FormCaption(:final text) => [text],
    _ => const [],
  };

  /// How many of the list's built rows carry [text].
  int countOf(String text) => listTexts.where((t) => t == text).length;

  bool shows(String text) => countOf(text) > 0;

  /// The pinned label above the list — its text and its count — or null
  /// while the slot is empty.
  (String, String?)? get pinnedLabel {
    final labels = tester.widgetList<FormSectionLabel>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ValueListenableBuilder<AgendaDayListRow?>,
        ),
        matching: find.byType(FormSectionLabel),
      ),
    );
    for (final label in labels) {
      // The slot's invisible template, which holds its height.
      if (label.text.trim().isEmpty) continue;
      return (label.text, label.trailing);
    }
    return null;
  }

  /// The list's built rows, each the widget the page's row builder made for
  /// one slot — a section label in its box, a row in its shell, the tail's
  /// caption — with the height of that slot.
  List<(Widget, double)> get laidOutRows {
    final slots = find.descendant(
      of: _list,
      matching: find.byElementPredicate(
        (element) =>
            element is RenderObjectElement &&
            element.renderObject.parent is RenderSliverMultiBoxAdaptor,
      ),
    );
    return [
      for (final element in slots.evaluate())
        (_builtRow(element.widget), element.size!.height),
    ];
  }

  /// What the sliver's delegate wrapped around the builder's widget.
  static Widget _builtRow(Widget slot) {
    var row = slot;
    while (row is IndexedSemantics || row is RepaintBoundary) {
      row = (row as SingleChildRenderObjectWidget).child!;
    }
    return row;
  }

  /// The texts of the section labels any part of which shows in the list —
  /// not scrolled wholly past its top edge, nor below its bottom.
  List<String> get visibleSectionLabels {
    final view = tester.getRect(_listScrollable);
    return [
      for (final element
          in find
              .descendant(of: _list, matching: find.byType(FormSectionLabel))
              .evaluate())
        if (_rectOf(element) case final rect
            when rect.bottom > view.top + 0.5 && rect.top < view.bottom - 0.5)
          (element.widget as FormSectionLabel).text,
    ];
  }

  static Rect _rectOf(Element element) {
    final box = element.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// How far below the list's top edge the first built row carrying [text]
  /// starts; null when no built row carries it.
  double? rowTopInView(String text) {
    final top = tester.getTopLeft(_listScrollable).dy;
    final rows = find.descendant(
      of: _list,
      matching: find.byWidgetPredicate(
        (w) => w is FormSectionLabel || w is FormRowShell,
      ),
    );
    for (final element in rows.evaluate()) {
      final widget = element.widget;
      final texts = widget is FormSectionLabel
          ? _textsOf(widget)
          : [
              for (final row in tester.widgetList(
                find.descendant(
                  of: find.byWidget(widget),
                  matching: find.byType(FormPickerRow),
                ),
              ))
                ..._textsOf(row),
            ];
      if (!texts.contains(text)) continue;
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero).dy - top;
    }
    return null;
  }

  /// The texts of the first row whose top is at or below the list's top
  /// edge — the row the list shows first.
  List<String> get topRowTexts {
    final top = tester.getTopLeft(_listScrollable).dy;
    final rows = find.descendant(
      of: _list,
      matching: find.byWidgetPredicate(
        (w) => w is FormSectionLabel || w is FormRowShell,
      ),
    );
    for (final element in rows.evaluate()) {
      final box = element.renderObject! as RenderBox;
      if (box.localToGlobal(Offset.zero).dy < top - 0.5) continue;
      final widget = element.widget;
      if (widget is FormSectionLabel) return _textsOf(widget);
      final picker = find.descendant(
        of: find.byWidget(widget),
        matching: find.byType(FormPickerRow),
      );
      return _textsOf(tester.widget(picker.first));
    }
    return const [];
  }

  /// The empty state's line.
  String get emptyPeriodText => _l10n.overviewEmptyPeriod;

  ScrollPosition get _listPosition =>
      tester.state<ScrollableState>(_listScrollable).position;

  double get listOffset => _listPosition.pixels;

  double get listMaxOffset => _listPosition.maxScrollExtent;

  double get listViewportExtent => _listPosition.viewportDimension;

  /// Jumps the list to [offset]. [settle] false draws one frame without
  /// moving the clock, so the list's pending runs stay pending.
  Future<void> scrollListTo(double offset, {bool settle = true}) async {
    _listPosition.jumpTo(offset);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// Drags the list up by [dy] with a finger, as a user would.
  Future<void> dragList(double dy) async {
    await tester.drag(_listScrollable, Offset(0, -dy));
    await tester.pumpAndSettle();
  }

  /// Flings the list upward and leaves the frames — and the ballistic run —
  /// to the caller.
  Future<void> flingList({double dy = 600, double speed = 6000}) =>
      tester.fling(_listScrollable, Offset(0, -dy), speed);

  /// Drags the list until an entry titled [title] is built, brings the first
  /// one into view and taps it. Not `scrollUntilVisible`: a recurring title
  /// is on many rows, and that helper wants exactly one. [settle] false pumps
  /// one frame after the tap.
  Future<void> tapRow(String title, {bool settle = true}) async {
    final row = find.descendant(of: _list, matching: find.text(title));
    for (var i = 0; i < 200 && row.evaluate().isEmpty; i++) {
      await tester.drag(_listScrollable, const Offset(0, -300));
      await tester.pump();
    }
    await tester.ensureVisible(row.first);
    await tester.pumpAndSettle();
    await _tap(row.first, settle: settle);
  }

  /// A long press on the first built entry titled [title] — the way to its
  /// detail sheet while Mark presence has the tap (D18).
  Future<void> longPressRow(String title) async {
    final row = find.descendant(of: _list, matching: find.text(title));
    await tester.ensureVisible(row.first);
    await tester.pumpAndSettle();
    await tester.longPress(row.first);
    await tester.pumpAndSettle();
  }

  /// The hint on the entry row carrying [id], as a screen reader hears it.
  String rowHint(String id) =>
      tester.getSemantics(_byId(id)).getSemanticsData().hint;

  // --- The detail sheet (slice 8b) -------------------------------------------

  /// The detail sheet a row tap opened, or null while none is up.
  EventDetailSheet? get detailSheet {
    final sheet = find.byType(EventDetailSheet);
    if (sheet.evaluate().isEmpty) return null;
    return tester.widget<EventDetailSheet>(sheet);
  }

  /// Taps the control carrying [id] in the open detail sheet — its ✕, Edit,
  /// Missed — and lets the route run. [settle] false pumps one frame.
  Future<void> tapInDetail(String id, {bool settle = true}) =>
      _tap(_byId(id), settle: settle);

  // --- The scrubber (slice 5) ------------------------------------------------

  Finder get _scrubber => find.descendant(
    of: _page,
    matching: find.bySemanticsIdentifier(SemanticsIds.overviewScrubber),
  );

  /// Whether the list wears the scrubber's lane.
  bool get hasScrubber => find
      .descendant(of: _page, matching: find.byType(ListScrubber))
      .evaluate()
      .isNotEmpty;

  /// Presses in the lane at [from] of its height and drags to [to], leaving
  /// the finger down so the bubble can be read; [TestGesture.up] lifts it.
  Future<TestGesture> scrub({double from = 0.1, required double to}) async {
    final box = tester.getRect(
      find.descendant(of: _page, matching: find.byType(ListScrubber)),
    );
    final x = box.right - FormMetrics.scrubberLaneWidth / 2;
    Offset at(double share) => Offset(x, box.top + box.height * share);
    final gesture = await tester.startGesture(at(from));
    // Past the touch slop first, so the drag is the lane's before it aims.
    await gesture.moveTo(at(from) + const Offset(0, 40));
    await gesture.moveTo(at(to));
    await tester.pump();
    return gesture;
  }

  /// The scrubber's bubble text while one shows, else null.
  String? get scrubberBubble {
    final text = find.descendant(
      of: find.descendant(
        of: find.byType(ListScrubber),
        matching: find.byType(CustomSingleChildLayout),
      ),
      matching: find.byType(Text),
    );
    if (text.evaluate().isEmpty) return null;
    return tester.widget<Text>(text).data;
  }

  /// The lane's one semantics node, for the suites that hold a handle.
  Finder get scrubberNode => _scrubber;

  /// How far the [index]th entry titled [title] is faded, or null at full
  /// strength.
  double? entryOpacity(String title, {int index = 0}) {
    final faded = find.ancestor(
      of: find.descendant(of: _list, matching: find.text(title)).at(index),
      matching: find.byType(Opacity),
    );
    if (faded.evaluate().isEmpty) return null;
    return tester.widget<Opacity>(faded.first).opacity;
  }
}
