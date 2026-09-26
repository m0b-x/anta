import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../services/agenda_search_text.dart';
import '../services/app_navigator.dart';
import '../services/settings_service.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/agenda_month_store.dart';
import '../utils/event_agenda.dart';
import '../utils/event_search_query.dart';
import '../widgets/agenda_day_list_rows.dart';
import '../widgets/agenda_list_view.dart';
import '../widgets/agenda_month_grid.dart';
import '../widgets/agenda_period_nav.dart';
import '../widgets/agenda_year_grid.dart';
import '../widgets/agenda_year_pager.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/month_year_picker_sheet.dart';

/// Opens the calendar on one occurrence. A seam so a widget test can watch a
/// row tap without a navigator key.
typedef OverviewOccurrenceOpener = void Function(DateTime day, String eventId);

/// The calendar overview: every event of the chosen categories across one
/// calendar year, as a year of dot-matrix tiles, a month grid or a dated list
/// — the agenda drill-down's presentations, standalone.
///
/// Independent of the calendar page on purpose: it has no window, no anchor
/// and no selected day, so a year is always a whole year. Years are pages —
/// swiped, paged with chevrons, or jumped to through the period title's
/// picker — and only the years the chosen events can be in are pages at all,
/// so nobody scrolls through empty decades. It owns no data either. Events
/// come from the app-wide `CalendarBloc`, whose loaded state is also what
/// guarantees the category and presence facades the rows read are
/// configured; every row tap leads back to the calendar, where the occurrence
/// is shown and edited. The category allowlist (empty = all, the agenda's
/// convention) and the presentation are persisted; the year and the search
/// are not, so the page opens on this year with nothing filtered away.
class CalendarOverviewPage extends StatefulWidget {
  final OverviewOccurrenceOpener? _openOccurrence;

  const CalendarOverviewPage({super.key}) : _openOccurrence = null;

  @visibleForTesting
  const CalendarOverviewPage.forTesting({
    super.key,
    required OverviewOccurrenceOpener openOccurrence,
  }) : _openOccurrence = openOccurrence;

  @override
  State<CalendarOverviewPage> createState() => _CalendarOverviewPageState();
}

