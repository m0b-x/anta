part of '../calendar_overview_page.dart';

final DateTime _firstMonth = AgendaMonthStore.monthOf(CalendarBounds.earliest);
final DateTime _lastMonth = AgendaMonthStore.monthOf(CalendarBounds.latest);

/// What the overview holds between builds. The page's State is this class
/// with the mixins of the sibling files applied in the order
/// [_CalendarOverviewPageState] lists them, and each of them sees only the
/// ones before it — a member that an earlier one needs from a later one is
/// declared at the end of this class and defined where it belongs.
abstract class _OverviewState extends State<CalendarOverviewPage>
    with RouteAware, WidgetsBindingObserver {
  CalendarAppearance _appearance = const CalendarAppearance();

  /// How a partner's rows are drawn: the look re-read on every settings
  /// trip, the partner by [_readPartner].
  PartnerLook _partnerLook = const PartnerLook();

  /// Whether [_readPartner] asked since the last settings trip.
  bool _partnerAsked = false;

  /// The taken state's `holdsPartnerEvents` or `holdsSharedByMe`: whether
  /// there is a partner to read at all.
  bool _eventsHoldShares = false;

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
    partnerLook: () => _partnerLook,
  );

  Set<String> _categoryIds = const {};
  AgendaDayListMode _mode = AgendaDayListMode.year;

  /// Whether the shown month was opened from a year tile (the overview
  /// record's D34; the day list sheet's flag). The tile tap is the one mode
  /// change that persists nothing, so it is the one drill back undoes; every
  /// persisted mode change ends it, and paging months or picking a day
  /// inside it keeps it.
  bool _cameFromYear = false;
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
  List<CalendarCategory>? _categoryPartnerShown;

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

  void _click() {
    if (_hapticFeedback) HapticFeedback.selectionClick();
  }

  /// Dropped before every picker and sheet this page opens, or the modal's
  /// return hands focus — and the keyboard — back to the search.
  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  // The page's verbs for redoing its work, and the two callbacks the year
  // scroll is built with: defined by the mixins further down, declared here
  // so that the ones above them can call them.
  void _adopt(CalendarPageState state);
  void _rebuild();
  void _recompute();
  void _foldNav();
  void _scheduleYearRun();
  void _onYearScrolled(int year);
}
