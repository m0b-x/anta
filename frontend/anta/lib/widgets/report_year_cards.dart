/// The year in review's two cards (S6, `docs/calendar-analytics-specs/
/// s6-design-spec.md` §2.2–2.3): Records and Months, which a whole-year
/// span puts after the Totals caption. Like the analytics cards, each draws
/// no section label of its own — the page sets `FormSectionLabel` above
/// it — and is absent when it has nothing to show.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../constants/analytics_metrics.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/category_kinds.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../utils/report_labels.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'report_category_group.dart';
import 'report_group_stack.dart';
import 'report_when_chart.dart';

/// The Records card (§2.2): one read [FormMeterRow] per record of
/// [ReportYear.records], in the model's order — the kind's glyph, its name,
/// "June · 31 events" and no meter. Past [ReportMetrics.yearRecordRows] a
/// disclosure row expands the card in place and folds it back, as Due soon
/// does.
///
/// The caption keeps one line below [RowMetrics.compactLeadingTextScale]
/// and reserves [ReportMetrics.yearRecordCaptionLinesCompact] from it,
/// decided by the scale and never by the record, so a refold that swaps a
/// record keeps every row's height.
class ReportRecordsCard extends StatefulWidget {
  const ReportRecordsCard({
    super.key,
    required this.report,
    required this.labels,
    required this.folds,
    this.onShrink,
    this.scroll,
    required this.weekStart,
  });

  /// The report whose [CalendarReport.year] records the card draws.
  final CalendarReport report;

  /// The page's words, built once per build.
  final ReportLabels labels;

  /// The surface's fold state; the card's expansion is kept there.
  final ReportGroupFolds folds;

  /// Called before "Show less" folds the card, as [ReportDueSoonCard]
  /// calls its own.
  final VoidCallback? onShrink;

  /// The surface's one scroll, which "Show less" moves back by the rows
  /// that leave (S); null moves nothing.
  final ScrollController? scroll;

  /// The app's week start, which names the busiest week as the band names
  /// a week page: the report does not carry it.
  final CalendarWeekStart weekStart;

  @override
  State<ReportRecordsCard> createState() => _ReportRecordsCardState();
}

class _ReportRecordsCardState extends State<ReportRecordsCard> {
  final GlobalKey _firstFolded = GlobalKey();
  final GlobalKey _disclosureKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final records = widget.report.year?.records ?? const <ReportRecord>[];
    if (records.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final captionLines =
        FormMeterRow.isCompact(MediaQuery.textScalerOf(context))
        ? ReportMetrics.yearRecordCaptionLinesCompact
        : 1;
    const cap = ReportMetrics.yearRecordRows;
    final capped = records.length > cap;
    final expanded = capped && widget.folds.isRecordsExpanded;
    final shown = capped && !expanded ? records.take(cap) : records;
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final (index, record) in shown.indexed)
          _row(
            scheme,
            record,
            captionLines,
            key: expanded && index == cap ? _firstFolded : null,
          ),
        if (capped)
          _yearDisclosure(
            widget.labels.l10n,
            key: _disclosureKey,
            section: widget.labels.l10n.reportSectionRecords,
            hidden: records.length - cap,
            expanded: expanded,
            onTap: _toggle,
            identifier: SemanticsIds.reportYearRecordsMore,
          ),
      ],
    );
  }

  Widget _row(
    ColorScheme scheme,
    ReportRecord record,
    int captionLines, {
    Key? key,
  }) {
    final labels = widget.labels;
    final words = labels.recordWords(
      record,
      widget.report,
      weekStart: widget.weekStart,
    );
    final glyph = FormGlyph(
      icon: _recordIcon(record.kind),
      color: scheme.onSurfaceVariant,
    );
    return FormMeterRow(
      key: key,
      leading: glyph,
      compactLeading: glyph,
      label: labels.recordName(record.kind),
      caption: words.caption,
      captionLines: captionLines,
      onTap: null,
      semanticsLabel: words.spoken,
      identifier: _recordId(record),
    );
  }

  /// The glyph names the record, never its value (§2.2, L).
  static IconData _recordIcon(ReportRecordKind kind) => switch (kind) {
    ReportRecordKind.busiestMonth => Icons.calendar_view_month_rounded,
    ReportRecordKind.busiestWeek => Icons.view_week_rounded,
    ReportRecordKind.socialMonth => CalendarIcons.areaIcon(LifeArea.people),
    ReportRecordKind.moneyMonth => CalendarIcons.areaIcon(LifeArea.money),
    ReportRecordKind.longestTrip => Icons.luggage_rounded,
    ReportRecordKind.longestStreak => Icons.done_all_rounded,
    ReportRecordKind.longestGap => Icons.hourglass_empty_rounded,
  };

  /// A streak by its event and a gap by its category, since a year holds
  /// one of each per routine or gap goal; every other kind once, by its
  /// name in kebab case.
  static String _recordId(ReportRecord record) => switch (record.kind) {
    ReportRecordKind.longestStreak => SemanticsIds.reportYearRecordStreak(
      record.eventId ?? '',
    ),
    ReportRecordKind.longestGap => SemanticsIds.reportYearRecordGap(
      record.categoryId ?? '',
    ),
    _ => SemanticsIds.reportYearRecord(
      record.kind.name.replaceAllMapped(
        RegExp('[A-Z]'),
        (match) => '-${match[0]!.toLowerCase()}',
      ),
    ),
  };

  void _toggle() {
    final folds = widget.folds;
    final expanded = folds.isRecordsExpanded;
    if (expanded) {
      _foldBack(widget.scroll, widget.onShrink, _firstFolded, _disclosureKey);
    }
    setState(() => folds.setRecordsExpanded(!expanded));
  }
}

