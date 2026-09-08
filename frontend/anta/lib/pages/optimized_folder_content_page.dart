import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:math' as math;
import '../l10n/app_localizations.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/import_export/import_export_state.dart';
import '../bloc/optimized_folder/optimized_folder_bloc.dart';
import '../bloc/optimized_folder/optimized_folder_event.dart';
import '../bloc/optimized_folder/optimized_folder_state.dart';
import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../bloc/optimized_note/optimized_note_state.dart';
import '../bloc/search/search_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/settings_keys.dart';
import '../controllers/in_place_search_controller.dart';
import '../controllers/selection_controller.dart';
import '../models/content_item.dart';
import '../models/export_format.dart';
import '../models/folder.dart';
import '../models/folder_change.dart';
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../models/search_scope.dart';
import '../repositories/note_repository.dart';
import '../services/folder_search_service.dart';
import '../services/folder_storage_service.dart';
import '../services/mixed_reorder_service.dart';
import '../services/move_coordinator.dart';
import '../services/move_history_service.dart';
import '../services/note_storage_service.dart';
import '../services/settings_service.dart';
import '../widgets/infinite_scroll_list.dart';
import '../widgets/app_drawer.dart';
import '../widgets/content_rows.dart';
import '../widgets/folder_overflow_menu.dart';
import '../widgets/folder_row.dart';
import '../widgets/folder_sliver_app_bar.dart';
import '../widgets/note_row.dart';
import '../widgets/search_field_app_bar.dart';
import '../widgets/search_surface.dart';
import '../widgets/selection_action_bar.dart';
import '../widgets/selection_app_bar.dart';
import '../utils/bloc_helpers.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../services/app_navigator.dart';
import '../services/drawer_host_registry.dart';
import '../widgets/move_history_sheet.dart';

/// One row of the browser's list: either a section label or a content item.
///
/// Both kinds live in the same sequence because there is exactly one
/// reorderable sliver over the whole list; a label is simply a row nothing
/// can pick up.
sealed class _RowEntry {
  const _RowEntry();
}

class _SectionEntry extends _RowEntry {
  final String label;
  const _SectionEntry(this.label);
}

class _ItemEntry extends _RowEntry {
  final ContentItem item;
  final RowGroupPosition position;
  const _ItemEntry(this.item, this.position);
}

/// Which bar is occupying the top of the page, and therefore how much scroll
/// extent the list underneath has lost or regained.
///
/// The three are mutually exclusive by construction: search is reachable only
/// from the normal bar, and selection replaces whichever of the other two is
/// showing.
enum _BarMode { normal, selection, search }

