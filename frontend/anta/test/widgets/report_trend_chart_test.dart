import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/date_range.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/report_trend_chart.dart';

import '../goldens/support/golden_fonts.dart';

/// The Over time card (§4.8): the axis labels per unit, the legend only with
/// both parts, the peak, the caption and the spoken summary, the columns'
/// geometry from the painter's own calls, and the card's height across the
/// text scales with Roboto loaded, as the page suite measures.
void main() {
  setUpAll(loadGoldenFonts);

  /// [count] columns from [start], one [step] apart; [happened] and
  /// [missed] give each column's counts by index.
  List<ReportTrendBucket> columns(
    DateTime start,
    int count, {
    required DateTime Function(DateTime start, int index) step,
    int Function(int index)? happened,
    int Function(int index)? missed,
  }) => [
    for (var i = 0; i < count; i++)
      ReportTrendBucket(
        start: step(start, i),
        happened: happened?.call(i) ?? (i % 3 == 0 ? 0 : 1 + i % 2),
        missed: missed?.call(i) ?? 0,
      ),
  ];

  DateTime days(DateTime start, int i) =>
      DateTime.utc(start.year, start.month, start.day + i);

  // October 2026 opens on a Thursday; its Mondays are the 5th, 12th, 19th
  // and 26th.
  final october = (
    start: DateTime.utc(2026, 10, 1),
    end: DateTime.utc(2026, 10, 31),
  );
  ReportTrend monthTrend({
    int? busiestWeekday = DateTime.monday,
    int? start = 18 * 60,
    int? end = 19 * 60 + 30,
    bool withMissed = true,
  }) => ReportTrend(
    unit: ReportTrendUnit.day,
    buckets: columns(
      october.start,
      31,
      step: days,
      missed: withMissed ? (i) => i == 4 ? 1 : 0 : null,
    ),
    busiestWeekday: busiestWeekday,
    usualStartMinute: start,
    usualEndMinute: end,
  );

  // The week of Monday 5 October; the peak, 3, on the Wednesday.
  final week = (
    start: DateTime.utc(2026, 10, 5),
    end: DateTime.utc(2026, 10, 11),
  );
  final weekTrend = ReportTrend(
    unit: ReportTrendUnit.day,
    buckets: columns(
      week.start,
      7,
      step: days,
      happened: (i) => const [1, 0, 3, 1, 2, 0, 1][i],
    ),
  );

  // 27 week columns over 182 days: a partial week from Thursday 2 April,
  // then the Mondays from 6 April to 28 September.
  final weeks = (
    start: DateTime.utc(2026, 4, 2),
    end: DateTime.utc(2026, 9, 30),
  );
  final weeksTrend = ReportTrend(
    unit: ReportTrendUnit.week,
    buckets: columns(
      weeks.start,
      27,
      step: (start, i) =>
          i == 0 ? start : DateTime.utc(2026, 4, 6 + 7 * (i - 1)),
    ),
  );

  // Fourteen month columns, September 2025 to October 2026.
  final months = (
    start: DateTime.utc(2025, 9, 1),
    end: DateTime.utc(2026, 10, 31),
  );
  final monthsTrend = ReportTrend(
    unit: ReportTrendUnit.month,
    buckets: columns(
      months.start,
      14,
      step: (start, i) => DateTime.utc(2025, 9 + i, 1),
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    ReportTrend trend,
    DateRange span, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    double width = 360,
    double devicePixelRatio = 1.0,
    bool boldText = false,
    TextScaler? scaler,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = Size(width, 780) * devicePixelRatio;
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: scaler ?? TextScaler.linear(textScale),
            alwaysUse24HourFormat: true,
            boldText: boldText,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            // The page's group inset, so the card is the page's width.
            padding: const EdgeInsets.symmetric(
              horizontal: RowMetrics.groupInset,
            ),
            children: [
              Builder(
                builder: (context) => ReportTrendChart(
                  trend: trend,
                  labels: ReportLabels(AppLocalizations.of(context)!),
                  weekStart: weekStart,
                  span: span,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  Finder card() => find.byType(ReportTrendChart);

  /// The texts the axis row draws, left to right.
  List<String> axisLabels(WidgetTester tester) {
    final texts = find.descendant(
      of: find.descendant(of: card(), matching: find.byType(Stack)),
      matching: find.byType(Text),
    );
    final found = [
      for (final element in texts.evaluate())
        (
          tester.getTopLeft(find.byWidget(element.widget)).dx,
          (element.widget as Text).data!,
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, text) in found) text];
  }

  /// The axis labels' boxes as drawn, left to right.
  List<Rect> axisRects(WidgetTester tester) => [
    for (final element
        in find
            .descendant(
              of: find.descendant(of: card(), matching: find.byType(Stack)),
              matching: find.byType(Text),
            )
            .evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ]..sort((a, b) => a.left.compareTo(b.left));

  /// Every label at least the label gap from the one before it.
  void expectApart(List<Rect> rects) {
    for (var i = 1; i < rects.length; i++) {
      expect(
        rects[i].left - rects[i - 1].right,
        greaterThanOrEqualTo(ReportMetrics.axisLabelMinGap - 0.01),
        reason: 'label $i',
      );
    }
  }

  /// The plot's canvas calls, from the painter itself.
  List<RecordedInvocation> plotCalls(WidgetTester tester) {
    final plot = tester
        .renderObjectList<RenderCustomPaint>(
          find.descendant(of: card(), matching: find.byType(CustomPaint)),
        )
        .firstWhere((render) => render.painter != null);
    final canvas = TestRecordingCanvas();
    plot.painter!.paint(canvas, plot.size);
    return canvas.invocations;
  }

  /// The column segments the plot draws.
  List<RRect> segments(WidgetTester tester) => [
    for (final call in plotCalls(tester))
      if (call.invocation.memberName == #drawRRect)
        call.invocation.positionalArguments.first as RRect,
  ];

  /// Twelve month columns, January to December 2026: This year.
  final year = (
    start: DateTime.utc(2026, 1, 1),
    end: DateTime.utc(2026, 12, 31),
  );
  final yearTrend = ReportTrend(
    unit: ReportTrendUnit.month,
    buckets: columns(
      year.start,
      12,
      step: (start, i) => DateTime.utc(2026, 1 + i, 1),
    ),
  );

  group('axis', () {
    testWidgets('a 31-day month labels the Mondays as day numbers', (
      tester,
    ) async {
      await pump(tester, monthTrend(), october);
      expect(axisLabels(tester), ['5', '12', '19', '26']);
    });

    testWidgets('on a Sunday start it labels the Sundays', (tester) async {
      await pump(
        tester,
        monthTrend(),
        october,
        weekStart: CalendarWeekStart.sunday,
      );
      expect(axisLabels(tester), ['4', '11', '18', '25']);
    });

    testWidgets('a week labels every day with its short name', (tester) async {
      await pump(tester, weekTrend, week);
      final short = DateFormat.E('en');
      expect(axisLabels(tester), [
        for (var i = 0; i < 7; i++) short.format(DateTime.utc(2026, 10, 5 + i)),
      ]);
    });

    testWidgets('27 weeks label the week holding each 1st with its month', (
      tester,
    ) async {
      await pump(tester, weeksTrend, weeks);
      expect(axisLabels(tester), ['May', 'Jun', 'Jul', 'Aug', 'Sep']);
    });

    testWidgets('14 months take the narrow names when the short ones do not '
        'fit a column', (tester) async {
      await pump(tester, monthsTrend, months);
      final labels = axisLabels(tester);
      expect(labels, isNotEmpty);
      expect(
        labels.every((label) => label.length == 1),
        isTrue,
        reason: '$labels',
      );
      expect(labels.first, 'S');
    });

    testWidgets('This year at 360 labels all twelve months, apart', (
      tester,
    ) async {
      await pump(tester, yearTrend, year);
      expect(axisLabels(tester), hasLength(12));
      expectApart(axisRects(tester));
    });

    testWidgets('This year in Romanian at 412 labels all twelve months, '
        'narrow if it must, never with a gap', (tester) async {
      await pump(
        tester,
        yearTrend,
        year,
        locale: const Locale('ro'),
        width: 412,
      );
      expect(axisLabels(tester), hasLength(12));
      expectApart(axisRects(tester));
    });

    testWidgets('under bold text the labels are measured bold and stay '
        'apart', (tester) async {
      await pump(tester, yearTrend, year, boldText: true);
      expect(axisLabels(tester), hasLength(12));
      expectApart(axisRects(tester));
      await pump(tester, weekTrend, week, boldText: true, textScale: 2.0);
      expect(axisLabels(tester), hasLength(7));
      expectApart(axisRects(tester));
    });

    testWidgets('a non-linear scale that grows small text more keeps every '
        'label inside its one-line box', (tester) async {
      const scaler = _SmallTextGrowsMore();
      await pump(tester, weekTrend, week, scaler: scaler);
      final box = scaler.scale(FormMetrics.captionLineHeight);
      final rects = axisRects(tester);
      expect(rects, isNotEmpty);
      for (final rect in rects) {
        expect(rect.height, lessThanOrEqualTo(box + 0.01));
      }
    });
  });

  group('columns', () {
    testWidgets('31 day columns stay narrower than the cap, one segment per '
        'part, none for an empty day', (tester) async {
      final trend = monthTrend();
      await pump(tester, trend, october, devicePixelRatio: 3);
      final drawn = segments(tester);
      final parts = trend.buckets.fold<int>(
        0,
        (sum, b) => sum + (b.happened > 0 ? 1 : 0) + (b.missed > 0 ? 1 : 0),
      );
      expect(drawn, hasLength(parts));
      for (final segment in drawn) {
        expect(segment.width, lessThanOrEqualTo(ReportMetrics.columnMaxWidth));
        expect(
          segment.width,
          closeTo(296 / 31 - ReportMetrics.columnGap, 1 / 3 + 0.01),
        );
      }
    });

    testWidgets('31 columns snap to physical pixels with even 2 dp gaps, and '
        'the hairlines are one pixel row each', (tester) async {
      final trend = ReportTrend(
        unit: ReportTrendUnit.day,
        buckets: columns(october.start, 31, step: days, happened: (i) => 1),
      );
      await pump(tester, trend, october, devicePixelRatio: 3);
      final drawn = segments(tester);
      expect(drawn, hasLength(31));
      for (final segment in drawn) {
        expect(
          (segment.left * 3).roundToDouble(),
          closeTo(segment.left * 3, 1e-6),
        );
        expect(
          (segment.right * 3).roundToDouble(),
          closeTo(segment.right * 3, 1e-6),
        );
      }
      for (var i = 1; i < drawn.length; i++) {
        expect(
          drawn[i].left - drawn[i - 1].right,
          closeTo(ReportMetrics.columnGap, 1e-6),
          reason: 'gap $i',
        );
      }
      final hairlines = [
        for (final call in plotCalls(tester))
          if (call.invocation.memberName == #drawRect)
            call.invocation.positionalArguments.first as Rect,
      ];
      expect(hairlines, hasLength(2));
      expect(hairlines.first.top, 0);
      expect(hairlines.last.bottom, ReportMetrics.chartPlotHeight);
      for (final line in hairlines) {
        expect(line.height, 1.0);
      }
    });

    testWidgets('one missed on a happened 59 column under a peak of 60 still '
        'shows a missed slice, a gap above the happened part', (tester) async {
      final trend = ReportTrend(
        unit: ReportTrendUnit.day,
        buckets: columns(
          week.start,
          7,
          step: days,
          happened: (i) => i == 0 ? 60 : (i == 1 ? 59 : 0),
          missed: (i) => i == 1 ? 1 : 0,
        ),
      );
      await pump(tester, trend, week);
      final drawn = segments(tester);
      expect(drawn, hasLength(3));
      final happened = drawn[1];
      final missed = drawn[2];
      expect(missed.height, greaterThanOrEqualTo(ReportMetrics.columnGap));
      expect(missed.top, closeTo(0, 0.01), reason: 'the column is the peak');
      expect(
        happened.top - missed.bottom,
        closeTo(ReportMetrics.columnGap, 0.01),
      );
      expect(happened.bottom, ReportMetrics.chartPlotHeight);
    });

    testWidgets('a week\'s columns are capped at the maximum width and the '
        'peak column fills the plot', (tester) async {
      await pump(tester, weekTrend, week);
      final drawn = segments(tester);
      expect(drawn, hasLength(5), reason: 'two empty days draw nothing');
      for (final segment in drawn) {
        expect(segment.width, closeTo(ReportMetrics.columnMaxWidth, 0.01));
        expect(segment.bottom, ReportMetrics.chartPlotHeight);
      }
      final tallest = drawn.reduce((a, b) => a.height > b.height ? a : b);
      expect(tallest.top, 0);
      expect(tallest.tlRadiusX, ReportMetrics.columnRadius);
      expect(tallest.blRadiusX, 0, reason: 'square at the baseline');
    });

    testWidgets('the missed part sits above the happened part, a gap apart, '
        'and only it is rounded', (tester) async {
      final trend = ReportTrend(
        unit: ReportTrendUnit.day,
        buckets: columns(
          week.start,
          7,
          step: days,
          happened: (i) => 2,
          missed: (i) => i == 0 ? 2 : 0,
        ),
      );
      await pump(tester, trend, week);
      final first = segments(tester).take(2).toList();
      final happened = first[0];
      final missed = first[1];
      expect(happened.bottom, ReportMetrics.chartPlotHeight);
      expect(happened.tlRadiusX, 0);
      expect(
        missed.bottom,
        closeTo(happened.top - ReportMetrics.columnGap, 0.01),
      );
      expect(missed.top, 0, reason: 'the peak is the whole column');
      expect(missed.tlRadiusX, ReportMetrics.columnRadius);
    });
  });

  group('legend and peak', () {
    testWidgets('the legend shows while both parts exist', (tester) async {
      await pump(tester, monthTrend(), october);
      expect(find.text('Happened'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
    });

    testWidgets('a single series draws no legend', (tester) async {
      await pump(tester, monthTrend(withMissed: false), october);
      expect(find.text('Happened'), findsNothing);
      expect(find.text('Missed'), findsNothing);
    });

    testWidgets('the peak value stands at the right of the top row', (
      tester,
    ) async {
      await pump(tester, weekTrend, week);
      final peak = find.text('3');
      expect(peak, findsOneWidget);
      expect(
        tester.getRect(peak).right,
        closeTo(
          tester.getRect(card()).right - ReportMetrics.chartPaddingHorizontal,
          0.5,
        ),
      );
    });
  });

  group('caption and semantics', () {
    testWidgets('the busiest weekday and the usual band', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, monthTrend(), october);
      expect(
        find.text(
          'Most on Monday${ReportLabels.separator}usually 18:00 – 19:30',
        ),
        findsOneWidget,
      );
      final node = tester.getSemantics(
        find.bySemanticsIdentifier(SemanticsIds.reportTrend),
      );
      expect(node.label, 'Over time. Most on Monday, usually 18:00 – 19:30');
      expect(node.childrenCount, 0, reason: 'the plot is not read');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('the band alone opens the caption', (tester) async {
      await pump(tester, monthTrend(busiestWeekday: null), october);
      expect(find.text('Usually 18:00 – 19:30'), findsOneWidget);
    });

    testWidgets('a start with no durations reads as a time', (tester) async {
      await pump(tester, monthTrend(busiestWeekday: null, end: null), october);
      expect(find.text('Usually at 18:00'), findsOneWidget);
    });

    testWidgets('neither fact: no caption, the peak is spoken', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, weekTrend, week);
      expect(find.textContaining('sually'), findsNothing);
      expect(find.textContaining('Most on'), findsNothing);
      final day = DateFormat.MMMMEEEEd('en').format(DateTime.utc(2026, 10, 7));
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.reportTrend))
            .label,
        'Over time. Peak 3 on $day',
      );
      handle.dispose();
    });

    testWidgets('a month peak names the month', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, monthsTrend, months);
      final peak = ReportLabels.peakOf(monthsTrend);
      final at = monthsTrend.buckets.firstWhere(
        (b) => b.happened + b.missed == peak,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.reportTrend))
            .label,
        'Over time. Peak $peak in ${DateFormat.yMMMM('en').format(at.start)}',
      );
      handle.dispose();
    });

    testWidgets('a week peak names the week by its first day', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, weeksTrend, weeks);
      // The first column of 2 is the week of Monday 6 April.
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.reportTrend))
            .label,
        'Over time. Peak 2 in the week of '
        '${DateFormat.MMMMd('en').format(DateTime.utc(2026, 4, 6))}',
      );
      handle.dispose();
    });

    test('a trend with no occurrence speaks only its name, never Peak 0', () {
      final labels = ReportLabels(lookupAppLocalizations(const Locale('en')));
      for (final buckets in [
        const <ReportTrendBucket>[],
        [
          ReportTrendBucket(
            start: DateTime.utc(2026, 10, 1),
            happened: 0,
            missed: 0,
          ),
        ],
      ]) {
        final words = labels.trendWords(
          ReportTrend(unit: ReportTrendUnit.day, buckets: buckets),
          use24Hour: true,
        );
        expect(words.caption, isNull);
        expect(words.spoken, 'Over time');
      }
    });

    test('the peak phrases in German and Romanian', () {
      final trend = ReportTrend(
        unit: ReportTrendUnit.month,
        buckets: [
          ReportTrendBucket(
            start: DateTime.utc(2026, 10, 1),
            happened: 3,
            missed: 0,
          ),
        ],
      );
      final de = ReportLabels(lookupAppLocalizations(const Locale('de')));
      final ro = ReportLabels(lookupAppLocalizations(const Locale('ro')));
      expect(
        de.trendWords(trend, use24Hour: true).spoken,
        'Im Zeitverlauf. Höchstwert 3 im '
        '${DateFormat.yMMMM('de').format(DateTime.utc(2026, 10, 1))}',
      );
      expect(
        ro.trendWords(trend, use24Hour: true).spoken,
        'În timp. Maxim 3 în '
        '${DateFormat.yMMMM('ro').format(DateTime.utc(2026, 10, 1))}',
      );
    });
  });

  group('geometry', () {
    // §4.8's measures: one caption line at 1.0, two at 1.3 and 2.0.
    for (final (scale, height) in [(1.0, 178.0), (1.3, 216.4), (2.0, 268.0)]) {
      testWidgets('the card is $height high at en $scale', (tester) async {
        await pump(tester, monthTrend(), october, textScale: scale);
        expect(tester.getSize(card()).height, closeTo(height, 1));
      });
    }

    testWidgets('German at 2.0 on 360 lays out, the legend wrapping to a '
        'second line', (tester) async {
      await pump(
        tester,
        monthTrend(),
        october,
        locale: const Locale('de'),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Verpasst')).dy,
        greaterThan(tester.getTopLeft(find.text('Stattgefunden')).dy),
      );
      // §4.8's measure: the legend on two lines, the caption on three.
      expect(tester.getSize(card()).height, closeTo(342, 1));
    });

    testWidgets('dark draws the same card', (tester) async {
      await pump(tester, monthTrend(), october, brightness: Brightness.dark);
      expect(tester.getSize(card()).height, closeTo(178, 1));
      final scheme = AppTheme.dark().colorScheme;
      final plot = tester
          .renderObjectList<RenderCustomPaint>(
            find.descendant(of: card(), matching: find.byType(CustomPaint)),
          )
          .firstWhere((render) => render.painter != null);
      final canvas = TestRecordingCanvas();
      plot.painter!.paint(canvas, plot.size);
      final colours = {
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawRRect)
            (call.invocation.positionalArguments[1] as Paint).color.toARGB32(),
      };
      expect(colours, {
        scheme.primary.toARGB32(),
        scheme.outlineVariant.toARGB32(),
      });
    });
  });
}

/// A text scale that grows small text more than large, as Android's
/// non-linear 200 % curve does: a 13 px caption outgrows the box that a
/// linear 18 px line measures.
class _SmallTextGrowsMore extends TextScaler {
  const _SmallTextGrowsMore();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 14 ? 2.4 : 2.0);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 2.0;

  @override
  bool operator ==(Object other) => other is _SmallTextGrowsMore;

  @override
  int get hashCode => (_SmallTextGrowsMore).hashCode;
}