/// The Months card (§2.3): an axis of month names, then one strip row per
/// category of [CalendarReport.categories] kept in the year, in that card's
/// order — the avatar, the name, the kept span "Jan 2 – Dec 30" and twelve
/// tiles of the category's primary by month. Past
/// [AnalyticsMetrics.yearMonthsStripCategories] strips a disclosure row
/// expands the card in place (C).
///
/// The tiles are a texture (F): the caption, the spoken twelve-month list
/// and the Categories rows carry the facts.
class ReportMonthsCard extends StatefulWidget {
  const ReportMonthsCard({
    super.key,
    required this.report,
    required this.labels,
    required this.folds,
    this.onShrink,
    this.scroll,
    this.onCategoryTap,
  });

  /// The report whose [CalendarReport.year] months the card draws.
  final CalendarReport report;

  /// The page's words, built once per build.
  final ReportLabels labels;

  /// The surface's fold state; the card's expansion is kept there.
  final ReportGroupFolds folds;

  /// Called before "Show less" folds the card, as [ReportDueSoonCard]
  /// calls its own.
  final VoidCallback? onShrink;

  /// The surface's one scroll, which "Show less" moves back by the strips
  /// that leave (S); null moves nothing.
  final ScrollController? scroll;

  /// A strip's tap, with its category id: the page opens that category's
  /// Categories group (S4 G). Null draws read rows.
  final ValueChanged<String>? onCategoryTap;

  @override
  State<ReportMonthsCard> createState() => _ReportMonthsCardState();
}

class _ReportMonthsCardState extends State<ReportMonthsCard> {
  final GlobalKey _firstFolded = GlobalKey();
  final GlobalKey _disclosureKey = GlobalKey();

  /// What [_lines] was measured at: every strip's caption shares one
  /// template, so one count serves the card until the width, scale,
  /// locale, style or direction changes.
  ({
    double width,
    TextScaler scaler,
    String locale,
    TextStyle style,
    TextDirection direction,
  })?
  _linesKey;
  int _lines = 1;

  CalendarReport get report => widget.report;
  ReportLabels get labels => widget.labels;

