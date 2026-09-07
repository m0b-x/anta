import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_state.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/pages/all_notes_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/move_history_service.dart';
import 'package:anta/services/move_history_store.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/folder_sliver_app_bar.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/note_row.dart';
import 'package:anta/widgets/search_field_app_bar.dart';
import 'package:anta/widgets/search_surface.dart';

/// The flat note lists the root's two smart rows open.
///
/// What is worth a page-level test here is the flattening: rows drawn from
/// several folders at once, each carrying the path it came from, and a
/// "Recent" mode that is the same page under a cap rather than a copy of it.
///
/// Harness notes travel with the browser suite
/// ([optimized_folder_content_page_test]): `path_provider` and
/// `SharedPreferences` are mocked so every singleton binds to one real
/// database, drift answers on a background isolate that `FakeAsync` cannot
/// advance (hence [settle] rather than `pumpAndSettle` alone), and the page is
/// unmounted before the case ends so no timer outlives it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late SettingsService settings;
  late FolderStorageService folderService;
  late NoteStorageService noteService;
  late FolderSearchService searchService;
  late OptimizedNoteBloc noteBloc;
  late ImportExportBloc exportBloc;

  late Folder training;
  late Folder winter;

  /// More than [AllNotesPage.recentLimit], so the cap has something to cut.
  const sessionCount = 60;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_all_notes_page');
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
    await settings.setShowNotePreview(true);

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
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());

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

    training = await db.folderDao.createFolder(name: 'Training');
    winter = await db.folderDao.createFolder(
      name: 'Winter block',
      parentId: training.id,
    );
    // Two folders at different depths, so a row's path has to say more than
    // the folder's own name to be right.
    for (var i = 0; i < sessionCount; i++) {
      await noteService.createNote(
        folderId: winter.id,
        title: 'Session ${i + 1}',
        content: 'squat, bench, row',
      );
    }
    await noteService.createNote(
      folderId: training.id,
      title: 'Plan',
      content: 'the block in outline',
    );
    // Sixty-one rows written inside one second share an `updatedAt` — drift
    // stores it to the second — and "most recently edited" then falls back to
    // whatever order the rows happen to come out in. One statement spreads
    // them so the newest is the last written, which is what the page claims
    // to show and what the cap has to cut from.
    await db.customStatement(
      "UPDATE notes SET updated_at = strftime('%s','now') + rowid",
    );
  });

  tearDownAll(() async {
    await noteBloc.close();
    await exportBloc.close();
    await GetIt.I.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  final l10n = AppLocalizationsEn();

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
    AllNotesMode mode = AllNotesMode.all,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
          BlocProvider<ImportExportBloc>.value(value: exportBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [AppNavigator.routeObserver],
          home: AllNotesPage(mode: mode),
        ),
      ),
    );
    await settle(tester);
  }

  List<NoteRow> rows(WidgetTester tester) =>
      tester.widgetList<NoteRow>(find.byType(NoteRow)).toList();

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

  group('All notes', () {
    testWidgets('the bar is the nav pair, the title and a search icon', (
      tester,
    ) async {
      await pumpPage(tester);

      final bar = tester.widget<FolderSliverAppBar>(
        find.byType(FolderSliverAppBar),
      );
      expect(bar.isRootPage, isFalse);
      expect(bar.title, l10n.allNotes);
      expect(bar.eyebrow, isNull);
      expect(find.byType(LeadingNavPair), findsOneWidget);
      expect(find.byType(BackButtonIcon), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('the drawer button opens the drawer this page hosts', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );

      await teardownPage(tester);
    });

    testWidgets('it lists notes from several folders at once', (tester) async {
      await pumpPage(tester);

      final titles = rows(tester).map((row) => row.metadata.title).toSet();
      expect(titles, contains('Plan'));
      expect(titles.any((title) => title.startsWith('Session ')), isTrue);

      await teardownPage(tester);
    });

    testWidgets('every row carries the folder path it lives under', (
      tester,
    ) async {
      await pumpPage(tester);

      final byTitle = {
        for (final row in rows(tester)) row.metadata.title: row,
      };
      expect(byTitle['Plan']!.pathLabel, 'Training');
      final session = byTitle.entries.firstWhere(
        (entry) => entry.key.startsWith('Session '),
      );
      expect(session.value.pathLabel, 'Training › Winter block');
      expect(find.text('Training › Winter block'), findsWidgets);

      await teardownPage(tester);
    });

    testWidgets('a row is scoped to its own folder, not to the page', (
      tester,
    ) async {
      await pumpPage(tester);

      // The move, the rename-uniqueness check and the push all read this;
      // a flat list that handed every row one folder id would send them all
      // to the wrong place.
      final byTitle = {
        for (final row in rows(tester)) row.metadata.title: row,
      };
      expect(byTitle['Plan']!.folderId, training.id);
      expect(
        byTitle.entries
            .firstWhere((entry) => entry.key.startsWith('Session '))
            .value
            .folderId,
        winter.id,
      );

      await teardownPage(tester);
    });

    testWidgets('the path lane is reserved before the walk answers, so rows '
        'do not move when it lands', (tester) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
            BlocProvider<ImportExportBloc>.value(value: exportBloc),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AllNotesPage(),
          ),
        ),
      );
      // Enough for the notes but not necessarily for the ancestor walk.
      await settle(tester, rounds: 4);
      final early = rows(tester);
      if (early.isNotEmpty) {
        final heightBefore = tester.getSize(find.byType(NoteRow).first).height;
        await settle(tester, rounds: 20);
        expect(rows(tester).first.pathLabel, isNotEmpty);
        expect(tester.getSize(find.byType(NoteRow).first).height, heightBefore);
      }

      await teardownPage(tester);
    });
  });

  group('Recent', () {
    testWidgets('it is the same page under a cap, not a copy', (tester) async {
      await pumpPage(tester, mode: AllNotesMode.recent);

      final bar = tester.widget<FolderSliverAppBar>(
        find.byType(FolderSliverAppBar),
      );
      expect(bar.title, l10n.recent);
      expect(find.byType(AllNotesPage), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('it never lists more than the cap, however far it scrolls', (
      tester,
    ) async {
      await pumpPage(tester, mode: AllNotesMode.recent);

      final position = scrollPosition(tester);
      for (var i = 0; i < 12; i++) {
        position.jumpTo(position.maxScrollExtent);
        await settle(tester, rounds: 6);
      }

      // The rendered rows are a window onto the list, so the list length is
      // read off the bloc's page instead: the cap is on what was asked for.
      final state = noteBloc.state;
      expect(state, isA<OptimizedNoteLoaded>());
      final loaded = state as OptimizedNoteLoaded;
      expect(
        loaded.paginatedNotes.notes.length,
        lessThanOrEqualTo(AllNotesPage.recentLimit),
      );
      expect(loaded.paginatedNotes.totalCount, sessionCount + 1);

      await teardownPage(tester);
    });
  });

  group('search hosted in place', () {
    /// Frames without waiting for an idle tree: a pass in flight paints a
    /// `CircularProgressIndicator`, which `pumpAndSettle` never outlasts.
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

    /// `SearchQueryChanged` is debounced 200 ms, so a plain [settle] — 60 ms
    /// of fake time — never reaches the quick pass.
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 250));
      await flush(tester);
    }

    testWidgets('the search icon swaps the whole bar for a field, and offers '
        'no scope chips', (tester) async {
      await pumpPage(tester);

      await openSearch(tester);

      expect(find.byType(SearchFieldAppBar), findsOneWidget);
      expect(find.byType(FolderSliverAppBar), findsNothing);
      // Everywhere is the only scope a flat list of every note can have.
      expect(find.byType(SearchScopeChips), findsNothing);
      expect(find.byType(NoteRow), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('typing shows hits where the list was', (tester) async {
      await pumpPage(tester);

      await openSearch(tester);
      await type(tester, 'Plan');

      expect(find.byType(SearchResultRow), findsWidgets);
      expect(
        tester
            .widgetList<SearchResultRow>(find.byType(SearchResultRow))
            .map((row) => row.metadata.title),
        contains('Plan'),
      );

      await teardownPage(tester);
    });

    testWidgets('back leaves search before it leaves the page, and the list '
        'comes back at the offset it left', (tester) async {
      await pumpPage(tester);

      final position = scrollPosition(tester);
      position.jumpTo(400);
      await tester.pump();
      final before = position.pixels;

      await openSearch(tester);
      expect(scrollPosition(tester).pixels, 0);

      await tester.tap(find.byType(BackButtonIcon));
      await flush(tester);

      expect(find.byType(SearchFieldAppBar), findsNothing);
      expect(find.byType(FolderSliverAppBar), findsOneWidget);
      expect(scrollPosition(tester).pixels, before);

      await teardownPage(tester);
    });

    testWidgets('leaving the list unregisters its load-more listener', (
      tester,
    ) async {
      await pumpPage(tester);
      final list = scrollPosition(tester);
      list.jumpTo(list.maxScrollExtent);
      await settle(tester, rounds: 8);

      await openSearch(tester);

      final recorder = _EventRecorder();
      final previousObserver = Bloc.observer;
      Bloc.observer = recorder;
      addTearDown(() => Bloc.observer = previousObserver);

      final results = scrollPosition(tester);
      results.jumpTo(results.maxScrollExtent);
      await flush(tester);

      expect(
        recorder.events.whereType<LoadMoreNotes>(),
        isEmpty,
        reason:
            'the paging sliver left the tree when the bar became a field; a '
            'listener left on the page controller goes on paging the list '
            'that is no longer there, once per search round trip',
      );

      await teardownPage(tester);
    });
  });

  group('coming back to the page', () {
    /// Pushes a bare route and pops it, so the page runs the `didPopNext`
    /// path a note editor would return through.
    Future<void> roundTrip(WidgetTester tester) async {
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
      await settle(tester, rounds: 20);
    }

    testWidgets('returning from a note keeps the pages already loaded', (
      tester,
    ) async {
      await pumpPage(tester);
      final position = scrollPosition(tester);
      position.jumpTo(position.maxScrollExtent);
      await settle(tester, rounds: 20);

      final loaded = noteBloc.state as OptimizedNoteLoaded;
      expect(
        loaded.paginatedNotes.notes.length,
        greaterThan(NoteStorageService.defaultPageSize),
        reason: 'the case needs a list that has actually paged',
      );
      final before = loaded.paginatedNotes.notes.length;

      await roundTrip(tester);

      expect(
        (noteBloc.state as OptimizedNoteLoaded).paginatedNotes.notes.length,
        before,
        reason:
            'the reload asked for page 1 alone, so All notes shrank back to '
            'twenty rows and the offset clamped to the top with it',
      );

      await teardownPage(tester);
    });

    testWidgets('a MediaQuery change does not re-read settings', (
      tester,
    ) async {
      addTearDown(() => settings.setFolderSwipeEnabled(true));
      addTearDown(tester.view.reset);
      await pumpPage(tester);

      Scaffold pageScaffold() =>
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(pageScaffold().drawerEnableOpenDragGesture, isTrue);

      // Changed behind the page's back: only a moment that actually re-reads
      // the preferences can pick this up.
      await tester.runAsync(() => settings.setFolderSwipeEnabled(false));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await settle(tester, rounds: 10);

      expect(
        pageScaffold().drawerEnableOpenDragGesture,
        isTrue,
        reason:
            'didChangeDependencies fires on every MediaQuery change — once '
            'per keyboard animation frame — and reading two preferences plus '
            'a page setState there is work the keyboard should not cost',
      );

      // The pop back from the settings page is the moment that does re-read.
      await roundTrip(tester);
      expect(pageScaffold().drawerEnableOpenDragGesture, isFalse);

      await teardownPage(tester);
    });

    testWidgets('a failed path walk is retried on the next build', (
      tester,
    ) async {
      final flaky = _FlakyFolderStorage(FolderRepository(database: db));
      await tester.runAsync(flaky.initialize);
      flaky.failuresLeft = 1;
      GetIt.I.unregister<FolderStorageService>();
      GetIt.I.registerSingleton<FolderStorageService>(flaky);
      addTearDown(() {
        GetIt.I.unregister<FolderStorageService>();
        GetIt.I.registerSingleton<FolderStorageService>(folderService);
      });

      await pumpPage(tester);

      expect(
        flaky.calls,
        greaterThan(1),
        reason:
            'the first walk threw. The ids used to be recorded as answered '
            'before the await, so nothing ever asked again',
      );
      expect(
        rows(tester).first.pathLabel,
        isNotEmpty,
        reason: 'the retry landed, so the path lane is filled in after all',
      );

      await teardownPage(tester);
    });
  });
}

/// Every event that reaches any bloc, for asserting that one never does.
class _EventRecorder extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    events.add(event);
    super.onEvent(bloc, event);
  }
}

/// Fails the ancestor walk a scripted number of times before answering.
class _FlakyFolderStorage extends FolderStorageService {
  _FlakyFolderStorage(FolderRepository repository)
    : super(repository: repository);

  int calls = 0;
  int failuresLeft = 0;

  @override
  Future<Map<String, List<String>>> folderPathSegments(
    Iterable<String> folderIds,
  ) {
    calls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      return Future.error(StateError('walk failed'));
    }
    return super.folderPathSegments(folderIds);
  }
}
