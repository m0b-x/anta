import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The Windows and Linux `Shortcuts` path end to end: Shift+Ctrl+arrows
/// extend the selection by a word in the arrow's direction, and Ctrl+Y
/// redoes. The controller's extend-by-word methods carry upstream's
/// reversed names, so the table pinned in `shortcut_table_test.dart` can
/// look right and still move the wrong way — only a key press proves it.
///
/// **Platform trap.** `kIsAndroid` / `kIsIOS` are top-level `final`s in
/// the fork, resolved on first read and then fixed for the whole test
/// process, so the override is set in `setUpAll` before any editor is
/// built and cleared again at once (the idiom of
/// `readonly_shortcut_override_desktop_test.dart`).
void main() {
  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(kIsAndroid, isFalse);
    expect(kIsIOS, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<CodeLineEditingController> pumpEditor(
    WidgetTester tester, {
    required int caret,
  }) async {
    final controller = CodeLineEditingController.fromText('foo bar');
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            focusNode: focusNode,
            autofocus: false,
            padding: EdgeInsets.zero,
            style: const CodeEditorStyle(fontSize: kTestFontSize),
          ),
        ),
      ),
    );
    await settle(tester);
    focusNode.requestFocus();
    controller.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: caret,
    );
    await settle(tester);
    return controller;
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester, 4);
  }

  testWidgets('Shift+Ctrl+Right extends the selection to the next word end',
      (tester) async {
    final controller = await pumpEditor(tester, caret: 3);

    await chord(tester, LogicalKeyboardKey.arrowRight, shift: true);

    expect(controller.selection.baseOffset, 3);
    expect(controller.selection.extentOffset, 7);
    await teardownEditor(tester);
  });

  testWidgets('Shift+Ctrl+Left extends the selection to the word start',
      (tester) async {
    final controller = await pumpEditor(tester, caret: 7);

    await chord(tester, LogicalKeyboardKey.arrowLeft, shift: true);

    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 4);
    await teardownEditor(tester);
  });

  testWidgets('Ctrl+Y redoes what Ctrl+Z undid', (tester) async {
    final controller = await pumpEditor(tester, caret: 7);
    controller.replaceSelection('!');
    await settle(tester, 4);
    expect(controller.text, 'foo bar!');

    await chord(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, 'foo bar');

    await chord(tester, LogicalKeyboardKey.keyY);
    expect(controller.text, 'foo bar!');
    await teardownEditor(tester);
  });
}
