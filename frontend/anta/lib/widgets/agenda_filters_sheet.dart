import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_priorities.dart';
import '../constants/fasting_calendar.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/upcoming_agenda_filters.dart';
import '../utils/calendar_filter_summary.dart';
import '../utils/event_agenda.dart';
import 'agenda_list_view.dart';
import 'category_picker_sheet.dart';
import 'filter_check_list_sheet.dart';
import 'form_rows.dart';

/// Every upcoming-agenda filter, in one modal sheet — the Filters sheet's
/// twin (`CalendarFilterSheet`), in the same grouped-row language since the
/// 2026-09-27 Tier 1 pass (`docs/calendar-language-tier-1-roadmap.md`): a
/// mutually exclusive choice is a menu row, a set is a picker row that reads
/// its value back and opens the shared category picker or check-list sheet,
/// a layer is a switch row, and Reset filters is the last action row.
///
/// These are set-and-forget, persisted choices, so they do not earn permanent
/// space in a bottom panel that is already short — the panel keeps only the
/// search field and a summary of what is currently narrowing the results.
///
/// Edits a **local draft** and returns it on Apply (or `null` when dismissed):
/// a live-applying sheet would re-run the agenda scan behind the sheet on
/// every tap. No discard guard — the sheet holds no typed text, and the draft
/// costs a tap to redo. [UpcomingAgendaFilters.query] is never touched here:
/// it belongs to the panel's search field, which is why Reset keeps it and
/// why the Reset row ignores it when deciding whether there is anything left
/// to reset.
///
/// A control that cannot act — Fasting while no tradition is configured,
/// Categories and Priority while no events are listed — is drawn at 38 % with
/// its stored value rather than dropped: a row that appears between two
/// openings moves everything under it.
class AgendaFiltersSheet extends StatefulWidget {
  final UpcomingAgendaFilters initial;

  const AgendaFiltersSheet({super.key, required this.initial});

  /// Names one period choice. Shared with the panel's summary chip so the
  /// sheet and the chip that undoes it can never name the same window
  /// differently. [AgendaPeriodMode.rollingDays] is the Period menu's three
  /// day presets rather than one item, so it falls back to the window it
  /// spans.
  static String periodModeLabel(
    AppLocalizations l10n,
    AgendaPeriodMode mode,
    int rangeDays,
  ) {
    return switch (mode) {
      AgendaPeriodMode.wholeYear => l10n.upcomingPeriodWholeYear,
      AgendaPeriodMode.restOfYear => l10n.upcomingPeriodRestOfYear,
      AgendaPeriodMode.rollingDays => l10n.upcomingPeriodDays(rangeDays),
    };
  }

  /// The sub-sheet shape: as tall as its content, clamped at the editor's
  /// height, the route's own drag.
  static Future<UpcomingAgendaFilters?> show(
    BuildContext context, {
    required UpcomingAgendaFilters filters,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<UpcomingAgendaFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: AgendaFiltersSheet(initial: filters),
      ),
    );
  }

  @override
  State<AgendaFiltersSheet> createState() => _AgendaFiltersSheetState();
}

/// The Period menu's six choices. The first three stand for
/// [UpcomingAgendaFilters.rangePresets] in order (an assertion in the sheet
/// keeps them from drifting); the two year windows are anchored to the
/// calendar year rather than counted forward, which is why they cannot be
/// expressed as another rolling preset; [custom] writes nothing itself — it
/// opens the range picker, which writes both dates or nothing.
enum _PeriodChoice {
  days7(mode: AgendaPeriodMode.rollingDays, days: 7),
  days30(mode: AgendaPeriodMode.rollingDays, days: 30),
  days90(mode: AgendaPeriodMode.rollingDays, days: 90),
  restOfYear(mode: AgendaPeriodMode.restOfYear),
  wholeYear(mode: AgendaPeriodMode.wholeYear),
  custom();

  /// What picking the choice writes: the window mode and, for a rolling
  /// preset, its day count. Both null on [custom].
  final AgendaPeriodMode? mode;
  final int? days;

  const _PeriodChoice({this.mode, this.days});
}

