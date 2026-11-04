import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/analytics_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_group_stack.dart';
import 'package:anta/widgets/report_when_chart.dart';
import 'package:anta/widgets/report_year_cards.dart';

import '../goldens/support/golden_fonts.dart';

/// The year in review's Records and Months cards (S6 §2.2–2.3) drawn alone,
/// with Roboto loaded so the axis and the span templates measure the real
/// font: 2025 seen from Friday 30 October 2026, and 2026 itself with
/// November and December still ahead.
void main() {
  setUpAll(() async {
    await loadGoldenFonts();
    await initializeDateFormatting();
  });

  setUp(() {
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
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  final today = DateTime.utc(2026, 10, 30);
  final year2025 = (
    start: DateTime.utc(2025, 1, 1),
    end: DateTime.utc(2025, 12, 31),
  );
  final year2026 = (
    start: DateTime.utc(2026, 1, 1),
    end: DateTime.utc(2026, 12, 31),
  );

  final events = {
    for (final (id, title, category) in const [
      ('e-lisbon', 'Lisbon', 'holiday'),
      ('e-rome', 'Rome', 'holiday'),
      ('e-car', 'Car service', 'other'),
      ('e-boiler', 'Boiler service', 'other'),
      ('e-lift', 'Lifting', 'gym'),
      ('e-run', 'Morning run', 'cardio'),
    ])
      id: CalendarEvent(
        id: id,
        title: title,
        categoryId: category,
        startDate: DateTime.utc(2025, 1, 1),
        rule: const OneTimeRecurrence(),
      ),
  };

  // Nine records, in the model's order: the four month and week records,
  // the longer of the two trips, a streak per routine and a gap per
  // service category.
  final records = [
    ReportRecord(
      kind: ReportRecordKind.busiestMonth,
      value: 31,
      start: DateTime.utc(2025, 6, 1),
      end: DateTime.utc(2025, 6, 30),
    ),
    ReportRecord(
      kind: ReportRecordKind.busiestWeek,
      value: 11,
      start: DateTime.utc(2025, 6, 16),
      end: DateTime.utc(2025, 6, 22),
    ),
    ReportRecord(
      kind: ReportRecordKind.socialMonth,
      value: 6,
      start: DateTime.utc(2025, 12, 1),
      end: DateTime.utc(2025, 12, 31),
    ),
    ReportRecord(
      kind: ReportRecordKind.moneyMonth,
      value: 134000,
      start: DateTime.utc(2025, 9, 1),
      end: DateTime.utc(2025, 9, 30),
    ),
    ReportRecord(
      kind: ReportRecordKind.longestTrip,
      categoryId: 'holiday',
      eventId: 'e-lisbon',
      value: 6,
      start: DateTime.utc(2025, 8, 4),
      end: DateTime.utc(2025, 8, 9),
    ),
    ReportRecord(
      kind: ReportRecordKind.longestStreak,
      categoryId: 'gym',
      eventId: 'e-lift',
      value: 14,
      start: DateTime.utc(2025, 3, 3),
      end: DateTime.utc(2025, 4, 10),
    ),
    ReportRecord(
      kind: ReportRecordKind.longestStreak,
      categoryId: 'cardio',
      eventId: 'e-run',
      value: 9,
      start: DateTime.utc(2025, 5, 5),
      end: DateTime.utc(2025, 6, 2),
    ),
    ReportRecord(
      kind: ReportRecordKind.longestGap,
      categoryId: 'other',
      value: 212,
      start: DateTime.utc(2025, 2, 3),
      end: DateTime.utc(2025, 9, 3),
    ),
    ReportRecord(
      kind: ReportRecordKind.longestGap,
      categoryId: 'birthday',
      value: 140,
      start: DateTime.utc(2025, 4, 1),
      end: DateTime.utc(2025, 8, 19),
    ),
  ];

  /// The nine built-ins in the Categories card's order.
  const categoryOrder = [
    'gym',
    'cardio',
    'rest',
    'measurement',
    'mobility',
    'competition',
    'holiday',
    'birthday',
    'other',
  ];

  /// Twelve values per category: gym's peak 9 in January, an empty March;
  /// the others a step each.
  final monthsOf = {
    'gym': const [9, 8, 0, 4, 2, 7, 6, 5, 3, 1, 8, 9],
    'cardio': const [60, 120, 180, 240, 0, 0, 30, 60, 90, 120, 150, 240],
    'rest': const [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    'measurement': const [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0],
    'mobility': const [2, 4, 6, 8, 2, 4, 6, 8, 2, 4, 6, 8],
    'competition': const [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
    'holiday': const [0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0],
    'birthday': const [0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0],
    'other': const [0, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
  };

  ({DateTime first, DateTime last}) spanOf(String id, int year) {
    if (id == 'measurement') {
      // One kept day: the caption reads the day alone.
      final day = DateTime.utc(year, 6, 14);
      return (first: day, last: day);
    }
    return (first: DateTime.utc(year, 1, 2), last: DateTime.utc(year, 12, 30));
  }

  CalendarReport yearReport({
    List<ReportRecord>? withRecords,
    List<String> categories = const [
      'gym',
      'cardio',
      'rest',
      'measurement',
      'mobility',
      'competition',
    ],
    Set<String> allMissed = const {},
    DateRange? span,
    bool year = true,
  }) {
    final range = span ?? year2025;
    final kept = [
      for (final id in categories)
        if (!allMissed.contains(id)) id,
    ];
    return CalendarReport(
      span: range,
      today: today,
      tense: CalendarReport.tenseOf(span: range, today: today),
      countedTo: CalendarReport.countedToOf(span: range, today: today),
      events: events,
      tiles: const [],
      skippedDays: 0,
      aheadCount: 0,
      categories: [
        for (final id in categories)
          ReportCategoryGroup(
            categoryId: id,
            count: 1,
            minutes: 0,
            missed: 0,
            rows: const [],
          ),
      ],
      missed: const [],
      ahead: const [],
      measures: {
        for (final id in categories)
          id: ReportMeasures(
            categoryId: id,
            primary: id == 'cardio' ? ReportMeasure.hours : ReportMeasure.count,
          ),
      },
      year: year
          ? ReportYear(
              records: withRecords ?? records,
              months: {for (final id in kept) id: monthsOf[id]!},
              spans: {for (final id in kept) id: spanOf(id, range.start.year)},
            )
          : null,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget Function(ReportLabels labels) card, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    double width = 360,
    bool boldText = false,
    ScrollController? scroll,
    double room = 0,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 780);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        themeAnimationStyle: AnimationStyle.noAnimation,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            boldText: boldText,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              controller: scroll,
              // The page's group inset, so the card is the page's width.
              padding: const EdgeInsets.symmetric(
                horizontal: RowMetrics.groupInset,
              ),
              children: [
                if (room > 0) SizedBox(height: room),
                card(ReportLabels(AppLocalizations.of(context)!)),
                if (room > 0) SizedBox(height: room),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  ReportLabels labelsIn(String locale) =>
      ReportLabels(lookupAppLocalizations(Locale(locale)));

  final noBreakSpace = String.fromCharCode(0x00A0);

  Finder rowWithId(String id) => find.byWidgetPredicate(
    (widget) => widget is FormMeterRow && widget.identifier == id,
  );

  Finder cardGroup() => find.byType(FormRowGroup);

  group('records', () {
    late ReportGroupFolds folds;
    final shrinks = <bool>[];

    setUp(() {
      folds = ReportGroupFolds();
      shrinks.clear();
    });

    Future<void> pumpRecords(
      WidgetTester tester, {
      CalendarReport? report,
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Brightness brightness = Brightness.light,
      double width = 360,
      bool boldText = false,
      ScrollController? scroll,
    }) => pump(
      tester,
      (labels) => ReportRecordsCard(
        report: report ?? yearReport(),
        labels: labels,
        folds: folds,
        onShrink: () => shrinks.add(folds.isRecordsExpanded),
        scroll: scroll,
        weekStart: CalendarWeekStart.monday,
      ),
      locale: locale,
      textScale: textScale,
      brightness: brightness,
      width: width,
      boldText: boldText,
      scroll: scroll,
      room: scroll == null ? 0 : 900,
    );

    String idOf(ReportRecord record) => switch (record.kind) {
      ReportRecordKind.longestStreak => SemanticsIds.reportYearRecordStreak(
        record.eventId!,
      ),
      ReportRecordKind.longestGap => SemanticsIds.reportYearRecordGap(
        record.categoryId!,
      ),
      _ => SemanticsIds.reportYearRecord(switch (record.kind) {
        ReportRecordKind.busiestMonth => 'busiest-month',
        ReportRecordKind.busiestWeek => 'busiest-week',
        ReportRecordKind.socialMonth => 'social-month',
        ReportRecordKind.moneyMonth => 'money-month',
        _ => 'longest-trip',
      }),
    };

    Finder more() =>
        find.bySemanticsIdentifier(SemanticsIds.reportYearRecordsMore);

    testWidgets('nothing without a year or a record', (tester) async {
      await pumpRecords(tester, report: yearReport(year: false));
      expect(find.byType(FormMeterRow), findsNothing);
      expect(cardGroup(), findsNothing);
      await pumpRecords(tester, report: yearReport(withRecords: const []));
      expect(find.byType(FormMeterRow), findsNothing);
    });

    testWidgets('1 and 6 records draw whole; 9 draw six and "3 more", '
        'expand to nine and "Show less", and fold back after onShrink', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpRecords(tester, report: yearReport(withRecords: [records[0]]));
      expect(find.byType(FormMeterRow), findsOneWidget);
      expect(more(), findsNothing);

      await pumpRecords(
        tester,
        report: yearReport(withRecords: records.take(6).toList()),
      );
      expect(find.byType(FormMeterRow), findsNWidgets(6));
      expect(more(), findsNothing);

      await pumpRecords(tester);
      expect(ReportMetrics.yearRecordRows, 6);
      expect(find.byType(FormMeterRow), findsNWidgets(6));
      for (final record in records.skip(6)) {
        expect(find.bySemanticsIdentifier(idOf(record)), findsNothing);
      }
      expect(find.text('3 more'), findsOneWidget);
      var data = tester.getSemantics(more()).getSemanticsData();
      expect(data.label, '3 more in Records');
      expect(data.flagsCollection.isExpanded, Tristate.isFalse);

      await tester.tap(more());
      await tester.pump();
      expect(find.byType(FormMeterRow), findsNWidgets(9));
      expect(find.text('Show less'), findsOneWidget);
      data = tester.getSemantics(more()).getSemanticsData();
      expect(data.label, 'Show less of Records');
      expect(data.flagsCollection.isExpanded, Tristate.isTrue);
      expect(folds.isRecordsExpanded, isTrue);
      expect(shrinks, isEmpty);

      await tester.tap(more());
      await tester.pump();
      expect(shrinks, [true], reason: 'onShrink came before the fold');
      expect(find.byType(FormMeterRow), findsNWidgets(6));
      expect(folds.isRecordsExpanded, isFalse);
      handle.dispose();
    });

    testWidgets('"Show less" jumps back by the rows that leave, so "3 more" '
        'lands under the finger', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpRecords(tester, scroll: scroll);
      // The card's top at the screen's: expanded, "Show less" stays on it.
      const offset = 900.0;
      scroll.jumpTo(offset);
      await tester.pump();
      await tester.tap(more());
      await tester.pump();
      expect(scroll.offset, offset, reason: 'expanding never compensates');
      final tapY = tester.getRect(more()).top;
      final leaving =
          tester.getRect(rowWithId(idOf(records[8]))).bottom +
          1 -
          tester.getRect(rowWithId(idOf(records[6]))).top;
      await tester.tap(more());
      await tester.pump();
      expect(find.text('3 more'), findsOneWidget);
      expect(scroll.offset, closeTo(offset - leaving, 0.01));
      expect(tester.getRect(more()).top, closeTo(tapY, 0.01));
    });

    testWidgets('each kind wears its glyph in onSurfaceVariant, its name, '
        'the labels\' caption and spoken label, its id, and no button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      folds.setRecordsExpanded(true);
      final glyphs = {
        ReportRecordKind.busiestMonth: Icons.calendar_view_month_rounded,
        ReportRecordKind.busiestWeek: Icons.view_week_rounded,
        ReportRecordKind.socialMonth: CalendarIcons.areaIcon(LifeArea.people),
        ReportRecordKind.moneyMonth: CalendarIcons.areaIcon(LifeArea.money),
        ReportRecordKind.longestTrip: Icons.luggage_rounded,
        ReportRecordKind.longestStreak: Icons.done_all_rounded,
        ReportRecordKind.longestGap: Icons.hourglass_empty_rounded,
      };
      final report = yearReport();
      for (final brightness in Brightness.values) {
        final scheme = brightness == Brightness.light
            ? AppTheme.lightScheme
            : AppTheme.darkScheme;
        await pumpRecords(tester, brightness: brightness);
        final labels = labelsIn('en');
        for (final record in records) {
          final id = idOf(record);
          final row = tester.widget<FormMeterRow>(rowWithId(id));
          final words = labels.recordWords(
            record,
            report,
            weekStart: CalendarWeekStart.monday,
          );
          final icon = tester.widget<Icon>(
            find.descendant(of: rowWithId(id), matching: find.byType(Icon)),
          );
          expect(icon.icon, glyphs[record.kind], reason: id);
          expect(icon.color, scheme.onSurfaceVariant, reason: id);
          expect(row.label, labels.recordName(record.kind));
          expect(row.caption, words.caption);
          expect(row.fraction, isNull);
          expect(row.chart, isNull);
          expect(row.onTap, isNull);
          final data = tester
              .getSemantics(find.bySemanticsIdentifier(id))
              .getSemanticsData();
          expect(data.label, words.spoken, reason: id);
          expect(data.flagsCollection.isButton, isFalse, reason: id);
          expect(data.hasAction(SemanticsAction.tap), isFalse, reason: id);
        }
      }
      String read(String id) => tester
          .widget<FormMeterRow>(rowWithId(id))
          .caption!
          .replaceAll(noBreakSpace, ' ');
      expect(read(idOf(records[0])), 'June · 31 events');
      expect(read(idOf(records[4])), 'Lisbon · 6 days');
      expect(read(idOf(records[5])), 'Lifting · 14 in a row');
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(idOf(records[0])))
            .label
            .replaceAll(noBreakSpace, ' '),
        'Busiest month: June, 31 events',
      );
      expect(
        idOf(records[3]),
        'report-year-record-money-month',
        reason: 'the kebab id',
      );
      handle.dispose();
    });

    for (final (scale, row, disclosure, card) in const [
      (1.0, 62.0, 48.0, 426.0),
      (1.3, 67.4, 48.0, 458.4),
      (2.0, 130.0, 52.0, 838.0),
    ]) {
      testWidgets('at $scale a row is $row, the disclosure $disclosure and '
          'six rows with "3 more" $card, en and de at 360 and 412', (
        tester,
      ) async {
        for (final locale in const ['en', 'de']) {
          for (final width in const [360.0, 412.0]) {
            await pumpRecords(
              tester,
              locale: Locale(locale),
              textScale: scale,
              width: width,
            );
            final reason = '$locale $width';
            for (final record in records.take(6)) {
              expect(
                tester.getRect(rowWithId(idOf(record))).height,
                closeTo(row, 1),
                reason: '${record.kind.name} $reason',
              );
            }
            expect(
              tester.getRect(find.byType(FormActionRow)).height,
              closeTo(disclosure, 1),
              reason: reason,
            );
            expect(
              tester.getRect(cardGroup()).height,
              closeTo(card, 1),
              reason: reason,
            );
          }
        }
      });
    }

    testWidgets('Romanian at 1.0 and 1.3 is the table\'s; at 2.0 its one '
        'wrapped name grows its row by 4', (tester) async {
      for (final (scale, card) in const [(1.0, 426.0), (1.3, 458.4)]) {
        await pumpRecords(tester, locale: const Locale('ro'), textScale: scale);
        expect(tester.getRect(cardGroup()).height, closeTo(card, 1));
      }
      await pumpRecords(tester, locale: const Locale('ro'), textScale: 2.0);
      // A wrapped name takes the second label line under a one-line
      // caption: the row reserves two caption lines below the label's
      // first, so a name on two lines adds 4, not 40.
      for (final record in records.take(6)) {
        expect(
          tester.getRect(rowWithId(idOf(record))).height,
          closeTo(record.kind == ReportRecordKind.socialMonth ? 134 : 130, 1),
          reason: record.kind.name,
        );
      }
      expect(tester.getRect(cardGroup()).height, closeTo(842, 1));
    });

    testWidgets('below 1.6 one caption line, from 1.6 two and the glyph '
        'in the compact box with the hairline at the glyph indent', (
      tester,
    ) async {
      await pumpRecords(tester, textScale: 1.3);
      var row = tester.widget<FormMeterRow>(rowWithId(idOf(records[0])));
      expect(row.captionLines, 1);
      expect(
        tester.widget<Divider>(find.byType(Divider).first).indent,
        FormMetrics.dividerIndentTitle,
      );
      await pumpRecords(tester, textScale: 2.0);
      row = tester.widget<FormMeterRow>(rowWithId(idOf(records[0])));
      expect(row.captionLines, ReportMetrics.yearRecordCaptionLinesCompact);
      expect(row.compactLeading, isNotNull);
      expect(
        tester.widget<Divider>(find.byType(Divider).first).indent,
        RowMetrics.dividerIndentWithGlyph,
      );
    });

    for (final bold in [false, true]) {
      testWidgets('${bold ? 'under bold text ' : ''}no name and no caption '
          'is cut, in every locale and scale, at 360 and 412', (tester) async {
        folds.setRecordsExpanded(true);
        for (final locale in const ['en', 'de', 'ro']) {
          for (final scale in const [1.0, 1.3, 2.0]) {
            for (final width in const [360.0, 412.0]) {
              await pumpRecords(
                tester,
                locale: Locale(locale),
                textScale: scale,
                width: width,
                boldText: bold,
              );
              for (final record in records) {
                final row = rowWithId(idOf(record));
                final widget = tester.widget<FormMeterRow>(row);
                for (final text in [widget.label, widget.caption!]) {
                  final paragraph = tester.renderObject<RenderParagraph>(
                    find.descendant(of: row, matching: find.text(text)),
                  );
                  final reason = '"$text" $locale $scale $width';
                  if (bold) {
                    expect(paragraph.text.style?.fontWeight, FontWeight.bold);
                  }
                  expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
                }
              }
            }
          }
        }
      });
    }
  });

  group('months', () {
    late ReportGroupFolds folds;
    final shrinks = <bool>[];
    final tapped = <String>[];

    setUp(() {
      folds = ReportGroupFolds();
      shrinks.clear();
      tapped.clear();
    });

    Future<void> pumpMonths(
      WidgetTester tester, {
      CalendarReport? report,
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Brightness brightness = Brightness.light,
      double width = 360,
      bool boldText = false,
      bool tappable = true,
      ScrollController? scroll,
    }) => pump(
      tester,
      (labels) => ReportMonthsCard(
        report: report ?? yearReport(),
        labels: labels,
        folds: folds,
        onShrink: () => shrinks.add(folds.isMonthsExpanded),
        scroll: scroll,
        onCategoryTap: tappable ? tapped.add : null,
      ),
      locale: locale,
      textScale: textScale,
      brightness: brightness,
      width: width,
      boldText: boldText,
      scroll: scroll,
      room: scroll == null ? 0 : 900,
    );

    Finder strip(String id) => rowWithId(SemanticsIds.reportYearMonths(id));
    Finder axis() => find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_MonthAxisRow',
    );
    Finder more() =>
        find.bySemanticsIdentifier(SemanticsIds.reportYearMonthsMore);

    /// The strip's tiles from its painter: the rect, the colour and
    /// whether it is an outline.
    List<(RRect, Color, bool)> tilesOf(WidgetTester tester, String id) {
      final render = tester.renderObject<RenderCustomPaint>(
        find.descendant(
          of: strip(id),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter is ReportYearStripPainter,
          ),
        ),
      );
      final canvas = TestRecordingCanvas();
      render.painter!.paint(canvas, render.size);
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawRRect)
            (
              call.invocation.positionalArguments[0] as RRect,
              (call.invocation.positionalArguments[1] as Paint).color,
              (call.invocation.positionalArguments[1] as Paint).style ==
                  PaintingStyle.stroke,
            ),
      ];
    }

    /// The axis's names, left to right.
    List<String> axisNames(WidgetTester tester) => [
      for (final element
          in find
              .descendant(of: axis(), matching: find.byType(Text))
              .evaluate())
        (element.widget as Text).data!,
    ];

    testWidgets('nothing without a year or a kept category; a category '
        'whose every day was missed draws no strip', (tester) async {
      await pumpMonths(tester, report: yearReport(year: false));
      expect(cardGroup(), findsNothing);
      await pumpMonths(
        tester,
        report: yearReport(categories: const ['gym'], allMissed: {'gym'}),
      );
      expect(cardGroup(), findsNothing);
      await pumpMonths(tester, report: yearReport(allMissed: {'rest'}));
      expect(find.byType(FormMeterRow), findsNWidgets(5));
      expect(strip('rest'), findsNothing);
    });

    testWidgets('1 and 7 strips draw whole; 9 draw seven and "2 more", '
        'expand to nine in the Categories order and fold back after '
        'onShrink', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMonths(tester, report: yearReport(categories: const ['gym']));
      expect(find.byType(FormMeterRow), findsOneWidget);
      expect(more(), findsNothing);

      await pumpMonths(
        tester,
        report: yearReport(categories: categoryOrder.take(7).toList()),
      );
      expect(find.byType(FormMeterRow), findsNWidgets(7));
      expect(more(), findsNothing);

      await pumpMonths(tester, report: yearReport(categories: categoryOrder));
      expect(AnalyticsMetrics.yearMonthsStripCategories, 7);
      expect(find.byType(FormMeterRow), findsNWidgets(7));
      expect(find.text('2 more'), findsOneWidget);
      expect(tester.getSemantics(more()).label, '2 more in Months');

      await tester.tap(more());
      await tester.pump();
      expect(find.byType(FormMeterRow), findsNWidgets(9));
      final tops = [
        for (final id in categoryOrder) tester.getRect(strip(id)).top,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(folds.isMonthsExpanded, isTrue);

      await tester.tap(more());
      await tester.pump();
      expect(shrinks, [true]);
      expect(find.byType(FormMeterRow), findsNWidgets(7));
      handle.dispose();
    });

    testWidgets('"Show less" jumps back by the strips that leave', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpMonths(
        tester,
        report: yearReport(categories: categoryOrder),
        scroll: scroll,
      );
      // The card 200 above the screen's top: expanded, "Show less" stays on
      // it.
      const offset = 1100.0;
      scroll.jumpTo(offset);
      await tester.pump();
      await tester.tap(more());
      await tester.pump();
      expect(scroll.offset, offset, reason: 'expanding never compensates');
      final tapY = tester.getRect(more()).top;
      final leaving =
          tester.getRect(strip('other')).bottom +
          1 -
          tester.getRect(strip('birthday')).top;
      await tester.tap(more());
      await tester.pump();
      expect(find.text('2 more'), findsOneWidget);
      expect(scroll.offset, closeTo(offset - leaving, 0.01));
      expect(tester.getRect(more()).top, closeTo(tapY, 0.01));
    });

    testWidgets('a strip row: the avatar, the name, the kept span, no meter, '
        'a button with the twelve months spoken and its id; a tap hands '
        'over the category', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMonths(tester);
      final labels = labelsIn('en');
      final report = yearReport();
      final row = tester.widget<FormMeterRow>(strip('gym'));
      final name = CalendarCategories.labelOf(
        CalendarCategories.resolve('gym'),
        labels.l10n,
      );
      expect(row.leading, isA<EventAvatar>());
      expect(row.compactLeading, isA<FormGlyph>());
      expect(row.label, name);
      expect(row.fraction, isNull);
      expect(row.chart, isNotNull);
      expect(row.caption!.replaceAll(noBreakSpace, ' '), 'Jan 2 – Dec 30');
      final measurement = tester.widget<FormMeterRow>(strip('measurement'));
      expect(
        measurement.caption!.replaceAll(noBreakSpace, ' '),
        'Jun 14',
        reason: 'one kept day reads the day alone',
      );

      final data = tester
          .getSemantics(find.bySemanticsIdentifier('report-year-months-gym'))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      final span = report.year!.spans['gym']!;
      expect(
        data.label,
        labels.yearMonthsSpoken(
          category: name,
          span: labels.yearSpanSpoken(span.first, span.last),
          months: monthsOf['gym']!,
          primary: ReportMeasure.count,
        ),
      );
      expect(
        data.label.replaceAll(noBreakSpace, ' '),
        startsWith(
          '$name, from January 2 to December 30. By month: January 9, '
          'February 8, March 0',
        ),
      );
      final cardio = tester
          .getSemantics(find.bySemanticsIdentifier('report-year-months-cardio'))
          .label;
      expect(cardio, contains('February 2 hours'), reason: 'the primary unit');

      await tester.tap(strip('cardio'));
      expect(tapped, ['cardio']);

      await pumpMonths(tester, tappable: false);
      final read = tester
          .getSemantics(find.bySemanticsIdentifier('report-year-months-gym'))
          .getSemanticsData();
      expect(read.flagsCollection.isButton, isFalse);
      handle.dispose();
    });

    testWidgets('the axis is decoration: no node of its own', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMonths(tester);
      for (final name in axisNames(tester)) {
        expect(find.bySemanticsLabel(name), findsNothing, reason: name);
      }
      handle.dispose();
    });

    for (final (width, scale, tileWidth) in const [
      (360.0, 1.0, 18.67),
      (360.0, 2.0, 20.17),
      (412.0, 1.0, 23.0),
    ]) {
      testWidgets('at $width $scale a tile is $tileWidth × 16 on the text '
          'column, flush with its start and end', (tester) async {
        await pumpMonths(tester, width: width, textScale: scale);
        final tiles = tilesOf(tester, 'gym');
        expect(tiles, hasLength(12));
        for (final (rect, _, _) in tiles) {
          expect(rect.width, closeTo(tileWidth, 1));
          expect(rect.height, ReportMetrics.yearTileHeight);
        }
        final mean = tiles.map((t) => t.$1.width).reduce((a, b) => a + b) / 12;
        expect(mean, closeTo(tileWidth, 0.1));
        final painted = tester.getRect(
          find.descendant(
            of: strip('gym'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint &&
                  widget.painter is ReportYearStripPainter,
            ),
          ),
        );
        expect(tiles.first.$1.left, 0);
        expect(tiles.last.$1.right, closeTo(painted.width, 0.01));
        final textStart = tester.getRect(
          find.descendant(of: strip('gym'), matching: find.text('Gym')),
        );
        expect(painted.left, closeTo(textStart.left, 0.01));
      });
    }

    testWidgets('each tile fills at its step of the strip\'s own peak; an '
        'empty month is the meter\'s track', (tester) async {
      for (final brightness in Brightness.values) {
        final scheme = brightness == Brightness.light
            ? AppTheme.lightScheme
            : AppTheme.darkScheme;
        await pumpMonths(tester, brightness: brightness);
        int painted(Color color) => (Paint()..color = color).color.toARGB32();
        int fill(int step) => painted(ReportWhenChart.fillFor(scheme, step));
        final gym = tilesOf(tester, 'gym');
        // Peak 9: 9 and 8 are step 4, 4 is step 2, 2 step 1, 7 step 4,
        // 6 and 5 step 3, 3 and 1 step 2 and 1.
        const steps = [4, 4, 0, 2, 1, 4, 3, 3, 2, 1, 4, 4];
        for (final (month, step) in steps.indexed) {
          expect(gym[month].$2.toARGB32(), fill(step), reason: 'month $month');
          expect(gym[month].$3, isFalse);
        }
        expect(gym[2].$2.toARGB32(), painted(scheme.rowDivider));
        final rest = tilesOf(tester, 'rest');
        expect(
          rest.every((tile) => tile.$2.toARGB32() == fill(4)),
          isTrue,
          reason: 'a flat strip is its own peak',
        );
      }
    });

    testWidgets('in the current year the months after today\'s are hollow '
        'outlines; today\'s month draws its value so far', (tester) async {
      for (final brightness in Brightness.values) {
        final scheme = brightness == Brightness.light
            ? AppTheme.lightScheme
            : AppTheme.darkScheme;
        await pumpMonths(
          tester,
          report: yearReport(span: year2026),
          brightness: brightness,
        );
        int painted(Color color) => (Paint()..color = color).color.toARGB32();
        final tiles = tilesOf(tester, 'gym');
        for (final month in [10, 11]) {
          expect(tiles[month].$3, isTrue, reason: 'month $month is ahead');
          expect(tiles[month].$2.toARGB32(), painted(scheme.outlineVariant));
          expect(tiles[month].$1.height, ReportMetrics.yearTileHeight - 1);
        }
        expect(tiles[9].$3, isFalse, reason: 'October is today\'s');
        expect(
          tiles[9].$2.toARGB32(),
          painted(ReportWhenChart.fillFor(scheme, 1)),
        );
      }
      await pumpMonths(tester);
      expect(
        tilesOf(tester, 'gym').where((tile) => tile.$3),
        isEmpty,
        reason: 'a past year has nothing ahead',
      );
    });

    for (final brightness in Brightness.values) {
      test('the ramp\'s step 1 clears 2:1 against the card and stands off '
          'the empty tile in $brightness', () {
        final scheme = brightness == Brightness.light
            ? AppTheme.lightScheme
            : AppTheme.darkScheme;
        double ratio(Color a, Color b) => MarkerContrast.contrastRatio(
          Color.alphaBlend(a, scheme.rowGroup).computeLuminance(),
          Color.alphaBlend(b, scheme.rowGroup).computeLuminance(),
        );
        final step1 = ReportWhenChart.fillFor(scheme, 1);
        expect(ratio(step1, scheme.rowGroup), greaterThanOrEqualTo(2));
        expect(
          ratio(step1, scheme.rowDivider),
          closeTo(brightness == Brightness.light ? 1.77 : 2.61, 0.05),
        );
      });
    }

    for (final (scale, axisHeight, row, card, step) in const [
      (1.0, 30.0, 78.0, 504.0, 1),
      (1.3, 35.4, 89.4, 577.8, 1),
      (2.0, 48.0, 116.0, 750.0, 2),
    ]) {
      testWidgets('at $scale the axis is $axisHeight, a strip $row, six '
          'strips $card and the axis steps by $step, in every locale at '
          '360 and 412', (tester) async {
        for (final locale in const ['en', 'de', 'ro']) {
          for (final width in const [360.0, 412.0]) {
            final reason = '$locale $width';
            await pumpMonths(
              tester,
              locale: Locale(locale),
              textScale: scale,
              width: width,
            );
            expect(
              tester.getRect(axis()).height,
              closeTo(axisHeight, 1),
              reason: reason,
            );
            for (final id in categoryOrder.take(6)) {
              expect(
                tester.getRect(strip(id)).height,
                closeTo(row, 1),
                reason: '$id $reason',
              );
            }
            expect(
              tester.getRect(cardGroup()).height,
              closeTo(card, 1),
              reason: reason,
            );
            if (width == 360) {
              expect(axisNames(tester), hasLength(12 ~/ step), reason: reason);
            }
          }
        }
      });
    }

    testWidgets('the axis names centre on their tiles at the text column; '
        'short names when they fit, narrow ones otherwise', (tester) async {
      for (final (width, scale) in const [
        (360.0, 1.0),
        (360.0, 1.3),
        (360.0, 2.0),
        (412.0, 1.0),
        (480.0, 1.0),
      ]) {
        await pumpMonths(tester, width: width, textScale: scale);
        final names = axisNames(tester);
        final tiles = tilesOf(tester, 'gym');
        final origin = tester
            .getRect(
              find.descendant(
                of: strip('gym'),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      widget.painter is ReportYearStripPainter,
                ),
              ),
            )
            .left;
        final step = 12 ~/ names.length;
        for (final (index, name) in names.indexed) {
          final rect = tester.getRect(
            find
                .descendant(of: axis(), matching: find.text(name))
                .at(
                  // Narrow names repeat ("J", "M"); take this one's place.
                  names.take(index).where((n) => n == name).length,
                ),
          );
          final tile = tiles[index * step].$1;
          final centre = origin + tile.center.dx;
          final clamped =
              rect.left <= origin + 0.01 ||
              rect.right >= origin + tiles.last.$1.right - 0.01;
          if (!clamped) {
            expect(rect.center.dx, closeTo(centre, 1), reason: name);
          }
        }
        // "Jan" is wider than a pitch less the gap even at 412, so the
        // phones read the narrow names, 2.0 every other; a wider screen
        // has room for the short ones.
        expect(names, switch ((width, scale)) {
          (480, _) => const [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          ],
          (_, 2.0) => const ['J', 'M', 'M', 'J', 'S', 'N'],
          _ => const [
            'J',
            'F',
            'M',
            'A',
            'M',
            'J',
            'J',
            'A',
            'S',
            'O',
            'N',
            'D',
          ],
        }, reason: '$width $scale');
      }
    });

    testWidgets('under bold text no span caption is cut, in every locale '
        'and scale', (tester) async {
      for (final locale in const ['en', 'de', 'ro']) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          await pumpMonths(
            tester,
            locale: Locale(locale),
            textScale: scale,
            boldText: true,
          );
          for (final id in categoryOrder.take(6)) {
            final row = tester.widget<FormMeterRow>(strip(id));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: strip(id), matching: find.text(row.caption!)),
            );
            expect(paragraph.text.style?.fontWeight, FontWeight.bold);
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '$id $locale $scale',
            );
          }
        }
      }
    });
  });

  testWidgets('no exception across 1.0 / 1.3 / 2.0 × en / de / ro × 360 / '
      '412 × light / dark, both cards, past and current year', (tester) async {
    final folds = ReportGroupFolds();
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final locale in const ['en', 'de', 'ro']) {
        for (final width in const [360.0, 412.0]) {
          for (final brightness in Brightness.values) {
            for (final span in [year2025, year2026]) {
              final report = yearReport(span: span, categories: categoryOrder);
              await pump(
                tester,
                (labels) => Column(
                  children: [
                    ReportRecordsCard(
                      report: report,
                      labels: labels,
                      folds: folds,
                      weekStart: CalendarWeekStart.monday,
                    ),
                    ReportMonthsCard(
                      report: report,
                      labels: labels,
                      folds: folds,
                      onCategoryTap: (_) {},
                    ),
                  ],
                ),
                locale: Locale(locale),
                textScale: scale,
                width: width,
                brightness: brightness,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$scale $locale $width ${brightness.name}',
              );
            }
          }
        }
      }
    }
  });
}
