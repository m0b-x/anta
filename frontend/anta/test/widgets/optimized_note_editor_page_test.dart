import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_state.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/font_constants.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/pages/optimized_note_editor_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/note_position_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';
import 'package:anta/widgets/unified_app_bars.dart';

/// The first page-level test in the app.
///
/// What it buys: the editor page resolves five ambient async singletons in
/// `initState` (database, settings, note positions, dev options, vocabulary)
/// and three BLoCs from the tree, and the interesting bugs live in how those
/// *land relative to each other* — which is exactly what a unit test of any
/// one of them cannot see. Two orderings are pinned here (B2: the saved caret
/// survives whichever of content and position arrives last) plus B3 (editor
/// settings edited on a page pushed above this one apply on the way back).
///
/// Harness notes for reuse:
/// - `AppDatabase.getInstance()` needs `path_provider` and `SharedPreferences`
///   mocked; with both in place every singleton binds to the same real
///   database, so nothing has to be faked below the service layer.
/// - drift opens that database with `NativeDatabase.createInBackground`, so
///   its queries complete on a real isolate that `FakeAsync` cannot advance.
///   [settle] hands the real event loop back and then flushes the resulting
///   `setState`s into a frame; `pumpAndSettle` alone never gets there.
/// - The note BLoC is a real one with its `LoadNoteContent` handling
///   suppressed, so the test decides exactly when the content lands.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const folderId = 'folder-1';
  const noteId = 'note-1';
  const content = 'first line\nsecond line\nthird line here\nfourth';

  late Directory tempDir;
  late AppDatabase db;
  late NotePositionService positions;
  late SettingsService settings;
  late NoteStorageService storageService;
  late _ThrowingStorage throwingStorage;
  late FolderSearchService searchService;
  late FolderStorageService folderService;
  late _TestExportService exportService;
  late ImportExportBloc exportBloc;
  late _TestNoteBloc noteBloc;
  late MarkdownBarBloc barBloc;
  late CounterBloc counterBloc;

  final metadata = NoteMetadata(
    id: noteId,
    folderId: folderId,
    title: 'Training log',
    preview: 'first line',
    contentLength: content.length,
    chunkCount: 1,
    isCompressed: false,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  /// A sibling note, for the cases about the app-wide BLoC delivering one
  /// editor's state to another's listener.
  final otherMetadata = NoteMetadata(
    id: 'note-2',
    folderId: folderId,
    title: 'Groceries',
    preview: 'milk',
    contentLength: 4,
    chunkCount: 1,
    isCompressed: false,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_note_editor_page');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    db = await AppDatabase.getInstance();
    // drift opens lazily; pay for the open (and the device-id file) here
    // rather than inside a `FakeAsync` test body.
    await db.customSelect('SELECT 1').get();
    positions = await NotePositionService.getInstance();
    settings = await SettingsService.getInstance();
    storageService = NoteStorageService(
      repository: NoteRepository(database: db),
    );
    await storageService.initialize();
    // A second service over the same database whose title lookup always
    // throws, for the case about the tap handler's own guard. Built here
    // like every other service: a `testWidgets` body cannot await one.
    throwingStorage = _ThrowingStorage(
      repository: NoteRepository(database: db),
    );
    await throwingStorage.initialize();
    searchService = FolderSearchService(storageService: storageService);
    await searchService.initialize();
    folderService = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderService.initialize();
    // Everything the page's BLoCs need is built here, in real async:
    // inside `testWidgets` the database answers on a background isolate
    // that `FakeAsync` never lets run, so an `await` on one of these in a
    // test body deadlocks rather than failing.
    //
    // The BLoCs themselves live for the whole file rather than per test:
    // the page dispatches to two of them from `dispose`, and the binding
    // unmounts a leftover tree at the *start* of the next test — closing
    // them between tests turns any earlier failure into a confusing
    // "cannot add new events after calling close" cascade.
    noteBloc = _TestNoteBloc(
      storageService: storageService,
      searchService: searchService,
    );
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    counterBloc = CounterBloc(
      counterService: await CounterService.getInstance(),
    );
    // A real export bloc over the real service, with only the share sheet
    // stubbed out: the editor's share has to reach `shareExport`, which is
    // exactly the call it used to make itself.
    exportService = _TestExportService(
      noteStorage: storageService,
      folderStorage: folderService,
      noteRepository: NoteRepository(database: db),
    );
    exportBloc = ImportExportBloc(service: exportService);
    GetIt.I.registerSingleton<NoteStorageService>(storageService);
    GetIt.I.registerSingleton<FolderStorageService>(folderService);
    // The drawer's avatar badge resolves this during its build, and the bar's
    // menu button can now open that drawer.
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDownAll(() async {
    await noteBloc.close();
    await barBloc.close();
    await counterBloc.close();
    await exportBloc.close();
    await GetIt.I.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    // A `BlocListener` only fires on a state *change*, so the shared note
    // BLoC has to drop back to its initial state between tests or the
    // second emit of an equal `OptimizedNoteContentLoaded` is a no-op.
    noteBloc.reset();
    await positions.deletePosition(noteId);
    await settings.setShowLineNumbers(false);
    await settings.setLiveMarkdownRendering(true);
    // Font sizes are per-database rows, and one case below writes the
    // editor's; clear both so the next test starts at the default.
    await db.userSettingsDao.deleteValue(SettingsKeys.editorFontSize);
    await db.userSettingsDao.deleteValue(SettingsKeys.previewFontSize);
  });

  /// Lets the page's real async work finish, then flushes whatever
  /// `setState`s it produced into frames. Both halves are needed: the
  /// database answers on a background isolate (real time only), and the
  /// widget tree advances only on `pump` (fake time only). One round
  /// carries roughly one round trip, so a chain of sequential reads needs
  /// several — the settings bundle is one statement now, but the money
  /// config, the colour palette and the stored position still queue up
  /// behind it. Prefer [settleUntil] over guessing a count.
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  /// [settle], stopping as soon as [ready] holds. Use it whenever the
  /// assertion is about something the page reaches asynchronously, so the
  /// test does not depend on a guessed round count.
  Future<void> settleUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 200; i++) {
      if (ready()) return;
      await settle(tester, rounds: 1);
    }
    fail('the awaited condition never held');
  }

  /// Unmounts the page before the test body ends. The editor keeps a cursor
  /// blink timer and the page an auto-save interval timer; both are cancelled
  /// by `dispose`, and leaving either running trips the binding's
  /// pending-timer check.
  Future<void> teardownPage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Seeds the note's stored position. A database *write* is a drift
  /// transaction on the background isolate, so it can only run through
  /// [WidgetTester.runAsync] — awaiting one directly inside `testWidgets`
  /// deadlocks in `FakeAsync` rather than failing.
  Future<void> savePosition(
    WidgetTester tester,
    int lineIndex,
    int columnOffset,
  ) {
    return tester.runAsync(
      () => positions.savePosition(
        noteId,
        NotePositionData(
          isPreviewMode: false,
          previewScrollProgress: 0.0,
          editorLineIndex: lineIndex,
          editorColumnOffset: columnOffset,
        ),
      ),
    );
  }

  /// `skipOffstage: false` because pushing a route above the page moves it
  /// into the overlay's offstage half, which the default finder skips.
  final editorFinder = find.byType(ModernEditorWrapper, skipOffstage: false);

  ModernEditorWrapper editorOf(WidgetTester tester) =>
      tester.widget<ModernEditorWrapper>(editorFinder);

  /// The wrapper's `State` object. Identity is the remount test (B4): a
  /// changed `ValueKey` gives the editor a brand-new `State`, and with it
  /// a fresh `CodeEditor` torn down mid-initialization.
  State<ModernEditorWrapper> editorStateOf(WidgetTester tester) =>
      tester.state<State<ModernEditorWrapper>>(editorFinder);

  /// The caret's line, or -1 while the page is still on its loading
  /// placeholder and no editor exists to ask.
  int caretLine(WidgetTester tester) => editorFinder.evaluate().isEmpty
      ? -1
      : editorOf(tester).controller.selection.baseIndex;

  /// Mounts the page over a real navigator (so a route can be pushed above
  /// it) with the real observer `didPopNext` rides on.
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
          BlocProvider<MarkdownBarBloc>.value(value: barBloc),
          BlocProvider<CounterBloc>.value(value: counterBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [AppNavigator.routeObserver],
          home: const OptimizedNoteEditorPage(
            folderId: folderId,
            noteId: noteId,
          ),
        ),
      ),
    );
  }

  /// Mounts the page and hands it the note's text, returning the editor's
  /// controller once both have landed.
  Future<CodeLineEditingController> loadNote(WidgetTester tester) async {
    await pumpPage(tester);
    noteBloc.emitContentLoaded(metadata, content);
    await tester.pump();
    await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
    await settle(tester);
    return editorOf(tester).controller;
  }

  /// [pumpPage] for a note that exists in the database. The reload cases
  /// read their note back through the service, so a metadata-only
  /// stand-in has nothing to read; everything else about the mount is
  /// [pumpPage]'s.
  Future<void> pumpPageFor(WidgetTester tester, NoteMetadata note) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
          BlocProvider<MarkdownBarBloc>.value(value: barBloc),
          BlocProvider<CounterBloc>.value(value: counterBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [AppNavigator.routeObserver],
          home: OptimizedNoteEditorPage(
            folderId: note.folderId,
            noteId: note.id,
            metadata: note,
          ),
        ),
      ),
    );
  }

  /// The page's app bar, whose `hasChanges` is the dirty indicator the save
  /// coordinator publishes.
  NoteAppBar appBar(WidgetTester tester) =>
      tester.widget<NoteAppBar>(find.byType(NoteAppBar, skipOffstage: false));

  /// The visible-column mapping the tap groups below address. The page
  /// (unlike the bare wrapper suites) renders through the markdown span
  /// builder, so a `[[title]]`'s brackets are concealed to ~0 width: the
  /// *visible* columns are what geometry can address, and the title's own
  /// glyphs start one visible column past `see `. Every tap lands in the
  /// middle of the rendered title, which is the whole tap zone, so the
  /// exact source offset it resolves to does not matter.
  const lineBox = FontConstants.defaultFontSize * MarkdownConstants.lineHeight;

  Offset visiblePoint(WidgetTester tester, int line, double column) {
    final origin = tester.getTopLeft(
      find.byType(CodeEditor, skipOffstage: false).first,
    );
    return origin +
        Offset(
          AppSpacing.lg + column * FontConstants.defaultFontSize,
          AppSpacing.lg + line * lineBox + lineBox / 2,
        );
  }

  NoteMetadata metadataFor(String text) => NoteMetadata(
    id: noteId,
    folderId: folderId,
    title: 'Training log',
    preview: text,
    contentLength: text.length,
    chunkCount: 1,
    isCompressed: false,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  /// Loads [text] into the page and parks the caret on line 1, so line 0
  /// — which carries the link in every case — is never the reveal line.
  Future<CodeLineEditingController> loadAndPark(
    WidgetTester tester,
    String text,
  ) async {
    await pumpPage(tester);
    noteBloc.emitContentLoaded(metadataFor(text), text);
    await tester.pump();
    await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
    await settle(tester);
    final controller = editorOf(tester).controller;
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 0,
    );
    await tester.pump();
    return controller;
  }

  Finder pages() => find.byType(OptimizedNoteEditorPage, skipOffstage: false);

  /// Pops whatever the tap pushed, so the next test starts on one page.
  Future<void> popPushed(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('B2 — the saved position survives either load order', () {
    testWidgets('a long note shows its stored line in the editor\'s first '
        'frame', (tester) async {
      const int storedLine = 300;
      final longContent = List.generate(400, (i) => 'line $i').join('\n');
      await savePosition(tester, storedLine, 2);

      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, longContent);
      await tester.pump();
      // Stop on the first frame the editor exists: the mount gate waits
      // for the stored position, and the restore arms the fork's
      // layout-time centring before that frame is built, so this frame's
      // own layout must already sit on the stored line — no frame ever
      // paints the top of the note and jumps.
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      final render = CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      );
      expect(render.displayedLineIndices, contains(storedLine));
      expect(
        editorOf(tester).scrollController.verticalScroller.position.pixels,
        greaterThan(0.0),
      );
      expect(editorOf(tester).controller.selection.baseIndex, storedLine);
      expect(editorOf(tester).controller.selection.baseOffset, 2);
      await teardownPage(tester);
    });

    testWidgets('the body is blank while loading and appears fully formed '
        'in one frame', (tester) async {
      await pumpPage(tester);

      // Nothing has landed: no half-built chrome — no toolbar built from
      // default settings, no stats bar — just the blank body.
      expect(find.byType(MarkdownBar, skipOffstage: false), findsNothing);
      expect(editorFinder, findsNothing);

      // Everything but the content settles; the body must still be blank,
      // because the toolbar would otherwise reflow when the editor lands.
      await settle(tester);
      expect(find.byType(MarkdownBar, skipOffstage: false), findsNothing);
      expect(editorFinder, findsNothing);

      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      // The frame the editor first exists in already carries the toolbar
      // — the bar bloc's answer is part of the mount gate, so the two
      // never arrive in different frames.
      expect(find.byType(MarkdownBar, skipOffstage: false), findsOneWidget);
      // And it arrives through the fade, not a hard swap.
      expect(
        find.ancestor(of: editorFinder, matching: find.byType(FadeTransition)),
        findsWidgets,
      );
      await teardownPage(tester);
    });

    testWidgets('content lands before the saved position', (tester) async {
      await savePosition(tester, 2, 6);

      await pumpPage(tester);

      // No `settle` yet: nothing the page awaited has resolved, so the
      // position is still in flight when the content arrives.
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      // The editor deliberately does not exist yet — its `ValueKey`
      // depends on a setting that has not landed (B4) — so wait for the
      // mount rather than reading the controller through the tree.
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      expect(editorOf(tester).controller.text, content);
      final mounted = editorStateOf(tester);

      await settleUntil(tester, () => caretLine(tester) == 2);

      final selection = editorOf(tester).controller.selection;
      expect(selection.baseIndex, 2);
      expect(selection.baseOffset, 6);

      // And it was mounted exactly once: everything the first frame's key
      // depends on had already landed.
      await settle(tester);
      expect(identical(editorStateOf(tester), mounted), isTrue);
      await teardownPage(tester);
    });

    testWidgets('live rendering off: the editor still mounts once', (
      tester,
    ) async {
      await tester.runAsync(() => settings.setLiveMarkdownRendering(false));

      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      // The stored flag picks the key, and it picks it on the first
      // frame the editor exists — never `editor-md` first and then this.
      expect(editorOf(tester).key, const ValueKey('editor'));
      final mounted = editorStateOf(tester);

      await settle(tester);
      expect(editorOf(tester).key, const ValueKey('editor'));
      expect(identical(editorStateOf(tester), mounted), isTrue);
      await teardownPage(tester);
    });

    testWidgets('the saved position lands before the content', (tester) async {
      await savePosition(tester, 3, 4);

      await pumpPage(tester);

      // The position resolves while the page is still on its loading
      // placeholder — there is no editor yet, so the restore has to wait
      // for the content rather than clamp itself against an empty
      // document.
      await settle(tester);
      expect(editorFinder, findsNothing);

      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => caretLine(tester) == 3);

      final selection = editorOf(tester).controller.selection;
      expect(selection.baseIndex, 3);
      expect(selection.baseOffset, 4);
      await teardownPage(tester);
    });

    testWidgets('a restored position is consumed exactly once', (tester) async {
      await savePosition(tester, 1, 3);

      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => caretLine(tester) == 1);

      final controller = editorOf(tester).controller;
      expect(controller.selection.baseIndex, 1);

      // Park the caret somewhere else, then drive the content-loaded
      // listener a second time (through `reset`, because a BLoC never
      // re-emits an equal state). `_pendingPosition` was nulled on
      // consume, so nothing should drag the caret back to line 1.
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );
      noteBloc.reset();
      await tester.pump();
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settle(tester);

      expect(controller.selection.baseIndex, isNot(1));
      expect(controller.selection.baseIndex, 0);
      await teardownPage(tester);
    });

    testWidgets('a note with no saved position keeps the caret at the top', (
      tester,
    ) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settle(tester);

      final selection = editorOf(tester).controller.selection;
      expect(selection.baseIndex, 0);
      expect(selection.baseOffset, 0);
      await teardownPage(tester);
    });
  });

  group('P2 — Enter on a list line', () {
    // 700 lines is three 256-line segments, so the structural edit has
    // untouched segments on both sides of the one it splits.
    const documentLines = 700;
    const listLine = 300;
    const emptyItemLine = 400;

    final longContent = List<String>.generate(documentLines, (i) {
      if (i == listLine) return '- squat 5x5';
      if (i == emptyItemLine) return '- ';
      return 'plain line $i';
    }).join('\n');

    final longMetadata = NoteMetadata(
      id: noteId,
      folderId: folderId,
      title: 'Training log',
      preview: 'plain line 0',
      contentLength: longContent.length,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    List<List<CodeLine>> backingLists(CodeLineEditingController controller) => [
      for (final segment in controller.codeLines.segments) segment.codeLines,
    ];

    Future<CodeLineEditingController> loadLongNote(WidgetTester tester) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(longMetadata, longContent);
      await tester.pump();
      await settle(tester);
      final controller = editorOf(tester).controller;
      expect(controller.codeLines.length, documentLines);
      expect(controller.codeLines.segments, hasLength(3));
      return controller;
    }

    testWidgets('continues the list prefix onto the new line', (tester) async {
      final controller = await loadLongNote(tester);
      final before = backingLists(controller);

      controller.selection = CodeLineSelection.collapsed(
        index: listLine,
        offset: '- squat 5x5'.length,
      );
      await tester.pump();

      controller.applyNewLine();
      await settle(tester, rounds: 4);

      expect(controller.codeLines.length, documentLines + 1);
      expect(controller.codeLines[listLine].text, '- squat 5x5');
      expect(controller.codeLines[listLine + 1].text, '- ');
      expect(controller.codeLines[listLine + 2].text, 'plain line 301');
      expect(controller.selection.baseIndex, listLine + 1);
      expect(controller.selection.baseOffset, 2);

      // The split rebuilds only the segment line 300 sat in (into a head
      // and a tail); the segments before and after it are carried over by
      // reference, which is what the incremental line index reads as
      // "nothing to re-render here".
      final after = backingLists(controller);
      expect(after, hasLength(4));
      expect(identical(after.first, before.first), isTrue);
      expect(identical(after.last, before.last), isTrue);
      expect(identical(after[1], before[1]), isFalse);
      expect(identical(after[2], before[1]), isFalse);

      await teardownPage(tester);
    });

    testWidgets('the continuation is part of the Enter undo step', (
      tester,
    ) async {
      final controller = await loadLongNote(tester);

      controller.selection = CodeLineSelection.collapsed(
        index: listLine,
        offset: '- squat 5x5'.length,
      );
      await tester.pump();

      controller.applyNewLine();
      await settle(tester, rounds: 4);
      expect(controller.codeLines[listLine + 1].text, '- ');

      controller.undo();
      await tester.pump();

      expect(controller.codeLines.length, documentLines);
      expect(controller.codeLines[listLine].text, '- squat 5x5');
      expect(controller.codeLines[listLine + 1].text, 'plain line 301');

      await teardownPage(tester);
    });

    testWidgets('Enter on an empty item drops the item line', (tester) async {
      final controller = await loadLongNote(tester);
      final before = backingLists(controller);

      controller.selection = const CodeLineSelection.collapsed(
        index: emptyItemLine,
        offset: 2,
      );
      await tester.pump();

      controller.applyNewLine();
      await settle(tester, rounds: 4);

      expect(controller.codeLines.length, documentLines);
      expect(controller.codeLines[emptyItemLine].text, '');
      expect(controller.codeLines[emptyItemLine + 1].text, 'plain line 401');
      expect(controller.selection.baseIndex, emptyItemLine);
      expect(controller.selection.baseOffset, 0);

      // The split and the removal together rebuild only the segment line
      // 400 sat in: `removeLine`'s `sublines` head re-owns it and `addFrom`
      // merges the 1-line remainder plus the split tail into it, while the
      // segments on either side are carried over by reference. A full-text
      // re-parse would hand back three brand-new lists instead.
      final after = backingLists(controller);
      expect(after, hasLength(3));
      expect(identical(after.first, before.first), isTrue);
      expect(identical(after.last, before.last), isTrue);
      expect(identical(after[1], before[1]), isFalse);

      await teardownPage(tester);
    });

    testWidgets('dropping the empty item is part of the Enter undo step', (
      tester,
    ) async {
      final controller = await loadLongNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: emptyItemLine,
        offset: 2,
      );
      await tester.pump();

      controller.applyNewLine();
      await settle(tester, rounds: 4);
      expect(controller.codeLines[emptyItemLine].text, '');

      controller.undo();
      await tester.pump();

      expect(controller.codeLines.length, documentLines);
      expect(controller.codeLines[emptyItemLine].text, '- ');
      expect(controller.codeLines[emptyItemLine + 1].text, 'plain line 401');

      await teardownPage(tester);
    });
  });

  group('B5 — the page writes settings through SettingsService', () {
    testWidgets('a font-size tap writes only the editor row', (tester) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      expect(editorOf(tester).editorFontSize, FontConstants.defaultFontSize);

      // Driven through the toolbar's own callback rather than a tap: the
      // bar's font buttons live behind a horizontal scroll view whose
      // layout is not what this case is about.
      tester
          .widget<MarkdownBar>(find.byType(MarkdownBar, skipOffstage: false))
          .onIncreaseFontSize();
      await tester.pump();

      // The editor sees the new size immediately — the controller updates
      // its value before the (debounced) write.
      expect(editorOf(tester).editorFontSize, 18.0);

      // Two clocks to get past: the write's debounce timer was started
      // inside the test's fake clock, and the statement it then issues
      // completes on drift's background isolate, which only real time
      // advances.
      await tester.pump(
        SettingsService.defaultWriteDebounce + const Duration(milliseconds: 50),
      );
      await settle(tester);

      expect(await tester.runAsync(settings.getEditorFontSize), 18.0);
      // And only that row: zooming the editor must never write the
      // preview's size (B5's other half — the page used to write both).
      expect(
        await tester.runAsync(
          () => db.userSettingsDao.getValue(SettingsKeys.previewFontSize),
        ),
        isNull,
      );
      await teardownPage(tester);
    });
  });

  group('toolbar shortcuts land under the page\'s own guards', () {
    const listContent = 'first line\n- squat 5x5\nthird line';

    final listMetadata = NoteMetadata(
      id: noteId,
      folderId: folderId,
      title: 'Training log',
      preview: 'first line',
      contentLength: listContent.length,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    /// A plain symmetric wrapper: with an empty selection the applier
    /// resolves it to [text] alone, so it is the simplest non-header
    /// shortcut there is.
    CustomMarkdownShortcut wrapper(String text) => CustomMarkdownShortcut(
      id: 'test-wrap',
      label: 'test',
      iconCodePoint: 0xe000,
      iconFontFamily: 'MaterialIcons',
      beforeText: text,
      afterText: text,
    );

    /// Fires the toolbar's own callback, the way B5 drives the font
    /// buttons — the bar's shortcut row is behind a horizontal scroll
    /// view whose layout is not what these cases are about.
    void press(WidgetTester tester, CustomMarkdownShortcut shortcut) {
      tester
          .widget<MarkdownBar>(find.byType(MarkdownBar, skipOffstage: false))
          .onShortcutPressed(shortcut);
    }

    Future<CodeLineEditingController> loadListNote(WidgetTester tester) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(listMetadata, listContent);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      return editorOf(tester).controller;
    }

    testWidgets('the insert is one undo step, not merged into the typing', (
      tester,
    ) async {
      final controller = await loadListNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'first line'.length,
      );
      controller.replaceSelection(' typed');
      await tester.pump();
      expect(controller.codeLines[0].text, 'first line typed');

      press(tester, wrapper('**'));
      await settle(tester, rounds: 3);
      expect(controller.codeLines[0].text, 'first line typed**');

      controller.undo();
      await tester.pump();

      expect(
        controller.codeLines[0].text,
        'first line typed',
        reason: 'one undo reverts the shortcut, not the burst before it',
      );
      await teardownPage(tester);
    });

    testWidgets('the edit tracker never sees the insert as a typed Enter', (
      tester,
    ) async {
      final controller = await loadListNote(tester);

      // A one-newline insert at the end of a list line is exactly the
      // shape the tracker's Enter branch continues a list on: growth of
      // one, caret parked at column 0 of the new line, a list item above
      // it. Only the tracker's guard tells the two apart — and while the
      // insert landed in a microtask after the guard had been lowered, it
      // did not.
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: '- squat 5x5'.length,
      );
      await tester.pump();

      press(tester, wrapper('\n'));
      await settle(tester, rounds: 3);

      expect(controller.codeLines.length, 4);
      expect(controller.codeLines[1].text, '- squat 5x5');
      expect(
        controller.codeLines[2].text,
        '',
        reason: 'a shortcut insert is not an Enter: no list marker follows',
      );
      expect(controller.codeLines[3].text, 'third line');
      await teardownPage(tester);
    });

    testWidgets('the header shortcut cycles the caret line', (tester) async {
      final controller = await loadListNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      await tester.pump();

      press(
        tester,
        const CustomMarkdownShortcut(
          id: 'test-header',
          label: 'header',
          iconCodePoint: 0xe000,
          iconFontFamily: 'MaterialIcons',
          beforeText: '# ',
          afterText: '',
          insertType: 'header',
        ),
      );
      await settle(tester, rounds: 3);

      expect(controller.codeLines[0].text, '# first line');
      expect(controller.codeLines[1].text, '- squat 5x5');
      await teardownPage(tester);
    });
  });

  group('undo baseline — the loaded note is the floor', () {
    MarkdownBar bar(WidgetTester tester) => tester.widget<MarkdownBar>(
      find.byType(MarkdownBar, skipOffstage: false),
    );

    testWidgets('a freshly opened note has nothing to undo', (tester) async {
      final controller = await loadNote(tester);

      expect(controller.canUndo, isFalse);
      expect(bar(tester).canUndo, isFalse, reason: 'the button is disabled');

      // The bug: seeding was a revocable write over the empty document the
      // controller is constructed with, so this used to wipe the note.
      controller.undo();
      await tester.pump();

      expect(controller.text, content);
      await teardownPage(tester);
    });

    testWidgets('typing enables undo and undoing lands on the loaded text', (
      tester,
    ) async {
      final controller = await loadNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'first line'.length,
      );
      controller.replaceSelection(' typed');
      await tester.pump();

      expect(controller.canUndo, isTrue);
      expect(
        bar(tester).canUndo,
        isTrue,
        reason: 'the first edit after a load rebuilds the toolbar',
      );

      controller.undo();
      await tester.pump();
      expect(controller.text, content);
      expect(controller.canUndo, isFalse);
      expect(bar(tester).canUndo, isFalse);
      expect(bar(tester).canRedo, isTrue);

      controller.undo();
      await tester.pump();
      expect(controller.text, content, reason: 'never below the baseline');
      await teardownPage(tester);
    });
  });

  group('B1 — loading a note is not an edit', () {
    /// The page's auto-save runs on the shipped defaults, so a case about
    /// the debounce has to outlast the real one.
    const pastDebounce = Duration(seconds: 6);

    testWidgets('the loaded text is never written back', (tester) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      noteBloc.clearDispatched();

      // `loadText` fires the page's text listener exactly like a keystroke:
      // without a re-baseline the debounce rewrites the note it just read,
      // with a fresh updatedAt, version and HLC behind it.
      await tester.pump(pastDebounce);
      await settle(tester);

      expect(noteBloc.updates, isEmpty);
      expect(appBar(tester).hasChanges, isFalse);
      await teardownPage(tester);
    });

    testWidgets('an edit after the load still saves', (tester) async {
      final controller = await loadNote(tester);
      noteBloc.clearDispatched();

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'first line'.length,
      );
      controller.replaceSelection(' typed');
      await tester.pump();

      await tester.pump(pastDebounce);
      await settle(tester);

      expect(noteBloc.updates, hasLength(1));
      expect(noteBloc.updates.single.noteId, noteId);
      expect(noteBloc.updates.single.content, startsWith('first line typed'));
      await teardownPage(tester);
    });
  });

  group('B3 — one bloc, many editors', () {
    testWidgets('another note\'s content is not loaded over this one', (
      tester,
    ) async {
      await loadNote(tester);
      expect(editorOf(tester).controller.text, content);

      // The bloc is app-wide (main.dart registers one), and an editor
      // buried under another route stays mounted and listening.
      noteBloc.reset();
      await tester.pump();
      noteBloc.emitContentLoaded(otherMetadata, 'a completely different note');
      await tester.pump();
      await settle(tester);

      expect(editorOf(tester).controller.text, content);
      await teardownPage(tester);
    });
  });

  group('B7 — a route pushed over the editor flushes first', () {
    testWidgets('a pending edit is force-saved on push', (tester) async {
      final controller = await loadNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'first line'.length,
      );
      controller.replaceSelection(' typed');
      await tester.pump();
      noteBloc.clearDispatched();

      // The drawer's settings route leads to the database switcher, which
      // restarts the app: the debounce never gets to fire.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('settings stand-in')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);

      expect(noteBloc.updates, hasLength(1));
      expect(noteBloc.updates.single.content, startsWith('first line typed'));

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await teardownPage(tester);
    });
  });

  group('B3 — editor settings apply on the way back', () {
    testWidgets('a flag changed under a pushed route lands on pop', (
      tester,
    ) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settle(tester);
      expect(editorOf(tester).showLineNumbers, isFalse);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      // The editor keeps a cursor-blink timer running, so `pumpAndSettle`
      // would spin rather than settle: pump the transition by hand.
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('settings stand-in')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.runAsync(() => settings.setShowLineNumbers(true));
      // Still stale while the settings page is up — nothing has re-read.
      expect(editorOf(tester).showLineNumbers, isFalse);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settleUntil(tester, () => editorOf(tester).showLineNumbers);

      expect(editorOf(tester).showLineNumbers, isTrue);
      await teardownPage(tester);
    });
  });

  group('the edit tracker reads the page\'s fence index', () {
    // Line 2 is a list item as far as the list grammar is concerned, and
    // inert markdown as far as the document is concerned — only the page's
    // own line index knows which, so this is the wiring under test.
    const fencedContent =
        'intro\n'
        '```\n'
        '- squat 5x5\n'
        'code\n'
        '```\n'
        'tail';

    final fencedMetadata = NoteMetadata(
      id: noteId,
      folderId: folderId,
      title: 'Training log',
      preview: 'intro',
      contentLength: fencedContent.length,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    testWidgets('Enter on a list line inside a fence does not continue it', (
      tester,
    ) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(fencedMetadata, fencedContent);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      final controller = editorOf(tester).controller;

      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: '- squat 5x5'.length,
      );
      await tester.pump();

      controller.applyNewLine();
      await settle(tester, rounds: 4);

      expect(controller.codeLines[2].text, '- squat 5x5');
      expect(
        controller.codeLines[3].text,
        '',
        reason: 'a fenced `- ` is code, not a list to grow a marker on',
      );
      expect(controller.codeLines[4].text, 'code');
      await teardownPage(tester);
    });

    testWidgets('Enter on a list line outside the fence still continues', (
      tester,
    ) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(fencedMetadata, '- squat 5x5\n```\ncode\n```');
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      final controller = editorOf(tester).controller;

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: '- squat 5x5'.length,
      );
      await tester.pump();

      controller.applyNewLine();
      await settle(tester, rounds: 4);

      expect(controller.codeLines[1].text, '- ');
      await teardownPage(tester);
    });
  });

  group('C11 — the colour shortcut reflows what it inserted', () {
    /// One line far wider than any editor, so wrapping it in anything at
    /// all leaves a line the auto-break setting has to break.
    final wideContent = List<String>.filled(60, 'squat').join(' ');

    final wideMetadata = NoteMetadata(
      id: noteId,
      folderId: folderId,
      title: 'Training log',
      preview: 'squat',
      contentLength: wideContent.length,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    const colorShortcut = CustomMarkdownShortcut(
      id: 'default_color_text',
      label: 'colour',
      iconCodePoint: 0xe000,
      iconFontFamily: 'MaterialIcons',
      beforeText: '{red:',
      afterText: '}',
    );

    testWidgets('an over-wide selection wrapped in a colour is broken up', (
      tester,
    ) async {
      await tester.runAsync(() => settings.setAutoBreakLongLines(true));
      addTearDown(
        () => tester.runAsync(() => settings.setAutoBreakLongLines(false)),
      );

      await pumpPage(tester);
      noteBloc.emitContentLoaded(wideMetadata, wideContent);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      final controller = editorOf(tester).controller;
      expect(controller.codeLines.length, 1);

      controller.selection = CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: wideContent.length,
      );
      await tester.pump();

      tester
          .widget<MarkdownBar>(find.byType(MarkdownBar, skipOffstage: false))
          .onShortcutPressed(colorShortcut);
      await settle(tester, rounds: 4);

      expect(
        controller.codeLines.length,
        greaterThan(1),
        reason: 'the colour path reflows like Bold does, not never',
      );
      expect(controller.text.replaceAll('\n', ' '), '{red:$wideContent}');
      await teardownPage(tester);
    });
  });

  group('wiki links — tap, resolve, navigate', () {
    late Folder wikiFolder;
    late NoteMetadata target;

    setUp(() async {
      // Plain `async` rather than `tester.runAsync`: a group `setUp` runs
      // outside the widget test's fake clock, so a drift round trip here
      // simply completes.
      wikiFolder = await db.folderDao.createFolder(name: 'Wiki targets');
      target = await storageService.createNote(
        folderId: wikiFolder.id,
        title: 'Squat Progression',
        content: 'target',
      );
    });

    tearDown(() async {
      await db.noteDao.hardDeleteNote(target.id);
      await db.folderDao.hardDeleteFolder(wikiFolder.id);
    });

    testWidgets('a resolved wiki link saves the position and pushes the '
        'editor for that note', (tester) async {
      final controller = await loadAndPark(
        tester,
        'see [[Squat Progression]] now\nsecond line',
      );
      expect(pages(), findsOneWidget);

      // `see ` is four visible columns, then the seventeen glyphs of the
      // title: column 12.5 is its middle.
      await tester.tapAt(visiblePoint(tester, 0, 12.5));
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, target.id);
      expect(pushed.folderId, target.folderId);
      // The tap is intercepted, so the caret it saved is the one the user
      // left behind, not one the tap moved.
      expect(controller.selection.baseIndex, 1);
      final stored = await tester.runAsync(() => positions.getPosition(noteId));
      expect(stored!.editorLineIndex, 1);

      await popPushed(tester);
      await teardownPage(tester);
    });

    testWidgets('an unresolved wiki link shows the snackbar and pushes '
        'nothing', (tester) async {
      await loadAndPark(tester, 'see [[Nope]] now\nx');

      // `see ` plus the four glyphs of `Nope`: column 6 is its middle.
      await tester.tapAt(visiblePoint(tester, 0, 6));
      await tester.pump();
      await settleUntil(
        tester,
        () => find
            .text(AppLocalizationsEn().wikiLinkNoteNotFound('Nope'))
            .evaluate()
            .isNotEmpty,
      );

      expect(pages(), findsOneWidget);
      await teardownPage(tester);
    });

    testWidgets('a wiki link to the open note itself does nothing', (
      tester,
    ) async {
      // The page's own note is not in the database in this file, so the
      // self-link case has to seed it — under the title the metadata
      // carries, which is what the link has to name.
      await tester.runAsync(() async {
        await db.noteDao.insertNote(
          NotesCompanion.insert(
            id: noteId,
            folderId: wikiFolder.id,
            title: 'Training log',
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
          ),
        );
        // `insertNote` is the raw row write; the DAO's own create path
        // indexes right after it, and the seed has to as well. `notes_fts`
        // is an external-content FTS5 table, so hard-deleting a row that
        // was never indexed makes SQLite delete a term list that does not
        // exist — reported as a malformed database image.
        await db.customStatement(
          'INSERT OR REPLACE INTO notes_fts(rowid, title, preview) '
          'SELECT rowid, ?, ? FROM notes WHERE id = ?',
          ['Training log', '', noteId],
        );
      });

      final controller = await loadAndPark(
        tester,
        'see [[Training log]] now\nx',
      );

      // `see ` plus the twelve glyphs of `Training log`: column 10 is its
      // middle.
      await tester.tapAt(visiblePoint(tester, 0, 10));
      await tester.pump();
      await settle(tester);

      // The caret proves the tap was claimed rather than missed: a tap that
      // fell through to caret placement would have landed on line 0.
      expect(controller.selection.baseIndex, 1);
      expect(pages(), findsOneWidget, reason: 'no second editor on the row');
      expect(
        find.byType(SnackBar, skipOffstage: false),
        findsNothing,
        reason: 'a link that resolves is not a missing note',
      );

      await teardownPage(tester);
      // Later cases depend on the seeded note not existing.
      await tester.runAsync(() => db.noteDao.hardDeleteNote(noteId));
    });

    testWidgets('the title is trimmed before the lookup', (tester) async {
      await loadAndPark(tester, 'see [[  Squat Progression ]] now\nx');

      // `see ` plus the twenty glyphs of `  Squat Progression `: column 14
      // is its middle.
      await tester.tapAt(visiblePoint(tester, 0, 14));
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, target.id);

      await popPushed(tester);
      await teardownPage(tester);
    });
  });

  group('two editors on one note (C1) and tap races (B2, C11)', () {
    /// Real rows, not metadata stand-ins: the reload cases read the note
    /// back through the service on the way out of the pushed editor, and
    /// the tap cases resolve a title through it.
    late Folder stackFolder;
    late NoteMetadata host;
    late NoteMetadata linkTarget;

    const targetTitle = 'Deadlift Cues';

    setUp(() async {
      // Plain `async` rather than `tester.runAsync`, like the wiki group's:
      // a group `setUp` runs outside the widget test's fake clock, so a
      // drift round trip here simply completes.
      stackFolder = await db.folderDao.createFolder(name: 'Stacked editors');
      host = await storageService.createNote(
        folderId: stackFolder.id,
        title: 'Reload host',
        content: 'X',
      );
      linkTarget = await storageService.createNote(
        folderId: stackFolder.id,
        title: targetTitle,
        content: 'target',
      );
    });

    tearDown(() async {
      // Both rows went in through the service, so the DAO's create path
      // indexed them; hard-deleting an unindexed row out of the
      // external-content `notes_fts` table is what reads as a malformed
      // database image.
      await db.noteDao.hardDeleteNote(host.id);
      await db.noteDao.hardDeleteNote(linkTarget.id);
      await db.folderDao.hardDeleteFolder(stackFolder.id);
    });

    /// Pushes a second editor over the one already mounted — what a
    /// `[[wiki link]]` back to an open note does, minus the tap.
    NavigatorState pushEditor(
      WidgetTester tester, {
      required String folderId,
      required String noteId,
      NoteMetadata? metadata,
    }) {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => OptimizedNoteEditorPage(
            folderId: folderId,
            noteId: noteId,
            metadata: metadata,
          ),
        ),
      );
      return navigator;
    }

    /// The dirty flag of the page *under* whatever is on top: with two
    /// editors mounted there are two app bars, and the buried page's is the
    /// first one — the overlay renders the bottom route first.
    bool buriedHasChanges(WidgetTester tester) => tester
        .widgetList<NoteAppBar>(find.byType(NoteAppBar, skipOffstage: false))
        .first
        .hasChanges;

    testWidgets('a second editor for the same note leaves the buried page '
        'untouched', (tester) async {
      final buried = await loadNote(tester);
      buried.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'first line'.length,
      );
      buried.replaceSelection('!');
      await tester.pump();
      expect(buried.canUndo, isTrue);

      buried.selection = const CodeLineSelection.collapsed(index: 1, offset: 3);
      await tester.pump();

      final navigator = pushEditor(tester, folderId: folderId, noteId: noteId);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      // The pushed page is still on its placeholder: its editor mounts
      // only once the content *it* asked for lands.
      expect(editorFinder, findsOneWidget);

      // That answer, for the very note the buried page is showing — the
      // shape the id guard alone cannot tell apart (C1). `reset` first
      // because a bloc drops a state equal to the one it holds.
      noteBloc.reset();
      await tester.pump();
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().length == 2);
      await settle(tester);

      final wrappers = tester
          .widgetList<ModernEditorWrapper>(editorFinder)
          .toList();
      expect(
        identical(wrappers.first.controller, buried),
        isTrue,
        reason: 'the overlay renders the bottom route first',
      );
      expect(
        wrappers.last.controller.text,
        content,
        reason: 'the page that asked is the one that adopted',
      );

      expect(buried.text, startsWith('first line!'));
      expect(buried.selection.baseIndex, 1);
      expect(buried.selection.baseOffset, 3);
      expect(
        buried.canUndo,
        isTrue,
        reason: 'an adoption here would have restarted the undo history',
      );

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await teardownPage(tester);
    });

    testWidgets('returning to a buried editor reloads a note that changed '
        'underneath', (tester) async {
      await pumpPageFor(tester, host);
      noteBloc.emitContentLoaded(host, 'X');
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      final buried = editorOf(tester).controller;
      expect(buried.text, 'X');

      final navigator = pushEditor(
        tester,
        folderId: host.folderId,
        noteId: host.id,
        metadata: host,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      noteBloc.reset();
      await tester.pump();
      noteBloc.emitContentLoaded(host, 'X');
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().length == 2);
      await settle(tester);

      // What the editor on top would write, made directly through the
      // service so the case does not depend on that page's debounce.
      await tester.runAsync(
        () => storageService.updateNote(noteId: host.id, content: 'XY'),
      );
      expect(
        buried.text,
        'X',
        reason: 'the buried editor knows nothing about it yet',
      );

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // The reload is a service round trip started from `didPopNext`.
      await settleUntil(tester, () => buried.text == 'XY');

      expect(buried.text, 'XY');
      expect(
        appBar(tester).hasChanges,
        isFalse,
        reason: 'adopting the row is not an edit of it',
      );
      await teardownPage(tester);
    });

    testWidgets('an unchanged round trip keeps caret and undo', (tester) async {
      await pumpPageFor(tester, host);
      noteBloc.emitContentLoaded(host, 'X');
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      final buried = editorOf(tester).controller;

      buried.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
      buried.replaceSelection('Y');
      await tester.pump();
      expect(buried.text, 'XY');
      expect(buried.canUndo, isTrue);
      expect(buriedHasChanges(tester), isTrue);
      final caret = buried.selection;

      // The push force-saves (B7), so the row and the editor agree by the
      // time the pop asks for a reload — which is the case under test: the
      // guards let it through and it finds nothing to adopt.
      final navigator = pushEditor(
        tester,
        folderId: host.folderId,
        noteId: host.id,
        metadata: host,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settleUntil(tester, () => !buriedHasChanges(tester));
      expect(
        buriedHasChanges(tester),
        isFalse,
        reason: 'a dirty page skips the reload, which would pass vacuously',
      );
      expect(
        await tester.runAsync(() => storageService.loadNoteContent(host.id)),
        'XY',
        reason: 'the row the reload is about to read matches the editor',
      );

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);

      expect(buried.text, 'XY');
      expect(buried.selection.baseIndex, caret.baseIndex);
      expect(buried.selection.baseOffset, caret.baseOffset);
      expect(buried.canUndo, isTrue);

      // Not just the flag: the step itself is still there to take.
      buried.undo();
      await tester.pump();
      expect(buried.text, 'X');
      await teardownPage(tester);
    });

    testWidgets('two rapid taps on a wiki link push one editor', (
      tester,
    ) async {
      await loadAndPark(tester, 'see [[$targetTitle]] now\nsecond line');
      expect(pages(), findsOneWidget);
      noteBloc.clearDispatched();

      // Both taps get their whole round trip — the interceptor claims
      // every tap on the zone by design — so only the `isCurrent` check
      // after the awaits keeps the second one from pushing its own
      // editor (B2).
      final openWikiLink = editorOf(tester).onOpenWikiLink!;
      openWikiLink(targetTitle);
      openWikiLink(targetTitle);
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);
      // Long enough for a second push to have landed if one were coming.
      await settle(tester);

      expect(pages(), findsNWidgets(2));
      final loads = noteBloc.dispatched.whereType<LoadNoteContent>().toList();
      expect(loads, hasLength(1));
      expect(loads.single.noteId, linkTarget.id);

      await popPushed(tester);
      await teardownPage(tester);
    });

    testWidgets('a throwing lookup shows the error snackbar and pushes '
        'nothing', (tester) async {
      await loadAndPark(tester, 'see [[$targetTitle]] now\nx');

      GetIt.I.unregister<NoteStorageService>();
      GetIt.I.registerSingleton<NoteStorageService>(throwingStorage);
      try {
        // `see ` is four visible columns, then the thirteen glyphs of the
        // title: column 10.5 is its middle.
        await tester.tapAt(visiblePoint(tester, 0, 10.5));
        await tester.pump();
        await settleUntil(
          tester,
          () => find
              .text(AppLocalizationsEn().linkOpenFailed)
              .evaluate()
              .isNotEmpty,
        );

        expect(pages(), findsOneWidget, reason: 'a throw pushes nothing');
      } finally {
        GetIt.I.unregister<NoteStorageService>();
        GetIt.I.registerSingleton<NoteStorageService>(storageService);
      }
      await teardownPage(tester);
    });
  });

  group("the app bar's leading pair and its menu", () {
    late Folder menuFolder;
    late NoteMetadata menuNote;

    setUp(() async {
      menuFolder = await db.folderDao.createFolder(name: 'Training plans');
      menuNote = await storageService.createNote(
        folderId: menuFolder.id,
        title: 'Squat day',
        content: 'warm up',
      );
    });

    tearDown(() async {
      // The delete case already took the note out of the FTS index, and
      // asking the external-content table to drop the same row twice is
      // what reads as a malformed database image.
      final note = await db.noteDao.getNoteById(menuNote.id);
      if (note != null && !note.isDeleted) {
        await db.noteDao.hardDeleteNote(menuNote.id);
      } else if (note != null) {
        await (db.delete(db.notes)..where((n) => n.id.equals(note.id))).go();
      }
      await db.folderDao.hardDeleteFolder(menuFolder.id);
    });

    /// The editor pushed over a route stamped as this note's folder — the
    /// stack "Open folder" is meant to walk back to, and a page for delete
    /// to pop onto. The folder page itself is a stand-in: what the helper
    /// reads is the stamp, not the widget.
    Future<void> pushEditorOverFolder(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
            BlocProvider<MarkdownBarBloc>.value(value: barBloc),
            BlocProvider<CounterBloc>.value(value: counterBloc),
            BlocProvider<ImportExportBloc>.value(value: exportBloc),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [AppNavigator.routeObserver],
            home: const Scaffold(body: Text('root')),
          ),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final folder = NavDestination.folder(
        folderId: menuFolder.id,
        title: menuFolder.name,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('the folder below')),
          settings: RouteSettings(
            name: folder.kind.name,
            arguments: folder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => OptimizedNoteEditorPage(
            folderId: menuFolder.id,
            noteId: menuNote.id,
            metadata: menuNote,
          ),
        ),
      );
      await tester.pumpAndSettle();
      noteBloc.emitContentLoaded(menuNote, 'warm up');
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    testWidgets('the bar leads with the back arrow paired with the drawer', (
      tester,
    ) async {
      await pushEditorOverFolder(tester);

      expect(find.byType(LeadingNavPair), findsOneWidget);
      expect(find.byType(BackButtonIcon), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('the drawer half opens the editor drawer', (tester) async {
      await pushEditorOverFolder(tester);

      final scaffold = tester.state<ScaffoldState>(
        find.byType(Scaffold).last,
      );
      expect(scaffold.isDrawerOpen, isFalse);

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(scaffold.isDrawerOpen, isTrue);

      await teardownPage(tester);
    });

    testWidgets('the menu opens on the note folder, then the note actions', (
      tester,
    ) async {
      await pushEditorOverFolder(tester);
      await openMenu(tester);

      final l10n = AppLocalizationsEn();
      // The item's type argument is private to the menu widget, so the rows
      // are counted by predicate rather than by `byType`.
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        findsNWidgets(6),
      );
      expect(find.text(menuFolder.name), findsOneWidget);
      expect(find.text(l10n.openFolder), findsOneWidget);
      expect(find.text(l10n.editTitle), findsOneWidget);
      expect(find.text(l10n.moveToFolder), findsOneWidget);
      expect(find.text(l10n.shareNote), findsOneWidget);
      expect(find.text(l10n.deleteNote), findsOneWidget);
      expect(find.text(l10n.settings), findsOneWidget);

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    testWidgets('Open folder pops back to the page below', (tester) async {
      await pushEditorOverFolder(tester);
      await openMenu(tester);

      await tester.tap(find.text(AppLocalizationsEn().openFolder));
      await tester.pumpAndSettle();
      // The row saves before it pops, and that save is a real round trip.
      await settleUntil(tester, () => pages().evaluate().isEmpty);
      await tester.pumpAndSettle();

      expect(find.text('the folder below'), findsOneWidget);
      expect(pages(), findsNothing);
      await teardownPage(tester);
    });

    testWidgets('deleting dispatches the delete, saves nothing, and pops', (
      tester,
    ) async {
      await pushEditorOverFolder(tester);
      final controller = editorOf(tester).controller;
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'warm up'.length,
      );
      controller.replaceSelection(' more');
      await tester.pump();
      noteBloc.clearDispatched();

      await openMenu(tester);
      await tester.tap(find.text(AppLocalizationsEn().deleteNote));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await settle(tester);

      final deletes = noteBloc.dispatched
          .whereType<DeleteOptimizedNote>()
          .toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.noteId, menuNote.id);
      expect(
        pages(),
        findsNothing,
        reason: 'the page pops itself once the delete is dispatched',
      );
      // The unsaved edit above is deliberate: the exit save the page runs on
      // every other way out must not run on this one.
      expect(
        noteBloc.updates,
        isEmpty,
        reason: 'a save around the delete would write into a tombstone',
      );

      // Past the auto-save debounce, with the page still being torn down.
      await tester.pump(const Duration(seconds: 8));
      await settle(tester);
      expect(noteBloc.updates, isEmpty);

      await teardownPage(tester);
    });

    testWidgets('sharing goes through the import/export bloc, not the '
        'share sheet', (tester) async {
      await pushEditorOverFolder(tester);
      exportService.shared.clear();

      await openMenu(tester);
      await tester.tap(find.text(AppLocalizationsEn().shareNote));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsEn().exportAsMarkdown));
      await tester.pumpAndSettle();
      await settleUntil(tester, () => exportService.shared.isNotEmpty);

      expect(exportService.shared, hasLength(1));
      expect(exportService.shared.single.format, ExportFormat.markdown);

      await teardownPage(tester);
    });
  });
}

