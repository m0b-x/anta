import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/search/search_bloc.dart';
import 'package:anta/controllers/in_place_search_controller.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
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
  final List<
    ({String query, Set<String>? folderIds, Set<ItemLabel> labels, int limit})
  >
  quickCalls = [];
  final List<({String query, SearchFilter? filter})> searchCalls = [];

  /// Every colour listing asked for: the set, the scope it was scoped to and
  /// the cap. The listing stands in for the whole idle list, so the cap is
  /// part of its contract.
  final List<({Set<ItemLabel> labels, Set<String>? folderIds, int limit})>
  labelledCalls = [];

  List<SearchResult> quickResults = const [];
  List<SearchResult> fullResults = const [];
  List<SearchResult> labelledResults = const [];
  int labelledTotal = 0;
  Object? failure;

  /// Held open to park a quick pass mid-flight, so a later event can be
  /// proven to win regardless of which query resolves first.
  Completer<void>? quickGate;

  @override
  Future<List<SearchResult>> quickSearch(
    String query, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
    int limit = FolderSearchService.quickHitLimit,
    bool caseSensitive = false,
  }) async {
    quickCalls.add((
      query: query,
      folderIds: folderIds,
      labels: labels,
      limit: limit,
    ));
    if (quickGate != null) await quickGate!.future;
    if (failure != null) throw failure!;
    return quickResults;
  }

  @override
  Future<({List<SearchResult> results, int total})> labelledNotes({
    required Set<ItemLabel> labels,
    Set<String>? folderIds,
    int limit = 50,
  }) async {
    labelledCalls.add((labels: labels, folderIds: folderIds, limit: limit));
    if (failure != null) throw failure!;
    return (results: labelledResults, total: labelledTotal);
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

  /// What the next [labelsInUse] answers, and every scope it was asked for —
  /// the chip row is scoped, so which subtree the bloc handed down is part of
  /// the contract.
  List<ItemLabel> inUse = const [];
  final List<Set<String>?> labelsInUseCalls = [];

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

  @override
  Future<List<ItemLabel>> labelsInUse({Set<String>? folderIds}) async {
    labelsInUseCalls.add(folderIds);
    return inUse;
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

NoteMetadata _note(
  String id, {
  String folderId = 'f1',
  String title = '',
  ItemLabel label = ItemLabel.none,
}) {
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
    label: label,
  );
}

/// A result with no located match, which is exactly what a label-only pass
/// produces: nothing was searched for, so there is nothing to highlight.
SearchResult _unmatched(NoteMetadata metadata) {
  return SearchResult(metadata: metadata, matches: const [], relevanceScore: 0);
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
      expect(
        noteStorage.labelsInUseCalls,
        hasLength(1),
        reason:
            'the subtree is resolved once per open, for the colour chips — '
            'which are scoped even though the recents beside them are not',
      );
      expect(folderStorage.subtreeCalls, ['f1']);
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
    test('a keystroke still in the debounce when the field is emptied is '
        'dropped', () async {
      searchService.quickResults = [
        _hit(_note('a'), [SearchMatchType.title]),
      ];
      noteStorage.recents = [_note('r')];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('pr'));
      await settleDebounce();
      expect(bloc.state.phase, SearchPhase.quick);

      bloc.add(const SearchQueryChanged('p'));
      bloc.add(const SearchCleared());
      await settleDebounce();

      expect(searchService.quickCalls.map((call) => call.query), ['pr']);
      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.hasResults, isFalse);
      expect(bloc.state.recents.map((note) => note.id), ['r']);
      await bloc.close();
    });

    test('a keystroke still in the debounce when the surface is reopened is '
        'dropped', () async {
      searchService.quickResults = [
        _hit(_note('a'), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('p'));
      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Legs'),
        ),
      );
      await settleDebounce();

      expect(searchService.quickCalls, isEmpty);
      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.query, isEmpty);
      expect(
        bloc.state.scope,
        const SearchScope.folder(folderId: 'f1', name: 'Legs'),
      );
      await bloc.close();
    });

    test(
      'a scope change does not swallow the keystroke it interrupted',
      () async {
        searchService.quickResults = [
          _hit(_note('a'), [SearchMatchType.title]),
        ];
        folderStorage.subtrees = {
          'f1': {'f1', 'f1a'},
        };
        final bloc = buildBloc();
        bloc.add(const SearchOpened());
        await pumpEventQueue();

        bloc.add(const SearchQueryChanged('p'));
        bloc.add(
          const SearchScopeChanged(
            SearchScope.folder(folderId: 'f1', name: 'Legs'),
          ),
        );
        await settleDebounce();

        expect(searchService.quickCalls.single.query, 'p');
        expect(searchService.quickCalls.single.folderIds, {'f1', 'f1a'});
        expect(bloc.state.phase, SearchPhase.quick);
        expect(bloc.state.query, 'p');
        await bloc.close();
      },
    );

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

    test('an open pass landing after an idle scope change does not put its '
        'chips back', () async {
      final gate = Completer<void>();
      noteStorage.recentsGate = gate;
      noteStorage.recents = [_note('r')];
      noteStorage.inUse = const [ItemLabel.red];
      final bloc = buildBloc();

      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      // Everywhere wears a different set, and the open is still parked.
      noteStorage.inUse = const [ItemLabel.blue];
      bloc.add(const SearchScopeChanged(SearchScope.everywhere()));
      await pumpEventQueue();
      expect(bloc.state.labelsInUse, const [ItemLabel.blue]);

      gate.complete();
      await pumpEventQueue();

      expect(
        bloc.state.labelsInUse,
        const [ItemLabel.blue],
        reason:
            'an idle scope change deliberately does not bump the generation, '
            'so the open still lands — but the chips it read are about a '
            'scope the surface has left',
      );
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

  /// A colour chip filters whatever pass is showing, and with the field empty
  /// it *is* the pass: "everything red" is a question, and idle recents are
  /// the wrong answer to it.
  group('label filtering', () {
    test('opening loads the colours worth offering', () async {
      noteStorage.inUse = const [ItemLabel.red, ItemLabel.teal];
      final bloc = buildBloc();

      bloc.add(const SearchOpened());
      await pumpEventQueue();

      expect(bloc.state.labelsInUse, const [ItemLabel.red, ItemLabel.teal]);
      expect(noteStorage.labelsInUseCalls, [null]);
      await bloc.close();
    });

    test('a folder scope asks about that subtree, not the whole app', () async {
      folderStorage.subtrees = {
        'f1': {'f1', 'f2'},
      };
      noteStorage.inUse = const [ItemLabel.blue];
      final bloc = buildBloc();

      bloc.add(
        const SearchOpened(
          scope: SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      expect(noteStorage.labelsInUseCalls, [
        {'f1', 'f2'},
      ]);
      await bloc.close();
    });

    test('changing the scope re-reads them', () async {
      folderStorage.subtrees = {
        'f1': {'f1', 'f2'},
      };
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      noteStorage.inUse = const [ItemLabel.pink];

      bloc.add(
        const SearchScopeChanged(
          SearchScope.folder(folderId: 'f1', name: 'Training'),
        ),
      );
      await pumpEventQueue();

      expect(noteStorage.labelsInUseCalls, [
        null,
        {'f1', 'f2'},
      ]);
      expect(bloc.state.labelsInUse, const [ItemLabel.pink]);
      expect(searchService.quickCalls, isEmpty);
      await bloc.close();
    });

    test('the refresh a host runs on the way back from a note re-reads '
        'them, a keystroke does not', () async {
      searchService.quickResults = [
        _hit(_note('a'), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      expect(
        noteStorage.labelsInUseCalls,
        hasLength(1),
        reason: 'typing cannot change which colours exist',
      );

      // What `InPlaceSearchController.refresh` dispatches for a quick pass:
      // the query already in state, which typing never repeats.
      noteStorage.inUse = const [ItemLabel.green];
      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      expect(noteStorage.labelsInUseCalls, hasLength(2));
      expect(bloc.state.labelsInUse, const [ItemLabel.green]);
      await bloc.close();
    });

    test('a colour with an empty query lists the labelled notes, as a quick '
        'pass', () async {
      noteStorage.recents = [_note('r')];
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
        _unmatched(_note('b', label: ItemLabel.red)),
      ];
      searchService.labelledTotal = 2;
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.quick);
      expect(bloc.state.labels, const {ItemLabel.red});
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.recents, isEmpty);
      expect(bloc.state.titleHits.map((r) => r.metadata.id), ['a', 'b']);
      expect(
        bloc.state.contentHits,
        isEmpty,
        reason:
            'nothing was searched for, so nothing can be an "In text" hit — '
            'they belong under the header that names the colours',
      );
      expect(
        searchService.quickCalls,
        isEmpty,
        reason:
            'a colour with nothing typed is a listing, not a search with an '
            'empty query',
      );
      expect(searchService.labelledCalls.single.labels, const {ItemLabel.red});
      expect(
        searchService.labelledCalls.single.limit,
        SearchBloc.recentsPageSize,
        reason:
            'this listing stands in for the whole idle list, not for ten hits',
      );
      await bloc.close();
    });

    test('the header\'s total comes off the listing, not the rows it '
        'returned', () async {
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
      ];
      searchService.labelledTotal = 97;
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      expect(bloc.state.titleHits, hasLength(1));
      expect(
        bloc.state.labelledTotal,
        97,
        reason:
            'the listing is capped and the header is not: counting the rows '
            'that fitted would put the one wrong number on screen',
      );
      await bloc.close();
    });

    test(
      'a pass that is not a colour listing leaves no total behind',
      () async {
        searchService.labelledResults = [
          _unmatched(_note('a', label: ItemLabel.red)),
        ];
        searchService.labelledTotal = 97;
        searchService.quickResults = [
          _hit(_note('b', label: ItemLabel.red), [SearchMatchType.title]),
        ];
        final bloc = buildBloc();
        bloc.add(const SearchOpened());
        await pumpEventQueue();
        bloc.add(const SearchLabelsChanged({ItemLabel.red}));
        await pumpEventQueue();
        expect(bloc.state.labelledTotal, 97);

        bloc.add(const SearchQueryChanged('squat'));
        await settleDebounce();

        expect(bloc.state.labelledTotal, 0);
        await bloc.close();
      },
    );

    test('adding a query narrows within the colour', () async {
      searchService.quickResults = [
        _hit(_note('a', label: ItemLabel.red), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();

      expect(searchService.quickCalls.last.query, 'squat');
      expect(searchService.quickCalls.last.labels, const {ItemLabel.red});
      expect(
        searchService.quickCalls.last.limit,
        FolderSearchService.quickHitLimit,
      );
      expect(bloc.state.labels, const {ItemLabel.red});
      await bloc.close();
    });

    test('a submitted search carries the colour in its filter', () async {
      searchService.fullResults = [
        _hit(_note('a'), [SearchMatchType.content]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.teal}));
      await pumpEventQueue();

      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      expect(searchService.searchCalls.single.filter?.labels, const {
        ItemLabel.teal,
      });
      expect(searchService.searchCalls.single.filter?.folderIds, isNull);
      await bloc.close();
    });

    test('picking a second colour re-runs the pass on screen', () async {
      searchService.fullResults = [
        _hit(_note('a'), [SearchMatchType.content]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchSubmitted('squat'));
      await pumpEventQueue();

      bloc.add(const SearchLabelsChanged({ItemLabel.red, ItemLabel.teal}));
      await pumpEventQueue();

      expect(searchService.searchCalls, hasLength(2));
      expect(searchService.searchCalls.last.filter?.labels, const {
        ItemLabel.red,
        ItemLabel.teal,
      });
      expect(bloc.state.phase, SearchPhase.full);
      await bloc.close();
    });

    test('dropping the last colour with an empty query goes back to '
        'recents', () async {
      noteStorage.recents = [_note('r')];
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();
      expect(bloc.state.phase, SearchPhase.quick);

      bloc.add(const SearchLabelsChanged({}));
      await pumpEventQueue();

      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.labels, isEmpty);
      expect(bloc.state.hasResults, isFalse);
      expect(bloc.state.recents.map((note) => note.id), ['r']);
      await bloc.close();
    });

    test('clearing the field keeps the colour, and keeps its notes', () async {
      noteStorage.recents = [_note('r')];
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      bloc.add(const SearchCleared());
      await pumpEventQueue();

      expect(bloc.state.labels, const {ItemLabel.red});
      expect(bloc.state.phase, SearchPhase.quick);
      expect(bloc.state.titleHits.map((r) => r.metadata.id), ['a']);
      expect(bloc.state.recents, isEmpty);
      await bloc.close();
    });

    test('re-picking the colours already showing does nothing', () async {
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();
      final passes = searchService.labelledCalls.length;

      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      expect(searchService.labelledCalls, hasLength(passes));
      await bloc.close();
    });

    test('a pass in flight when a colour is picked is dropped', () async {
      final gate = Completer<void>();
      searchService.quickGate = gate;
      searchService.quickResults = [
        _hit(_note('stale'), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('squat'));
      await settleDebounce();
      expect(searchService.quickCalls, hasLength(1));

      // The chip's own pass is parked behind the same gate, so the order the
      // two resolve in is the file's: oldest first.
      searchService.quickResults = [
        _hit(_note('fresh', label: ItemLabel.red), [SearchMatchType.title]),
      ];
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      gate.complete();
      await pumpEventQueue();

      expect(
        bloc.state.titleHits.map((r) => r.metadata.id),
        ['fresh'],
        reason:
            'the generation guard has to cover a label change exactly like a '
            'query change, or the pass the chip replaced repaints over it',
      );
      expect(bloc.state.labels, const {ItemLabel.red});
      await bloc.close();
    });

    test('a colour picked mid-debounce filters the text the field is '
        'showing', () async {
      searchService.quickResults = [
        _hit(_note('a'), [SearchMatchType.title]),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchQueryChanged('p'));
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await settleDebounce();

      expect(
        searchService.quickCalls,
        hasLength(1),
        reason:
            'the chip\'s pass already carries the on-screen text, so the '
            'keystroke behind it finds nothing left to match and drops — one '
            'tap, one pass, no flicker',
      );
      expect(
        searchService.quickCalls.single.query,
        'p',
        reason:
            'the field plainly says "p"; running a colour-only listing under '
            'it would answer a question nobody asked',
      );
      expect(searchService.quickCalls.single.labels, const {ItemLabel.red});
      expect(
        searchService.labelledCalls,
        isEmpty,
        reason: 'there is text, so this is a search and not a listing',
      );
      expect(bloc.state.labels, const {ItemLabel.red});
      expect(bloc.state.query, 'p');
      await bloc.close();
    });

    test('a colour picked with nothing pending is still a listing', () async {
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
      ];
      final bloc = buildBloc();
      bloc.add(const SearchOpened());
      await pumpEventQueue();

      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await settleDebounce();

      expect(searchService.quickCalls, isEmpty);
      expect(searchService.labelledCalls, hasLength(1));
      expect(bloc.state.query, isEmpty);
      await bloc.close();
    });
  });

  /// The colour filter is the one part of the surface that outlives an empty
  /// field, which is exactly why leaving search has to end it: the field comes
  /// back blank, and a filter nobody can see is a filter nobody can undo.
  group('leaving and reopening', () {
    test('leaving search and reopening drops the colour filter', () async {
      noteStorage.recents = [_note('r')];
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
      ];
      final bloc = buildBloc();
      final search = InPlaceSearchController(bloc: bloc);

      search.open(const SearchScope.everywhere());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();
      expect(bloc.state.labels, const {ItemLabel.red});

      search.leave();
      await pumpEventQueue();
      expect(
        bloc.state.labels,
        const {ItemLabel.red},
        reason: 'leaving does not repaint the surface on its way off screen',
      );

      search.open(const SearchScope.everywhere());
      await pumpEventQueue();

      expect(bloc.state.labels, isEmpty);
      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.recents.map((note) => note.id), ['r']);
      search.dispose();
    });

    test('the refresh a host runs on the way back keeps it', () async {
      searchService.labelledResults = [
        _unmatched(_note('a', label: ItemLabel.red)),
      ];
      searchService.labelledTotal = 1;
      final bloc = buildBloc();
      final search = InPlaceSearchController(bloc: bloc);

      search.open(const SearchScope.everywhere());
      await pumpEventQueue();
      bloc.add(const SearchLabelsChanged({ItemLabel.red}));
      await pumpEventQueue();

      search.refresh();
      await pumpEventQueue();

      expect(
        bloc.state.labels,
        const {ItemLabel.red},
        reason:
            'the colours are what is on screen here; a refresh that dropped '
            'them would answer a different question than the one showing',
      );
      expect(bloc.state.titleHits.map((r) => r.metadata.id), ['a']);
      search.dispose();
    });
  });

  /// The chip row is part of the search bar's committed height, so the hosts
  /// that keep a bloc alive read the colours once at mount rather than letting
  /// an already-visible bar grow 60 dp a frame after search opens.
  group('priming the chips', () {
    test('the event loads the colours and touches nothing else', () async {
      noteStorage.inUse = const [ItemLabel.red, ItemLabel.blue];
      final bloc = buildBloc();

      bloc.add(const SearchLabelsPrimed());
      await pumpEventQueue();

      expect(bloc.state.labelsInUse, const [ItemLabel.red, ItemLabel.blue]);
      expect(bloc.state.phase, SearchPhase.idle);
      expect(bloc.state.query, isEmpty);
      expect(bloc.state.recents, isEmpty);
      expect(searchService.quickCalls, isEmpty);
      expect(searchService.searchCalls, isEmpty);
      expect(bloc.state.isSearching, isFalse);
      await bloc.close();
    });

    test('the in-place controller primes as it is built', () async {
      noteStorage.inUse = const [ItemLabel.teal];
      final bloc = buildBloc();
      final search = InPlaceSearchController(bloc: bloc);
      await pumpEventQueue();

      expect(bloc.state.labelsInUse, const [ItemLabel.teal]);
      expect(search.isSearching, isFalse);
      search.dispose();
    });
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

    test(
      'shows recents rather than the previous results while it loads',
      () async {
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
      },
    );

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
