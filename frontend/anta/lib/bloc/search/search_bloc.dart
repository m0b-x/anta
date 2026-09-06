import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/note_metadata.dart';
import '../../models/search_scope.dart';
import '../../services/folder_search_service.dart';
import '../../services/folder_storage_service.dart';
import '../../services/note_storage_service.dart';
import '../../utils/bloc_helpers.dart';
import 'search_event.dart';
import 'search_state.dart';

export 'search_event.dart';
export 'search_state.dart';

/// Owns search state for as long as the surface is on screen.
///
/// It exists so query, scope and results survive pushing a note and coming
/// back, and so searching stops clobbering the folder list: the browser and
/// the search field used to share `OptimizedNoteBloc`, whose search results
/// replaced the very list the page underneath was rendering.
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  static const Duration queryDebounce = Duration(milliseconds: 200);
  static const int recentsPageSize = 20;

  final FolderSearchService _searchService;
  final NoteStorageService _noteService;
  final FolderStorageService _folderService;

  /// Bumped by every handler that changes what should be on screen, and
  /// re-checked immediately before each `emit` that follows an await.
  ///
  /// Only [SearchQueryChanged] has a transformer, so handlers of *different*
  /// event types run concurrently and the slowest one used to win: a tag
  /// open's recents landing after its own submitted search wiped the results
  /// and blanked the query, and a debounced quick pass landing after a clear
  /// repainted hits under an empty field.
  int _generation = 0;

  SearchBloc({
    required FolderSearchService searchService,
    required NoteStorageService noteService,
    required FolderStorageService folderService,
  }) : _searchService = searchService,
       _noteService = noteService,
       _folderService = folderService,
       super(const SearchState()) {
    on<SearchOpened>(_onOpened);
    on<SearchQueryChanged>(
      _onQueryChanged,
      transformer: debounce(queryDebounce),
    );
    on<SearchSubmitted>(_onSubmitted);
    on<SearchScopeChanged>(_onScopeChanged);
    on<SearchCleared>(_onCleared);
  }

  Future<void> _onOpened(SearchOpened event, Emitter<SearchState> emit) async {
    final generation = ++_generation;
    emit(state.copyWith(scope: event.scope, isSearching: true));
    await _emitRecents(emit, generation);
  }

  Future<void> _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query.trim().isEmpty) {
      final generation = ++_generation;
      await _emitRecents(emit, generation);
      return;
    }

    if (state.phase == SearchPhase.full && state.query == event.query) return;

    final generation = ++_generation;
    emit(
      state.copyWith(
        query: event.query,
        phase: SearchPhase.quick,
        recents: const [],
        isSearching: true,
      ),
    );
    await _runQuick(emit, event.query, state.scope, generation);
  }

  Future<void> _onSubmitted(
    SearchSubmitted event,
    Emitter<SearchState> emit,
  ) async {
    final generation = ++_generation;
    if (event.query.trim().isEmpty) {
      await _emitRecents(emit, generation);
      return;
    }

    emit(
      state.copyWith(
        query: event.query,
        phase: SearchPhase.full,
        recents: const [],
        isSearching: true,
      ),
    );
    await _runFull(emit, event.query, state.scope, generation);
  }

  Future<void> _onScopeChanged(
    SearchScopeChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (event.scope == state.scope) return;

    // Idle has nothing scoped on screen — recents are global — so the chip
    // only records the choice the next query will run under.
    if (state.phase == SearchPhase.idle) {
      emit(state.copyWith(scope: event.scope));
      return;
    }

    final generation = ++_generation;
    final query = state.query;
    emit(state.copyWith(scope: event.scope, isSearching: true));

    switch (state.phase) {
      case SearchPhase.quick:
        await _runQuick(emit, query, event.scope, generation);
      case SearchPhase.full:
        await _runFull(emit, query, event.scope, generation);
      case SearchPhase.idle:
        break;
    }
  }

  Future<void> _onCleared(
    SearchCleared event,
    Emitter<SearchState> emit,
  ) async {
    final generation = ++_generation;
    await _emitRecents(emit, generation);
  }

  Future<void> _runQuick(
    Emitter<SearchState> emit,
    String query,
    SearchScope scope,
    int generation,
  ) async {
    try {
      final results = await _searchService.quickSearch(
        query,
        folderIds: await _folderIdsFor(scope),
      );
      await _emitResults(
        emit,
        query: query,
        scope: scope,
        phase: SearchPhase.quick,
        results: results,
        generation: generation,
      );
    } catch (e, stackTrace) {
      _logError('Quick search failed', e, stackTrace);
      if (generation != _generation) return;
      emit(state.copyWith(isSearching: false));
    }
  }

  Future<void> _runFull(
    Emitter<SearchState> emit,
    String query,
    SearchScope scope,
    int generation,
  ) async {
    try {
      final folderIds = await _folderIdsFor(scope);
      final results = await _searchService.search(
        query,
        filter: folderIds == null ? null : SearchFilter(folderIds: folderIds),
      );
      await _emitResults(
        emit,
        query: query,
        scope: scope,
        phase: SearchPhase.full,
        results: results,
        generation: generation,
      );
    } catch (e, stackTrace) {
      _logError('Search failed', e, stackTrace);
      if (generation != _generation) return;
      emit(state.copyWith(isSearching: false));
    }
  }

  Future<void> _emitRecents(Emitter<SearchState> emit, int generation) async {
    try {
      final page = await _noteService.loadNotesPaginated(
        pageSize: recentsPageSize,
        sortOrder: NotesSortOrder.updatedDesc,
      );
      final folderPaths = await _pathsFor(page.notes);
      if (generation != _generation) return;
      emit(
        state.copyWith(
          query: '',
          phase: SearchPhase.idle,
          recents: page.notes,
          titleHits: const [],
          contentHits: const [],
          folderPaths: folderPaths,
          isSearching: false,
        ),
      );
    } catch (e, stackTrace) {
      _logError('Loading recents failed', e, stackTrace);
      if (generation != _generation) return;
      emit(
        state.copyWith(
          query: '',
          phase: SearchPhase.idle,
          recents: const [],
          titleHits: const [],
          contentHits: const [],
          isSearching: false,
        ),
      );
    }
  }

  /// Splits [results] the way the surface groups them: a note whose title
  /// matched is a title hit even when its body matched too, so it is listed
  /// once, under the section that explains why it is there.
  Future<void> _emitResults(
    Emitter<SearchState> emit, {
    required String query,
    required SearchScope scope,
    required SearchPhase phase,
    required List<SearchResult> results,
    required int generation,
  }) async {
    final titleHits = <SearchResult>[];
    final contentHits = <SearchResult>[];
    for (final result in results) {
      final isTitleHit = result.matches.any(
        (match) => match.type == SearchMatchType.title,
      );
      (isTitleHit ? titleHits : contentHits).add(result);
    }

    final folderPaths = await _pathsFor([
      for (final result in results) result.metadata,
    ]);
    if (generation != _generation) return;

    emit(
      state.copyWith(
        query: query,
        scope: scope,
        phase: phase,
        recents: const [],
        titleHits: titleHits,
        contentHits: contentHits,
        folderPaths: folderPaths,
        isSearching: false,
      ),
    );
  }

  Future<Set<String>?> _folderIdsFor(SearchScope scope) async {
    final folderId = scope.folderId;
    if (folderId == null) return null;
    return _folderService.subtreeIds(folderId);
  }

  Future<Map<String, List<String>>> _pathsFor(List<NoteMetadata> notes) async {
    if (notes.isEmpty) return const {};
    return _folderService.folderPathSegments(
      notes.map((note) => note.folderId),
    );
  }

  void _logError(String message, Object error, StackTrace stackTrace) {
    debugPrint('[SearchBloc] $message: $error');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 10);
  }
}
