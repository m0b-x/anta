/// The report's analytics cards (S4, `docs/calendar-analytics-specs/
/// s4-design-spec.md` §2.2–2.4): Goals, Insights and Due soon, the three
/// cards a profiled selection puts above Totals. One file for the three (V):
/// they share the row primitive's fields, the template rule and the page's
/// slot shape. Each card draws no section label of its own — the page sets
/// `FormSectionLabel` above it — and is absent when it has nothing to show.
library;

import 'package:flutter/material.dart';

import '../constants/analytics_metrics.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/category_kinds.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../models/date_range.dart';
import '../utils/report_labels.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'report_group_stack.dart';

/// The Goals card (§2.2): one [FormMeterRow] per [CalendarReport.goals], in
/// the model's order — the category's avatar and name, the state glyph at
/// the label line's end, the read-back caption and a meter in the
/// category's colour.
///
/// A row's caption lines are decided by templates (D): every state sentence
/// its goal can show, figures written in eights, laid out at the caption's
/// width, scale and locale. The row keeps that many lines whatever the
/// value, so a refold never moves the card under the finger.
class ReportGoalsCard extends StatefulWidget {
  const ReportGoalsCard({
    super.key,
    required this.report,
    required this.labels,
    this.onGoalTap,
    this.canTap,
  });

  /// The report whose [CalendarReport.goals] the card draws; its tense,
  /// span and today decide which period each row reads.
  final CalendarReport report;

  /// The page's words, built once per build, so the card's captions and
  /// templates use the same formatters as the band and the Totals tiles.
  final ReportLabels labels;

  /// A row's tap (G): the page scrolls to the goal's category group and
  /// opens it. Null draws read rows.
  final ValueChanged<ReportGoal>? onGoalTap;

  /// Whether a goal's row answers [onGoalTap]: false for a goal whose
  /// category has no group to open (G), which then reads as a read row —
  /// no tap and no button in its semantics. Null taps every row.
  final bool Function(ReportGoal goal)? canTap;

  @override
  State<ReportGoalsCard> createState() => _ReportGoalsCardState();
}

/// A goal's state as its glyph shows it (§2.2's glyph table): the shape
/// and the spoken word carry the state, the colour only follows it, and
/// nothing is `error` red (K — pace, not scolding).
enum _GoalGlyph {
  met(Icons.check_circle_rounded),
  pace(Icons.timelapse_rounded),
  behind(Icons.hourglass_bottom_rounded),
  alarm(Icons.error_outline_rounded),
  idle(Icons.radio_button_unchecked_rounded);

  const _GoalGlyph(this.icon);

  final IconData icon;

  Color colorIn(ColorScheme scheme) => switch (this) {
    _GoalGlyph.met => scheme.primary,
    _GoalGlyph.alarm => scheme.onSurface,
    _GoalGlyph.pace ||
    _GoalGlyph.behind ||
    _GoalGlyph.idle => scheme.onSurfaceVariant,
  };
}

class _ReportGoalsCardState extends State<ReportGoalsCard> {
  /// What [_lines] was measured at; a change of width, scale, locale,
  /// currency, style or day measures every row again — a budget's templates
  /// carry the symbol, so a currency changed in settings can rewrap them,
  /// and which periods have closed decides a goal's template set.
  ({
    double width,
    TextScaler scaler,
    String locale,
    String currencySymbol,
    bool currencySuffix,
    TextStyle style,
    TextDirection direction,
    DateRange span,
    ReportTense tense,
    DateTime today,
  })?
  _linesKey;

  /// Each shown goal's caption lines, kept for the goals of the last build
  /// only, so the cache never outgrows the card.
  Map<ReportGoal, int> _lines = const {};

  CalendarReport get report => widget.report;
  ReportLabels get labels => widget.labels;

  /// The caption's role, as [FormMeterRow] draws it; measured merged over
  /// the ambient style, which a bare style would measure in the box font.
  static const TextStyle _captionStyle = TextStyle(
    fontSize: FormMetrics.captionSize,
    height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
  );

