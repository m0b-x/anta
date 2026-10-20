import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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
import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/controllers/note_editor_stats_tracker.dart';
import 'package:anta/widgets/overlay_snackbar.dart';
import 'package:anta/constants/font_constants.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/pages/optimized_note_editor_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/auto_save_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/note_position_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_editor_paint_spans.dart';
import 'package:anta/widgets/label_swatch_strip.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';
import 'package:anta/widgets/note_editor_chrome.dart';
import 'package:anta/widgets/note_search_bar.dart';
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
    await settings.setHapticFeedback(true);
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
    /// toggles the pair in with the caret between.
    CustomMarkdownShortcut wrapper(String text) => CustomMarkdownShortcut(
      id: 'test-wrap',
      label: 'test',
      iconCodePoint: 0xe000,
      iconFontFamily: 'MaterialIcons',
      beforeText: text,
      afterText: text,
    );

    /// A one-sided insert: the applier resolves it to [text] alone, so it
    /// is the simplest shortcut that goes through the resolved insert.
    CustomMarkdownShortcut insert(String text) => CustomMarkdownShortcut(
      id: 'test-insert',
      label: 'test',
      iconCodePoint: 0xe000,
      iconFontFamily: 'MaterialIcons',
      beforeText: text,
      afterText: '',
    );

    /// One of the H menu's items: the level is spelled by its marker.
    CustomMarkdownShortcut headerLevel(int level) => CustomMarkdownShortcut(
      id: 'header_level_$level',
      label: 'H$level',
      iconCodePoint: 0xe000,
      iconFontFamily: 'MaterialIcons',
      beforeText: '${'#' * level} ',
      afterText: '',
      insertType: 'header',
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
      expect(controller.codeLines[0].text, 'first line typed****');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(
          index: 0,
          offset: 'first line typed**'.length,
        ),
        reason: 'the caret lands between the pair',
      );

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

      press(tester, insert('\n'));
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

      // The bar's own button: it carries `# ` like the H1 menu item, but
      // it is the cycling one.
      const button = CustomMarkdownShortcut(
        id: 'default_header',
        label: 'header',
        iconCodePoint: 0xe000,
        iconFontFamily: 'MaterialIcons',
        beforeText: '# ',
        afterText: '',
        insertType: 'header',
      );
      press(tester, button);
      await settle(tester, rounds: 3);
      expect(controller.codeLines[0].text, '# first line');

      press(tester, button);
      await settle(tester, rounds: 3);
      expect(controller.codeLines[0].text, '## first line');
      expect(controller.codeLines[1].text, '- squat 5x5');
      await teardownPage(tester);
    });

    testWidgets('H3 picked on plain text gives a level-3 heading', (
      tester,
    ) async {
      final controller = await loadListNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );
      await tester.pump();

      press(tester, headerLevel(3));
      await settle(tester, rounds: 3);

      expect(controller.codeLines[0].text, '### first line');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 9),
        reason: 'the caret keeps its place in the text',
      );
      await teardownPage(tester);
    });

    testWidgets('H3 picked on an H3 line removes the heading', (tester) async {
      final controller = await loadListNote(tester);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      await tester.pump();

      press(tester, headerLevel(3));
      await settle(tester, rounds: 3);
      expect(controller.codeLines[0].text, '### first line');

      press(tester, headerLevel(3));
      await settle(tester, rounds: 3);
      expect(controller.codeLines[0].text, 'first line');
      await teardownPage(tester);
    });

    testWidgets('the H menu checks a setext heading and its pick removes it', (
      tester,
    ) async {
      final controller = await loadListNote(tester);
      controller.text = 'Week 3\n---\nafter';
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );
      await tester.pump();
      int? checked() => tester
          .widget<MarkdownBar>(find.byType(MarkdownBar, skipOffstage: false))
          .currentHeadingLevel!();
      expect(checked(), 2);

      press(tester, headerLevel(2));
      await settle(tester, rounds: 3);
      expect(controller.text, 'Week 3\nafter');
      expect(checked(), isNull);
      await teardownPage(tester);
    });

    testWidgets('the H menu reads a setext pair only where it is a heading', (
      tester,
    ) async {
      final controller = await loadListNote(tester);
      int? checkedAt(String text, int index) {
        controller.text = text;
        controller.selection = CodeLineSelection.collapsed(
          index: index,
          offset: 0,
        );
        return tester
            .widget<MarkdownBar>(find.byType(MarkdownBar, skipOffstage: false))
            .currentHeadingLevel!();
      }

      await tester.pump();
      expect(checkedAt('Week 3\n===\nafter', 1), 1, reason: 'the underline');
      expect(checkedAt('```\nWeek 3\n---\n```', 1), isNull);
      expect(checkedAt('%%\nWeek 3\n---\n%%', 1), isNull);
      expect(checkedAt('---\ntags: a\n---\n# H', 1), isNull);
      expect(checkedAt('---\ntags: a\n---\n# H', 2), isNull);
      // S2 C5 / U1 C15 — the editor's own reader: a fenced `#` line is
      // code, and a text line past the render cap draws no heading.
      expect(checkedAt('```\n# x\n```', 1), isNull);
      expect(checkedAt('${'a' * 5000}\n===\nafter', 1), isNull);
      expect(checkedAt('${'a' * 5000}\n===\nafter', 0), isNull);
      await teardownPage(tester);
    });

    testWidgets('a level picked on a fenced # line is inert; a capped '
        'underline takes an ATX run', (tester) async {
      final controller = await loadListNote(tester);
      final long = 'a' * 5000;
      for (final (text, index, after) in [
        ('```\n# x\n```', 1, '```\n# x\n```'),
        ('$long\n===\nafter', 1, '$long\n## ===\nafter'),
      ]) {
        controller.text = text;
        controller.selection = CodeLineSelection.collapsed(
          index: index,
          offset: 0,
        );
        await tester.pump();
        press(tester, headerLevel(2));
        await settle(tester, rounds: 3);
        expect(controller.text, after, reason: text.substring(0, 3));
      }
      await teardownPage(tester);
    });

    testWidgets('a list shortcut toggles the line marker as one undo step', (
      tester,
    ) async {
      final controller = await loadListNote(tester);

      // Mid-line on the bullet item: the checkbox swaps the marker at the
      // line start instead of landing at the caret.
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: '- squat'.length,
      );
      await tester.pump();

      const checkbox = CustomMarkdownShortcut(
        id: 'default_checkbox',
        label: 'Checkbox',
        iconCodePoint: 0xe000,
        iconFontFamily: 'MaterialIcons',
        beforeText: '- [ ] ',
        afterText: '',
        isDefault: true,
      );
      press(tester, checkbox);
      await settle(tester, rounds: 3);
      expect(controller.codeLines[1].text, '- [ ] squat 5x5');

      press(tester, checkbox);
      await settle(tester, rounds: 3);
      expect(controller.codeLines[1].text, 'squat 5x5');

      controller.undo();
      await tester.pump();
      expect(
        controller.codeLines[1].text,
        '- [ ] squat 5x5',
        reason: 'one undo reverts one toggle',
      );
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

  group('the title fallback', () {
    // The folder opens an existing note with its metadata, whose title
    // seeds the page's title field; the folder lists a note saved without
    // a title as "Untitled Note", and the editor once called the same note
    // "New Note" on reopening, so one note carried two names (device pass,
    // 2026-10-21). "New Note" is for a page opened with no note id.
    Future<void> open(WidgetTester tester, NoteMetadata note) async {
      await pumpPageFor(tester, note);
      noteBloc.emitContentLoaded(note, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
    }

    testWidgets('a saved note reopened without a title is named as the '
        'folder lists it', (tester) async {
      await open(
        tester,
        NoteMetadata(
          id: noteId,
          folderId: folderId,
          title: '',
          preview: 'first line',
          contentLength: content.length,
          chunkCount: 1,
          isCompressed: false,
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(appBar(tester).title, l10n.untitledNote);
      expect(appBar(tester).title, isNot(l10n.newNote));
      await teardownPage(tester);
    });

    testWidgets('a titled note keeps its title', (tester) async {
      await open(tester, metadata);
      expect(appBar(tester).title, 'Training log');
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

    testWidgets('U2.3 a caret move is not an edit', (tester) async {
      final controller = await loadNote(tester);
      noteBloc.clearDispatched();

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );
      await tester.pump();
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: 5,
      );
      await tester.pump();
      expect(appBar(tester).hasChanges, isFalse);

      await tester.pump(pastDebounce);
      await settle(tester);

      expect(noteBloc.updates, isEmpty);
      expect(appBar(tester).hasChanges, isFalse);
      await teardownPage(tester);
    });

    testWidgets('U2.3 a same-length replacement is still an edit', (
      tester,
    ) async {
      final controller = await loadNote(tester);
      noteBloc.clearDispatched();

      // 'f' -> 'F': the text length does not move, the lines instance does.
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: 1,
      );
      await tester.pump();
      controller.replaceSelection('F');
      await tester.pump();

      expect(appBar(tester).hasChanges, isTrue);
      await tester.pump(pastDebounce);
      await settle(tester);
      expect(noteBloc.updates, hasLength(1));
      await teardownPage(tester);
    });

    testWidgets('an opened note reads as saved from the frame its editor '
        'appears — mounting the editor is not an edit either', (tester) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);

      // Well inside the debounce: the fork's controller handoff used to
      // announce itself to the page from the editor's `initState`, and the
      // note then wore the unsaved dot until the debounce found nothing to
      // write, five seconds after every open.
      expect(appBar(tester).hasChanges, isFalse);
      expect(appBar(tester).saveStatusNotifier!.value, SaveStatus.saved);
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

    testWidgets('live rendering toggled under a pushed route remounts the '
        'editor, and the remount neither edits the note nor dirties the app '
        'bar mid-build', (tester) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadata, content);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      final mounted = editorStateOf(tester);
      expect(appBar(tester).saveStatusNotifier!.value, SaveStatus.saved);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('settings stand-in')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => settings.setLiveMarkdownRendering(false));

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // The flag is the editor's key, so landing it is a remount: a new
      // `CodeEditor` attaches to the page's controller while the status is
      // `saved` and the app bar's builder is already clean. That is the
      // frame "setState() or markNeedsBuild() called during build" came
      // from.
      await settleUntil(
        tester,
        () => !identical(editorStateOf(tester), mounted),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(editorOf(tester).key, const ValueKey('editor'));
      expect(appBar(tester).hasChanges, isFalse);
      expect(appBar(tester).saveStatusNotifier!.value, SaveStatus.saved);
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
        () => tester.runAsync(
          () => settings.setAutoBreakLongLines(
            SettingsKeys.defaultAutoBreakLongLines,
          ),
        ),
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

    testWidgets('an aliased link shows the alias and opens the title', (
      tester,
    ) async {
      await loadAndPark(tester, 'see [[Squat Progression|squats]] now\nx');

      // `see ` plus the six glyphs of the alias — the title is concealed
      // chrome: column 7 is the alias's middle.
      await tester.tapAt(visiblePoint(tester, 0, 7));
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, target.id);
      expect(pushed.targetHeading, isNull);

      await popPushed(tester);
      await teardownPage(tester);
    });

    testWidgets('a heading suffix opens the note and hands the heading on', (
      tester,
    ) async {
      await loadAndPark(tester, 'x\ny');

      editorOf(tester).onOpenWikiLink!(' Squat Progression # Warm-up ');
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, target.id);
      expect(pushed.targetHeading, 'Warm-up');

      await popPushed(tester);
      await teardownPage(tester);
    });

    testWidgets('a trailing .md resolves the note it names', (tester) async {
      await loadAndPark(tester, 'x\ny');

      editorOf(tester).onOpenWikiLink!('Squat Progression.md');
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, target.id);
      expect(pushed.targetHeading, isNull);

      await popPushed(tester);
      await teardownPage(tester);
    });

    testWidgets('a bare heading centres it in this note without moving the '
        'caret', (tester) async {
      final text = <String>[
        'see [[#Cool-down]] now',
        for (var i = 0; i < 120; i++) 'line $i',
        '## Cool-down',
        'end',
      ].join('\n');
      final controller = await loadAndPark(tester, text);
      final scroller = editorOf(tester).scrollController.verticalScroller;
      expect(scroller.position.pixels, 0.0);

      editorOf(tester).onOpenWikiLink!('#cool-down');
      await settle(tester);

      expect(scroller.position.pixels, greaterThan(0.0));
      final render = CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      );
      expect(render.displayedLineIndices, contains(121));
      expect(controller.selection.baseIndex, 1);
      expect(pages(), findsOneWidget);
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
      await teardownPage(tester);
    });

    /// Mounts the page over this file's note with [heading] as its target,
    /// the way a `[[Note#heading]]` tap pushes it.
    Future<void> pumpPageWithHeading(WidgetTester tester, String heading) {
      return tester.pumpWidget(
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
              folderId: folderId,
              noteId: noteId,
              targetHeading: heading,
            ),
          ),
        ),
      );
    }

    final headedContent = <String>[
      'top',
      for (var i = 0; i < 200; i++) 'line $i',
      '```',
      '## Cool-down',
      '```',
      for (var i = 0; i < 100; i++) 'more $i',
      '##   cool-DOWN  ',
      'end',
    ].join('\n');

    testWidgets('a target heading replaces the restored position in the '
        "editor's first frame", (tester) async {
      await savePosition(tester, 2, 1);
      await pumpPageWithHeading(tester, 'Cool-down');
      noteBloc.emitContentLoaded(metadata, headedContent);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      // The fenced `## Cool-down` is code, not a heading; the real one
      // matches trimmed and case-insensitively.
      const headingLine = 1 + 200 + 3 + 100;
      final render = CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      );
      expect(render.displayedLineIndices, contains(headingLine));
      expect(editorOf(tester).controller.selection.baseIndex, headingLine);

      // Later gate callers (a settings reload) never drag it back.
      editorOf(tester).controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      await settle(tester);
      expect(editorOf(tester).controller.selection.baseIndex, 0);
      await teardownPage(tester);
    });

    testWidgets('a heading the note does not hold keeps the restored '
        'position', (tester) async {
      await savePosition(tester, 2, 1);
      await pumpPageWithHeading(tester, 'Nowhere');
      noteBloc.emitContentLoaded(metadata, headedContent);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settleUntil(tester, () => caretLine(tester) == 2);

      expect(editorOf(tester).controller.selection.baseOffset, 1);
      await teardownPage(tester);
    });

    testWidgets('a heading that holds a hash is found by the whole fragment '
        'before its last segment', (tester) async {
      await pumpPageWithHeading(tester, 'Week #3');
      noteBloc.emitContentLoaded(
        metadata,
        <String>[
          'top',
          '## 3',
          for (var i = 0; i < 150; i++) 'line $i',
          '## Week #3',
          'end',
        ].join('\n'),
      );
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      expect(editorOf(tester).controller.selection.baseIndex, 152);
      await teardownPage(tester);
    });

    testWidgets('a heading matches by the text it shows: markup and a '
        'closing hash run dropped', (tester) async {
      await pumpPageWithHeading(tester, 'squat DAY');
      noteBloc.emitContentLoaded(
        metadata,
        <String>[
          'top',
          for (var i = 0; i < 150; i++) 'line $i',
          '## **Squat** {red:day} ##',
          'end',
        ].join('\n'),
      );
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      expect(editorOf(tester).controller.selection.baseIndex, 151);
      await teardownPage(tester);
    });

    testWidgets('a setext heading is a target too, by its text line', (
      tester,
    ) async {
      await pumpPageWithHeading(tester, 'squat DAY');
      noteBloc.emitContentLoaded(
        metadata,
        <String>[
          'top',
          for (var i = 0; i < 150; i++) 'line $i',
          '**Squat** day',
          '---',
          'end',
        ].join('\n'),
      );
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      expect(editorOf(tester).controller.selection.baseIndex, 151);
      await teardownPage(tester);
    });

    testWidgets('a front matter property or a commented pair is no target', (
      tester,
    ) async {
      await pumpPageWithHeading(tester, 'tags: a');
      noteBloc.emitContentLoaded(
        metadata,
        <String>[
          '---',
          'tags: a',
          '---',
          '%%',
          'tags: a',
          '---',
          '%%',
          for (var i = 0; i < 150; i++) 'line $i',
          'tags: a',
          '===',
          'end',
        ].join('\n'),
      );
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      expect(editorOf(tester).controller.selection.baseIndex, 157);
      await teardownPage(tester);
    });

    // C1 fix pass P14 — the target reads the editor's heading reader, so a
    // match the editor draws as no heading (fenced, past the render cap)
    // keeps the restored position.
    testWidgets('a fenced or capped match is no target', (tester) async {
      final long = 'a' * 5000;
      await savePosition(tester, 2, 1);
      await pumpPageWithHeading(tester, long);
      noteBloc.emitContentLoaded(
        metadata,
        <String>[
          'top',
          for (var i = 0; i < 150; i++) 'line $i',
          '```',
          '# $long',
          '```',
          long,
          '===',
          '# $long',
          'end',
        ].join('\n'),
      );
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settleUntil(tester, () => caretLine(tester) == 2);

      expect(editorOf(tester).controller.selection.baseOffset, 1);
      await teardownPage(tester);
    });

    // One closing run comes off, never two: `## Foo # ##` shows `Foo #`.
    testWidgets('a heading whose content ends in a lone hash is not the '
        'target of its stem', (tester) async {
      await pumpPageWithHeading(tester, 'Foo');
      noteBloc.emitContentLoaded(
        metadata,
        <String>[
          'top',
          for (var i = 0; i < 150; i++) 'line $i',
          '## Foo # ##',
          '## Foo',
          'end',
        ].join('\n'),
      );
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);

      expect(editorOf(tester).controller.selection.baseIndex, 152);
      await teardownPage(tester);
    });

    testWidgets('a later gate call never drags the caret back to the target '
        'heading', (tester) async {
      await pumpPageWithHeading(tester, 'Cool-down');
      noteBloc.emitContentLoaded(metadata, headedContent);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      const headingLine = 1 + 200 + 3 + 100;
      expect(editorOf(tester).controller.selection.baseIndex, headingLine);

      editorOf(tester).controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      // A settings change re-runs the page's ready gate; the latch is all
      // that keeps the heading from landing a second time. Up and back
      // down, so the stored size is the default again for later cases.
      final bar = tester.widget<MarkdownBar>(
        find.byType(MarkdownBar, skipOffstage: false),
      );
      bar.onIncreaseFontSize();
      await tester.pump();
      bar.onDecreaseFontSize();
      await tester.pump(
        SettingsService.defaultWriteDebounce + const Duration(milliseconds: 50),
      );
      await settle(tester);

      expect(editorOf(tester).controller.selection.baseIndex, 0);
      await teardownPage(tester);
    });

    testWidgets('a suffixed link to the open note centres the heading in '
        'place', (tester) async {
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
        // Indexed as the self-link case explains: hard-deleting a row
        // `notes_fts` never saw reads as a malformed database image.
        await db.customStatement(
          'INSERT OR REPLACE INTO notes_fts(rowid, title, preview) '
          'SELECT rowid, ?, ? FROM notes WHERE id = ?',
          ['Training log', '', noteId],
        );
      });
      final text = <String>[
        'see [[Training log#Cool-down]] now',
        for (var i = 0; i < 120; i++) 'line $i',
        '## Cool-down',
        'end',
      ].join('\n');
      final controller = await loadAndPark(tester, text);
      final scroller = editorOf(tester).scrollController.verticalScroller;
      expect(scroller.position.pixels, 0.0);

      editorOf(tester).onOpenWikiLink!('Training log#Cool-down');
      await tester.pump();
      await settleUntil(tester, () => scroller.position.pixels > 0.0);

      final render = CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      );
      expect(render.displayedLineIndices, contains(121));
      expect(controller.selection.baseIndex, 1);
      expect(pages(), findsOneWidget);
      expect(find.byType(SnackBar, skipOffstage: false), findsNothing);

      await teardownPage(tester);
      await tester.runAsync(() => db.noteDao.hardDeleteNote(noteId));
    });

    testWidgets('a note whose own name holds a hash wins over its note part', (
      tester,
    ) async {
      final hashed = (await tester.runAsync(
        () => storageService.createNote(
          folderId: wikiFolder.id,
          title: 'Squat Progression#Warm-up',
          content: 'hashed',
        ),
      ))!;
      await loadAndPark(tester, 'x\ny');

      editorOf(tester).onOpenWikiLink!('Squat Progression#Warm-up');
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, hashed.id);
      expect(pushed.targetHeading, isNull);

      await popPushed(tester);
      await teardownPage(tester);
      await tester.runAsync(() => db.noteDao.hardDeleteNote(hashed.id));
    });

    testWidgets('a block reference opens the note with no heading', (
      tester,
    ) async {
      await loadAndPark(tester, 'x\ny');

      editorOf(tester).onOpenWikiLink!('Squat Progression^abc');
      await tester.pump();
      await settleUntil(tester, () => pages().evaluate().length == 2);

      final pushed = tester.widgetList<OptimizedNoteEditorPage>(pages()).last;
      expect(pushed.noteId, target.id);
      expect(pushed.targetHeading, isNull);

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
          settings: RouteSettings(name: folder.kind.name, arguments: folder),
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

    /// [pushEditorOverFolder] for a note that does not exist yet: no id, no
    /// metadata, nothing to label until the early create lands.
    Future<void> pushNewNoteEditor(WidgetTester tester) async {
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
            home: OptimizedNoteEditorPage(folderId: menuFolder.id),
          ),
        ),
      );
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
    }

    /// Types [text] at the caret, the way the delete case does — the edit has
    /// to go through the controller for the save coordinator to see it.
    Future<void> type(WidgetTester tester, String text) async {
      final controller = editorOf(tester).controller;
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      controller.replaceSelection(text);
      await tester.pump();
    }

    /// Opens the menu and its Label row, waiting for the fresh metadata read
    /// the handler does before it can show the sheet.
    Future<void> openLabelSheet(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text(AppLocalizationsEn().labelAction));
      await tester.pumpAndSettle();
      await settleUntil(
        tester,
        () => find.byType(LabelSwatchStrip).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
    }

    /// Takes notes an early create left behind back out of the database, so
    /// the folder this group hard-deletes in `tearDown` is empty.
    Future<void> discardNotes(WidgetTester tester, List<String> ids) async {
      for (final id in ids) {
        await tester.runAsync(() => db.noteDao.hardDeleteNote(id));
      }
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

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).last);
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
        findsNWidgets(7),
      );
      expect(find.text(menuFolder.name), findsOneWidget);
      expect(find.text(l10n.openFolder), findsOneWidget);
      expect(find.text(l10n.editTitle), findsOneWidget);
      expect(find.text(l10n.moveToFolder), findsOneWidget);
      expect(find.text(l10n.labelAction), findsOneWidget);
      expect(find.text(l10n.shareNote), findsOneWidget);
      expect(find.text(l10n.deleteNote), findsOneWidget);
      expect(find.text(l10n.settings), findsOneWidget);
      // Appearance sits with move, ahead of sharing and deleting.
      expect(
        tester.getCenter(find.text(l10n.labelAction)).dy,
        inExclusiveRange(
          tester.getCenter(find.text(l10n.moveToFolder)).dy,
          tester.getCenter(find.text(l10n.shareNote)).dy,
        ),
      );

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    PopupMenuItem labelItem(WidgetTester tester) =>
        tester.widget(
              find.ancestor(
                of: find.text(AppLocalizationsEn().labelAction),
                matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
              ),
            )
            as PopupMenuItem;

    testWidgets('a brand-new note shows the Label row disabled (U2.8)', (
      tester,
    ) async {
      await pushNewNoteEditor(tester);
      await openMenu(tester);

      final l10n = AppLocalizationsEn();
      // Disabled, never removed: the menu keeps its shape before and after
      // the early create.
      expect(find.text(l10n.labelAction), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        findsNWidgets(7),
      );
      expect(
        labelItem(tester).enabled,
        isFalse,
        reason: 'a note with no id has no row to carry a colour',
      );

      await tester.tap(find.text(l10n.labelAction), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(noteBloc.dispatched.whereType<SetOptimizedNoteLabel>(), isEmpty);
      expect(find.text(l10n.labelAction), findsOneWidget);

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
    });

    testWidgets('the Label row appears once the early create lands', (
      tester,
    ) async {
      await pushNewNoteEditor(tester);
      final created = <String>[];
      final sub = noteBloc.stream.listen((state) {
        if (state is OptimizedNoteCreated) created.add(state.metadata.id);
      });
      addTearDown(sub.cancel);

      await openMenu(tester);
      expect(labelItem(tester).enabled, isFalse);
      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();

      await type(tester, 'bench press');
      await settleUntil(
        tester,
        () =>
            noteBloc.dispatched.whereType<CreateOptimizedNote>().isNotEmpty &&
            created.isNotEmpty,
      );
      await settle(tester);

      await openMenu(tester);

      expect(
        find.text(AppLocalizationsEn().labelAction),
        findsOneWidget,
        reason: 'adopting the new id has to rebuild the bar that reads it',
      );
      expect(
        labelItem(tester).enabled,
        isTrue,
        reason: 'adopting the new id has to rebuild the bar that reads it',
      );

      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await teardownPage(tester);
      await discardNotes(tester, created);
    });

    testWidgets('U2.2 a rename to a taken title warns in the dialog, and the '
        'reverted save puts the stored title back in the bar', (tester) async {
      // Drift runs outside the test's fake clock.
      final sibling = (await tester.runAsync(
        () => storageService.createNote(
          folderId: menuFolder.id,
          title: 'Bench day',
          content: '',
        ),
      ))!;
      addTearDown(
        () => tester.runAsync(() => db.noteDao.hardDeleteNote(sibling.id)),
      );
      await pushEditorOverFolder(tester);
      final l10n = AppLocalizationsEn();

      await tester.tap(find.text(menuNote.title));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(field).controller!.selection,
        TextSelection(baseOffset: 0, extentOffset: menuNote.title.length),
        reason: 'the title opens selected whole, so typing replaces it',
      );

      await tester.enterText(field, 'Bench day');
      final warning = find.text(l10n.noteTitleAlreadyExists('Bench day'));
      await settleUntil(tester, () => warning.evaluate().isNotEmpty);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.save),
        ),
      );
      await tester.pumpAndSettle();
      expect(appBar(tester).title, 'Bench day');

      await tester.pump(const Duration(seconds: 6));
      await settleUntil(tester, () => appBar(tester).title == menuNote.title);
      expect(find.text('Bench day'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      await teardownPage(tester);
    });

    testWidgets('picking a swatch dispatches SetOptimizedNoteLabel once', (
      tester,
    ) async {
      await pushEditorOverFolder(tester);
      noteBloc.clearDispatched();

      await openLabelSheet(tester);
      expect(find.byType(LabelSwatchStrip), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(AppLocalizationsEn().labelRed));
      await tester.pumpAndSettle();
      await settle(tester);

      final picks = noteBloc.dispatched
          .whereType<SetOptimizedNoteLabel>()
          .toList();
      expect(picks, hasLength(1));
      expect(picks.single.noteId, menuNote.id);
      expect(picks.single.label, ItemLabel.red);
      expect(find.byType(LabelSwatchStrip), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('picking the current value dispatches nothing', (tester) async {
      await pushEditorOverFolder(tester);
      // Written *after* the push, so `widget.metadata` still says "none":
      // the sheet has to read the row rather than the value it was handed.
      await tester.runAsync(
        () => storageService.setNoteLabel(menuNote.id, ItemLabel.red),
      );
      noteBloc.clearDispatched();

      await openLabelSheet(tester);

      expect(
        tester.widget<LabelSwatchStrip>(find.byType(LabelSwatchStrip)).value,
        ItemLabel.red,
      );

      await tester.tap(find.bySemanticsLabel(AppLocalizationsEn().labelRed));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(noteBloc.dispatched.whereType<SetOptimizedNoteLabel>(), isEmpty);
      expect(find.byType(LabelSwatchStrip), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('dismissing the sheet dispatches nothing', (tester) async {
      await pushEditorOverFolder(tester);
      noteBloc.clearDispatched();

      await openLabelSheet(tester);
      await tester.tapAt(const Offset(400, 8));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(noteBloc.dispatched.whereType<SetOptimizedNoteLabel>(), isEmpty);
      expect(find.byType(LabelSwatchStrip), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('labelling a deleted note says so instead of opening the '
        'sheet', (tester) async {
      // A second editor over the same note — a `[[wiki link]]` back to A —
      // can delete it and pop onto this one, and a merge can tombstone it
      // outright. The row is still readable, so only the service's tombstone
      // guard stands between the menu and a write the DAO refuses in silence.
      await pushEditorOverFolder(tester);
      await tester.runAsync(() => storageService.deleteNote(menuNote.id));
      noteBloc.clearDispatched();

      await openMenu(tester);
      await tester.tap(find.text(AppLocalizationsEn().labelAction));
      await tester.pumpAndSettle();
      await settleUntil(
        tester,
        () =>
            find.text(AppLocalizationsEn().noteNotFound).evaluate().isNotEmpty,
      );

      expect(find.byType(LabelSwatchStrip), findsNothing);
      // The editor lays itself out around the keyboard, so its notices ride
      // the overlay road, never a Scaffold's SnackBar.
      expect(find.byType(OverlaySnackbarBody), findsOneWidget);
      expect(noteBloc.dispatched.whereType<SetOptimizedNoteLabel>(), isEmpty);

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

    testWidgets('two fast Back taps pop the editor once', (tester) async {
      // D-2: the handler awaits the exit save, and a second Back arriving
      // inside that await used to run the whole exit again — taking the
      // folder page underneath with it.
      await pushEditorOverFolder(tester);

      await tester.tap(find.byType(BackButtonIcon));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.tap(find.byType(BackButtonIcon), warnIfMissed: false);
      await tester.pumpAndSettle();
      await settleUntil(tester, () => pages().evaluate().isEmpty);
      await tester.pumpAndSettle();

      expect(pages(), findsNothing);
      expect(find.text('the folder below'), findsOneWidget);
      expect(find.text('root'), findsNothing);

      await teardownPage(tester);
    });

    testWidgets('Back with the drawer open closes the drawer and leaves the '
        'page able to exit', (tester) async {
      // A drawer adds a local-history entry to the route, but the page's
      // `PopScope(canPop: false)` still wins `popDisposition`, so the Back
      // reaches the exit handler; its pop must close the drawer and must not
      // leave the exit latch set on a page that is still showing.
      await pushEditorOverFolder(tester);

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).last);
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isFalse);
      expect(pages(), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await settleUntil(tester, () => pages().evaluate().isEmpty);
      await tester.pumpAndSettle();

      expect(pages(), findsNothing);
      expect(find.text('the folder below'), findsOneWidget);

      await teardownPage(tester);
    });

    testWidgets('U2.7 the app bar toggle focuses the open field; the row X '
        'is the one way out', (tester) async {
      await pushEditorOverFolder(tester);
      final toggle = find.descendant(
        of: find.byType(NoteAppBar),
        matching: find.byIcon(Icons.search),
      );
      final focusedField = find.descendant(
        of: find.byType(NoteSearchBar),
        matching: find.byWidgetPredicate(
          (w) => w is EditableText && w.focusNode.hasFocus,
        ),
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(NoteSearchBar), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(focusedField, findsNothing);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byType(NoteSearchBar), findsOneWidget);
      expect(focusedField, findsOneWidget);

      await tester.tap(find.byTooltip(AppLocalizationsEn().closeSearch));
      await tester.pumpAndSettle();

      expect(find.byType(NoteSearchBar), findsNothing);
      expect(toggle, findsOneWidget);

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

  /// The ids an accessibility-tree driver targets. The editor's own nodes —
  /// one per visible line plus the text field — must survive the annotation,
  /// which is why it is an explicit-children container rather than a merge.
  group('editor quality of life (R2a)', () {
    const taskContent = '- [ ] squat 5x5\nplain line';
    const listContent = 'first line\n- squat 5x5\nthird line';
    final tallContent = List.generate(60, (i) => 'line $i').join('\n');

    Future<CodeLineEditingController> loadText(
      WidgetTester tester,
      String text,
    ) async {
      await pumpPage(tester);
      noteBloc.emitContentLoaded(metadataFor(text), text);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      return editorOf(tester).controller;
    }

    MarkdownBar bar(WidgetTester tester) => tester.widget<MarkdownBar>(
      find.byType(MarkdownBar, skipOffstage: false),
    );

    FocusNode focusOf(WidgetTester tester) => editorOf(tester).focusNode;

    /// Lets the debounced font-size write out (fake clock), then lets its
    /// statement complete (real clock), so no timer outlives the test.
    Future<void> flushFontSizeWrite(WidgetTester tester) async {
      await tester.pump(
        SettingsService.defaultWriteDebounce + const Duration(milliseconds: 50),
      );
      await settle(tester);
    }

    double scrollOffset(WidgetTester tester) =>
        editorOf(tester).scrollController.verticalScroller.offset;

    /// A focus change applies in a microtask after the first pump's frame,
    /// so whatever it rebuilds lands one frame later.
    Future<void> focusEditor(WidgetTester tester) async {
      focusOf(tester).requestFocus();
      await tester.pump();
      await tester.pump();
    }

    /// Asks the page's own span builder for line [index] as it would render
    /// now. The reveal predicate is read at call time, so this is what the
    /// editor lays out on its next pass.
    bool paintsBox(WidgetTester tester, int index) {
      final controller = editorOf(tester).controller;
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(CodeEditor, skipOffstage: false)),
        index: index,
        textSpan: TextSpan(text: controller.codeLines[index].text),
        style: const TextStyle(fontSize: FontConstants.defaultFontSize),
      );
      var found = false;
      span.visitChildren((child) {
        if (child is EditorCheckboxSpan) found = true;
        return !found;
      });
      return found;
    }

    testWidgets('E5: an unfocused editor conceals the caret line and its box '
        'toggles without raising focus', (tester) async {
      final controller = await loadText(tester, taskContent);
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 0),
        reason: 'a note with no saved position opens at the top',
      );
      expect(focusOf(tester).hasFocus, isFalse);
      expect(paintsBox(tester, 0), isTrue, reason: 'nothing reveals line 0');

      final lineBox = CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      ).lineHeight;
      await tester.tapAt(
        tester.getTopLeft(find.byType(CodeEditor)) +
            Offset(AppSpacing.xl + 2, AppSpacing.lg + lineBox / 2),
      );
      await tester.pump();

      expect(controller.codeLines[0].text, '- [x] squat 5x5');
      expect(
        focusOf(tester).hasFocus,
        isFalse,
        reason: 'a toggle never focuses',
      );

      await focusEditor(tester);
      expect(
        paintsBox(tester, 0),
        isFalse,
        reason: 'with focus the caret line reveals its raw marker',
      );
      await teardownPage(tester);
    });

    testWidgets('E4: the bar\'s Paste focuses the editor and inserts at the '
        'caret', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': 'pasted '}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final controller = await loadText(tester, content);
      expect(focusOf(tester).hasFocus, isFalse);

      bar(tester).onPaste!();
      await tester.pump();
      await tester.pump();

      expect(focusOf(tester).hasFocus, isTrue);
      expect(controller.codeLines[0].text, 'pasted first line');
      await teardownPage(tester);
    });

    CustomMarkdownShortcut heading(int level) => CustomMarkdownShortcut(
      id: 'header_level_$level',
      label: 'H$level',
      iconCodePoint: 0xe167,
      iconFontFamily: 'MaterialIcons',
      beforeText: '${'#' * level} ',
      afterText: '',
      isDefault: true,
      insertType: 'header',
    );

    // U2.1: a bar edit on an unfocused editor focuses it first, or the
    // edit lands with no caret on screen and no keyboard to go on with.
    testWidgets('U2.1: Bold, Indent and the H menu focus an unfocused editor '
        'and edit at the caret', (tester) async {
      final controller = await loadText(tester, listContent);
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 11,
      );
      await tester.pump();

      Future<void> unfocus() async {
        focusOf(tester).unfocus();
        await tester.pump();
        await tester.pump();
        expect(focusOf(tester).hasFocus, isFalse);
      }

      await unfocus();
      bar(tester).onIndent!();
      await tester.pump();
      await tester.pump();
      expect(focusOf(tester).hasFocus, isTrue, reason: 'indent');
      expect(controller.codeLines[1].text, '  - squat 5x5');

      await unfocus();
      bar(tester).onShortcutPressed(
        const CustomMarkdownShortcut(
          id: 'default_bold',
          label: 'Bold',
          iconCodePoint: 0xe238,
          iconFontFamily: 'MaterialIcons',
          beforeText: '**',
          afterText: '**',
          isDefault: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(focusOf(tester).hasFocus, isTrue, reason: 'bold');
      expect(controller.codeLines[1].text, contains('**'));

      await unfocus();
      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: 0,
      );
      bar(tester).onShortcutPressed(heading(2));
      await tester.pump();
      await tester.pump();
      expect(focusOf(tester).hasFocus, isTrue, reason: 'H menu');
      expect(controller.codeLines[2].text, '## third line');
      await teardownPage(tester);
    });

    // U1 T10: Body text is the caret line's own level picked again, the
    // path the bar's menu takes; both heading shapes come off.
    for (final (name, text, index, expected) in [
      (
        'an ATX heading with a closing run',
        'intro\n## Squat ##',
        1,
        'intro\nSquat',
      ),
      ('a setext heading', 'Squat\n===\nafter', 0, 'Squat\nafter'),
    ]) {
      testWidgets('U1: Body text removes $name', (tester) async {
        final controller = await loadText(tester, text);
        controller.selection = CodeLineSelection.collapsed(
          index: index,
          offset: 0,
        );
        await tester.pump();

        final level = bar(tester).currentHeadingLevel!();
        expect(level, isNotNull);
        bar(tester).onShortcutPressed(heading(level!));
        await tester.pump();
        await tester.pump();

        expect(controller.text, expected);
        await teardownPage(tester);
      });
    }

    testWidgets('E9: the bar indents and outdents a list line, caret kept', (
      tester,
    ) async {
      final controller = await loadText(tester, listContent);
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 11,
      );
      await tester.pump();

      bar(tester).onIndent!();
      await tester.pump();
      expect(controller.codeLines[1].text, '  - squat 5x5');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 13),
      );

      bar(tester).onOutdent!();
      await tester.pump();
      expect(controller.codeLines[1].text, '- squat 5x5');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 11),
      );
      expect(controller.text, listContent, reason: 'nothing else moved');
      await teardownPage(tester);
    });

    testWidgets('E16: a keyboard rising over a focused caret reveals it', (
      tester,
    ) async {
      addTearDown(tester.view.resetViewInsets);
      final controller = await loadText(tester, tallContent);
      await focusEditor(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 15,
        offset: 0,
      );
      await tester.pump();
      expect(
        scrollOffset(tester),
        0,
        reason: 'line 15 fits without a keyboard',
      );

      tester.view.viewInsets = FakeViewPadding(
        bottom: 250 * tester.view.devicePixelRatio,
      );
      await tester.pump();
      await tester.pump();

      expect(
        scrollOffset(tester),
        greaterThan(0),
        reason: 'the shrunken body would leave line 15 behind the keyboard',
      );
      await teardownPage(tester);
    });

    testWidgets('E19: a new note opens focused', (tester) async {
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
            home: const OptimizedNoteEditorPage(folderId: folderId),
          ),
        ),
      );
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);

      expect(focusOf(tester).hasFocus, isTrue);
      await teardownPage(tester);
    });

    testWidgets('E19: an existing note opens unfocused', (tester) async {
      await loadNote(tester);

      expect(focusOf(tester).hasFocus, isFalse);
      await teardownPage(tester);
    });

    testWidgets('E20: the haptics setting reaches the wrapper and the bar', (
      tester,
    ) async {
      await tester.runAsync(() => settings.setHapticFeedback(false));
      await loadNote(tester);

      expect(editorOf(tester).hapticsEnabled, isFalse);
      expect(bar(tester).hapticsEnabled, isFalse);
      await teardownPage(tester);
    });

    testWidgets('E25: a font-size step keeps a focused caret in view', (
      tester,
    ) async {
      final controller = await loadText(tester, tallContent);
      await focusEditor(tester);
      controller.selection = const CodeLineSelection.collapsed(
        index: 15,
        offset: 0,
      );
      await tester.pump();
      expect(scrollOffset(tester), 0);

      for (var i = 0; i < 4; i++) {
        bar(tester).onIncreaseFontSize();
        await tester.pump();
        await tester.pump();
      }

      expect(scrollOffset(tester), greaterThan(0));
      await flushFontSizeWrite(tester);
      await teardownPage(tester);
    });

    /// Line [index] as it would render now, concealed leaves left out.
    String visibleText(WidgetTester tester, int index) {
      final controller = editorOf(tester).controller;
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(CodeEditor, skipOffstage: false)),
        index: index,
        textSpan: TextSpan(text: controller.codeLines[index].text),
        style: const TextStyle(fontSize: FontConstants.defaultFontSize),
      );
      final out = StringBuffer();
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.text != null &&
            (child.style?.color?.a ?? 1) > 0) {
          out.write(child.text);
        }
        return true;
      });
      return out.toString();
    }

    testWidgets('Y1: a find match inside a concealed url reveals its line '
        'while the search field holds focus', (tester) async {
      const link = '[video](https://youtube.com/x)';
      final controller = await loadText(tester, '$link\nplain line');
      expect(visibleText(tester, 0), isNot(contains('youtube')));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(NoteSearchBar),
          matching: find.byType(TextField),
        ),
        'youtube',
      );
      await settle(tester);

      expect(focusOf(tester).hasFocus, isFalse);
      expect(controller.selection.startIndex, 0);
      expect(
        controller.selection.startOffset,
        link.indexOf('youtube'),
        reason: 'find selects its match',
      );
      expect(visibleText(tester, 0), contains('youtube'));
      expect(editorOf(tester).revealWhenUnfocused?.value, isTrue);

      // A query that finds nothing reveals nothing (U2.7).
      await tester.enterText(
        find.descendant(
          of: find.byType(NoteSearchBar),
          matching: find.byType(TextField),
        ),
        'zzz',
      );
      await settle(tester);
      expect(editorOf(tester).revealWhenUnfocused?.value, isFalse);

      tester.state<NoteSearchBarState>(find.byType(NoteSearchBar)).close();
      await tester.pumpAndSettle();
      expect(editorOf(tester).revealWhenUnfocused?.value, isFalse);
      await teardownPage(tester);
    });

    testWidgets(
      'Y13: Ctrl+B runs under the page\'s guard as one undo step',
      (tester) async {
        final controller = await loadText(tester, 'do squat now');
        expect(editorOf(tester).onFormatShortcut, isNotNull);
        await focusEditor(tester);
        controller.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 'do squat now'.length,
        );
        controller.replaceSelection(' typed');
        await tester.pump();
        controller.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 3,
          extentIndex: 0,
          extentOffset: 8,
        );
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await settle(tester, rounds: 3);

        expect(controller.codeLines[0].text, 'do **squat** now typed');
        expect(controller.selectedText, 'squat');

        controller.undo();
        await tester.pump();
        expect(
          controller.codeLines[0].text,
          'do squat now typed',
          reason: 'one undo reverts the toggle, not the typing before it',
        );
        await teardownPage(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('E25: an unfocused editor is not scrolled by a font-size '
        'step', (tester) async {
      final controller = await loadText(tester, tallContent);
      controller.selection = const CodeLineSelection.collapsed(
        index: 15,
        offset: 0,
      );
      await tester.pump();

      for (var i = 0; i < 4; i++) {
        bar(tester).onIncreaseFontSize();
        await tester.pump();
        await tester.pump();
      }

      expect(scrollOffset(tester), 0);
      await flushFontSizeWrite(tester);
      await teardownPage(tester);
    });
  });

  // Slice L1 — the page-level pins the completion pass could not reach:
  // each one is a promise of a widget suite that only the page can keep.
  group('the page keeps its widgets\' promises (L1)', () {
    final en = AppLocalizationsEn();

    Widget host({
      Widget home = const OptimizedNoteEditorPage(
        folderId: folderId,
        noteId: noteId,
      ),
      Locale locale = const Locale('en'),
      double textScale = 1.0,
    }) => MultiBlocProvider(
      providers: [
        BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
        BlocProvider<MarkdownBarBloc>.value(value: barBloc),
        BlocProvider<CounterBloc>.value(value: counterBloc),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        navigatorObservers: [AppNavigator.routeObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

    Future<CodeLineEditingController> loadText(
      WidgetTester tester,
      String text, {
      Locale locale = const Locale('en'),
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(host(locale: locale, textScale: textScale));
      noteBloc.emitContentLoaded(metadataFor(text), text);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      return editorOf(tester).controller;
    }

    String statsText(WidgetTester tester) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(NoteEditorStatsBar),
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;

    testWidgets('a 360 x 780 de screen at 2.0: the body follows the text '
        'scale, the strip stays legible, the bar keeps its height', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.view.resetViewInsets);
      expect(SettingsKeys.defaultAutoBreakLongLines, isTrue);
      final controller = await loadText(
        tester,
        '',
        locale: const Locale('de'),
        textScale: 2.0,
      );
      const scaled = FontConstants.defaultFontSize * 2.0;
      expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).style!.fontSize,
        scaled,
      );

      // The reflow measures with the width calculator, padded as the page
      // pads it: at the scaled size a line holds (360 - 16 - 16 - 16) / 32
      // = 9 cells, where an unscaled calculator would leave lines of up to
      // 19. Every third word is "satzx", so a calculator one cell wider
      // (one that lost the scrollbar padding) joins it into a 10-cell line.
      editorOf(tester).focusNode.requestFocus();
      await tester.pump();
      await tester.pump();
      controller.replaceSelection(
        List.generate(12, (i) => i % 3 == 2 ? 'satzx' : 'satz').join(' '),
      );
      await tester.pump();
      await tester.pump();
      final maxCells =
          ((360 - 2 * AppSpacing.lg - AppConstants.editorScrollbarPadding) /
                  scaled)
              .floor();
      expect(maxCells, 9);
      final lines = [
        for (var i = 0; i < controller.lineCount; i++)
          controller.codeLines[i].text,
      ];
      expect(lines.length, greaterThan(1), reason: 'the paste was reflowed');
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(maxCells), reason: line);
      }
      expect(
        lines.any((line) => line.split(' ').length > 1),
        isTrue,
        reason:
            'a line holds two words: the width is the scaled one, not '
            'a fallback that breaks at every space',
      );

      // The strip follows the system size up to its own cap, inside its
      // fixed height.
      final strip = find.byType(NoteEditorStatsBar);
      expect(tester.getSize(strip).height, NoteEditorStatsBar.statsBarHeight);
      final stripText = find
          .descendant(of: strip, matching: find.byType(Text))
          .first;
      expect(
        MediaQuery.textScalerOf(tester.element(stripText)).scale(10),
        closeTo(10 * NoteEditorStatsBar.maxTextScale, 1e-9),
      );
      // A clipped or ellipsized line throws nothing, so the fit is read off
      // the paragraph itself.
      expect(
        tester.renderObject<RenderParagraph>(stripText).didExceedMaxLines,
        isFalse,
        reason: statsText(tester),
      );

      final bar = find.byType(MarkdownBar);
      final height = tester.getSize(bar).height;
      final bottom = tester.getBottomLeft(bar).dy;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(bar).height, height);
      expect(tester.getBottomLeft(bar).dy, bottom - 300);

      tester.view.resetViewInsets();
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(bar).height, height);
      expect(tester.getBottomLeft(bar).dy, bottom);
      expect(tester.takeException(), isNull);
      await teardownPage(tester);
    });

    testWidgets('a new note shows the hint until the first keystroke, and '
        'the first line keeps its height when it goes', (tester) async {
      await tester.pumpWidget(
        host(home: const OptimizedNoteEditorPage(folderId: folderId)),
      );
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      final hint = find.text(en.editorHint);
      expect(hint, findsOneWidget);
      CodeFieldRenderForTesting field() => CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      );
      final before = field().lineHeightOfLine(0);

      editorOf(tester).controller.replaceSelection('a');
      await tester.pump();
      await tester.pump();

      expect(hint, findsNothing);
      expect(field().lineHeightOfLine(0), before);
      await settle(tester);
      await teardownPage(tester);
    });

    testWidgets('the strip counts graphemes once the tracker has reported', (
      tester,
    ) async {
      // '👍👍 ok' is 7 code units and 5 characters. The stored length is
      // the code-unit fallback, accepted before the first report; the
      // loading body is blank, so it never reaches this page's screen.
      const text = '👍👍 ok';
      expect(text.length, 7);
      await loadText(tester, text);

      expect(statsText(tester), en.noteStats(5, 1));
      await teardownPage(tester);
    });

    testWidgets('the stored length never outlives the load', (tester) async {
      const text = '👍👍 ok';
      final note = metadataFor(text);
      await pumpPageFor(tester, note);
      await tester.pump();
      expect(
        find.byType(NoteEditorStatsBar),
        findsNothing,
        reason: 'the loading body is blank',
      );

      noteBloc.emitContentLoaded(note, text);
      await tester.pump();
      await settleUntil(tester, () => editorFinder.evaluate().isNotEmpty);
      await settle(tester);
      expect(
        tester
            .widget<NoteEditorStatsBar>(find.byType(NoteEditorStatsBar))
            .fallbackCharCount,
        isNull,
      );
      expect(statsText(tester), en.noteStats(5, 1));

      // Emptied, the note shows its own count, never the stored 7.
      final controller = editorOf(tester).controller;
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: text.length,
      );
      controller.replaceSelection('');
      await tester.pump(
        NoteEditorStatsTracker.debounceDelay + const Duration(milliseconds: 50),
      );
      await tester.pump();
      expect(statsText(tester), en.noteStats(0, 1));
      await settle(tester);
      await teardownPage(tester);
    });

    testWidgets('a link prompt stays up past 4.5 s and is gone by 5.5 s', (
      tester,
    ) async {
      await loadText(tester, content);
      editorOf(tester).onOpenLink!('https://example.com/squat');
      await tester.pump();
      final prompt = find.text(en.linkOpenPrompt('example.com'));
      expect(prompt, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 4500));
      expect(prompt, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(prompt, findsNothing);
      await teardownPage(tester);
    });
  });

  group('automation identifiers', () {
    testWidgets('the loaded editor carries body, toolbar and overflow', (
      tester,
    ) async {
      await loadNote(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.editorBody),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.editorToolbar),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.editorMore),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.editorBody),
          matching: find.byType(ModernEditorWrapper),
        ),
        findsOneWidget,
        reason: 'the id has to sit on the editing surface, not beside it',
      );

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
