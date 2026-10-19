import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// A hardware keyboard on a phone or a tablet (widget tests run on the
/// Android path). That branch builds no `Shortcuts`, only a bare
/// `Focus.onKeyEvent`, so Ctrl+V, Ctrl+Z and Ctrl+Y used to fall through
/// to nothing; they now paste, undo and redo, and a read-only editor still
/// runs none of them.
void main() {
  Future<CodeLineEditingController> pumpEditor(
    WidgetTester tester, {
    bool readOnly = false,
  }) async {
    final controller = CodeLineEditingController.fromText('ab');
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      controller.dispose();
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'XY'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            focusNode: focusNode,
            autofocus: false,
            readOnly: readOnly,
            padding: EdgeInsets.zero,
            style: const CodeEditorStyle(fontSize: kTestFontSize),
          ),
        ),
      ),
    );
    await settle(tester);
    focusNode.requestFocus();
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 2,
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

  testWidgets('Ctrl+V pastes at the caret', (tester) async {
    final controller = await pumpEditor(tester);

    await chord(tester, LogicalKeyboardKey.keyV);

    expect(controller.text, 'abXY');
    await teardownEditor(tester);
  });

  testWidgets('Ctrl+Z undoes; Ctrl+Y and Ctrl+Shift+Z redo', (tester) async {
    final controller = await pumpEditor(tester);
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(controller.text, 'abXY');

    await chord(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, 'ab');
    await chord(tester, LogicalKeyboardKey.keyY);
    expect(controller.text, 'abXY');
    await chord(tester, LogicalKeyboardKey.keyZ);
    await chord(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(controller.text, 'abXY');

    await teardownEditor(tester);
  });

  testWidgets('a read-only editor runs none of them', (tester) async {
    final controller = await pumpEditor(tester, readOnly: true);

    await chord(tester, LogicalKeyboardKey.keyV);
    expect(controller.text, 'ab');

    controller.replaceSelection('!');
    await chord(tester, LogicalKeyboardKey.keyZ);
    expect(controller.text, 'ab!');

    await teardownEditor(tester);
  });

  testWidgets('a bare V is left to the input method, never a paste', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await settle(tester, 4);

    expect(controller.text, 'ab');
    await teardownEditor(tester);
  });
}
