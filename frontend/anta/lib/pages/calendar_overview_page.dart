import 'dart:async';

import 'package:flutter/foundation.dart'
    show precisionErrorTolerance, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_state.dart';
import '../controllers/calendar_export_controller.dart';
import '../controllers/event_sheets_flow.dart';
import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_presence.dart';
import '../constants/overview_list_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/date_range.dart';
import '../models/day_bar.dart';
import '../models/overview_list_options.dart';
import '../models/overview_period.dart';
import '../models/overview_view.dart';
import '../models/partner_look.dart';
import '../models/share_settings.dart';
import '../services/agenda_search_text.dart';
import '../services/alert_keep_notice.dart';
import '../services/app_navigator.dart';
import '../services/day_bars_resolver.dart';
import '../services/overview_view_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/agenda_month_store.dart';
import '../utils/category_allowlist.dart';
import '../utils/date_span_label.dart';
import '../utils/event_agenda.dart';
import '../utils/event_query_matcher.dart';
import '../utils/event_search_query.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/sheet_guard.dart';
import '../widgets/agenda_day_list_rows.dart';
import '../widgets/agenda_list_view.dart';
import '../widgets/agenda_month_grid.dart';
import '../widgets/agenda_period_nav.dart';
import '../widgets/agenda_year_grid.dart';
import '../widgets/agenda_year_scroll.dart';
import '../widgets/automation_id.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/calendar_header_menus.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/form_rows.dart';
import '../widgets/list_scrubber.dart';
import '../widgets/overview_mode_chips.dart';
import '../widgets/overview_options_sheet.dart';
import '../widgets/overview_view_sheet.dart';

part 'calendar_overview_page/state.dart';
part 'calendar_overview_page/queries.dart';
part 'calendar_overview_page/years.dart';
part 'calendar_overview_page/row_actions.dart';
part 'calendar_overview_page/list_scroll.dart';
part 'calendar_overview_page/navigation.dart';
part 'calendar_overview_page/controls.dart';
part 'calendar_overview_page/loading.dart';
part 'calendar_overview_page/data.dart';
part 'calendar_overview_page/chrome.dart';
part 'calendar_overview_page/body.dart';
part 'calendar_overview_page/list_layout.dart';
part 'calendar_overview_page/row_extent_probe.dart';

/// The calendar overview: every event of the chosen categories as a year of
/// dot-matrix tiles, a month grid or a dated list over a period — the agenda
/// drill-down's presentations, standalone.
///
/// Independent of the calendar page on purpose: it has no window, no anchor
/// and no selected day, so a year is always a whole year. Years are sections
/// of one continuous scroll — dragged through, or scrolled to with the
/// chevrons and the Period menu — and only the years the chosen events can
/// be in are sections at all, an open-ended series reaching next year, so
/// nobody scrolls through empty decades. The list shows a period instead —
/// a year, a span ending today, or one picked in the Dates sheet. It owns no
/// data either. Events come from the app-wide `CalendarBloc`, whose loaded
/// state is also what guarantees the category and presence facades the rows
/// read are configured; a row tap opens the occurrence's detail sheet right
/// over the list (D14 · A), the calendar's own trip through it
/// ([EventSheetsFlow]), so back closes it onto the row. The category allowlist (empty = all, the
/// agenda's convention), the presentation, a preset period and the list's
/// order and rows are persisted; a custom span, Missed only and the search
/// are not, so the page never opens on a narrowing nobody remembers asking
/// for.
class CalendarOverviewPage extends StatefulWidget {
  /// Handed every store the page resolves into, so a budget test can ask
  /// which months it holds.
  final ValueChanged<AgendaMonthStore>? _onStore;

  static int _debugListedEntryVisits = 0;

  /// How many entries the list's row building has visited — each day's
  /// entries once per run that lists its month — so a test can pin that the
  /// runs of a long period visit each entry once, not once per run.
  @visibleForTesting
  static int get debugListedEntryVisits => _debugListedEntryVisits;