  @override
  Widget build(BuildContext context) {
    final year = report.year;
    if (year == null) return const SizedBox.shrink();
    // A category whose every day was missed has no months: it has no strip.
    final strips = [
      for (final group in report.categories)
        if ((year.months[group.categoryId], year.spans[group.categoryId]) case (
          final months?,
          final span?,
        ))
          (id: group.categoryId, months: months, span: span),
    ];
    if (strips.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final fills = [
      for (var step = 0; step <= ReportMetrics.whenRamp.length; step++)
        ReportWhenChart.fillFor(scheme, step),
    ];
    // Today's month draws its value so far; only the months after it, in
    // the current year, are still ahead.
    final aheadFrom = report.today.year == report.span.start.year
        ? report.today.month
        : DateTime.monthsPerYear;
    const cap = AnalyticsMetrics.yearMonthsStripCategories;
    final capped = strips.length > cap;
    final expanded = capped && widget.folds.isMonthsExpanded;
    final shown = capped && !expanded ? strips.take(cap) : strips;
    return LayoutBuilder(
      builder: (context, constraints) {
        final captionLines = _captionLinesFor(context, constraints.maxWidth);
        return FormRowGroup(
          trailingGap: false,
          children: [
            _MonthAxisRow(locale: labels.l10n.localeName),
            for (final (index, strip) in shown.indexed)
              _row(
                strip.id,
                strip.months,
                strip.span,
                captionLines: captionLines,
                strip: _YearStrip(
                  months: strip.months,
                  fills: fills,
                  ahead: scheme.outlineVariant,
                  aheadFrom: aheadFrom,
                ),
                key: expanded && index == cap ? _firstFolded : null,
              ),
            if (capped)
              _yearDisclosure(
                labels.l10n,
                key: _disclosureKey,
                section: labels.l10n.reportSectionMonths,
                hidden: strips.length - cap,
                expanded: expanded,
                onTap: _toggle,
                identifier: SemanticsIds.reportYearMonthsMore,
              ),
          ],
        );
      },
    );
  }

  /// The caption lines every strip reserves at [cardWidth] (S4 D): the
  /// lines its span template wraps to, the widest month measured as the
  /// caption draws it.
  int _captionLinesFor(BuildContext context, double cardWidth) {
    final style = reportCaptionStyleOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final key = (
      width: cardWidth - _textColumnStart(scaler) - FormMetrics.rowEndPadding,
      scaler: scaler,
      locale: labels.l10n.localeName,
      style: style,
      direction: direction,
    );
    if (key == _linesKey) return _lines;
    _linesKey = key;
    return _lines = reportCaptionLines(
      labels.yearSpanTemplates(
        widest: (names) =>
            ReportTagCaptions.widestOf(names, style, scaler, direction),
      ),
      style: style,
      scaler: scaler,
      direction: direction,
      width: key.width,
    );
  }

  Widget _row(
    String categoryId,
    List<int> months,
    ({DateTime first, DateTime last}) span, {
    required int captionLines,
    required Widget strip,
    Key? key,
  }) {
    final category = CalendarCategories.resolve(categoryId);
    final name = CalendarCategories.labelOf(category, labels.l10n);
    final icon = CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
    final onCategoryTap = widget.onCategoryTap;
    return FormMeterRow(
      key: key,
      leading: EventAvatar(icon: icon, color: category.color),
      compactLeading: FormGlyph(icon: icon, color: category.color),
      label: name,
      caption: labels.yearSpan(span.first, span.last),
      captionLines: captionLines,
      chart: strip,
      onTap: onCategoryTap == null ? null : () => onCategoryTap(categoryId),
      semanticsLabel: labels.yearMonthsSpoken(
        category: name,
        span: labels.yearSpanSpoken(span.first, span.last),
        months: months,
        primary: report.measures[categoryId]?.primary ?? ReportMeasure.count,
      ),
      identifier: SemanticsIds.reportYearMonths(categoryId),
    );
  }

  void _toggle() {
    final folds = widget.folds;
    final expanded = folds.isMonthsExpanded;
    if (expanded) {
      _foldBack(widget.scroll, widget.onShrink, _firstFolded, _disclosureKey);
    }
    setState(() => folds.setMonthsExpanded(!expanded));
  }
}

/// Where a strip row's text column starts at [scaler] — it ends
/// [FormMetrics.rowEndPadding] before the row's — so the axis names and
/// the span captions are laid out at the width the row draws its chart.
double _textColumnStart(TextScaler scaler) =>
    RowMetrics.groupInset +
    (FormMeterRow.isCompact(scaler)
        ? RowMetrics.glyphSize
        : FormMetrics.rowLeadingSize) +
    FormMetrics.gap;

/// The Months card's first row (N): the twelve month names, each centred
/// on its tile at the strips' x. Short names where every one fits its
/// tile's pitch less [ReportMetrics.axisLabelMinGap], else the narrow ones
/// — the Over time axis's rule — then every step-th name, the smallest of
/// [ReportMetrics.yearAxisSteps] that keeps the gap. Measured as the
/// caption draws, bold included. Decoration: the strips' spoken lists are
/// its twin.
class _MonthAxisRow extends FormDividedRow {
  const _MonthAxisRow({required this.locale});

