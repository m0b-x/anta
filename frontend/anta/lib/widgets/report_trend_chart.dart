import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../models/date_range.dart';
import '../utils/report_labels.dart';

/// The report's Over time card (§4.8): one series of columns — the
/// occurrences that happened in `primary`, the routines' missed part stacked
/// above in `outlineVariant` — over the whole span, the days after today at
/// zero so a month so far still reads as a month.
///
/// Read-only on purpose (Q): no column is a target, and a screen reader
/// hears one summary; the group headers are the chart's table twin. Every
/// label is laid out here in `build`, so the painter only draws rectangles.
class ReportTrendChart extends StatelessWidget {
  const ReportTrendChart({
    super.key,
    required this.trend,
    required this.labels,
    required this.weekStart,
    required this.span,
  });

  final ReportTrend trend;
  final ReportLabels labels;

  /// The app's week start: a month's axis labels the columns a week opens.
  final CalendarWeekStart weekStart;

  /// The span the buckets cover, so the last week column knows where it
  /// ends.
  final DateRange span;

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
    final buckets = trend.buckets;
    final peak = ReportLabels.peakOf(trend);
    final words = labels.trendWords(trend, use24Hour: use24Hour);
    final caption = words.caption;
    final bothParts =
        buckets.any((bucket) => bucket.happened > 0) &&
        buckets.any((bucket) => bucket.missed > 0);
    final axis = _AxisFormats.of(trend.unit, locale);
    // The axis is measured as `Text` will draw it: under the bold-text
    // setting a label is wider, and a fit decided without it would overlap.
    var axisStyle = DefaultTextStyle.of(context).style.merge(captionStyle);
    if (MediaQuery.boldTextOf(context)) {
      axisStyle = axisStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }

    final topRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: bothParts
              ? Wrap(
                  spacing: ReportMetrics.legendItemSpacing,
                  runSpacing: RowMetrics.lineGap,
                  children: [
                    _LegendItem(
                      color: colorScheme.primary,
                      label: labels.l10n.reportLegendHappened,
                      style: captionStyle,
                    ),
                    _LegendItem(
                      color: colorScheme.outlineVariant,
                      label: labels.l10n.reportTileMissed,
                      style: captionStyle,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: FormMetrics.gap),
        Text('$peak', style: captionStyle, textAlign: TextAlign.end),
      ],
    );

