import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_filter_preset.dart';
import '../models/calendar_grid_filters.dart';
import '../services/filter_preset_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/calendar_filter_summary.dart';
import '../utils/custom_snackbar.dart';
import 'app_dialogs.dart';

/// Bottom-sheet listing the user's saved filters, with a search field.
///
/// Returns the [CalendarGridFilters] to apply, or `null` when dismissed —
/// renames and deletes happen in place and never pop, so the sheet stays open
/// while you tidy the list and only closes when you actually pick something.
///
/// Loads through `FilterPresetService` rather than a synchronous facade:
/// nothing here renders during someone else's build, so the calendar's
/// lazily-constructed-services rule is satisfied by awaiting the owner. The
/// service keeps its cache, so a reopen costs no query.
class FilterPresetSheet extends StatefulWidget {
  /// What the calendar is filtered by right now, so the matching preset can be
  /// marked as the one in use.
  final CalendarGridFilters current;

  const FilterPresetSheet({super.key, required this.current});

  static Future<CalendarGridFilters?> show(
    BuildContext context, {
    required CalendarGridFilters current,
  }) {
    return showModalBottomSheet<CalendarGridFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.75,
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  void _report(String message) {
    if (!mounted) return;
    CustomSnackbar.show(context, message);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final visible = _visible(l10n);
    // Offered only when there is something to save that is not already saved,
    // so the row never duplicates an existing preset and never saves a no-op —
    // the same two conditions the filter sheet's bookmark enforces. Hidden
    // while searching: a query is a find, and an action row among its results
    // is noise.
    final showSaveRow =
        !_loading &&
        _query.isEmpty &&
        !widget.current.isEmpty &&
        _service?.matching(widget.current) == null;
    // `useSafeArea: true` has proven unreliable against the bottom
    // gesture/nav bar on real devices, so the list pads by the larger of the
    // keyboard inset and the system inset — the same fix every sibling
    // calendar sheet uses.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.filterPresetsTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              // The most common answer to "which lens am I using" is *none*,
              // and until this button it was the one answer the sheet could
              // not give: clearing meant closing, opening the filter sheet,
              // Reset, Apply. It lives in the header rather than as a list row
              // so the list keeps meaning "things you saved", mirroring the
              // filter sheet's own title + Reset.
              //
              // Labelled "Show everything" rather than "Clear" or "Reset" on
              // purpose: in a sheet full of saved filters, either of those
              // reads as an offer to delete them.
              TextButton(
                // Disabled rather than hidden, so the header cannot change
                // height between two openings of the same sheet.
                onPressed: widget.current.isEmpty
                    ? null
                    // `cleared()`, never `CalendarGridFilters.none`:
                    // `panelShowsAll` is a preference about the day panel, not
                    // something being hidden, and the filter sheet's Reset
                    // keeps it for the same reason.
                    : () => Navigator.of(context).pop(widget.current.cleared()),
                child: Text(l10n.calendarFilterShowAll),
              ),
            ],
          ),
        ),
        // The field is the point of this sheet, so it is always present once
        // there is anything to search — but **never autofocused**: opening a
        // sheet with the keyboard already up hides the list it is meant to
        // show, the rule every other searchable sheet here follows.
        if (_presets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                hintText: l10n.filterPresetSearchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.upcomingClearSearch,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          _onQueryChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
            ),
          ),
        Expanded(
          // The save row keeps the list alive on its own: with no presets yet
          // and a filter applied, the row **is** the content, and falling
          // through to the empty state would hide the one action that state is
          // asking for.
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty && !showSaveRow
              ? _EmptyState(
                  message: _presets.isEmpty
                      ? l10n.filterPresetEmpty
                      : l10n.filterPresetNoMatches,
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + bottomClearance),
                  itemCount: visible.length + (showSaveRow ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (showSaveRow && index == 0) {
                      return _SaveCurrentTile(
                        subtitle: CalendarFilterSummary.describe(
                          widget.current,
                          l10n,
                        ),
                        onTap: _saveCurrent,
                      );
                    }
                    final preset = visible[index - (showSaveRow ? 1 : 0)];
                    // Value equality on the filters, not the id: what makes a
                    // preset "the one in use" is that the calendar is showing
                    // exactly what it saves.
                    final inUse = preset.filters == widget.current;
                    return _PresetTile(
                      preset: preset,
                      inUse: inUse,
                      subtitle: CalendarFilterSummary.describe(
                        preset.filters,
                        l10n,
                      ),
                      onApply: () =>
                          Navigator.of(context).pop(preset.filters),
                      onRename: () => _rename(preset),
                      // Disabled when it would do nothing (the preset already
                      // holds the live filter) **and** when the live filter is
                      // empty — the filter sheet's bookmark already rules that
                      // an empty set is not a preset, and letting Update turn
                      // a working preset into one would be that same rule
                      // disagreeing with itself.
                      onUpdate: inUse || widget.current.isEmpty
                          ? null
                          : () => _updateToCurrent(preset),
                      onDelete: () => _delete(preset),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The "save what is applied right now" row, first in the list.
///
/// A row rather than a floating action or a header button: it is offered only
/// in the state where it means something, and the list is where the user is
/// already looking when they notice their filter is missing from it.
class _SaveCurrentTile extends StatelessWidget {
  final String subtitle;
  final VoidCallback onTap;

  const _SaveCurrentTile({required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        child: const Icon(Icons.bookmark_add_outlined, size: 20),
      ),
      title: Text(l10n.filterPresetSaveCurrent),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      onTap: onTap,
    );
  }
}

class _PresetTile extends StatelessWidget {
  final CalendarFilterPreset preset;
  final bool inUse;
  final String subtitle;
  final VoidCallback onApply;
  final VoidCallback onRename;

  /// `null` while the preset already holds the current filters — there would
  /// be nothing to update it to.
  final VoidCallback? onUpdate;
  final VoidCallback onDelete;

  const _PresetTile({
    required this.preset,
    required this.inUse,
    required this.subtitle,
    required this.onApply,
    required this.onRename,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: inUse
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        foregroundColor: inUse
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
        child: Icon(
          inUse ? Icons.check_rounded : Icons.bookmark_rounded,
          size: 20,
        ),
      ),
      title: Text(
        preset.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: inUse
            ? theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.primary,
              )
            : null,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      onTap: onApply,
      trailing: PopupMenuButton<_PresetAction>(
        tooltip: l10n.filterPresetActions,
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) {
          switch (action) {
            case _PresetAction.rename:
              onRename();
            case _PresetAction.update:
              onUpdate?.call();
            case _PresetAction.delete:
              onDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_PresetAction>(
            value: _PresetAction.rename,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(l10n.filterPresetRename),
            ),
          ),
          PopupMenuItem<_PresetAction>(
            value: _PresetAction.update,
            enabled: onUpdate != null,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_rounded),
              title: Text(l10n.filterPresetUpdate),
            ),
          ),
          PopupMenuItem<_PresetAction>(
            value: _PresetAction.delete,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded, color: colors.error),
              title: Text(
                l10n.delete,
                style: TextStyle(color: colors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PresetAction { rename, update, delete }

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