  final String locale;

  @override
  double get dividerIndent => FormMetrics.dividerIndentTitle;

  @override
  double dividerIndentIn(BuildContext context) =>
      FormMeterRow.isCompact(MediaQuery.textScalerOf(context))
      ? RowMetrics.dividerIndentWithGlyph
      : FormMetrics.dividerIndentTitle;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final line = scaler.scale(FormMetrics.captionLineHeight);
    final measured = reportCaptionStyleOf(context);
    final drawn = TextStyle(
      fontSize: FormMetrics.captionSize,
      height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.only(
          left: _textColumnStart(scaler),
          right: FormMetrics.rowEndPadding,
          top: ReportMetrics.yearAxisPadding,
          bottom: ReportMetrics.yearAxisPadding,
        ),
        child: SizedBox(
          height: line,
          child: LayoutBuilder(
            builder: (context, constraints) => _names(
              context,
              constraints.maxWidth,
              measured: measured,
              drawn: drawn,
              scaler: scaler,
              line: line,
            ),
          ),
        ),
      ),
    );
  }

  Widget _names(
    BuildContext context,
    double width, {
    required TextStyle measured,
    required TextStyle drawn,
    required TextScaler scaler,
    required double line,
  }) {
    if (width <= 0) return const SizedBox.shrink();
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

    final pitch = _YearStripGeometry.pitchOf(width);
    final formats = _AxisFormats.of(locale);
    final short = formats.short;
    final room = pitch - ReportMetrics.axisLabelMinGap;
    final names = short.every((name) => measure(name) <= room)
        ? short
        : formats.narrow;
    final widest = names.map(measure).reduce(math.max);
    final step = ReportMetrics.yearAxisSteps.firstWhere(
      (step) => step * pitch >= widest + ReportMetrics.axisLabelMinGap,
      orElse: () => ReportMetrics.yearAxisSteps.last,
    );
    final tile = pitch - ReportMetrics.columnGap;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var month = 0; month < names.length; month += step)
          _name(
            names[month],
            textWidth: math.min(measure(names[month]), width),
            centre: month * pitch + tile / 2,
            width: width,
            line: line,
            style: drawn,
          ),
      ],
    );
  }

  /// A name centred on its tile and kept inside the strip, in a box of one
  /// caption line it shrinks to — the trend axis's rule, so a non-linear
  /// scale never spills past the row.
  static Widget _name(
    String text, {
    required double textWidth,
    required double centre,
    required double width,
    required double line,
    required TextStyle style,
  }) => Positioned(
    left: (centre - textWidth / 2).clamp(0.0, math.max(0.0, width - textWidth)),
    top: 0,
    width: textWidth,
    height: line,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: style, maxLines: 1, softWrap: false),
    ),
  );
}

/// The axis's month names for a locale, built once per locale; the app
/// speaks three languages, so the cache stays that small.
class _AxisFormats {
  _AxisFormats._(String locale)
    : short = _months(DateFormat.MMM(locale)),
      narrow = _months(DateFormat('MMMMM', locale));

  static final Map<String, _AxisFormats> _byLocale = {};

  factory _AxisFormats.of(String locale) =>
      _byLocale.putIfAbsent(locale, () => _AxisFormats._(locale));

  final List<String> short;
  final List<String> narrow;

  static List<String> _months(DateFormat format) => [
    for (var month = 1; month <= DateTime.monthsPerYear; month++)
      format.format(DateTime.utc(2026, month)),
  ];
}

/// The strip's tile grid, shared by the axis and the painter so a name sits
/// on its tile.
abstract final class _YearStripGeometry {
  /// Twelve tiles and eleven [ReportMetrics.columnGap]s fill [width].
  static double pitchOf(double width) =>
      (width + ReportMetrics.columnGap) / DateTime.monthsPerYear;
}

/// One category's twelve tiles, [ReportMetrics.yearTileHeight] tall at the
/// text column's width, repainting alone.
class _YearStrip extends StatelessWidget {
  const _YearStrip({
    required this.months,
    required this.fills,
    required this.ahead,
    required this.aheadFrom,
  });