    return Semantics(
      container: true,
      identifier: SemanticsIds.reportTrend,
      label: words.spoken,
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
                topRow,
                const SizedBox(height: ReportMetrics.chartTopGap),
                SizedBox(
                  height: ReportMetrics.chartPlotHeight,
                  child: CustomPaint(
                    painter: _TrendPainter(
                      buckets: buckets,
                      peak: peak,
                      happenedColor: colorScheme.primary,
                      missedColor: colorScheme.outlineVariant,
                      lineColor: colorScheme.rowDivider,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: ReportMetrics.axisGap),
                SizedBox(
                  height: scaler.scale(FormMetrics.captionLineHeight),
                  child: LayoutBuilder(
                    builder: (context, constraints) => _axis(
                      context,
                      constraints.maxWidth,
                      axis,
                      axisStyle,
                      captionStyle,
                      scaler,
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: ReportMetrics.chartCaptionGap),
                  Text(caption, style: captionStyle),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The axis labels as positioned texts, each centred under its column and
  /// kept inside the card; one closer than [ReportMetrics.axisLabelMinGap]
  /// to the last one drawn is skipped, so a busy axis thins out rather than
  /// overlapping. Each label sits in a box of one caption line and shrinks
  /// to it — the meter row's caption rule — so a non-linear text scale that
  /// grows the line past the box never spills into the caption gap.
  Widget _axis(
    BuildContext context,
    double width,
    _AxisFormats axis,
    TextStyle measured,
    TextStyle drawn,
    TextScaler scaler,
  ) {
    final buckets = trend.buckets;
    if (buckets.isEmpty || width <= 0) return const SizedBox.shrink();
    final direction = Directionality.of(context);
    final slot = width / buckets.length;
    // One layout per distinct label: the fit pass and the placement pass
    // read the same widths.
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

    final lineHeight = scaler.scale(FormMetrics.captionLineHeight);
    final candidates = _candidates(axis, slot, measure);
    final placed = <Widget>[];
    var lastEnd = double.negativeInfinity;
    for (final (index, text) in candidates) {
      final textWidth = math.min(measure(text), width);
      final centre = (index + 0.5) * slot;
      final left = math.min(
        math.max(0.0, centre - textWidth / 2),
        math.max(0.0, width - textWidth),
      );
      if (left < lastEnd + ReportMetrics.axisLabelMinGap) continue;
      lastEnd = left + textWidth;
      placed.add(
        Positioned(
          left: left,
          top: 0,
          width: textWidth,
          height: lineHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, style: drawn, maxLines: 1, softWrap: false),
          ),
        ),
      );
    }
    return Stack(clipBehavior: Clip.none, children: placed);
  }

  /// The labels the unit asks for, by column (§4.8): a week's weekdays
  /// (narrow when the short name does not fit a column), a longer run of
  /// days' week starts as day numbers (X), the week holding a month's 1st
  /// as the month, every month (narrow when the short name does not fit).
  List<(int, String)> _candidates(
    _AxisFormats axis,
    double slot,
    double Function(String) measure,
  ) {
    final buckets = trend.buckets;
    switch (trend.unit) {
      case ReportTrendUnit.day:
        if (buckets.length <= DateTime.daysPerWeek) {
          return _fitted(axis.short, axis.narrow, slot, measure);
        }
        return [
          for (final (index, bucket) in buckets.indexed)
            if (bucket.start.weekday == weekStart.weekday)
              (index, '${bucket.start.day}'),
        ];
      case ReportTrendUnit.week:
        return [
          for (var index = 0; index < buckets.length; index++)
            if (_firstOfMonthIn(index) case final first?)
              (index, axis.short.format(first)),
        ];
      case ReportTrendUnit.month:
        return _fitted(axis.short, axis.narrow, slot, measure);
    }
  }

  /// One label per column in [short], or in [narrow] when any short label
  /// would leave less than [ReportMetrics.axisLabelMinGap] to its
  /// neighbour — a label that fits its column but would then be thinned
  /// left "This year" with seven of its twelve months.
  List<(int, String)> _fitted(
    DateFormat short,
    DateFormat narrow,
    double slot,
    double Function(String) measure,
  ) {
    final buckets = trend.buckets;
    final shortLabels = [
      for (final bucket in buckets) short.format(bucket.start),
    ];
    final room = slot - ReportMetrics.axisLabelMinGap;
    final fits = shortLabels.every((label) => measure(label) <= room);
    return [
      for (final (index, bucket) in buckets.indexed)
        (index, fits ? shortLabels[index] : narrow.format(bucket.start)),
    ];
  }

  /// The 1st of a month inside week column [index], or null. A column runs
  /// to the day before the next one starts; the last runs to the span's end.
  DateTime? _firstOfMonthIn(int index) {
    final buckets = trend.buckets;
    final start = buckets[index].start;
    if (start.day == 1) return start;
    final end = index + 1 < buckets.length
        ? buckets[index + 1].start.subtract(const Duration(days: 1))
        : span.end;
    if (end.year == start.year && end.month == start.month) return null;
    return DateTime.utc(end.year, end.month, 1);
  }
}

/// The axis's two date formats for a unit, built once per build.
class _AxisFormats {
  const _AxisFormats(this.short, this.narrow);

  /// Days: `E`, weeks and months: `MMM`.
  final DateFormat short;

  /// Days: `EEEEE`, months: `MMMMM`; weeks never narrow.
  final DateFormat narrow;

  factory _AxisFormats.of(ReportTrendUnit unit, String locale) {
    return switch (unit) {
      ReportTrendUnit.day => _AxisFormats(
        DateFormat.E(locale),
        DateFormat('EEEEE', locale),
      ),
      ReportTrendUnit.week || ReportTrendUnit.month => _AxisFormats(
        DateFormat.MMM(locale),
        DateFormat('MMMMM', locale),
      ),
    };
  }
}

/// A legend dot and its word; the word shrinks to the wrap's width rather
/// than overflow it.
class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.style,
  });

