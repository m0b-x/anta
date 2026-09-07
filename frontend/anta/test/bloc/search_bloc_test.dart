import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/search/search_bloc.dart';
import 'package:anta/controllers/in_place_search_controller.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/models/search_scope.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';

/// The bloc under test never reaches storage on its own — every service it
/// talks to is scripted here — so these assertions are about routing, phases
/// and grouping and nothing else.
///
/// The two storage fakes `extend` rather than `implement` their services:
/// both take a repository, so a lazily-opened in-memory database (never
/// queried, because every method the bloc calls is overridden) costs less
/// than two dozen `UnimplementedError` stubs that would silently rot the next
/// time either service grows a member.
class _FakeSearchService implements FolderSearchService {
  final List<({String query, Set<String>? folderIds})> quickCalls = [];
  final List<({String query, SearchFilter? filter})> searchCalls = [];

  List<SearchResult> quickResults = const [];
  List<SearchResult> fullResults = const [];
  Object? failure;

  /// Held open to park a quick pass mid-flight, so a later event can be
  /// proven to win regardless of which query resolves first.
  Completer<void>? quickGate;

  @override
  Future<List<SearchResult>> quickSearch(
    String query, {
    Set<String>? folderIds,
    int limit = 10,
    bool caseSensitive = false,
  }) async {
    quickCalls.add((query: query, folderIds: folderIds));
    if (quickGate != null) await quickGate!.future;
    if (failure != null) throw failure!;
    return quickResults;
  }

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilter? filter,
    int limit = 50,
    bool caseSensitive = false,
  }) async {
    searchCalls.add((query: query, filter: filter));
    if (failure != null) throw failure!;
    return fullResults;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> buildIndex() async {}

  @override
  Future<void> updateIndex(String noteId, String title, String content) async {}

  @override
  Future<void> removeFromIndex(String noteId) async {}

  @override
  void dispose() {}

  @override
  Future<void> close() async {}
}

class _FakeNoteStorage extends NoteStorageService {
  _FakeNoteStorage(NoteRepository repository) : super(repository: repository);

  List<NoteMetadata> recents = const [];
  int pageSizeAsked = 0;
  NotesSortOrder? sortOrderAsked;
  Object? failure;

  /// Held open to make the recents load finish *after* whatever event came
  /// next — the ordering the tag path hits in the wild.
  Completer<void>? recentsGate;

  @override
  Future<PaginatedNotes> loadNotesPaginated({
    String? folderId,
    int page = 1,
    int pageSize = NoteStorageService.defaultPageSize,
    NotesSortOrder sortOrder = NotesSortOrder.updatedDesc,
  }) async {
    pageSizeAsked = pageSize;
    sortOrderAsked = sortOrder;
    if (recentsGate != null) await recentsGate!.future;
    if (failure != null) throw failure!;
    return PaginatedNotes(
      notes: recents,
      currentPage: 1,
      totalPages: 1,
      totalCount: recents.length,
      hasMore: false,
    );
  }
}

class _FakeFolderStorage extends FolderStorageService {
  _FakeFolderStorage(FolderRepository repository)
    : super(repository: repository);

  Map<String, Set<String>> subtrees = const {};
  Map<String, List<String>> paths = const {};
  final List<String> subtreeCalls = [];

  @override
  Future<Set<String>> subtreeIds(String folderId) async {
    subtreeCalls.add(folderId);
    return subtrees[folderId] ?? {folderId};
  }

  @override
  Future<Map<String, List<String>>> folderPathSegments(
    Iterable<String> folderIds,
  ) async {
    return {
      for (final id in folderIds.toSet())
        if (paths.containsKey(id)) id: paths[id]!,
    };
  }
}

NoteMetadata _note(String id, {String folderId = 'f1', String title = ''}) {
  final now = DateTime(2026, 9, 6);
  return NoteMetadata(
    id: id,
    folderId: folderId,
    title: title.isEmpty ? 'Note $id' : title,
    preview: 'preview $id',
    contentLength: 10,
    chunkCount: 1,
    isCompressed: false,
    createdAt: now,
    updatedAt: now,
  );
}

