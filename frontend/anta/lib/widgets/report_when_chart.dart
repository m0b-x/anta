import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../utils/report_labels.dart';

/// The report's When card (S5 §2.3): the kept timed minutes as a heatmap of
/// seven weekday rows from the app's week start by 24 hour columns, under
/// the busiest day and hour in words.
///
/// The cells are a texture, not a reading (M): no legend and no peak
/// figure — the caption, the spoken label and the Categories rows carry the
/// facts. Every label is laid out here in `build`, so the painter only
/// draws rectangles, as the Over time card does.
class ReportWhenChart extends StatelessWidget {
  const ReportWhenChart({
    super.key,
    required this.when,
    required this.labels,
    required this.weekStart,
  });

  final ReportWhen when;
  final ReportLabels labels;

  /// The app's week start, the weekday of row 0 — the fold's rows count
  /// from it.
  final CalendarWeekStart weekStart;

  /// A cell's colour at ramp [step]: 0 is an empty cell on the meter's
  /// track, 1–4 the validated linear steps of `primary` over the card (C).
  @visibleForTesting
  static Color fillFor(ColorScheme scheme, int step) => step <= 0
      ? scheme.rowDivider
      : Color.lerp(
          scheme.rowGroup,
          scheme.primary,
          ReportMetrics.whenRamp[step - 1],
        )!;

  /// The ramp step of [minutes] against the fullest cell [peakCell]: linear
  /// quarters of the peak (D), so any filled cell shows at least step 1.
  @visibleForTesting
  static int stepFor(int minutes, int peakCell) {
    if (minutes <= 0 || peakCell <= 0) return 0;
    final steps = ReportMetrics.whenRamp.length;
    return (steps * minutes / peakCell).ceil().clamp(1, steps);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final locale = Localizations.localeOf(context).toString();
    final captionStyle = TextStyle(
      fontSize: FormMetrics.captionSize,
      height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
      color: colorScheme.onSurfaceVariant,
    );
    // Measured as `Text` will draw it: under the bold-text setting a label
    // is wider, and a column or a step decided without it would overlap.
    var measuredStyle = DefaultTextStyle.of(context).style.merge(captionStyle);
    if (MediaQuery.boldTextOf(context)) {
      measuredStyle = measuredStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final words = labels.whenWords(
      when,
      weekStart: weekStart,
      use24Hour: use24Hour,
    );
    final weekday = DateFormat.E(locale);
    // January 2024 opens on a Monday, so its day N is weekday N.
    final rowNames = [
      for (var row = 0; row < DateTime.daysPerWeek; row++)
        weekday.format(
          DateTime.utc(
            2024,
            1,
            (weekStart.weekday - 1 + row) % DateTime.daysPerWeek + 1,
          ),
        ),
    ];
    final fills = [
      for (var step = 0; step <= ReportMetrics.whenRamp.length; step++)
        fillFor(colorScheme, step),
    ];

    return Semantics(
      container: true,
      identifier: SemanticsIds.reportWhen,
      label: words?.spoken ?? labels.l10n.reportSectionWhen,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.card,
          clipBehavior: Clip.antiAlias,
          color: colorScheme.rowGroup,
          borderRadius: BorderRadius.circular(RowMetrics.groupRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ReportMetrics.chartPaddingHorizontal,
              vertical: ReportMetrics.chartPaddingVertical,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => _grid(
                    context,
                    constraints.maxWidth,
                    rowNames: rowNames,
                    hourLabels: _hourLabels(locale, use24Hour: use24Hour),
                    fills: fills,
                    measured: measuredStyle,
                    drawn: captionStyle,
                    scaler: scaler,
                  ),
                ),
                if (words != null) ...[
                  const SizedBox(height: ReportMetrics.chartCaptionGap),
                  Text(words.caption, style: captionStyle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The hour axis's words by hour, for every hour a step can land on. The
  /// hour alone where the clock writes a day period ("6 PM"), as the
  /// caption's words do; else the bare hour ("18").
  static Map<int, String> _hourLabels(
    String locale, {
    required bool use24Hour,
  }) {
    final dayPeriod =
        !use24Hour && (DateFormat.jm(locale).pattern ?? '').contains('a');
    final hourOnly = DateFormat.j(locale);
    final every = ReportMetrics.whenHourSteps.first;
    return {
      for (var hour = 0; hour < ReportWhen.hoursPerDay; hour += every)
        hour: dayPeriod ? hourOnly.format(DateTime(2000, 1, 1, hour)) : '$hour',
    };
  }

  /// The grid with its weekday column and hour axis, sized from [width]:
  /// the column pitch from what the weekday names leave, the row pitch from
  /// one caption line held between one and two pitches (L), so a large text
  /// scale thins the weekday labels rather than stretching the grid.
  Widget _grid(
    BuildContext context,
    double width, {
    required List<String> rowNames,
    required Map<int, String> hourLabels,
    required List<Color> fills,
    required TextStyle measured,
    required TextStyle drawn,
    required TextScaler scaler,
  }) {
    final direction = Directionality.of(context);
    final widths = <String, double>{};
    double measure(String text) => widths.putIfAbsent(text, () {
      final painter = TextPainter(
        text: TextSpan(text: text, style: measured),
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final measuredWidth = painter.width;
      painter.dispose();
      return measuredWidth;
    });

    final line = scaler.scale(FormMetrics.captionLineHeight);
    final nameWidth = rowNames.map(measure).reduce(math.max);
    final labelColumn = nameWidth + ReportMetrics.whenLabelGap;
    final pitch = (width - labelColumn) / ReportWhen.hoursPerDay;
    if (pitch <= 0) return const SizedBox.shrink();
    final rowPitch = line.clamp(pitch, ReportMetrics.whenRowAspectMax * pitch);
    final gridHeight = rowPitch * DateTime.daysPerWeek;
    final labelEvery = math.max(1, (line / rowPitch).ceil());
    final widestHour = hourLabels.values.map(measure).reduce(math.max);
    final hourStep = ReportMetrics.whenHourSteps.firstWhere(
      (step) => step * pitch >= widestHour + ReportMetrics.axisLabelMinGap,
      orElse: () => ReportMetrics.whenHourSteps.last,
    );

    // Each label sits in a box of one caption line and shrinks to it — the
    // trend axis's rule — so a non-linear scale never spills past its row.
    Widget label(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: drawn, maxLines: 1, softWrap: false),
    );

    var peakCell = 0;
    for (final minutes in when.cells) {
      if (minutes > peakCell) peakCell = minutes;
    }

    return SizedBox(
      height: gridHeight + ReportMetrics.axisGap + line,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: width,
            height: gridHeight,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WhenPainter(
                  cells: when.cells,
                  peakCell: peakCell,
                  fills: fills,
                  labelColumn: labelColumn,
                  pitch: pitch,
                  rowPitch: rowPitch,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
              ),
            ),
          ),
          for (var row = 0; row < rowNames.length; row += labelEvery)
            Positioned(
              left: 0,
              top: (row + 0.5) * rowPitch - line / 2,
              width: math.min(measure(rowNames[row]), nameWidth),
              height: line,
              child: label(rowNames[row]),
            ),
          for (var hour = 0; hour < ReportWhen.hoursPerDay; hour += hourStep)
            if (hourLabels[hour] case final text?)
              _hourLabel(
                textWidth: math.min(measure(text), width),
                centre: labelColumn + (hour + 0.5) * pitch,
                width: width,
                top: gridHeight + ReportMetrics.axisGap,
                line: line,
                child: label(text),
              ),
        ],
      ),
    );
  }

  /// An hour label centred under its column and kept inside the card.
  static Widget _hourLabel({
    required double textWidth,
    required double centre,
    required double width,
    required double top,
    required double line,
    required Widget child,
  }) {
    final left = math.min(
      math.max(0.0, centre - textWidth / 2),
      math.max(0.0, width - textWidth),
    );
    return Positioned(
      left: left,
      top: top,
      width: textWidth,
      height: line,
      child: child,
    );
  }
}

/// The cells, row-major as [ReportWhen.cells] holds them. Bounds and
/// colours only; every word is laid out by the card.
///
/// Cell edges are snapped to physical pixels, so 24 narrow columns keep
/// even gaps.
class _WhenPainter extends CustomPainter {
  _WhenPainter({
    required this.cells,
    required this.peakCell,
    required this.fills,
    required this.labelColumn,
    required this.pitch,
    required this.rowPitch,
    required this.devicePixelRatio,
  });

