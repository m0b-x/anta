import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_priorities.dart';
import '../constants/fasting_calendar.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_grid_filters.dart';
import '../models/upcoming_agenda_filters.dart';
import '../services/filter_preset_service.dart';
import '../utils/calendar_filter_summary.dart';
import '../utils/custom_snackbar.dart';
import 'category_picker_sheet.dart';
import 'filter_preset_sheet.dart';

/// Result returned by [CalendarFilterSheet] when the user applies a change.
class CalendarFilterResult {
  final CalendarFormat format;
  final CalendarGridFilters filters;

  const CalendarFilterResult({required this.format, required this.filters});
}

/// Bottom-sheet that lets the user pick the calendar view range and narrow
/// the grid — by recurrence, time of day, priority, category and the boolean
/// traits.
///
/// Edits a **local draft** and returns it on Apply (or `null` when dismissed),
/// mirroring `AgendaFiltersSheet`: a live-applying sheet would re-filter the
/// event list and repaint 42 cells behind the sheet on every chip tap.
///
/// The label and icon of every axis come from [CalendarFilterSummary], never
/// from a second switch here, so this sheet, the summary chip that undoes a
/// filter and a saved preset's subtitle can never name the same thing
/// differently.
class CalendarFilterSheet extends StatefulWidget {
  final CalendarFormat initialFormat;
  final CalendarGridFilters initialFilters;

  const CalendarFilterSheet({
    super.key,
    required this.initialFormat,
    required this.initialFilters,
  });

  /// Wraps the category chip row so a test can count *those* chips without
  /// catching the priority and trait chips beside them.
  static const Key categoryChipsKey = Key('calendarFilterCategoryChips');

  static Future<CalendarFilterResult?> show(
    BuildContext context, {
    required CalendarFormat format,
    required CalendarGridFilters filters,
  }) {
    return showModalBottomSheet<CalendarFilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          CalendarFilterSheet(initialFormat: format, initialFilters: filters),
    );
  }

  @override
  State<CalendarFilterSheet> createState() => _CalendarFilterSheetState();
}

class _CalendarFilterSheetState extends State<CalendarFilterSheet> {
  late CalendarFormat _format;
  late CalendarGridFilters _draft;

  FilterPresetService? _presets;

