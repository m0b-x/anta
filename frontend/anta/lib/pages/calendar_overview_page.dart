import 'dart:async';

import 'package:flutter/foundation.dart'
    show precisionErrorTolerance, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_state.dart';
import '../controllers/calendar_export_controller.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../constants/overview_list_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/agenda_day_list_mode.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/date_range.dart';
import '../models/day_bar.dart';
import '../models/overview_list_options.dart';
import '../models/overview_period.dart';
import '../services/agenda_search_text.dart';
import '../services/app_navigator.dart';
import '../services/settings_service.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/agenda_month_store.dart';
import '../utils/calendar_filter_summary.dart';
import '../utils/event_agenda.dart';
import '../utils/event_query_matcher.dart';
import '../utils/event_search_query.dart';
import '../widgets/agenda_day_list_rows.dart';
import '../widgets/agenda_list_view.dart';
import '../widgets/agenda_month_grid.dart';
import '../widgets/agenda_period_nav.dart';
import '../widgets/agenda_year_grid.dart';
import '../widgets/agenda_year_pager.dart';
import '../widgets/automation_id.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/calendar_header_menus.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/form_rows.dart';
import '../widgets/list_scrubber.dart';
import '../widgets/month_year_picker_sheet.dart';
import '../widgets/overview_options_sheet.dart';

/// Opens the calendar on one occurrence. A seam so a widget test can watch a
/// row tap without a navigator key.
typedef OverviewOccurrenceOpener = void Function(DateTime day, String eventId);

/// The calendar overview: every event of the chosen categories as a year of
/// dot-matrix tiles, a month grid or a dated list over a period — the agenda
/// drill-down's presentations, standalone.
///
/// Independent of the calendar page on purpose: it has no window, no anchor
/// and no selected day, so a year is always a whole year. Years are pages —
/// swiped, paged with chevrons, or jumped to through the period title's
/// picker — and only the years the chosen events can be in are pages at all,
/// so nobody scrolls through empty decades. The list shows a period instead —
/// a year, a span ending today, or one picked in the Dates sheet. It owns no
/// data either. Events come from the app-wide `CalendarBloc`, whose loaded
/// state is also what guarantees the category and presence facades the rows
/// read are configured; every row tap leads to the calendar, where the
/// occurrence is shown and edited. The category allowlist (empty = all, the
/// agenda's convention), the presentation, a preset period and the list's
/// order and rows are persisted; a custom span, Missed only and the search
/// are not, so the page never opens on a narrowing nobody remembers asking
/// for.
class CalendarOverviewPage extends StatefulWidget {
  final OverviewOccurrenceOpener? _openOccurrence;

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

  const CalendarOverviewPage({super.key})
    : _openOccurrence = null,
      _onStore = null;

  @visibleForTesting
  const CalendarOverviewPage.forTesting({
    super.key,
    required OverviewOccurrenceOpener openOccurrence,
    ValueChanged<AgendaMonthStore>? onStore,
  }) : _openOccurrence = openOccurrence,
       _onStore = onStore;

  @override
  State<CalendarOverviewPage> createState() => _CalendarOverviewPageState();
}

