import 'package:flutter/foundation.dart'
    show ValueListenable, precisionErrorTolerance, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show PipelineOwner, RenderSliverToBoxAdapter, SliverGeometry;

import '../constants/alert_constants.dart';
import '../constants/analytics_metrics.dart';
import '../constants/event_digests.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_report.dart';
import '../models/overview_period.dart';
import '../models/overview_view.dart';
import '../models/report_period_choice.dart';
import '../utils/date_span_label.dart';
import '../utils/report_insight_filter.dart';
import '../utils/report_labels.dart';
import 'agenda_period_nav.dart';
import 'form_rows.dart';
import 'report_analytics_cards.dart';
import 'report_group_stack.dart';
import 'report_totals_card.dart';
import 'report_trend_chart.dart';
import 'report_when_chart.dart';
import 'report_year_cards.dart';

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
    this.navIdentifier,
  });

  /// The nav's ids, handed `previous`, `next`, `today` or `title`; null
  /// keeps the report page's own (`report-nav-*`). The guide's stage gives
  /// its own, so a flow never finds the page's ids on the guide (D86).
  final String Function(String control)? navIdentifier;

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
      ReportPeriodChoice.lastYear => l10n.reportPeriodLastYear,
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
    final settled = report != null && !widget.folding;
    // The goals form only where it fits at the 1.0 size (Q); the nav owns
    // the box, so it decides between the two forms handed to it.
    final goalsForm =
        settled &&
        report.goals.isNotEmpty &&
        report.tense != ReportTense.future;
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
      compactSubtitle: goalsForm ? labels.subtitle(report, goals: false) : null,
      subtitleTemplate: goalsForm
          ? labels.subtitleTemplate(
              report.goals.length,
              past: report.tense == ReportTense.past,
            )
          : null,
      previousTooltip: l10n.overviewPeriodPrevious,
      nextTooltip: l10n.overviewPeriodNext,
      todayTooltip: l10n.overviewPeriodHome(
        home == null ? '' : labels.periodName(home),
      ),
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier:
          widget.navIdentifier?.call('previous') ??
          SemanticsIds.reportNavPrevious,
      nextIdentifier:
          widget.navIdentifier?.call('next') ?? SemanticsIds.reportNavNext,
      todayIdentifier:
          widget.navIdentifier?.call('today') ?? SemanticsIds.reportNavToday,
      titleIdentifier:
          widget.navIdentifier?.call('title') ?? SemanticsIds.reportNavTitle,
      onTitleTap: widget.onTitleTap,
      onPrevious: onStep != null && canStep(-1) ? () => onStep(-1) : null,
      onNext: onStep != null && canStep(1) ? () => onStep(1) : null,
      onToday: onHome == null || home == null || period == home ? null : onHome,
    );
  }
}

