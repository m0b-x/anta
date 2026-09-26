import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/utils/date_stamp.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/year_month_tile.dart';

/// The multi-date picker as three views over one set — month to pick, year
/// to see and travel, list to review and remove — plus the footer that stamps
/// the picked dates forward. Single mode must stay the bare grid it was.
void main() {
  DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

  final physio = {
    d(2026, 9, 25),
    d(2026, 10, 2),
    d(2026, 10, 9),
    d(2026, 10, 16),
  };

  Future<List<Set<DateTime>?>> openMulti(
    WidgetTester tester,
    Set<DateTime> initial, {
    CalendarDatePickerView view = CalendarDatePickerView.month,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    final results = <Set<DateTime>?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await CalendarDatePickerSheet.pickMulti(
                    context,
                    initialSelection: initial,
                    firstDate: CalendarBounds.earliest,
                    lastDate: CalendarBounds.latest,
                    appearance: const CalendarAppearance(),
                    initialView: view,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Finder viewSegment(String label) => find.descendant(
    of: find.byType(SegmentedButton<CalendarDatePickerView>),
    matching: find.text(label),
  );

  Finder unitSegment(String label) => find.descendant(
    of: find.byType(SegmentedButton<DateStampUnit>),
    matching: find.text(label),
  );

  Finder gridDay(DateTime day) => find.byWidgetPredicate(
    (w) => w is CalendarDayCell && w.day == day && !w.isOutside,
  );

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('single mode stays the bare grid', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: CalendarDatePickerSheet(
            mode: CalendarDatePickerMode.single,
            initialSelection: {d(2026, 9, 25)},
            firstDate: CalendarBounds.earliest,
            lastDate: CalendarBounds.latest,
            appearance: const CalendarAppearance(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<CalendarDatePickerView>), findsNothing);
    expect(find.text('Repeat the picked dates…'), findsNothing);
    expect(find.text('Clear'), findsNothing);
    expect(gridDay(d(2026, 9, 25)), findsOneWidget);
  });

  testWidgets('multi mode reads the set back under the header', (tester) async {
    await openMulti(tester, physio);

    expect(find.text('4 dates · Sep 25 – Oct 16, 2026'), findsOneWidget);
    expect(gridDay(d(2026, 9, 25)), findsOneWidget);

    await tester.tap(gridDay(d(2026, 9, 28)));
    await tester.pumpAndSettle();
    expect(find.text('5 dates · Sep 25 – Oct 16, 2026'), findsOneWidget);
  });

  testWidgets('year view marks the picked months and opens one on the grid', (
    tester,
  ) async {
    await openMulti(tester, physio);
    await tester.tap(viewSegment('Year'));
    await tester.pumpAndSettle();

    expect(find.byType(YearMonthTile), findsNWidgets(12));
    expect(find.text('2026'), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Sep 2026, 1 date selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Oct 2026, 3 dates selected'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Nov 2026, No dates selected'),
      findsOneWidget,
    );
    handle.dispose();

    await tester.tap(find.byTooltip('Next year'));
    await tester.pumpAndSettle();
    expect(find.text('2027'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(YearMonthTile, 'Oct 2026'));
    await tester.pumpAndSettle();
    expect(gridDay(d(2026, 10, 2)), findsOneWidget);
    expect(find.byType(YearMonthTile), findsNothing);
  });

  testWidgets('list view lists every date in order with a remove button', (
    tester,
  ) async {
    final results = await openMulti(tester, physio);
    await tester.tap(viewSegment('List'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove date'), findsNWidgets(4));
    expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    expect(find.text('OCTOBER 2026'), findsOneWidget);
    expect(find.widgetWithText(FormPickerRow, 'Fri, Sep 25'), findsOneWidget);
    expect(find.text('1 of 4'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(FormPickerRow, 'Fri, Oct 2'),
        matching: find.byTooltip('Remove date'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove date'), findsNWidgets(3));
    expect(find.text('3 dates · Sep 25 – Oct 16, 2026'), findsOneWidget);

    await save(tester);
    expect(results.single, {d(2026, 9, 25), d(2026, 10, 9), d(2026, 10, 16)});
  });

  testWidgets('a list row opens its month on the grid', (tester) async {
    await openMulti(tester, physio, view: CalendarDatePickerView.list);
    expect(find.byTooltip('Remove date'), findsNWidgets(4));

    await tapText(tester, 'Fri, Oct 16');
    expect(gridDay(d(2026, 10, 16)), findsOneWidget);
  });

  testWidgets('the list has an empty state and the footer is inert', (
    tester,
  ) async {
    await openMulti(tester, {}, view: CalendarDatePickerView.list);

    expect(
      find.text('No dates yet. Pick them in Month or Year.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FormActionRow>(
            find.widgetWithText(FormActionRow, 'Repeat the picked dates…'),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('repeat stamps the picked dates forward into the list', (
    tester,
  ) async {
    final results = await openMulti(tester, {d(2026, 3, 15)});
    await tapText(tester, 'Repeat the picked dates…');

    await tester.tap(unitSegment('Year'));
    await tester.pumpAndSettle();
    expect(find.text('3 more'), findsOneWidget);
    expect(find.text('Adds 3 dates · through Mar 15, 2029'), findsOneWidget);

    await tester.tap(find.byTooltip('Fewer'));
    await tester.pumpAndSettle();
    expect(find.text('Adds 2 dates · through Mar 15, 2028'), findsOneWidget);

    await tapText(tester, 'Add 2 dates');
    expect(find.byTooltip('Remove date'), findsNWidgets(3));
    expect(find.text('3 dates · Mar 15, 2026 – Mar 15, 2028'), findsOneWidget);
    expect(find.text('Repeat the picked dates…'), findsOneWidget);

    await save(tester);
    expect(results.single, {d(2026, 3, 15), d(2027, 3, 15), d(2028, 3, 15)});
  });

  testWidgets('repeat names the days that do not exist', (tester) async {
    await openMulti(tester, {d(2026, 1, 31)});
    await tapText(tester, 'Repeat the picked dates…');

    expect(
      find.text('Adds 1 date · through Mar 31, 2026 · 2 skipped, no such day'),
      findsOneWidget,
    );

    await tester.tap(unitSegment('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Adds 3 dates · through Feb 21, 2026'), findsOneWidget);

    await tapText(tester, 'Cancel');
    expect(find.text('Repeat the picked dates…'), findsOneWidget);
    expect(find.byType(SegmentedButton<DateStampUnit>), findsNothing);
  });

  testWidgets('clearing everything disables Save', (tester) async {
    await openMulti(tester, physio);
    await tapText(tester, 'Clear');

    expect(find.text('No dates selected'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
  });
}
