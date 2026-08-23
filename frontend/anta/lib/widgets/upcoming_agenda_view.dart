import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../constants/event_priorities.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../models/upcoming_agenda_filters.dart';
import '../utils/event_agenda.dart';
import '../utils/markdown_color_syntax.dart';
import 'agenda_filters_sheet.dart';
import 'agenda_list_view.dart';

/// Non-modal "Upcoming" mode of the calendar's bottom panel: every event
/// occurrence in a look-ahead window, filtered by an optional text query and
/// whatever the filters sheet holds.
///
/// The window starts on [anchorDay] — today, unless the user opted into
/// following the calendar's selection — and a custom date range overrides it.
///
/// Reads the already-loaded event list rather than the database. The filters
/// are **controlled** — owned and persisted by the panel — because this widget
/// is disposed every time the user switches panel mode, and a search that
/// evaporated on a mode switch was the whole problem.
///
/// Inline chrome is deliberately thin: a search field, a badge counting what
/// is narrowing the results, and one row of chips undoing those. Everything
/// else lives in [AgendaFiltersSheet], because a persisted set-and-forget
/// choice does not earn permanent height in a panel this short.
class UpcomingAgendaView extends StatefulWidget {
  /// Every known event, unfiltered — the same list `CalendarPageLoaded`
  /// holds. Category filtering is applied here via [hiddenCategoryIds].
  final List<CalendarEvent> events;

  /// The day the look-ahead window starts on when no custom range is set.
  /// Owned by the panel: today by default, the calendar's selected day while
  /// "start from selected day" is on. Date-only UTC.
  final DateTime anchorDay;

  /// Returns the window to today. Wired to the header's `from <date>` chip,
  /// which only appears while the anchor has moved off today.
  final VoidCallback? onResetAnchor;

  /// The calendar's active category filter, inherited so the agenda and the
  /// grid can never show a different set of categories.
  final Set<String> hiddenCategoryIds;

  final UpcomingAgendaFilters filters;
  final ValueChanged<UpcomingAgendaFilters> onFiltersChanged;

  final ValueChanged<DateTime> onDaySelected;

  /// Carries the row's own occurrence day, so editing from the agenda can
  /// target that day rather than the event's start (v24).
  final void Function(CalendarEvent event, DateTime day) onEditEvent;
  final ValueChanged<CalendarEvent> onOpenNote;

  /// Forwarded to the agenda rows so event descriptions render with the
  /// user's custom markdown colours.
  final MarkdownColorPalette colorPalette;

  /// Forwarded to the agenda rows: whether subtitles mention the repeat
  /// pattern.
  final bool showRecurrenceLabels;

  /// Bumped when a per-occurrence description or a presence mark changes.
  /// Part of the row-memo key below and **deliberately excluded** from this
  /// widget's rescan test: neither changes which days an event occurs on, so
  /// re-running a 366-day scan for one would be pure waste.
  final int occurrenceRevision;

  /// Whether missed occurrences are dimmed or dropped. Dropping happens while
  /// the rows are built, so a hidden occurrence costs no row — and no entry in
  /// the header count. Excluded from the rescan test for the same reason as
  /// the revision: hiding is a render-time filter, never a membership one.
  final CalendarMissedDisplay missedDisplay;

  /// Bumped when an occurrence is cancelled or restored. **Included** in the
  /// rescan test below, unlike [occurrenceRevision]: a skip changes which days
  /// an event occurs on, so the 366-day scan must actually re-run or the
  /// agenda keeps listing a day that no longer exists.
  final int membershipRevision;

  const UpcomingAgendaView({
    super.key,
    required this.events,
    required this.anchorDay,
    required this.hiddenCategoryIds,
    required this.filters,
    required this.onFiltersChanged,
    required this.onDaySelected,
    required this.onEditEvent,
    required this.onOpenNote,
    this.onResetAnchor,
    this.colorPalette = MarkdownColorPalette.presets,
    this.showRecurrenceLabels = true,
    this.occurrenceRevision = 0,
    this.membershipRevision = 0,
    this.missedDisplay = CalendarMissedDisplay.faded,
  });

