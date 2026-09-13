import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants/app_constants.dart';
import '../../models/item_label.dart';
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

  /// The idle list's cap, shared with the Recent page so "recent" means one
  /// number everywhere.
  static const int recentsPageSize = AppConstants.recentNotesLimit;

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

  /// The text of the [SearchQueryChanged] still allowed to run, or null once
  /// an event of another kind was added after it.
  ///
  /// [_generation] settles which *handler* wins; this settles which *event*
  /// does. [SearchQueryChanged] is the only debounced event, so it is the
  /// only one that can be delivered after events added later than it:
  /// emptying the field dispatches an immediate [SearchCleared], and the
  /// keystroke before it — the "p" of a "pr" backspaced away — used to fire
  /// 200 ms later and search under a blank field. Recorded in [onEvent],
  /// which runs synchronously inside `add`, ahead of the transformer.
  ///
  /// A scope change and a **label** change both deliberately leave it alone,
  /// and read it instead: the keystroke either interrupted is still what the
  /// field says, so their own pass runs the pending text under the new scope
  /// or the new colours, and clears it. Dropping it and reading `state.query`
  /// instead is what made tapping a chip 100 ms into typing "p" search for
  /// nothing while the field plainly said "p".
  String? _pendingQuery;

  SearchBloc({
    required FolderSearchService searchService,
    required NoteStorageService noteService,
    required FolderStorageService folderService,
  }) : _searchService = searchService,
       _noteService = noteService,
       _folderService = folderService,
       super(const SearchState()) {
    on<SearchOpened>(_onOpened);
    on<SearchLabelsPrimed>(_onLabelsPrimed);
    on<SearchQueryChanged>(
      _onQueryChanged,
      transformer: debounce(queryDebounce),
    );
    on<SearchSubmitted>(_onSubmitted);
    on<SearchScopeChanged>(_onScopeChanged);
    on<SearchLabelsChanged>(_onLabelsChanged);
    on<SearchCleared>(_onCleared);
  }

  @override
  void onEvent(SearchEvent event) {
    super.onEvent(event);
    switch (event) {
      case SearchQueryChanged(:final query):
        _pendingQuery = query;
      case SearchOpened() || SearchSubmitted() || SearchCleared():
        _pendingQuery = null;
      case SearchScopeChanged() ||
          SearchLabelsChanged() ||
          SearchLabelsPrimed():
        break;
    }
  }

  Future<void> _onOpened(SearchOpened event, Emitter<SearchState> emit) async {
    final generation = ++_generation;
    emit(
      state.copyWith(
        scope: event.scope,
        query: '',
        phase: SearchPhase.idle,
        // A filter the user cannot see is a filter they cannot undo: the
        // field comes up empty, so a colour held over from the last time
        // search was open would quietly answer a question nobody asked. The
        // refresh paths, which re-dispatch this for a surface already on
        // screen, are the exception and say so.
        labels: event.keepLabels ? null : const {},
        titleHits: const [],
        contentHits: const [],
        folderPaths: const {},
        labelledTotal: 0,
        isSearching: true,
      ),
    );
    await _emitUnqueried(emit, event.scope, generation, reloadLabels: true);
  }

  /// Reads the chip row's colours for a surface that is not open yet, so the
  /// row exists on the frame it first appears on rather than a frame later.
  Future<void> _onLabelsPrimed(
    SearchLabelsPrimed event,
    Emitter<SearchState> emit,
  ) async {
    await _reloadLabelsInUse(emit, state.scope);
  }

  Future<void> _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query != _pendingQuery) return;

    if (event.query.trim().isEmpty) {
      final generation = ++_generation;
      await _emitUnqueried(emit, state.scope, generation);
      return;
    }

    if (state.phase == SearchPhase.full && state.query == event.query) return;

    // The refresh path a host runs on the way back from a note re-dispatches
    // the query already in state, where typing always changes it — so this is
    // where a colour picked in the editor a moment ago earns its chip. Fresh
    // keystrokes deliberately skip the reload: typing cannot change which
    // labels exist, and the typing path pays for every await on it.
    final reloadLabels =
        state.phase == SearchPhase.quick && state.query == event.query;

    final generation = ++_generation;
    emit(
      state.copyWith(
        query: event.query,
        phase: SearchPhase.quick,
        recents: const [],
        isSearching: true,
      ),
    );
    await _runQuick(
      emit,
      event.query,
      state.scope,
      generation,
      reloadLabels: reloadLabels,
    );
  }

  Future<void> _onSubmitted(
    SearchSubmitted event,
    Emitter<SearchState> emit,
  ) async {
    final generation = ++_generation;
    if (event.query.trim().isEmpty) {
      await _emitUnqueried(emit, state.scope, generation, reloadLabels: true);
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
    await _runFull(
      emit,
      event.query,
      state.scope,
      generation,
      reloadLabels: true,
    );
  }

  Future<void> _onScopeChanged(
    SearchScopeChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (event.scope == state.scope) return;

    // Idle has nothing scoped on screen — recents are global — so the chip
    // only records the choice the next query will run under, and [_generation]
    // is deliberately left alone: a recents load still in flight is still the
    // right list. The colour chips beside it are scoped, though, so that half
    // is re-read even here.
    if (state.phase == SearchPhase.idle) {
      emit(state.copyWith(scope: event.scope));
      await _reloadLabelsInUse(emit, event.scope);
      return;
    }

    final generation = ++_generation;
    final query = state.query;
    emit(state.copyWith(scope: event.scope, isSearching: true));

    // A quick phase with nothing typed is the colour listing, which is not a
    // query to re-run but a listing to re-make under the new scope.
    if (query.trim().isEmpty) {
      await _emitUnqueried(emit, event.scope, generation, reloadLabels: true);
      return;
    }

    switch (state.phase) {
      case SearchPhase.quick:
        await _runQuick(
          emit,
          query,
          event.scope,
          generation,
          reloadLabels: true,
        );
      case SearchPhase.full:
        await _runFull(
          emit,
          query,
          event.scope,
          generation,
          reloadLabels: true,
        );
      case SearchPhase.idle:
        break;
    }
  }

  /// Re-reads the chip row's colours on their own, for the one transition
  /// that changes which labels are on offer without changing what is listed.
  ///
  /// Guarded on the scope rather than on [_generation]: nothing else in the
  /// state moves here, so bumping the generation would cancel a recents load
  /// still in flight, and the scope this was read for is exactly what makes
  /// it stale.
  Future<void> _reloadLabelsInUse(
    Emitter<SearchState> emit,
    SearchScope scope,
  ) async {
    try {
      final labelsInUse = await _noteService.labelsInUse(
        folderIds: await _folderIdsFor(scope),
      );
      if (state.scope != scope) return;
      emit(state.copyWith(labelsInUse: labelsInUse));
    } catch (e, stackTrace) {
      _logError('Loading labels in use failed', e, stackTrace);
    }
  }

  Future<void> _onLabelsChanged(
    SearchLabelsChanged event,
    Emitter<SearchState> emit,
  ) async {
    if (setEquals(event.labels, state.labels)) return;

    final generation = ++_generation;
    // The text on screen, which a keystroke still inside the debounce has
    // not put into the state yet: a chip tapped 100 ms into typing "p" must
    // filter "p", not run a colour-only listing under a field that says "p".
    // Taking the pending text here is also what drops that keystroke — it
    // fires with nothing left to match against and returns — so the tap
    // costs one pass rather than two.
    final query = _pendingQuery ?? state.query;
    _pendingQuery = null;
    emit(state.copyWith(labels: event.labels, query: query, isSearching: true));

    // With nothing typed the colours *are* the query, so dropping the last
    // one is what puts the surface back to recents.
    if (query.trim().isEmpty) {
      await _emitUnqueried(emit, state.scope, generation);
      return;
    }

    switch (state.phase) {
      case SearchPhase.full:
        await _runFull(emit, query, state.scope, generation);
      case SearchPhase.quick:
      case SearchPhase.idle:
        await _runQuick(emit, query, state.scope, generation);
    }
  }

  Future<void> _onCleared(
    SearchCleared event,
    Emitter<SearchState> emit,
  ) async {
    final generation = ++_generation;
    await _emitUnqueried(emit, state.scope, generation, reloadLabels: true);
  }

  /// What an empty field means, which depends on whether a colour is picked:
  /// recents when nothing filters, and otherwise the listing of everything
  /// wearing the picked colours — "everything red" is a question, and idle
  /// recents would be the wrong answer to it.
  Future<void> _emitUnqueried(
    Emitter<SearchState> emit,
    SearchScope scope,
    int generation, {
    bool reloadLabels = false,
  }) async {
    if (state.labels.isEmpty) {
      await _emitRecents(emit, scope, generation, reloadLabels: reloadLabels);
      return;
    }
    emit(
      state.copyWith(
        query: '',
        phase: SearchPhase.quick,
        recents: const [],
        isSearching: true,
      ),
    );
    await _runLabelled(emit, scope, generation, reloadLabels: reloadLabels);
  }

  /// The colour listing, which stands in for the whole idle list and is
  /// therefore capped where that list is rather than at the handful of hits a
  /// typed query shows.
  Future<void> _runLabelled(
    Emitter<SearchState> emit,
    SearchScope scope,
    int generation, {
    bool reloadLabels = false,
  }) async {
    try {
      final folderIds = await _folderIdsFor(scope);
      final (listing, labelsInUse) = await (
        _searchService.labelledNotes(
          labels: state.labels,
          folderIds: folderIds,
          limit: recentsPageSize,
        ),
        _labelsInUseIf(reloadLabels, folderIds),
      ).wait;
      await _emitResults(
        emit,
        query: '',
        scope: scope,
        phase: SearchPhase.quick,
        results: listing.results,
        generation: generation,
        labelsInUse: labelsInUse,
        labelledTotal: listing.total,
      );
    } catch (e, stackTrace) {
      _logError('Listing labelled notes failed', e, stackTrace);
      if (generation != _generation) return;
      emit(state.copyWith(isSearching: false));
    }
  }

  Future<void> _runQuick(
    Emitter<SearchState> emit,
    String query,
    SearchScope scope,
    int generation, {
    bool reloadLabels = false,
  }) async {
    try {
      final folderIds = await _folderIdsFor(scope);
      final (results, labelsInUse) = await (
        _searchService.quickSearch(
          query,
          folderIds: folderIds,
          labels: state.labels,
          limit: FolderSearchService.quickHitLimit,
        ),
        _labelsInUseIf(reloadLabels, folderIds),
      ).wait;
      await _emitResults(
        emit,
        query: query,
        scope: scope,
        phase: SearchPhase.quick,
        results: results,
        generation: generation,
        labelsInUse: labelsInUse,
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
    int generation, {
    bool reloadLabels = false,
  }) async {
    try {
      final folderIds = await _folderIdsFor(scope);
      final labels = state.labels;
      final (results, labelsInUse) = await (
        _searchService.search(
          query,
          filter: folderIds == null && labels.isEmpty
              ? null
              : SearchFilter(folderIds: folderIds, labels: labels),
        ),
        _labelsInUseIf(reloadLabels, folderIds),
      ).wait;
      await _emitResults(
        emit,
        query: query,
        scope: scope,
        phase: SearchPhase.full,
        results: results,
        generation: generation,
        labelsInUse: labelsInUse,
      );
    } catch (e, stackTrace) {
      _logError('Search failed', e, stackTrace);
      if (generation != _generation) return;
      emit(state.copyWith(isSearching: false));
    }
  }

  Future<void> _emitRecents(
    Emitter<SearchState> emit,
    SearchScope scope,
    int generation, {
    bool reloadLabels = false,
  }) async {
    try {
      // The recents and the chips answer different questions — one unscoped,
      // one scoped — so neither waits on the other. Only the paths depend on
      // the page, and they are read after it.
      final (page, labelsInUse) = await (
        _noteService.loadNotesPaginated(
          pageSize: recentsPageSize,
          sortOrder: NotesSortOrder.updatedDesc,
        ),
        reloadLabels
            ? _folderIdsFor(
                scope,
              ).then((ids) => _noteService.labelsInUse(folderIds: ids))
            : Future<List<ItemLabel>?>.value(),
      ).wait;
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
          labelsInUse: _labelsInUseForScope(labelsInUse, scope),
          labelledTotal: 0,
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
          folderPaths: const {},
          labelledTotal: 0,
          isSearching: false,
        ),
      );
    }
  }

  /// The colours read for [scope], or null — which [SearchState.copyWith]
  /// reads as "keep what is there" — when the surface has moved to another
  /// scope since.
  ///
  /// A scope change while idle deliberately does not bump [_generation], so
  /// the open pass it interrupted is still allowed to land; its chips are the
  /// one part of it that has gone stale, and this is what drops them.
  List<ItemLabel>? _labelsInUseForScope(
    List<ItemLabel>? labelsInUse,
    SearchScope scope,
  ) {
    if (labelsInUse == null || state.scope != scope) return null;
    return labelsInUse;
  }

  /// The colours in use, or a future of null when this pass is not the one
  /// paying for them — so every caller can put the two reads side by side.
  Future<List<ItemLabel>?> _labelsInUseIf(bool reload, Set<String>? folderIds) {
    if (!reload) return Future<List<ItemLabel>?>.value();
    return _noteService.labelsInUse(folderIds: folderIds);
  }

  /// Splits [results] the way the surface groups them: a note whose title
  /// matched is a title hit even when its body matched too, so it is listed
  /// once, under the section that explains why it is there.
  ///
  /// A label-only pass has no matched text anywhere, so every row would fall
  /// to "In text" under a heading about text nothing was found in. They are
  /// all title hits instead, and the surface heads them with the colours
  /// that selected them.
  Future<void> _emitResults(
    Emitter<SearchState> emit, {
    required String query,
    required SearchScope scope,
    required SearchPhase phase,
    required List<SearchResult> results,
    required int generation,
    List<ItemLabel>? labelsInUse,
    int labelledTotal = 0,
  }) async {
    final unqueried = query.trim().isEmpty;
    final titleHits = <SearchResult>[];
    final contentHits = <SearchResult>[];
    for (final result in results) {
      final isTitleHit =
          unqueried ||
          result.matches.any((match) => match.type == SearchMatchType.title);
      (isTitleHit ? titleHits : contentHits).add(result);
    }

    final folderPaths = await _pathsFor([
      for (final result in results) result.metadata,
    ]);
    if (generation != _generation) return;

    final labels = _labelsInUseForScope(labelsInUse, scope);

    emit(
      state.copyWith(
        query: query,
        scope: scope,
        phase: phase,
        recents: const [],
        titleHits: titleHits,
        contentHits: contentHits,
        folderPaths: folderPaths,
        labelsInUse: labels,
        labelledTotal: labelledTotal,
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
