import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/editor_edit_tracker.dart';
import 'package:anta/utils/editor_input_policy.dart';
import 'package:anta/utils/list_aware_paste.dart';
import 'package:anta/utils/marker_space_policy.dart';

/// Space at an empty list item's content start: the pure rule
/// ([MarkerSpacePolicy]) row by row, then the delegate that applies it
/// ([ListAwarePasteController]) to a soft keyboard's `edit()` with the
/// caret line one space longer, and the whole round trip through the text
/// input channel.
void main() {
  group('MarkerSpacePolicy.apply', () {
    void row(
      String line,
      int caret,
      String? text, [
      int? newCaret,
      int? maxLevel,
    ]) {
      final result = MarkerSpacePolicy.apply(
        line,
        caret,
        maxLevelOf: maxLevel == null ? null : () => maxLevel,
      );
      if (text == null) {
        expect(result, isNull, reason: '"$line" @ $caret');
      } else {
        expect(
          result,
          MarkerSpaceResult(text, newCaret!),
          reason: '"$line" @ $caret',
        );
      }
    }

    test('an empty bullet nests one grid step, caret at its content', () {
      row('- ', 2, '  - ', 4);
      row('* ', 2, '  * ', 4);
      row('+ ', 2, '  + ', 4);
      row('• ', 2, '  • ', 4);
      row('-  ', 3, '  -  ', 5);
      row('  - ', 4, '    - ', 6);
      // Off the grid it snaps to the next column, as Tab does.
      row(' - ', 3, '  - ', 4);
    });

    test('a task keeps its box, a custom state its state', () {
      row('- [ ] ', 6, '  - [ ] ', 8);
      row('- [x] ', 6, '  - [x] ', 8);
      row('- [-] ', 6, '  - [-] ', 8);
      row('* [/] ', 6, '  * [/] ', 8);
    });

    test('an ordered item restarts at 1 with its delimiter kept', () {
      row('2. ', 3, '  1. ', 5);
      row('3) ', 3, '  1) ', 5);
      row('12. ', 4, '  1. ', 5);
      row('1. ', 3, '  1. ', 5);
      row('  7) ', 5, '    1) ', 7);
    });

    test('a quoted item keeps its quote run and nests after it', () {
      row('> - ', 4, '>   - ', 6);
      row('> > - [ ] ', 10, '> >   - [ ] ', 12);
      row('> 4. ', 5, '>   1. ', 7);
      row('>   - ', 6, '>     - ', 8);
    });

    test('a tab-indented item takes Tab\'s step in front of the tab', () {
      row('\t- ', 3, '  \t- ', 5);
    });

    test('at the cap the key is consumed and nothing changes', () {
      row('- ', 2, '- ', 2, 0);
      row('  - [ ] ', 8, '  - [ ] ', 8, 1);
      row('3. ', 3, '3. ', 3, 0);
      row('> - ', 4, '> - ', 4, 0);
      // Below the cap it nests as before.
      row('- ', 2, '  - ', 4, 1);
      row('  - ', 4, '    - ', 6, 2);
    });

    test('a non-empty item, or a caret elsewhere, types the space', () {
      row('- a', 2, null);
      row('- [ ] a', 6, null);
      row('1. a', 3, null);
      row('- ', 0, null);
      row('- ', 1, null);
      row('-  ', 2, null);
      row('  - ', 2, null);
      row('- [ ] ', 5, null);
      row('> - ', 2, null);
      row('> - ', 3, null);
    });

    test('a box typed by hand without its space types the space', () {
      // The content start sits right after `]`: this space separates the
      // box from the text the user is about to type.
      row('- [ ]', 5, null);
      row('- [x]', 5, null);
      row('- [-]', 5, null);
    });

    test('a line that is no list item types the space', () {
      row('', 0, null);
      row('plain', 5, null);
      row('-', 1, null);
      row('1.', 2, null);
      row('> ', 2, null);
      row('# ', 2, null);
      row('- - -', 4, null);
    });

    test('the cap is read only once the line is claimed', () {
      // The cap scans upward from the line; a double space in prose or in
      // an indented block must not pay for that scan.
      var reads = 0;
      int Function() capOf(List<String> lines) =>
          () => EditorInputPolicy.listIndentCap(
            lineAt: (i) {
              reads++;
              return lines[i];
            },
            index: lines.length - 1,
          );

      for (final (line, caret) in [
        ('prose  ', 7),
        ('    indented  ', 14),
        ('- a ', 4),
        ('- [ ]', 5),
        ('> quoted  ', 10),
      ]) {
        final result = MarkerSpacePolicy.apply(
          line,
          caret,
          maxLevelOf: capOf(['intro', '- a', line]),
        );
        expect(result, isNull, reason: '"$line" @ $caret');
      }
      expect(reads, 0);

      final claimed = MarkerSpacePolicy.apply(
        '- ',
        2,
        maxLevelOf: capOf(['- a', '- ']),
      );
      expect(claimed, const MarkerSpaceResult('  - ', 4));
      expect(reads, greaterThan(0), reason: 'a claimed line reads the cap');
    });
  });

  group('applied by ListAwarePasteController', () {
    ListAwarePasteController controllerAt(
      String text, {
      required int index,
      required int offset,
      bool fenced = false,
    }) {
      final controller = ListAwarePasteController(
        delegate: CodeLineEditingController.fromText(text),
        isFenceLine: (_) => fenced,
      );
      addTearDown(controller.dispose);
      controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: offset,
      );
      return controller;
    }

    /// The caret line as the input method sends it after a space at
    /// [caret].
    TextEditingValue typedSpace(String line, int caret) => TextEditingValue(
      text: '${line.substring(0, caret)} ${line.substring(caret)}',
      selection: TextSelection.collapsed(offset: caret + 1),
    );

    test('a space on an empty nested slot nests the item as one undo '
        'step', () {
      final controller = controllerAt('- a\n- ', index: 1, offset: 2);

      controller.edit(typedSpace('- ', 2));

      expect(controller.text, '- a\n  - ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 4),
      );
      controller.undo();
      expect(controller.text, '- a\n- ');
      expect(controller.canUndo, isFalse);
    });

    test('an ordered item restarts its number', () {
      final controller = controllerAt('1. a\n2. ', index: 1, offset: 3);

      controller.edit(typedSpace('2. ', 3));

      expect(controller.text, '1. a\n  1. ');
      expect(controller.selection.extentOffset, 5);
    });

    test('a first item is at its cap: the space is swallowed, no undo '
        'node', () {
      final controller = controllerAt('- ', index: 0, offset: 2);

      controller.edit(typedSpace('- ', 2));

      expect(controller.text, '- ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 2),
      );
      expect(controller.canUndo, isFalse);
    });

    test('the item may nest only one level under the item above', () {
      final controller = controllerAt('- a\n  - ', index: 1, offset: 4);

      controller.edit(typedSpace('  - ', 4));

      expect(controller.text, '- a\n  - ');
    });

    test('a space anywhere else is typed', () {
      final controller = controllerAt('- a\n- b', index: 1, offset: 3);

      controller.edit(typedSpace('- b', 3));
      expect(controller.text, '- a\n- b ');

      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 1,
      );
      controller.edit(typedSpace('- b ', 1));
      expect(controller.text, '- a\n-  b ');
    });

    test('a fenced line types the space', () {
      final controller = controllerAt(
        '- a\n- ',
        index: 1,
        offset: 2,
        fenced: true,
      );

      controller.edit(typedSpace('- ', 2));

      expect(controller.text, '- a\n-  ');
    });

    test('a space while composing is the fork\'s', () {
      final controller = controllerAt('- a\n- ', index: 1, offset: 2);

      controller.edit(
        const TextEditingValue(
          text: '-  ',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 2, end: 3),
        ),
      );

      expect(controller.text, '- a\n-  ');
    });

    /// The caret line as the input method sends a double-space period: the
    /// space before [caret] replaced by `. `.
    TextEditingValue periodSpace(String line, int caret) => TextEditingValue(
      text: '${line.substring(0, caret - 1)}. ${line.substring(caret)}',
      selection: TextSelection.collapsed(offset: caret + 1),
    );

    test('a double-space period on a hand-typed item nests it and the '
        '`. ` never lands', () {
      for (final (item, nested) in [
        ('- [ ] ', '  - [ ] '),
        ('3) ', '  1) '),
        ('+ ', '  + '),
      ]) {
        final controller = controllerAt(
          '- a\n$item',
          index: 1,
          offset: item.length,
        );

        controller.edit(periodSpace(item, item.length));

        expect(controller.text, '- a\n$nested', reason: item);
        expect(
          controller.selection,
          CodeLineSelection.collapsed(index: 1, offset: nested.length),
          reason: item,
        );
        controller.undo();
        expect(controller.text, '- a\n$item', reason: item);
      }
    });

    test('a double-space period at the cap is swallowed', () {
      final controller = controllerAt('- [ ] ', index: 0, offset: 6);

      controller.edit(periodSpace('- [ ] ', 6));

      expect(controller.text, '- [ ] ');
      expect(controller.canUndo, isFalse);
    });

    test('a double-space period anywhere else is typed', () {
      final controller = controllerAt('- a\n- b ', index: 1, offset: 4);

      controller.edit(periodSpace('- b ', 4));

      expect(controller.text, '- a\n- b. ');
      expect(controller.selection.extentOffset, 5);
    });

    test('a quoted empty item nests after its quote run', () {
      final controller = controllerAt('> - a\n> - ', index: 1, offset: 4);

      controller.edit(typedSpace('> - ', 4));

      expect(controller.text, '> - a\n>   - ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 6),
      );
    });

    test('a quoted first item is at its cap', () {
      final controller = controllerAt('> - ', index: 0, offset: 4);

      controller.edit(typedSpace('> - ', 4));

      expect(controller.text, '> - ');
      expect(controller.selection.extentOffset, 4);
      expect(controller.canUndo, isFalse);
    });

    test('an item under a heading opens its list: the space is '
        'swallowed', () {
      final controller = controllerAt('# Plan\n- ', index: 1, offset: 2);

      controller.edit(typedSpace('- ', 2));

      expect(controller.text, '# Plan\n- ');
      expect(controller.canUndo, isFalse);
    });

    test('an indented first item under a paragraph is at its cap', () {
      final controller = controllerAt('intro\n  - ', index: 1, offset: 4);

      controller.edit(typedSpace('  - ', 4));

      expect(controller.text, 'intro\n  - ');
      expect(controller.canUndo, isFalse);
    });

    test('an item under a deep one nests one level past it, no '
        'further', () {
      final controller = controllerAt(
        'intro\n    - a\n    - ',
        index: 2,
        offset: 6,
      );

      controller.edit(typedSpace('    - ', 6));
      expect(controller.text, 'intro\n    - a\n      - ');
      expect(controller.selection.extentOffset, 8);

      controller.edit(typedSpace('      - ', 8));
      expect(controller.text, 'intro\n    - a\n      - ');
      expect(controller.selection.extentOffset, 8);
    });

    test('a space at the end of a long document re-owns only the last '
        'segment', () {
      final lines = [for (var i = 0; i < 700; i++) '- item $i', '- '];
      final controller = controllerAt(
        lines.join('\n'),
        index: lines.length - 1,
        offset: 2,
      );
      final before = [
        for (final segment in controller.codeLines.segments) segment.codeLines,
      ];
      expect(before.length, greaterThan(1));

      controller.edit(typedSpace('- ', 2));

      expect(controller.codeLines[lines.length - 1].text, '  - ');
      expect(controller.codeLines.length, lines.length);
      final after = controller.codeLines.segments;
      expect(after.length, before.length);
      for (var i = 0; i < after.length - 1; i++) {
        expect(
          identical(after[i].codeLines, before[i]),
          isTrue,
          reason: 'segment $i is shared',
        );
      }
      expect(identical(after.last.codeLines, before.last), isFalse);
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

    int? inputClient;

    /// [deltaText] replacing the [replaced] units before the caret, as
    /// Gboard sends it: a delta over the input method's own view of the
    /// line (zero-width prefix included), the caret right after the text.
    /// The log is cleared first, so what it holds afterwards is the
    /// editor's answer.
    Future<void> sendDelta(
      WidgetTester tester,
      String deltaText, {
      int replaced = 0,
    }) async {
      final state = lastPushedState(tester);
      final setClient = tester.testTextInput.log
          .where((call) => call.method == 'TextInput.setClient')
          .lastOrNull;
      // A log cleared by the previous key no longer holds the connection.
      if (setClient != null) {
        inputClient = (setClient.arguments as List)[0] as int;
      }
      final client = inputClient!;
      final caret = state['selectionExtent'] as int;
      final next = caret - replaced + deltaText.length;
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
                  'deltaText': deltaText,
                  'deltaStart': caret - replaced,
                  'deltaEnd': caret,
                  'selectionBase': next,
                  'selectionExtent': next,
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

    /// One Space as Gboard sends it.
    Future<void> sendSpace(WidgetTester tester) => sendDelta(tester, ' ');

    /// [continueLists] attaches the hosts' [EditorEditTracker], which is
    /// what continues a list on Enter.
    Future<ListAwarePasteController> pumpEditorAtEnd(
      WidgetTester tester,
      String text, {
      bool continueLists = false,
    }) async {
      final controller = ListAwarePasteController(
        delegate: CodeLineEditingController.fromText(text),
      );
      final focusNode = FocusNode();
      final tracker = EditorEditTracker(
        controller: controller,
        autoBreakLongLines: () => false,
        pasteContext: () => null,
        onLinesReformatted: (_) {},
      )..syncLength();
      if (continueLists) controller.addListener(tracker.onTextChanged);
      addTearDown(() {
        controller.removeListener(tracker.onTextChanged);
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
      // A tap past the last line parks the caret at the document end and
      // opens the input connection.
      await tester.tapAt(
        tester.getTopLeft(find.byType(CodeEditor)) + const Offset(200, 60),
      );
      await tester.pump();
      return controller;
    }

    Future<void> teardownEditor(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('a Space on an empty item nests it and the input method is '
        'handed the new line', (tester) async {
      final controller = await pumpEditorAtEnd(tester, '- a\n- ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 2),
      );

      await sendSpace(tester);
      await tester.pump();

      expect(controller.text, '- a\n  - ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 4),
      );
      final pushed = lastPushedState(tester);
      expect(pushed['text'], '​  - ');
      expect(pushed['selectionBase'], 5);
      expect(pushed['selectionExtent'], 5);

      await teardownEditor(tester);
    });

    testWidgets('a Space swallowed at the cap hands the input method the '
        'unchanged line', (tester) async {
      final controller = await pumpEditorAtEnd(tester, '- ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 2),
      );

      await sendSpace(tester);
      await tester.pump();

      expect(controller.text, '- ');
      // The keyboard already holds `-  `; without this push its next key
      // would edit a line with a space the editor never kept.
      final pushed = lastPushedState(tester);
      expect(pushed['text'], '​- ');
      expect(pushed['selectionBase'], 3);
      expect(pushed['selectionExtent'], 3);

      await teardownEditor(tester);
    });

    testWidgets('a double-space period on a hand-typed task nests it and '
        'the input method is handed the new line', (tester) async {
      final controller = await pumpEditorAtEnd(tester, '- a\n- [ ] ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 6),
      );

      // Gboard's second Space of a quick pair: the first one, before the
      // caret, rewritten as `. `.
      await sendDelta(tester, '. ', replaced: 1);
      await tester.pump();

      expect(controller.text, '- a\n  - [ ] ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 8),
      );
      final pushed = lastPushedState(tester);
      expect(pushed['text'], '​  - [ ] ');
      expect(pushed['selectionBase'], 9);
      expect(pushed['selectionExtent'], 9);

      await teardownEditor(tester);
    });

    testWidgets('Enter, Space and a letter make a nested item, and one '
        'undo after the letter takes the Space back', (tester) async {
      final controller = await pumpEditorAtEnd(
        tester,
        '- a',
        continueLists: true,
      );
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 3),
      );

      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(controller.text, '- a\n- ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 2),
      );

      await sendSpace(tester);
      await tester.pump();
      await sendDelta(tester, 'b');
      await tester.pump();

      expect(controller.text, '- a\n  - b');

      controller.undo();
      await tester.pump();
      expect(controller.text, '- a\n  - ');
      expect(lastPushedState(tester)['text'], '​  - ');

      controller.undo();
      await tester.pump();
      expect(controller.text, '- a\n- ');
      final pushed = lastPushedState(tester);
      expect(pushed['text'], '​- ');
      expect(pushed['selectionBase'], 3);
      expect(pushed['selectionExtent'], 3);

      await teardownEditor(tester);
    });
  });
}
