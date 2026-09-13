import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/folder_change.dart';
import '../../services/folder_storage_service.dart';
import 'optimized_folder_event.dart';
import 'optimized_folder_state.dart';

class OptimizedFolderBloc
    extends Bloc<OptimizedFolderEvent, OptimizedFolderState> {
  final FolderStorageService _storageService;

  String? _currentParentId;
  int _currentPage = 1;
  int _currentPageSize = FolderStorageService.defaultPageSize;
  FoldersSortOrder _currentSortOrder = FoldersSortOrder.nameAsc;
  StreamSubscription<FolderChange>? _changesSubscription;

  /// The parents a refresh has been asked for but not yet dispatched for.
  ///
  /// A bulk label, delete or move raises one [FolderChange] per item, and a
  /// refresh is now a `pageSize * loadedPages` read — so labelling twenty
  /// rows used to re-read the whole visible list twenty times, each read
  /// larger than the one the old page-1 reload cost. Collecting the parents
  /// and flushing them at the end of the tick makes that one read per
  /// distinct parent, which is what the user is waiting for.
  final Set<String?> _pendingRefreshParents = {};
  Timer? _refreshTimer;

  OptimizedFolderBloc({required FolderStorageService storageService})
    : _storageService = storageService,
      super(OptimizedFolderInitial()) {
    on<LoadFoldersPaginated>(_onLoadFoldersPaginated);
    on<LoadMoreFolders>(_onLoadMoreFolders);
    on<CreateOptimizedFolder>(_onCreateFolder);
    on<UpdateOptimizedFolder>(_onUpdateFolder);
    on<SetOptimizedFolderLabel>(_onSetFolderLabel);
    on<SetOptimizedFoldersLabel>(_onSetFoldersLabel);
    on<DeleteOptimizedFolder>(_onDeleteFolder);
    on<DeleteOptimizedFolders>(_onDeleteFolders);
    on<RefreshFolders>(_onRefreshFolders);
    on<ReorderFolders>(_onReorderFolders);

    _changesSubscription = _storageService.changes.listen(_onExternalChange);
  }

  void _onExternalChange(FolderChange change) {
    final affectsCurrent =
        change.parentId == _currentParentId ||
        (change.type == FolderChangeType.moved &&
            change.sourceParentId == _currentParentId);
    if (affectsCurrent) {
      _scheduleRefresh(_currentParentId);
    }
  }

  /// Asks for a reload of [parentId], at most once per tick per parent.
  ///
  /// Every path that reloads the list goes through this, the writes' own
  /// `add(RefreshFolders(...))` included: a bulk write raises its change
  /// events *and* ends in a refresh of its own, and the two used to arrive as
  /// N + 1 reads of the same rows.
  /// A zero-duration [Timer] rather than a microtask: the change events being
  /// coalesced arrive one microtask apart (a broadcast stream delivers them
  /// that way), so a microtask flush would run *between* two of them and
  /// coalesce nothing.
  void _scheduleRefresh(String? parentId) {
    _pendingRefreshParents.add(parentId);
    _refreshTimer ??= Timer(Duration.zero, () {
      _refreshTimer = null;
      final parents = _pendingRefreshParents.toList(growable: false);
      _pendingRefreshParents.clear();
      // A page popped while its own write was in flight closes this bloc
      // before the flush runs, and `add` on a closed bloc throws.
      if (isClosed) return;
      for (final parent in parents) {
        add(RefreshFolders(parentId: parent));
      }
    });
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    _changesSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadFoldersPaginated(
    LoadFoldersPaginated event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    emit(OptimizedFolderLoading(parentId: event.parentId));

    try {
      await _storageService.initialize();

      _currentParentId = event.parentId;
      _currentPage = event.page;
      _currentPageSize = event.pageSize;
      _currentSortOrder = event.sortOrder;

      final paginatedFolders = await _storageService.loadFoldersPaginated(
        parentId: event.parentId,
        page: event.page,
        pageSize: event.pageSize,
        sortOrder: event.sortOrder,
      );

      emit(
        OptimizedFolderLoaded(
          paginatedFolders: paginatedFolders,
          parentId: event.parentId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load folders', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to load folders: $e',
          parentId: event.parentId,
        ),
      );
    }
  }

  Future<void> _onLoadMoreFolders(
    LoadMoreFolders event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    final currentState = state;

    if (currentState is! OptimizedFolderLoaded) return;
    if (!currentState.paginatedFolders.hasMore) return;
    if (currentState.isLoadingMore) return;

    // The state this page is being appended to, emitted rather than merely
    // captured: this bloc processes events concurrently, so a refresh can
    // land while the read below is in flight. Building the combined state
    // from `currentState` after the await put the pre-refresh rows back on
    // screen — a bulk label applied, then visibly undone.
    final loading = currentState.copyWith(
      isLoadingMore: true,
      parentId: event.parentId ?? _currentParentId,
    );
    emit(loading);

    // Counted up only once the page is actually in hand: a failed read used
    // to leave the counter advanced, so the next load-more skipped the page
    // that had just been missed and the list lost those rows for good.
    final nextPage = _currentPage + 1;

    try {
      final morePaginatedFolders = await _storageService.loadFoldersPaginated(
        parentId: event.parentId ?? _currentParentId,
        page: nextPage,
        pageSize: _currentPageSize,
        sortOrder: _currentSortOrder,
      );

      // Something else owns the list now, and it re-read every page this one
      // was about to extend.
      if (!identical(state, loading)) return;

      final combinedFolders = [
        ...loading.paginatedFolders.folders,
        ...morePaginatedFolders.folders,
      ];

      final updatedPaginatedFolders = morePaginatedFolders.copyWith(
        folders: combinedFolders,
      );

      _currentPage = nextPage;

      emit(
        loading.copyWith(
          paginatedFolders: updatedPaginatedFolders,
          isLoadingMore: false,
          parentId: event.parentId ?? _currentParentId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load more folders', e, stackTrace);
      if (!identical(state, loading)) return;
      emit(
        loading.copyWith(
          isLoadingMore: false,
          parentId: event.parentId ?? _currentParentId,
        ),
      );
    }
  }

  Future<void> _onCreateFolder(
    CreateOptimizedFolder event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    try {
      await _storageService.createFolder(
        name: event.name,
        parentId: event.parentId,
      );

      _scheduleRefresh(event.parentId);
    } catch (e, stackTrace) {
      _logError('Failed to create folder', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to create folder: $e',
          parentId: event.parentId,
        ),
      );
    }
  }

  Future<void> _onUpdateFolder(
    UpdateOptimizedFolder event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    try {
      final folder = await _storageService.getFolderById(event.folderId);

      await _storageService.updateFolder(
        folderId: event.folderId,
        name: event.name,
      );

      _scheduleRefresh(folder?.parentId);
    } catch (e, stackTrace) {
      _logError('Failed to update folder', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to update folder: $e',
          parentId: _currentParentId,
        ),
      );
    }
  }

  Future<void> _onSetFolderLabel(
    SetOptimizedFolderLabel event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    try {
      final folder = await _storageService.setFolderLabel(
        event.folderId,
        event.label,
      );
      _scheduleRefresh(folder?.parentId ?? _currentParentId);
    } catch (e, stackTrace) {
      _logError('Failed to label folder', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to label folder: $e',
          parentId: _currentParentId,
        ),
      );
    }
  }

  Future<void> _onSetFoldersLabel(
    SetOptimizedFoldersLabel event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    if (event.folderIds.isEmpty) return;
    try {
      await _storageService.setLabelForFolders(event.folderIds, event.label);
      _scheduleRefresh(_currentParentId);
    } catch (e, stackTrace) {
      _logError('Failed to label folders', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to label folders: $e',
          parentId: _currentParentId,
        ),
      );
    }
  }

  Future<void> _onDeleteFolder(
    DeleteOptimizedFolder event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    try {
      await _storageService.deleteFolder(event.folderId);

      _scheduleRefresh(event.parentId);
    } catch (e, stackTrace) {
      _logError('Failed to delete folder', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to delete folder: $e',
          parentId: event.parentId,
        ),
      );
    }
  }

  Future<void> _onDeleteFolders(
    DeleteOptimizedFolders event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    if (event.folderIds.isEmpty) return;
    try {
      await _storageService.deleteFolders(event.folderIds);

      _scheduleRefresh(event.parentId);
    } catch (e, stackTrace) {
      _logError('Failed to delete folders', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to delete folders: $e',
          parentId: event.parentId,
        ),
      );
    }
  }

  /// Reloads the list the page is already showing, in place.
  ///
  /// It used to reset the page counter and re-dispatch
  /// [LoadFoldersPaginated], which emits [OptimizedFolderLoading] before its
  /// page-1 result. That one Loading frame is what made bulk actions flash:
  /// leaving selection mode drops the browser's cached row list, so the frame
  /// with no data behind it rendered the cold-start spinner where the rows
  /// had been — and the scroll offset went with them. It also cost a list
  /// scrolled to its third page every row past the first twenty.
  ///
  /// Re-reading `pageSize * loadedPages` in one statement keeps the rows that
  /// were there and leaves `hasMore` answering about the same boundary the
  /// next [LoadMoreFolders] reads from. A refresh aimed at a *different*
  /// parent than the one on screen is a different list, not this one, so it
  /// still goes through the full load.
  Future<void> _onRefreshFolders(
    RefreshFolders event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    _storageService.invalidateCache();

    final parentId = event.parentId ?? _currentParentId;
    if (parentId != _currentParentId) {
      _currentPage = 1;
      add(
        LoadFoldersPaginated(
          parentId: parentId,
          pageSize: _currentPageSize,
          sortOrder: _currentSortOrder,
        ),
      );
      return;
    }

    try {
      final paginatedFolders = await _loadLoadedPages(
        parentId: parentId,
        pages: _currentPage,
      );

      emit(
        OptimizedFolderLoaded(
          paginatedFolders: paginatedFolders,
          parentId: parentId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to refresh folders', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to refresh folders: $e',
          parentId: parentId,
        ),
      );
    }
  }

  /// Re-reads every page the list already has, as one query.
  ///
  /// The folder twin of `OptimizedNoteBloc._loadLoadedPages`, and the same
  /// shape for the same reason: asking for page 1 alone brought a list
  /// scrolled three pages deep back holding twenty rows.
  ///
  /// `pageSize` is widened rather than the page walked, so the service's own
  /// `totalPages` comes back counted in *those* pages. It is restated here in
  /// the page size the list actually reads in, so the count means the same
  /// thing before and after a refresh.
  Future<PaginatedFolders> _loadLoadedPages({
    required String? parentId,
    required int pages,
  }) async {
    final loaded = pages < 1 ? 1 : pages;
    final result = await _storageService.loadFoldersPaginated(
      parentId: parentId,
      page: 1,
      pageSize: _currentPageSize * loaded,
      sortOrder: _currentSortOrder,
    );
    return result.copyWith(
      currentPage: loaded,
      totalPages: (result.totalCount / _currentPageSize).ceil().clamp(
        1,
        double.maxFinite.toInt(),
      ),
    );
  }

  Future<void> _onReorderFolders(
    ReorderFolders event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    try {
      await _storageService.reorderFolders(
        parentId: event.parentId,
        orderedIds: event.orderedIds,
      );

      // Refresh to get updated order
      _scheduleRefresh(event.parentId);
    } catch (e, stackTrace) {
      _logError('Failed to reorder folders', e, stackTrace);
      emit(
        OptimizedFolderError(
          'Failed to reorder folders: $e',
          parentId: event.parentId,
        ),
      );
    }
  }

  void _logError(String message, Object error, StackTrace stackTrace) {
    debugPrint('\n╔══════════════════════════════════════════════════════════');
    debugPrint('║ [OptimizedFolderBloc] $message');
    debugPrint('║ Error: $error');
    debugPrint('╠══════════════════════════════════════════════════════════');
    debugPrint('║ Stack trace:');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 10);
    debugPrint('╚══════════════════════════════════════════════════════════\n');
  }
}
