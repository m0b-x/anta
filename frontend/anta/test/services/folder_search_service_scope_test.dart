import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// Searching "in this folder" means the folder **and everything under it**.
///
/// Before this, `SearchFilter` compared one folder id, so a note two levels
/// down was invisible from the folder the user was standing in — the folder
/// row above it counted that note, and the search below it did not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FolderStorageService folders;
  late NoteStorageService notes;
  late FolderSearchService search;

  late String rootId;
  late String childId;
  late String grandchildId;
  late String siblingId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    folders = FolderStorageService(repository: FolderRepository(database: db));
    await folders.initialize();
    notes = NoteStorageService(repository: NoteRepository(database: db));
    await notes.initialize();
    search = FolderSearchService(storageService: notes);
    await search.initialize();

    rootId = (await folders.createFolder(name: 'Training')).id;
    childId = (await folders.createFolder(
      name: 'Winter block',
      parentId: rootId,
    )).id;
    grandchildId = (await folders.createFolder(
      name: 'Week 1',
      parentId: childId,
    )).id;
    siblingId = (await folders.createFolder(name: 'Groceries')).id;

    await notes.createNote(
      folderId: rootId,
      title: 'Squat plan',
      content: 'heavy squat triples',
    );
    await notes.createNote(
      folderId: childId,
      title: 'Squat volume',
      content: 'squat sets and reps',
    );
    await notes.createNote(
      folderId: grandchildId,
      title: 'Squat day',
      content: 'squat and press',
    );
    await notes.createNote(
      folderId: siblingId,
      title: 'Squat rack shopping',
      content: 'buy a squat rack',
    );
  });

  tearDown(() async => db.close());

  group('subtreeIds', () {
    test('includes the folder itself and every descendant', () async {
      expect(await folders.subtreeIds(rootId), {rootId, childId, grandchildId});
    });

    test('a leaf folder is just itself', () async {
      expect(await folders.subtreeIds(grandchildId), {grandchildId});
    });

    test('a sibling subtree does not leak in', () async {
      final subtree = await folders.subtreeIds(rootId);
      expect(subtree, isNot(contains(siblingId)));
    });
  });

  group('SearchFilter', () {
    NoteMetadata metadataIn(String folderId) => NoteMetadata(
      id: 'n',
      folderId: folderId,
      title: 't',
      preview: 'p',
      contentLength: 1,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('a null set matches everything', () {
      const filter = SearchFilter();
      expect(filter.matches(metadataIn(siblingId)), isTrue);
    });

    test('a set matches only its members', () {
      final filter = SearchFilter(folderIds: {rootId, childId});
      expect(filter.matches(metadataIn(childId)), isTrue);
      expect(filter.matches(metadataIn(siblingId)), isFalse);
    });

    test('an empty set matches nothing', () {
      const filter = SearchFilter(folderIds: <String>{});
      expect(filter.matches(metadataIn(rootId)), isFalse);
    });
  });

  group('quickSearch', () {
    test('a folder scope reaches notes in its subfolders', () async {
      final results = await search.quickSearch(
        'squat',
        folderIds: await folders.subtreeIds(rootId),
      );

      expect(
        results.map((r) => r.metadata.title),
        containsAll(<String>['Squat plan', 'Squat volume', 'Squat day']),
      );
    });

    test('a folder scope excludes everything outside the subtree', () async {
      final results = await search.quickSearch(
        'squat',
        folderIds: await folders.subtreeIds(rootId),
      );

      expect(
        results.map((r) => r.metadata.title),
        isNot(contains('Squat rack shopping')),
      );
    });

    test('everywhere ignores folders entirely', () async {
      final results = await search.quickSearch('squat');

      expect(results, hasLength(4));
    });

    test('an empty set finds nothing', () async {
      final results = await search.quickSearch('squat', folderIds: const {});

      expect(results, isEmpty);
    });
  });

  group('search', () {
    test('a folder scope reaches notes in its subfolders', () async {
      final results = await search.search(
        'squat',
        filter: SearchFilter(folderIds: await folders.subtreeIds(rootId)),
      );

      expect(
        results.map((r) => r.metadata.title),
        containsAll(<String>['Squat plan', 'Squat volume', 'Squat day']),
      );
      expect(
        results.map((r) => r.metadata.title),
        isNot(contains('Squat rack shopping')),
      );
    });

    test('no filter searches everywhere', () async {
      final results = await search.search('squat');

      expect(results, hasLength(4));
    });

    test('a leaf scope finds only that folder', () async {
      final results = await search.search(
        'squat',
        filter: SearchFilter(folderIds: await folders.subtreeIds(grandchildId)),
      );

      expect(results.map((r) => r.metadata.title), ['Squat day']);
    });
  });
}