class _AgendaFiltersSheetState extends State<AgendaFiltersSheet> {
  late UpcomingAgendaFilters _draft = widget.initial;

  /// Guards the sheet's own sub-routes — the category picker, the priority
  /// check list and the range picker — against a double tap pushing two
  /// identical copies, which reads as a sheet that will not close. One flag
  /// for all: they are never nested.
  bool _subRouteOpen = false;

  /// The body's scroll position feeds the header's hairline (a form sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    assert(
      listEquals(
        [for (final choice in _PeriodChoice.values) ?choice.days],
        UpcomingAgendaFilters.rangePresets,
      ),
      'The Period menu must offer UpcomingAgendaFilters.rangePresets in order',
    );
    _bodyScroll.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  bool get _eventsShown => _draft.eventType != AgendaEventType.none;

  /// Whether Reset would change anything. The query is the panel's, never
  /// this sheet's — Reset keeps it — so it is left out of the comparison, or
  /// a typed search would light a row that cannot clear it.
  bool get _isDefault =>
      _draft.copyWith(query: '') == const UpcomingAgendaFilters();

  void _update(UpcomingAgendaFilters next) => setState(() => _draft = next);

  /// Back to the defaults with the query kept; the sheet stays open.
  void _reset() {
    _update(const UpcomingAgendaFilters().copyWith(query: _draft.query));
  }

  /// Runs [open] unless a sub-route is already up.
  Future<void> _guarded(Future<void> Function() open) async {
    if (_subRouteOpen) return;
    _subRouteOpen = true;
    try {
      await open();
    } finally {
      _subRouteOpen = false;
    }
  }

  /// Opens the multi-select picker over the category allowlist.
  ///
  /// The sheet is semantics-free — a set in, a set out — and this side is an
  /// **allowlist** where empty means "all categories". That is why
  /// `pickMulti` must not collapse an empty result to `null` the way its date
  /// twin does: clearing every row here is a real choice, not a dismissal.
  ///
  /// **The inversion is the caller's, in both directions.** An empty
  /// allowlist opens with every row *checked* — it already means "all", the
  /// row above says so, and opening it unchecked would make one state read
  /// two ways (and disagree with the calendar filter's sub-sheet, which
  /// inverts its denylist and so opens checked for the same "everything
  /// shown" state). A result covering everything on offer collapses back to
  /// the empty set rather than freezing today's catalog into an explicit
  /// list, which would silently exclude every category created afterwards.
  ///
  /// Unchecking every row still stores the empty set — the only reading "no
  /// allowlist" has.
  ///
  /// It returns into the local draft, so nothing re-runs the agenda scan
  /// behind the sheet until Apply.
  Future<void> _pickCategories(List<CalendarCategory> categories) =>
      _guarded(() async {
        final offered = {for (final category in categories) category.id};
        final picked = await CategoryPickerSheet.pickMulti(
          context,
          selected: _draft.categoryIds.isEmpty ? offered : _draft.categoryIds,
        );
        if (picked == null || !mounted) return;
        _update(
          _draft.copyWith(
            categoryIds: picked.containsAll(offered) ? const {} : picked,
          ),
        );
      });

  Future<void> _pickPriorities(AppLocalizations l10n) => _guarded(() async {
    final picked = await FilterCheckListSheet.show(
      context,
      title: l10n.upcomingPriority,
      items: [
        // Ascending: P1 (highest) leads, since lower numbers rank higher.
        for (var p = kMinEventPriority; p <= kMaxEventPriority; p++)
          FilterCheckItem(
            id: '$p',
            icon: EventPriorities.iconFor(p),
            label: EventPriorities.labelOf(p, l10n),
            identifier: SemanticsIds.filterListRow('priority-$p'),
          ),
      ],
      selected: {for (final p in _draft.priorities) '$p'},
    );
    if (picked == null || !mounted) return;
    _update(
      _draft.copyWith(
        priorities: {for (final id in picked) ?int.tryParse(id)},
      ),
    );
  });

  /// Opens a date-range picker. The lower bound reaches into the past on
  /// purpose: with an explicit range the agenda doubles as an event search,
  /// and refusing to look back would make that half a feature.
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _draft.hasCustomRange
          ? DateTimeRange(start: _draft.customStart!, end: _draft.customEnd!)
          : DateTimeRange(
              start: now,
              end: now.add(Duration(days: _draft.rangeDays - 1)),
            ),
    );
    if (picked == null || !mounted) return;
    _update(
      _draft.copyWith(
        customStart: EventAgenda.dateOnly(picked.start),
        customEnd: EventAgenda.dateOnly(picked.end),
      ),
    );
  }

  /// The Period menu's checked item: a pinned range wins, then the window
  /// mode, then the preset the day count matches. A stored count outside the
  /// presets (a value another build wrote) checks nothing and reads back as
  /// its own day count rather than snapping to the nearest preset.
  _PeriodChoice? get _periodChoice {
    if (_draft.hasCustomRange) return _PeriodChoice.custom;
    for (final choice in _PeriodChoice.values) {
      if (choice.mode != _draft.periodMode) continue;
      if (choice.days == null || choice.days == _draft.rangeDays) return choice;
    }
    return null;
  }

  /// A preset or a year window writes the draft at once; `Custom range…`
  /// opens the range picker, which writes both dates or nothing. Nullable
  /// only because [_periodChoice] is — the menu itself never answers null.
  void _selectPeriod(_PeriodChoice? choice) {
    if (choice == null) return;
    final mode = choice.mode;
    if (mode == null) {
      _guarded(_pickCustomRange);
      return;
    }
    _update(
      _draft.copyWith(
        periodMode: mode,
        rangeDays: choice.days,
        clearCustomRange: true,
      ),
    );
  }

  String _periodValue(AppLocalizations l10n) {
    if (_draft.hasCustomRange) return _rangeLabel(l10n);
    return AgendaFiltersSheet.periodModeLabel(
      l10n,
      _draft.periodMode,
      _draft.rangeDays,
    );
  }

  String _rangeLabel(AppLocalizations l10n) {
    return AgendaListView.rangeLabel(
      l10n.localeName,
      _draft.customStart!,
      _draft.customEnd!,
    );
  }

  String _periodItemLabel(AppLocalizations l10n, _PeriodChoice choice) {
    if (choice.days case final days?) return l10n.upcomingPeriodDays(days);
    if (choice.mode case final mode?) {
      return AgendaFiltersSheet.periodModeLabel(l10n, mode, _draft.rangeDays);
    }
    return l10n.upcomingPeriodCustom;
  }

  static IconData _periodIcon(_PeriodChoice choice) => switch (choice) {
    _PeriodChoice.days7 ||
    _PeriodChoice.days30 ||
    _PeriodChoice.days90 => Icons.schedule_rounded,
    _PeriodChoice.restOfYear ||
    _PeriodChoice.wholeYear => Icons.calendar_today_rounded,
    _PeriodChoice.custom => Icons.edit_calendar_rounded,
  };

  static String _periodId(_PeriodChoice choice) => switch (choice) {
    _PeriodChoice.days7 => SemanticsIds.agendaFilterPeriod7,
    _PeriodChoice.days30 => SemanticsIds.agendaFilterPeriod30,
    _PeriodChoice.days90 => SemanticsIds.agendaFilterPeriod90,
    _PeriodChoice.restOfYear => SemanticsIds.agendaFilterPeriodRestOfYear,
    _PeriodChoice.wholeYear => SemanticsIds.agendaFilterPeriodThisYear,
    _PeriodChoice.custom => SemanticsIds.agendaFilterPeriodCustom,
  };

  static String _eventTypeId(AgendaEventType type) => switch (type) {
    AgendaEventType.all => SemanticsIds.agendaFilterEventsAll,
    AgendaEventType.recurring => SemanticsIds.agendaFilterEventsRecurring,
    AgendaEventType.oneTime => SemanticsIds.agendaFilterEventsOneTime,
    AgendaEventType.none => SemanticsIds.agendaFilterEventsNone,
  };

  /// "All", the allowed categories by name, or "No categories" — counted
  /// over the offered catalog, so a stale id left by a deleted category
  /// cannot make the row lie.
  String _categoriesValue(
    AppLocalizations l10n,
    List<CalendarCategory> categories,
  ) {
    if (_draft.categoryIds.isEmpty) return l10n.calendarFilterCategoriesAll;
    final names = [
      for (final c in categories)
        if (_draft.categoryIds.contains(c.id))
          CalendarCategories.labelOf(c, l10n),
    ];
    if (names.isEmpty) return l10n.calendarFilterNoCategories;
    return CalendarFilterSummary.namesReadBack(names, l10n);
  }

  String _priorityValue(AppLocalizations l10n) {
    if (_draft.priorities.isEmpty) return l10n.upcomingPriorityAny;
    final ascending = _draft.priorities.toList()..sort();
    return CalendarFilterSummary.namesReadBack(
      [for (final p in ascending) EventPriorities.labelOf(p, l10n)],
      l10n,
    );
  }

  /// Its own keys rather than the fasting/holiday ones, even where the English
  /// coincides: sharing strings across axes means rewording one silently
  /// rewords the others.
  String _eventDisplayLabel(AppLocalizations l10n, AgendaEventDisplay display) {
    return switch (display) {
      AgendaEventDisplay.everyOccurrence =>
        l10n.upcomingEventDisplayEveryOccurrence,
      AgendaEventDisplay.perEvent => l10n.upcomingEventDisplayPerEvent,
      AgendaEventDisplay.summary => l10n.upcomingEventDisplaySummary,
    };
  }

  static IconData _eventDisplayIcon(AgendaEventDisplay display) =>
      switch (display) {
        AgendaEventDisplay.everyOccurrence => Icons.view_agenda_outlined,
        AgendaEventDisplay.perEvent => Icons.repeat_one_rounded,
        AgendaEventDisplay.summary => Icons.summarize_outlined,
      };

  static String _eventDisplayId(AgendaEventDisplay display) =>
      switch (display) {
        AgendaEventDisplay.everyOccurrence =>
          SemanticsIds.agendaFilterEventRowsEvery,
        AgendaEventDisplay.perEvent =>
          SemanticsIds.agendaFilterEventRowsPerEvent,
        AgendaEventDisplay.summary => SemanticsIds.agendaFilterEventRowsSummary,
      };

  String _fastingDisplayLabel(
    AppLocalizations l10n,
    AgendaFastingDisplay display,
  ) {
    return switch (display) {
      AgendaFastingDisplay.everyDay => l10n.upcomingFastingDisplayEveryDay,
      AgendaFastingDisplay.periods => l10n.upcomingFastingDisplayPeriods,
      AgendaFastingDisplay.summary => l10n.upcomingFastingDisplaySummary,
    };
  }

  static IconData _fastingDisplayIcon(AgendaFastingDisplay display) =>
      switch (display) {
        AgendaFastingDisplay.everyDay => Icons.view_agenda_outlined,
        AgendaFastingDisplay.periods => Icons.date_range_rounded,
        AgendaFastingDisplay.summary => Icons.summarize_outlined,
      };

  static String _fastingDisplayId(AgendaFastingDisplay display) =>
      switch (display) {
        AgendaFastingDisplay.everyDay =>
          SemanticsIds.agendaFilterFastingRowsEveryDay,
        AgendaFastingDisplay.periods =>
          SemanticsIds.agendaFilterFastingRowsPeriods,
        AgendaFastingDisplay.summary =>
          SemanticsIds.agendaFilterFastingRowsSummary,
      };

  /// Its own keys rather than the fasting ones, even though the English words
  /// coincide: sharing strings across two axes means rewording one silently
  /// rewords the other.
  String _holidayDisplayLabel(
    AppLocalizations l10n,
    AgendaHolidayDisplay display,
  ) {
    return switch (display) {
      AgendaHolidayDisplay.everyDay => l10n.upcomingHolidayDisplayEveryDay,
      AgendaHolidayDisplay.summary => l10n.upcomingHolidayDisplaySummary,
    };
  }

  static IconData _holidayDisplayIcon(AgendaHolidayDisplay display) =>
      switch (display) {
        AgendaHolidayDisplay.everyDay => Icons.view_agenda_outlined,
        AgendaHolidayDisplay.summary => Icons.summarize_outlined,
      };

  static String _holidayDisplayId(AgendaHolidayDisplay display) =>
      switch (display) {
        AgendaHolidayDisplay.everyDay =>
          SemanticsIds.agendaFilterHolidayRowsEveryDay,
        AgendaHolidayDisplay.summary =>
          SemanticsIds.agendaFilterHolidayRowsSummary,
      };

  void _apply() {
    Navigator.of(context).pop(
      _draft.copyWith(
        priorities: Set.unmodifiable(_draft.priorities),
        categoryIds: Set.unmodifiable(_draft.categoryIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the clearance rule every calendar
    // sheet follows (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    // Read on every build so a database switch (which clears the facade)
    // cannot leave a stale category list here. Hidden categories are dropped
    // from every choosing surface, but an allowlist already holding a hidden
    // id must still show it or the user cannot un-select it.
    final categories = CalendarCategories.visiblePlus(_draft.categoryIds);
    final eventsShown = _eventsShown;
    final fastingEnabled = FastingCalendar.isEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.agendaFilterClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.upcomingFilters,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Always enabled: a no-op Apply pops the unchanged draft.
          trailing: FormHeaderTextButton(
            label: l10n.apply,
            identifier: SemanticsIds.agendaFilterApply,
            onPressed: _apply,
          ),
        ),
        Flexible(
          child: Semantics(
            identifier: SemanticsIds.agendaFilterSheet,
            child: SingleChildScrollView(
              controller: _bodyScroll,
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The window first: it is the agenda's own axis, and the
                  // anchor switch belongs to the window it moves.
                  FormRowGroup(
                    children: [
                      FormMenuRow<_PeriodChoice?>(
                        glyph: Icons.date_range_rounded,
                        label: l10n.upcomingPeriod,
                        value: _periodValue(l10n),
                        selected: _periodChoice,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.agendaFilterPeriod,
                        items: [
                          for (final choice in _PeriodChoice.values)
                            FormMenuItem(
                              value: choice,
                              label: _periodItemLabel(l10n, choice),
                              icon: _periodIcon(choice),
                              identifier: _periodId(choice),
                            ),
                        ],
                        onSelected: _selectPeriod,
                      ),
                      FormSwitchRow(
                        glyph: Icons.my_location_rounded,
                        label: l10n.upcomingFollowSelectedDay,
                        value: _draft.followSelectedDay,
                        identifier: SemanticsIds.agendaFilterFollow,
                        onChanged: (v) =>
                            _update(_draft.copyWith(followSelectedDay: v)),
                      ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.calendarFilterSectionEvents),
                  FormRowGroup(
                    children: [
                      // One axis for "which events", "No events" included:
                      // the model has no separate switch, so it can never
                      // encode the contradictory neither state two controls
                      // would allow. While nothing is listed the two rows
                      // that narrow the listing go inert, not away.
                      FormMenuRow<AgendaEventType>(
                        glyph: Icons.event_rounded,
                        label: l10n.upcomingShowEvents,
                        value: CalendarFilterSummary.eventTypeLabel(
                          l10n,
                          _draft.eventType,
                        ),
                        selected: _draft.eventType,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.agendaFilterEvents,
                        items: [
                          for (final type in AgendaEventType.values)
                            FormMenuItem(
                              value: type,
                              label: CalendarFilterSummary.eventTypeLabel(
                                l10n,
                                type,
                              ),
                              icon: CalendarFilterSummary.eventTypeIcon(type),
                              identifier: _eventTypeId(type),
                            ),
                        ],
                        onSelected: (type) =>
                            _update(_draft.copyWith(eventType: type)),
                      ),
                      FormPickerRow(
                        glyph: Icons.label_outlined,
                        label: l10n.calendarCategories,
                        value: _categoriesValue(l10n, categories),
                        identifier: SemanticsIds.agendaFilterCategories,
                        enabled: eventsShown,
                        onTap: eventsShown
                            ? () => _pickCategories(categories)
                            : null,
                      ),
                      FormPickerRow(
                        glyph: Icons.flag_outlined,
                        label: l10n.upcomingPriority,
                        value: _priorityValue(l10n),
                        identifier: SemanticsIds.agendaFilterPriority,
                        enabled: eventsShown,
                        onTap: eventsShown ? () => _pickPriorities(l10n) : null,
                      ),
                    ],
                  ),
                  // The layers add rows rather than hide them, which is why
                  // they sit apart from the narrowing rows above.
                  FormSectionLabel(text: l10n.calendarFilterSectionAlsoShow),
                  FormRowGroup(
                    children: [
                      FormSwitchRow(
                        glyph: CalendarFilterSummary.holidayIcon,
                        label: l10n.upcomingShowHolidays,
                        value: _draft.showHolidays,
                        identifier: SemanticsIds.agendaFilterHolidays,
                        onChanged: (v) =>
                            _update(_draft.copyWith(showHolidays: v)),
                      ),
                      // Fasting is inert until a tradition is configured.
                      // Disabled with its stored value rather than omitted: a
                      // row that appears between two openings moves
                      // everything under it.
                      FormSwitchRow(
                        glyph: CalendarFilterSummary.fastingIcon,
                        label: l10n.upcomingShowFasting,
                        value: _draft.showFasting,
                        identifier: SemanticsIds.agendaFilterFasting,
                        onChanged: fastingEnabled
                            ? (v) => _update(_draft.copyWith(showFasting: v))
                            : null,
                      ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.upcomingSectionDisplay),
                  FormRowGroup(
                    children: [
                      FormMenuRow<AgendaEventDisplay>(
                        glyph: Icons.view_agenda_outlined,
                        label: l10n.upcomingEventDisplayTitle,
                        value: _eventDisplayLabel(l10n, _draft.eventDisplay),
                        selected: _draft.eventDisplay,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.agendaFilterEventRows,
                        items: [
                          for (final display in AgendaEventDisplay.values)
                            FormMenuItem(
                              value: display,
                              label: _eventDisplayLabel(l10n, display),
                              icon: _eventDisplayIcon(display),
                              identifier: _eventDisplayId(display),
                            ),
                        ],
                        onSelected: (display) =>
                            _update(_draft.copyWith(eventDisplay: display)),
                      ),
                      // The same gate as the Fasting switch above, for the
                      // same reason.
                      FormMenuRow<AgendaFastingDisplay>(
                        glyph: CalendarFilterSummary.fastingIcon,
                        label: l10n.upcomingFastingDisplayTitle,
                        value: _fastingDisplayLabel(
                          l10n,
                          _draft.fastingDisplay,
                        ),
                        selected: _draft.fastingDisplay,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.agendaFilterFastingRows,
                        items: [
                          for (final display in AgendaFastingDisplay.values)
                            FormMenuItem(
                              value: display,
                              label: _fastingDisplayLabel(l10n, display),
                              icon: _fastingDisplayIcon(display),
                              identifier: _fastingDisplayId(display),
                            ),
                        ],
                        onSelected: fastingEnabled
                            ? (display) => _update(
                                _draft.copyWith(fastingDisplay: display),
                              )
                            : null,
                      ),
                      FormMenuRow<AgendaHolidayDisplay>(
                        glyph: CalendarFilterSummary.holidayIcon,
                        label: l10n.upcomingHolidayDisplayTitle,
                        value: _holidayDisplayLabel(
                          l10n,
                          _draft.holidayDisplay,
                        ),
                        selected: _draft.holidayDisplay,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.agendaFilterHolidayRows,
                        items: [
                          for (final display in AgendaHolidayDisplay.values)
                            FormMenuItem(
                              value: display,
                              label: _holidayDisplayLabel(l10n, display),
                              icon: _holidayDisplayIcon(display),
                              identifier: _holidayDisplayId(display),
                            ),
                        ],
                        onSelected: (display) =>
                            _update(_draft.copyWith(holidayDisplay: display)),
                      ),
                    ],
                  ),
                  FormRowGroup(
                    trailingGap: false,
                    children: [
                      FormActionRow(
                        glyph: Icons.restart_alt_rounded,
                        label: l10n.calendarFilterReset,
                        identifier: SemanticsIds.agendaFilterReset,
                        onTap: _isDefault ? null : _reset,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
