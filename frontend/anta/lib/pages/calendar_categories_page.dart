import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/calendar_event_service.dart';
import '../services/category_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/category_search.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/category_editor_sheet.dart';
import '../widgets/settings_reorder.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/unified_app_bars.dart';

/// One entry of the per-row "category options" menu.
enum _CategoryAction { moveToTop, toggleHidden, edit, delete }

/// Management page for event categories. Lists every category — hidden ones
/// included, dimmed — and lets the user search, reorder, hide, edit, create
/// and delete them.
///
/// Mutations go directly through [CategoryService] (the same service-direct
/// pattern the holiday settings and the vocabularies page use); the in-memory
/// [CalendarCategories] cache is updated by the service, so the calendar
/// reflects changes once the user returns to it. Actions key on **ids**, never
/// on render positions, so a filtered view needs no index bookkeeping — the
/// one positional surface is the reorder callback, which maps its render index
/// to the id list before it leaves the widget.
class CalendarCategoriesPage extends StatefulWidget {
  const CalendarCategoriesPage({super.key});

  @override
  State<CalendarCategoriesPage> createState() => _CalendarCategoriesPageState();
}

class _CalendarCategoriesPageState extends State<CalendarCategoriesPage> {
  final TextEditingController _searchController = TextEditingController();

  CategoryService? _service;
  CalendarEventService? _eventService;

  /// The local display order. While a drag is being persisted this leads the
  /// service's own list, which is the whole point of the optimistic update —
  /// and the reason an empty query renders it **directly** rather than through
  /// [rankCategories], which sorts same-band rows on `sortOrder` and never on
  /// input order (a deliberate, tested property of that function), so the
  /// pre-drag values it still sees would snap the dragged row back.
  List<CalendarCategory> _categories = const [];

  /// Advisory event counts, loaded once per page entry and after a delete.
  /// Never live state — one `GROUP BY` for the whole page, never a count per
  /// row.
  Map<String, int> _counts = const {};

  SettingsQuery _query = SettingsQuery.empty;
  bool _isLoading = true;