class _CalendarOverviewPageState extends State<CalendarOverviewPage>
    with RouteAware, WidgetsBindingObserver {
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

  /// Re-read on every return and resume: a page left open overnight would
  /// otherwise keep yesterday's Today header, rolling spans and bounds.
  late DateTime _today;

  /// Year mode's year. Paging it, a tile tap and the month nav also make it
  /// the list's [_period], so the two modes share one notion of "the year".
  late int _year;
  late DateTime _month;
  DateTime? _selectedDay;

  /// The list's unit. Kept across mode switches, so a span picked in the list
  /// survives a look at the year tiles.
  late OverviewPeriod _period;

  /// Set when the persisted period is not a year: year mode opens on the
  /// period's first year, as a switch into it does, once the year bounds the
  /// events give are known (review 7).
  bool _yearFromPeriod = false;
  OverviewListOptions _options = OverviewListOptions.defaults;

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
  final ScrollController _listScroll = ScrollController();
  Timer? _searchDebounce;
  EventSearchQuery _query = EventSearchQuery.empty;

  /// Typed text whose debounce has not run yet. Covering the page cancels the
  /// debounce, so the return applies it instead.
  String? _unappliedQuery;

  List<CalendarEvent>? _events;

  /// The loaded events by id: the query's post-filter asks the matcher about
  /// an entry's event.
  Map<String, CalendarEvent> _eventsById = const {};

  /// What of the last adopted state the store was resolved from. A state
  /// that differs in nothing here — an `occurrenceRevision` bump under a live
  /// query — only refilters.
  (List<CalendarEvent>?, int, int)? _adoptedInputs;

  AppLocalizations? _l10n;
  Map<String, String> _categoryLabels = const {};
  int? _categoryRevision;

  /// Rebuilt whenever an input of the resolvers changes; null until both the
  /// settings and the event list have arrived. Query-free (T3): the query is
  /// a post-filter, so typing never resolves a month again.
  AgendaMonthStore? _store;

  /// Set by every input of the resolvers — the events and their revisions,
  /// the categories, the locale, the appearance, the day — and cleared when
  /// [_rebuild] resolves a new store. A query change leaves it alone.
  bool _storeStale = true;

  /// The query as a post-filter over the store's entries; null while the
  /// search is empty. A new one per [_rebuild]: its memo reads the
  /// descriptions, which an `occurrenceRevision` bump may have changed.
  EventQueryMatcher? _matcher;

  /// The store's months narrowed to [_matcher] and, in month mode, their day
  /// bars — folded once per matcher, on navigation, as the store folds its
  /// own.
  final Map<int, AgendaDayListMonth> _filteredMonths = {};
  final Map<int, Map<int, List<DayBar>>> _filteredBars = {};

  /// Every row kind's height for the inputs that size them (T4); null until
  /// [_RowExtentProbe] has first measured them, and the list is not built
  /// until then, so no row is ever laid out in a slot that is too small.
  _RowExtents? _extents;

  /// What [_extents] were measured for — the text scale, the locale and the
  /// list's width; the theme sizes nothing, and the period nothing either
  /// (a day header is templated with its year). When one moves the list
  /// stays on its old extents, its rows clipped to them, until the probe
  /// reports — no spinner, no lost place.
  (TextScaler, String, double)? _extentsInputs;
  bool _extentsStale = true;

  /// Where the list was when its extents went stale, aimed at once the new
  /// ones are in — unless a landing asked for somewhere else meanwhile.
  double? Function(_ListLayout layout)? _staleAnchor;

  /// The offsets of [_rows] under [_extents], rebuilt when either changes.
  _ListLayout? _layout;

  /// Where the list goes once rows just recomputed are laid out: the anchor
  /// a rebuild noted, or the landing a period, query or order change asks
  /// for (D7). Read when the frame is done, so the last one asked wins.
  double? Function(_ListLayout layout)? _listTarget;

  /// The section row whose label is pinned above the list — the month, or
  /// the category group, under the list's top edge once its own label has
  /// scrolled past it; null leaves the slot empty.
  final ValueNotifier<AgendaDayListRow?> _pinned = ValueNotifier(null);

  List<AgendaDayListRow> _rows = const [];

  /// The rows [_rows] extend when the last run appended to them, so the
  /// layout of these extends rather than being summed again; null after any
  /// other change of the rows.
  List<AgendaDayListRow>? _rowsBase;

  /// Every entry listed so far, kept under One per event only: a run folds
  /// them all again.
  List<AgendaDayListEntry> _listedEntries = [];
  AgendaDayListMonth? _monthBucket;
  int _yearKept = 0;
  int _yearMissed = 0;

  /// The list's entries after every filter, for the count caption.
  int _listedKept = 0;
  int _listedMissed = 0;

  /// Whether the list's period crosses New Year, which names the year in
  /// its month and day headers.
  bool _spanCrossesYear = false;

  /// The list's period and its months in reading order — ascending, or
  /// descending under Newest first — of which the first [_listedMonthCount]
  /// are listed. Only [OverviewListMetrics.syncMonths] of them resolve with
  /// the frame that asks; the rest follow one run per event-loop turn
  /// (§3.8 item 3), so a decade never blocks a frame.
  DateRange? _listSpan;
  List<DateTime> _listMonths = const [];
  int _listedMonthCount = 0;

  /// Whether the listed entries reached [OverviewListMetrics.maxEntries]:
  /// nothing past them is listed or resolved (T5).
  bool _listCapped = false;

  /// Bumped by every recompute and by dispose. A run scheduled under an
  /// older value belongs to inputs that are gone and returns untouched.
  int _resolveGeneration = 0;

  /// Set until the list first shows after the page opens, which lands per
  /// D7 as a period change does — "This year" opened in October shows
  /// October, not January.
  bool _landOnOpen = true;

  bool _pickerOpen = false;

  /// The ⋮ menu's `.ics` export, answered only when this page started it —
  /// the calendar beneath answers for its own.
  final CalendarExportController _export = CalendarExportController();

  /// A row tap pushes the calendar over this page, and every edit made there
  /// emits. Resolving a whole period for each one underneath would be pure
  /// waste, so the state is parked while covered and adopted on return.
  PageRoute<dynamic>? _route;
  bool _covered = false;
  CalendarPageState? _pendingState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = EventAgenda.dateOnly(DateTime.now());
    _year = _today.year;
    _years = (first: _year, last: _year);
    _month = AgendaMonthStore.monthOf(_today);
    _period = OverviewPeriod.thisYear(today: _today);
    _listScroll.addListener(_updatePinned);
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
    if (localeChanged || _refreshCategoryLabels()) {
      _storeStale = true;
      _rebuild();
    }
  }

  @override
  void dispose() {
    _resolveGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) AppNavigator.routeObserver.unsubscribe(this);
    _prewarm?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _monthScroll.dispose();
    _listScroll.dispose();
    _pinned.dispose();
    _yearPager?.dispose();
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
  /// anew anyway: the prewarm and a typed query's debounce are dropped here,
  /// and the query is applied on the way back; the list's runs pause until
  /// then.
  @override
  void didPushNext() {
    _covered = true;
    _prewarm?.cancel();
    _searchDebounce?.cancel();
  }

  @override
  void didPopNext() {
    _covered = false;
    if (_mode == AgendaDayListMode.list && _listResolving) _scheduleListRun();
    unawaited(_resumeUncovered());
  }

  /// Whether the wall clock has moved [_today] to another day. Across New
  /// Year, This year moves on with it — the period and the year it opens
  /// year mode on — except in year mode, whose pager holds the year shown.
  bool _refreshToday() {
    final today = EventAgenda.dateOnly(DateTime.now());
    if (today == _today) return false;
    final before = _today;
    _today = today;
    if (_mode != AgendaDayListMode.year) {
      final period = _period.followingToday(before: before, today: today);
      if (period != _period) {
        _period = period;
        _year = _firstYearOf(period);
      }
    }
    return true;
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final loaded = await settings.getCalendarOverviewSettings(today: _today);
    if (!mounted) return;
    _appearance = loaded.appearance;
    _categoryIds = loaded.categoryIds;
    _mode = loaded.mode;
    _period = loaded.period;
    if (loaded.period case OverviewYearPeriod(:final year)) {
      _year = year;
    } else {
      _yearFromPeriod = true;
    }
    _options = loaded.listOptions;
    _hapticFeedback = loaded.hapticFeedback;
    _settingsLoaded = true;
    _storeStale = true;
    _rebuild();
  }

  /// Catches up with everything that moved while a page covered this one, in
  /// one rebuild: the bloc state parked meanwhile, the appearance — the
  /// calendar's settings are one ⋮ away, from here or from a calendar pushed
  /// over this page — the day, and a query typed just before the cover.
  ///
  /// The allowlist, the mode and the period are left alone. Only this page
  /// writes them, and a month drilled into from a year tile is not persisted,
  /// so reading the mode back would throw the user out of it.
  Future<void> _resumeUncovered() async {
    final settings = await SettingsService.getInstance();
    final loaded = await settings.getCalendarOverviewSettings(today: _today);
    if (!mounted || _covered) return;
    if (_refreshToday()) _storeStale = true;
    if (_settingsLoaded) {
      _hapticFeedback = loaded.hapticFeedback;
      if (loaded.appearance != _appearance) {
        _appearance = loaded.appearance;
        _storeStale = true;
      }
    }
    final pending = _pendingState;
    var changed = _storeStale;
    if (pending != null) {
      _pendingState = null;
      _take(pending);
      changed = true;
    }
    final raw = _unappliedQuery;
    if (raw != null) _setQuery(raw);
    if (changed || raw != null) {
      _rebuild();
    } else {
      _schedulePrewarm();
    }
    if (raw != null) _land();
  }

  /// The ⋮ menu's Calendar settings. Settings → Categories can delete a
  /// category, which reassigns its events behind the service's cache without
  /// bumping a revision, so the events are reloaded after the trip — as the
  /// calendar does after its own.
  Future<void> _openSettings() async {
    final bloc = context.read<CalendarBloc>();
    await AppNavigator.toCalendarSettings(context);
    if (!mounted) return;
    bloc.add(const LoadCalendarEvents());
  }

  void _exportEvents() {
    final state = context.read<CalendarBloc>().state;
    if (state is! CalendarPageLoaded) return;
    _export.start(context, state.allEvents);
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
  /// which counts those — is an input only while a query is live: a day's
  /// match reads its description; presence has its own revision.
  bool _listenWhen(CalendarPageState previous, CalendarPageState current) {
    if (current is! CalendarPageLoaded) return previous is CalendarPageLoaded;
    if (previous is! CalendarPageLoaded) return true;
    return !identical(previous.allEvents, current.allEvents) ||
        previous.membershipRevision != current.membershipRevision ||
        previous.presenceRevision != current.presenceRevision ||
        (_query.isNotEmpty &&
            previous.occurrenceRevision != current.occurrenceRevision);
  }

  void _onStateChanged(CalendarPageState state) {
    if (_covered) {
      _pendingState = state;
      return;
    }
    // A return still reading the settings must not adopt the older state it
    // parked over this one.
    _pendingState = null;
    _adopt(state);
  }

  /// Takes the event list from a bloc state and repaints.
  void _adopt(CalendarPageState state) {
    _take(state);
    _rebuild();
  }

  /// A revision bump arrives as a fresh state with the same list, so the
  /// listener's test above decides when this runs; the store is resolved
  /// again only when the list or a revision its rows read moved.
  void _take(CalendarPageState state) {
    final loaded = state is CalendarPageLoaded ? state : null;
    _events = loaded?.allEvents;
    final inputs = (
      loaded?.allEvents,
      loaded?.membershipRevision ?? 0,
      loaded?.presenceRevision ?? 0,
    );
    if (inputs != _adoptedInputs) {
      _adoptedInputs = inputs;
      _storeStale = true;
    }
    if (_refreshCategoryLabels()) _storeStale = true;
  }

  /// Resolves what the current presentation shows through the query, then
  /// repaints — and, while the list shows, keeps it on the row it was on.
  /// Every input funnels through here: the events and their revisions, the
  /// categories, the query, the locale, the appearance. Those that feed the
  /// resolvers set [_storeStale] first, and only then is every resolved
  /// month dropped and the year bounds re-derived; a query alone keeps the
  /// store and refilters what it holds (T3).
  void _rebuild() {
    final events = _events;
    final l10n = _l10n;
    _tilesByYear.clear();
    _filteredMonths.clear();
    _filteredBars.clear();
    if (events == null || !_settingsLoaded || l10n == null) {
      _resolveGeneration++;
      _store = null;
      _storeStale = true;
      _rows = const [];
      _monthBucket = null;
      if (mounted) setState(() {});
      return;
    }
    final anchor = _anchorOfList();
    _matcher = _query.isEmpty
        ? null
        : EventQueryMatcher(
            query: _query,
            categoryLabels: _categoryLabels,
            labelTextOf: (event) =>
                AgendaSearchText.forEventCached(event, l10n),
          );
    if (_storeStale || _store == null) {
      _storeStale = false;
      _eventsById = {for (final event in events) event.id: event};
      final years = EventAgenda.yearBoundsOf(
        events,
        categoryIds: _categoryIds,
        todayYear: _today.year,
        earliestYear: CalendarBounds.earliest.year,
        latestYear: CalendarBounds.latest.year,
      );
      _years = years;
      if (_yearFromPeriod) {
        _yearFromPeriod = false;
        _year = _firstYearOf(_period);
      } else {
        _year = _year.clamp(years.first, years.last);
      }
      _syncPager();
      final store = _store = AgendaMonthStore(
        resolve: _resolve,
        resolveMarks: _resolveMarks,
        maxBars: AgendaMonthGrid.maxBarsFor(_appearance),
      );
      widget._onStore?.call(store);
    }
    if (mounted) setState(_recompute);
    _schedulePrewarm();
    final landing = _landOnOpen;
    _landOnOpen = false;
    if (landing && _mode == AgendaDayListMode.list) {
      _land();
    } else if (anchor != null) {
      _aimList(anchor);
    }
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

  /// The allowlist narrows the expansion itself and changes rarely, so it
  /// stays an input of the scan; the query is applied after it (T3).
  List<EventOccurrence> _scan(DateTime start, DateTime end) {
    return EventAgenda.occurrencesInRange(
      events: _events!,
      from: start,
      to: end,
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
    _resolveGeneration++;
    _rowsBase = null;
    final store = _store;
    if (store == null) return;
    switch (_mode) {
      case AgendaDayListMode.year:
        _rows = const [];
        _monthBucket = null;
        _tallyYear(_year);
      case AgendaDayListMode.list:
        _monthBucket = null;
        final span = _period.resolve(today: _today, yearBounds: _years);
        final months = _monthsOf(span);
        _listSpan = span;
        _spanCrossesYear = span.start.year != span.end.year;
        _listMonths = _options.order == OverviewOrder.newestFirst
            ? months.reversed.toList()
            : months;
        _listedMonthCount = 0;
        _listMore(OverviewListMetrics.syncMonths);
      case AgendaDayListMode.month:
        final bucket = _bucketOf(_month);
        if (_matcher != null) {
          _filteredBars[AgendaMonthStore.keyOf(_month)] ??=
              AgendaMonthStore.buildBars(bucket, maxBars: store.maxBars);
        }
        _monthBucket = bucket;
        final selected = _selectedDay;
        _rows = buildAgendaDayListRows(
          selected != null ? [selected] : bucket.days,
          (day) => _listed(bucket.entriesOn(day)),
          groupByDay: selected == null,
          withMonths: false,
          keptCountOf: _options.missedOnly ? (_) => 0 : bucket.keptCountForDay,
        );
    }
  }

  /// Whether months of the list are still to come: neither all listed nor
  /// stopped by the cap.
  bool get _listResolving =>
      !_listCapped && _listedMonthCount < _listMonths.length;

  /// What closes the list after its last row, if anything does.
  _ListTail? get _listTail => _listCapped
      ? _ListTail.capped
      : _listResolving
      ? _ListTail.loading
      : null;

  /// Lists [count] more of [_listMonths] — and every month right after them
  /// the store already holds, which costs no scan, so a query or an option
  /// over a period resolved before relists it whole — and schedules the
  /// next run while months are left.
  void _listMore(int count) {
    final store = _store!;
    var end = _listedMonthCount + count;
    if (end > _listMonths.length) end = _listMonths.length;
    while (end < _listMonths.length && store.isResolved(_listMonths[end])) {
      end++;
    }
    final from = _listedMonthCount;
    store.ensure(_listMonths.sublist(from, end));
    _listedMonthCount = end;
    _buildListRows(from: from);
    if (_listResolving) _scheduleListRun();
  }

  /// The next run, one event-loop turn later — a `Future`, never a
  /// microtask, so the frame the last run asked for is drawn first. New
  /// rows only ever join at the list's reading end, so the offset is kept
  /// as it is; a landing or an anchor still waiting for its row is tried
  /// again. Nothing runs while a page covers this one: a run that comes due
  /// then leaves the list as it is, and [didPopNext] schedules the next.
  void _scheduleListRun() {
    if (_covered) return;
    final generation = _resolveGeneration;
    unawaited(
      Future(() {
        if (!mounted || generation != _resolveGeneration || _covered) return;
        setState(() => _listMore(OverviewListMetrics.batchMonths));
        if (_listTarget != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _jumpList());
        }
      }),
    );
  }

  /// The rows of the months listed from [from] on, appended to the rows of
  /// the months before them: months only ever join at the list's reading
  /// end, so a run visits its own months' entries and no others (review 16).
  /// One per event folds every entry listed so far again — a fold has no
  /// end to append at. The cap counts what the rows show — after the query
  /// and Missed only — in reading order, so Newest first keeps the newest
  /// entries; the day it falls in keeps the entries before it.
  void _buildListRows({required int from}) {
    final perEvent = _options.rows == OverviewRows.perEvent;
    if (from == 0) {
      _rows = const [];
      _rowsBase = null;
      _listedEntries = [];
      _listedKept = 0;
      _listedMissed = 0;
      _listCapped = false;
    }
    final span = _listSpan!;
    final newestFirst = _options.order == OverviewOrder.newestFirst;
    final newMonths = _listMonths.sublist(from, _listedMonthCount);
    final buckets = {
      for (final month in newestFirst ? newMonths.reversed : newMonths)
        AgendaMonthStore.keyOf(month): _bucketOf(month),
    };
    AgendaDayListMonth bucketOf(DateTime day) =>
        buckets[AgendaMonthStore.keyOf(day)]!;
    // The store resolves whole months; a span starting on the 15th lists
    // nothing before it.
    final days = <DateTime>[
      for (final bucket in buckets.values)
        for (final day in bucket.days)
          if (!day.isBefore(span.start) && !day.isAfter(span.end)) day,
    ];
    final shown = <DateTime>[];
    var total = _listedKept + _listedMissed;
    DateTime? cutDay;
    var cut = const <AgendaDayListEntry>[];
    for (final day in newestFirst ? days.reversed : days) {
      final entries = _listed(bucketOf(day).entriesOn(day));
      CalendarOverviewPage._debugListedEntryVisits += entries.length;
      if (entries.isEmpty) continue;
      shown.add(day);
      final room = OverviewListMetrics.maxEntries - total;
      if (entries.length < room) {
        total += entries.length;
        continue;
      }
      if (entries.length > room) {
        cutDay = day;
        cut = entries.sublist(0, room);
      }
      _listCapped = true;
      break;
    }
    List<AgendaDayListEntry> entriesOf(DateTime day) =>
        day == cutDay ? cut : _listed(bucketOf(day).entriesOn(day));
    int keptCountOf(DateTime day) {
      if (_options.missedOnly) return 0;
      if (day == cutDay) return cut.where((entry) => !entry.missed).length;
      return bucketOf(day).keptCountForDay(day);
    }

    final listed = <AgendaDayListEntry>[
      for (final day in newestFirst ? shown.reversed : shown) ...entriesOf(day),
    ];
    final missed = listed.where((entry) => entry.missed).length;
    _listedKept += listed.length - missed;
    _listedMissed += missed;
    if (perEvent) {
      _listedEntries.addAll(listed);
      _rowsBase = null;
      _rows = foldAgendaDayListRowsByEvent(
        _listedEntries,
        categoryLabels: {
          for (final category in CalendarCategories.all)
            category.id: CalendarCategories.labelOf(category, _l10n!),
        },
        categoryOrder: [
          for (final category in CalendarCategories.all) category.id,
        ],
        newestFirst: newestFirst,
        categoryOf: _categoryOf,
      );
    } else {
      final added = buildAgendaDayListRows(
        shown,
        entriesOf,
        groupByDay: true,
        withMonths: true,
        alwaysMonths: true,
        showYear: _spanCrossesYear,
        keptCountOf: keptCountOf,
      );
      // A month is never split across runs, so the new months' rows follow
      // the old ones as they are; the layout extends from where it was.
      if (_rows.isEmpty) {
        _rows = added;
      } else if (added.isNotEmpty) {
        _rowsBase = _rows;
        _rows = [..._rows, ...added];
      }
    }
    // The rows moved under an offset that did not: the pinned label
    // follows once they are laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePinned());
  }

  /// Every month [span] touches, in order.
  static List<DateTime> _monthsOf(DateRange span) {
    final last = AgendaMonthStore.keyOf(span.end);
    return [
      for (var key = AgendaMonthStore.keyOf(span.start); key <= last; key++)
        AgendaMonthStore.monthOfKey(key),
    ];
  }

  /// [month]'s bucket as the page lists it: the store's own, or — while a
  /// query is live — the entries of it the query matches, folded into a
  /// bucket of its own once per matcher. Resolves the month if the store
  /// has not, so it runs on navigation only.
  AgendaDayListMonth _bucketOf(DateTime month) {
    final bucket = _store!.monthFor(month);
    final matcher = _matcher;
    if (matcher == null) return bucket;
    return _filteredMonths[AgendaMonthStore.keyOf(
      month,
    )] ??= AgendaDayListMonth.build(bucket.month, [
      for (final entry in bucket.entries)
        if (_matches(matcher, entry)) entry,
    ]);
  }

  /// One grammar with the scan's own candidate test and per-day match, so a
  /// post-filtered entry is exactly one the scan would have kept.
  bool _matches(EventQueryMatcher matcher, AgendaDayListEntry entry) {
    final event = _eventsById[entry.eventId];
    if (event == null) return false;
    return matcher.mayMatch(event) && matcher.matches(event, entry.day);
  }

  /// The category an entry's event wears, an unknown one read as the
  /// fallback, as every surface resolves it.
  String _categoryOf(AgendaDayListEntry entry) {
    final event = _eventsById[entry.eventId];
    return CalendarCategories.resolve(event?.categoryId ?? '').id;
  }

  /// Whether [day] has anything listed: the store's mask, or the narrowed
  /// month's while a query is live. Cache-only, for the grid's builder.
  bool _hasEntry(DateTime day) {
    if (_matcher == null) return _store?.hasEntry(day) ?? false;
    final mask = _filteredMonths[AgendaMonthStore.keyOf(day)]?.markedMask ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  /// The day's bars as [_hasEntry] reads its marks. Cache-only.
  List<DayBar>? _barsFor(DateTime day) {
    final bars = _matcher == null
        ? _store?.barsFor(day)
        : _filteredBars[AgendaMonthStore.keyOf(day)];
    return bars?[day.day];
  }

  /// A day's entries as the rows list them: only the missed ones under
  /// Missed only.
  List<AgendaDayListEntry> _listed(List<AgendaDayListEntry> entries) {
    if (!_options.missedOnly) return entries;
    return [
      for (final entry in entries)
        if (entry.missed) entry,
    ];
  }

  /// The year's tiles, folded from marks and kept for the pager: a page that
  /// slides in under a finger reads them without folding anything. Each day
  /// wears its top entry's colour, so several categories on one tile stay
  /// tellable apart. While a query is live they are folded from the narrowed
  /// months instead, which costs the year's rows once and then nothing per
  /// keystroke; [_rebuild] drops them with every query.
  List<AgendaYearTile> _tilesFor(int year) {
    final cached = _tilesByYear[year];
    if (cached != null) return cached;
    final store = _store!;
    final months = AgendaMonthStore.monthsOfYear(year);
    if (_matcher != null) {
      store.ensure(months);
      return _tilesByYear[year] = [
        for (final month in months)
          AgendaYearTile.ofTally(
            AgendaMonthTally.ofBucket(_bucketOf(month)),
            perDayColors: true,
          ),
      ];
    }
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
  /// repaint. Year mode on a year only: the list and the month grid have no
  /// year to page to, and their scans would warm tiles nobody is about to
  /// see.
  void _schedulePrewarm() {
    _prewarm?.cancel();
    _prewarm = Timer(OverviewListMetrics.prewarmDelay, () {
      if (!mounted || _store == null) return;
      if (_mode != AgendaDayListMode.year) return;
      if (_period is! OverviewYearPeriod) return;
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
      if (mode == AgendaDayListMode.year && _period is! OverviewYearPeriod) {
        _year = _firstYearOf(_period);
      }
      if (mode == AgendaDayListMode.month) {
        _month = _month.year == _year
            ? _month
            : DateTime.utc(_year, _today.year == _year ? _today.month : 1, 1);
      }
      if (mode == AgendaDayListMode.year) _syncPager();
      _recompute();
    });
    // A switch into the list opens it, so it lands as an open does.
    if (mode == AgendaDayListMode.list) _land();
    _schedulePrewarm();
    unawaited(_persistMode(mode));
  }

  Future<void> _persistMode(AgendaDayListMode mode) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewMode(mode);
  }

  /// The year a period opens year mode on: its first, inside the bounds.
  int _firstYearOf(OverviewPeriod period) {
    final span = period.resolve(today: _today, yearBounds: _years);
    return span.start.year.clamp(_years.first, _years.last);
  }

  /// A year the pager settled on — a swipe, or the end of an animated jump.
  void _onYearPaged(int year) {
    if (year == _year) return;
    setState(() {
      _year = year;
      _period = OverviewYearPeriod(year);
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
        duration: OverviewListMetrics.pageDuration,
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
      _period = OverviewYearPeriod(month.year);
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
      _period = OverviewYearPeriod(_year);
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

  /// The list's position, or null while no list is laid out. The newest one:
  /// a mode cross-fade can hold an outgoing list for a moment.
  ScrollPosition? get _listPosition =>
      _listScroll.hasClients ? _listScroll.positions.last : null;

  /// [_rows]' offsets under [_extents]; null until the extents are measured.
  _ListLayout? get _currentLayout {
    final extents = _extents;
    if (extents == null) return null;
    final layout = _layout;
    final tail = _listTail;
    final newestFirst = _options.order == OverviewOrder.newestFirst;
    if (layout != null &&
        identical(layout.extents, extents) &&
        layout.newestFirst == newestFirst) {
      if (identical(layout.rows, _rows) && layout.tail == tail) return layout;
      // A run appended rows, or only the tail moved: the slots summed so
      // far stand.
      if (identical(layout.rows, _rows) || identical(layout.rows, _rowsBase)) {
        return _layout = layout.extendedTo(_rowBuilder(_rows), tail: tail);
      }
    }
    return _layout = _ListLayout.of(
      _rowBuilder(_rows),
      extents,
      newestFirst: _options.order == OverviewOrder.newestFirst,
      tail: tail,
    );
  }

  /// Sends the list to [target] once the frame that lays the new rows out is
  /// done; a later call before then replaces it. A target that answers null
  /// has no row in the list yet.
  void _aimList(double? Function(_ListLayout layout) target) {
    _listTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpList());
  }

  /// Applies [_listTarget], clamped to the list's extent. Waits — keeping the
  /// target — while the rows' extents are still being measured, and while
  /// the row it wants is in months still to be resolved; the probe's report
  /// and each run call it again. A row that never comes is the end.
  void _jumpList() {
    final target = _listTarget;
    if (target == null || !mounted) return;
    if (_mode != AgendaDayListMode.list) {
      _listTarget = null;
      return;
    }
    final position = _listPosition;
    final layout = _currentLayout;
    if (position == null || layout == null || _extentsStale) return;
    final aimed = target(layout);
    if (aimed == null && _listResolving) return;
    _listTarget = null;
    final offset = (aimed ?? double.infinity).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (offset != position.pixels) position.jumpTo(offset);
    _updatePinned();
  }

  /// Where the list lands on a period, query, order or rows change, and when
  /// it first shows (D7 · A): on today's day — the first day on or after it,
  /// or the end — when today is inside the period and the oldest come first;
  /// else at the top.
  void _land() {
    final span = _period.resolve(today: _today, yearBounds: _years);
    final today = _today;
    final onToday =
        _options.order == OverviewOrder.oldestFirst &&
        _options.rows == OverviewRows.everyOccurrence &&
        !today.isBefore(span.start) &&
        !today.isAfter(span.end);
    _aimList((layout) => onToday ? layout.offsetOfDay(today) : 0);
  }

  /// What keeps the list on the row it shows across a rebuild that keeps the
  /// period: the first visible row's day — or its month, its category, its
  /// event — found again in the new rows, at the same depth into it when the
  /// same row is there; the nearest later day when it is gone, the end when
  /// nothing follows. Null at the top, which a rebuild keeps by itself.
  double? Function(_ListLayout layout)? _anchorOfList() {
    if (_mode != AgendaDayListMode.list) return null;
    final position = _listPosition;
    final layout = _currentLayout;
    if (position == null || layout == null || layout.rows.isEmpty) return null;
    final pixels = position.pixels;
    if (pixels <= 0) return null;
    final index = layout.rowAtOffset(pixels);
    final depth = pixels - layout.offsetOfRow(index);
    double? nearDay(_ListLayout next, DateTime day) => next.offsetOfDay(day);
    switch (layout.rows[index]) {
      case AgendaDayListMonthRow(:final month):
        return (next) {
          final row = next.monthRowOf(month);
          return row == null
              ? nearDay(next, month)
              : next.offsetOfRow(row) + depth;
        };
      case AgendaDayListDayRow(:final day):
        return (next) {
          final row = next.dayRowOf(day);
          return row == null
              ? nearDay(next, day)
              : next.offsetOfRow(row) + depth;
        };
      case AgendaDayListEntryRow(:final entry):
        // Held by its day's read row, whose depth into the day it keeps.
        final dayRow = layout.dayRowOf(entry.day);
        final dayDepth = dayRow == null
            ? 0.0
            : pixels - layout.offsetOfRow(dayRow);
        return (next) {
          final row = next.dayRowOf(entry.day);
          return row == null
              ? nearDay(next, entry.day)
              : next.offsetOfRow(row) + dayDepth;
        };
      case AgendaDayListCategoryRow(:final categoryId):
        return (next) {
          final row = next.categoryRowOf(categoryId);
          return row == null ? pixels : next.offsetOfRow(row) + depth;
        };
      case AgendaDayListEventRow(:final entry):
        return (next) {
          final row = next.eventRowOf(entry.eventId);
          return row == null ? pixels : next.offsetOfRow(row) + depth;
        };
    }
  }

  /// Pins the label of the section under the list's top edge once that
  /// section's own label has wholly scrolled past it — the one before it
  /// until then — so no label is ever drawn twice (C, the fix pass).
  void _updatePinned() {
    if (!mounted) return;
    final position = _listPosition;
    final layout = _mode == AgendaDayListMode.list ? _currentLayout : null;
    AgendaDayListRow? pinned;
    if (position != null && layout != null && layout.rows.isNotEmpty) {
      if (layout.pinnedAt(position.pixels) case final section?) {
        pinned = layout.rows[section];
      }
    }
    _pinned.value = pinned;
  }

  /// The scrubber's semantics actions: the list's next or previous section —
  /// a month, or a category group — at its top (review 15).
  void _stepList(_ListLayout layout, int direction) {
    final position = _listPosition;
    if (position == null) return;
    final target = layout.sectionStep(position.pixels, direction);
    if (target == null) return;
    _listTarget = null;
    _staleAnchor = null;
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    _updatePinned();
    _click();
  }

  /// A drag the user starts is where they want the list: a landing or an
  /// anchor still waiting for its run or its extents is dropped, so a late
  /// one never yanks the list from under the finger.
  bool _onListScrollStart(ScrollStartNotification notification) {
    if (notification.dragDetails != null) {
      _listTarget = null;
      _staleAnchor = null;
    }
    return false;
  }

  /// Marks the extents stale when an input of theirs moved since they were
  /// measured, noting where the list is while its layout still says so.
  /// Runs while the list body builds, where the width is known.
  void _checkExtentsInputs(BuildContext context, double width) {
    final inputs = (
      MediaQuery.textScalerOf(context),
      AppLocalizations.of(context)!.localeName,
      width,
    );
    if (inputs == _extentsInputs) return;
    _extentsInputs = inputs;
    if (_extentsStale) return;
    _extentsStale = true;
    _staleAnchor = _anchorOfList();
  }

  /// The probe's report: the list can be built — or re-laid on the new
  /// extents — and a target waiting for it applied once it is.
  void _onExtentsMeasured(_RowExtents extents) {
    if (!mounted) return;
    final anchor = _staleAnchor;
    _staleAnchor = null;
    setState(() {
      _extents = extents;
      _extentsStale = false;
    });
    _listTarget ??= anchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpList();
      _updatePinned();
    });
  }

  /// Dropped before every picker and sheet this page opens, or the modal's
  /// return hands focus — and the keyboard — back to the search.
  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  /// Typing waits out the debounce; clearing applies at once, as the clear
  /// button promises.
  void _onQueryChanged(String raw) {
    _searchDebounce?.cancel();
    _unappliedQuery = raw;
    if (raw.isEmpty) {
      _applyQuery(raw);
      return;
    }
    _searchDebounce = Timer(
      OverviewListMetrics.searchDebounce,
      () => _applyQuery(raw),
    );
  }

  /// A query that parses to the one applied changes nothing — a trailing
  /// space, a letter's case.
  void _applyQuery(String raw) {
    if (!mounted) return;
    final previous = _query;
    _setQuery(raw);
    if (_query == previous) return;
    _rebuild();
    _land();
  }

  void _setQuery(String raw) {
    _unappliedQuery = null;
    _query = EventSearchQuery.parse(raw, localeName: _l10n?.localeName ?? '');
  }

  /// The Period row's pick. A preset applies at once; Custom range… asks the
  /// Dates sheet for a span, seeded with the one shown, and changes nothing
  /// when it is cancelled.
  Future<void> _selectPeriod(OverviewPeriodChoice choice) async {
    if (choice != OverviewPeriodChoice.custom) {
      _setPeriod(OverviewPeriod.fromChoice(choice, today: _today));
      return;
    }
    if (_pickerOpen) return;
    _pickerOpen = true;
    try {
      _blur();
      final picked = await CalendarDatePickerSheet.pickRange(
        context,
        initialRange: _shownPeriod.resolve(today: _today, yearBounds: _years),
        firstDate: DateTime.utc(_years.first, 1, 1),
        lastDate: DateTime.utc(_years.last, 12, 31),
        appearance: _appearance,
      );
      if (picked == null || !mounted) return;
      _setPeriod(OverviewCustomPeriod(picked.start, picked.end));
    } finally {
      _pickerOpen = false;
    }
  }

  /// Lists [period], landing per D7, and persists it — a preset is kept for
  /// the next visit, a custom span clears what was kept. Year mode jumps to the
  /// period's first year; the jump lands on the year already set, so the
  /// pager's report of it leaves the period alone. A pick of the period
  /// already shown is still persisted: year paging changes the period
  /// without writing it, so "This year" picked after paging back to this
  /// year is a choice the next visit must see (review 1).
  void _setPeriod(OverviewPeriod period) {
    if (period == _period) {
      unawaited(_persistPeriod(period));
      return;
    }
    setState(() {
      _period = period;
      _year = _firstYearOf(period);
      _recompute();
    });
    final pager = _yearPager;
    if (_mode == AgendaDayListMode.year && pager != null && pager.hasClients) {
      pager.jumpToPage(AgendaYearPager.indexOf(_year, _years.first));
    }
    _land();
    _schedulePrewarm();
    unawaited(_persistPeriod(period));
  }

  Future<void> _persistPeriod(OverviewPeriod period) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewPeriod(period, today: _today);
  }

  /// What the Period row shows: year mode's year there, the list's period
  /// everywhere else.
  OverviewPeriod get _shownPeriod =>
      _mode == AgendaDayListMode.year ? OverviewYearPeriod(_year) : _period;

  void _openOptions() {
    _blur();
    unawaited(
      OverviewOptionsSheet.show(
        context,
        initial: _options,
        listMode: _mode == AgendaDayListMode.list,
        onChanged: _setOptions,
      ),
    );
  }

  /// The options sheet's live writes. Order and Rows re-present the list and
  /// land it anew (D7); Missed only narrows the rows shown and keeps the list
  /// on its row. Order and Rows are kept for the next visit; Missed only is
  /// not.
  void _setOptions(OverviewListOptions next) {
    if (!mounted) return;
    final previous = _options;
    final represented =
        next.order != previous.order || next.rows != previous.rows;
    final anchor = represented ? null : _anchorOfList();
    setState(() {
      _options = next;
      _recompute();
    });
    if (represented) {
      _land();
      unawaited(_persistOptions(next));
    } else if (anchor != null) {
      _aimList(anchor);
    }
  }

  Future<void> _persistOptions(OverviewListOptions options) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewListOptions(options);
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
      _storeStale = true;
      _rebuild();
      final settings = await SettingsService.getInstance();
      await settings.setCalendarOverviewCategories(next);
    } finally {
      _pickerOpen = false;
    }
  }

  void _openOccurrence(AgendaDayListEntry entry) =>
      _openOn(entry.day, entry.eventId);

  /// A per-event row opens the calendar on the event's last day in the
  /// period (D10 · A): the most recent of what the row counts.
  void _openEventRow(AgendaDayListEventRow row) =>
      _openOn(row.last, row.entry.eventId);

  void _openOn(DateTime day, String? eventId) {
    if (eventId == null) return;
    final open = widget._openOccurrence;
    if (open != null) {
      open(day, eventId);
      return;
    }
    unawaited(AppNavigator.toCalendarOccurrence(day: day, eventId: eventId));
  }

  /// The rows of the list and of month mode, one geometry per kind (T4, T8):
  /// titles on one line, a caption clamped to one, no pencil — a row opens
  /// its occurrence on the calendar, where it is edited. The list's headers
  /// take [headers], its slots' layout; month mode's sliver sizes each row
  /// itself, so its headers wrap as their text needs.
  AgendaDayListRowBuilder _rowBuilder(
    List<AgendaDayListRow> rows, {
    AgendaHeaderSlots? headers,
    bool? dayHeaderWithYear,
  }) {
    return AgendaDayListRowBuilder(
      rows: rows,
      today: _today,
      onEntryTap: _openOccurrence,
      onEventTap: _openEventRow,
      captionMaxLines: 1,
      dayHeaderWithYear:
          dayHeaderWithYear ??
          (_mode == AgendaDayListMode.list && _spanCrossesYear),
      monthCounts: true,
      headerSlots: headers,
      singleLineTitles: true,
      rowIdentifier: (entry) => switch (entry.eventId) {
        final id? => SemanticsIds.overviewRow(id, entry.day),
        null => null,
      },
      eventRowIdentifier: (row) => switch (row.entry.eventId) {
        final id? => SemanticsIds.overviewEventRow(id),
        null => null,
      },
    );
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
      child: Scaffold(
        // The language's ground, which the rows' groups are drawn against.
        backgroundColor: colorScheme.pageGround,
        appBar: AppBar(
          titleSpacing: CalendarViewMenu.titleSpacing,
          excludeHeaderSemantics: true,
          title: CalendarViewMenu(
            page: CalendarViewPage.overview,
            onPageSelected: (_) => AppNavigator.switchToCalendar(context),
            presentation: _mode,
            onPresentationSelected: _selectMode,
          ),
          backgroundColor: colorScheme.surface,
          scrolledUnderElevation: 0,
          actions: [
            _buildOptionsButton(l10n),
            CalendarOverflowMenu(
              onAlerts: () => AppNavigator.toAlertsFromCalendar(context),
              onExport: (_events?.isNotEmpty ?? false) ? _exportEvents : null,
              onSettings: _openSettings,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilterGroup(l10n),
              if (_mode == AgendaDayListMode.list)
                _buildCount(l10n)
              else
                const SizedBox(height: FormMetrics.bodyTop),
              Expanded(
                child: AnimatedSwitcher(
                  duration: OverviewListMetrics.modeSwitchDuration,
                  child: KeyedSubtree(
                    key: ValueKey(_mode),
                    child: _buildBody(l10n, colorScheme),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Badged by the restrictions alone — Missed only — as the calendar's
  /// filter button is: Order and Rows re-present the same entries, and a
  /// badge means something is hidden.
  Widget _buildOptionsButton(AppLocalizations l10n) {
    // Missed only narrows the list and month mode's rows; year mode's tiles
    // ignore it, so there it hides nothing (review 10).
    final restrictions = _options.missedOnly && _mode != AgendaDayListMode.year
        ? 1
        : 0;
    return Badge.count(
      count: restrictions,
      isLabelVisible: restrictions > 0,
      child: AutomationId(
        identifier: SemanticsIds.overviewOptionsOpen,
        child: IconButton(
          tooltip: l10n.overviewListOptions,
          isSelected: restrictions > 0,
          icon: const Icon(Icons.tune_rounded),
          onPressed: _openOptions,
        ),
      ),
    );
  }

  Widget _buildFilterGroup(AppLocalizations l10n) {
    final shown = _shownPeriod;
    return Padding(
      padding: const EdgeInsets.only(
        left: RowMetrics.groupInset,
        top: FormMetrics.bodyTop,
        right: RowMetrics.groupInset,
      ),
      child: FormRowGroup(
        trailingGap: false,
        children: [
          FormSearchRow(
            controller: _searchController,
            hint: l10n.upcomingSearchHint,
            clearTooltip: l10n.upcomingClearSearch,
            onChanged: _onQueryChanged,
            identifier: SemanticsIds.overviewSearch,
          ),
          FormPickerRow(
            glyph: Icons.category_rounded,
            label: l10n.overviewCategories,
            value: _categoriesValue(l10n),
            onTap: _pickCategories,
            identifier: SemanticsIds.overviewCategories,
          ),
          FormMenuRow<OverviewPeriodChoice>(
            glyph: Icons.date_range_rounded,
            label: l10n.overviewPeriod,
            value: shown.menuValue(l10n),
            selected: shown.menuChoice(today: _today),
            menuWidth: FormMetrics.menuWidth,
            identifier: SemanticsIds.overviewPeriod,
            items: [
              for (final choice in OverviewPeriodChoice.values)
                FormMenuItem(
                  value: choice,
                  label: _periodLabel(l10n, choice),
                  icon: _periodIcon(choice),
                  identifier: _periodId(choice),
                ),
            ],
            // The month nav is month mode's period control.
            onSelected: _mode == AgendaDayListMode.month ? null : _selectPeriod,
          ),
        ],
      ),
    );
  }

  /// "All" for the empty allowlist, else the chosen categories read back in
  /// catalog order — two names, then "+N more", never an ellipsis.
  String _categoriesValue(AppLocalizations l10n) {
    if (_categoryIds.isEmpty) return l10n.calendarFilterCategoriesAll;
    return CalendarFilterSummary.namesReadBack([
      for (final category in CalendarCategories.visiblePlus(_categoryIds))
        if (_categoryIds.contains(category.id))
          CalendarCategories.labelOf(category, l10n),
    ], l10n);
  }

  static String _periodLabel(
    AppLocalizations l10n,
    OverviewPeriodChoice choice,
  ) {
    return switch (choice) {
      OverviewPeriodChoice.thisYear => l10n.upcomingPeriodWholeYear,
      OverviewPeriodChoice.last12Months => l10n.overviewPeriodLast12Months,
      OverviewPeriodChoice.last90Days => l10n.overviewPeriodLast90Days,
      OverviewPeriodChoice.allTime => l10n.overviewPeriodAllTime,
      OverviewPeriodChoice.custom => l10n.upcomingPeriodCustom,
    };
  }

  static IconData _periodIcon(OverviewPeriodChoice choice) {
    return switch (choice) {
      OverviewPeriodChoice.thisYear => Icons.today_rounded,
      OverviewPeriodChoice.last12Months => Icons.history_rounded,
      OverviewPeriodChoice.last90Days => Icons.history_rounded,
      OverviewPeriodChoice.allTime => Icons.all_inclusive_rounded,
      OverviewPeriodChoice.custom => Icons.date_range_rounded,
    };
  }

  static String _periodId(OverviewPeriodChoice choice) {
    return switch (choice) {
      OverviewPeriodChoice.thisYear => SemanticsIds.overviewPeriodThisYear,
      OverviewPeriodChoice.last12Months =>
        SemanticsIds.overviewPeriodLast12Months,
      OverviewPeriodChoice.last90Days => SemanticsIds.overviewPeriodLast90Days,
      OverviewPeriodChoice.allTime => SemanticsIds.overviewPeriodAllTime,
      OverviewPeriodChoice.custom => SemanticsIds.overviewPeriodCustom,
    };
  }

  /// The listed entries, in a slot that changes text and never height.
  Widget _buildCount(AppLocalizations l10n) {
    final caption = FormCaption(
      text: agendaDayListCountLabel(l10n, _listedKept, _listedMissed),
      maxLines: 1,
      padding: FormMetrics.groupCaptionPadding,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
      child: FormCaptionSlot(candidates: [caption], child: caption),
    );
  }

  /// The pinned band's height: the group gap, then one section slot.
  static double _pinnedBandHeight(AgendaHeaderSlots headers) =>
      RowMetrics.groupGap + (headers.sectionHeight ?? 0);

  /// The label of the section the list is scrolled into — its month, or its
  /// category group under One per event — on the ground above the list. A
  /// slot of one geometry, the list's section slot: drawn by the list's own
  /// builder, so it reads as the label it stands for, and shown only once
  /// that label has wholly scrolled out of the list — the section before it
  /// until then — so a label is never drawn twice (C, the fix pass).
  Widget _buildPinnedLabel(AgendaHeaderSlots headers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset,
        RowMetrics.groupGap,
        RowMetrics.groupInset,
        0,
      ),
      child: ValueListenableBuilder<AgendaDayListRow?>(
        valueListenable: _pinned,
        builder: (context, row, _) {
          final pinned = switch (row) {
            AgendaDayListMonthRow(:final month, :final kept, :final missed) =>
              AgendaDayListMonthRow(
                month: month,
                showYear: true,
                kept: kept,
                missed: missed,
              ),
            AgendaDayListCategoryRow() => row,
            _ => null,
          };
          if (pinned == null) return SizedBox(height: headers.sectionHeight);
          return _rowBuilder([pinned], headers: headers).build(context, 0);
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme colorScheme) {
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }
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
                // The scaffold already resizes for the keyboard, so the pager
                // carries no inset of its own — and no inset frame rebuilds a
                // year of tiles.
                padding: OverviewListMetrics.yearPagerPadding,
                highlightMonth: _highlightMonth,
                highlightToken: _highlightToken,
              ),
            ),
          ],
        );
      case AgendaDayListMode.list:
        return LayoutBuilder(
          builder: (context, constraints) {
            _checkExtentsInputs(context, constraints.maxWidth);
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: RowMetrics.groupInset,
                  top: 0,
                  right: RowMetrics.groupInset,
                  child: _RowExtentProbe(
                    builderOf: _rowBuilder,
                    today: _today,
                    measure: _extentsStale,
                    onMeasured: _onExtentsMeasured,
                  ),
                ),
                if (_currentLayout case final layout?)
                  _buildList(l10n, layout)
                else
                  const Center(child: CircularProgressIndicator()),
              ],
            );
          },
        );
      case AgendaDayListMode.month:
        return _buildMonthBody(l10n);
    }
  }

  /// The list on its exact extents (T4): every row's slot is its kind's
  /// measured height, so a jump lands where it was aimed, the scrollbar is
  /// true and a far jump lays out only what it lands on.
  Widget _buildList(AppLocalizations l10n, _ListLayout layout) {
    // Captured, not read from the fields: the outgoing list of a mode
    // cross-fade keeps building rows while it fades, and the fields by then
    // hold the next mode's.
    final rows = _rowBuilder(layout.rows, headers: layout.extents.headers);
    final rowCount = layout.rows.length;
    final tail = layout.tail;
    final extents = layout.slots;
    // Until the probe reports, the rows are drawn at the new scale or in the
    // new locale on the old extents: clipped to them for that frame rather
    // than overflowing them.
    final stale = _extentsStale;
    Widget slotted(Widget row) => stale
        ? ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: row,
            ),
          )
        : row;
    return Builder(
      builder: (context) {
        final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
        final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
        final padding = EdgeInsets.fromLTRB(
          RowMetrics.groupInset,
          0,
          RowMetrics.groupInset,
          FormMetrics.bodyBottom +
              (viewInsets > viewPadding ? viewInsets : viewPadding),
        );
        final list = Semantics(
          container: true,
          identifier: SemanticsIds.overviewList,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: _onListScrollStart,
            child: extents.isEmpty
                ? ListView(
                    controller: _listScroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: padding,
                    children: [
                      FormCaption(
                        text: l10n.overviewEmptyPeriod,
                        padding: FormMetrics.groupCaptionPadding,
                      ),
                    ],
                  )
                : CustomScrollView(
                    controller: _listScroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    semanticChildCount: extents.length,
                    slivers: [
                      SliverPadding(
                        padding: padding,
                        sliver: _ExactExtentSliver(
                          layout: layout,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => slotted(
                              index < rowCount
                                  ? rows.build(context, index)
                                  : _tailCaption(l10n, tail!),
                            ),
                            childCount: extents.length,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
        // Outside the list's node, so the lane joins none of its indexes;
        // it overlays the rows' trailing 48 dp, which carry no control.
        final body = rowCount == 0
            ? list
            : ListScrubber(
                controller: _listScroll,
                labelAt: (offset) => _groupLabelAt(l10n, layout, offset),
                semanticsLabel: l10n.overviewScrubberLabel,
                identifier: SemanticsIds.overviewScrubber,
                onLabelChanged: _click,
                onStep: (direction) => _stepList(layout, direction),
                child: list,
              );
        // The band takes its height from the list's share of the page, not
        // from the column above it, so nothing overflows; and it yields
        // when it would take most of that share — with the keyboard up at a
        // large scale on a small phone — so the list keeps a height to drag.
        return LayoutBuilder(
          builder: (context, constraints) {
            final band = _pinnedBandHeight(layout.extents.headers);
            final showBand =
                band <=
                constraints.maxHeight * OverviewListMetrics.pinnedBandMaxShare;
            // One shape either way, so the list keeps its state when the
            // band yields or returns.
            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: showBand ? band : 0),
                  child: body,
                ),
                if (showBand)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildPinnedLabel(layout.extents.headers),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// The scrubber's bubble: the month at [offset], with its year, or the
  /// category group under One per event.
  static String? _groupLabelAt(
    AppLocalizations l10n,
    _ListLayout layout,
    double offset,
  ) {
    final group = layout.groupAt(offset);
    if (group == null) return null;
    return switch (layout.rows[group]) {
      AgendaDayListMonthRow(:final month) => AgendaListView.monthLabel(
        l10n.localeName,
        month,
        withYear: true,
      ),
      AgendaDayListCategoryRow(:final label) => label,
      _ => null,
    };
  }

  /// The list's last row while it is not the period's end: "Loading more…"
  /// while runs are pending, the cap's line once it is reached. The probe
  /// measures it through this same builder, so its slot is exact.
  static Widget _tailCaption(AppLocalizations l10n, _ListTail tail) {
    return FormCaption(
      text: switch (tail) {
        _ListTail.loading => l10n.overviewLoading,
        _ListTail.capped => l10n.overviewCapReached(
          OverviewListMetrics.maxEntries,
        ),
      },
      padding: FormMetrics.groupCaptionPadding,
    );
  }

  /// Month mode below its nav and grid: the day list's rows (§3.2 item 7) —
  /// read rows over their entries for the whole month, or, with a day
  /// picked, that day's read row carrying "Whole month" over its entries.
  Widget _buildMonthBody(AppLocalizations l10n) {
    final bucket = _monthBucket!;
    final rows = _rowBuilder(_rows);
    final selected = _selectedDay;
    // With a day picked the rows are its entries alone (`_recompute` groups
    // by day only for the whole month), so its read row is built in front
    // of them here, from the bucket's counts.
    final leadingRows = selected == null ? 0 : 1;
    final empty = _rows.isEmpty && selected == null;
    return Builder(
      builder: (context) {
        final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
        final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
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
                selectedDay: selected,
                appearance: _appearance,
                hasEntry: _hasEntry,
                barsFor: _barsFor,
                onDaySelected: _toggleSelectedDay,
                onPageChanged: _goToMonth,
              ),
            ),
            SliverPadding(
              // The group gap above the first group: the grid's last row of
              // cells ends flush, and a rounded group straight under it
              // read as part of the grid.
              padding: const EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                RowMetrics.groupGap,
                RowMetrics.groupInset,
                0,
              ),
              sliver: empty
                  ? SliverToBoxAdapter(
                      child: FormCaption(
                        text: l10n.dayListEmptyMonth,
                        padding: FormMetrics.groupCaptionPadding,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => selected != null && index == 0
                            ? _buildPickedDayRow(
                                context,
                                l10n,
                                rows,
                                bucket,
                                selected,
                              )
                            : rows.build(context, index - leadingRows),
                        childCount: _rows.length + leadingRows,
                      ),
                    ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    FormMetrics.bodyBottom +
                    (viewInsets > viewPadding ? viewInsets : viewPadding),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The picked day's head in month mode: its read row with "Whole month" as
  /// the second target, above its entries — the day list's own (D3).
  Widget _buildPickedDayRow(
    BuildContext context,
    AppLocalizations l10n,
    AgendaDayListRowBuilder rows,
    AgendaDayListMonth bucket,
    DateTime day,
  ) {
    final count = bucket.countForDay(day);
    final kept = _options.missedOnly ? 0 : bucket.keptCountForDay(day);
    final missed = count - bucket.keptCountForDay(day);
    return FormRowShell(
      first: true,
      last: _rows.isEmpty,
      child: rows.readRow(
        context,
        day: day,
        kept: kept,
        missed: missed,
        trailingButton: FormTrailingButton(
          icon: Icons.close_rounded,
          tooltip: l10n.dayListWholeMonth,
          identifier: SemanticsIds.overviewWholeMonth,
          onPressed: () => _toggleSelectedDay(day),
        ),
      ),
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
      month: _month,
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
}

/// Every row kind's height at the text scale, locale and width in use (T4),
/// read off [_RowExtentProbe]'s templates; an entry kind twice, as the
/// shell draws it — with the hairline under it, and closing its group. The
/// headers' two are their widest's, in the layout [headers] gives them.
@immutable
class _RowExtents {
  final AgendaHeaderSlots headers;
  final double month;
  final double dayRead;
  final double entry;
  final double entryEnd;
  final double entryCaption;
  final double entryCaptionEnd;

  /// The list's tail: "Loading more…", and the cap's line, which wraps to
  /// two lines in German at 200 %.
  final double caption;
  final double capCaption;

  const _RowExtents({
    required this.headers,
    required this.month,
    required this.dayRead,
    required this.entry,
    required this.entryEnd,
    required this.entryCaption,
    required this.entryCaptionEnd,
    required this.caption,
    required this.capCaption,
  });

  double slotOfTail(_ListTail tail) => switch (tail) {
    _ListTail.loading => caption,
    _ListTail.capped => capCaption,
  };

  /// The slot of a row of [kind]: its height, plus the gap to the next group
  /// when it carries one.
  double slotOf(
    AgendaRowExtentKind kind, {
    required bool closesGroup,
    required bool trailingGap,
  }) {
    final height = switch (kind) {
      AgendaRowExtentKind.month => month,
      AgendaRowExtentKind.dayRead => dayRead,
      AgendaRowExtentKind.entry => closesGroup ? entryEnd : entry,
      AgendaRowExtentKind.entryCaption =>
        closesGroup ? entryCaptionEnd : entryCaption,
    };
    return trailingGap ? height + RowMetrics.groupGap : height;
  }

  @override
  bool operator ==(Object other) =>
      other is _RowExtents &&
      other.headers == headers &&
      other.month == month &&
      other.dayRead == dayRead &&
      other.entry == entry &&
      other.entryEnd == entryEnd &&
      other.entryCaption == entryCaption &&
      other.entryCaptionEnd == entryCaptionEnd &&
      other.caption == caption &&
      other.capCaption == capCaption;

  @override
  int get hashCode => Object.hash(
    headers,
    month,
    dayRead,
    entry,
    entryEnd,
    entryCaption,
    entryCaptionEnd,
    caption,
    capCaption,
  );
}

/// What closes a list that does not reach its period's end: months still
/// being resolved, or the entry cap (T5).
enum _ListTail { loading, capped }

/// The list's rows as slots and their prefix sums, so an offset, a row, a
/// day and a section convert into one another without laying out a row
/// (§3.8 item 4): a jump, the landing and the anchoring are exact, and the
/// pinned label is a lookup.
class _ListLayout {
  final List<AgendaDayListRow> rows;
  final _RowExtents extents;

  /// The caption after [rows], if the list has one: one slot more than
  /// there are rows.
  final _ListTail? tail;

  /// Each row's extent, as the list's `itemExtentBuilder` hands it out, and
  /// the tail's last.
  final List<double> slots;

  /// `slots` summed: row `i` starts at `_offsets[i]`; the last entry is the
  /// whole run.
  final List<double> _offsets;

  /// The section rows — months, or category groups — in list order.
  final List<int> _sections;

  /// The day read rows in list order, their days ascending, or descending
  /// under Newest first.
  final List<int> _days;
  final bool _newestFirst;

  _ListLayout._(
    this.rows,
    this.extents,
    this.tail,
    this.slots,
    this._offsets,
    this._sections,
    this._days,
    this._newestFirst,
  );

  factory _ListLayout.of(
    AgendaDayListRowBuilder builder,
    _RowExtents extents, {
    required bool newestFirst,
    required _ListTail? tail,
  }) => _summed(builder, extents, newestFirst: newestFirst, tail: tail);

  bool get newestFirst => _newestFirst;

  /// This layout over [builder]'s rows, which begin with [rows]: the slots
  /// summed so far stand but the last row's — whose group a new row may
  /// carry on, so its gap can change — and only the rest is summed (review
  /// 16). The arrays are copied, so every layout stays what it was.
  _ListLayout extendedTo(
    AgendaDayListRowBuilder builder, {
    required _ListTail? tail,
  }) {
    final kept = rows.isEmpty ? 0 : rows.length - 1;
    return _summed(
      builder,
      extents,
      newestFirst: _newestFirst,
      tail: tail,
      from: this,
      kept: kept,
    );
  }

  /// Sums [builder]'s rows from row [kept] on, the ones before it taken from
  /// [from].
  static _ListLayout _summed(
    AgendaDayListRowBuilder builder,
    _RowExtents extents, {
    required bool newestFirst,
    required _ListTail? tail,
    _ListLayout? from,
    int kept = 0,
  }) {
    final rows = builder.rows;
    final count = rows.length + (tail == null ? 0 : 1);
    final slots = List<double>.filled(count, 0);
    final offsets = List<double>.filled(count + 1, 0);
    final sections = <int>[];
    final days = <int>[];
    if (from != null && kept > 0) {
      slots.setRange(0, kept, from.slots);
      offsets.setRange(0, kept + 1, from._offsets);
      sections.addAll(from._sections.where((row) => row < kept));
      days.addAll(from._days.where((row) => row < kept));
    }
    for (var i = kept; i < rows.length; i++) {
      slots[i] = extents.slotOf(
        builder.extentKindOf(i),
        closesGroup: builder.closesGroupOf(i),
        trailingGap: builder.trailingGapOf(i),
      );
      offsets[i + 1] = offsets[i] + slots[i];
      switch (rows[i]) {
        case AgendaDayListMonthRow() || AgendaDayListCategoryRow():
          sections.add(i);
        case AgendaDayListDayRow():
          days.add(i);
        case AgendaDayListEntryRow() || AgendaDayListEventRow():
          break;
      }
    }
    if (tail != null) {
      slots[rows.length] = extents.slotOfTail(tail);
      offsets[count] = offsets[rows.length] + slots[rows.length];
    }
    return _ListLayout._(
      rows,
      extents,
      tail,
      slots,
      offsets,
      sections,
      days,
      newestFirst,
    );
  }

  double offsetOfRow(int index) => _offsets[index];

  /// Where slot [index] starts — the tail's too; past the last, the end.
  double offsetOfSlot(int index) =>
      _offsets[index < slots.length ? index : slots.length];

  /// The slot a sliver lays out first or last for [scrollOffset]: the one
  /// whose end reaches it — at a slot's boundary the one before it, as the
  /// stock varied-extent sliver counts; past the end, the last.
  int slotReaching(double scrollOffset) {
    if (scrollOffset <= 0) return 0;
    var low = 1;
    var high = slots.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_offsets[mid] >= scrollOffset) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low - 1;
  }

  /// The whole run of rows, end to end.
  double get extent => _offsets.last;

  /// The row under [offset]: the last one starting at or above it.
  int rowAtOffset(double offset) {
    var low = 0;
    var high = rows.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// The section row heading the row under [offset]; null above the first.
  int? groupAt(double offset) => switch (_sectionIndexAt(offset)) {
    final index? => _sections[index],
    null => null,
  };

  /// The section whose label is pinned above the list at [offset]: the one
  /// [groupAt] names once its own label's slot lies wholly above [offset],
  /// else the one before it — while any of a label still shows in the list,
  /// the pinned label is another.
  int? pinnedAt(double offset) {
    final index = _sectionIndexAt(offset);
    if (index == null) return null;
    final section = _sections[index];
    if (offset >= _offsets[section + 1]) return section;
    return index > 0 ? _sections[index - 1] : null;
  }

  /// Where the next section starts from [offset] ([direction] 1), or the
  /// previous one (-1) — the section [offset] is inside first, unless it is
  /// at that section's very start; null past either end.
  double? sectionStep(double offset, int direction) {
    if (_sections.isEmpty) return null;
    final index = _sectionIndexAt(offset);
    final int target;
    if (index == null) {
      target = direction > 0 ? 0 : -1;
    } else if (direction > 0) {
      target = index + 1;
    } else {
      target = _offsets[_sections[index]] < offset ? index : index - 1;
    }
    if (target < 0 || target >= _sections.length) return null;
    return _offsets[_sections[target]];
  }

  /// [_sections]' index of the section heading the row under [offset].
  int? _sectionIndexAt(double offset) {
    final row = rowAtOffset(offset);
    int? found;
    var low = 0;
    var high = _sections.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_sections[mid] <= row) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  /// The month the row under [offset] belongs to; null in per-event rows.
  DateTime? monthAtOffset(double offset) => switch (groupAt(offset)) {
    final index? => switch (rows[index]) {
      AgendaDayListMonthRow(:final month) => month,
      _ => null,
    },
    null => null,
  };

  /// The first day read row at or past [day] in the list's direction — the
  /// day's own, or the nearest after it as the list reads; null when none
  /// follows.
  int? _dayRowFrom(DateTime day) {
    bool reached(int row) {
      final rowDay = (rows[row] as AgendaDayListDayRow).day;
      return _newestFirst ? !rowDay.isAfter(day) : !rowDay.isBefore(day);
    }

    var low = 0;
    var high = _days.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (reached(_days[mid])) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low < _days.length ? _days[low] : null;
  }

  /// Where [day]'s read row starts, or the nearest later day's as the list
  /// reads; null when no day follows.
  double? offsetOfDay(DateTime day) => switch (_dayRowFrom(day)) {
    final row? => _offsets[row],
    null => null,
  };

  /// [day]'s own read row, if the list has one.
  int? dayRowOf(DateTime day) {
    final row = _dayRowFrom(day);
    if (row == null) return null;
    return (rows[row] as AgendaDayListDayRow).day == day ? row : null;
  }

  int? monthRowOf(DateTime month) {
    for (final row in _sections) {
      if (rows[row] case AgendaDayListMonthRow(
        month: final m,
      ) when m == month) {
        return row;
      }
    }
    return null;
  }

  int? categoryRowOf(String categoryId) {
    for (final row in _sections) {
      if (rows[row] case AgendaDayListCategoryRow(
        categoryId: final id,
      ) when id == categoryId) {
        return row;
      }
    }
    return null;
  }

  int? eventRowOf(String? eventId) {
    if (eventId == null) return null;
    for (var row = 0; row < rows.length; row++) {
      if (rows[row] case AgendaDayListEventRow(
        :final entry,
      ) when entry.eventId == eventId) {
        return row;
      }
    }
    return null;
  }
}

/// The list's rows on [_ListLayout]'s slots, which it reads by their prefix
/// sums: the stock varied-extent sliver sums the extents from the first row
/// on every lookup, so a frame near the end of thirty thousand rows walked
/// them all (review 17); here a row's offset, the row at an offset and the
/// whole are lookups. The whole is exact before the last row is laid out —
/// an estimate from the rows built would put the scroll range, the
/// scrollbar and a jump's clamp thousands of pixels off (R9).
class _ExactExtentSliver extends SliverMultiBoxAdaptorWidget {
  final _ListLayout layout;

  const _ExactExtentSliver({required super.delegate, required this.layout});

  @override
  _RenderExactExtentSliver createRenderObject(BuildContext context) {
    return _RenderExactExtentSliver(
      childManager: context as SliverMultiBoxAdaptorElement,
      layout: layout,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExactExtentSliver renderObject,
  ) {
    renderObject.listLayout = layout;
  }
}

class _RenderExactExtentSliver extends RenderSliverFixedExtentBoxAdaptor {
  _RenderExactExtentSliver({
    required super.childManager,
    required _ListLayout layout,
  }) : _layout = layout;

  _ListLayout _layout;
  set listLayout(_ListLayout value) {
    if (identical(value, _layout)) return;
    _layout = value;
    markNeedsLayout();
  }

  @override
  double? get itemExtent => null;

  @override
  ItemExtentBuilder get itemExtentBuilder => _slotOf;

  double? _slotOf(int index, SliverLayoutDimensions _) =>
      index < _layout.slots.length ? _layout.slots[index] : null;

  @override
  double indexToLayoutOffset(double itemExtent, int index) =>
      _layout.offsetOfSlot(index);

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _layout.slotReaching(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _layout.slotReaching(scrollOffset);

  @override
  double computeMaxScrollOffset(
    SliverConstraints constraints,
    double itemExtent,
  ) => _layout.extent;

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) => _layout.extent;
}

/// One template of every row kind, laid out offstage at the list's width so
/// [_RowExtents] holds the heights the rows really take — the invisible
/// template that sizes the nav's title, for rows. Built through the page's
/// own row builder, so a template is the row it stands for. A header kind is
/// templated by its widest — the widest label the kind can carry in this
/// locale, beside a three-digit count — once on one line and once wrapped,
/// and keeps one line when that one fits it (D, the fix pass).
class _RowExtentProbe extends StatefulWidget {
  final AgendaDayListRowBuilder Function(
    List<AgendaDayListRow> rows, {
    AgendaHeaderSlots? headers,
    bool? dayHeaderWithYear,
  })
  builderOf;
  final DateTime today;

  /// Whether the heights are wanted: read after the frame that laid the
  /// templates out, and reported through [onMeasured].
  final bool measure;
  final ValueChanged<_RowExtents> onMeasured;

  const _RowExtentProbe({
    required this.builderOf,
    required this.today,
    required this.measure,
    required this.onMeasured,
  });

  @override
  State<_RowExtentProbe> createState() => _RowExtentProbeState();
}

class _RowExtentProbeState extends State<_RowExtentProbe> {
  /// The count the header templates carry: "100 entries · 100 missed".
  static const int _widestCount = 100;

  static const AgendaHeaderSlots _oneLine = AgendaHeaderSlots(
    sectionsOnOneLine: true,
    daysOnOneLine: true,
  );
  static const AgendaHeaderSlots _wrapped = AgendaHeaderSlots(
    sectionsOnOneLine: false,
    daysOnOneLine: false,
  );

  /// The widest section label and the widest read row, each laid out on one
  /// line and wrapped; a read row also bare, outside its shell, which is the
  /// height its slot gives it.
  final GlobalKey _sectionOneLine = GlobalKey();
  final GlobalKey _sectionWrapped = GlobalKey();
  final GlobalKey _dayOneLine = GlobalKey();
  final GlobalKey _dayWrapped = GlobalKey();
  final GlobalKey _dayBareOneLine = GlobalKey();
  final GlobalKey _dayBareWrapped = GlobalKey();

  /// Two runs of templates — plain entries, captioned entries — each entry
  /// kind measured inside its group and closing it.
  final List<GlobalKey> _plain = List.generate(3, (_) => GlobalKey());
  final List<GlobalKey> _captioned = List.generate(3, (_) => GlobalKey());

  /// The tail's two captions, in [_ListTail] order.
  final List<GlobalKey> _tails = List.generate(
    _ListTail.values.length,
    (_) => GlobalKey(),
  );

  void _read() {
    if (!mounted || !widget.measure) return;
    double heightOf(GlobalKey key) => key.currentContext?.size?.height ?? 0;
    // Wrapping changes nothing while the widest fits one line: the one-line
    // shape is kept then, and a count longer than the template's squeezes
    // its label rather than outgrowing the slot.
    final sectionsOnOneLine =
        heightOf(_sectionWrapped) <=
        heightOf(_sectionOneLine) + precisionErrorTolerance;
    final daysOnOneLine =
        heightOf(_dayWrapped) <=
        heightOf(_dayOneLine) + precisionErrorTolerance;
    final month = heightOf(
      sectionsOnOneLine ? _sectionOneLine : _sectionWrapped,
    );
    final extents = _RowExtents(
      headers: AgendaHeaderSlots(
        sectionsOnOneLine: sectionsOnOneLine,
        daysOnOneLine: daysOnOneLine,
        sectionHeight: month,
        dayReadHeight: heightOf(
          daysOnOneLine ? _dayBareOneLine : _dayBareWrapped,
        ),
      ),
      month: month,
      dayRead: heightOf(daysOnOneLine ? _dayOneLine : _dayWrapped),
      entry: heightOf(_plain[1]),
      entryEnd: heightOf(_plain[2]),
      entryCaption: heightOf(_captioned[1]),
      entryCaptionEnd: heightOf(_captioned[2]),
      caption: heightOf(_tails[_ListTail.loading.index]),
      capCaption: heightOf(_tails[_ListTail.capped.index]),
    );
    if (extents.month <= 0 ||
        extents.dayRead <= 0 ||
        extents.entryCaptionEnd <= 0 ||
        extents.capCaption <= 0) {
      return;
    }
    widget.onMeasured(extents);
  }

  /// The widest of [labels] as [style] draws it at the ambient scale.
  static String _widest(
    BuildContext context,
    Iterable<String> labels,
    TextStyle? style,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = '';
    var widestWidth = -1.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widestWidth) {
        widest = label;
        widestWidth = painter.width;
      }
      painter.dispose();
    }
    return widest;
  }

  /// The day whose read row's label is the widest the list can show: every
  /// weekday in every month of the year at a two-digit day — the read row's
  /// own format, `DateFormat` over the locale's names, with the year a
  /// period across New Year adds, so no period needs another measurement —
  /// and Today and Tomorrow.
  DateTime _widestDay(BuildContext context, AgendaDayListRowBuilder rows) {
    final l10n = AppLocalizations.of(context)!;
    final today = widget.today;
    final days = <String, DateTime>{
      for (var month = 1; month <= 12; month++)
        for (var day = 22; day <= 28; day++)
          _dayLabel(l10n, rows, DateTime.utc(today.year, month, day)):
              DateTime.utc(today.year, month, day),
      _dayLabel(l10n, rows, today): today,
      _dayLabel(l10n, rows, today.add(const Duration(days: 1))): today.add(
        const Duration(days: 1),
      ),
    };
    final style = FormLabelValue.labelStyle(
      Theme.of(context).colorScheme.onSurface,
    );
    return days[_widest(context, days.keys, style)]!;
  }

  String _dayLabel(
    AppLocalizations l10n,
    AgendaDayListRowBuilder rows,
    DateTime day,
  ) => AgendaListView.dayHeaderLabel(
    l10n,
    day,
    rows.today,
    withYear: rows.dayHeaderWithYear,
  );

  /// The month whose label is the widest: the twelve of the year, with the
  /// year, in the section label's capitals — the pinned label's form.
  DateTime _widestMonth(BuildContext context) {
    final localeName = AppLocalizations.of(context)!.localeName;
    final months = <String, DateTime>{
      for (var month = 1; month <= 12; month++)
        FormSectionLabel.capitals(
          AgendaListView.monthLabel(
            localeName,
            DateTime.utc(widget.today.year, month),
            withYear: true,
          ),
        ): DateTime.utc(
          widget.today.year,
          month,
        ),
    };
    final style = FormSectionLabel.textStyle(Theme.of(context));
    return months[_widest(context, months.keys, style)]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.measure) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
    final color = Theme.of(context).colorScheme.primary;
    final today = widget.today;
    AgendaDayListEntryRow entry(String? caption) => AgendaDayListEntryRow(
      entry: AgendaDayListEntry(
        day: today,
        icon: Icons.event_rounded,
        color: color,
        title: today.toIso8601String(),
        subtitle: caption,
      ),
    );
    final day = AgendaDayListDayRow(day: today, count: 1, missed: 1);
    final plain = <AgendaDayListRow>[day, entry(null), entry(null)];
    final captioned = <AgendaDayListRow>[
      day,
      entry(today.toIso8601String()),
      entry(today.toIso8601String()),
    ];
    final plainRows = widget.builderOf(plain);
    final captionedRows = widget.builderOf(captioned);
    AgendaDayListRowBuilder headerRows(
      List<AgendaDayListRow> rows,
      bool oneLine,
    ) => widget.builderOf(
      rows,
      headers: oneLine ? _oneLine : _wrapped,
      dayHeaderWithYear: true,
    );
    final widestDay = _widestDay(context, headerRows(const [], true));
    final section = <AgendaDayListRow>[
      AgendaDayListMonthRow(
        month: _widestMonth(context),
        showYear: true,
        kept: _widestCount,
        missed: _widestCount,
      ),
    ];
    final dayRead = <AgendaDayListRow>[
      AgendaDayListDayRow(
        day: widestDay,
        count: _widestCount,
        missed: _widestCount,
      ),
    ];
    Widget header(GlobalKey key, List<AgendaDayListRow> rows, bool oneLine) =>
        KeyedSubtree(
          key: key,
          child: headerRows(rows, oneLine).build(context, 0),
        );
    Widget bare(GlobalKey key, bool oneLine) => KeyedSubtree(
      key: key,
      child: headerRows(dayRead, oneLine).readRow(
        context,
        day: widestDay,
        kept: _widestCount,
        missed: _widestCount,
      ),
    );
    return Offstage(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: TickerMode(
            enabled: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(_sectionOneLine, section, true),
                header(_sectionWrapped, section, false),
                header(_dayOneLine, dayRead, true),
                header(_dayWrapped, dayRead, false),
                bare(_dayBareOneLine, true),
                bare(_dayBareWrapped, false),
                for (var i = 0; i < plain.length; i++)
                  KeyedSubtree(
                    key: _plain[i],
                    child: plainRows.build(context, i),
                  ),
                for (var i = 0; i < captioned.length; i++)
                  KeyedSubtree(
                    key: _captioned[i],
                    child: captionedRows.build(context, i),
                  ),
                for (final tail in _ListTail.values)
                  KeyedSubtree(
                    key: _tails[tail.index],
                    child: _CalendarOverviewPageState._tailCaption(
                      AppLocalizations.of(context)!,
                      tail,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