  final Color color;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: RowMetrics.labelDotSize,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: ReportMetrics.legendDotGap),
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}

/// The plot: the peak and baseline hairlines and the columns. Bounds and
/// colours only; every word is laid out by the card.
///
/// Column edges and the hairlines are snapped to physical pixels, so 31
/// narrow columns keep even gaps and the hairlines stay one crisp line
/// rather than two blurred half-lines.
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.buckets,
    required this.peak,
    required this.happenedColor,
    required this.missedColor,
    required this.lineColor,
    required this.devicePixelRatio,
  });

  final List<ReportTrendBucket> buckets;
  final int peak;
  final Color happenedColor;
  final Color missedColor;
  final Color lineColor;
  final double devicePixelRatio;

  /// [logical] rounded to the nearest physical pixel.
  double _snap(double logical) =>
      (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final height = size.height;
    final line = Paint()..color = lineColor;
    final hairline =
        math.max(1.0, devicePixelRatio.roundToDouble()) / devicePixelRatio;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, hairline), line);
    canvas.drawRect(
      Rect.fromLTWH(0, height - hairline, size.width, hairline),
      line,
    );
    if (buckets.isEmpty || peak <= 0) return;
    final slot = size.width / buckets.length;
    final width = math.max(
      0.0,
      math.min(ReportMetrics.columnMaxWidth, slot - ReportMetrics.columnGap),
    );
    if (width == 0) return;
    final capped = width < slot - ReportMetrics.columnGap;
    final gap = math.max(1.0, _snap(ReportMetrics.columnGap));
    final perUnit = height / peak;
    final happened = Paint()..color = happenedColor;
    final missed = Paint()..color = missedColor;
    for (final (index, bucket) in buckets.indexed) {
      if (bucket.happened + bucket.missed == 0) continue;
      // A capped column keeps its width, centred; a full-slot column runs
      // from half a gap past its slot's start to the next column's start
      // less a whole gap, so every gap is the same number of pixels.
      final double left;
      final double right;
      if (capped) {
        left = _snap(index * slot + (slot - width) / 2);
        right = left + _snap(width);
      } else {
        left = _snap(index * slot + ReportMetrics.columnGap / 2);
        right = _snap((index + 1) * slot + ReportMetrics.columnGap / 2) - gap;
      }
      final radius = math.min(ReportMetrics.columnRadius, (right - left) / 2);
      final total = (bucket.happened + bucket.missed) * perUnit;
      if (bucket.missed == 0) {
        _column(
          canvas,
          Rect.fromLTRB(left, height - total, right, height),
          radius,
          happened,
        );
        continue;
      }
      // A missed part never vanishes under the surface gap: it keeps at
      // least the gap's height, and a short column takes the room from its
      // happened part instead (which keeps a gap's height too).
      final gapAbove = bucket.happened > 0 ? ReportMetrics.columnGap : 0.0;
      final missedHeight = math.max(
        ReportMetrics.columnGap,
        bucket.missed * perUnit - gapAbove,
      );
      var happenedHeight = 0.0;
      if (bucket.happened > 0) {
        happenedHeight = math.max(
          ReportMetrics.columnGap,
          total - missedHeight - gapAbove,
        );
        _column(
          canvas,
          Rect.fromLTRB(left, height - happenedHeight, right, height),
          0,
          happened,
        );
      }
      final missedBottom = height - happenedHeight - gapAbove;
      _column(
        canvas,
        Rect.fromLTRB(left, missedBottom - missedHeight, right, missedBottom),
        radius,
        missed,
      );
    }
  }

  /// A segment rounded at its top only: the data end, never the baseline.
  static void _column(Canvas canvas, Rect rect, double radius, Paint paint) {
    final corner = Radius.circular(math.min(radius, rect.height));
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect, topLeft: corner, topRight: corner),
      paint,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      !identical(buckets, oldDelegate.buckets) ||
      peak != oldDelegate.peak ||
      happenedColor != oldDelegate.happenedColor ||
      missedColor != oldDelegate.missedColor ||
      lineColor != oldDelegate.lineColor ||
      devicePixelRatio != oldDelegate.devicePixelRatio;
}