  bool get _isFiltering => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Independent resolves, so start both before awaiting either. Reaching
    // this page means the calendar has already been open, so the event
    // service is a warm singleton and its `getInstance()` costs nothing.
    final categoryFuture = CategoryService.getInstance();
    final eventFuture = CalendarEventService.getInstance();
    final service = await categoryFuture;
    final eventService = await eventFuture;
    final counts = await eventService.countByCategory();
    if (!mounted) return;
    setState(() {
      _service = service;
      _eventService = eventService;
      _categories = service.categories;
      _counts = counts;
      _isLoading = false;
    });
  }

  void _refresh() {
    final service = _service;
    if (service == null) return;
    setState(() => _categories = service.categories);
  }

  Future<void> _refreshCounts() async {
    final eventService = _eventService;
    if (eventService == null) return;
    final counts = await eventService.countByCategory();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  // ── Search ───────────────────────────────────────────────────────────

  void _onQueryChanged(String raw) {
    setState(() => _query = SettingsQuery.parse(raw));
  }

  void _clearQuery() {
    _searchController.clear();
    _onQueryChanged('');
  }

  // ── Mutations ────────────────────────────────────────────────────────

  /// Runs [write] and reconciles with the service afterwards, whether it
  /// succeeded or not.
  ///
  /// Every mutation here is fired from a menu callback and never awaited, so
  /// an escaping error would surface as an unhandled async error rather than
  /// anything the user can act on. Reconciling on failure is the feedback: an
  /// optimistic order or a flipped visibility icon visibly springs back to
  /// what is actually stored.
  Future<bool> _guarded(Future<void> Function() write) async {
    try {
      await write();
      return true;
    } catch (e) {
      debugPrint('[CalendarCategoriesPage] Write failed: $e');
      return false;
    } finally {
      if (mounted) _refresh();
    }
  }

  Future<void> _create() async {
    final created = await CategoryEditorSheet.show(context);
    if (created == null || !mounted) return;
    _refresh();
  }

  Future<void> _edit(CalendarCategory category) async {
    final updated = await CategoryEditorSheet.show(context, initial: category);
    if (updated == null || !mounted) return;
    _refresh();
  }

  Future<void> _setHidden(CalendarCategory category, bool hidden) {
    return _guarded(() => _service!.setHidden(category.id, hidden));
  }

  Future<void> _delete(CalendarCategory category) async {
    final l10n = AppLocalizations.of(context)!;
    final count = _counts[category.id] ?? 0;
    // A nonzero count makes the consequence concrete — and earns the sentence
    // pointing at hiding, which keeps the events in their own colour instead
    // of repainting that whole history grey.
    final content = count > 0
        ? '${l10n.deleteCategoryConfirmWithEvents(count, category.name)}'
              '\n\n${l10n.deleteCategoryHideHint}'
        : l10n.deleteCategoryConfirm(category.name);
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteCategory,
      content: content,
      confirmText: l10n.delete,
      icon: Icons.delete_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final deleted = await _guarded(() => _service!.deleteCategory(category.id));
    if (!mounted || !deleted) return;
    await _refreshCounts();
    if (!mounted) return;
    CustomSnackbar.showSuccess(context, l10n.categoryDeleted);
  }

  // ── Order ────────────────────────────────────────────────────────────

  /// Applies [ordered] optimistically, then persists it.
  ///
  /// [CategoryService.reorder] already serializes its writes onto a chain, so
  /// this must not build a second one — it just hands over its *current* full
  /// local order, which is what makes the last write the whole truth however
  /// the futures land.
  Future<void> _persistOrder(List<CalendarCategory> ordered) {
    setState(() => _categories = ordered);
    return _guarded(
      () => _service!.reorder([for (final c in ordered) c.id]),
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) {
    final ordered = List<CalendarCategory>.from(_categories);
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    return _persistOrder(ordered);
  }

  /// One tap for the case a long drag exists to serve: promoting a category
  /// you have started using a lot. Dragging row forty to the top is miserable
  /// at any auto-scroll velocity.
  Future<void> _moveToTop(CalendarCategory category) {
    final ordered = List<CalendarCategory>.from(_categories)
      ..removeWhere((c) => c.id == category.id)
      ..insert(0, category);
    return _persistOrder(ordered);
  }

  /// The escape hatch for anyone who reaches forty categories before caring
  /// about a manual order. Sorted on the same fold the search uses, so the
  /// result reads alphabetically in the user's own locale.
  Future<void> _sortAlphabetically() {
    final l10n = AppLocalizations.of(context)!;
    final folded = {
      for (final c in _categories)
        c.id: normalizeForSearch(CalendarCategories.labelOf(c, l10n)),
    };
    final ordered = List<CalendarCategory>.from(_categories)
      ..sort((a, b) {
        final byLabel = folded[a.id]!.compareTo(folded[b.id]!);
        return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
      });
    return _persistOrder(ordered);
  }

  void _onCategoryAction(_CategoryAction action, CalendarCategory category) {
    switch (action) {
      case _CategoryAction.moveToTop:
        _moveToTop(category);
      case _CategoryAction.toggleHidden:
        _setHidden(category, !category.isHidden);
      case _CategoryAction.edit:
        _edit(category);
      case _CategoryAction.delete:
        _delete(category);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SettingsAppBar(
        title: l10n.calendarCategories,
        showMenuButton: false,
        actions: [
          // A filled *icon* button rather than a labelled one: the localized
          // page title plus a text action overflows the bar. The bar is
          // pinned, so unlike the FAB this never scrolls away.
          IconButton.filledTonal(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n.createCategory,
          ),
          PopupMenuButton<void>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (ctx) => [
              PopupMenuItem<void>(
                onTap: _sortAlphabetically,
                child: Row(
                  children: [
                    const Icon(Icons.sort_by_alpha_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.sortCategoriesAlphabetically),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Short lists carry no search chrome; the threshold trips on its own as
    // the set grows.
    final showSearch = _categories.length > AppConstants.listSearchThreshold;
    final rows = _isFiltering
        ? [
            for (final ranked in rankCategories(_query, _categories, l10n))
              ranked.category,
          ]
        : _categories;

    return Column(
      children: [
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SettingsSearchField(
              controller: _searchController,
              hint: l10n.searchCategories,
              onChanged: _onQueryChanged,
            ),
          ),
        if (showSearch && _isFiltering) const ReorderLockedHint(),
        // The list owns the nearest enclosing `Scrollable`, which is what
        // binds `ReorderableListView`'s edge auto-scroller to the thing that
        // actually scrolls. Nesting it in an outer scroll view with
        // `shrinkWrap: true` silently kills dragging past the fold.
        Expanded(
          child: _isFiltering
              ? (rows.isEmpty
                    ? _buildNoMatchesState(context)
                    : _buildFilteredList(rows))
              : _buildReorderableList(rows),
        ),
      ],
    );
  }

  Widget _buildFilteredList(List<CalendarCategory> rows) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: rows.length,
      itemBuilder: (context, index) => _rowFor(rows[index], dragIndex: null),
    );
  }

  Widget _buildReorderableList(List<CalendarCategory> rows) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      // An open keyboard halves the viewport, which halves the usable drag
      // region. A query cannot be active during a drag (reorder is off while
      // filtering), but focus with an empty field can.
      onReorderStart: (_) => FocusScope.of(context).unfocus(),
      onReorderItem: _reorder,
      proxyDecorator: reorderDragProxy,
      itemBuilder: (context, index) => ReorderableDelayedDragStartListener(
        key: ValueKey(rows[index].id),
        index: index,
        child: _rowFor(rows[index], dragIndex: index),
      ),
    );
  }

  Widget _rowFor(CalendarCategory category, {required int? dragIndex}) {
    final row = _CategoryRow(
      category: category,
      eventCount: _counts[category.id] ?? 0,
      dragIndex: dragIndex,
      onToggleHidden: () => _setHidden(category, !category.isHidden),
      onAction: (action) => _onCategoryAction(action, category),
      onTap: () => _edit(category),
    );
    // The reorderable list keys its own wrapper; the filtered one has to.
    return dragIndex == null
        ? KeyedSubtree(key: ValueKey(category.id), child: row)
        : row;
  }

  Widget _buildNoMatchesState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
          const SizedBox(height: 4),
          TextButton(onPressed: _clearQuery, child: Text(l10n.clearSearch)),
        ],
      ),
    );
  }
}

