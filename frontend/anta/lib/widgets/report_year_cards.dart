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
/// A row reserves the caption lines its kind's template wraps to at the
/// caption's width (S4 D) — the widest month, the value in 8s at the
/// record's digit count — so a week across two months is never cut. A
/// trip, a streak and a gap are named by a title or a category no template
/// can know: theirs is measured with the row's own subject, at most
/// [ReportMetrics.yearRecordCaptionLinesCompact] lines with an ellipsis
/// beyond, and a refold that swaps such a record may change its row's
/// height, as S5's digit-count rule may.
class ReportRecordsCard extends StatefulWidget {
  const ReportRecordsCard({
    super.key,
    required this.report,
    required this.labels,
    required this.folds,
    this.onShrink,
    this.scroll,
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

  static int _measurements = 0;

  /// How many captions the cards have laid out to count their lines — the
  /// misses of the card's memo — so a test can pin that an unchanged
  /// rebuild lays out none.
  @visibleForTesting
  static int get measurementCount => _measurements;

  @override
  State<ReportRecordsCard> createState() => _ReportRecordsCardState();
}

class _ReportRecordsCardState extends State<ReportRecordsCard> {
  final GlobalKey _firstFolded = GlobalKey();
  final GlobalKey _disclosureKey = GlobalKey();

  /// What [_widest] and [_lines] were measured in; a change of any of these
  /// measures every row again — the money month's template carries the
  /// currency symbol.
  ({
    double width,
    TextScaler scaler,
    String locale,
    String currencySymbol,
    bool currencySuffix,
    TextStyle style,
    TextDirection direction,
  })?
  _measuredIn;

  /// The widest of a list of names, by the names joined.
  final Map<String, String> _widest = {};

  /// Each measured row's caption lines, kept for the last build's records
  /// only, so the memo never outgrows the card.
  Map<({ReportRecordKind kind, int digits, String? subject}), int> _lines =
      const {};

  @override
  Widget build(BuildContext context) {
    final records = widget.report.year?.records ?? const <ReportRecord>[];
    if (records.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    const cap = ReportMetrics.yearRecordRows;
    final capped = records.length > cap;
    final expanded = capped && widget.folds.isRecordsExpanded;
    final shown = capped && !expanded ? records.take(cap) : records;
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = _captionLinesFor(
          context,
          constraints.maxWidth,
          records,
          shown.length,
        );
        return FormRowGroup(
          trailingGap: false,
          children: [
            for (final (index, record) in shown.indexed)
              _row(
                scheme,
                record,
                lines[_lineKeyOf(record)] ?? 1,
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
      },
    );
  }

  /// The caption lines of the first [shown] of [records] at [cardWidth]:
  /// its kind's template, joined to the row's own subject where a title or
  /// a category names the record, measured as the caption draws it.
  Map<({ReportRecordKind kind, int digits, String? subject}), int>
  _captionLinesFor(
    BuildContext context,
    double cardWidth,
    List<ReportRecord> records,
    int shown,
  ) {
    final labels = widget.labels;
    final style = reportCaptionStyleOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final measuredIn = (
      width: cardWidth - _textColumnStart(scaler) - FormMetrics.rowEndPadding,
      scaler: scaler,
      locale: labels.l10n.localeName,
      currencySymbol: labels.currencySymbol,
      currencySuffix: labels.currencySuffix,
      style: style,
      direction: direction,
    );
    if (measuredIn != _measuredIn) {
      _measuredIn = measuredIn;
      _widest.clear();
      _lines = const {};
    }
    final previous = _lines;
    final lines =
        <({ReportRecordKind kind, int digits, String? subject}), int>{};
    // A folded row keeps its count, so folding and unfolding measures
    // nothing twice; only a shown row is measured.
    for (final (index, record) in records.indexed) {
      final key = _lineKeyOf(record);
      if (lines.containsKey(key)) continue;
      final kept = previous[key];
      if (kept == null && index >= shown) continue;
      lines[key] =
          kept ??
          _measure(
            record,
            key.subject,
            width: measuredIn.width,
            style: style,
            scaler: scaler,
            direction: direction,
          );
    }
    return _lines = lines;
  }

  int _measure(
    ReportRecord record,
    String? subject, {
    required double width,
    required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
  }) {
    ReportRecordsCard._measurements++;
    final labels = widget.labels;
    final templates = labels.recordTemplates(
      record.kind,
      widest: (names) => _widest.putIfAbsent(
        names.join('\n'),
        () => ReportTagCaptions.widestOf(names, style, scaler, direction),
      ),
      value: record.value,
    );
    final lines = reportCaptionLines(
      [
        for (final template in templates)
          subject == null
              ? template
              : labels.l10n.reportRecordCaption(subject, template),
      ],
      style: style,
      scaler: scaler,
      direction: direction,
      width: width,
    );
    return subject == null
        ? lines
        : math.min(lines, ReportMetrics.yearRecordCaptionLinesCompact);
  }

  /// A row's memo key: its kind, its value's digit count in the kind's unit
  /// (the template's 8s) and, for a record named by a title or a category,
  /// that subject.
  ({ReportRecordKind kind, int digits, String? subject}) _lineKeyOf(
    ReportRecord record,
  ) {
    final figure = record.kind == ReportRecordKind.moneyMonth
        ? (record.value / 100).round().abs()
        : record.value.abs();
    return (
      kind: record.kind,
      digits: '$figure'.length,
      subject: _subjectOf(record),
    );
  }

  /// The title or the category a trip, a streak or a gap is named by, as
  /// the labels' caption names it; null for a kind its template names.
  String? _subjectOf(ReportRecord record) {
    final l10n = widget.labels.l10n;
    switch (record.kind) {
      case ReportRecordKind.longestTrip || ReportRecordKind.longestStreak:
        final id = record.eventId ?? '';
        return widget.report.events[id]?.title ?? id;
      case ReportRecordKind.longestGap:
        return CalendarCategories.labelOf(
          CalendarCategories.resolve(record.categoryId ?? ''),
          l10n,
        );
      case ReportRecordKind.busiestMonth ||
          ReportRecordKind.busiestWeek ||
          ReportRecordKind.socialMonth ||
          ReportRecordKind.moneyMonth:
        return null;
    }
  }

  Widget _row(
    ColorScheme scheme,
    ReportRecord record,
    int captionLines, {
    Key? key,
  }) {
    final labels = widget.labels;
    final words = labels.recordWords(record, widget.report);
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
        _capital,
        (match) => '-${match[0]!.toLowerCase()}',
      ),
    ),
  };

  static final RegExp _capital = RegExp('[A-Z]');

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
    this.canTap,
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

  /// Whether a strip answers [onCategoryTap]: false for a category with no
  /// group to open, which then reads as a read row — no tap and no button
  /// in its semantics, as the Goals card's. Null taps every strip.
  final bool Function(String categoryId)? canTap;

  static int _axisMeasurements = 0;

  /// How many times the axis has laid its month names out — the misses of
  /// its memo — so a test can pin that an unchanged rebuild lays out none.
  @visibleForTesting
  static int get axisMeasurementCount => _axisMeasurements;

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
    final aheadFrom = (report.aheadFromMonth ?? DateTime.monthsPerYear + 1) - 1;
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
    final onCategoryTap = widget.canTap?.call(categoryId) ?? true
        ? widget.onCategoryTap
        : null;
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
        // The list stops at today's month in the current year: the months
        // after it have not happened.
        aheadFrom: report.aheadFromMonth,
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
/// on its tile at the strips' x. Every step-th name, at the smallest of
/// [ReportMetrics.yearAxisSteps] whose names keep
/// [ReportMetrics.axisLabelMinGap]: the short names at a step, else the
/// narrow ones at it — the Over time axis's rule at each step. Measured as
/// the caption draws, bold included. Decoration: the strips' spoken lists
/// are its twin.
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
            builder: (context, constraints) => _MonthAxisNames(
              width: constraints.maxWidth,
              locale: locale,
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
}

/// The axis's names at [width], measured once per width, scale, locale,
/// style and direction and kept in the state, so a rebuild of the card — a
/// fold, a tap — lays no name out again.
class _MonthAxisNames extends StatefulWidget {
  const _MonthAxisNames({
    required this.width,
    required this.locale,
    required this.measured,
    required this.drawn,
    required this.scaler,
    required this.line,
  });

  final double width;
  final String locale;
  final TextStyle measured;
  final TextStyle drawn;
  final TextScaler scaler;
  final double line;

  @override
  State<_MonthAxisNames> createState() => _MonthAxisNamesState();
}

class _MonthAxisNamesState extends State<_MonthAxisNames> {
  ({
    double width,
    TextScaler scaler,
    String locale,
    TextStyle style,
    TextDirection direction,
  })?
  _key;

  /// The names drawn, every step-th month's, with each one's width.
  List<({int month, String name, double width})> _shown = const [];

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    if (width <= 0) return const SizedBox.shrink();
    final key = (
      width: width,
      scaler: widget.scaler,
      locale: widget.locale,
      style: widget.measured,
      direction: Directionality.of(context),
    );
    if (key != _key) {
      _key = key;
      _shown = _layOut(key.direction);
    }
    final pitch = _YearStripGeometry.pitchOf(width);
    final tile = pitch - ReportMetrics.columnGap;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final shown in _shown)
          _name(
            shown.name,
            textWidth: math.min(shown.width, width),
            centre: shown.month * pitch + tile / 2,
            width: width,
            line: widget.line,
            style: widget.drawn,
          ),
      ],
    );
  }

  /// The short names at each of [ReportMetrics.yearAxisSteps] before the
  /// narrow ones — so a wide phone at 2.0 keeps German's "Jan Mär Mai",
  /// whose short names fit every other tile — the first that keeps the
  /// gap, else the narrow names at the last step.
  List<({int month, String name, double width})> _layOut(
    TextDirection direction,
  ) {
    ReportMonthsCard._axisMeasurements++;
    final widths = <String, double>{};
    double measure(String text) => widths.putIfAbsent(text, () {
      final painter = TextPainter(
        text: TextSpan(text: text, style: widget.measured),
        textScaler: widget.scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final measuredWidth = painter.width;
      painter.dispose();
      return measuredWidth;
    });

    final pitch = _YearStripGeometry.pitchOf(widget.width);
    final formats = _AxisFormats.of(widget.locale);
    final shortWidest = formats.short.map(measure).reduce(math.max);
    final narrowWidest = formats.narrow.map(measure).reduce(math.max);
    bool fits(double widest, int step) =>
        step * pitch >= widest + ReportMetrics.axisLabelMinGap;
    var names = formats.narrow;
    var step = ReportMetrics.yearAxisSteps.last;
    for (final candidate in ReportMetrics.yearAxisSteps) {
      if (fits(shortWidest, candidate)) {
        (names, step) = (formats.short, candidate);
        break;
      }
      if (fits(narrowWidest, candidate)) {
        (names, step) = (formats.narrow, candidate);
        break;
      }
    }
    return [
      for (var month = 0; month < names.length; month += step)
        (month: month, name: names[month], width: measure(names[month])),
    ];
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