/// One of the root's smart rows: a destination that is not a folder, drawn
/// in the same shell as the rows below it so the whole page reads as one
/// kind of list.
///
/// The count rides the trailing slot rather than a second line, in the
/// reserved-width box every folder row uses: a count that arrives late
/// changes nothing about the row it lands in, so the rows below it never
/// move.
class _SmartRow extends StatelessWidget {
  const _SmartRow({
    required this.icon,
    required this.label,
    required this.position,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final RowGroupPosition position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ContentRowShell(
      position: position,
      dividerIndent: RowMetrics.dividerIndentWithGlyph,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RowMetrics.singleLineMinHeight,
          ),
          child: Padding(
            padding: RowMetrics.singleLinePadding,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: RowMetrics.glyphSize,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: RowMetrics.gap),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: RowMetrics.titleFontSize,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: RowMetrics.gap),
                RowCountChevron(count: count),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OptimizedFolderContentPage extends StatefulWidget {
  final String? folderId;
  final String title;

  const OptimizedFolderContentPage({
    super.key,
    this.folderId,
    required this.title,
  });

  @override
  State<OptimizedFolderContentPage> createState() =>
      _OptimizedFolderContentPageState();
}

class _OptimizedFolderContentPageState extends State<OptimizedFolderContentPage>
    with RouteAware {
  /// Lets a restored settings page raise this page's drawer when it is popped
  /// — see [DrawerHostRegistry].
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  NotesSortOrder _notesSortOrder = NotesSortOrder.updatedDesc;
  FoldersSortOrder _foldersSortOrder = FoldersSortOrder.nameAsc;
  bool _folderSwipeEnabled = true;
  bool _showNotePreview = SettingsKeys.defaultShowNotePreview;

  /// This page's own folder, for the overflow menu's rename/move/share/
  /// delete rows. Null on the root page, and until the first read answers.
  Folder? _folder;

  /// Root → direct parent, excluding this folder. Feeds both the eyebrow
  /// above the large title and the ancestor menu behind it. Null until the
  /// walk answers, so the eyebrow appears once rather than saying "Folders"
  /// and then correcting itself; empty for a folder directly under the root.
  List<Folder>? _ancestors;

  // Per-page selection state. Long-press a card to enter selection mode,
  // tap to toggle, then act on the whole batch (move, delete, drag-and-drop).
  late final SelectionController _selection = SelectionController();
  StreamSubscription<Set<MovableItemRef>>? _selectionSub;

  /// Both of the bars that can replace the tall sliver one are shorter than
  /// it, so keeping the scroll offset across a swap would carry every row up
  /// by the difference — a 68 px jump on every long press. These remember
  /// where the folder list was so the swap can be paid for in the same frame:
  /// [_barMode] against [_lastBarMode] detects the edge,
  /// [_offsetBeforeSwap] is what to return to, and [_offsetOnEnterSwap] is
  /// what was jumped to, so scrolling done in selection mode is added back
  /// rather than thrown away.
  _BarMode _lastBarMode = _BarMode.normal;
  double _offsetBeforeSwap = 0;
  double _offsetOnEnterSwap = 0;

  /// What the expanded bar is worth over the bar that replaces it. Measured
  /// against [SelectionAppBar]'s own height rather than the framework's
  /// default toolbar, and against this page's own expanded height, which the
  /// root and a nested folder do not share.
  double get _barSwapShift =>
      FolderSliverAppBar.expandedHeightFor(widget.folderId == null) -
      SelectionAppBar.height;

  /// Search runs on a bloc of this page's own, so results never touch the
  /// folder list underneath and query, scope and scroll all survive pushing
  /// a note and coming back — the page stays mounted below it.
  late final InPlaceSearchController _search = InPlaceSearchController(
    bloc: SearchBloc(
      searchService: GetIt.I<FolderSearchService>(),
      noteService: GetIt.I<NoteStorageService>(),
      folderService: _folderStorageService,
    ),
  );

  bool get _searching => _search.isSearching;

  // Latest visible items, kept up to date by [_buildFoldersSection] and
  // [_buildNotesSection] so SelectAll can act on them without re-querying.
  List<Folder> _visibleFolders = const [];
  List<NoteMetadata> _visibleNotes = const [];

  // Optimistic reorder state for the unified mixed (folders + notes)
  // sliver. SliverReorderableList only calls onReorderItem; it does not
  // mutate the data itself, so without an immediate local update the list
  // would visually "snap back" while the bloc round-trip (DB write ->
  // refresh -> reload) completes. We render from this list during selection
  // mode and mutate it synchronously inside onReorderItem.
  List<ContentItem>? _localMixed;

  // Drag-in-progress tracking for multi-selection visual feedback. While a
  // drag is active, other selected cards are dimmed so the user sees the
  // whole batch is travelling along with the lifted card.
  bool _isDraggingMulti = false;

  // Tracks whether an in-progress export/import loading dialog is currently
  // mounted, so the [ImportExportBloc] listener can pop it exactly once on
  // the terminal state transition.
  bool _ioLoadingDialogOpen = false;

  /// Descendant-inclusive note count per visible folder id. Read for the
  /// whole page in one statement rather than two per row, which is what a
  /// row could do when it owned its own counts.
  Map<String, int> _folderNoteCounts = const {};

  /// The id set the counts in [_folderNoteCounts] were read for, so a rebuild
  /// that shows the same folders does not re-query.
  List<String> _countedFolderIds = const [];

  /// Guards against a slow per-folder count landing on top of a newer one.
  int _folderCountsGeneration = 0;

  /// Every live note in the database, for the root's "All notes" row. Null
  /// until the first read answers, which the row draws as no trailing label
  /// rather than as a zero — a count that corrected itself would be worse
  /// than one that arrives.
  int? _allNotesCount;

  /// Guards against a slow global count landing on top of a newer one.
  int _allNotesCountGeneration = 0;

  /// Coalesces bursts of folder/note changes — a bulk move, a cascade delete,
  /// a batch reorder — into one trailing-edge count read for the page.
  Timer? _countDebounce;
  static const _countDebounceDuration = Duration(milliseconds: 120);
  StreamSubscription<FolderChange>? _folderChangesSub;
  StreamSubscription<NoteChange>? _noteChangesSub;

  /// The rows as the list renders them: section labels and content items in
  /// one flat sequence, rebuilt whenever the displayed items change. The
  /// reorder handler reads it to translate a row index into a content index.
  List<_RowEntry> _entries = const [];

  /// Sync the local list from the bloc list, preserving local order if it
  /// contains exactly the same set of ids (covers the case where we just
  /// reordered locally and the bloc refresh confirms with the same items).
  List<T> _syncLocal<T>(
    List<T>? local,
    List<T> incoming,
    String Function(T) idOf,
  ) {
    if (local == null) return List<T>.from(incoming);
    if (local.length != incoming.length) return List<T>.from(incoming);
    final localIds = local.map(idOf).toSet();
    final incomingIds = incoming.map(idOf).toSet();
    if (localIds.length != incomingIds.length ||
        !localIds.containsAll(incomingIds)) {
      return List<T>.from(incoming);
    }
    // Same set of ids -> assume local order is the source of truth (just
    // reordered). Replace each local entry with the latest incoming object
    // (so other fields like updatedAt are fresh) but keep order.
    final byId = {for (final item in incoming) idOf(item): item};
    return [for (final item in local) byId[idOf(item)] as T];
  }

  FolderStorageService get _folderStorageService =>
      GetIt.I<FolderStorageService>();
  MixedReorderService get _mixedReorderService =>
      GetIt.I<MixedReorderService>();

  @override
  void initState() {
    super.initState();
    DrawerHostRegistry.register(_scaffoldKey);
    _selectionSub = _selection.changes.listen((_) {
      if (mounted) {
        // Drop optimistic state when leaving selection mode so the next
        // entry starts fresh from bloc data.
        if (!_selection.isActive) {
          _localMixed = null;
        }
        if (_selection.isActive) _leaveSearch();
        _compensateBarSwap();
        setState(() {});
      }
    });
    _subscribeToContentChanges();
    _loadSettings();
    _loadSortPreferencesAndData();
    if (widget.folderId == null) _loadAllNotesCount();
  }

  /// One subscription for the whole page, not one per row: any folder or note
  /// write can change a descendant-inclusive count, and the debounce collapses
  /// a burst into a single re-read of every visible folder.
  void _subscribeToContentChanges() {
    _folderChangesSub = _folderStorageService.changes.listen(
      (_) => _scheduleCountRefresh(),
    );
    _noteChangesSub = GetIt.I<NoteStorageService>().changes.listen(
      (_) => _scheduleCountRefresh(),
    );
  }

  void _scheduleCountRefresh() {
    if (!mounted) return;
    _countDebounce?.cancel();
    _countDebounce = Timer(_countDebounceDuration, () {
      if (!mounted) return;
      _loadFolderCounts(_countedFolderIds, force: true);
      if (widget.folderId == null) _loadAllNotesCount();
    });
  }

  /// The global note count behind the root's "All notes" row.
  ///
  /// The generation guard is what keeps a slow read from painting a stale
  /// total over a newer one: a bulk delete answers this twice, and the two
  /// reads can land in either order.
  Future<void> _loadAllNotesCount() async {
    final generation = ++_allNotesCountGeneration;
    try {
      final count = await GetIt.I<NoteStorageService>().getNoteCount(null);
      if (!mounted || generation != _allNotesCountGeneration) return;
      setState(() => _allNotesCount = count);
    } catch (e, stackTrace) {
      debugPrint('[FolderPage] Failed to count all notes: $e\n$stackTrace');
    }
  }

  /// Reads every visible folder's count in one statement. Skips the read when
  /// the same ids were already answered, which is what keeps a rebuild from
  /// re-querying on every scroll frame.
  ///
  /// Called from the list's own builder, so the empty case assigns without a
  /// `setState`: with no folder rows on screen there is nothing whose count
  /// could repaint, and asking for a rebuild there is a rebuild during build.
  Future<void> _loadFolderCounts(
    List<String> folderIds, {
    bool force = false,
  }) async {
    if (folderIds.isEmpty) {
      _countedFolderIds = const [];
      _folderNoteCounts = const {};
      return;
    }
    if (!force && _sameIds(folderIds, _countedFolderIds)) return;
    // The id check alone cannot order two reads of the *same* ids, which is
    // exactly what a forced refresh issues: a bulk delete answers this twice
    // and the two can land in either order. Same guard as
    // [_loadAllNotesCount].
    final generation = ++_folderCountsGeneration;
    _countedFolderIds = List<String>.unmodifiable(folderIds);
    try {
      final counts = await _folderStorageService.getNoteCountsWithDescendants(
        folderIds,
      );
      if (!mounted ||
          generation != _folderCountsGeneration ||
          !_sameIds(folderIds, _countedFolderIds)) {
        return;
      }
      setState(() {
        _folderNoteCounts = {for (final id in folderIds) id: counts[id] ?? 0};
      });
    } catch (e, stackTrace) {
      debugPrint('[FolderPage] Failed to load folder counts: $e\n$stackTrace');
    }
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  _BarMode get _barMode {
    if (_selection.isActive) return _BarMode.selection;
    return _searching ? _BarMode.search : _BarMode.normal;
  }

  /// Pays for the app-bar swap in the same tick the rebuild is scheduled, so
  /// the jump and the new bar land in one frame. A post-frame callback would
  /// paint one frame at the wrong offset first, which is the jump this
  /// exists to remove.
  ///
  /// Selection keeps the same rows under a shorter bar, so entering shifts by
  /// the height the bar gave back and leaving is its exact inverse. Entering
  /// near the top is the case worth naming: the shift clamps at zero there,
  /// and adding the clamped-away pixels back on the way out would drop the
  /// list below where it started, so a selection that never scrolled returns
  /// to the offset it entered from and one that did pays the full shift back.
  /// Search replaces the rows outright, so it opens its results at the top and
  /// gives the folder list back the offset it had, untouched by any scrolling
  /// done through results.
  ///
  /// The result is deliberately not clamped against `maxScrollExtent`: the
  /// new extent is not known until the swap has been laid out, and the
  /// physics settle the rare case where the list shrank.
  ///
  /// A caller tearing one mode down on the way into another passes the
  /// intermediate [target] so the two swaps are paid for one at a time: the
  /// folder list gets its offset back first, and the next swap measures from
  /// there rather than from the offset the outgoing mode had.
  void _compensateBarSwap([_BarMode? target]) {
    final mode = target ?? _barMode;
    if (mode == _lastBarMode) return;
    final previous = _lastBarMode;
    _lastBarMode = mode;
    if (!_scrollController.hasClients) {
      _offsetBeforeSwap = 0;
      _offsetOnEnterSwap = 0;
      return;
    }
    final offset = _scrollController.offset;
    if (mode != _BarMode.normal) {
      _offsetBeforeSwap = offset;
      _offsetOnEnterSwap = mode == _BarMode.selection
          ? math.max(0, offset - _barSwapShift)
          : 0;
      _scrollController.jumpTo(_offsetOnEnterSwap);
      return;
    }
    final restored = previous == _BarMode.selection
        ? (offset > _offsetOnEnterSwap
              ? offset + _barSwapShift
              : _offsetBeforeSwap)
        : _offsetBeforeSwap;
    _scrollController.jumpTo(math.max(0, restored));
  }

  FolderScope? get _folderScope {
    final folderId = widget.folderId;
    if (folderId == null) return null;
    return FolderScope(folderId: folderId, name: _folder?.name ?? widget.title);
  }

  void _openSearch() {
    if (_selection.isActive) {
      _selection.clear();
      _compensateBarSwap(_BarMode.normal);
    }
    if (!_search.open(_folderScope ?? const SearchScope.everywhere())) return;
    _compensateBarSwap();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) _search.requestFocus();
    });
  }

  /// Tears search down without asking for a frame, so the selection listener
  /// can run it and its own swap back to back in one tick. The swap is paid
  /// for as search → normal explicitly: by the time the listener runs,
  /// selection is already active and [_barMode] would report it, which would
  /// skip giving the folder list its offset back before the selection swap
  /// measures from it. Selection and search are mutually exclusive.
  void _leaveSearch() {
    if (!_search.leave()) return;
    _compensateBarSwap(_BarMode.normal);
  }

