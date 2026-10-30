import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/calendar_report/calendar_report_bloc.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_state.dart';
import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/calendar_export_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_report.dart';
import '../models/overview_period.dart';
import '../models/report_look.dart';
import '../models/report_period_choice.dart';
import '../services/app_navigator.dart';
import '../services/calendar_report_service.dart';
import '../services/settings_service.dart';
import '../utils/date_span_label.dart';
import '../utils/event_agenda.dart';
import '../utils/report_labels.dart';
import '../widgets/agenda_period_nav.dart';
import '../widgets/automation_id.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/calendar_header_menus.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/form_rows.dart';
import '../widgets/report_totals_card.dart';
import '../widgets/report_trend_chart.dart';

/// The calendar's third view (A): what happened and what is planned over a
/// period, folded from the app-wide calendar into one `CalendarReport` by the
/// page's own bloc and service (U, D30).
///
/// [look] is the overview's period and allowlist when its view menu opened
/// the report (D35) — for this visit; opened from the calendar or restored at
/// launch, the report reads what it remembers.
class CalendarReportPage extends StatelessWidget {
  const CalendarReportPage({super.key, this.look})
    : _service = null,
      _clock = DateTime.now,
      _nextFrame = null;

  /// Hands the page the [service] it folds through, so a suite can count its
  /// folds; the [clock] today is read from, so no case reads the wall clock;
  /// and what a fold waits on before it runs ([nextFrame]), so a suite can
  /// hold a refold open.
  @visibleForTesting
  const CalendarReportPage.forTesting({
    super.key,
    this.look,
    required CalendarReportService service,
    DateTime Function() clock = DateTime.now,
    Future<void> Function()? nextFrame,
  }) : _service = service,
       _clock = clock,
       _nextFrame = nextFrame;

  final ReportLook? look;
  final CalendarReportService? _service;
  final DateTime Function() _clock;
  final Future<void> Function()? _nextFrame;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final calendar = context.read<CalendarBloc>();
        // Restored at launch, the report may be the first calendar surface
        // to open: the overview's rule.
        if (calendar.isStale) calendar.add(const LoadCalendarEvents());
        return CalendarReportBloc(
          service: _service ?? CalendarReportService(),
          calendar: calendar,
          settings: SettingsService.getInstance(),
          clock: _clock,
          nextFrame: _nextFrame,
        )..add(ReportOpened(look: look));
      },
      child: _ReportView(clock: _clock),
    );
  }
}

class _ReportView extends StatefulWidget {
  const _ReportView({required this.clock});

  final DateTime Function() clock;

