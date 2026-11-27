import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/tag_catalog.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/tag_catalog_service.dart';

/// `TagCatalogService.prime`, what the editor asks as it opens with
/// Autocomplete on, over the app's own singletons: a tag saved in one note
/// reaches the catalog the next editor reads, and the first open reads the
/// ledger once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late NoteStorageService storage;
  late FolderSearchService search;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_tag_catalog_prime');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    SharedPreferences.setMockInitialValues({'active_database': 'one'});
    DatabaseManager.resetForTesting();
    await DatabaseManager.getInstance();
    db = await AppDatabase.getInstance();
    storage = NoteStorageService(repository: NoteRepository(database: db));
    await storage.initialize();
    // The app's listener that tells the indexer notes moved.
    search = FolderSearchService(storageService: storage);
    await search.initialize();
  });

  setUp(() async {
    TagCatalogService.reset();
    BodySearchIndexer.reset();
    // The launch drain (`BodySearchIndexer.startAfterLaunch`).
    await (await BodySearchIndexer.getInstance()).drain();
    TagCatalogService.debugLedgerReads = 0;
  });

  tearDownAll(() async {
    TagCatalogService.reset();
    BodySearchIndexer.reset();
    await search.close();
    await AppDatabase.deleteAllData();
    AppDatabase.resetSwitchAnnouncementForTesting();
    DatabaseManager.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Waits, in real time, for [ready] — the catalog's own refresh, which the
  /// drain's pages set off and nothing here may stand in for.
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  bool holds(String tag) => TagCatalog.all.any((entry) => entry.tag == tag);

  test('a tag saved in note A is in the catalog once note B\'s editor has '
      'primed it and the drain settled', () async {
    await TagCatalogService.prime();
    final folder = await db.folderDao.createFolder(name: 'Training');
    await storage.createNote(
      folderId: folder.id,
      title: 'A',
      content: 'squat #FreshTag',
    );
    // The save's change reaches the search service's listener first, as
    // it does long before another note opens.
    await pumpEventQueue();

    await TagCatalogService.prime();
    await (await BodySearchIndexer.getInstance()).whenIdle();
    await until(() => holds('FreshTag'));

    expect(holds('FreshTag'), isTrue);
  });

  test(
    'the first open reads the ledger once; a later one reads it again',
    () async {
      await TagCatalogService.prime();
      expect(TagCatalogService.debugLedgerReads, 1);

      await TagCatalogService.prime();
      expect(TagCatalogService.debugLedgerReads, 2);
    },
  );

  test('two editors opening together read the ledger once', () async {
    await Future.wait([TagCatalogService.prime(), TagCatalogService.prime()]);

    expect(TagCatalogService.debugLedgerReads, 1);
  });
}
