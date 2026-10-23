@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/pages/optimized_folder_content_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/mixed_reorder_service.dart';
import 'package:anta/services/move_history_service.dart';
import 'package:anta/services/move_history_store.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/services/settings_service.dart';

import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The browser on a folder holding a subfolder and fifteen notes, harnessed
/// and seeded as `test/widgets/optimized_folder_content_page_test.dart` does
/// it.
///
/// The notes are ordered by title, not by the default last-edited order:
/// they are created within the same milliseconds, and a tie in that order
/// would let the rows trade places between runs. Each row's date reads
/// "Today", which holds for as long as the notes were created on the day the
/// golden is drawn — always, since they are created by the same run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late OptimizedFolderBloc folderBloc;
  late OptimizedNoteBloc noteBloc;
  late ImportExportBloc exportBloc;
  late Folder shown;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_golden_browser');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    final settings = await SettingsService.getInstance();
    await settings.setFolderSwipeEnabled(true);
    await settings.setShowNotePreview(true);

    final folderService = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderService.initialize();
    final noteService = NoteStorageService(
      repository: NoteRepository(database: db),
    );
    await noteService.initialize();
    final searchService = FolderSearchService(storageService: noteService);
    await searchService.initialize();

    GetIt.I.registerSingleton<NoteRepository>(NoteRepository(database: db));
    GetIt.I.registerSingleton<FolderRepository>(FolderRepository(database: db));
    GetIt.I.registerSingleton<FolderStorageService>(folderService);
    GetIt.I.registerSingleton<NoteStorageService>(noteService);
    GetIt.I.registerSingleton<FolderSearchService>(searchService);
    GetIt.I.registerSingleton<MoveHistoryService>(
      MoveHistoryService(store: InMemoryMoveHistoryStore()),
    );
    GetIt.I.registerSingleton<RecentDestinationsService>(
      RecentDestinationsService(),
    );
    GetIt.I.registerSingleton<MixedReorderService>(
      MixedReorderService(
        folderRepository: GetIt.I<FolderRepository>(),
        noteRepository: GetIt.I<NoteRepository>(),
      ),
    );
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());

    folderBloc = OptimizedFolderBloc(storageService: folderService);
    noteBloc = OptimizedNoteBloc(
      storageService: noteService,
      searchService: searchService,
    );
    exportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: noteService,
        folderStorage: folderService,
        noteRepository: GetIt.I<NoteRepository>(),
      ),
    );

    final training = await db.folderDao.createFolder(name: 'Training');
    shown = await db.folderDao.createFolder(
      name: 'Winter block',
      parentId: training.id,
    );
    await db.folderDao.createFolder(name: 'Week 1', parentId: shown.id);
    for (var i = 0; i < 15; i++) {
      await noteService.createNote(
        folderId: shown.id,
        title: 'Session ${i + 1}',
        content: 'squat, bench, row',
      );
    }
    await folderService.updateFolderSortPreferences(
      folderId: shown.id,
      noteSortOrder: NotesSortOrder.titleAsc.name,
      subfolderSortOrder: FoldersSortOrder.nameAsc.name,
    );
  });

  tearDownAll(() async {
    await folderBloc.close();
    await noteBloc.close();
    await exportBloc.close();
    await GetIt.I.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// The database answers in real time on its own isolate, the tree advances
  /// only on `pump`: both are interleaved until the page has loaded.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  for (final cell in goldenCells) {
    testWidgets('folder browser, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<OptimizedFolderBloc>.value(value: folderBloc),
              BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
              BlocProvider<ImportExportBloc>.value(value: exportBloc),
            ],
            child: goldenApp(
              cell,
              navigatorObservers: [AppNavigator.routeObserver],
              home: OptimizedFolderContentPage(
                folderId: shown.id,
                title: shown.name,
              ),
            ),
          ),
        );
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 300));
      });

      expect(errors, isEmpty);
      await expectGolden('folder_browser', cell);

      // No timer of the page's may outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
