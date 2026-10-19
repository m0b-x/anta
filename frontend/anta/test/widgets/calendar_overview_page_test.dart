import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter/services.dart' show MethodChannel, SystemChannels;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/overview_list_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_overview_page.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/alert_keep_notice.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/agenda_month_store.dart';
import 'package:anta/utils/date_span_label.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/agenda_year_scroll.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/month_year_picker_sheet.dart';
import 'package:anta/widgets/year_month_tile.dart';

import '../database/support/db_test_support.dart';
import 'support/layout_errors.dart';
import 'support/overview_robot.dart';
import 'support/semantics_geometry.dart';

/// Every event the blocs are handed while it is [Bloc.observer]: what the
/// overview's detail sheet dispatches into a bloc whose service never comes.
class _RecordingObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}

/// The overview owns no data: it reads the app-wide bloc's loaded state,
/// resolves whole calendar years through the same scan the agenda uses, and
/// opens a row's detail sheet over the list, writing through that bloc. So
/// the suite hands it a loaded bloc, watches what it draws, and watches what
/// a tap opens and dispatches.
void main() {
  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;
  late _RecordingObserver observer;
  late BlocObserver previousObserver;

  // A presence write reaches `DatabaseManager`, whose singleton a missing
  // plugin would leave half-built for the editor cases below.
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  final today = EventAgenda.dateOnly(DateTime.now());
  final year = today.year;
  final january = DateTime.utc(year, 1, 1);

  String tileLabel(DateTime month) => DateFormat.yMMM('en').format(month);

  final gymDaily = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: january,
    rule: const DailyRecurrence(),
  );

  final mobilityOnce = CalendarEvent(
    id: 'e2',
    title: 'Stretch class',
    categoryId: 'mobility',
    startDate: DateTime.utc(year, 3, 9),
    rule: const OneTimeRecurrence(),
  );

  /// Two years back, so the pager has a page before this one and stops there.
  final oldCheckup = CalendarEvent(
    id: 'e3',
    title: 'Old checkup',
    categoryId: 'other',
    startDate: DateTime.utc(year - 2, 6, 1),
    rule: const OneTimeRecurrence(),
  );

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    // The bar's saved views button resolves the service as the page opens;
    // bound here so it never reaches for the file database.
    OverviewViewService.reset();
    await OverviewViewService.forTesting(db);
    final notes = NoteRepository(database: db);
    importExport = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: db),
        ),
        noteRepository: notes,
      ),
    );
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
    // Before the bloc: a bloc takes the observer it is constructed under.
    previousObserver = Bloc.observer;
    observer = _RecordingObserver();
    Bloc.observer = observer;
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: [gymDaily, mobilityOnce, oldCheckup],
        focusedDay: today,
        selectedDay: today,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await importExport.close();
    Bloc.observer = previousObserver;
    AlertKeepNotice.instance.clearForTesting();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    OverviewViewService.reset();
    await db.close();
  });

  /// The settings read is a real async gap; pump a bounded number of frames
  /// rather than settling, so a stalled read fails instead of hanging.
  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      if (find.byType(YearMonthTile).evaluate().isNotEmpty ||
          find.byType(ListTile).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  /// The blocs sit above the app, where the real ones live, so a route
  /// pushed over the page still finds them.
  Widget app({GlobalKey<NavigatorState>? navigatorKey, required Widget home}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CalendarBloc>.value(value: bloc),
        BlocProvider<ImportExportBloc>.value(value: importExport),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        navigatorObservers: [AppNavigator.routeObserver],
        home: home,
      ),
    );
  }

  /// Records every bloc event from here to the end of the test.
  _RecordingObserver recordBlocEvents() => observer..events.clear();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(app(home: const CalendarOverviewPage.forTesting()));
    await pumpUntilLoaded(tester);
  }

  IconButton navButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  /// [text] on the year or month nav, never a tile's or a row's.
  Finder navText(String text) => find.descendant(
    of: find.byType(AgendaPeriodNav),
    matching: find.text(text),
  );

  testWidgets('opens on this year with a tile per month and its counts', (
    tester,
  ) async {
    await pumpPage(tester);

    // Slice 11: one section of the year scroll, its header at the top.
    final robot = OverviewRobot(tester);
    expect(robot.yearTiles(year), findsNWidgets(12));
    expect(robot.yearHeaderTop(year), 0);
    expect(navText('$year'), findsOneWidget);

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('${tileLabel(january)}, 31 entries'),
      findsOneWidget,
    );
    handle.dispose();
    expect(navButton(tester, Icons.today_rounded).onPressed, isNull);
  });

  testWidgets('the year chevrons scroll to the year, the title follows, and '
      'the this-year button returns', (tester) async {
    await pumpPage(tester);
    final robot = OverviewRobot(tester);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    // The scroll animates there: under way the title still names this year.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(robot.yearHeaderTop(year)!, greaterThan(0));
    expect(robot.yearHeaderTop(year)!, lessThan(robot.yearSectionExtent));
    await tester.pumpAndSettle();
    expect(navText('${year - 1}'), findsOneWidget);
    expect(robot.yearHeaderTop(year - 1), 0);
    expect(navButton(tester, Icons.today_rounded).onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.today_rounded));
    await tester.pumpAndSettle();
    expect(navText('$year'), findsOneWidget);
    expect(robot.yearHeaderTop(year), 0);
  });

  testWidgets('the years span the events: an open-ended series ends next '
      'year, a bounded end or a pinned date past it extends it (D28)', (
    tester,
  ) async {
    await pumpPage(tester);
    final robot = OverviewRobot(tester);

    // The oldest event is two years back; the daily one is open-ended, so
    // the span ends next year rather than at the calendar's ceiling.
    expect(robot.yearSpan, (first: year - 2, last: year + 1));
    await robot.next();
    expect(navText('${year + 1}'), findsOneWidget);
    expect(navButton(tester, Icons.chevron_right_rounded).onPressed, isNull);
    await robot.today();
    await robot.previous();
    await robot.previous();
    expect(navText('${year - 2}'), findsOneWidget);
    expect(navButton(tester, Icons.chevron_left_rounded).onPressed, isNull);

    // A fling past the first year goes nowhere.
    await tester.fling(
      find.byType(AgendaYearScroll),
      const Offset(0, 600),
      3000,
    );
    await tester.pumpAndSettle();
    expect(navText('${year - 2}'), findsOneWidget);
    expect(robot.yearsOffset, 0);

    final bounded = gymDaily.copyWith(
      id: 'b2',
      endDate: DateTime.utc(year + 3, 6, 30),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: [gymDaily, bounded],
        focusedDay: today,
        selectedDay: today,
      ),
    );
    await tester.pumpAndSettle();
    expect(robot.yearSpan, (first: year, last: year + 3));

    final pinned = CalendarEvent(
      id: 'pin',
      title: 'Pinned',
      categoryId: 'other',
      startDate: january,
      rule: SpecificDatesRecurrence(dates: {DateTime.utc(year + 5, 2, 2)}),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: [gymDaily, pinned],
        focusedDay: today,
        selectedDay: today,
      ),
    );
    await tester.pumpAndSettle();
    expect(robot.yearSpan, (first: year, last: year + 5));
  });

  testWidgets('a drag into the neighbour flips the title at the half-header '
      'threshold', (tester) async {
    await pumpPage(tester);
    final robot = OverviewRobot(tester);
    // Where the next year's header is half a header below the top.
    final threshold =
        robot.yearsOffset +
        robot.yearSectionExtent -
        robot.yearHeaderHeight / 2;
    final gesture = await robot.holdYears();

    await gesture.moveBy(Offset(0, -(threshold - robot.yearsOffset - 1)));
    await tester.pump();
    expect(navText('$year'), findsOneWidget);

    await gesture.moveBy(const Offset(0, -2));
    await tester.pump();
    expect(navText('${year + 1}'), findsOneWidget);

    await gesture.moveBy(const Offset(0, 2));
    await tester.pump();
    expect(navText('$year'), findsOneWidget, reason: 'and back');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the year title opens the Period menu, never the jump picker '
      '(D19, D25)', (tester) async {
    await pumpPage(tester);

    await tester.tap(navText('$year'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthYearPickerSheet), findsNothing);
    expect(
      [
        for (final row in tester.widgetList<FormMenuItemRow>(
          find.byType(FormMenuItemRow),
        ))
          (row.identifier, row.checked),
      ],
      [
        (SemanticsIds.overviewPeriodThisYear, true),
        (SemanticsIds.overviewPeriodLast12Months, false),
        (SemanticsIds.overviewPeriodLast90Days, false),
        (SemanticsIds.overviewPeriodAllTime, false),
        (SemanticsIds.overviewPeriodCustom, false),
      ],
    );
  });

  testWidgets('one category bounds the years to its own events', (
    tester,
  ) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewCategories({'mobility'});

    await pumpPage(tester);

    // The class is this year and one-off: nothing before, nothing after.
    expect(navButton(tester, Icons.chevron_left_rounded).onPressed, isNull);
    expect(navButton(tester, Icons.chevron_right_rounded).onPressed, isNull);
  });

  testWidgets('a persisted category allowlist narrows what the tiles count', (
    tester,
  ) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewCategories({'mobility'});

    await pumpPage(tester);

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('${tileLabel(january)}, 0 entries'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('${tileLabel(DateTime.utc(year, 3, 1))}, 1 entry'),
      findsOneWidget,
    );
    handle.dispose();
    // One category selected: the tiles wear its colour.
    final matrix = OverviewRobot(tester).yearMatrices(year)[2];
    expect(matrix.markedColor, const Color(0xFFEC407A));
  });

  testWidgets('several categories paint each day in its top entry\'s colour', (
    tester,
  ) async {
    await pumpPage(tester);

    final march = OverviewRobot(tester).yearMatrices(year)[2];
    // Day 9 carries the gym event and the mobility class; the gym one leads
    // by title, so the square wears gym blue like every other day.
    expect(march.dayColors, isNotNull);
    expect(march.dayColors![8], const Color(0xFF1E88E5));
  });

  testWidgets('a tile opens its month, a row tap opens the occurrence', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text(tileLabel(DateTime.utc(year, 3, 1))));
    await tester.pumpAndSettle();
    expect(
      find.text(
        AgendaListView.monthLabel(
          'en',
          DateTime.utc(year, 3, 1),
          withYear: true,
        ),
      ),
      findsOneWidget,
    );

    // Tapping a marked day narrows the rows to it, so the class's row is
    // built without scrolling past thirty gym days.
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable.first);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stretch class'));
    await tester.pumpAndSettle();

    final sheet = tester.widget<EventDetailSheet>(
      find.byType(EventDetailSheet),
    );
    expect(sheet.event.id, 'e2');
    expect(sheet.day, DateTime.utc(year, 3, 9));
  });

  testWidgets('the nav ids sit on the year nav in Year mode and on the month '
      'nav in Month mode, never on both', (tester) async {
    List<AgendaPeriodNav> navsWearing(String id) => [
      for (final element
          in find
              .ancestor(
                of: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.identifier == id,
                ),
                matching: find.byType(AgendaPeriodNav),
              )
              .evaluate())
        element.widget as AgendaPeriodNav,
    ];
    const ids = [
      SemanticsIds.overviewNavTitle,
      SemanticsIds.overviewNavPrevious,
      SemanticsIds.overviewNavNext,
      SemanticsIds.overviewNavToday,
    ];
    final robot = OverviewRobot(tester);
    await robot.open(bloc: bloc, importExport: importExport);
    expect(robot.currentMode, AgendaDayListMode.year);
    for (final id in ids) {
      final navs = navsWearing(id);
      expect(navs, hasLength(1), reason: id);
      expect(navs.single.month, isNull, reason: '$id on the year nav');
    }

    await robot.selectMode(AgendaDayListMode.month);
    for (final id in ids) {
      final navs = navsWearing(id);
      expect(navs, hasLength(1), reason: id);
      expect(navs.single.month, isNotNull, reason: '$id on the month nav');
    }
  });

  testWidgets('list mode lists the year under month and day headers', (
    tester,
  ) async {
    await pumpPage(tester);
    await OverviewRobot(tester).selectMode(AgendaDayListMode.list);
    // Slice 4: a switch into List lands on today (D7); January is the top.
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.byType(YearMonthTile), findsNothing);
    // Slice 3b: a month is the language's section label, in its capitals.
    expect(find.text('JANUARY'), findsOneWidget);
    expect(find.text('Leg day'), findsWidgets);
  });

  testWidgets('a bloc emit with a new event list redraws the tiles', (
    tester,
  ) async {
    await pumpPage(tester);

    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: [mobilityOnce],
        focusedDay: today,
        selectedDay: today,
      ),
    );
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('${tileLabel(january)}, 0 entries'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('header', () {
    Finder id(String identifier) => find.bySemanticsIdentifier(identifier);

    Future<void> open(WidgetTester tester, String identifier) async {
      await tester.tap(id(identifier));
      await tester.pumpAndSettle();
    }

    testWidgets('the title is the view menu, Overview checked, no formats, '
        'no second group (D12)', (tester) async {
      await pumpPage(tester);
      expect(find.text('Overview'), findsOneWidget);

      await open(tester, SemanticsIds.calendarViewMenu);
      expect(id(SemanticsIds.calendarViewCalendar), findsOneWidget);
      expect(
        find.descendant(
          of: id(SemanticsIds.calendarOverviewOpen),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(id(SemanticsIds.calendarFormatMonth), findsNothing);
      // The two pages and nothing under them: the modes left the menu.
      expect(
        find.byWidgetPredicate((w) => w is PopupMenuItem),
        findsNWidgets(2),
      );
      expect(find.byType(PopupMenuDivider), findsNothing);
    });

    testWidgets('the bar is AppBarMetrics on the page ground: 48 dp, 22 px '
        'glyphs, no tint (D33)', (tester) async {
      await pumpPage(tester);
      final bar = find.byType(AppBar);
      final colorScheme = Theme.of(tester.element(bar)).colorScheme;
      final appBar = tester.widget<AppBar>(bar);
      expect(appBar.backgroundColor, colorScheme.pageGround);
      expect(appBar.surfaceTintColor, Colors.transparent);
      // The test draws no status bar: the bar is its toolbar.
      expect(tester.getSize(bar).height, AppBarMetrics.toolbarHeight);
      expect(appBar.iconTheme?.size, AppBarMetrics.glyphSize);
      for (final icon in const [
        Icons.tune_rounded,
        Icons.bookmarks_outlined,
        Icons.more_vert,
      ]) {
        expect(
          tester.getSize(find.descendant(of: bar, matching: find.byIcon(icon))),
          const Size.square(AppBarMetrics.glyphSize),
          reason: '$icon',
        );
      }
    });

    testWidgets('the chip row\'s search button is a 48 dp target with a '
        '20 px glyph, selected under a query (D33)', (tester) async {
      await pumpPage(tester);
      final robot = OverviewRobot(tester);
      final button = find.descendant(
        of: id(SemanticsIds.overviewSearchOpen),
        matching: find.byType(IconButton),
      );
      expect(
        tester.getSize(button),
        const Size.square(FormMetrics.trailingButtonSize),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: button,
            matching: find.byIcon(Icons.search_rounded),
          ),
        ),
        const Size.square(FormMetrics.trailingIconSize),
      );
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      await robot.typeQuery('leg');
      expect(tester.widget<IconButton>(button).isSelected, isTrue);
      expect(
        tester.getSize(button),
        const Size.square(FormMetrics.trailingButtonSize),
      );
    });

    testWidgets('the year tiles sit on the page\'s group role (D33)', (
      tester,
    ) async {
      await pumpPage(tester);
      final robot = OverviewRobot(tester);
      final tiles = robot.yearTiles(year);
      final colorScheme = Theme.of(tester.element(tiles.first)).colorScheme;
      for (final tile in tester.widgetList<YearMonthTile>(tiles)) {
        expect(tile.background, colorScheme.rowGroup);
      }
    });

    testWidgets('the mode chips are on the page in every mode, Year · Month · '
        'List, the current one selected (D12)', (tester) async {
      await pumpPage(tester);
      final robot = OverviewRobot(tester);
      // The page opens in year mode.
      expect(robot.modeChips, [
        AgendaDayListMode.year,
        AgendaDayListMode.month,
        AgendaDayListMode.list,
      ]);
      expect(robot.currentMode, AgendaDayListMode.year);

      for (final mode in [
        AgendaDayListMode.list,
        AgendaDayListMode.month,
        AgendaDayListMode.year,
      ]) {
        await robot.selectMode(mode);
        expect(robot.currentMode, mode);
        for (final chip in [
          SemanticsIds.overviewViewYear,
          SemanticsIds.overviewViewMonth,
          SemanticsIds.overviewViewList,
        ]) {
          expect(id(chip), findsOneWidget, reason: '$chip in $mode');
        }
      }
    });

    testWidgets('the ⋮ offers Alerts, Export and Calendar settings', (
      tester,
    ) async {
      await pumpPage(tester);

      await open(tester, SemanticsIds.calendarMore);
      expect(id(SemanticsIds.calendarAlertsOpen), findsOneWidget);
      expect(id(SemanticsIds.calendarSettingsOpen), findsOneWidget);
      expect(
        tester
            .getSemantics(id(SemanticsIds.calendarExport))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isTrue,
      );
    });

    testWidgets('Export is disabled while the calendar holds no events', (
      tester,
    ) async {
      await pumpPage(tester);
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        CalendarPageLoaded(
          allEvents: const [],
          focusedDay: today,
          selectedDay: today,
        ),
      );
      await tester.pumpAndSettle();

      await open(tester, SemanticsIds.calendarMore);
      expect(
        tester
            .getSemantics(id(SemanticsIds.calendarExport))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
    });

    testWidgets('Calendar returns to the calendar beneath instead of '
        'stacking another', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        app(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('root')),
        ),
      );
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('calendar beneath')),
            settings: const RouteSettings(
              name: 'calendar',
              arguments: NavDestination(NavDestinationKind.calendar),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const CalendarOverviewPage.forTesting(),
            settings: const RouteSettings(
              name: 'calendarOverview',
              arguments: NavDestination(NavDestinationKind.calendarOverview),
            ),
          ),
        ),
      );
      await pumpUntilLoaded(tester);
      await tester.pumpAndSettle();

      await open(tester, SemanticsIds.calendarViewMenu);
      await tester.tap(id(SemanticsIds.calendarViewCalendar));
      await tester.pumpAndSettle();

      expect(find.text('calendar beneath'), findsOneWidget);
      expect(find.byType(CalendarOverviewPage), findsNothing);
    });

    testWidgets('coming back re-reads the accent another page changed', (
      tester,
    ) async {
      await pumpPage(tester);
      final page = tester.element(find.byType(CalendarOverviewPage));
      Color pagerColor() =>
          tester.widget<AgendaYearScroll>(find.byType(AgendaYearScroll)).color;
      expect(pagerColor(), Theme.of(page).colorScheme.primary);

      unawaited(
        Navigator.of(page).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('settings')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final settings = await SettingsService.getInstance();
      await settings.setCalendarAccentColor(0xFF00897B);
      Navigator.of(page).pop();
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        if (pagerColor() == const Color(0xFF00897B)) break;
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(pagerColor(), const Color(0xFF00897B));
    });
  });

  /// The List mode rework's safety net (`docs/calendar-overview-list-roadmap.md`
  /// slice 0): what list mode does before the rework touches it, driven
  /// through [OverviewRobot]. A case that names an R-number pins a known
  /// defect of the review table (§1.3) as it is today, so the slice that fixes
  /// it flips the case on purpose.
  group('list mode', () {
    final en = lookupAppLocalizations(const Locale('en'));

    int daysIn(int year) =>
        DateTime.utc(year + 1).difference(DateTime.utc(year)).inDays;

    String count(int kept, {int missed = 0}) {
      final label = en.daySummaryEntryCount(kept);
      return missed == 0 ? label : '$label · ${en.dayListMissedCount(missed)}';
    }

    String dayLabel(DateTime day, {AppLocalizations? l10n}) =>
        AgendaListView.dayHeaderLabel(l10n ?? en, day, today);

    /// D7 · A: the list landed on [day] — its read row at the list's top
    /// edge to the pixel, or the list at its end with the row in view.
    void expectLandedOn(OverviewRobot robot, DateTime day) {
      final top = robot.rowTopInView(dayLabel(day));
      expect(top, isNotNull, reason: '${dayLabel(day)} is in view');
      if (robot.listOffset < robot.listMaxOffset) {
        expect(top, moreOrLessEquals(0, epsilon: 0.01));
      }
    }

    CalendarPageLoaded loaded() => bloc.state as CalendarPageLoaded;

    void emit(CalendarPageLoaded state) {
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(state);
    }

    void emitEvents(List<CalendarEvent> events) => emit(
      CalendarPageLoaded(
        allEvents: events,
        focusedDay: today,
        selectedDay: today,
      ),
    );

    Future<void> openList(
      OverviewRobot robot, {
      Locale locale = const Locale('en'),
      double? textScale,
      Size? surface,
      OverviewPeriod? period,
      OverviewListOptions? options,
    }) => robot.open(
      bloc: bloc,
      importExport: importExport,
      mode: AgendaDayListMode.list,
      period: period,
      options: options,
      locale: locale,
      textScale: textScale,
      surface: surface,
    );

    /// Three days of a tracked series, the middle one marked missed, beside
    /// the March class — two months, so the list draws month headers.
    final rowing = CalendarEvent(
      id: 'p1',
      title: 'Rowing',
      categoryId: 'gym',
      startDate: january,
      endDate: DateTime.utc(year, 1, 3),
      rule: const DailyRecurrence(),
      tracksPresence: true,
    );

    void markSecondRowingMissed() {
      EventPresence.updateCache(
        byEvent: {
          'p1': {DateTime.utc(year, 1, 2): PresenceStatus.missed},
        },
      );
    }

    /// A daily series from sixty days before today: under Last 12 months
    /// today's read row has two months of rows above it on any day of the
    /// year, so a landing on today is never a landing at the top — which
    /// This year cannot promise on 1 January.
    final recentDaily = CalendarEvent(
      id: 'r1',
      title: 'Recent',
      categoryId: 'gym',
      startDate: today.subtract(const Duration(days: 60)),
      rule: const DailyRecurrence(),
    );

    testWidgets('a persisted list mode opens in list mode', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      expect(robot.currentMode, AgendaDayListMode.list);
      expect(find.byType(YearMonthTile), findsNothing);
      expect(robot.navTitle, '$year');
      expect(robot.navCount, count(daysIn(year) + 1));
      // Slice 4: the list opens landed on today (D7); January is the top.
      await robot.scrollListTo(0);
      expect(robot.listTexts.first, 'January');
    });

    testWidgets('the rows carry month and day headers with counts, a missed '
        'entry faded', (tester) async {
      addTearDown(EventPresence.resetCache);
      markSecondRowingMissed();
      emitEvents([rowing, mobilityOnce]);
      final robot = OverviewRobot(tester);
      // Tall enough that every row of the short list is built: in the test
      // font the widest day header does not fit one line, so day headers
      // take their two-line slot and the list outgrows a phone.
      await openList(robot, surface: const Size(412, 1400));

      expect(
        robot.listTexts,
        containsAllInOrder([
          'January',
          dayLabel(january),
          count(1),
          'Rowing',
          dayLabel(DateTime.utc(year, 1, 2)),
          count(0, missed: 1),
          'Rowing',
          dayLabel(DateTime.utc(year, 1, 3)),
          count(1),
          'Rowing',
          'March',
          dayLabel(DateTime.utc(year, 3, 9)),
          count(1),
          'Stretch class',
        ]),
      );
      expect(robot.countOf('Rowing'), 3);
      expect(robot.entryOpacity('Rowing'), isNull);
      expect(
        robot.entryOpacity('Rowing', index: 1),
        CalendarColors.missedEventAlpha,
      );
      expect(robot.navCount, count(3, missed: 1));
    });

    testWidgets('hidden missed display drops the missed row and its count', (
      tester,
    ) async {
      addTearDown(EventPresence.resetCache);
      markSecondRowingMissed();
      emitEvents([rowing, mobilityOnce]);
      final settings = await SettingsService.getInstance();
      await settings.setCalendarMissedDisplay(CalendarMissedDisplay.hidden);
      final robot = OverviewRobot(tester);
      // Slice 8a: a phone's height, so every row fits under the mode chips.
      await openList(robot, surface: const Size(412, 915));

      expect(robot.countOf('Rowing'), 2);
      expect(robot.shows(dayLabel(DateTime.utc(year, 1, 2))), isFalse);
      expect(robot.shows(count(0, missed: 1)), isFalse);
      expect(robot.entryOpacity('Rowing', index: 1), isNull);
      expect(robot.navCount, count(3));
    });

    group('a row tap opens the detail sheet over the list (D14 · A)', () {
      /// Runs a sheet in, or out and the next one in, by hand: the editor
      /// loads data of its own that a widget test's clock never completes.
      Future<void> settleSheet(WidgetTester tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      testWidgets('with its title and day, and no calendar pushed', (
        tester,
      ) async {
        final robot = OverviewRobot(tester);
        await openList(robot);
        // Slice 4: the list opens landed on today (D7); March is above it.
        await robot.scrollListTo(0);

        await robot.tapRow('Stretch class');

        final sheet = robot.detailSheet!;
        expect(sheet.event.title, 'Stretch class');
        expect(sheet.day, DateTime.utc(year, 3, 9));
        expect(find.byType(CalendarPage), findsNothing);
        // The sheet's modal route is the only one over the page: once it
        // closes, the page's own route is the current one again.
        expect(
          ModalRoute.of(tester.element(find.byType(EventDetailSheet))),
          isA<PopupRoute<dynamic>>(),
        );
        final pageRoute = ModalRoute.of(
          tester.element(find.byType(CalendarOverviewPage)),
        )!;
        expect(pageRoute.isCurrent, isFalse);

        await robot.tapInDetail(SemanticsIds.eventDetailClose);

        expect(robot.detailSheet, isNull);
        expect(pageRoute.isCurrent, isTrue);
      });

      testWidgets('back closes it onto the row, the list where it was', (
        tester,
      ) async {
        final robot = OverviewRobot(tester);
        await openList(robot, surface: const Size(412, 915));
        // Mid-list, a daily row mid-view: the list opens landed on today
        // (D7), so a step up leaves rows above and below.
        await robot.scrollListTo(robot.listOffset - 200);
        final offset = robot.listOffset;
        expect(offset, greaterThan(0));
        final viewport = tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.identifier == SemanticsIds.overviewList,
          ),
        );
        final rows = find.text('Leg day').hitTestable();
        final tapped = rows.evaluate().reduce(
          (a, b) =>
              (tester.getCenter(find.byWidget(a.widget)).dy -
                          viewport.center.dy)
                      .abs() <=
                  (tester.getCenter(find.byWidget(b.widget)).dy -
                          viewport.center.dy)
                      .abs()
              ? a
              : b,
        );
        final top = tester.getTopLeft(find.byWidget(tapped.widget)).dy;
        await tester.tap(find.byWidget(tapped.widget));
        await tester.pumpAndSettle();
        final day = robot.detailSheet!.day;

        await robot.back();

        expect(robot.detailSheet, isNull);
        expect(robot.isOpen, isTrue);
        expect(robot.listOffset, offset);
        final row = find.descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.overviewRow('e1', day)),
          matching: find.text('Leg day'),
        );
        expect(tester.getTopLeft(row).dy, top);
      });

      testWidgets('Missed from the sheet dims the row once the bloc says so', (
        tester,
      ) async {
        addTearDown(EventPresence.resetCache);
        emitEvents([rowing, mobilityOnce]);
        final robot = OverviewRobot(tester);
        await openList(robot);
        await robot.scrollListTo(0);
        final observer = recordBlocEvents();

        await robot.tapRow('Rowing');
        expect(robot.detailSheet!.day, january);
        await robot.tapInDetail(SemanticsIds.eventDetailMissed);

        final mark = observer.events.whereType<SetOccurrencePresence>().single;
        expect(mark.eventId, 'p1');
        expect(mark.day, january);
        expect(mark.status, PresenceStatus.missed);
        // What the bloc's write lands as: the facade and a revision bump.
        EventPresence.updateCache(
          byEvent: {
            'p1': {january: PresenceStatus.missed},
          },
        );
        emit(
          loaded().copyWith(presenceRevision: loaded().presenceRevision + 1),
        );
        await tester.pumpAndSettle();
        // Parked under the sheet, adopted as it closes.
        expect(robot.entryOpacity('Rowing'), isNull);
        await robot.back();

        expect(robot.entryOpacity('Rowing'), CalendarColors.missedEventAlpha);
      });

      testWidgets('the bloc states the trip emits are parked under the sheet '
          'and adopted once it closes', (tester) async {
        var stores = 0;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
          onStore: (_) => stores++,
        );
        await robot.scrollListTo(0);
        await robot.tapRow('Stretch class');
        stores = 0;

        // Two writes landing under the sheet, each a different list (an
        // equal state is no emit at all).
        emitEvents([gymDaily, mobilityOnce]);
        await tester.pumpAndSettle();
        emitEvents([gymDaily, mobilityOnce, rowing]);
        await tester.pumpAndSettle();
        expect(stores, 0, reason: 'nothing resolved under the sheet');

        await robot.back();
        await robot.finishResolving();

        expect(stores, 1, reason: 'the parked state, adopted once');
        expect(robot.shows('Stretch class'), isTrue);
      });

      group('into the editor', () {
        late Directory tempDir;

        setUpAll(() async {
          tempDir = await Directory.systemTemp.createTemp(
            'anta_overview_editor',
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (call) async => tempDir.path,
              );
        });

        tearDownAll(() async {
          // Closes the file database and drops the cached instance, so a
          // later test in this file cannot be handed a closed one.
          await AppDatabase.deleteAllData();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              );
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        });

        /// The markdown bar the event editor reads as it mounts, loaded
        /// already: one that is not would be asked to load, and that read
        /// never comes back under a widget test's clock.
        Future<MarkdownBarBloc> loadedMarkdownBar(WidgetTester tester) async {
          final bar = await tester.runAsync(() async {
            final bar = MarkdownBarBloc(
              barService: await MarkdownBarService.getInstance(),
            );
            final loaded = bar.stream
                .firstWhere((state) => state is MarkdownBarLoaded)
                .timeout(const Duration(seconds: 30));
            bar.add(const LoadMarkdownBar());
            await loaded;
            return bar;
          });
          addTearDown(bar!.close);
          return bar;
        }

        testWidgets("the editor's Save renames the row", (tester) async {
          final markdownBar = await loadedMarkdownBar(tester);
          final robot = OverviewRobot(tester);
          await robot.open(
            bloc: bloc,
            importExport: importExport,
            mode: AgendaDayListMode.list,
            markdownBar: markdownBar,
          );
          await robot.scrollListTo(0);
          final observer = recordBlocEvents();

          await robot.tapRow('Stretch class');
          await robot.tapInDetail(SemanticsIds.eventDetailEdit, settle: false);
          await settleSheet(tester);
          await tester.enterText(
            find
                .descendant(
                  of: find.byType(EventEditorSheet),
                  matching: find.byType(TextField),
                )
                .first,
            'Pilates',
          );
          await tester.pump();
          await tester.tap(find.bySemanticsIdentifier(SemanticsIds.eventSave));
          await settleSheet(tester);

          final update = observer.events
              .whereType<UpdateCalendarEvent>()
              .single;
          expect(update.event.title, 'Pilates');
          // The save reopens the sheet on the saved event, over the list.
          expect(robot.detailSheet!.event.title, 'Pilates');

          // What the bloc's write lands as: parked under the sheet.
          emitEvents([gymDaily, update.event, oldCheckup]);
          await tester.pump();
          expect(robot.shows('Pilates'), isFalse);
          await robot.back();

          expect(robot.shows('Pilates'), isTrue);
          expect(robot.shows('Stretch class'), isFalse);
        });
      });
    });

    group('The presence button on a day row (D18 revisited, 2026-10-17)', () {
      final rowingJanuary = SemanticsIds.overviewRowPresence('p1', january);

      /// The presence buttons built on the page, whoever's.
      final anyPresenceButton = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.identifier?.startsWith(
                  'overview-row-presence-',
                ) ??
                false),
      );

      /// The list on Rowing's three January days, the bloc's events recorded
      /// from there.
      Future<(OverviewRobot, List<Object?>)> openRowing(
        WidgetTester tester,
      ) async {
        addTearDown(EventPresence.resetCache);
        emitEvents([rowing, mobilityOnce]);
        final robot = OverviewRobot(tester);
        await openList(robot);
        await robot.scrollListTo(0);
        return (robot, recordBlocEvents().events);
      }

      testWidgets('a kept row\'s button marks it missed with the day panel\'s '
          'words, the row dims once the bloc says so, and pressed again it '
          'marks present', (tester) async {
        final (robot, events) = await openRowing(tester);
        expect(robot.presenceTooltip(rowingJanuary), en.eventMarkMissed);

        await robot.pressPresence(rowingJanuary);

        expect(robot.detailSheet, isNull);
        final missed = events.whereType<SetOccurrencePresence>().single;
        expect(
          (missed.eventId, missed.day, missed.status),
          ('p1', january, PresenceStatus.missed),
        );
        expect(robot.entryOpacity('Rowing'), isNull);
        // What the bloc's write lands as: the facade and a revision bump.
        EventPresence.updateCache(
          byEvent: {
            'p1': {january: PresenceStatus.missed},
          },
        );
        emit(
          loaded().copyWith(presenceRevision: loaded().presenceRevision + 1),
        );
        await tester.pumpAndSettle();
        expect(robot.entryOpacity('Rowing'), CalendarColors.missedEventAlpha);
        expect(robot.presenceTooltip(rowingJanuary), en.eventMarkPresent);

        events.clear();
        await robot.pressPresence(rowingJanuary);

        expect(robot.detailSheet, isNull);
        final present = events.whereType<SetOccurrencePresence>().single;
        expect(
          (present.eventId, present.day, present.status),
          ('p1', january, PresenceStatus.present),
        );
      });

      testWidgets('the button is its own node beside the row\'s: the id a '
          'device script hits, the day panel\'s words as its tooltip, a tap '
          'action of its own', (tester) async {
        final handle = tester.ensureSemantics();
        await openRowing(tester);

        final button = tester
            .getSemantics(find.bySemanticsIdentifier(rowingJanuary))
            .getSemanticsData();
        expect(button.identifier, rowingJanuary);
        expect(button.tooltip, en.eventMarkMissed);
        expect(button.hasAction(SemanticsAction.tap), isTrue);
        final row = tester
            .getSemantics(
              find.bySemanticsIdentifier(
                SemanticsIds.overviewRow('p1', january),
              ),
            )
            .getSemanticsData();
        expect(row.identifier, SemanticsIds.overviewRow('p1', january));
        expect(row.tooltip, isEmpty);
        expect(row.hasAction(SemanticsAction.tap), isTrue);
        handle.dispose();
      });

      testWidgets('under Missed only a press marks the day present and, once '
          'the bloc says so, takes its row and its day out of the list', (
        tester,
      ) async {
        addTearDown(EventPresence.resetCache);
        markSecondRowingMissed();
        emitEvents([rowing, mobilityOnce]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: const Size(412, 915));
        await robot.setMissedOnly(true);
        final second = DateTime.utc(year, 1, 2);
        final secondRow = SemanticsIds.overviewRow('p1', second);
        final secondPresence = SemanticsIds.overviewRowPresence('p1', second);
        expect(robot.countOf('Rowing'), 1);
        expect(find.bySemanticsIdentifier(secondRow), findsOneWidget);
        expect(robot.shows(dayLabel(second)), isTrue);
        expect(robot.navCount, count(0, missed: 1));
        expect(robot.presenceTooltip(secondPresence), en.eventMarkPresent);
        final events = recordBlocEvents().events;

        await robot.pressPresence(secondPresence);

        final present = events.whereType<SetOccurrencePresence>().single;
        expect(
          (present.eventId, present.day, present.status),
          ('p1', second, PresenceStatus.present),
        );
        // What the bloc's write lands as: the facade and a revision bump.
        EventPresence.updateCache(
          byEvent: {
            'p1': {second: PresenceStatus.present},
          },
        );
        emit(
          loaded().copyWith(presenceRevision: loaded().presenceRevision + 1),
        );
        await tester.pumpAndSettle();

        expect(robot.countOf('Rowing'), 0);
        expect(find.bySemanticsIdentifier(secondRow), findsNothing);
        expect(robot.presenceButton(secondPresence), findsNothing);
        expect(robot.shows(dayLabel(second)), isFalse);
        expect(robot.navCount, count(0));
      });

      testWidgets('a row tap still opens the detail sheet and marks nothing; '
          'a row whose event keeps no attendance has no button', (
        tester,
      ) async {
        final (robot, events) = await openRowing(tester);
        expect(robot.presenceButton(rowingJanuary), findsOneWidget);

        await robot.tapRow('Rowing');

        expect(robot.detailSheet!.day, january);
        expect(events.whereType<SetOccurrencePresence>(), isEmpty);
        await robot.back();

        await robot.tapRow('Stretch class');
        expect(robot.detailSheet!.event.title, 'Stretch class');
        await robot.back();
        expect(robot.shows('Stretch class'), isTrue);
        expect(
          robot.presenceButton(
            SemanticsIds.overviewRowPresence('e2', DateTime.utc(year, 3, 9)),
          ),
          findsNothing,
        );
        expect(events.whereType<SetOccurrencePresence>(), isEmpty);
      });

      testWidgets('month mode\'s rows carry it too', (tester) async {
        addTearDown(EventPresence.resetCache);
        emitEvents([rowing, mobilityOnce]);
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.month,
          surface: const Size(412, 915),
        );
        await robot.pageMonthTo(january);
        final events = recordBlocEvents().events;
        expect(robot.presenceTooltip(rowingJanuary), en.eventMarkMissed);

        await robot.pressPresence(rowingJanuary);

        expect(robot.detailSheet, isNull);
        final missed = events.whereType<SetOccurrencePresence>().single;
        expect(
          (missed.eventId, missed.day, missed.status),
          ('p1', january, PresenceStatus.missed),
        );
      });

      testWidgets('One per event\'s rows are no day and carry none; back to '
          'every occurrence they do again', (tester) async {
        final (robot, _) = await openRowing(tester);
        expect(anyPresenceButton, findsWidgets);

        await robot.setRows(OverviewRows.perEvent);

        expect(robot.shows('Rowing'), isTrue);
        expect(anyPresenceButton, findsNothing);
        await robot.setRows(OverviewRows.everyOccurrence);
        await robot.scrollListTo(0);
        expect(robot.presenceButton(rowingJanuary), findsOneWidget);
      });

      testWidgets('missed entries hidden take the buttons away from the '
          'list\'s rows: a mark would remove its own row (review 2)', (
        tester,
      ) async {
        final (robot, events) = await openRowing(tester);
        expect(robot.presenceButton(rowingJanuary), findsOneWidget);
        await robot.cover();
        final settings = await SettingsService.getInstance();
        await settings.setCalendarMissedDisplay(CalendarMissedDisplay.hidden);

        await robot.uncover();
        await robot.scrollListTo(0);

        expect(robot.shows('Rowing'), isTrue);
        expect(anyPresenceButton, findsNothing);
        expect(events.whereType<SetOccurrencePresence>(), isEmpty);
      });

      /// D32 · A: under the hidden display month mode's picked day is the
      /// day panel's twin — its missed and assumed-absent occurrences listed
      /// faded, with the button — while the whole month keeps dropping them.
      group('the picked day under the hidden display (D32)', () {
        final first = january;
        final third = DateTime.utc(year, 1, 3);
        final tenth = DateTime.utc(year, 1, 10);

        /// A daily attendance series assumed absent, Jan 1–5, Jan 1 marked
        /// present — the owner's gym event: under `hidden` only the kept
        /// day has an entry, the rest are dropped before they are rows.
        final gym = CalendarEvent(
          id: 'a1',
          title: 'Workout',
          categoryId: 'gym',
          startDate: january,
          endDate: DateTime.utc(year, 1, 5),
          rule: const DailyRecurrence(),
          tracksPresence: true,
          assumeAbsent: true,
        );

        /// Beside the kept day, so a query has something to leave out.
        final stretchFirst = CalendarEvent(
          id: 'a2',
          title: 'Stretch',
          categoryId: 'mobility',
          startDate: january,
          rule: const OneTimeRecurrence(),
        );

        void markGym(Map<DateTime, PresenceStatus> marks) =>
            EventPresence.updateCache(byEvent: {'a1': marks});

        void bumpPresence() => emit(
          loaded().copyWith(presenceRevision: loaded().presenceRevision + 1),
        );

        /// Month mode on January under `hidden`, the bloc's events recorded
        /// from there.
        Future<(OverviewRobot, List<Object?>)> openHiddenJanuary(
          WidgetTester tester, {
          List<CalendarEvent>? events,
          Map<DateTime, PresenceStatus>? marks,
        }) async {
          addTearDown(EventPresence.resetCache);
          markGym(marks ?? {first: PresenceStatus.present});
          emitEvents(events ?? [gym]);
          final settings = await SettingsService.getInstance();
          await settings.setCalendarMissedDisplay(CalendarMissedDisplay.hidden);
          final robot = OverviewRobot(tester);
          await robot.open(
            bloc: bloc,
            importExport: importExport,
            mode: AgendaDayListMode.month,
            surface: const Size(412, 915),
          );
          await robot.pageMonthTo(january);
          return (robot, recordBlocEvents().events);
        }

        testWidgets('a hidden assumed-absent day is a day to pick: its read '
            'row, its row faded with "Mark as present"; a press marks it '
            'present and, once the bloc says so, the row is at full strength '
            'and the day has its bar', (tester) async {
          final (robot, events) = await openHiddenJanuary(tester);
          final presence = SemanticsIds.overviewRowPresence('a1', third);
          expect(robot.gridDayHasBars(third), isFalse);
          expect(robot.gridDayPickable(third), isTrue);

          await robot.tapGridDay(third);

          expect(robot.dayPicked, isTrue);
          expect(find.text(dayLabel(third)), findsOneWidget);
          expect(find.text(count(0, missed: 1)), findsOneWidget);
          expect(find.text('Workout'), findsOneWidget);
          expect(
            robot.monthEntryOpacity('Workout'),
            CalendarColors.missedEventAlpha,
          );
          expect(robot.presenceTooltip(presence), en.eventMarkPresent);

          await robot.pressPresence(presence);

          expect(robot.detailSheet, isNull);
          final present = events.whereType<SetOccurrencePresence>().single;
          expect(
            (present.eventId, present.day, present.status),
            ('a1', third, PresenceStatus.present),
          );
          markGym({
            first: PresenceStatus.present,
            third: PresenceStatus.present,
          });
          bumpPresence();
          await tester.pumpAndSettle();

          expect(robot.dayPicked, isTrue);
          expect(robot.monthEntryOpacity('Workout'), isNull);
          expect(find.text(count(1)), findsOneWidget);
          expect(robot.presenceTooltip(presence), en.eventMarkMissed);
          expect(robot.gridDayHasBars(third), isTrue);
          expect(robot.navCount, count(2));
        });

        testWidgets('a day with no occurrence stays inert: drawn faded, a tap '
            'picks nothing', (tester) async {
          final (robot, _) = await openHiddenJanuary(tester);
          expect(robot.gridDayPickable(tenth), isFalse);

          await robot.tapGridDay(tenth);

          expect(robot.dayPicked, isFalse);
          expect(find.text(dayLabel(tenth)), findsNothing);
        });

        testWidgets('the whole month\'s rows keep no button and list no '
            'hidden day', (tester) async {
          final (robot, _) = await openHiddenJanuary(tester);

          expect(robot.dayPicked, isFalse);
          expect(find.text('Workout'), findsOneWidget);
          expect(find.text(dayLabel(third)), findsNothing);
          expect(anyPresenceButton, findsNothing);
          expect(robot.navCount, count(1));
        });

        testWidgets('a mark missed on the picked day fades its row and keeps '
            'it; the day stays a day to pick, its bar gone', (tester) async {
          final (robot, events) = await openHiddenJanuary(tester);
          final presence = SemanticsIds.overviewRowPresence('a1', first);
          await robot.tapGridDay(first);
          expect(robot.monthEntryOpacity('Workout'), isNull);
          expect(robot.presenceTooltip(presence), en.eventMarkMissed);

          await robot.pressPresence(presence);

          final missed = events.whereType<SetOccurrencePresence>().single;
          expect(
            (missed.eventId, missed.day, missed.status),
            ('a1', first, PresenceStatus.missed),
          );
          markGym({first: PresenceStatus.missed});
          bumpPresence();
          await tester.pumpAndSettle();

          expect(robot.dayPicked, isTrue);
          expect(find.text('Workout'), findsOneWidget);
          expect(
            robot.monthEntryOpacity('Workout'),
            CalendarColors.missedEventAlpha,
          );
          expect(find.text(count(0, missed: 1)), findsOneWidget);
          expect(robot.presenceTooltip(presence), en.eventMarkPresent);
          expect(robot.gridDayHasBars(first), isFalse);
          expect(robot.gridDayPickable(first), isTrue);
          expect(robot.navCount, count(0));
        });

        testWidgets('under a live query the picked day lists only what '
            'matches, and a day only hidden occurrences fill stays inert', (
          tester,
        ) async {
          final (robot, _) = await openHiddenJanuary(
            tester,
            events: [gym, stretchFirst],
          );
          await robot.tapGridDay(first);
          expect(find.text('Workout'), findsOneWidget);
          expect(find.text('Stretch'), findsOneWidget);

          // Lower case, so the field's own text is not the row's title.
          await robot.typeQuery('workout');
          await tester.pumpAndSettle();

          expect(robot.dayPicked, isTrue);
          expect(find.text('Workout'), findsOneWidget);
          expect(find.text('Stretch'), findsNothing);
          expect(robot.gridDayPickable(third), isFalse);
        });

        testWidgets('a hidden-only picked day under a query that matches it '
            'keeps its cell pickable, as its rows list the match', (
          tester,
        ) async {
          final (robot, _) = await openHiddenJanuary(
            tester,
            events: [gym, stretchFirst],
          );
          await robot.tapGridDay(third);

          await robot.typeQuery('workout');
          await tester.pumpAndSettle();

          expect(robot.dayPicked, isTrue);
          expect(find.text('Workout'), findsOneWidget);
          expect(
            robot.monthEntryOpacity('Workout'),
            CalendarColors.missedEventAlpha,
          );
          expect(robot.gridDayPickable(third), isTrue);
        });

        testWidgets('a picked day a query has emptied still lets go through '
            'its ✕, back to the whole month', (tester) async {
          final (robot, _) = await openHiddenJanuary(
            tester,
            events: [gym, stretchFirst],
          );
          await robot.tapGridDay(third);
          expect(find.text('Workout'), findsOneWidget);

          await robot.typeQuery('stretch');
          await tester.pumpAndSettle();
          expect(robot.dayPicked, isTrue);
          expect(find.text('Workout'), findsNothing);
          expect(find.text('Stretch'), findsNothing);

          await robot.releaseDay();

          expect(robot.dayPicked, isFalse);
          expect(find.text(dayLabel(first)), findsOneWidget);
          expect(find.text('Stretch'), findsOneWidget);
        });

        testWidgets('under Missed only a hidden picked day lists its missed '
            'entries alone, its read row counting none kept', (tester) async {
          // Jan 1 unmarked: Workout assumed absent beside the kept Stretch.
          final (robot, _) = await openHiddenJanuary(
            tester,
            events: [gym, stretchFirst],
            marks: const {},
          );
          await robot.tapGridDay(first);
          expect(find.text('Workout'), findsOneWidget);
          expect(find.text('Stretch'), findsOneWidget);
          expect(find.text(count(1, missed: 1)), findsOneWidget);

          await robot.setMissedOnly(true);

          expect(robot.dayPicked, isTrue);
          expect(find.text('Workout'), findsOneWidget);
          expect(find.text('Stretch'), findsNothing);
          expect(
            robot.monthEntryOpacity('Workout'),
            CalendarColors.missedEventAlpha,
          );
          expect(find.text(count(0, missed: 1)), findsOneWidget);
        });
      });

      testWidgets('the tune button reads selected for restrictions alone', (
        tester,
      ) async {
        final (robot, _) = await openRowing(tester);
        expect(robot.presenceButton(rowingJanuary), findsOneWidget);
        expect(robot.optionsSelected, isFalse);
        await robot.selectMode(AgendaDayListMode.month);
        expect(robot.optionsSelected, isFalse);
        await robot.selectMode(AgendaDayListMode.list);

        await robot.setMissedOnly(true);

        expect(robot.optionsSelected, isTrue);
      });

      testWidgets('a mark\'s forget re-resolves its month alone, and the year '
          'scroll then shows it on the tile and the header', (tester) async {
        // The bloc writes the mark through the presence service on the
        // suite's database, which publishes the facade and bumps the
        // revision as on the phone.
        await tester.runAsync(() => EventPresenceService.forTesting(db));
        final (robot, events) = await openRowing(tester);
        CalendarEvent.debugOccursOnCalls = 0;
        final before = loaded().presenceRevision;
        await robot.pressPresence(rowingJanuary);
        // The write is real database work, which the fake clock never
        // advances: wait for its bump in real time, then draw it.
        for (var wait = 0; wait < 100; wait++) {
          if (loaded().presenceRevision != before) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();
        expect(loaded().presenceRevision, before + 1);
        expect(events.whereType<SetOccurrencePresence>(), hasLength(1));
        expect(EventPresence.isMissed(rowing, january), isTrue);
        final rescanned = CalendarEvent.debugOccursOnCalls;
        expect(rescanned, inInclusiveRange(1, 31), reason: 'January alone');

        await robot.selectMode(AgendaDayListMode.year);

        expect(CalendarEvent.debugOccursOnCalls, rescanned);
        final handle = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(
            '${tileLabel(january)}, ${count(2, missed: 1)}',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getSemantics(
                find.bySemanticsIdentifier(
                  SemanticsIds.overviewYearHeader(year),
                ),
              )
              .label,
          '$year, ${count(3, missed: 1)}',
        );
        handle.dispose();
      });

      testWidgets('a mark far down a long period re-resolves its month alone: '
          'the store stays and the list holds still on every frame '
          '(review 1)', (tester) async {
        addTearDown(EventPresence.resetCache);
        final first = DateTime.utc(year - 4, 1, 1);
        final tracked = CalendarEvent(
          id: 'p9',
          title: 'Rowing',
          categoryId: 'gym',
          startDate: first,
          rule: const DailyRecurrence(),
          tracksPresence: true,
        );
        emitEvents([tracked]);
        var stores = 0;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
          period: const OverviewRollingPeriod(OverviewRollingPreset.allTime),
          surface: const Size(412, 915),
          onStore: (_) => stores++,
        );
        // Five years: two with the frame, the rest in runs.
        for (var run = 0; run < 6; run++) {
          await robot.finishResolving();
        }
        await tester.pumpAndSettle();
        await robot.scrollListTo(robot.listMaxOffset - 2000);
        final events = recordBlocEvents().events;
        final button = tester.widget<Semantics>(anyPresenceButton.first);

        await robot.pressPresence(button.properties.identifier!);

        final mark = events.whereType<SetOccurrencePresence>().single;
        final offset = robot.listOffset;
        expect(offset, greaterThan(robot.listMaxOffset / 2));
        stores = 0;
        CalendarEvent.debugOccursOnCalls = 0;
        // What the bloc's write lands as: the facade and a revision bump.
        EventPresence.updateCache(
          byEvent: {
            'p9': {mark.day: PresenceStatus.missed},
          },
        );
        emit(
          loaded().copyWith(presenceRevision: loaded().presenceRevision + 1),
        );
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump();
          expect(robot.listOffset, offset, reason: 'frame $frame');
        }
        await robot.finishResolving();

        expect(robot.listOffset, offset);
        expect(stores, 0, reason: 'the store is kept');
        expect(
          CalendarEvent.debugOccursOnCalls,
          DateTime.utc(mark.day.year, mark.day.month + 1, 0).day,
          reason: 'one month scanned again, not the period',
        );
        final listed = today.difference(first).inDays;
        expect(robot.navCount, count(listed, missed: 1));
      });
    });

    group('a Keep taken on the alarm page', () {
      testWidgets('with no calendar beneath reloads the bloc and leaves the '
          'notice for the calendar an Open event pushes, which defers its '
          'sheet to its own reload', (tester) async {
        addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
        final robot = OverviewRobot(tester);
        await robot.openFromDrawer(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
        );
        final observer = recordBlocEvents();

        AlertKeepNotice.instance.publish();
        await tester.pump();

        expect(observer.events.whereType<LoadCalendarEvents>(), hasLength(1));
        expect(AlertKeepNotice.instance.hasPending, isTrue);

        observer.events.clear();
        unawaited(AppNavigator.toCalendarOccurrence(day: today, eventId: 'e1'));
        for (var i = 0; i < 60 && robot.isOpen; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(CalendarPage), findsOneWidget);
        expect(AlertKeepNotice.instance.hasPending, isFalse);
        expect(observer.events.whereType<LoadCalendarEvents>(), isNotEmpty);
        expect(
          find.byType(EventDetailSheet),
          findsNothing,
          reason: 'the target waits for the reload, not the copy before Keep',
        );

        // The reload lands — a different list, as an equal state would not
        // be emitted at all — and the sheet opens on it.
        emitEvents([gymDaily, mobilityOnce]);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(find.byType(EventDetailSheet), findsOneWidget);
      });

      testWidgets('already taken by a calendar beneath is neither taken nor '
          'reloaded again here', (tester) async {
        // The calendar beneath registered first, so it hears the notice
        // before this page does.
        void calendarBeneath() => AlertKeepNotice.instance.take();
        AlertKeepNotice.instance.addListener(calendarBeneath);
        addTearDown(
          () => AlertKeepNotice.instance.removeListener(calendarBeneath),
        );
        final robot = OverviewRobot(tester);
        await robot.openAboveCalendar(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
        );
        final observer = recordBlocEvents();

        AlertKeepNotice.instance.publish();
        await tester.pump();

        expect(observer.events.whereType<LoadCalendarEvents>(), isEmpty);
        expect(AlertKeepNotice.instance.hasPending, isFalse);
      });

      testWidgets('before the overview opened is served after its first '
          'frame, and left standing', (tester) async {
        AlertKeepNotice.instance.publish();
        final observer = recordBlocEvents();
        final robot = OverviewRobot(tester);
        await openList(robot);

        expect(observer.events.whereType<LoadCalendarEvents>(), hasLength(1));
        expect(AlertKeepNotice.instance.hasPending, isTrue);
      });
    });

    group('the period band (slice 9a)', () {
      const last90Days = OverviewRollingPeriod(
        OverviewRollingPreset.last90Days,
      );
      const phone = Size(412, 915);

      /// A daily series from well over a year back, so every step a case
      /// takes lists rows.
      final longDaily = CalendarEvent(
        id: 'l1',
        title: 'Long run',
        categoryId: 'gym',
        startDate: today.subtract(const Duration(days: 800)),
        rule: const DailyRecurrence(),
      );

      testWidgets('List mode draws the nav: the period as its title, the '
          'count as its subtitle, no count caption (D15)', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);

        expect(find.byType(AgendaPeriodNav), findsOneWidget);
        expect(robot.navTitle, '$year');
        expect(robot.navTitle, robot.periodValue);
        expect(robot.navCount, count(daysIn(year) + 1));
        // The count is said once, by the nav; the caption under the filter
        // group is gone.
        expect(find.text(count(daysIn(year) + 1)), findsOneWidget);
        expect(await robot.periodChoice(), OverviewPeriodChoice.thisYear);
        expect(robot.periodEnabled, isTrue);
        expect(robot.canJumpToToday, isFalse, reason: 'on the home period');
        expect(robot.navTodayTooltip, 'Back to $year');
      });

      testWidgets('◄ on Last 90 days lists the ninety days before as a span, '
          'nothing persisted; ► back onto the preset is the preset (review '
          '5); Today back to the preset (D15a–c)', (tester) async {
        emitEvents([longDaily]);
        final settings = await SettingsService.getInstance();
        final robot = OverviewRobot(tester);
        await openList(robot, period: last90Days, surface: phone);
        final start = today.subtract(const Duration(days: 89));
        final backStart = start.subtract(const Duration(days: 90));
        final backEnd = start.subtract(const Duration(days: 1));
        expect(robot.navTodayTooltip, 'Back to Last 90 days');

        await robot.previous();
        final back = dateSpanLabel(en, backStart, backEnd);
        expect(robot.navTitle, back);
        expect(robot.periodValue, back);
        expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
        expect(robot.navCount, count(90));
        // Today lies outside the span: the list lands at its top (D7).
        expect(robot.listOffset, 0);
        expect(robot.shows(dayLabel(backStart)), isTrue);
        expect(robot.canJumpToToday, isTrue);
        expect(
          (await settings.getCalendarOverviewSettings()).period,
          last90Days,
          reason: 'a step never persists (D15c)',
        );

        await robot.next();
        expect(robot.navTitle, 'Last 90 days');
        expect(robot.periodValue, 'Last 90 days');
        expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
        expect(robot.canJumpToToday, isFalse, reason: 'the preset, not a span');

        await robot.previous();
        expect(robot.navTitle, back);
        await robot.today();
        expect(robot.navTitle, 'Last 90 days');
        expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
        expect(robot.canJumpToToday, isFalse);
        expectLandedOn(robot, today);
        expect(
          (await settings.getCalendarOverviewSettings()).period,
          last90Days,
        );
      });

      testWidgets('This year ◄ lists last year, the year persisted stays this '
          'year; a pick moves the home', (tester) async {
        emitEvents([longDaily]);
        final settings = await SettingsService.getInstance();
        final robot = OverviewRobot(tester);
        await openList(robot);

        await robot.previous();
        expect(robot.navTitle, '${year - 1}');
        expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
        expect(
          (await settings.getCalendarOverviewSettings()).period,
          OverviewYearPeriod(year),
        );

        await robot.pickPeriod(OverviewPeriodChoice.last12Months);
        expect(robot.navTodayTooltip, 'Back to Last 12 months');
        expect(robot.canJumpToToday, isFalse);
      });

      testWidgets("All time's chevrons are disabled", (tester) async {
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          period: const OverviewRollingPeriod(OverviewRollingPreset.allTime),
        );

        expect(robot.navTitle, 'All time');
        expect(robot.canGoPrevious, isFalse);
        expect(robot.canGoNext, isFalse);
      });

      testWidgets('a step at the year bounds is disabled', (tester) async {
        // The events reach back to the checkup two years ago.
        final robot = OverviewRobot(tester);
        await openList(robot);

        expect(robot.canGoPrevious, isTrue);
        await robot.previous();
        await robot.previous();
        expect(robot.navTitle, '${year - 2}');
        expect(robot.canGoPrevious, isFalse);
        expect(robot.canGoNext, isTrue);
      });

      testWidgets('the title opens the Period menu; its Custom range…: a '
          'cancel changes nothing, a pick is a pick and becomes the home '
          '(D19)', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);

        await robot.tapNavTitle();
        expect(robot.menuOpen, isTrue);
        await robot.pickOpenPeriod(OverviewPeriodChoice.custom);
        expect(robot.rangePickerOpen, isTrue);
        await robot.cancelRange();
        expect(robot.rangePickerOpen, isFalse);
        expect(robot.navTitle, '$year');
        expect(robot.currentMode, AgendaDayListMode.list);

        await robot.pickCustomMonth(DateTime.utc(year - 1, 6, 1));
        expect(
          robot.navTitle,
          dateSpanLabel(
            en,
            DateTime.utc(year - 1, 6, 1),
            DateTime.utc(year - 1, 6, 30),
          ),
        );
        expect(robot.canJumpToToday, isFalse, reason: 'the pick is the home');
      });

      testWidgets('the title box is as tall for a year, a preset and a '
          'cross-year span at German 200 %', (tester) async {
        emitEvents([longDaily]);
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          locale: const Locale('de'),
          textScale: 2.0,
          surface: const Size(360, 780),
        );
        final height = robot.navSize.height;

        await robot.pickPeriod(OverviewPeriodChoice.last12Months);
        expect(robot.navSize.height, height);
        await robot.previous();
        expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
        expect(robot.navSize.height, height);
      });

      for (final surface in const [Size(360, 780), Size(412, 915)]) {
        testWidgets('the band does not move between a year, a preset and a '
            'stepped span — de, 200 %, '
            '${surface.width.round()} wide (device pass)', (tester) async {
          emitEvents([longDaily]);
          final robot = OverviewRobot(tester);
          await openList(
            robot,
            locale: const Locale('de'),
            textScale: 2.0,
            surface: surface,
          );
          final top = robot.navTop;
          expect(robot.periodValue, '$year');

          await robot.pickPeriod(OverviewPeriodChoice.last90Days);
          expect(robot.navTop, top);
          await robot.previous();
          expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
          expect(robot.navTop, top, reason: robot.periodValue);
        });
      }

      testWidgets('Month mode\'s Period menu checks the month\'s year, not a '
          'span stepped to in the list; a pick there lists it (device '
          'pass)', (tester) async {
        emitEvents([longDaily]);
        final robot = OverviewRobot(tester);
        await openList(robot, period: last90Days);
        await robot.previous();
        expect(await robot.periodChoice(), OverviewPeriodChoice.custom);

        await robot.selectMode(AgendaDayListMode.month);

        final shown = int.parse(
          RegExp(r'\d{4}').firstMatch(robot.periodValue)![0]!,
        );
        expect(robot.navTitle, contains('$shown'));
        expect(
          await robot.periodChoice(),
          shown == year
              ? OverviewPeriodChoice.thisYear
              : OverviewPeriodChoice.custom,
        );

        await robot.pickPeriod(OverviewPeriodChoice.last90Days);
        expect(robot.currentMode, AgendaDayListMode.list);
        expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
        expect(robot.navTitle, 'Last 90 days');
      });

      testWidgets('Month mode on a past year reads it with Custom checked', (
        tester,
      ) async {
        emitEvents([longDaily]);
        final robot = OverviewRobot(tester);
        await openList(robot);
        await robot.previous();

        await robot.selectMode(AgendaDayListMode.month);

        expect(robot.periodValue, contains('${year - 1}'));
        expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
        expect(robot.navTitle, contains('${year - 1}'));
      });

      for (final locale in const [Locale('en'), Locale('de')]) {
        testWidgets('the title box is as tall for every month\'s span at '
            '360 × 780, ${locale.languageCode}, 200 % (review 6)', (
          tester,
        ) async {
          emitEvents([longDaily]);
          final robot = OverviewRobot(tester);
          await openList(
            robot,
            locale: locale,
            textScale: 2.0,
            surface: const Size(360, 780),
          );
          final height = robot.navSize.height;

          for (var month = 1; month <= 12; month++) {
            await robot.pickCustomMonth(DateTime.utc(year, month, 1));
            expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
            expect(robot.navSize.height, height, reason: robot.navTitle);
          }
        });
      }

      for (final (surface, locale, scale) in const [
        (Size(412, 915), Locale('en'), 1.0),
        (Size(360, 780), Locale('en'), 1.0),
        (Size(412, 915), Locale('de'), 2.0),
        (Size(360, 780), Locale('de'), 2.0),
      ]) {
        testWidgets('each mode\'s nav is measured over its own titles, and a '
            'page or a step inside a mode moves nothing (D20) — '
            '${surface.width.round()} × ${surface.height.round()}, '
            '${locale.languageCode}, text ×$scale', (tester) async {
          emitEvents([longDaily]);
          final robot = OverviewRobot(tester);
          final errors = await layoutErrorsDuring(
            () => openList(
              robot,
              locale: locale,
              textScale: scale,
              surface: surface,
            ),
          );
          expect(errors, isEmpty);
          final list = robot.navSize.height;
          final navTop = robot.navTop;
          await robot.previous();
          expect(robot.navSize.height, list, reason: robot.navTitle);
          expect(robot.navTop, navTop, reason: robot.navTitle);

          await robot.selectMode(AgendaDayListMode.year);
          final yearNav = robot.navSize.height;
          final scrollTop = tester.getTopLeft(find.byType(AgendaYearScroll)).dy;
          await robot.previous();
          expect(robot.navSize.height, yearNav, reason: robot.navTitle);
          expect(
            tester.getTopLeft(find.byType(AgendaYearScroll)).dy,
            scrollTop,
          );

          await robot.selectMode(AgendaDayListMode.month);
          final monthNav = robot.navSize.height;
          for (var i = 0; i < 12; i++) {
            if (!robot.canGoNext) break;
            await robot.next();
            expect(robot.navSize.height, monthNav, reason: robot.navTitle);
          }

          if (locale.languageCode == 'en' &&
              scale == 1.0 &&
              surface.width == 360) {
            // One line for a year; a span takes two here. (The test font's
            // square glyphs wrap "September 2026" too, which a phone's font
            // does not, so Month's box is pinned to its own titles only.)
            expect(yearNav, 52);
            expect(list, greaterThan(yearNav));
          }
          expect(list, greaterThanOrEqualTo(yearNav));
          expect(monthNav, greaterThanOrEqualTo(yearNav));
          expect(monthNav, lessThanOrEqualTo(list));
        });
      }

      for (final surface in const [Size(360, 780), Size(412, 915)]) {
        testWidgets('the twelve months fit a ${surface.width.round()} × '
            '${surface.height.round()} phone in Year mode: the chip row, a '
            '52 dp nav and a 26 dp totals line between the bar and the '
            'scroll, December above the fold (D19–D25)', (tester) async {
          final robot = OverviewRobot(tester);
          await robot.open(
            bloc: bloc,
            importExport: importExport,
            mode: AgendaDayListMode.year,
            surface: surface,
          );

          final barBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
          final pagerTop = tester.getTopLeft(find.byType(AgendaYearScroll)).dy;
          final chipRow = robot.modeChipRowExtent;
          expect(robot.navSize.height, 52);
          expect(robot.totalsHeight, 26);
          expect(pagerTop - barBottom, chipRow + 52 + 26);
          if (surface.width > 400) {
            // One run of chips: 134 dp, the record's number. At 360 the test
            // font's square glyphs wrap the chips to a second run, which a
            // phone's font does not (the device pass reads it there).
            expect(chipRow, 56);
            expect(pagerTop - barBottom, 134);
          }
          // Slice 11: this year's section opens at the top, under its header.
          final tiles = robot.yearTiles(year);
          expect(tiles, findsNWidgets(12));
          expect(robot.yearHeaderTop(year), 0);
          // The screen less the 24 dp status bar the test does not draw, and
          // at 360 less the test font's second run of chips (above), which
          // pushes December past the fold here and not on a phone.
          final secondRun = surface.width > 400 ? 0.0 : chipRow - 56;
          expect(
            tester.getBottomLeft(tiles.last).dy - secondRun,
            lessThanOrEqualTo(surface.height - 24),
          );
        });
      }

      for (final mode in AgendaDayListMode.values) {
        testWidgets('the title opens the Period menu under it in ${mode.name} '
            'mode, its tooltip "Period" (D19)', (tester) async {
          final robot = OverviewRobot(tester);
          await robot.open(
            bloc: bloc,
            importExport: importExport,
            mode: mode,
            surface: phone,
          );
          final nav = tester.widget<AgendaPeriodNav>(
            find.byType(AgendaPeriodNav),
          );
          expect(nav.titleTooltip, en.overviewPeriod);
          final title = tester.getRect(
            find.bySemanticsIdentifier(SemanticsIds.overviewNavTitle),
          );

          await robot.openPeriodMenu();

          expect(robot.menuOpen, isTrue);
          final items = find.byType(FormMenuItemRow);
          expect(items, findsNWidgets(OverviewPeriodChoice.values.length));
          expect(
            tester.getTopLeft(items.first).dy,
            greaterThanOrEqualTo(title.bottom),
            reason: 'below the title while it fits',
          );
          final menu = tester.getRect(
            find
                .ancestor(of: items.first, matching: find.byType(Material))
                .first,
          );
          // Centred under the title (D33), never pushed to the screen's left
          // edge by a row's right-alignment rule. The menu's floor is what is
          // centred: a phone's font fits the presets in it, while the test
          // font's square glyphs widen the menu past it, and the extra width
          // grows from the centred floor's left edge.
          expect(menu.left, greaterThanOrEqualTo(RowMetrics.groupInset));
          expect(
            menu.left,
            closeTo(title.center.dx - FormMetrics.menuWidth / 2, 2),
            reason: 'FormMenuAlignment.center centres the floor on its anchor',
          );
          expect(
            menu.center.dx,
            closeTo(
              title.center.dx,
              (menu.width - FormMetrics.menuWidth) / 2 + 2,
            ),
          );
        });
      }

      testWidgets('on a 360 dp phone the Period menu stays inside the '
          'screen\'s margins (D33)', (tester) async {
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
          surface: const Size(360, 780),
        );
        await robot.openPeriodMenu();
        final items = find.byType(FormMenuItemRow);
        final menu = tester.getRect(
          find.ancestor(of: items.first, matching: find.byType(Material)).first,
        );
        expect(menu.left, greaterThanOrEqualTo(RowMetrics.groupInset));
        expect(menu.right, lessThanOrEqualTo(360 - RowMetrics.groupInset));
      });

      testWidgets(
        'a preset picked from the title in Year mode leaves the nav\'s '
        'semantics where the band re-laid it out',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final robot = OverviewRobot(tester);
          await robot.open(
            bloc: bloc,
            importExport: importExport,
            mode: AgendaDayListMode.year,
            surface: const Size(360, 780),
          );

          await robot.pickPeriod(OverviewPeriodChoice.last90Days);
          await tester.pumpAndSettle();

          expect(robot.menuOpen, isFalse);
          for (final id in [
            SemanticsIds.overviewNavNext,
            SemanticsIds.overviewNavTitle,
          ]) {
            final node = find.bySemanticsIdentifier(id);
            final painted = tester.getRect(node);
            final reported = semanticsGlobalRect(
              tester.getSemantics(node),
              tester.view,
            );
            expect(reported.top, closeTo(painted.top, 1), reason: id);
            expect(reported.left, closeTo(painted.left, 1), reason: id);
            expect(reported.bottom, closeTo(painted.bottom, 1), reason: id);
            expect(reported.right, closeTo(painted.right, 1), reason: id);
          }
          semantics.dispose();
        },
        // Open: the nodes report 10 dp above where the band re-laid them
        // out, and FormSheetSemanticsRefresh cannot help a page — a
        // PageRoute's secondary animation never follows a popup route.
        skip: true,
      );

      group('the totals (D16)', () {
        final seeds = CalendarCategories.builtInSeeds;
        String label(int seed) => CalendarCategories.labelOf(
          CalendarCategories.resolve(seeds[seed].id),
          en,
        );

        CalendarEvent once(String id, int seed, int day) => CalendarEvent(
          id: id,
          title: 'Entry $id',
          categoryId: seeds[seed].id,
          startDate: DateTime.utc(year, 1, day),
          rule: const OneTimeRecurrence(),
        );

        /// Five categories, listed against catalog order, the first one's
        /// second day missed: 2 kept + 1 missed, 1, 3, 1, 1.
        void emitFive() {
          EventPresence.updateCache(
            byEvent: {
              't1': {DateTime.utc(year, 1, 2): PresenceStatus.missed},
            },
          );
          emitEvents([
            once('a', 4, 1),
            once('b', 2, 1),
            once('c', 2, 2),
            CalendarEvent(
              id: 't1',
              title: 'Tracked',
              categoryId: seeds[0].id,
              startDate: january,
              endDate: DateTime.utc(year, 1, 3),
              rule: const DailyRecurrence(),
              tracksPresence: true,
            ),
            once('d', 3, 3),
            once('e', 2, 4),
            once('f', 1, 5),
          ]);
        }

        testWidgets('catalog order, three named then "+N more", kept only; '
            'year mode reads the same', (tester) async {
          addTearDown(EventPresence.resetCache);
          emitFive();
          final robot = OverviewRobot(tester);
          await openList(robot);

          final kept =
              '${label(0)} 2 · ${label(1)} 1 · ${label(2)} 3 · '
              '${en.categoriesMore(2)}';
          expect(robot.totals, kept);
          expect(robot.navCount, count(8, missed: 1));

          await robot.selectMode(AgendaDayListMode.year);
          expect(robot.totals, kept);
        });

        testWidgets('under Missed only the totals are the missed ones '
            '(D16a)', (tester) async {
          addTearDown(EventPresence.resetCache);
          emitFive();
          final robot = OverviewRobot(tester);
          await openList(robot);

          await robot.setMissedOnly(true);
          expect(robot.totals, '${label(0)} 1');

          // Year mode's tiles ignore Missed only, and so do its totals.
          await robot.selectMode(AgendaDayListMode.year);
          expect(robot.totals, startsWith('${label(0)} 2 · '));
        });

        testWidgets('the slot is one line and keeps its height from empty to '
            'full and across the three modes (D23)', (tester) async {
          addTearDown(EventPresence.resetCache);
          emitEvents(const []);
          final robot = OverviewRobot(tester);
          await openList(robot, surface: phone);
          final handle = tester.ensureSemantics();
          await tester.pump();
          expect(robot.totals, isEmpty);
          expect(robot.totalsHasNode, isFalse, reason: 'no unlabeled stop');
          final slot = robot.totalsHeight;
          // The group caption's 8 dp over one 18 dp line.
          expect(slot, 26);
          expect(
            tester
                .widget<FormCaption>(
                  find
                      .descendant(
                        of: find.byType(FormCaptionSlot),
                        matching: find.byType(FormCaption),
                      )
                      .last,
                )
                .maxLines,
            1,
          );

          emitFive();
          await tester.pumpAndSettle();
          expect(robot.totals, isNotEmpty);
          expect(robot.totalsHasNode, isTrue);
          handle.dispose();
          expect(robot.totalsHeight, slot);

          for (final mode in [
            AgendaDayListMode.year,
            AgendaDayListMode.month,
          ]) {
            await robot.selectMode(mode);
            expect(robot.totalsHeight, slot, reason: mode.name);
          }
        });
      });
    });

    testWidgets('Custom range… on the year view lists last year, then the '
        'year before; cancelling changes nothing', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      await robot.scrollListTo(2000);

      // The daily series starts this January: last year is empty.
      await robot.pickCustomYear(year - 1);
      expect(robot.rangePickerOpen, isFalse);
      expect(
        robot.periodValue,
        dateSpanLabel(
          en,
          DateTime.utc(year - 1, 1, 1),
          DateTime.utc(year - 1, 12, 31),
        ),
      );
      expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
      expect(robot.shows(robot.emptyPeriodText), isTrue);
      expect(robot.shows('Leg day'), isFalse);
      expect(robot.navCount, count(0));

      await robot.pickCustomYear(year - 2);
      expect(robot.shows('Old checkup'), isTrue);
      expect(robot.listOffset, 0);

      await robot.pickPeriod(OverviewPeriodChoice.custom);
      await robot.cancelRange();
      expect(robot.shows('Old checkup'), isTrue);
      expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
    });

    testWidgets('All time lists every year the events are in, oldest first, '
        'landing on today (D7)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      await robot.scrollListTo(2000);

      await robot.pickPeriod(OverviewPeriodChoice.allTime);

      expect(robot.periodValue, en.overviewPeriodAllTime);
      // Slice 3b: today is inside All time, so the list lands on it rather
      // than at the top.
      expectLandedOn(robot, today);
      await robot.scrollListTo(0);
      // Crossing years, the month labels name theirs.
      expect(
        robot.listTexts.first,
        AgendaListView.monthLabel(
          'en',
          DateTime.utc(year - 2, 6, 1),
          withYear: true,
        ),
      );
      expect(robot.shows('Old checkup'), isTrue);
      // Every day of the daily series up to today, the class if it has
      // happened, the checkup.
      final daily = today.difference(january).inDays + 1;
      final march9 = DateTime.utc(year, 3, 9);
      final classes = today.isBefore(march9) ? 0 : 1;
      expect(robot.navCount, count(daily + classes + 1));
    });

    testWidgets('Last 90 days lists the days ending today, landing on today '
        '(D7)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      await robot.scrollListTo(2000);

      await robot.pickPeriod(OverviewPeriodChoice.last90Days);

      expect(robot.periodValue, en.overviewPeriodLast90Days);
      expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
      // Slice 3b: the span ends today, so the landing is its last day.
      expectLandedOn(robot, today);
      final first = today.subtract(const Duration(days: 89));
      final daily = [
        for (var i = 0; i < 90; i++) first.add(Duration(days: i)),
      ].where((day) => !day.isBefore(january)).length;
      final march9 = DateTime.utc(year, 3, 9);
      final classes = march9.isBefore(first) || march9.isAfter(today) ? 0 : 1;
      expect(robot.navCount, count(daily + classes));
      expect(robot.shows('Old checkup'), isFalse);
    });

    testWidgets('a query change lands the list on today (D7)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      await robot.scrollListTo(2000);

      await robot.typeQuery('leg');

      // Slice 3b: was "at the top"; today is inside this year.
      expectLandedOn(robot, today);
    });

    testWidgets('the search narrows, clearing restores, an empty period says '
        'so', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      await robot.typeQuery('stretch');
      expect(robot.countOf('Stretch class'), 1);
      expect(robot.shows('Leg day'), isFalse);
      expect(robot.navCount, count(1));

      await robot.clearQuery();
      expect(robot.shows('Leg day'), isTrue);
      expect(robot.navCount, count(daysIn(year) + 1));

      await robot.typeQuery('zzz');
      expect(robot.shows(robot.emptyPeriodText), isTrue);
    });

    group('the search button (D21 · A)', () {
      testWidgets('the page opens with the Search row closed; the button '
          'reveals it focused', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);
        expect(robot.searchOpen, isFalse);
        expect(robot.searchSelected, isFalse);

        await robot.openSearch();

        expect(robot.searchOpen, isTrue);
        expect(robot.searchFocused, isTrue);
        expect(robot.searchSelected, isFalse, reason: 'no query yet');
      });

      testWidgets('the row\'s ✕ clears the text and the query and leaves the '
          'row open; the button reads selected while a query is set', (
        tester,
      ) async {
        final robot = OverviewRobot(tester);
        await openList(robot);

        await robot.typeQuery('stretch');
        expect(robot.searchSelected, isTrue);
        expect(robot.shows('Leg day'), isFalse);

        await robot.clearQuery();

        expect(robot.searchOpen, isTrue);
        expect(robot.searchText, isEmpty);
        expect(robot.searchSelected, isFalse);
        expect(robot.shows('Leg day'), isTrue);
      });

      testWidgets('the button again closes the row and clears the query, a '
          'pending keystroke included', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);

        await robot.typeQuery('stretch');
        await robot.closeSearch();

        expect(robot.searchOpen, isFalse);
        expect(robot.searchSelected, isFalse);
        expect(robot.searchFocused, isFalse);
        expect(robot.shows('Leg day'), isTrue);
        expect(robot.navCount, count(daysIn(year) + 1));

        // A word still inside the debounce never applies behind the closed
        // row.
        await robot.typeQuery('stretch', wait: false);
        await robot.closeSearch();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(robot.shows('Leg day'), isTrue);

        await robot.openSearch();
        expect(robot.searchText, isEmpty);
      });
    });

    testWidgets('picking a category narrows the rows', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      await robot.pickCategories({'mobility'});

      expect(robot.shows('Leg day'), isFalse);
      expect(robot.shows('Stretch class'), isTrue);
      expect(robot.navCount, count(1));
    });

    testWidgets('a bloc emit with a new event list redraws the rows', (
      tester,
    ) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      emitEvents([mobilityOnce]);
      await tester.pumpAndSettle();

      expect(robot.shows('Leg day'), isFalse);
      expect(robot.shows('Stretch class'), isTrue);
      // R16: rows that all fall in one month still sit under its header —
      // list mode always heads a month.
      expect(robot.shows('March'), isTrue);
    });

    testWidgets('a presenceRevision bump redraws the rows', (tester) async {
      addTearDown(EventPresence.resetCache);
      emitEvents([rowing, mobilityOnce]);
      final robot = OverviewRobot(tester);
      // Tall enough for both rowing days under the period band (slice 9a).
      await openList(robot, surface: const Size(412, 915));
      // Slice 4: the list opens landed on today (D7); January is the top.
      await robot.scrollListTo(0);
      expect(robot.navCount, count(4));

      markSecondRowingMissed();
      emit(loaded().copyWith(presenceRevision: loaded().presenceRevision + 1));
      await tester.pumpAndSettle();

      expect(robot.navCount, count(3, missed: 1));
      expect(
        robot.entryOpacity('Rowing', index: 1),
        CalendarColors.missedEventAlpha,
      );
    });

    testWidgets('an occurrenceRevision-only emit redraws a live query (R5)', (
      tester,
    ) async {
      addTearDown(OccurrenceDescriptions.resetCache);
      final cardio = CalendarEvent(
        id: 'd1',
        title: 'Cardio',
        categoryId: 'gym',
        startDate: january,
        endDate: DateTime.utc(year, 1, 5),
        rule: const DailyRecurrence(),
        perOccurrenceDescriptions: true,
      );
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'd1': {DateTime.utc(year, 1, 2): 'intervals'},
        },
      );
      emitEvents([cardio, mobilityOnce]);
      final robot = OverviewRobot(tester);
      // Tall enough for both days under the period band (slice 9a).
      await openList(robot, surface: const Size(412, 915));
      await robot.typeQuery('intervals');
      expect(robot.countOf('Cardio'), 1);

      // A second day's text now matches too, and the bloc says so the way a
      // description edit does: occurrenceRevision alone.
      OccurrenceDescriptions.updateCache(
        byEvent: {
          'd1': {
            DateTime.utc(year, 1, 2): 'intervals',
            DateTime.utc(year, 1, 4): 'intervals',
          },
        },
      );
      CalendarEvent.debugOccursOnCalls = 0;
      emit(
        loaded().copyWith(occurrenceRevision: loaded().occurrenceRevision + 1),
      );
      await tester.pumpAndSettle();

      // R5: while a query is live, occurrenceRevision is an input — the
      // second day is found. Slice 3b: by a new matcher over the entries
      // already resolved, not by a rescan (T3).
      expect(robot.countOf('Cardio'), 2);
      expect(CalendarEvent.debugOccursOnCalls, 0);

      // Without a query it is not: nothing the rows show moved.
      await robot.clearQuery();
      CalendarEvent.debugOccursOnCalls = 0;
      emit(
        loaded().copyWith(occurrenceRevision: loaded().occurrenceRevision + 1),
      );
      await tester.pumpAndSettle();
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });

    testWidgets('emits while covered are parked and adopted once on return', (
      tester,
    ) async {
      final swim = CalendarEvent(
        id: 'e9',
        title: 'Swim',
        categoryId: 'gym',
        startDate: january,
        rule: const DailyRecurrence(),
      );
      final robot = OverviewRobot(tester);
      await openList(robot);
      await tester.pump(const Duration(milliseconds: 300));
      await robot.cover();

      CalendarEvent.debugOccursOnCalls = 0;
      emitEvents([mobilityOnce]);
      await tester.pump();
      emitEvents([swim]);
      await tester.pumpAndSettle();
      expect(CalendarEvent.debugOccursOnCalls, 0, reason: 'parked');

      await robot.uncover(settle: false);
      // One year of the daily series, once: only the last emit is adopted.
      expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
      await tester.pumpAndSettle();
      expect(robot.shows('Swim'), isTrue);
      expect(robot.shows('Stretch class'), isFalse);
      expect(robot.shows('Leg day'), isFalse);
    });

    testWidgets('a return with a parked emit and a changed appearance rebuilds '
        'once (R15)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      await tester.pump(const Duration(milliseconds: 300));
      await robot.cover();

      emitEvents([gymDaily]);
      final settings = await SettingsService.getInstance();
      await settings.setCalendarAccentColor(0xFF00897B);
      await tester.pumpAndSettle();
      CalendarEvent.debugOccursOnCalls = 0;

      await robot.uncover();

      // One year of the daily series, once — not once per change.
      expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
      expect(robot.shows('Stretch class'), isFalse);
    });

    testWidgets('a query typed just before a cover applies on the return, '
        'never underneath (R19)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      await tester.pump(const Duration(milliseconds: 300));

      // A query the daily series matches, so applying it scans the year.
      CalendarEvent.debugOccursOnCalls = 0;
      await robot.typeQuery('leg', wait: false);
      await robot.cover();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        CalendarEvent.debugOccursOnCalls,
        0,
        reason: 'nothing ran beneath',
      );

      await robot.uncover();

      // Slice 3b: the query is a post-filter (T3), so applying it on the
      // return refilters the year already resolved and scans nothing.
      expect(CalendarEvent.debugOccursOnCalls, 0);
      expect(robot.shows('Leg day'), isTrue);
      expect(robot.shows('Stretch class'), isFalse);
    });

    testWidgets('a fling, then a mode switch inside the cross-fade (R3)', (
      tester,
    ) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      final errors = await layoutErrorsDuring(() async {
        await robot.flingList();
        await tester.pump(const Duration(milliseconds: 16));
        await robot.selectMode(AgendaDayListMode.year, settle: false);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
      });

      // R3: the outgoing list still flings while it fades, and builds its
      // rows from the list it was built with, never from the year mode's.
      expect(errors, isEmpty);
      expect(robot.currentMode, AgendaDayListMode.year);
    });

    group("a digest's look (v42, D13)", () {
      final march = OverviewCustomPeriod(
        DateTime.utc(year, 3, 1),
        DateTime.utc(year, 3, 31),
      );

      void publishMarch() {
        AppNavigator.pendingOverviewLook.value = (
          start: march.start,
          end: march.end,
          categoryIds: const {'mobility'},
        );
      }

      setUp(() => AppNavigator.pendingOverviewLook.value = null);
      tearDown(() => AppNavigator.pendingOverviewLook.value = null);

      testWidgets('is served once: the list on the span over the allowlist, '
          'the mode and the allowlist kept, the period the user kept left '
          'alone', (tester) async {
        const last90Days = OverviewRollingPeriod(
          OverviewRollingPreset.last90Days,
        );
        final settings = await SettingsService.getInstance();
        await settings.setCalendarOverviewCategories({'gym'});
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.year,
          period: last90Days,
        );

        publishMarch();
        await tester.pumpAndSettle();

        expect(AppNavigator.pendingOverviewLook.value, isNull);
        expect(robot.currentMode, AgendaDayListMode.list);
        expect(robot.periodValue, march.menuValue(en));
        expect(robot.shows('Stretch class'), isTrue);
        expect(robot.shows('Leg day'), isFalse);

        final stored = await settings.getCalendarOverviewSettings();
        expect(stored.mode, AgendaDayListMode.list);
        expect(stored.categoryIds, {'mobility'});
        expect(
          stored.period,
          last90Days,
          reason: 'a look writes no period: the kept one survives the tap',
        );
      });

      testWidgets('drops a typed query and Missed only, and keeps Order and '
          'Rows as they were', (tester) async {
        const options = OverviewListOptions(
          order: OverviewOrder.newestFirst,
          rows: OverviewRows.everyOccurrence,
        );
        final robot = OverviewRobot(tester);
        await openList(robot);
        await robot.setOrder(options.order);
        await robot.setMissedOnly(true);
        await robot.typeQuery('Leg');

        publishMarch();
        await tester.pumpAndSettle();

        expect(robot.searchText, isEmpty);
        expect(robot.shows('Stretch class'), isTrue);
        await robot.openOptions();
        expect(robot.options.missedOnly, isFalse);
        expect(robot.options.order, OverviewOrder.newestFirst);
        expect(robot.options.rows, OverviewRows.everyOccurrence);
        await robot.options.close();
        final stored = await (await SettingsService.getInstance())
            .getCalendarOverviewSettings();
        expect(stored.listOptions.order, OverviewOrder.newestFirst);
      });

      testWidgets('published before the settings load, it wins over them', (
        tester,
      ) async {
        final settings = await SettingsService.getInstance();
        await settings.setCalendarOverviewCategories({'gym'});
        publishMarch();

        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.year,
          period: const OverviewRollingPeriod(
            OverviewRollingPreset.last90Days,
          ),
        );
        await tester.pumpAndSettle();

        expect(AppNavigator.pendingOverviewLook.value, isNull);
        expect(robot.currentMode, AgendaDayListMode.list);
        expect(robot.periodValue, march.menuValue(en));
        expect(robot.shows('Stretch class'), isTrue);
        expect(robot.shows('Leg day'), isFalse);
        expect(
          (await settings.getCalendarOverviewSettings()).categoryIds,
          {'mobility'},
        );
      });

      testWidgets('a tap with an overview under another page collapses onto '
          'it and lands the look there, pushing no second one', (tester) async {
        final robot = OverviewRobot(tester);
        await robot.openFromDrawer(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.year,
        );
        await robot.cover();
        expect(robot.isOpen, isFalse);

        unawaited(
          AppNavigator.toCalendarOverviewLook(
            start: march.start,
            end: march.end,
            categoryIds: const {'mobility'},
          ),
        );
        await tester.pumpAndSettle();

        expect(robot.isOpen, isTrue);
        expect(find.text('covering'), findsNothing);
        expect(
          find.byType(CalendarOverviewPage, skipOffstage: false),
          findsOneWidget,
        );
        expect(AppNavigator.pendingOverviewLook.value, isNull);
        expect(robot.currentMode, AgendaDayListMode.list);
        expect(robot.periodValue, march.menuValue(en));
      });

      testWidgets('a tap with no overview open pushes one, stamped to restore '
          'like the drawer\'s, which serves the look', (tester) async {
        await tester.pumpWidget(
          app(
            navigatorKey: AppNavigator.navigatorKey,
            home: const Scaffold(body: Text('root')),
          ),
        );

        unawaited(
          AppNavigator.toCalendarOverviewLook(
            start: march.start,
            end: march.end,
            categoryIds: const {'mobility'},
          ),
        );
        await pumpUntilLoaded(tester);
        await tester.pumpAndSettle();

        final robot = OverviewRobot(tester);
        expect(robot.isOpen, isTrue);
        final top = AppNavigator.routeObserver.pageRoutes.lastWhere(
          (route) => route.isActive,
        );
        expect(
          top.settings.arguments,
          const NavDestination(NavDestinationKind.calendarOverview),
        );
        expect(AppNavigator.pendingOverviewLook.value, isNull);
        expect(robot.currentMode, AgendaDayListMode.list);
        expect(robot.periodValue, march.menuValue(en));
        expect(robot.shows('Stretch class'), isTrue);
      });
    });

    group('saved views (slice 9c, D17)', () {
      const last90Days = OverviewRollingPeriod(
        OverviewRollingPreset.last90Days,
      );
      const last12Months = OverviewRollingPeriod(
        OverviewRollingPreset.last12Months,
      );

      Future<String> seedView({
        required OverviewPeriod period,
        OverviewListOptions options = OverviewListOptions.defaults,
        Set<String> categoryIds = const {},
      }) async {
        final service = await OverviewViewService.getInstance();
        final view = await service.create(
          name: 'Saved',
          period: period,
          options: options,
          categoryIds: categoryIds,
        );
        return view!.id;
      }

      testWidgets('the bookmarks button sits between the tune button and the '
          '⋮, live and unselected with nothing saved', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);

        expect(robot.hasViewsButton, isTrue);
        expect(robot.viewsEnabled, isTrue);
        expect(robot.viewsSelected, isFalse);
        expect(
          robot.barButtonLeft(SemanticsIds.overviewOptionsOpen),
          lessThan(robot.barButtonLeft(SemanticsIds.overviewViewsOpen)),
        );
      });

      testWidgets('selected while the list shown is a saved view, and not '
          'once it is another', (tester) async {
        await seedView(period: last90Days);
        final robot = OverviewRobot(tester);
        await openList(robot, period: last90Days);

        expect(robot.viewsSelected, isTrue);

        await robot.pickPeriod(OverviewPeriodChoice.thisYear);
        await tester.pumpAndSettle();

        expect(robot.viewsSelected, isFalse);
      });

      testWidgets('applying a custom span from Year mode lists it with the '
          "view's options and categories, persists each as a pick would, "
          'and leaves the query as typed', (tester) async {
        final settings = await SettingsService.getInstance();
        final march = OverviewCustomPeriod(
          DateTime.utc(year, 3, 1),
          DateTime.utc(year, 3, 31),
        );
        const options = OverviewListOptions(
          order: OverviewOrder.newestFirst,
          rows: OverviewRows.perEvent,
        );
        final id = await seedView(
          period: march,
          options: options,
          categoryIds: {'gym'},
        );
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.year,
          period: last12Months,
        );
        await robot.typeQuery('Leg');

        await robot.applyView(id);
        await tester.pumpAndSettle();

        expect(robot.currentMode, AgendaDayListMode.list);
        expect(robot.periodValue, march.menuValue(en));
        expect(robot.viewsSelected, isTrue);
        expect(robot.searchText, 'Leg');
        expect(robot.shows('Leg day'), isTrue);
        expect(robot.shows('Stretch class'), isFalse);

        final stored = await settings.getCalendarOverviewSettings();
        expect(stored.mode, AgendaDayListMode.list);
        expect(
          stored.period,
          OverviewYearPeriod(year),
          reason: 'a custom span clears the period key (D4)',
        );
        expect(stored.listOptions.order, OverviewOrder.newestFirst);
        expect(stored.listOptions.rows, OverviewRows.perEvent);
        expect(stored.categoryIds, {'gym'});
      });

      testWidgets('applying a preset persists it', (tester) async {
        final settings = await SettingsService.getInstance();
        final id = await seedView(period: last90Days);
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.year,
        );

        await robot.applyView(id);
        await tester.pumpAndSettle();

        expect(robot.currentMode, AgendaDayListMode.list);
        expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
        expect(robot.viewsSelected, isTrue);
        final stored = await settings.getCalendarOverviewSettings();
        expect(stored.mode, AgendaDayListMode.list);
        expect(stored.period, last90Days);
      });
    });

    group('scan budgets', () {
      /// One retroactive daily series: every year the page scans costs
      /// exactly that year's days in `occursOn` calls, so each budget reads
      /// as a count of year scans.
      final everyDay = CalendarEvent(
        id: 'b1',
        title: 'Leg day',
        categoryId: 'gym',
        startDate: january,
        rule: const DailyRecurrence(),
        retroactive: true,
      );

      setUp(() => emitEvents([everyDay]));

      testWidgets('opening the list scans the year once, and no year run '
          'follows (R7)', (tester) async {
        CalendarEvent.debugOccursOnCalls = 0;
        await openList(OverviewRobot(tester));
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));

        // R7: the list has no years to scroll through, so none is resolved.
        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
      });

      testWidgets('opening Year draws its first frame on the top year alone, '
          'scanned once, with at most three sections built; the two '
          'neighbours follow one per frame (R7, D30, slice 12)', (
        tester,
      ) async {
        emitEvents(const []);
        AgendaMonthStore? store;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: const Size(412, 915),
          onStore: (resolved) => store = resolved,
        );
        await robot.finishResolving();
        int resolvedYears() => [
          for (var shown = year - 3; shown <= year + 3; shown++)
            if (store!.cachedTally(DateTime.utc(shown, 6, 1)) != null) shown,
        ].length;

        CalendarEvent.debugOccursOnCalls = 0;
        emitEvents([everyDay]);
        // Registered before the page's own: reads what the frame was drawn
        // from, before any run that follows it.
        final atFirstFrame = <int>[];
        tester.binding.addPostFrameCallback(
          (_) => atFirstFrame.add(CalendarEvent.debugOccursOnCalls),
        );
        await tester.pump();

        expect(atFirstFrame, [daysIn(year)]);
        expect(robot.builtYears, hasLength(lessThanOrEqualTo(3)));
        expect(robot.yearHeaderTop(year), 0);
        expect(robot.navCount, count(daysIn(year)));

        // Frame by frame from there: at most one year more per frame, the
        // two neighbours in two frames, then nothing — and none in the
        // frame that drew the top year's scan (R7): the first neighbour
        // waits for the frame after it.
        final perFrame = [resolvedYears()];
        for (var frame = 0; frame < 4; frame++) {
          await robot.pumpYearRun();
          perFrame.add(resolvedYears());
        }
        for (var frame = 1; frame < perFrame.length; frame++) {
          expect(
            perFrame[frame] - perFrame[frame - 1],
            lessThanOrEqualTo(1),
            reason: 'frame $frame: $perFrame',
          );
        }
        expect(perFrame.take(3), [1, 2, 3], reason: '$perFrame');
        expect(perFrame.last, 3);
        expect(
          CalendarEvent.debugOccursOnCalls,
          daysIn(year - 1) + daysIn(year) + daysIn(year + 1),
        );
      });

      testWidgets('the keyboard folding the chip row frame by frame in Year '
          'mode rebuilds no tile and scans nothing (slice 12)', (tester) async {
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: const Size(412, 915),
        );
        await robot.finishResolving();
        await robot.focusSearch();
        await tester.pumpAndSettle();
        await robot.finishResolving();
        final full = robot.modeChipRowExtent;
        expect(full, greaterThan(0));

        CalendarEvent.debugOccursOnCalls = 0;
        var tileBuilds = 0;
        debugOnRebuildDirtyWidget = (element, _) {
          if (element.widget is YearMonthTile) tileBuilds++;
        };
        addTearDown(tester.view.resetViewInsets);
        try {
          for (var frame = 1; frame <= 12; frame++) {
            tester.view.viewInsets = FakeViewPadding(bottom: 30.0 * frame);
            await tester.pump(const Duration(milliseconds: 16));
          }
        } finally {
          debugOnRebuildDirtyWidget = null;
        }

        expect(robot.modeChips, isEmpty, reason: 'the chips folded');
        expect(CalendarEvent.debugOccursOnCalls, 0);
        expect(tileBuilds, 0);
        expect(robot.yearHeaderTop(year), 0);
      });

      testWidgets('Today from 26 years back resolves only its target on the '
          'way, then the target\'s neighbours once it lands (slice 12)', (
        tester,
      ) async {
        AgendaMonthStore? store;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: const Size(412, 915),
          onStore: (resolved) => store = resolved,
        );
        await robot.finishResolving();
        await robot.jumpYearsTo(
          robot.yearsOffset - 26 * robot.yearSectionExtent,
        );
        await robot.finishResolving();
        expect(robot.navTitle, '${year - 26}');
        // A new store with the scroll back there: only what is shown there
        // is resolved. (An equal state would not be emitted at all.)
        emitEvents([everyDay.copyWith(title: 'Leg day, renamed')]);
        await tester.pumpAndSettle();
        await robot.finishResolving();
        bool resolvedYear(int shown) =>
            store!.cachedTally(DateTime.utc(shown, 6, 1)) != null;
        expect(resolvedYear(year), isFalse);

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.today(settle: false);
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
        final titles = <String>{};
        final frames = OverviewListMetrics.pageDuration.inMilliseconds ~/ 16;
        for (var frame = 1; frame < frames; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          titles.add(robot.navTitle);
          expect(
            CalendarEvent.debugOccursOnCalls,
            daysIn(year),
            reason: 'frame $frame, at ${robot.navTitle}',
          );
        }
        expect(titles.length, greaterThan(2), reason: 'the title followed');
        for (var passed = year - 24; passed < year - 1; passed++) {
          expect(resolvedYear(passed), isFalse, reason: '$passed');
        }

        await tester.pumpAndSettle();
        await robot.finishResolving();
        expect(robot.navTitle, '$year');
        expect(resolvedYear(year - 1), isTrue);
        expect(resolvedYear(year + 1), isTrue);
        expect(
          CalendarEvent.debugOccursOnCalls,
          daysIn(year - 1) + daysIn(year) + daysIn(year + 1),
        );
      });

      testWidgets('a keystroke under a live query in Year mode scans nothing, '
          'and its one frame turns every shown count, none blank (slice 12)', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: const Size(412, 915),
        );
        await robot.finishResolving();
        await robot.typeQuery('leg');
        await robot.finishResolving();
        String header(int shown) => tester
            .getSemantics(
              find.bySemanticsIdentifier(
                SemanticsIds.overviewYearHeader(shown),
              ),
            )
            .label;
        final built = robot.builtYears;
        expect(built, contains(year));
        for (final shown in built) {
          expect(header(shown), '$shown, ${count(daysIn(shown))}');
        }

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.typeQuery('legs', wait: false);
        // The debounce, then the one frame it asks for.
        await tester.pump(OverviewListMetrics.searchDebounce);

        expect(CalendarEvent.debugOccursOnCalls, 0);
        expect(robot.builtYears, built);
        for (final shown in built) {
          expect(header(shown), '$shown, ${count(0)}');
        }
        expect(robot.navCount, count(0));
        semantics.dispose();
      });

      testWidgets('a fling across unresolved years resolves only what the '
          'viewport shows when each run fires', (tester) async {
        AgendaMonthStore? store;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: const Size(412, 915),
          onStore: (resolved) => store = resolved,
        );
        await robot.finishResolving();
        await tester.pumpAndSettle();
        final extent = robot.yearSectionExtent;
        final base = robot.yearsOffset;
        double offsetOf(int target) => base + (target - year) * extent;
        bool resolvedYear(int target) =>
            store!.cachedTally(DateTime.utc(target, 6, 1)) != null;

        // A fast fling's frames, ten years apart: each frame's run, at its
        // end, resolves the year that frame put at the top and nothing it
        // only showed beside it; the years between frames are never seen.
        CalendarEvent.debugOccursOnCalls = 0;
        await robot.jumpYearsTo(offsetOf(year - 10), settle: false);
        expect(
          CalendarEvent.debugOccursOnCalls,
          daysIn(year - 10),
          reason: 'one year at the end of the frame, none inside it',
        );
        await robot.jumpYearsTo(offsetOf(year - 20), settle: false);
        await robot.jumpYearsTo(offsetOf(year - 30), settle: false);
        expect(robot.navTitle, '${year - 30}');

        await robot.finishResolving();

        for (final passed in [year - 11, year - 9, year - 21, year - 19]) {
          expect(resolvedYear(passed), isFalse, reason: '$passed');
        }
        // The two frames' tops, then what the viewport shows once the runs
        // catch up, with the top year's neighbours.
        final shownOnTheWay = [year - 20, year - 10];
        final landed = [year - 31, year - 30, year - 29];
        for (final shown in [...shownOnTheWay, ...landed]) {
          expect(resolvedYear(shown), isTrue, reason: '$shown');
        }
        expect(
          CalendarEvent.debugOccursOnCalls,
          [...shownOnTheWay, ...landed].map(daysIn).reduce((a, b) => a + b),
        );
        expect(robot.navCount, count(daysIn(year - 30)));
      });

      testWidgets('a keystroke pause scans nothing, and no run follows '
          '(T3, R7)', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);
        await tester.pump(const Duration(milliseconds: 300));

        // Slice 3b: was one year scan per keystroke; the query now filters
        // the entries the store holds.
        CalendarEvent.debugOccursOnCalls = 0;
        await robot.typeQuery('leg');
        expect(CalendarEvent.debugOccursOnCalls, 0);
        expect(robot.shows('Leg day'), isTrue);

        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, 0);
      });

      testWidgets('a keystroke pause in month mode scans nothing (T3)', (
        tester,
      ) async {
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.month,
        );
        await tester.pump(const Duration(milliseconds: 300));

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.typeQuery('leg');
        await robot.typeQuery('le');
        expect(CalendarEvent.debugOccursOnCalls, 0);
      });

      testWidgets('in year mode the first query resolves the year\'s entries '
          'once; every later query change scans nothing (T3)', (tester) async {
        final robot = OverviewRobot(tester);
        await robot.open(bloc: bloc, importExport: importExport);
        await tester.pump(const Duration(milliseconds: 300));

        // The tiles were folded from marks; a search needs the rows — the
        // shown year's with the frame, the two neighbours' in the runs —
        // the first of them a frame after the one that drew the shown
        // year's scan (R7).
        CalendarEvent.debugOccursOnCalls = 0;
        await robot.typeQuery('leg');
        await robot.finishResolving();
        expect(
          CalendarEvent.debugOccursOnCalls,
          daysIn(year - 1) + daysIn(year) + daysIn(year + 1),
        );

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.typeQuery('le');
        await robot.typeQuery('zzz');
        expect(CalendarEvent.debugOccursOnCalls, 0);
        expect(robot.navCount, count(0));
      });

      testWidgets('a preset scans only the months it adds, and no run '
          'follows (R7)', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);
        await tester.pump(const Duration(milliseconds: 300));

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.pickPeriod(OverviewPeriodChoice.last12Months);
        // This year's months are resolved already; only last year's tail is
        // new.
        final start = today.subtract(const Duration(days: 364));
        var added = 0;
        for (
          var month = DateTime.utc(start.year, start.month, 1);
          month.year < year;
          month = DateTime.utc(month.year, month.month + 1, 1)
        ) {
          added += DateTime.utc(month.year, month.month + 1, 0).day;
        }
        expect(CalendarEvent.debugOccursOnCalls, added);

        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, added);
      });

      testWidgets('a rolling period resolves no year in the list; the switch '
          'to the year tiles costs exactly the top year and its two '
          'neighbours, then nothing more (R7)', (tester) async {
        AgendaMonthStore? store;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
          period: const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
          onStore: (resolved) => store = resolved,
        );
        CalendarEvent.debugOccursOnCalls = 0;
        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, 0);
        // The months the list resolved are counted from their rows.
        final listed = {
          for (
            var month = AgendaMonthStore.monthOf(
              today.subtract(const Duration(days: 89)),
            );
            !month.isAfter(today);
            month = DateTime.utc(month.year, month.month + 1, 1)
          )
            AgendaMonthStore.keyOf(month),
        };

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.selectMode(AgendaDayListMode.year);
        await robot.finishResolving();
        final shown = today.subtract(const Duration(days: 89)).year;
        expect(robot.navTitle, '$shown');
        var expected = 0;
        for (final resolved in [shown - 1, shown, shown + 1]) {
          for (final month in AgendaMonthStore.monthsOfYear(resolved)) {
            if (listed.contains(AgendaMonthStore.keyOf(month))) continue;
            expected += DateTime.utc(resolved, month.month + 1, 0).day;
          }
          expect(
            store!.cachedTally(DateTime.utc(resolved, 6, 1)),
            isNotNull,
            reason: '$resolved',
          );
        }
        expect(CalendarEvent.debugOccursOnCalls, expected);
        CalendarEvent.debugOccursOnCalls = 0;
        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, 0);
      });

      testWidgets('the first frame after a switch into Year shows the year\'s '
          'header at the top, and no jump follows (slice 12)', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot, surface: const Size(412, 915));
        await robot.finishResolving();

        await robot.selectMode(AgendaDayListMode.year, settle: false);
        expect(robot.yearHeaderTop(year), 0);
        final offset = robot.yearsOffset;
        await tester.pumpAndSettle();
        await robot.finishResolving();
        expect(robot.yearsOffset, offset);
        expect(robot.yearHeaderTop(year), 0);
      });

      testWidgets('Year → List → Year scans the year\'s entries once', (
        tester,
      ) async {
        final robot = OverviewRobot(tester);
        await robot.open(bloc: bloc, importExport: importExport);
        await tester.pump(const Duration(milliseconds: 300));

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.selectMode(AgendaDayListMode.list);
        await robot.selectMode(AgendaDayListMode.year);
        await tester.pump(const Duration(milliseconds: 300));

        expect(robot.currentMode, AgendaDayListMode.year);
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
      });
    });

    /// An alarm's Open event over the overview: the alert path still pushes
    /// a calendar over it, which a row tap no longer does (D14 · A).
    Future<void> openOccurrenceFromAlert(
      WidgetTester tester,
      OverviewRobot robot,
    ) async {
      unawaited(AppNavigator.toCalendarOccurrence(day: today, eventId: 'e1'));
      // Frames rather than a settle: the pushed calendar's own loading need
      // not settle for this.
      for (var i = 0; i < 60 && robot.isOpen; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('a row tap with the calendar beneath opens the detail sheet '
        'over the overview; back returns to the list (R1, D14)', (
      tester,
    ) async {
      final history = NavigationHistoryService();
      addTearDown(history.dispose);
      const restorable = [
        NavDestination(NavDestinationKind.calendar),
        NavDestination(NavDestinationKind.calendarOverview),
      ];
      final robot = OverviewRobot(tester);
      await robot.openAboveCalendar(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.list,
        observers: [NavigationHistoryObserver(history)],
      );
      await robot.pickPeriod(OverviewPeriodChoice.last90Days);
      expect(history.stack, restorable);

      await robot.tapRow('Leg day');

      expect(robot.detailSheet!.event.id, 'e1');
      expect(find.byType(CalendarPage), findsNothing);
      expect(AppNavigator.pendingCalendarOccurrence.value, isNull);
      expect(history.stack, restorable);

      await robot.back();

      expect(robot.detailSheet, isNull);
      expect(robot.isOpen, isTrue);
      expect(robot.currentMode, AgendaDayListMode.list);
      expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
      expect(robot.calendarBeneathVisible, isFalse);
      expect(history.stack, restorable);
    });

    testWidgets('a second trip to an occurrence opens it on the calendar '
        'pushed over the overview, stacking nothing', (tester) async {
      addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
      final robot = OverviewRobot(tester);
      await robot.openAboveCalendar(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.list,
      );
      await openOccurrenceFromAlert(tester, robot);
      await tester.pumpAndSettle();
      // The pushed calendar's own sheet for the tapped row.
      await robot.back();
      expect(find.byType(EventDetailSheet), findsNothing);
      int liveRoutes() => AppNavigator.routeObserver.pageRoutes
          .where((route) => route.isActive)
          .length;
      final routes = liveRoutes();

      await AppNavigator.toCalendarOccurrence(
        day: DateTime.utc(year, 3, 9),
        eventId: 'e2',
      );
      await tester.pumpAndSettle();

      expect(AppNavigator.pendingCalendarOccurrence.value, isNull);
      expect(liveRoutes(), routes);
      expect(
        find.byType(CalendarPage, skipOffstage: false),
        findsOneWidget,
        reason: 'no second calendar pushed',
      );
      expect(robot.isAlive, isTrue);
      expect(
        tester.widget<EventDetailSheet>(find.byType(EventDetailSheet)).event.id,
        'e2',
      );
    });

    testWidgets('with a real calendar beneath and the pushed one on top, only '
        'the top one serves a trip: the one beneath declines it (review 19)', (
      tester,
    ) async {
      addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
      // The calendar beneath reads a bloc of its own that holds no events:
      // had it served the trip, it would have had nothing to open.
      final beneathBloc = CalendarBloc(
        service: Completer<CalendarEventService>().future,
      );
      addTearDown(beneathBloc.close);
      // ignore: invalid_use_of_visible_for_testing_member
      beneathBloc.emit(
        CalendarPageLoaded(
          allEvents: const [],
          focusedDay: today,
          selectedDay: today,
        ),
      );
      final robot = OverviewRobot(tester);
      await robot.openAboveCalendar(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.list,
        calendar: BlocProvider<CalendarBloc>.value(
          value: beneathBloc,
          child: const CalendarPage(),
        ),
      );
      await openOccurrenceFromAlert(tester, robot);
      await tester.pumpAndSettle();
      await robot.back();
      expect(find.byType(EventDetailSheet), findsNothing);
      expect(find.byType(CalendarPage, skipOffstage: false), findsNWidgets(2));

      await AppNavigator.toCalendarOccurrence(
        day: DateTime.utc(year, 3, 9),
        eventId: 'e2',
      );
      await tester.pumpAndSettle();

      expect(AppNavigator.pendingCalendarOccurrence.value, isNull);
      expect(find.byType(EventDetailSheet), findsOneWidget);
      expect(
        tester.widget<EventDetailSheet>(find.byType(EventDetailSheet)).event.id,
        'e2',
      );
      expect(robot.isAlive, isTrue);
    });

    testWidgets('from the drawer, with no calendar beneath, an alert pushes '
        'the named calendar over the overview, unstamped (review 3)', (
      tester,
    ) async {
      addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
      final history = NavigationHistoryService();
      addTearDown(history.dispose);
      const restorable = [NavDestination(NavDestinationKind.calendarOverview)];
      final robot = OverviewRobot(tester);
      await robot.openFromDrawer(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.list,
        observers: [NavigationHistoryObserver(history)],
      );
      expect(history.stack, restorable);

      await openOccurrenceFromAlert(tester, robot);

      final route = ModalRoute.of(tester.element(find.byType(CalendarPage)))!;
      expect(route.settings.name, AppNavigator.occurrenceCalendarRouteName);
      expect(route.settings.arguments, isNull);
      expect(robot.isAlive, isTrue, reason: 'the overview survives beneath');
      expect(history.stack, restorable);

      await tester.pumpAndSettle();
      expect(find.byType(EventDetailSheet), findsOneWidget);
      await robot.back();
      await robot.back();

      expect(find.byType(CalendarPage), findsNothing);
      expect(robot.isOpen, isTrue);
      expect(history.stack, restorable);
    });

    testWidgets('the options sheet\'s categories row reads back All, two '
        'names, then "+N more" (D22)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.overviewCategories),
        findsNothing,
        reason: 'not on the page',
      );
      expect(await robot.categoriesValue(), en.calendarFilterCategoriesAll);

      final catalog = CalendarCategories.visiblePlus(const {});
      List<String> labelsOf(Set<String> ids) => [
        for (final category in catalog)
          if (ids.contains(category.id))
            CalendarCategories.labelOf(category, en),
      ];

      await robot.pickCategories({'gym', 'mobility'});
      expect(
        await robot.categoriesValue(),
        labelsOf({'gym', 'mobility'}).join(', '),
      );

      await robot.pickCategories({'gym', 'mobility', 'other'});
      final three = labelsOf({'gym', 'mobility', 'other'});
      expect(
        await robot.categoriesValue(),
        '${three[0]}, ${three[1]} ${en.categoriesMore(1)}',
      );
    });

    testWidgets('the tune badge counts the categories allowlist in every '
        'mode, and a pick over the sheet applies at once (D22)', (
      tester,
    ) async {
      final settings = await SettingsService.getInstance();
      final robot = OverviewRobot(tester);
      await openList(robot);
      expect(robot.optionsBadge, isNull);

      await robot.openOptions();
      await robot.options.pickCategories({'mobility'});
      expect(robot.options.isOpen, isTrue, reason: 'the sheet stays up');
      await robot.options.close();

      expect(robot.shows('Leg day'), isFalse);
      expect(robot.shows('Stretch class'), isTrue);
      expect((await settings.getCalendarOverviewSettings()).categoryIds, {
        'mobility',
      });
      for (final mode in AgendaDayListMode.values) {
        await robot.selectMode(mode);
        expect(robot.optionsBadge, '1', reason: mode.name);
        expect(robot.optionsSelected, isTrue, reason: mode.name);
      }

      // Missed only is inert in Year mode (D33), so it is set from the list.
      await robot.selectMode(AgendaDayListMode.list);
      await robot.setMissedOnly(true);
      expect(robot.optionsBadge, '2');
    });

    /// The badge rides the glyph, not the button: around the button Material
    /// puts it 4 dp above, which the 48 dp bar's toolbar clip cuts off. The
    /// painted pill is measured, not its text, at the scale where the slack
    /// is 9 dp and at 2.0 where it is about 1 dp; and the count stays out of
    /// the button's spoken name (Android 9+ would announce it instead of the
    /// tooltip).
    Future<void> badgeInsideBar(WidgetTester tester, double textScale) async {
      final semantics = tester.ensureSemantics();
      final robot = OverviewRobot(tester);
      await openList(
        robot,
        textScale: textScale,
        surface: const Size(412, 915),
      );
      await robot.openOptions();
      await robot.options.pickCategories({'mobility'});
      await robot.options.close();
      expect(robot.optionsBadge, '1');

      final pill = robot.optionsBadgeRect;
      final bar = tester.getRect(find.byType(AppBar));
      expect(pill.top, greaterThanOrEqualTo(bar.top));
      expect(pill.bottom, lessThanOrEqualTo(bar.bottom));
      expect(robot.optionsSemanticsLabel, isNot('1'));
      semantics.dispose();
    }

    testWidgets('the tune badge stays inside the 48 dp bar', (tester) async {
      await badgeInsideBar(tester, 1.0);
    });

    testWidgets('the tune badge stays inside the 48 dp bar at text scale 2.0', (
      tester,
    ) async {
      await badgeInsideBar(tester, 2.0);
    });

    testWidgets('a preset period persists; a custom span clears it', (
      tester,
    ) async {
      final settings = await SettingsService.getInstance();
      final robot = OverviewRobot(tester);
      await openList(robot);

      await robot.pickPeriod(OverviewPeriodChoice.last12Months);
      await tester.pumpAndSettle();
      expect(
        (await settings.getCalendarOverviewSettings()).period,
        const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
      );

      await robot.pickCustomMonth(DateTime.utc(year, 3, 1));
      await tester.pumpAndSettle();
      expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
      // March: the daily series' 31 days and the class.
      expect(robot.navCount, count(32));
      expect(
        (await settings.getCalendarOverviewSettings()).period,
        OverviewYearPeriod(year),
        reason: 'the key is cleared, so the next visit opens on this year',
      );
    });

    testWidgets('This year picked after paging back to this year is persisted '
        '(review 1)', (tester) async {
      final settings = await SettingsService.getInstance();
      const last90Days = OverviewRollingPeriod(
        OverviewRollingPreset.last90Days,
      );
      final robot = OverviewRobot(tester);
      await robot.open(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.year,
        period: last90Days,
      );
      // Paging sets the shown year as the period without writing it.
      await robot.previous();
      await robot.next();
      expect(robot.navTitle, '$year');
      expect((await settings.getCalendarOverviewSettings()).period, last90Days);

      await robot.pickPeriod(OverviewPeriodChoice.thisYear);
      await tester.pumpAndSettle();

      expect(
        (await settings.getCalendarOverviewSettings()).period,
        OverviewYearPeriod(year),
      );
    });

    testWidgets('Newest first reverses the days, keeps each day\'s entries in '
        'order, lands at the top and persists', (tester) async {
      emitEvents([rowing, mobilityOnce]);
      final robot = OverviewRobot(tester);
      await openList(robot, surface: const Size(412, 915));

      await robot.setOrder(OverviewOrder.newestFirst);

      expect(robot.listOffset, 0);
      expect(
        robot.listTexts,
        containsAllInOrder([
          'March',
          dayLabel(DateTime.utc(year, 3, 9)),
          'Stretch class',
          'January',
          dayLabel(DateTime.utc(year, 1, 3)),
          dayLabel(DateTime.utc(year, 1, 2)),
        ]),
      );
      // Slice 8a: the mode chips leave the first of January just below.
      await robot.scrollListTo(robot.listMaxOffset);
      expect(
        robot.listTexts,
        containsAllInOrder([
          dayLabel(DateTime.utc(year, 1, 2)),
          dayLabel(january),
        ]),
      );
      final settings = await SettingsService.getInstance();
      expect(
        (await settings.getCalendarOverviewSettings()).listOptions.order,
        OverviewOrder.newestFirst,
      );
    });

    testWidgets('Rows is kept for the next visit', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      await robot.setRows(OverviewRows.perEvent);

      final settings = await SettingsService.getInstance();
      expect(
        (await settings.getCalendarOverviewSettings()).listOptions.rows,
        OverviewRows.perEvent,
      );
    });

    testWidgets('Missed only narrows the list and month mode\'s rows, badges '
        'the tune button, and is not kept', (tester) async {
      addTearDown(EventPresence.resetCache);
      markSecondRowingMissed();
      emitEvents([rowing, mobilityOnce]);
      final robot = OverviewRobot(tester);
      // A phone again: slice 3b's picked-day row fits where the old section
      // header overflowed by 25 px at this width.
      await openList(robot, surface: const Size(412, 915));
      expect(robot.optionsBadge, isNull);

      await robot.setMissedOnly(true);

      expect(robot.optionsBadge, '1');
      expect(robot.countOf('Rowing'), 1);
      expect(robot.shows('Stretch class'), isFalse);
      expect(robot.shows(dayLabel(january)), isFalse);
      expect(robot.navCount, count(0, missed: 1));

      await robot.selectMode(AgendaDayListMode.month);
      await robot.pageMonthTo(january);
      expect(find.text('Rowing'), findsOneWidget);

      final settings = await SettingsService.getInstance();
      expect(
        (await settings.getCalendarOverviewSettings()).listOptions.missedOnly,
        isFalse,
      );

      await robot.setMissedOnly(false);
      expect(robot.optionsBadge, isNull);
      // At a phone's height the month's last rows are past the viewport, so
      // the month nav's count says all three are back.
      expect(find.text('Rowing'), findsWidgets);
      expect(robot.navCount, count(2, missed: 1));
    });

    testWidgets('the tune badge counts Missed only in list and month mode, '
        'never over year mode\'s tiles (review 10)', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot, surface: const Size(412, 915));
      await robot.setMissedOnly(true);
      expect(robot.optionsBadge, '1');

      await robot.selectMode(AgendaDayListMode.year);
      expect(robot.optionsBadge, isNull);

      await robot.selectMode(AgendaDayListMode.month);
      expect(robot.optionsBadge, '1');
    });

    testWidgets('outside list mode the options sheet\'s Order and Rows are '
        'disabled', (tester) async {
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);

      await robot.openOptions();
      expect(robot.options.enabled(SemanticsIds.overviewOrder), isFalse);
      expect(robot.options.enabled(SemanticsIds.overviewRows), isFalse);
      // The page opens in Year mode, whose tiles Missed only does not
      // change (D33); Month mode keeps it live.
      expect(robot.options.enabled(SemanticsIds.overviewMissedOnly), isFalse);
      await robot.options.close();

      await robot.selectMode(AgendaDayListMode.month);
      await robot.openOptions();
      expect(robot.options.enabled(SemanticsIds.overviewOrder), isFalse);
      expect(robot.options.enabled(SemanticsIds.overviewMissedOnly), isTrue);
      await robot.options.close();

      await robot.selectMode(AgendaDayListMode.list);
      await robot.openOptions();
      expect(robot.options.enabled(SemanticsIds.overviewOrder), isTrue);
      expect(robot.options.enabled(SemanticsIds.overviewRows), isTrue);
    });

    testWidgets('the title\'s Period menu checks year mode\'s year and is live '
        'in month mode (D13, D19)', (tester) async {
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);

      expect(robot.periodValue, '$year');
      expect(await robot.periodChoice(), OverviewPeriodChoice.thisYear);

      await robot.previous();
      expect(robot.periodValue, '${year - 1}');
      expect(await robot.periodChoice(), OverviewPeriodChoice.custom);

      await robot.selectMode(AgendaDayListMode.list);
      expect(robot.periodValue, '${year - 1}', reason: 'paging set the period');

      await robot.selectMode(AgendaDayListMode.month);
      expect(robot.periodEnabled, isTrue);
      await robot.openPeriodMenu();
      expect(robot.menuOpen, isTrue);
    });

    testWidgets('Last 90 days picked in month mode lists it, and both the '
        'mode and the period persist (D13)', (tester) async {
      final settings = await SettingsService.getInstance();
      const last90Days = OverviewRollingPeriod(
        OverviewRollingPreset.last90Days,
      );
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);
      await robot.selectMode(AgendaDayListMode.month);

      await robot.pickPeriod(OverviewPeriodChoice.last90Days);
      await tester.pumpAndSettle();

      expect(robot.currentMode, AgendaDayListMode.list);
      expect(await robot.periodChoice(), OverviewPeriodChoice.last90Days);
      expect(robot.navTitle, 'Last 90 days');
      final stored = await settings.getCalendarOverviewSettings();
      expect(stored.mode, AgendaDayListMode.list);
      expect(stored.period, last90Days);
    });

    testWidgets('Custom range… in year mode asks the Dates sheet, then lists '
        'the span (D13)', (tester) async {
      final settings = await SettingsService.getInstance();
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);
      expect(robot.currentMode, AgendaDayListMode.year);

      await robot.pickCustomMonth(DateTime.utc(year, 3, 1));
      await tester.pumpAndSettle();

      expect(robot.rangePickerOpen, isFalse);
      expect(robot.currentMode, AgendaDayListMode.list);
      expect(await robot.periodChoice(), OverviewPeriodChoice.custom);
      expect(
        robot.periodValue,
        OverviewCustomPeriod(
          DateTime.utc(year, 3, 1),
          DateTime.utc(year, 3, 31),
        ).menuValue(en),
      );
      expect(
        (await settings.getCalendarOverviewSettings()).mode,
        AgendaDayListMode.list,
      );
    });

    testWidgets('a cancelled Custom range… leaves year mode as it was (D13)', (
      tester,
    ) async {
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);

      await robot.pickPeriod(OverviewPeriodChoice.custom);
      expect(robot.rangePickerOpen, isTrue);
      await robot.cancelRange();

      expect(robot.rangePickerOpen, isFalse);
      expect(robot.currentMode, AgendaDayListMode.year);
      expect(robot.navTitle, '$year');
      expect(await robot.periodChoice(), OverviewPeriodChoice.thisYear);
    });

    testWidgets('This year in year mode pages to this year and stays in year '
        'mode (D13)', (tester) async {
      final settings = await SettingsService.getInstance();
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);
      await robot.previous();
      expect(robot.navTitle, '${year - 1}');

      await robot.pickPeriod(OverviewPeriodChoice.thisYear);
      await tester.pumpAndSettle();

      expect(robot.currentMode, AgendaDayListMode.year);
      expect(robot.navTitle, '$year');
      expect(
        (await settings.getCalendarOverviewSettings()).period,
        OverviewYearPeriod(year),
      );
    });

    testWidgets('a span kept from the list opens year mode on its first year '
        'and survives the trip', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(
        robot,
        period: const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
      );

      await robot.selectMode(AgendaDayListMode.year);
      final first = today.subtract(const Duration(days: 364)).year;
      expect(robot.navTitle, '$first');
      expect(robot.periodValue, '$first');

      await robot.selectMode(AgendaDayListMode.list);
      expect(await robot.periodChoice(), OverviewPeriodChoice.last12Months);
    });

    testWidgets('year mode opened on a persisted rolling period shows its '
        'first year (review 7)', (tester) async {
      final robot = OverviewRobot(tester);
      await robot.open(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.year,
        period: const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
      );

      final first = today.subtract(const Duration(days: 364)).year;
      expect(robot.navTitle, '$first');
      expect(robot.periodValue, '$first');
    });

    for (final (surface, scale) in [
      (const Size(360, 780), 1.0),
      (const Size(412, 915), 1.0),
      (const Size(360, 780), 2.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets('the keyboard at ${surface.width.round()} × '
          '${surface.height.round()}, text ×$scale, leaves the list '
          'scrollable', (tester) async {
        final robot = OverviewRobot(tester);
        final errors = await layoutErrorsDuring(() async {
          await openList(robot, surface: surface, textScale: scale);
          await robot.focusSearch();
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pumpAndSettle();
        });

        expect(errors, isEmpty);
        expect(robot.searchFocused, isTrue);
        expect(robot.listViewportExtent, greaterThan(0));
        expect(robot.listMaxOffset, greaterThan(0));
        // From the top: the list lands on today, so an offset above zero
        // would not show that the drag moved it.
        await robot.scrollListTo(0);
        await robot.dragList(200);
        expect(robot.listOffset, greaterThan(0));
        // R18: dragging the list drops the keyboard.
        expect(robot.searchFocused, isFalse);
      });
    }

    testWidgets('the mode chips fold with the keyboard over their own height: '
        'half at half, out of semantics and hit testing past it, whole at '
        'zero (slice 8a)', (tester) async {
      Finder chip(String id) => find.bySemanticsIdentifier(id);
      final robot = OverviewRobot(tester);
      await openList(robot, surface: const Size(412, 915));
      final full = robot.modeChipRowExtent;
      expect(full, greaterThan(0));

      await robot.focusSearch();
      tester.view.viewInsets = FakeViewPadding(bottom: full / 2);
      await tester.pumpAndSettle();
      expect(robot.modeChipRowExtent, moreOrLessEquals(full / 2));
      expect(robot.modeChips, hasLength(3));
      expect(chip(SemanticsIds.overviewViewYear), findsOneWidget);

      tester.view.viewInsets = FakeViewPadding(bottom: full);
      await tester.pumpAndSettle();
      expect(robot.modeChips, isEmpty);
      expect(chip(SemanticsIds.overviewViewYear), findsNothing);
      expect(chip(SemanticsIds.overviewSearchOpen), findsNothing);
      expect(
        find.byType(FormChip).hitTestable(),
        findsNothing,
        reason: 'nothing of the row takes a tap',
      );
      expect(robot.searchFocused, isTrue, reason: 'the field kept its state');
      expect(robot.searchOpen, isTrue, reason: 'the Search row stays');

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(robot.modeChips, isEmpty);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(robot.modeChipRowExtent, full);
      expect(robot.modeChips, hasLength(3));
      expect(robot.currentMode, AgendaDayListMode.list);
    });

    testWidgets("a sheet's keyboard over the page leaves the mode chips "
        'whole behind it', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot, surface: const Size(412, 915));
      final full = robot.modeChipRowExtent;
      await robot.scrollListTo(0);
      await robot.tapRow('Stretch class');
      expect(robot.detailSheet, isNotNull);

      tester.view.viewInsets = FakeViewPadding(bottom: full);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(robot.modeChipRowExtent, full);
    });

    for (final locale in const [Locale('de'), Locale('ro')]) {
      testWidgets('${locale.languageCode} month and day headers', (
        tester,
      ) async {
        final l10n = lookupAppLocalizations(locale);
        final robot = OverviewRobot(tester);
        await openList(robot, locale: locale);
        // Slice 4: the list opens landed on today (D7); January is the top.
        await robot.scrollListTo(0);

        expect(
          robot.listTexts,
          containsAllInOrder([
            DateFormat.MMMM(locale.languageCode).format(january),
            dayLabel(january, l10n: l10n),
            l10n.daySummaryEntryCount(1),
            'Leg day',
            dayLabel(DateTime.utc(year, 1, 2), l10n: l10n),
          ]),
        );
      });
    }

    /// Slice 3b: the day list's rows on exact extents, the pinned label,
    /// the landing and the anchoring, per event, month mode's picked day.
    group('the list body', () {
      const phone = Size(412, 915);
      const smallPhone = Size(360, 780);

      /// The list's own node, found with no semantics handle in play.
      final listCarrier = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.identifier == SemanticsIds.overviewList,
      );

      /// A tracked daily series missed on every day of the year, beside the
      /// suite's own events: every day reads a missed count and carries a
      /// faded entry.
      void missEveryDay() {
        addTearDown(EventPresence.resetCache);
        emitEvents([
          gymDaily,
          mobilityOnce,
          CalendarEvent(
            id: 't1',
            title: 'Tracked',
            categoryId: 'gym',
            startDate: january,
            rule: const DailyRecurrence(),
            tracksPresence: true,
          ),
        ]);
        EventPresence.updateCache(
          byEvent: {
            't1': {
              for (
                var day = january;
                day.year == year;
                day = DateTime.utc(day.year, day.month, day.day + 1)
              )
                day: PresenceStatus.missed,
            },
          },
        );
      }

      for (final surface in const [phone, smallPhone]) {
        for (final locale in const [Locale('en'), Locale('de')]) {
          for (final scale in const [1.0, 1.3, 2.0]) {
            testWidgets('every laid-out row fills its slot exactly — '
                '${surface.width.round()} × ${surface.height.round()}, '
                '${locale.languageCode}, text ×$scale', (tester) async {
              missEveryDay();
              final robot = OverviewRobot(tester);
              // Identity-keyed: a row widget is one slot the list laid out.
              final slots = <Widget, double>{};
              void collect() {
                for (final (row, height) in robot.laidOutRows) {
                  slots[row] = height;
                }
              }

              final errors = await layoutErrorsDuring(() async {
                await openList(
                  robot,
                  locale: locale,
                  textScale: scale,
                  surface: surface,
                );
                collect();
                await robot.scrollListTo(robot.listMaxOffset / 2);
                collect();
                await robot.scrollListTo(robot.listMaxOffset);
                collect();
                await robot.setRows(OverviewRows.perEvent);
                collect();
              });
              expect(errors, isEmpty);
              expect(slots, isNotEmpty);

              // Each row laid out again on its own, free to take the height it
              // wants at the list's width, under the same text and locale.
              final rows = slots.keys.toList();
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: locale,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RowMetrics.groupInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: rows,
                      ),
                    ),
                  ),
                ),
              );
              for (final row in rows) {
                expect(
                  tester.getSize(find.byWidget(row)).height,
                  moreOrLessEquals(slots[row]!, epsilon: 0.01),
                  reason: '${row.runtimeType} keeps its natural height',
                );
              }
            });
          }
        }
      }

      testWidgets('a far jump lays out only the rows it lands on, at the true '
          'end of the list', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        // From the top: the list lands on today, which late in December is
        // already the end.
        await robot.scrollListTo(0);

        var builds = 0;
        debugOnRebuildDirtyWidget = (element, _) {
          final widget = element.widget;
          if ((widget is FormRowShell || widget is FormSectionLabel) &&
              element.findAncestorWidgetOfExactType<CustomScrollView>() !=
                  null) {
            builds++;
          }
        };
        try {
          await robot.scrollListTo(robot.listMaxOffset);
        } finally {
          debugOnRebuildDirtyWidget = null;
        }

        // A viewport's worth: what fits in the viewport and the cache band on
        // either side of it, at the smallest slot a row takes. Slice 0
        // measured 6 346 builds for this jump.
        final smallest = robot.laidOutRows
            .map((row) => row.$2)
            .reduce((a, b) => a < b ? a : b);
        final viewportsWorth =
            ((robot.listViewportExtent +
                        2 * RenderAbstractViewport.defaultCacheExtent) /
                    smallest)
                .ceil();
        expect(builds, greaterThan(0));
        expect(builds, lessThanOrEqualTo(viewportsWorth));
        // The extent was exact before the jump: the end is the year's end.
        expect(robot.shows(dayLabel(DateTime.utc(year, 12, 31))), isTrue);
        expect(robot.listOffset, robot.listMaxOffset);
      });

      testWidgets('a period change with today inside lands on today\'s read '
          'row', (tester) async {
        emitEvents([recentDaily]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(0);

        await robot.pickPeriod(OverviewPeriodChoice.last12Months);

        expectLandedOn(robot, today);
      });

      testWidgets('Newest first lands at the top, today inside or not', (
        tester,
      ) async {
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(2000);

        await robot.setOrder(OverviewOrder.newestFirst);

        expect(robot.listOffset, 0);
        expect(
          robot.topRowTexts.first,
          AgendaListView.monthLabel(
            'en',
            DateTime.utc(year, 12, 1),
            withYear: false,
          ),
        );
      });

      testWidgets('a period in the past lands at the top', (tester) async {
        emitEvents([
          gymDaily,
          CalendarEvent(
            id: 'l1',
            title: 'Last year',
            categoryId: 'gym',
            startDate: DateTime.utc(year - 1, 1, 1),
            endDate: DateTime.utc(year - 1, 12, 31),
            rule: const DailyRecurrence(),
          ),
        ]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(2000);

        await robot.pickCustomYear(year - 1);

        expect(robot.listOffset, 0);
        expect(
          robot.topRowTexts.first,
          AgendaListView.monthLabel(
            'en',
            DateTime.utc(year - 1, 1, 1),
            withYear: false,
          ),
        );
      });

      testWidgets('a presence emit keeps the first visible row where it was', (
        tester,
      ) async {
        addTearDown(EventPresence.resetCache);
        final settings = await SettingsService.getInstance();
        await settings.setCalendarMissedDisplay(CalendarMissedDisplay.hidden);
        final tracked = CalendarEvent(
          id: 't1',
          title: 'Tracked',
          categoryId: 'gym',
          startDate: january,
          rule: const DailyRecurrence(),
          tracksPresence: true,
        );
        emitEvents([tracked]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(5000);
        final top = robot.topRowTexts;
        final depth = robot.rowTopInView(top.first);
        final before = robot.listOffset;

        // Two days above the viewport go missed — hidden, so their rows go.
        EventPresence.updateCache(
          byEvent: {
            't1': {
              DateTime.utc(year, 1, 2): PresenceStatus.missed,
              DateTime.utc(year, 1, 3): PresenceStatus.missed,
            },
          },
        );
        emit(
          loaded().copyWith(presenceRevision: loaded().presenceRevision + 1),
        );
        await tester.pumpAndSettle();

        expect(robot.listOffset, lessThan(before));
        expect(robot.topRowTexts, top);
        expect(robot.rowTopInView(top.first), moreOrLessEquals(depth!));
      });

      testWidgets('the pinned label is empty at the top, names the month once '
          'its own label has scrolled past, and follows it', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        // Slice 4: the list opens landed on today (D7); this reads it from
        // the top.
        await robot.scrollListTo(0);
        expect(robot.pinnedLabel, isNull);

        String month(int number) => AgendaListView.monthLabel(
          'en',
          DateTime.utc(year, number, 1),
          withYear: true,
        );
        Future<void> scrollUntilPinned(String label) async {
          for (var i = 0; i < 100 && robot.pinnedLabel?.$1 != label; i++) {
            await robot.dragList(150);
          }
        }

        await scrollUntilPinned(month(3));
        // The month's 31 days of the series and the class on the 9th.
        expect(robot.pinnedLabel, (month(3), count(32)));
        expect(
          robot.shows(
            AgendaListView.monthLabel(
              'en',
              DateTime.utc(year, 3),
              withYear: false,
            ),
          ),
          isFalse,
          reason: 'March\'s own label is past the top, not drawn twice',
        );

        await scrollUntilPinned(month(4));
        expect(robot.pinnedLabel, (month(4), count(30)));
      });

      testWidgets('per event, the pinned label names the category group', (
        tester,
      ) async {
        emitEvents([
          for (var i = 1; i <= 12; i++)
            CalendarEvent(
              id: 'g$i',
              title: 'Gym $i',
              categoryId: 'gym',
              startDate: DateTime.utc(year, 1, i),
              rule: const OneTimeRecurrence(),
            ),
          for (var i = 1; i <= 12; i++)
            CalendarEvent(
              id: 'm$i',
              title: 'Mobility $i',
              categoryId: 'mobility',
              startDate: DateTime.utc(year, 2, i),
              rule: const OneTimeRecurrence(),
            ),
        ]);
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          surface: phone,
          options: const OverviewListOptions(rows: OverviewRows.perEvent),
        );
        String label(String id) =>
            CalendarCategories.labelOf(CalendarCategories.resolve(id), en);

        expect(robot.pinnedLabel, isNull);
        await robot.dragList(100);
        expect(robot.pinnedLabel, (label('gym'), en.overviewEventCount(12)));

        await robot.scrollListTo(robot.listMaxOffset);
        expect(robot.pinnedLabel, (
          label('mobility'),
          en.overviewEventCount(12),
        ));
      });

      for (final (surface, locale, scale) in const [
        (phone, Locale('en'), 1.0),
        // The large phone: on the small one the period band (slice 9a)
        // leaves the list about 50 tall at 200 % German, and the pinned
        // label yields to it by design (`pinnedBandMaxShare`).
        (phone, Locale('de'), 2.0),
      ]) {
        testWidgets('at no offset across a month boundary is a section label '
            'both pinned and in the list (C) — ${locale.languageCode}, text '
            '×$scale', (tester) async {
          final l10n = lookupAppLocalizations(locale);
          final robot = OverviewRobot(tester);
          await openList(
            robot,
            locale: locale,
            textScale: scale,
            surface: surface,
          );
          final march = AgendaListView.monthLabel(
            locale.languageCode,
            DateTime.utc(year, 3),
            withYear: false,
          );
          // March's own label at the list's top edge.
          await robot.scrollListTo(0);
          // A view per step, so no label is stepped over: under the mode
          // chips and the period band the view is short at 200 % (slices
          // 8a, 9a).
          for (var i = 0; i < 400 && robot.rowTopInView(march) == null; i++) {
            await robot.scrollListTo(
              robot.listOffset + robot.listViewportExtent,
            );
          }
          final labelAt = robot.listOffset + robot.rowTopInView(march)!;
          // The pinned label reads February, then March — only once March's
          // own label has wholly left the list.
          final pinnedSeen = <String>{};
          for (var offset = labelAt - 80; offset < labelAt + 160; offset += 2) {
            await robot.scrollListTo(offset, settle: false);
            final pinned = robot.pinnedLabel?.$1;
            if (pinned == null) continue;
            pinnedSeen.add(pinned);
            for (final shown in robot.visibleSectionLabels) {
              expect(
                pinned == shown || pinned.startsWith('$shown '),
                isFalse,
                reason: '"$shown" shows in the list at $offset while pinned',
              );
            }
          }
          expect(pinnedSeen, {
            AgendaListView.monthLabel(
              l10n.localeName,
              DateTime.utc(year, 2),
              withYear: true,
            ),
            AgendaListView.monthLabel(
              l10n.localeName,
              DateTime.utc(year, 3),
              withYear: true,
            ),
          });
        });
      }

      testWidgets('at 360 × 780 in German at 200 % a day header keeps its '
          'label beside or above its count — never squeezed to an ellipsis — '
          'and every header fills its kind\'s slot (D)', (tester) async {
        const locale = Locale('de');
        final de = lookupAppLocalizations(locale);
        addTearDown(EventPresence.resetCache);
        final tomorrow = today.add(const Duration(days: 1));
        // Tomorrow reads "1 Termin · 1 verpasst", as on the device.
        emitEvents([
          gymDaily,
          CalendarEvent(
            id: 't1',
            title: 'Tracked',
            categoryId: 'gym',
            startDate: january,
            rule: const DailyRecurrence(),
            tracksPresence: true,
          ),
        ]);
        EventPresence.updateCache(
          byEvent: {
            't1': {tomorrow: PresenceStatus.missed},
          },
        );
        final robot = OverviewRobot(tester);
        final errors = await layoutErrorsDuring(
          () => openList(
            robot,
            locale: locale,
            textScale: 2.0,
            surface: smallPhone,
          ),
        );
        expect(errors, isEmpty);

        final label = AgendaListView.dayHeaderLabel(de, tomorrow, today);
        expect(label, de.upcomingTomorrow);
        // The page's chrome leaves the list a short view at this scale: bring
        // tomorrow's read row to its top.
        for (var i = 0; i < 20 && robot.rowTopInView(label) == null; i++) {
          await robot.scrollListTo(robot.listOffset + 100);
        }
        await robot.scrollListTo(robot.listOffset + robot.rowTopInView(label)!);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: listCarrier, matching: find.text(label)),
        );
        final row = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FormRowShell),
          ),
        );
        expect(paragraph.size.width, greaterThan(row.width / 2));
        expect(paragraph.didExceedMaxLines, isFalse);

        // No header in view is cut short, and every header is its slot.
        for (final text in tester.widgetList<Text>(
          find.descendant(of: listCarrier, matching: find.byType(Text)),
        )) {
          if (text.data == null) continue;
          final shown = tester.renderObject<RenderParagraph>(
            find.byWidget(text),
          );
          expect(
            shown.didExceedMaxLines && shown.size.width < row.width / 2,
            isFalse,
            reason: '"${text.data}" is squeezed',
          );
        }
        // A read row is its shell around the slot's box, a section label the
        // box alone; each kind is one height whatever its text.
        final readRows = <double>{};
        final sections = <double>{};
        for (final (built, height) in robot.laidOutRows) {
          if (built is FormRowShell && built.child is SizedBox) {
            readRows.add(height);
          } else if (built is SizedBox) {
            sections.add(height);
          }
        }
        expect(readRows, hasLength(1));
        expect(sections, hasLength(lessThanOrEqualTo(1)));
      });

      testWidgets('a text scale change keeps the list mounted, with no '
          'spinner, on the day it showed (E2)', (tester) async {
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(robot.listMaxOffset / 2);
        String? top;
        for (
          var day = january;
          top == null;
          day = DateTime.utc(day.year, day.month, day.day + 1)
        ) {
          final label = dayLabel(day);
          final at = robot.rowTopInView(label);
          if (at != null && at > 0) {
            await robot.scrollListTo(robot.listOffset + at);
            top = label;
          }
        }
        expect(robot.topRowTexts.first, top);
        final position = tester.state<ScrollableState>(
          find.descendant(of: listCarrier, matching: find.byType(Scrollable)),
        );

        // Until the probe reports, the rows and the pinned band are drawn at
        // the new scale on the old extents: clipped, never overflowing.
        final errors = await layoutErrorsDuring(() async {
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump();
            expect(find.byType(CircularProgressIndicator), findsNothing);
          }
          await tester.pumpAndSettle();
        });
        expect(errors, isEmpty);

        expect(
          tester.state<ScrollableState>(
            find.descendant(of: listCarrier, matching: find.byType(Scrollable)),
          ),
          same(position),
          reason: 'the list stayed mounted',
        );
        expect(robot.topRowTexts.first, top);
        expect(robot.rowTopInView(top), moreOrLessEquals(0, epsilon: 0.01));
      });

      group('per event', () {
        final warmUp = CalendarEvent(
          id: 'w1',
          title: 'Warm-up',
          categoryId: 'gym',
          startDate: january,
          endDate: DateTime.utc(year, 1, 20),
          rule: const DailyRecurrence(),
        );
        final late = CalendarEvent(
          id: 'z1',
          title: 'Late session',
          categoryId: 'gym',
          startDate: DateTime.utc(year, 12, 1),
          rule: const OneTimeRecurrence(),
        );

        setUp(() => emitEvents([gymDaily, warmUp, late, mobilityOnce]));

        String label(String id) =>
            CalendarCategories.labelOf(CalendarCategories.resolve(id), en);

        testWidgets('one row per event under its category, the most frequent '
            'first, the caption still counting entries', (tester) async {
          final robot = OverviewRobot(tester);
          await openList(robot, surface: phone);

          await robot.setRows(OverviewRows.perEvent);

          expect(
            robot.listTexts,
            containsAllInOrder([
              label('gym'),
              en.overviewEventCount(3),
              'Leg day',
              '${daysIn(year)}',
              'Jan 1 – ${DateFormat.yMMMd('en').format(DateTime.utc(year, 12, 31))}',
              'Warm-up',
              '20',
              'Late session',
              '1',
              label('mobility'),
              en.overviewEventCount(1),
              'Stretch class',
            ]),
          );
          expect(robot.navCount, count(daysIn(year) + 20 + 1 + 1));
        });

        testWidgets('Newest first leads with the event seen last', (
          tester,
        ) async {
          final robot = OverviewRobot(tester);
          await openList(robot, surface: phone);

          await robot.setRows(OverviewRows.perEvent);
          await robot.setOrder(OverviewOrder.newestFirst);

          expect(
            robot.listTexts,
            containsAllInOrder(['Leg day', 'Late session', 'Warm-up']),
          );
        });

        testWidgets('a row tap opens the event\'s last day in the period', (
          tester,
        ) async {
          final robot = OverviewRobot(tester);
          await openList(robot, surface: phone);

          await robot.setRows(OverviewRows.perEvent);
          await robot.tapRow('Warm-up');

          final sheet = robot.detailSheet!;
          expect(sheet.event.id, 'w1');
          expect(sheet.day, DateTime.utc(year, 1, 20));
        });
      });

      testWidgets('month mode: a picked day heads its entries with its read '
          'row and the ✕, which restores the whole month; nothing overflows '
          'on a phone with a missed count', (tester) async {
        addTearDown(EventPresence.resetCache);
        markSecondRowingMissed();
        emitEvents([rowing, mobilityOnce]);
        final robot = OverviewRobot(tester);
        final errors = await layoutErrorsDuring(() async {
          await robot.open(
            bloc: bloc,
            importExport: importExport,
            mode: AgendaDayListMode.month,
            surface: phone,
          );
          await robot.pageMonthTo(january);
          await tester.tap(find.text('2').first);
          await tester.pumpAndSettle();
        });
        expect(errors, isEmpty);

        final wholeMonth = find.bySemanticsIdentifier(
          SemanticsIds.overviewWholeMonth,
        );
        expect(wholeMonth, findsOneWidget);
        expect(find.text(dayLabel(DateTime.utc(year, 1, 2))), findsOneWidget);
        expect(find.text(count(0, missed: 1)), findsOneWidget);
        expect(find.text('Rowing'), findsOneWidget);

        await tester.tap(wholeMonth);
        await tester.pumpAndSettle();
        expect(wholeMonth, findsNothing);
        expect(find.text(dayLabel(january)), findsOneWidget);
      });
    });

    /// Slice 4: a long period lists its first two years with the frame that
    /// asks and the rest one run per event-loop turn under a tail caption
    /// (§3.8 item 3), up to the entry cap (T5); the list lands per D7 when
    /// it first shows.
    group('resolution between frames', () {
      const phone = Size(412, 915);
      const allTime = OverviewRollingPeriod(OverviewRollingPreset.allTime);

      /// An open-ended daily series from January [years] years back: All
      /// time spans exactly those years and this one, and every day the page
      /// scans costs one `occursOn` call.
      CalendarEvent dailyFrom(int years) => CalendarEvent(
        id: 's1',
        title: 'Session',
        categoryId: 'gym',
        startDate: DateTime.utc(year - years, 1, 1),
        rule: const DailyRecurrence(),
      );

      int daysFrom(DateTime first, DateTime last) =>
          last.difference(first).inDays + 1;

      final monthEnd = DateTime.utc(year, today.month + 1, 0);

      testWidgets('a three-year period lists two years with the frame and the '
          'rest a turn later, under "Loading more…" until then', (
        tester,
      ) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone, period: allTime);

        CalendarEvent.debugOccursOnCalls = 0;
        emitEvents([dailyFrom(2)]);
        await robot.pumpWithoutTurns();

        final first = DateTime.utc(year - 2, 1, 1);
        final synced = daysIn(year - 2) + daysIn(year - 1);
        expect(CalendarEvent.debugOccursOnCalls, synced);
        expect(robot.navCount, count(synced));
        final extent = robot.listMaxOffset;
        await robot.scrollListTo(extent, settle: false);
        expect(robot.listTexts.last, en.overviewLoading);

        await robot.finishResolving();

        expect(CalendarEvent.debugOccursOnCalls, daysFrom(first, monthEnd));
        expect(robot.navCount, count(daysFrom(first, today)));
        expect(robot.listMaxOffset, greaterThan(extent));
        await robot.scrollListTo(robot.listMaxOffset);
        expect(robot.shows(en.overviewLoading), isFalse);
        expect(robot.shows(dayLabel(today)), isTrue);
      });

      testWidgets('Newest first lists the latest two years first; the older '
          'months join at the bottom and the offset stays', (tester) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          surface: phone,
          period: allTime,
          options: const OverviewListOptions(order: OverviewOrder.newestFirst),
        );

        emitEvents([dailyFrom(2)]);
        await robot.pumpWithoutTurns();

        // Twenty-four months back from this one.
        final synced = DateTime.utc(year - 2, today.month + 1, 1);
        expect(robot.navCount, count(daysFrom(synced, today)));
        expect(
          robot.topRowTexts.first,
          AgendaListView.monthLabel(
            'en',
            DateTime.utc(year, today.month, 1),
            withYear: true,
          ),
        );
        await robot.scrollListTo(1000, settle: false);
        final top = robot.topRowTexts;
        final extent = robot.listMaxOffset;

        await robot.finishResolving();

        expect(robot.listOffset, 1000);
        expect(robot.topRowTexts, top);
        expect(robot.listMaxOffset, greaterThan(extent));
        final first = DateTime.utc(year - 2, 1, 1);
        expect(robot.navCount, count(daysFrom(first, today)));
        await robot.scrollListTo(robot.listMaxOffset);
        expect(
          robot.pinnedLabel?.$1,
          AgendaListView.monthLabel('en', first, withYear: true),
        );
      });

      testWidgets('a period change mid-batch cancels the old runs: no stale '
          'scans, rows or caption', (tester) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone, period: allTime);
        await robot.openPeriodMenu();

        // Five years under the open menu: two listed, three still to come.
        emitEvents([dailyFrom(4)]);
        await robot.pumpWithoutTurns();
        expect(robot.navCount, count(daysIn(year - 4) + daysIn(year - 3)));

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.pickOpenPeriod(
          OverviewPeriodChoice.thisYear,
          settle: false,
        );
        await robot.finishResolving();
        await tester.pumpAndSettle();

        // This year's one scan, and nothing of the years the old runs were
        // to list.
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
        expect(await robot.periodChoice(), OverviewPeriodChoice.thisYear);
        expect(robot.navCount, count(daysIn(year)));
        await robot.scrollListTo(robot.listMaxOffset);
        expect(robot.shows(en.overviewLoading), isFalse);
        expect(robot.shows(dayLabel(DateTime.utc(year, 12, 31))), isTrue);
      });

      testWidgets('a switch to Month mid-batch cancels the list\'s runs', (
        tester,
      ) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone, period: allTime);

        emitEvents([dailyFrom(4)]);
        await robot.pumpWithoutTurns();
        await robot.selectMode(AgendaDayListMode.month, settle: false);
        await robot.finishResolving();
        await tester.pumpAndSettle();

        expect(robot.currentMode, AgendaDayListMode.month);
        // Month mode's rows are a month's days, never the list's months.
        expect(find.byType(FormSectionLabel), findsNothing);
        expect(find.text('Session'), findsWidgets);
      });

      testWidgets('past the cap resolution stops under the cap\'s caption, and '
          'the count reads the cap', (tester) async {
        // Retroactive: All time reaches back to the calendar's first year,
        // tens of thousands of days.
        emitEvents([
          CalendarEvent(
            id: 'r1',
            title: 'Every day',
            categoryId: 'gym',
            startDate: january,
            rule: const DailyRecurrence(),
            retroactive: true,
          ),
        ]);
        final robot = OverviewRobot(tester);
        CalendarEvent.debugOccursOnCalls = 0;
        await openList(robot, surface: phone, period: allTime);

        const cap = OverviewListMetrics.maxEntries;
        expect(robot.navCount, count(cap));
        // Stopped in the run that reached the cap: at most a year past it.
        expect(
          CalendarEvent.debugOccursOnCalls,
          inInclusiveRange(cap, cap + 366),
        );
        await robot.scrollListTo(robot.listMaxOffset);
        expect(robot.listTexts.last, en.overviewCapReached(cap));
        // The count reads as a number is written in the locale (review 14).
        expect(
          robot.listTexts.last,
          contains(NumberFormat.decimalPattern('en').format(cap)),
        );
        expect(robot.shows(en.overviewLoading), isFalse);

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.finishResolving();
        await tester.pump(const Duration(seconds: 1));
        expect(CalendarEvent.debugOccursOnCalls, 0);
      });

      testWidgets('both tail captions fill their slots exactly in German at '
          '200 %', (tester) async {
        const locale = Locale('de');
        const scale = 2.0;
        final de = lookupAppLocalizations(locale);
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          locale: locale,
          textScale: scale,
          surface: phone,
          period: allTime,
        );
        final slots = <Widget, double>{};
        void collect(String text) {
          final caption = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.widgetWithText(FormCaption, text),
          );
          slots[tester.widget(caption)] = tester.getSize(caption).height;
        }

        emitEvents([dailyFrom(2)]);
        await robot.pumpWithoutTurns();
        await robot.scrollListTo(robot.listMaxOffset, settle: false);
        collect(de.overviewLoading);

        emitEvents([
          CalendarEvent(
            id: 'r1',
            title: 'Every day',
            categoryId: 'gym',
            startDate: january,
            rule: const DailyRecurrence(),
            retroactive: true,
          ),
        ]);
        await robot.finishResolving();
        await robot.scrollListTo(robot.listMaxOffset);
        collect(de.overviewCapReached(OverviewListMetrics.maxEntries));

        // Each laid out again on its own at the list's width.
        final captions = slots.keys.toList();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: RowMetrics.groupInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: captions,
                ),
              ),
            ),
          ),
        );
        for (final caption in captions) {
          expect(
            tester.getSize(find.byWidget(caption)).height,
            moreOrLessEquals(slots[caption]!, epsilon: 0.01),
          );
        }
        expect(slots.values.last, greaterThan(slots.values.first));
      });

      testWidgets('the runs of a long period visit each entry once and extend '
          'the layout to the extent a whole build sums (review 16)', (
        tester,
      ) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone, period: allTime);

        CalendarOverviewPage.resetDebugListedEntryVisits();
        // Ten years: two with the frame, eight runs of twelve months after.
        emitEvents([dailyFrom(9)]);
        await robot.pumpWithoutTurns();
        for (var run = 0; run < 12; run++) {
          await robot.finishResolving();
        }
        await tester.pumpAndSettle();

        final first = DateTime.utc(year - 9, 1, 1);
        expect(robot.navCount, count(daysFrom(first, today)));
        expect(
          CalendarOverviewPage.debugListedEntryVisits,
          daysFrom(first, today),
        );
        final extended = robot.listMaxOffset;

        // Newest first and back: every month is resolved, so the list is
        // built whole, in one pass, and summed whole.
        await robot.setOrder(OverviewOrder.newestFirst);
        await robot.setOrder(OverviewOrder.oldestFirst);
        expect(robot.listMaxOffset, moreOrLessEquals(extended));
        await robot.scrollListTo(robot.listMaxOffset);
        expect(robot.shows(dayLabel(today)), isTrue);
      });

      testWidgets('a width change re-measures the rows: "Loading more…" and '
          'every row fill their slots at the new width (review 9)', (
        tester,
      ) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(robot, textScale: 2.0, surface: phone, period: allTime);
        emitEvents([dailyFrom(2)]);
        await robot.pumpWithoutTurns();

        const narrow = Size(280, 915);
        tester.view.physicalSize = narrow;
        await tester.pump();
        await tester.pump();
        await robot.scrollListTo(robot.listMaxOffset, settle: false);
        expect(robot.listTexts.last, en.overviewLoading);
        final slots = {
          for (final (row, height) in robot.laidOutRows) row: height,
        };
        await robot.finishResolving();

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: RowMetrics.groupInset,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: slots.keys.toList(),
                ),
              ),
            ),
          ),
        );
        for (final row in slots.keys) {
          expect(
            tester.getSize(find.byWidget(row)).height,
            moreOrLessEquals(slots[row]!, epsilon: 0.01),
            reason: '${row.runtimeType} at ${narrow.width}',
          );
        }
      });

      testWidgets('a period opened with today inside lands on today, not its '
          'top', (tester) async {
        emitEvents([recentDaily]);
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          surface: phone,
          period: const OverviewRollingPeriod(
            OverviewRollingPreset.last12Months,
          ),
        );

        expectLandedOn(robot, today);
      });

      testWidgets('a switch into List lands on today too', (tester) async {
        emitEvents([recentDaily]);
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: phone,
          period: const OverviewRollingPeriod(
            OverviewRollingPreset.last12Months,
          ),
        );

        await robot.selectMode(AgendaDayListMode.list);

        expectLandedOn(robot, today);
      });

      testWidgets('Newest first opens at the top', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          surface: phone,
          options: const OverviewListOptions(order: OverviewOrder.newestFirst),
        );

        expect(robot.listOffset, 0);
      });

      testWidgets('runs pause while a page covers the overview and the rest '
          'lands on the return', (tester) async {
        emitEvents(const []);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone, period: allTime);

        // Five years: two listed with the frame, three still to come.
        emitEvents([dailyFrom(4)]);
        await robot.pumpWithoutTurns();
        expect(robot.navCount, count(daysIn(year - 4) + daysIn(year - 3)));

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.cover();
        await robot.finishResolving();
        await tester.pump(const Duration(seconds: 1));
        expect(
          CalendarEvent.debugOccursOnCalls,
          0,
          reason: 'nothing ran beneath',
        );

        await robot.uncover();

        expect(
          CalendarEvent.debugOccursOnCalls,
          daysFrom(DateTime.utc(year - 2, 1, 1), monthEnd),
        );
        expect(
          robot.navCount,
          count(daysFrom(DateTime.utc(year - 4, 1, 1), today)),
        );
        await robot.scrollListTo(robot.listMaxOffset);
        expect(robot.shows(en.overviewLoading), isFalse);
      });

      testWidgets('a landing past the first two years waits for the run that '
          'lists it', (tester) async {
        // Five years: this one is resolved by the open, the two before it
        // are what the runs after All time's first two years list.
        emitEvents([dailyFrom(4)]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.openPeriodMenu();

        await robot.pickOpenPeriod(OverviewPeriodChoice.allTime, settle: false);
        await robot.finishResolving();
        await tester.pumpAndSettle();

        expectLandedOn(robot, today);
      });

      testWidgets('a drag while a landing waits for its run drops the landing: '
          'the run leaves the list where the finger put it (review 6)', (
        tester,
      ) async {
        emitEvents([dailyFrom(4)]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(0);
        await robot.openPeriodMenu();
        // Today is in the fifth year, two runs away: the landing waits.
        await robot.pickOpenPeriod(OverviewPeriodChoice.allTime, settle: false);

        await tester.drag(
          find
              .descendant(
                of: find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics &&
                      widget.properties.identifier == SemanticsIds.overviewList,
                ),
                matching: find.byType(Scrollable),
              )
              .first,
          const Offset(0, -200),
        );
        await tester.pump();
        expect(robot.listOffset, greaterThan(0));
        await robot.finishResolving();
        await tester.pumpAndSettle();

        expect(robot.listOffset, lessThan(1000));
        expect(robot.rowTopInView(dayLabel(today)), isNull);
      });
    });

    /// Slice 5: the lane along the list's right edge (§3.7).
    group('the scrubber', () {
      const phone = Size(412, 915);

      String label(String id) =>
          CalendarCategories.labelOf(CalendarCategories.resolve(id), en);

      testWidgets('it is on the list while the list has rows, outside the '
          'list\'s node, and nowhere else', (tester) async {
        final semantics = tester.ensureSemantics();
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        expect(robot.hasScrubber, isTrue);

        final lane = tester.getSemantics(robot.scrubberNode);
        expect(lane.label, en.overviewScrubberLabel);
        var inList = false;
        bool visit(SemanticsNode node) {
          if (identical(node, lane)) inList = true;
          node.visitChildren(visit);
          return true;
        }

        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.overviewList))
            .visitChildren(visit);
        expect(inList, isFalse);

        await robot.typeQuery('nothing matches this');
        await tester.pumpAndSettle();
        expect(robot.shows(robot.emptyPeriodText), isTrue);
        expect(robot.hasScrubber, isFalse);

        await robot.clearQuery();
        expect(robot.hasScrubber, isTrue);

        await robot.selectMode(AgendaDayListMode.month);
        expect(robot.hasScrubber, isFalse);
        semantics.dispose();
      });

      testWidgets('Year mode wears the year lane over a span of years, outside '
          'the scroll\'s node, and none over one year (D29)', (tester) async {
        final semantics = tester.ensureSemantics();
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: phone,
        );
        await robot.finishResolving();
        expect(robot.yearSpan, (first: year - 2, last: year + 1));
        expect(robot.hasScrubber, isTrue);

        final lane = tester.getSemantics(robot.scrubberNode);
        expect(lane.label, en.overviewYearScrubberLabel);
        var inScroll = false;
        bool visit(SemanticsNode node) {
          if (identical(node, lane)) inScroll = true;
          node.visitChildren(visit);
          return true;
        }

        tester
            .getSemantics(
              find.bySemanticsIdentifier(SemanticsIds.overviewYears),
            )
            .visitChildren(visit);
        expect(inScroll, isFalse);

        final gesture = await robot.scrub(to: 0);
        expect(robot.scrubberBubble, '${year - 2}');
        expect(robot.navTitle, '${year - 2}');
        await gesture.up();
        await tester.pumpAndSettle();

        // One year: the span of a store with a single one-time event.
        emitEvents([mobilityOnce]);
        await tester.pumpAndSettle();
        expect(robot.yearSpan, (first: year, last: year));
        expect(robot.hasScrubber, isFalse);
        semantics.dispose();
      });

      testWidgets('a lane drag lands the list at its share of the extent and '
          'the bubble names the month there', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);

        final gesture = await robot.scrub(to: 0.5);

        expect(
          robot.listOffset,
          moreOrLessEquals(robot.listMaxOffset / 2, epsilon: 0.5),
        );
        final month = robot.pinnedLabel?.$1;
        expect(month, isNotNull);
        expect(month, endsWith('$year'));
        expect(robot.scrubberBubble, month);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          robot.listOffset,
          moreOrLessEquals(robot.listMaxOffset / 2, epsilon: 0.5),
        );
      });

      testWidgets('increase and decrease on the lane step the list to the next '
          'and the previous month (review 15)', (tester) async {
        final semantics = tester.ensureSemantics();
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.scrollListTo(0);
        String month(int number) => AgendaListView.monthLabel(
          'en',
          DateTime.utc(year, number),
          withYear: false,
        );
        Future<void> step(SemanticsAction action) async {
          final node = tester.getSemantics(robot.scrubberNode);
          node.owner!.performAction(node.id, action);
          await tester.pumpAndSettle();
        }

        await step(SemanticsAction.increase);
        expect(robot.topRowTexts.first, month(2));
        await step(SemanticsAction.increase);
        expect(robot.topRowTexts.first, month(3));
        // Back from inside a month goes to its own start first.
        await robot.scrollListTo(robot.listOffset + 100);
        await step(SemanticsAction.decrease);
        expect(robot.topRowTexts.first, month(3));
        await step(SemanticsAction.decrease);
        expect(robot.topRowTexts.first, month(2));
        await step(SemanticsAction.decrease);
        await step(SemanticsAction.decrease);
        expect(robot.listOffset, 0);
        semantics.dispose();
      });

      testWidgets('One per event: the bubble names the category group', (
        tester,
      ) async {
        emitEvents([
          for (var i = 0; i < 25; i++)
            CalendarEvent(
              id: 'g$i',
              title: 'Gym $i',
              categoryId: 'gym',
              startDate: DateTime.utc(year, 1, i + 1),
              rule: const OneTimeRecurrence(),
            ),
          for (var i = 0; i < 15; i++)
            CalendarEvent(
              id: 'm$i',
              title: 'Mobility $i',
              categoryId: 'mobility',
              startDate: DateTime.utc(year, 2, i + 1),
              rule: const OneTimeRecurrence(),
            ),
        ]);
        final robot = OverviewRobot(tester);
        await openList(robot, surface: phone);
        await robot.setRows(OverviewRows.perEvent);

        var gesture = await robot.scrub(to: 0.15);
        expect(robot.scrubberBubble, label('gym'));
        await gesture.up();
        await tester.pumpAndSettle();

        gesture = await robot.scrub(to: 0.99);
        expect(robot.scrubberBubble, label('mobility'));
        expect(robot.pinnedLabel?.$1, label('mobility'));
        await gesture.up();
        await tester.pumpAndSettle();
      });
    });

    group('the years scroll after review (slice 12 fix pass)', () {
      const phone = Size(412, 915);

      /// One retroactive daily series, as in the scan budgets: every year
      /// scanned costs its days in `occursOn` calls, and the series is
      /// open-ended, so the scroll ends next year while the calendar's
      /// ceiling stays reachable everywhere else (D28).
      final everyDay = CalendarEvent(
        id: 'r1',
        title: 'Leg day',
        categoryId: 'gym',
        startDate: january,
        rule: const DailyRecurrence(),
        retroactive: true,
      );

      String headerLabel(WidgetTester tester, int shown) => tester
          .getSemantics(
            find.bySemanticsIdentifier(SemanticsIds.overviewYearHeader(shown)),
          )
          .label;

      /// Every selection click the page asks the platform for.
      List<Object?> recordClicks(WidgetTester tester) {
        final clicks = <Object?>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        const channel = SystemChannels.platform;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            clicks.add(call.arguments);
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        return clicks;
      }

      testWidgets('R1: Custom range… from the list reaches the calendar\'s '
          'ceiling with an open-ended series, and the list nav steps past '
          'next year', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(robot);

        await robot.next();
        expect(robot.navTitle, contains('${year + 1}'));
        expect(robot.canGoNext, isTrue);
        await robot.next();
        expect(robot.navTitle, contains('${year + 2}'));

        await robot.pickPeriod(OverviewPeriodChoice.custom);
        final sheet = tester.widget<CalendarDatePickerSheet>(
          find.byType(CalendarDatePickerSheet),
        );
        expect(
          sheet.lastDate,
          DateTime.utc(CalendarBounds.latest.year, 12, 31),
        );
        await robot.cancelRange();
      });

      testWidgets('R1: Month mode paged into the year after next keeps its '
          'year; Year mode then lands at the scroll\'s end, where its ► '
          'stops', (tester) async {
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.month,
        );
        await robot.pageMonthTo(DateTime.utc(year + 2, 1, 1));

        // The list opens on the year the month pages reached.
        await robot.selectMode(AgendaDayListMode.list);
        expect(robot.navTitle, contains('${year + 2}'));

        await robot.selectMode(AgendaDayListMode.year);
        await robot.finishResolving();
        expect(robot.yearSpan.last, year + 1);
        expect(robot.navTitle, '${year + 1}');
        expect(robot.yearHeaderTop(year + 1), 0);
        expect(robot.canGoNext, isFalse);
      });

      testWidgets('R1: a custom span past the ceiling, kept from the list, '
          'opens Year mode clamped to the scroll\'s last year', (tester) async {
        // A saved view's span: the range sheet extends from the span shown,
        // so a span that starts past the ceiling comes from a view.
        final service = await OverviewViewService.getInstance();
        final view = await service.create(
          name: 'Later',
          period: OverviewCustomPeriod(
            DateTime.utc(year + 3, 3, 1),
            DateTime.utc(year + 4, 2, 28),
          ),
          options: OverviewListOptions.defaults,
          categoryIds: const {},
        );
        final robot = OverviewRobot(tester);
        await openList(robot);
        await robot.applyView(view!.id);
        await tester.pumpAndSettle();
        expect(robot.navTitle, contains('${year + 3}'));

        await robot.selectMode(AgendaDayListMode.year);
        await robot.finishResolving();
        expect(robot.yearSpan.last, year + 1);
        expect(robot.navTitle, '${year + 1}');
        expect(robot.yearHeaderTop(year + 1), 0);

        // The span is still the list's.
        await robot.selectMode(AgendaDayListMode.list);
        expect(robot.navTitle, contains('${year + 3}'));
      });

      testWidgets('R3: a scrubber step resolves its target before the '
          'animation and clicks once; a step during a landing goes on from '
          'its target', (tester) async {
        emitEvents([everyDay]);
        final semantics = tester.ensureSemantics();
        final clicks = recordClicks(tester);
        AgendaMonthStore? store;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: phone,
          onStore: (resolved) => store = resolved,
        );
        await robot.finishResolving();
        bool resolvedYear(int shown) =>
            store!.cachedTally(DateTime.utc(shown, 6, 1)) != null;
        void decrease() {
          final node = tester.getSemantics(robot.scrubberNode);
          node.owner!.performAction(node.id, SemanticsAction.decrease);
        }

        clicks.clear();
        decrease();
        expect(clicks, hasLength(1));
        await tester.pump(const Duration(milliseconds: 16));
        expect(resolvedYear(year - 2), isFalse);

        decrease();
        expect(clicks, hasLength(2));
        expect(resolvedYear(year - 2), isTrue, reason: 'before any frame');
        await tester.pumpAndSettle();
        await robot.finishResolving();
        expect(robot.navTitle, '${year - 2}');
        expect(robot.yearHeaderTop(year - 2), 0);
        semantics.dispose();
      });

      testWidgets('R4: a rebuild mid-landing scans the landing\'s target, not '
          'the year passing the top', (tester) async {
        emitEvents([everyDay]);
        AgendaMonthStore? store;
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: phone,
          onStore: (resolved) => store = resolved,
        );
        await robot.finishResolving();
        await robot.jumpYearsTo(
          robot.yearsOffset - 26 * robot.yearSectionExtent,
        );
        await robot.finishResolving();

        await robot.today(settle: false);
        await tester.pump(const Duration(milliseconds: 60));
        final passing = int.parse(robot.navTitle);
        expect(passing, inExclusiveRange(year - 26, year));

        CalendarEvent.debugOccursOnCalls = 0;
        emitEvents([everyDay.copyWith(title: 'Leg day, renamed')]);
        await tester.pump();
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
        expect(store!.cachedTally(DateTime.utc(year, 6, 1)), isNotNull);
        expect(store!.cachedTally(DateTime.utc(passing, 6, 1)), isNull);

        await tester.pumpAndSettle();
        await robot.finishResolving();
        expect(robot.navTitle, '$year');
        expect(robot.yearHeaderTop(year), 0);
      });

      testWidgets('R5: a locale change while a page covers the overview scans '
          'nothing until the pop', (tester) async {
        emitEvents([everyDay]);
        final robot = OverviewRobot(tester);
        await robot.open(bloc: bloc, importExport: importExport);
        await robot.finishResolving();
        await robot.cover();

        CalendarEvent.debugOccursOnCalls = 0;
        await robot.switchLocale(
          const Locale('de'),
          bloc: bloc,
          importExport: importExport,
        );
        await robot.finishResolving();
        await tester.pump(const Duration(milliseconds: 300));
        expect(CalendarEvent.debugOccursOnCalls, 0);

        await robot.uncover();
        await robot.finishResolving();
        expect(CalendarEvent.debugOccursOnCalls, greaterThan(0));
        expect(robot.yearTiles(year), findsNWidgets(12));
        expect(robot.navCount, isNotEmpty);
      });

      testWidgets('R6: a far year folded under one query shows the '
          'placeholder under the next, then its counts after one frame — '
          'never the old counts', (tester) async {
        emitEvents([everyDay]);
        final semantics = tester.ensureSemantics();
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: phone,
        );
        await robot.finishResolving();
        final extent = robot.yearSectionExtent;
        final base = robot.yearsOffset;
        double offsetOf(int target) => base + (target - year) * extent;
        final far = year - 10;

        // Under no query, the far year is folded from marks.
        await robot.jumpYearsTo(offsetOf(far));
        await robot.finishResolving();
        expect(headerLabel(tester, far), '$far, ${count(daysIn(far))}');
        await robot.jumpYearsTo(offsetOf(year));
        await robot.finishResolving();

        await robot.typeQuery('zzz');
        await robot.finishResolving();

        await robot.jumpYearsTo(offsetOf(far), settle: false);
        expect(headerLabel(tester, far), '$far');
        expect(
          tester.widget<YearMonthTile>(robot.yearTiles(far).first).count,
          '',
        );
        await tester.pump();
        expect(headerLabel(tester, far), '$far, ${count(0)}');
        semantics.dispose();
      });

      testWidgets('R8: a run resolving one year builds exactly its twelve '
          'tiles and its one header', (tester) async {
        emitEvents([everyDay]);
        final robot = OverviewRobot(tester);
        await robot.open(
          bloc: bloc,
          importExport: importExport,
          surface: phone,
        );
        await robot.finishResolving();
        final far = year - 10;
        // The frame the jump draws builds the far sections as placeholders;
        // the run at its end resolves the top one.
        await robot.jumpYearsTo(
          robot.yearsOffset - 10 * robot.yearSectionExtent,
          settle: false,
        );
        expect(robot.builtYears, hasLength(greaterThan(1)));

        var tileBuilds = 0;
        var headerBuilds = 0;
        final tileYears = <String>{};
        debugOnRebuildDirtyWidget = (element, _) {
          final widget = element.widget;
          if (widget is YearMonthTile) {
            tileBuilds++;
            tileYears.add(widget.label.substring(widget.label.length - 4));
          }
          if (widget.runtimeType.toString() == '_YearHeader') headerBuilds++;
        };
        try {
          await tester.pump();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }
        expect(tileBuilds, 12);
        expect(headerBuilds, 1);
        expect(tileYears, {'$far'});
        expect(robot.navCount, count(daysIn(far)));
      });
    });
  });
}
