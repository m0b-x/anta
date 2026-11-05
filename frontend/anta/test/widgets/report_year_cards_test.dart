import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;

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
          final words = labels.recordWords(record, report);
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

    for (final (scale, row, line, disclosure) in const [
      (1.0, 62.0, 18.0, 48.0),
      (1.3, 67.4, 23.4, 48.0),
      (2.0, 94.0, 36.0, 52.0),
    ]) {
      testWidgets('at $scale a one-line row is $row, each further caption '
          'line adds $line and the disclosure is $disclosure, en and de at '
          '360 and 412', (tester) async {
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
              final lines = tester
                  .widget<FormMeterRow>(rowWithId(idOf(record)))
                  .captionLines!;
              expect(
                tester.getRect(rowWithId(idOf(record))).height,
                closeTo(row + (lines - 1) * line, 1),
                reason: '${record.kind.name} $reason',
              );
            }
            expect(
              tester.getRect(find.byType(FormActionRow)).height,
              closeTo(disclosure, 1),
              reason: reason,
            );
          }
        }
      });
    }

    // Six rows and "3 more": each row reserves what its template wraps to.
    for (final (locale, scale, width, card) in const [
      ('en', 1.0, 360.0, 426.0),
      ('de', 1.0, 412.0, 426.0),
      ('ro', 1.0, 360.0, 426.0),
      ('en', 1.3, 360.0, 458.4),
      ('de', 1.3, 360.0, 481.8),
      ('de', 1.3, 412.0, 458.4),
      ('ro', 1.3, 360.0, 505.2),
      ('ro', 1.3, 412.0, 481.8),
      ('en', 2.0, 360.0, 730.0),
      ('en', 2.0, 412.0, 658.0),
      ('de', 2.0, 360.0, 730.0),
      ('ro', 2.0, 412.0, 694.0),
    ]) {
      testWidgets('$locale at $scale and $width: six rows with "3 more" '
          'take $card', (tester) async {
        await pumpRecords(
          tester,
          locale: Locale(locale),
          textScale: scale,
          width: width,
        );
        expect(tester.getRect(cardGroup()).height, closeTo(card, 1));
      });
    }

    testWidgets('Romanian at 2.0 and 360: its one wrapped name grows its '
        'row by 4', (tester) async {
      await pumpRecords(tester, locale: const Locale('ro'), textScale: 2.0);
      // A wrapped name takes the second label line under a one-line
      // caption: the row reserves two caption lines below the label's
      // first, so a name on two lines adds 4, not 40.
      for (final record in records.take(6)) {
        final lines = tester
            .widget<FormMeterRow>(rowWithId(idOf(record)))
            .captionLines!;
        expect(
          tester.getRect(rowWithId(idOf(record))).height,
          closeTo(
            94 +
                (lines - 1) * 36 +
                (record.kind == ReportRecordKind.socialMonth ? 4 : 0),
            1,
          ),
          reason: record.kind.name,
        );
      }
      expect(
        tester.widget<FormMeterRow>(rowWithId(idOf(records[2]))).captionLines,
        2,
      );
      expect(tester.getRect(cardGroup()).height, closeTo(734, 1));
    });

    testWidgets('the lines come from the kind\'s template at the caption\'s '
        'width, never from the scale; from 1.6 the glyph in the compact box '
        'with the hairline at the glyph indent', (tester) async {
      int linesOf(ReportRecord record) =>
          tester.widget<FormMeterRow>(rowWithId(idOf(record))).captionLines!;
      // German at 1.3 on the small phone: the week's two months wrap, the
      // month's one name does not.
      await pumpRecords(tester, locale: const Locale('de'), textScale: 1.3);
      expect(linesOf(records[0]), 1);
      expect(linesOf(records[1]), 2);
      expect(
        tester.widget<Divider>(find.byType(Divider).first).indent,
        FormMetrics.dividerIndentTitle,
      );
      // At 2.0 on the wide phone a month fits one line, the week two.
      await pumpRecords(tester, textScale: 2.0, width: 412);
      expect(linesOf(records[0]), 1);
      expect(linesOf(records[1]), 2);
      expect(linesOf(records[3]), 1, reason: 'the money month');
      final row = tester.widget<FormMeterRow>(rowWithId(idOf(records[0])));
      expect(row.compactLeading, isNotNull);
      expect(
        tester.widget<Divider>(find.byType(Divider).first).indent,
        RowMetrics.dividerIndentWithGlyph,
      );
    });

    testWidgets('a title\'s caption is measured with the title, at most '
        'two lines with an ellipsis beyond', (tester) async {
      final long = ReportRecord(
        kind: ReportRecordKind.longestTrip,
        categoryId: 'holiday',
        eventId: 'e-long',
        value: 12,
        start: DateTime.utc(2025, 8, 4),
        end: DateTime.utc(2025, 8, 15),
      );
      final base = yearReport(withRecords: [long]);
      CalendarReport titled(String title) => CalendarReport(
        span: base.span,
        today: base.today,
        tense: base.tense,
        countedTo: base.countedTo,
        events: {
          ...events,
          'e-long': CalendarEvent(
            id: 'e-long',
            title: title,
            categoryId: 'holiday',
            startDate: DateTime.utc(2025, 1, 1),
            rule: const OneTimeRecurrence(),
          ),
        },
        tiles: const [],
        skippedDays: 0,
        aheadCount: 0,
        categories: base.categories,
        missed: const [],
        ahead: const [],
        measures: base.measures,
        year: base.year,
      );
      FormMeterRow row() => tester.widget<FormMeterRow>(rowWithId(idOf(long)));
      await pumpRecords(tester, report: titled('Rome'));
      expect(row().captionLines, 1);
      await pumpRecords(
        tester,
        report: titled('The long summer road trip along the coast'),
      );
      expect(row().captionLines, 2);
      await pumpRecords(tester, report: titled('Road trip ' * 12));
      expect(
        row().captionLines,
        ReportMetrics.yearRecordCaptionLinesCompact,
        reason: 'capped',
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: rowWithId(idOf(long)),
          matching: find.text(row().caption!),
        ),
      );
      expect(paragraph.didExceedMaxLines, isTrue, reason: 'the ellipsis');
    });

    testWidgets('a busiest week across two months with 188 events is never '
        'cut: ro 1.3, de 1.5 and bold en 1.5 at 360', (tester) async {
      final week = ReportRecord(
        kind: ReportRecordKind.busiestWeek,
        value: 188,
        start: DateTime.utc(2025, 9, 29),
        end: DateTime.utc(2025, 10, 5),
      );
      for (final (locale, scale, bold) in const [
        ('ro', 1.3, false),
        ('de', 1.5, false),
        ('en', 1.5, true),
        ('en', 1.5, false),
        ('de', 2.0, true),
      ]) {
        await pumpRecords(
          tester,
          report: yearReport(withRecords: [week]),
          locale: Locale(locale),
          textScale: scale,
          boldText: bold,
        );
        final row = tester.widget<FormMeterRow>(rowWithId(idOf(week)));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: rowWithId(idOf(week)),
            matching: find.text(row.caption!),
          ),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"${row.caption}" $locale $scale bold $bold',
        );
      }
    });

    testWidgets('an unchanged rebuild, a fold and an unfold lay no caption '
        'out again; a new scale measures again', (tester) async {
      await pumpRecords(tester);
      final first = ReportRecordsCard.measurementCount;
      await pumpRecords(tester);
      expect(ReportRecordsCard.measurementCount, first, reason: 'rebuilt');
      await tester.tap(more());
      await tester.pump();
      final unfolded = ReportRecordsCard.measurementCount;
      expect(unfolded, greaterThan(first), reason: 'the folded rows');
      await tester.tap(more());
      await tester.pump();
      await tester.tap(more());
      await tester.pump();
      expect(ReportRecordsCard.measurementCount, unfolded);
      await pumpRecords(tester, textScale: 1.3);
      expect(ReportRecordsCard.measurementCount, greaterThan(unfolded));
    });

    testWidgets('German at 2.0 and 360: the disclosure is 52 folded and '
        'expanded, "Weniger" on one line', (tester) async {
      await pumpRecords(tester, locale: const Locale('de'), textScale: 2.0);
      expect(tester.getRect(find.byType(FormActionRow)).height, closeTo(52, 1));
      await tester.tap(more());
      await tester.pump();
      expect(find.text('Weniger'), findsOneWidget);
      expect(tester.getRect(find.byType(FormActionRow)).height, closeTo(52, 1));
    });

    for (final bold in [false, true]) {
      testWidgets('${bold ? 'under bold text ' : ''}no name and no caption '
          'is cut, in every locale and scale, at 360 and 412', (tester) async {
        folds.setRecordsExpanded(true);
        for (final locale in const ['en', 'de', 'ro']) {
          for (final scale in const [1.0, 1.3, 1.5, 2.0]) {
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
      bool Function(String categoryId)? canTap,
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
        canTap: canTap,
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
          'February 8, April 4',
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

    testWidgets('a strip canTap refuses is a read row; the others stay '
        'buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMonths(tester, canTap: (id) => id != 'gym');
      expect(tester.widget<FormMeterRow>(strip('gym')).onTap, isNull);
      final gym = tester
          .getSemantics(find.bySemanticsIdentifier('report-year-months-gym'))
          .getSemanticsData();
      expect(gym.flagsCollection.isButton, isFalse);
      expect(gym.hasAction(SemanticsAction.tap), isFalse);
      expect(tester.widget<FormMeterRow>(strip('cardio')).onTap, isNotNull);
      await tester.tap(strip('gym'), warnIfMissed: false);
      await tester.tap(strip('cardio'));
      expect(tapped, ['cardio']);
      handle.dispose();
    });

    testWidgets('the spoken list stops at today\'s month in the current '
        'year and runs to December in a past one', (tester) async {
      final handle = tester.ensureSemantics();
      String spoken() => tester
          .getSemantics(find.bySemanticsIdentifier('report-year-months-gym'))
          .label
          .replaceAll(noBreakSpace, ' ');
      await pumpMonths(tester, report: yearReport(span: year2026));
      expect(spoken(), endsWith('September 3, October 1.'));
      expect(spoken(), isNot(contains('November')));
      expect(spoken(), isNot(contains('December 9')));
      await pumpMonths(tester);
      expect(spoken(), endsWith('November 8, December 9.'));
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
        (412.0, 2.0),
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
        // phones read the narrow names, 2.0 every other — even at 412,
        // whose two pitches miss "May" by under a pixel; a wider screen
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

    testWidgets('the axis in every locale at 2.0: 360 keeps the narrow '
        'names every other month; at 412 the short ones where they fit '
        'two pitches', (tester) async {
      for (final locale in const ['en', 'de', 'ro']) {
        final short = [
          for (var month = 1; month <= 11; month += 2)
            DateFormat.MMM(locale).format(DateTime.utc(2026, month)),
        ];
        await pumpMonths(tester, locale: Locale(locale), textScale: 2.0);
        expect(axisNames(tester), hasLength(6), reason: locale);
        expect(
          axisNames(tester).every((name) => name.length == 1),
          isTrue,
          reason: '$locale 360',
        );
        await pumpMonths(
          tester,
          locale: Locale(locale),
          textScale: 2.0,
          width: 412,
        );
        // German's short names fit two pitches with the gap; English "May"
        // misses by under a pixel and Romanian "sept." by more, so they
        // keep the narrow names.
        expect(
          axisNames(tester),
          locale == 'de'
              ? short
              : [for (final name in short) name[0].toUpperCase()],
          reason: '$locale 412',
        );
      }
    });

    testWidgets('an unchanged rebuild and a fold lay no axis name out '
        'again; a new width measures again', (tester) async {
      await pumpMonths(tester, report: yearReport(categories: categoryOrder));
      final first = ReportMonthsCard.axisMeasurementCount;
      await pumpMonths(tester, report: yearReport(categories: categoryOrder));
      expect(ReportMonthsCard.axisMeasurementCount, first, reason: 'rebuilt');
      await tester.tap(more());
      await tester.pump();
      await tester.tap(more());
      await tester.pump();
      expect(ReportMonthsCard.axisMeasurementCount, first, reason: 'folds');
      await pumpMonths(
        tester,
        report: yearReport(categories: categoryOrder),
        width: 412,
      );
      expect(ReportMonthsCard.axisMeasurementCount, first + 1);
    });

    testWidgets('German at 2.0 and 360: the disclosure is 52 folded and '
        'expanded, "Weniger" on one line', (tester) async {
      await pumpMonths(
        tester,
        report: yearReport(categories: categoryOrder),
        locale: const Locale('de'),
        textScale: 2.0,
      );
      expect(tester.getRect(find.byType(FormActionRow)).height, closeTo(52, 1));
      await tester.ensureVisible(more());
      await tester.pump();
      await tester.tap(more());
      await tester.pump();
      expect(find.text('Weniger'), findsOneWidget);
      expect(tester.getRect(find.byType(FormActionRow)).height, closeTo(52, 1));
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