SearchResult _hit(NoteMetadata metadata, List<SearchMatchType> types) {
  return SearchResult(
    metadata: metadata,
    matches: [
      for (final type in types)
        SearchMatch(text: 'squat', startIndex: 0, endIndex: 5, type: type),
    ],
    relevanceScore: 1,
  );
}

void main() {
  late AppDatabase db;
  late _FakeSearchService searchService;
  late _FakeNoteStorage noteStorage;
  late _FakeFolderStorage folderStorage;

  setUpAll(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDownAll(() async => db.close());

  setUp(() {
    searchService = _FakeSearchService();
    noteStorage = _FakeNoteStorage(NoteRepository(database: db));
    folderStorage = _FakeFolderStorage(FolderRepository(database: db));
  });

  SearchBloc buildBloc() => SearchBloc(
    searchService: searchService,
    noteService: noteStorage,
    folderService: folderStorage,
  );

  Future<void> settleDebounce() async {
    await Future<void>.delayed(SearchBloc.queryDebounce * 2);
    await pumpEventQueue();
  }

  group('opening', () {
    test('idle loads recents and the folder path of every row', () async {
      noteStorage.recents = [_note('a'), _note('b', folderId: 'f2')];
      folderStorage.paths = {
        'f1': ['Training'],
        'f2': ['Training', 'Winter block'],
      };
      final bloc = buildBloc();

      bloc.add(const SearchOpened());
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.recents, hasLength(2));
      expect(bloc.state.folderPaths['f2'], ['Training', 'Winter block']);
      expect(bloc.state.isSearching, isFalse);
      await bloc.close();
    });

    test('recents are the most recently edited notes, unscoped', () async {
      final bloc = buildBloc();

      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      expect(noteStorage.pageSizeAsked, SearchBloc.recentsPageSize);
      expect(noteStorage.sortOrderAsked, NotesSortOrder.updatedDesc);
      expect(folderStorage.subtreeCalls, isEmpty);
      expect(
        bloc.state.scope,
        const FolderScope(folderId: 'f1', name: 'Training'),
      );
      await bloc.close();
    });
  });

  group('typing', () {
    test('a burst of keystrokes runs one quick pass, for the last', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('s'));
      bloc.add(const SearchQueryChanged('sq'));
      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      expect(searchService.quickCalls, hasLength(1));
      expect(searchService.quickCalls.single.query, 'squat');
      expect(bloc.state.phase, SearchPhase.quick);
      expect(bloc.state.query, 'squat');
      await bloc.close();
    });

    test('a folder scope reaches the service as its whole subtree', () async {
      folderStorage.subtrees = {
        'f1': {'f1', 'f2', 'f3'},
      };
      final bloc = buildBloc();
      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      expect(searchService.quickCalls.single.folderIds, {'f1', 'f2', 'f3'});
      await bloc.close();
    });

    test('everywhere passes no folder set at all', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      expect(searchService.quickCalls.single.folderIds, isNull);
      expect(folderStorage.subtreeCalls, isEmpty);
      await bloc.close();
    });

    test('emptying the field is handled without waiting for a query', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      bloc.add(const SearchCleared());
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.hasResults, isFalse);
      await bloc.close();
    });
  });

  group('grouping', () {
    test(
      'a note matching title and body is listed under titles only',
      () async {
        final both = _note('a');
        final bodyOnly = _note('b');
        searchService.fullResults = [
          _hit(both, [SearchMatchType.title, SearchMatchType.content]),
          _hit(bodyOnly, [SearchMatchType.content]),
        ];
        final bloc = buildBloc();
        bloc.add(const SearchOpened());
        await pumpEventQueue();

        bloc.add(const SearchSubmitted('squat'));
        await pumpEventQueue();

        expect(
          bloc.state.titleHits.map((r) => r.metadata.id),
          ['a'],
          reason: 'a title hit is a title hit even when the body matched too',
        );
        expect(bloc.state.contentHits.map((r) => r.metadata.id), ['b']);
        expect(bloc.state.phase, SearchPhase.full);
        await bloc.close();
      },
    );

    test('a hit with no located match still shows, under in-text', () async {
      searchService.fullResults = [_hit(_note('a'), const [])];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchSubmitted('squat lunge'));
      await pumpEventQueue();

      expect(bloc.state.titleHits, isEmpty);
      expect(bloc.state.contentHits, hasLength(1));
      await bloc.close();
    });

    test('submitting sends the subtree through the filter', () async {
      folderStorage.subtrees = {
        'f1': {'f1', 'f2'},
      };
      final bloc = buildBloc();
      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      expect(searchService.searchCalls.single.filter?.folderIds, {'f1', 'f2'});
      await bloc.close();
    });

    test('everywhere submits with no filter', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      expect(searchService.searchCalls.single.filter, isNull);
      await bloc.close();
    });
  });

  group('scope changes', () {
    test('re-runs the quick pass that is showing', () async {
      folderStorage.subtrees = {
        'f1': {'f1', 'f2'},
      };
      final bloc = buildBloc();
      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();
      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      bloc.add(const SearchScopeChanged(SearchScope.everywhere()));
      await pumpEventQueue();

      expect(searchService.quickCalls, hasLength(2));
      expect(searchService.quickCalls.last.query, 'squat');
      expect(searchService.quickCalls.last.folderIds, isNull);
      expect(bloc.state.scope, const EverywhereScope());
      await bloc.close();
    });

    test('re-runs the full pass that is showing', () async {
      folderStorage.subtrees = {
        'f1': {'f1', 'f2'},
      };
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      bloc.add(
        const SearchScopeChanged(
          SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      expect(searchService.searchCalls, hasLength(2));
      expect(searchService.searchCalls.last.filter?.folderIds, {'f1', 'f2'});
      await bloc.close();
    });

    test('while idle it only records the choice', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(
        const SearchScopeChanged(
          SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      expect(searchService.quickCalls, isEmpty);
      expect(searchService.searchCalls, isEmpty);
      expect(
        bloc.state.scope,
        const FolderScope(folderId: 'f1', name: 'Training'),
      );
      await bloc.close();
    });

    test('re-selecting the scope already searching does nothing', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      bloc.add(const SearchScopeChanged(SearchScope.everywhere()));
      await pumpEventQueue();

      expect(searchService.searchCalls, hasLength(1));
      await bloc.close();
    });
  });

  /// Only [SearchQueryChanged] has a transformer, so handlers of different
  /// event types run concurrently and the slowest one lands last. These pin
  /// the rule that decides the winner: the newest event owns the screen, and
  /// anything older that finishes afterwards is dropped rather than painted.
  group('races between event types', () {
    test('a tag open whose recents resolve after the search keeps the '
        'results', () async {
      final gate = Completer<void>();
      noteStorage.recentsGate = gate;
      noteStorage.recents = [_note('r')];
      searchService.fullResults = [
        _hit(_note('a'), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();

      bloc.add(const SearchOpened());
      bloc.add(const SearchSubmitted('#tag'));
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.full);
      expect(bloc.state.titleHits.map((r) => r.metadata.id), ['a']);

      gate.complete();
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.full);
      expect(bloc.state.titleHits.map((r) => r.metadata.id), ['a']);
      expect(bloc.state.query, '#tag');
      expect(bloc.state.recents, isEmpty);
      await bloc.close();
    });

    test('a debounced keystroke does not downgrade a submitted search for '
        'the same text', () async {
      searchService.fullResults = [
        _hit(_note('a'), [SearchMatchType.content]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('squat'));
      bloc.add(const SearchSubmitted('squat'));
      await settleDebounce();

      expect(searchService.quickCalls, isEmpty);
      expect(searchService.searchCalls, hasLength(1));
      expect(bloc.state.phase, SearchPhase.full);
      await bloc.close();
    });

    test('a slow quick pass landing after the field was cleared is '
        'dropped', () async {
      final gate = Completer<void>();
      searchService.quickGate = gate;
      searchService.quickResults = [
        _hit(_note('a'), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();
      expect(searchService.quickCalls, hasLength(1));

      bloc.add(const SearchCleared());
      await pumpEventQueue();
      expect(bloc.state.phase, SearchPhase.idle);

      gate.complete();
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.hasResults, isFalse);
      expect(bloc.state.query, isEmpty);
      await bloc.close();
    });

    test(
      'changing the scope while idle survives the recents landing',
      () async {
        final gate = Completer<void>();
        noteStorage.recentsGate = gate;
        noteStorage.recents = [_note('r')];
        final bloc = buildBloc();

        bloc.add(
          const SearchOpened(
            scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
          ),
        );
        await pumpEventQueue();
        bloc.add(const SearchScopeChanged(SearchScope.everywhere()));
        await pumpEventQueue();

        gate.complete();
        await pumpEventQueue();

        expect(bloc.state.scope, const EverywhereScope());
        expect(bloc.state.recents, hasLength(1));
        await bloc.close();
      },
    );
  });

  group('failures', () {
    test('a throwing search clears the spinner instead of hanging', () async {
      searchService.failure = StateError('index unavailable');
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      expect(bloc.state.isSearching, isFalse);
      expect(bloc.state.hasResults, isFalse);
      await bloc.close();
    });

    test('a failed recents load leaves no path map behind', () async {
      searchService.fullResults = [
        _hit(_note('a', folderId: 'f2'), const [SearchMatchType.title]),
      ];
      folderStorage.paths = {
        'f2': ['Training', 'Winter block'],
      };
      final bloc = buildBloc();
      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();
      expect(bloc.state.folderPaths, isNotEmpty);

      noteStorage.failure = StateError('storage unavailable');
      bloc.add(const SearchCleared());
      await pumpEventQueue();

      expect(bloc.state.recents, isEmpty);
      expect(
        bloc.state.folderPaths,
        isEmpty,
        reason:
            'the rows those paths belong to are gone; a path lane keyed by a '
            'folder no row is in is stale data waiting to be painted',
      );
      await bloc.close();
    });
  });

  group('reopening', () {
    test('drops the hits the last query left on screen', () async {
      searchService.fullResults = [
        _hit(_note('a'), const [SearchMatchType.title]),
      ];
      noteStorage.recents = [_note('b')];
      final bloc = buildBloc();
      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();
      expect(bloc.state.hasResults, isTrue);

      bloc.add(const SearchOpened());
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.titleHits, isEmpty);
      expect(bloc.state.contentHits, isEmpty);
      expect(bloc.state.recents, hasLength(1));
      await bloc.close();
    });

    test('shows recents rather than the previous results while it loads', () async {
      searchService.fullResults = [
        _hit(_note('a'), const [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      final gate = Completer<void>();
      noteStorage.recentsGate = gate;
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      // The surface paints its spinner off exactly this: searching, with
      // nothing to show. Stale hits under a fresh field is the alternative.
      expect(bloc.state.isSearching, isTrue);
      expect(bloc.state.hasResults, isFalse);

      gate.complete();
      await pumpEventQueue();
      await bloc.close();
    });

    test('the searching flag is up before the bloc emits anything', () async {
      noteStorage.recents = [_note('a')];
      final bloc = buildBloc();
      final search = InPlaceSearchController(bloc: bloc);
      bool? flagAtFirstEmit;
      final sub = bloc.stream.listen((_) {
        flagAtFirstEmit ??= search.isSearching;
      });

      search.open(const SearchScope.everywhere());
      await pumpEventQueue();

      expect(
        flagAtFirstEmit,
        isTrue,
        reason:
            'both hosts guard their results with `buildWhen: (_, __) => '
            '_searching`, which *drops* states rather than deferring them — '
            'so every emit of this bloc has to happen with the flag already '
            'up, or the surface opens on a state it never sees again',
      );
      await sub.cancel();
      search.dispose();
    });
  });
}