  @override
  Widget build(BuildContext context) {
    final goals = report.goals;
    if (goals.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = _captionLinesFor(context, constraints.maxWidth);
        return FormRowGroup(
          trailingGap: false,
          children: [
            for (final goal in goals) _row(context, goal, lines[goal] ?? 1),
          ],
        );
      },
    );
  }

  /// Every goal's caption lines at [cardWidth]: the most any of its
  /// templates wraps to at the caption's width.
  Map<ReportGoal, int> _captionLinesFor(
    BuildContext context,
    double cardWidth,
  ) {
    final style = DefaultTextStyle.of(context).style.merge(_captionStyle);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // The caption runs from the text column's start to the row's end; the
    // leading box narrows at a large scale, as the row's own rule says.
    final leading = FormMeterRow.isCompact(scaler)
        ? RowMetrics.glyphSize
        : FormMetrics.rowLeadingSize;
    final width =
        cardWidth -
        RowMetrics.groupInset -
        leading -
        FormMetrics.gap -
        FormMetrics.rowEndPadding;
    final key = (
      width: width,
      scaler: scaler,
      locale: labels.l10n.localeName,
      currencySymbol: labels.currencySymbol,
      currencySuffix: labels.currencySuffix,
      style: style,
      direction: direction,
      span: report.span,
      tense: report.tense,
      today: report.today,
    );
    final previous = key == _linesKey ? _lines : const <ReportGoal, int>{};
    _linesKey = key;
    return _lines = {
      for (final goal in report.goals)
        goal:
            previous[goal] ??
            _measureLines(goal, style, scaler, direction, width),
    };
  }

  int _measureLines(
    ReportGoal goal,
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    double width,
  ) {
    var most = 1;
    for (final template in labels.goalTemplates(goal, report)) {
      final painter = TextPainter(
        text: TextSpan(text: template, style: style),
        textScaler: scaler,
        textDirection: direction,
      )..layout(maxWidth: width);
      final count = painter.computeLineMetrics().length;
      painter.dispose();
      if (count > most) most = count;
    }
    return most;
  }

  Widget _row(BuildContext context, ReportGoal goal, int captionLines) {
    final scheme = Theme.of(context).colorScheme;
    final category = CalendarCategories.resolve(goal.categoryId);
    final name = CalendarCategories.labelOf(category, labels.l10n);
    final icon = CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
    final glyph = _glyphOf(goal);
    final onGoalTap = widget.canTap?.call(goal) ?? true
        ? widget.onGoalTap
        : null;
    return FormMeterRow(
      leading: EventAvatar(icon: icon, color: category.color),
      compactLeading: FormGlyph(icon: icon, color: category.color),
      label: name,
      labelTrailing: FormTrailingGlyph(
        icon: glyph.icon,
        color: glyph.colorIn(scheme),
      ),
      caption: labels.goalCaption(goal, report),
      captionLines: captionLines,
      fraction: _fractionOf(goal),
      // The category's colour in every state (C): the glyph says the state.
      meterColor: category.color,
      onTap: onGoalTap == null ? null : () => onGoalTap(goal),
      semanticsLabel: labels.goalSpoken(name, goal, report),
      identifier: SemanticsIds.reportGoal(goal.categoryId),
    );
  }

  /// The closed periods a past span of several counts met (F), or null
  /// where the caption reads one period — the labels' own condition, so the
  /// glyph and the meter count what "3 of 4 weeks met" counts.
  List<ReportGoalPeriod>? _periodsMetReading(ReportGoal goal) {
    if (report.tense != ReportTense.past || goal.periods.length < 2) {
      return null;
    }
    final closed = ReportLabels.closedPeriods(goal, report);
    return closed.isEmpty ? null : closed;
  }

  /// The glyph of the state the caption reads: the period
  /// [ReportLabels.goalPeriod] picks — an open one in a past span reads its
  /// pace — or, for a past span of several, its closed periods: all met is
  /// met, some is pace (a partial result is not a failure, C), none is the
  /// alarm.
  _GoalGlyph _glyphOf(ReportGoal goal) {
    if (goal.target.kind == TargetKind.maxGap) {
      return switch (goal.gap?.state) {
        null => _GoalGlyph.idle,
        GapState.within => _GoalGlyph.pace,
        GapState.due => _GoalGlyph.behind,
        GapState.overdue => _GoalGlyph.alarm,
      };
    }
    if (_periodsMetReading(goal) case final closed?) {
      final met = closed.where((p) => p.state == GoalState.met).length;
      if (met == closed.length) return _GoalGlyph.met;
      return met > 0 ? _GoalGlyph.pace : _GoalGlyph.alarm;
    }
    final period = ReportLabels.goalPeriod(goal, report);
    if (period == null) return _GoalGlyph.idle;
    return switch (period.state) {
      GoalState.met => _GoalGlyph.met,
      GoalState.onPace => _GoalGlyph.pace,
      GoalState.behind => _GoalGlyph.behind,
      GoalState.over || GoalState.missed => _GoalGlyph.alarm,
      GoalState.notDue || GoalState.future => _GoalGlyph.idle,
    };
  }

  /// The meter's share, from the period the caption reads: its value of
  /// the target; a gap's days of its limit; a past span of several periods,
  /// the closed periods met of those closed, as the caption's "3 of 4 weeks
  /// met" counts them — a period still open is not yet a result.
  double _fractionOf(ReportGoal goal) {
    double share(int part, int whole) =>
        whole <= 0 ? 0 : (part / whole).clamp(0.0, 1.0);
    if (goal.target.kind == TargetKind.maxGap) {
      final gap = goal.gap;
      return gap == null ? 0 : share(gap.daysSince, gap.limit);
    }
    if (_periodsMetReading(goal) case final closed?) {
      final met = closed.where((p) => p.state == GoalState.met).length;
      return share(met, closed.length);
    }
    final period = ReportLabels.goalPeriod(goal, report);
    return period == null ? 0 : share(period.value, goal.target.value);
  }
}

