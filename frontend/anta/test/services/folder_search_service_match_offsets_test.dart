import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// Where a match is, in the text the row actually paints.
///
/// A [SearchMatch] carries a snippet plus the offsets to highlight inside it,
/// and the surface trusts them literally: `text.substring(startIndex,
/// endIndex)`. They used to be found in the diacritic-folded copy and applied
/// to the raw one, which only agrees while the fold is length-preserving —
/// `ß` folds to `ss`, so a single German word ahead of the hit slid the
/// highlight one character to the right and, at the end of a line, past it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late NoteStorageService notes;
  late FolderSearchService search;
  late Folder folder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    notes = NoteStorageService(repository: NoteRepository(database: db));
    await notes.initialize();
    search = FolderSearchService(storageService: notes);
    await search.initialize();
    folder = await db.folderDao.createFolder(name: 'Training');
  });

  tearDown(() async {
    await search.close();
    await db.close();
  });

  /// The text a highlight would paint bold, read the way [SearchResultRow]
  /// reads it.
  String highlighted(SearchMatch match) =>
      match.text.substring(match.startIndex, match.endIndex);

  test('a fold that changes length keeps the match on the raw text', () async {
    await notes.createNote(
      folderId: folder.id,
      title: 'Straße squat notes',
      content: 'nothing in the body',
    );

    final results = await search.search('squat');

    expect(results, hasLength(1));
    final titleMatch = results.single.matches.firstWhere(
      (m) => m.type == SearchMatchType.title,
    );
    expect(
      highlighted(titleMatch),
      'squat',
      reason:
          '"Straße" folds to "strasse", one code unit longer, so the folded '
          'offset points one past the match in the raw title',
    );
  });

  test('a fold in the body keeps the snippet highlight on the query', () async {
    await notes.createNote(
      folderId: folder.id,
      title: 'Session',
      content: 'Straße und Grüße, dann squat und bench.',
    );

    final results = await search.search('squat');

    expect(results, hasLength(1));
    final contentMatch = results.single.matches.firstWhere(
      (m) => m.type == SearchMatchType.content,
    );
    expect(highlighted(contentMatch), 'squat');
  });

  test('a diacritic inside the match itself is highlighted whole', () async {
    await notes.createNote(
      folderId: folder.id,
      title: 'Împins de la piept',
      content: 'ridicări',
    );

    final results = await search.search('impins');

    expect(results, hasLength(1));
    final titleMatch = results.single.matches.firstWhere(
      (m) => m.type == SearchMatchType.title,
    );
    expect(
      highlighted(titleMatch),
      'Împins',
      reason:
          'the end offset must come off the length of what matched, not off '
          'the length of what was typed',
    );
  });

  test('plain text still highlights exactly the query', () async {
    await notes.createNote(
      folderId: folder.id,
      title: 'Wednesday heavy squat session',
      content: 'squat 5x5',
    );

    final results = await search.search('squat');

    expect(results, hasLength(1));
    for (final match in results.single.matches) {
      expect(highlighted(match).toLowerCase(), 'squat');
    }
  });
}
