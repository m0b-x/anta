import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
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
import '../controllers/selection_controller.dart';
import '../models/content_item.dart';
import '../models/export_format.dart';
import '../models/folder.dart';
import '../models/folder_change.dart';
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../repositories/note_repository.dart';
import '../services/folder_storage_service.dart';
import '../services/mixed_reorder_service.dart';
import '../services/move_coordinator.dart';
import '../services/move_history_service.dart';
import '../services/note_storage_service.dart';
import '../services/settings_service.dart';
import '../widgets/infinite_scroll_list.dart';
import '../widgets/app_drawer.dart';
import '../widgets/selection_action_bar.dart';
import '../widgets/selection_app_bar.dart';
import '../widgets/unified_app_bars.dart';
import '../utils/bloc_helpers.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../constants/app_colors.dart';
import '../constants/folder_card_action.dart';
import '../constants/note_card_action.dart';
import '../services/app_navigator.dart';
import '../services/drawer_host_registry.dart';
import '../widgets/move_history_sheet.dart';

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

class _OptimizedFolderContentPageState
    extends State<OptimizedFolderContentPage> {
  /// Lets a restored settings page raise this page's drawer when it is popped
  /// — see [DrawerHostRegistry].
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  NotesSortOrder _notesSortOrder = NotesSortOrder.updatedDesc;
  FoldersSortOrder _foldersSortOrder = FoldersSortOrder.nameAsc;
  bool _folderSwipeEnabled = true;
  bool _isSortSheetOpen = false;

  // Per-page selection state. Long-press a card to enter selection mode,
  // tap to toggle, then act on the whole batch (move, delete, drag-and-drop).
  late final SelectionController _selection = SelectionController();
  StreamSubscription<Set<MovableItemRef>>? _selectionSub;

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

  NoteRepository get _noteRepository => GetIt.I<NoteRepository>();
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
        setState(() {});
      }
    });
    _loadSettings();
    _loadSortPreferencesAndData();
  }

  Future<void> _loadSortPreferencesAndData() async {
    // Load sort preferences from DB for this folder
    if (widget.folderId != null) {
      final folder = await _folderStorageService.getFolderById(
        widget.folderId!,
      );
      if (folder != null && mounted) {
        setState(() {
          _notesSortOrder = _parseNotesSortOrder(folder.noteSortOrder);
          _foldersSortOrder = _parseFoldersSortOrder(folder.subfolderSortOrder);
        });
      }
    }
    _loadData();
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

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final folderSwipe = await settings.getFolderSwipeEnabled();
    if (mounted) {
      setState(() {
        _folderSwipeEnabled = folderSwipe;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    FocusManager.instance.primaryFocus?.unfocus();
    _loadSettings();
  }

  @override
  void dispose() {
    DrawerHostRegistry.unregister(_scaffoldKey);
    _selectionSub?.cancel();
    _selection.dispose();
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
    for (final f in _visibleFolders) {
      _selection.add(_refForFolder(f));
    }
    for (final n in _visibleNotes) {
      _selection.add(_refForNote(n));
    }
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

    for (final ref in items) {
      if (ref.kind == MovableItemKind.folder) {
        if (!mounted) return;
        context.read<OptimizedFolderBloc>().add(
          DeleteOptimizedFolder(folderId: ref.id, parentId: widget.folderId),
        );
      } else {
        if (!mounted) return;
        context.read<OptimizedNoteBloc>().add(DeleteOptimizedNote(ref.id));
      }
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
    _noteRepository.preloadContent(noteIds);
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

    final scaffold = Scaffold(
      key: _scaffoldKey,
      drawer: isSelecting ? null : const AppDrawer(),
      drawerEnableOpenDragGesture: !isSelecting && _folderSwipeEnabled,
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
          : FolderAppBar(
              title: widget.title,
              isRootPage: isRootPage,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: widget.folderId != null
                      ? AppLocalizations.of(context)!.searchInFolder
                      : AppLocalizations.of(context)!.searchAll,
                  onPressed: () {
                    AppNavigator.toSearch(
                      context,
                      folderId: widget.folderId,
                    ).then((_) {
                      if (mounted) {
                        _loadData();
                      }
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.sort),
                  tooltip: AppLocalizations.of(context)!.sortBy,
                  onPressed: _showQuickSortOptions,
                ),
                StreamBuilder<int>(
                  stream: GetIt.I<MoveHistoryService>().changes,
                  initialData: GetIt.I<MoveHistoryService>().undoableCount,
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    return IconButton(
                      icon: Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: const Icon(Icons.history),
                      ),
                      tooltip: AppLocalizations.of(context)!.moveHistory,
                      onPressed: () => showMoveHistorySheet(context),
                    );
                  },
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadData();
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            ..._buildContentSlivers(isSelecting: isSelecting),
            _buildEmptyStateSection(),
          ],
        ),
      ),
      bottomNavigationBar: isSelecting
          ? SelectionActionBar(
              count: _selection.count,
              onMove: _moveSelected,
              onShare: _shareSelected,
              onDelete: _deleteSelected,
            )
          : null,
      floatingActionButton: isSelecting
          ? null
          : AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(bottom: _isSortSheetOpen ? 280 : 0),
              child: FloatingActionButton(
                onPressed: _showCreateOptions,
                backgroundColor: AppColors.isDarkMode(context)
                    ? Theme.of(context).colorScheme.surfaceContainerHigh
                    : null,
                foregroundColor: AppColors.isDarkMode(context)
                    ? Theme.of(context).colorScheme.onSurface
                    : null,
                child: const Icon(Icons.add),
              ),
            ),
    );

    // While in selection mode, intercept back to exit selection instead of
    // popping the route. Wraps the existing PopScope so it always gets first dibs.
    if (isSelecting) {
      return _wrapWithImportExportListener(
        PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _selection.clear();
          },
          child: scaffold,
        ),
      );
    }

    // Wrap with PopScope to disable iOS swipe-back gesture in subfolders
    // so that drawer swipe gesture works instead
    if (!isRootPage && _folderSwipeEnabled) {
      return _wrapWithImportExportListener(
        PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              AppNavigator.pop(context);
            }
          },
          child: scaffold,
        ),
      );
    }

    return _wrapWithImportExportListener(scaffold);
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
    setState(() => _isSortSheetOpen = true);
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
    ).whenComplete(() {
      if (mounted) setState(() => _isSortSheetOpen = false);
    });
  }

  void _showFolderSortOptions() {
    setState(() => _isSortSheetOpen = true);
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
    ).whenComplete(() {
      if (mounted) setState(() => _isSortSheetOpen = false);
    });
  }

  void _showNoteSortOptions() {
    setState(() => _isSortSheetOpen = true);
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
    ).whenComplete(() {
      if (mounted) setState(() => _isSortSheetOpen = false);
    });
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

  // ─── Unified mixed (folders + notes) sliver ─────────────────────────────

  /// Top-level slivers list selector. The mixed sliver is the *only* visible
  /// list in both modes — it just toggles between a reorderable list (in
  /// selection mode) and an infinite-scroll list (otherwise). Rendering the
  /// same merged ordering in both modes fixes the previous inconsistency
  /// where folders always appeared above notes outside of selection mode,
  /// hiding the user's manual cross-kind reorders.
  ///
  /// Default ordering (no manual reorder yet): each kind's `position` is
  /// dense within its own table, and [mergeByPosition] breaks ties in favor
  /// of folders, so legacy data and freshly-created items naturally show
  /// folders above notes. Once the user drags a note above a folder in
  /// selection mode, the explicit positions persist and that exact ordering
  /// is what the non-selection view also renders.
  List<Widget> _buildContentSlivers({required bool isSelecting}) {
    return [_buildMixedSliver(isSelecting: isSelecting)];
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
                      style: const TextStyle(color: Colors.red),
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

            final merged = mergeByPosition(folders: folders, notes: notes);
            final display = _syncLocal<ContentItem>(
              _localMixed,
              merged,
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

  /// Render the actual sliver (reorderable in selection mode, otherwise
  /// infinite-scroll) from a final [display] list. Extracted so the
  /// "reuse cached list during a transient Loading state" path and the
  /// fresh-data path produce the same widget tree (no re-creation jank).
  Widget _buildMixedListFromDisplay({
    required List<ContentItem> display,
    required bool isSelecting,
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    if (isSelecting) {
      return SliverReorderableList(
        itemCount: display.length,
        proxyDecorator: (child, index, animation) =>
            _buildReorderProxy(child, animation, _selection.count),
        onReorderStart: (_) => _onReorderStart(),
        onReorderEnd: (_) => _onReorderEnd(),
        onReorderItem: (oldIndex, newIndex) {
          final reordered = _applyMultiReorder<ContentItem>(
            source: display,
            oldIndex: oldIndex,
            newIndex: newIndex,
            refOf: _refForContentItem,
          );
          _handleReorderMixed(reordered);
        },
        itemBuilder: (context, index) =>
            _buildMixedItem(display[index], index, isSelecting: true),
      );
    }

    return InfiniteScrollSliver<ContentItem>(
      items: display,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      controller: _scrollController,
      onLoadMore: () {
        context.read<OptimizedNoteBloc>().add(
          LoadMoreNotes(folderId: widget.folderId),
        );
      },
      itemBuilder: (context, item, index) =>
          _buildMixedItem(item, index, isSelecting: false),
    );
  }

  /// Single source of truth for rendering a [ContentItem] inside the mixed
  /// sliver, used by both the reorderable and the infinite-scroll branches.
  /// [isSelecting] toggles the drag handle (`isReorderMode`) — outside of
  /// selection the cards show their normal trailing menu.
  Widget _buildMixedItem(
    ContentItem item,
    int index, {
    required bool isSelecting,
  }) {
    switch (item) {
      case FolderItem(:final folder):
        return _FolderCard(
          key: ValueKey('folder:${folder.id}'),
          folder: folder,
          parentId: widget.folderId,
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
        return _NoteCard(
          key: ValueKey('note:${metadata.id}'),
          metadata: metadata,
          folderId: widget.folderId!,
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
                          AppLocalizations.of(context)!.tapPlusToCreate,
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

  void _showCreateOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.folder,
                  color: AppColors.folderIcon(context),
                ),
                title: Text(AppLocalizations.of(context)!.createFolder),
                onTap: () {
                  AppNavigator.pop(bottomSheetContext);
                  _showCreateFolderDialog();
                },
              ),
              if (widget.folderId != null)
                ListTile(
                  leading: Icon(Icons.note, color: AppColors.noteIcon(context)),
                  title: Text(AppLocalizations.of(context)!.createNote),
                  onTap: () {
                    AppNavigator.pop(bottomSheetContext);
                    _createNewNote();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: Text(AppLocalizations.of(context)!.importNoteOrFolder),
                onTap: () {
                  AppNavigator.pop(bottomSheetContext);
                  _pickAndImport();
                },
              ),
            ],
          ),
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

class _FolderCard extends StatefulWidget {
  final Folder folder;
  final String? parentId;
  final VoidCallback onReturn;
  final bool isReorderMode;
  final int? index;
  // True while a multi-selection drag is in flight on the parent list. Used
  // to dim/scale this card if it is selected but not the lifted one, so the
  // user sees that the whole batch will follow.
  final bool isMultiDragging;

  // Selection-mode wiring. Optional so the card can be reused outside of
  // selection contexts in the future.
  final SelectionController? selection;
  final void Function(MovableItemRef ref)? onLongPressItem;
  final void Function(MovableItemRef ref)? onTapInSelection;
  final Future<void> Function(Folder target, Set<MovableItemRef> dropped)?
  onAcceptDrop;

  const _FolderCard({
    super.key,
    required this.folder,
    this.parentId,
    required this.onReturn,
    this.isReorderMode = false,
    this.index,
    this.isMultiDragging = false,
    this.selection,
    this.onLongPressItem,
    this.onTapInSelection,
    this.onAcceptDrop,
  });

  @override
  State<_FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<_FolderCard> {
  int? _subfolderCount;
  int? _noteCount;
  StreamSubscription<FolderChange>? _folderSub;
  StreamSubscription<NoteChange>? _noteSub;

  /// Debounce timer for `_loadCounts`. Bursts of folder/note changes
  /// (bulk move, cascade delete, batch reorder) can fire many events in
  /// quick succession; without coalescing, every visible card would issue
  /// 2 count queries per event. 120 ms is short enough that the count
  /// still updates before the user looks away from a single card, but
  /// long enough to collapse a burst into a single read.
  Timer? _countDebounce;
  static const _countDebounceDuration = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _subscribeToChanges();
  }

  @override
  void didUpdateWidget(covariant _FolderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.id != widget.folder.id) {
      _folderSub?.cancel();
      _noteSub?.cancel();
      _countDebounce?.cancel();
      _loadCounts();
      _subscribeToChanges();
    }
  }

  @override
  void dispose() {
    _folderSub?.cancel();
    _noteSub?.cancel();
    _countDebounce?.cancel();
    super.dispose();
  }

  void _subscribeToChanges() {
    final folderService = GetIt.I<FolderStorageService>();
    final noteService = GetIt.I<NoteStorageService>();
    _folderSub = folderService
        .changesForParent(widget.folder.id)
        .listen((_) => _scheduleLoadCounts());
    _noteSub = noteService
        .changesForFolder(widget.folder.id)
        .listen((_) => _scheduleLoadCounts());
  }

  /// Coalesce burst events into a single trailing-edge `_loadCounts` call.
  void _scheduleLoadCounts() {
    if (!mounted) return;
    _countDebounce?.cancel();
    _countDebounce = Timer(_countDebounceDuration, () {
      if (!mounted) return;
      _loadCounts();
    });
  }

  Future<void> _loadCounts() async {
    try {
      final folderService = GetIt.I<FolderStorageService>();
      final noteService = GetIt.I<NoteStorageService>();
      final results = await Future.wait([
        folderService.getSubfolderCount(widget.folder.id),
        noteService.getNoteCount(widget.folder.id),
      ]);
      if (mounted) {
        setState(() {
          _subfolderCount = results[0];
          _noteCount = results[1];
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[_FolderCard] Failed to load counts: $e\n$stackTrace');
    }
  }

  String? _buildCountText(AppLocalizations l10n) {
    if (_subfolderCount == null && _noteCount == null) return null;
    final parts = <String>[];
    final folders = _subfolderCount ?? 0;
    final notes = _noteCount ?? 0;
    if (folders > 0) parts.add('${l10n.folders}: $folders');
    if (notes > 0) parts.add('${l10n.notes}: $notes');
    if (parts.isEmpty) return null;
    return parts.join('  ·  ');
  }

  MovableItemRef get _ref => MovableItemRef(
    kind: MovableItemKind.folder,
    id: widget.folder.id,
    name: widget.folder.name,
    currentParentId: widget.parentId,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final countText = _buildCountText(l10n);
    final selection = widget.selection;
    final isSelecting = selection != null && selection.isActive;
    final isSelected = selection != null && selection.contains(_ref);
    final colorScheme = Theme.of(context).colorScheme;

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      child: ListTile(
        leading: isSelected
            ? Icon(Icons.check_circle, size: 40, color: colorScheme.primary)
            : Icon(
                Icons.folder,
                size: 40,
                color: AppColors.folderIcon(context),
              ),
        title: Text(
          widget.folder.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: countText != null
            ? Text(
                countText,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
            : null,
        trailing: widget.isReorderMode
            ? ReorderableDragStartListener(
                index: widget.index ?? 0,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, color: Colors.grey),
                ),
              )
            : isSelecting
            ? null
            : PopupMenuButton<FolderCardAction>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case FolderCardAction.rename:
                      _showRenameDialog(context);
                    case FolderCardAction.move:
                      _showMoveDialog(context);
                    case FolderCardAction.share:
                      _shareFolder(context);
                    case FolderCardAction.delete:
                      _confirmDelete(context);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: FolderCardAction.rename,
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 20),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.rename),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: FolderCardAction.move,
                    child: Row(
                      children: [
                        const Icon(Icons.drive_file_move_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.moveToFolder),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: FolderCardAction.share,
                    child: Row(
                      children: [
                        const Icon(Icons.share_rounded, size: 20),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.shareFolder),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: FolderCardAction.delete,
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 20, color: Colors.red),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)!.delete,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: isSelecting
            ? () => widget.onTapInSelection?.call(_ref)
            : () {
                AppNavigator.toFolder(
                  context,
                  folderId: widget.folder.id,
                  title: widget.folder.name,
                ).then((_) {
                  if (context.mounted) {
                    widget.onReturn();
                  }
                });
              },
        onLongPress: () {
          if (isSelecting) {
            widget.onTapInSelection?.call(_ref);
          } else if (widget.onLongPressItem != null) {
            widget.onLongPressItem!(_ref);
          } else {
            _showRenameDialog(context);
          }
        },
      ),
    );

    // Drag source: only when this card is itself selected, so the user
    // explicitly opted in via long-press.
    Widget result = card;
    if (isSelecting && isSelected) {
      result = LongPressDraggable<Set<MovableItemRef>>(
        data: selection.items,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          color: Colors.transparent,
          child: _DragFeedback(count: selection.count),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: card),
        child: result,
      );
    }

    // Drop target: any folder card during selection mode (except folders
    // that are themselves in the dragged set, but the page-level handler
    // already filters that out).
    if (widget.onAcceptDrop != null) {
      final child = result;
      result = DragTarget<Set<MovableItemRef>>(
        onWillAcceptWithDetails: (details) {
          // Don't highlight if dropping onto self.
          return !details.data.any(
            (r) => r.kind == MovableItemKind.folder && r.id == widget.folder.id,
          );
        },
        onAcceptWithDetails: (details) {
          widget.onAcceptDrop!(widget.folder, details.data);
        },
        builder: (context, candidate, rejected) {
          if (candidate.isNotEmpty) {
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            );
          }
          return child;
        },
      );
    }

    // Multi-drag visual: when a batch reorder is in flight and this card is
    // a passenger (selected but not the lifted one), dim & shrink slightly
    // so the user sees "this is going with the dragged card."
    if (widget.isMultiDragging && isSelected) {
      result = AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: 0.96,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: 0.55,
          child: result,
        ),
      );
    }

    return result;
  }

  void _showRenameDialog(BuildContext context) async {
    final name = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.renameFolder,
      hintText: AppLocalizations.of(context)!.enterNewName,
      initialValue: widget.folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;
    final trimmed = name.trim();
    // Skip the network roundtrip when nothing actually changed.
    if (trimmed.toLowerCase() == widget.folder.name.trim().toLowerCase()) {
      return;
    }
    final exists = await GetIt.I<FolderStorageService>()
        .folderNameExistsInParent(
          parentId: widget.parentId,
          name: trimmed,
          excludeId: widget.folder.id,
        );
    if (!context.mounted) return;
    if (exists) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.folderNameAlreadyExists(trimmed),
      );
      return;
    }
    context.read<OptimizedFolderBloc>().add(
      UpdateOptimizedFolder(folderId: widget.folder.id, name: trimmed),
    );
  }

  void _showMoveDialog(BuildContext context) {
    MoveCoordinator.moveFolder(
      context,
      folder: widget.folder,
      currentParentId: widget.parentId,
    );
  }

  void _shareFolder(BuildContext context) {
    context.read<ImportExportBloc>().add(
      ExportFolderRequested(folderId: widget.folder.id, share: true),
    );
  }

  void _confirmDelete(BuildContext context) async {
    AppDialogs.showLoading(
      context,
      message: AppLocalizations.of(context)!.loadingContent,
    );

    final folderService = GetIt.I<FolderStorageService>();
    final noteCount = await folderService.getNoteCountForDeletion(
      widget.folder.id,
    );

    if (!context.mounted) return;
    AppNavigator.pop(context);

    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.deleteFolder,
      content: noteCount > 0
          ? AppLocalizations.of(
              context,
            )!.deleteFolderWithNotesConfirm(widget.folder.name, noteCount)
          : AppLocalizations.of(
              context,
            )!.deleteFolderConfirm(widget.folder.name),
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    context.read<OptimizedFolderBloc>().add(
      DeleteOptimizedFolder(
        folderId: widget.folder.id,
        parentId: widget.parentId,
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final NoteMetadata metadata;
  final String folderId;
  final VoidCallback onReturn;
  final bool isReorderMode;
  final int? index;
  final bool isMultiDragging;

  // Selection-mode wiring.
  final SelectionController? selection;
  final void Function(MovableItemRef ref)? onLongPressItem;
  final void Function(MovableItemRef ref)? onTapInSelection;

  const _NoteCard({
    super.key,
    required this.metadata,
    required this.folderId,
    required this.onReturn,
    this.isReorderMode = false,
    this.index,
    this.isMultiDragging = false,
    this.selection,
    this.onLongPressItem,
    this.onTapInSelection,
  });

  MovableItemRef _refFor(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MovableItemRef(
      kind: MovableItemKind.note,
      id: metadata.id,
      name: metadata.title.isEmpty ? l10n.untitledNote : metadata.title,
      currentParentId: folderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = _refFor(context);
    final isSelecting = selection != null && selection!.isActive;
    final isSelected = selection != null && selection!.contains(ref);
    final colorScheme = Theme.of(context).colorScheme;

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      child: ListTile(
        leading: isSelected
            ? Icon(Icons.check_circle, size: 40, color: colorScheme.primary)
            : Stack(
                children: [
                  const Icon(Icons.note, size: 40, color: Colors.blue),
                  if (metadata.isCompressed)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(
                        Icons.compress,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
        title: Text(
          metadata.title.isEmpty
              ? AppLocalizations.of(context)!.untitledNote
              : metadata.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metadata.preview.isEmpty
                  ? AppLocalizations.of(context)!.emptyNote
                  : metadata.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _formatDate(metadata.updatedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatSize(metadata.contentLength),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: isReorderMode
            ? ReorderableDragStartListener(
                index: index ?? 0,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, color: Colors.grey),
                ),
              )
            : isSelecting
            ? null
            : PopupMenuButton<NoteCardAction>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case NoteCardAction.rename:
                      _showRenameDialog(context);
                    case NoteCardAction.move:
                      _showMoveDialog(context);
                    case NoteCardAction.share:
                      _showExportFormatDialog(context);
                    case NoteCardAction.delete:
                      _confirmDelete(context);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: NoteCardAction.rename,
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 20),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.rename),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: NoteCardAction.move,
                    child: Row(
                      children: [
                        const Icon(Icons.drive_file_move_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.moveToFolder),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: NoteCardAction.share,
                    child: Row(
                      children: [
                        const Icon(Icons.share, size: 20),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context)!.shareNote),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: NoteCardAction.delete,
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 20, color: Colors.red),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)!.delete,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: isSelecting
            ? () => onTapInSelection?.call(ref)
            : () {
                AppNavigator.toNoteEditorInstant(
                  context,
                  folderId: folderId,
                  noteId: metadata.id,
                  metadata: metadata,
                ).then((_) {
                  if (context.mounted) {
                    onReturn();
                  }
                });
              },
        onLongPress: () {
          if (isSelecting) {
            onTapInSelection?.call(ref);
          } else if (onLongPressItem != null) {
            onLongPressItem!(ref);
          } else {
            _showOptionsBottomSheet(context);
          }
        },
      ),
    );

    Widget result = card;
    if (isSelecting && isSelected && selection != null) {
      result = LongPressDraggable<Set<MovableItemRef>>(
        data: selection!.items,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          color: Colors.transparent,
          child: _DragFeedback(count: selection!.count),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: card),
        child: card,
      );
    }

    // Multi-drag visual: passenger cards dim & shrink so the user sees the
    // batch is travelling with the lifted card.
    if (isMultiDragging && isSelected) {
      result = AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: 0.96,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: 0.55,
          child: result,
        ),
      );
    }

    return result;
  }

  void _showOptionsBottomSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                metadata.title.isEmpty
                    ? AppLocalizations.of(context)!.untitledNote
                    : metadata.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: Text(AppLocalizations.of(context)!.rename),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _showRenameDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(AppLocalizations.of(context)!.moveToFolder),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _showMoveDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text(AppLocalizations.of(context)!.shareNote),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _showExportFormatDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: colorScheme.error),
              title: Text(
                AppLocalizations.of(context)!.delete,
                style: TextStyle(color: colorScheme.error),
              ),
              onTap: () {
                AppNavigator.pop(sheetContext);
                _confirmDelete(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMoveDialog(BuildContext context) {
    MoveCoordinator.moveNote(
      context,
      metadata: metadata,
      currentFolderId: folderId,
    );
  }

  void _showExportFormatDialog(BuildContext context) async {
    final format = await AppDialogs.choose<ExportFormat>(
      context,
      title: AppLocalizations.of(context)!.chooseExportFormat,
      options: [
        (
          value: ExportFormat.markdown,
          label: AppLocalizations.of(context)!.exportAsMarkdown,
          icon: Icons.description_rounded,
        ),
        (
          value: ExportFormat.json,
          label: AppLocalizations.of(context)!.exportAsJson,
          icon: Icons.data_object_rounded,
        ),
        (
          value: ExportFormat.text,
          label: AppLocalizations.of(context)!.exportAsText,
          icon: Icons.text_snippet_rounded,
        ),
      ],
    );
    if (format == null || !context.mounted) return;
    context.read<ImportExportBloc>().add(
      ExportNoteRequested(metadata: metadata, format: format, share: true),
    );
  }

  void _showRenameDialog(BuildContext context) async {
    final name = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.renameNote,
      hintText: AppLocalizations.of(context)!.enterNewName,
      initialValue: metadata.title,
    );
    if (name == null || !context.mounted) return;
    final trimmed = name.trim();
    if (trimmed.toLowerCase() == metadata.title.trim().toLowerCase()) {
      return;
    }
    // Empty titles are allowed (multiple "Untitled" notes can coexist) so
    // we only enforce uniqueness when the user actually typed a name.
    if (trimmed.isNotEmpty) {
      final exists = await GetIt.I<NoteStorageService>()
          .noteTitleExistsInFolder(
            folderId: folderId,
            title: trimmed,
            excludeId: metadata.id,
          );
      if (!context.mounted) return;
      if (exists) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.noteTitleAlreadyExists(trimmed),
        );
        return;
      }
    }
    context.read<OptimizedNoteBloc>().add(
      UpdateOptimizedNote(noteId: metadata.id, title: trimmed),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _confirmDelete(BuildContext context) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.deleteNote,
      content: AppLocalizations.of(context)!.deleteNoteConfirm(
        metadata.title.isEmpty
            ? AppLocalizations.of(context)!.deleteThisNote
            : metadata.title,
      ),
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    context.read<OptimizedNoteBloc>().add(DeleteOptimizedNote(metadata.id));
  }
}

/// Floating chip displayed under the user's finger while a selection batch
/// is being dragged onto a target folder.
class _DragFeedback extends StatelessWidget {
  final int count;

  const _DragFeedback({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 8,
      color: colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator, color: colorScheme.onPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
