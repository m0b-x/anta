import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_state.dart';
import 'package:anta/constants/font_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/pages/optimized_note_editor_page.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/note_position_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

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
  late FolderSearchService searchService;
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
    searchService = FolderSearchService(storageService: storageService);
    await searchService.initialize();
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
    GetIt.I.registerSingleton<NoteStorageService>(storageService);
  });

  tearDownAll(() async {
    await noteBloc.close();
    await barBloc.close();
    await counterBloc.close();
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

  group('B2 — the saved position survives either load order', () {
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
}

/// A real [OptimizedNoteBloc] whose content load is inert, so the test owns
/// the moment the note's text reaches the page. Everything else — the state
/// classes, the listener wiring, the page's own handling — stays real.
class _TestNoteBloc extends OptimizedNoteBloc {
  _TestNoteBloc({required super.storageService, required super.searchService});

  @override
  void add(OptimizedNoteEvent event) {
    if (event is LoadNoteContent) return;
    super.add(event);
  }

  void reset() => emit(OptimizedNoteInitial());

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