  @override
  State<UpcomingAgendaView> createState() => _UpcomingAgendaViewState();
}

class _UpcomingAgendaViewState extends State<UpcomingAgendaView> {
  late final TextEditingController _searchController;
  final ScrollController _scrollController = ScrollController();

  /// Debounces the range scan on query-only changes so a burst of keystrokes
  /// folds every title and description once, not per character. Discrete
  /// changes (anchor, range, priority, category, data) still scan
  /// synchronously — see [didUpdateWidget].
  Timer? _scanDebounce;
  static const Duration _scanDebounceDelay = Duration(milliseconds: 200);

  List<EventOccurrence> _occurrences = const [];
  List<DateTime> _holidayDays = const [];
  List<DateTime> _fastingDays = const [];

  /// Fasting periods collapsed to one row each.
  List<FastingRun> _fastingRuns = const [];

  /// The whole window digested to one card per tradition. These three lists
  /// are mutually exclusive: [UpcomingAgendaFilters.fastingDisplay] picks one
  /// and [_recomputeFasting] zeroes the other two.
  List<FastingSummary> _fastingSummaries = const [];

  /// The clamped, normalized look-ahead window, recomputed once per input
  /// change by [_updateRange] and shared by the event scan, the holiday scan
  /// and the header label so none of them re-derives it.
  late (DateTime, DateTime) _resolved;

  /// Cached flattened rows plus the inputs they were derived from, so
  /// unrelated rebuilds — keyboard animation, theme — reuse them instead of
  /// re-deriving O(occurrences) entries.
  ///
  /// Owned here rather than inside [AgendaListView] because the header count
  /// above the list is derived from these same rows: one computation, so the
  /// number and the rows can never disagree. The entries embed localized
  /// strings, hence the locale key; the Today/Tomorrow header labels are NOT
  /// part of it — the list resolves those per item.
  List<AgendaRow> _rows = const [];

  /// Entry rows in [_rows], counted while the rows are (re)built rather than
  /// walked per `build` — the panel header shows it on every keystroke.
  ///
  /// Counting `AgendaEntryRow` alone is also what keeps a fasting summary card
  /// out of the total for free: it summarizes entries rather than being one,
  /// and it is a row type of its own.
  int _entryCount = 0;
  List<EventOccurrence>? _rowsForOccurrences;
  List<DateTime>? _rowsForHolidays;
  List<DateTime>? _rowsForFasting;
  List<FastingRun>? _rowsForFastingRuns;
  List<FastingSummary>? _rowsForFastingSummaries;
  String? _rowsForLocale;
  bool? _rowsForShowRecurrence;
  int? _rowsForOccurrenceRevision;
  int? _rowsForMembershipRevision;
  CalendarMissedDisplay? _rowsForMissedDisplay;

