import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_bloc.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/controllers/partner_look_reader.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/models/share_settings.dart';
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
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/widgets/folder_overflow_menu.dart';
import 'package:anta/widgets/share_folders_sheets.dart';
import 'package:anta/widgets/folder_row.dart';
import 'package:anta/utils/share_leave_voice.dart';
import 'package:anta/widgets/folder_sliver_app_bar.dart';
import 'package:anta/widgets/note_row.dart';
import 'package:anta/widgets/user_avatar.dart';

import '../goldens/support/golden_fonts.dart';
import '../services/support/body_index_support.dart';
import '../support/fake_share_service.dart';

/// The partner's folders and notes in the browser and in All notes
/// (`docs/cloud-share-surfaces-roadmap.md` §6.12, §16.8): the root's "From
/// {name}" group after the person's own, out of every selection and
/// reorder; the look read once per page; a folder that stops being shared
/// while open closes back to where it was opened from, with one bar.
///
/// The harness is the browser suite's: one real database behind every
/// singleton, drift answering in real time, [settle] alternating the clocks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const partner = 'maria';
  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [AppUser(uid: partner, displayName: 'Maria')],
  );

  late Directory tempDir;
  late AppDatabase db;
  late FolderRepository folderRepository;
  late FolderStorageService folderService;
  late NoteStorageService noteService;
  late OptimizedFolderBloc folderBloc;
  late OptimizedNoteBloc noteBloc;
  late ImportExportBloc exportBloc;
  late FakeShareService share;
  var opened = 0;

  late Folder kitchen;
  late Folder plain;
  late Folder pantry;
  late Folder recipes;
  late Folder soups;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_partner_rows');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    final settings = await SettingsService.getInstance();
    await settings.setShowNotePreview(true);

    folderRepository = FolderRepository(database: db);
    folderService = FolderStorageService(repository: folderRepository);
    await folderService.initialize();
    noteService = NoteStorageService(repository: NoteRepository(database: db));
    await noteService.initialize();
    final searchService = FolderSearchService(
      storageService: noteService,
      indexer: bodyIndexerOver(db),
    );
    await searchService.initialize();

    GetIt.I.registerSingleton<NoteRepository>(NoteRepository(database: db));
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
        noteRepository: GetIt.I<NoteRepository>(),
      ),
    );
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());

    folderBloc = OptimizedFolderBloc(storageService: folderService);
    noteBloc = OptimizedNoteBloc(storageService: noteService);
    exportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: noteService,
        folderStorage: folderService,
        noteRepository: GetIt.I<NoteRepository>(),
      ),
    );

    kitchen = await db.folderDao.createFolder(name: 'Kitchen');
    plain = await db.folderDao.createFolder(name: 'Plain');
    pantry = await db.folderDao.createFolder(
      name: 'Pantry',
      parentId: kitchen.id,
    );
    recipes = await db.folderDao.createFolder(name: 'Recipes');
    soups = await db.folderDao.createFolder(
      name: 'Soups',
      parentId: recipes.id,
    );
    await noteService.createNote(
      folderId: kitchen.id,
      title: 'Shopping',
      content: 'leeks',
    );
    final leek = await noteService.createNote(
      folderId: recipes.id,
      title: 'Leek soup',
      content: 'leeks, potatoes',
    );
    await db.folderDao.setSharedPair(kitchen.id, 'pair-1');
    // Handed to the partner as the shared reader stores them: the owner on
    // the rows, then the key that names whose shared rows these are.
    await db.customStatement(
      'UPDATE folders SET owner_id = ? WHERE id IN (?, ?)',
      [partner, recipes.id, soups.id],
    );
    await db.customStatement('UPDATE notes SET owner_id = ? WHERE id = ?', [
      partner,
      leek.id,
    ]);
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
    folderRepository.shareCensus.forget();
    folderService.invalidateCache();
    noteService.invalidateCache();
    await searchService.buildIndex();
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

  setUp(() {
    share = FakeShareService(availability: const ShareReady(audience));
    opened = 0;
    ShareService.publishLookForTesting(null);
    // The fake clock runs ahead of a probe's real database read: a leave's
    // bound measured on it would count every page in front as staying.
    ShareLeaveVoice.probeLimit = const Duration(hours: 1);
    addTearDown(
      () => ShareLeaveVoice.probeLimit = AppConstants.shareLeaveProbeLimit,
    );
    PartnerLookReader.openService = () async {
      opened++;
      return share;
    };
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

  /// A route's transition, then the page's real reads: an empty folder's
  /// page spins until the database answers, so `pumpAndSettle` never ends.
  Future<void> transition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> teardownPage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpRoot(WidgetTester tester) => pumpApp(
    tester,
    const OptimizedFolderContentPage(folderId: null, title: 'ANTA'),
  );

  Future<void> openFolder(WidgetTester tester, Folder folder) async {
    AppNavigator.toFolder(
      tester.element(find.byType(OptimizedFolderContentPage).last),
      folderId: folder.id,
      title: folder.name,
    ).ignore();
    await transition(tester);
  }

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  group('the root', () {
    testWidgets('draws the partner\'s folders under "From Maria", after the '
        'Folders group they leave', (tester) async {
      await pumpRoot(tester);

      final header = find.bySemanticsIdentifier(
        SemanticsIds.browserSectionPartner,
      );
      expect(header, findsOneWidget);
      expect(tester.getSemantics(header).label, 'From Maria');
      expect(find.text('FROM MARIA'), findsOneWidget);
      expect(top(tester, find.text('Plain')), lessThan(top(tester, header)));
      expect(
        top(tester, find.text('Recipes')),
        greaterThan(top(tester, header)),
      );
      expect(find.text('Soups'), findsNothing, reason: 'top level only');

      final theirs = tester.widget<FolderRow>(
        find.widgetWithText(FolderRow, 'Recipes'),
      );
      expect(theirs.isReorderMode, isFalse);
      expect(theirs.selection, isNull);
      expect(theirs.onAcceptDrop, isNull);
      expect(
        find.descendant(
          of: find.widgetWithText(FolderRow, 'Recipes'),
          matching: find.byType(UserAvatar),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(FolderRow, 'Kitchen'),
          matching: find.byIcon(Icons.group_rounded),
        ),
        findsOneWidget,
        reason: 'my shared folder wears the sign',
      );
      expect(opened, 1, reason: 'one read for the page, not one per row');

      await teardownPage(tester);
    });

    testWidgets('repaints with no restart: the look and the mark on the way '
        'back from another page, the pair as it changes', (tester) async {
      await pumpRoot(tester);
      Finder inRow(String name, Finder matching) => find.descendant(
        of: find.widgetWithText(FolderRow, name),
        matching: matching,
      );
      expect(inRow('Recipes', find.byType(UserAvatar)), findsOneWidget);

      share
        ..notes = ShareNoteLook.plain
        ..mine = false;
      Navigator.of(tester.element(find.byType(OptimizedFolderContentPage)))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Sharing')),
            ),
          )
          .ignore();
      await transition(tester);
      Navigator.of(tester.element(find.text('Sharing'))).pop();
      await transition(tester);

      expect(inRow('Recipes', find.byType(UserAvatar)), findsNothing);
      expect(inRow('Kitchen', find.byIcon(Icons.group_rounded)), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^From Maria\nRecipes')),
        findsOneWidget,
        reason: 'the words stay in every look',
      );

      share.emit(
        const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Mara',
            members: [AppUser(uid: partner, displayName: 'Mara')],
          ),
        ),
      );
      await transition(tester);
      expect(find.text('FROM MARA'), findsOneWidget);
      expect(opened, 1);

      await teardownPage(tester);
    });

    testWidgets('in selection mode the group is drawn dimmed and out of '
        'reach: no handle, no tap, never selected', (tester) async {
      await pumpRoot(tester);
      await tester.tap(find.byType(FolderOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.select));
      await tester.pumpAndSettle();
      await settle(tester);

      final dimmed = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Recipes'), matching: find.byType(Opacity))
            .first,
      );
      expect(dimmed.opacity, FormMetrics.disabledOpacity);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      expect(find.text('FROM MARIA'), findsOneWidget);

      await tester.tap(find.text('Recipes'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byType(OptimizedFolderContentPage), findsOneWidget);

      await tester.tap(find.text('Plain'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('a reorder neither lifts the partner\'s folder nor lands one '
        'of mine among them', (tester) async {
      await pumpRoot(tester);
      await tester.tap(find.byType(FolderOverflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.select));
      await tester.pumpAndSettle();
      await settle(tester);
      final positions = {
        for (final row
            in await tester.runAsync(
                  () => db.folderDao.getByIdsIncludingDeleted([recipes.id]),
                ) ??
                const <Folder>[])
          row.id: row.position,
      };
      final list = tester.widget<SliverReorderableList>(
        find.byType(SliverReorderableList),
      );

      // Rows: [Folders][Kitchen][Plain][From Maria][Recipes].
      list.onReorderItem!(4, 0);
      await tester.pump();
      list.onReorderItem!(1, 5);
      await settle(tester, rounds: 60);

      expect(
        top(tester, find.text('Kitchen')),
        greaterThan(top(tester, find.text('Plain'))),
      );
      expect(
        top(tester, find.text('Kitchen')),
        lessThan(
          top(
            tester,
            find.bySemanticsIdentifier(SemanticsIds.browserSectionPartner),
          ),
        ),
      );
      final after = await tester.runAsync(
        () => db.folderDao.getByIdsIncludingDeleted([recipes.id]),
      );
      expect(after!.single.position, positions[recipes.id]);

      await teardownPage(tester);
    });
  });

  group('a partner\'s folder that stops being shared while open', () {
    Finder bar() => find.text('Maria no longer shares this folder.');
    Finder pages() =>
        find.byType(OptimizedFolderContentPage, skipOffstage: false);

    /// How many bars were raised over [frames] frames: each raise is a new
    /// SnackBar, kept by identity while it stands.
    Future<int> barsRaised(WidgetTester tester, {int frames = 30}) async {
      final raised = <Widget>{};
      for (var i = 0; i < frames; i++) {
        raised.addAll(tester.widgetList(find.byType(SnackBar)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      return raised.length;
    }

    testWidgets('closes every page of it, and what they opened above them, '
        'back to the root — with one bar', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);
      await openFolder(tester, soups);
      expect(pages(), findsNWidgets(3));
      await tester.tap(find.byType(FolderOverflowMenu).last);
      await transition(tester);
      expect(find.text(l10n.sortBy), findsOneWidget, reason: 'menu open');

      // The sub-folder in front heard first, in the same moment as the outer.
      folderRepository.announceRemoved({
        soups.id: recipes.id,
        recipes.id: null,
      });
      expect(await barsRaised(tester), 1);
      await transition(tester);

      expect(pages(), findsOneWidget);
      expect(find.text(l10n.sortBy), findsNothing);
      expect(bar(), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('never closes a page under it', (tester) async {
      await pumpRoot(tester);
      Navigator.of(tester.element(find.byType(OptimizedFolderContentPage)))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Sharing')),
            ),
          )
          .ignore();
      await transition(tester);
      AppNavigator.toFolder(
        tester.element(find.text('Sharing')),
        folderId: recipes.id,
        title: recipes.name,
      ).ignore();
      await transition(tester);
      await openFolder(tester, soups);
      expect(pages(), findsNWidgets(3));

      // The outer one first: the page above it is still open then.
      folderRepository.announceRemoved({
        recipes.id: null,
        soups.id: recipes.id,
      });
      await transition(tester);

      expect(find.text('Sharing'), findsOneWidget);
      expect(
        pages(),
        findsOneWidget,
        reason: 'the root, under the Sharing page',
      );
      expect(bar(), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('her sub-folder in front, both leaves at once, the outer one '
        'heard while the sub-folder is still closing: one bar', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);
      await openFolder(tester, soups);

      folderRepository.announceRemoved({soups.id: recipes.id});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(pages(), findsNWidgets(3), reason: 'the sub-folder is closing');
      folderRepository.announceRemoved({recipes.id: null});
      expect(await barsRaised(tester), 1);
      await transition(tester);
      expect(pages(), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('her sub-folder in front, two frames, the outer one first: '
        'one bar, when the sub-folder\'s own leave lands', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);
      await openFolder(tester, soups);

      folderRepository.announceRemoved({recipes.id: null});
      expect(await barsRaised(tester, frames: 6), 0);
      folderRepository.announceRemoved({soups.id: recipes.id});
      expect(await barsRaised(tester), 1);
      await transition(tester);
      expect(pages(), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('her sub-folder in front, two frames, it first: its bar, '
        'then the outer folder\'s — two closings, two bars', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);
      await openFolder(tester, soups);

      folderRepository.announceRemoved({soups.id: recipes.id});
      expect(await barsRaised(tester, frames: 10), 1);
      folderRepository.announceRemoved({recipes.id: null});
      expect(await barsRaised(tester), 1, reason: 'the outer one\'s, now');
      await transition(tester);
      expect(pages(), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('a folder of mine removed by a sync stays as it was', (
      tester,
    ) async {
      await pumpRoot(tester);
      await openFolder(tester, plain);

      folderRepository.announceRemoved({plain.id: null});
      await transition(tester);

      expect(pages(), findsNWidgets(2));
      expect(bar(), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('takes its own sheet with it when a page that sheet led to '
        'stays above', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);
      await tester.longPress(find.text('Soups'));
      await transition(tester);
      expect(find.text(l10n.rename), findsOneWidget, reason: 'sheet open');
      Navigator.of(tester.element(find.text(l10n.rename)))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Above')),
            ),
          )
          .ignore();
      await transition(tester);

      folderRepository.announceRemoved({recipes.id: null});
      await transition(tester);
      Navigator.of(tester.element(find.text('Above'))).pop();
      await transition(tester);

      expect(pages(), findsOneWidget, reason: 'the root');
      expect(find.text(l10n.rename), findsNothing, reason: 'no sheet left');

      await teardownPage(tester);
    });
  });

  group('inside the partner\'s folder', () {
    /// The frames, over the next forty, in which the page of [folderId]
    /// drew its create bar enabled — what a page that does not yet know
    /// whose the folder is draws.
    Future<int> writableFrames(WidgetTester tester, String folderId) async {
      final page = find.byWidgetPredicate(
        (w) => w is OptimizedFolderContentPage && w.folderId == folderId,
      );
      var writable = 0;
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (frame.isEven) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        final buttons = find.descendant(
          of: page,
          matching: find.ancestor(
            of: find.byTooltip(l10n.newFolder),
            matching: find.byType(IconButton),
          ),
        );
        for (final element in buttons.evaluate()) {
          if ((element.widget as IconButton).onPressed != null) writable++;
        }
      }
      return writable;
    }

    PopupMenuItem<Object?> item(WidgetTester tester, String label) =>
        tester.widget<PopupMenuItem<Object?>>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
              )
              .first,
        );

    testWidgets('a line says whose it is; the bar\'s buttons and every '
        'write in the ⋮ are disabled, not hidden; no share entry', (
      tester,
    ) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);

      final line = find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine);
      expect(line, findsOneWidget);
      expect(tester.getSemantics(line).label, 'From Maria · Read only');
      for (final tooltip in [l10n.newFolder, l10n.newNote]) {
        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull, reason: tooltip);
      }

      await tester.tap(find.byType(FolderOverflowMenu).last);
      await transition(tester);
      for (final enabled in [l10n.sortBy, l10n.moveHistory, l10n.settings]) {
        expect(item(tester, enabled).enabled, isTrue, reason: enabled);
      }
      for (final off in [
        l10n.select,
        l10n.renameFolder,
        l10n.moveToFolder,
        l10n.shareFolder,
        l10n.importNoteOrFolder,
        l10n.deleteFolder,
      ]) {
        expect(item(tester, off).enabled, isFalse, reason: off);
        // Review 10: the words dim with the glyph, not the glyph alone.
        final onSurface = Theme.of(
          tester.element(find.text(off)),
        ).colorScheme.onSurface;
        expect(
          tester.widget<Text>(find.text(off)).style?.color,
          onSurface.withValues(alpha: FormMetrics.disabledOpacity),
          reason: off,
        );
      }
      expect(
        find.bySemanticsIdentifier(SemanticsIds.folderMenuShare),
        findsNothing,
      );

      await teardownPage(tester);
    });

    // Review 9 (B7): a door that read the folder before the push — the
    // editor's way back to its folder, the ancestor menu, launch restore —
    // hands whose it is to the page, for the caches the page would ask may
    // have been let go since (here the share census). No frame of her
    // folder's page may be writable.
    testWidgets('her folder reached past a let-go census: no frame is '
        'writable', (tester) async {
      await pumpRoot(tester);
      folderRepository.shareCensus.forget();
      expect(folderService.knownFromPartner(recipes.id), isNull);

      AppNavigator.popToFolder(
        tester.element(find.byType(OptimizedFolderContentPage).last),
        folderId: recipes.id,
        title: 'Recipes',
        fromPartner: true,
      ).ignore();

      expect(
        await writableFrames(tester, recipes.id),
        0,
        reason: 'frames with her create bar enabled',
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
        findsOneWidget,
      );
      await teardownPage(tester);
    });

    // Leg 6's door left unpinned: a caller with no title (the editor's
    // "Open folder" before the name loads) gets the folder read, and the
    // read's whose-it-is goes to the page with its name.
    testWidgets('her folder reached by a replacement with no title: no frame '
        'is writable', (tester) async {
      await pumpRoot(tester);
      folderRepository.shareCensus.forget();
      expect(folderService.knownFromPartner(recipes.id), isNull);

      AppNavigator.popToFolder(
        tester.element(find.byType(OptimizedFolderContentPage).last),
        folderId: recipes.id,
        title: '',
      ).ignore();
      // The read answers and the replacement is pushed, unbuilt; a write
      // lets the caches go before its first frame, as a merge can.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      folderRepository.shareCensus.forget();
      expect(folderService.knownFromPartner(recipes.id), isNull);

      expect(await writableFrames(tester, recipes.id), 0);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
        findsOneWidget,
      );
      await teardownPage(tester);
    });

    // §16.9 B1: the page holds its first frame for her name, and a read that
    // fails must end the hold — never a blank ground with no way back.
    testWidgets('a look read that fails: the page is drawn — its bar, its '
        'back button, the line', (tester) async {
      share = _LooksFail();
      await pumpRoot(tester);
      await openFolder(tester, recipes);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(FolderSliverAppBar), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
        findsOneWidget,
      );

      await teardownPage(tester);
    });

    // Leg 7's B12: while the look is out the page holds only what the look
    // sizes — the line and the rows under it — and draws its bar with the
    // back button, so the hold is never a bare ground with no way back; the
    // bar does not move when the look lands.
    testWidgets('a look still out: the bar and its back button are drawn, '
        'the line and rows wait, and the bar stays put when it lands', (
      tester,
    ) async {
      final look = Completer<ShareLook>();
      share = _LooksHeld(look.future);
      await pumpRoot(tester);
      AppNavigator.toFolder(
        tester.element(find.byType(OptimizedFolderContentPage).last),
        folderId: recipes.id,
        title: recipes.name,
        fromPartner: true,
      ).ignore();
      await transition(tester);

      final herPage = find.byWidgetPredicate(
        (w) => w is OptimizedFolderContentPage && w.folderId == recipes.id,
      );
      Finder inHers(Finder finder) =>
          find.descendant(of: herPage, matching: finder);
      expect(inHers(find.byType(FolderSliverAppBar)), findsOneWidget);
      expect(inHers(find.byTooltip('Back')), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
        findsNothing,
      );
      expect(inHers(find.text('Leek soup')), findsNothing);
      final title = tester.getRect(inHers(find.text('Recipes')).first);

      look.complete(const ShareLook());
      await transition(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
        findsOneWidget,
      );
      expect(inHers(find.text('Leek soup')), findsOneWidget);
      expect(tester.getRect(inHers(find.text('Recipes')).first), title);
      await teardownPage(tester);
    });

    // §16.9 B2: the page starts its reader on every build; a service that
    // cannot be built must not be asked again on the rebuild its failure
    // causes. Counted over a bounded number of frames, so a regression fails
    // rather than spins.
    testWidgets('a share service that cannot be built is not asked once per '
        'frame', (tester) async {
      PartnerLookReader.openService = () async {
        opened++;
        throw StateError('ShareService is not configured');
      };
      await pumpRoot(tester);
      await transition(tester);
      final settled = opened;
      expect(settled, greaterThan(0));

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(opened, settled);
      expect(find.text('Plain'), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('her rows\' sheets: the reason on top, Select and every write '
        'disabled, Copy to my notes on a note', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, recipes);

      await tester.longPress(find.text('Leek soup'));
      await transition(tester);
      expect(find.text('Only Maria can change this.'), findsOneWidget);
      ListTile tile(String label) => tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      for (final off in [
        l10n.select,
        l10n.rename,
        l10n.moveToFolder,
        l10n.shareNote,
        l10n.delete,
      ]) {
        expect(tile(off).enabled, isFalse, reason: off);
      }
      expect(
        find.bySemanticsIdentifier(SemanticsIds.rowActionCopyToMine),
        findsOneWidget,
      );
      expect(tile(l10n.sharedNoteCopy).enabled, isTrue);

      await teardownPage(tester);
    });

    testWidgets('the root\'s row of hers offers Select disabled', (
      tester,
    ) async {
      await pumpRoot(tester);
      await tester.longPress(find.text('Recipes'));
      await transition(tester);

      final select = tester.widget<ListTile>(
        find.ancestor(
          of: find.text(l10n.select),
          matching: find.byType(ListTile),
        ),
      );
      expect(select.enabled, isFalse);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.rowActionShare),
        findsNothing,
      );

      await teardownPage(tester);
    });

    testWidgets('German at 2.0 with a long name: the line wraps, nothing is '
        'cut', (tester) async {
      share = FakeShareService(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maximilian-Alexander Mustermann',
            members: [AppUser(uid: partner)],
          ),
        ),
      );
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<OptimizedFolderBloc>.value(value: folderBloc),
            BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
            BlocProvider<ImportExportBloc>.value(value: exportBloc),
          ],
          child: MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [AppNavigator.routeObserver],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: OptimizedFolderContentPage(
              folderId: recipes.id,
              title: recipes.name,
            ),
          ),
        ),
      );
      await transition(tester);
      await transition(tester);

      final line = find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine);
      expect(line, findsOneWidget);
      expect(
        tester.getSemantics(line).label,
        'Von Maximilian-Alexander Mustermann · Schreibgeschützt',
      );
      expect(tester.takeException(), isNull);

      // Review 15: the ⋮ menu at German 2.0 — the Sort row's value gives
      // way instead of running past the menu.
      await tester.tap(find.byType(FolderOverflowMenu));
      await transition(tester);
      expect(tester.takeException(), isNull);

      await teardownPage(tester);
    });

    // Review 2's unrendered pin: the picker's path row is pinned already;
    // this is the page's own bar over a chain of hers.
    testWidgets('German at 2.0 with real Roboto, four long names deep in her '
        'folder: the bar and its crumbs overflow nothing', (tester) async {
      await tester.runAsync(loadGoldenFonts);
      const names = [
        'Krafttraining und Ausdauerprogramme',
        'Wochenpläne für die Wintervorbereitung',
        'Oberkörperübungen mit Langhantel',
        'Aufzeichnungen der Trainingseinheiten',
      ];
      // Made as mine, then handed under her Soups as the shared reader
      // writes her rows: past the fence.
      final chain = (await tester.runAsync(() async {
        final made = <String>[];
        String? parentId;
        for (final name in names) {
          parentId = (await db.folderDao.createFolder(
            name: name,
            parentId: parentId,
          )).id;
          made.add(parentId);
        }
        await db.sharedRowDao.writing(() async {
          await db.customStatement(
            'UPDATE folders SET parent_id = ? WHERE id = ?',
            [soups.id, made.first],
          );
          await db.customStatement(
            'UPDATE folders SET owner_id = ? WHERE id IN (?, ?, ?, ?)',
            [partner, ...made],
          );
        });
        folderRepository.shareCensus.forget();
        folderService.invalidateCache();
        return made;
      }))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          await db.sharedRowDao.writing(
            () => db.customStatement(
              'DELETE FROM folders WHERE id IN (?, ?, ?, ?)',
              chain,
            ),
          );
          folderRepository.shareCensus.forget();
          folderService.invalidateCache();
        });
      });
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<OptimizedFolderBloc>.value(value: folderBloc),
            BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
            BlocProvider<ImportExportBloc>.value(value: exportBloc),
          ],
          child: MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [AppNavigator.routeObserver],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: OptimizedFolderContentPage(
              folderId: chain.last,
              title: names.last,
            ),
          ),
        ),
      );
      await transition(tester);
      await transition(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
        findsOneWidget,
      );
      expect(find.text(names.last), findsWidgets);
      expect(tester.takeException(), isNull);
      // The large title's band clips instead of reporting an overflow, so
      // what is pinned is that each line stands whole in its own place: the
      // parent's name under the toolbar, the name under it, the line below.
      final eyebrow = tester.getRect(find.text(names[2]));
      final large = find
          .text(names.last)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)));
      final title = large.reduce((a, b) => a.top > b.top ? a : b);
      final line = tester.getRect(
        find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine),
      );
      expect(eyebrow.top, greaterThanOrEqualTo(AppBarMetrics.toolbarHeight));
      expect(eyebrow.bottom, lessThanOrEqualTo(title.top));
      expect(title.bottom, lessThanOrEqualTo(line.top));

      await teardownPage(tester);
    });

    testWidgets('opened from the Sharing page\'s list with cold caches: '
        'read-only from its first frame, the line naming her', (tester) async {
      share.shareOverview = ShareOverview(
        partnerFolders: [
          PartnerSharedFolder(id: recipes.id, name: 'Recipes', noteCount: 1),
        ],
      );
      final bloc = ShareBloc(
        service: () async => share,
        calendarChanges: const Stream.empty(),
      );
      addTearDown(bloc.close);
      bloc.add(const ShareOpened());
      await tester.runAsync(
        () => bloc.stream.firstWhere((state) => state is ShareLoaded),
      );
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => PartnerSharedFoldersSheet.show(
                context,
                bloc: bloc,
                partnerName: 'Maria',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Cold: no census held and no folder cached — only the opener knows.
      folderService.invalidateCache();
      expect(folderService.knownFromPartner(recipes.id), isNull);
      await tester.tap(find.text('Recipes'));
      var frames = 0;
      while (find.byTooltip(l10n.newNote).evaluate().isEmpty && frames < 60) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      final newFolder = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip(l10n.newFolder),
              matching: find.byType(IconButton),
            )
            .last,
      );
      expect(newFolder.onPressed, isNull);
      final line = find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine);
      expect(tester.getSemantics(line).label, 'From Maria · Read only');

      await transition(tester);
      await teardownPage(tester);
    });

    testWidgets('read-only from its first frame, the line already naming her; '
        'a folder of mine never shows a disabled bar', (tester) async {
      IconButton? newFolder() {
        final found = find.ancestor(
          of: find.byTooltip(l10n.newFolder),
          matching: find.byType(IconButton),
        );
        return found.evaluate().isEmpty
            ? null
            : tester.widget<IconButton>(found.last);
      }

      await pumpRoot(tester);
      await tester.tap(find.text('Recipes'));
      // Frame by frame until the page's own bar is drawn: from that first
      // frame on, nothing on it may change.
      var frames = 0;
      while (find.byTooltip(l10n.newNote).evaluate().isEmpty && frames < 60) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(newFolder()!.onPressed, isNull);
      final line = find.bySemanticsIdentifier(SemanticsIds.browserPartnerLine);
      expect(tester.getSemantics(line).label, 'From Maria · Read only');
      await transition(tester);
      await teardownPage(tester);

      await pumpRoot(tester);
      await tester.tap(find.text('Plain'));
      frames = 0;
      while (find.byTooltip(l10n.newNote).evaluate().isEmpty && frames < 60) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip(l10n.newFolder),
                    matching: find.byType(IconButton),
                  )
                  .last,
            )
            .onPressed,
        isNotNull,
      );
      await transition(tester);
      await teardownPage(tester);
    });
  });

  group('the share entry of a folder of mine', () {
    PopupMenuItem<Object?> shareItem(WidgetTester tester) =>
        tester.widget<PopupMenuItem<Object?>>(
          find
              .ancestor(
                of: find.bySemanticsIdentifier(SemanticsIds.folderMenuShare),
                matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
              )
              .first,
        );

    Future<void> openMenuOn(WidgetTester tester, Folder folder) async {
      await pumpRoot(tester);
      await openFolder(tester, folder);
      await tester.tap(find.byType(FolderOverflowMenu).last);
      await transition(tester);
    }

    testWidgets('"Share with Maria" shares, says so, and its Undo undoes', (
      tester,
    ) async {
      share.nextChange = ShareChange(
        sharedFolders: [ShareFolderRef(id: plain.id, name: 'Plain')],
      );
      await openMenuOn(tester, plain);
      expect(shareItem(tester).enabled, isTrue);
      expect(find.text('Share with Maria'), findsOneWidget);
      final shareTop = tester.getTopLeft(find.text('Share with Maria')).dy;
      expect(
        shareTop,
        lessThan(tester.getTopLeft(find.text(l10n.shareFolder)).dy),
        reason: 'directly above "Send a copy"',
      );

      await tester.tap(find.text('Share with Maria'));
      await transition(tester);

      expect(share.folderShares, [(plain.id, true)]);
      expect(find.text('Sharing Plain with Maria'), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.snackbarUndo));
      await transition(tester);
      expect(share.undone, hasLength(1));

      await teardownPage(tester);
    });

    testWidgets('its own mark set: "Shared with Maria" with a tick; a tap '
        'stops it', (tester) async {
      await openMenuOn(tester, kitchen);
      expect(find.text('Shared with Maria'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.tap(find.text('Shared with Maria'));
      await transition(tester);
      expect(share.folderShares, [(kitchen.id, false)]);

      await teardownPage(tester);
    });

    // Review 10 (B7): the act forgets the share census itself, and the
    // forget reloads every open folder page; the page reloads once for it,
    // never once more of its own.
    group('the reloads an act costs', () {
      late OptimizedFolderBloc shared;
      late _CountingFolderBloc counting;

      setUp(() {
        shared = folderBloc;
        counting = _CountingFolderBloc(storageService: folderService);
        folderBloc = counting;
        share = _ForgetsAsTheAppDoes(folderService.invalidateCache);
      });

      tearDown(() async {
        folderBloc = shared;
        await counting.close();
      });

      int loadsOf(Folder folder) => counting.events
          .whereType<LoadFoldersPaginated>()
          .where((event) => event.parentId == folder.id)
          .length;

      testWidgets('a share and its Undo: one reload each', (tester) async {
        share.nextChange = ShareChange(
          sharedFolders: [ShareFolderRef(id: plain.id, name: 'Plain')],
        );
        await openMenuOn(tester, plain);
        final opening = loadsOf(plain);

        await tester.tap(find.text('Share with Maria'));
        await transition(tester);
        expect(share.folderShares, [(plain.id, true)]);
        expect(loadsOf(plain) - opening, 1, reason: 'the share');

        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.snackbarUndo));
        await transition(tester);
        expect(share.undone, hasLength(1));
        expect(loadsOf(plain) - opening, 2, reason: 'and its Undo');

        await teardownPage(tester);
      });
    });

    testWidgets('covered by the folder around it: disabled, captioned with '
        'that folder', (tester) async {
      await pumpRoot(tester);
      await openFolder(tester, kitchen);
      await openFolder(tester, pantry);
      await tester.tap(find.byType(FolderOverflowMenu).last);
      await transition(tester);

      expect(shareItem(tester).enabled, isFalse);
      expect(find.text('Shared with Maria'), findsOneWidget);
      expect(find.text('On for everything in Kitchen'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await transition(tester);

      // Review 16: the same entry in the row's sheet is still a button,
      // and says it is off.
      await openFolder(tester, kitchen);
      await tester.longPress(find.text('Pantry'));
      await transition(tester);
      expect(
        tester.getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.rowActionShare),
        ),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );

      await teardownPage(tester);
    });

    testWidgets('a database that does not sync: disabled, "Turn on sync to '
        'share"', (tester) async {
      share = FakeShareService(availability: const ShareNotSyncing(audience));
      await openMenuOn(tester, plain);

      expect(shareItem(tester).enabled, isFalse);
      expect(find.text(l10n.shareNeedsSync), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('not paired: absent', (tester) async {
      share = FakeShareService();
      await openMenuOn(tester, plain);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.folderMenuShare),
        findsNothing,
      );
      expect(find.text(l10n.shareFolder), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('refused — the database stopped syncing since — and failed: '
        'each said plainly, nothing offered to undo', (tester) async {
      share = _ActFails(const ShareRefused(ShareNotSyncing(audience)));
      await openMenuOn(tester, plain);
      await tester.tap(find.text('Share with Maria'));
      await transition(tester);
      expect(find.text(l10n.shareNeedsSync), findsOneWidget);
      expect(find.text(l10n.undo), findsNothing);
      await teardownPage(tester);

      share = _ActFails(StateError('disk'));
      await openMenuOn(tester, plain);
      await tester.tap(find.text('Share with Maria'));
      await transition(tester);
      expect(find.text(l10n.shareChangeFailed), findsOneWidget);
      await teardownPage(tester);
    });

    testWidgets('a stop that found no mark — another device cleared it — '
        'says nothing; a share that found one says it is shared', (
      tester,
    ) async {
      share.nextChange = ShareChange.none;
      await openMenuOn(tester, kitchen);
      await tester.tap(find.text('Shared with Maria'));
      await transition(tester);
      expect(share.folderShares, [(kitchen.id, false)]);
      expect(find.text('Kitchen is already shared'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await teardownPage(tester);

      await openMenuOn(tester, plain);
      await tester.tap(find.text('Share with Maria'));
      await transition(tester);
      expect(find.text('Plain is already shared'), findsOneWidget);
      await teardownPage(tester);
    });

    // Leg 2's D: the act is fenced by the database the tap was made under.
    // A switch while the service is fetched hands back the new database's
    // service, which must not take the write; a switch during the write
    // leaves the answer unsaid.
    testWidgets('the database switched between the tap and the write: '
        'nothing written, nothing said', (tester) async {
      share.nextChange = ShareChange(
        sharedFolders: [ShareFolderRef(id: plain.id, name: 'Plain')],
      );
      await openMenuOn(tester, plain);
      PartnerLookReader.openService = () async {
        DatabaseLifecycle.notifyDatabaseSwitching();
        return share;
      };

      await tester.tap(find.text('Share with Maria'));
      await transition(tester);

      expect(share.folderShares, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await teardownPage(tester);
    });

    testWidgets('the database switched during the write: nothing said', (
      tester,
    ) async {
      share = _SwitchesDuringAct(
        ShareChange(
          sharedFolders: [ShareFolderRef(id: plain.id, name: 'Plain')],
        ),
      );
      await openMenuOn(tester, plain);

      await tester.tap(find.text('Share with Maria'));
      await transition(tester);

      expect(share.folderShares, [(plain.id, true)]);
      expect(find.byType(SnackBar), findsNothing);
      await teardownPage(tester);
    });

    testWidgets('a share made elsewhere — the Sharing page, an Undo after '
        'its page left, another device — reaches the signs on screen', (
      tester,
    ) async {
      Finder signOn(String name) => find.descendant(
        of: find.widgetWithText(FolderRow, name),
        matching: find.byIcon(Icons.group_rounded),
      );
      await pumpRoot(tester);
      expect(signOn('Plain'), findsNothing);

      await tester.runAsync(
        () => db.folderDao.setSharedPair(plain.id, 'pair-1'),
      );
      // What every act, merge and shared read ends in.
      folderRepository.shareCensus.forget();
      await transition(tester);
      await transition(tester);
      expect(signOn('Plain'), findsOneWidget);

      await tester.runAsync(() => db.folderDao.setSharedPair(plain.id, null));
      folderRepository.shareCensus.forget();
      await transition(tester);
      await transition(tester);
      expect(signOn('Plain'), findsNothing);

      await teardownPage(tester);
    });
  });

  testWidgets('the root\'s "From Maria" group is whole on its first frame '
      'with more of my folders than a page holds', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < FolderStorageService.defaultPageSize + 5; i++) {
        await db.folderDao.createFolder(name: 'Archive $i');
      }
    });
    folderService.invalidateCache();
    await pumpRoot(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.browserSectionPartner),
      findsOneWidget,
    );
    expect(find.text('Recipes', skipOffstage: false), findsOneWidget);

    await teardownPage(tester);
  });

  group('All notes', () {
    testWidgets('marks the partner\'s note; Recent never lists it', (
      tester,
    ) async {
      await pumpApp(tester, const AllNotesPage());

      final theirs = find.widgetWithText(NoteRow, 'Leek soup');
      expect(theirs, findsOneWidget);
      expect(
        find.descendant(of: theirs, matching: find.byType(UserAvatar)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^From Maria\n')), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(NoteRow, 'Shopping'),
          matching: find.byType(UserAvatar),
        ),
        findsNothing,
        reason: 'a note of mine in a shared folder is not marked',
      );
      await teardownPage(tester);

      await pumpApp(tester, const AllNotesPage(mode: AllNotesMode.recent));
      expect(find.text('Shopping'), findsOneWidget);
      expect(find.text('Leek soup'), findsNothing);
      await teardownPage(tester);
    });
  });
}

