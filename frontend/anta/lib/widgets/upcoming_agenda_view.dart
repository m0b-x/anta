import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/event_priorities.dart';
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
/// occurrence in a look-ahead window, filtered by priority and an optional
/// text query.
///
/// Reads the already-loaded event list rather than the database. The filters
/// are **controlled** — owned and persisted by the page — because this widget
/// is disposed every time the user switches panel mode, and a search that
/// evaporated on a mode switch was the whole problem.
class UpcomingAgendaView extends StatefulWidget {
  /// Every known event, unfiltered — the same list `CalendarPageLoaded`
  /// holds. Category filtering is applied here via [hiddenCategoryIds].
  final List<CalendarEvent> events;

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

  List<EventOccurrence> _occurrences = const [];
  List<DateTime> _holidayDays = const [];

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
  List<EventOccurrence>? _rowsForOccurrences;
  List<DateTime>? _rowsForHolidays;
  String? _rowsForLocale;
  bool? _rowsForShowRecurrence;
  int? _rowsForOccurrenceRevision;
  int? _rowsForMembershipRevision;
  CalendarMissedDisplay? _rowsForMissedDisplay;

  List<AgendaRow> _rowsFor(AppLocalizations l10n) {
    if (identical(_rowsForOccurrences, _occurrences) &&
        identical(_rowsForHolidays, _holidayDays) &&
        _rowsForLocale == l10n.localeName &&
        _rowsForShowRecurrence == widget.showRecurrenceLabels &&
        _rowsForOccurrenceRevision == widget.occurrenceRevision &&
        _rowsForMembershipRevision == widget.membershipRevision &&
        _rowsForMissedDisplay == widget.missedDisplay) {
      return _rows;
    }
    _rowsForOccurrences = _occurrences;
    _rowsForHolidays = _holidayDays;
    _rowsForLocale = l10n.localeName;
    _rowsForShowRecurrence = widget.showRecurrenceLabels;
    _rowsForOccurrenceRevision = widget.occurrenceRevision;
    _rowsForMembershipRevision = widget.membershipRevision;
    _rowsForMissedDisplay = widget.missedDisplay;
    return _rows = buildAgendaRows(
      occurrences: _occurrences,
      holidayDays: _holidayDays,
      l10n: l10n,
      showRecurrenceLabels: widget.showRecurrenceLabels,
      missedDisplay: widget.missedDisplay,
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filters.query);
    _recompute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recomputeHolidays();
  }

  @override
  void didUpdateWidget(UpcomingAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt an externally-changed query (e.g. restored from settings).
    // Echoing back the user's own keystrokes would reset the caret.
    if (widget.filters.query != _searchController.text) {
      _searchController.text = widget.filters.query;
    }
    // The event set, the category filter and the filters all live above this
    // widget, so their changes arrive here. Compare only the fields that
    // change the result: `filtersExpanded` is pure chrome, and rescanning a
    // year of recurrences because the chip row was toggled would be waste.
    final o = oldWidget.filters;
    final n = widget.filters;
    final scanChanged =
        !identical(oldWidget.events, widget.events) ||
        oldWidget.hiddenCategoryIds != widget.hiddenCategoryIds ||
        o.rangeDays != n.rangeDays ||
        !setEquals(o.priorities, n.priorities) ||
        o.customStart != n.customStart ||
        o.customEnd != n.customEnd ||
        o.query != n.query ||
        // The one revision that belongs here: cancelling an occurrence changes
        // what the scan would find, so the scan has to run again.
        oldWidget.membershipRevision != widget.membershipRevision;
    if (scanChanged) _recompute();
    if (scanChanged || o.showHolidays != n.showHolidays) {
      _recomputeHolidays();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime get _rangeStart {
    final start = widget.filters.customStart;
    if (widget.filters.hasCustomRange) return EventAgenda.dateOnly(start!);
    return EventAgenda.dateOnly(DateTime.now());
  }

  DateTime get _rangeEnd {
    final end = widget.filters.customEnd;
    if (widget.filters.hasCustomRange) return EventAgenda.dateOnly(end!);
    return _rangeStart.add(Duration(days: widget.filters.rangeDays - 1));
  }

  /// The range as the scans actually see it — clamped to
  /// [EventAgenda.maxRangeDays]. The header label must come from this, not
  /// from the raw filters: a picked two-year range is scanned for its first
  /// year only, and a label claiming otherwise would misreport the results.
  (DateTime, DateTime) get _resolvedRange =>
      EventAgenda.resolveRange(_rangeStart, _rangeEnd) ??
      (_rangeStart, _rangeStart);

  /// Re-runs the range scan. Called from the lifecycle hooks so `build`
  /// never expands recurrences.
  void _recompute() {
    _occurrences = EventAgenda.occurrencesInRange(
      events: widget.events,
      from: _rangeStart,
      to: _rangeEnd,
      hiddenCategoryIds: widget.hiddenCategoryIds,
      priorities: widget.filters.priorities,
      query: widget.filters.query,
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
      from: _rangeStart,
      to: _rangeEnd,
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

  void _onQueryChanged(String value) {
    widget.onFiltersChanged(widget.filters.copyWith(query: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filters = widget.filters;
    final dateFormat = DateFormat.MMMd(l10n.localeName);
    final (shownStart, shownEnd) = _resolvedRange;
    final rangeLabel =
        '${dateFormat.format(shownStart)} – ${dateFormat.format(shownEnd)}';
    final rows = _rowsFor(l10n);
    final entryCount = rows.whereType<AgendaEntryRow>().length;

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
                    ChoiceChip(
                      avatar: const Icon(Icons.date_range_rounded, size: 18),
                      label: Text(l10n.upcomingPeriodCustom),
                      visualDensity: VisualDensity.compact,
                      selected: filters.hasCustomRange,
                      onSelected: (_) => _pickCustomRange(),
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
                  ],
                ),
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