  /// The name of the saved preset holding **exactly** the current draft, or
  /// `null`. Drives the save button's icon, its tooltip and its disabled
  /// state, so the answer to "have I already saved this?" is on screen rather
  /// than something the user has to remember.
  String? _savedName;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
    _draft = widget.initialFilters;
    _loadPresets();
  }

  /// Resolved lazily and tolerated when it fails: the sheet's whole job is
  /// editing filters, and a preset table that would not open must not take
  /// that away — it only costs the save button.
  Future<void> _loadPresets() async {
    try {
      final service = await FilterPresetService.getInstance();
      if (!mounted) return;
      setState(() {
        _presets = service;
        _savedName = service.matching(_draft)?.name;
      });
    } catch (e) {
      debugPrint('[CalendarFilterSheet] Preset load failed: $e');
    }
  }

  Set<String> get _hidden => _draft.hiddenCategoryIds;

  void _update(CalendarGridFilters next) {
    setState(() {
      _draft = next;
      // Re-resolved on every edit, not just on save: a draft that drifts back
      // onto a saved combination should show as saved again.
      _savedName = _presets?.matching(next)?.name;
    });
  }

  /// Saves the draft under a name the user confirms, pre-filled with a summary
  /// of what it filters.
  ///
  /// Saves the **draft**, not the applied filters: the user is looking at the
  /// draft, and making them Apply first before they could save it would be a
  /// step with no reason behind it.
  Future<void> _saveAsPreset() async {
    final service = _presets;
    if (service == null || _draft.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    if (service.isFull) {
      _report(l10n.filterPresetLimitReached(FilterPresetService.maxPresets));
      return;
    }
    final name = await FilterPresetNameDialog.show(
      context,
      title: l10n.filterPresetSave,
      initialName: CalendarFilterSummary.suggestName(_draft, l10n),
    );
    if (name == null || !mounted) return;
    final saved = await service.create(name: name, filters: _draft);
    if (!mounted) return;
    if (saved == null) {
      _report(l10n.filterPresetLimitReached(FilterPresetService.maxPresets));
      return;
    }
    setState(() => _savedName = saved.name);
    _report(l10n.filterPresetSaved(saved.name));
  }

  void _report(String message) {
    if (!mounted) return;
    CustomSnackbar.show(context, message);
  }

  /// Clears every filter but leaves the view range alone — a range is what
  /// you are looking through, not something being hidden from you. The panel
  /// preference survives for the same reason ([CalendarGridFilters.cleared]).
  void _reset() => _update(_draft.cleared());

  String _formatLabel(AppLocalizations l10n, CalendarFormat f) {
    return switch (f) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
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

  void _toggleCategory(String id, bool visible) {
    final next = {..._hidden};
    if (visible) {
      next.remove(id);
    } else {
      next.add(id);
    }
    _update(_draft.copyWith(hiddenCategoryIds: next));
  }

  /// Shows everything: empties the denylist outright, archived denials
  /// included.
  ///
  /// **The asymmetry with [_clearAll]'s union is deliberate, not an
  /// oversight.** That union exists so that *hiding* everything cannot
  /// accidentally un-hide something — a one-directional hazard with no mirror
  /// here. An archived category's events already render on the grid in their
  /// own colour (hiding a category archives it, it does not filter it), so
  /// restoring them is exactly what "show everything" means, and nothing about
  /// this button touches `is_hidden`. Subtracting only the visible ids instead
  /// would leave an archived denial stranded: the header would keep offering
  /// "Select all" with nothing left for it to do.
  void _selectAll() => _update(_draft.copyWith(hiddenCategoryIds: const {}));

  /// Hides everything the sheet offers. The union keeps any archived category
  /// already sitting in the denylist denied — this filter reaches events of
  /// hidden categories too, and "hide all" must not quietly un-hide one.
  void _clearAll() {
    _update(
      _draft.copyWith(
        hiddenCategoryIds: {
          ..._hidden,
          for (final c in CalendarCategories.visible) c.id,
        },
      ),
    );
  }

  /// Opens the multi-select picker over the categories currently shown.
  ///
  /// The sheet is semantics-free — a set in, a set out — and this side is a
  /// **denylist**, so the caller inverts: what comes back is what should be
  /// visible, and everything else is hidden. `pickMulti` deliberately does
  /// not collapse an empty result to `null`, because selecting nothing here
  /// means "hide every category", which is a real state.
  Future<void> _pickCategories(List<CalendarCategory> categories) async {
    final picked = await CategoryPickerSheet.pickMulti(
      context,
      selected: {
        for (final c in categories)
          if (!_hidden.contains(c.id)) c.id,
      },
    );
    if (picked == null || !mounted) return;
    _update(
      _draft.copyWith(
        hiddenCategoryIds: {
          for (final c in categories)
            if (!picked.contains(c.id)) c.id,
        },
      ),
    );
  }

  void _apply() {
    Navigator.of(context).pop(
      CalendarFilterResult(
        format: _format,
        filters: _draft.copyWith(
          hiddenCategoryIds: Set.unmodifiable(_hidden),
          priorities: Set.unmodifiable(_draft.priorities),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // `useSafeArea: true` on the modal route avoids the status bar but has
    // proven unreliable against the bottom gesture/nav bar on real devices —
    // same fix as `EventEditorSheet` / `CategoryEditorSheet`: pad the whole
    // sheet by the larger of the keyboard inset and the system's bottom
    // inset so the fixed Cancel/Apply row is never obscured.
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
                    l10n.calendarFiltersTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                // Saving lives beside Reset, the sheet's other whole-draft
                // action, rather than in the scroll body: both act on
                // everything below them, and a save button that scrolls away
                // is one the user has to go looking for.
                IconButton(
                  tooltip: _savedName == null
                      ? l10n.filterPresetSave
                      : l10n.filterPresetSaved(_savedName!),
                  isSelected: _savedName != null,
                  icon: Icon(
                    _savedName != null
                        ? Icons.bookmark_added_rounded
                        : Icons.bookmark_add_outlined,
                  ),
                  // Nothing to save while nothing is filtered, and nothing to
                  // save *again* once this exact set already has a name.
                  onPressed: _draft.isEmpty || _savedName != null
                      ? null
                      : _saveAsPreset,
                ),
                TextButton(
                  onPressed: _draft.isEmpty ? null : _reset,
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
                  _SectionLabel(l10n.calendarViewRange),
                  _segmented<CalendarFormat>(
                    values: CalendarFormat.values,
                    selected: _format,
                    labelOf: (f) => _formatLabel(l10n, f),
                    onChanged: (f) => setState(() => _format = f),
                  ),
                  const SizedBox(height: 20),
                  // Categories stay the second section, where they have always
                  // been: they are the filter reached for most, and the axes
                  // added around them must not push the familiar one below the
                  // fold.
                  _buildCategories(l10n),
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.upcomingPriority),
                  _buildPriorities(l10n),
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.calendarFilterRepeat),
                  _segmented<AgendaEventType>(
                    values: const [
                      AgendaEventType.all,
                      AgendaEventType.recurring,
                      AgendaEventType.oneTime,
                    ],
                    selected: _draft.eventType,
                    labelOf: (t) => CalendarFilterSummary.eventTypeLabel(l10n, t),
                    onChanged: (t) => _update(_draft.copyWith(eventType: t)),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.calendarFilterTiming),
                  _segmented<CalendarEventTiming>(
                    values: CalendarEventTiming.values,
                    selected: _draft.timing,
                    labelOf: (t) => CalendarFilterSummary.timingLabel(l10n, t),
                    onChanged: (t) => _update(_draft.copyWith(timing: t)),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.calendarFilterOnlyShow),
                  _buildTraits(l10n),
                  const SizedBox(height: 20),
                  _SectionLabel(l10n.upcomingSectionShow),
                  _buildLayers(l10n),
                  const SizedBox(height: 8),
                  // Last, and a switch rather than a chip, because it is the
                  // one control here that *widens* — everything above hides
                  // something, this hands one surface back.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.calendarFilterPanelShowsAll),
                    subtitle: Text(l10n.calendarFilterPanelShowsAllDesc),
                    value: _draft.panelShowsAll,
                    onChanged: (value) =>
                        _update(_draft.copyWith(panelShowsAll: value)),
                  ),
                ],
              ),
            ),
          ),
          // The body scrolls under a pinned footer; without an edge the last
          // row bleeds into the buttons with nothing to say it continues.
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text(l10n.apply),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmented<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    return SegmentedButton<T>(
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

  Widget _traitChip({
    required IconData icon,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      selected: selected,
      onSelected: onSelected,
    );
  }

  /// The narrowing traits, in the order they are most likely to be reached
  /// for. "Hide ended" sits last because it is the one that subtracts rather
  /// than selects.
  Widget _buildTraits(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _traitChip(
          icon: CalendarFilterSummary.trackedIcon,
          label: l10n.calendarFilterTracked,
          selected: _draft.trackedOnly,
          onSelected: (selected) =>
              _update(_draft.copyWith(trackedOnly: selected)),
        ),
        _traitChip(
          icon: CalendarFilterSummary.missedIcon,
          label: l10n.eventPresenceMissed,
          selected: _draft.missedOnly,
          onSelected: (selected) =>
              _update(_draft.copyWith(missedOnly: selected)),
        ),
        _traitChip(
          icon: CalendarFilterSummary.linkedNoteIcon,
          label: l10n.eventLinkedNote,
          selected: _draft.linkedNotesOnly,
          onSelected: (selected) =>
              _update(_draft.copyWith(linkedNotesOnly: selected)),
        ),
        _traitChip(
          icon: CalendarFilterSummary.moneyIcon,
          label: l10n.calendarFilterWithMoney,
          selected: _draft.moneyOnly,
          onSelected: (selected) =>
              _update(_draft.copyWith(moneyOnly: selected)),
        ),
        _traitChip(
          icon: CalendarFilterSummary.descriptionIcon,
          label: l10n.calendarFilterWithDescription,
          selected: _draft.withDescriptionOnly,
          onSelected: (selected) =>
              _update(_draft.copyWith(withDescriptionOnly: selected)),
        ),
        _traitChip(
          icon: CalendarFilterSummary.countedIcon,
          label: l10n.calendarFilterCounted,
          selected: _draft.countedOnly,
          onSelected: (selected) =>
              _update(_draft.copyWith(countedOnly: selected)),
        ),
        _traitChip(
          icon: CalendarFilterSummary.hideEndedIcon,
          label: l10n.calendarFilterHideEnded,
          selected: _draft.hideEnded,
          onSelected: (selected) =>
              _update(_draft.copyWith(hideEnded: selected)),
        ),
      ],
    );
  }

  /// The day annotations — not event filters. Each chip is **on** by default
  /// and composes a provider out of the bar/tint/summary resolvers when
  /// switched off, so it clears the annotation from the grid and the day panel
  /// together.
  Widget _buildLayers(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _traitChip(
          icon: CalendarFilterSummary.holidayIcon,
          label: l10n.upcomingShowHolidays,
          selected: _draft.showHolidays,
          onSelected: (selected) =>
              _update(_draft.copyWith(showHolidays: selected)),
        ),
        // Fasting is inert until a tradition is configured, so the chip only
        // appears once it can act — the same gate the agenda sheet uses.
        if (FastingCalendar.isEnabled)
          _traitChip(
            icon: CalendarFilterSummary.fastingIcon,
            label: l10n.upcomingShowFasting,
            selected: _draft.showFasting,
            onSelected: (selected) =>
                _update(_draft.copyWith(showFasting: selected)),
          ),
        _traitChip(
          icon: CalendarFilterSummary.moneyIcon,
          label: l10n.calendarFilterMoneyLayer,
          selected: _draft.showMoney,
          onSelected: (selected) =>
              _update(_draft.copyWith(showMoney: selected)),
        ),
      ],
    );
  }

  Widget _buildCategories(AppLocalizations l10n) {
    final allSelected = _hidden.isEmpty;
    // Hidden categories leave every choosing surface, but a denylist already
    // holding an archived id must still show it or the user cannot un-hide
    // what they can no longer see.
    final categories = CalendarCategories.visiblePlus(_hidden);
    final shown = [
      for (final c in categories)
        if (!_hidden.contains(c.id)) c,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _SectionLabel(l10n.calendarEventCategories)),
            TextButton(
              onPressed: allSelected ? _clearAll : _selectAll,
              child: Text(
                allSelected ? l10n.calendarClearAll : l10n.calendarSelectAll,
              ),
            ),
          ],
        ),
        // Short sets are genuinely better as chips — one tap, no navigation.
        // Past the threshold the wall of chips buries the sections above it,
        // so it collapses to one row plus a sub-sheet. Select all / Clear all
        // stay in the header either way, so the common "show everything
        // again" reset never needs the sub-sheet.
        if (categories.length > AppConstants.listSearchThreshold)
          CategoryFilterTile(
            offered: categories,
            selected: shown,
            selectsAll: shown.length == categories.length,
            onTap: () => _pickCategories(categories),
          )
        else
          Wrap(
            key: CalendarFilterSheet.categoryChipsKey,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                FilterChip(
                  avatar: CircleAvatar(
                    backgroundColor: c.color.withValues(alpha: 0.18),
                    foregroundColor: c.color,
                    child: Icon(
                      CalendarIcons.forKey(c.iconKey) ?? Icons.event_rounded,
                      size: 16,
                    ),
                  ),
                  label: Text(CalendarCategories.labelOf(c, l10n)),
                  selected: !_hidden.contains(c.id),
                  onSelected: (sel) => _toggleCategory(c.id, sel),
                ),
            ],
          ),
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