/// The real export service with only its last step stubbed: it still
/// encodes and writes the file, so the assertion is about what the editor
/// asked the bloc to export rather than about a mock's bookkeeping.
class _TestExportService extends ImportExportService {
  _TestExportService({
    required super.noteStorage,
    required super.folderStorage,
    required super.noteRepository,
  });

  final List<ExportResult> shared = <ExportResult>[];

  @override
  Future<void> shareExport(ExportResult result) async {
    shared.add(result);
    await cleanupExport(result);
  }
}

/// A [NoteStorageService] whose wiki-link lookup always fails, for the case
/// about the tap handler's own `try`. Everything else is the real service
/// over the real database.
class _ThrowingStorage extends NoteStorageService {
  _ThrowingStorage({required super.repository});

  @override
  Future<NoteMetadata?> resolveNoteByTitle(
    String title, {
    String? preferFolderId,
  }) async {
    throw StateError('resolveNoteByTitle failed');
  }
}

/// A real [OptimizedNoteBloc] whose content load is inert, so the test owns
/// the moment the note's text reaches the page. Everything else — the state
/// classes, the listener wiring, the page's own handling — stays real.
class _TestNoteBloc extends OptimizedNoteBloc {
  _TestNoteBloc({required super.storageService, required super.searchService});

  /// Every event the page dispatched, in order. The save cases assert on
  /// what the page *asked* for rather than on what the database ended up
  /// with, so they stay independent of whether the seeded note exists.
  final List<OptimizedNoteEvent> dispatched = <OptimizedNoteEvent>[];

  List<UpdateOptimizedNote> get updates =>
      dispatched.whereType<UpdateOptimizedNote>().toList();

  void clearDispatched() => dispatched.clear();

  @override
  void add(OptimizedNoteEvent event) {
    dispatched.add(event);
    if (event is LoadNoteContent) return;
    super.add(event);
  }

  void reset() {
    dispatched.clear();
    emit(OptimizedNoteInitial());
  }

  void emitContentLoaded(NoteMetadata metadata, String content) {
    emit(
      OptimizedNoteContentLoaded(
        note: LazyNote(
          metadata: metadata,
          content: content,
          isContentLoaded: true,
        ),
      ),
    );
  }
}
