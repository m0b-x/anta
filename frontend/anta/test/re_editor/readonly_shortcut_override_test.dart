import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// A read-only editor must resolve **no** editing intent, and a host's
/// `shortcutOverrideActions` entry is an editing intent like any other:
/// the app's Tab override is a list indent that rewrites the line.
///
/// The touch-platform key path used to consult the override map before it
/// looked at `readOnly` at all, so Tab in a read-only editor ran the
/// host's indent and mutated a document the editor had promised not to
/// touch. This is the Android half — the fork's bare `Focus.onKeyEvent`
/// branch, which is the app's primary target; the desktop
/// `Shortcuts`/`Actions` half is pinned in the `_desktop` twin, because
/// the fork's `kIsAndroid` resolves once per test process and cannot be
/// flipped mid-file.
void main() {
  const document = 'alpha\nbravo';

  /// Mounts a bare [CodeEditor] whose Tab / Shift-Tab are overridden by a
  /// host action that records the invocation and appends a marker, so a
  /// leaked override is visible both as a count and as a text change.
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
              CodeShortcutOutdentIntent: record<CodeShortcutOutdentIntent>(
                'outdent',
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

  testWidgets('a read-only editor never runs the host Shift-Tab override', (
    tester,
  ) async {
    final e = await pumpEditor(tester, readOnly: true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await settle(tester);

    expect(e.invoked, isEmpty);
    expect(e.controller.text, document);
    await teardownEditor(tester);
  });

  testWidgets('an editable editor still runs it', (tester) async {
    // The guard above must be the read-only rule, not a broken override
    // lookup: the same editor without `readOnly` still hands Tab over.
    final e = await pumpEditor(tester, readOnly: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);

    expect(e.invoked, ['indent']);
    expect(e.controller.codeLines[0].text, 'overridden');
    await teardownEditor(tester);
  });
}
