import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_filter_preset.dart';
import '../models/calendar_grid_filters.dart';
import '../services/filter_preset_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/calendar_filter_summary.dart';
import 'app_dialogs.dart';
import 'form_menu_item.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'settings_reorder.dart';

/// Bottom-sheet listing the user's saved filters: "No filter" first, then
/// one two-line radio row per preset with its drag handle and its ⋮, then
/// the row that saves the live filter — a sub-sheet of the editor's
/// grouped-row language since the 2026-09-27 filter redesign
/// (`docs/calendar-filters-redesign-roadmap.md`, D14), reorderable since
/// 2026-09-29 (`docs/calendar-saved-filters-roadmap.md`), opened from the
/// calendar's app bar over the applied filters and from the filter sheet's
/// Saved filter row over the draft.
///
/// Returns the [CalendarGridFilters] to apply, or `null` when dismissed —
/// renames, updates, deletes and reorders happen in place and never pop, so
/// the sheet stays open while you tidy the list and only closes when you
/// actually pick something.
///
/// The body is one `ReorderableListView` that owns its own scrolling — the
/// "No filter" group as its header, the search row, the presets and the save
/// row as its items, each drawn in a [FormRowShell] so the run reads as one
/// group. A reorderable list nested inside a scroll view would lose its
/// auto-scroll past the fold (the categories page records the trap), and
/// the sheet stays content-tall because the list shrink-wraps under the
/// sub-sheet's clamp.
///
/// Loads through `FilterPresetService` rather than a synchronous facade:
/// nothing here renders during someone else's build, so the calendar's
/// lazily-constructed-services rule is satisfied by awaiting the owner. The
/// service keeps its cache, so a reopen costs no query; until it answers the
/// groups render with no preset rows — no spinner in the language.
class FilterPresetSheet extends StatefulWidget {
  /// What the calendar is filtered by right now, so the matching preset can be
  /// marked as the one in use.
  final CalendarGridFilters current;

  const FilterPresetSheet({super.key, required this.current});

  /// The sub-sheet shape: as tall as its content, clamped at the editor's
  /// height, the route's own drag. No guard: nothing here can be lost.
  static Future<CalendarGridFilters?> show(
    BuildContext context, {
    required CalendarGridFilters current,
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
        child: FilterPresetSheet(current: current),
      ),
    );
  }

  @override
  State<FilterPresetSheet> createState() => _FilterPresetSheetState();
}

class _FilterPresetSheetState extends State<FilterPresetSheet> {
  final TextEditingController _search = TextEditingController();

  FilterPresetService? _service;
  List<CalendarFilterPreset> _presets = const [];
  bool _loading = true;

  /// Folded once per keystroke rather than once per row — `describe` builds a
  /// string per preset, so folding inside the filter loop would refold the
  /// query for every row it tests.
  String _query = '';

