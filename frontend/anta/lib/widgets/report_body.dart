import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/alert_constants.dart';
import '../constants/event_digests.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../models/overview_period.dart';
import '../models/report_period_choice.dart';
import '../utils/date_span_label.dart';
import '../utils/report_labels.dart';
import 'agenda_period_nav.dart';
import 'form_rows.dart';
import 'report_group_stack.dart';
import 'report_totals_card.dart';
import 'report_trend_chart.dart';

/// Hands the overview a span and an allowlist to list: a group's Show as
/// list, and the footer's.
typedef ReportShowAsList =
    void Function({
      required DateTime start,
      required DateTime end,
      required Set<String> categoryIds,
    });

/// The Report view's band: the period's title — the Period menu — with its
/// counts, the steps and the Today slot, drawn by the report page and by the
/// guide's screen stage over plain inputs, so the two never drift (D74, the
/// owner's one-copy rule D59).
///
/// A null callback disables its control where it stands, never hides it:
/// the stage draws the range this way.
class ReportBand extends StatefulWidget {
  const ReportBand({
    super.key,
    required this.period,
    this.home,
    this.report,
    this.folding = false,
    required this.today,
    this.years,
    required this.labels,
    this.onTitleTap,
    this.onStep,
    this.onHome,
  });

  /// The period titled — the pick, while a refold runs too; null until the
  /// settings have loaded.
  final OverviewPeriod? period;

  /// The period as picked, which the Today slot returns to and names.
  final OverviewPeriod? home;

  /// The report whose counts the subtitle reads; null before the first.
  final CalendarReport? report;

  /// Whether a refold runs: the subtitle is blank, so the new title never
  /// reads the old counts.
  final bool folding;

  /// Date-only UTC today, which a step and the titles' year are read from.
  final DateTime today;

  /// The years a step may reach; null steps nowhere.
  final AgendaYearBounds? years;

  final ReportLabels labels;

  /// The title's tap, handed the title as the menu's anchor.
  final ValueChanged<BuildContext>? onTitleTap;

  /// A step by the period's own length, handed −1 or 1; offered only in a
  /// direction the period can step to.
  final ValueChanged<int>? onStep;

  /// The Today slot's tap; offered only while the period is not the home.
  final VoidCallback? onHome;

  /// [choice]'s name in the Period menu, which the band measures its title
  /// against too.
  static String choiceLabel(AppLocalizations l10n, ReportPeriodChoice c) {
    return switch (c) {
      ReportPeriodChoice.thisWeek => l10n.overviewPeriodThisWeek,
      ReportPeriodChoice.lastWeek => l10n.reportPeriodLastWeek,
      ReportPeriodChoice.nextWeek => l10n.reportPeriodNextWeek,
      ReportPeriodChoice.thisMonth => l10n.overviewPeriodThisMonth,
      ReportPeriodChoice.lastMonth => l10n.reportPeriodLastMonth,
      ReportPeriodChoice.nextMonth => l10n.reportPeriodNextMonth,
      ReportPeriodChoice.thisYear => l10n.upcomingPeriodWholeYear,
      ReportPeriodChoice.last12Months => l10n.overviewPeriodLast12Months,
      ReportPeriodChoice.last90Days => l10n.overviewPeriodLast90Days,
      ReportPeriodChoice.custom => l10n.upcomingPeriodCustom,
    };
  }

  @override
  State<ReportBand> createState() => _ReportBandState();
}

class _ReportBandState extends State<ReportBand> {
  String? _templatesKey;
  List<String> _templates = const [];