/// The Insights card (§2.3): one [FormPickerRow] per insight, in rank
/// order — the severity glyph in the leading box, the subject as the label
/// and the finding's detail as a caption of up to
/// [ReportMetrics.insightCaptionMaxLines] lines (I).
///
/// A row's height follows its sentence, so the page anchors this card on a
/// refold (R) rather than the card reserving lines.
class ReportInsightsCard extends StatelessWidget {
  const ReportInsightsCard({
    super.key,
    required this.insights,
    required this.report,
    required this.labels,
    required this.weekStart,
    this.onInsightTap,
    this.canTap,
  });

  /// The insights the page keeps, ranked: [CalendarReport.insights] less
  /// those the Goals or Due soon card already shows (H). The card draws the
  /// first [AnalyticsMetrics.insightsOnPage].
  final List<ReportInsight> insights;

  /// The report the insights fired on; its goals, tags and events word the
  /// sentences.
  final CalendarReport report;

  /// The page's words, built once per build.
  final ReportLabels labels;

  /// The app's week start, which places a weekday insight's days: the
  /// report counts from it but does not carry it.
  final CalendarWeekStart weekStart;

  /// A row's tap: the page takes it to the insight's [ReportInsight.target].
  /// Null draws read rows.
  final ValueChanged<ReportInsight>? onInsightTap;

