import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_bloc.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_event.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_state.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_state.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/folder.dart' as model;
import 'package:anta/models/item_label.dart';
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
import 'package:anta/services/note_storage_service.dart'
    show NoteStorageService, NotesSortOrder;
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/folder_row.dart';
import 'package:anta/widgets/note_row.dart';

import '../services/support/body_index_support.dart';

/// The browser as the app stacks it: one app-wide [OptimizedFolderBloc]
/// under every folder page, a page pushed for each folder opened. What a
/// page shows after another page loaded its own parent through the same
/// bloc — and whether every row of a parent can be reached — is a question
/// only mounted pages can answer.
///
/// Harness as in `optimized_folder_content_page_test.dart`: one real
/// database behind mocked `path_provider` and `SharedPreferences`, services
/// and BLoCs built in `setUpAll`, real async work let through by [settle].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late FolderRepository folderRepository;
  late _FlakyFolderStorageService folderService;
  late NoteStorageService noteService;
  late OptimizedFolderBloc folderBloc;
  late OptimizedNoteBloc noteBloc;
  late ImportExportBloc exportBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_folder_parents');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    await SettingsService.getInstance();

    folderRepository = FolderRepository(database: db);
    final noteRepository = NoteRepository(database: db);
    folderService = _FlakyFolderStorageService(
      repository: folderRepository,
      noteRepository: noteRepository,
    );
    await folderService.initialize();
    noteService = NoteStorageService(repository: noteRepository);
    await noteService.initialize();
    final searchService = FolderSearchService(
      storageService: noteService,
      indexer: bodyIndexerOver(db),
    );
    await searchService.initialize();

    GetIt.I.registerSingleton<NoteRepository>(noteRepository);
    GetIt.I.registerSingleton<FolderRepository>(folderRepository);
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
        folderRepository: folderRepository,
        noteRepository: noteRepository,
      ),
    );
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());

    folderBloc = OptimizedFolderBloc(storageService: folderService);
    noteBloc = OptimizedNoteBloc(storageService: noteService);
    exportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: noteService,
        folderStorage: folderService,
        noteRepository: noteRepository,
      ),
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

  tearDown(() {
    folderService.failCreates = false;
    folderService.failLoads = false;
  });

  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  Future<T> real<T>(WidgetTester tester, Future<T> Function() work) async =>
      (await tester.runAsync(work)) as T;

  /// Ends with the real reads the last frames started let through: the
  /// services outlive the case, and a share-census read left halfway in this
  /// case's fake zone is memoized, so every later case awaiting the census
  /// would wait on it for good.
  Future<void> teardownPage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await settle(tester, rounds: 4);
  }

  /// [settled] false returns with the first frame drawn and nothing the
  /// blocs were asked yet answered, as at a cold launch. [stack] puts those
  /// folders' pages over it as the navigator's initial routes, so every page
  /// builds in the first frame, before the blocs have answered anything.
  Future<void> pumpPage(
    WidgetTester tester, {
    String? folderId,
    bool settled = true,
    List<Folder> stack = const [],
  }) async {
    final home = OptimizedFolderContentPage(
      folderId: folderId,
      title: folderId == null ? 'ANTA' : 'Parent',
    );
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
          home: stack.isEmpty ? home : null,
          initialRoute: stack.isEmpty ? null : '/',
          onGenerateRoute: (_) => null,
          onGenerateInitialRoutes: stack.isEmpty
              ? null
              : (_) => [
                  MaterialPageRoute<void>(builder: (_) => home),
                  for (final folder in stack)
                    MaterialPageRoute<void>(
                      builder: (_) => OptimizedFolderContentPage(
                        folderId: folder.id,
                        title: folder.name,
                      ),
                    ),
                ],
        ),
      ),
    );
    if (settled) await settle(tester);
  }

  /// A route's animation, then the pages' real async work; never
  /// `pumpAndSettle`, which a loading spinner keeps from settling.
  Future<void> transition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  /// Opens [folder] the way tapping its row does, on top of the page shown.
  Future<void> push(WidgetTester tester, Folder folder) async {
    AppNavigator.toFolder(
      tester.element(find.byType(OptimizedFolderContentPage).last),
      folderId: folder.id,
      title: folder.name,
    ).ignore();
    await transition(tester);
  }

  Future<void> back(WidgetTester tester) async {
    Navigator.of(
      tester.element(find.byType(OptimizedFolderContentPage).last),
    ).pop();
    await transition(tester);
  }

  /// The folder rows the shown page draws now, by name.
  Set<String> folderRowsInView(WidgetTester tester) => {
    for (final row in tester.widgetList<FolderRow>(
      find.descendant(
        of: find.byType(OptimizedFolderContentPage).last,
        matching: find.byType(FolderRow),
      ),
    ))
      row.folder.name,
  };

  /// Every folder row a scroll to the end of the shown page passes.
  Future<Set<String>> folderRowsReachable(WidgetTester tester) async {
    final seen = <String>{...folderRowsInView(tester)};
    for (var i = 0; i < 40; i++) {
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -250),
      );
      await tester.pump();
      await settle(tester, rounds: 4);
      seen.addAll(folderRowsInView(tester));
    }
    return seen;
  }

  ItemLabel? labelOfRow(WidgetTester tester, String name) {
    for (final row in tester.widgetList<FolderRow>(find.byType(FolderRow))) {
      if (row.folder.name == name) return row.folder.label;
    }
    return null;
  }

  /// A folder written beneath the repository and announced as a sync pull
  /// announces it.
  Future<Folder> mergedIn(
    WidgetTester tester,
    String name, {
    String? parentId,
  }) => real(tester, () async {
    final folder = await db.folderDao.createFolder(
      name: name,
      parentId: parentId,
    );
    await folderRepository.announceMerged([folder.id], inserted: {folder.id});
    return folder;
  });

  /// The folder rows the shown page draws, in the order it draws them.
  List<String> orderInView(WidgetTester tester) => [
    for (final row in tester.widgetList<FolderRow>(
      find.descendant(
        of: find.byType(OptimizedFolderContentPage).last,
        matching: find.byType(FolderRow),
      ),
    ))
      row.folder.name,
  ];

  /// The note rows the shown page draws, by title.
  Set<String> noteRowsInView(WidgetTester tester) => {
    for (final row in tester.widgetList<NoteRow>(
      find.descendant(
        of: find.byType(OptimizedFolderContentPage).last,
        matching: find.byType(NoteRow),
      ),
    ))
      row.metadata.title,
  };

  /// Whether [names] read A to Z, as the DAO's `nameAsc` sorts them.
  bool ascending(List<String> names) {
    for (var i = 1; i < names.length; i++) {
      if (names[i - 1].toLowerCase().compareTo(names[i].toLowerCase()) > 0) {
        return false;
      }
    }
    return true;
  }

  /// A `.md` file imported into [folderId] through the app-wide
  /// [ImportExportBloc], as a folder's Import does: every mounted browser
  /// page hears its success, the covered ones included.
  Future<void> importInto(
    WidgetTester tester,
    String folderId,
    String name,
  ) async {
    final path = await real(tester, () async {
      final file = File('${tempDir.path}/$name.md');
      await file.writeAsString('# $name\nbody');
      return file.path;
    });
    exportBloc.add(
      ImportFileRequested(filePath: path, targetFolderId: folderId),
    );
    await settle(tester, rounds: 30);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester, rounds: 10);
  }

  /// [label] as the bottom bar of the page [at] draws it, found whether that
  /// page is in front or under another.
  Finder countOn(Finder at, String label) => find.descendant(
    of: at,
    matching: find.text(label, skipOffstage: false),
    skipOffstage: false,
  );

  final en = lookupAppLocalizations(const Locale('en'));

  group('every folder of a parent is reachable (review item 7)', () {
    testWidgets('25 subfolders of one parent', (tester) async {
      final parent = await real(
        tester,
        () => db.folderDao.createFolder(name: 'Many'),
      );
      await real(tester, () async {
        for (var i = 0; i < 25; i++) {
          await db.folderDao.createFolder(
            name: 'Sub ${i.toString().padLeft(2, '0')}',
            parentId: parent.id,
          );
        }
      });
      await pumpPage(tester, folderId: parent.id);

      final reached = await folderRowsReachable(tester);

      expect(reached, {
        for (var i = 0; i < 25; i++) 'Sub ${i.toString().padLeft(2, '0')}',
      });
      await teardownPage(tester);
    });

    testWidgets('25 folders at the root', (tester) async {
      await real(tester, () async {
        for (var i = 0; i < 25; i++) {
          await db.folderDao.createFolder(
            name: 'Top ${i.toString().padLeft(2, '0')}',
          );
        }
      });
      await pumpPage(tester);

      final reached = await folderRowsReachable(tester);

      for (var i = 0; i < 25; i++) {
        expect(reached, contains('Top ${i.toString().padLeft(2, '0')}'));
      }
      await teardownPage(tester);
    });
  });

  group('the root page after a child page loaded (review item 8)', () {
    late Folder opened;

    setUpAll(() async {
      opened = await db.folderDao.createFolder(name: 'Aa opened');
      await db.folderDao.createFolder(name: 'Aa sibling');
    });

    Future<void> rootThenChildThenBack(WidgetTester tester) async {
      await pumpPage(tester);
      await push(tester, opened);
      await back(tester);
    }

    testWidgets('a folder created at the root appears there', (tester) async {
      await rootThenChildThenBack(tester);

      // What the root page's create dialog dispatches.
      folderBloc.add(
        const CreateOptimizedFolder(name: 'Aa created', parentId: null),
      );
      await settle(tester);

      expect(folderRowsInView(tester), contains('Aa created'));
      await teardownPage(tester);
    });

    testWidgets('pull-to-refresh re-reads the root', (tester) async {
      await rootThenChildThenBack(tester);
      // Written with no announcement, as another isolate's write is.
      await real(tester, () => db.folderDao.createFolder(name: 'Aa unheard'));

      tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show()
          .ignore();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);

      expect(folderRowsInView(tester), contains('Aa unheard'));
      await teardownPage(tester);
    });

    testWidgets('a bulk label at the root shows on its rows', (tester) async {
      await rootThenChildThenBack(tester);
      final sibling = await real(
        tester,
        () => db.folderDao.getFoldersByParent(null),
      );
      final ids = [
        for (final f in sibling)
          if (f.name == 'Aa opened' || f.name == 'Aa sibling') f.id,
      ];

      // What the selection bar's label action dispatches.
      folderBloc.add(
        SetOptimizedFoldersLabel(folderIds: ids, label: ItemLabel.red),
      );
      await settle(tester);

      expect(labelOfRow(tester, 'Aa opened'), ItemLabel.red);
      expect(labelOfRow(tester, 'Aa sibling'), ItemLabel.red);
      await teardownPage(tester);
    });

    testWidgets('a folder a sync pull merges in at the root appears there', (
      tester,
    ) async {
      await rootThenChildThenBack(tester);

      await mergedIn(tester, 'Aa merged');
      await settle(tester);

      expect(folderRowsInView(tester), contains('Aa merged'));
      await teardownPage(tester);
    });
  });

  testWidgets('a nested folder renamed from its own page still hears of a '
      'subfolder merged into it (review item 8)', (tester) async {
    final parent = await real(
      tester,
      () => db.folderDao.createFolder(name: 'Nest parent'),
    );
    final nested = await real(
      tester,
      () => db.folderDao.createFolder(name: 'Nest', parentId: parent.id),
    );
    await pumpPage(tester, folderId: parent.id);
    await push(tester, nested);

    // What the open folder's rename dispatches.
    folderBloc.add(UpdateOptimizedFolder(folderId: nested.id, name: 'Nest 2'));
    await settle(tester);
    await mergedIn(tester, 'Nest child', parentId: nested.id);
    await settle(tester);

    expect(folderRowsInView(tester), contains('Nest child'));
    await teardownPage(tester);
  });

  group('a failed folder act (review item 4)', () {
    testWidgets('a failed create in an empty folder leaves no spinner', (
      tester,
    ) async {
      final empty = await real(
        tester,
        () => db.folderDao.createFolder(name: 'Empty for create'),
      );
      await pumpPage(tester, folderId: empty.id);
      folderService.failCreates = true;

      folderBloc.add(CreateOptimizedFolder(name: 'Never', parentId: empty.id));
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await teardownPage(tester);
    });

    testWidgets('a failed refresh in an empty folder shows the error, not a '
        'spinner', (tester) async {
      final empty = await real(
        tester,
        () => db.folderDao.createFolder(name: 'Empty for refresh'),
      );
      await pumpPage(tester, folderId: empty.id);
      folderService.failLoads = true;

      folderBloc.add(RefreshFolders(parentId: empty.id));
      await settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Failed to refresh folders'), findsOneWidget);
      await teardownPage(tester);
    });
  });

  /// One bloc under every page: the page in front owns it, a page under
  /// another never moves it, and the page in front gets its own parent back
  /// in its own order, without a flash. Root-level folders a case creates
  /// are named to sort first, so they are among the rows the root draws.
  group('the page in front owns the one bloc (second review)', () {
    Future<Folder> folderAt(
      WidgetTester tester,
      String name, {
      String? parentId,
    }) => real(
      tester,
      () => db.folderDao.createFolder(name: name, parentId: parentId),
    );

    NavigatorState navigatorOf(WidgetTester tester) => Navigator.of(
      tester.element(find.byType(OptimizedFolderContentPage).last),
    );

    testWidgets('a subfolder an import was made in still shows its own '
        'creates (finding 1, PROBE-A1)', (tester) async {
      final opened = await folderAt(tester, 'Imp open');
      await folderAt(tester, 'Imp kid', parentId: opened.id);
      await pumpPage(tester);
      await push(tester, opened);
      expect(folderRowsInView(tester), {'Imp kid'});

      await importInto(tester, opened.id, 'imp_note');
      // What the open folder's create dialog dispatches.
      folderBloc.add(
        CreateOptimizedFolder(name: 'Imp created', parentId: opened.id),
      );
      await settle(tester, rounds: 20);

      expect(folderRowsInView(tester), contains('Imp created'));
      await teardownPage(tester);
    });

    testWidgets('the root an import was made above hears its own changes '
        'after the pop (finding 4)', (tester) async {
      final opened = await folderAt(tester, 'Imp2 open');
      await pumpPage(tester);
      await push(tester, opened);
      await importInto(tester, opened.id, 'imp2_note');
      await back(tester);

      // What the root's create dialog dispatches.
      folderBloc.add(
        const CreateOptimizedFolder(name: '0 Imp2 created', parentId: null),
      );
      await settle(tester, rounds: 20);

      expect(folderRowsInView(tester), contains('0 Imp2 created'));
      await teardownPage(tester);
    });

    testWidgets('the root comes back in its own order after a child of '
        'another order moved the bloc (finding 2, PROBE-A2)', (tester) async {
      final child = await folderAt(tester, 'Ord child');
      await real(tester, () async {
        await folderService.updateFolderSortPreferences(
          folderId: child.id,
          subfolderSortOrder: 'nameDesc',
        );
        await db.folderDao.createFolder(name: 'k1', parentId: child.id);
        await db.folderDao.createFolder(name: 'k2', parentId: child.id);
      });
      await pumpPage(tester);
      expect(ascending(orderInView(tester)), isTrue);
      await push(tester, child);
      expect(orderInView(tester), ['k2', 'k1']);

      // What a covered root's import listener sent before the gate: its own
      // parent, with no order — so the root was read in the child's.
      folderBloc.add(const RefreshFolders(parentId: null));
      await settle(tester, rounds: 20);
      await back(tester);

      final order = orderInView(tester);
      expect(order, isNotEmpty);
      expect(
        ascending(order),
        isTrue,
        reason:
            'the root kept the nameDesc of the child it was read in: '
            '$order',
      );
      await teardownPage(tester);
    });

    testWidgets('an import from a child of another order leaves the child '
        'hearing in its order and the root in its own', (tester) async {
      final child = await folderAt(tester, 'Ord2 child');
      await real(tester, () async {
        await folderService.updateFolderSortPreferences(
          folderId: child.id,
          subfolderSortOrder: 'nameDesc',
        );
        await db.folderDao.createFolder(name: 'k1', parentId: child.id);
        await db.folderDao.createFolder(name: 'k2', parentId: child.id);
      });
      await pumpPage(tester);
      await push(tester, child);

      await importInto(tester, child.id, 'ord2_note');
      folderBloc.add(CreateOptimizedFolder(name: 'k0', parentId: child.id));
      await settle(tester, rounds: 20);
      expect(orderInView(tester), ['k2', 'k1', 'k0']);

      await back(tester);
      expect(ascending(orderInView(tester)), isTrue);
      await teardownPage(tester);
    });

    testWidgets('the count label never empties across a pop from a '
        'subfolder (finding 3)', (tester) async {
      final parent = await folderAt(tester, 'Count parent');
      final kid = await folderAt(tester, 'Count a', parentId: parent.id);
      await folderAt(tester, 'Count b', parentId: parent.id);
      await folderAt(tester, 'Count c', parentId: parent.id);
      await folderAt(tester, 'Count a1', parentId: kid.id);
      await pumpPage(tester, folderId: parent.id);
      final parentPage = find
          .byType(OptimizedFolderContentPage, skipOffstage: false)
          .first;
      // Three: no row of the parent's counts three of its own.
      final label = en.folderCountLabel(3);
      expect(countOn(parentPage, label), findsOneWidget);
      await push(tester, kid);
      expect(find.text(en.folderCountLabel(1)), findsOneWidget);
      // A folder made in the child: its refresh drops the service's cache,
      // so the parent's reload on the way back is a real read, not a cache
      // hit answered inside one frame.
      folderBloc.add(CreateOptimizedFolder(name: 'Count a2', parentId: kid.id));
      await settle(tester);

      navigatorOf(tester).pop();
      for (var frame = 0; frame < 30; frame++) {
        // The blocs were built outside the test's fake zone, so what they
        // emit reaches the page only through real microtasks: flushing those
        // alone before each frame delivers a Loading while the read it
        // waits on is still out, as a frame in the app would see it.
        await tester.runAsync(() async {});
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          countOn(parentPage, label),
          findsOneWidget,
          reason: 'frame $frame of the pop',
        );
        // Lets the reload's real read land somewhere inside the frames.
        if (frame % 3 == 2) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }
      await settle(tester);
      expect(countOn(parentPage, label), findsOneWidget);
      await teardownPage(tester);
    });

    testWidgets('a page whose folder changed while it was covered shows the '
        'change, and counts it, when uncovered', (tester) async {
      final parent = await folderAt(tester, 'Cover parent');
      final child = await folderAt(tester, 'Cover child', parentId: parent.id);
      await pumpPage(tester, folderId: parent.id);
      await push(tester, child);

      // Written while the child is in front: a folder no one announces, as
      // another isolate writes one, and a note merged in, which the note
      // bloc — open on the child — does not answer for the parent.
      await folderAt(tester, 'Cover fresh', parentId: parent.id);
      await real(
        tester,
        () => noteService.createNote(
          folderId: parent.id,
          title: 'Cover note',
          content: 'body',
        ),
      );
      // An import from the child, which the covered parent hears and skips.
      await importInto(tester, child.id, 'cover_import');
      await back(tester);

      expect(folderRowsInView(tester), {'Cover child', 'Cover fresh'});
      expect(noteRowsInView(tester), {'Cover note'});
      expect(
        find.text(
          en.folderAndNoteCount(en.folderCountLabel(2), en.noteCountLabel(1)),
        ),
        findsOneWidget,
      );
      await teardownPage(tester);
    });

    testWidgets('a covered page keeps its own note order through an import '
        'from the page over it', (tester) async {
      final parent = await folderAt(tester, 'Order parent');
      final child = await folderAt(tester, 'Order child', parentId: parent.id);
      await real(tester, () async {
        for (final title in ['Nb', 'Na', 'Nc']) {
          await noteService.createNote(
            folderId: parent.id,
            title: title,
            content: 'body',
          );
        }
        await folderService.updateFolderSortPreferences(
          folderId: parent.id,
          noteSortOrder: NotesSortOrder.titleAsc.name,
        );
      });
      List<String> noteOrder() => [
        for (final row in tester.widgetList<NoteRow>(
          find.descendant(
            of: find.byType(OptimizedFolderContentPage).last,
            matching: find.byType(NoteRow),
          ),
        ))
          row.metadata.title,
      ];
      await pumpPage(tester, folderId: parent.id);
      expect(noteOrder(), ['Na', 'Nb', 'Nc']);
      await push(tester, child);

      // The child reads its notes newest first; a refresh the covered
      // parent sent would read the parent's in that order too.
      await importInto(tester, child.id, 'order_import');
      await back(tester);

      expect(noteOrder(), ['Na', 'Nb', 'Nc']);
      await teardownPage(tester);
    });

    testWidgets('pull-to-refresh on a subfolder in front of the root still '
        'reloads it', (tester) async {
      final opened = await folderAt(tester, 'Pull open');
      await pumpPage(tester);
      await push(tester, opened);
      // Written with no announcement, as another isolate's write is.
      await folderAt(tester, 'Pull unheard', parentId: opened.id);

      tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator).last)
          .show()
          .ignore();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);

      expect(folderRowsInView(tester), contains('Pull unheard'));
      await teardownPage(tester);
    });

    testWidgets('a dialog over the page in front does not cover it', (
      tester,
    ) async {
      final opened = await folderAt(tester, 'Dialog open');
      await pumpPage(tester);
      await push(tester, opened);
      await folderAt(tester, 'Dialog unheard', parentId: opened.id);
      showDialog<void>(
        context: tester.element(find.byType(OptimizedFolderContentPage).last),
        builder: (_) => const AlertDialog(content: Text('Over the page')),
      ).ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The import's refresh runs with the dialog still up.
      await importInto(tester, opened.id, 'dialog_import');

      expect(find.text('Over the page'), findsOneWidget);
      expect(folderRowsInView(tester), contains('Dialog unheard'));
      await teardownPage(tester);
    });

    testWidgets('a stack pushed in one go, as launch restore builds it, '
        'gives each page its own rows on the way back', (tester) async {
      final outer = await folderAt(tester, 'Stack outer');
      final inner = await folderAt(tester, 'Stack inner', parentId: outer.id);
      await folderAt(tester, 'Stack sib', parentId: outer.id);
      await folderAt(tester, 'Stack leaf', parentId: inner.id);
      await real(
        tester,
        () => noteService.createNote(
          folderId: outer.id,
          title: 'Stack note',
          content: 'body',
        ),
      );
      await pumpPage(tester);

      final navigator = navigatorOf(tester);
      for (final folder in [outer, inner]) {
        navigator
            .push(
              MaterialPageRoute<void>(
                builder: (_) => OptimizedFolderContentPage(
                  folderId: folder.id,
                  title: folder.name,
                ),
              ),
            )
            .ignore();
      }
      await transition(tester);
      expect(folderRowsInView(tester), {'Stack leaf'});
      expect((folderBloc.state as OptimizedFolderLoaded).parentId, inner.id);

      await back(tester);
      expect(folderRowsInView(tester), {'Stack inner', 'Stack sib'});
      expect(noteRowsInView(tester), {'Stack note'});
      expect(
        find.text(
          en.folderAndNoteCount(en.folderCountLabel(2), en.noteCountLabel(1)),
        ),
        findsOneWidget,
      );

      await back(tester);
      expect(ascending(orderInView(tester)), isTrue);
      await teardownPage(tester);
    });

    testWidgets('a note saved on a page over the folder shows when that page '
        'pops, as the editor\'s does', (tester) async {
      final opened = await folderAt(tester, 'Editor open');
      await pumpPage(tester);
      await push(tester, opened);
      final navigator = navigatorOf(tester);
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Editor stand-in')),
            ),
          )
          .ignore();
      await transition(tester);

      // What the editor's first save dispatches.
      noteBloc.add(
        CreateOptimizedNote(
          folderId: opened.id,
          title: 'Editor note',
          content: 'body',
        ),
      );
      await settle(tester, rounds: 20);
      navigator.pop();
      await transition(tester);

      expect(noteRowsInView(tester), contains('Editor note'));
      await teardownPage(tester);
    });

    testWidgets('a child popped during its push leaves the bloc with the page '
        'it uncovered (finding 5)', (tester) async {
      final opened = await folderAt(tester, 'Quick open');
      await folderAt(tester, 'Quick kid', parentId: opened.id);
      await pumpPage(tester);
      // Nothing cached, so the child's first reads are real ones, still out
      // when it is popped.
      folderService.invalidateCache();

      final navigator = navigatorOf(tester);
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => OptimizedFolderContentPage(
                folderId: opened.id,
                title: opened.name,
              ),
            ),
          )
          .ignore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      navigator.pop();
      // The child's first reads land while its pop is still animating.
      await tester.pump();
      await settle(tester, rounds: 6);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      folderBloc.add(
        const CreateOptimizedFolder(name: '0 Quick created', parentId: null),
      );
      await settle(tester, rounds: 20);

      expect(folderRowsInView(tester), contains('0 Quick created'));
      await teardownPage(tester);
    });
  });

  /// The third review: a covered page reads its own rows without taking a
  /// bloc, a pop that finds the blocs already aimed costs nothing, a pushed
  /// page never draws its parent's rows, and a page back in front gets its
  /// notes back as deep as it had them.
  group('covered, revealed and pushed pages (third review)', () {
    Future<Folder> folderAt(
      WidgetTester tester,
      String name, {
      String? parentId,
    }) => real(
      tester,
      () => db.folderDao.createFolder(name: name, parentId: parentId),
    );

    NavigatorState navigatorOf(WidgetTester tester) => Navigator.of(
      tester.element(find.byType(OptimizedFolderContentPage).last),
    );

    Finder pageOf(String? folderId) => find.byWidgetPredicate(
      (widget) =>
          widget is OptimizedFolderContentPage && widget.folderId == folderId,
      skipOffstage: false,
    );

    Set<String> rowsOn(WidgetTester tester, Finder page) => {
      for (final row in tester.widgetList<FolderRow>(
        find.descendant(
          of: page,
          matching: find.byType(FolderRow, skipOffstage: false),
          skipOffstage: false,
        ),
      ))
        row.folder.name,
    };

    Set<String> notesOn(WidgetTester tester, Finder page) => {
      for (final row in tester.widgetList<NoteRow>(
        find.descendant(
          of: page,
          matching: find.byType(NoteRow, skipOffstage: false),
          skipOffstage: false,
        ),
      ))
        row.metadata.title,
    };

    /// [folders] pushed one over the other in one go, as launch restore
    /// replays a stack.
    void pushInOneGo(NavigatorState navigator, List<Folder> folders) {
      for (final folder in folders) {
        navigator
            .push(
              MaterialPageRoute<void>(
                builder: (_) => OptimizedFolderContentPage(
                  folderId: folder.id,
                  title: folder.name,
                ),
              ),
            )
            .ignore();
      }
    }

    /// Whether [state] is the bloc aimed at [parentId]: a load or a read of
    /// that parent.
    bool aimedAt(OptimizedFolderState state, String parentId) =>
        (state is OptimizedFolderLoading && state.parentId == parentId) ||
        (state is OptimizedFolderLoaded && state.parentId == parentId);

    /// Frames of a pop, each preceded by the blocs' real microtasks alone so
    /// a state emitted before its read is drawn, as a frame in the app sees
    /// it; every third lets the reads land.
    Future<void> frames(
      WidgetTester tester,
      void Function(int frame) check,
    ) async {
      for (var frame = 0; frame < 30; frame++) {
        await tester.runAsync(() async {});
        await tester.pump(const Duration(milliseconds: 16));
        check(frame);
        if (frame % 3 == 2) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }
    }

    /// Gives the enclosing group blocs of its own that have loaded nothing,
    /// as at a cold launch, so a case about a bloc's starting state builds
    /// that state itself instead of inheriting what an earlier case left.
    void onFreshBlocs() {
      late OptimizedFolderBloc sharedFolders;
      late OptimizedNoteBloc sharedNotes;

      setUpAll(() {
        sharedFolders = folderBloc;
        sharedNotes = noteBloc;
        folderBloc = OptimizedFolderBloc(storageService: folderService);
        noteBloc = OptimizedNoteBloc(storageService: noteService);
      });

      // The note bloc is left open: closing it disposes the note service it
      // shares with every other case of the suite.
      tearDownAll(() async {
        await folderBloc.close();
        folderBloc = sharedFolders;
        noteBloc = sharedNotes;
      });
    }

    group('a cold launch\'s reveal, on blocs that have loaded nothing', () {
      onFreshBlocs();

      testWidgets('a page restored under another has its rows in every frame '
          'of its reveal, and the bloc never moved to it while covered '
          '(item 1)', (tester) async {
        final outer = await folderAt(tester, 'Reveal outer');
        final inner = await folderAt(
          tester,
          'Reveal inner',
          parentId: outer.id,
        );
        await folderAt(tester, 'Reveal sib', parentId: outer.id);
        await folderAt(tester, 'Reveal leaf', parentId: inner.id);
        await real(
          tester,
          () => noteService.createNote(
            folderId: outer.id,
            title: 'Reveal note',
            content: 'body',
          ),
        );
        await pumpPage(tester);
        final seen = <OptimizedFolderState>[];
        final sub = folderBloc.stream.listen(seen.add);
        addTearDown(sub.cancel);
        // As at a cold launch: the root loads no notes, so the outer page's
        // note builder starts from Initial, and the inner page's states
        // never pass its filter.
        expect(noteBloc.state, isA<OptimizedNoteInitial>());

        pushInOneGo(navigatorOf(tester), [outer, inner]);
        await transition(tester);
        expect(rowsOn(tester, pageOf(inner.id)), {'Reveal leaf'});
        expect(seen.where((state) => aimedAt(state, outer.id)), isEmpty);
        expect(
          folderBloc.isAimedAt(inner.id, FoldersSortOrder.nameAsc),
          isTrue,
        );

        navigatorOf(tester).pop();
        await frames(tester, (frame) {
          expect(rowsOn(tester, pageOf(outer.id)), {
            'Reveal inner',
            'Reveal sib',
          }, reason: 'frame $frame of the reveal');
          expect(notesOn(tester, pageOf(outer.id)), {
            'Reveal note',
          }, reason: 'frame $frame of the reveal');
        });
        await settle(tester);
        expect(
          folderBloc.isAimedAt(outer.id, FoldersSortOrder.nameAsc),
          isTrue,
        );
        await teardownPage(tester);
      });
    });

    group('a cold launch, on blocs that have loaded nothing', () {
      onFreshBlocs();

      testWidgets('only the page in front of a stack built at a cold launch '
          'takes the bloc (the cold-start gate)', (tester) async {
        final outer = await folderAt(tester, 'Cold outer');
        final inner = await folderAt(tester, 'Cold inner', parentId: outer.id);
        await folderAt(tester, 'Cold leaf', parentId: inner.id);
        final seen = <OptimizedFolderState>[];
        final sub = folderBloc.stream.listen(seen.add);
        addTearDown(sub.cancel);

        // Every page builds in the first frame, before the bloc has answered
        // anything, so each builder sees the bloc's initial state.
        expect(folderBloc.state, isA<OptimizedFolderInitial>());
        await pumpPage(tester, settled: false, stack: [outer, inner]);
        await transition(tester);

        expect(seen.where((state) => aimedAt(state, outer.id)), isEmpty);
        expect(rowsOn(tester, pageOf(inner.id)), {'Cold leaf'});
        await back(tester);
        expect(rowsOn(tester, pageOf(outer.id)), {'Cold inner'});
        await teardownPage(tester);
      });
    });

    testWidgets('a page that peeked, was revealed and changed never draws the '
        'peeked rows again', (tester) async {
      final outer = await folderAt(tester, 'Drop outer');
      final inner = await folderAt(tester, 'Drop inner', parentId: outer.id);
      await folderAt(tester, 'Drop sib', parentId: outer.id);
      await pumpPage(tester);
      pushInOneGo(navigatorOf(tester), [outer, inner]);
      await transition(tester);
      await back(tester);
      expect(rowsOn(tester, pageOf(outer.id)), {'Drop inner', 'Drop sib'});

      // A folder the read made while covered does not hold. (A rename would
      // not show the fault: the list keeps its drawn rows by id.)
      folderBloc.add(
        CreateOptimizedFolder(name: 'Drop new', parentId: outer.id),
      );
      await settle(tester);
      const current = {'Drop inner', 'Drop sib', 'Drop new'};
      expect(rowsOn(tester, pageOf(outer.id)), current);

      // Both blocs on another folder, then search opened and left, which
      // builds the list's builders again from the blocs' states.
      folderBloc.add(LoadFoldersPaginated(parentId: inner.id));
      noteBloc.add(LoadNotesPaginated(folderId: inner.id));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: pageOf(outer.id),
          matching: find.byIcon(Icons.search),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(
        rowsOn(tester, pageOf(outer.id)),
        isEmpty,
        reason: 'search replaces the list',
      );
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await frames(tester, (frame) {
        expect(
          rowsOn(tester, pageOf(outer.id)),
          current,
          reason: 'frame $frame after search',
        );
      });
      expect(pageOf(outer.id), findsOneWidget);
      // Opening search starts the body index's drain in this case's fake
      // zone; left halfway, it holds up every later write to a note.
      await settle(tester, rounds: 60);
      await teardownPage(tester);
    });

    testWidgets('paging on after a return reads every note once', (
      tester,
    ) async {
      final parent = await folderAt(tester, 'Page parent');
      final child = await folderAt(tester, 'Page child', parentId: parent.id);
      await real(tester, () async {
        for (var i = 0; i < 70; i++) {
          await noteService.createNote(
            folderId: parent.id,
            title: 'Page $i',
            content: 'body',
          );
        }
      });
      await pumpPage(tester, folderId: parent.id);
      noteBloc.add(LoadMoreNotes(folderId: parent.id));
      await settle(tester);
      expect(
        (noteBloc.state as OptimizedNoteLoaded).paginatedNotes.notes,
        hasLength(40),
      );
      await push(tester, child);
      await importInto(tester, child.id, 'page_import');
      await back(tester);

      // What scrolling to the end of the list sends, twice.
      for (var i = 0; i < 2; i++) {
        noteBloc.add(LoadMoreNotes(folderId: parent.id));
        await settle(tester);
      }

      final notes = (noteBloc.state as OptimizedNoteLoaded).paginatedNotes;
      expect(notes.notes, hasLength(70));
      expect({for (final note in notes.notes) note.id}, hasLength(70));
      expect(notes.hasMore, isFalse);
      await teardownPage(tester);
    });

    testWidgets('a pop from a page that changed nothing costs no folder '
        'read (item 2)', (tester) async {
      await pumpPage(tester);
      final navigator = navigatorOf(tester);
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Plain page')),
            ),
          )
          .ignore();
      await transition(tester);
      final before = folderService.loadCalls;

      navigator.pop();
      await transition(tester);

      expect(folderService.loadCalls - before, 0);
      await teardownPage(tester);
    });

    testWidgets('a pop after a reload the covered page turned away still '
        'reads it (item 2)', (tester) async {
      final target = await folderAt(tester, 'Plain target');
      await pumpPage(tester);
      final navigator = navigatorOf(tester);
      navigator
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Plain page')),
            ),
          )
          .ignore();
      await transition(tester);
      // Written with no announcement, then an import the covered root hears
      // and turns away.
      await folderAt(tester, '0 Plain unheard');
      await importInto(tester, target.id, 'plain_import');

      navigator.pop();
      await transition(tester);

      expect(folderRowsInView(tester), contains('0 Plain unheard'));
      await teardownPage(tester);
    });

    testWidgets('a pushed folder page never draws its parent\'s rows, and a '
        'tap on its first frame opens nothing of the parent\'s (item 3)', (
      tester,
    ) async {
      final parent = await folderAt(tester, 'Push parent');
      final kid = await folderAt(tester, 'Push a', parentId: parent.id);
      final sibling = await folderAt(tester, 'Push b', parentId: parent.id);
      await folderAt(tester, 'Push a1', parentId: kid.id);
      await pumpPage(tester, folderId: parent.id);

      navigatorOf(tester)
          .push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  OptimizedFolderContentPage(folderId: kid.id, title: kid.name),
            ),
          )
          .ignore();
      await tester.pump();
      expect(rowsOn(tester, pageOf(kid.id)).difference({'Push a1'}), isEmpty);
      final stray = find.descendant(
        of: pageOf(kid.id),
        matching: find.text('Push b'),
      );
      if (stray.evaluate().isNotEmpty) {
        await tester.tap(stray.first, warnIfMissed: false);
      }
      await frames(tester, (frame) {
        expect(
          rowsOn(tester, pageOf(kid.id)).difference({'Push a1'}),
          isEmpty,
          reason: 'frame $frame of the push',
        );
      });
      await settle(tester);

      expect(rowsOn(tester, pageOf(kid.id)), {'Push a1'});
      expect(pageOf(sibling.id), findsNothing);
      await teardownPage(tester);
    });

    testWidgets('a note added to a folder while its subfolder covers it '
        'shows when it is back (item 4)', (tester) async {
      final parent = await folderAt(tester, 'Back parent');
      final child = await folderAt(tester, 'Back child', parentId: parent.id);
      await pumpPage(tester, folderId: parent.id);
      await push(tester, child);

      // Announced, but the note bloc is open on the child.
      await real(
        tester,
        () => noteService.createNote(
          folderId: parent.id,
          title: 'Back note',
          content: 'body',
        ),
      );
      await settle(tester);
      await back(tester);

      expect(noteRowsInView(tester), {'Back note'});
      await teardownPage(tester);
    });

    testWidgets('notes come back as deep as they were read, and the count '
        'keeps its notes half through the return (item 4)', (tester) async {
      final parent = await folderAt(tester, 'Deep parent');
      final child = await folderAt(tester, 'Deep child', parentId: parent.id);
      await real(tester, () async {
        for (var i = 0; i < 45; i++) {
          await noteService.createNote(
            folderId: parent.id,
            title: 'Deep $i',
            content: 'body',
          );
        }
      });
      await pumpPage(tester, folderId: parent.id);
      noteBloc.add(LoadMoreNotes(folderId: parent.id));
      await settle(tester);
      final label = en.folderAndNoteCount(
        en.folderCountLabel(1),
        en.noteCountLabel(45),
      );
      expect(find.text(label), findsOneWidget);
      await push(tester, child);
      // An import from the child, which the covered parent turns away.
      await importInto(tester, child.id, 'deep_import');

      navigatorOf(tester).pop();
      await frames(tester, (frame) {
        expect(
          countOn(pageOf(parent.id), label),
          findsOneWidget,
          reason: 'frame $frame of the return',
        );
      });
      await settle(tester);

      final notes = noteBloc.state as OptimizedNoteLoaded;
      expect(notes.folderId, parent.id);
      expect(notes.paginatedNotes.notes, hasLength(40));
      await teardownPage(tester);
    });
  });
}

/// The real folder service, whose creates or loads can be made to fail.
class _FlakyFolderStorageService extends FolderStorageService {
  _FlakyFolderStorageService({
    required super.repository,
    required super.noteRepository,
  });

  bool failCreates = false;
  bool failLoads = false;

  /// Every paginated folder read so far, for what a pop costs.
  int loadCalls = 0;

  @override
  Future<model.Folder> createFolder({
    required String name,
    String? parentId,
    ItemLabel label = ItemLabel.none,
  }) {
    if (failCreates) return Future.error(StateError('create failed'));
    return super.createFolder(name: name, parentId: parentId, label: label);
  }

  @override
  Future<PaginatedFolders> loadFoldersPaginated({
    String? parentId,
    int page = 1,
    int pageSize = FolderStorageService.defaultPageSize,
    FoldersSortOrder sortOrder = FoldersSortOrder.nameAsc,
  }) {
    loadCalls++;
    if (failLoads) return Future.error(StateError('load failed'));
    return super.loadFoldersPaginated(
      parentId: parentId,
      page: page,
      pageSize: pageSize,
      sortOrder: sortOrder,
    );
  }
}
