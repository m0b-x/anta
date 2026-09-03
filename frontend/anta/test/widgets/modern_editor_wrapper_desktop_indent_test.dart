import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The desktop half of the Tab / Shift-Tab list indent.
///
/// The fork builds two different key paths: on Android and iOS the editor
/// mounts a bare `Focus.onKeyEvent`, and everywhere else it mounts its
/// `Shortcuts` + `Actions` layer, where `shortcutOverrideActions` is spread
/// over the built-in intents. Both have to keep working, so the touch path
/// is pinned on the default test platform in
/// `modern_editor_wrapper_toggle_test.dart` and this file forces the other
/// one.
///
/// **Trap.** `kIsAndroid` / `kIsIOS` are top-level `final`s in the fork,
/// resolved on first read and then fixed for the whole test process — so
/// `debugDefaultTargetPlatformOverride` has to be in place *before the
/// first editor builds*, and clearing it later cannot un-cache them. It
/// also cannot be left set across a test body: the binding fails a test
/// that leaves a foundation debug variable set. Hence `setUpAll` sets the
/// override, reads both flags to force resolution, and clears it again.
void main() {
  const fontSize = 16.0;
  const documentLines = 700;
  const listLine = 650;
  const plainLine = 640;

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(kIsAndroid, isFalse);
    expect(kIsIOS, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  String buildDocument({required String lineAt650}) {
    return List<String>.generate(documentLines, (i) {
      if (i == listLine) return lineAt650;
      return 'plain line $i';
    }).join('\n');
  }

  Future<({CodeLineEditingController controller, FocusNode focusNode})>
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
    return (controller: controller, focusNode: focusNode);
  }

  List<List<CodeLine>> backingLists(CodeLineEditingController controller) => [
    for (final segment in controller.codeLines.segments) segment.codeLines,
  ];

  /// The fork's cursor-blink controller arms an unguarded 100 ms delayed
  /// value-set on every focus change, so the tree is flushed while it is
  /// still alive.
  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> focusOnLine(
    WidgetTester tester,
    ({CodeLineEditingController controller, FocusNode focusNode}) e,
    int index,
    int offset,
  ) async {
    e.focusNode.requestFocus();
    await tester.pump();
    e.controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
    await tester.pump();
  }

  testWidgets('Tab indents the caret list line and leaves the other '
      'segments shared', (tester) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- squat 5x5'),
    );
    expect(e.controller.codeLines.segments, hasLength(3));

    await focusOnLine(tester, e, listLine, 4);
    final before = backingLists(e.controller);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(e.controller.codeLines[listLine].text, '  - squat 5x5');
    expect(e.controller.selection.baseIndex, listLine);
    expect(e.controller.selection.baseOffset, 6);
    expect(e.controller.selection.extentOffset, 6);
    expect(e.controller.codeLines.length, documentLines);
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

  testWidgets('Shift-Tab outdents the caret list line', (tester) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '  - squat 5x5'),
    );

    await focusOnLine(tester, e, listLine, 6);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(e.controller.codeLines[listLine].text, '- squat 5x5');
    expect(e.controller.selection.baseOffset, 4);
    expect(e.focusNode.hasFocus, isTrue);
    await teardownEditor(tester);
  });

  testWidgets('Tab on a non-list line falls back to the editor indent', (
    tester,
  ) async {
    final e = await pumpEditor(
      tester,
      text: buildDocument(lineAt650: '- squat 5x5'),
    );

    await focusOnLine(tester, e, plainLine, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final indent = e.controller.options.indent;
    expect(e.controller.codeLines[plainLine].text, '${indent}plain line 640');
    expect(e.controller.selection.baseIndex, plainLine);
    expect(e.controller.selection.baseOffset, indent.length);
    expect(e.controller.codeLines.length, documentLines);
    expect(e.focusNode.hasFocus, isTrue);
    await teardownEditor(tester);
  });
}
