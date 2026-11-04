import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/report_when_chart.dart';

import '../goldens/support/golden_fonts.dart';

/// The When card (S5 §2.3): the grid's geometry from the painter's own
/// calls, the weekday and hour labels per text scale and clock, the ramp's
/// tokens and contrast, the caption and the one spoken node — with Roboto
/// loaded, as the spec measured.
void main() {
  setUpAll(loadGoldenFonts);

  // 34 timed days on a Monday start; the peak cell Tuesday 18:00, one cell
  // per ramp step and the rest empty.
  int at(int row, int hour) => row * ReportWhen.hoursPerDay + hour;
  final peakWhen = ReportWhen(
    cells: [
      for (var i = 0; i < ReportWhen.cellCount; i++)
        switch (i) {
          _ when i == at(1, 18) => 600, // step 4, the peak
          _ when i == at(0, 18) => 500, // step 4
          _ when i == at(1, 19) => 450, // step 3
          _ when i == at(3, 7) => 300, // step 2
          _ when i == at(5, 10) => 60, // step 1
          _ => 0,
        },
    ],
    timedDays: 34,
    busiestWeekday: 1,
    busiestHour: 18,
  );
  final quietWhen = ReportWhen(cells: peakWhen.cells, timedDays: 9);

  Future<void> pump(
    WidgetTester tester,
    ReportWhen when, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    double width = 360,
    bool use24Hour = true,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 780);
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
            textScaler: TextScaler.linear(textScale),
            alwaysUse24HourFormat: use24Hour,
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
                builder: (context) => ReportWhenChart(
                  when: when,
                  labels: ReportLabels(AppLocalizations.of(context)!),
                  weekStart: weekStart,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  Finder card() => find.byType(ReportWhenChart);

  /// The grid's own paint.
  Finder plot() => find.descendant(
    of: card(),
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter != null,
    ),
  );

  /// The cells' calls from the painter itself, row-major.
  List<(RRect, Color)> cells(WidgetTester tester) {
    final render = tester.renderObject<RenderCustomPaint>(plot());
    final canvas = TestRecordingCanvas();
    render.painter!.paint(canvas, render.size);
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName == #drawRRect)
          (
            call.invocation.positionalArguments[0] as RRect,
            (call.invocation.positionalArguments[1] as Paint).color,
          ),
    ];
  }

  /// The card's texts with their boxes, top to bottom then left to right.
  List<(String, Rect)> texts(WidgetTester tester) {
    final found = [
      for (final element
          in find
              .descendant(of: card(), matching: find.byType(Text))
              .evaluate())
        (
          (element.widget as Text).data!,
          tester.getRect(find.byWidget(element.widget)),
        ),
    ];
    found.sort(
      (a, b) => a.$2.top != b.$2.top
          ? a.$2.top.compareTo(b.$2.top)
          : a.$2.left.compareTo(b.$2.left),
    );
    return found;
  }

  const weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};

  /// The weekday labels, top to bottom.
  List<String> weekdayLabels(WidgetTester tester) => [
    for (final (text, _) in texts(tester))
      if (weekdays.contains(text)) text,
  ];

  /// The hour labels, left to right: the texts on the grid's last line.
  List<String> hourLabels(WidgetTester tester) {
    final grid = cells(tester);
    final plotTop = tester.getRect(plot()).top;
    final gridBottom = plotTop + grid.last.$1.bottom;
    final axis = [
      for (final (text, rect) in texts(tester))
        if (rect.top > gridBottom && !text.contains('Busiest')) (text, rect),
    ]..sort((a, b) => a.$2.left.compareTo(b.$2.left));
    return [for (final (text, _) in axis) text];
  }

  group('geometry', () {
    testWidgets('360 en 1.0: the spec\'s grid, every weekday, step 3', (
      tester,
    ) async {
      await pump(tester, peakWhen);
      expect(tester.getSize(card()).height, closeTo(202, 1));
      final grid = cells(tester);
      expect(grid, hasLength(ReportWhen.cellCount));
      final first = grid.first.$1;
      final labelColumn = first.left - ReportMetrics.columnGap / 2;
      expect(labelColumn, closeTo(34.7, 1));
      final pitch = (grid[23].$1.left - first.left) / 23;
      expect(pitch, closeTo(10.89, 0.05));
      for (final (cell, _) in grid) {
        expect(cell.width, closeTo(8.89, 1));
        expect(cell.height, closeTo(16, 1));
        expect(cell.tlRadiusX, ReportMetrics.whenCellRadius);
      }
      expect(grid[ReportWhen.hoursPerDay].$1.top - first.top, closeTo(18, 1));
      expect(weekdayLabels(tester), [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(hourLabels(tester), [
        for (var hour = 0; hour < 24; hour += 3) '$hour',
      ]);
    });

    testWidgets('a weekday label is centred on its row\'s cells', (
      tester,
    ) async {
      await pump(tester, peakWhen);
      final grid = cells(tester);
      final plotTop = tester.getRect(plot()).top;
      final tue = tester.getRect(find.text('Tue'));
      final cell = grid[ReportWhen.hoursPerDay].$1;
      expect(tue.center.dy, closeTo(plotTop + cell.center.dy, 0.5));
    });

    testWidgets('360 en 1.3: every other weekday, step 3', (tester) async {
      await pump(tester, peakWhen, textScale: 1.3);
      expect(tester.getSize(card()).height, closeTo(234.3, 1));
      expect(weekdayLabels(tester), ['Mon', 'Wed', 'Fri', 'Sun']);
      expect(hourLabels(tester), hasLength(8));
    });

    testWidgets('360 en 2.0: the 2:1 cap, step 6, the caption on two lines', (
      tester,
    ) async {
      await pump(tester, peakWhen, textScale: 2.0);
      expect(tester.getSize(card()).height, closeTo(285.3, 1));
      final grid = cells(tester);
      expect(
        grid[ReportWhen.hoursPerDay].$1.top - grid.first.$1.top,
        closeTo(19.61, 1),
      );
      expect(weekdayLabels(tester), ['Mon', 'Wed', 'Fri', 'Sun']);
      expect(hourLabels(tester), ['0', '6', '12', '18']);
    });

    testWidgets('412 en 1.0: a wider pitch, the same card', (tester) async {
      await pump(tester, peakWhen, width: 412);
      expect(tester.getSize(card()).height, closeTo(202, 1));
      final grid = cells(tester);
      expect(
        (grid[23].$1.left - grid.first.$1.left) / 23,
        closeTo(13.05, 0.05),
      );
      for (final (cell, _) in grid) {
        expect(cell.width, closeTo(11.05, 1));
        expect(cell.height, closeTo(16, 1));
      }
    });

    for (final (locale, height) in [('de', 293.8), ('ro', 281.2)]) {
      testWidgets('360 $locale 2.0: the card is $height', (tester) async {
        await pump(tester, peakWhen, locale: Locale(locale), textScale: 2.0);
        expect(tester.getSize(card()).height, closeTo(height, 1));
      });
    }

    testWidgets('a Sunday week start puts Sunday in row 0', (tester) async {
      await pump(tester, peakWhen, weekStart: CalendarWeekStart.sunday);
      expect(weekdayLabels(tester), [
        'Sun',
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
      ]);
    });
  });

  group('the 12-hour clock', () {
    // intl writes the day period after a narrow no-break space.
    String hour(int hour) =>
        DateFormat.j('en').format(DateTime(2000, 1, 1, hour));

    test('the hour alone reads "12 AM"', () {
      expect(hour(0).replaceAll(' ', ' '), '12 AM');
    });

    testWidgets('labels the hours with their day period, step 6 at 1.0', (
      tester,
    ) async {
      await pump(tester, peakWhen, use24Hour: false);
      expect(hourLabels(tester), [hour(0), hour(6), hour(12), hour(18)]);
    });

    testWidgets('thins to step 12 at 2.0', (tester) async {
      await pump(tester, peakWhen, use24Hour: false, textScale: 2.0);
      expect(hourLabels(tester), [hour(0), hour(12)]);
    });
  });

  group('ramp', () {
    for (final brightness in Brightness.values) {
      final scheme = brightness == Brightness.light
          ? AppTheme.light().colorScheme
          : AppTheme.dark().colorScheme;

      test('the four steps are the spec\'s lerps of the tokens, the empty '
          'cell the track, in $brightness', () {
        expect(ReportWhenChart.fillFor(scheme, 0), scheme.rowDivider);
        for (final (step, t) in [(1, 0.5), (2, 0.67), (3, 0.84), (4, 1.0)]) {
          expect(
            ReportWhenChart.fillFor(scheme, step),
            Color.lerp(scheme.rowGroup, scheme.primary, t),
          );
        }
      });

      testWidgets('each cell draws its step\'s fill in $brightness', (
        tester,
      ) async {
        await pump(tester, peakWhen, brightness: brightness);
        final grid = cells(tester);
        // A `Paint` stores its channels as 32-bit floats, so the expected
        // colour goes through one too.
        int painted(Color color) => (Paint()..color = color).color.toARGB32();
        int fill(int step) => painted(ReportWhenChart.fillFor(scheme, step));
        int drawn(int index) => grid[index].$2.toARGB32();
        expect(drawn(at(1, 18)), fill(4));
        expect(drawn(at(0, 18)), fill(4));
        expect(drawn(at(1, 19)), fill(3));
        expect(drawn(at(3, 7)), fill(2));
        expect(drawn(at(5, 10)), fill(1));
        expect(drawn(at(6, 0)), painted(scheme.rowDivider));
        expect(
          grid.where((cell) => cell.$2.toARGB32() == fill(0)),
          hasLength(ReportWhen.cellCount - 5),
        );
      });

      test('step 1 clears 2:1 against the card and every step is darker '
          'against it than the one before, in $brightness', () {
        double ratio(Color color) => MarkerContrast.contrastRatio(
          color.computeLuminance(),
          scheme.rowGroup.computeLuminance(),
        );
        expect(ratio(ReportWhenChart.fillFor(scheme, 1)), greaterThan(2));
        for (var step = 2; step <= 4; step++) {
          expect(
            ratio(ReportWhenChart.fillFor(scheme, step)),
            greaterThan(ratio(ReportWhenChart.fillFor(scheme, step - 1))),
            reason: 'step $step',
          );
        }
      });
    }

    test('the steps are linear quarters of the peak cell', () {
      expect(ReportWhenChart.stepFor(0, 600), 0);
      expect(ReportWhenChart.stepFor(1, 600), 1);
      expect(ReportWhenChart.stepFor(150, 600), 1);
      expect(ReportWhenChart.stepFor(151, 600), 2);
      expect(ReportWhenChart.stepFor(450, 600), 3);
      expect(ReportWhenChart.stepFor(600, 600), 4);
      expect(ReportWhenChart.stepFor(5, 0), 0);
    });
  });

  group('caption and semantics', () {
    testWidgets('the busiest day and hour, one node with the spoken label, '
        'the cells excluded', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, peakWhen);
      final words = ReportLabels(lookupAppLocalizations(const Locale('en')))
          .whenWords(
            peakWhen,
            weekStart: CalendarWeekStart.monday,
            use24Hour: true,
          )!;
      expect(find.text(words.caption), findsOneWidget);
      expect(words.caption, startsWith('Busiest: Tuesday'));
      final node = tester.getSemantics(
        find.bySemanticsIdentifier(SemanticsIds.reportWhen),
      );
      expect(node.label, words.spoken);
      expect(node.label, contains('Busiest day Tuesday'));
      expect(node.label, contains('34 timed days'));
      expect(node.childrenCount, 0, reason: 'the cells are not read');
      handle.dispose();
    });

    testWidgets('no busiest day: the grid without a caption, the section '
        'name spoken', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, quietWhen);
      expect(cells(tester), hasLength(ReportWhen.cellCount));
      expect(find.textContaining('Busiest'), findsNothing);
      expect(
        tester
            .getSemantics(find.bySemanticsIdentifier(SemanticsIds.reportWhen))
            .label,
        'When',
      );
      handle.dispose();
    });
  });

  testWidgets('no layout error across the matrix', (tester) async {
    for (final scale in [1.0, 1.3, 2.0]) {
      for (final locale in const ['en', 'de', 'ro']) {
        for (final width in [360.0, 412.0]) {
          for (final brightness in Brightness.values) {
            await pump(
              tester,
              peakWhen,
              locale: Locale(locale),
              textScale: scale,
              width: width,
              brightness: brightness,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$locale $scale $width $brightness',
            );
          }
        }
      }
    }
  });
}
