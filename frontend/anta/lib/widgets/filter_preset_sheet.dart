import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_filter_preset.dart';
import '../models/calendar_grid_filters.dart';
import '../services/filter_preset_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/calendar_filter_summary.dart';
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

  Future<void> _rename(CalendarFilterPreset preset) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await FilterPresetNameDialog.show(
      context,
      title: l10n.filterPresetRename,
      initialName: preset.name,
    );
    if (name == null || !mounted) return;
    await _service?.update(preset.copyWith(name: name));
    if (!mounted) return;
    setState(() => _presets = _service?.presets ?? const []);
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            l10n.filterPresetsTitle,
            style: theme.textTheme.titleMedium,
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
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _presets.isEmpty
              ? _EmptyState(message: l10n.filterPresetEmpty)
              : visible.isEmpty
              ? _EmptyState(message: l10n.filterPresetNoMatches)
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + bottomClearance),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final preset = visible[index];
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
                      onUpdate: inUse ? null : () => _updateToCurrent(preset),
                      onDelete: () => _delete(preset),
                    );
                  },
                ),
        ),
      ],
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
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: title, initialName: initialName),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String initialName;

  const _NameDialog({required this.title, required this.initialName});

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
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        maxLength: 60,
        decoration: InputDecoration(
          labelText: l10n.filterPresetName,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
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
