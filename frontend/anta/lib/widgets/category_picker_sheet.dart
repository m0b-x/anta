import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../utils/category_search.dart';
import '../utils/settings_search.dart';
import 'category_editor_sheet.dart';
import 'settings_search_field.dart';

/// How many categories a single [CategoryPickerSheet] pass may return.
enum CategoryPickerMode { single, multi }

/// Bottom-sheet selector for event categories, in the two arities
/// `CalendarDatePickerSheet` established: [pickSingle] returns one id, and
/// [pickMulti] edits a whole set in one pass.
///
/// Rows come from `CalendarCategories.visiblePlus(initialSelection)` — the
/// archive flag hides a category from every choosing surface, but a selection
/// that already carries a hidden id must still list it or the user cannot
/// un-select what they can no longer see. The *opening* selection, not the
/// live one, so a row cannot vanish the moment it is un-ticked.
///
/// Search runs on the shared `rankCategories`, so this sheet and the
/// management page can never answer the same query differently. There is
/// deliberately **no autofocus**: the sheet's job is picking, and raising the
/// keyboard on every open pushes the list up and costs a tap to dismiss.
class CategoryPickerSheet extends StatefulWidget {
  final CategoryPickerMode mode;

  /// Ids selected when the sheet opens. Single mode uses it only to mark the
  /// current row and to keep a hidden category listed.
  final Set<String> initialSelection;

  const CategoryPickerSheet({
    super.key,
    required this.mode,
    required this.initialSelection,
  });

  /// Picks one category. Returns its id, or `null` when dismissed.
  static Future<String?> pickSingle(
    BuildContext context, {
    required String selectedId,
  }) async {
    final picked = await _show(
      context,
      mode: CategoryPickerMode.single,
      initialSelection: {selectedId},
    );
    if (picked == null || picked.isEmpty) return null;
    return picked.first;
  }

  /// Edits a whole set of categories in one pass. Returns `null` when
  /// dismissed.
  ///
  /// Like its date twin this is **semantics-free** — a set goes in, a set
  /// comes out — so it serves the agenda's allowlist and the calendar
  /// filter's denylist without knowing which it is; the caller inverts.
  /// **Unlike `CalendarDatePickerSheet.pickMulti` an empty result is not
  /// collapsed to `null`**: empty is a real, meaningful state on both sides
  /// here (no allowlist, nothing hidden), and swallowing it would make
  /// clearing the last category look like a dismissal.
  static Future<Set<String>?> pickMulti(
    BuildContext context, {
    required Set<String> selected,
  }) {
    return _show(
      context,
      mode: CategoryPickerMode.multi,
      initialSelection: selected,
    );
  }

