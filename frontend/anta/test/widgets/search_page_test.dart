import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
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
        find.textContaining('Training › Winter block', findRichText: true),
        findsOneWidget,
        reason: 'a nested note shows its whole path, not just its folder',
      );
      await teardownPage(tester);
    });

    testWidgets('a recent row reads "path · date", the date in w500 '
        'onSurface', (tester) async {
      await pumpPage(tester);

      final row = find.byType(SearchResultRow).first;
      final line = tester.widget<Text>(
        find
            .descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (w) => w is Text && w.textSpan != null,
              ),
            )
            .last,
      );
      final spans = (line.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans, hasLength(3));
      expect(spans[1].text, ' · ');
      expect(spans[2].text, l10n.today);
      expect(spans[2].style!.fontWeight, FontWeight.w500);

      final scheme = Theme.of(tester.element(row)).colorScheme;
      expect(spans[2].style!.color, scheme.onSurface);
      expect(line.style!.color, scheme.onSurfaceVariant);
      expect(line.style!.fontSize, 13);

      // No leading glyph, and the row is the note row's own height.
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.description_outlined),
        ),
        findsNothing,
      );
      expect(
        tester
            .getSize(find.descendant(of: row, matching: find.byType(InkWell)))
            .height,
        62,
      );

      // Without a leading glyph the text column must still hug the row's
      // start edge — a shrink-wrapped column would sit centred in the row.
      final rowRect = tester.getRect(
        find.descendant(of: row, matching: find.byType(InkWell)),
      );
      final titleRect = tester.getRect(
        find.descendant(of: row, matching: find.byType(Text)).first,
      );
      expect(titleRect.left, rowRect.left + RowMetrics.twoLinePadding.left);
      expect(titleRect.right, rowRect.right - RowMetrics.twoLinePadding.right);

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

  group('the search bar', () {
    testWidgets('the field is 17 px with the hint in outline', (tester) async {
      await pumpPage(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.fontSize, AppBarMetrics.titleFontSize);
      expect(field.textInputAction, TextInputAction.search);
      expect(
        field.decoration!.hintStyle!.color,
        Theme.of(tester.element(find.byType(TextField))).colorScheme.outline,
      );

      await teardownPage(tester);
    });

    testWidgets('the clear button is labelled and 22 px', (tester) async {
      await pumpPage(tester);
      expect(find.byIcon(Icons.clear), findsNothing);

      await type(tester, 'squat');

      final clear = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.clear),
          matching: find.byType(IconButton),
        ),
      );
      expect(clear.tooltip, l10n.clearSearch);
      expect(clear.iconSize, AppBarMetrics.glyphSize);

      await teardownPage(tester);
    });
  });

  group('opening a result and coming back', () {
    /// A stand-in for the note a hit pushes: the editor itself is another
    /// suite's subject, and what matters here is only that a route went on
    /// top of this one and came off again.
    Future<NavigatorState> pushOver(WidgetTester tester) async {
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
      return navigator;
    }

    testWidgets('coming back from a result leaves the keyboard down', (
      tester,
    ) async {
      await pumpPage(tester);
      await type(tester, 'squat');

      final focusNode = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(focusNode.hasFocus, isTrue);

      final navigator = await pushOver(tester);
      expect(focusNode.hasFocus, isFalse);

      navigator.pop();
      await settle(tester, rounds: 40);

      expect(
        focusNode.hasFocus,
        isFalse,
        reason:
            'a route regaining focus hands it back to the child that had it, '
            'and a field regaining focus reopens the keyboard over the very '
            'results the user came back to',
      );
      expect(find.byType(SearchResultRow), findsWidgets);

      await teardownPage(tester);
    });

    testWidgets('a note edited through a result comes back refreshed', (
      tester,
    ) async {
      await pumpPage(tester, initialQuery: 'squat');
      expect(rowTitles(tester), contains('Squat plan'));

      final navigator = await pushOver(tester);
      final page = await tester.runAsync(
        () => noteService.loadNotesPaginated(pageSize: 20),
      );
      final target = page!.notes.firstWhere((n) => n.title == 'Squat plan');
      await tester.runAsync(
        () => noteService.updateNote(noteId: target.id, title: 'Squat plan v2'),
      );
      addTearDown(
        () => noteService.updateNote(noteId: target.id, title: 'Squat plan'),
      );

      navigator.pop();
      await settle(tester, rounds: 60);

      expect(
        rowTitles(tester),
        contains('Squat plan v2'),
        reason:
            'the hits are a snapshot of the moment the push was made; a note '
            'renamed through one of them comes back stale unless the pass is '
            're-run',
      );

      await teardownPage(tester);
    });

    testWidgets('an idle surface reloads its recents on the way back', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(sectionLabels(tester), [l10n.recent]);

      final navigator = await pushOver(tester);
      navigator.pop();
      await settle(tester, rounds: 40);

      expect(sectionLabels(tester), [l10n.recent]);
      expect(find.byType(SearchResultRow), findsWidgets);

      await teardownPage(tester);
    });
  });
}
