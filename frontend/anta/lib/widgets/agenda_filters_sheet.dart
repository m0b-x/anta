import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_priorities.dart';
import '../constants/fasting_calendar.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/upcoming_agenda_filters.dart';
import '../utils/event_agenda.dart';
import 'agenda_list_view.dart';
import 'category_picker_sheet.dart';

/// Every upcoming-agenda filter, in one modal sheet.
///
/// These are set-and-forget, persisted choices, so they do not earn permanent
/// space in a bottom panel that is already short — the panel keeps only the
/// search field and a summary of what is currently narrowing the results.
///
/// Edits a **local draft** and returns it on Apply (or `null` when dismissed),
/// mirroring [CalendarCategories]-based sibling sheets: a live-applying sheet
/// would re-run the agenda scan on every chip tap behind the sheet. [query] is
/// never touched here — it belongs to the panel's search field.
class AgendaFiltersSheet extends StatefulWidget {
  final UpcomingAgendaFilters initial;

  const AgendaFiltersSheet({super.key, required this.initial});

  /// Names one period choice. Shared with the panel's summary chip so the
  /// sheet and the chip that undoes it can never name the same window
  /// differently. [AgendaPeriodMode.rollingDays] has no chip of its own — it
  /// is the preset row — so it falls back to the window it spans.
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

  static Future<UpcomingAgendaFilters?> show(
    BuildContext context, {
    required UpcomingAgendaFilters filters,
  }) {
    return showModalBottomSheet<UpcomingAgendaFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AgendaFiltersSheet(initial: filters),
    );
  }

  @override
  State<AgendaFiltersSheet> createState() => _AgendaFiltersSheetState();
}

class _AgendaFiltersSheetState extends State<AgendaFiltersSheet> {
  late UpcomingAgendaFilters _draft = widget.initial;

  /// Which events layer to restore when the Events toggle comes back on.
  /// Held here rather than in the model so switching the layer off and on
  /// again is not silently a reset to "All".
  late AgendaEventType _lastEventType = _draft.eventType == AgendaEventType.none
      ? AgendaEventType.all
      : _draft.eventType;

  bool get _eventsShown => _draft.eventType != AgendaEventType.none;

  void _update(UpcomingAgendaFilters next) => setState(() => _draft = next);

  void _reset() {
    setState(() {
      _draft = const UpcomingAgendaFilters().copyWith(query: _draft.query);
      _lastEventType = AgendaEventType.all;
    });
  }

  void _setEventsShown(bool shown) {
    if (!shown) _lastEventType = _draft.eventType;
    _update(
      _draft.copyWith(eventType: shown ? _lastEventType : AgendaEventType.none),
    );
  }

  void _togglePriority(int priority, bool selected) {
    final next = {..._draft.priorities};
    if (selected) {
      next.add(priority);
    } else {
      next.remove(priority);
    }
    _update(_draft.copyWith(priorities: next));
  }

