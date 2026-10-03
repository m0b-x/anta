import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_priorities.dart';
import '../constants/fasting_calendar.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_grid_filters.dart';
import '../models/upcoming_agenda_filters.dart';
import '../services/filter_preset_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/calendar_filter_summary.dart';
import 'category_picker_sheet.dart';
import 'filter_check_list_sheet.dart';
import 'filter_preset_sheet.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';

/// Bottom-sheet that narrows the grid — by category, priority, recurrence,
/// time of day and the boolean traits — and switches the day annotations.
/// How the grid is *looked at* (month, two weeks, a week) is not a filter and
/// lives in the title's view menu.
///
/// A two-level summary in the editor's grouped-row language (the 2026-09-27
/// redesign, `docs/calendar-filters-redesign-roadmap.md`): a *set* is a
/// picker row that reads its value back and opens a check-list sub-sheet, a
/// three-way choice is a menu row, a boolean is a switch row. Twelve rows,
/// so the top level never scrolls on a phone and every row says what it is
/// set to.
///
/// Edits a **local draft** and returns it on Apply (or `null` when dismissed),
/// mirroring `AgendaFiltersSheet`: a live-applying sheet would re-filter the
/// event list and repaint 42 cells behind the sheet on every tap. No discard
/// guard: the sheet holds no typed text, and the draft costs a tap to redo.
///
/// The label and icon of every axis come from [CalendarFilterSummary], never
/// from a second switch here, so this sheet, the summary chip that undoes a
/// filter and a saved preset's subtitle can never name the same thing
/// differently.
class CalendarFilterSheet extends StatefulWidget {
  final CalendarGridFilters initialFilters;

  const CalendarFilterSheet({super.key, required this.initialFilters});

  /// The sub-sheet shape: as tall as its content, clamped at the editor's
  /// height, the route's own drag.
  static Future<CalendarGridFilters?> show(
    BuildContext context, {
    required CalendarGridFilters filters,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<CalendarGridFilters>(
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
        child: CalendarFilterSheet(initialFilters: filters),
      ),
    );
  }

  @override
  State<CalendarFilterSheet> createState() => _CalendarFilterSheetState();
}

/// One of the seven "Only show" traits: its id on the check-list sheet, the
/// facet icon and label the chip strip shows for it, and the flag it reads
/// and writes.
class _Trait {
  final String id;
  final IconData icon;
  final String label;
  final bool Function(CalendarGridFilters filters) isSet;
  final CalendarGridFilters Function(CalendarGridFilters filters, bool value)
  write;

  const _Trait({
    required this.id,
    required this.icon,
    required this.label,
    required this.isSet,
    required this.write,
  });
}

class _CalendarFilterSheetState extends State<CalendarFilterSheet> {
  late CalendarGridFilters _draft;

  FilterPresetService? _presets;

  /// The name of the saved preset holding **exactly** the current draft, or
  /// `null`. Drives the Saved filter row's value, its bookmark's icon, tooltip
  /// and disabled state, so the answer to "have I already saved this?" is on
  /// screen rather than something the user has to remember.
  String? _savedName;

  /// Guards the sheet's own sub-routes — the four sub-sheets and the save
  /// dialog — against a double tap pushing two identical copies, which reads
  /// as a sheet that will not close. One flag for all: they are never nested.
  bool _subRouteOpen = false;

  /// The body's scroll position feeds the header's hairline (a form sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilters;
    _bodyScroll.addListener(_onBodyScroll);
    _loadPresets();
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

  /// Resolved lazily and tolerated when it fails: the sheet's whole job is
  /// editing filters, and a preset table that would not open must not take
  /// that away — it only costs the Saved filter row its name and its bookmark.
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
    await _guarded(() async {
      final name = await FilterPresetNameDialog.show(
        context,
        title: l10n.filterPresetSave,
        initialName: CalendarFilterSummary.suggestName(_draft, l10n),
        // Both save paths warn on a duplicate name, or the warning would be a
        // property of which sheet you happened to save from.
        existingNames: {
          for (final preset in service.presets)
            normalizeForSearch(preset.name),
        },
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
    });
  }

  /// In the overlay, not the page's `Scaffold`: this sheet is a route above
  /// that page, and a bar raised there is drawn under the sheet.
  void _report(String message) {
    if (!mounted) return;
    OverlaySnackbar.show(
      context,
      message,
      duration: AppConstants.snackbarDuration,
    );
  }

  /// Clears every filter but leaves the panel preference alone
  /// ([CalendarGridFilters.cleared]): it hides nothing, it hands the day
  /// panel its whole day back. The sheet stays open.
  void _reset() => _update(_draft.cleared());

