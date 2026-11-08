import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

/// The real service, with the one call a save used to pay counted.
class _CountingNoteStorage extends NoteStorageService {
  _CountingNoteStorage(NoteRepository repository)
    : super(repository: repository);

  int contentLoads = 0;

  @override
  Future<String> loadNoteContent(String noteId) {
    contentLoads++;
    return super.loadNoteContent(noteId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });

  tearDown(() async => db.close());

  group('writes that never pass a bloc', () {
    late NoteStorageService notes;
    late FolderSearchService search;
    late Folder folder;

    setUp(() async {
      notes = NoteStorageService(repository: NoteRepository(database: db));
      await notes.initialize();
      search = FolderSearchService(
        storageService: notes,
        indexer: bodyIndexerOver(db),
      );
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

    test(
      'a note written outside the bloc is found by the next full search',
      () async {
        // Restore, import and sync all land here: storage, never
        // `OptimizedNoteBloc`, so nothing but the change stream tells the
        // index about them.
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
      },
    );

    test('an edit outside the bloc is reflected, old words and new', () async {
      final page = await notes.loadNotesPaginated(pageSize: 10);
      final session = page.notes.firstWhere((n) => n.title == 'Session 1');

      await notes.updateNote(noteId: session.id, content: 'zercher only');

      expect(await search.search('zercher'), hasLength(1));
      expect(
        await search.search('squat'),
        isEmpty,
        reason:
            'a refreshed note replaces its terms rather than adding to them',
      );
    });

    test(
      'a new note refreshed through the stale path is found by prefix',
      () async {
        expect(await search.search('squ'), hasLength(1));

        await notes.createNote(
          folderId: folder.id,
          title: 'Session 2',
          content: 'zebra crossing',
        );
        await pumpEventQueue();

        expect((await search.search('zeb')).map((r) => r.metadata.title), [
          'Session 2',
        ]);
        expect((await search.search('cross')).map((r) => r.metadata.title), [
          'Session 2',
        ]);
      },
    );

    test('a note deleted outside the bloc stops being a hit', () async {
      final page = await notes.loadNotesPaginated(pageSize: 10);
      final session = page.notes.firstWhere((n) => n.title == 'Session 1');

      await notes.deleteNote(session.id);

      expect(await search.search('squat'), isEmpty);
    });
  });

  group('a colour label is not an edit', () {
    late _CountingNoteStorage notes;
    late FolderSearchService search;
    late NoteMetadata session;

    setUp(() async {
      notes = _CountingNoteStorage(NoteRepository(database: db));
      await notes.initialize();
      search = FolderSearchService(
        storageService: notes,
        indexer: bodyIndexerOver(db),
      );
      await search.initialize();
      final folder = await db.folderDao.createFolder(name: 'Training');
      session = await notes.createNote(
        folderId: folder.id,
        title: 'Session 1',
        content: 'squat bench row',
      );
      await search.buildIndex();
    });

    tearDown(() async => search.close());

    /// How many notes a search re-projects into the body index on its way —
    /// "did this change mark the note stale?" asked of the index itself. It
    /// counted per-note body loads while the index was built in memory; S11
    /// reads bodies in batches, so the projection is what is left to count.
    Future<int> reindexesForASearch(String query) async {
      statements.reset();
      await search.search(query);
      return statements.executions('INSERT INTO note_body_fts');
    }

    test('labelling a note does not mark it stale', () async {
      final baseline = await reindexesForASearch('squat');

      await notes.setNoteLabel(session.id, ItemLabel.red);
      await pumpEventQueue();

      expect(
        await reindexesForASearch('squat'),
        baseline,
        reason:
            'the index holds title and body; a colour is neither, so a '
            'labelled note must not be read back out of the chunk table',
      );
    });

    test('labelling a selection does not mark them stale either', () async {
      final baseline = await reindexesForASearch('squat');

      await notes.setLabelForNotes([session.id], ItemLabel.blue);
      await pumpEventQueue();

      expect(await reindexesForASearch('squat'), baseline);
    });

    test('an edit beside it still does, so the count can move', () async {
      final baseline = await reindexesForASearch('squat');

      await notes.updateNote(noteId: session.id, content: 'squat zercher');
      await pumpEventQueue();

      expect(
        await reindexesForASearch('squat'),
        greaterThan(baseline),
        reason: 'an update is what a re-index is for',
      );
    });
  });

  group('a save through the bloc', () {
    late _CountingNoteStorage notes;
    late FolderSearchService search;
    late OptimizedNoteBloc bloc;
    late NoteMetadata session;

    setUp(() async {
      notes = _CountingNoteStorage(NoteRepository(database: db));
      await notes.initialize();
      search = FolderSearchService(
        storageService: notes,
        indexer: bodyIndexerOver(db),
      );
      await search.initialize();
      bloc = OptimizedNoteBloc(storageService: notes);
      final folder = await db.folderDao.createFolder(name: 'Training');
      session = await notes.createNote(
        folderId: folder.id,
        title: 'Session 1',
        content: 'squat bench row',
      );
      await search.buildIndex();
    });

    tearDown(() async {
      await bloc.close();
      await search.close();
    });

    test('a 300,000-code-unit save neither tokenises nor reads back', () async {
      final body = '${'zercher carry and sled '.padRight(100, 'x')}\n' * 2970;
      final content = body.padRight(300000, 'y');
      expect(content.length, 300000);
      notes.contentLoads = 0;
      statements.reset();

      final saved = Completer<void>();
      bloc.add(
        UpdateOptimizedNote(
          noteId: session.id,
          content: content,
          completer: saved,
        ),
      );
      await saved.future;
      await pumpEventQueue();

      expect(
        [
          ...statements.matching('note_body_fts'),
          ...statements.matching('note_search_ledger'),
        ],
        isEmpty,
        reason: 'a save touches neither index table; the next search does',
      );
      expect(notes.contentLoads, 0);

      final results = await search.search('zercher');
      expect(
        results.map((r) => r.metadata.id),
        [session.id],
        reason:
            'the change stream marked the index dirty, so the next search '
            're-reads the note',
      );
      expect(await search.search('squat'), isEmpty);
    });
  });

  group('an index bigger than one page', () {
    test('the build pages past its page size instead of stopping', () async {
      final notes = NoteStorageService(
        repository: NoteRepository(database: db),
      );
      await notes.initialize();
      final indexer = BodySearchIndexer(
        database: db,
        scheduler: inlineBodyIndexScheduler,
        pageBytes: 100,
      );
      final search = FolderSearchService(
        storageService: notes,
        indexer: () async => indexer,
      );
      addTearDown(search.close);

      final folder = await db.folderDao.createFolder(name: 'Training');
      for (var i = 0; i < 12; i++) {
        await notes.createNote(
          folderId: folder.id,
          title: 'Session $i',
          content: i == 0 ? 'zercher carry' : 'squat bench row ' * 4,
        );
      }
      statements.reset();

      await search.buildIndex();

      expect(
        statements.executions('FROM "content_chunks"'),
        greaterThan(1),
        reason: 'one page was the whole build; later notes were invisible',
      );
      final results = await search.search('zercher', limit: 5);
      expect(results.map((r) => r.metadata.title), contains('Session 0'));
    });
  });
}