  /// Whether an insight's row answers [onInsightTap]: false where its
  /// target cannot be reached — no group, no day — which leaves the row with
  /// no tap. Null taps every row.
  final bool Function(ReportInsight insight)? canTap;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final shown = insights.take(AnalyticsMetrics.insightsOnPage);
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final (rank, insight) in shown.indexed)
          _row(scheme, rank, insight),
      ],
    );
  }

  Widget _row(ColorScheme scheme, int rank, ReportInsight insight) {
    final categoryId = insight.categoryId;
    // With no one category the labels' own nouns stand in.
    final category = categoryId == null
        ? ''
        : CalendarCategories.labelOf(
            CalendarCategories.resolve(categoryId),
            labels.l10n,
          );
    final onInsightTap = canTap?.call(insight) ?? true
        ? this.onInsightTap
        : null;
    return FormPickerRow(
      leading: _LeadingGlyph(
        icon: _severityIcon(insight.severity),
        // The shape carries the severity (J); only "act now" is louder.
        color: insight.severity >= 3
            ? scheme.onSurface
            : scheme.onSurfaceVariant,
      ),
      label: labels.insightSubject(insight, report, category: category),
      caption: labels.insightDetail(
        insight,
        report,
        category: category,
        weekStart: weekStart,
      ),
      captionMaxLines: ReportMetrics.insightCaptionMaxLines,
      singleLine: true,
      showChevron: false,
      onTap: onInsightTap == null ? null : () => onInsightTap(insight),
      semanticsLabel: labels.insightSpoken(
        insight,
        report,
        category: category,
        weekStart: weekStart,
      ),
      identifier: SemanticsIds.reportInsight(rank),
    );
  }

  /// The severity's glyph (J), as [ReportLabels.insightSeverityWord] words
  /// it: 3 act now, 2 worth a look, 1 worth knowing, 0 a fact.
  static IconData _severityIcon(int severity) => switch (severity) {
    >= 3 => Icons.error_outline_rounded,
    2 => Icons.flag_outlined,
    1 => Icons.lightbulb_outline_rounded,
    _ => Icons.info_outline_rounded,
  };
}

/// The Due soon card (§2.4): one [FormPickerRow] per [CalendarReport.dueSoon]
/// row, in the model's order — the state glyph in the leading box, the
/// event's title and a one-line phrase (K). Past
/// [AnalyticsMetrics.dueSoonRows] a disclosure row expands the card in
/// place (L) and folds it back.
///
/// Stateful the way [ReportGroupStack] is: the expansion lives in the
/// surface's [ReportGroupFolds], read and written here, so it survives the
/// card's rebuilds for the visit.
class ReportDueSoonCard extends StatefulWidget {
  const ReportDueSoonCard({
    super.key,
    required this.report,
    required this.labels,
    required this.folds,
    this.onDueTap,
    this.onShrink,
    this.scroll,
  });

  /// The report whose [CalendarReport.dueSoon] rows the card draws.
  final CalendarReport report;

  /// The page's words, built once per build.
  final ReportLabels labels;

  /// The surface's fold state; the card's expansion is kept there.
  final ReportGroupFolds folds;

  /// A row's tap (M): the page opens the event on the row's day. Null draws
  /// read rows.
  final ValueChanged<ReportDueRow>? onDueTap;

  /// Called before "Show less" folds the card, as [ReportGroupStack] calls
  /// its own: the surface arms its [EndSlackSliver] there, for a card
  /// folded at the scroll's end.
  final VoidCallback? onShrink;

  /// The surface's one scroll, which "Show less" moves back by the rows
  /// that leave so "n more" stays under the finger, as a group's does (S);
  /// null moves nothing.
  final ScrollController? scroll;

  @override
  State<ReportDueSoonCard> createState() => _ReportDueSoonCardState();
}

