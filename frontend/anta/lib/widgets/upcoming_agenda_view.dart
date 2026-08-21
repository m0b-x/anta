import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
import 'agenda_list_view.dart';

/// Non-modal "Upcoming" mode of the calendar's bottom panel: every event
/// occurrence in a look-ahead window that starts on the calendar's selected
/// day, filtered by priority and an optional text query. A custom date range
/// overrides the anchor.
///
/// Reads the already-loaded event list rather than the database. The filters
/// are **controlled** — owned and persisted by the page — because this widget
/// is disposed every time the user switches panel mode, and a search that
/// evaporated on a mode switch was the whole problem. The anchor is threaded
/// down the same way, so tapping a day restarts the window from there.
class UpcomingAgendaView extends StatefulWidget {
  /// Every known event, unfiltered — the same list `CalendarPageLoaded`
  /// holds. Category filtering is applied here via [hiddenCategoryIds].
  final List<CalendarEvent> events;

  /// The day the look-ahead window starts on when no custom range is set —
  /// the calendar's selected day, which defaults to today. A custom range
  /// overrides it. Date-only UTC (already normalized by the bloc).
  final DateTime anchorDay;

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
    this.colorPalette = MarkdownColorPalette.presets,
    this.showRecurrenceLabels = true,
    this.occurrenceRevision = 0,
    this.membershipRevision = 0,
    this.missedDisplay = CalendarMissedDisplay.faded,
  });

  /// Look-ahead windows offered as presets, in days.
  static const List<int> rangePresets = [7, 30, 90];

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

  /// `DateFormat.MMMd` per locale for the header range label — it parses a
  /// skeleton on construction and `build` runs on every keystroke.
  static final Map<String, DateFormat> _rangeFormatCache = {};

  List<EventOccurrence> _occurrences = const [];
  List<DateTime> _holidayDays = const [];
  List<DateTime> _fastingDays = const [];

  /// The clamped, normalized look-ahead window, recomputed once per input
  /// change by [_updateRange] and shared by the event scan, the holiday scan
  /// and the header label so none of them re-derives it.
  late (DateTime, DateTime) _resolved;

  /// Cached flattened rows plus the inputs they were derived from, so
  /// unrelated rebuilds — keyboard animation, theme, chip expansion — reuse
  /// them instead of re-deriving O(occurrences) entries.
  ///
  /// Owned here rather than inside [AgendaListView] because the header count
  /// above the list is derived from these same rows: one computation, so the
  /// number and the rows can never disagree. The entries embed localized
  /// strings, hence the locale key; the Today/Tomorrow header labels are NOT
  /// part of it — the list resolves those per item.
  List<AgendaRow> _rows = const [];

  /// Entry rows in [_rows], counted while the rows are (re)built rather than
  /// walked per `build` — the panel header shows it on every keystroke.
  int _entryCount = 0;
  List<EventOccurrence>? _rowsForOccurrences;
  List<DateTime>? _rowsForHolidays;
  List<DateTime>? _rowsForFasting;
  String? _rowsForLocale;
  bool? _rowsForShowRecurrence;
  int? _rowsForOccurrenceRevision;
  int? _rowsForMembershipRevision;
  CalendarMissedDisplay? _rowsForMissedDisplay;

  List<AgendaRow> _rowsFor(AppLocalizations l10n) {
    if (identical(_rowsForOccurrences, _occurrences) &&
        identical(_rowsForHolidays, _holidayDays) &&
        identical(_rowsForFasting, _fastingDays) &&
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
    _rowsForLocale = l10n.localeName;
    _rowsForShowRecurrence = widget.showRecurrenceLabels;
    _rowsForOccurrenceRevision = widget.occurrenceRevision;
    _rowsForMembershipRevision = widget.membershipRevision;
    _rowsForMissedDisplay = widget.missedDisplay;
    _rows = buildAgendaRows(
      occurrences: _occurrences,
      holidayDays: _holidayDays,
      fastingDays: _fastingDays,
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
    // The event set, the category filter and the filters all live above this
    // widget, so their changes arrive here. Compare only the fields that
    // change the result: `filtersExpanded` is pure chrome, and rescanning a
    // year of recurrences because the chip row was toggled would be waste.
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
      // An anchor move restarts the window from the tapped day; put it in view.
      if (anchorChanged) _scrollToTopSoon();
    } else if (o.query != n.query) {
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
    } else if (o.showHolidays != n.showHolidays) {
      // Only whether holidays interleave changed — no event rescan needed.
      _recomputeHolidays();
    } else if (o.showFasting != n.showFasting) {
      // Only whether fasting days interleave changed.
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
  /// selected day — now the window's first row — is what the user sees rather
  /// than a retained scroll offset against a shorter list. Post-frame because
  /// the rebuilt rows must be laid out before offset 0 is meaningful.
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

  /// Fasting-day interleave, mirroring [_recomputeHolidays]. Inert unless the
  /// toggle is on **and** a fasting tradition is configured, and — like
  /// holidays — narrowed by the text query so a search folds the whole agenda,
  /// not just its event half.
  void _recomputeFasting() {
    if (!widget.filters.showFasting || !FastingCalendar.isEnabled) {
      _fastingDays = const [];
      return;
    }
    final days = EventAgenda.fastingDaysInRange(
      from: _resolved.$1,
      to: _resolved.$2,
    );
    final needle = normalizeForSearch(widget.filters.query.trim());
    if (needle.isEmpty) {
      _fastingDays = days;
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    _fastingDays = [
      for (final day in days)
        if (_fastingMatches(day, l10n, needle)) day,
    ];
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

  void _selectRange(int days) {
    widget.onFiltersChanged(
      widget.filters.copyWith(rangeDays: days, clearCustomRange: true),
    );
  }

  /// Toggles one priority. Emptying the set means "all priorities", which is
  /// also what the explicit "Any" chip produces.
  void _togglePriority(int priority, bool selected) {
    final next = {...widget.filters.priorities};
    if (selected) {
      next.add(priority);
    } else {
      next.remove(priority);
    }
    widget.onFiltersChanged(widget.filters.copyWith(priorities: next));
  }

  void _clearPriorities() {
    widget.onFiltersChanged(widget.filters.copyWith(priorities: const {}));
  }

  String _eventTypeLabel(AppLocalizations l10n, AgendaEventType type) {
    return switch (type) {
      AgendaEventType.all => l10n.upcomingEventTypeAll,
      AgendaEventType.recurring => l10n.upcomingEventTypeRecurring,
      AgendaEventType.oneTime => l10n.upcomingEventTypeOneTime,
      AgendaEventType.none => l10n.upcomingEventTypeNone,
    };
  }

  /// Opens a date-range picker. The lower bound reaches into the past on
  /// purpose: with an explicit range the agenda doubles as an event search,
  /// and refusing to look back would make that half a feature.
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: widget.filters.hasCustomRange
          ? DateTimeRange(
              start: widget.filters.customStart!,
              end: widget.filters.customEnd!,
            )
          : DateTimeRange(
              start: now,
              end: now.add(Duration(days: widget.filters.rangeDays)),
            ),
    );
    if (picked == null || !mounted) return;
    widget.onFiltersChanged(
      widget.filters.copyWith(
        customStart: EventAgenda.dateOnly(picked.start),
        customEnd: EventAgenda.dateOnly(picked.end),
      ),
    );
  }

  /// Clears the custom range, reverting the window to the anchored preset
  /// (the last `rangeDays` from [UpcomingAgendaView.anchorDay]). Bound to the
  /// Custom chip's delete "×" only while a range is active.
  void _clearCustomRange() {
    widget.onFiltersChanged(widget.filters.copyWith(clearCustomRange: true));
  }

  void _onQueryChanged(String value) {
    widget.onFiltersChanged(widget.filters.copyWith(query: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filters = widget.filters;
    final dateFormat = _rangeFormatCache[l10n.localeName] ??= DateFormat.MMMd(
      l10n.localeName,
    );
    final (shownStart, shownEnd) = _resolved;
    final rangeLabel =
        '${dateFormat.format(shownStart)} – ${dateFormat.format(shownEnd)}';
    final rows = _rowsFor(l10n);
    final entryCount = _entryCount;

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
              IconButton(
                tooltip: l10n.upcomingFilters,
                isSelected: filters.filtersExpanded,
                icon: const Icon(Icons.tune_rounded),
                selectedIcon: const Icon(Icons.tune_rounded),
                onPressed: () => widget.onFiltersChanged(
                  filters.copyWith(filtersExpanded: !filters.filtersExpanded),
                ),
              ),
            ],
          ),
        ),
        if (filters.filtersExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final days in UpcomingAgendaView.rangePresets)
                      ChoiceChip(
                        label: Text(l10n.upcomingPeriodDays(days)),
                        visualDensity: VisualDensity.compact,
                        selected:
                            !filters.hasCustomRange &&
                            filters.rangeDays == days,
                        onSelected: (selected) {
                          if (selected) _selectRange(days);
                        },
                      ),
                    InputChip(
                      avatar: const Icon(Icons.date_range_rounded, size: 18),
                      label: Text(l10n.upcomingPeriodCustom),
                      visualDensity: VisualDensity.compact,
                      // The date_range avatar is the chip's identity; with a
                      // range active the delete "×" already signals selection,
                      // so the checkmark would only crowd the chip.
                      showCheckmark: false,
                      selected: filters.hasCustomRange,
                      onSelected: (_) => _pickCustomRange(),
                      onDeleted: filters.hasCustomRange
                          ? _clearCustomRange
                          : null,
                      deleteButtonTooltipMessage: l10n.upcomingClearRange,
                    ),
                    FilterChip(
                      avatar: const Icon(Icons.celebration_rounded, size: 18),
                      label: Text(l10n.upcomingShowHolidays),
                      visualDensity: VisualDensity.compact,
                      selected: filters.showHolidays,
                      onSelected: (selected) => widget.onFiltersChanged(
                        filters.copyWith(showHolidays: selected),
                      ),
                    ),
                    // Fasting is off by default and inert until a tradition
                    // is configured, so the chip only appears once it can act.
                    if (FastingCalendar.isEnabled)
                      FilterChip(
                        avatar: const Icon(Icons.no_food_rounded, size: 18),
                        label: Text(l10n.upcomingShowFasting),
                        visualDensity: VisualDensity.compact,
                        selected: filters.showFasting,
                        onSelected: (selected) => widget.onFiltersChanged(
                          filters.copyWith(showFasting: selected),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      l10n.upcomingEventType,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final type in AgendaEventType.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_eventTypeLabel(l10n, type)),
                                  visualDensity: VisualDensity.compact,
                                  selected: filters.eventType == type,
                                  onSelected: (selected) {
                                    if (selected) {
                                      widget.onFiltersChanged(
                                        filters.copyWith(eventType: type),
                                      );
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Priority only refines the events layer, so it drops out
                // when events are hidden.
                if (filters.eventType != AgendaEventType.none) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        l10n.upcomingPriority,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(l10n.upcomingPriorityAny),
                                  visualDensity: VisualDensity.compact,
                                  selected: filters.priorities.isEmpty,
                                  onSelected: (selected) {
                                    if (selected) _clearPriorities();
                                  },
                                ),
                              ),
                              // Ascending: P1 (highest) leads now that lower
                              // numbers rank higher.
                              for (
                                var priority = kMinEventPriority;
                                priority <= kMaxEventPriority;
                                priority++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    avatar: Icon(
                                      EventPriorities.iconFor(priority),
                                      size: 18,
                                    ),
                                    label: Text(
                                      EventPriorities.labelOf(priority, l10n),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    selected: filters.priorities.contains(
                                      priority,
                                    ),
                                    onSelected: (selected) =>
                                        _togglePriority(priority, selected),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            // Counted from the rows actually built, not from the scan: hidden
            // mode drops missed occurrences while the rows are flattened, and
            // a count taken before that would promise entries the list never
            // shows. "Entries", not "events": holidays count too when shown,
            // and the day panel's key already says exactly that in every
            // locale.
            '${l10n.daySummaryEntryCount(entryCount)} · $rangeLabel',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: AgendaListView(
            rows: rows,
            controller: _scrollController,
            onDaySelected: widget.onDaySelected,
            onEditEvent: widget.onEditEvent,
            onOpenNote: widget.onOpenNote,
            emptyTitle: l10n.upcomingNoEvents,
            emptyHint: l10n.upcomingNoEventsHint,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            colorPalette: widget.colorPalette,
          ),
        ),
      ],
    );
  }
}