  final List<int> months;
  final List<Color> fills;
  final Color ahead;
  final int aheadFrom;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ReportMetrics.yearTileHeight,
    child: RepaintBoundary(
      child: CustomPaint(
        painter: ReportYearStripPainter(
          months: months,
          fills: fills,
          ahead: ahead,
          aheadFrom: aheadFrom,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    ),
  );
}

/// A Months strip (§2.3, F): twelve tiles, each filled at its ramp step of
/// the strip's own peak — the units differ per category, so a strip is
/// read against itself — an empty month on the meter's track, and a month
/// still ahead as a hollow outline. Tile edges are snapped to physical
/// pixels, so twelve narrow tiles keep even gaps, as the When grid does.
class ReportYearStripPainter extends CustomPainter {
  ReportYearStripPainter({
    required this.months,
    required this.fills,
    required this.ahead,
    required this.aheadFrom,
    required this.devicePixelRatio,
  });

  /// The twelve months' values, in the category primary's unit.
  final List<int> months;

  /// [ReportWhenChart.fillFor] by step, the empty tile's first.
  final List<Color> fills;

  /// The outline of a month still ahead.
  final Color ahead;

  /// The first month index still ahead — the one after today's in the
  /// current year; [DateTime.monthsPerYear] when none is.
  final int aheadFrom;
  final double devicePixelRatio;

  /// [logical] rounded to the nearest physical pixel.
  double _snap(double logical) =>
      (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = _YearStripGeometry.pitchOf(size.width);
    final gap = math.max(1.0, _snap(ReportMetrics.columnGap));
    final bottom = _snap(size.height);
    var peak = 0;
    for (final value in months) {
      if (value > peak) peak = value;
    }
    final paints = [for (final color in fills) Paint()..color = color];
    final outline = Paint()
      ..color = ahead
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const radius = Radius.circular(ReportMetrics.whenCellRadius);
    for (var month = 0; month < DateTime.monthsPerYear; month++) {
      // A tile runs from its pitch's start to the next one's less a whole
      // gap, so every gap is the same number of pixels.
      final left = _snap(month * pitch);
      final right = _snap((month + 1) * pitch) - gap;
      if (right <= left || bottom <= 0) continue;
      final tile = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, 0, right, bottom),
        radius,
      );
      if (month >= aheadFrom) {
        // Inset by half the stroke, so the outline stays inside the tile.
        canvas.drawRRect(tile.deflate(0.5), outline);
        continue;
      }
      final value = month < months.length ? months[month] : 0;
      canvas.drawRRect(tile, paints[ReportWhenChart.stepFor(value, peak)]);
    }
  }

  @override
  bool shouldRepaint(ReportYearStripPainter oldDelegate) =>
      !listEquals(months, oldDelegate.months) ||
      !listEquals(fills, oldDelegate.fills) ||
      ahead != oldDelegate.ahead ||
      aheadFrom != oldDelegate.aheadFrom ||
      devicePixelRatio != oldDelegate.devicePixelRatio;
}

/// "n more ▾" under a year card's first rows, "Show less ▴" under every
/// row — one id both ways, as Due soon's.
FormActionRow _yearDisclosure(
  AppLocalizations l10n, {
  required Key key,
  required String section,
  required int hidden,
  required bool expanded,
  required VoidCallback onTap,
  required String identifier,
}) => expanded
    ? FormActionRow.disclosure(
        key: key,
        glyph: Icons.expand_less_rounded,
        label: l10n.reportGroupLess,
        onTap: onTap,
        expanded: true,
        semanticsLabel: l10n.reportGroupLessSpoken(section),
        identifier: identifier,
      )
    : FormActionRow.disclosure(
        key: key,
        glyph: Icons.expand_more_rounded,
        label: l10n.reportGroupMore(hidden),
        onTap: onTap,
        expanded: false,
        semanticsLabel: l10n.reportGroupMoreSpoken(hidden, section),
        identifier: identifier,
      );

/// Moves [scroll] back by the rows between [first] — the first row "Show
/// less" folds away — and the disclosure row, dividers included, so the
/// folded disclosure lands under the finger (S).
void _foldBack(
  ScrollController? scroll,
  VoidCallback? onShrink,
  GlobalKey first,
  GlobalKey disclosure,
) => foldBackInPlace(
  scroll,
  onShrink: onShrink,
  extent: () {
    final from = first.currentContext?.findRenderObject();
    final to = disclosure.currentContext?.findRenderObject();
    if (from is! RenderBox || to is! RenderBox) return null;
    return to.localToGlobal(Offset.zero).dy -
        from.localToGlobal(Offset.zero).dy;
  },
);
