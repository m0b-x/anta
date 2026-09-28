import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/utils/date_stamp.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/year_month_tile.dart';

/// The multi-date picker as three views over one set — month to pick, year
/// to see and travel, list to review and remove — plus the footer that stamps
/// the picked dates forward. Single mode must stay the bare grid it was.
/// Since the 2026-09-27 Tier 1 pass the chrome is the language's: ✕ · title ·
/// Save in the header, Today a fixed slot in the month and year navigation
/// rows — the cases address them by `SemanticsIds`.
void main() {
  DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

  Finder byId(String id) => find.bySemanticsIdentifier(id);

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
    bool allowEmpty = false,
    Locale locale = const Locale('en'),
    Size size = const Size(412, 915),
    double textScale = 1.0,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    final results = <Set<DateTime>?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
                    allowEmpty: allowEmpty,
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
    await tester.tap(byId(SemanticsIds.datePickerSave));
    await tester.pumpAndSettle();
  }

  /// Save is the header's text button; its handler says whether it is live.
  VoidCallback? saveOnPressed(WidgetTester tester) => tester
      .widget<TextButton>(
        find.descendant(
          of: byId(SemanticsIds.datePickerSave),
          matching: find.byType(TextButton),
        ),
      )
      .onPressed;

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
    expect(saveOnPressed(tester), isNull);
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
    // Disabled, never hidden: the header's text button stays where it was.
    expect(
      find.ancestor(
        of: byId(SemanticsIds.datePickerSave),
        matching: find.byType(FormHeaderTextButton),
      ),
      findsOneWidget,
    );
    expect(saveOnPressed(tester), isNull);
  });

  testWidgets('an empty set keeps Save live when the caller allows it', (
    tester,
  ) async {
    final results = await openMulti(tester, physio, allowEmpty: true);
    await tapText(tester, 'Clear');

    expect(saveOnPressed(tester), isNotNull);
    await save(tester);
    expect(results.single, isEmpty);
  });

  testWidgets('the header is ✕ · title · Save, and ✕ pops nothing', (
    tester,
  ) async {
    final results = await openMulti(tester, physio);

    expect(find.byType(FormSheetHeader), findsOneWidget);
    expect(find.text('Pick dates'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byIcon(Icons.today_rounded), findsOneWidget);

    await tester.tap(byId(SemanticsIds.datePickerCancel));
    await tester.pumpAndSettle();
    expect(results, [null]);
    expect(find.byType(CalendarDatePickerSheet), findsNothing);
  });

  testWidgets('single mode has no Save and answers on the day tap', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    final results = <DateTime?>[];
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
                  await CalendarDatePickerSheet.pickSingle(
                    context,
                    initialDate: d(2026, 9, 25),
                    firstDate: CalendarBounds.earliest,
                    lastDate: CalendarBounds.latest,
                    appearance: const CalendarAppearance(),
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

    expect(find.text('Pick a date'), findsOneWidget);
    expect(byId(SemanticsIds.datePickerSave), findsNothing);
    expect(byId(SemanticsIds.datePickerCancel), findsOneWidget);
    expect(byId(SemanticsIds.datePickerToday), findsOneWidget);

    await tester.tap(gridDay(d(2026, 9, 28)));
    await tester.pumpAndSettle();
    expect(results, [d(2026, 9, 28)]);
  });

  testWidgets('the Today slot sits in the month and year navigation rows and '
      'not in the list', (tester) async {
    final now = DateTime.now();
    final today = d(now.year, now.month, now.day);
    await openMulti(tester, physio);

    expect(byId(SemanticsIds.datePickerToday), findsOneWidget);
    expect(find.byTooltip('Today'), findsOneWidget);
    expect(
      tester.getSize(byId(SemanticsIds.datePickerToday)).width,
      AgendaPeriodNav.slot,
    );

    await tester.tap(viewSegment('Year'));
    await tester.pumpAndSettle();
    expect(byId(SemanticsIds.datePickerToday), findsOneWidget);
    await tester.tap(find.byTooltip('Next year'));
    await tester.pumpAndSettle();
    expect(find.text('2027'), findsOneWidget);
    // Today in the year view pages back to the current year.
    await tester.tap(byId(SemanticsIds.datePickerToday));
    await tester.pumpAndSettle();
    expect(find.text('${now.year}'), findsOneWidget);
    expect(find.byType(YearMonthTile), findsNWidgets(12));

    await tester.tap(viewSegment('List'));
    await tester.pumpAndSettle();
    expect(byId(SemanticsIds.datePickerToday), findsNothing);

    // Today in the month view lands on the current month's grid.
    await tester.tap(viewSegment('Month'));
    await tester.pumpAndSettle();
    await tester.tap(byId(SemanticsIds.datePickerToday));
    await tester.pumpAndSettle();
    expect(gridDay(today), findsOneWidget);
  });

  testWidgets("the month navigation row is 48 dp, AgendaPeriodNav's height", (
    tester,
  ) async {
    // The package pads its header 8 dp above and below the chevrons — a
    // 64 dp row where every other ‹ title [today] › row of the language is
    // 48; the sheet zeroes that padding. Wide enough for the title to sit on
    // one line even in the test font, whose em-square glyphs are twice
    // Roboto's width.
    await openMulti(tester, physio, size: const Size(800, 1400));

    final chevron = find.byIcon(Icons.chevron_left_rounded);
    expect(chevron, findsOneWidget);
    final row = find.ancestor(of: chevron, matching: find.byType(Row)).first;
    expect(tester.getSize(row).height, AgendaPeriodNav.slot);
    expect(tester.getSize(chevron.first).height, lessThanOrEqualTo(48));
    expect(
      tester.getSize(byId(SemanticsIds.datePickerToday)).height,
      AgendaPeriodNav.slot,
    );
  });

  testWidgets('at text scale 2.0 the month title wraps to two lines with '
      'its year, and the row is one height for every month', (tester) async {
    // 600 dp wide: in the test font "September 2026" needs two lines here
    // and "Mai 2026" one, which is exactly the pair the reservation exists
    // for — the row must not grow and shrink as the grid pages.
    await openMulti(
      tester,
      physio,
      locale: const Locale('de'),
      size: const Size(600, 1000),
      textScale: 2.0,
    );

    final title = find.text('September 2026');
    expect(title, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(title);
    expect(paragraph.didExceedMaxLines, isFalse);
    final replica = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
      maxLines: FormMetrics.periodTitleMaxLines,
    )..layout(maxWidth: paragraph.size.width);
    expect(replica.computeLineMetrics().length, 2);
    replica.dispose();
    // The header's paragraph is reused across page changes, so its height
    // is read now, before it lays "Mai 2026" out.
    final septemberHeight = paragraph.size.height;
    final chevron = find.byIcon(Icons.chevron_left_rounded);
    final row = find.ancestor(of: chevron, matching: find.byType(Row)).first;
    final rowHeight = tester.getSize(row).height;
    expect(rowHeight, greaterThan(AgendaPeriodNav.slot));

    for (var i = 0; i < 4; i++) {
      await tester.tap(chevron);
      await tester.pumpAndSettle();
    }
    expect(find.text('Mai 2026'), findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(find.text('Mai 2026')).size.height,
      lessThan(septemberHeight),
      reason: 'one line where September took two',
    );
    expect(tester.getSize(row).height, rowHeight);
  });

  testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
      'overflows and the header keeps ✕, the title and Speichern', (
    tester,
  ) async {
    await openMulti(
      tester,
      physio,
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Daten wählen'), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Leeren'), findsOneWidget);
    expect(byId(SemanticsIds.datePickerCancel), findsOneWidget);
    expect(byId(SemanticsIds.datePickerToday), findsOneWidget);
    // The header stays a single 48 dp row: Speichern beside the title, not
    // under it.
    expect(
      tester.getSize(find.byType(FormSheetHeader)).height,
      FormMetrics.headerHeight,
    );
    // The month title may wrap rather than ellipsize ("Septem…") — the wrap
    // itself is pinned on a wider surface, the test font being twice
    // Roboto's width — and the weekday labels are the calendar page's, whole
    // where the package's default was cut in half at this scale.
    final title = find.text('September 2026');
    expect(title, findsOneWidget);
    expect(
      tester.widget<Text>(title).maxLines,
      FormMetrics.periodTitleMaxLines,
    );
    expect(tester.widget<Text>(title).softWrap, isTrue);
    final monday = find.text(DateFormat.E('de').format(DateTime(2026, 9, 28)));
    expect(monday, findsOneWidget);
    final weekday = tester.widget<Text>(monday);
    final labelMedium = Theme.of(tester.element(monday)).textTheme.labelMedium!;
    expect(weekday.style?.fontSize, labelMedium.fontSize);
    expect(weekday.style?.fontWeight, FontWeight.w600);

    await tester.tap(viewSegment('Jahr'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The grid builds lazily, so only the tiles that fit the viewport exist.
    expect(find.byType(YearMonthTile), findsWidgets);
    expect(byId(SemanticsIds.datePickerToday), findsOneWidget);

    await tester.tap(viewSegment('Liste'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Gewählte Daten wiederholen…'), findsOneWidget);
  });
}