  static Future<Set<String>?> _show(
    BuildContext context, {
    required CategoryPickerMode mode,
    required Set<String> initialSelection,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        // Raised from 0.7 now that a search field sits above the rows.
        heightFactor: 0.85,
        child: CategoryPickerSheet(
          mode: mode,
          initialSelection: initialSelection,
        ),
      ),
    );
  }

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  late final Set<String> _selected = {...widget.initialSelection};

  SettingsQuery _query = SettingsQuery.empty;

  bool get _isMulti => widget.mode == CategoryPickerMode.multi;
  bool get _isFiltering => _query.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    setState(() => _query = SettingsQuery.parse(raw));
  }

  void _clearQuery() {
    _searchController.clear();
    _onQueryChanged('');
  }

  void _onTapCategory(CalendarCategory category) {
    if (!_isMulti) {
      Navigator.of(context).pop({category.id});
      return;
    }
    setState(() {
      if (!_selected.remove(category.id)) _selected.add(category.id);
    });
  }

  /// Creates a category without leaving the sheet. In single mode the new
  /// category is the answer, so the sheet returns it; in multi mode it joins
  /// the selection and the list stays open.
  Future<void> _createCategory({String? initialName}) async {
    final created = await CategoryEditorSheet.show(
      context,
      initialName: initialName,
    );
    if (created == null || !mounted) return;
    if (!_isMulti) {
      Navigator.of(context).pop({created.id});
      return;
    }
    _searchController.clear();
    setState(() {
      _selected.add(created.id);
      _query = SettingsQuery.empty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Read on every build so a database switch (which clears the facade)
    // cannot leave a stale list here, and so a category created from this
    // sheet appears the moment the facade republishes.
    //
    // The kept set is the selection the sheet **opened with**, not the live
    // one: an archived category is listed because the selection carries it,
    // and de-selecting it mid-pass must not delete the row out from under the
    // finger that just un-ticked it — leaving the user unable to change their
    // mind, and shrinking the offered set (and with it the search field's
    // threshold) mid-interaction. Invariant 8 is "visible plus its own
    // selected ids"; for a sheet that edits a selection, those are the ids it
    // was handed.
    final categories = CalendarCategories.visiblePlus(widget.initialSelection);
    final rows = _isFiltering
        ? [
            for (final ranked in rankCategories(_query, categories, l10n))
              ranked.category,
          ]
        : categories;
    // Short lists carry no search chrome; the threshold trips on its own as
    // the set grows. `_isFiltering` holds the field open once it is in use,
    // the same rule the management page follows: a list that is filtered with
    // no field left to clear it is stranded, and the two searchable category
    // surfaces must not disagree about when the field is there.
    final showSearch =
        _isFiltering || categories.length > AppConstants.listSearchThreshold;
    // `useSafeArea: true` on the modal route avoids the status bar but has
    // proven unreliable against the bottom gesture/nav bar on real devices
    // (the last row rendered under it) — same fix as `EventEditorSheet` /
    // `CategoryEditorSheet`: pad by the larger of the keyboard inset and the
    // system's bottom inset.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              // Balances the trailing button so the title stays centred.
              const SizedBox(width: 48),
              Expanded(
                child: Text(
                  _isMulti ? l10n.calendarCategories : l10n.eventType,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              // The same affordance the management page's app bar carries, so
              // the two surfaces read as one system.
              IconButton.filledTonal(
                onPressed: _createCategory,
                icon: const Icon(Icons.add_rounded),
                tooltip: l10n.createCategory,
              ),
            ],
          ),
        ),
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SettingsSearchField(
              controller: _searchController,
              hint: l10n.searchCategories,
              onChanged: _onQueryChanged,
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    4,
                    8,
                    4 + (_isMulti ? 0 : bottomClearance),
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final category = rows[index];
                    return _CategoryPickerRow(
                      category: category,
                      selected: _selected.contains(category.id),
                      multi: _isMulti,
                      onTap: () => _onTapCategory(category),
                    );
                  },
                ),
        ),
        if (_isMulti)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomClearance),
            child: FilledButton(
              // Pops the set as-is, empty included — see [pickMulti].
              onPressed: () => Navigator.of(context).pop({..._selected}),
              child: Text(l10n.apply),
            ),
          ),
      ],
    );
  }

  /// Nothing matched. The typed text is almost certainly the name the user
  /// wants, so the action is to create it rather than to start over.
  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final typed = _searchController.text.trim();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noCategoriesMatch,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () =>
                _createCategory(initialName: typed.isEmpty ? null : typed),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              typed.isEmpty
                  ? l10n.createCategory
                  : l10n.createCategoryNamed(typed),
            ),
          ),
          if (_isFiltering)
            TextButton(onPressed: _clearQuery, child: Text(l10n.clearSearch)),
        ],
      ),
    );
  }
}

/// The bounded stand-in for a per-category chip `Wrap`, shared by the two
/// filter sheets so they cannot describe a selection differently.
///
/// One row naming what is included — *All categories*, or the first names
/// plus *+N more* — opening [CategoryPickerSheet.pickMulti]. It is the
/// pattern the agenda panel's own `Categories (3)` chip already follows: a
/// wall of chips over the whole set is what breaks at forty categories, and
/// re-adding a chip row for the *selection* beneath this tile would rebuild
/// exactly the wall it removes.
class CategoryFilterTile extends StatelessWidget {
  /// The included categories, in display order. Empty means the filter
  /// currently excludes every one of them.
  final List<CalendarCategory> selected;

  /// Whether [selected] covers the whole offered set — an allowlist that is
  /// empty by convention says this too.
  final bool selectsAll;

  final VoidCallback onTap;

  /// How many names the subtitle spells out before folding the rest into
  /// *+N more*. Two keeps it to one line at typical name lengths.
  static const int namedLimit = 2;

  const CategoryFilterTile({
    super.key,
    required this.selected,
    required this.selectsAll,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.category_rounded),
        title: Text(l10n.calendarCategories),
        subtitle: Text(_subtitle(l10n), maxLines: 2),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  String _subtitle(AppLocalizations l10n) {
    if (selectsAll) return l10n.categoriesAllSelected;
    if (selected.isEmpty) return l10n.categoriesNSelected(0);
    final names = [
      for (final category in selected.take(namedLimit))
        CalendarCategories.labelOf(category, l10n),
    ];
    final rest = selected.length - names.length;
    return [
      names.join(', '),
      if (rest > 0) l10n.categoriesMore(rest),
    ].join(' ');
  }
}

/// One picker row. A widget rather than a method so a keystroke in the search
/// field rebuilds the list without rebuilding every row's subtree wholesale.
class _CategoryPickerRow extends StatelessWidget {
  final CalendarCategory category;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  const _CategoryPickerRow({
    required this.category,
    required this.selected,
    required this.multi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: category.color.withValues(alpha: 0.18),
        foregroundColor: category.color,
        child: Icon(
          CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded,
        ),
      ),
      title: Text(CalendarCategories.labelOf(category, l10n)),
      // A hidden category only reaches this list by already being selected;
      // say so, or it reads as an ordinary row the user forgot about.
      subtitle: category.isHidden ? Text(l10n.categoryHidden) : null,
      trailing: multi
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : (selected
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null),
      selected: selected,
      onTap: onTap,
    );
  }
}
