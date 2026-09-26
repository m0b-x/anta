import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_overview_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/month_dot_matrix.dart';
import 'package:anta/widgets/month_year_picker_sheet.dart';
import 'package:anta/widgets/year_month_tile.dart';

import '../database/support/db_test_support.dart';

/// The overview owns no data: it reads the app-wide bloc's loaded state,
/// resolves whole calendar years through the same scan the agenda uses, and
/// routes every tap back to the calendar. So the suite hands it a loaded
/// bloc, watches what it draws, and watches where a tap goes.
void main() {
  late CalendarBloc bloc;

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
    SettingsService.forTesting(await openTestDatabase());
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
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
  });

  Future<List<(DateTime, String)>> pumpPage(WidgetTester tester) async {
    final opened = <(DateTime, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<CalendarBloc>.value(
          value: bloc,
          child: CalendarOverviewPage.forTesting(
            openOccurrence: (day, eventId) => opened.add((day, eventId)),
          ),
        ),
      ),
    );
    // The settings read is a real async gap; pump a bounded number of frames
    // rather than settling, so a stalled read fails instead of hanging.
    for (var i = 0; i < 20; i++) {
      if (find.byType(YearMonthTile).evaluate().isNotEmpty ||
          find.byType(ListTile).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    return opened;
  }

  Future<void> tapMode(WidgetTester tester, IconData icon) async {
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is SegmentedButton<AgendaDayListMode>,
        ),
        matching: find.byIcon(icon),
      ),
    );
    await tester.pumpAndSettle();
  }

  IconButton navButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

  testWidgets('opens on this year with a tile per month and its counts', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(YearMonthTile), findsNWidgets(12));
    expect(find.text('$year'), findsOneWidget);

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

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('${year - 1}'), findsOneWidget);
    expect(navButton(tester, Icons.today_rounded).onPressed, isNotNull);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.today_rounded));
    await tester.pumpAndSettle();
    expect(find.text('$year'), findsOneWidget);
  });

  testWidgets('the years stop where the events do', (tester) async {
    await pumpPage(tester);

    // The oldest event is two years back; the daily one is open-ended, so
    // the future stays reachable.
    expect(navButton(tester, Icons.chevron_right_rounded).onPressed, isNotNull);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('${year - 2}'), findsOneWidget);
    expect(navButton(tester, Icons.chevron_left_rounded).onPressed, isNull);

    // A fling past the first page goes nowhere.
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('${year - 2}'), findsOneWidget);
  });

  testWidgets('a swipe pages the years', (tester) async {
    await pumpPage(tester);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('${year - 1}'), findsOneWidget);
  });

  testWidgets('the year title opens the jump picker and its pick lands', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('$year'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthYearPickerSheet), findsOneWidget);

    // Apply with the wheels where they opened: this year, this month.
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthYearPickerSheet), findsNothing);
    expect(find.text('$year'), findsOneWidget);
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
      find.text(AgendaListView.monthLabel('en', DateTime.utc(year, 3, 1),
          withYear: true)),
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

    expect(find.byType(YearMonthTile), findsNothing);
    expect(find.text('January'), findsOneWidget);
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
}
