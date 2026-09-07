import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_state.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/utils/bloc_helpers.dart';

/// Paging, reloading and bulk deleting, with storage scripted.
///
/// The fake `extends` the real service over a lazily-opened in-memory
/// database, the way [search_bloc_test] does: every method the bloc calls is
/// overridden, so nothing here reaches SQLite, and the service can still grow
/// members without a wall of `UnimplementedError` stubs going stale.
class _FakeNoteStorage extends NoteStorageService {
  _FakeNoteStorage(NoteRepository repository) : super(repository: repository);

  List<NoteMetadata> all = const [];
  final List<({int page, int pageSize})> loads = [];
  final List<List<String>> bulkDeletes = [];
  final List<List<String>> preloads = [];

  /// How many of the next loads should throw, for the failure paths.
  int failNextLoads = 0;

  @override
  Future<PaginatedNotes> loadNotesPaginated({
    String? folderId,
    int page = 1,
    int pageSize = NoteStorageService.defaultPageSize,
    NotesSortOrder sortOrder = NotesSortOrder.updatedDesc,
  }) async {
    loads.add((page: page, pageSize: pageSize));
    if (failNextLoads > 0) {
      failNextLoads--;
      throw StateError('storage unavailable');
    }
    final start = (page - 1) * pageSize;
    final slice = all.skip(start).take(pageSize).toList(growable: false);
    return PaginatedNotes(
      notes: slice,
      currentPage: page,
      totalPages: (all.length / pageSize).ceil(),
      totalCount: all.length,
      hasMore: start + slice.length < all.length,
    );
  }

  @override
  Future<void> deleteNotes(List<String> noteIds) async {
    bulkDeletes.add(noteIds);
    all = [
      for (final note in all)
        if (!noteIds.contains(note.id)) note,
    ];
  }

  @override
  void preloadContent(List<String> noteIds) => preloads.add(noteIds);

  @override
  void dispose() {}
}

class _FakeSearchService implements FolderSearchService {
  final List<String> removed = [];

  @override
  Future<List<SearchResult>> quickSearch(
    String query, {
    Set<String>? folderIds,
    int limit = 10,
    bool caseSensitive = false,
  }) async => const [];

  @override
  Future<List<SearchResult>> search(
    String query, {
    SearchFilter? filter,
    int limit = 50,
    bool caseSensitive = false,
  }) async => const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> buildIndex() async {}

  @override
  Future<void> updateIndex(String noteId, String title, String content) async {}

  @override
  Future<void> removeFromIndex(String noteId) async => removed.add(noteId);

  @override
  void dispose() {}

  @override
  Future<void> close() async {}
}

