import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/list_aware_paste.dart';
import 'package:anta/utils/marker_backspace_policy.dart';

/// Backspace right after a line's leading marker: the pure rule
/// ([MarkerBackspacePolicy]) row by row, then the delegate that applies
/// it ([ListAwarePasteController]) on both ways a Backspace arrives — the
/// hardware key's `deleteBackward()` and a soft keyboard's `edit()` with
/// the caret line one code unit shorter.
void main() {
  group('MarkerBackspacePolicy.apply', () {
    void row(String line, int caret, String? text, [int? newCaret]) {
      final result = MarkerBackspacePolicy.apply(line, caret);
      if (text == null) {
        expect(result, isNull, reason: '"$line" @ $caret');
      } else {
        expect(
          result,
          MarkerBackspaceResult(text, newCaret!),
          reason: '"$line" @ $caret',
        );
      }
    }

    test('a top-level item becomes its bare content, caret at 0', () {
      row('- ', 2, '', 0);
      row('- item', 2, 'item', 0);
      row('* a', 2, 'a', 0);
      row('+ a', 2, 'a', 0);
      row('• a', 2, 'a', 0);
      row('-  a', 3, 'a', 0);
      row('1. a', 3, 'a', 0);
      row('12) a', 4, 'a', 0);
    });

    test('a task loses its marker and its box in one keystroke', () {
      row('- [ ] ', 6, '', 0);
      row('- [x] done', 6, 'done', 0);
      row('- [ ]', 5, '', 0);
    });

    test('a nested item outdents one level first, as Shift-Tab does', () {
      row('  - a', 4, '- a', 2);
      row('    - [ ] a', 10, '  - [ ] a', 8);
      // Off the two-column grid it snaps to the nearest column.
      row('   - a', 5, '  - a', 4);
      row('\t- a', 3, '- a', 2);
    });

    test('a quote loses its innermost marker only', () {
      row('> a', 2, 'a', 0);
      row('> ', 2, '', 0);
      row('>a', 1, 'a', 0);
      row('> > a', 4, '> a', 2);
      row('>> a', 3, '>a', 1);
      row('  > a', 4, '  a', 2);
      row('> [!TIP] title', 2, '[!TIP] title', 0);
    });

    test('an item inside a quote follows the list rule, quote kept', () {
      // Read after the quote run, as Enter continues it.
      row('> - a', 4, '> a', 2);
      row('> - ', 4, '> ', 2);
      row('> 1. a', 5, '> a', 2);
      row('> - [ ] a', 8, '> a', 2);
      row('> > - a', 6, '> > a', 4);
      row('>   - a', 6, '> - a', 4);
      // At the quote's own content start the quote marker goes first.
      row('> - a', 2, '- a', 0);
      row('> - a', 3, null);
      row('> - a', 5, null);
    });

    test('anywhere but the content start is the editor\'s Backspace', () {
      row('- item', 0, null);
      row('- item', 1, null);
      row('- item', 3, null);
      row('- [ ] a', 5, null);
      row('> > a', 2, null);
      row('plain', 1, null);
      row('', 0, null);
    });
  });

  group('applied by ListAwarePasteController', () {
    ListAwarePasteController controllerAt(
      String text,
      int offset, {
      bool fenced = false,
    }) {
      final controller = ListAwarePasteController(
        delegate: CodeLineEditingController.fromText(text),
        isFenceLine: (_) => fenced,
      );
      addTearDown(controller.dispose);
      controller.selection = CodeLineSelection.collapsed(
        index: 0,
        offset: offset,
      );
      return controller;
    }

    test('deleteBackward takes the marker as one undo step', () {
      final controller = controllerAt('- [ ] ', 6);

      controller.deleteBackward();

      expect(controller.text, '');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 0),
      );
      controller.undo();
      expect(controller.text, '- [ ] ');
      expect(controller.canUndo, isFalse);
    });

    test('a nested item outdents, then loses its marker', () {
      final controller = controllerAt('  - a', 4);

      controller.deleteBackward();
      expect(controller.text, '- a');
      expect(controller.selection.extentOffset, 2);

      controller.deleteBackward();
      expect(controller.text, 'a');
      expect(controller.selection.extentOffset, 0);
    });

    test('off the content start it is the fork\'s plain Backspace', () {
      final controller = controllerAt('- ab', 4);

      controller.deleteBackward();

      expect(controller.text, '- a');
    });

    test('a fenced line keeps its marker characters', () {
      final controller = controllerAt('- ', 2, fenced: true);

      controller.deleteBackward();

      expect(controller.text, '-');
    });

    test('a soft keyboard Backspace after a marker takes the marker', () {
      final controller = controllerAt('- [ ] ', 6);

      controller.edit(
        const TextEditingValue(
          text: '- [ ]',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      expect(controller.text, '');
      expect(controller.selection.extentOffset, 0);
      controller.undo();
      expect(controller.text, '- [ ] ');
    });

    test('a soft keyboard Backspace while composing is left as typed', () {
      final controller = controllerAt('- [ ] ', 6);

      controller.edit(
        const TextEditingValue(
          text: '- [ ]',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 2, end: 5),
        ),
      );

      expect(controller.text, '- [ ]');
    });

    test('any other soft keyboard edit is the fork\'s', () {
      final controller = controllerAt('- ab', 4);

      controller.edit(
        const TextEditingValue(
          text: '- abc',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(controller.text, '- abc');

      controller.edit(
        const TextEditingValue(
          text: '- ab',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      expect(controller.text, '- ab');
    });
  });

  group('through the text input channel', () {
    /// The latest editing state the editor pushed to the input method.
    Map<String, dynamic> lastPushedState(WidgetTester tester) {
      final call = tester.testTextInput.log.lastWhere(
        (call) => call.method == 'TextInput.setEditingState',
      );
      return (call.arguments as Map).cast<String, dynamic>();
    }

    /// One Backspace as Gboard sends it: a deletion delta over the input
    /// method's own view of the line (zero-width prefix included). The log
    /// is cleared first, so what it holds afterwards is the editor's answer.
    Future<void> sendBackspace(WidgetTester tester) async {
      final state = lastPushedState(tester);
      final setClient = tester.testTextInput.log.lastWhere(
        (call) => call.method == 'TextInput.setClient',
      );
      final client = (setClient.arguments as List)[0] as int;
      final caret = state['selectionExtent'] as int;
      tester.testTextInput.log.clear();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', [
            client,
            {
              'deltas': [
                {
                  'oldText': state['text'],
                  'deltaText': '',
                  'deltaStart': caret - 1,
                  'deltaEnd': caret,
                  'selectionBase': caret - 1,
                  'selectionExtent': caret - 1,
                  'selectionAffinity': 'TextAffinity.downstream',
                  'selectionIsDirectional': false,
                  'composingBase': -1,
                  'composingExtent': -1,
                },
              ],
            },
          ]),
        ),
        (_) {},
      );
    }

    testWidgets('a Backspace after `- ` takes the marker and the input '
        'method is handed the new line', (tester) async {
      final controller = ListAwarePasteController(
        delegate: CodeLineEditingController.fromText('- '),
      );
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
              style: const CodeEditorStyle(fontSize: 14),
            ),
          ),
        ),
      );
      await tester.pump();
      // A tap past the line's end focuses the editor, opens the input
      // connection and parks the caret after the marker.
      await tester.tapAt(
        tester.getTopLeft(find.byType(CodeEditor)) + const Offset(200, 4),
      );
      await tester.pump();
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.extentOffset, 2);

      await sendBackspace(tester);
      await tester.pump();

      expect(controller.text, '');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 0),
      );
      // The keyboard only removed the space; without this push it would
      // still hold `-` and its next key would edit a line that is gone.
      final pushed = lastPushedState(tester);
      expect(pushed['text'], '​');
      expect(pushed['selectionBase'], 1);
      expect(pushed['selectionExtent'], 1);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