  @override
  State<_ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<_ReportView>
    with WidgetsBindingObserver, RouteAware {
  /// The ⋮ menu's `.ics` export, answered only when this page started it.
  final CalendarExportController _export = CalendarExportController();

  PageRoute<dynamic>? _route;
  bool _pickerOpen = false;

  /// Whether a page covers this one: a resume underneath asks nothing, and
  /// [didPopNext] asks once on the way back (the overview's rule).
  bool _covered = false;

  String? _templatesKey;
  List<String> _templates = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && !identical(route, _route)) {
      if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
      _route = route;
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_covered) _askAgain();
  }

  @override
  void didPushNext() => _covered = true;

  @override
  void didPopNext() {
    _covered = false;
    _askAgain();
  }

  /// Back in front: a new day moves the periods holding today and asks the
  /// rest too; otherwise the report asks again for what changes with no
  /// calendar event (D32).
  void _askAgain() {
    final bloc = context.read<CalendarReportBloc>();
    final today = EventAgenda.dateOnly(widget.clock());
    final state = bloc.state;
    if (state is ReportShown && state.today != today) {
      bloc.add(ReportDayChanged(today));
    } else {
      bloc.add(const ReportResumed());
    }
  }

  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  /// Calendar settings can delete a category, which reassigns its events
  /// behind the service's cache without a revision, so the events reload
  /// after the trip — as the calendar and the overview do.
  Future<void> _openSettings() async {
    final calendar = context.read<CalendarBloc>();
    await AppNavigator.toCalendarSettings(context);
    if (!mounted) return;
    calendar.add(const LoadCalendarEvents());
  }

  void _exportEvents() {
    final state = context.read<CalendarBloc>().state;
    if (state is! CalendarPageLoaded) return;
    _export.start(context, state.allEvents);
  }

  void _switchPage(CalendarViewPage page) {
    switch (page) {
      case CalendarViewPage.calendar:
        unawaited(AppNavigator.switchToCalendar(context));
      case CalendarViewPage.overview:
        unawaited(AppNavigator.switchToCalendarOverview(context));
      case CalendarViewPage.report:
        break;
    }
  }

  /// The multi picker over the allowlist, as the overview's: an empty
  /// allowlist opens with every offered row ticked, and a pick covering
  /// every offered row collapses back to empty, so a category created later
  /// is in scope too.
  Future<void> _pickCategories() async {
    if (_pickerOpen) return;
    final bloc = context.read<CalendarReportBloc>();
    final state = bloc.state;
    if (state is! ReportShown) return;
    _pickerOpen = true;
    try {
      _blur();
      final current = state.categoryIds;
      final offered = {
        for (final category in CalendarCategories.visiblePlus(current))
          category.id,
      };
      final picked = await CategoryPickerSheet.pickMulti(
        context,
        selected: current.isEmpty ? offered : current,
      );
      if (picked == null || !mounted) return;
      final next = picked.containsAll(offered) ? const <String>{} : picked;
      if (setEquals(next, current)) return;
      bloc.add(ReportCategoriesPicked(next));
    } finally {
      _pickerOpen = false;
    }
  }

  static String _choiceLabel(AppLocalizations l10n, ReportPeriodChoice c) {
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

  static IconData _choiceIcon(ReportPeriodChoice c) {
    return switch (c) {
      ReportPeriodChoice.thisWeek ||
      ReportPeriodChoice.lastWeek ||
      ReportPeriodChoice.nextWeek => Icons.view_week_rounded,
      ReportPeriodChoice.thisMonth ||
      ReportPeriodChoice.lastMonth ||
      ReportPeriodChoice.nextMonth => Icons.calendar_view_month_rounded,
      ReportPeriodChoice.thisYear => Icons.today_rounded,
      ReportPeriodChoice.last12Months ||
      ReportPeriodChoice.last90Days => Icons.history_rounded,
      ReportPeriodChoice.custom => Icons.date_range_rounded,
    };
  }

  static String _choiceId(ReportPeriodChoice c) {
    return switch (c) {
      ReportPeriodChoice.thisWeek => SemanticsIds.reportPeriodThisWeek,
      ReportPeriodChoice.lastWeek => SemanticsIds.reportPeriodLastWeek,
      ReportPeriodChoice.nextWeek => SemanticsIds.reportPeriodNextWeek,
      ReportPeriodChoice.thisMonth => SemanticsIds.reportPeriodThisMonth,
      ReportPeriodChoice.lastMonth => SemanticsIds.reportPeriodLastMonth,
      ReportPeriodChoice.nextMonth => SemanticsIds.reportPeriodNextMonth,
      ReportPeriodChoice.thisYear => SemanticsIds.reportPeriodThisYear,
      ReportPeriodChoice.last12Months => SemanticsIds.reportPeriodLast12Months,
      ReportPeriodChoice.last90Days => SemanticsIds.reportPeriodLast90Days,
      ReportPeriodChoice.custom => SemanticsIds.reportPeriodCustom,
    };
  }

  /// The band's title as the Period menu, centred under the title (the
  /// overview's D33). Custom range… asks the Dates sheet and changes
  /// nothing when it is cancelled.
  Future<void> _openPeriodMenu(BuildContext anchor) async {
    final bloc = context.read<CalendarReportBloc>();
    final state = bloc.state;
    if (state is! ReportShown) return;
    final l10n = AppLocalizations.of(context)!;
    _blur();
    final choice = await showFormMenu<ReportPeriodChoice>(
      anchor,
      items: [
        for (final choice in ReportPeriodChoice.values)
          FormMenuItem(
            value: choice,
            label: _choiceLabel(l10n, choice),
            icon: _choiceIcon(choice),
            identifier: _choiceId(choice),
          ),
      ],
      selected: ReportPeriodChoice.checkedFor(
        state.period,
        today: state.today,
        weekStart: state.weekStart,
        years: state.years,
      ),
      menuWidth: FormMetrics.menuWidth,
      alignment: FormMenuAlignment.center,
    );
    if (choice == null || !mounted) return;
    final current = bloc.state;
    if (current is! ReportShown) return;
    if (choice == ReportPeriodChoice.custom) {
      final picked = await _pickRange(current);
      if (picked == null) return;
      bloc.add(ReportPeriodPicked(picked));
      return;
    }
    bloc.add(
      ReportPeriodPicked(
        choice.periodFor(
          today: current.today,
          weekStart: current.weekStart,
          years: current.years,
        ),
      ),
    );
  }

  /// The Dates sheet's range mode, seeded with the span shown; null when it
  /// is cancelled, already open, or the page has gone. The bloc clamps a
  /// span past 366 days (D33).
  Future<OverviewCustomPeriod?> _pickRange(ReportShown state) async {
    if (_pickerOpen) return null;
    _pickerOpen = true;
    try {
      final picked = await CalendarDatePickerSheet.pickRange(
        context,
        initialRange: state.period.resolve(
          today: state.today,
          yearBounds: state.years,
        ),
        firstDate: DateTime.utc(state.years.first, 1, 1),
        lastDate: DateTime.utc(state.years.last, 12, 31),
        appearance: state.appearance,
      );
      if (picked == null || !mounted) return null;
      return OverviewCustomPeriod(picked.start, picked.end);
    } finally {
      _pickerOpen = false;
    }
  }

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
        _choiceLabel(l10n, choice),
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

  /// The period and allowlist the report [state] draws was folded for: the
  /// pick itself once Ready, the one before it while a refold runs — so the
  /// caption and Show as list never pair the new pick with the old numbers
  /// (D36.9); null before the first report.
  static ({OverviewPeriod period, Set<String> categoryIds})? _foldedFor(
    ReportShown state,
  ) => switch (state) {
    ReportReady(:final period, :final categoryIds) => (
      period: period,
      categoryIds: categoryIds,
    ),
    ReportFolding(:final previousPeriod?, :final previousCategoryIds) => (
      period: previousPeriod,
      categoryIds: previousCategoryIds,
    ),
    ReportFolding() => null,
  };

  /// What the caption and the spoken deltas compare [report] against: the
  /// previous period's name, or the span of its days counted (D36.3).
  static String? _againstName(
    ReportShown state,
    CalendarReport report,
    OverviewPeriod period,
    ReportLabels labels,
  ) {
    final previous = period.stepped(
      direction: -1,
      today: state.today,
      yearBounds: state.years,
    );
    return labels.comparisonName(report, previous: previous);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final labels = ReportLabels(l10n);
    final hasEvents = context.select<CalendarBloc, bool>(
      (bloc) => switch (bloc.state) {
        CalendarPageLoaded(:final allEvents) => allEvents.isNotEmpty,
        _ => false,
      },
    );
    return BlocListener<ImportExportBloc, ImportExportState>(
      listener: _export.onState,
      child: BlocBuilder<CalendarReportBloc, ReportState>(
        builder: (context, state) {
          final shown = state is ReportShown ? state : null;
          return Scaffold(
            backgroundColor: colorScheme.pageGround,
            // The body pads itself by the larger of the keyboard and the
            // system inset, so it must see the keyboard's.
            resizeToAvoidBottomInset: false,
            appBar: _buildBar(l10n, colorScheme, shown, hasEvents),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBand(l10n, labels, state),
                Expanded(
                  child: _RefoldDim(
                    folding: state is ReportFolding && state.previous != null,
                    child: _buildBody(l10n, labels, state),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildBar(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    ReportShown? shown,
    bool hasEvents,
  ) {
    final ids = shown?.categoryIds ?? const <String>{};
    final narrowed = ids.isNotEmpty;
    return AppBar(
      titleSpacing: CalendarViewMenu.titleSpacing,
      excludeHeaderSemantics: true,
      title: CalendarViewMenu(
        page: CalendarViewPage.report,
        onPageSelected: _switchPage,
      ),
      toolbarHeight: AppBarMetrics.toolbarHeight,
      iconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      actionsIconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [
        AutomationId(
          identifier: SemanticsIds.reportCategoriesOpen,
          child: IconButton(
            tooltip: l10n.calendarCategories,
            isSelected: narrowed,
            iconSize: AppBarMetrics.glyphSize,
            // The count rides the glyph and stays out of the button's node
            // (the ui-language badge rule): the tooltip stays what is read.
            icon: ExcludeSemantics(
              child: Badge.count(
                count: ids.length,
                isLabelVisible: narrowed,
                child: Icon(
                  narrowed
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                ),
              ),
            ),
            onPressed: shown == null ? null : _pickCategories,
          ),
        ),
        CalendarOverflowMenu(
          identifier: SemanticsIds.reportMore,
          onAlerts: () => AppNavigator.toAlertsFromCalendar(context),
          onExport: hasEvents ? _exportEvents : null,
          onGuide: () => AppNavigator.toCalendarGuide(context),
          onSettings: _openSettings,
        ),
      ],
    );
  }

  Widget _buildBand(
    AppLocalizations l10n,
    ReportLabels labels,
    ReportState state,
  ) {
    final shown = state is ReportShown ? state : null;
    final period = switch (state) {
      ReportShown(:final period) => period,
      ReportLoading(:final period) => period,
    };
    final report = shown?.shown;
    final bloc = context.read<CalendarReportBloc>();
    bool canStep(int direction) =>
        shown != null &&
        shown.period.stepped(
              direction: direction,
              today: shown.today,
              yearBounds: shown.years,
            ) !=
            null;
    return AgendaPeriodNav(
      title: period == null ? '' : labels.periodName(period),
      titleTemplates: _titleTemplates(
        l10n,
        shown?.today ?? EventAgenda.dateOnly(widget.clock()),
      ),
      // Never null: a null subtitle drops the count's line, and the band
      // would grow under the finger when the first report lands. Blank
      // while a refold runs, so the new title never reads the old counts —
      // a no-break space, whose line is a word's height at every scale
      // where an empty string's fell a pixel short at 1.3.
      subtitle: report == null || state is ReportFolding
          ? ' '
          : labels.subtitle(report),
      previousTooltip: l10n.overviewPeriodPrevious,
      nextTooltip: l10n.overviewPeriodNext,
      todayTooltip: l10n.overviewPeriodHome(
        shown == null ? '' : labels.periodName(shown.home),
      ),
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.reportNavPrevious,
      nextIdentifier: SemanticsIds.reportNavNext,
      todayIdentifier: SemanticsIds.reportNavToday,
      titleIdentifier: SemanticsIds.reportNavTitle,
      onTitleTap: shown == null ? null : _openPeriodMenu,
      onPrevious: canStep(-1) ? () => bloc.add(const ReportStepped(-1)) : null,
      onNext: canStep(1) ? () => bloc.add(const ReportStepped(1)) : null,
      onToday: shown == null || shown.period == shown.home
          ? null
          : () => bloc.add(const ReportHomePressed()),
    );
  }

  /// Before the first report: the Totals frame with dashes, so the page
  /// never opens on a spinner.
  static const List<ReportTileValue> _placeholderTiles = [
    ReportTileValue(tile: ReportTile.events, value: 0),
    ReportTileValue(tile: ReportTile.hours, value: 0),
  ];

  Widget _buildBody(
    AppLocalizations l10n,
    ReportLabels labels,
    ReportState state,
  ) {
    final shown = state is ReportShown ? state : null;
    final folded = shown == null ? null : _foldedFor(shown);
    final report = folded == null ? null : shown?.shown;
    final against = shown == null || report == null || folded == null
        ? null
        : _againstName(shown, report, folded.period, labels);
    final caption = report == null || folded == null
        ? null
        : labels.caption(
            report,
            periodName: labels.periodName(folded.period),
            against: against,
          );
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Semantics(
      container: true,
      identifier: SemanticsIds.reportBody,
      child: CustomScrollView(
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
                // The builder already left the trend out below the
                // threshold and for a plan (Q, T).
                if (report case CalendarReport(:final trend?, :final span))
                  if (shown != null) ...[
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
                          weekStart: shown.weekStart,
                          span: span,
                        ),
                      ),
                    ),
                  ],
                if (folded != null && report != null) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: RowMetrics.groupGap),
                  ),
                  SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _buildFooter(
                        l10n,
                        report,
                        period: folded.period,
                        categoryIds: folded.categoryIds,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The footer of [report], folded over [period] and [categoryIds]: Show
  /// as list hands the overview the span the service folded — clamped past
  /// 366 days (D33) — not the period's own.
  Widget _buildFooter(
    AppLocalizations l10n,
    CalendarReport report, {
    required OverviewPeriod period,
    required Set<String> categoryIds,
  }) {
    return FormRowGroup(
      trailingGap: false,
      children: [
        FormActionRow(
          glyph: Icons.view_list_rounded,
          label: l10n.reportShowAsList,
          identifier: SemanticsIds.reportShowList,
          onTap: () => AppNavigator.toCalendarOverviewLook(
            start: report.span.start,
            end: report.span.end,
            categoryIds: categoryIds,
          ),
        ),
        // Share arrives with S5, the scheduled report with S4 (K, J):
        // disabled at 38 %, never hidden.
        FormActionRow(
          glyph: Icons.share_rounded,
          label: l10n.reportShare,
          identifier: SemanticsIds.reportShare,
          onTap: null,
        ),
        FormActionRow(
          glyph: Icons.notifications_rounded,
          label: period is OverviewWeekPeriod
              ? l10n.reportSendWeekly
              : l10n.reportSendMonthly,
          identifier: SemanticsIds.reportSend,
          onTap: null,
        ),
      ],
    );
  }
}

/// The refold (§4.2, R): while a fold runs over a report already shown,
/// the body keeps it and dims after [ReportMetrics.refoldDimDelay] — a
/// quick fold lands before that and never flickers — absorbing taps while
/// dim, and un-dims at once. The bar and the band are not inside it.
class _RefoldDim extends StatefulWidget {
  const _RefoldDim({required this.folding, required this.child});

  final bool folding;
  final Widget child;

  @override
  State<_RefoldDim> createState() => _RefoldDimState();
}

class _RefoldDimState extends State<_RefoldDim> {
  Timer? _timer;
  bool _dim = false;

  @override
  void initState() {
    super.initState();
    if (widget.folding) _arm();
  }

  @override
  void didUpdateWidget(_RefoldDim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.folding && !oldWidget.folding) {
      _arm();
    } else if (!widget.folding) {
      _timer?.cancel();
      _timer = null;
      _dim = false;
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(ReportMetrics.refoldDimDelay, () {
      if (mounted) setState(() => _dim = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _dim,
      child: Opacity(
        opacity: _dim ? ReportMetrics.refoldOpacity : 1,
        child: widget.child,
      ),
    );
  }
}
