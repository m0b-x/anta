import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/search/search_bloc.dart';
import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/search_scope.dart';
import 'package:anta/pages/all_notes_page.dart';
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
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/app_drawer.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/folder_overflow_menu.dart';
import 'package:anta/widgets/folder_row.dart';
import 'package:anta/widgets/folder_sliver_app_bar.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/note_row.dart';
import 'package:anta/widgets/search_surface.dart';
import 'package:anta/widgets/selection_action_bar.dart';
import 'package:anta/widgets/selection_app_bar.dart';

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
  late Folder child;
  late Folder grandchild;
  late Folder notesOnly;

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
    child = await db.folderDao.createFolder(
      name: 'Winter block',
      parentId: folder.id,
    );
    grandchild = await db.folderDao.createFolder(
      name: 'Week 1',
      parentId: child.id,
    );
    // Enough rows that the bar can actually be scrolled past its collapse
    // threshold on the default 800x600 surface.
    for (var i = 0; i < 15; i++) {
      await noteService.createNote(
        folderId: child.id,
        title: 'Session ${i + 1}',
        content: 'squat, bench, row',
      );
    }
    // A folder holding notes and nothing else, so the bottom bar's third
    // plural shape ("4 notes", no folder half) has somewhere to be read.
    notesOnly = await db.folderDao.createFolder(name: 'Loose notes');
    for (var i = 0; i < 3; i++) {
      await noteService.createNote(
        folderId: notesOnly.id,
        title: 'Loose ${i + 1}',
        content: 'jotted down',
      );
    }
    // One note that carries "down" in its title next to three that carry it
    // only in their body: the pair is what makes a search over this folder
    // show both the Titles and the In text sections.
    await noteService.createNote(
      folderId: notesOnly.id,
      title: 'down day',
      content: 'nothing much',
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

  setUp(() async {
    // One case changes the folder's note order, and the order is persisted
    // on the folder row: without this, that case would decide what the
    // sort row reads in every case declared after it.
    await folderService.updateFolderSortPreferences(
      folderId: folder.id,
      noteSortOrder: NotesSortOrder.updatedDesc.name,
      subfolderSortOrder: FoldersSortOrder.nameAsc.name,
    );
    // The reorder cases flip this folder to position order and persist it.
    await folderService.updateFolderSortPreferences(
      folderId: child.id,
      noteSortOrder: NotesSortOrder.updatedDesc.name,
      subfolderSortOrder: FoldersSortOrder.nameAsc.name,
    );
    await settings.setShowNotePreview(true);
  });

  final l10n = AppLocalizationsEn();

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

  Future<void> pumpPage(
    WidgetTester tester, {
    String? folderId,
    String? title,
    List<NavigatorObserver> observers = const [],
    ThemeData? theme,
  }) async {
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
          navigatorObservers: [AppNavigator.routeObserver, ...observers],
          theme: theme,
          home: OptimizedFolderContentPage(
            folderId: folderId,
            title: title ?? (folderId == null ? 'ANTA' : 'Training'),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Pushes a real folder route, the way tapping a folder card does, so the
  /// ancestor menu has a stack to walk. The push future completes when the
  /// route is popped, so it is deliberately not awaited.
  Future<void> pushFolder(WidgetTester tester, Folder target) async {
    AppNavigator.toFolder(
      tester.element(find.byType(OptimizedFolderContentPage).first),
      folderId: target.id,
      title: target.name,
    ).ignore();
    await tester.pumpAndSettle();
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(FolderOverflowMenu));
    await tester.pumpAndSettle();
  }

  Future<void> dismissMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 8));
    await tester.pumpAndSettle();
  }

  FolderSliverAppBar appBar(WidgetTester tester) =>
      tester.widget<FolderSliverAppBar>(find.byType(FolderSliverAppBar));

  FlexibleSpaceBarSettings barSettings(WidgetTester tester) => tester
      .widget<FlexibleSpaceBarSettings>(find.byType(FlexibleSpaceBarSettings));

  /// The opacity the framework is driving the *toolbar* copy of the title
  /// towards. `SliverAppBar.large` keeps that copy at 0 until the bar is
  /// fully collapsed, which is exactly the threshold under test — and the
  /// flexible space holds a second copy of the same string, so the toolbar
  /// one is addressed through [NavigationToolbar].
  double collapsedTitleOpacity(WidgetTester tester, String title) {
    return tester
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.descendant(
              of: find.byType(NavigationToolbar),
              matching: find.text(title),
            ),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .first
        .opacity;
  }

  /// Depth-first, so the first hit is the scroll view's own: in search mode
  /// the field's `EditableText` puts a second [Scrollable] inside it.
  ScrollPosition scrollPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// Where every note row currently sits on screen. Comparing two of these
  /// across the app-bar swap is the only way to say "nothing moved" that does
  /// not depend on which rows happen to be in view.
  Map<String, double> rowTops(WidgetTester tester) {
    final tops = <String, double>{};
    for (var i = 1; i <= 15; i++) {
      final finder = find.text('Session $i');
      if (finder.evaluate().isNotEmpty) {
        tops['Session $i'] = tester.getTopLeft(finder).dy;
      }
    }
    return tops;
  }

  /// The bar is a sliver, so what it takes from the list is its geometry
  /// rather than a box size.
  double barHeight(WidgetTester tester) {
    final sliver = tester.renderObject<RenderSliver>(
      find.byType(FolderSliverAppBar),
    );
    return sliver.geometry!.paintExtent;
  }

  /// Where the root's folder rows sit. The smart rows above them are the
  /// content selection mode used to remove, so these are what would jump.
  Map<String, double> folderRowTops(WidgetTester tester) {
    final tops = <String, double>{};
    for (final name in const ['Training', 'Loose notes']) {
      final finder = find.text(name);
      if (finder.evaluate().isNotEmpty) {
        tops[name] = tester.getTopLeft(finder).dy;
      }
    }
    return tops;
  }

  Future<void> enterSelection(WidgetTester tester) async {
    await openMenu(tester);
    await tester.tap(find.text(l10n.select));
    await tester.pumpAndSettle();
    await settle(tester);
  }

  Future<void> leaveSelection(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await settle(tester);
  }

  Future<void> longPressBack(WidgetTester tester) async {
    await tester.longPress(find.byType(BackButtonIcon));
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

  group('leading controls', () {
    testWidgets('the root page keeps the drawer button and shows no back '
        'arrow', (tester) async {
      await pumpPage(tester);

      expect(appBar(tester).isRootPage, isTrue);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byType(BackButtonIcon), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('the root drawer button still opens the drawer from inside '
        'the scroll view', (tester) async {
      await pumpPage(tester);
      expect(find.byType(AppDrawer), findsNothing);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );

      await teardownPage(tester);
    });

    testWidgets('a nested folder pairs the back arrow with the drawer button', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id);

      expect(find.byType(LeadingNavPair), findsOneWidget);
      expect(find.byType(BackButtonIcon), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('the nested drawer button opens the drawer', (tester) async {
      await pumpPage(tester, folderId: folder.id);
      expect(find.byType(AppDrawer), findsNothing);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );

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

    testWidgets('the bar reserves exactly what the pair draws', (tester) async {
      await pumpPage(tester, folderId: folder.id);

      expect(
        tester.getSize(find.byType(LeadingNavPair)).width,
        LeadingNavPair.width,
      );

      await teardownPage(tester);
    });

    testWidgets('the pair is gone in selection mode', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      expect(find.byType(LeadingNavPair), findsOneWidget);

      await enterSelection(tester);

      expect(find.byType(LeadingNavPair), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);

      await leaveSelection(tester);
      await teardownPage(tester);
    });
  });

  group('the bar geometry', () {
    testWidgets('the expanded bar is the height the swap math pays for', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      expect(barHeight(tester), FolderSliverAppBar.expandedHeightNested);
      await teardownPage(tester);

      await pumpPage(tester);
      expect(barHeight(tester), FolderSliverAppBar.expandedHeightRoot);
      await teardownPage(tester);
    });

    testWidgets('the refresh spinner drops from under whichever bar this '
        'page wears', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      expect(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .edgeOffset,
        FolderSliverAppBar.expandedHeightNested,
      );
      await teardownPage(tester);

      await pumpPage(tester);
      expect(
        tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .edgeOffset,
        FolderSliverAppBar.expandedHeightRoot,
      );
      await teardownPage(tester);
    });

    testWidgets('the eyebrow sits directly under the toolbar', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      final toolbar = tester.getRect(find.byType(NavigationToolbar).first);
      final eyebrow = tester.getRect(find.text('Training'));

      expect(toolbar.height, AppBarMetrics.toolbarHeight);
      expect(eyebrow.top, greaterThanOrEqualTo(toolbar.bottom));
      expect(
        eyebrow.bottom,
        lessThanOrEqualTo(toolbar.bottom + AppBarMetrics.eyebrowHeight),
      );

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

      expect(find.byType(FolderSliverAppBar), findsNothing);
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

  group('the large title bar', () {
    testWidgets('a nested folder names its parent above the large title', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(appBar(tester).eyebrow, 'Training');
      expect(find.text('Training'), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('a folder directly under the root names the root', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id);

      expect(appBar(tester).eyebrow, l10n.folders);

      await teardownPage(tester);
    });

    testWidgets('the root page has no eyebrow and no ancestor menu', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(appBar(tester).eyebrow, isNull);
      expect(appBar(tester).onShowAncestors, isNull);

      await teardownPage(tester);
    });

    testWidgets('the root title is Folders, not the route title', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(appBar(tester).title, l10n.folders);
      expect(find.text('ANTA'), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('scrolling past the threshold hands the title to the toolbar', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(barSettings(tester).isScrolledUnder, isFalse);
      expect(collapsedTitleOpacity(tester, 'Winter block'), 0);

      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      // The framework flips at `shrinkOffset > maxExtent - minExtent`, so
      // the threshold itself is still "expanded".
      final pastThreshold =
          FolderSliverAppBar.expandedHeightNested -
          FolderSliverAppBar.collapsedHeight +
          8;
      expect(position.maxScrollExtent, greaterThan(pastThreshold));
      position.jumpTo(pastThreshold);
      await tester.pumpAndSettle();

      expect(barSettings(tester).isScrolledUnder, isTrue);
      expect(collapsedTitleOpacity(tester, 'Winter block'), 1);

      await teardownPage(tester);
    });

    testWidgets('a list shorter than the screen leaves the bar expanded', (
      tester,
    ) async {
      await pumpPage(tester, folderId: grandchild.id, title: 'Week 1');

      expect(barSettings(tester).isScrolledUnder, isFalse);
      expect(collapsedTitleOpacity(tester, 'Week 1'), 0);

      await teardownPage(tester);
    });
  });

  group('the ancestor menu', () {
    testWidgets('long-pressing Back lists the ancestors nearest first and '
        'ends at the root', (tester) async {
      await pumpPage(tester, folderId: grandchild.id, title: 'Week 1');

      await longPressBack(tester);

      expect(menuLabels(tester), ['Winter block', 'Training', l10n.folders]);

      await dismissMenu(tester);
      await teardownPage(tester);
    });

    testWidgets('tapping the eyebrow opens the same menu', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      await tester.tap(find.text('Training'));
      await tester.pumpAndSettle();

      expect(menuLabels(tester), ['Training', l10n.folders]);

      await dismissMenu(tester);
      await teardownPage(tester);
    });

    testWidgets('a screen reader can reach it from the back button and from '
        'the eyebrow', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      final backButton = tester.getSemantics(
        find.ancestor(
          of: find.byType(BackButtonIcon),
          matching: find.byType(IconButton),
        ),
      );
      final actionIds =
          backButton.getSemanticsData().customSemanticsActionIds ??
          const <int>[];
      expect(
        actionIds.map((id) => CustomSemanticsAction.getAction(id)?.label),
        contains(l10n.showAncestors),
      );
      expect(
        tester.getSemantics(find.text('Training')),
        isSemantics(isButton: true, label: 'Training'),
      );

      semantics.dispose();
      await teardownPage(tester);
    });

    testWidgets('the root row removes the intermediates and pops once', (
      tester,
    ) async {
      final observer = _RecordingObserver();
      await pumpPage(tester, observers: [observer]);
      await pushFolder(tester, folder);
      await pushFolder(tester, child);
      final top = observer.pushed.last;
      final intermediate = observer.pushed[observer.pushed.length - 2];
      observer.clear();

      await longPressBack(tester);
      await tester.tap(find.text(l10n.folders));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(observer.removed, [intermediate]);
      expect(observer.popped, [top]);
      expect(find.byType(OptimizedFolderContentPage), findsOneWidget);
      expect(appBar(tester).isRootPage, isTrue);

      await teardownPage(tester);
    });

    testWidgets('an ancestor row pops to that folder', (tester) async {
      final observer = _RecordingObserver();
      await pumpPage(tester, observers: [observer]);
      await pushFolder(tester, folder);
      await pushFolder(tester, child);
      await pushFolder(tester, grandchild);
      observer.clear();

      await longPressBack(tester);
      await tester.tap(find.text('Training'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(observer.removed, hasLength(1));
      expect(observer.popped, hasLength(1));
      expect(appBar(tester).title, 'Training');
      expect(appBar(tester).isRootPage, isFalse);

      await teardownPage(tester);
    });
  });

  group('the selection-mode bar swap', () {
    // The tall sliver leaves the scroll view and the 48 dp selection bar
    // takes its place outside it, so an uncompensated offset would carry
    // every row up by the difference.
    const shift =
        FolderSliverAppBar.expandedHeightNested - SelectionAppBar.height;
    const rootShift =
        FolderSliverAppBar.expandedHeightRoot - SelectionAppBar.height;

    testWidgets('entering selection leaves the rows where they are, and '
        'leaving puts the offset back', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      scrollPosition(tester).jumpTo(300);
      await tester.pumpAndSettle();

      final before = rowTops(tester);
      expect(before, isNotEmpty);

      await enterSelection(tester);

      expect(scrollPosition(tester).pixels, 300 - shift);
      final after = rowTops(tester);
      final shared = before.keys.where(after.containsKey).toList();
      expect(shared, isNotEmpty);
      for (final row in shared) {
        expect(after[row], moreOrLessEquals(before[row]!), reason: row);
      }

      await leaveSelection(tester);

      expect(scrollPosition(tester).pixels, 300);

      await teardownPage(tester);
    });

    testWidgets('scrolling while selecting is kept, not thrown away', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      scrollPosition(tester).jumpTo(300);
      await tester.pumpAndSettle();

      await enterSelection(tester);
      scrollPosition(tester).jumpTo(300 - shift + 40);
      await tester.pumpAndSettle();

      await leaveSelection(tester);

      expect(scrollPosition(tester).pixels, 340);

      await teardownPage(tester);
    });

    testWidgets('a list shorter than the screen stays at the top through '
        'both swaps', (tester) async {
      await pumpPage(tester, folderId: grandchild.id, title: 'Week 1');
      expect(scrollPosition(tester).pixels, 0);

      await enterSelection(tester);
      expect(scrollPosition(tester).pixels, 0);

      await leaveSelection(tester);
      expect(scrollPosition(tester).pixels, 0);

      await teardownPage(tester);
    });

    testWidgets('entering selection at the top and scrolling gives the '
        'offset back with the bar', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      expect(scrollPosition(tester).pixels, 0);

      await enterSelection(tester);
      // Entering at zero has nothing to give back, so the shift clamps away;
      // the scroll that follows is real and must come back with the taller
      // bar's height added, not with the clamped-away pixels.
      expect(scrollPosition(tester).pixels, 0);
      scrollPosition(tester).jumpTo(150);
      await tester.pumpAndSettle();
      final before = rowTops(tester);
      expect(before, isNotEmpty);

      await leaveSelection(tester);

      expect(scrollPosition(tester).pixels, 150 + shift);
      final after = rowTops(tester);
      final shared = before.keys.where(after.containsKey).toList();
      expect(shared, isNotEmpty);
      for (final row in shared) {
        expect(after[row], moreOrLessEquals(before[row]!), reason: row);
      }

      await teardownPage(tester);
    });

    testWidgets('the root list does not jump when selection starts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 240);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpPage(tester);

      final position = scrollPosition(tester);
      expect(position.maxScrollExtent, greaterThan(rootShift + 40));
      position.jumpTo(rootShift + 40);
      await tester.pumpAndSettle();
      final before = folderRowTops(tester);
      expect(before, isNotEmpty);

      await enterSelection(tester);

      expect(scrollPosition(tester).pixels, 40);
      final after = folderRowTops(tester);
      for (final row in before.keys) {
        expect(
          after[row],
          moreOrLessEquals(before[row]!, epsilon: 1),
          reason: row,
        );
      }

      await leaveSelection(tester);
      expect(scrollPosition(tester).pixels, rootShift + 40);

      await teardownPage(tester);
    });
  });

  group('grouped rows', () {
    testWidgets('folders and notes are labelled when both are present', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(find.text(l10n.folders.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.notes.toUpperCase()), findsOneWidget);
      expect(find.byType(FolderRow), findsOneWidget);
      expect(find.byType(NoteRow), findsWidgets);
      // The label is what makes the group readable; with one group there is
      // nothing to tell apart, so it would only cost a line.
      expect(
        tester.getTopLeft(find.byType(FolderRow).first).dy,
        lessThan(tester.getTopLeft(find.byType(NoteRow).first).dy),
      );

      await teardownPage(tester);
    });

    testWidgets('a folder holding only folders is not labelled', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id);

      expect(find.byType(FolderRow), findsOneWidget);
      expect(find.byType(NoteRow), findsNothing);
      expect(find.text(l10n.folders.toUpperCase()), findsNothing);
      expect(find.text(l10n.notes.toUpperCase()), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('a folder row counts the notes below it, descendants '
        'included', (tester) async {
      await pumpPage(tester, folderId: folder.id);

      // Training holds no notes itself; all fifteen live two levels down.
      final row = tester.widget<FolderRow>(find.byType(FolderRow));
      expect(row.noteCount, 15);
      expect(
        find.descendant(of: find.byType(FolderRow), matching: find.text('15')),
        findsOneWidget,
      );

      await teardownPage(tester);
    });

    testWidgets('a note row shows the preview when the setting is on', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(
        tester.widget<NoteRow>(find.byType(NoteRow).first).showPreview,
        isTrue,
      );
      expect(find.textContaining('squat, bench, row'), findsWidgets);

      await teardownPage(tester);
    });

    testWidgets('the preview line disappears when the setting is off', (
      tester,
    ) async {
      // Through `runAsync`: the test body itself runs in fake time, which the
      // settings write — a real database round trip — never returns in.
      await tester.runAsync(() => settings.setShowNotePreview(false));
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(
        tester.widget<NoteRow>(find.byType(NoteRow).first).showPreview,
        isFalse,
      );
      expect(find.textContaining('squat, bench, row'), findsNothing);
      // The date it shared the line with stays.
      expect(find.byType(NoteRow), findsWidgets);

      await teardownPage(tester);
    });
  });

  group('the mock palette', () {
    Scaffold pageScaffold(WidgetTester tester) => tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(OptimizedFolderContentPage),
            matching: find.byType(Scaffold),
          )
          .first,
    );

    /// The shell's own `Material` is the first one under it: everything the
    /// row draws inside is an `InkWell`, which adds no `Material` of its own.
    Color firstGroupColor(WidgetTester tester) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(ContentRowShell).first,
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;

    for (final (name, theme, scheme) in [
      ('light', AppTheme.light(), AppTheme.lightScheme),
      ('dark', AppTheme.dark(), AppTheme.darkScheme),
    ]) {
      testWidgets('in $name the groups sit one tone above the ground', (
        tester,
      ) async {
        await pumpPage(tester, folderId: child.id, theme: theme);

        expect(pageScaffold(tester).backgroundColor, scheme.pageGround);
        expect(firstGroupColor(tester), scheme.rowGroup);
        // Not the same tone: an invisible step is the bug this replaced.
        expect(scheme.rowGroup, isNot(scheme.pageGround));

        await teardownPage(tester);
      });

      testWidgets('in $name the large bar sits on the same ground', (
        tester,
      ) async {
        await pumpPage(tester, folderId: child.id, theme: theme);

        final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
        expect(bar.backgroundColor, scheme.pageGround);
        // Both halves of "no tone change on scroll".
        expect(bar.surfaceTintColor, Colors.transparent);
        expect(bar.scrolledUnderElevation, 0);

        await teardownPage(tester);
      });
    }

    testWidgets('a folder row wears the one accent the mock has', (
      tester,
    ) async {
      await pumpPage(tester, folderId: folder.id, theme: AppTheme.light());

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(FolderRow),
          matching: find.byIcon(Icons.folder_outlined),
        ),
      );
      expect(icon.color, AppTheme.lightScheme.primary);

      await teardownPage(tester);
    });
  });

  group('a long press on a row', () {
    /// The sheet's rows, top to bottom, so *Select* can be shown to be the
    /// first one rather than merely present.
    List<String> sheetRows(WidgetTester tester) => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data!)
        .toList();

    testWidgets('a folder row opens a sheet that leads with Select and '
        'carries the four card actions', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      await tester.longPress(find.byType(FolderRow));
      await tester.pumpAndSettle();

      expect(sheetRows(tester), [
        l10n.select,
        l10n.rename,
        l10n.moveToFolder,
        l10n.shareFolder,
        l10n.delete,
      ]);

      await tester.tap(find.text(l10n.select));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(find.byType(SelectionAppBar), findsOneWidget);
      expect(find.byType(SelectionActionBar), findsOneWidget);
      expect(
        tester.widget<SelectionAppBar>(find.byType(SelectionAppBar)).count,
        1,
      );

      await leaveSelection(tester);
      await teardownPage(tester);
    });

    testWidgets('a note row opens the same sheet, and Select puts that note '
        'in the selection', (tester) async {
      await pumpPage(tester, folderId: notesOnly.id, title: 'Loose notes');

      await tester.longPress(find.text('Loose 1'));
      await tester.pumpAndSettle();

      expect(sheetRows(tester), [
        l10n.select,
        l10n.rename,
        l10n.moveToFolder,
        l10n.shareNote,
        l10n.delete,
      ]);

      await tester.tap(find.text(l10n.select));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(
        tester.widget<SelectionAppBar>(find.byType(SelectionAppBar)).count,
        1,
      );

      await leaveSelection(tester);
      await teardownPage(tester);
    });
  });

  group('the root smart rows', () {
    testWidgets('the root opens with All notes and Recent above its folders', (
      tester,
    ) async {
      await pumpPage(tester);

      final allNotes = find.text(l10n.allNotes);
      final recent = find.text(l10n.recent);
      expect(allNotes, findsOneWidget);
      expect(recent, findsOneWidget);
      expect(
        tester.getTopLeft(allNotes).dy,
        lessThan(tester.getTopLeft(recent).dy),
      );
      expect(
        tester.getTopLeft(recent).dy,
        lessThan(tester.getTopLeft(find.byType(FolderRow).first).dy),
      );

      await teardownPage(tester);
    });

    testWidgets('All notes carries the live global count', (tester) async {
      await pumpPage(tester);

      // Nineteen: fifteen sessions two levels down, three loose notes and
      // the one titled "down day". A bare number, as the mock draws it.
      expect(find.text('19'), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('the folders below them are labelled, which a folder page '
        'holding only folders is not', (tester) async {
      await pumpPage(tester);

      expect(find.text(l10n.folders.toUpperCase()), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('a nested folder has no smart rows', (tester) async {
      await pumpPage(tester, folderId: folder.id);

      expect(find.text(l10n.allNotes), findsNothing);
      expect(find.text(l10n.recent), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('All notes pushes a route stamped for launch restore', (
      tester,
    ) async {
      final history = NavigationHistoryService();
      await pumpPage(tester, observers: [NavigationHistoryObserver(history)]);

      await tester.tap(find.text(l10n.allNotes));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(history.stack, [
        const NavDestination(NavDestinationKind.allNotes),
      ]);
      expect(find.byType(AllNotesPage), findsOneWidget);

      AppNavigator.pop(tester.element(find.byType(AllNotesPage)));
      await tester.pumpAndSettle();
      await settle(tester);
      history.dispose();
      await teardownPage(tester);
    });

    testWidgets('Recent pushes the same page in its capped mode', (
      tester,
    ) async {
      final history = NavigationHistoryService();
      await pumpPage(tester, observers: [NavigationHistoryObserver(history)]);

      await tester.tap(find.text(l10n.recent));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(history.stack, [
        const NavDestination(NavDestinationKind.recentNotes),
      ]);
      expect(
        tester.widget<AllNotesPage>(find.byType(AllNotesPage)).mode,
        AllNotesMode.recent,
      );

      AppNavigator.pop(tester.element(find.byType(AllNotesPage)));
      await tester.pumpAndSettle();
      await settle(tester);
      history.dispose();
      await teardownPage(tester);
    });

    testWidgets('selection mode disables them — they stay drawn and cannot '
        'be tapped', (tester) async {
      await pumpPage(tester);
      await enterSelection(tester);

      // Still there: removing them would take ~164 dp out from above the
      // folder rows, which the bar swap does not pay for.
      expect(find.text(l10n.allNotes), findsOneWidget);
      expect(find.text(l10n.recent), findsOneWidget);
      expect(find.text(l10n.folders.toUpperCase()), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(l10n.allNotes),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );

      await tester.tap(find.text(l10n.recent));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byType(AllNotesPage), findsNothing);

      await leaveSelection(tester);
      await teardownPage(tester);
    });

    testWidgets('both are 48 tall and end in a chevron; only All notes '
        'carries a count', (tester) async {
      await pumpPage(tester);

      for (final label in [l10n.allNotes, l10n.recent]) {
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(ContentRowShell),
        );
        expect(
          tester
              .getSize(
                find.descendant(of: row, matching: find.byType(InkWell)).first,
              )
              .height,
          RowMetrics.singleLineMinHeight,
          reason: label,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsOneWidget,
          reason: label,
        );
      }

      final scheme = Theme.of(
        tester.element(find.text(l10n.allNotes)),
      ).colorScheme;
      for (final icon in [Icons.description_outlined, Icons.schedule_outlined]) {
        final glyph = tester.widget<Icon>(find.byIcon(icon));
        expect(glyph.size, RowMetrics.glyphSize);
        expect(glyph.color, scheme.primary);
      }

      // The count sits on All notes only; Recent's slot is reserved and
      // empty, which is what keeps the two rows the same shape.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(l10n.recent),
            matching: find.byType(ContentRowShell),
          ),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null && int.tryParse(w.data!) != null,
          ),
        ),
        findsNothing,
      );

      await teardownPage(tester);
    });
  });

  group('the bottom bar', () {
    testWidgets('is 52 dp over the safe-area inset, with primary 22 dp '
        'glyphs and a 13 px count', (tester) async {
      // Physical pixels: the harness runs at devicePixelRatio 3, so this is
      // a 48 dp gesture bar.
      tester.view.viewPadding = const FakeViewPadding(bottom: 144);
      tester.view.padding = const FakeViewPadding(bottom: 144);
      addTearDown(tester.view.reset);
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      final bar = find
          .ancestor(
            of: find.byIcon(Icons.create_new_folder_outlined),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getSize(bar).height, RowMetrics.bottomBarHeight);
      // Lifted clear of the gesture bar rather than drawn under it: the bar
      // and the inset below it fill the bottom of the window.
      final screenHeight = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      expect(
        screenHeight - tester.getTopLeft(bar).dy,
        RowMetrics.bottomBarHeight + 48,
      );

      final scheme = Theme.of(
        tester.element(find.byIcon(Icons.create_new_folder_outlined)),
      ).colorScheme;
      for (final icon in [
        Icons.create_new_folder_outlined,
        Icons.note_add_outlined,
      ]) {
        final button = tester.widget<IconButton>(
          find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
        );
        expect(button.iconSize, RowMetrics.bottomBarGlyphSize, reason: '$icon');
        expect(button.color, scheme.primary, reason: '$icon');
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.byIcon(icon),
                  matching: find.byType(IconButton),
                ),
              )
              .height,
          RowMetrics.bottomBarButtonSize,
          reason: '$icon',
        );
      }

      final count = tester.widget<Text>(
        find.text(
          l10n.folderAndNoteCount(
            l10n.folderCountLabel(1),
            l10n.noteCountLabel(15),
          ),
        ),
      );
      expect(count.style!.fontSize, RowMetrics.bottomBarCountFontSize);
      expect(count.style!.color, scheme.onSurfaceVariant);

      await teardownPage(tester);
    });

    testWidgets('the floating action button and its sheet are gone', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('a nested folder offers New folder and New note', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.note_add_outlined), findsOneWidget);
      // Import stays reachable from the overflow menu, not from the bar.
      expect(find.byIcon(Icons.file_download_outlined), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('the root offers Import in the slot a note cannot use', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.byIcon(Icons.create_new_folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.note_add_outlined), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('New folder opens the create dialog', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();

      expect(find.text(l10n.createFolder), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    testWidgets('the count reads both halves when both are present', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      expect(
        find.text(
          l10n.folderAndNoteCount(
            l10n.folderCountLabel(1),
            l10n.noteCountLabel(15),
          ),
        ),
        findsOneWidget,
      );

      await teardownPage(tester);
    });

    testWidgets('the count drops the note half when there are none', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.text(l10n.folderCountLabel(2)), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('the count drops the folder half when there are none', (
      tester,
    ) async {
      await pumpPage(tester, folderId: notesOnly.id, title: 'Loose notes');

      expect(find.text(l10n.noteCountLabel(4)), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('an empty folder says nothing rather than "no folders, no '
        'notes"', (tester) async {
      await pumpPage(tester, folderId: grandchild.id, title: 'Week 1');

      expect(find.text(l10n.folderCountLabel(0)), findsNothing);
      expect(find.text(l10n.noteCountLabel(0)), findsNothing);
      expect(find.text(l10n.createFromBarBelow), findsOneWidget);

      await teardownPage(tester);
    });
  });

  group('reordering stays inside its group', () {
    /// The one reorderable sliver over the whole list, headers included.
    SliverReorderableList reorderable(WidgetTester tester) => tester
        .widget<SliverReorderableList>(find.byType(SliverReorderableList));

    List<String> noteTitles(WidgetTester tester) => tester
        .widgetList<NoteRow>(find.byType(NoteRow))
        .map((row) => row.metadata.title)
        .toList();

    /// A surface tall enough to hold the folder, both labels and all fifteen
    /// notes at once, so the rendered order is the whole order.
    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    /// Lets the reorder's position writes land before the case ends.
    ///
    /// `_handleReorderMixed` deliberately does not await them — the optimistic
    /// list is what the user sees. They are started inside the case's fake
    /// clock, though, so their continuations only run while that clock is
    /// still being pumped: let the case end first and the sixteen row writes
    /// are stranded mid-transaction, and the *next* case's very first query
    /// queues behind a lock nothing will ever release. Real time alone does
    /// not do it either — [settle] alternates the two, which is the point.
    Future<void> drainWrites(WidgetTester tester) async {
      await settle(tester, rounds: 60);
    }

    testWidgets('a note dropped among the folders lands at the top of the '
        'notes instead', (tester) async {
      useTallSurface(tester);
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      await enterSelection(tester);

      final before = noteTitles(tester);
      expect(before, hasLength(15));
      // Rows: [Folders label][Week 1][Notes label][15 notes] — 18 in all, so
      // the last note is 17 and index 1 is inside the folder group.
      reorderable(tester).onReorderItem!(17, 1);
      await tester.pumpAndSettle();
      await settle(tester);

      final after = noteTitles(tester);
      expect(after.first, before.last);
      expect(after, [before.last, ...before.take(14)]);
      expect(
        tester.getTopLeft(find.byType(FolderRow).first).dy,
        lessThan(tester.getTopLeft(find.byType(NoteRow).first).dy),
        reason: 'the folder group must still come first',
      );

      await drainWrites(tester);
      await teardownPage(tester);
    });

    testWidgets('a folder dropped among the notes stays a folder row', (
      tester,
    ) async {
      useTallSurface(tester);
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      await enterSelection(tester);

      final before = noteTitles(tester);
      reorderable(tester).onReorderItem!(1, 16);
      await tester.pumpAndSettle();
      await settle(tester);

      expect(find.byType(FolderRow), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(FolderRow).first).dy,
        lessThan(tester.getTopLeft(find.byType(NoteRow).first).dy),
      );
      expect(noteTitles(tester), before, reason: 'the notes must not move');

      await drainWrites(tester);
      await teardownPage(tester);
    });

    testWidgets('a reorder inside the notes is kept', (tester) async {
      useTallSurface(tester);
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      await enterSelection(tester);

      final before = noteTitles(tester);
      // Third note to the front of its own group; nothing is clamped here.
      reorderable(tester).onReorderItem!(5, 3);
      await tester.pumpAndSettle();
      await settle(tester);

      expect(noteTitles(tester), [
        before[2],
        before[0],
        before[1],
        ...before.skip(3),
      ]);

      await drainWrites(tester);
      await teardownPage(tester);
    });

    testWidgets('a section label cannot be dragged anywhere', (tester) async {
      useTallSurface(tester);
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      await enterSelection(tester);

      final before = noteTitles(tester);
      // No drag listener can produce this, but the handler must refuse it
      // rather than reorder whatever happened to be at that index.
      reorderable(tester).onReorderItem!(0, 10);
      await tester.pumpAndSettle();
      await settle(tester);

      expect(noteTitles(tester), before);
      expect(find.text(l10n.folders.toUpperCase()), findsOneWidget);

      await drainWrites(tester);
      await teardownPage(tester);
    });
  });

  group('search hosted in place', () {
    /// The page's own bloc, reached through the provider it wraps the
    /// scaffold in — the only way to read the scope a chipless root opened on.
    SearchBloc searchBloc(WidgetTester tester) =>
        BlocProvider.of<SearchBloc>(tester.element(find.byType(Scaffold)));

    /// Frames without waiting for an idle tree: a pass in flight paints a
    /// `CircularProgressIndicator`, which `pumpAndSettle` never outlasts. The
    /// 400 ms is a route transition's worth of fake time.
    Future<void> flush(WidgetTester tester) async {
      await tester.pump();
      await settle(tester, rounds: 20);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester, rounds: 10);
    }

    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.search));
      await flush(tester);
    }

    Future<void> closeSearch(WidgetTester tester) async {
      await tester.tap(find.byType(BackButtonIcon));
      await flush(tester);
    }

    /// `SearchQueryChanged` is debounced 200 ms, so a plain [settle] — 60 ms
    /// of fake time — never reaches the quick pass.
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 250));
      await flush(tester);
    }

    /// The system back gesture, which is what has to find the search surface
    /// before it finds the route.
    Future<void> systemBack(WidgetTester tester) async {
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await flush(tester);
    }

    /// Section labels are upper-cased by [ContentSectionHeader], so they are
    /// read off the widget rather than found as text.
    List<String> sectionLabels(WidgetTester tester) => tester
        .widgetList<ContentSectionHeader>(find.byType(ContentSectionHeader))
        .map((header) => header.label)
        .toList();

    testWidgets('the search icon swaps the whole bar for a field, chips and '
        'recents', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      await openSearch(tester);

      expect(find.byType(FolderSliverAppBar), findsNothing);
      // No drawer while the field owns the bar: the arrow leaves search.
      expect(find.byType(LeadingNavPair), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Winter block'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, l10n.everywhere), findsOneWidget);
      // The bar reserves a fixed height for the chips, so a taller row would
      // be cut off by the sliver's own extent rather than push it open.
      expect(
        tester.getSize(find.byType(SearchScopeChips)).height,
        lessThanOrEqualTo(SearchScopeChips.preferredHeight),
      );
      expect(sectionLabels(tester), [l10n.recent]);
      expect(find.byType(SearchResultRow), findsWidgets);
      // The list it replaced, and the bar that created into it, are both gone.
      expect(find.byType(NoteRow), findsNothing);
      expect(find.byType(FolderRow), findsNothing);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('the root searches everywhere and offers no chips', (
      tester,
    ) async {
      await pumpPage(tester);

      await openSearch(tester);

      expect(find.byType(SearchScopeChips), findsNothing);
      expect(searchBloc(tester).state.scope, const SearchScope.everywhere());
      expect(find.text(l10n.searchAll), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('typing shows hits grouped where the folder list was', (
      tester,
    ) async {
      await pumpPage(tester, folderId: notesOnly.id, title: 'Loose notes');

      await openSearch(tester);
      await type(tester, 'down');

      expect(sectionLabels(tester), [l10n.titlesSection, l10n.inTextSection]);
      expect(find.byType(SearchResultRow), findsNWidgets(4));
      expect(find.byType(NoteRow), findsNothing);

      await teardownPage(tester);
    });

    /// Backspacing "down" away one character at a time: the last non-empty
    /// keystroke is still inside its debounce when the field goes blank, and
    /// it used to land 200 ms later as a search for "dow" under an empty
    /// field.
    testWidgets('emptying the field while a keystroke is still debounced '
        'shows recents, not that keystroke', (tester) async {
      await pumpPage(tester, folderId: notesOnly.id, title: 'Loose notes');

      await openSearch(tester);
      await type(tester, 'down');
      expect(sectionLabels(tester), [l10n.titlesSection, l10n.inTextSection]);

      await tester.enterText(find.byType(TextField), 'dow');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 250));
      await flush(tester);

      expect(sectionLabels(tester), [l10n.recent]);
      expect(searchBloc(tester).state.query, isEmpty);
      expect(searchBloc(tester).state.hasResults, isFalse);

      await teardownPage(tester);
    });

    testWidgets('back leaves search before it leaves the folder', (
      tester,
    ) async {
      final observer = _RecordingObserver();
      await pumpPage(tester, observers: [observer]);
      await pushFolder(tester, folder);
      await openSearch(tester);
      await type(tester, 'Session');
      observer.clear();

      await systemBack(tester);

      expect(observer.popped, isEmpty);
      expect(find.byType(FolderSliverAppBar), findsOneWidget);
      expect(find.byType(SearchResultRow), findsNothing);

      await systemBack(tester);

      expect(observer.popped, hasLength(1));
      expect(appBar(tester).isRootPage, isTrue);

      await teardownPage(tester);
    });

    testWidgets('the folder list comes back at the offset it left', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      scrollPosition(tester).jumpTo(300);
      await tester.pumpAndSettle();
      final before = rowTops(tester);
      expect(before, isNotEmpty);

      await openSearch(tester);

      // Results open at their own top, not 300 px into someone else's list.
      expect(scrollPosition(tester).pixels, 0);

      await closeSearch(tester);

      expect(scrollPosition(tester).pixels, 300);
      final after = rowTops(tester);
      final shared = before.keys.where(after.containsKey).toList();
      expect(shared, isNotEmpty);
      for (final row in shared) {
        expect(after[row], moreOrLessEquals(before[row]!), reason: row);
      }

      await teardownPage(tester);
    });

    testWidgets('selection mode has no way in while search is up, and comes '
        'back when it closes', (tester) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');

      await openSearch(tester);

      // The overflow menu is the only door into selection, and long-press
      // needs a row: neither is on screen while results are.
      expect(find.byType(FolderOverflowMenu), findsNothing);
      expect(find.byType(NoteRow), findsNothing);

      await closeSearch(tester);
      await enterSelection(tester);

      expect(find.byType(SelectionAppBar), findsOneWidget);

      await leaveSelection(tester);
      await teardownPage(tester);
    });

    testWidgets('opening and closing search leaves the recorded location '
        'stack alone', (tester) async {
      final history = NavigationHistoryService();
      addTearDown(history.dispose);
      await pumpPage(tester, observers: [NavigationHistoryObserver(history)]);
      await pushFolder(tester, folder);

      final recorded = [
        NavDestination.folder(folderId: folder.id, title: folder.name),
      ];
      expect(history.stack, recorded);

      await openSearch(tester);
      expect(history.stack, recorded);

      await type(tester, 'Session');
      expect(history.stack, recorded);

      await closeSearch(tester);
      expect(history.stack, recorded);

      await teardownPage(tester);
    });

    testWidgets('coming back from a pushed route keeps the query and re-runs '
        'it', (tester) async {
      await pumpPage(tester, folderId: notesOnly.id, title: 'Loose notes');
      await openSearch(tester);
      await type(tester, 'down');

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('a note')),
            ),
          )
          .ignore();
      await tester.pumpAndSettle();
      expect(find.text('a note'), findsOneWidget);

      navigator.pop();
      await flush(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'down',
      );
      expect(find.byType(SearchResultRow), findsNWidgets(4));
      expect(sectionLabels(tester), [l10n.titlesSection, l10n.inTextSection]);

      await teardownPage(tester);
    });

    testWidgets('returning from a recent keeps the recents list where it was', (
      tester,
    ) async {
      await pumpPage(tester, folderId: child.id, title: 'Winter block');
      await openSearch(tester);
      expect(sectionLabels(tester), [l10n.recent]);

      final position = scrollPosition(tester);
      expect(position.maxScrollExtent, greaterThan(200));
      position.jumpTo(200);
      await tester.pump();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('a note')),
            ),
          )
          .ignore();
      await tester.pumpAndSettle();
      navigator.pop();
      await flush(tester);

      // The refresh the pop runs re-reads the same recents. Replacing them
      // with a full-screen spinner for that round trip collapses the scroll
      // extent to zero, and the offset never comes back.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SearchResultRow), findsWidgets);
      expect(scrollPosition(tester).pixels, 200);

      await teardownPage(tester);
    });

    testWidgets('the keyboard opening does not take the focus it was opened '
        'for', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      await pumpPage(tester, folderId: notesOnly.id, title: 'Loose notes');
      await openSearch(tester);

      final focusNode = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(focusNode.hasFocus, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = FakeViewPadding.zero;
      await flush(tester);

      expect(focusNode.hasFocus, isTrue);
      expect(find.byType(TextField), findsOneWidget);

      await teardownPage(tester);
    });
  });
}

/// Records page routes only: the ancestor menu is itself a route, and its
/// dismissal would otherwise read as a navigation.
class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> popped = [];
  final List<Route<dynamic>> removed = [];

  void clear() {
    pushed.clear();
    popped.clear();
    removed.clear();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) popped.add(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) removed.add(route);
  }
}
