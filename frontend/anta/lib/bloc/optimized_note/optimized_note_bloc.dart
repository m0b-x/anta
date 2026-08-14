import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';
import '../../models/note_change.dart';
import '../../models/note_metadata.dart';
import '../../services/note_storage_service.dart';
import '../../services/folder_search_service.dart';
import 'optimized_note_event.dart';
import 'optimized_note_state.dart';

/// Debounce transformer for search events - waits for user to stop typing
EventTransformer<T> debounce<T>(Duration duration) {
  return (events, mapper) => events.debounce(duration).switchMap(mapper);
}

class OptimizedNoteBloc extends Bloc<OptimizedNoteEvent, OptimizedNoteState> {
  final NoteStorageService _storageService;
  final FolderSearchService _searchService;

  String? _currentFolderId;
  int _currentPage = 1;
  NotesSortOrder _currentSortOrder = NotesSortOrder.updatedDesc;
  PaginatedNotes? _lastPaginatedNotes;
  StreamSubscription<NoteChange>? _changesSubscription;

  OptimizedNoteBloc({
    required NoteStorageService storageService,
    required FolderSearchService searchService,
  }) : _storageService = storageService,
       _searchService = searchService,
       super(OptimizedNoteInitial()) {
    on<LoadNotesPaginated>(_onLoadNotesPaginated);
    on<LoadMoreNotes>(_onLoadMoreNotes);
    on<LoadNoteContent>(_onLoadNoteContent);
    on<CreateOptimizedNote>(_onCreateNote);
    on<UpdateOptimizedNote>(_onUpdateNote);
    on<DeleteOptimizedNote>(_onDeleteNote);
    on<SearchNotes>(_onSearchNotes);
    on<QuickSearchNotes>(
      _onQuickSearchNotes,
      transformer: debounce(const Duration(milliseconds: 200)),
    );
    on<ClearSearch>(_onClearSearch);
    on<RefreshNotes>(_onRefreshNotes);
    on<ReorderNotes>(_onReorderNotes);

    _changesSubscription = _storageService.changes.listen(_onExternalChange);
  }

  void _onExternalChange(NoteChange change) {
    final affectsCurrent =
        change.folderId == _currentFolderId ||
        (change.type == NoteChangeType.moved &&
            change.sourceFolderId == _currentFolderId);
    if (affectsCurrent) {
      add(RefreshNotes(folderId: _currentFolderId));
    }
  }

  Future<void> _onLoadNotesPaginated(
    LoadNotesPaginated event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    emit(OptimizedNoteLoading(folderId: event.folderId));

    try {
      await _storageService.initialize();

      _currentFolderId = event.folderId;
      _currentPage = event.page;
      _currentSortOrder = event.sortOrder;

      final paginatedNotes = await _storageService.loadNotesPaginated(
        folderId: event.folderId,
        page: event.page,
        pageSize: event.pageSize,
        sortOrder: event.sortOrder,
      );

      _lastPaginatedNotes = paginatedNotes;

      emit(
        OptimizedNoteLoaded(
          paginatedNotes: paginatedNotes,
          folderId: event.folderId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load notes', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to load notes: $e',
          folderId: event.folderId,
        ),
      );
    }
  }

  Future<void> _onLoadMoreNotes(
    LoadMoreNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    final currentState = state;

    if (currentState is! OptimizedNoteLoaded) return;
    if (!currentState.paginatedNotes.hasMore) return;
    if (currentState.isLoadingMore) return;

    emit(
      currentState.copyWith(
        isLoadingMore: true,
        folderId: event.folderId ?? _currentFolderId,
      ),
    );

    try {
      _currentPage++;

      final morePaginatedNotes = await _storageService.loadNotesPaginated(
        folderId: event.folderId ?? _currentFolderId,
        page: _currentPage,
        sortOrder: _currentSortOrder,
      );

      final combinedNotes = [
        ...currentState.paginatedNotes.notes,
        ...morePaginatedNotes.notes,
      ];

      final updatedPaginatedNotes = morePaginatedNotes.copyWith(
        notes: combinedNotes,
      );

      _lastPaginatedNotes = updatedPaginatedNotes;

      emit(
        currentState.copyWith(
          paginatedNotes: updatedPaginatedNotes,
          isLoadingMore: false,
          folderId: event.folderId ?? _currentFolderId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load more notes', e, stackTrace);
      emit(
        currentState.copyWith(
          isLoadingMore: false,
          folderId: event.folderId ?? _currentFolderId,
        ),
      );
    }
  }

  Future<void> _onLoadNoteContent(
    LoadNoteContent event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    try {
      final lazyNote = await _storageService.loadNoteWithContent(event.noteId);

      if (lazyNote == null) {
        emit(const OptimizedNoteError('Note not found'));
        return;
      }

      emit(
        OptimizedNoteContentLoaded(
          note: lazyNote,
          previousPaginatedNotes: _lastPaginatedNotes,
          folderId: _currentFolderId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load note content', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to load note content: $e',
          folderId: _currentFolderId,
        ),
      );
    }
  }

  Future<void> _onCreateNote(
    CreateOptimizedNote event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    try {
      final metadata = await _storageService.createNote(
        folderId: event.folderId,
        title: event.title,
        content: event.content,
      );

      await _searchService.updateIndex(metadata.id, event.title, event.content);

      emit(OptimizedNoteCreated(metadata: metadata));
      add(RefreshNotes(folderId: event.folderId));
    } catch (e, stackTrace) {
      _logError('Failed to create note', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to create note: $e',
          folderId: event.folderId,
        ),
      );
    }
  }

  Future<void> _onUpdateNote(
    UpdateOptimizedNote event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    try {
      final metadata = await _storageService.updateNote(
        noteId: event.noteId,
        title: event.title,
        content: event.content,
      );

      if (metadata != null) {
        final content =
            event.content ??
            await _storageService.loadNoteContent(event.noteId);
        await _searchService.updateIndex(metadata.id, metadata.title, content);
      }

      if (_currentFolderId != null) {
        add(RefreshNotes(folderId: _currentFolderId));
      }

      event.completer?.complete();
    } catch (e, stackTrace) {
      _logError('Failed to update note', e, stackTrace);
      event.completer?.completeError(e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to update note: $e',
          folderId: _currentFolderId,
        ),
      );
    }
  }