  @visibleForTesting
  static void resetDebugListedEntryVisits() => _debugListedEntryVisits = 0;

  const CalendarOverviewPage({super.key}) : _onStore = null;

  @visibleForTesting
  const CalendarOverviewPage.forTesting({
    super.key,
    ValueChanged<AgendaMonthStore>? onStore,
  }) : _onStore = onStore;

  @override
  State<CalendarOverviewPage> createState() => _CalendarOverviewPageState();
}

class _CalendarOverviewPageState extends _OverviewState
    with
        _OverviewQueries,
        _OverviewYears,
        _OverviewRowActions,
        _OverviewListScroll,
        _OverviewNavigation,
        _OverviewControls,
        _OverviewLoading,
        _OverviewData,
        _OverviewChrome,
        _OverviewBody {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = EventAgenda.dateOnly(DateTime.now());
    _year = _today.year;
    _years = _scrollYears = (first: _year, last: _year);
    _month = AgendaMonthStore.monthOf(_today);
    _period = _home = OverviewPeriod.thisYear(today: _today);
    _listScroll.addListener(_updatePinned);
    final bloc = context.read<CalendarBloc>();
    if (bloc.isStale) bloc.add(const LoadCalendarEvents());
    unawaited(_loadSettings());
    unawaited(_loadViews());
    // The alarm page's Keep, as the calendar page hears it: this page reads
    // the same bloc, and may be the only one open when Keep is pressed.
    AlertKeepNotice.instance.addListener(_serveKeepNotice);
    if (AlertKeepNotice.instance.hasPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _serveKeepNotice();
      });
    }
    // A digest's tap collapses onto a live overview rather than pushing a
    // second one, so its look arrives through the notifier; a pushed page
    // finds it waiting, and serves it once its settings are in.
    AppNavigator.pendingOverviewLook.addListener(_serveOverviewLook);
    if (AppNavigator.pendingOverviewLook.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _serveOverviewLook();
      });
    }
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
    final l10n = AppLocalizations.of(context)!;
    final localeChanged = _l10n?.localeName != l10n.localeName;
    _l10n = l10n;
    var rebuild = false;
    if (_events == null) {
      _take(context.read<CalendarBloc>().state);
      rebuild = true;
    }
    if (localeChanged || _refreshCategoryLabels()) {
      _storeStale = true;
      rebuild = true;
    }
    if (rebuild) _rebuild(duringBuild: true);
  }

  @override
  void dispose() {
    _resolveGeneration++;
    AlertKeepNotice.instance.removeListener(_serveKeepNotice);
    AppNavigator.pendingOverviewLook.removeListener(_serveOverviewLook);
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _monthScroll.dispose();
    _listScroll.dispose();
    _pinned.dispose();
    _yearScroll.dispose();
    _yearTiles.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _covered) return;
    if (_refreshToday()) {
      _storeStale = true;
      _rebuild();
    }
  }

  /// Nothing resolved underneath is seen until the return, which resolves
  /// anew anyway: a typed query's debounce is dropped here, and the query is
  /// applied on the way back; the list's runs and the year runs pause until
  /// then.
  @override
  void didPushNext() {
    _covered = true;
    _searchDebounce?.cancel();
  }

  @override
  void didPopNext() {
    _covered = false;
    if (_mode == AgendaDayListMode.list && _listResolving) _scheduleListRun();
    _scheduleYearRun();
    unawaited(_resumeUncovered());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final appBar = AppBar(
      titleSpacing: CalendarViewMenu.titleSpacing,
      excludeHeaderSemantics: true,
      title: CalendarViewMenu(
        page: CalendarViewPage.overview,
        onPageSelected: (page) => switch (page) {
          // The report opens on what this page shows, for the visit (D35):
          // Month mode hands its month, not its year (D36.8).
          CalendarViewPage.report => AppNavigator.switchToCalendarReport(
            context,
            look: (
              period: _mode == AgendaDayListMode.month
                  ? OverviewMonthPeriod(_month.year, _month.month)
                  : _shownPeriod,
              categoryIds: _categoryIds,
            ),
          ),
          _ => AppNavigator.switchToCalendar(context),
        },
      ),
      toolbarHeight: AppBarMetrics.toolbarHeight,
      // The leading glyph and the actions take their size and colour from
      // here, `onSurface` as the browser's bars draw them.
      iconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      actionsIconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      // The page's ground, as the browser's bars: a `surface` bar over it is
      // a white band in the light theme.
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actions: [
        _buildOptionsButton(l10n),
        _buildViewsButton(l10n),
        CalendarOverflowMenu(
          onAlerts: () => AppNavigator.toAlertsFromCalendar(context),
          onCategories: () => AppNavigator.toCalendarCategories(context),
          onExport: (_events?.isNotEmpty ?? false) ? _exportEvents : null,
          onGuide: () => AppNavigator.toCalendarGuide(context),
          onSettings: _openSettings,
        ),
      ],
    );
    final chips = _buildModeChips(l10n);
    final band = _buildBand(l10n);
    final body = Expanded(
      child: AnimatedSwitcher(
        duration: OverviewListMetrics.modeSwitchDuration,
        child: KeyedSubtree(
          key: ValueKey(_mode),
          child: _buildBody(l10n, colorScheme),
        ),
      ),
    );
    return MultiBlocListener(
      listeners: [
        BlocListener<CalendarBloc, CalendarPageState>(
          listenWhen: _listenWhen,
          listener: (_, state) => _onStateChanged(state),
        ),
        BlocListener<ImportExportBloc, ImportExportState>(
          listener: _export.onState,
        ),
      ],
      // The chips yield to the keyboard: on a small phone at a large text
      // scale the chips, the Search row and the keyboard together leave the
      // list no height. They fold over the keyboard's first
      // [_chipRowHeight] of travel, frame by frame as the calendar's grid
      // does, so the rows below follow the keyboard rather than jump. The
      // inset is read above the scaffold, which takes it out of its body, and
      // in a builder of its own, so a keyboard frame rebuilds the scaffold
      // and none of the parts built above. Only the page's own keyboard
      // folds them: one raised by a sheet over the page (the editor a row's
      // trip opens) leaves the row whole behind it. A steady small inset — a
      // floating keyboard's strip — half-folds the row by design.
      child: Builder(
        builder: (context) {
          final inset = MediaQuery.viewInsetsOf(context).bottom;
          final current = ModalRoute.of(context)?.isCurrent ?? true;
          final factor = current
              ? 1 - (inset / _chipRowHeight).clamp(0.0, 1.0)
              : 1.0;
          return PopScope(
            canPop: !_backIsHandled,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _onBackIntercepted();
            },
            child: Scaffold(
              // The language's ground, which the rows' groups are drawn
              // against.
              backgroundColor: colorScheme.pageGround,
              appBar: appBar,
              body: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Folded away, the chips leave semantics and hit testing,
                    // so a flow's wait for a chip holds until the keyboard is
                    // down.
                    Visibility(
                      visible: factor > 0,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: factor,
                          child: chips,
                        ),
                      ),
                    ),
                    if (_searchOpen) ...[
                      _buildSearchGroup(l10n),
                      const SizedBox(height: FormMetrics.bodyTop),
                    ],
                    // The period band folds with the chips: at 200 % on a
                    // small phone the nav's two-line title and the totals'
                    // line alone are taller than what the keyboard
                    // leaves the list, and while a query is typed the list's
                    // rows are what is read.
                    if (band != null)
                      Visibility(
                        visible: factor > 0,
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: factor,
                            child: band,
                          ),
                        ),
                      ),
                    body,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