  /// Opens the saved filters over the draft. A pick — a preset, or "No
  /// filter" — replaces the draft; a dismissal changes nothing but the name
  /// the row reads, which is re-resolved because the list may have been
  /// renamed or pruned while the sheet was up.
  Future<void> _openPresets() => _guarded(() async {
    final picked = await FilterPresetSheet.show(context, current: _draft);
    if (!mounted) return;
    if (picked != null) {
      _update(picked);
      return;
    }
    setState(() => _savedName = _presets?.matching(_draft)?.name);
  });

  /// Opens the multi-select picker over the categories currently shown.
  ///
  /// The sheet is semantics-free — a set in, a set out — and this side is a
  /// **denylist**, so the caller inverts: what comes back is what should be
  /// visible, and everything else is hidden. `pickMulti` deliberately does
  /// not collapse an empty result to `null`, because selecting nothing here
  /// means "hide every category", which is a real state.
  ///
  /// An answer that ticks every listed row — the picker's Select all, or every
  /// row by hand — **empties the denylist outright, archived denials
  /// included.** The picker never lists a denied archived category (a hidden
  /// category reaches it only inside a selection, and a denied one is not
  /// selected), so subtracting the answer from the offered set would strand
  /// that denial where no row could ever clear it: the row would keep
  /// reading a count with nothing left to un-tick. Restoring an archived
  /// category's events is exactly what "show everything" means — its events
  /// already render on the grid in their own colour, since hiding a category
  /// archives it rather than filtering it — and nothing here touches
  /// `is_hidden`. Select none un-ticks the listed rows, the picker's own rule.
  ///
  /// An empty picker (every category archived) has no listed row to tick, so
  /// its Done is no such answer and the archived denials stay.
  Future<void> _pickCategories() => _guarded(() async {
    final picked = await CategoryPickerSheet.pickMulti(
      context,
      selected: {
        for (final c in CalendarCategories.visiblePlus(_hidden))
          if (!_hidden.contains(c.id)) c.id,
      },
    );
    if (picked == null || !mounted) return;
    // Read again after the picker returns, never from the build that opened
    // it: a category created inside the picker is visible now, and an answer
    // that omits it must deny it.
    final visible = CalendarCategories.visible;
    final everyListedRow =
        visible.isNotEmpty && visible.every((c) => picked.contains(c.id));
    _update(
      _draft.copyWith(
        hiddenCategoryIds: everyListedRow
            ? const {}
            : {
                for (final c in CalendarCategories.visiblePlus(_hidden))
                  if (!picked.contains(c.id)) c.id,
              },
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

  Future<void> _pickTraits(AppLocalizations l10n) => _guarded(() async {
    final traits = _traitsOf(l10n);
    final picked = await FilterCheckListSheet.show(
      context,
      title: l10n.calendarFilterOnlyShow,
      items: [
        for (final trait in traits)
          FilterCheckItem(
            id: trait.id,
            icon: trait.icon,
            label: trait.label,
            identifier: SemanticsIds.filterListRow(trait.id),
          ),
      ],
      selected: {
        for (final trait in traits)
          if (trait.isSet(_draft)) trait.id,
      },
    );
    if (picked == null || !mounted) return;
    var next = _draft;
    for (final trait in traits) {
      next = trait.write(next, picked.contains(trait.id));
    }
    _update(next);
  });

  /// The narrowing traits, in the order they are most likely to be reached
  /// for. "Not ended" sits last because it is the one that subtracts rather
  /// than selects. The chip strip keeps its own order through `facetsOf`.
  static List<_Trait> _traitsOf(AppLocalizations l10n) => [
    _Trait(
      id: 'tracked',
      icon: CalendarFilterSummary.trackedIcon,
      label: l10n.calendarFilterTracked,
      isSet: (f) => f.trackedOnly,
      write: (f, v) => f.copyWith(trackedOnly: v),
    ),
    _Trait(
      id: 'missed',
      icon: CalendarFilterSummary.missedIcon,
      label: l10n.eventPresenceMissed,
      isSet: (f) => f.missedOnly,
      write: (f, v) => f.copyWith(missedOnly: v),
    ),
    _Trait(
      id: 'linked-note',
      icon: CalendarFilterSummary.linkedNoteIcon,
      label: l10n.eventLinkedNote,
      isSet: (f) => f.linkedNotesOnly,
      write: (f, v) => f.copyWith(linkedNotesOnly: v),
    ),
    _Trait(
      id: 'money',
      icon: CalendarFilterSummary.moneyIcon,
      label: l10n.calendarFilterWithMoney,
      isSet: (f) => f.moneyOnly,
      write: (f, v) => f.copyWith(moneyOnly: v),
    ),
    _Trait(
      id: 'description',
      icon: CalendarFilterSummary.descriptionIcon,
      label: l10n.calendarFilterWithDescription,
      isSet: (f) => f.withDescriptionOnly,
      write: (f, v) => f.copyWith(withDescriptionOnly: v),
    ),
    _Trait(
      id: 'counted',
      icon: CalendarFilterSummary.countedIcon,
      label: l10n.calendarFilterCounted,
      isSet: (f) => f.countedOnly,
      write: (f, v) => f.copyWith(countedOnly: v),
    ),
    _Trait(
      id: 'not-ended',
      icon: CalendarFilterSummary.hideEndedIcon,
      label: l10n.calendarFilterHideEnded,
      isSet: (f) => f.hideEnded,
      write: (f, v) => f.copyWith(hideEnded: v),
    ),
  ];

  /// "All", the shown categories by name, or "No categories" — counted over
  /// the offered catalog, so a stale id left by a deleted category cannot
  /// make the row lie.
  String _categoriesValue(
    AppLocalizations l10n,
    List<CalendarCategory> categories,
  ) {
    if (_hidden.isEmpty) return l10n.calendarFilterCategoriesAll;
    final shown = [
      for (final c in categories)
        if (!_hidden.contains(c.id)) CalendarCategories.labelOf(c, l10n),
    ];
    if (shown.isEmpty) return l10n.calendarFilterNoCategories;
    return CalendarFilterSummary.namesReadBack(shown, l10n);
  }

  String _priorityValue(AppLocalizations l10n) {
    if (_draft.priorities.isEmpty) return l10n.upcomingPriorityAny;
    final ascending = _draft.priorities.toList()..sort();
    return CalendarFilterSummary.namesReadBack(
      [for (final p in ascending) EventPriorities.labelOf(p, l10n)],
      l10n,
    );
  }

  String _traitsValue(AppLocalizations l10n) {
    final names = [
      for (final trait in _traitsOf(l10n))
        if (trait.isSet(_draft)) trait.label,
    ];
    if (names.isEmpty) return l10n.calendarFilterOnlyShowAny;
    return CalendarFilterSummary.namesReadBack(names, l10n);
  }

  void _apply() {
    Navigator.of(context).pop(
      _draft.copyWith(
        hiddenCategoryIds: Set.unmodifiable(_hidden),
        priorities: Set.unmodifiable(_draft.priorities),
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
    // Hidden categories leave every choosing surface, but a denylist already
    // holding an archived id must still offer it or the user cannot un-hide
    // what they can no longer see.
    final categories = CalendarCategories.visiblePlus(_hidden);
    final savedName = _savedName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.filterClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.calendarFiltersTitle,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Always enabled: a no-op Apply pops the unchanged draft.
          trailing: FormHeaderTextButton(
            label: l10n.apply,
            identifier: SemanticsIds.filterApply,
            onPressed: _apply,
          ),
        ),
        Flexible(
          child: Semantics(
            identifier: SemanticsIds.filterSheet,
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
                  FormRowGroup(
                    children: [
                      // The row names the lens the draft matches and opens
                      // the list; its bookmark saves the draft. Nothing to
                      // save while nothing is filtered, and nothing to save
                      // *again* once this exact set already has a name.
                      FormPickerRow(
                        glyph: Icons.bookmark_border_rounded,
                        label: l10n.calendarFilterSavedFilter,
                        value: savedName ?? l10n.calendarFilterSavedNone,
                        identifier: SemanticsIds.filterSavedFilter,
                        onTap: _openPresets,
                        trailingButton: FormTrailingButton(
                          icon: savedName == null
                              ? Icons.bookmark_add_outlined
                              : Icons.bookmark_added_rounded,
                          tooltip: savedName == null
                              ? l10n.filterPresetSave
                              : l10n.filterPresetSaved(savedName),
                          identifier: SemanticsIds.filterSave,
                          onPressed: _draft.isEmpty || savedName != null
                              ? null
                              : _saveAsPreset,
                        ),
                      ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.calendarFilterSectionEvents),
                  FormRowGroup(
                    children: [
                      FormPickerRow(
                        glyph: Icons.label_outlined,
                        label: l10n.calendarCategories,
                        value: _categoriesValue(l10n, categories),
                        identifier: SemanticsIds.filterCategories,
                        onTap: _pickCategories,
                      ),
                      FormPickerRow(
                        glyph: Icons.flag_outlined,
                        label: l10n.upcomingPriority,
                        value: _priorityValue(l10n),
                        identifier: SemanticsIds.filterPriority,
                        onTap: () => _pickPriorities(l10n),
                      ),
                      FormMenuRow<AgendaEventType>(
                        glyph: Icons.repeat_rounded,
                        label: l10n.calendarFilterRepeat,
                        value: CalendarFilterSummary.eventTypeLabel(
                          l10n,
                          _draft.eventType,
                        ),
                        selected: _draft.eventType,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.filterRepeat,
                        items: [
                          for (final (type, id) in const [
                            (AgendaEventType.all, SemanticsIds.filterRepeatAll),
                            (
                              AgendaEventType.recurring,
                              SemanticsIds.filterRepeatRecurring,
                            ),
                            (
                              AgendaEventType.oneTime,
                              SemanticsIds.filterRepeatOneTime,
                            ),
                          ])
                            FormMenuItem(
                              value: type,
                              label: CalendarFilterSummary.eventTypeLabel(
                                l10n,
                                type,
                              ),
                              icon: CalendarFilterSummary.eventTypeIcon(type),
                              identifier: id,
                            ),
                        ],
                        onSelected: (type) =>
                            _update(_draft.copyWith(eventType: type)),
                      ),
                      FormMenuRow<CalendarEventTiming>(
                        glyph: Icons.schedule_outlined,
                        label: l10n.calendarFilterTiming,
                        value: CalendarFilterSummary.timingLabel(
                          l10n,
                          _draft.timing,
                        ),
                        selected: _draft.timing,
                        menuWidth: FormMetrics.menuWidth,
                        identifier: SemanticsIds.filterTime,
                        items: [
                          for (final timing in CalendarEventTiming.values)
                            FormMenuItem(
                              value: timing,
                              label: CalendarFilterSummary.timingLabel(
                                l10n,
                                timing,
                              ),
                              icon: CalendarFilterSummary.timingIcon(timing),
                              identifier: _timingId(timing),
                            ),
                        ],
                        onSelected: (timing) =>
                            _update(_draft.copyWith(timing: timing)),
                      ),
                      FormPickerRow(
                        glyph: Icons.tune_rounded,
                        label: l10n.calendarFilterOnlyShow,
                        value: _traitsValue(l10n),
                        identifier: SemanticsIds.filterOnlyShow,
                        onTap: () => _pickTraits(l10n),
                      ),
                    ],
                  ),
                  // The day annotations — not event filters. Each is **on** by
                  // default and composes a provider out of the bar/tint/summary
                  // resolvers when switched off, clearing the annotation from
                  // the grid and the day panel together. The panel switch is
                  // the one control here that *widens*.
                  FormSectionLabel(text: l10n.calendarFilterSectionAlsoShow),
                  FormRowGroup(
                    children: [
                      FormSwitchRow(
                        glyph: CalendarFilterSummary.holidayIcon,
                        label: l10n.upcomingShowHolidays,
                        value: _draft.showHolidays,
                        identifier: SemanticsIds.filterHolidays,
                        onChanged: (v) =>
                            _update(_draft.copyWith(showHolidays: v)),
                      ),
                      // Fasting is inert until a tradition is configured —
                      // the same gate the agenda sheet uses. Disabled with its
                      // stored value rather than omitted: a row that appears
                      // between two openings moves everything under it.
                      FormSwitchRow(
                        glyph: CalendarFilterSummary.fastingIcon,
                        label: l10n.upcomingShowFasting,
                        value: _draft.showFasting,
                        identifier: SemanticsIds.filterFasting,
                        onChanged: FastingCalendar.isEnabled
                            ? (v) => _update(_draft.copyWith(showFasting: v))
                            : null,
                      ),
                      FormSwitchRow(
                        glyph: CalendarFilterSummary.moneyIcon,
                        label: l10n.calendarFilterMoneyLayer,
                        value: _draft.showMoney,
                        identifier: SemanticsIds.filterMoney,
                        onChanged: (v) =>
                            _update(_draft.copyWith(showMoney: v)),
                      ),
                      FormSwitchRow(
                        glyph: Icons.view_day_outlined,
                        label: l10n.calendarFilterPanelShowsAll,
                        value: _draft.panelShowsAll,
                        identifier: SemanticsIds.filterPanelAll,
                        onChanged: (v) =>
                            _update(_draft.copyWith(panelShowsAll: v)),
                      ),
                    ],
                  ),
                  FormRowGroup(
                    trailingGap: false,
                    children: [
                      FormActionRow(
                        glyph: Icons.restart_alt_rounded,
                        label: l10n.calendarFilterReset,
                        identifier: SemanticsIds.filterReset,
                        onTap: _draft.isEmpty ? null : _reset,
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

  static String _timingId(CalendarEventTiming timing) => switch (timing) {
    CalendarEventTiming.all => SemanticsIds.filterTimeAll,
    CalendarEventTiming.timed => SemanticsIds.filterTimeTimed,
    CalendarEventTiming.allDay => SemanticsIds.filterTimeAllDay,
  };
}
