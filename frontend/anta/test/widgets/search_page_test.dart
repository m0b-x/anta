import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/pages/search_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/search_surface.dart';

/// The standalone search route end to end: a real database under a real
/// [SearchBloc], with only the platform channels mocked.
///
/// Harness notes are the editor and browser suites' and travel with them:
/// drift answers on a background isolate that `FakeAsync` cannot advance, so
/// [settle] hands the real event loop back before pumping frames, services
/// live in `setUpAll`, and the page is unmounted before a case ends.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late FolderStorageService folderService;
  late NoteStorageService noteService;
  late FolderSearchService searchService;

  late String trainingId;
  late String winterId;
  late String groceriesId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_search_page');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();

    folderService = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderService.initialize();
    noteService = NoteStorageService(repository: NoteRepository(database: db));
    await noteService.initialize();
    searchService = FolderSearchService(storageService: noteService);
    await searchService.initialize();

    GetIt.I.registerSingleton<FolderStorageService>(folderService);
    GetIt.I.registerSingleton<NoteStorageService>(noteService);
    GetIt.I.registerSingleton<FolderSearchService>(searchService);

    trainingId = (await folderService.createFolder(name: 'Training')).id;
    winterId = (await folderService.createFolder(
      name: 'Winter block',
      parentId: trainingId,
    )).id;
    groceriesId = (await folderService.createFolder(name: 'Groceries')).id;

    // Matches on the title only.
    await noteService.createNote(
      folderId: trainingId,
      title: 'Squat plan',
      content: 'warm up thoroughly and then work up #heavy',
    );
    // Matches in the body only, and lives one level down — the case for
    // recursive scope.
    await noteService.createNote(
      folderId: winterId,
      title: 'Week 1 session',
      content: 'squat 5x5 then press #heavy',
    );
    // Outside the Training subtree entirely.
    await noteService.createNote(
      folderId: groceriesId,
      title: 'Shopping',
      content: 'buy a squat rack eventually',
    );
    await searchService.buildIndex();
  });

  tearDownAll(() async {
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
    String? folderId,
    String? folderName,
    String? initialQuery,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [AppNavigator.routeObserver],
        home: SearchPage(
          folderId: folderId,
          folderName: folderName,
          initialQuery: initialQuery,
        ),
      ),
    );
    await settle(tester);
  }

  List<String> rowTitles(WidgetTester tester) {
    return tester
        .widgetList<SearchResultRow>(find.byType(SearchResultRow))
        .map((row) => row.metadata.title)
        .toList();
  }

  /// Section labels are rendered upper-cased by [ContentSectionHeader], so
  /// they are read off the widget rather than searched for as text.
  List<String> sectionLabels(WidgetTester tester) {
    return tester
        .widgetList<ContentSectionHeader>(find.byType(ContentSectionHeader))
        .map((header) => header.label)
        .toList();
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await settle(tester, rounds: 60);
  }

  group('a tag tap', () {
    testWidgets('opens on Everywhere with no scope chips', (tester) async {
      await pumpPage(tester, initialQuery: '#heavy');

      expect(find.byType(SearchScopeChips), findsNothing);
      expect(find.text(l10n.everywhere), findsNothing);
      await teardownPage(tester);
    });

    testWidgets('lands straight in grouped results', (tester) async {
      await pumpPage(tester, initialQuery: 'squat');

      expect(sectionLabels(tester), [l10n.titlesSection, l10n.inTextSection]);
      expect(rowTitles(tester), contains('Squat plan'));
      await teardownPage(tester);
    });

    testWidgets('a note matching title and body appears once', (tester) async {
      await pumpPage(tester, initialQuery: 'squat');

      final titles = rowTitles(tester);
      expect(
        titles.where((t) => t == 'Squat plan'),
        hasLength(1),
        reason: 'a title hit must not repeat under In text',
      );
      await teardownPage(tester);
    });
  });

  group('idle', () {
    testWidgets('shows recents with the folder each one lives in', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(sectionLabels(tester), [l10n.recent]);
      expect(rowTitles(tester), isNotEmpty);
      expect(
        find.text('Training › Winter block'),
        findsOneWidget,
        reason: 'a nested note shows its whole path, not just its folder',
      );
      await teardownPage(tester);
    });

    testWidgets('clearing the field returns to recents', (tester) async {
      await pumpPage(tester);
      await type(tester, 'squat');
      expect(sectionLabels(tester), isNot(contains(l10n.recent)));

      await type(tester, '');

      expect(sectionLabels(tester), [l10n.recent]);
      await teardownPage(tester);
    });
  });

  group('folder scope', () {
    testWidgets('offers the folder and Everywhere', (tester) async {
      await pumpPage(tester, folderId: trainingId, folderName: 'Training');

      expect(find.byType(SearchScopeChips), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Training'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, l10n.everywhere), findsOneWidget);
      await teardownPage(tester);
    });

    testWidgets('falls back to "This folder" without a name', (tester) async {
      await pumpPage(tester, folderId: trainingId);

      expect(find.widgetWithText(ChoiceChip, l10n.thisFolder), findsOneWidget);
      await teardownPage(tester);
    });

    testWidgets('a search reaches into subfolders but stops at the subtree', (
      tester,
    ) async {
      await pumpPage(tester, folderId: trainingId, folderName: 'Training');
      await type(tester, 'squat');

      final titles = rowTitles(tester);
      expect(titles, contains('Squat plan'));
      expect(
        titles,
        contains('Week 1 session'),
        reason: 'the note one level down is inside the folder being searched',
      );
      expect(titles, isNot(contains('Shopping')));
      await teardownPage(tester);
    });

    testWidgets('switching to Everywhere re-runs the same query wider', (
      tester,
    ) async {
      await pumpPage(tester, folderId: trainingId, folderName: 'Training');
      await type(tester, 'squat');
      expect(rowTitles(tester), isNot(contains('Shopping')));

      await tester.tap(find.widgetWithText(ChoiceChip, l10n.everywhere));
      await settle(tester, rounds: 40);

      expect(rowTitles(tester), contains('Shopping'));
      await teardownPage(tester);
    });
  });

  group('no results', () {
    testWidgets('says so rather than showing an empty list', (tester) async {
      await pumpPage(tester);
      await type(tester, 'deadliftxyz');

      expect(find.text(l10n.noSearchResults), findsOneWidget);
      expect(find.byType(SearchResultRow), findsNothing);
      await teardownPage(tester);
    });
  });

  group('grouping labels', () {
    testWidgets('a single group carries no section label', (tester) async {
      await pumpPage(tester, folderId: groceriesId, folderName: 'Groceries');
      await type(tester, 'squat');

      expect(rowTitles(tester), ['Shopping']);
      expect(sectionLabels(tester), isEmpty);
      await teardownPage(tester);
    });

    testWidgets('rows are drawn in the browser row shell', (tester) async {
      await pumpPage(tester);

      expect(find.byType(ContentRowShell), findsWidgets);
      await teardownPage(tester);
    });
  });
}