  void _exitSearch() {
    if (!_searching) return;
    _leaveSearch();
    setState(() {});
  }

  Future<void> _loadSortPreferencesAndData() async {
    // Load sort preferences from DB for this folder
    if (widget.folderId != null) {
      final folder = await _folderStorageService.getFolderById(
        widget.folderId!,
      );
      if (folder != null && mounted) {
        setState(() {
          _folder = folder;
          _notesSortOrder = _parseNotesSortOrder(folder.noteSortOrder);
          _foldersSortOrder = _parseFoldersSortOrder(folder.subfolderSortOrder);
        });
      }
      await _loadAncestors();
    }
    _loadData();
  }

  Future<void> _loadAncestors() async {
    final folderId = widget.folderId;
    if (folderId == null) return;
    final ancestors = await _folderStorageService.getAncestors(folderId);
    if (!mounted) return;
    setState(() => _ancestors = ancestors);
  }

  NotesSortOrder _parseNotesSortOrder(String? value) {
    if (value == null) return NotesSortOrder.updatedDesc;
    return NotesSortOrder.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotesSortOrder.updatedDesc,
    );
  }

  FoldersSortOrder _parseFoldersSortOrder(String? value) {
    if (value == null) return FoldersSortOrder.nameAsc;
    return FoldersSortOrder.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FoldersSortOrder.nameAsc,
    );
  }

  /// Reads the two page-level switches, and repaints only if one moved.
  ///
  /// Both callers are moments the values can actually have changed — first
  /// build and the pop back from the settings page that owns them. It used to
  /// run from [didChangeDependencies] as well, which fires on every
  /// MediaQuery change: two preference reads and a page `setState` per
  /// keyboard animation frame.
  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final folderSwipe = await settings.getFolderSwipeEnabled();
    final showPreview = await settings.getShowNotePreview();
    if (!mounted) return;
    if (folderSwipe == _folderSwipeEnabled && showPreview == _showNotePreview) {
      return;
    }
    setState(() {
      _folderSwipeEnabled = folderSwipe;
      _showNotePreview = showPreview;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  /// The note-preview switch lives in the settings page the drawer opens over
  /// this one, so the only moment it can have changed is the pop back.
  ///
  /// Search is deliberately left standing: the page was never unmounted, so
  /// query, scope and scroll are still there. Only the hits are re-run, so a
  /// note edited through a result comes back with a fresh snippet.
  @override
  void didPopNext() {
    _loadSettings();
    if (_searching) _search.refresh();
  }

  /// A route regaining focus hands it back to the child that had it, and a
  /// field regaining focus reopens the keyboard — so coming back from a
  /// result would cover the results it returns to. Letting go of the field
  /// on the way out leaves the query and the hits where they were, with the
  /// keyboard down until the field is tapped again.
  @override
  void didPushNext() {
    if (_searching) _search.unfocus();
  }

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    DrawerHostRegistry.unregister(_scaffoldKey);
    _selectionSub?.cancel();
    _folderChangesSub?.cancel();
    _noteChangesSub?.cancel();
    _countDebounce?.cancel();
    _selection.dispose();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Selection mode helpers ─────────────────────────────────────────────

  MovableItemRef _refForFolder(Folder f) => MovableItemRef(
    kind: MovableItemKind.folder,
    id: f.id,
    name: f.name,
    currentParentId: widget.folderId,
  );

  MovableItemRef _refForNote(NoteMetadata n) {
    final l10n = AppLocalizations.of(context)!;
    return MovableItemRef(
      kind: MovableItemKind.note,
      id: n.id,
      name: n.title.isEmpty ? l10n.untitledNote : n.title,
      currentParentId: widget.folderId,
    );
  }

  void _onCardLongPress(MovableItemRef ref) {
    _selection.add(ref);
  }

  void _onCardTapInSelection(MovableItemRef ref) {
    _selection.toggle(ref);
  }

  /// Multi-item reorder.
  ///
  /// `SliverReorderableList` only knows about the single dragged item, but
  /// the user expects all selected items to travel as a group when they drag
  /// any one of them. This helper:
  ///
  ///   1. Detects whether the dragged item belongs to a multi-selection.
  ///   2. If so, removes every selected item from the list (preserving their
  ///      original relative order) and inserts them as a contiguous block at
  ///      the drop target — adjusted for the items removed before it.
  ///   3. Falls back to a plain single-item reorder when only one item (or
  ///      none) is selected, or when the dragged item is not in the
  ///      selection.
  ///
  /// This is O(n) in the visible list size, runs synchronously, and produces
  /// a single ordered list to hand to the bloc — no per-item bloc events.
  List<T> _applyMultiReorder<T>({
    required List<T> source,
    required int oldIndex,
    required int newIndex,
    required MovableItemRef Function(T) refOf,
  }) {
    final draggedItem = source[oldIndex];
    final draggedRef = refOf(draggedItem);
    final selectionContainsDragged = _selection.contains(draggedRef);
    final isMulti = selectionContainsDragged && _selection.count > 1;

    if (!isMulti) {
      // `onReorderItem` hands over the post-removal index, so it can be used
      // directly as the insertion point.
      final result = List<T>.from(source);
      final item = result.removeAt(oldIndex);
      result.insert(newIndex, item);
      return result;
    }

    // Multi: split selected vs. unselected while preserving the visible
    // order, then re-insert the selected block at the right position among
    // the unselected items.
    final selected = <T>[];
    final unselected = <T>[];
    // Track how many unselected items live strictly before the drop target.
    // `newIndex` addresses the list *without* the dragged item, so each
    // unselected item is compared via its position in that same list (the
    // dragged item itself is selected here and never reaches this branch).
    var unselectedBeforeTarget = 0;
    for (var i = 0; i < source.length; i++) {
      final item = source[i];
      final inSelection = _selection.contains(refOf(item));
      if (inSelection) {
        selected.add(item);
      } else {
        final positionWithoutDragged = i < oldIndex ? i : i - 1;
        if (positionWithoutDragged < newIndex) unselectedBeforeTarget += 1;
        unselected.add(item);
      }
    }

    final insertIndex = unselectedBeforeTarget.clamp(0, unselected.length);
    final result = List<T>.from(unselected)..insertAll(insertIndex, selected);
    debugPrint(
      '[Reorder] multi: dragged ${selected.length} items, oldIndex=$oldIndex '
      'newIndex=$newIndex insertIndex=$insertIndex',
    );
    return result;
  }

  void _selectAll() {
    _selection.addAll([
      for (final f in _visibleFolders) _refForFolder(f),
      for (final n in _visibleNotes) _refForNote(n),
    ]);
  }

  /// Called when SliverReorderableList starts a drag. We only flip the multi
  /// flag if there's an actual multi-selection — single-item drags get the
  /// default behavior with no extra rebuilds.
  void _onReorderStart() {
    if (_selection.count > 1) {
      setState(() => _isDraggingMulti = true);
    }
  }

  void _onReorderEnd() {
    if (_isDraggingMulti) {
      setState(() => _isDraggingMulti = false);
    }
  }

  /// Decorates the dragged card with a count badge when the user is moving a
  /// multi-selection, so it's visually obvious that the whole batch will move
  /// even though only one card lifts off.
  Widget _buildReorderProxy(
    Widget child,
    Animation<double> animation,
    int selectionCount,
  ) {
    if (selectionCount <= 1) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: 0,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$selectionCount',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _moveSelected() async {
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;
    await MoveCoordinator.moveItems(context, items: items);
    if (mounted) {
      _selection.clear();
      _loadData();
    }
  }

  /// Multi-select export: ask for the note format, then ship the whole
  /// selection (notes + folders) through the bloc as a single zip. Folders
  /// are zipped recursively; loose notes land at the archive root. Selection
  /// stays active so the user can retry on failure; on success the listener
  /// shows the share sheet and we clear it.
  Future<void> _shareSelected() async {
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final hasNotes = items.any((r) => r.kind == MovableItemKind.note);

    // Format only matters when at least one note will be written. If the
    // selection is folders-only, default to JSON for round-trip fidelity
    // and skip the prompt entirely.
    ExportFormat format = ExportFormat.json;
    if (hasNotes) {
      final picked = await AppDialogs.choose<ExportFormat>(
        context,
        title: l10n.chooseExportFormat,
        options: [
          (
            value: ExportFormat.markdown,
            label: l10n.exportAsMarkdown,
            icon: Icons.description_rounded,
          ),
          (
            value: ExportFormat.json,
            label: l10n.exportAsJson,
            icon: Icons.data_object_rounded,
          ),
          (
            value: ExportFormat.text,
            label: l10n.exportAsText,
            icon: Icons.text_snippet_rounded,
          ),
        ],
      );
      if (picked == null || !mounted) return;
      format = picked;
    }

    final noteIds = <String>{};
    final folderIds = <String>{};
    for (final ref in items) {
      if (ref.kind == MovableItemKind.note) {
        noteIds.add(ref.id);
      } else {
        folderIds.add(ref.id);
      }
    }

    context.read<ImportExportBloc>().add(
      ExportItemsRequested(
        noteIds: noteIds,
        folderIds: folderIds,
        noteFormat: format,
        share: true,
      ),
    );
    _selection.clear();
  }

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;

    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.delete,
      content: l10n.deleteSelectedConfirm(items.length),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final folderIds = <String>[];
    final noteIds = <String>[];
    for (final ref in items) {
      (ref.kind == MovableItemKind.folder ? folderIds : noteIds).add(ref.id);
    }

    if (folderIds.isNotEmpty) {
      context.read<OptimizedFolderBloc>().add(
        DeleteOptimizedFolders(folderIds: folderIds, parentId: widget.folderId),
      );
    }
    if (noteIds.isNotEmpty) {
      context.read<OptimizedNoteBloc>().add(DeleteOptimizedNotes(noteIds));
    }
    _selection.clear();
  }

  Future<void> _onDropOnFolder(
    Folder targetFolder,
    Set<MovableItemRef> dropped,
  ) async {
    // Filter out the target itself if it was selected; can't move a folder into itself.
    final filtered = dropped
        .where(
          (r) => !(r.kind == MovableItemKind.folder && r.id == targetFolder.id),
        )
        .toList(growable: false);
    if (filtered.isEmpty) return;
    await MoveCoordinator.moveItemsTo(
      context,
      items: filtered,
      targetParentId: targetFolder.id,
    );
    if (mounted) {
      _selection.clear();
      _loadData();
    }
  }

  void _preloadNoteContent(List<String> noteIds) {
    context.read<OptimizedNoteBloc>().add(PreloadNoteContent(noteIds));
  }

  void _loadData() {
    context.read<OptimizedFolderBloc>().add(
      LoadFoldersPaginated(
        parentId: widget.folderId,
        sortOrder: _foldersSortOrder,
      ),
    );
    if (widget.folderId != null) {
      context.read<OptimizedNoteBloc>().add(
        LoadNotesPaginated(
          folderId: widget.folderId,
          sortOrder: _notesSortOrder,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRootPage = widget.folderId == null;
    final isSelecting = _selection.isActive;
    final colorScheme = Theme.of(context).colorScheme;

    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: colorScheme.pageGround,
      drawer: isSelecting || _searching ? null : const AppDrawer(),
      drawerEnableOpenDragGesture:
          !isSelecting && !_searching && _folderSwipeEnabled,
      appBar: isSelecting
          ? SelectionAppBar(
              count: _selection.count,
              allSelected:
                  _selection.count > 0 &&
                  _selection.count ==
                      _visibleFolders.length + _visibleNotes.length,
              onCancel: _selection.clear,
              onSelectAll: _selectAll,
              onDeselectAll: _selection.deselectAll,
            )
          : null,
      body: RefreshIndicator(
        // Without this the spinner would drop from the very top of the body,
        // which the expanded bar covers.
        edgeOffset: isSelecting || _searching
            ? 0
            : MediaQuery.paddingOf(context).top +
                  FolderSliverAppBar.expandedHeightFor(isRootPage),
        notificationPredicate: (notification) =>
            !_searching && defaultScrollNotificationPredicate(notification),
        onRefresh: () async {
          _loadData();
        },
        child: BlocBuilder<SearchBloc, SearchState>(
          bloc: _search.bloc,
          buildWhen: (previous, current) => _searching,
          builder: (context, searchState) => CustomScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            slivers: _searching
                ? [
                    SearchFieldAppBar(
                      search: _search,
                      hintText: isRootPage
                          ? AppLocalizations.of(context)!.searchAll
                          : AppLocalizations.of(context)!.searchInFolder,
                      selectedScope: searchState.scope,
                      folderScope: _folderScope,
                      onLeave: _exitSearch,
                    ),
                    ...SearchSurface.resultSlivers(context, searchState),
                  ]
                : [
                    if (!isSelecting)
                      FolderSliverAppBar(
                        title: isRootPage
                            ? AppLocalizations.of(context)!.folders
                            : (_folder?.name ?? widget.title),
                        isRootPage: isRootPage,
                        eyebrow: isRootPage ? null : _eyebrowLabel(context),
                        onShowAncestors: isRootPage ? null : _showAncestorMenu,
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.search),
                            tooltip: widget.folderId != null
                                ? AppLocalizations.of(context)!.searchInFolder
                                : AppLocalizations.of(context)!.searchAll,
                            onPressed: _openSearch,
                          ),
                          StreamBuilder<int>(
                            stream: GetIt.I<MoveHistoryService>().changes,
                            initialData:
                                GetIt.I<MoveHistoryService>().undoableCount,
                            builder: (context, snapshot) => FolderOverflowMenu(
                              isRootPage: isRootPage,
                              sortLabel: _sortLabel(
                                AppLocalizations.of(context)!,
                              ),
                              moveHistoryCount: snapshot.data ?? 0,
                              onSortBy: _showQuickSortOptions,
                              onSelect: _selection.activate,
                              onMoveHistory: () =>
                                  showMoveHistorySheet(context),
                              onImport: _pickAndImport,
                              onSettings: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              onRenameFolder: isRootPage
                                  ? null
                                  : _renameCurrentFolder,
                              onMoveFolder: isRootPage
                                  ? null
                                  : _moveCurrentFolder,
                              onShareFolder: isRootPage
                                  ? null
                                  : _shareCurrentFolder,
                              onDeleteFolder: isRootPage
                                  ? null
                                  : _deleteCurrentFolder,
                            ),
                          ),
                        ],
                      ),
                    ..._buildContentSlivers(isSelecting: isSelecting),
                    _buildEmptyStateSection(),
                  ],
          ),
        ),
      ),
      bottomNavigationBar: isSelecting
          ? SelectionActionBar(
              count: _selection.count,
              onMove: _moveSelected,
              onShare: _shareSelected,
              onDelete: _deleteSelected,
            )
          : _searching
          ? null
          : _buildBottomBar(context, isRootPage: isRootPage),
    );

    return BlocProvider<SearchBloc>.value(
      value: _search.bloc,
      child: _wrapWithImportExportListener(
        PopScope(
          canPop: !_backIsHandled(isRootPage: isRootPage),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _onBackIntercepted();
          },
          child: scaffold,
        ),
      ),
    );
  }

  /// Whether Back means something on this page before it means leaving it.
  ///
  /// There is exactly one [PopScope] on the browser and deliberately not one
  /// per mode: a route calls **every** registered `PopEntry`'s callback, so
  /// nesting them would run two handlers for a single gesture, and swapping
  /// between sibling ones changes the tree shape above the [Scaffold] —
  /// which rebuilds it and takes the scroll position with it.
  bool _backIsHandled({required bool isRootPage}) {
    if (_selection.isActive || _searching) return true;
    return !isRootPage && _folderSwipeEnabled;
  }

  /// The three meanings of Back, in priority order: leave selection, leave
  /// search, and only once neither is up the nested-folder case — the one
  /// that exists so the swipe-back gesture cannot steal the drawer's edge
  /// drag.
  void _onBackIntercepted() {
    if (_selection.isActive) {
      _selection.clear();
      return;
    }
    if (_searching) {
      _exitSearch();
      return;
    }
    AppNavigator.pop(context);
  }

  /// The create bar that replaced the floating action button and its sheet.
  ///
  /// One tap per action instead of two, and the row that used to be hidden
  /// behind the `+` is now readable at a glance: what is here, and what the
  /// two buttons will add to it. The second button is Import at the root,
  /// where a note has no folder to live in.
  ///
  /// Both buttons cluster at the left behind [RowMetrics.bottomBarInset] so
  /// one hand reaches them; the count still rides the bar's own centre line,
  /// held clear of the buttons by symmetric padding rather than by a slot,
  /// and truncated instead of ever running under them.
  ///
  /// The padding is `max(viewInsets, viewPadding)` on purpose: either alone
  /// leaves the bar under the keyboard or under the gesture bar.
  Widget _buildBottomBar(BuildContext context, {required bool isRootPage}) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return Material(
      color: colorScheme.rowGroup,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          height: RowMetrics.bottomBarHeight,
          foregroundDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.rowDivider, width: 1),
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: RowMetrics.bottomBarInset),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _barButton(
                      icon: Icons.create_new_folder_outlined,
                      tooltip: l10n.newFolder,
                      onPressed: _showCreateFolderDialog,
                    ),
                    if (isRootPage)
                      _barButton(
                        icon: Icons.file_download_outlined,
                        tooltip: l10n.importNoteOrFolder,
                        onPressed: _pickAndImport,
                      )
                    else
                      _barButton(
                        icon: Icons.note_add_outlined,
                        tooltip: l10n.newNote,
                        onPressed: _createNewNote,
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal:
                          RowMetrics.bottomBarInset +
                          2 * RowMetrics.bottomBarButtonSize,
                    ),
                    child: Center(child: _buildCountLabel(context)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One of the create bar's two buttons: a 54 dp target around a 28 dp
  /// glyph in the page's one accent, sized explicitly because the default
  /// [IconButton] target is taller than the 60 dp bar it sits in.
  Widget _barButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon),
      iconSize: RowMetrics.bottomBarGlyphSize,
      color: Theme.of(context).colorScheme.primary,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: RowMetrics.bottomBarButtonSize,
        height: RowMetrics.bottomBarButtonSize,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  /// What this folder holds, read off the same paginated states the list
  /// renders from — the totals they already carry, so the bar costs no query
  /// of its own. Its own builders, because the bar is constructed before the
  /// list's and would otherwise trail it by a frame.
  Widget _buildCountLabel(BuildContext context) {
    return BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
      buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
      builder: (context, folderState) {
        return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          buildWhen: NoteBlocFilters.forFolder(widget.folderId),
          builder: (context, noteState) {
            final folderCount = folderState is OptimizedFolderLoaded
                ? folderState.paginatedFolders.totalCount
                : 0;
            final noteCount = _noteTotalCount(noteState);
            final label = _countText(
              AppLocalizations.of(context)!,
              folderCount: folderCount,
              noteCount: noteCount,
            );
            if (label.isEmpty) return const SizedBox.shrink();
            return Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: RowMetrics.bottomBarCountFontSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
          },
        );
      },
    );
  }

  int _noteTotalCount(OptimizedNoteState state) {
    if (widget.folderId == null) return 0;
    if (state is OptimizedNoteLoaded) return state.paginatedNotes.totalCount;
    if (state is OptimizedNoteContentLoaded &&
        state.previousPaginatedNotes != null) {
      return state.previousPaginatedNotes!.totalCount;
    }
    return 0;
  }

  /// "3 folders, 5 notes", or whichever half is non-empty. Two plural keys
  /// plus a joiner rather than one nested-plural message, so each half stays
  /// a translatable sentence in its own right.
  String _countText(
    AppLocalizations l10n, {
    required int folderCount,
    required int noteCount,
  }) {
    if (folderCount > 0 && noteCount > 0) {
      return l10n.folderAndNoteCount(
        l10n.folderCountLabel(folderCount),
        l10n.noteCountLabel(noteCount),
      );
    }
    if (folderCount > 0) return l10n.folderCountLabel(folderCount);
    if (noteCount > 0) return l10n.noteCountLabel(noteCount);
    return '';
  }

  /// Listens to [ImportExportBloc] from anywhere in the page subtree and
  /// surfaces a single loading dialog plus snackbars for export/import
  /// success and failure. The note and folder cards just dispatch events;
  /// all UI feedback funnels through here so behavior stays consistent
  /// whether the trigger came from a folder card or a note card.
  Widget _wrapWithImportExportListener(Widget child) {
    return BlocListener<ImportExportBloc, ImportExportState>(
      listener: _onImportExportState,
      child: child,
    );
  }

  void _onImportExportState(BuildContext context, ImportExportState state) {
    final l10n = AppLocalizations.of(context)!;
    if (state is ImportExportInProgress) {
      if (_ioLoadingDialogOpen) return;
      _ioLoadingDialogOpen = true;
      AppDialogs.showLoading(
        context,
        message: _progressMessage(state.operation, l10n),
      );
      return;
    }

    if (state is ImportExportInitial) return;

    // Terminal state: pop the loading dialog once if it's still up.
    if (_ioLoadingDialogOpen) {
      _ioLoadingDialogOpen = false;
      AppNavigator.pop(context);
    }

    if (state is ImportExportFailure) {
      CustomSnackbar.showError(
        context,
        '${_failureMessage(state.operation, l10n)}: ${state.message}',
      );
    } else if (state is ImportExportImportSuccess) {
      CustomSnackbar.showSuccess(
        context,
        l10n.importedSummary(
          state.result.foldersImported,
          state.result.notesImported,
        ),
      );
      // The import wrote new folders/notes; refresh the visible list so
      // the user sees them immediately.
      _loadData();
    }
    // Reset the bloc back to Initial so the next operation starts from a
    // clean slate (also so the next InProgress emission triggers).
    context.read<ImportExportBloc>().add(const ImportExportReset());
  }

  String _progressMessage(ImportExportOperation op, AppLocalizations l10n) {
    switch (op) {
      case ImportExportOperation.exportNote:
        return l10n.exportingNote;
      case ImportExportOperation.exportFolder:
        return l10n.exportingFolder;
      case ImportExportOperation.exportItems:
        return l10n.exportingSelection;
      case ImportExportOperation.exportCalendar:
        return l10n.exportingEvents;
      case ImportExportOperation.importFile:
      case ImportExportOperation.importArchive:
        return l10n.importingFile;
    }
  }

  String _failureMessage(ImportExportOperation op, AppLocalizations l10n) {
    switch (op) {
      case ImportExportOperation.exportNote:
        return l10n.noteExportError;
      case ImportExportOperation.exportFolder:
        return l10n.folderExportError;
      case ImportExportOperation.exportItems:
        return l10n.selectionExportError;
      case ImportExportOperation.exportCalendar:
        return l10n.eventsExportError;
      case ImportExportOperation.importFile:
      case ImportExportOperation.importArchive:
        return l10n.importFileError;
    }
  }

  void _showQuickSortOptions() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(l10n.sortFolders),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                AppNavigator.pop(context);
                _showFolderSortOptions();
              },
            ),
            if (widget.folderId != null)
              ListTile(
                leading: const Icon(Icons.note_outlined),
                title: Text(l10n.sortNotes),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  AppNavigator.pop(context);
                  _showNoteSortOptions();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showFolderSortOptions() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined),
                  const SizedBox(width: 12),
                  Text(
                    l10n.sortFolders,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha,
              title: '${l10n.sortByName} (A-Z)',
              isSelected: _foldersSortOrder == FoldersSortOrder.nameAsc,
              onTap: () {
                AppNavigator.pop(context);
                _sortFoldersBy(FoldersSortOrder.nameAsc);
              },
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha,
              title: '${l10n.sortByName} (Z-A)',
              isSelected: _foldersSortOrder == FoldersSortOrder.nameDesc,
              onTap: () {
                AppNavigator.pop(context);
                _sortFoldersBy(FoldersSortOrder.nameDesc);
              },
            ),
            _buildSortOption(
              icon: Icons.calendar_today,
              title: '${l10n.sortByCreated} (${l10n.descending})',
              isSelected: _foldersSortOrder == FoldersSortOrder.createdDesc,
              onTap: () {
                AppNavigator.pop(context);
                _sortFoldersBy(FoldersSortOrder.createdDesc);
              },
            ),
            _buildSortOption(
              icon: Icons.calendar_today,
              title: '${l10n.sortByCreated} (${l10n.ascending})',
              isSelected: _foldersSortOrder == FoldersSortOrder.createdAsc,
              onTap: () {
                AppNavigator.pop(context);
                _sortFoldersBy(FoldersSortOrder.createdAsc);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteSortOptions() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.note_outlined),
                  const SizedBox(width: 12),
                  Text(
                    l10n.sortNotes,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha,
              title: '${l10n.sortByTitle} (A-Z)',
              isSelected: _notesSortOrder == NotesSortOrder.titleAsc,
              onTap: () {
                AppNavigator.pop(context);
                _sortNotesBy(NotesSortOrder.titleAsc);
              },
            ),
            _buildSortOption(
              icon: Icons.sort_by_alpha,
              title: '${l10n.sortByTitle} (Z-A)',
              isSelected: _notesSortOrder == NotesSortOrder.titleDesc,
              onTap: () {
                AppNavigator.pop(context);
                _sortNotesBy(NotesSortOrder.titleDesc);
              },
            ),
            _buildSortOption(
              icon: Icons.update,
              title: '${l10n.sortByUpdated} (${l10n.descending})',
              isSelected: _notesSortOrder == NotesSortOrder.updatedDesc,
              onTap: () {
                AppNavigator.pop(context);
                _sortNotesBy(NotesSortOrder.updatedDesc);
              },
            ),
            _buildSortOption(
              icon: Icons.update,
              title: '${l10n.sortByUpdated} (${l10n.ascending})',
              isSelected: _notesSortOrder == NotesSortOrder.updatedAsc,
              onTap: () {
                AppNavigator.pop(context);
                _sortNotesBy(NotesSortOrder.updatedAsc);
              },
            ),
            _buildSortOption(
              icon: Icons.calendar_today,
              title: '${l10n.sortByCreated} (${l10n.descending})',
              isSelected: _notesSortOrder == NotesSortOrder.createdDesc,
              onTap: () {
                AppNavigator.pop(context);
                _sortNotesBy(NotesSortOrder.createdDesc);
              },
            ),
            _buildSortOption(
              icon: Icons.calendar_today,
              title: '${l10n.sortByCreated} (${l10n.ascending})',
              isSelected: _notesSortOrder == NotesSortOrder.createdAsc,
              onTap: () {
                AppNavigator.pop(context);
                _sortNotesBy(NotesSortOrder.createdAsc);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: isSelected ? colorScheme.primary : null),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }

  void _sortFoldersBy(FoldersSortOrder order) {
    setState(() {
      _foldersSortOrder = order;
      _localMixed = null;
    });
    context.read<OptimizedFolderBloc>().add(
      LoadFoldersPaginated(parentId: widget.folderId, sortOrder: order),
    );
    // Persist sort preference
    if (widget.folderId != null) {
      _folderStorageService.updateFolderSortPreferences(
        folderId: widget.folderId!,
        subfolderSortOrder: order.name,
      );
    }
  }

  void _sortNotesBy(NotesSortOrder order) {
    setState(() {
      _notesSortOrder = order;
      _localMixed = null;
    });
    context.read<OptimizedNoteBloc>().add(
      LoadNotesPaginated(folderId: widget.folderId, sortOrder: order),
    );
    // Persist sort preference
    if (widget.folderId != null) {
      _folderStorageService.updateFolderSortPreferences(
        folderId: widget.folderId!,
        noteSortOrder: order.name,
      );
    }
  }

  // ─── This folder's own actions (app-bar overflow menu) ──────────────────

  /// The active ordering, for the menu's sort row. A folder's notes are what
  /// the user reorders; the root has none, so it reports its folder order.
  String _sortLabel(AppLocalizations l10n) {
    if (widget.folderId == null) {
      return switch (_foldersSortOrder) {
        FoldersSortOrder.nameAsc ||
        FoldersSortOrder.nameDesc => l10n.sortByName,
        FoldersSortOrder.createdAsc ||
        FoldersSortOrder.createdDesc => l10n.sortByCreated,
        FoldersSortOrder.positionAsc ||
        FoldersSortOrder.positionDesc => l10n.sortByCustom,
      };
    }
    return switch (_notesSortOrder) {
      NotesSortOrder.updatedAsc ||
      NotesSortOrder.updatedDesc => l10n.sortByUpdated,
      NotesSortOrder.createdAsc ||
      NotesSortOrder.createdDesc => l10n.sortByCreated,
      NotesSortOrder.titleAsc || NotesSortOrder.titleDesc => l10n.sortByTitle,
      NotesSortOrder.positionAsc ||
      NotesSortOrder.positionDesc => l10n.sortByCustom,
    };
  }

  String? _eyebrowLabel(BuildContext context) {
    final ancestors = _ancestors;
    if (ancestors == null) return null;
    if (ancestors.isEmpty) return AppLocalizations.of(context)!.folders;
    return ancestors.last.name;
  }

  void _showAncestorMenu(BuildContext anchorContext) {
    final ancestors = _ancestors;
    if (ancestors == null) return;
    showFolderAncestorMenu(
      anchorContext,
      ancestors: ancestors,
      rootLabel: AppLocalizations.of(context)!.folders,
      onSelected: (folder) {
        if (!mounted) return;
        AppNavigator.popToAncestor(
          context,
          folderId: folder?.id,
          title: folder?.name,
        );
      },
    );
  }

  Future<void> _renameCurrentFolder() async {
    final folder = _folder;
    if (folder == null) return;
    final l10n = AppLocalizations.of(context)!;
    final name = await AppDialogs.textInput(
      context,
      title: l10n.renameFolder,
      hintText: l10n.enterNewName,
      initialValue: folder.name,
    );
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == folder.name.trim().toLowerCase()) {
      return;
    }
    final exists = await _folderStorageService.folderNameExistsInParent(
      parentId: folder.parentId,
      name: trimmed,
      excludeId: folder.id,
    );
    if (!mounted) return;
    if (exists) {
      CustomSnackbar.showError(context, l10n.folderNameAlreadyExists(trimmed));
      return;
    }
    context.read<OptimizedFolderBloc>().add(
      UpdateOptimizedFolder(folderId: folder.id, name: trimmed),
    );
    setState(() => _folder = folder.copyWith(name: trimmed));
  }

  Future<void> _moveCurrentFolder() async {
    final folder = _folder;
    if (folder == null) return;
    await MoveCoordinator.moveFolder(
      context,
      folder: folder,
      currentParentId: folder.parentId,
    );
    if (!mounted) return;
    final moved = await _folderStorageService.getFolderById(folder.id);
    if (!mounted || moved == null) return;
    setState(() => _folder = moved);
    await _loadAncestors();
  }

  void _shareCurrentFolder() {
    final folder = _folder;
    if (folder == null) return;
    context.read<ImportExportBloc>().add(
      ExportFolderRequested(folderId: folder.id, share: true),
    );
  }

  Future<void> _deleteCurrentFolder() async {
    final folder = _folder;
    if (folder == null) return;
    final l10n = AppLocalizations.of(context)!;
    AppDialogs.showLoading(context, message: l10n.loadingContent);
    final noteCount = await _folderStorageService.getNoteCountForDeletion(
      folder.id,
    );
    if (!mounted) return;
    AppNavigator.pop(context);

    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteFolder,
      content: noteCount > 0
          ? l10n.deleteFolderWithNotesConfirm(folder.name, noteCount)
          : l10n.deleteFolderConfirm(folder.name),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    context.read<OptimizedFolderBloc>().add(
      DeleteOptimizedFolder(folderId: folder.id, parentId: folder.parentId),
    );
    AppNavigator.pop(context);
  }

  // ─── Unified mixed (folders + notes) sliver ─────────────────────────────

  /// Top-level slivers list selector. The mixed sliver is the *only* visible
  /// list in both modes — it just toggles between a reorderable list (in
  /// selection mode) and an infinite-scroll list (otherwise), over the same
  /// rows in the same order, so nothing moves when selection starts.
  ///
  /// Ordering is grouped, not interleaved: every folder, then every note,
  /// each in its own sort order, with a section label above each group when
  /// both are present. The two `position` columns still share one index
  /// space, so a drag inside either group persists exactly as before — the
  /// cross-kind orderings that space could express are simply no longer
  /// drawn.
  List<Widget> _buildContentSlivers({required bool isSelecting}) {
    return [
      if (widget.folderId == null)
        _buildSmartRowsSliver(isSelecting: isSelecting),
      _buildMixedSliver(isSelecting: isSelecting),
    ];
  }

  /// The root's two ways into the notes underneath its folders: every note
  /// there is, and the handful touched most recently.
  ///
  /// They are their own group above the folders, not entries in the list: a
  /// smart row has no position, cannot be selected, renamed or dragged, and
  /// giving it a slot in the reorderable sliver would offer all four.
  ///
  /// Selection mode disables them where it used to drop them. Removing two
  /// rows and their label from above the list is a height the bar swap does
  /// not pay for, so the folders underneath jumped; dimmed and unreachable
  /// they hold their space and stay outside the reorderable sliver, which is
  /// what kept them unselectable in the first place.
  Widget _buildSmartRowsSliver({required bool isSelecting}) {
    final l10n = AppLocalizations.of(context)!;
    final count = _allNotesCount;
    final rows = Column(
      children: [
        _SmartRow(
          icon: Icons.description_outlined,
          label: l10n.allNotes,
          count: count,
          position: RowGroupPosition.first,
          onTap: () => AppNavigator.toAllNotes(context),
        ),
        _SmartRow(
          icon: Icons.schedule_outlined,
          label: l10n.recent,
          position: RowGroupPosition.last,
          onTap: () => AppNavigator.toRecentNotes(context),
        ),
      ],
    );
    return SliverToBoxAdapter(
      child: isSelecting
          ? ExcludeSemantics(
              child: IgnorePointer(child: Opacity(opacity: 0.38, child: rows)),
            )
          : rows,
    );
  }

  MovableItemRef _refForContentItem(ContentItem item) => switch (item) {
    FolderItem(:final folder) => _refForFolder(folder),
    NoteItem(:final metadata) => _refForNote(metadata),
  };

  Widget _buildMixedSliver({required bool isSelecting}) {
    return BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
      buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
      builder: (context, folderState) {
        return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          buildWhen: NoteBlocFilters.forFolder(widget.folderId),
          builder: (context, noteState) {
            // Kick the bloc on cold-start only. After the first load, the
            // bloc transitions through Loading on every refresh / sort
            // change; we deliberately do NOT clear our cached [_localMixed]
            // in that window so the UI keeps showing the last known list
            // instead of flashing to a spinner.
            if (folderState is OptimizedFolderInitial) {
              context.read<OptimizedFolderBloc>().add(
                LoadFoldersPaginated(
                  parentId: widget.folderId,
                  sortOrder: _foldersSortOrder,
                ),
              );
            }

            // Surface errors prominently — but only if we have no prior data
            // to show. With cached data, a transient error mid-refresh would
            // wipe the screen which is worse UX than just keeping the stale
            // list visible.
            if (folderState is OptimizedFolderError && _localMixed == null) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.error(folderState.message),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              );
            }

            final folders = folderState is OptimizedFolderLoaded
                ? folderState.paginatedFolders.folders
                : const <Folder>[];
            final notes = widget.folderId == null
                ? const <NoteMetadata>[]
                : (NoteStateHelper.getNotesForFolder(
                        noteState,
                        widget.folderId,
                      ) ??
                      const <NoteMetadata>[]);

            // Detect the "this state has no fresh data" case (Loading,
            // Initial, Error). Without this, a reorder dispatch that
            // triggers Loading would feed empty lists into mergeByPosition
            // and we would render an empty sliver for one frame — exactly
            // the white flash this method exists to prevent.
            final folderHasData = folderState is OptimizedFolderLoaded;
            final noteHasData =
                widget.folderId == null ||
                noteState is OptimizedNoteLoaded ||
                noteState is OptimizedNoteContentLoaded;

            if (!folderHasData || !noteHasData) {
              // No fresh data this build. If we have a previous render,
              // reuse it verbatim; otherwise show the cold-start spinner.
              if (_localMixed != null && _localMixed!.isNotEmpty) {
                return _buildMixedListFromDisplay(
                  display: _localMixed!,
                  isSelecting: isSelecting,
                  hasMore: false,
                  isLoadingMore: false,
                );
              }
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            // Keep the SelectAll source-of-truth in sync with what's visible.
            _visibleFolders = folders;
            _visibleNotes = notes;
            _loadFolderCounts([for (final f in folders) f.id]);

            // Kick off a small content preload for the first few notes so
            // tapping in feels instant. Was previously done by the notes
            // section; keep behavior parity here.
            if (notes.isNotEmpty) {
              _preloadNoteContent(notes.take(3).map((n) => n.id).toList());
            }

            if (folders.isEmpty && notes.isEmpty) {
              _localMixed = null;
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            final grouped = groupFoldersThenNotes(
              folders: folders,
              notes: notes,
            );
            final display = _syncLocal<ContentItem>(
              _localMixed,
              grouped,
              (i) => i.id,
            );
            _localMixed = display;

            final hasMore = widget.folderId != null
                ? NoteStateHelper.hasMoreForFolder(noteState, widget.folderId)
                : false;
            final isLoadingMore = noteState is OptimizedNoteLoaded
                ? NoteStateHelper.isLoadingMore(noteState)
                : false;

            return _buildMixedListFromDisplay(
              display: display,
              isSelecting: isSelecting,
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
            );
          },
        );
      },
    );
  }

  /// The flat row sequence for [items]: a section label above each group,
  /// then that group's rows carrying the corner and divider treatment that
  /// makes a run of them read as one card.
  ///
  /// Labels appear when both groups are present. A folder full of notes does
  /// not need to be told they are notes — except at the root, where the smart
  /// rows sit above and the label is what separates them from the folders
  /// rather than the folders from the notes, which is why the root always
  /// labels, selection mode included: the smart rows stay drawn there.
  List<_RowEntry> _buildEntries(
    List<ContentItem> items,
    AppLocalizations l10n,
  ) {
    final folders = [
      for (final item in items)
        if (item is FolderItem) item,
    ];
    final notes = [
      for (final item in items)
        if (item is NoteItem) item,
    ];
    final labelled =
        (folders.isNotEmpty && notes.isNotEmpty) || widget.folderId == null;
    final entries = <_RowEntry>[];

    void addGroup(List<ContentItem> group, String label) {
      if (group.isEmpty) return;
      if (labelled) entries.add(_SectionEntry(label));
      for (var i = 0; i < group.length; i++) {
        entries.add(
          _ItemEntry(group[i], _positionIn(index: i, length: group.length)),
        );
      }
    }

    addGroup(folders, l10n.folders);
    addGroup(notes, l10n.notes);
    return entries;
  }

  RowGroupPosition _positionIn({required int index, required int length}) {
    if (length == 1) return RowGroupPosition.single;
    if (index == 0) return RowGroupPosition.first;
    if (index == length - 1) return RowGroupPosition.last;
    return RowGroupPosition.middle;
  }

  /// Render the actual sliver (reorderable in selection mode, otherwise
  /// infinite-scroll) from a final [display] list. Extracted so the
  /// "reuse cached list during a transient Loading state" path and the
  /// fresh-data path produce the same widget tree (no re-creation jank).
  ///
  /// There is exactly one reorderable sliver over the whole sequence,
  /// headers included: two would let a drag leave one and never arrive in
  /// the other. Headers carry no drag listener, so they cannot be lifted,
  /// and [_onReorderEntry] refuses to let a row land outside its own group.
  Widget _buildMixedListFromDisplay({
    required List<ContentItem> display,
    required bool isSelecting,
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    final entries = _buildEntries(display, AppLocalizations.of(context)!);
    _entries = entries;

    if (isSelecting) {
      return SliverReorderableList(
        itemCount: entries.length,
        proxyDecorator: (child, index, animation) =>
            _buildReorderProxy(child, animation, _selection.count),
        onReorderStart: (_) => _onReorderStart(),
        onReorderEnd: (_) => _onReorderEnd(),
        onReorderItem: _onReorderEntry,
        itemBuilder: (context, index) =>
            _buildEntry(entries[index], index, isSelecting: true),
      );
    }

    return InfiniteScrollSliver<_RowEntry>(
      items: entries,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      controller: _scrollController,
      onLoadMore: () {
        context.read<OptimizedNoteBloc>().add(
          LoadMoreNotes(folderId: widget.folderId),
        );
      },
      itemBuilder: (context, entry, index) =>
          _buildEntry(entry, index, isSelecting: false),
    );
  }

  /// Single source of truth for rendering a row, used by both the reorderable
  /// and the infinite-scroll branches. [isSelecting] toggles the drag handle
  /// (`isReorderMode`) — outside of selection the rows show their menu.
  Widget _buildEntry(_RowEntry entry, int index, {required bool isSelecting}) {
    switch (entry) {
      case _SectionEntry(:final label):
        return KeyedSubtree(
          key: ValueKey('section:$label'),
          child: ContentSectionHeader(label: label),
        );
      case _ItemEntry(:final item, :final position):
        switch (item) {
          case FolderItem(:final folder):
            return FolderRow(
              key: ValueKey('folder:${folder.id}'),
              folder: folder,
              parentId: widget.folderId,
              noteCount: _folderNoteCounts[folder.id],
              groupPosition: position,
              onReturn: _loadData,
              isReorderMode: isSelecting,
              index: isSelecting ? index : null,
              isMultiDragging: _isDraggingMulti,
              selection: _selection,
              onLongPressItem: _onCardLongPress,
              onTapInSelection: _onCardTapInSelection,
              onAcceptDrop: _onDropOnFolder,
            );
          case NoteItem(:final metadata):
            return NoteRow(
              key: ValueKey('note:${metadata.id}'),
              metadata: metadata,
              folderId: widget.folderId!,
              groupPosition: position,
              showPreview: _showNotePreview,
              onReturn: _loadData,
              isReorderMode: isSelecting,
              index: isSelecting ? index : null,
              isMultiDragging: _isDraggingMulti,
              selection: _selection,
              onLongPressItem: _onCardLongPress,
              onTapInSelection: _onCardTapInSelection,
            );
        }
    }
  }

  /// Turns a drop on the flat row list into a reorder of the content items,
  /// clamped to the dragged row's own group.
  ///
  /// `onReorderItem` reports [newIndex] against the list with the dragged row
  /// already removed, so the group's bounds are measured there too: the
  /// insertion point may sit anywhere from the group's first row to just past
  /// its last. A drop aimed at a header, or across the boundary into the
  /// other group, lands at the nearest edge of the group it started in.
  void _onReorderEntry(int oldIndex, int newIndex) {
    final entries = _entries;
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final moved = entries[oldIndex];
    if (moved is! _ItemEntry) return;

    final remaining = [...entries]..removeAt(oldIndex);
    final kind = moved.item.kind;
    var lower = -1;
    var upper = -1;
    for (var i = 0; i < remaining.length; i++) {
      final entry = remaining[i];
      if (entry is _ItemEntry && entry.item.kind == kind) {
        if (lower < 0) lower = i;
        upper = i;
      }
    }
    final target = lower < 0 ? newIndex : newIndex.clamp(lower, upper + 1);

    final source = [
      for (final entry in entries)
        if (entry is _ItemEntry) entry.item,
    ];
    final contentOld = _contentIndexBefore(entries, oldIndex);
    final contentNew = _contentIndexBefore(remaining, target);
    if (contentOld >= source.length) return;

    final reordered = _applyMultiReorder<ContentItem>(
      source: source,
      oldIndex: contentOld,
      newIndex: contentNew,
      refOf: _refForContentItem,
    );
    _handleReorderMixed(regroupFoldersThenNotes(reordered));
  }

  int _contentIndexBefore(List<_RowEntry> entries, int rowIndex) {
    var count = 0;
    for (var i = 0; i < rowIndex && i < entries.length; i++) {
      if (entries[i] is _ItemEntry) count++;
    }
    return count;
  }

  /// Persist a unified folder+note ordering. Mirrors [_handleReorderFolders]:
  /// flips both per-kind sort orders to position-based (so the next refresh
  /// preserves what the user just did), persists the preference, then writes
  /// both tables via [MixedReorderService].
  void _handleReorderMixed(List<ContentItem> reordered) {
    debugPrint(
      '[Reorder] mixed: applying optimistic order '
      '${reordered.map((i) => '${i.kind.name}:${i.displayName('')}').toList()}',
    );
    setState(() {
      _localMixed = List<ContentItem>.from(reordered);
    });

    var sortChanged = false;
    if (_foldersSortOrder != FoldersSortOrder.positionAsc &&
        _foldersSortOrder != FoldersSortOrder.positionDesc) {
      _foldersSortOrder = FoldersSortOrder.positionAsc;
      sortChanged = true;
      context.read<OptimizedFolderBloc>().add(
        LoadFoldersPaginated(
          parentId: widget.folderId,
          sortOrder: FoldersSortOrder.positionAsc,
        ),
      );
    }
    if (widget.folderId != null &&
        _notesSortOrder != NotesSortOrder.positionAsc &&
        _notesSortOrder != NotesSortOrder.positionDesc) {
      _notesSortOrder = NotesSortOrder.positionAsc;
      sortChanged = true;
      context.read<OptimizedNoteBloc>().add(
        LoadNotesPaginated(
          folderId: widget.folderId,
          sortOrder: NotesSortOrder.positionAsc,
        ),
      );
    }
    if (sortChanged && widget.folderId != null) {
      _folderStorageService.updateFolderSortPreferences(
        folderId: widget.folderId!,
        subfolderSortOrder: _foldersSortOrder.name,
        noteSortOrder: _notesSortOrder.name,
      );
    }

    // Fire-and-forget: the optimistic local list keeps the UI consistent
    // until the bloc refresh completes; errors are surfaced via the change
    // streams (which would re-emit and replace the local list).
    unawaited(
      _mixedReorderService.reorderMixed(
        parentId: widget.folderId,
        items: reordered,
      ),
    );
  }

  Widget _buildEmptyStateSection() {
    return BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
      buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
      builder: (context, folderState) {
        return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          buildWhen: NoteBlocFilters.forEmptyState(widget.folderId),
          builder: (context, noteState) {
            bool foldersEmpty = true;
            if (folderState is OptimizedFolderLoaded) {
              foldersEmpty = folderState.paginatedFolders.folders.isEmpty;
            }

            bool notesEmpty = true;
            if (widget.folderId != null) {
              final notes = NoteStateHelper.getNotesForFolder(
                noteState,
                widget.folderId,
              );
              notesEmpty = notes == null || notes.isEmpty;
            }

            if (foldersEmpty &&
                notesEmpty &&
                folderState is OptimizedFolderLoaded &&
                (widget.folderId == null ||
                    noteState is OptimizedNoteLoaded ||
                    noteState is OptimizedNoteContentLoaded)) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.folderId != null
                              ? Icons.note_add
                              : Icons.folder_open,
                          size: 80,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.folderId != null
                              ? AppLocalizations.of(context)!.emptyNotesHint
                              : AppLocalizations.of(context)!.emptyFoldersHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)!.createFromBarBelow,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return const SliverToBoxAdapter(child: SizedBox.shrink());
          },
        );
      },
    );
  }

  /// Opens the platform file picker, then dispatches the appropriate
  /// import event. Routing by extension keeps the UI thin: the bloc and
  /// service decide how to actually parse the file.
  Future<void> _pickAndImport() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'json', 'md', 'txt'],
    );
    if (result == null) return;
    final path = result.path;
    if (path == null || !mounted) return;
    final isArchive = path.toLowerCase().endsWith('.zip');
    final bloc = context.read<ImportExportBloc>();
    if (isArchive) {
      bloc.add(
        ImportArchiveRequested(
          filePath: path,
          targetParentFolderId: widget.folderId,
        ),
      );
    } else {
      // Importing a single note requires a destination folder.
      if (widget.folderId == null) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.importFileError,
        );
        return;
      }
      bloc.add(
        ImportFileRequested(filePath: path, targetFolderId: widget.folderId!),
      );
    }
  }

  void _showCreateFolderDialog() async {
    final name = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.createFolder,
      hintText: AppLocalizations.of(context)!.enterFolderName,
      confirmText: AppLocalizations.of(context)!.create,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    final trimmed = name.trim();
    // Per-parent name uniqueness: prevent two sibling folders sharing a
    // name. Comparison is case-insensitive + whitespace-trimmed.
    final exists = await _folderStorageService.folderNameExistsInParent(
      parentId: widget.folderId,
      name: trimmed,
    );
    if (!mounted) return;
    if (exists) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.folderNameAlreadyExists(trimmed),
      );
      return;
    }
    context.read<OptimizedFolderBloc>().add(
      CreateOptimizedFolder(name: trimmed, parentId: widget.folderId),
    );
  }

  void _createNewNote() {
    AppNavigator.toNoteEditor(context, folderId: widget.folderId!).then((_) {
      if (mounted) {
        _loadData();
      }
    });
  }
}
