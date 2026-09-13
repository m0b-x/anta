import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/note_change.dart';
import '../../models/note_metadata.dart';
import '../../services/note_storage_service.dart';
import '../../services/folder_search_service.dart';
import 'optimized_note_event.dart';
import 'optimized_note_state.dart';

class OptimizedNoteBloc extends Bloc<OptimizedNoteEvent, OptimizedNoteState> {
  final NoteStorageService _storageService;
  final FolderSearchService _searchService;

  String? _currentFolderId;
  int _currentPage = 1;
  int _currentPageSize = NoteStorageService.defaultPageSize;
  NotesSortOrder _currentSortOrder = NotesSortOrder.updatedDesc;
  PaginatedNotes? _lastPaginatedNotes;
  StreamSubscription<NoteChange>? _changesSubscription;

  /// The folders a refresh has been asked for but not yet dispatched for.
  ///
  /// A bulk label or delete raises one [NoteChange] per note, and a refresh
  /// re-reads every page the list has — so labelling twenty rows used to cost
  /// twenty full reads of the visible list. Collecting the folders and
  /// flushing them at the end of the tick makes that one read per folder.
  final Set<String?> _pendingRefreshFolders = {};
  Timer? _refreshTimer;

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
    on<SetOptimizedNoteLabel>(_onSetNoteLabel);
    on<SetOptimizedNotesLabel>(_onSetNotesLabel);
    on<DeleteOptimizedNote>(_onDeleteNote);
    on<DeleteOptimizedNotes>(_onDeleteNotes);
    on<PreloadNoteContent>(_onPreloadContent);
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
      _scheduleRefresh(_currentFolderId);
    }
  }

  /// Asks for a reload of [folderId], at most once per tick per folder.
  ///
  /// Every path that reloads the list goes through this, the writes' own
  /// post-write refresh included: a bulk write raises its change events *and*
  /// ends in a refresh, and the two used to arrive as N + 1 reads of the same
  /// rows.
  /// A zero-duration [Timer] rather than a microtask: the change events being
  /// coalesced arrive one microtask apart (a broadcast stream delivers them
  /// that way), so a microtask flush would run *between* two of them and
  /// coalesce nothing.
  void _scheduleRefresh(String? folderId) {
    _pendingRefreshFolders.add(folderId);
    _refreshTimer ??= Timer(Duration.zero, () {
      _refreshTimer = null;
      final folders = _pendingRefreshFolders.toList(growable: false);
      _pendingRefreshFolders.clear();
      // A page popped while its own write was in flight closes this bloc
      // before the flush runs, and `add` on a closed bloc throws.
      if (isClosed) return;
      for (final folder in folders) {
        add(RefreshNotes(folderId: folder));
      }
    });
  }

  Future<void> _onLoadNotesPaginated(
    LoadNotesPaginated event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    emit(OptimizedNoteLoading(folderId: event.folderId));

    try {
      await _storageService.initialize();

      // A page asking for its first page again is reloading the list it is
      // already showing — after a pop, a settings change or a note write —
      // not starting a new one. Serving it page 1 alone is what made a
      // paginated list shrink to twenty rows on the way back.
      final continuesCurrentList =
          event.page == 1 &&
          _currentPage > 1 &&
          _currentFolderId == event.folderId &&
          _currentPageSize == event.pageSize &&
          _currentSortOrder == event.sortOrder;

      _currentFolderId = event.folderId;
      _currentPageSize = event.pageSize;
      _currentSortOrder = event.sortOrder;
      if (!continuesCurrentList) _currentPage = event.page;

      final paginatedNotes = continuesCurrentList
          ? await _loadLoadedPages(
              folderId: event.folderId,
              pages: _currentPage,
            )
          : await _storageService.loadNotesPaginated(
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

    // The state this page is being appended to, emitted rather than merely
    // captured: this bloc processes events concurrently, so a refresh can
    // land while the read below is in flight, and building the combined
    // state from `currentState` afterwards would put the pre-refresh rows
    // back on screen.
    final loading = currentState.copyWith(
      isLoadingMore: true,
      folderId: event.folderId ?? _currentFolderId,
    );
    emit(loading);

    // Counted up only once the page is actually in hand: a failed read used
    // to leave the counter advanced, so the next load-more skipped the page
    // that had just been missed and the list lost twenty rows for good.
    final nextPage = _currentPage + 1;

    try {
      final morePaginatedNotes = await _storageService.loadNotesPaginated(
        folderId: event.folderId ?? _currentFolderId,
        page: nextPage,
        pageSize: _currentPageSize,
        sortOrder: _currentSortOrder,
      );

      // Something else owns the list now, and it re-read every page this one
      // was about to extend.
      if (!identical(state, loading)) return;

      final combinedNotes = [
        ...loading.paginatedNotes.notes,
        ...morePaginatedNotes.notes,
      ];

      final updatedPaginatedNotes = morePaginatedNotes.copyWith(
        notes: combinedNotes,
      );

      _currentPage = nextPage;
      _lastPaginatedNotes = updatedPaginatedNotes;

      emit(
        loading.copyWith(
          paginatedNotes: updatedPaginatedNotes,
          isLoadingMore: false,
          folderId: event.folderId ?? _currentFolderId,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Failed to load more notes', e, stackTrace);
      if (!identical(state, loading)) return;
      emit(
        loading.copyWith(
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
      _scheduleRefresh(event.folderId);
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
        _scheduleRefresh(_currentFolderId);
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

  Future<void> _onSetNoteLabel(
    SetOptimizedNoteLabel event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    try {
      await _storageService.setNoteLabel(event.noteId, event.label);
      _scheduleRefresh(_currentFolderId);
    } catch (e, stackTrace) {
      _logError('Failed to label note', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to label note: $e',
          folderId: _currentFolderId,
        ),
      );
    }
  }

  Future<void> _onSetNotesLabel(
    SetOptimizedNotesLabel event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    if (event.noteIds.isEmpty) return;
    try {
      await _storageService.setLabelForNotes(event.noteIds, event.label);
      _scheduleRefresh(_currentFolderId);
    } catch (e, stackTrace) {
      _logError('Failed to label notes', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to label notes: $e',
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

      _scheduleRefresh(_currentFolderId);
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

  Future<void> _onDeleteNotes(
    DeleteOptimizedNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    if (event.noteIds.isEmpty) return;
    try {
      await _storageService.deleteNotes(event.noteIds);
      for (final noteId in event.noteIds) {
        await _searchService.removeFromIndex(noteId);
      }

      _scheduleRefresh(_currentFolderId);
    } catch (e, stackTrace) {
      _logError('Failed to delete notes', e, stackTrace);
      emit(
        OptimizedNoteError(
          'Failed to delete notes: $e',
          folderId: _currentFolderId,
        ),
      );
    }
  }

  Future<void> _onPreloadContent(
    PreloadNoteContent event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    if (event.noteIds.isEmpty) return;
    _storageService.preloadContent(event.noteIds);
  }

  Future<void> _onRefreshNotes(
    RefreshNotes event,
    Emitter<OptimizedNoteState> emit,
  ) async {
    final folderId = event.folderId ?? _currentFolderId;
    final paginatedNotes = await _loadLoadedPages(
      folderId: folderId,
      pages: folderId == _currentFolderId ? _currentPage : 1,
    );

    _lastPaginatedNotes = paginatedNotes;

    emit(
      OptimizedNoteLoaded(paginatedNotes: paginatedNotes, folderId: folderId),
    );
  }

  /// Re-reads every page the list already has, as one query.
  ///
  /// A reload used to ask for page 1 alone, so a list scrolled to its third
  /// page came back holding twenty rows — All notes visibly shrank on the way
  /// back from a note, and the offset clamped to the top with it. Asking for
  /// `pageSize * pages` in one statement keeps the rows that were there and
  /// leaves `hasMore` answering about the same boundary the next
  /// [LoadMoreNotes] will read from.
  Future<PaginatedNotes> _loadLoadedPages({
    required String? folderId,
    required int pages,
  }) async {
    final loaded = pages < 1 ? 1 : pages;
    final result = await _storageService.loadNotesPaginated(
      folderId: folderId,
      page: 1,
      pageSize: _currentPageSize * loaded,
      sortOrder: _currentSortOrder,
    );
    return result.copyWith(currentPage: loaded);
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
      _scheduleRefresh(event.folderId);
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
    _refreshTimer?.cancel();
    _changesSubscription?.cancel();
    _storageService.dispose();
    _searchService.dispose();
    return super.close();
  }
}