  final List<int> cells;
  final int peakCell;

  /// [ReportWhenChart.fillFor] by step, the empty cell's first.
  final List<Color> fills;

  /// Where the first hour column starts: the weekday names and their gap.
  final double labelColumn;
  final double pitch;
  final double rowPitch;
  final double devicePixelRatio;

  /// [logical] rounded to the nearest physical pixel.
  double _snap(double logical) =>
      (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final half = ReportMetrics.columnGap / 2;
    final gap = math.max(1.0, _snap(ReportMetrics.columnGap));
    final paints = [for (final color in fills) Paint()..color = color];
    const radius = Radius.circular(ReportMetrics.whenCellRadius);
    for (var row = 0; row < DateTime.daysPerWeek; row++) {
      // A cell runs from half a gap past its pitch's start to the next
      // cell's start less a whole gap, so every gap is the same number of
      // pixels.
      final top = _snap(row * rowPitch + half);
      final bottom = _snap((row + 1) * rowPitch + half) - gap;
      for (var hour = 0; hour < ReportWhen.hoursPerDay; hour++) {
        final index = row * ReportWhen.hoursPerDay + hour;
        final minutes = index < cells.length ? cells[index] : 0;
        final left = _snap(labelColumn + hour * pitch + half);
        final right = _snap(labelColumn + (hour + 1) * pitch + half) - gap;
        if (right <= left || bottom <= top) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(left, top, right, bottom),
            radius,
          ),
          paints[ReportWhenChart.stepFor(minutes, peakCell)],
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WhenPainter oldDelegate) =>
      !identical(cells, oldDelegate.cells) ||
      peakCell != oldDelegate.peakCell ||
      !listEquals(fills, oldDelegate.fills) ||
      labelColumn != oldDelegate.labelColumn ||
      pitch != oldDelegate.pitch ||
      rowPitch != oldDelegate.rowPitch ||
      devicePixelRatio != oldDelegate.devicePixelRatio;
}