  /// The body's scroll position feeds the header's hairline (a form sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
    _load();
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  Future<void> _load() async {
    try {
      final service = await FilterPresetService.getInstance();
      if (!mounted) return;
      setState(() {
        _service = service;
        _presets = service.presets;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[FilterPresetSheet] Preset load failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = normalizeForSearch(value));
  }

  /// The field is never autofocused: opening a sheet with the keyboard
  /// already up hides the list it is meant to show. A live query keeps the
  /// row, or the list would be filtered with no field left to clear it.
  bool get _showSearch =>
      _presets.length > AppConstants.listSearchThreshold || _query.isNotEmpty;

  /// Reorder is off while a query is live — the rule every reorderable list
  /// in the app follows: the rows shown are a subset, so a render index no
  /// longer maps to a stored position. The handles grey in place and Move
  /// to top dims; nothing moves.
  bool get _canReorder => _query.isEmpty;

  /// Applies [ordered] optimistically, then persists it — the categories
  /// page's shape. The service serializes its writes, so two quick drags
  /// each hand over their whole current order and the last one is the
  /// truth. Reconciling with the service afterwards, whether the write
  /// succeeded or not, is the feedback: an order that failed to persist
  /// visibly springs back to what is stored.
  Future<void> _persistOrder(List<CalendarFilterPreset> ordered) async {
    final service = _service;
    if (service == null) return;
    setState(() => _presets = ordered);
    try {
      await service.reorder([for (final preset in ordered) preset.id]);
    } catch (e) {
      debugPrint('[FilterPresetSheet] Reorder failed: $e');
    } finally {
      if (mounted) setState(() => _presets = service.presets);
    }
  }

  /// A drop from the list: [oldIndex] and [newIndex] are item indices, the
  /// latter against the list with the dragged row already removed. Only a
  /// preset carries a drag listener, but the list's own accessibility
  /// actions (move to start / end) can name any index, so the row is mapped
  /// into the preset run and a drop outside it is clamped to its ends — a
  /// preset can never land above the search row or below the save row.
  void _onReorder(int oldIndex, int newIndex) {
    if (!_canReorder) return;
    final offset = _showSearch ? 1 : 0;
    final count = _presets.length;
    final from = oldIndex - offset;
    if (from < 0 || from >= count) return;
    final to = (newIndex - offset).clamp(0, count - 1);
    if (from == to) return;
    final ordered = List<CalendarFilterPreset>.from(_presets);
    final moved = ordered.removeAt(from);
    ordered.insert(to, moved);
    _persistOrder(ordered);
  }

  /// One tap for the case a long drag exists to serve: promoting the preset
  /// you have started using most. Dragging row twelve to the top is
  /// miserable at any auto-scroll velocity (the categories page's reasoning).
  Future<void> _moveToTop(CalendarFilterPreset preset) {
    final ordered = List<CalendarFilterPreset>.from(_presets)
      ..removeWhere((p) => p.id == preset.id)
      ..insert(0, preset);
    return _persistOrder(ordered);
  }

  /// The lifted row: the shared proxy (a hair of scale, a shadow) over a
  /// clip. A middle row of the group paints square corners of its own, and
  /// the proxy's rounded shadow would otherwise frame a square card.
  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return reorderDragProxy(
      ClipRRect(
        borderRadius: BorderRadius.circular(reorderProxyRadius),
        child: child,
      ),
      index,
      animation,
    );
  }

  /// Membership by folded substring over the name **and** the description, so
  /// a preset is findable by what it does ("tracked") as well as by what it
  /// was called. Folds through the note search's `normalizeForSearch`, which
  /// is case- and diacritic-insensitive — never `toLowerCase().contains`.
  List<CalendarFilterPreset> _visible(AppLocalizations l10n) {
    if (_query.isEmpty) return _presets;
    return [
      for (final preset in _presets)
        if (normalizeForSearch(preset.name).contains(_query) ||
            normalizeForSearch(
              CalendarFilterSummary.describe(preset.filters, l10n),
            ).contains(_query))
          preset,
    ];
  }

  /// Folded names of every preset **except** [excluding], for the naming
  /// dialog's soft duplicate warning. Renaming a preset must not warn that it
  /// collides with itself.
  Set<String> _otherNames({String? excluding}) {
    return {
      for (final preset in _presets)
        if (preset.id != excluding) normalizeForSearch(preset.name),
    };
  }

  /// Saves the live filter without leaving the sheet — the moment you notice
  /// "the filter I am using is not in this list" is exactly here, and the
  /// other way to save it is three steps away (close, open the filter sheet,
  /// find the bookmark).
  Future<void> _saveCurrent() async {
    final service = _service;
    if (service == null || widget.current.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    if (service.isFull) {
      _report(l10n.filterPresetLimitReached(FilterPresetService.maxPresets));
      return;
    }
    final name = await FilterPresetNameDialog.show(
      context,
      title: l10n.filterPresetSave,
      initialName: CalendarFilterSummary.suggestName(widget.current, l10n),
      existingNames: _otherNames(),
    );
    if (name == null || !mounted) return;
    final saved = await service.create(name: name, filters: widget.current);
    if (!mounted) return;
    if (saved == null) {
      _report(l10n.filterPresetLimitReached(FilterPresetService.maxPresets));
      return;
    }
    // Stays open: the filter is already applied, so there is nothing to pick —
    // the new row appearing, marked in use, is the whole confirmation.
    setState(() => _presets = service.presets);
  }

  Future<void> _rename(CalendarFilterPreset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await FilterPresetNameDialog.show(
      context,
      title: l10n.filterPresetRename,
      initialName: preset.name,
      existingNames: _otherNames(excluding: preset.id),
    );
    if (name == null || !mounted) return;
    await _service?.update(preset.copyWith(name: name));
    if (!mounted) return;
    setState(() => _presets = _service?.presets ?? const []);
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

  /// Re-points a saved preset at whatever the calendar is filtered by now —
  /// the "I tweaked this and want to keep the tweak" path, which otherwise
  /// means deleting and re-saving under the same name.
  Future<void> _updateToCurrent(CalendarFilterPreset preset) async {
    await _service?.update(preset.copyWith(filters: widget.current));
    if (!mounted) return;
    setState(() => _presets = _service?.presets ?? const []);
  }

  Future<void> _delete(CalendarFilterPreset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.filterPresetDelete,
      content: l10n.filterPresetDeleteConfirm(preset.name),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _service?.delete(preset.id);
    if (!mounted) return;
    setState(() => _presets = _service?.presets ?? const []);
  }

  /// The row's ⋮: Rename · Update to current filter · Move to top · Delete, a
  /// popup route in the app's menu anatomy under the row. Focus is dropped
  /// first, or the route's return would hand it back to the search row and
  /// raise the keyboard under the menu's answer.
  Future<void> _openActions(
    BuildContext anchor,
    CalendarFilterPreset preset, {
    required bool inUse,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    // Disabled when it would do nothing (the preset already holds the live
    // filter) **and** when the live filter is empty — the filter sheet's
    // bookmark already rules that an empty set is not a preset, and letting
    // Update turn a working preset into one would be that same rule
    // disagreeing with itself.
    final canUpdate = !inUse && !widget.current.isEmpty;
    // Nothing to promote while the preset already leads, and nothing to
    // promote *into* while a query hides the rows it would pass.
    final canMoveToTop =
        _canReorder && _presets.isNotEmpty && _presets.first.id != preset.id;
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await showMenu<_PresetAction>(
      context: anchor,
      positionBuilder: (_, constraints) => formMenuPosition(
        anchor,
        constraints,
        menuHeight: formMenuHeight(_PresetAction.values.length),
      ),
      color: colorScheme.menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
      ),
      menuPadding: FormMetrics.menuPadding,
      // The header menus' floor and cap: "Auf aktuellen Filter
      // aktualisieren" does not fit the floor.
      constraints: const BoxConstraints(
        minWidth: AppTheme.menuWidth,
        maxWidth: AppTheme.menuMaxWidth,
      ),
      items: [
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.rename,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.filterPresetRename,
            icon: Icons.drive_file_rename_outline_rounded,
            label: l10n.filterPresetRename,
          ),
        ),
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.update,
          height: FormMetrics.menuRowHeight,
          enabled: canUpdate,
          child: FormMenuItemRow(
            identifier: SemanticsIds.filterPresetUpdate,
            icon: Icons.sync_rounded,
            label: l10n.filterPresetUpdate,
            enabled: canUpdate,
          ),
        ),
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.moveToTop,
          height: FormMetrics.menuRowHeight,
          enabled: canMoveToTop,
          child: FormMenuItemRow(
            identifier: SemanticsIds.filterPresetMoveToTop,
            icon: Icons.vertical_align_top_rounded,
            label: l10n.moveToTop,
            enabled: canMoveToTop,
          ),
        ),
        PopupMenuItem<_PresetAction>(
          value: _PresetAction.delete,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.filterPresetDelete,
            icon: Icons.delete_outline_rounded,
            label: l10n.delete,
            color: colorScheme.error,
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PresetAction.rename:
        await _rename(preset);
      case _PresetAction.update:
        await _updateToCurrent(preset);
      case _PresetAction.moveToTop:
        await _moveToTop(preset);
      case _PresetAction.delete:
        await _delete(preset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = widget.current;
    final visible = _visible(l10n);
    final canReorder = _canReorder;
    // Disabled, never hidden: while there is nothing to save that is not
    // already saved — the two conditions the filter sheet's bookmark enforces
    // — and while a query is live, when a query is a find and an action row
    // among its results is noise. Hiding it would move the results under the
    // finger.
    final canSave =
        !_loading &&
        _query.isEmpty &&
        !current.isEmpty &&
        _service?.matching(current) == null;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the clearance rule every calendar
    // sheet follows (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    // One list holds the search row, the presets and the save row. The rows
    // that cannot be lifted carry no drag listener, and a drop is clamped
    // into the preset run, so a drag can never leave the group it started in
    // — the browser's one-sliver rule.
    final items = <_Item>[
      if (_showSearch) const _SearchItem(),
      for (final preset in visible) _PresetItem(preset),
      const _SaveItem(),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.filterPresetClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.filterPresetsTitle,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // A pick-on-tap list confirms nothing.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: ReorderableListView.builder(
            scrollController: _bodyScroll,
            // Content-tall under the sheet's clamp, and still the one
            // Scrollable — which is what lets a drag past the fold scroll it.
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            // The most common answer to "which lens am I using" is *none*,
            // and this row is what lets the sheet give it: it is the one row
            // that is never a saved filter, so it stands in its own group
            // above the list.
            //
            // `cleared()`, never `CalendarGridFilters.none`: `panelShowsAll`
            // is a preference about the day panel, not something being
            // hidden, and the filter sheet's Reset keeps it for the same
            // reason.
            header: FormRowGroup(
              children: [
                FormCheckRow(
                  exclusive: true,
                  label: l10n.filterPresetNone,
                  checked: current.isEmpty,
                  identifier: SemanticsIds.filterPresetNone,
                  onChanged: (_) =>
                      Navigator.of(context).pop(current.cleared()),
                ),
              ],
            ),
            footer: visible.isEmpty && _query.isNotEmpty
                ? FormCaption(
                    text: l10n.filterPresetNoMatches,
                    padding: FormMetrics.groupCaptionPadding,
                  )
                : null,
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItem(
              items,
              index,
              l10n,
              current: current,
              canReorder: canReorder,
              canSave: canSave,
            ),
            // An open keyboard halves the sheet, which halves the drag
            // region; a query cannot be live during a drag, but focus with
            // an empty field can.
            onReorderStart: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onReorderItem: _onReorder,
            proxyDecorator: _liftedRow,
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    List<_Item> items,
    int index,
    AppLocalizations l10n, {
    required CalendarGridFilters current,
    required bool canReorder,
    required bool canSave,
  }) {
    final item = items[index];
    final Widget row = switch (item) {
      _SearchItem() => FormSearchRow(
        controller: _search,
        hint: l10n.filterPresetSearchHint,
        clearTooltip: l10n.upcomingClearSearch,
        identifier: SemanticsIds.filterPresetSearch,
        onChanged: _onQueryChanged,
      ),
      _PresetItem(:final preset) => _PresetRow(
        preset: preset,
        index: index,
        canReorder: canReorder,
        // Value equality on the filters, not the id: what makes a preset
        // "the one in use" is that the calendar is showing exactly what it
        // saves.
        inUse: preset.filters == current,
        caption: CalendarFilterSummary.describe(preset.filters, l10n),
        reorderLabel: l10n.filterPresetReorder,
        actionsTooltip: l10n.filterPresetActions,
        onPick: () => Navigator.of(context).pop(preset.filters),
        onActions: (anchor, inUse) => _openActions(anchor, preset, inUse: inUse),
      ),
      _SaveItem() => FormActionRow(
        glyph: Icons.bookmark_add_outlined,
        label: l10n.filterPresetSaveCurrent,
        identifier: SemanticsIds.filterPresetSave,
        onTap: canSave ? _saveCurrent : null,
      ),
    };
    final shell = FormRowShell(
      first: index == 0,
      last: index == items.length - 1,
      trailingGap: false,
      child: row,
    );
    // Only a preset can be lifted — by its handle, or by a long press
    // anywhere on it (the categories page's pair) — and only while the list
    // is not filtered.
    if (item case _PresetItem()) {
      return ReorderableDelayedDragStartListener(
        key: item.key,
        index: index,
        enabled: canReorder,
        child: shell,
      );
    }
    return KeyedSubtree(key: item.key, child: shell);
  }
}

enum _PresetAction { rename, update, moveToTop, delete }

/// One entry of the sheet's reorderable list. The search row and the save
/// row are items of the same list as the presets so the run draws as one
/// group; they carry no drag listener and never move.
sealed class _Item {
  const _Item();

  Key get key;
}

class _SearchItem extends _Item {
  const _SearchItem();

  @override
  Key get key => const _FixedRowKey('search');
}

class _PresetItem extends _Item {
  final CalendarFilterPreset preset;

  const _PresetItem(this.preset);

  @override
  Key get key => ValueKey(preset.id);
}

class _SaveItem extends _Item {
  const _SaveItem();

  @override
  Key get key => const _FixedRowKey('save');
}

/// The key of a row that is not a preset — its own type, so a preset whose
/// id happened to read "search" or "save" (a hand-edited backup) could never
/// collide with it: a `ValueKey` compares its runtime type as well.
class _FixedRowKey extends ValueKey<String> {
  const _FixedRowKey(super.value);
}

/// One preset as a two-line radio row — the name over what it filters, the
/// check while it is the filter in use — with its drag handle at the start
/// and its ⋮ at the end as the row's second and third targets. A
/// `FormDividedRow` of its own rather than a `Builder` around the check row,
/// so the shell draws the hairline at the handle's column and the ⋮ has the
/// row's own context to anchor its menu under.
class _PresetRow extends FormDividedRow {
  final CalendarFilterPreset preset;

  /// The row's index in the enclosing reorderable list, which the handle
  /// hands to the list when it is dragged.
  final int index;

  /// False while a query is live: the handle greys in place and drags
  /// nothing.
  final bool canReorder;
  final bool inUse;
  final String caption;
  final String reorderLabel;
  final String actionsTooltip;
  final VoidCallback onPick;
  final void Function(BuildContext anchor, bool inUse) onActions;

  const _PresetRow({
    required this.preset,
    required this.index,
    required this.canReorder,
    required this.inUse,
    required this.caption,
    required this.reorderLabel,
    required this.actionsTooltip,
    required this.onPick,
    required this.onActions,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    return FormCheckRow(
      exclusive: true,
      handle: FormDragHandle(
        index: index,
        enabled: canReorder,
        label: reorderLabel,
        identifier: SemanticsIds.filterPresetHandle(preset.id),
      ),
      label: preset.name,
      caption: caption,
      checked: inUse,
      identifier: SemanticsIds.filterPresetRow(preset.id),
      onChanged: (_) => onPick(),
      trailingButton: FormTrailingButton(
        icon: Icons.more_vert_rounded,
        tooltip: actionsTooltip,
        identifier: SemanticsIds.filterPresetOptions(preset.id),
        onPressed: () => onActions(context, inUse),
      ),
    );
  }
}

/// Names a preset — used when saving a new one and when renaming an existing
/// one, so the two can never disagree about what a legal name is.
///
/// Returns the trimmed name, or `null` on cancel. Save is disabled on an empty
/// field: a nameless preset is unfindable in a list whose whole point is being
/// searched.
abstract final class FilterPresetNameDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String initialName,
    Set<String> existingNames = const {},
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        title: title,
        initialName: initialName,
        existingNames: existingNames,
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String initialName;

  /// Folded names already in use, for the soft duplicate warning. Never a
  /// constraint — see [_NameDialogState.build].
  final Set<String> existingNames;

  const _NameDialog({
    required this.title,
    required this.initialName,
    required this.existingNames,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void initState() {
    super.initState();
    // Opens with the suggestion selected, so typing replaces it and Save
    // keeps it — the suggestion is a starting point, never something to
    // delete first.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      // Rebuilt on every keystroke so both the warning and Save's enabled
      // state follow the field. Cheap: one set probe over at most 50 folded
      // names.
      content: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final trimmed = _controller.text.trim();
          // **Soft, and never blocks Save** — the category editor's rule,
          // shared deliberately: presets are keyed by id, so a duplicate name
          // is confusing rather than corrupting, and blocking would break
          // "rename A, then reuse A's old name".
          final duplicate =
              trimmed.isNotEmpty &&
              widget.existingNames.contains(normalizeForSearch(trimmed));
          return TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: l10n.filterPresetName,
              border: const OutlineInputBorder(),
              errorText: duplicate ? l10n.categoryNameExists(trimmed) : null,
              // An `errorText` that does not block submission would otherwise
              // paint the field red; this keeps it a remark.
              errorStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              errorBorder: const OutlineInputBorder(),
              focusedErrorBorder: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: _controller.text.trim().isEmpty ? null : _submit,
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}