/// The Report view's body — Goals, Insights, Due soon, Totals, on a whole
/// year Records and Months, Categories, By tag, Over time, When, Balance,
/// Missed, Ahead and the footer, ending in
/// the [EndSlackSliver] — drawn by the report page and by the guide's screen
/// stage over plain inputs, so the two never drift (D74, the owner's
/// one-copy rule D59). It writes nothing and owns no data.
///
/// Every callback is what leaves the body; null leaves its control inert —
/// a row with no tap, a footer action disabled at 38 % — while the folds
/// stay live, since they are the body's own; [onCompare] is the one
/// exception. Before the first report it draws the Totals frame with
/// dashes, so a page never opens on a spinner.
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
    this.onDueTap,
    this.onReveal,
    this.onPresence,
    this.onShowAsList,
    this.onMoreCategories,
    this.onShare,
    this.onSend,
    this.onShrink,
    this.compare = ReportCompare.previous,
    this.compareView,
    this.foldedCompareView,
    this.views = const [],
    this.onCompare,
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

  /// A Due soon row's tap (M); the surface picks the day it opens on.
  final void Function(ReportDueRow row)? onDueTap;

  /// Called when a goal's or an insight's tap moves the body to one of its
  /// own cards — a group opened and scrolled to, the Due soon card scrolled
  /// to — so the surface can click. Null leaves those rows with no tap, as
  /// the guide's stage draws them; a tap that leaves the body reads
  /// [onMoreCategories] or [onShowAsList] instead.
  final VoidCallback? onReveal;

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
  /// caption compares it against — [against] a period, or [beside] a saved
  /// view's name, never both.
  final void Function(
    CalendarReport report, {
    required String periodName,
    required String? against,
    required String? beside,
  })?
  onShare;

  /// Send me this report, handed the period and allowlist the report was
  /// folded for.
  final void Function(OverviewPeriod period, Set<String> categoryIds)? onSend;

  /// Called before a frame that may shrink the content under the finger —
  /// a header close, "Show less" — so the surface can arm [slack].
  final VoidCallback? onShrink;

  /// The comparison asked for, which the Compare with row names. What the
  /// body draws — deltas, the second Totals card, the caption — reads
  /// [CalendarReport.compare] instead: the fold's truth, which falls back
  /// to the previous period where the asked one could not fold.
  final ReportCompare compare;

  /// The saved view asked for under [ReportCompare.view], which the row
  /// names.
  final OverviewView? compareView;

  /// The saved view [report] was folded beside, which the second Totals
  /// card and the caption name: while a refold runs it is still the old
  /// report's, so the card never wears the new pick's name over the old
  /// numbers (D36.9). Null under a view names it as the row's no-view word.
  final OverviewView? foldedCompareView;

  /// The saved views in their stored order: the Compare with menu's items.
  final List<OverviewView> views;

  /// A pick in the Compare with menu, handed the choice and, for a saved
  /// view, the view. Null draws no Compare with row at all — the one
  /// control here a null callback hides rather than disables (S5 A): the
  /// guide's stage has no comparison to offer, so a dimmed row would only
  /// teach a dead control.
  final void Function(ReportCompare compare, OverviewView? view)? onCompare;

  @override
  State<ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends State<ReportBody> {
  ScrollController? _ownScroll;

  ScrollController get _scroll =>
      widget.scroll ?? (_ownScroll ??= ScrollController());

  /// The Categories card's stack, which a goal's or an insight's tap opens
  /// a group of and scrolls to (G).
  final GlobalKey<ReportGroupStackState> _categories = GlobalKey();

  /// The By tag card's stack, which an insight about a tag opens the tag of
  /// and scrolls to.
  final GlobalKey<ReportGroupStackState> _tags = GlobalKey();

  /// The Due soon card's label, which an insight's tap scrolls to the top.
  final GlobalKey _dueSoonLabel = GlobalKey();

  /// How many reports of the same look have replaced the one drawn; the
  /// refold anchor acts on a count that moved, so a build only hands it
  /// over (R).
  int _refolds = 0;

  /// The section labels laid out, which the refold anchor is picked from.
  final _LabelAnchors _anchors = _LabelAnchors();

  /// The label the last refold holds, by its id; null holds none.
  Object? _anchor;

  /// The Totals block as last built, and the side-by-side choice it was
  /// built for: its [SliverLayoutBuilder] calls back on every scroll frame
  /// — the constraints carry the offset — and the same widget handed back
  /// rebuilds nothing. Dropped by every build of the body.
  ({bool sideBySide, Widget block})? _totalsBlock;

  /// Only a refold — a new report for the same period and allowlist, a
  /// compare pick's included — moves the anchor (§2.6). A step, a pick or a
  /// category change is another report altogether: it keeps the raw
  /// offset, and the page releases its end slack for it, which a correction
  /// would then spring back from. The anchor is decided here, from the
  /// labels' last layout, before the frame that lays the new report out
  /// (S6 H): the nearest label at or above the viewport's top.
  @override
  void didUpdateWidget(ReportBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report != null &&
        widget.report != null &&
        !identical(oldWidget.report, widget.report) &&
        oldWidget.period == widget.period &&
        setEquals(oldWidget.categoryIds, widget.categoryIds)) {
      _refolds++;
      final scroll = _scroll;
      _anchor = scroll.hasClients
          ? _anchors.nearestAbove(scroll.position.pixels)
          : null;
    }
  }

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

  /// From this body width a saved view's Totals card stands beside the
  /// page's rather than under it (S5 §2.5): Material 3's compact window
  /// ends here, and two half cards narrower than this wrap their tiles.
  static const double _compareSideBySideWidth = 600;

  /// [tiles] with no deltas: a saved view's two cards are the comparison,
  /// so neither draws one (S5 I).
  static List<ReportTileValue> _withoutDeltas(List<ReportTileValue> tiles) => [
    for (final tile in tiles)
      ReportTileValue(tile: tile.tile, value: tile.value, of: tile.of),
  ];

  /// The report [_bareTiles] last stripped, and its two cards' tiles.
  CalendarReport? _bareFor;
  ({List<ReportTileValue> shown, List<ReportTileValue> compared})? _bare;

  /// [report]'s and its saved view's tiles with no deltas, once per report.
  ({List<ReportTileValue> shown, List<ReportTileValue> compared}) _bareTiles(
    CalendarReport report,
    CalendarReport compared,
  ) {
    final bare = _bare;
    if (bare != null && identical(report, _bareFor)) return bare;
    _bareFor = report;
    return _bare = (
      shown: _withoutDeltas(report.tiles),
      compared: _withoutDeltas(compared.tiles),
    );
  }

  /// What the caption and the spoken deltas compare [report] against: the
  /// previous period by its name, the shown one stepped back, or the span of
  /// its days counted (D36.3); last year by the compared span itself, as
  /// the insights name it — a whole month or year by its name, anything
  /// else, a month so far included, by its counted days (D28).
  String? _againstName(
    CalendarReport report,
    OverviewPeriod period,
    ReportLabels labels,
  ) {
    if (report.compare == ReportCompare.lastYear) {
      return report.previousSpan == null
          ? null
          : labels.comparedSpanName(report);
    }
    return labels.comparisonName(
      report,
      previous: period.stepped(
        direction: -1,
        today: widget.today,
        yearBounds: widget.years,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = widget.labels;
    final report = widget.report;
    final period = widget.period;
    // A saved view's fold, drawn as a second Totals card; the last year's
    // and the previous period's are read through the tiles' deltas.
    final compared = report?.compare == ReportCompare.view
        ? report?.compared
        : null;
    final viewName =
        widget.foldedCompareView?.name ??
        labels.compareName(ReportCompare.view);
    final beside = compared == null ? null : viewName;
    final against = report == null || period == null || compared != null
        ? null
        : _againstName(report, period, labels);
    final caption = report == null || period == null
        ? null
        : labels.caption(
            report,
            periodName: labels.periodName(period),
            against: against,
            beside: beside,
          );
    final clearance = widget.bottomClearance;
    final slack = widget.slack;
    final analytics = report == null
        ? const <Widget>[]
        : _analyticsCards(l10n, labels, report);
    _totalsBlock = null;
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
                ...analytics,
                if (analytics.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                // The body's own width, not the screen's, decides how a
                // saved view's card stands (S5 §2.5); read around the
                // Totals block alone, so a change of height rebuilds no
                // other card. Keyed: the cards above may change their
                // count of slivers, and the anchors inside keep their last
                // layout (R).
                SliverLayoutBuilder(
                  key: const ValueKey(#totals),
                  builder: (context, constraints) {
                    final sideBySide =
                        constraints.crossAxisExtent +
                            2 * RowMetrics.groupInset >=
                        _compareSideBySideWidth;
                    final built = _totalsBlock;
                    if (built != null && built.sideBySide == sideBySide) {
                      return built.block;
                    }
                    final block = SliverMainAxisGroup(
                      slivers: _totalsCards(
                        l10n,
                        labels,
                        report,
                        compared: compared,
                        viewName: viewName,
                        against: against,
                        caption: caption,
                        sideBySide: sideBySide,
                      ),
                    );
                    _totalsBlock = (sideBySide: sideBySide, block: block);
                    return block;
                  },
                ),
                if (report != null) ...[
                  ..._yearCards(l10n, labels, report),
                  ..._buildCard(
                    ReportCard.categories,
                    l10n.reportSectionCategories,
                    report,
                    labels,
                  ),
                  ..._tagsCard(l10n, labels, report),
                ],
                // The builder already left the trend out below the
                // threshold and for a plan (Q, T).
                if (report case CalendarReport(:final trend?, :final span)) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                  _sectionLabel(#overTime, l10n.reportSectionOverTime),
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
                // Under the model's timed-day threshold, and in a plan,
                // which keeps no day, When has no busiest day (S5 §2.1).
                if (report?.when case final hours?
                    when hours.busiestWeekday != null) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                  _sectionLabel(#when, l10n.reportSectionWhen),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: ReportWhenChart(
                        when: hours,
                        labels: labels,
                        weekStart: widget.weekStart,
                      ),
                    ),
                  ),
                ],
                // An unprofiled calendar counts no area's hours, so it
                // inserts no Balance.
                if (report != null &&
                    report.balance.length >=
                        AnalyticsMetrics.balanceMinAreas) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                  _sectionLabel(#balance, l10n.reportSectionBalance),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: ReportBalanceCard(report: report, labels: labels),
                    ),
                  ),
                ],
                // A plan has no Missed and no Ahead (T): the builder
                // leaves both empty, and an empty card is not drawn (H).
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
                        beside: beside,
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

  /// [child], a section label's sliver, as a refold anchor candidate under
  /// [id] — the one the last refold holds when [id] is [_anchor] (R, S6 H).
  Widget _anchored(Object id, Widget child) => _AnchoredLabel(
    id: id,
    anchors: _anchors,
    refolds: _refolds,
    anchor: id == _anchor,
    child: child,
  );

  /// The section label [text] as a refold anchor candidate under [id].
  Widget _sectionLabel(Object id, String text) =>
      _anchored(id, FormSectionLabel(text: text));

  /// The Totals card under its label, then the caption. Beside a saved
  /// view (S5 §2.5) the view's card joins it under the view's name —
  /// stacked on a phone, side by side from [_compareSideBySideWidth] — with
  /// no deltas on either and the one caption under both. Both labels are
  /// anchor candidates (R); side by side, their row is one.
  List<Widget> _totalsCards(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport? report, {
    required CalendarReport? compared,
    required String viewName,
    required String? against,
    required String? caption,
    required bool sideBySide,
  }) {
    final totalsLabel = FormSectionLabel(text: l10n.reportSectionTotals);
    final bare = report == null || compared == null
        ? null
        : _bareTiles(report, compared);
    final card = ReportTotalsCard(
      tiles: bare?.shown ?? report?.tiles ?? _placeholderTiles,
      labels: labels,
      against: against,
      muted: report?.isEmpty ?? false,
      nominalMinutes: report?.nominalMinutes ?? 0,
    );
    final captionSliver = caption == null
        ? null
        : SliverToBoxAdapter(
            child: FormCaption(
              text: caption,
              padding: FormMetrics.groupCaptionPadding,
            ),
          );
    if (compared == null) {
      return [
        _anchored(#totals, totalsLabel),
        SliverToBoxAdapter(child: RepaintBoundary(child: card)),
        ?captionSliver,
      ];
    }
    // A compared fold has no categories, so it always reads as empty: the
    // view's card is never muted.
    final viewCard = ReportTotalsCard(
      tiles: bare!.compared,
      labels: labels,
      nominalMinutes: compared.nominalMinutes,
      tileIdentifier: SemanticsIds.reportViewTile,
    );
    final viewLabel = FormSectionLabel(text: viewName);
    if (!sideBySide) {
      return [
        _anchored(#totals, totalsLabel),
        SliverToBoxAdapter(child: RepaintBoundary(child: card)),
        const SliverToBoxAdapter(child: SizedBox(height: RowMetrics.groupGap)),
        _anchored(#view, viewLabel),
        SliverToBoxAdapter(child: RepaintBoundary(child: viewCard)),
        ?captionSliver,
      ];
    }
    // The labels share one row, so a name that wraps lowers both cards
    // alike and their tile rows stay level (J).
    return [
      _anchored(
        #totals,
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: totalsLabel),
            const SizedBox(width: RowMetrics.groupGap),
            Expanded(child: viewLabel),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: RepaintBoundary(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: card),
              const SizedBox(width: RowMetrics.groupGap),
              Expanded(child: viewCard),
            ],
          ),
        ),
      ),
      ?captionSliver,
    ];
  }

  /// The year in review between the Totals caption and Categories (S6
  /// §2.1): Records, then Months, each under its label after the gap
  /// between cards and absent with it when the card would draw nothing —
  /// the card's own rule, so a label never stands over an empty card. The
  /// model folds no year for a month, a week or a plan (A): they insert
  /// nothing. A strip's tap lands on its Categories group (G); with no way
  /// there wired, as on the guide's stage, the strips are read rows.
  List<Widget> _yearCards(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport report,
  ) {
    final year = report.year;
    if (year == null) return const [];
    final hasStrips = report.categories.any(
      (group) =>
          year.months[group.categoryId] != null &&
          year.spans[group.categoryId] != null,
    );
    final reachable =
        widget.onReveal != null || widget.onMoreCategories != null;
    return [
      if (year.records.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: RowMetrics.groupGap)),
        _sectionLabel(#records, l10n.reportSectionRecords),
        SliverToBoxAdapter(
          child: RepaintBoundary(
            child: ReportRecordsCard(
              report: report,
              labels: labels,
              folds: widget.folds,
              onShrink: widget.onShrink,
              scroll: _scroll,
              weekStart: widget.weekStart,
            ),
          ),
        ),
      ],
      if (hasStrips) ...[
        const SliverToBoxAdapter(child: SizedBox(height: RowMetrics.groupGap)),
        _sectionLabel(#months, l10n.reportSectionMonths),
        SliverToBoxAdapter(
          child: RepaintBoundary(
            child: ReportMonthsCard(
              report: report,
              labels: labels,
              folds: widget.folds,
              onShrink: widget.onShrink,
              scroll: _scroll,
              onCategoryTap: reachable
                  ? (categoryId) => _toGroup(report, categoryId)?.call()
                  : null,
            ),
          ),
        ),
      ],
    ];
  }

  /// The By tag card under its label (S5 §2.2), after the gap between
  /// cards: its tags are slivers of the page's one scroll, opened closed,
  /// with the card's own "n more"; nothing when no event carries a tag.
  List<Widget> _tagsCard(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport report,
  ) {
    if (report.tags.isEmpty) return const [];
    final tags = {for (final tag in report.tags) tag.key: tag};
    final span = report.span;
    final onShowAsList = widget.onShowAsList;
    return [
      const SliverToBoxAdapter(child: SizedBox(height: RowMetrics.groupGap)),
      _sectionLabel(#tags, l10n.reportSectionTags),
      ReportGroupStack(
        key: _tags,
        scroll: _scroll,
        folds: widget.folds,
        card: ReportCard.tags,
        groups: ReportGroupStack.tagGroups(report.tags),
        tags: tags,
        preview: ReportMetrics.groupPreviewRows,
        events: report.events,
        labels: labels,
        onDatedTap: widget.onDatedTap,
        // A tag's group stands under its key, always one of [tags]: the
        // list is over the tag's categories.
        onShowAsList: onShowAsList == null
            ? null
            : (group) => onShowAsList(
                start: span.start,
                end: span.end,
                categoryIds: tags[group.categoryId]!.categoryIds.toSet(),
              ),
        today: widget.today,
        spansMonths: _spansMonths(report),
        use24Hour: widget.use24Hour,
        onShrink: widget.onShrink,
      ),
    ];
  }

  /// Goals, Insights and Due soon above Totals (S4 §2.1), each under its
  /// label after the gap between cards, the first with none; a card with
  /// nothing to show is absent with its label (H), so an unprofiled report
  /// inserts no sliver and opens on Totals as it always has. A plan has no
  /// Insights: nothing has happened to remark on. The Insights card reads
  /// the page's filter, which drops what Goals and Due soon already say.
  List<Widget> _analyticsCards(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport report,
  ) {
    final insights = report.tense == ReportTense.future
        ? const <ReportInsight>[]
        : ReportInsightFilter.forPage(report);
    final cards = [
      if (report.goals.isNotEmpty)
        (
          id: #goals,
          label: l10n.reportSectionGoals,
          labelKey: null,
          card: ReportGoalsCard(
            report: report,
            labels: labels,
            canTap: (goal) => _toGroup(report, goal.categoryId) != null,
            onGoalTap: (goal) => _toGroup(report, goal.categoryId)?.call(),
          ),
        ),
      if (insights.isNotEmpty)
        (
          id: #insights,
          label: l10n.reportSectionInsights,
          labelKey: null,
          card: ReportInsightsCard(
            insights: insights,
            report: report,
            labels: labels,
            weekStart: widget.weekStart,
            canTap: (insight) => _toInsight(report, insight) != null,
            onInsightTap: (insight) => _toInsight(report, insight)?.call(),
          ),
        ),
      if (report.dueSoon.isNotEmpty)
        (
          id: #dueSoon,
          label: l10n.reportSectionDueSoon,
          labelKey: _dueSoonLabel,
          card: ReportDueSoonCard(
            report: report,
            labels: labels,
            folds: widget.folds,
            onDueTap: widget.onDueTap,
            onShrink: widget.onShrink,
            scroll: _scroll,
          ),
        ),
    ];
    return [
      for (final (index, (:id, :label, :labelKey, :card)) in cards.indexed) ...[
        if (index > 0)
          const SliverToBoxAdapter(
            child: SizedBox(height: RowMetrics.groupGap),
          ),
        _anchored(id, FormSectionLabel(key: labelKey, text: label)),
        SliverToBoxAdapter(child: RepaintBoundary(child: card)),
      ],
    ];
  }

  /// Where a tap about [categoryId]'s group lands (G): a group the card
  /// shows opens and scrolls to the top; one past the cap opens the "n more
  /// categories" sheet, as the cap row does. Null — a row with no tap —
  /// when the category has no group, or the surface wired no way there.
  VoidCallback? _toGroup(CalendarReport report, String? categoryId) {
    if (categoryId == null) return null;
    final groups = report.categories;
    final index = groups.indexWhere((group) => group.categoryId == categoryId);
    if (index < 0) return null;
    if (index < ReportMetrics.maxCategoryRows) {
      final onReveal = widget.onReveal;
      if (onReveal == null) return null;
      return () {
        onReveal();
        _categories.currentState?.reveal(categoryId);
      };
    }
    final onMoreCategories = widget.onMoreCategories;
    if (onMoreCategories == null) return null;
    return () => onMoreCategories(
      report,
      largest: groups.first.count,
      spansMonths: _spansMonths(report),
    );
  }

  /// Where [insight]'s tap lands, by its target (§2.3): its category's
  /// group, the Due soon card's label at the top, or the overview's list on
  /// its days — over its category, else the page's allowlist. A tag's rows
  /// are its header in the By tag card, opened and scrolled to; a tag past
  /// the card's [AnalyticsMetrics.tagRows] has none there, so it reads its
  /// first category's group. Null when the target cannot be reached.
  VoidCallback? _toInsight(CalendarReport report, ReportInsight insight) {
    switch (insight.target) {
      case InsightTarget.categoryGroup:
        return _toGroup(report, insight.categoryId);
      case InsightTarget.tagRows:
        final index = report.tags.indexWhere(
          (tag) => tag.key == insight.tagKey,
        );
        if (index < 0) return null;
        final tag = report.tags[index];
        if (index >= AnalyticsMetrics.tagRows) {
          return _toGroup(report, tag.categoryIds.firstOrNull);
        }
        final onReveal = widget.onReveal;
        if (onReveal == null) return null;
        return () {
          onReveal();
          _tags.currentState?.reveal(tag.key);
        };
      case InsightTarget.dueSoon:
        final onReveal = widget.onReveal;
        if (onReveal == null || report.dueSoon.isEmpty) return null;
        return () {
          onReveal();
          revealAtTop(
            _scroll,
            () => _dueSoonLabel.currentContext?.findRenderObject(),
          );
        };
      case InsightTarget.overviewDays:
        final day = insight.day;
        final onShowAsList = widget.onShowAsList;
        if (day == null || onShowAsList == null) return null;
        final categoryId = insight.categoryId;
        return () => onShowAsList(
          start: day,
          end: insight.dayEnd ?? day,
          categoryIds: categoryId == null ? widget.categoryIds : {categoryId},
        );
    }
  }

  /// Whether [report]'s span crosses a month: a row's day names it (U).
  static bool _spansMonths(CalendarReport report) {
    final span = report.span;
    return span.start.year != span.end.year ||
        span.start.month != span.end.month;
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
      ReportCard.tags => throw StateError('the tags card is _tagsCard\'s'),
    };
    if (all.isEmpty) return const [];
    final capped =
        card == ReportCard.categories &&
        all.length > ReportMetrics.maxCategoryRows;
    final groups = capped ? all.sublist(0, ReportMetrics.maxCategoryRows) : all;
    final span = report.span;
    final spansMonths = _spansMonths(report);
    // Ahead's rows are the days after the counted end, so its list starts
    // there; Categories and Missed list the folded span.
    final counted = report.countedTo;
    final listStart = card == ReportCard.ahead
        ? DateTime.utc(counted.year, counted.month, counted.day + 1)
        : span.start;
    final onShowAsList = widget.onShowAsList;
    return [
      const SliverToBoxAdapter(child: SizedBox(height: RowMetrics.groupGap)),
      _sectionLabel(card, label),
      ReportGroupStack(
        // Still one key per card: Categories' is the one a goal reaches.
        key: card == ReportCard.categories ? _categories : ValueKey(card),
        scroll: _scroll,
        folds: widget.folds,
        card: card,
        groups: groups,
        events: report.events,
        labels: labels,
        measures: report.measures,
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

  /// The footer of [report], folded over [period] and [categoryIds]:
  /// Compare with first where the surface offers it; Show as list hands the
  /// overview the span the service folded — clamped past 366 days (D33) —
  /// not the period's own; Share writes the report shown, with [against] or
  /// [beside] as the caption names it.
  Widget _buildFooter(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport report, {
    required OverviewPeriod period,
    required Set<String> categoryIds,
    required String? against,
    required String? beside,
  }) {
    final onShowAsList = widget.onShowAsList;
    final onShare = widget.onShare;
    final onSend = widget.onSend;
    final onCompare = widget.onCompare;
    return FormRowGroup(
      trailingGap: false,
      children: [
        if (onCompare != null) _compareRow(l10n, labels, report, onCompare),
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
                  beside: beside,
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

  /// "Compare with … ›", the footer's first row (S5 A): the previous
  /// period, the same period last year — disabled where the calendar's
  /// first year does not reach back — and every saved view by name, picked
  /// in one tap (G); with no saved view one disabled item says so, never
  /// hidden. Its value is the choice asked for, not the one folded.
  Widget _compareRow(
    AppLocalizations l10n,
    ReportLabels labels,
    CalendarReport report,
    void Function(ReportCompare compare, OverviewView? view) onCompare,
  ) {
    final compare = widget.compare;
    final views = widget.views;
    return FormMenuRow<_CompareChoice>(
      glyph: Icons.compare_arrows_rounded,
      label: l10n.reportCompareWith,
      value: labels.compareName(compare, viewName: widget.compareView?.name),
      selected: (
        compare: compare,
        viewId: compare == ReportCompare.view ? widget.compareView?.id : null,
      ),
      items: [
        FormMenuItem(
          value: (compare: ReportCompare.previous, viewId: null),
          label: l10n.reportComparePrevious,
          icon: Icons.history_rounded,
          identifier: SemanticsIds.reportComparePrevious,
        ),
        FormMenuItem(
          value: (compare: ReportCompare.lastYear, viewId: null),
          label: l10n.reportCompareLastYear,
          icon: Icons.event_repeat_rounded,
          identifier: SemanticsIds.reportCompareLastYear,
          enabled: report.span.start.year - 1 >= widget.years.first,
        ),
        if (views.isEmpty)
          FormMenuItem(
            value: (compare: ReportCompare.view, viewId: null),
            label: l10n.reportCompareNoViews,
            icon: Icons.bookmark_border_rounded,
            identifier: SemanticsIds.reportCompareNone,
            enabled: false,
          )
        else
          for (final view in views)
            FormMenuItem(
              value: (compare: ReportCompare.view, viewId: view.id),
              label: view.name,
              icon: Icons.bookmark_border_rounded,
              identifier: SemanticsIds.reportCompareView(view.id),
            ),
      ],
      onSelected: (choice) => onCompare(
        choice.compare,
        views.where((view) => view.id == choice.viewId).firstOrNull,
      ),
      menuWidth: FormMetrics.menuWidth,
      identifier: SemanticsIds.reportCompare,
    );
  }
}

/// A Compare with menu item: the mode, and the saved view's id under
/// [ReportCompare.view]. A record, so the menu's selection compares by
/// value.
typedef _CompareChoice = ({ReportCompare compare, String? viewId});

/// The section labels laid out, by id: a refold holds the one nearest above
/// the viewport's top (R, S6 H), read from their last layout before the
/// frame that lays the new report out.
class _LabelAnchors {
  final Map<Object, _RenderAnchoredLabel> _labels = {};

  /// The label whose start, at its last layout, lies nearest at or above
  /// [top], the viewport's scroll offset; null when [top] lies above every
  /// label, as at offset 0. At the top counts: a label a reveal left there
  /// is where the reader reads.
  Object? nearestAbove(double top) {
    Object? nearest;
    var nearestStart = double.negativeInfinity;
    for (final MapEntry(key: id, value: label) in _labels.entries) {
      final start = label._preceding;
      if (start == null ||
          start > top + precisionErrorTolerance ||
          start <= nearestStart) {
        continue;
      }
      nearest = id;
      nearestStart = start;
    }
    return nearest;
  }
}

/// A section label's sliver, a candidate for the page's anchor on a refold
/// (R, §2.6, S6 H): the cards above the reader's place change height with
/// the report — Insights, Due soon, a saved view's Totals card, a group —
/// and everything under the finger would move by that change. Still a
/// [SliverToBoxAdapter], so the body's slivers read as they always have.
/// Keyed by [id], so a refold that changes the count of slivers above it
/// keeps its last layout to compare against.
class _AnchoredLabel extends SliverToBoxAdapter {
  _AnchoredLabel({
    required this.id,
    required this.anchors,
    required this.refolds,
    required this.anchor,
    required Widget super.child,
  }) : super(key: ValueKey((#anchor, id)));

  /// The label's section, which [anchors] knows it by.
  final Object id;

  final _LabelAnchors anchors;

  /// How many reports have replaced the one drawn; a count that moved arms
  /// the next layout.
  final int refolds;

  /// Whether this label is the one the last refold holds.
  final bool anchor;

  @override
  _RenderAnchoredLabel createRenderObject(BuildContext context) =>
      _RenderAnchoredLabel(
        id: id,
        anchors: anchors,
        refolds: refolds,
        anchor: anchor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAnchoredLabel renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..refolds = refolds;
  }
}

/// Armed by a new report, the anchor's next layout compares its preceding
/// extent — everything above it — with the last one laid, and corrects the
/// scroll offset by the difference inside that layout, so the new report's
/// first frame already holds the label, and all below it, where it was:
/// never a post-frame jump, never a frame drawn off the finger. With no
/// label at or above the top there is no anchor, so at offset 0 the page
/// still opens on the first card. Only a new report arms it: "Show less" on
/// the Due soon card carries its own compensation.
class _RenderAnchoredLabel extends RenderSliverToBoxAdapter {
  _RenderAnchoredLabel({
    required Object id,
    required _LabelAnchors anchors,
    required int refolds,
    required bool anchor,
  }) : _id = id,
       _anchors = anchors,
       _refolds = refolds,
       _anchor = anchor;

  final Object _id;
  final _LabelAnchors _anchors;
  int _refolds;
  bool _anchor;
  bool _armed = false;

  /// The extent above the label at the last layout — its start in the
  /// scroll; null before the first.
  double? _preceding;

  set anchor(bool value) => _anchor = value;

  set refolds(int value) {
    if (value == _refolds) return;
    _refolds = value;
    _armed = true;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _anchors._labels[_id] = this;
  }

  @override
  void detach() {
    if (identical(_anchors._labels[_id], this)) _anchors._labels.remove(_id);
    super.detach();
  }

  @override
  void performLayout() {
    final preceding = constraints.precedingScrollExtent;
    final old = _preceding;
    final armed = _armed;
    _armed = false;
    if (armed && _anchor && old != null && preceding != old) {
      // The viewport lays every sliver out again at the corrected offset.
      geometry = SliverGeometry(scrollOffsetCorrection: preceding - old);
      return;
    }
    super.performLayout();
    _preceding = preceding;
  }
}
