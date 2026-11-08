import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

/// Counts note bodies read on the way to a page of results.
///
/// The interesting number is not how long a search takes on this machine but
/// how much it reads: `search` used to load the content of **every** hit and
/// then throw away all but `limit` of them after sorting, so a common word
/// pulled the whole note collection through memory to render ten rows.
///
/// Since S11 (`docs/scalability-roadmap.md` §5.5) the scoring itself reads
/// the candidates' bodies — the body index is contentless — but in batched
/// pages through `loadContentForNotes`, never one by one; the one-by-one
/// `loadNoteContent` this counts is the offsets read, still `limit` at most.
/// The batched pages are pinned beside it.
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
  late _CountingNoteStorage notes;
  late FolderSearchService search;

  const int seeded = 60;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    notes = _CountingNoteStorage(NoteRepository(database: db));
    await notes.initialize();
    search = FolderSearchService(
      storageService: notes,
      indexer: bodyIndexerOver(db),
    );
    await search.initialize();

    final folder = await db.folderDao.createFolder(name: 'Training');
    for (var i = 0; i < seeded; i++) {
      await notes.createNote(
        folderId: folder.id,
        title: 'Session ${i + 1}',
        content: 'squat bench row session ${i + 1}',
      );
    }
    // Build the index up front so the count below is the search's own reads
    // and not the one-off bulk index pass.
    await search.buildIndex();
  });

  tearDown(() async => db.close());

  test('a query matching every note loads at most `limit` bodies', () async {
    notes.contentLoads = 0;
    statements.reset();

    final results = await search.search('squat', limit: 10);

    expect(
      results,
      hasLength(10),
      reason: 'the cap is on work done, not on results returned',
    );
    expect(
      notes.contentLoads,
      lessThanOrEqualTo(10),
      reason:
          'the hit set is ranked and cut before any body is read one by one. '
          '$seeded notes match "squat"; loading more than the 10 that are '
          'shown is the whole bug this guards.',
    );
    expect(
      statements
          .matching('FROM "content_chunks"')
          .where((sql) => sql.contains(' IN ('))
          .length,
      1,
      reason:
          'S11: scoring reads all $seeded candidate bodies, in one batched '
          'page here, never one statement per candidate',
    );
  });

  test('a smaller hit set is not padded up to the limit', () async {
    notes.contentLoads = 0;

    final results = await search.search('session 7', limit: 10);

    expect(results, isNotEmpty);
    expect(notes.contentLoads, results.length);
  });

  test('every returned result still carries its located matches', () async {
    final results = await search.search('squat', limit: 5);

    expect(results, hasLength(5));
    for (final result in results) {
      expect(
        result.matches.where((m) => m.type == SearchMatchType.content),
        isNotEmpty,
        reason: 'ranking before loading must not skip the match pass',
      );
    }
  });

  test('the cap survives a folder filter', () async {
    final ids = await notes.loadNotesPaginated(pageSize: seeded);
    final folderIds = <String>{
      for (final NoteMetadata note in ids.notes) note.folderId,
    };
    notes.contentLoads = 0;

    final results = await search.search(
      'squat',
      filter: SearchFilter(folderIds: folderIds),
      limit: 8,
    );

    expect(results, hasLength(8));
    expect(notes.contentLoads, lessThanOrEqualTo(8));
  });
}