/// One category row: colour/icon avatar, localized label, the built-in badge
/// and usage count, a visibility toggle and the options menu.
///
/// A widget rather than a method on the page so a keystroke in the search
/// field rebuilds the rows without rebuilding their subtrees wholesale, and so
/// the row's own layout stays readable next to a page that owns five slices'
/// worth of behaviour.
class _CategoryRow extends StatelessWidget {
  final CalendarCategory category;
  final int eventCount;

  /// Index in the enclosing reorderable list, or `null` while a query is
  /// active and reorder is therefore off.
  final int? dragIndex;

  final VoidCallback onToggleHidden;
  final ValueChanged<_CategoryAction> onAction;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.category,
    required this.eventCount,
    required this.dragIndex,
    required this.onToggleHidden,
    required this.onAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final subtitle = [
      if (category.isBuiltIn) l10n.categoryDefault,
      l10n.categoryEventCount(eventCount),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Opacity(
        opacity: category.isHidden ? 0.5 : 1.0,
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: theme.colorScheme.surfaceContainer,
          child: ListTile(
            minLeadingWidth: 0,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderHandle(index: dragIndex, enabled: dragIndex != null),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: category.color.withValues(alpha: 0.18),
                  foregroundColor: category.color,
                  child: Icon(
                    CalendarIcons.forKey(category.iconKey) ??
                        Icons.event_rounded,
                  ),
                ),
              ],
            ),
            title: Text(CalendarCategories.labelOf(category, l10n)),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    category.isHidden
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  tooltip: category.isHidden ? l10n.show : l10n.hide,
                  onPressed: onToggleHidden,
                ),
                PopupMenuButton<_CategoryAction>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: onAction,
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: _CategoryAction.moveToTop,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.vertical_align_top_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(l10n.moveToTop),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _CategoryAction.toggleHidden,
                      child: Row(
                        children: [
                          Icon(
                            category.isHidden
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(category.isHidden ? l10n.show : l10n.hide),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _CategoryAction.edit,
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 18),
                          const SizedBox(width: 8),
                          Text(l10n.edit),
                        ],
                      ),
                    ),
                    // Built-ins can be hidden; they still cannot be deleted.
                    if (!category.isBuiltIn)
                      PopupMenuItem(
                        value: _CategoryAction.delete,
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.delete,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