  /// Every title the band may show — the menu's labels, the year, the twelve
  /// month names, and for every month a same-year and a cross-year span with
  /// two-digit days, which a week is titled with too — so a step never moves
  /// the body (the overview's list nav rule). Built once per locale and year.
  List<String> _titleTemplates(AppLocalizations l10n, DateTime today) {
    final year = today.year;
    final key = '${l10n.localeName} $year';
    if (key == _templatesKey) return _templates;
    _templatesKey = key;
    return _templates = List.unmodifiable([
      for (final choice in ReportPeriodChoice.values)
        ReportBand.choiceLabel(l10n, choice),
      '$year',
      for (var m = DateTime.january; m <= DateTime.december; m++) ...[
        OverviewMonthPeriod(year, m).menuValue(l10n),
        dateSpanLabel(
          l10n,
          DateTime.utc(year, m, 10),
          DateTime.utc(year, m, 28),
        ),
        dateSpanLabel(
          l10n,
          DateTime.utc(year - 1, m, 28),
          DateTime.utc(year, m, 28),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = widget.labels;
    final period = widget.period;
    final home = widget.home;
    final report = widget.report;
    final years = widget.years;
    final onStep = widget.onStep;
    final onHome = widget.onHome;
    bool canStep(int direction) =>
        period != null &&
        years != null &&
        period.stepped(
              direction: direction,
              today: widget.today,
              yearBounds: years,
            ) !=
            null;
    return AgendaPeriodNav(
      title: period == null ? '' : labels.periodName(period),
      titleTemplates: _titleTemplates(l10n, widget.today),
      // Never null: a null subtitle drops the count's line, and the band
      // would grow under the finger when the first report lands. Blank
      // while a refold runs, so the new title never reads the old counts —
      // a no-break space, whose line is a word's height at every scale
      // where an empty string's fell a pixel short at 1.3.
      subtitle: report == null || widget.folding
          ? ' '
          : labels.subtitle(report),
      previousTooltip: l10n.overviewPeriodPrevious,
      nextTooltip: l10n.overviewPeriodNext,
      todayTooltip: l10n.overviewPeriodHome(
        home == null ? '' : labels.periodName(home),
      ),
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.reportNavPrevious,
      nextIdentifier: SemanticsIds.reportNavNext,
      todayIdentifier: SemanticsIds.reportNavToday,
      titleIdentifier: SemanticsIds.reportNavTitle,
      onTitleTap: widget.onTitleTap,
      onPrevious: onStep != null && canStep(-1) ? () => onStep(-1) : null,
      onNext: onStep != null && canStep(1) ? () => onStep(1) : null,
      onToday: onHome == null || home == null || period == home ? null : onHome,
    );
  }
}

/// The Report view's body — Totals, Categories, Over time, Missed, Ahead and
/// the footer, ending in the [EndSlackSliver] — drawn by the report page and
/// by the guide's screen stage over plain inputs, so the two never drift
/// (D74, the owner's one-copy rule D59). It writes nothing and owns no data.
///
/// Every callback is what leaves the body; null leaves its control inert —
/// a row with no tap, a footer action disabled at 38 % — while the folds
/// stay live, since they are the body's own. Before the first report it
/// draws the Totals frame with dashes, so a page never opens on a spinner.
class ReportBody extends StatefulWidget {
  const ReportBody({
    super.key,
    required this.report,
    required this.period,
    this.categoryIds = const {},
    required this.today,
    required this.years,
    required this.weekStart,
    required this.labels,
    required this.folds,
    this.scroll,
    this.slack,
    required this.bottomClearance,
    required this.use24Hour,
    this.onDatedTap,
    this.onRoutineTap,
    this.onPresence,
    this.onShowAsList,
    this.onMoreCategories,
    this.onShare,
    this.onSend,
    this.onShrink,
  });

  /// The report drawn; null before the first.
  final CalendarReport? report;

  /// The period [report] was folded for — the caption, the comparison and
  /// the footer read it, never the pick a refold is running for (D36.9);
  /// null with [report].
  final OverviewPeriod? period;

  /// The allowlist [report] was folded over; empty is every category.
  final Set<String> categoryIds;

  /// Date-only UTC today, which the comparison's step and the rows read.
  final DateTime today;

  /// The years a step may reach, for the comparison's previous period.
  final AgendaYearBounds years;

  /// The calendar's first weekday, the trend's columns.
  final CalendarWeekStart weekStart;

  final ReportLabels labels;

  /// Which groups are open and which show every row; kept by the surface,
  /// per visit (X).
  final ReportGroupFolds folds;

  /// The surface's one scroll, which "Show less" moves so "n more" stays
  /// under the finger (S); null gives the body one of its own.
  final ScrollController? scroll;

  /// The arms and releases of the body's [EndSlackSliver], counted by the
  /// surface (D40); null never arms it.
  final ValueListenable<({int arms, int releases})>? slack;

  /// The larger of the keyboard and the system inset, which the body pads
  /// its bottom by.
  final double bottomClearance;

  /// Whether the phone is on the 24-hour clock: a row's start reads as
  /// every other calendar time does.
  final bool use24Hour;

  /// A dated row's tap.
  final void Function(ReportDatedRow row)? onDatedTap;

  /// A routine aggregate's tap.
  final void Function(ReportRoutineRow row)? onRoutineTap;

  /// A Missed row's presence button, handed the status to write; null draws
  /// no button.
  final void Function(ReportDatedRow row, bool missed)? onPresence;

  /// A group's or the footer's Show as list.
  final ReportShowAsList? onShowAsList;

  /// "n more categories", handed the report, the card's [largest] group's
  /// count — the sheet's meters compare with it — and whether the period
  /// crosses a month.
  final void Function(
    CalendarReport report, {
    required int largest,
    required bool spansMonths,
  })?
  onMoreCategories;

  /// Share report, handed the report shown, the period's name and what the
  /// caption compares it against.
  final void Function(
    CalendarReport report, {
    required String periodName,
    required String? against,
  })?
  onShare;

  /// Send me this report, handed the period and allowlist the report was
  /// folded for.
  final void Function(OverviewPeriod period, Set<String> categoryIds)? onSend;

  /// Called before a frame that may shrink the content under the finger —
  /// a header close, "Show less" — so the surface can arm [slack].
  final VoidCallback? onShrink;

  @override
  State<ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<ReportBody> {
  ScrollController? _ownScroll;

  ScrollController get _scroll =>
      widget.scroll ?? (_ownScroll ??= ScrollController());

  @override
  void dispose() {
    _ownScroll?.dispose();
    super.dispose();
  }

  /// Before the first report: the Totals frame with dashes, so the page
  /// never opens on a spinner.
  static const List<ReportTileValue> _placeholderTiles = [
    ReportTileValue(tile: ReportTile.events, value: 0),
    ReportTileValue(tile: ReportTile.hours, value: 0),
  ];

  /// What the caption and the spoken deltas compare [report] against: the
  /// previous period's name, or the span of its days counted (D36.3).
  String? _againstName(
    CalendarReport report,
    OverviewPeriod period,
    ReportLabels labels,
  ) {
    final previous = period.stepped(
      direction: -1,
      today: widget.today,
      yearBounds: widget.years,
    );
    return labels.comparisonName(report, previous: previous);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = widget.labels;
    final report = widget.report;
    final period = widget.period;
    final against = report == null || period == null
        ? null
        : _againstName(report, period, labels);
    final caption = report == null || period == null
        ? null
        : labels.caption(
            report,
            periodName: labels.periodName(period),
            against: against,
          );
    final clearance = widget.bottomClearance;
    final slack = widget.slack;
    return Semantics(
      container: true,
      identifier: SemanticsIds.reportBody,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: FormSectionLabel(text: l10n.reportSectionTotals),
                ),
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: ReportTotalsCard(
                      tiles: report?.tiles ?? _placeholderTiles,
                      labels: labels,
                      against: against,
                      muted: report?.isEmpty ?? false,
                    ),
                  ),
                ),
                if (caption != null)
                  SliverToBoxAdapter(
                    child: FormCaption(
                      text: caption,
                      padding: FormMetrics.groupCaptionPadding,
                    ),
                  ),
                if (report != null)
                  ..._buildCard(
                    ReportCard.categories,
                    l10n.reportSectionCategories,
                    report,
                    labels,
                  ),
                // The builder already left the trend out below the
                // threshold and for a plan (Q, T).
                if (report case CalendarReport(:final trend?, :final span)) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                  SliverToBoxAdapter(
                    child: FormSectionLabel(text: l10n.reportSectionOverTime),
                  ),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: ReportTrendChart(
                        trend: trend,
                        labels: labels,
                        weekStart: widget.weekStart,
                        span: span,
                      ),
                    ),
                  ),
                ],
                // A plan has no Missed and no Ahead (T): the builder leaves
                // both empty, and an empty card is not drawn (H).
                if (report != null) ...[
                  ..._buildCard(
                    ReportCard.missed,
                    l10n.reportSectionMissed,
                    report,
                    labels,
                  ),
                  ..._buildCard(
                    ReportCard.ahead,
                    l10n.reportSectionAhead,
                    report,
                    labels,
                  ),
                ],
                if (period != null && report != null) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _buildFooter(
                        l10n,
                        labels,
                        report,
                        period: period,
                        categoryIds: widget.categoryIds,
                        against: against,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (slack == null)
            EndSlackSliver(arms: 0, clearance: clearance)
          else
            ValueListenableBuilder(
              valueListenable: slack,
              builder: (_, slack, _) => EndSlackSliver(
                arms: slack.arms,
                releases: slack.releases,
                clearance: clearance,
              ),
            ),
        ],
      ),
    );
  }

  /// [card]'s groups under their [label], after the gap between cards;
  /// nothing when the card has no group (H). Categories shows its first
  /// [ReportMetrics.maxCategoryRows] groups and a row for the rest (V). The
  /// groups are a [ReportGroupStack], keyed by card so a card leaving never
  /// hands its fold machinery to the next one.
  List<Widget> _buildCard(
    ReportCard card,
    String label,
    CalendarReport report,
    ReportLabels labels,
  ) {
    final all = switch (card) {
      ReportCard.categories => report.categories,
      ReportCard.missed => report.missed,
      ReportCard.ahead => report.ahead,
    };
    if (all.isEmpty) return const [];
    final capped =
        card == ReportCard.categories &&
        all.length > ReportMetrics.maxCategoryRows;
    final groups = capped ? all.sublist(0, ReportMetrics.maxCategoryRows) : all;
    final span = report.span;
    final spansMonths =
        span.start.year != span.end.year || span.start.month != span.end.month;
    // Ahead's rows are the days after the counted end, so its list starts
    // there; Categories and Missed list the folded span.
    final counted = report.countedTo;
    final listStart = card == ReportCard.ahead
        ? DateTime.utc(counted.year, counted.month, counted.day + 1)
        : span.start;
    final onShowAsList = widget.onShowAsList;
    return [
      const SliverToBoxAdapter(child: SizedBox(height: RowMetrics.groupGap)),
      SliverToBoxAdapter(child: FormSectionLabel(text: label)),
      ReportGroupStack(
        key: ValueKey(card),
        scroll: _scroll,
        folds: widget.folds,
        card: card,
        groups: groups,
        events: report.events,
        labels: labels,
        onDatedTap: widget.onDatedTap,
        onRoutineTap: widget.onRoutineTap,
        onPresence: card == ReportCard.missed ? widget.onPresence : null,
        onShowAsList: onShowAsList == null
            ? null
            : (group) => onShowAsList(
                start: listStart,
                end: span.end,
                categoryIds: {group.categoryId},
              ),
        today: widget.today,
        spansMonths: spansMonths,
        use24Hour: widget.use24Hour,
        // The page's gap follows the card; the cap's row is a card of its
        // own and keeps the air above it.
        trailingGap: capped,
        onShrink: widget.onShrink,
      ),
      if (capped)
        SliverToBoxAdapter(
          child: _moreCategories(
            labels,
            report,
            groups: groups,
            spansMonths: spansMonths,
          ),
        ),
    ];
  }

  /// "n more categories ›" under the Categories card's last group (V): the
  /// rest of [report]'s categories, past the [groups] the card shows.
  Widget _moreCategories(
    ReportLabels labels,
    CalendarReport report, {
    required List<ReportCategoryGroup> groups,
    required bool spansMonths,
  }) {
    final onMoreCategories = widget.onMoreCategories;
    return FormRowShell(
      first: true,
      last: true,
      trailingGap: false,
      child: FormActionRow.disclosure(
        glyph: Icons.chevron_right_rounded,
        label: labels.l10n.reportMoreCategories(
          report.categories.length - groups.length,
        ),
        identifier: SemanticsIds.reportCategoriesMore,
        onTap: onMoreCategories == null
            ? null
            : () => onMoreCategories(
                report,
                largest: groups.first.count,
                spansMonths: spansMonths,
              ),
      ),
    );
  }

  /// The footer of [report], folded over [period] and [categoryIds]: Show
  /// as list hands the overview the span the service folded — clamped past
  /// 366 days (D33) — not the period's own; Share writes the report shown,
  /// with [against] as the caption names it.
  Widget _buildFooter(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport report, {
    required OverviewPeriod period,
    required Set<String> categoryIds,
    required String? against,
  }) {
    final onShowAsList = widget.onShowAsList;
    final onShare = widget.onShare;
    final onSend = widget.onSend;
    return FormRowGroup(
      trailingGap: false,
      children: [
        FormActionRow(
          glyph: Icons.view_list_rounded,
          label: l10n.reportShowAsList,
          identifier: SemanticsIds.reportShowList,
          onTap: onShowAsList == null
              ? null
              : () => onShowAsList(
                  start: report.span.start,
                  end: report.span.end,
                  categoryIds: categoryIds,
                ),
        ),
        // An empty period has nothing to share: disabled at 38 %, never
        // hidden.
        FormActionRow(
          glyph: Icons.share_rounded,
          label: l10n.reportShare,
          identifier: SemanticsIds.reportShare,
          onTap: report.isEmpty || onShare == null
              ? null
              : () => onShare(
                  report,
                  periodName: labels.periodName(period),
                  against: against,
                ),
        ),
        // At the digest cap there is nothing to send to: disabled, as the
        // hub hides its Add row there, rather than a sheet that refuses.
        FormActionRow(
          glyph: Icons.notifications_rounded,
          label: period is OverviewWeekPeriod
              ? l10n.reportSendWeekly
              : l10n.reportSendMonthly,
          identifier: SemanticsIds.reportSend,
          onTap:
              onSend == null ||
                  EventDigests.all.length >= kDigestHorizon.maxDigests
              ? null
              : () => onSend(period, categoryIds),
        ),
      ],
    );
  }
}
