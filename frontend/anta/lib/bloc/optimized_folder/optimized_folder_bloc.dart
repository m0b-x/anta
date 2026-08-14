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
  FoldersSortOrder _currentSortOrder = FoldersSortOrder.nameAsc;
  StreamSubscription<FolderChange>? _changesSubscription;

  OptimizedFolderBloc({required FolderStorageService storageService})
    : _storageService = storageService,
      super(OptimizedFolderInitial()) {
    on<LoadFoldersPaginated>(_onLoadFoldersPaginated);
    on<LoadMoreFolders>(_onLoadMoreFolders);
    on<CreateOptimizedFolder>(_onCreateFolder);
    on<UpdateOptimizedFolder>(_onUpdateFolder);
    on<DeleteOptimizedFolder>(_onDeleteFolder);
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
      add(RefreshFolders(parentId: _currentParentId));
    }
  }

  @override
  Future<void> close() {
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

    emit(
      currentState.copyWith(
        isLoadingMore: true,
        parentId: event.parentId ?? _currentParentId,
      ),
    );

    try {
      _currentPage++;

      final morePaginatedFolders = await _storageService.loadFoldersPaginated(
        parentId: event.parentId ?? _currentParentId,
        page: _currentPage,
        sortOrder: _currentSortOrder,
      );

      final combinedFolders = [
        ...currentState.paginatedFolders.folders,
        ...morePaginatedFolders.folders,
      ];

      final updatedPaginatedFolders = morePaginatedFolders.copyWith(
        folders: combinedFolders,
      );

      emit(
        currentState.copyWith(
          paginatedFolders: updatedPaginatedFolders,
          isLoadingMore: false,
          parentId: event.parentId ?? _currentParentId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load more folders', e, stackTrace);
      emit(
        currentState.copyWith(
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

      add(RefreshFolders(parentId: event.parentId));
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

      add(RefreshFolders(parentId: folder?.parentId));
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

  Future<void> _onDeleteFolder(
    DeleteOptimizedFolder event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    try {
      await _storageService.deleteFolder(event.folderId);

      add(RefreshFolders(parentId: event.parentId));
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

  Future<void> _onRefreshFolders(
    RefreshFolders event,
    Emitter<OptimizedFolderState> emit,
  ) async {
    _storageService.invalidateCache();
    _currentPage = 1;

    add(
      LoadFoldersPaginated(
        parentId: event.parentId ?? _currentParentId,
        sortOrder: _currentSortOrder,
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
      add(RefreshFolders(parentId: event.parentId));
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