NoteMetadata _note(int index) {
  final now = DateTime(2026, 9, 7);
  return NoteMetadata(
    id: 'n${index.toString().padLeft(3, '0')}',
    folderId: 'f1',
    title: 'Session $index',
    preview: '',
    contentLength: 0,
    chunkCount: 0,
    isCompressed: false,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late _FakeNoteStorage storage;
  late _FakeSearchService searchService;

  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDownAll(() async => db.close());

  setUp(() {
    storage = _FakeNoteStorage(NoteRepository(database: db));
    storage.all = [for (var i = 0; i < 60; i++) _note(i)];
    searchService = _FakeSearchService();
  });

  OptimizedNoteBloc buildBloc() => OptimizedNoteBloc(
    storageService: storage,
    searchService: searchService,
  );

  List<String> idsIn(OptimizedNoteState state) => [
    for (final note in (state as OptimizedNoteLoaded).paginatedNotes.notes)
      note.id,
  ];

  Future<OptimizedNoteBloc> openedOnPageOne() async {
    final bloc = buildBloc();
    bloc.add(const LoadNotesPaginated(folderId: 'f1', pageSize: 20));
    await pumpEventQueue();
    return bloc;
  }

  group('load more', () {
    test('a failed load-more does not skip a page', () async {
      final bloc = await openedOnPageOne();

      storage.failNextLoads = 1;
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      expect(idsIn(bloc.state), hasLength(20));
      expect(NoteStateHelper.isLoadingMore(bloc.state), isFalse);

      storage.loads.clear();
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      expect(
        storage.loads.map((load) => load.page),
        [2],
        reason:
            'the page counter must not advance on a read that threw, or the '
            'rows the failed page held are never fetched at all',
      );
      expect(idsIn(bloc.state), hasLength(40));
      expect(idsIn(bloc.state).toSet(), hasLength(40));
      await bloc.close();
    });

    test('a successful load-more appends the next page once', () async {
      final bloc = await openedOnPageOne();

      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      expect(idsIn(bloc.state), hasLength(40));
      expect(idsIn(bloc.state).first, 'n000');
      expect(idsIn(bloc.state).last, 'n039');
      await bloc.close();
    });
  });

  group('reloading a list that has grown', () {
    test('re-reads every page already loaded, in one query', () async {
      final bloc = await openedOnPageOne();
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      storage.loads.clear();
      bloc.add(const LoadNotesPaginated(folderId: 'f1', pageSize: 20));
      await pumpEventQueue();

      expect(
        storage.loads,
        [(page: 1, pageSize: 40)],
        reason:
            'a reload asking for page 1 alone is what made a paginated list '
            'shrink back to twenty rows after a pop',
      );
      expect(idsIn(bloc.state), hasLength(40));
      await bloc.close();
    });

    test('the next load-more still continues where the list ends', () async {
      final bloc = await openedOnPageOne();
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();
      bloc.add(const LoadNotesPaginated(folderId: 'f1', pageSize: 20));
      await pumpEventQueue();

      storage.loads.clear();
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      expect(storage.loads, [(page: 3, pageSize: 20)]);
      expect(idsIn(bloc.state), hasLength(60));
      expect(idsIn(bloc.state).toSet(), hasLength(60));
      await bloc.close();
    });

    test('a different page size starts the list over', () async {
      final bloc = await openedOnPageOne();
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      storage.loads.clear();
      bloc.add(const LoadNotesPaginated(folderId: 'f1', pageSize: 50));
      await pumpEventQueue();

      expect(storage.loads, [(page: 1, pageSize: 50)]);
      await bloc.close();
    });

    test('a refresh keeps the pages too', () async {
      final bloc = await openedOnPageOne();
      bloc.add(const LoadMoreNotes(folderId: 'f1'));
      await pumpEventQueue();

      storage.loads.clear();
      bloc.add(const RefreshNotes(folderId: 'f1'));
      await pumpEventQueue();

      expect(storage.loads, [(page: 1, pageSize: 40)]);
      await bloc.close();
    });
  });

  group('bulk delete', () {
    test('is one service call and one reload, not one per item', () async {
      final bloc = await openedOnPageOne();
      storage.loads.clear();

      bloc.add(const DeleteOptimizedNotes(['n000', 'n001', 'n002']));
      await pumpEventQueue();

      expect(storage.bulkDeletes, [
        ['n000', 'n001', 'n002'],
      ]);
      expect(
        storage.loads,
        hasLength(1),
        reason: 'one delete, one reload — the loop cost a reload per row',
      );
      expect(idsIn(bloc.state).contains('n000'), isFalse);
      await bloc.close();
    });

    test('every deleted note leaves the search index', () async {
      final bloc = await openedOnPageOne();

      bloc.add(const DeleteOptimizedNotes(['n000', 'n001']));
      await pumpEventQueue();

      expect(searchService.removed, ['n000', 'n001']);
      await bloc.close();
    });

    test('an empty selection touches neither storage nor the list', () async {
      final bloc = await openedOnPageOne();
      storage.loads.clear();

      bloc.add(const DeleteOptimizedNotes([]));
      await pumpEventQueue();

      expect(storage.bulkDeletes, isEmpty);
      expect(storage.loads, isEmpty);
      await bloc.close();
    });
  });

  group('preloading', () {
    test('reaches storage through the bloc, not past it', () async {
      final bloc = await openedOnPageOne();

      bloc.add(const PreloadNoteContent(['n000', 'n001']));
      await pumpEventQueue();

      expect(storage.preloads, [
        ['n000', 'n001'],
      ]);
      await bloc.close();
    });

    test('emits nothing, so no list rebuilds for a cache warm-up', () async {
      final bloc = await openedOnPageOne();
      final before = bloc.state;
      final emitted = <OptimizedNoteState>[];
      final sub = bloc.stream.listen(emitted.add);

      bloc.add(const PreloadNoteContent(['n000']));
      await pumpEventQueue();

      expect(emitted, isEmpty);
      expect(bloc.state, same(before));
      await sub.cancel();
      await bloc.close();
    });
  });
}