class _ReportDueSoonCardState extends State<ReportDueSoonCard> {
  /// The first row "Show less" folds away and the disclosure row: the
  /// extent between their tops is what leaves, dividers included, and the
  /// folded disclosure takes the first one's place.
  final GlobalKey _firstFolded = GlobalKey();
  final GlobalKey _disclosureKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final rows = widget.report.dueSoon;
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final capped = rows.length > AnalyticsMetrics.dueSoonRows;
    final expanded = capped && widget.folds.isDueSoonExpanded;
    final shown = capped && !expanded
        ? rows.take(AnalyticsMetrics.dueSoonRows)
        : rows;
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final (index, row) in shown.indexed)
          _row(
            scheme,
            row,
            key: expanded && index == AnalyticsMetrics.dueSoonRows
                ? _firstFolded
                : null,
          ),
        if (capped) _disclosure(rows.length, expanded),
      ],
    );
  }

  Widget _row(ColorScheme scheme, ReportDueRow row, {Key? key}) {
    final report = widget.report;
    final labels = widget.labels;
    final title = report.events[row.eventId]?.title ?? row.eventId;
    final onDueTap = widget.onDueTap;
    return FormPickerRow(
      key: key,
      leading: _LeadingGlyph(
        icon: _stateIcon(row.state),
        // The shape carries the state; what is past its day is louder.
        color: switch (row.state) {
          ReportDueState.overdue || ReportDueState.unmarked => scheme.onSurface,
          ReportDueState.due ||
          ReportDueState.upcoming => scheme.onSurfaceVariant,
        },
      ),
      label: title,
      caption: labels.dueCaption(row, report),
      captionMaxLines: 1,
      singleLine: true,
      showChevron: false,
      onTap: onDueTap == null ? null : () => onDueTap(row),
      semanticsLabel: labels.dueSpoken(title, row, report),
      identifier: SemanticsIds.reportDue(row.eventId, row.day),
    );
  }

  static IconData _stateIcon(ReportDueState state) => switch (state) {
    ReportDueState.overdue => Icons.error_outline_rounded,
    ReportDueState.due => Icons.hourglass_bottom_rounded,
    ReportDueState.unmarked => Icons.radio_button_unchecked_rounded,
    ReportDueState.upcoming => Icons.schedule_rounded,
  };

  /// "n more ▾" under the first rows, "Show less ▴" under every row — one
  /// id both ways.
  Widget _disclosure(int length, bool expanded) {
    final l10n = widget.labels.l10n;
    final section = l10n.reportSectionDueSoon;
    if (expanded) {
      return FormActionRow.disclosure(
        key: _disclosureKey,
        glyph: Icons.expand_less_rounded,
        label: l10n.reportGroupLess,
        onTap: _toggle,
        expanded: true,
        semanticsLabel: l10n.reportGroupLessSpoken(section),
        identifier: SemanticsIds.reportDueMore,
      );
    }
    final more = length - AnalyticsMetrics.dueSoonRows;
    return FormActionRow.disclosure(
      key: _disclosureKey,
      glyph: Icons.expand_more_rounded,
      label: l10n.reportGroupMore(more),
      onTap: _toggle,
      expanded: false,
      semanticsLabel: l10n.reportGroupMoreSpoken(more, section),
      identifier: SemanticsIds.reportDueMore,
    );
  }

  void _toggle() {
    final folds = widget.folds;
    final expanded = folds.isDueSoonExpanded;
    // Expanding grows the card below the finger and moves nothing above it.
    if (expanded) {
      foldBackInPlace(
        widget.scroll,
        onShrink: widget.onShrink,
        extent: () {
          final first = _firstFolded.currentContext?.findRenderObject();
          final disclosure = _disclosureKey.currentContext?.findRenderObject();
          if (first is! RenderBox || disclosure is! RenderBox) return null;
          return disclosure.localToGlobal(Offset.zero).dy -
              first.localToGlobal(Offset.zero).dy;
        },
      );
    }
    setState(() => folds.setDueSoonExpanded(!expanded));
  }
}

/// A row's glyph centred in the [FormMetrics.rowLeadingSize] box, so the
/// text starts where every report row's does (I).
class _LeadingGlyph extends StatelessWidget {
  const _LeadingGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: FormMetrics.rowLeadingSize,
    child: Center(
      child: FormGlyph(icon: icon, color: color),
    ),
  );
}
