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
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
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
import 'package:anta/widgets/app_drawer.dart';
import 'package:anta/widgets/folder_overflow_menu.dart';
import 'package:anta/widgets/unified_app_bars.dart';

/// The first page-level test for the browser.
///
/// It exists for the app-bar convention: root shows the drawer button,
/// anywhere below it shows one back arrow, and everything the two of them
/// used to share the corner with now lives in a single overflow menu — a
/// rule about *which* controls exist, which only a mounted page can answer.
///
/// Harness notes are the editor page suite's ([optimized_note_editor_page_test])
/// and travel with it: `path_provider` and `SharedPreferences` are mocked so
/// every singleton binds to one real database, drift answers on a background
/// isolate that `FakeAsync` cannot advance (hence [settle] rather than
/// `pumpAndSettle` alone), services and BLoCs are built in `setUpAll`, and
/// the page is unmounted before the test ends so no timer outlives it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late SettingsService settings;
  late FolderStorageService folderService;
  late NoteStorageService noteService;
  late FolderSearchService searchService;
  late OptimizedFolderBloc folderBloc;
  late OptimizedNoteBloc noteBloc;
  late ImportExportBloc exportBloc;

  late Folder folder;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_folder_page');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    settings = await SettingsService.getInstance();
    await settings.setFolderSwipeEnabled(true);

    folderService = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderService.initialize();
    noteService = NoteStorageService(repository: NoteRepository(database: db));
    await noteService.initialize();
    searchService = FolderSearchService(storageService: noteService);
    await searchService.initialize();

    GetIt.I.registerSingleton<NoteRepository>(NoteRepository(database: db));
    GetIt.I.registerSingleton<FolderRepository>(FolderRepository(database: db));
    GetIt.I.registerSingleton<FolderStorageService>(folderService);
    GetIt.I.registerSingleton<NoteStorageService>(noteService);
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
    // The drawer's avatar badge resolves this during its build; the rest of
    // the drawer only reaches for a BLoC from a row's `onTap`.
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

    folder = await db.folderDao.createFolder(name: 'Training');
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

  setUp(() async {
    // One case changes the folder's note order, and the order is persisted
    // on the folder row: without this, that case would decide what the
    // sort row reads in every case declared after it.
    await folderService.updateFolderSortPreferences(
      folderId: folder.id,
      noteSortOrder: NotesSortOrder.updatedDesc.name,
      subfolderSortOrder: FoldersSortOrder.nameAsc.name,
    );
  });

  /// Lets the page's real async work finish, then flushes the `setState`s it
  /// produced into frames — the database answers in real time, the widget
  /// tree advances only on `pump`.
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  Future<void> teardownPage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> pumpPage(WidgetTester tester, {String? folderId}) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OptimizedFolderBloc>.value(value: folderBloc),
          BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
          BlocProvider<ImportExportBloc>.value(value: exportBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [AppNavigator.routeObserver],
          home: OptimizedFolderContentPage(
            folderId: folderId,
            title: folderId == null ? 'ANTA' : 'Training',
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(FolderOverflowMenu));
    await tester.pumpAndSettle();
  }

  /// The menu's rows, top to bottom. The items' type argument is private to
  /// the menu widget, so they are collected by predicate.
  List<String> menuLabels(WidgetTester tester) {
    return tester
        .widgetList<Text>(
          find.descendant(
            of: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .toList();
  }

  final l10n = AppLocalizationsEn();

  group('one icon per corner', () {
    testWidgets('the root page keeps the drawer button and shows no back '
        'arrow', (tester) async {
      await pumpPage(tester);

      final bar = tester.widget<FolderAppBar>(find.byType(FolderAppBar));
      expect(bar.isRootPage, isTrue);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byType(BackButtonIcon), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('a nested folder shows one back arrow and no drawer button', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id);

      expect(find.byType(BackButtonIcon), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.byIcon(Icons.menu), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('the bar carries exactly search and the overflow menu', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id);

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byType(FolderOverflowMenu), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsNothing);
      expect(find.byIcon(Icons.history), findsNothing);

      await teardownPage(tester);
    });
  });

  group('the overflow menu', () {
    testWidgets('a nested folder lists its own actions in order', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id);
      await openMenu(tester);

      expect(menuLabels(tester), [
        l10n.sortBy,
        l10n.sortByUpdated,
        l10n.select,
        l10n.moveHistory,
        l10n.renameFolder,
        l10n.moveToFolder,
        l10n.shareFolder,
        l10n.importNoteOrFolder,
        l10n.deleteFolder,
        l10n.settings,
      ]);

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    testWidgets('the root menu drops the rows that need a folder', (
      tester,
    ) async {
      await pumpPage(tester);
      await openMenu(tester);

      expect(menuLabels(tester), [
        l10n.sortBy,
        l10n.sortByName,
        l10n.select,
        l10n.moveHistory,
        l10n.importNoteOrFolder,
        l10n.settings,
      ]);

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    testWidgets('the sort row reports the order the list is in', (
      tester,
    ) async {
      // The note-sort sheet is six rows plus a header, which does not fit
      // the 800x600 default surface.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpPage(tester, folderId: folder.id);
      await openMenu(tester);
      expect(find.text(l10n.sortByUpdated), findsOneWidget);

      await tester.tap(find.text(l10n.sortBy));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.sortNotes));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${l10n.sortByTitle} (A-Z)'));
      await tester.pumpAndSettle();
      await settle(tester);

      await openMenu(tester);
      expect(find.text(l10n.sortByTitle), findsOneWidget);
      expect(find.text(l10n.sortByUpdated), findsNothing);

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    testWidgets('Select enters selection mode', (tester) async {
      await pumpPage(tester, folderId: folder.id);
      await openMenu(tester);

      await tester.tap(find.text(l10n.select));
      await tester.pumpAndSettle();

      expect(find.byType(FolderAppBar), findsNothing);
      expect(find.byType(FolderOverflowMenu), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('Settings opens the drawer through the page, not the menu '
        'route', (tester) async {
      await pumpPage(tester, folderId: folder.id);
      expect(find.byType(AppDrawer), findsNothing);
      await openMenu(tester);

      await tester.tap(find.text(l10n.settings));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsOneWidget);
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );

      await teardownPage(tester);
    });
  });
}