  void _toggleCategory(String id, bool selected) {
    final next = {..._draft.categoryIds};
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    _update(_draft.copyWith(categoryIds: next));
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
  /// tile above says so, and opening it unchecked would make one state read
  /// two ways (and disagree with the calendar filter's sub-sheet, which
  /// inverts its denylist and so opens checked for the same "everything
  /// shown" state). A result covering everything on offer collapses back to
  /// the empty set rather than freezing today's catalog into an explicit
  /// list, which would silently exclude every category created afterwards.
  ///
  /// Unchecking every row still stores the empty set — the same thing
  /// unchecking every chip does below the threshold, and the only reading
  /// "no allowlist" has.
  ///
  /// It returns into the local draft, so nothing re-runs the agenda scan
  /// behind the sheet until Apply.
  Future<void> _pickCategories(List<CalendarCategory> categories) async {
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
      initialDateRange: _draft.hasCustomRange
          ? DateTimeRange(start: _draft.customStart!, end: _draft.customEnd!)
          : DateTimeRange(
              start: now,
              end: now.add(Duration(days: _draft.rangeDays)),
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

  String _eventTypeLabel(AppLocalizations l10n, AgendaEventType type) {
    return switch (type) {
      AgendaEventType.all => l10n.upcomingEventTypeAll,
      AgendaEventType.recurring => l10n.upcomingEventTypeRecurring,
      AgendaEventType.oneTime => l10n.upcomingEventTypeOneTime,
      AgendaEventType.none => l10n.upcomingEventsHidden,
    };
  }

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // `useSafeArea: true` guards the status bar but is unreliable against the
    // bottom gesture/nav bar on real devices, so pad by the larger of the
    // keyboard and system bottom insets — the same fix the sibling calendar
    // sheets use so the Apply button is never covered.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.upcomingFilters,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _reset,
                  child: Text(l10n.upcomingFiltersReset),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionLabel(l10n.upcomingSectionPeriod),
                  _buildPeriod(l10n),
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.upcomingSectionShow),
                  _buildLayers(l10n),
                  if (_eventsShown) ...[
                    const SizedBox(height: 20),
                    _SectionLabel(l10n.upcomingPriority),
                    _buildPriorities(l10n),
                    const SizedBox(height: 20),
                    _SectionLabel(l10n.calendarCategories),
                    _buildCategories(l10n),
                  ],
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.upcomingSectionDisplay),
                  _buildDisplay(l10n),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              child: Text(l10n.apply),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriod(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final days in UpcomingAgendaFilters.rangePresets)
          ChoiceChip(
            label: Text(l10n.upcomingPeriodDays(days)),
            visualDensity: VisualDensity.compact,
            selected:
                !_draft.hasCustomRange &&
                _draft.periodMode == AgendaPeriodMode.rollingDays &&
                _draft.rangeDays == days,
            onSelected: (selected) {
              if (!selected) return;
              _update(
                _draft.copyWith(
                  periodMode: AgendaPeriodMode.rollingDays,
                  rangeDays: days,
                  clearCustomRange: true,
                ),
              );
            },
          ),
        // The two year windows are anchored to the calendar year rather than
        // counted forward, which is why they cannot be expressed as another
        // entry in `rangePresets`.
        for (final mode in const [
          AgendaPeriodMode.restOfYear,
          AgendaPeriodMode.wholeYear,
        ])
          ChoiceChip(
            label: Text(
              AgendaFiltersSheet.periodModeLabel(l10n, mode, _draft.rangeDays),
            ),
            visualDensity: VisualDensity.compact,
            selected: !_draft.hasCustomRange && _draft.periodMode == mode,
            onSelected: (selected) {
              if (!selected) return;
              _update(
                _draft.copyWith(periodMode: mode, clearCustomRange: true),
              );
            },
          ),
        InputChip(
          avatar: const Icon(Icons.date_range_rounded, size: 18),
          label: Text(
            _draft.hasCustomRange
                ? _rangeLabel(l10n)
                : l10n.upcomingPeriodCustom,
          ),
          visualDensity: VisualDensity.compact,
          // The date_range avatar is the chip's identity; with a range active
          // the delete "x" already signals selection, so the checkmark would
          // only crowd the chip.
          showCheckmark: false,
          selected: _draft.hasCustomRange,
          onSelected: (_) => _pickCustomRange(),
          onDeleted: _draft.hasCustomRange
              ? () => _update(_draft.copyWith(clearCustomRange: true))
              : null,
          deleteButtonTooltipMessage: l10n.upcomingClearRange,
        ),
      ],
    );
  }

  String _rangeLabel(AppLocalizations l10n) {
    return AgendaListView.rangeLabel(
      l10n.localeName,
      _draft.customStart!,
      _draft.customEnd!,
    );
  }

  Widget _buildLayers(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: const Icon(Icons.event_rounded, size: 18),
              label: Text(l10n.upcomingShowEvents),
              visualDensity: VisualDensity.compact,
              selected: _eventsShown,
              onSelected: _setEventsShown,
            ),
            FilterChip(
              avatar: const Icon(Icons.celebration_rounded, size: 18),
              label: Text(l10n.upcomingShowHolidays),
              visualDensity: VisualDensity.compact,
              selected: _draft.showHolidays,
              onSelected: (selected) =>
                  _update(_draft.copyWith(showHolidays: selected)),
            ),
            // Fasting is inert until a tradition is configured, so the chip
            // only appears once it can act.
            if (FastingCalendar.isEnabled)
              FilterChip(
                avatar: const Icon(Icons.no_food_rounded, size: 18),
                label: Text(l10n.upcomingShowFasting),
                visualDensity: VisualDensity.compact,
                selected: _draft.showFasting,
                onSelected: (selected) =>
                    _update(_draft.copyWith(showFasting: selected)),
              ),
          ],
        ),
        // The events sub-choice, so "which events" reads as a refinement of
        // the layer rather than as a fourth peer of the layer toggles.
        if (_eventsShown) ...[
          const SizedBox(height: 12),
          SegmentedButton<AgendaEventType>(
            segments: [
              for (final type in const [
                AgendaEventType.all,
                AgendaEventType.recurring,
                AgendaEventType.oneTime,
              ])
                ButtonSegment<AgendaEventType>(
                  value: type,
                  label: Text(
                    _eventTypeLabel(l10n, type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            selected: {_draft.eventType},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (selection) {
              _lastEventType = selection.first;
              _update(_draft.copyWith(eventType: selection.first));
            },
          ),
        ],
      ],
    );
  }

  Widget _buildPriorities(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(l10n.upcomingPriorityAny),
          visualDensity: VisualDensity.compact,
          selected: _draft.priorities.isEmpty,
          onSelected: (selected) {
            if (selected) _update(_draft.copyWith(priorities: const {}));
          },
        ),
        // Ascending: P1 (highest) leads, since lower numbers rank higher.
        for (
          var priority = kMinEventPriority;
          priority <= kMaxEventPriority;
          priority++
        )
          FilterChip(
            avatar: Icon(EventPriorities.iconFor(priority), size: 18),
            label: Text(EventPriorities.labelOf(priority, l10n)),
            visualDensity: VisualDensity.compact,
            selected: _draft.priorities.contains(priority),
            onSelected: (selected) => _togglePriority(priority, selected),
          ),
      ],
    );
  }

  Widget _buildCategories(AppLocalizations l10n) {
    // Read on every build so a database switch (which clears the facade)
    // cannot leave a stale category list here. Hidden categories are dropped
    // from every choosing surface, but an allowlist already holding a hidden
    // id must still show it or the user cannot un-select it.
    final categories = CalendarCategories.visiblePlus(_draft.categoryIds);
    final selectedCategories = [
      for (final category in categories)
        if (_draft.categoryIds.contains(category.id)) category,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Short sets are genuinely better as chips — one tap, no navigation.
        // Past the threshold the wall of chips buries every other section, so
        // it collapses to one row plus a sub-sheet.
        if (categories.length > AppConstants.listSearchThreshold)
          CategoryFilterTile(
            selected: selectedCategories,
            selectsAll:
                _draft.categoryIds.isEmpty ||
                selectedCategories.length == categories.length,
            onTap: () => _pickCategories(categories),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in categories)
                FilterChip(
                  avatar: CircleAvatar(
                    backgroundColor: category.color.withValues(alpha: 0.18),
                    foregroundColor: category.color,
                    child: Icon(
                      CalendarIcons.forKey(category.iconKey) ??
                          Icons.event_rounded,
                      size: 16,
                    ),
                  ),
                  label: Text(CalendarCategories.labelOf(category, l10n)),
                  selected: _draft.categoryIds.contains(category.id),
                  onSelected: (selected) =>
                      _toggleCategory(category.id, selected),
                ),
            ],
          ),
        // An empty allowlist already means "all", so the reset only appears
        // when there is a selection to clear.
        if (_draft.categoryIds.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _update(_draft.copyWith(categoryIds: const {})),
              child: Text(l10n.upcomingClearCategories),
            ),
          ),
      ],
    );
  }

  Widget _buildDisplay(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _displayControl<AgendaEventDisplay>(
          icon: Icons.event_rounded,
          label: l10n.upcomingEventDisplayTitle,
          values: AgendaEventDisplay.values,
          selected: _draft.eventDisplay,
          labelOf: (display) => _eventDisplayLabel(l10n, display),
          onChanged: (display) =>
              _update(_draft.copyWith(eventDisplay: display)),
        ),
        // Fasting is inert until a tradition is configured, so its control
        // only appears once it can act. Holidays are always available.
        if (FastingCalendar.isEnabled)
          _displayControl<AgendaFastingDisplay>(
            icon: Icons.no_food_rounded,
            label: l10n.upcomingFastingDisplayTitle,
            values: AgendaFastingDisplay.values,
            selected: _draft.fastingDisplay,
            labelOf: (display) => _fastingDisplayLabel(l10n, display),
            onChanged: (display) =>
                _update(_draft.copyWith(fastingDisplay: display)),
          ),
        _displayControl<AgendaHolidayDisplay>(
          icon: Icons.celebration_rounded,
          label: l10n.upcomingHolidayDisplayTitle,
          values: AgendaHolidayDisplay.values,
          selected: _draft.holidayDisplay,
          labelOf: (display) => _holidayDisplayLabel(l10n, display),
          onChanged: (display) =>
              _update(_draft.copyWith(holidayDisplay: display)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          secondary: const Icon(Icons.my_location_rounded),
          title: Text(l10n.upcomingFollowSelectedDay),
          value: _draft.followSelectedDay,
          onChanged: (value) =>
              _update(_draft.copyWith(followSelectedDay: value)),
        ),
      ],
    );
  }

  /// One "how is this layer presented" control: mutually exclusive options, so
  /// a `SegmentedButton` rather than a switch — the same shape the events
  /// sub-choice uses in the Show section. Shared by the fasting and holiday
  /// axes so the two cannot drift apart visually.
  Widget _displayControl<T>({
    required IconData icon,
    required String label,
    required List<T> values,
    required T selected,
    required String Function(T value) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon),
              // Matches the zero-padding SwitchListTiles' title offset, so the
              // label lines up with the switches above and below it.
              const SizedBox(width: 16),
              Expanded(child: Text(label)),
            ],
          ),
        ),
        SegmentedButton<T>(
          segments: [
            for (final value in values)
              ButtonSegment<T>(
                value: value,
                label: Text(
                  labelOf(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selected: {selected},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