  List<AgendaRow> _rowsFor(AppLocalizations l10n) {
    if (identical(_rowsForOccurrences, _occurrences) &&
        identical(_rowsForHolidays, _holidayDays) &&
        identical(_rowsForFasting, _fastingDays) &&
        identical(_rowsForFastingRuns, _fastingRuns) &&
        identical(_rowsForFastingSummaries, _fastingSummaries) &&
        _rowsForLocale == l10n.localeName &&
        _rowsForShowRecurrence == widget.showRecurrenceLabels &&
        _rowsForOccurrenceRevision == widget.occurrenceRevision &&
        _rowsForMembershipRevision == widget.membershipRevision &&
        _rowsForMissedDisplay == widget.missedDisplay) {
      return _rows;
    }
    _rowsForOccurrences = _occurrences;
    _rowsForHolidays = _holidayDays;
    _rowsForFasting = _fastingDays;
    _rowsForFastingRuns = _fastingRuns;
    _rowsForFastingSummaries = _fastingSummaries;
    _rowsForLocale = l10n.localeName;
    _rowsForShowRecurrence = widget.showRecurrenceLabels;
    _rowsForOccurrenceRevision = widget.occurrenceRevision;
    _rowsForMembershipRevision = widget.membershipRevision;
    _rowsForMissedDisplay = widget.missedDisplay;
    _rows = buildAgendaRows(
      occurrences: _occurrences,
      holidayDays: _holidayDays,
      fastingDays: _fastingDays,
      fastingRuns: _fastingRuns,
      fastingSummaries: _fastingSummaries,
      l10n: l10n,
      showRecurrenceLabels: widget.showRecurrenceLabels,
      missedDisplay: widget.missedDisplay,
    );
    var entries = 0;
    for (final row in _rows) {
      if (row is AgendaEntryRow) entries++;
    }
    _entryCount = entries;
    return _rows;
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filters.query);
    _updateRange();
    _recompute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recomputeHolidays();
    _recomputeFasting();
  }

  @override
  void didUpdateWidget(UpcomingAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt an externally-changed query (e.g. restored from settings).
    // Echoing back the user's own keystrokes would reset the caret.
    if (widget.filters.query != _searchController.text) {
      _searchController.text = widget.filters.query;
    }
    // Refresh the shared window before any branch below reads it.
    _updateRange();
    final o = oldWidget.filters;
    final n = widget.filters;
    // The anchor only drives the window when no custom range overrides it, so
    // an anchor move under a pinned custom range changes nothing — do not
    // rescan it. The custom-range transitions themselves are covered by the
    // customStart/customEnd comparisons below.
    final anchorChanged =
        !n.hasCustomRange && oldWidget.anchorDay != widget.anchorDay;
    // Everything that moves the scan except the text query. A concrete change
    // like this is worth scanning for at once; only a lone keystroke is worth
    // debouncing.
    final nonQueryScanChanged =
        !identical(oldWidget.events, widget.events) ||
        oldWidget.hiddenCategoryIds != widget.hiddenCategoryIds ||
        o.rangeDays != n.rangeDays ||
        !setEquals(o.priorities, n.priorities) ||
        o.customStart != n.customStart ||
        o.customEnd != n.customEnd ||
        o.eventType != n.eventType ||
        !setEquals(o.categoryIds, n.categoryIds) ||
        o.collapseRecurring != n.collapseRecurring ||
        // Cancelling an occurrence changes what the scan finds, so it must run.
        oldWidget.membershipRevision != widget.membershipRevision ||
        anchorChanged;

    if (nonQueryScanChanged) {
      // A fresh scan already reflects the current query, so drop any pending
      // debounced one.
      _scanDebounce?.cancel();
      _recompute();
      _recomputeHolidays();
      _recomputeFasting();
      // An anchor move restarts the window from the anchored day; put it in
      // view rather than keeping an offset into a list that just moved.
      if (anchorChanged) _scrollToTopSoon();
      return;
    }

    if (o.query != n.query) {
      // Query-only: debounce the expansion so typing does not re-fold every
      // title and description per character. The field stays live (it is
      // controlled above); only the results lag by one short window.
      _scanDebounce?.cancel();
      _scanDebounce = Timer(_scanDebounceDelay, () {
        if (!mounted) return;
        setState(() {
          _recompute();
          _recomputeHolidays();
          _recomputeFasting();
        });
      });
    }

    // Annotation-layer changes need no event rescan. Tested independently
    // rather than as an else-chain: applying the filters sheet can move
    // several of these at once.
    if (o.showHolidays != n.showHolidays) _recomputeHolidays();
    if (o.showFasting != n.showFasting ||
        o.fastingDisplay != n.fastingDisplay) {
      _recomputeFasting();
    }
  }

  @override
  void dispose() {
    _scanDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Resets the agenda to the top after an anchor-driven rescan, so the newly
  /// anchored day — now the window's first row — is what the user sees rather
  /// than a retained scroll offset against a different list. Post-frame
  /// because the rebuilt rows must be laid out before offset 0 is meaningful.
  void _scrollToTopSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// Recomputes [_resolved] from the current anchor and filters. Called once
  /// per input change (init + didUpdateWidget) so the event scan, the holiday
  /// scan and the header label read one clamped window instead of each
  /// re-deriving the raw bounds and re-clamping.
  ///
  /// The clamp matters for the label: a picked two-year range is scanned for
  /// its first year only ([EventAgenda.maxRangeDays]), and a label claiming
  /// otherwise would misreport the results. `resolveRange` only returns null
  /// for an empty window, which the filters and picker already preclude; the
  /// fallback keeps a degenerate range self-consistent.
  void _updateRange() {
    final filters = widget.filters;
    final DateTime rawStart;
    final DateTime rawEnd;
    if (filters.hasCustomRange) {
      rawStart = EventAgenda.dateOnly(filters.customStart!);
      rawEnd = EventAgenda.dateOnly(filters.customEnd!);
    } else {
      rawStart = EventAgenda.dateOnly(widget.anchorDay);
      rawEnd = rawStart.add(Duration(days: filters.rangeDays - 1));
    }
    _resolved =
        EventAgenda.resolveRange(rawStart, rawEnd) ?? (rawStart, rawStart);
  }

  /// Re-runs the range scan. Called from the lifecycle hooks so `build`
  /// never expands recurrences.
  void _recompute() {
    _occurrences = EventAgenda.occurrencesInRange(
      events: widget.events,
      from: _resolved.$1,
      to: _resolved.$2,
      hiddenCategoryIds: widget.hiddenCategoryIds,
      priorities: widget.filters.priorities,
      query: widget.filters.query,
      eventType: widget.filters.eventType,
      categoryIds: widget.filters.categoryIds,
      collapseRecurring: widget.filters.collapseRecurring,
    );
  }

  /// Resolves the holiday days to interleave.
  ///
  /// Separate from [_recompute] because matching a holiday against the
  /// search text needs its localized label, so this needs a context — hence
  /// the `didChangeDependencies` hook, which also re-runs it when the app
  /// locale changes and the labels move underneath us.
  ///
  /// The event filters (priority, category) deliberately do not apply: a
  /// holiday is a property of the day, with no priority or category to
  /// filter on. The text query does apply, so searching narrows the whole
  /// agenda rather than only its event half.
  void _recomputeHolidays() {
    if (!widget.filters.showHolidays) {
      _holidayDays = const [];
      return;
    }
    final days = EventAgenda.holidayDaysInRange(
      from: _resolved.$1,
      to: _resolved.$2,
    );
    // Same case + diacritic fold the event scan and the note search use.
    final needle = normalizeForSearch(widget.filters.query.trim());
    if (needle.isEmpty) {
      _holidayDays = days;
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    _holidayDays = [
      for (final day in days)
        if (normalizeForSearch(_holidayLabel(day, l10n)).contains(needle)) day,
    ];
  }

  String _holidayLabel(DateTime day, AppLocalizations l10n) {
    final info = PublicHolidays.holidayOn(day);
    return info == null ? '' : PublicHolidays.labelOf(info, l10n);
  }

  /// Fasting interleave, mirroring [_recomputeHolidays]. Inert unless the
  /// toggle is on **and** a fasting tradition is configured, and — like
  /// holidays — narrowed by the text query so a search folds the whole agenda,
  /// not just its event half.
  ///
  /// The three presentations are mutually exclusive, so each branch zeroes the
  /// other two lists: `buildAgendaRows` reads whichever is non-empty. The query
  /// filter is handed to the run walk and the summary scan alike, so neither
  /// can claim days the search excluded.
  void _recomputeFasting() {
    if (!widget.filters.showFasting || !FastingCalendar.isEnabled) {
      _fastingDays = const [];
      _fastingRuns = const [];
      _fastingSummaries = const [];
      return;
    }
    final needle = normalizeForSearch(widget.filters.query.trim());
    bool Function(DateTime day)? dayFilter;
    if (needle.isNotEmpty) {
      final l10n = AppLocalizations.of(context)!;
      dayFilter = (day) => _fastingMatches(day, l10n, needle);
    }

    switch (widget.filters.fastingDisplay) {
      case AgendaFastingDisplay.summary:
        _fastingDays = const [];
        _fastingRuns = const [];
        _fastingSummaries = EventAgenda.fastingSummariesInRange(
          from: _resolved.$1,
          to: _resolved.$2,
          dayFilter: dayFilter,
        );
      case AgendaFastingDisplay.periods:
        _fastingDays = const [];
        _fastingSummaries = const [];
        _fastingRuns = EventAgenda.fastingRunsInRange(
          from: _resolved.$1,
          to: _resolved.$2,
          dayFilter: dayFilter,
        );
      case AgendaFastingDisplay.everyDay:
        _fastingRuns = const [];
        _fastingSummaries = const [];
        final days = EventAgenda.fastingDaysInRange(
          from: _resolved.$1,
          to: _resolved.$2,
        );
        _fastingDays = dayFilter == null
            ? days
            : [
                for (final day in days)
                  if (dayFilter(day)) day,
              ];
    }
  }

  /// Whether any of [day]'s fasting entries (across configured traditions)
  /// matches [needle] — the displayed title (custom override or period name)
  /// or the regime subtitle. [needle] is already folded through
  /// [normalizeForSearch].
  bool _fastingMatches(DateTime day, AppLocalizations l10n, String needle) {
    for (final info in FastingCalendar.on(day)) {
      final title =
          FastingCalendar.styleOf(info.tradition).titleOverride ??
          FastingCalendar.periodNameOf(info.period, l10n);
      if (normalizeForSearch(title).contains(needle)) return true;
      final regime = FastingCalendar.regimeNameOf(info.regime, l10n);
      if (normalizeForSearch(regime).contains(needle)) return true;
    }
    return false;
  }

  Future<void> _openFilters() async {
    final result = await AgendaFiltersSheet.show(
      context,
      filters: widget.filters,
    );
    if (result == null || !mounted) return;
    // The sheet never owns the query; carry the live one so a keystroke typed
    // while it was open is not rolled back by Apply.
    widget.onFiltersChanged(result.copyWith(query: widget.filters.query));
  }

  void _onQueryChanged(String value) {
    widget.onFiltersChanged(widget.filters.copyWith(query: value));
  }

  /// The chips shown under the search field: one per filter that is currently
  /// **narrowing** the list, each removable on its own.
  ///
  /// Layer toggles and the collapse switches are deliberately absent — they
  /// add or condense rows rather than hide them, so they never answer "why is
  /// this missing", which is the question this row exists for.
  List<_SummaryChip> _summaryChips(AppLocalizations l10n) {
    final filters = widget.filters;
    final chips = <_SummaryChip>[];

    if (filters.hasCustomRange) {
      chips.add(
        _SummaryChip(
          icon: Icons.date_range_rounded,
          label: AgendaListView.rangeLabel(
            l10n.localeName,
            filters.customStart!,
            filters.customEnd!,
          ),
          onDeleted: () =>
              widget.onFiltersChanged(filters.copyWith(clearCustomRange: true)),
        ),
      );
    } else if (filters.rangeDays != UpcomingAgendaFilters.defaultRangeDays) {
      chips.add(
        _SummaryChip(
          icon: Icons.schedule_rounded,
          label: l10n.upcomingPeriodDays(filters.rangeDays),
          onDeleted: () => widget.onFiltersChanged(
            filters.copyWith(rangeDays: UpcomingAgendaFilters.defaultRangeDays),
          ),
        ),
      );
    }

    if (filters.eventType != AgendaEventType.all) {
      chips.add(
        _SummaryChip(
          icon: switch (filters.eventType) {
            AgendaEventType.recurring => Icons.repeat_rounded,
            AgendaEventType.oneTime => Icons.event_rounded,
            _ => Icons.event_busy_rounded,
          },
          label: switch (filters.eventType) {
            AgendaEventType.recurring => l10n.upcomingEventTypeRecurring,
            AgendaEventType.oneTime => l10n.upcomingEventTypeOneTime,
            _ => l10n.upcomingEventsHidden,
          },
          onDeleted: () => widget.onFiltersChanged(
            filters.copyWith(eventType: AgendaEventType.all),
          ),
        ),
      );
    }

    if (filters.priorities.isNotEmpty) {
      final single = filters.priorities.length == 1
          ? filters.priorities.single
          : null;
      chips.add(
        _SummaryChip(
          icon: EventPriorities.iconFor(single ?? kDefaultEventPriority),
          label: single != null
              ? EventPriorities.labelOf(single, l10n)
              : '${l10n.upcomingPriority} (${filters.priorities.length})',
          onDeleted: () =>
              widget.onFiltersChanged(filters.copyWith(priorities: const {})),
        ),
      );
    }

    if (filters.categoryIds.isNotEmpty) {
      chips.add(
        _SummaryChip(
          icon: Icons.category_rounded,
          label: '${l10n.calendarCategories} (${filters.categoryIds.length})',
          onDeleted: () =>
              widget.onFiltersChanged(filters.copyWith(categoryIds: const {})),
        ),
      );
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filters = widget.filters;
    final (shownStart, shownEnd) = _resolved;
    final rangeLabel = AgendaListView.rangeLabel(
      l10n.localeName,
      shownStart,
      shownEnd,
    );
    final rows = _rowsFor(l10n);
    final entryCount = _entryCount;
    final chips = _summaryChips(l10n);
    // The anchor only reads as "moved" when it actually drives the window and
    // sits off today — with a custom range pinned, or the window left on
    // today, there is nothing to return from.
    final today = EventAgenda.dateOnly(DateTime.now());
    final anchorMoved = !filters.hasCustomRange && widget.anchorDay != today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
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
                    suffixIcon: filters.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.upcomingClearSearch,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => _onQueryChanged(''),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
              Badge.count(
                count: chips.length,
                isLabelVisible: chips.isNotEmpty,
                child: IconButton(
                  tooltip: l10n.upcomingFilters,
                  isSelected: chips.isNotEmpty,
                  icon: const Icon(Icons.tune_rounded),
                  selectedIcon: const Icon(Icons.tune_rounded),
                  onPressed: _openFilters,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          // Only the search row above is a hard minimum. Everything that
          // used to be fixed-height chrome below it — the summary chips, the
          // header line — now scrolls away with the list inside one
          // CustomScrollView, so a squeezed panel (a short window, or the
          // on-screen keyboard eating most of the height while the grid is
          // still showing) clips gracefully instead of throwing a RenderFlex
          // overflow. `AgendaListView`'s sliver stays lazily built, so this
          // costs nothing extra even for a 366-day window.
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              if (chips.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final chip in chips)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InputChip(
                                avatar: Icon(chip.icon, size: 18),
                                label: Text(chip.label),
                                visualDensity: VisualDensity.compact,
                                showCheckmark: false,
                                onPressed: _openFilters,
                                onDeleted: chip.onDeleted,
                                deleteButtonTooltipMessage:
                                    l10n.upcomingRemoveFilter,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          // Counted from the rows actually built, not from the
                          // scan: hidden mode drops missed occurrences while
                          // the rows are flattened, and a count taken before
                          // that would promise entries the list never shows.
                          // "Entries", not "events": holidays count too when
                          // shown, and the day panel's key already says
                          // exactly that in every locale.
                          '${l10n.daySummaryEntryCount(entryCount)} · $rangeLabel',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (anchorMoved)
                        InputChip(
                          avatar: const Icon(
                            Icons.my_location_rounded,
                            size: 16,
                          ),
                          label: Text(
                            l10n.upcomingAnchorFrom(
                              AgendaListView.anchorLabel(
                                l10n.localeName,
                                widget.anchorDay,
                              ),
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          showCheckmark: false,
                          onDeleted: widget.onResetAnchor,
                          deleteButtonTooltipMessage: l10n.upcomingResetAnchor,
                        ),
                    ],
                  ),
                ),
              ),
              AgendaListView(
                rows: rows,
                sliver: true,
                onDaySelected: widget.onDaySelected,
                onEditEvent: widget.onEditEvent,
                onOpenNote: widget.onOpenNote,
                emptyTitle: l10n.upcomingNoEvents,
                emptyHint: l10n.upcomingNoEventsHint,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                colorPalette: widget.colorPalette,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One removable "this is narrowing your results" chip.
class _SummaryChip {
  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.onDeleted,
  });
}
