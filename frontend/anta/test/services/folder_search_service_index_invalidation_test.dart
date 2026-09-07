import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// Serves as many pages as it is asked for, and answers content without
/// touching storage — so a build over more notes than one page holds is a
/// test that finishes.
class _PagedNoteStorage extends NoteStorageService {
  _PagedNoteStorage(NoteRepository repository) : super(repository: repository);

  final List<int> pagesAsked = [];
  List<NoteMetadata> all = const [];
  Map<String, String> contents = const {};

  @override
  Future<PaginatedNotes> loadNotesPaginated({
    String? folderId,
    int page = 1,
    int pageSize = NoteStorageService.defaultPageSize,
    NotesSortOrder sortOrder = NotesSortOrder.updatedDesc,
  }) async {
    pagesAsked.add(page);
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
  Future<String> loadNoteContent(String noteId) async => contents[noteId] ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
  });

  tearDown(() async => db.close());

  group('writes that never pass a bloc', () {
    late NoteStorageService notes;
    late FolderSearchService search;
    late Folder folder;

    setUp(() async {
      notes = NoteStorageService(repository: NoteRepository(database: db));
      await notes.initialize();
      search = FolderSearchService(storageService: notes);
      await search.initialize();
      folder = await db.folderDao.createFolder(name: 'Training');
      await notes.createNote(
        folderId: folder.id,
        title: 'Session 1',
        content: 'squat bench row',
      );
      await search.buildIndex();
    });

    tearDown(() async => search.close());

    test('a note written outside the bloc is found by the next full search',
        () async {
      // Restore, import and sync all land here: storage, never
      // `OptimizedNoteBloc`, so `updateIndex` is never called for them.
      await notes.createNote(
        folderId: folder.id,
        title: 'Session 2',
        content: 'zercher carry and sled',
      );

      final results = await search.search('zercher');

      expect(
        results.map((r) => r.metadata.title),
        contains('Session 2'),
        reason:
            'the index is built once per session; without invalidation it '
            'answers for the database as it was at launch',
      );
    });

    test('an edit outside the bloc is reflected, old words and new', () async {
      final page = await notes.loadNotesPaginated(pageSize: 10);
      final session = page.notes.firstWhere((n) => n.title == 'Session 1');

      await notes.updateNote(noteId: session.id, content: 'zercher only');

      expect(await search.search('zercher'), hasLength(1));
      expect(
        await search.search('squat'),
        isEmpty,
        reason: 'a refreshed note replaces its terms rather than adding to them',
      );
    });

    test('a note deleted outside the bloc stops being a hit', () async {
      final page = await notes.loadNotesPaginated(pageSize: 10);
      final session = page.notes.firstWhere((n) => n.title == 'Session 1');

      await notes.deleteNote(session.id);

      expect(await search.search('squat'), isEmpty);
    });
  });

  group('an index bigger than one page', () {
    test('the build pages past its page size instead of stopping', () async {
      final storage = _PagedNoteStorage(NoteRepository(database: db));
      await storage.initialize();
      final search = FolderSearchService(storageService: storage);
      addTearDown(search.close);

      final now = DateTime.now();
      storage.all = [
        for (var i = 0; i < 1200; i++)
          NoteMetadata(
            id: 'n$i',
            folderId: 'f1',
            title: 'Session $i',
            preview: '',
            contentLength: 0,
            chunkCount: 0,
            isCompressed: false,
            createdAt: now,
            updatedAt: now,
            position: i,
          ),
      ];
      storage.contents = {
        for (var i = 0; i < 1200; i++) 'n$i': 'squat bench row',
        'n1150': 'zercher carry',
      };

      await search.buildIndex();

      expect(
        storage.pagesAsked,
        contains(2),
        reason: 'one page was the whole build; note 1001 onwards was invisible',
      );
      final results = await search.search('zercher', limit: 5);
      expect(results.map((r) => r.metadata.id), contains('n1150'));
    });
  });
}