/// A share service whose folder act always fails with [error].
class _ActFails extends FakeShareService {
  _ActFails(this.error)
    : super(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maria',
            members: [AppUser(uid: 'maria', displayName: 'Maria')],
          ),
        ),
      );

  final Object error;

  @override
  Future<ShareChange> setFolderShared(String id, bool on) async => throw error;
}

/// A share service paired with Maria whose look read always fails.
class _LooksFail extends FakeShareService {
  _LooksFail()
    : super(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maria',
            members: [AppUser(uid: 'maria', displayName: 'Maria')],
          ),
        ),
      );

  @override
  Future<ShareLook> looks() async => throw StateError('settings');
}

/// A share service paired with Maria whose look read answers with [held].
class _LooksHeld extends FakeShareService {
  _LooksHeld(this.held)
    : super(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maria',
            members: [AppUser(uid: 'maria', displayName: 'Maria')],
          ),
        ),
      );

  final Future<ShareLook> held;

  @override
  Future<ShareLook> looks() => held;
}

/// A share service paired with Maria whose acts end as the app's do: the
/// service's `foldersChanged` hook — the folder cache and the share census
/// dropped — runs before the act answers.
class _ForgetsAsTheAppDoes extends FakeShareService {
  _ForgetsAsTheAppDoes(this.foldersChanged)
    : super(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maria',
            members: [AppUser(uid: 'maria', displayName: 'Maria')],
          ),
        ),
      );

  final void Function() foldersChanged;

  @override
  Future<ShareChange> setFolderShared(String id, bool on) async {
    final change = await super.setFolderShared(id, on);
    foldersChanged();
    return change;
  }

  @override
  Future<ShareChange> undo(ShareChange change) async {
    final undone = await super.undo(change);
    foldersChanged();
    return undone;
  }
}

/// The folder bloc, counting what the pages ask of it.
class _CountingFolderBloc extends OptimizedFolderBloc {
  _CountingFolderBloc({required super.storageService});

  final events = <Object?>[];

  @override
  void onEvent(OptimizedFolderEvent event) {
    super.onEvent(event);
    events.add(event);
  }
}

/// A share service whose folder act writes, then sees the database switch
/// before it answers [change].
class _SwitchesDuringAct extends FakeShareService {
  _SwitchesDuringAct(this.change)
    : super(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maria',
            members: [AppUser(uid: 'maria', displayName: 'Maria')],
          ),
        ),
      );

  final ShareChange change;

  @override
  Future<ShareChange> setFolderShared(String id, bool on) async {
    folderShares.add((id, on));
    DatabaseLifecycle.notifyDatabaseSwitching();
    return change;
  }
}
