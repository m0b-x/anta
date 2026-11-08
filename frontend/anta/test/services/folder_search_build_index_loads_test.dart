import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

/// Counts note bodies read, as `folder_search_service_limit_test.dart` does.
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

/// What building the search index reads: the bodies of the notes it lacks,
/// a page at a time in one batched chunk query per page, and no per-note
/// load at all. Until S11 (`docs/scalability-roadmap.md` §5.5) it was one
/// load and one chunk query per note — 60 and 60 here — before a single
/// term was indexed; S11 flipped the pin to the page count.
///
/// Every body is 26 characters, so a page budget is an exact note count. The
/// notes are written through the DAO and read through a fresh repository,
/// so its content cache starts cold, as it does after a launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seeded = 60;
  const bodyLength = 26;

  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    final folder = await db.folderDao.createFolder(name: 'Training');
    for (var i = 0; i < seeded; i++) {
      final body = 'squat bench row session ${'${i + 1}'.padLeft(2, '0')}';
      expect(body, hasLength(bodyLength));
      await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Session ${i + 1}',
        preview: NoteMetadata.generatePreview(body),
        contentLength: body.length,
        content: body,
      );
    }
  });

  tearDown(() async => db.close());

  Future<(_CountingNoteStorage, FolderSearchService)> searchWith(
    int pageBytes,
  ) async {
    final notes = _CountingNoteStorage(NoteRepository(database: db));
    await notes.initialize();
    final indexer = BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
      pageBytes: pageBytes,
    );
    final search = FolderSearchService(
      storageService: notes,
      indexer: () async => indexer,
    );
    addTearDown(search.close);
    return (notes, search);
  }

  test('a cold build reads every body in one batched page', () async {
    final (notes, search) = await searchWith(256 * 1024);
    statements.reset();

    await search.buildIndex();

    expect(notes.contentLoads, 0, reason: 'S11 flipped this pin from 60');
    expect(
      statements.executions('FROM "content_chunks"'),
      1,
      reason: 'the content cache is cold; S11 flipped this pin from 60',
    );
    expect(await search.search('squat', limit: 5), hasLength(5));
  });

  test('a build over several pages reads once per page', () async {
    const notesPerPage = 8;
    final (notes, search) = await searchWith(notesPerPage * bodyLength);
    statements.reset();

    await search.buildIndex();

    expect(notes.contentLoads, 0);
    expect(
      statements.executions('FROM "content_chunks"'),
      (seeded / notesPerPage).ceil(),
    );
  });
}
