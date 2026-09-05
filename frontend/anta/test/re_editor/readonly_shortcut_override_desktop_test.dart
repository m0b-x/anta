import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The desktop half of the read-only override rule — the fork's
/// `Shortcuts` / `Actions` layer in `_code_shortcuts.dart`, where the
/// action table already skipped every [CodeShortcutEditableIntent] while
/// read only but the host's `shortcutOverrideActions` were spread in
/// underneath that filter, putting the app's Tab indent back on a
/// document the editor promised not to touch. The Android twin
/// (`readonly_shortcut_override_test.dart`) pins the key-event path.
///
/// **Platform trap.** `kIsAndroid` / `kIsIOS` are top-level `final`s in
/// the fork, resolved on first read and then fixed for the whole test
/// process, so `debugDefaultTargetPlatformOverride` has to be set before
/// the first editor is built anywhere in this file — hence the `setUpAll`
/// idiom copied from `tap_interceptor_desktop_test.dart`, which clears
/// the override again immediately (the binding fails a test that leaves a
/// foundation debug variable set across a test body).
void main() {
  const document = 'alpha\nbravo';

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(kIsAndroid, isFalse);
    expect(kIsIOS, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<({CodeLineEditingController controller, List<String> invoked})>
  pumpEditor(WidgetTester tester, {required bool readOnly}) async {
    final controller = CodeLineEditingController.fromText(document);
    final focusNode = FocusNode();
    final invoked = <String>[];
    addTearDown(() {
      focusNode.dispose();
      controller.dispose();
    });

    Action<Intent> record<T extends Intent>(String name) {
      return CallbackAction<T>(
        onInvoke: (intent) {
          invoked.add(name);
          controller.value = CodeLineEditingValue(
            codeLines: controller.codeLines.replaceLine(
              0,
              controller.codeLines[0].copyWith(text: 'overridden'),
            ),
            selection: controller.selection,
          );
          return null;
        },
      );
    }

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
            shortcutOverrideActions: {
              CodeShortcutIndentIntent: record<CodeShortcutIndentIntent>(
                'indent',
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    focusNode.requestFocus();
    await settle(tester);
    return (controller: controller, invoked: invoked);
  }

  testWidgets('a read-only editor never runs the host Tab override', (
    tester,
  ) async {
    final e = await pumpEditor(tester, readOnly: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);

    expect(e.invoked, isEmpty);
    expect(e.controller.text, document);
    await teardownEditor(tester);
  });

  testWidgets('an editable editor still runs it', (tester) async {
    final e = await pumpEditor(tester, readOnly: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);

    expect(e.invoked, ['indent']);
    expect(e.controller.codeLines[0].text, 'overridden');
    await teardownEditor(tester);
  });
}
