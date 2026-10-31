import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_alerts.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/calendar_event_service.dart';
import '../services/category_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/category_search.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/automation_id.dart';
import '../widgets/category_editor_sheet.dart';
import '../widgets/content_rows.dart';
import '../widgets/event_avatar.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/form_rows.dart';
import '../widgets/settings_reorder.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/unified_app_bars.dart';
import '../widgets/value_change_highlight.dart';

/// One entry of the per-row "category options" menu.
enum _CategoryAction { moveToTop, edit, archive, delete }

/// The page's one list: a section's header or a category's row. The headers
/// are entries of the same reorderable sliver as the rows, as the browser's
/// Folders and Notes are, so a drag can never leave one sliver for another.
sealed class _Entry {
  const _Entry();

  Key get key;
}

class _HeaderEntry extends _Entry {
  final bool archived;

  const _HeaderEntry({required this.archived});

  @override
  Key get key => ValueKey('section:$archived');
}

class _RowEntry extends _Entry {
  final CalendarCategory category;
  final RowGroupPosition position;

  const _RowEntry(this.category, this.position);

  @override
  Key get key => ValueKey(category.id);
}

/// Management page for event categories: the browser's content rows in two
/// sections, In use over Archived, where the user searches, reorders,
/// archives, edits, creates and deletes them.
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
  final ScrollController _scrollController = ScrollController();

  CategoryService? _service;
  CalendarEventService? _eventService;

  /// The local display order. While a drag is being persisted this leads the
  /// service's own list, which is the whole point of the optimistic update —
  /// and the reason an empty query renders it **directly** rather than through
  /// [rankCategories], which sorts same-band rows on `sortOrder` and never on
  /// input order (a deliberate, tested property of that function), so the
  /// pre-drag values it still sees would snap the dragged row back.
  List<CalendarCategory> _categories = const [];

  /// The entries the list was last built from, which the reorder callback's
  /// render indices refer to.
  List<_Entry> _entries = const [];

  /// Advisory event counts, loaded once per page entry and after a delete.
  /// Never live state — one `GROUP BY` for the whole page, never a count per
  /// row.
  Map<String, int> _counts = const {};

  SettingsQuery _query = SettingsQuery.empty;
  bool _isLoading = true;

  /// The facade revision [_categories] was read at, so a catalogue change that
  /// came from this page is not refreshed a second time.
  int _categoryRevision = -1;

  /// How many times each row has been flashed: a row's highlight fires when
  /// its own count changes, so a row flashed once never flashes again when
  /// another one is.
  final Map<String, int> _flashes = {};

  /// The row a create last revealed, and the key that finds it on screen.
  /// Kept after the reveal: dropping the key would rebuild that row's subtree
  /// from scratch, and a fresh highlight never flashes.
  String? _revealId;
  GlobalKey? _revealKey;

  StreamSubscription<void>? _externalChanges;

  bool get _isFiltering => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    // A pull reloads `CategoryService` after every page it merges and a backup
    // import does the same, both of them behind this page. Without this the
    // page goes on holding the catalogue it opened with, and a drag, Move to
    // top or Sort A–Z persists *that* order: `reorder` numbers only the ids it
    // is handed, so a category that arrived meanwhile keeps a colliding
    // `sort_order` and the dense `0..N-1` order the facade's tie-break needs
    // is gone — on a synced row. Delete on a row the pull already removed is
    // the other half: it no-ops in the service, and the page would report a
    // delete that happened on another device.
    _externalChanges = CalendarEventService.externalChanges.listen(
      (_) => _onExternalChange(),
    );
  }

  @override
  void dispose() {
    _externalChanges?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Re-reads the catalogue and the counts when the store moved behind the
  /// page, guarded on the facade revision (the overview's shape) so the signal
  /// this page's own delete now fires costs nothing.
  void _onExternalChange() {
    if (!mounted || _categoryRevision == CalendarCategories.revision) return;
    _refresh();
    unawaited(_refreshCounts());
  }

  Future<void> _load() async {
    // Independent resolves, so start both before awaiting either. Reaching
    // this page means the calendar has already been open, so the event
    // service is a warm singleton and its `getInstance()` costs nothing.
    final categoryFuture = CategoryService.getInstance();
    final eventFuture = CalendarEventService.getInstance();
    try {
      final service = await categoryFuture;
      final eventService = await eventFuture;
      final counts = await eventService.countByCategory();
      if (!mounted) return;
      setState(() {
        _service = service;
        _eventService = eventService;
        _categories = service.categories;
        _categoryRevision = CalendarCategories.revision;
        _counts = counts;
        _isLoading = false;
      });
    } catch (e) {
      // Either `getInstance()` can throw — a database that failed to open
      // after a switch. Without this the spinner is the page for good and the
      // error escapes as an unhandled async error; the empty list at least
      // says the catalogue could not be read and leaves the page usable.
      debugPrint('[CalendarCategoriesPage] Load failed: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _refresh() {
    final service = _service;
    if (service == null) return;
    setState(() {
      _categories = service.categories;
      _categoryRevision = CalendarCategories.revision;
    });
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

  // ── Mutations ────────────────────────────────────────────────────────

  /// Runs [write] and reconciles with the service afterwards, whether it
  /// succeeded or not.
  ///
  /// Every mutation here is fired from a menu callback and never awaited, so
  /// an escaping error would surface as an unhandled async error rather than
  /// anything the user can act on. Reconciling on failure says half of it —
  /// an optimistic order visibly springs back to what is actually stored —
  /// but only half: the sections render the stored flag, so a failed
  /// `setHidden` springs back to nothing at all, and a failed delete leaves
  /// the row exactly where the user left it. Hence the message.
  Future<bool> _guarded(Future<void> Function() write) async {
    try {
      await write();
      return true;
    } catch (e) {
      debugPrint('[CalendarCategoriesPage] Write failed: $e');
      if (mounted) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.categoryChangeFailed,
        );
      }
      return false;
    } finally {
      if (mounted) _refresh();
    }
  }

  /// Refreshes whatever the sheet answers, then brings a created row into
  /// view and flashes it (K20): a new category lands at the end of In use,
  /// below the fold of any list long enough to need it.
  ///
  /// The sheet returns `null` when it was dismissed rather than saved — but a
  /// drag-close after a failed alert write pops past its `PopScope` and
  /// answers `null` with the category already written, and the row would then
  /// be listed only after the page was reopened. One `setState` is cheaper
  /// than trusting the answer.
  Future<void> _create() async {
    final created = await CategoryEditorSheet.show(context);
    if (!mounted) return;
    if (created != null) {
      _revealId = created.id;
      _revealKey = GlobalKey();
    }
    _refresh();
    if (created != null) await _reveal(created.id);
  }

  /// Scrolls the row of [id] into view, then flashes it.
  ///
  /// The list is a lazy sliver, so a row past the built range has no context
  /// to ensure visible: the position first moves to an estimate in proportion
  /// to the row's place in the list, which builds it, and only then is the
  /// row brought to the top of the viewport — `ensureVisible`'s own
  /// alignment, and the end away from the FAB over the bottom right; a row at
  /// the list's end stops short of the top and still clears the FAB through
  /// the `fabClearance` under the list.
  ///
  /// The extent past the built rows is itself an estimate the sliver refines
  /// as it lays them out, so the estimate can land past the true end for a
  /// few frames; the position is pulled back inside before the row is
  /// ensured, which would otherwise start from out of range.
  Future<void> _reveal(String id) async {
    final key = _revealKey;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || key == null) return;
    final index = _entries.indexWhere(
      (entry) => entry is _RowEntry && entry.category.id == id,
    );
    // A live query the new name does not match: nothing to show.
    if (index < 0) return;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final duration = animate ? Durations.medium2 : Duration.zero;
    if (key.currentContext == null && _scrollController.hasClients) {
      final position = _scrollController.position;
      final estimate =
          position.maxScrollExtent * index / math.max(1, _entries.length - 1);
      if (animate) {
        await position.animateTo(
          estimate,
          duration: duration,
          curve: Curves.easeInOut,
        );
      } else {
        position.jumpTo(estimate);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (position.pixels > position.maxScrollExtent) {
        position.jumpTo(position.maxScrollExtent);
      }
    }
    final target = key.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: duration,
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;
    setState(() => _flashes[id] = (_flashes[id] ?? 0) + 1);
  }

  Future<void> _edit(CalendarCategory category) async {
    await CategoryEditorSheet.show(context, initial: category);
    if (!mounted) return;
    _refresh();
  }

  Future<void> _setHidden(CalendarCategory category, bool hidden) {
    return _guarded(() => _service!.setHidden(category.id, hidden));
  }

  Future<void> _delete(CalendarCategory category) async {
    final l10n = AppLocalizations.of(context)!;
    final count = _counts[category.id] ?? 0;
    // Named through `labelOf` like every other surface, not through the raw
    // `name` column: only customs are deletable and the two agree for them,
    // but a dialog that names a category differently from the row that opened
    // it is one built-in away from reading in English.
    final label = CalendarCategories.labelOf(category, l10n);
    // A nonzero count makes the consequence concrete — and earns the sentence
    // pointing at hiding, which keeps the events in their own colour instead
    // of repainting that whole history grey.
    final content = count > 0
        ? '${l10n.deleteCategoryConfirmWithEvents(count, label)}'
              '\n\n${l10n.deleteCategoryHideHint}'
        : l10n.deleteCategoryConfirm(label);
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
    // The cascade tombstoned the category's alerts and moved its events onto
    // Other's, which the calendar's badges and the Alerts hub draw. Nullable:
    // a host without the app's bloc has nothing to redraw.
    context.read<CalendarBloc?>()?.add(const CategoryAlertsChanged());
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
    return _guarded(() => _service!.reorder([for (final c in ordered) c.id]));
  }

  /// Persists a new order of one section, [section], as the full list
  /// `reorder` numbers densely: the section's categories fill the slots its
  /// categories held, in their new order, and every row of the other section
  /// keeps its slot — so an archived category still comes back where it was
  /// when it is restored.
  ///
  /// [section] comes from the entries of the last build, and a pull can
  /// refresh [_categories] between that build and the drop: a section that no
  /// longer fills its slots one for one writes nothing, and the next build
  /// lists what is stored.
  Future<void> _persistSection(bool archived, List<CalendarCategory> section) {
    final slots = [
      for (final category in _categories)
        if (category.isHidden == archived) category.id,
    ];
    final held = {...slots};
    if (section.length != slots.length ||
        section.any((category) => !held.contains(category.id))) {
      return Future.value();
    }
    final next = section.iterator;
    final ordered = [
      for (final category in _categories)
        if (category.isHidden == archived)
          (next..moveNext()).current
        else
          category,
    ];
    return _persistOrder(ordered);
  }

  /// Turns a drop on the flat entry list into a reorder of the dragged row's
  /// own section.
  ///
  /// `onReorderItem` reports [newIndex] against the list with the dragged row
  /// already removed, so the section's bounds are measured there too. A drop
  /// past the other section's rows is refused — the row snaps back, nothing
  /// is written, since moving a category between sections is archiving and
  /// that has its own menu item; a drop on a header beside the row's own
  /// section lands at that section's nearest edge (the browser's rule).
  void _onReorderEntry(int oldIndex, int newIndex) {
    final entries = _entries;
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final moved = entries[oldIndex];
    if (moved is! _RowEntry) return;
    final archived = moved.category.isHidden;

    final remaining = [...entries]..removeAt(oldIndex);
    bool ownRow(_Entry entry) =>
        entry is _RowEntry && entry.category.isHidden == archived;
    final lower = remaining.indexWhere(ownRow);
    // Alone in its section: a drop anywhere leaves the order as it was, and
    // the write would only tick the clock and republish the catalogue.
    if (lower < 0) return;
    final upper = remaining.lastIndexWhere(ownRow);
    var target = newIndex;
    if (target < lower || target > upper + 1) {
      final between = target < lower
          ? remaining.sublist(target, lower)
          : remaining.sublist(upper + 1, math.min(target, remaining.length));
      if (between.any((entry) => entry is _RowEntry)) return;
      target = target.clamp(lower, upper + 1);
    }
    remaining.insert(target, moved);
    _persistSection(archived, [
      for (final entry in remaining)
        if (ownRow(entry)) (entry as _RowEntry).category,
    ]);
  }

  /// One tap for the case a long drag exists to serve: promoting a category
  /// you have started using a lot. Dragging row forty to the top is miserable
  /// at any auto-scroll velocity. The top of the row's own section, as a
  /// drag would.
  Future<void> _moveToTop(CalendarCategory category) {
    final archived = category.isHidden;
    return _persistSection(archived, [
      category,
      for (final c in _categories)
        if (c.isHidden == archived && c.id != category.id) c,
    ]);
  }

  /// One slot up ([delta] -1) or down (+1) inside the row's own section: the
  /// screen reader's way to do what the handle does, written as a drop is.
  Future<void> _moveBy(CalendarCategory category, int delta) {
    final section = [
      for (final c in _categories)
        if (c.isHidden == category.isHidden) c,
    ];
    final from = section.indexWhere((c) => c.id == category.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= section.length) return Future.value();
    section.insert(to, section.removeAt(from));
    return _persistSection(category.isHidden, section);
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

  // ── Menus ────────────────────────────────────────────────────────────

  Future<void> _openBarMenu(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context)!;
    FocusManager.instance.primaryFocus?.unfocus();
    final sort = await showFormMenu<bool>(
      anchor,
      items: [
        // Disabled, not hidden, while a query is live: it rewrites the whole
        // order, which the ranked list cannot show — the same reason the
        // handles go dead.
        FormMenuItem(
          value: true,
          label: l10n.sortCategoriesAlphabetically,
          icon: Icons.sort_by_alpha_rounded,
          identifier: SemanticsIds.categorySortAz,
          enabled: !_isFiltering,
        ),
      ],
      selected: null,
      menuWidth: FormMetrics.menuWidth,
    );
    if (sort != true || !mounted) return;
    unawaited(_sortAlphabetically());
  }

  /// The row's ⋮. Every item is always listed and disabled in place where it
  /// would do nothing or must not happen, so the menu never changes shape
  /// under the finger.
  Future<void> _openRowMenu(
    BuildContext anchor,
    CalendarCategory category, {
    required bool firstInSection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final inUse = _categories.where((c) => !c.isHidden).length;
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await showFormMenu<_CategoryAction>(
      anchor,
      items: [
        // Reorder and filtering are mutually exclusive, and this writes the
        // whole order: offered while the handles are dead it would persist a
        // promotion the ranked list never shows.
        FormMenuItem(
          value: _CategoryAction.moveToTop,
          label: l10n.moveToTop,
          icon: Icons.vertical_align_top_rounded,
          identifier: SemanticsIds.categoryMenuMoveToTop,
          enabled: !_isFiltering && !firstInSection,
        ),
        FormMenuItem(
          value: _CategoryAction.edit,
          label: l10n.edit,
          icon: Icons.edit_rounded,
          identifier: SemanticsIds.categoryMenuEdit,
        ),
        // The last visible category stays: with nothing in use every picker
        // would open empty. The service refuses it too.
        FormMenuItem(
          value: _CategoryAction.archive,
          label: category.isHidden
              ? l10n.categoryRestore
              : l10n.categoryArchive,
          icon: category.isHidden
              ? Icons.unarchive_rounded
              : Icons.archive_rounded,
          identifier: SemanticsIds.categoryMenuArchive,
          enabled: category.isHidden || inUse > 1,
        ),
        // Built-ins can be archived; they still cannot be deleted.
        FormMenuItem(
          value: _CategoryAction.delete,
          label: l10n.categoryDeleteEllipsis,
          icon: Icons.delete_rounded,
          identifier: SemanticsIds.categoryMenuDelete,
          enabled: !category.isBuiltIn,
          color: colorScheme.error,
        ),
      ],
      selected: null,
      menuWidth: FormMetrics.menuWidth,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _CategoryAction.moveToTop:
        unawaited(_moveToTop(category));
      case _CategoryAction.edit:
        unawaited(_edit(category));
      case _CategoryAction.archive:
        unawaited(_setHidden(category, !category.isHidden));
      case _CategoryAction.delete:
        unawaited(_delete(category));
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // While the keyboard is up the list is a few rows tall and the FAB would
    // sit on them; it floats, so leaving it out moves no row.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.calendarCategories,
        actions: [
          Builder(
            builder: (anchor) => AutomationId(
              identifier: SemanticsIds.categoryBarMenu,
              child: IconButton(
                icon: const Icon(Icons.more_vert),
                iconSize: AppBarMetrics.glyphSize,
                tooltip: MaterialLocalizations.of(anchor).showMenuTooltip,
                onPressed: () => _openBarMenu(anchor),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: keyboardUp
          ? null
          : AutomationId(
              identifier: SemanticsIds.categoryAdd,
              child: FloatingActionButton(
                heroTag: null,
                tooltip: l10n.createCategory,
                onPressed: _create,
                child: const Icon(Icons.add_rounded),
              ),
            ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Short lists carry no search chrome; the threshold trips on its own as
    // the set grows. `_isFiltering` holds the field open once it is in use:
    // deleting a category can drop the count back under the threshold, and
    // retracting the field mid-query would strand the list filtered with
    // nothing left to clear it.
    final showSearch =
        _isFiltering || _categories.length > AppConstants.listSearchThreshold;
    final rows = _isFiltering
        ? [
            for (final ranked in rankCategories(_query, _categories, l10n))
              ranked.category,
          ]
        : _categories;
    final entries = _entriesFor(rows);
    _entries = entries;

    return Column(
      children: [
        if (showSearch)
          Padding(
            padding: FormMetrics.settingsSearchPadding,
            child: SettingsSearchField(
              controller: _searchController,
              hint: l10n.searchCategories,
              onChanged: _onQueryChanged,
              identifier: SemanticsIds.categorySearch,
            ),
          ),
        if (_isFiltering)
          ReorderLockedHint(text: l10n.categoryReorderLockedHint),
        // The list owns the nearest enclosing `Scrollable`, which is what
        // binds the reorderable sliver's edge auto-scroller to the thing that
        // actually scrolls. Nesting it in an outer scroll view with
        // `shrinkWrap: true` silently kills dragging past the fold.
        Expanded(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.only(top: FormMetrics.bodyTop),
              ),
              if (entries.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RowMetrics.groupInset,
                    ),
                    child: FormCaption(
                      text: l10n.noCategoriesMatch,
                      padding: FormMetrics.groupCaptionPadding,
                    ),
                  ),
                )
              else if (_isFiltering)
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _buildEntry(entries[index]),
                )
              else
                SliverReorderableList(
                  itemCount: entries.length,
                  // An open keyboard halves the viewport, which halves the
                  // usable drag region. A query cannot be active during a
                  // drag, but focus with an empty field can.
                  onReorderStart: (_) => FocusScope.of(context).unfocus(),
                  onReorderItem: _onReorderEntry,
                  proxyDecorator: _liftedRow,
                  itemBuilder: (context, index) =>
                      _buildEntry(entries[index], dragIndex: index),
                ),
              // The FAB floats over the list's end: the last row scrolls
              // clear of it.
              const SliverPadding(
                padding: EdgeInsets.only(bottom: AppSpacing.fabClearance),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// [rows] split into In use over Archived, each in [rows]' own order (the
  /// stored one, or the query's ranking), with a header over a section only
  /// while it holds a row.
  List<_Entry> _entriesFor(List<CalendarCategory> rows) {
    final inUse = [
      for (final c in rows)
        if (!c.isHidden) c,
    ];
    final archived = [
      for (final c in rows)
        if (c.isHidden) c,
    ];
    return [
      for (final (isArchived, section) in [(false, inUse), (true, archived)])
        if (section.isNotEmpty) ...[
          _HeaderEntry(archived: isArchived),
          for (var i = 0; i < section.length; i++)
            _RowEntry(section[i], _positionIn(i, section.length)),
        ],
    ];
  }

  static RowGroupPosition _positionIn(int index, int length) {
    if (length == 1) return RowGroupPosition.single;
    if (index == 0) return RowGroupPosition.first;
    if (index == length - 1) return RowGroupPosition.last;
    return RowGroupPosition.middle;
  }

  /// One entry of the list; [dragIndex] is the entry's index in the
  /// reorderable sliver, null while a query is live.
  Widget _buildEntry(_Entry entry, {int? dragIndex}) {
    final l10n = AppLocalizations.of(context)!;
    return switch (entry) {
      _HeaderEntry(:final archived) => KeyedSubtree(
        key: entry.key,
        child: ContentSectionHeader(
          label: archived
              ? l10n.categorySectionArchived
              : l10n.categorySectionInUse,
          identifier: archived
              ? SemanticsIds.categorySectionArchivedHeader
              : SemanticsIds.categorySectionInUseHeader,
        ),
      ),
      _RowEntry() => KeyedSubtree(
        key: entry.key,
        child: _rowFor(entry, dragIndex: dragIndex),
      ),
    };
  }

  Widget _rowFor(_RowEntry entry, {int? dragIndex, bool lifted = false}) {
    final category = entry.category;
    return _CategoryRow(
      key: !lifted && category.id == _revealId ? _revealKey : null,
      category: category,
      caption: _captionFor(category),
      position: entry.position,
      dragIndex: dragIndex,
      reorderLocked: _isFiltering,
      flash: _flashes[category.id] ?? 0,
      lifted: lifted,
      onTap: () => _edit(category),
      // Where the handle could drag, as far as the section goes.
      onMoveUp: lifted || _isFiltering || entry.position.isFirst
          ? null
          : () => unawaited(_moveBy(category, -1)),
      onMoveDown: lifted || _isFiltering || entry.position.isLast
          ? null
          : () => unawaited(_moveBy(category, 1)),
      onMenu: (anchor) => _openRowMenu(
        anchor,
        category,
        firstInSection: entry.position.isFirst,
      ),
    );
  }

  /// The row's second line: its use, then what sets it apart. A segment's
  /// own words are held together by the no-break space the strings carry,
  /// and the space before each dot is one too, so a wrapped line never
  /// starts with the dot.
  String _captionFor(CalendarCategory category) {
    final l10n = AppLocalizations.of(context)!;
    // Read per build from the facade, which the editor republishes before it
    // pops — and [_refresh] rebuilds the rows when it does.
    final hasAlerts = EventAlerts.categoryAlertsFor(
      category.id,
    ).any((alert) => alert.enabled);
    return [
      l10n.categoryEventCount(_counts[category.id] ?? 0),
      if (category.isBuiltIn) l10n.categoryCaptionBuiltIn,
      if (hasAlerts) l10n.categoryCaptionAlertsOn,
    ].join(' · ');
  }

  /// The lifted row: one card of its own, whatever its place in its group,
  /// under the shared proxy (a hair of scale, a shadow). Inset and
  /// top-aligned by hand rather than drawn in a single-position shell: the
  /// proxy's box is the dragged item's own, and a shell's group gap under a
  /// row that had none would squeeze the card inside it.
  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    final entry = index < _entries.length ? _entries[index] : null;
    if (entry is! _RowEntry) return child;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
      child: Align(
        alignment: Alignment.topCenter,
        child: reorderDragProxy(
          _rowFor(
            _RowEntry(entry.category, RowGroupPosition.single),
            lifted: true,
          ),
          index,
          animation,
          // The card's own corner, so the shadow follows it.
          borderRadius: const BorderRadius.all(
            Radius.circular(RowMetrics.groupRadius),
          ),
        ),
      ),
    );
  }
}

/// One category row on the browser's two-line content row: the handle, the
/// category's avatar, its name over its caption, and the ⋮.
///
/// A widget rather than a method on the page so a keystroke in the search
/// field rebuilds the rows without rebuilding their subtrees wholesale, and so
/// the row's own layout stays readable next to a page that owns five slices'
/// worth of behaviour.
class _CategoryRow extends StatelessWidget {
  final CalendarCategory category;
  final String caption;
  final RowGroupPosition position;

  /// Index in the enclosing reorderable list, or `null` while a query is
  /// active and reorder is therefore off.
  final int? dragIndex;

  /// A live query: the handle greys in place and the row says nothing about
  /// reordering.
  final bool reorderLocked;

  /// The row's flash count; a change flashes the row.
  final int flash;

  /// Drawn as the drag proxy's card rather than inside its group.
  final bool lifted;

  final VoidCallback onTap;

  /// The row's "Move up" / "Move down" semantics actions; null where the row
  /// cannot move that way, which leaves the action off the node.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final void Function(BuildContext anchor) onMenu;

  const _CategoryRow({
    super.key,
    required this.category,
    required this.caption,
    required this.position,
    required this.dragIndex,
    required this.reorderLocked,
    required this.flash,
    required this.lifted,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final name = CalendarCategories.labelOf(category, l10n);
    final archived = category.isHidden;
    // Decided by the text scale, never by the names: the 18 dp the glyph
    // frees is what keeps every built-in name whole at 2.0 on a small phone.
    final scaler = MediaQuery.textScalerOf(context);
    final compact =
        scaler.scale(RowMetrics.titleFontSize) / RowMetrics.titleFontSize >=
        RowMetrics.compactLeadingTextScale;
    final icon = CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;

    // The handle sits inside the row's ink well: a short tap on it, meant as
    // the start of a drag, is taken here and does nothing rather than open
    // the editor. Its drag listeners are below this and untouched. Never
    // dimmed on an archived row — it is still a control to hold, and
    // `outline` at the disabled opacity measured 1.60:1.
    final handle = GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      child: ReorderHandle(
        index: dragIndex,
        enabled: !reorderLocked,
        label: l10n.categoryReorderLabel(name),
      ),
    );
    Widget leading = compact
        ? ExcludeSemantics(
            child: Icon(
              icon,
              size: RowMetrics.glyphSize,
              color: category.color,
            ),
          )
        : EventAvatar(icon: icon, color: category.color);
    // Only the leading dims on an archived row: the section header already
    // says Archived, and dimmed text on an operable row would fail contrast.
    if (archived) {
      leading = Opacity(opacity: FormMetrics.disabledOpacity, child: leading);
    }

    final texts = Padding(
      padding: EdgeInsets.symmetric(
        vertical: RowMetrics.twoLinePadding.vertical / 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: RowMetrics.titleFontSize,
              fontWeight: FontWeight.w400,
              height: FormMetrics.labelLineHeight / RowMetrics.titleFontSize,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: RowMetrics.lineGap),
          Text(
            caption,
            style: TextStyle(
              fontSize: RowMetrics.secondLineFontSize,
              height:
                  FormMetrics.captionLineHeight / RowMetrics.secondLineFontSize,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    Widget body = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: RowMetrics.twoLineMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: RowMetrics.reorderHandleLead),
          child: Row(
            children: [
              handle,
              leading,
              const SizedBox(width: RowMetrics.gap),
              Expanded(child: texts),
            ],
          ),
        ),
      ),
    );
    // A long press anywhere on the row lifts it, as the handle does at once.
    final at = dragIndex;
    if (at != null && !lifted) {
      body = ReorderableDelayedDragStartListener(index: at, child: body);
    }

    // One node with the name, the caption, the state and the handle's name,
    // in that order; the ⋮ is a sibling node, which a merged row could keep
    // neither ordered nor operable. The handle's name promises a reorder, and
    // a screen reader cannot drag: the node carries it as two actions.
    final row = Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            identifier: lifted ? null : SemanticsIds.categoryRow(category.id),
            button: true,
            excludeSemantics: true,
            label: [
              name,
              caption,
              if (archived) l10n.categoryRowArchived,
              if (!reorderLocked) l10n.categoryReorderLabel(name),
            ].join('\n'),
            onTap: onTap,
            customSemanticsActions: {
              CustomSemanticsAction(label: l10n.categoryMoveUp): ?onMoveUp,
              CustomSemanticsAction(label: l10n.categoryMoveDown): ?onMoveDown,
            },
            child: body,
          ),
        ),
        Builder(
          builder: (anchor) => FormTrailingButton(
            icon: Icons.more_vert_rounded,
            tooltip: l10n.categoryActions,
            identifier: lifted
                ? null
                : SemanticsIds.categoryRowMenu(category.id),
            onPressed: () => onMenu(anchor),
          ),
        ),
      ],
    );

    final radius = Radius.circular(RowMetrics.groupRadius);
    final corners = BorderRadius.vertical(
      top: position.isFirst ? radius : Radius.zero,
      bottom: position.isLast ? radius : Radius.zero,
    );
    final content = ValueChangeHighlight(
      value: flash,
      borderRadius: corners,
      child: row,
    );

    if (lifted) {
      return Material(
        type: MaterialType.card,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.rowGroup,
        borderRadius: corners,
        child: content,
      );
    }
    return ContentRowShell(
      position: position,
      dividerIndent: compact
          ? RowMetrics.reorderGlyphTextInset
          : RowMetrics.reorderAvatarTextInset,
      child: content,
    );
  }
}
