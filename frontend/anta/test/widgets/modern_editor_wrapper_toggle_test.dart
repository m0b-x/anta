import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// P2: the wrapper's two structural edits — the checkbox toggle and the
/// list indent — used to rebuild the whole document with `CodeLines.of`,
/// which re-owns every segment's backing list and so makes the editor's
/// incremental per-line index re-render the entire note.
///
/// These cases pin the replacement (`CodeLines.replaceLine`) at the level
/// that matters to the app: the document past the touched line keeps its
/// segments by *identity*, which is exactly the dirty flag the line index
/// reads. They also re-pin the toggle's two behavioural contracts — the
/// selection is untouched and the flip is one undo step.
///
/// Everything here runs on the default test platform (Android), the app's
/// primary target — including the Tab / Shift-Tab cases, which reach the
/// wrapper's `shortcutOverrideActions` through the fork's touch-platform
/// `Focus.onKeyEvent` branch. The desktop path (the fork's
/// `Shortcuts`/`Actions` layer) is pinned separately in
/// `modern_editor_wrapper_desktop_indent_test.dart`.
///
/// Harness notes are the same as `modern_editor_wrapper_tag_tap_test.dart`:
/// the fork's cursor-blink controller arms an unguarded 100 ms delayed
/// value-set on every focus change, so the tree is flushed before it comes
/// down; and a pass-through tap moves the caret, turning that line into the
/// reveal line (where every tap zone deliberately falls through).
void main() {
  const fontSize = 16.0;
  const lineBox = fontSize * MarkdownConstants.lineHeight;
  // 700 lines is three 256-line segments: 0..255, 256..511, 512..699.
  const documentLines = 700;
  const taskLine = 650;

  String buildDocument({required String lineAt650}) {
    return List<String>.generate(documentLines, (i) {
      if (i == 0) return 'caret line';
      if (i == taskLine) return lineAt650;
      return 'plain line $i';
    }).join('\n');
  }

  /// The global position of column [column] on line [line] while the
  /// editor is scrolled to [scroll] pixels. The `+ 2` biases the tap into
  /// the glyph so the nearest caret boundary is [column], never
  /// [column] - 1.
  Offset positionOf(
    WidgetTester tester,
    int line,
    int column, {
    double scroll = 0,
  }) {
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    return origin +
        Offset(
          AppSpacing.lg + column * fontSize + 2,
          AppSpacing.lg + line * lineBox - scroll + lineBox / 2,
        );
  }

  /// Mounts the wrapper over [text]. Kept close to the tag-tap harness so
  /// the two files stay comparable.
  Future<
    ({
      CodeLineEditingController controller,
      CodeScrollController scroller,
      FocusNode focusNode,
    })
  >
  pumpEditor(WidgetTester tester, {required String text}) async {
    final controller = CodeLineEditingController.fromText(text);
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      searchController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModernEditorWrapper(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            searchController: searchController,
            editorFontSize: fontSize,
            onTextChanged: () {},
            wordWrap: false,
            checkboxTapToggle: true,
            showScrollIndicator: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      controller: controller,
      scroller: scrollController,
      focusNode: focusNode,
    );
  }

  /// Scrolls so [line] sits at the top of the viewport and returns the
  /// pixel offset actually reached (the position clamps at the extent).
  Future<double> scrollToLine(
    WidgetTester tester,
    CodeScrollController scroller,
    int line,
  ) async {
    final position = scroller.verticalScroller.position;
    final target = (line * lineBox).clamp(0.0, position.maxScrollExtent);
    scroller.verticalScroller.jumpTo(target);
    await tester.pump();
    return scroller.verticalScroller.position.pixels;
  }

  List<List<CodeLine>> backingLists(CodeLineEditingController controller) => [
    for (final segment in controller.codeLines.segments) segment.codeLines,
  ];

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('a tap in the last segment resolves to the line it lands on', (
    tester,
  ) async {
    // Calibration for everything below: the scrolled position -> line
    // mapping has to hold before a tap can be aimed at line 650's
    // checkbox. Line 640 carries no zone, so the tap falls through to
    // plain caret placement.
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- [ ] squat 5x5'),
    );

    final scroll = await scrollToLine(tester, e.scroller, 640);
    await tester.tapAt(positionOf(tester, 640, 3, scroll: scroll));
    await tester.pump();

    expect(e.controller.selection.baseIndex, 640);
    expect(e.controller.selection.baseOffset, 3);
    await teardownEditor(tester);
  });

  testWidgets('toggling a checkbox in the last segment leaves every other '
      'segment shared', (tester) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- [ ] squat 5x5'),
    );
    expect(e.controller.codeLines.segments, hasLength(3));

    // Park the caret on line 0 so line 650 is not the reveal line.
    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    expect(e.controller.selection.baseIndex, 0);

    final before = backingLists(e.controller);
    final selectionBefore = e.controller.selection;

    final scroll = await scrollToLine(tester, e.scroller, taskLine);
    // Column 0 is inside the toggle zone whatever the checkbox rendering
    // does to the glyph widths — the zone runs from the list marker to
    // the closing bracket.
    await tester.tapAt(positionOf(tester, taskLine, 0, scroll: scroll));
    await tester.pump();

    expect(e.controller.codeLines[taskLine].text, '- [x] squat 5x5');
    expect(e.controller.codeLines[649].text, 'plain line 649');
    expect(e.controller.codeLines.length, documentLines);

    // An intercepted tap never moves the caret.
    expect(e.controller.selection, selectionBefore);

    final after = backingLists(e.controller);
    expect(after, hasLength(before.length));
    for (int i = 0; i < after.length; i++) {
      expect(
        identical(after[i], before[i]),
        i != 2,
        reason: 'segment $i identity after the toggle',
      );
    }
    await teardownEditor(tester);
  });

  testWidgets('the toggle is a single undo step', (tester) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- [x] squat 5x5'),
    );

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    final selectionBefore = e.controller.selection;

    final scroll = await scrollToLine(tester, e.scroller, taskLine);
    await tester.tapAt(positionOf(tester, taskLine, 0, scroll: scroll));
    await tester.pump();
    expect(e.controller.codeLines[taskLine].text, '- [ ] squat 5x5');

    e.controller.undo();
    await tester.pump();

    expect(e.controller.codeLines[taskLine].text, '- [x] squat 5x5');
    expect(e.controller.selection, selectionBefore);
    await teardownEditor(tester);
  });

  testWidgets('Tab indents the caret list line and leaves the other '
      'segments shared', (tester) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- squat 5x5'),
    );

    e.focusNode.requestFocus();
    await tester.pump();
    e.controller.selection = const CodeLineSelection.collapsed(
      index: taskLine,
      offset: 4,
    );
    await tester.pump();

    final before = backingLists(e.controller);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(e.controller.codeLines[taskLine].text, '  - squat 5x5');
    expect(e.controller.selection.baseIndex, taskLine);
    expect(e.controller.selection.baseOffset, 6);
    expect(e.controller.selection.extentOffset, 6);
    expect(e.controller.codeLines.length, documentLines);
    // A handled Tab must never fall through to focus traversal.
    expect(e.focusNode.hasFocus, isTrue);

    final after = backingLists(e.controller);
    expect(after, hasLength(before.length));
    for (int i = 0; i < after.length; i++) {
      expect(
        identical(after[i], before[i]),
        i != 2,
        reason: 'segment $i identity after the indent',
      );
    }
    await teardownEditor(tester);
  });

  testWidgets('Tab on a non-list line falls back to the editor indent', (
    tester,
  ) async {
    // `_tryListIndent` declines a non-list line, so the wrapper's override
    // hands the keystroke back to `applyIndent`.
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- squat 5x5'),
    );

    e.focusNode.requestFocus();
    await tester.pump();
    e.controller.selection = const CodeLineSelection.collapsed(
      index: 640,
      offset: 0,
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final indent = e.controller.options.indent;
    expect(e.controller.codeLines[640].text, '${indent}plain line 640');
    expect(e.controller.selection.baseIndex, 640);
    expect(e.controller.selection.baseOffset, indent.length);
    expect(e.controller.codeLines.length, documentLines);
    expect(e.focusNode.hasFocus, isTrue);
    await teardownEditor(tester);
  });

  testWidgets('Shift-Tab outdents the caret list line', (tester) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '  - squat 5x5'),
    );

    e.focusNode.requestFocus();
    await tester.pump();
    e.controller.selection = const CodeLineSelection.collapsed(
      index: taskLine,
      offset: 6,
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(e.controller.codeLines[taskLine].text, '- squat 5x5');
    expect(e.controller.selection.baseOffset, 4);
    await teardownEditor(tester);
  });
}