  Future<void> _onDeleteNote(
    DeleteOptimizedNote event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    try {
      await _storageService.deleteNote(event.noteId);
      await _searchService.removeFromIndex(event.noteId);

      add(RefreshNotes(folderId: _currentFolderId));
    } catch (e, stackTrace) {
      _logError('Failed to delete note', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to delete note: $e',
          folderId: _currentFolderId,
        ),
      );
    }
  }

  Future<void> _onSearchNotes(
    SearchNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    emit(
      const OptimizedNoteSearchResults(
        results: [],
        query: '',
        isSearching: true,
      ),
    );

    try {
      await _searchService.initialize();

      final results = await _searchService.search(
        event.query,
        filter: event.folderId != null
            ? SearchFilter(folderId: event.folderId)
            : null,
      );

      emit(
        OptimizedNoteSearchResults(
          results: results,
          query: event.query,
          isSearching: false,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Search failed', e, stackTrace);
      emit(OptimizedNoteError('Search failed: $e', folderId: event.folderId));
    }
  }

  Future<void> _onQuickSearchNotes(
    QuickSearchNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    final currentState = state;

    if (currentState is OptimizedNoteSearchResults) {
      emit(currentState.copyWith(isSearching: true));
    } else {
      emit(
        const OptimizedNoteSearchResults(
          results: [],
          query: '',
          isSearching: true,
        ),
      );
    }

    try {
      await _searchService.initialize();

      final results = await _searchService.quickSearch(
        event.query,
        folderId: event.folderId,
      );

      emit(
        OptimizedNoteSearchResults(
          results: results,
          query: event.query,
          isSearching: false,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Quick search failed', e, stackTrace);
      emit(
        OptimizedNoteError('Quick search failed: $e', folderId: event.folderId),
      );
    }
  }

  Future<void> _onClearSearch(
    ClearSearch event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    if (_lastPaginatedNotes != null) {
      emit(
        OptimizedNoteLoaded(
          paginatedNotes: _lastPaginatedNotes!,
          folderId: _currentFolderId,
        ),
      );
    } else {
      add(LoadNotesPaginated(folderId: _currentFolderId));
    }
  }

  Future<void> _onRefreshNotes(
    RefreshNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    _currentPage = 1;

    final paginatedNotes = await _storageService.loadNotesPaginated(
      folderId: event.folderId ?? _currentFolderId,
      page: 1,
      sortOrder: _currentSortOrder,
    );

    _lastPaginatedNotes = paginatedNotes;

    emit(
      OptimizedNoteLoaded(
        paginatedNotes: paginatedNotes,
        folderId: event.folderId ?? _currentFolderId,
      ),
    );
  }

  Future<void> _onReorderNotes(
    ReorderNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    try {
      await _storageService.reorderNotes(
        folderId: event.folderId,
        orderedIds: event.orderedIds,
      );

      // Refresh to get updated order
      add(RefreshNotes(folderId: event.folderId));
    } catch (e, stackTrace) {
      _logError('Failed to reorder notes', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to reorder notes: $e',
          folderId: event.folderId,
        ),
      );
    }
  }

  void _logError(String message, Object error, StackTrace stackTrace) {
    debugPrint('\n╔══════════════════════════════════════════════════════════');
    debugPrint('║ [OptimizedNoteBloc] $message');
    debugPrint('║ Error: $error');
    debugPrint('╠══════════════════════════════════════════════════════════');
    debugPrint('║ Stack trace:');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 10);
    debugPrint('╚══════════════════════════════════════════════════════════\n');
  }

  @override
  Future<void> close() {
    _changesSubscription?.cancel();
    _storageService.dispose();
    _searchService.dispose();
    return super.close();
  }
}
