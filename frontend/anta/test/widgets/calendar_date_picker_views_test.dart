import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/utils/date_stamp.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/month_dot_matrix.dart';
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

  /// One span on the same grid (`docs/calendar-overview-list-roadmap.md`
  /// §3.5, T7, T10): ✕ · Period · Apply, a summary slot of one height, Month
  /// and Year only, the span's ends filled and the days between on a band,
  /// and year tiles that pick whole months.
  group('range mode', () {
    /// Mar 15 – Jun 20, 2026: opens on March, whose first is a Sunday — so
    /// with the default Monday start the 15th ends a row and the 16th
    /// begins the next.
    final spring = (start: d(2026, 3, 15), end: d(2026, 6, 20));

    Future<List<DateRange?>> openRange(
      WidgetTester tester, {
      DateRange? initial,
      DateTime? firstDate,
      DateTime? lastDate,
      Locale locale = const Locale('en'),
      Size size = const Size(412, 915),
      double textScale = 1.0,
    }) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      final results = <DateRange?>[];
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
                    await CalendarDatePickerSheet.pickRange(
                      context,
                      initialRange: initial,
                      firstDate: firstDate ?? CalendarBounds.earliest,
                      lastDate: lastDate ?? CalendarBounds.latest,
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
      return results;
    }

    Future<void> tapDay(WidgetTester tester, DateTime day) async {
      await tester.tap(gridDay(day));
      await tester.pumpAndSettle();
    }

    Future<void> showView(WidgetTester tester, String label) async {
      await tester.tap(viewSegment(label));
      await tester.pumpAndSettle();
    }

    Finder tile(String label) => find.widgetWithText(YearMonthTile, label);

    Future<void> tapTile(WidgetTester tester, String label) async {
      await tester.tap(tile(label));
      await tester.pumpAndSettle();
    }

    MonthDotMatrix matrixOf(WidgetTester tester, String label) =>
        tester.widget<MonthDotMatrix>(
          find.descendant(
            of: tile(label),
            matching: find.byType(MonthDotMatrix),
          ),
        );

    Color accentOf(WidgetTester tester) => Theme.of(
      tester.element(find.byType(CalendarDatePickerSheet)),
    ).colorScheme.primary;

    String oneDay(DateTime day) =>
        '${DateFormat.yMMMd('en').format(day)} · 1 day';

    /// The band behind [cell], left half then right: a half's decoration,
    /// or null where it is unpainted; empty when the cell has no band.
    List<BoxDecoration?> bandOf(WidgetTester tester, Finder cell) {
      final stack = find.ancestor(of: cell, matching: find.byType(Stack)).first;
      final band = find.descendant(
        of: stack,
        matching: find.byWidgetPredicate(
          (w) => w is Positioned && w.top == CalendarDayCell.chipTop,
        ),
      );
      if (band.evaluate().isEmpty) return const [];
      return [
        for (final half in tester.widgetList<Expanded>(
          find.descendant(of: band, matching: find.byType(Expanded)),
        ))
          switch (half.child) {
            DecoratedBox(:final decoration) => decoration as BoxDecoration,
            _ => null,
          },
      ];
    }

    bool isEnd(WidgetTester tester, DateTime day) =>
        tester.widget<CalendarDayCell>(gridDay(day)).isSelected;

    testWidgets('the header is ✕ · Period · Apply over Month and Year, with '
        'no list, footer or Clear', (tester) async {
      await openRange(tester, initial: spring);

      expect(find.byType(FormSheetHeader), findsOneWidget);
      expect(find.text('Period'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(byId(SemanticsIds.datePickerCancel), findsOneWidget);
      expect(byId(SemanticsIds.datePickerToday), findsOneWidget);
      expect(viewSegment('Month'), findsOneWidget);
      expect(viewSegment('Year'), findsOneWidget);
      expect(viewSegment('List'), findsNothing);
      expect(find.text('Repeat the picked dates…'), findsNothing);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('Apply returns the span drawn on the grid', (tester) async {
      final now = DateTime.now();
      final first = d(now.year, now.month, 10);
      final last = d(now.year, now.month, 20);
      final results = await openRange(tester);

      await tapDay(tester, first);
      await tapDay(tester, last);
      expect(
        find.text(
          '${DateFormat.MMMd('en').format(first)} – '
          '${DateFormat.yMMMd('en').format(last)} · 11 days',
        ),
        findsOneWidget,
      );
      await save(tester);

      expect(results, [(start: first, end: last)]);
      expect(find.byType(CalendarDatePickerSheet), findsNothing);
    });

    testWidgets('an initial span reaching past the bounds opens clamped to '
        'them at both ends (review 8)', (tester) async {
      final results = await openRange(
        tester,
        initial: spring,
        firstDate: d(2026, 4, 1),
        lastDate: d(2026, 5, 31),
      );

      await save(tester);

      expect(results, [(start: d(2026, 4, 1), end: d(2026, 5, 31))]);
    });

    testWidgets('a start alone applies as its one day', (tester) async {
      final now = DateTime.now();
      final day = d(now.year, now.month, 10);
      final results = await openRange(tester);

      await tapDay(tester, day);
      expect(find.text(oneDay(day)), findsOneWidget);
      await save(tester);

      expect(results, [(start: day, end: day)]);
    });

    testWidgets('✕, the barrier and a drag down return null', (tester) async {
      final results = await openRange(tester, initial: spring);

      await tester.tap(byId(SemanticsIds.datePickerCancel));
      await tester.pumpAndSettle();
      expect(results, [null]);

      await tapText(tester, 'open');
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(results, [null, null]);

      await tapText(tester, 'open');
      await tester.drag(find.byType(FormSheetHandle), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(results, [null, null, null]);
      expect(find.byType(CalendarDatePickerSheet), findsNothing);
    });

    testWidgets('Apply is disabled, never hidden, while there is no start', (
      tester,
    ) async {
      final results = await openRange(tester);

      expect(find.text('Pick a start day'), findsOneWidget);
      expect(
        find.ancestor(
          of: byId(SemanticsIds.datePickerSave),
          matching: find.byType(FormHeaderTextButton),
        ),
        findsOneWidget,
      );
      expect(saveOnPressed(tester), isNull);

      await save(tester);
      expect(results, isEmpty);
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
    });

    testWidgets('with no start a tap sets the start', (tester) async {
      final now = DateTime.now();
      final day = d(now.year, now.month, 12);
      await openRange(tester);

      await tapDay(tester, day);

      expect(find.text(oneDay(day)), findsOneWidget);
      expect(isEnd(tester, day), isTrue);
      expect(saveOnPressed(tester), isNotNull);
    });

    testWidgets('with both ends set a tap starts over from that day', (
      tester,
    ) async {
      final results = await openRange(tester, initial: spring);
      expect(find.text('Mar 15 – Jun 20, 2026 · 98 days'), findsOneWidget);

      await tapDay(tester, d(2026, 3, 20));
      expect(find.text(oneDay(d(2026, 3, 20))), findsOneWidget);
      await save(tester);

      expect(results, [(start: d(2026, 3, 20), end: d(2026, 3, 20))]);
    });

    testWidgets('with a start alone a tap on or after it sets the end', (
      tester,
    ) async {
      final results = await openRange(tester, initial: spring);
      await tapDay(tester, d(2026, 3, 20));

      // On the start itself: a one-day span with both ends set, so a later
      // tap starts over where a start alone would have extended to it.
      await tapDay(tester, d(2026, 3, 20));
      await tapDay(tester, d(2026, 3, 25));
      expect(find.text(oneDay(d(2026, 3, 25))), findsOneWidget);

      await tapDay(tester, d(2026, 3, 28));
      expect(find.text('Mar 25 – Mar 28, 2026 · 4 days'), findsOneWidget);
      await save(tester);

      expect(results, [(start: d(2026, 3, 25), end: d(2026, 3, 28))]);
    });

    testWidgets('with a start alone a tap before it restarts the start', (
      tester,
    ) async {
      final results = await openRange(tester, initial: spring);
      await tapDay(tester, d(2026, 3, 20));

      await tapDay(tester, d(2026, 3, 5));
      expect(find.text(oneDay(d(2026, 3, 5))), findsOneWidget);
      expect(isEnd(tester, d(2026, 3, 20)), isFalse);

      await tapDay(tester, d(2026, 3, 6));
      await save(tester);
      expect(results, [(start: d(2026, 3, 5), end: d(2026, 3, 6))]);
    });

    testWidgets('a dimmed day outside the bounds refuses the tap', (
      tester,
    ) async {
      final results = await openRange(
        tester,
        initial: (start: d(2026, 3, 12), end: d(2026, 3, 14)),
        firstDate: d(2026, 3, 10),
        lastDate: d(2026, 12, 31),
      );
      // Before the bound, the 5th is the package's disabled text rather
      // than a day cell — the first "5" on the March grid (April's comes
      // last).
      expect(gridDay(d(2026, 3, 5)), findsNothing);

      await tester.tap(find.text('5').first);
      await tester.pumpAndSettle();
      expect(find.text('Mar 12 – Mar 14, 2026 · 3 days'), findsOneWidget);

      await save(tester);
      expect(results, [(start: d(2026, 3, 12), end: d(2026, 3, 14))]);
    });

    testWidgets('the ends are filled and the days between sit on one band, '
        'square inside a row and capped on its outer edges', (tester) async {
      await openRange(
        tester,
        initial: (start: d(2026, 3, 10), end: d(2026, 3, 25)),
      );
      final band = accentOf(
        tester,
      ).withValues(alpha: EventAvatar.backgroundAlpha);
      const cap = Radius.circular(CalendarDayCell.chipSize / 2);
      BoxDecoration capped(BorderRadius radius) =>
          BoxDecoration(color: band, borderRadius: radius);

      expect(isEnd(tester, d(2026, 3, 10)), isTrue);
      expect(isEnd(tester, d(2026, 3, 25)), isTrue);
      expect(isEnd(tester, d(2026, 3, 12)), isFalse);

      // The start's band runs from its centre right, the end's from the
      // left to its centre.
      expect(bandOf(tester, gridDay(d(2026, 3, 10))), [
        null,
        capped(BorderRadius.zero),
      ]);
      expect(bandOf(tester, gridDay(d(2026, 3, 25))), [
        capped(BorderRadius.zero),
        null,
      ]);
      expect(bandOf(tester, gridDay(d(2026, 3, 12))), [
        capped(BorderRadius.zero),
        capped(BorderRadius.zero),
      ]);
      // Sunday the 15th ends a row, Monday the 16th begins the next.
      expect(bandOf(tester, gridDay(d(2026, 3, 15))), [
        capped(BorderRadius.zero),
        capped(const BorderRadius.horizontal(right: cap)),
      ]);
      expect(bandOf(tester, gridDay(d(2026, 3, 16))), [
        capped(const BorderRadius.horizontal(left: cap)),
        capped(BorderRadius.zero),
      ]);
      expect(bandOf(tester, gridDay(d(2026, 3, 9))), isEmpty);
      expect(bandOf(tester, gridDay(d(2026, 3, 26))), isEmpty);
    });

    testWidgets('an outside-month day of the span is dimmed as today', (
      tester,
    ) async {
      await openRange(
        tester,
        initial: (start: d(2026, 3, 10), end: d(2026, 4, 3)),
      );
      final accent = accentOf(tester);
      final outside = find.byWidgetPredicate(
        (w) => w is CalendarDayCell && w.day == d(2026, 4, 1) && w.isOutside,
      );

      expect(
        bandOf(tester, outside).map((half) => half?.color).toList(),
        List.filled(
          2,
          accent.withValues(
            alpha: EventAvatar.backgroundAlpha * CalendarDayCell.outsideAlpha,
          ),
        ),
      );
      expect(
        bandOf(tester, gridDay(d(2026, 3, 31))).map((half) => half?.color),
        everyElement(accent.withValues(alpha: EventAvatar.backgroundAlpha)),
      );
    });

    testWidgets('the initial span is drawn on open, on its own months', (
      tester,
    ) async {
      await openRange(tester, initial: spring);

      expect(find.text('March 2026'), findsOneWidget);
      expect(isEnd(tester, d(2026, 3, 15)), isTrue);
      expect(bandOf(tester, gridDay(d(2026, 3, 20))), hasLength(2));
      expect(bandOf(tester, gridDay(d(2026, 3, 14))), isEmpty);

      await showView(tester, 'Year');
      expect(find.text('2026'), findsOneWidget);
      expect(matrixOf(tester, 'Apr 2026').markedMask, (1 << 30) - 1);
    });

    testWidgets('the year view colours the span and its tiles pick whole '
        'months', (tester) async {
      final results = await openRange(tester, initial: spring);
      await showView(tester, 'Year');
      final accent = accentOf(tester);

      expect(find.byType(YearMonthTile), findsNWidgets(12));
      final march = matrixOf(tester, 'Mar 2026').dayColors!;
      expect(march, hasLength(31));
      expect(march[13], isNull, reason: 'Mar 14');
      expect(march.sublist(14), everyElement(accent));
      expect(matrixOf(tester, 'Apr 2026').dayColors, everyElement(accent));
      expect(matrixOf(tester, 'Jul 2026').dayColors, everyElement(isNull));
      expect(
        find.descendant(of: tile('Apr 2026'), matching: find.text('30')),
        findsOneWidget,
      );

      // A month after the span's end extends it to that month's last day,
      // keeping the start, and the view stays.
      await tapTile(tester, 'Aug 2026');
      expect(find.text('Mar 15 – Aug 31, 2026 · 170 days'), findsOneWidget);
      expect(find.byType(YearMonthTile), findsNWidgets(12));
      expect(matrixOf(tester, 'Aug 2026').dayColors, everyElement(accent));
      expect(matrixOf(tester, 'Jul 2026').dayColors, everyElement(accent));

      // A month inside the span restarts it as that whole month.
      await tapTile(tester, 'Apr 2026');
      expect(find.text('Apr 1 – Apr 30, 2026 · 30 days'), findsOneWidget);
      expect(matrixOf(tester, 'Aug 2026').dayColors, everyElement(isNull));

      // A month before the start restarts it too; then a later one makes a
      // run of whole months in two taps.
      await tapTile(tester, 'Feb 2026');
      expect(find.text('Feb 1 – Feb 28, 2026 · 28 days'), findsOneWidget);
      await tapTile(tester, 'Dec 2026');
      expect(find.text('Feb 1 – Dec 31, 2026 · 334 days'), findsOneWidget);

      // A start alone: a later tile ends the span on its last day. August's
      // tile first, inside the span, brings the grid to August.
      await tapTile(tester, 'Aug 2026');
      expect(find.text('Aug 1 – Aug 31, 2026 · 31 days'), findsOneWidget);
      await showView(tester, 'Month');
      await tapDay(tester, d(2026, 8, 10));
      await showView(tester, 'Year');
      await tapTile(tester, 'Oct 2026');
      expect(find.text('Aug 10 – Oct 31, 2026 · 83 days'), findsOneWidget);

      // A start alone: an earlier tile restarts the span as its whole month.
      await showView(tester, 'Month');
      await tapDay(tester, d(2026, 10, 10));
      await showView(tester, 'Year');
      await tapTile(tester, 'May 2026');
      expect(find.text('May 1 – May 31, 2026 · 31 days'), findsOneWidget);

      await save(tester);
      expect(results, [(start: d(2026, 5, 1), end: d(2026, 5, 31))]);
    });

    testWidgets('with no span a year tile is its whole month', (tester) async {
      final year = DateTime.now().year;
      final results = await openRange(tester);
      await showView(tester, 'Year');

      await tapTile(tester, DateFormat.yMMM('en').format(d(year, 3, 1)));
      expect(find.text('Mar 1 – Mar 31, $year · 31 days'), findsOneWidget);
      await save(tester);

      expect(results, [(start: d(year, 3, 1), end: d(year, 3, 31))]);
    });

    testWidgets('the summary keeps one height in all three states, so the '
        'grid never moves', (tester) async {
      await openRange(tester, initial: spring);
      Finder slot() => find.byType(FormCaptionSlot);
      Offset switchTop() => tester.getTopLeft(
        find.byType(SegmentedButton<CalendarDatePickerView>),
      );

      // In the test font the span takes two lines at this width.
      final span = find.text('Mar 15 – Jun 20, 2026 · 98 days');
      expect(span, findsOneWidget);
      final spanHeight = tester.getSize(span).height;
      final height = tester.getSize(slot()).height;
      final top = switchTop();

      await tapDay(tester, d(2026, 3, 20));
      final start = find.text(oneDay(d(2026, 3, 20)));
      expect(start, findsOneWidget);
      expect(tester.getSize(start).height, lessThan(spanHeight));
      expect(tester.getSize(slot()).height, height);
      expect(switchTop(), top);

      await tester.tap(byId(SemanticsIds.datePickerCancel));
      await tester.pumpAndSettle();
      await openRange(tester);
      expect(find.text('Pick a start day'), findsOneWidget);
      expect(tester.getSize(slot()).height, height);
      expect(switchTop(), top);
    });

    testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
        'overflows and the header keeps ✕, Zeitraum and Übernehmen', (
      tester,
    ) async {
      await openRange(
        tester,
        initial: spring,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Zeitraum'), findsOneWidget);
      expect(find.text('Übernehmen'), findsOneWidget);
      expect(byId(SemanticsIds.datePickerCancel), findsOneWidget);
      expect(byId(SemanticsIds.datePickerToday), findsOneWidget);
      expect(
        tester.getSize(find.byType(FormSheetHeader)).height,
        FormMetrics.headerHeight,
      );
      expect(viewSegment('Monat'), findsOneWidget);
      expect(viewSegment('Liste'), findsNothing);
      // The span may wrap to the slot's second line rather than be cut;
      // the month title wraps as the other modes' does.
      final summary = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(FormCaptionSlot),
              matching: find.byType(Text),
            )
            .last,
      );
      expect(summary.maxLines, 2);
      final title = find.text('März 2026');
      expect(title, findsOneWidget);
      expect(
        tester.widget<Text>(title).maxLines,
        FormMetrics.periodTitleMaxLines,
      );

      await tapDay(tester, d(2026, 3, 20));
      expect(tester.takeException(), isNull);

      await showView(tester, 'Jahr');
      expect(tester.takeException(), isNull);
      expect(find.byType(YearMonthTile), findsWidgets);
      expect(byId(SemanticsIds.datePickerToday), findsOneWidget);
    });
  });
}
