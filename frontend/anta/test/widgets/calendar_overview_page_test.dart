import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
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
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/date_span_label.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/agenda_year_pager.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/month_dot_matrix.dart';
import 'package:anta/widgets/month_year_picker_sheet.dart';
import 'package:anta/widgets/year_month_tile.dart';

import '../database/support/db_test_support.dart';
import 'support/layout_errors.dart';
import 'support/overview_robot.dart';

/// The overview owns no data: it reads the app-wide bloc's loaded state,
/// resolves whole calendar years through the same scan the agenda uses, and
/// routes every tap back to the calendar. So the suite hands it a loaded
/// bloc, watches what it draws, and watches where a tap goes.
void main() {
  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;

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
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
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

  Future<List<(DateTime, String)>> pumpPage(WidgetTester tester) async {
    final opened = <(DateTime, String)>[];
    await tester.pumpWidget(
      app(
        home: CalendarOverviewPage.forTesting(
          openOccurrence: (day, eventId) => opened.add((day, eventId)),
        ),
      ),
    );
    await pumpUntilLoaded(tester);
    return opened;
  }

  /// Picks the presentation wearing [icon] in the title's view menu.
  Future<void> tapMode(WidgetTester tester, IconData icon) async {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.calendarViewMenu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is PopupMenuItem),
        matching: find.byIcon(icon),
      ),
    );
    await tester.pumpAndSettle();
  }

  IconButton navButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  /// [text] on the year or month nav. The Period row reads the same year in
  /// year mode, so a bare `find.text` of it finds two.
  Finder navText(String text) => find.descendant(
    of: find.byType(AgendaPeriodNav),
    matching: find.text(text),
  );

  testWidgets('opens on this year with a tile per month and its counts', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(YearMonthTile), findsNWidgets(12));
    expect(navText('$year'), findsOneWidget);

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('${tileLabel(january)}, 31 entries'),
      findsOneWidget,
    );
    handle.dispose();
    expect(navButton(tester, Icons.today_rounded).onPressed, isNull);
  });

  testWidgets('the year chevrons page and the this-year button returns', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    await tester.pumpAndSettle();
    expect(navText('${year - 1}'), findsOneWidget);
    expect(navButton(tester, Icons.today_rounded).onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.today_rounded));
    await tester.pumpAndSettle();
    expect(navText('$year'), findsOneWidget);
  });

  testWidgets('the years stop where the events do', (tester) async {
    await pumpPage(tester);

    // The oldest event is two years back; the daily one is open-ended, so
    // the future stays reachable.
    expect(navButton(tester, Icons.chevron_right_rounded).onPressed, isNotNull);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    await tester.pumpAndSettle();
    expect(navText('${year - 2}'), findsOneWidget);
    expect(navButton(tester, Icons.chevron_left_rounded).onPressed, isNull);

    // A fling past the first page goes nowhere.
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(navText('${year - 2}'), findsOneWidget);
  });

  testWidgets('a swipe pages the years', (tester) async {
    await pumpPage(tester);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(navText('${year - 1}'), findsOneWidget);
  });

  testWidgets('the year title opens the jump picker and its pick lands', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(navText('$year'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthYearPickerSheet), findsOneWidget);

    // Apply with the wheels where they opened: this year, this month.
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthYearPickerSheet), findsNothing);
    expect(navText('$year'), findsOneWidget);
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
    final matrix = tester.widget<MonthDotMatrix>(
      find.byType(MonthDotMatrix).at(2),
    );
    expect(matrix.markedColor, const Color(0xFFEC407A));
  });

  testWidgets('several categories paint each day in its top entry\'s colour', (
    tester,
  ) async {
    await pumpPage(tester);

    final march = tester.widget<MonthDotMatrix>(
      find.byType(MonthDotMatrix).at(2),
    );
    // Day 9 carries the gym event and the mobility class; the gym one leads
    // by title, so the square wears gym blue like every other day.
    expect(march.dayColors, isNotNull);
    expect(march.dayColors![8], const Color(0xFF1E88E5));
  });

  testWidgets('a tile opens its month, a row tap opens the occurrence', (
    tester,
  ) async {
    final opened = await pumpPage(tester);

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
    await tester.pump();

    expect(opened, [(DateTime.utc(year, 3, 9), 'e2')]);
  });

  testWidgets('list mode lists the year under month and day headers', (
    tester,
  ) async {
    await pumpPage(tester);
    await tapMode(tester, Icons.format_list_bulleted_rounded);
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
        'the presentations below', (tester) async {
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
      // The page opens in year mode: Year · Month · List, Year checked.
      for (final row in [
        SemanticsIds.overviewViewYear,
        SemanticsIds.overviewViewMonth,
        SemanticsIds.overviewViewList,
      ]) {
        expect(id(row), findsOneWidget, reason: row);
      }
      expect(
        find.descendant(
          of: id(SemanticsIds.overviewViewYear),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
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
            builder: (_) =>
                CalendarOverviewPage.forTesting(openOccurrence: (_, _) {}),
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
          tester.widget<AgendaYearPager>(find.byType(AgendaYearPager)).color;
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

    Future<List<(DateTime, String)>> openList(
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
      await openList(robot);

      expect(robot.countOf('Rowing'), 2);
      expect(robot.shows(dayLabel(DateTime.utc(year, 1, 2))), isFalse);
      expect(robot.shows(count(0, missed: 1)), isFalse);
      expect(robot.entryOpacity('Rowing', index: 1), isNull);
      expect(robot.navCount, count(3));
    });

    testWidgets('a row tap reports its day and event', (tester) async {
      final robot = OverviewRobot(tester);
      final opened = await openList(robot);
      // Slice 4: the list opens landed on today (D7); March is above it.
      await robot.scrollListTo(0);

      await robot.tapRow('Stretch class');

      expect(opened, [(DateTime.utc(year, 3, 9), 'e2')]);
    });

    testWidgets('list mode has no nav: the Period row is the period control', (
      tester,
    ) async {
      final robot = OverviewRobot(tester);
      await openList(robot);

      expect(find.byType(AgendaPeriodNav), findsNothing);
      expect(robot.periodValue, '$year');
      expect(robot.periodChoice, OverviewPeriodChoice.thisYear);
      expect(robot.periodEnabled, isTrue);
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
      expect(robot.periodChoice, OverviewPeriodChoice.custom);
      expect(robot.shows(robot.emptyPeriodText), isTrue);
      expect(robot.shows('Leg day'), isFalse);
      expect(robot.navCount, count(0));

      await robot.pickCustomYear(year - 2);
      expect(robot.shows('Old checkup'), isTrue);
      expect(robot.listOffset, 0);

      await robot.pickPeriod(OverviewPeriodChoice.custom);
      await robot.cancelRange();
      expect(robot.shows('Old checkup'), isTrue);
      expect(robot.periodChoice, OverviewPeriodChoice.custom);
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
      expect(robot.periodChoice, OverviewPeriodChoice.last90Days);
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
      await openList(robot);
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
      await openList(robot);
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

      testWidgets('opening scans the year once, and nothing prewarms (R7)', (
        tester,
      ) async {
        CalendarEvent.debugOccursOnCalls = 0;
        await openList(OverviewRobot(tester));
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));

        // R7: the list has no year to page to, so no neighbour is warmed.
        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));
      });

      testWidgets('a keystroke pause scans nothing, and nothing prewarms '
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

        // The tiles were folded from marks; a search needs the rows.
        CalendarEvent.debugOccursOnCalls = 0;
        await robot.typeQuery('leg');
        expect(CalendarEvent.debugOccursOnCalls, daysIn(year));

        CalendarEvent.debugOccursOnCalls = 0;
        // Each pause lands inside the last one's 250 ms prewarm, which it
        // cancels: what is counted is the queries alone.
        await robot.typeQuery('le');
        await robot.typeQuery('zzz');
        expect(CalendarEvent.debugOccursOnCalls, 0);
        expect(robot.navCount, count(0));
      });

      testWidgets('a preset scans only the months it adds, and nothing '
          'prewarms (R7)', (tester) async {
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

      testWidgets('a period that is not a year never prewarms, not even under '
          'the year tiles (R7)', (tester) async {
        final robot = OverviewRobot(tester);
        await openList(
          robot,
          period: const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
        );
        CalendarEvent.debugOccursOnCalls = 0;
        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, 0);

        await robot.selectMode(AgendaDayListMode.year);
        CalendarEvent.debugOccursOnCalls = 0;
        await tester.pump(const Duration(milliseconds: 250));
        expect(CalendarEvent.debugOccursOnCalls, 0);
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

    testWidgets('a row tap with the calendar beneath pushes a calendar over '
        'the overview; back returns to the list (R1)', (tester) async {
      addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
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

      await robot.tapRow('Leg day', settle: false);
      // Frames rather than a settle: the pushed calendar's own loading need
      // not settle for this.
      for (var i = 0; i < 60 && robot.isOpen; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final pushed = tester.widget<CalendarPage>(find.byType(CalendarPage));
      expect(pushed.initialEventId, 'e1');
      expect(robot.isOpen, isFalse);
      expect(robot.isAlive, isTrue, reason: 'the overview survives beneath');
      expect(AppNavigator.pendingCalendarOccurrence.value, isNull);
      // Unstamped: launch restore reopens the overview, never a calendar
      // replayed over it.
      expect(history.stack, restorable);

      // The calendar lands on the occurrence with its detail sheet up: back
      // closes the sheet, then the calendar.
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailSheet), findsOneWidget);
      await robot.back();
      expect(find.byType(CalendarPage), findsOneWidget);
      await robot.back();

      expect(find.byType(CalendarPage), findsNothing);
      expect(robot.isOpen, isTrue);
      expect(robot.currentMode, AgendaDayListMode.list);
      expect(robot.periodChoice, OverviewPeriodChoice.last90Days);
      expect(robot.calendarBeneathVisible, isFalse);
      expect(history.stack, restorable);
    });

    testWidgets('a second trip to an occurrence opens it on the calendar the '
        'overview pushed, stacking nothing', (tester) async {
      addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
      final robot = OverviewRobot(tester);
      await robot.openAboveCalendar(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.list,
      );
      await robot.tapRow('Leg day', settle: false);
      for (var i = 0; i < 60 && robot.isOpen; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
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
      await robot.tapRow('Leg day', settle: false);
      for (var i = 0; i < 60 && robot.isOpen; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
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

    testWidgets('from the drawer, with no calendar beneath, a row tap pushes '
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

      await robot.tapRow('Leg day', settle: false);
      for (var i = 0; i < 60 && robot.isOpen; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

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

    testWidgets('the categories row reads back All, two names, then "+N '
        'more"', (tester) async {
      final robot = OverviewRobot(tester);
      await openList(robot);
      expect(robot.categoriesValue, en.calendarFilterCategoriesAll);

      final catalog = CalendarCategories.visiblePlus(const {});
      List<String> labelsOf(Set<String> ids) => [
        for (final category in catalog)
          if (ids.contains(category.id))
            CalendarCategories.labelOf(category, en),
      ];

      await robot.pickCategories({'gym', 'mobility'});
      expect(robot.categoriesValue, labelsOf({'gym', 'mobility'}).join(', '));

      await robot.pickCategories({'gym', 'mobility', 'other'});
      final three = labelsOf({'gym', 'mobility', 'other'});
      expect(
        robot.categoriesValue,
        '${three[0]}, ${three[1]} ${en.categoriesMore(1)}',
      );
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
      expect(robot.periodChoice, OverviewPeriodChoice.custom);
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
      await robot.jumpTo(january);
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
      expect(robot.options.enabled(SemanticsIds.overviewMissedOnly), isTrue);
      await robot.options.close();

      await robot.selectMode(AgendaDayListMode.list);
      await robot.openOptions();
      expect(robot.options.enabled(SemanticsIds.overviewOrder), isTrue);
      expect(robot.options.enabled(SemanticsIds.overviewRows), isTrue);
    });

    testWidgets('the Period row reads year mode\'s year and is inert in month '
        'mode', (tester) async {
      final robot = OverviewRobot(tester);
      await robot.open(bloc: bloc, importExport: importExport);

      expect(robot.periodValue, '$year');
      expect(robot.periodChoice, OverviewPeriodChoice.thisYear);

      await robot.previous();
      expect(robot.periodValue, '${year - 1}');
      expect(robot.periodChoice, OverviewPeriodChoice.custom);

      await robot.selectMode(AgendaDayListMode.list);
      expect(robot.periodValue, '${year - 1}', reason: 'paging set the period');

      await robot.selectMode(AgendaDayListMode.month);
      expect(robot.periodEnabled, isFalse);
      await robot.tapPeriodRow();
      expect(robot.menuOpen, isFalse);
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
      expect(robot.periodChoice, OverviewPeriodChoice.last12Months);
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
        (smallPhone, Locale('de'), 2.0),
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
          for (var i = 0; i < 200 && robot.rowTopInView(march) == null; i++) {
            await robot.scrollListTo(robot.listOffset + 300);
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
          final opened = await openList(robot, surface: phone);

          await robot.setRows(OverviewRows.perEvent);
          await robot.tapRow('Warm-up');

          expect(opened, [(DateTime.utc(year, 1, 20), 'w1')]);
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
          await robot.jumpTo(january);
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
        expect(robot.periodChoice, OverviewPeriodChoice.thisYear);
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
        await robot.openViewMenu();

        emitEvents([dailyFrom(4)]);
        await robot.pumpWithoutTurns();
        await robot.pickOpenMode(AgendaDayListMode.month, settle: false);
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

        await robot.selectMode(AgendaDayListMode.year);
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
  });
}
