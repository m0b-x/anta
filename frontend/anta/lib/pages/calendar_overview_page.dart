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
import '../models/calendar_event.dart';
import '../models/date_range.dart';
import '../models/day_bar.dart';
import '../models/overview_list_options.dart';
import '../models/overview_period.dart';
import '../models/overview_view.dart';
import '../services/agenda_search_text.dart';
import '../services/alert_keep_notice.dart';
import '../services/app_navigator.dart';
import '../services/overview_view_service.dart';
import '../services/settings_service.dart';
import '../utils/agenda_day_list_index.dart';
import '../utils/agenda_month_store.dart';
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

class _CalendarOverviewPageState extends State<CalendarOverviewPage>
    with RouteAware, WidgetsBindingObserver {
  static final DateTime _firstMonth = AgendaMonthStore.monthOf(
    CalendarBounds.earliest,
  );
  static final DateTime _lastMonth = AgendaMonthStore.monthOf(
    CalendarBounds.latest,
  );

  CalendarAppearance _appearance = const CalendarAppearance();

  /// The markdown palette a row's detail sheet renders the description in.
  MarkdownColorPalette _palette = MarkdownColorPalette.presets;

  /// Guards the detail sheet a row opens, and the trip from it, against a
  /// double tap.
  final SheetGuard _sheetGuard = SheetGuard();

  /// How many Keeps this page has heard of; a detail-sheet trip compares it
  /// at its start and after each step, as on the calendar.
  int _keepsHeard = 0;

  late final EventSheetsFlow _sheets = EventSheetsFlow(
    guard: _sheetGuard,
    appearance: () => _appearance,
    palette: () => _palette,
    keepsHeard: () => _keepsHeard,
  );

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

  /// The period as picked — the Period menu's last pick, or the persisted
  /// one — which the list nav's Today slot returns to (D15b). A step and
  /// year paging move [_period] and never this.
  late OverviewPeriod _home;

  /// Set when the persisted period is not a year: year mode opens on the
  /// period's first year, as a switch into it does, once the year bounds the
  /// events give are known (review 7).
  bool _yearFromPeriod = false;
  OverviewListOptions _options = OverviewListOptions.defaults;

  /// The saved views (D17), awaited once and held: the bar button asks it
  /// for a match on every rebuild, which its cache answers with no query.
  /// Null until it answers, and the button is disabled until then.
  OverviewViewService? _viewService;

  /// The years the chosen events can be in — what the list's periods, the
  /// month pages and the range picker reach. Always holds today's year.
  AgendaYearBounds _years = (first: 0, last: 0);

  /// The year scroll's span: [_years] with an open-ended series ending it
  /// next year (D28) — the scroll's sections, its chevrons' stops and where
  /// a landing in year mode is clamped. Only the scroll lays every year out
  /// at once; nothing else is narrowed by the ceiling.
  AgendaYearBounds _scrollYears = (first: 0, last: 0);

  /// Year mode's scroll, kept across mode switches: it holds the year to
  /// open on while no scroll is laid out.
  late final AgendaYearScrollController _yearScroll =
      AgendaYearScrollController(
        initialYear: _year,
        onTopYearChanged: _onYearScrolled,
        // An animated landing resolves nothing on its way; where it stopped
        // is queued once it ends.
        onLanded: _scheduleYearRun,
      );

  /// Each year's tiles once all its months are resolved (D30): all the year
  /// scroll's sections read, so a section that scrolls in folds nothing,
  /// and a year written rebuilds its own section alone.
  final AgendaYearTileSource _yearTiles = AgendaYearTileSource();

  /// The years of [_yearTiles] folded before the query or a month under
  /// them last changed — only those in and next to the viewport, the rest
  /// are dropped then ([_rebuild]). They stay on screen — a keystroke never
  /// blanks a section — and are folded again: from what the store holds in
  /// [_recompute], otherwise by a run.
  final Set<int> _staleTileYears = {};

  /// The generation the pending year run was scheduled under; null while
  /// none is pending ([_scheduleYearRun]).
  int? _yearRunGeneration;

  /// Set by a year's scan until the frame that draws its result is over: a
  /// run that comes due meanwhile waits for the frame after it, so a frame
  /// that drew a scan's result runs no other scan.
  bool _yearFrameOwed = false;

  /// Whether the top year's tiles are resolved, so the band's count and
  /// totals are its own rather than blank.
  bool _yearTallied = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Whether the chip row's search button has revealed the Search row;
  /// session-only like the query, and closed on open.
  bool _searchOpen = false;
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

  /// The marks a row's presence button dispatched whose presence bump has not
  /// come back yet, oldest first. A bump they account for re-resolves only
  /// their months ([_forgetMarked]): a new store would list a long period in
  /// runs again, shrinking the list under the finger before its next tap.
  final List<(String eventId, DateTime day)> _pendingMarks = [];

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

  /// The picked day's entries before Missed only narrows them
  /// ([_pickedDayEntries]), and its read row's counts folded from them —
  /// kept 0 under Missed only — so the frame counts nothing.
  List<AgendaDayListEntry> _pickedEntries = const [];
  int _pickedKept = 0;
  int _pickedMissed = 0;
  int _yearKept = 0;
  int _yearMissed = 0;

  /// The list's entries after every filter, for the nav's count.
  int _listedKept = 0;
  int _listedMissed = 0;

  /// What the totals caption counts per category id in the current mode
  /// (D16): the kept entries, or the missed ones while Missed only narrows
  /// the mode.
  Map<String, int> _totals = {};

  /// Kept marks per category per month key, folded as the year tiles'
  /// marks are resolved, so year mode's totals cost no rows (the tiles are
  /// marks only). Lives as long as [_store]; a month absent here was
  /// resolved as a bucket and is counted from its entries.
  final Map<int, Map<String, int>> _markedKept = {};

  /// Every day with an occurrence in the allowlist per month key, a bit per
  /// day, hidden missed ones included (D32): under the hidden display such a
  /// day lists nothing in the bucket, yet it is still a day to pick and
  /// mark. Folded as [_resolve] scans, so it lives as long as [_store].
  final Map<int, int> _occurrenceMask = {};

  /// The navs' title templates and the locale and year they were built for
  /// ([_titleTemplates]).
  String? _titleTemplatesKey;
  List<String> _titleTemplatesCache = const [];

  /// The totals caption, the saved view the list shown is, and whether the
  /// list nav's chevrons reach anywhere — all four folded on navigation
  /// ([_foldNav]), never in a frame.
  String _totalsCaption = '';
  OverviewView? _activeView;
  bool _canStepBack = false;
  bool _canStepForward = false;

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

  /// A page pushed over this one — an alert's calendar, the note editor,
  /// settings, Alerts — can edit events, and every edit emits. Resolving a
  /// whole period for each one underneath would be pure waste, so the state
  /// is parked while covered and adopted on return; the same holds while a
  /// row's detail sheet holds [_sheetGuard] (see [_onStateChanged]).
  PageRoute<dynamic>? _route;
  bool _covered = false;
  CalendarPageState? _pendingState;

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

  /// Reloads the bloc after a Keep on the alarm page cleared an event's
  /// "remove after it rings" behind its back, and counts it, so a detail
  /// sheet open here learns that a Keep happened.
  ///
  /// Never takes the notice. A calendar beneath this page registered first
  /// and has taken it already — its reload is on its way — when the flag is
  /// down here. With no calendar beneath, the alarm page's Open event may
  /// push one over this page next, and that calendar must still find the
  /// flag standing: it is how it knows its initial target may predate the
  /// Keep and defers the sheet to the reload.
  void _serveKeepNotice() {
    if (!mounted) return;
    _keepsHeard++;
    if (!AlertKeepNotice.instance.hasPending) return;
    context.read<CalendarBloc>().add(const LoadCalendarEvents());
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

  /// Whether the wall clock has moved [_today] to another day. Across New
  /// Year, This year moves on with it — the period and the year it opens
  /// year mode on — except in year mode, whose scroll holds the year shown.
  bool _refreshToday() {
    final today = EventAgenda.dateOnly(DateTime.now());
    if (today == _today) return false;
    final before = _today;
    _today = today;
    _home = _home.followingToday(before: before, today: today);
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
    _palette = loaded.palette;
    _categoryIds = loaded.categoryIds;
    _mode = loaded.mode;
    _period = _home = loaded.period;
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
    // A look that arrived while the settings loaded wins over what they kept.
    _serveOverviewLook();
  }

  Future<void> _loadViews() async {
    try {
      final service = await OverviewViewService.getInstance();
      if (!mounted) return;
      setState(() {
        _viewService = service;
        _foldNav();
      });
    } catch (e) {
      debugPrint('[CalendarOverviewPage] Saved views load failed: $e');
    }
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
      _palette = loaded.palette;
      if (loaded.appearance != _appearance) {
        _appearance = loaded.appearance;
        _storeStale = true;
      }
    }
    // A page pushed from inside a row's trip returns to the trip: what was
    // parked waits for its end.
    final pending = _sheetGuard.isOpen ? null : _pendingState;
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
      _scheduleYearRun();
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

  /// Parked while covered, and while a row's detail sheet holds
  /// [_sheetGuard]: a sheet never fires the route observer, yet every tick
  /// in it gives the bloc's list a new identity, and the period under the
  /// sheet would be resolved anew for each. The trip's end adopts what was
  /// parked, once ([_openOn]).
  void _onStateChanged(CalendarPageState state) {
    if (_covered || _sheetGuard.isOpen) {
      _pendingState = state;
      // What is adopted later may carry presence writes of the sheet or the
      // page above, which no mark accounts for: that state takes a new store.
      _pendingMarks.clear();
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
    final adopted = _adoptedInputs;
    if (inputs != adopted) {
      _adoptedInputs = inputs;
      if (!_forgetMarked(adopted, inputs)) _storeStale = true;
    }
    if (_refreshCategoryLabels()) _storeStale = true;
  }

  /// Whether [next] moved from [previous] by nothing but presence bumps the
  /// pending marks account for. Then the marks' months — and only they — are
  /// dropped from the store and resolved again at once, so the rows fold
  /// anew under the same keys and the list's anchor finds its row in the
  /// same frame (review 1). Any other bump — the detail sheet's pair, adopted
  /// as its trip ends — is left to a new store, as is a bump arriving with
  /// the list, the membership or the store itself moved. The bumps consume
  /// the oldest marks either way; a mark's month is forgotten with every
  /// bump until its own is consumed, since writes may land out of order.
  bool _forgetMarked(
    (List<CalendarEvent>?, int, int)? previous,
    (List<CalendarEvent>?, int, int) next,
  ) {
    if (previous == null || _pendingMarks.isEmpty) return false;
    final (events, membership, presence) = next;
    final bumps = presence - previous.$3;
    if (bumps <= 0) return false;
    final months = {
      for (final (_, day) in _pendingMarks) AgendaMonthStore.keyOf(day),
    };
    final accounted = bumps <= _pendingMarks.length;
    if (accounted) {
      _pendingMarks.removeRange(0, bumps);
    } else {
      _pendingMarks.clear();
    }
    final store = _store;
    if (!accounted ||
        store == null ||
        _storeStale ||
        !identical(events, previous.$1) ||
        membership != previous.$2) {
      return false;
    }
    for (final key in months) {
      final month = AgendaMonthStore.monthOfKey(key);
      final resolved = store.isResolved(month);
      store.forget(month);
      // The year tiles' kept marks of this month are folded anew with its
      // tally; the filtered months, the bars and the tiles go whole with
      // [_rebuild].
      _markedKept.remove(key);
      // A listed month must be back before [_listMore] runs: it extends the
      // synchronous part over resolved months only, and stopping at this one
      // would leave the rest to runs, which is the shrink this path avoids.
      if (resolved) store.ensure([month]);
    }
    return true;
  }

  /// Resolves what the current presentation shows through the query, then
  /// repaints — and, while the list shows, keeps it on the row it was on.
  /// Every input funnels through here: the events and their revisions, the
  /// categories, the query, the locale, the appearance. Those that feed the
  /// resolvers set [_storeStale] first, and only then is every resolved
  /// month dropped and the year bounds re-derived; a query alone keeps the
  /// store and refilters what it holds (T3).
  ///
  /// [duringBuild] is a call from [didChangeDependencies]: the rebuild is
  /// still immediate, but year mode's shown year is resolved after the frame
  /// — its section shows the placeholder for that one frame — so no scan
  /// runs inside the build phase.
  void _rebuild({bool duringBuild = false}) {
    final events = _events;
    final l10n = _l10n;
    _filteredMonths.clear();
    _filteredBars.clear();
    if (events == null || !_settingsLoaded || l10n == null) {
      _resolveGeneration++;
      _store = null;
      _markedKept.clear();
      _occurrenceMask.clear();
      _clearTiles();
      _storeStale = true;
      _rows = const [];
      _monthBucket = null;
      _foldNav();
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
      // The year scroll lays every year out at once, so there an open-ended
      // series ends the span next year rather than at the calendar's
      // ceiling (D28); the list, the month pages and the range picker keep
      // every year an event can fire in.
      final spans = EventAgenda.yearSpansOf(
        events,
        categoryIds: _categoryIds,
        todayYear: _today.year,
        earliestYear: CalendarBounds.earliest.year,
        latestYear: CalendarBounds.latest.year,
        openEndedLastYear: _today.year + 1,
      );
      _years = spans.full;
      _scrollYears = spans.ceiled;
      if (_yearFromPeriod) {
        _yearFromPeriod = false;
        _year = _firstYearOf(_period);
      } else {
        _year = _year.clamp(_years.first, _years.last);
      }
      if (_mode == AgendaDayListMode.year) _clampYearToScroll();
      // A laid-out scroll keeps its own top year through a span change.
      if (!_yearScroll.isAttached) _yearScroll.jumpToYear(_year);
      _markedKept.clear();
      _occurrenceMask.clear();
      _clearTiles();
      final store = _store = AgendaMonthStore(
        resolve: _resolve,
        resolveMarks: _resolveMarks,
        maxBars: AgendaMonthGrid.maxBarsFor(_appearance),
      );
      widget._onStore?.call(store);
    } else {
      // The same store under a new query, or with a month forgotten. The
      // years in and next to the viewport keep their tiles on screen until
      // their refold replaces them — in [_recompute] when the store holds
      // them, otherwise by the runs, which take them first — so a keystroke
      // never blanks a section. Every other year is dropped: a far year
      // scrolled in later draws the placeholder until its run, never the
      // tiles of the query before as if they were current.
      final near = _nearYears();
      _yearTiles
        ..removeWhere((year) => !near.contains(year))
        ..notify();
      _staleTileYears
        ..clear()
        ..addAll(_yearTiles.years);
    }
    if (mounted) {
      final inYear = _mode == AgendaDayListMode.year;
      setState(() {
        // The year shown is resolved before its frame, so neither the first
        // frame nor a rebuild under it draws it blank — mid-landing the
        // year it is bound for, which the passing years only lead to.
        if (inYear && !duringBuild) _resolveYear(_shownYearTarget);
        _recompute();
      });
      if (inYear && duringBuild) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Covered, nothing is resolved: the return queues the shown year
          // with the rest ([didPopNext]).
          if (!mounted || _covered || _mode != AgendaDayListMode.year) return;
          final target = _shownYearTarget;
          if (_tilesCurrent(target)) return;
          setState(() {
            _resolveYear(target);
            _tallyYear(_year);
            _foldNav();
          });
        });
      }
    }
    final landing = _landOnOpen;
    _landOnOpen = false;
    if (landing && _mode == AgendaDayListMode.list) {
      _land();
    } else if (anchor != null) {
      _aimList(anchor);
    }
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
    final occurrences = _scan(start, end);
    for (final month in _monthsOf((start: start, end: end))) {
      _occurrenceMask[AgendaMonthStore.keyOf(month)] = 0;
    }
    for (final occurrence in occurrences) {
      final key = AgendaMonthStore.keyOf(occurrence.day);
      // A day the scan returned outside the span has no mask seeded above:
      // folded into a fresh one, since a release build has no assert to stop
      // it and this runs inside `setState`.
      _occurrenceMask[key] =
          (_occurrenceMask[key] ?? 0) | (1 << (occurrence.day.day - 1));
    }
    return AgendaListView.eventDayEntries(
      occurrences,
      _l10n!,
      false,
      showRecurrenceLabels: _appearance.showRecurrenceLabels,
      missedDisplay: _appearance.missedDisplay,
    );
  }

  List<AgendaDayMark> _resolveMarks(DateTime start, DateTime end) {
    final occurrences = _scan(start, end);
    for (final month in _monthsOf((start: start, end: end))) {
      _markedKept[AgendaMonthStore.keyOf(month)] = {};
    }
    for (final occurrence in occurrences) {
      final event = occurrence.event;
      if (EventPresence.appliesTo(event) &&
          EventPresence.isMissed(event, occurrence.day)) {
        continue;
      }
      // [_resolve]'s reasoning: a day outside the span gets its own counts
      // rather than a null check the asserts alone guard.
      final counts = _markedKept.putIfAbsent(
        AgendaMonthStore.keyOf(occurrence.day),
        () => <String, int>{},
      );
      final category = CalendarCategories.resolve(event.categoryId).id;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return AgendaListView.eventDayMarks(
      occurrences,
      missedDisplay: _appearance.missedDisplay,
    );
  }

  /// Resolves what the presentation shows and rebuilds its rows or tiles, so a
  /// frame folds nothing. Called inside `setState` on navigation only. In
  /// year mode it folds the years in and next to the viewport from what the
  /// store holds and queues a run for the rest, so no recompute leaves a
  /// visible placeholder unqueued.
  void _recompute() {
    _resolveGeneration++;
    _rowsBase = null;
    final store = _store;
    if (store == null) {
      _foldNav();
      return;
    }
    switch (_mode) {
      case AgendaDayListMode.year:
        _rows = const [];
        _monthBucket = null;
        _takePicked(const []);
        for (final year in _nearYears()) {
          if (!_tilesCurrent(year) && _yearHeld(year)) _resolveYear(year);
        }
        _tallyYear(_year);
        _scheduleYearRun();
      case AgendaDayListMode.list:
        _monthBucket = null;
        _takePicked(const []);
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
        _totals = {};
        _tally(_totals, bucket.entries);
        final selected = _selectedDay;
        if (selected == null) {
          _takePicked(const []);
          _rows = buildAgendaDayListRows(
            bucket.days,
            (day) => _listed(bucket.entriesOn(day)),
            groupByDay: true,
            withMonths: false,
            keptCountOf: _options.missedOnly
                ? (_) => 0
                : bucket.keptCountForDay,
          );
        } else {
          _takePicked(_pickedDayEntries(selected));
          final listed = _listed(_pickedEntries);
          final kept = _pickedKept;
          _rows = buildAgendaDayListRows(
            [selected],
            (_) => listed,
            groupByDay: false,
            withMonths: false,
            keptCountOf: (_) => kept,
          );
        }
    }
    _foldNav();
  }

  /// Folds what the chrome reads out of the state a navigation just set: the
  /// totals caption, the saved view the list shown matches and the reach of
  /// the list nav's two chevrons. [_titleTemplates]'s reasoning — a frame
  /// walks no category catalog, scans no saved list and resolves no period
  /// twice over just to enable a button.
  void _foldNav() {
    final l10n = _l10n;
    _totalsCaption = l10n == null ? '' : _totalsLabel(l10n);
    _activeView = _viewService?.matching(_shownPeriod, _options, _categoryIds);
    _canStepBack = _steppedPeriod(-1) != null;
    _canStepForward = _steppedPeriod(1) != null;
  }

  /// Holds [entries] as the picked day's and folds its read row's counts.
  void _takePicked(List<AgendaDayListEntry> entries) {
    _pickedEntries = entries;
    var missed = 0;
    for (final entry in entries) {
      if (entry.missed) missed++;
    }
    _pickedMissed = missed;
    _pickedKept = _options.missedOnly ? 0 : entries.length - missed;
  }

  /// The picked day as the day panel lists it (D32): scanned on its own and
  /// converted under `faded`, so under the hidden display its missed and
  /// assumed-absent occurrences still show — dimmed, with the button that
  /// marks them — where the month's bucket has dropped them. Under `faded`
  /// this is exactly the bucket's day. The query narrows it as it narrows
  /// the bucket; Missed only is left to the rows, the read row counts all.
  List<AgendaDayListEntry> _pickedDayEntries(DateTime day) {
    final entries = AgendaListView.eventDayEntries(
      _scan(day, day),
      _l10n!,
      false,
      showRecurrenceLabels: _appearance.showRecurrenceLabels,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    final matcher = _matcher;
    if (matcher == null) return entries;
    return [
      for (final entry in entries)
        if (_matches(matcher, entry)) entry,
    ];
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
        setState(() {
          _listMore(OverviewListMetrics.batchMonths);
          // A run appends months, so it moves the totals the caption reads:
          // the chrome folds after a background run exactly as it folds
          // after a navigation.
          _foldNav();
        });
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
      _totals = {};
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
      // [shown] is already in reading order — the loop above walked the days
      // under the order in force — so it is never reversed a second time.
      for (final day in shown) ...entriesOf(day),
    ];
    final missed = listed.where((entry) => entry.missed).length;
    _listedKept += listed.length - missed;
    _listedMissed += missed;
    _tally(_totals, listed);
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

  /// Adds [entries] to [totals] per category: the kept ones, or the missed
  /// ones while Missed only narrows this mode — year mode's tiles ignore it,
  /// as its count does (D16a).
  void _tally(Map<String, int> totals, Iterable<AgendaDayListEntry> entries) {
    final missed = _options.missedOnly && _mode != AgendaDayListMode.year;
    for (final entry in entries) {
      if (entry.missed != missed) continue;
      final category = _categoryOf(entry);
      totals[category] = (totals[category] ?? 0) + 1;
    }
  }

  /// The totals caption (D16): the categories with a count in catalog order,
  /// [OverviewListMetrics.namedTotals] of them named and the rest summed up
  /// as "+N more"; empty
  /// when nothing is listed.
  String _totalsLabel(AppLocalizations l10n) {
    final parts = <String>[];
    var rest = 0;
    for (final category in CalendarCategories.all) {
      final count = _totals[category.id];
      if (count == null || count == 0) continue;
      if (parts.length < OverviewListMetrics.namedTotals) {
        final label = CalendarCategories.labelOf(category, l10n);
        parts.add(l10n.overviewCategoryTotal(label, count));
      } else {
        rest++;
      }
    }
    if (rest > 0) parts.add(l10n.categoriesMore(rest));
    return parts.join(' · ');
  }

  /// Whether [day] has anything listed: the store's mask, or the narrowed
  /// month's while a query is live. Cache-only, for the grid's builder.
  bool _hasEntry(DateTime day) {
    if (_matcher == null) return _store?.hasEntry(day) ?? false;
    final mask = _filteredMonths[AgendaMonthStore.keyOf(day)]?.markedMask ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  /// Whether [day] is one to pick in month mode (D32): one with an entry,
  /// or under the hidden display one whose occurrences were all dropped as
  /// missed — the picked day lists them ([_pickedDayEntries]). A live query
  /// keeps every other day to [_hasEntry]: a dropped occurrence was never
  /// matched against it. Cache-only, for the grid's builder.
  bool _hasOccurrence(DateTime day) {
    if (_hasEntry(day)) return true;
    // The picked cell agrees with its rows, which a query matches faded.
    if (day == _selectedDay && _pickedEntries.isNotEmpty) return true;
    if (_matcher != null || !_missedHidden) return false;
    final mask = _occurrenceMask[AgendaMonthStore.keyOf(day)] ?? 0;
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

  /// Drops every year's tiles: the store they were folded from is gone.
  void _clearTiles() {
    _yearTiles
      ..clear()
      ..notify();
    _staleTileYears.clear();
  }

  /// Whether [year]'s tiles are folded from the store and query as they are
  /// now — not stale, not missing.
  bool _tilesCurrent(int year) =>
      _yearTiles.holds(year) && !_staleTileYears.contains(year);

  /// The year the scroll shows next: the one a landing under way is bound
  /// for, else the top year — inside the scroll's span, which a bloc emit
  /// may just have narrowed under the landing.
  int get _shownYearTarget => (_yearScroll.landingYear ?? _year).clamp(
    _scrollYears.first,
    _scrollYears.last,
  );

  /// Whether the store holds every month of [year] in the shape its tiles
  /// fold from — a tally or its rows, only its rows while a query is live —
  /// so resolving the year scans nothing.
  bool _yearHeld(int year) {
    final store = _store!;
    for (final month in AgendaMonthStore.monthsOfYear(year)) {
      if (store.isResolved(month)) continue;
      if (_matcher == null && store.cachedTally(month) != null) continue;
      return false;
    }
    return true;
  }

  /// Resolves [year]'s twelve months — one marks call, or the rows while a
  /// query is live, nothing for what the store holds — and folds its tiles
  /// from marks, each day in its top entry's colour so several categories on
  /// one tile stay tellable apart; under a query from the narrowed months,
  /// which costs the year's rows once and then nothing per keystroke. On
  /// navigation only: the opening year and a landing's target before their
  /// frame, the years in and next to the viewport in [_recompute] when held,
  /// every other year in a run ([_scheduleYearRun]). The sections read
  /// [_yearTiles] and fold nothing; only [year]'s section rebuilds.
  void _resolveYear(int year) {
    if (_tilesCurrent(year)) return;
    final store = _store;
    if (store == null) return;
    // A held year costs no scan, so only a scan holds the next run back.
    if (!_yearHeld(year)) _oweYearFrame();
    final months = AgendaMonthStore.monthsOfYear(year);
    if (_matcher != null) {
      store.ensure(months);
      _yearTiles.put(year, [
        for (final month in months)
          AgendaYearTile.ofTally(
            AgendaMonthTally.ofBucket(_bucketOf(month)),
            perDayColors: true,
          ),
      ]);
    } else {
      store.ensureTallies(months);
      _yearTiles.put(year, [
        for (final month in months)
          AgendaYearTile.ofTally(store.cachedTally(month)!, perDayColors: true),
      ]);
    }
    _staleTileYears.remove(year);
    _yearTiles.notify();
  }

  /// Holds year runs back until the frame that draws a scan's result is
  /// over. A run's scan comes at a frame's end and is drawn by the next
  /// one, whose end is where the flag drops and the next run fires: one
  /// year per frame. A scan anywhere else — a tap, a landing, a bloc emit —
  /// is drawn by the coming frame, and a run registered after it would fire
  /// at that same frame's end: the flag drops a frame later instead, so the
  /// frame that drew the scan's result runs no other scan.
  void _oweYearFrame() {
    if (_yearFrameOwed) return;
    _yearFrameOwed = true;
    final binding = WidgetsBinding.instance;
    void release(Duration _) => _yearFrameOwed = false;
    if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      binding.addPostFrameCallback(release);
    } else {
      binding.addPostFrameCallback(
        (_) => binding.addPostFrameCallback(release),
      );
    }
    binding.ensureVisualUpdate();
  }

  /// The band's count and totals for [year], read from its resolved tiles;
  /// blank while it is unresolved — the text changes, never the band's
  /// height — until the run that resolves it repaints.
  void _tallyYear(int year) {
    final tiles = _tilesCurrent(year) ? _yearTiles.tilesFor(year) : null;
    _yearTallied = tiles != null;
    if (tiles == null) {
      _yearKept = 0;
      _yearMissed = 0;
      _totals = {};
      return;
    }
    var kept = 0;
    var missed = 0;
    for (final tile in tiles) {
      kept += tile.count;
      missed += tile.missedCount;
    }
    _yearKept = kept;
    _yearMissed = missed;
    // The tiles above are folded from every month of the year: as rows while
    // a query is live, otherwise as marks (folded into [_markedKept]) or as
    // the rows a list or month look resolved before.
    final store = _store!;
    final totals = <String, int>{};
    for (final month in AgendaMonthStore.monthsOfYear(year)) {
      final marked = _matcher == null
          ? _markedKept[AgendaMonthStore.keyOf(month)]
          : null;
      if (marked != null) {
        marked.forEach((category, count) {
          totals[category] = (totals[category] ?? 0) + count;
        });
      } else if (_matcher != null) {
        _tally(totals, _bucketOf(month).entries);
      } else if (store.cached(month) case final bucket?) {
        _tally(totals, bucket.entries);
      }
    }
    _totals = totals;
  }

  /// The years in and next to the viewport, most wanted first: the top year,
  /// then those whose sections show in the viewport in reading order, then
  /// the top year's two neighbours — inside the span. Read from the scroll
  /// as it is when asked, so a year scrolled past is never among them.
  List<int> _nearYears() {
    if (_store == null || _mode != AgendaDayListMode.year) return const [];
    final visible = _yearScroll.visibleYears;
    final near = <int>[];
    void add(int year) {
      if (year < _scrollYears.first || year > _scrollYears.last) return;
      if (!near.contains(year)) near.add(year);
    }

    add(_year);
    if (visible != null) {
      for (var year = visible.first; year <= visible.last; year++) {
        add(year);
      }
    }
    add(_year - 1);
    add(_year + 1);
    return near;
  }

  /// What a year run should resolve: [_nearYears] whose tiles are not
  /// current.
  List<int> _wantedYears() => [
    for (final year in _nearYears())
      if (!_tilesCurrent(year)) year,
  ];

  /// The next year run when a year is wanted and no run is pending: at the
  /// end of the next frame, once it is drawn (a post-frame callback, a frame
  /// asked for if none is coming). A run resolves exactly one year, the most
  /// wanted when it fires, and one that finds a scan's frame still owed
  /// ([_yearFrameOwed]) waits for the frame after it: so at most one year
  /// resolves per frame, always after the frame the last one's repaint asked
  /// for, and a fling across a decade costs one marks call per frame at
  /// most. Never a timer — a turn-later run would land before the next frame
  /// as well as after it, and a chain cut short would leave it pending.
  /// Nothing is queued while an animated landing is under way — the years it
  /// passes are not stopped on — and [AgendaYearScrollController.onLanded]
  /// queues where it ends. Under [_resolveGeneration], like the list's runs;
  /// nothing runs while a page covers this one, and [didPopNext] schedules
  /// again.
  void _scheduleYearRun() {
    if (_covered || !mounted || _yearScroll.isLanding) return;
    final generation = _resolveGeneration;
    if (_yearRunGeneration == generation) return;
    if (_wantedYears().isEmpty) return;
    _yearRunGeneration = generation;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _runYear(generation))
      ..ensureVisualUpdate();
  }

  /// One year run (see [_scheduleYearRun]).
  void _runYear(int generation) {
    if (_yearRunGeneration == generation) _yearRunGeneration = null;
    if (!mounted ||
        generation != _resolveGeneration ||
        _covered ||
        _yearScroll.isLanding) {
      return;
    }
    if (_yearFrameOwed) {
      _scheduleYearRun();
      return;
    }
    final wanted = _wantedYears();
    if (wanted.isEmpty) return;
    setState(() {
      _resolveYear(wanted.first);
      _tallyYear(_year);
      _foldNav();
    });
    _scheduleYearRun();
  }

  /// Every scroll notification asks for the years it brought into view, and
  /// so does a metrics change — a width or text-scale change can bring a
  /// section into view without a scroll.
  bool _onYearScrollNotification(Notification notification) {
    if (notification is ScrollNotification ||
        notification is ScrollMetricsNotification) {
      _scheduleYearRun();
    }
    return false;
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
      if (mode == AgendaDayListMode.year) _clampYearToScroll();
      if (mode == AgendaDayListMode.month) {
        _month = _month.year == _year
            ? _month
            : DateTime.utc(_year, _today.year == _year ? _today.month : 1, 1);
      }
      // A switch into Year lands on the year, resolved before its frame.
      if (mode == AgendaDayListMode.year) _resolveYear(_year);
      _recompute();
    });
    // A switch into the list opens it, so it lands as an open does.
    if (mode == AgendaDayListMode.list) _land();
    if (mode == AgendaDayListMode.year) _yearScroll.jumpToYear(_year);
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

  /// Puts [_year] inside the scroll's span as year mode opens: a year paged
  /// to in month mode, or the first year of a span kept from the list, may
  /// lie past D28's ceiling, which only the scroll has. A year period
  /// follows the year, as the scroll would have set it; a span stays the
  /// list's.
  void _clampYearToScroll() {
    final year = _year.clamp(_scrollYears.first, _scrollYears.last);
    if (year == _year) return;
    _year = year;
    if (_period is OverviewYearPeriod) _period = OverviewYearPeriod(year);
  }

  /// A new year at the top of the year scroll — a drag, a fling, the years
  /// an animated landing passes, or the landing itself. The title follows
  /// each; the recompute queues runs for none passed by a landing.
  void _onYearScrolled(int year) {
    // A scroll still fading out under another mode reports nothing to it.
    if (!mounted || _mode != AgendaDayListMode.year || year == _year) return;
    setState(() {
      _year = year;
      _period = OverviewYearPeriod(year);
      _recompute();
    });
  }

  /// Scrolls [year]'s header to the top while the scroll is laid out, its
  /// tiles resolved before the first frame of the way and its neighbours
  /// once it lands; otherwise the year simply changes and the scroll opens
  /// there when it next appears. The chevrons, the Today slot and the
  /// scrubber lane's steps all land here.
  void _goToYear(int year) {
    final target = year.clamp(_scrollYears.first, _scrollYears.last);
    // Mid-landing the scroll is already bound somewhere: where it goes, not
    // the year passing the top, is what a repeat would duplicate.
    if (target == (_yearScroll.landingYear ?? _year)) return;
    _click();
    if (_mode == AgendaDayListMode.year && _yearScroll.isAttached) {
      setState(() => _resolveYear(target));
      unawaited(_yearScroll.animateToYear(target));
    } else {
      _onYearScrolled(target);
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
    // The picked day always lets go: a query may have emptied it since.
    if (day != _selectedDay && !_hasOccurrence(day)) return;
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

  /// The Period menu's pick, live in every mode (D13 · A). A preset applies at
  /// once; Custom range… asks the Dates sheet for a span, seeded with the one
  /// shown, and changes nothing — the mode included — when it is cancelled.
  /// A period is the list's unit, so a pick outside the list opens the list
  /// on it; This year in year mode only pages to this year, which the tiles
  /// already show as a period.
  Future<void> _selectPeriod(OverviewPeriodChoice choice) async {
    final OverviewPeriod period;
    if (choice != OverviewPeriodChoice.custom) {
      period = OverviewPeriod.fromChoice(choice, today: _today);
    } else {
      final picked = await _pickRange();
      if (picked == null) return;
      period = picked;
    }
    final keepsMode =
        _mode == AgendaDayListMode.list ||
        (_mode == AgendaDayListMode.year &&
            choice == OverviewPeriodChoice.thisYear);
    if (keepsMode) {
      _setPeriod(period);
    } else {
      _listPeriod(period);
    }
  }

  /// The Dates sheet's range mode, seeded with the span shown; null when it
  /// is cancelled, already open, or the page has gone.
  Future<OverviewCustomPeriod?> _pickRange() async {
    if (_pickerOpen) return null;
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
      if (picked == null || !mounted) return null;
      return OverviewCustomPeriod(picked.start, picked.end);
    } finally {
      _pickerOpen = false;
    }
  }

  /// The nav's title in every mode (D19 · A): the Period menu, anchored to
  /// the title, its pick taken as [_selectPeriod] takes any.
  Future<void> _openPeriodMenu(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context)!;
    _blur();
    final choice = await showFormMenu<OverviewPeriodChoice>(
      anchor,
      items: [
        for (final choice in OverviewPeriodChoice.values)
          FormMenuItem(
            value: choice,
            label: _periodLabel(l10n, choice),
            icon: _periodIcon(choice),
            identifier: _periodId(choice),
          ),
      ],
      selected: _shownPeriod.menuChoice(today: _today),
      menuWidth: FormMetrics.menuWidth,
      alignment: FormMenuAlignment.center,
    );
    if (choice == null || !mounted) return;
    await _selectPeriod(choice);
  }

  /// The list nav's neighbour of [_period] one step [direction] away, or
  /// null where its chevron is disabled.
  OverviewPeriod? _steppedPeriod(int direction) =>
      _period.stepped(direction: direction, today: _today, yearBounds: _years);

  /// A chevron of the list nav (D15a): a look at the neighbouring span,
  /// never persisted and never the home (D15c), landing as a pick does. A
  /// step back onto the home's own span is the home again (review 5), so the
  /// Period menu checks the preset, Today disables and a saved view matches.
  void _step(int direction) {
    final stepped = _steppedPeriod(direction);
    if (stepped == null) return;
    final home = _home.resolve(today: _today, yearBounds: _years);
    final span = stepped.resolve(today: _today, yearBounds: _years);
    final period = span == home ? _home : stepped;
    _click();
    setState(() {
      _period = period;
      _year = _firstYearOf(period);
      _recompute();
    });
    _land();
  }

  /// The list nav's Today slot (D15b): back to the period as picked.
  void _goHome() {
    _click();
    setState(() {
      _period = _home;
      _year = _firstYearOf(_home);
      _recompute();
    });
    _land();
  }

  /// Turns the page to the list on [period] in one rebuild and one landing —
  /// [_selectMode] then [_setPeriod] would resolve and land twice — and keeps
  /// both the mode and the period for the next visit.
  void _listPeriod(OverviewPeriod period) {
    setState(() {
      _mode = AgendaDayListMode.list;
      _period = _home = period;
      _year = _firstYearOf(period);
      _selectedDay = null;
      _recompute();
    });
    _land();
    unawaited(_persistMode(AgendaDayListMode.list));
    unawaited(_persistPeriod(period));
  }

  /// Lists [period], landing per D7, and persists it — a preset is kept for
  /// the next visit, a custom span clears what was kept. Year mode jumps to the
  /// period's first year, resolved before the frame; the jump lands on the
  /// year already set, so the scroll's report of it leaves the period alone.
  /// A pick of the period already shown is still persisted: scrolling the
  /// years changes the period without writing it, so "This year" picked
  /// after scrolling back to this year is a choice the next visit must see
  /// (review 1).
  void _setPeriod(OverviewPeriod period) {
    _home = period;
    if (period == _period) {
      // The Today slot reads the home, which may just have moved.
      setState(() {});
      // The years' scroll sets the period from the year at its top, so it can
      // sit well inside the section the pick names: the pick still has to
      // bring that year's header back up, or nothing on the page does.
      if (_mode == AgendaDayListMode.year) {
        _yearScroll.jumpToYear(_firstYearOf(period));
      }
      unawaited(_persistPeriod(period));
      return;
    }
    final inYear = _mode == AgendaDayListMode.year;
    setState(() {
      _period = period;
      _year = _firstYearOf(period);
      if (inYear) _resolveYear(_year);
      _recompute();
    });
    if (inYear) _yearScroll.jumpToYear(_year);
    _land();
    unawaited(_persistPeriod(period));
  }

  Future<void> _persistPeriod(OverviewPeriod period) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewPeriod(period, today: _today);
  }

  /// What the title's Period menu checks: the year of the page in Year and
  /// Month mode — a span stepped to in the list is no period of a month's
  /// nav — and the list's period in List mode.
  OverviewPeriod get _shownPeriod => switch (_mode) {
    AgendaDayListMode.year => OverviewYearPeriod(_year),
    AgendaDayListMode.month => OverviewYearPeriod(_month.year),
    AgendaDayListMode.list => _period,
  };

  void _openOptions() {
    _blur();
    unawaited(
      OverviewOptionsSheet.show(
        context,
        initial: _options,
        mode: _mode,
        onChanged: _setOptions,
        categoryIds: _categoryIds,
        onCategoriesChanged: _onCategoriesChanged,
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

  /// The options sheet's Categories row (D22 · A): a new allowlist, already
  /// collapsed to empty when it covers every offered category.
  void _onCategoriesChanged(Set<String> next) {
    if (!mounted) return;
    _categoryIds = next;
    _categoryRevision = null;
    _refreshCategoryLabels();
    _storeStale = true;
    _rebuild();
    unawaited(_persistCategories(next));
  }

  /// The saved views sheet over the list as shown — year mode's year is the
  /// period there, as the Period menu reads it. Rebuilt on return so the bar
  /// button follows a save, a rename or a delete made inside.
  Future<void> _openViews() async {
    _blur();
    // A page left open across midnight would save and update through
    // yesterday's clock — This year stored as last year's number, since the
    // period the sheet writes is the one this page is holding. The resume
    // path's refresh, taken again at the press.
    if (_refreshToday()) {
      _storeStale = true;
      _rebuild();
    }
    await OverviewViewSheet.show(
      context,
      current: OverviewView(
        id: '',
        name: '',
        period: _shownPeriod,
        options: _options,
        categoryIds: _categoryIds,
      ),
      onApply: _applyView,
    );
    // A save, a rename or a delete inside changes what the list matches.
    if (mounted) setState(_foldNav);
  }

  /// Applies [view] as the picks it holds would (D17c · A): the list on its
  /// period — which becomes the nav's home — with its options and its
  /// allowlist, each persisted as its own pick persists, a custom span
  /// clearing the period key per D4. The query stays as typed.
  void _applyView(OverviewView view) {
    if (!mounted) return;
    _listLook(
      period: view.period,
      categoryIds: view.categoryIds,
      options: view.options,
    );
  }

  /// Serves — and clears — the look a digest's tap published through
  /// `AppNavigator.toCalendarOverviewLook` (D13): the list on its span with
  /// its allowlist. The allowlist and the mode persist as picks; the span is
  /// a look and writes nothing, so a period the user kept survives the tap.
  ///
  /// Held until the settings are in — their period and allowlist would
  /// otherwise land over the look — and served by the one overview the
  /// navigator collapsed onto or pushed.
  void _serveOverviewLook() {
    if (!mounted || !_settingsLoaded) return;
    final look = AppNavigator.pendingOverviewLook.value;
    if (look == null) return;
    final route = ModalRoute.of(context);
    if (route != null && !AppNavigator.servesOverviewLook(route)) return;
    // Cleared before it is acted on, so a page mounting later cannot replay
    // a trip already made.
    AppNavigator.pendingOverviewLook.value = null;
    _listLook(
      period: OverviewCustomPeriod(look.start, look.end),
      categoryIds: look.categoryIds,
    );
  }

  /// Turns the page to the list on [period] over [categoryIds] in one
  /// rebuild and one landing — the shared body of a saved view and a digest's
  /// look.
  ///
  /// With [options] it is a view, applied as its picks would be: the options
  /// taken, and the period persisted too, a custom span clearing its key per
  /// D4. Without, it is a look: it lands on exactly what the digest counted,
  /// so a typed query and Missed only — both session-only — are dropped, while
  /// Order and Rows stay the user's and the period key is left alone.
  void _listLook({
    required OverviewPeriod period,
    required Set<String> categoryIds,
    OverviewListOptions? options,
  }) {
    final isView = options != null;
    final next = options ?? _options.copyWith(missedOnly: false);
    final queryDropped =
        !isView && (_query.isNotEmpty || _searchController.text.isNotEmpty);
    if (queryDropped) {
      _searchDebounce?.cancel();
      _searchController.clear();
      _setQuery('');
    }
    final categoriesChanged = !setEquals(categoryIds, _categoryIds);
    setState(() {
      _mode = AgendaDayListMode.list;
      _period = _home = period;
      _year = _firstYearOf(period);
      _selectedDay = null;
      _options = next;
      if (categoriesChanged) {
        _categoryIds = categoryIds;
        _categoryRevision = null;
        _refreshCategoryLabels();
        _storeStale = true;
      } else {
        _recompute();
      }
    });
    // The allowlist is an input of the scan, so a new one rebuilds the store
    // as a category pick does, and a dropped query refilters as a cleared
    // field does; the landing below then wins over its anchor.
    if (categoriesChanged || queryDropped) _rebuild();
    _land();
    unawaited(_persistMode(AgendaDayListMode.list));
    if (options != null) {
      unawaited(_persistPeriod(period));
      unawaited(_persistOptions(options));
    }
    if (categoriesChanged) unawaited(_persistCategories(categoryIds));
  }

  Future<void> _persistCategories(Set<String> categoryIds) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewCategories(categoryIds);
  }

  void _openOccurrence(AgendaDayListEntry entry) =>
      _openOn(entry.day, entry.eventId);

  /// Whether the appearance hides missed entries. A mark on a row the month
  /// or the list draws from its bucket would then take the row away with
  /// nothing there left to undo it (review 2); the picked day is exempt, as
  /// the day panel is (D32).
  bool get _missedHidden =>
      _appearance.missedDisplay == CalendarMissedDisplay.hidden;

  /// Whether the mode shows a row per occurrence — month mode's, and the
  /// list's under Every occurrence — the rows that are a day to mark.
  bool get _dayRowsShown =>
      _mode == AgendaDayListMode.month ||
      (_mode == AgendaDayListMode.list &&
          _options.rows == OverviewRows.everyOccurrence);

  /// Whether month mode shows one picked day, whose rows list its missed
  /// occurrences under every display ([_pickedDayEntries]).
  bool get _pickedDayShown =>
      _mode == AgendaDayListMode.month && _selectedDay != null;

  /// Where the day panel's presence button is offered on the rows: where a
  /// row is a day and a mark keeps its row — missed entries show, or the
  /// rows are the picked day's.
  bool get _presenceOffered =>
      _dayRowsShown && (!_missedHidden || _pickedDayShown);

  /// The day panel's presence toggle from the row's button (2026-10-17): the
  /// explicit status through the bloc, and the row's dimming and its day's
  /// counts are the feedback once the state comes back.
  void _onEntryPresence(AgendaDayListEntry entry, bool missed) {
    final eventId = entry.eventId;
    if (eventId == null) return;
    _click();
    _pendingMarks.add((eventId, entry.day));
    EventSheetsFlow.setOccurrencePresence(
      context.read<CalendarBloc>(),
      eventId,
      entry.day,
      missed,
    );
  }

  /// A per-event row opens the event's last day in the period (D10 · A):
  /// the most recent of what the row counts.
  void _openEventRow(AgendaDayListEventRow row) =>
      _openOn(row.last, row.entry.eventId);

  /// The occurrence's detail sheet over the list (D14 · A): no calendar is
  /// pushed, so back closes the sheet onto the row it came from. Read from
  /// the loaded events, so an event gone since the list was drawn opens
  /// nothing. The bloc states the trip's writes emit are parked while it
  /// runs ([_onStateChanged]) and adopted once at its end.
  void _openOn(DateTime day, String? eventId) {
    if (eventId == null) return;
    _blur();
    // [_events], not [_eventsById]: the list is taken with every adopted
    // state, the map only when the store is resolved anew.
    final events = _events;
    if (events == null) return;
    for (final event in events) {
      if (event.id != eventId) continue;
      unawaited(_openDetail(event, day));
      return;
    }
  }

  Future<void> _openDetail(CalendarEvent event, DateTime day) async {
    await _sheets.openDetail(context, event, day);
    if (!mounted || _covered || _sheetGuard.isOpen) return;
    final pending = _pendingState;
    if (pending == null) return;
    _pendingState = null;
    _adopt(pending);
  }

  /// The rows of the list and of month mode, one geometry per kind (T4, T8):
  /// titles on one line, a caption clamped to one, no pencil — a row opens
  /// its occurrence's detail sheet, where it is edited, and a day row of an
  /// event that keeps attendance carries the day panel's presence button
  /// ([_presenceOffered]). The list's headers take [headers], its slots'
  /// layout; month mode's sliver sizes each row itself, so its headers wrap
  /// as their text needs.
  AgendaDayListRowBuilder _rowBuilder(
    List<AgendaDayListRow> rows, {
    AgendaHeaderSlots? headers,
    bool? dayHeaderWithYear,
  }) {
    return AgendaDayListRowBuilder(
      rows: rows,
      today: _today,
      onEntryTap: _openOccurrence,
      onEntryPresence: _presenceOffered ? _onEntryPresence : null,
      presenceIdentifier: (entry) => switch (entry.eventId) {
        final id? => SemanticsIds.overviewRowPresence(id, entry.day),
        null => null,
      },
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
    final appBar = AppBar(
      titleSpacing: CalendarViewMenu.titleSpacing,
      excludeHeaderSemantics: true,
      title: CalendarViewMenu(
        page: CalendarViewPage.overview,
        onPageSelected: (_) => AppNavigator.switchToCalendar(context),
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
          return Scaffold(
            // The language's ground, which the rows' groups are drawn against.
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
          );
        },
      ),
    );
  }

  /// Badged by the restrictions alone — Missed only and the categories
  /// allowlist — as the calendar's filter button is: Order and Rows
  /// re-present the same entries, and a badge means something is hidden.
  Widget _buildOptionsButton(AppLocalizations l10n) {
    // Missed only narrows the list and month mode's rows; year mode's tiles
    // ignore it, so there it hides nothing (review 10). The allowlist
    // narrows every mode, the tiles included.
    final restrictions =
        (_options.missedOnly && _mode != AgendaDayListMode.year ? 1 : 0) +
        (_categoryIds.isNotEmpty ? 1 : 0);
    return AutomationId(
      identifier: SemanticsIds.overviewOptionsOpen,
      child: IconButton(
        tooltip: l10n.overviewListOptions,
        isSelected: restrictions > 0,
        iconSize: AppBarMetrics.glyphSize,
        // The badge rides the glyph, inside the button's 48 dp box: around
        // the button Material puts a labelled badge 4 dp above its child,
        // which a 48 dp bar's toolbar clip cuts off. Its count stays out of
        // the button's merged node: a label there would replace the tooltip
        // as what Android 9+ announces, and the button would be read as a
        // bare number (a spoken count needs words of its own).
        icon: ExcludeSemantics(
          child: Badge.count(
            count: restrictions,
            isLabelVisible: restrictions > 0,
            child: const Icon(Icons.tune_rounded),
          ),
        ),
        onPressed: _openOptions,
      ),
    );
  }

  /// The saved views (D17a · A), the calendar bar's saved-filters button in
  /// the overview's bar: selected while the list shown is a saved view, so a
  /// glance says whether what is on screen can be had back in one tap.
  Widget _buildViewsButton(AppLocalizations l10n) {
    final service = _viewService;
    final active = _activeView;
    return AutomationId(
      identifier: SemanticsIds.overviewViewsOpen,
      child: IconButton(
        tooltip: l10n.overviewViewsTitle,
        isSelected: active != null,
        iconSize: AppBarMetrics.glyphSize,
        icon: const Icon(Icons.bookmarks_outlined),
        onPressed: service == null ? null : _openViews,
      ),
    );
  }

  /// The page's primary control, on the page (D12 · A): the owner switches
  /// presentation on every visit, and the mode persists, so a switch kept in
  /// the title's menu left a page in List or Month with no visible way back.
  /// The search button ends the row (D21 · A): search is a List-mode tool
  /// most days, and the thumb is already on the chips.
  Widget _buildModeChips(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: FormMetrics.bodyTop),
      child: OverviewModeChips(
        mode: _mode,
        onSelected: _selectMode,
        modeIdentifier: _modeId,
        onSearch: _toggleSearch,
        searchActive: _query.isNotEmpty,
        searchIdentifier: SemanticsIds.overviewSearchOpen,
      ),
    );
  }

  /// The Search row in a group box of its own, only while the chip row's
  /// button has summoned it.
  Widget _buildSearchGroup(AppLocalizations l10n) {
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
            focusNode: _searchFocus,
            hint: l10n.upcomingSearchHint,
            clearTooltip: l10n.upcomingClearSearch,
            onChanged: _onQueryChanged,
            identifier: SemanticsIds.overviewSearch,
          ),
        ],
      ),
    );
  }

  /// Opens the Search row focused, or closes it and drops its query: the
  /// query is session-only, so a closed row never hides a live one.
  void _toggleSearch() {
    if (!_searchOpen) {
      setState(() => _searchOpen = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchOpen) _searchFocus.requestFocus();
      });
      return;
    }
    _blur();
    if (_searchController.text.isNotEmpty || _query.isNotEmpty) {
      _searchController.clear();
      _onQueryChanged('');
    }
    setState(() => _searchOpen = false);
  }

  /// The chip row's height at the default text scale — its gap under the bar
  /// and one run of chips, each on its 48 dp target — which is the
  /// keyboard's travel the row folds over.
  static const double _chipRowHeight =
      FormMetrics.bodyTop + FormMetrics.chipTapTarget;

  static String _modeId(AgendaDayListMode mode) {
    return switch (mode) {
      AgendaDayListMode.year => SemanticsIds.overviewViewYear,
      AgendaDayListMode.month => SemanticsIds.overviewViewMonth,
      AgendaDayListMode.list => SemanticsIds.overviewViewList,
    };
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

  /// The per-category totals under every mode's nav (D16), in a slot one
  /// line tall whatever it reads (D23 · A) — none, one category or a dozen —
  /// so the body below never moves. Empty, it is no semantics node at all
  /// rather than an unlabeled stop (review 12).
  Widget _buildTotals(AppLocalizations l10n) {
    final template = FormCaption(
      text: ' ',
      maxLines: OverviewListMetrics.totalsMaxLines,
      padding: FormMetrics.groupCaptionPadding,
    );
    final totals = _totalsCaption;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
      child: FormCaptionSlot(
        candidates: [template],
        child: Semantics(
          container: totals.isNotEmpty,
          excludeSemantics: totals.isEmpty,
          child: FormCaption(
            text: totals,
            maxLines: OverviewListMetrics.totalsMaxLines,
            padding: FormMetrics.groupCaptionPadding,
          ),
        ),
      ),
    );
  }

  /// The list's period band (D15): the year and month navs' row over the
  /// period, stepping by its own length, its title the Period menu.
  Widget _buildListNav(AppLocalizations l10n) {
    return AgendaPeriodNav(
      title: _period.menuValue(l10n),
      titleTemplates: _titleTemplates(l10n),
      subtitle: agendaDayListCountLabel(l10n, _listedKept, _listedMissed),
      previousTooltip: l10n.overviewPeriodPrevious,
      nextTooltip: l10n.overviewPeriodNext,
      todayTooltip: l10n.overviewPeriodHome(_home.menuValue(l10n)),
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.overviewNavPrevious,
      nextIdentifier: SemanticsIds.overviewNavNext,
      todayIdentifier: SemanticsIds.overviewNavToday,
      titleIdentifier: SemanticsIds.overviewNavTitle,
      onTitleTap: _openPeriodMenu,
      onPrevious: _canStepBack ? () => _step(-1) : null,
      onNext: _canStepForward ? () => _step(1) : null,
      onToday: _period == _home ? null : _goHome,
    );
  }

  /// Every shape the list nav's title takes, so a step never moves the list
  /// (D15): the presets, a year, and for every month a same-year and a
  /// cross-year span on it with two-digit days — every month, because the
  /// widest abbreviation is a matter of pixels, not characters (review 6).
  /// The list's alone: Year's and Month's boxes are their own titles' (D20 ·
  /// A), one line at 1.0, so the span's second line costs the tiles nothing.
  /// Built once per locale and year.
  List<String> _titleTemplates(AppLocalizations l10n) {
    final year = _today.year;
    final key = '${l10n.localeName} $year';
    if (key == _titleTemplatesKey) return _titleTemplatesCache;
    _titleTemplatesKey = key;
    return _titleTemplatesCache = List.unmodifiable([
      l10n.overviewPeriodLast12Months,
      l10n.overviewPeriodLast90Days,
      l10n.overviewPeriodAllTime,
      '$year',
      for (var m = DateTime.january; m <= DateTime.december; m++) ...[
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
        return NotificationListener<Notification>(
          onNotification: _onYearScrollNotification,
          child: AgendaYearScroll(
            controller: _yearScroll,
            firstYear: _scrollYears.first,
            lastYear: _scrollYears.last,
            // Cache-only: what the runs and the recomputes folded.
            tiles: _yearTiles,
            color: _tileColor(colorScheme),
            appearance: _appearance,
            today: _today,
            onOpenMonth: _openMonth,
            // The scaffold already resizes for the keyboard, so the scroll
            // carries no inset of its own, and the sections hang on the
            // width and their own year's tiles alone — no inset frame
            // rebuilds a year of tiles.
            padding: OverviewListMetrics.yearScrollPadding,
            // The page's groups' role, as Month's and List's cards.
            tileBackground: colorScheme.rowGroup,
            // One lane per page: the list's lane never shows with this one.
            scrubber: AgendaYearScrubber(
              semanticsLabel: l10n.overviewYearScrubberLabel,
              identifier: SemanticsIds.overviewScrubber,
              onLabelChanged: _click,
              onStep: _goToYear,
            ),
          ),
        );
      case AgendaDayListMode.list:
        return _buildListBody(l10n);
      case AgendaDayListMode.month:
        return _buildMonthBody(l10n);
    }
  }

  /// The period band of year and list mode (D15, D16): the nav, then the
  /// totals — one geometry in both, and month mode draws the same two at the
  /// top of its scroll view. Null in month mode and until the store exists.
  Widget? _buildBand(AppLocalizations l10n) {
    if (_store == null) return null;
    final nav = switch (_mode) {
      AgendaDayListMode.year => _buildYearNav(l10n),
      AgendaDayListMode.list => _buildListNav(l10n),
      AgendaDayListMode.month => null,
    };
    if (nav == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [nav, _buildTotals(l10n)],
    );
  }

  /// The list: the extents probe, then the list once the probe has
  /// measured.
  Widget _buildListBody(AppLocalizations l10n) {
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
  /// picked, that day's read row carrying "Whole month" over its entries,
  /// which list its missed occurrences under every display (D32).
  Widget _buildMonthBody(AppLocalizations l10n) {
    final bucket = _monthBucket!;
    final rows = _rowBuilder(_rows);
    // Captured beside its builder, [_buildList]'s reasoning: the outgoing
    // body of a mode cross-fade keeps building rows while it fades, and
    // `_rows` by then holds the next mode's — a count read from the field
    // would index past the rows this builder has.
    final rowCount = _rows.length;
    final selected = _selectedDay;
    // With a day picked the rows are its entries alone (`_recompute` groups
    // by day only for the whole month), so its read row is built in front
    // of them here, from the same entries' counts.
    final leadingRows = selected == null ? 0 : 1;
    final empty = rowCount == 0 && selected == null;
    return Builder(
      builder: (context) {
        final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
        final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
        return CustomScrollView(
          controller: _monthScroll,
          slivers: [
            SliverToBoxAdapter(child: _buildMonthNav(l10n, bucket)),
            SliverToBoxAdapter(child: _buildTotals(l10n)),
            SliverToBoxAdapter(
              child: AgendaMonthGrid(
                month: _month,
                firstDay: _firstMonth,
                lastDay: DateTime.utc(_lastMonth.year, _lastMonth.month + 1, 0),
                today: _today,
                selectedDay: selected,
                appearance: _appearance,
                hasEntry: _hasOccurrence,
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
                                rowCount,
                                selected,
                              )
                            : rows.build(context, index - leadingRows),
                        childCount: rowCount + leadingRows,
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
    int rowCount,
    DateTime day,
  ) {
    return FormRowShell(
      first: true,
      last: rowCount == 0,
      child: rows.readRow(
        context,
        day: day,
        kept: _pickedKept,
        missed: _pickedMissed,
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
      // Blank, in the same box, while the top year is still resolving.
      subtitle: _yearTallied
          ? agendaDayListCountLabel(l10n, _yearKept, _yearMissed)
          : '',
      previousTooltip: l10n.datePickerPreviousYear,
      nextTooltip: l10n.datePickerNextYear,
      todayTooltip: l10n.dayListScopeThisYear,
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.overviewNavPrevious,
      nextIdentifier: SemanticsIds.overviewNavNext,
      todayIdentifier: SemanticsIds.overviewNavToday,
      titleIdentifier: SemanticsIds.overviewNavTitle,
      onTitleTap: _openPeriodMenu,
      onPrevious: _year > _scrollYears.first
          ? () => _goToYear(_year - 1)
          : null,
      onNext: _year < _scrollYears.last ? () => _goToYear(_year + 1) : null,
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
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.overviewNavPrevious,
      nextIdentifier: SemanticsIds.overviewNavNext,
      todayIdentifier: SemanticsIds.overviewNavToday,
      titleIdentifier: SemanticsIds.overviewNavTitle,
      onTitleTap: _openPeriodMenu,
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
        // Measured with the presence button wherever the page offers it, so
        // the probe lays out the real row.
        presenceTracked: true,
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