class _CalendarOverviewPageState extends State<CalendarOverviewPage>
    with RouteAware {
  static const Duration _searchDebounceDelay = Duration(milliseconds: 200);
  static const Duration _pageDuration = Duration(milliseconds: 260);
  static const Duration _prewarmDelay = Duration(milliseconds: 250);
  static const Duration _modeSwitchDuration = Duration(milliseconds: 150);

  static final DateTime _firstMonth = AgendaMonthStore.monthOf(
    CalendarBounds.earliest,
  );
  static final DateTime _lastMonth = AgendaMonthStore.monthOf(
    CalendarBounds.latest,
  );

  CalendarAppearance _appearance = const CalendarAppearance();
  Set<String> _categoryIds = const {};
  AgendaDayListMode _mode = AgendaDayListMode.year;
  bool _hapticFeedback = false;
  bool _settingsLoaded = false;

  late final DateTime _today;
  late int _year;
  late DateTime _month;
  DateTime? _selectedDay;

  /// The years the chosen events can be in — the pager's pages and the
  /// chevrons' stops. Always holds today's year.
  AgendaYearBounds _years = (first: 0, last: 0);
  PageController? _yearPager;
  final Map<int, List<AgendaYearTile>> _tilesByYear = {};
  DateTime? _highlightMonth;
  int _highlightToken = 0;
  Timer? _prewarm;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _monthScroll = ScrollController();
  Timer? _searchDebounce;
  EventSearchQuery _query = EventSearchQuery.empty;

  List<CalendarEvent>? _events;

  AppLocalizations? _l10n;
  Map<String, String> _categoryLabels = const {};
  int? _categoryRevision;

  /// Rebuilt whenever an input of the resolvers changes; null until both the
  /// settings and the event list have arrived.
  AgendaMonthStore? _store;

  List<AgendaDayListRow> _rows = const [];
  AgendaDayListMonth? _monthBucket;
  int _yearKept = 0;
  int _yearMissed = 0;

  bool _pickerOpen = false;

  /// A row tap pushes the calendar over this page, and every edit made there
  /// emits. Resolving a whole year for each one underneath would be pure
  /// waste, so the state is parked while covered and adopted on return.
  PageRoute<dynamic>? _route;
  bool _covered = false;
  CalendarPageState? _pendingState;

  @override
  void initState() {
    super.initState();
    _today = EventAgenda.dateOnly(DateTime.now());
    _year = _today.year;
    _years = (first: _year, last: _year);
    _month = AgendaMonthStore.monthOf(_today);
    final bloc = context.read<CalendarBloc>();
    if (bloc.isStale) bloc.add(const LoadCalendarEvents());
    unawaited(_loadSettings());
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
    if (_events == null) _adopt(context.read<CalendarBloc>().state);
    if (localeChanged || _refreshCategoryLabels()) _rebuild();
  }

  @override
  void dispose() {
    if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
    _prewarm?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _monthScroll.dispose();
    _yearPager?.dispose();
    super.dispose();
  }

  @override
  void didPushNext() => _covered = true;

  @override
  void didPopNext() {
    _covered = false;
    final pending = _pendingState;
    if (pending == null) return;
    _pendingState = null;
    _adopt(pending);
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final loaded = await settings.getCalendarOverviewSettings();
    if (!mounted) return;
    _appearance = loaded.appearance;
    _categoryIds = loaded.categoryIds;
    _mode = loaded.mode;
    _hapticFeedback = loaded.hapticFeedback;
    _settingsLoaded = true;
    _rebuild();
  }

  /// Localized category labels for the search, re-resolved when the catalog
  /// or the locale moves.
  bool _refreshCategoryLabels() {
    final l10n = _l10n;
    if (l10n == null) return false;
    final revision = CalendarCategories.revision;
    if (_categoryRevision == revision) return false;
    _categoryRevision = revision;
    _categoryLabels = {
      for (final category in CalendarCategories.visiblePlus(_categoryIds))
        category.id: CalendarCategories.labelOf(category, l10n),
    };
    return true;
  }

  /// The rows show no description and no alert, so `occurrenceRevision` —
  /// which counts those — is deliberately not an input; presence has its own.
  bool _listenWhen(CalendarPageState previous, CalendarPageState current) {
    if (current is! CalendarPageLoaded) return previous is CalendarPageLoaded;
    if (previous is! CalendarPageLoaded) return true;
    return !identical(previous.allEvents, current.allEvents) ||
        previous.membershipRevision != current.membershipRevision ||
        previous.presenceRevision != current.presenceRevision;
  }

  void _onStateChanged(CalendarPageState state) {
    if (_covered) {
      _pendingState = state;
      return;
    }
    _adopt(state);
  }

  /// Takes the event list from a bloc state. A revision bump arrives as a
  /// fresh state with the same list, so the listener's test above decides
  /// when this runs and the store is simply rebuilt from the facades.
  void _adopt(CalendarPageState state) {
    _events = state is CalendarPageLoaded ? state.allEvents : null;
    _refreshCategoryLabels();
    _rebuild();
  }

  /// Drops every resolved month, re-derives the year bounds and resolves what
  /// the current presentation shows, then repaints. Every input of the
  /// resolvers funnels through here: the events and their revisions, the
  /// categories, the query, the locale, the appearance.
  void _rebuild() {
    final events = _events;
    _tilesByYear.clear();
    if (events == null || !_settingsLoaded || _l10n == null) {
      _store = null;
      _rows = const [];
      _monthBucket = null;
      if (mounted) setState(() {});
      return;
    }
    final years = EventAgenda.yearBoundsOf(
      events,
      categoryIds: _categoryIds,
      todayYear: _today.year,
      earliestYear: CalendarBounds.earliest.year,
      latestYear: CalendarBounds.latest.year,
    );
    _years = years;
    _year = _year.clamp(years.first, years.last);
    _syncPager();
    _store = AgendaMonthStore(
      resolve: _resolve,
      resolveMarks: _resolveMarks,
      maxBars: AgendaMonthGrid.maxBarsFor(_appearance),
    );
    if (mounted) setState(_recompute);
    _schedulePrewarm();
  }

  /// A pager whose first page is the current bounds' first year and whose
  /// starting page is the shown year. Recreated only while no page view holds
  /// it — an attached controller pages by itself.
  void _syncPager() {
    final pager = _yearPager;
    if (pager != null && pager.hasClients) return;
    pager?.dispose();
    _yearPager = PageController(
      initialPage: AgendaYearPager.indexOf(_year, _years.first),
    );
  }

  List<EventOccurrence> _scan(DateTime start, DateTime end) {
    final l10n = _l10n!;
    return EventAgenda.occurrencesInRange(
      events: _events!,
      from: start,
      to: end,
      query: _query,
      categoryLabels: _categoryLabels,
      labelTextOf: (event) => AgendaSearchText.forEventCached(event, l10n),
      categoryIds: _categoryIds,
    );
  }

  List<AgendaDayListEntry> _resolve(DateTime start, DateTime end) {
    return AgendaListView.eventDayEntries(
      _scan(start, end),
      _l10n!,
      null,
      showRecurrenceLabels: _appearance.showRecurrenceLabels,
      missedDisplay: _appearance.missedDisplay,
    );
  }

  List<AgendaDayMark> _resolveMarks(DateTime start, DateTime end) {
    return AgendaListView.eventDayMarks(
      _scan(start, end),
      missedDisplay: _appearance.missedDisplay,
    );
  }

  /// Resolves what the presentation shows and rebuilds its rows or tiles, so a
  /// frame folds nothing. Called inside `setState` on navigation only.
  void _recompute() {
    final store = _store;
    if (store == null) return;
    switch (_mode) {
      case AgendaDayListMode.year:
        _rows = const [];
        _monthBucket = null;
        _tallyYear(_year);
      case AgendaDayListMode.list:
        _monthBucket = null;
        final months = AgendaMonthStore.monthsOfYear(_year);
        store.ensure(months);
        final buckets = [for (final month in months) store.monthFor(month)];
        _tallyYear(_year);
        _rows = buildAgendaDayListRows(
          [for (final bucket in buckets) ...bucket.days],
          (day) => store.cached(day)!.entriesOn(day),
          groupByDay: true,
          withMonths: true,
          keptCountOf: (day) => store.cached(day)!.keptCountForDay(day),
        );
      case AgendaDayListMode.month:
        final bucket = store.monthFor(_month);
        _monthBucket = bucket;
        final selected = _selectedDay;
        _rows = buildAgendaDayListRows(
          selected != null ? [selected] : bucket.days,
          bucket.entriesOn,
          groupByDay: selected == null,
          withMonths: false,
          keptCountOf: bucket.keptCountForDay,
        );
    }
  }

  /// The year's tiles, folded from marks and kept for the pager: a page that
  /// slides in under a finger reads them without folding anything. Each day
  /// wears its top entry's colour, so several categories on one tile stay
  /// tellable apart.
  List<AgendaYearTile> _tilesFor(int year) {
    final cached = _tilesByYear[year];
    if (cached != null) return cached;
    final store = _store!;
    final months = AgendaMonthStore.monthsOfYear(year);
    store.ensureTallies(months);
    return _tilesByYear[year] = [
      for (final month in months)
        AgendaYearTile.ofTally(store.tallyFor(month), perDayColors: true),
    ];
  }

  void _tallyYear(int year) {
    var kept = 0;
    var missed = 0;
    for (final tile in _tilesFor(year)) {
      kept += tile.count;
      missed += tile.missedCount;
    }
    _yearKept = kept;
    _yearMissed = missed;
  }

  /// Warms the neighbouring years once the page has settled, so the next
  /// swipe or chevron finds its tiles ready. Cache-only work: nothing to
  /// repaint.
  void _schedulePrewarm() {
    _prewarm?.cancel();
    _prewarm = Timer(_prewarmDelay, () {
      if (!mounted || _store == null) return;
      if (_mode == AgendaDayListMode.month) return;
      for (final year in [_year - 1, _year + 1]) {
        if (year < _years.first || year > _years.last) continue;
        _tilesFor(year);
      }
    });
  }

  void _click() {
    if (_hapticFeedback) HapticFeedback.selectionClick();
  }

  void _selectMode(AgendaDayListMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _selectedDay = null;
      if (mode == AgendaDayListMode.month) {
        _month = _month.year == _year
            ? _month
            : DateTime.utc(_year, _today.year == _year ? _today.month : 1, 1);
      }
      if (mode == AgendaDayListMode.year) _syncPager();
      _recompute();
    });
    _schedulePrewarm();
    unawaited(_persistMode(mode));
  }

  Future<void> _persistMode(AgendaDayListMode mode) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewMode(mode);
  }

  /// A year the pager settled on — a swipe, or the end of an animated jump.
  void _onYearPaged(int year) {
    if (year == _year) return;
    setState(() {
      _year = year;
      _recompute();
    });
    _schedulePrewarm();
  }

  /// Animates the pager to [year] while it is on screen; otherwise the year
  /// simply changes and the pager starts there when it next appears.
  void _goToYear(int year) {
    final target = year.clamp(_years.first, _years.last);
    if (target == _year) return;
    _click();
    final pager = _yearPager;
    if (_mode == AgendaDayListMode.year && pager != null && pager.hasClients) {
      pager.animateToPage(
        AgendaYearPager.indexOf(target, _years.first),
        duration: _pageDuration,
        curve: Curves.easeOutCubic,
      );
    } else {
      _onYearPaged(target);
    }
  }

  /// The jump control behind every period title: a picked date lands the
  /// year pages on its year with its month flashed, the list on its year, or
  /// month mode on its month.
  Future<void> _pickDate() async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    try {
      final inMonthMode = _mode == AgendaDayListMode.month;
      final initial = inMonthMode
          ? _month
          : DateTime.utc(_year, _today.year == _year ? _today.month : 1, 1);
      final picked = await MonthYearPickerSheet.show(
        context,
        initialDate: initial,
        firstDate: inMonthMode
            ? CalendarBounds.earliest
            : DateTime.utc(_years.first, 1, 1),
        lastDate: inMonthMode
            ? CalendarBounds.latest
            : DateTime.utc(_years.last, 12, 31),
        accent: _appearance.accentOr(Theme.of(context).colorScheme.primary),
      );
      if (picked == null || !mounted) return;
      _click();
      if (inMonthMode) {
        _goToMonth(AgendaMonthStore.monthOf(picked));
        return;
      }
      setState(() {
        _highlightMonth = AgendaMonthStore.monthOf(picked);
        _highlightToken++;
      });
      _goToYear(picked.year);
    } finally {
      _pickerOpen = false;
    }
  }

  void _openMonth(DateTime month) {
    setState(() {
      _mode = AgendaDayListMode.month;
      _month = month;
      _year = month.year;
      _selectedDay = null;
      _recompute();
    });
  }

  void _goToMonth(DateTime month) {
    final order = AgendaMonthStore.monthOrder(month);
    if (order < AgendaMonthStore.monthOrder(_firstMonth) ||
        order > AgendaMonthStore.monthOrder(_lastMonth) ||
        order == AgendaMonthStore.monthOrder(_month)) {
      return;
    }
    setState(() {
      _month = month;
      _year = month.year.clamp(_years.first, _years.last);
      _selectedDay = null;
      _recompute();
    });
    _scrollMonthToTop();
  }

  void _toggleSelectedDay(DateTime day) {
    if ((_monthBucket?.countForDay(day) ?? 0) == 0) return;
    setState(() {
      _selectedDay = _selectedDay == day ? null : day;
      _recompute();
    });
    _scrollMonthToTop();
  }

  void _scrollMonthToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _monthScroll.hasClients) _monthScroll.jumpTo(0);
    });
  }

  void _onQueryChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () => _applyQuery(raw));
  }

  void _clearQuery() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _applyQuery('');
  }

  void _applyQuery(String raw) {
    if (!mounted) return;
    _query = EventSearchQuery.parse(raw, localeName: _l10n?.localeName ?? '');
    _rebuild();
  }

  /// The multi picker over the allowlist. An empty allowlist means every
  /// category, so it opens with every offered row ticked, and a result that
  /// covers every offered row collapses back to empty rather than freezing
  /// today's catalog into a list that silently excludes categories created
  /// later.
  Future<void> _pickCategories() async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    try {
      final offered = {
        for (final category in CalendarCategories.visiblePlus(_categoryIds))
          category.id,
      };
      final picked = await CategoryPickerSheet.pickMulti(
        context,
        selected: _categoryIds.isEmpty ? offered : _categoryIds,
      );
      if (picked == null || !mounted) return;
      final next = picked.containsAll(offered) ? const <String>{} : picked;
      if (setEquals(next, _categoryIds)) return;
      _categoryIds = next;
      _categoryRevision = null;
      _refreshCategoryLabels();
      _rebuild();
      final settings = await SettingsService.getInstance();
      await settings.setCalendarOverviewCategories(next);
    } finally {
      _pickerOpen = false;
    }
  }

  void _openOccurrence(AgendaDayListEntry entry) {
    final eventId = entry.eventId;
    if (eventId == null) return;
    final open = widget._openOccurrence;
    if (open != null) {
      open(entry.day, eventId);
      return;
    }
    unawaited(AppNavigator.toCalendarOccurrence(day: entry.day, eventId: eventId));
  }

  Color _tileColor(ColorScheme colorScheme) {
    if (_categoryIds.length == 1) {
      return CalendarCategories.resolve(_categoryIds.single).color;
    }
    return _appearance.accentOr(colorScheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return BlocListener<CalendarBloc, CalendarPageState>(
      listenWhen: _listenWhen,
      listener: (_, state) => _onStateChanged(state),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.calendarOverview),
          backgroundColor: colorScheme.surface,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSearchField(l10n, theme),
              _buildCategoryTile(),
              _buildModeSelector(l10n),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _modeSwitchDuration,
                  child: KeyedSubtree(
                    key: ValueKey(_mode),
                    child: _buildBody(l10n, theme, colorScheme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListenableBuilder(
        listenable: _searchController,
        builder: (context, _) => TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            hintText: l10n.upcomingSearchHint,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.upcomingClearSearch,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: _clearQuery,
                  ),
            border: const OutlineInputBorder(),
          ),
          onChanged: _onQueryChanged,
        ),
      ),
    );
  }

  Widget _buildCategoryTile() {
    final offered = CalendarCategories.visiblePlus(_categoryIds);
    final selected = <CalendarCategory>[
      for (final category in offered)
        if (_categoryIds.contains(category.id)) category,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CategoryFilterTile(
        offered: offered,
        selected: selected,
        selectsAll: _categoryIds.isEmpty,
        onTap: _pickCategories,
      ),
    );
  }

  Widget _buildModeSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SegmentedButton<AgendaDayListMode>(
        segments: [
          ButtonSegment<AgendaDayListMode>(
            value: AgendaDayListMode.year,
            icon: const Icon(Icons.grid_view_rounded),
            label: Text(
              l10n.dayListModeYear,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ButtonSegment<AgendaDayListMode>(
            value: AgendaDayListMode.month,
            icon: const Icon(Icons.calendar_view_month_rounded),
            label: Text(
              l10n.dayListModeMonth,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ButtonSegment<AgendaDayListMode>(
            value: AgendaDayListMode.list,
            icon: const Icon(Icons.format_list_bulleted_rounded),
            label: Text(
              l10n.dayListModeList,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => _selectMode(selection.first),
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // The scaffold already resizes for the keyboard, so the bodies carry no
    // inset of their own — and no inset frame rebuilds a year of tiles.
    const padding = EdgeInsets.fromLTRB(16, 0, 16, 16);
    switch (_mode) {
      case AgendaDayListMode.year:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildYearNav(l10n),
            Expanded(
              child: AgendaYearPager(
                controller: _yearPager!,
                firstYear: _years.first,
                lastYear: _years.last,
                tilesFor: _tilesFor,
                color: _tileColor(colorScheme),
                appearance: _appearance,
                today: _today,
                onOpenMonth: _openMonth,
                onYearChanged: _onYearPaged,
                padding: padding,
                highlightMonth: _highlightMonth,
                highlightToken: _highlightToken,
              ),
            ),
          ],
        );
      case AgendaDayListMode.list:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildYearNav(l10n),
            Expanded(
              child: _rows.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                      children: [
                        Text(
                          l10n.overviewEmptyYear(_year),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      itemCount: _rows.length,
                      itemBuilder: (context, index) => _buildRow(index),
                    ),
            ),
          ],
        );
      case AgendaDayListMode.month:
        final bucket = _monthBucket!;
        return CustomScrollView(
          controller: _monthScroll,
          slivers: [
            SliverToBoxAdapter(child: _buildMonthNav(l10n, bucket)),
            SliverToBoxAdapter(
              child: AgendaMonthGrid(
                month: _month,
                firstDay: _firstMonth,
                lastDay: DateTime.utc(_lastMonth.year, _lastMonth.month + 1, 0),
                today: _today,
                selectedDay: _selectedDay,
                appearance: _appearance,
                hasEntry: store.hasEntry,
                barsFor: (day) => store.barsFor(day)?[day.day],
                onDaySelected: _toggleSelectedDay,
                onPageChanged: _goToMonth,
              ),
            ),
            SliverToBoxAdapter(
              child: _buildSectionHeader(l10n, theme, colorScheme, bucket),
            ),
            if (_rows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    l10n.dayListEmptyMonth,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildRow(index),
                    childCount: _rows.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          ],
        );
    }
  }

  Widget _buildRow(int index) {
    return AgendaDayListRowView(
      rows: _rows,
      index: index,
      today: _today,
      onEntryTap: _openOccurrence,
    );
  }

  Widget _buildYearNav(AppLocalizations l10n) {
    return AgendaPeriodNav(
      title: '$_year',
      subtitle: agendaDayListCountLabel(l10n, _yearKept, _yearMissed),
      previousTooltip: l10n.datePickerPreviousYear,
      nextTooltip: l10n.datePickerNextYear,
      todayTooltip: l10n.dayListScopeThisYear,
      titleTooltip: l10n.monthYearPickerTitle,
      onTitleTap: _pickDate,
      onPrevious: _year > _years.first ? () => _goToYear(_year - 1) : null,
      onNext: _year < _years.last ? () => _goToYear(_year + 1) : null,
      onToday: _year == _today.year ? null : () => _goToYear(_today.year),
    );
  }

  Widget _buildMonthNav(AppLocalizations l10n, AgendaDayListMonth bucket) {
    final order = AgendaMonthStore.monthOrder(_month);
    final todayMonth = AgendaMonthStore.monthOf(_today);
    return AgendaPeriodNav(
      title: AgendaListView.monthLabel(l10n.localeName, _month, withYear: true),
      subtitle: agendaDayListCountLabel(
        l10n,
        bucket.keptCount,
        bucket.count - bucket.keptCount,
      ),
      previousTooltip: l10n.dayListPreviousMonth,
      nextTooltip: l10n.dayListNextMonth,
      todayTooltip: l10n.dayListJumpToToday,
      titleTooltip: l10n.monthYearPickerTitle,
      onTitleTap: _pickDate,
      onPrevious: order > AgendaMonthStore.monthOrder(_firstMonth)
          ? () => _goToMonth(DateTime.utc(_month.year, _month.month - 1, 1))
          : null,
      onNext: order < AgendaMonthStore.monthOrder(_lastMonth)
          ? () => _goToMonth(DateTime.utc(_month.year, _month.month + 1, 1))
          : null,
      onToday: order == AgendaMonthStore.monthOrder(todayMonth)
          ? null
          : () => _goToMonth(todayMonth),
    );
  }

  Widget _buildSectionHeader(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
    AgendaDayListMonth bucket,
  ) {
    final selected = _selectedDay;
    final label = selected == null
        ? AgendaListView.monthLabel(l10n.localeName, _month, withYear: false)
        : AgendaListView.dayHeaderLabel(l10n, selected, _today);
    final total = selected == null ? bucket.count : bucket.countForDay(selected);
    final kept = selected == null
        ? bucket.keptCount
        : bucket.keptCountForDay(selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              agendaDayListCountLabel(l10n, kept, total - kept),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 4),
            Visibility(
              visible: selected != null,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(
                onPressed: selected == null
                    ? null
                    : () => _toggleSelectedDay(selected),
                child: Text(l10n.dayListWholeMonth),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
