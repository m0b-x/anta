import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// Auto-pairing and wrapping as a soft keyboard drives them: one delta per
/// key through the text input channel, over the input method's own view of
/// the caret line (the zero-width prefix included — widget tests run on
/// the Android path).
///
/// Pairing is for notes, not code: `'` never pairs (an apostrophe is far
/// more common than a quoted phrase), `"` and the backtick do not pair
/// against a word, and typing a closer steps over it only when the pairing
/// put it there. A selection typed over with a bracket, a quote or a
/// markdown emphasis symbol is wrapped instead of replaced.
void main() {
  Future<_Keyboard> pumpEditor(WidgetTester tester, String text) async {
    final controller = CodeLineEditingController.fromText(text);
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
    await tester.pump();
    // A tap past the line's end focuses the editor and opens the input
    // connection with the caret at the end of the first line.
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodeEditor)) + const Offset(400, 4),
    );
    await tester.pump();
    return _Keyboard(tester, controller);
  }

  group('pairing', () {
    testWidgets('a quote on its own pairs, and typing it again steps over '
        'the closer', (tester) async {
      final k = await pumpEditor(tester, '');

      await k.type('"');
      expect(k.line, '""');
      expect(k.caret, 1);
      await k.type('a');
      await k.type('"');
      expect(k.line, '"a"');
      expect(k.caret, 3);

      await teardownEditor(tester);
    });

    testWidgets('an apostrophe never pairs', (tester) async {
      final k = await pumpEditor(tester, 'don');

      await k.type('\'');
      expect(k.line, 'don\'');
      await k.typeAt(0, '\'');
      expect(k.line, '\'don\'');

      await teardownEditor(tester);
    });

    testWidgets('a quote against a letter or a digit does not pair', (
      tester,
    ) async {
      final k = await pumpEditor(tester, 'say');

      await k.type('"');
      expect(k.line, 'say"');

      k.controller.loadText('word');
      await tester.pump();
      await k.typeAt(0, '"');
      expect(k.line, '"word');

      k.controller.loadText('pas 2');
      await tester.pump();
      await k.typeAt(5, '`');
      expect(k.line, 'pas 2`');

      k.controller.loadText('ă');
      await tester.pump();
      await k.typeAt(1, '"');
      expect(k.line, 'ă"', reason: 'a letter in any script counts');

      k.controller.loadText('é');
      await tester.pump();
      await k.typeAt(2, '"');
      expect(k.line, 'é"', reason: 'a decomposed accent ends a word');

      await teardownEditor(tester);
    });

    testWidgets('a bracket closer typed through content steps over the '
        'auto-inserted one, nested pairs included', (tester) async {
      final k = await pumpEditor(tester, '');

      await k.type('(');
      expect(k.line, '()');
      await k.type('[');
      expect(k.line, '([])');
      await k.type('a');
      await k.type(']');
      await k.type(')');

      expect(k.line, '([a])');
      expect(k.caret, 5);

      await teardownEditor(tester);
    });

    testWidgets('a closer that was already in the text is typed, not '
        'stepped over', (tester) async {
      final k = await pumpEditor(tester, 'f(x)');

      await k.typeAt(3, ')');
      expect(k.line, 'f(x))');

      k.controller.loadText('say ""');
      await tester.pump();
      await k.typeAt(5, '"');
      expect(k.line, 'say """"', reason: 'pairs as before; never a step');

      await teardownEditor(tester);
    });

    testWidgets('a word composed against the line start keeps the closer', (
      tester,
    ) async {
      // Gboard's composing range can take in the zero-width prefix at
      // column 0; the controller cannot hold that unit, so the view it
      // hands back differs in the composing range alone, and that must
      // not read as an outside change.
      final k = await pumpEditor(tester, '');

      await k.type('(');
      expect(k.line, '()');
      await k.type('a', composing: const TextRange(start: 0, end: 3));
      await k.type('b', composing: const TextRange(start: 0, end: 4));
      await k.type('c', composing: const TextRange(start: 0, end: 5));
      await k.type(')');

      expect(k.line, '(abc)');
      expect(k.caret, 5);

      await teardownEditor(tester);
    });

    testWidgets('a change of the composing range alone keeps the closer', (
      tester,
    ) async {
      final k = await pumpEditor(tester, '');

      await k.type('(');
      // The view the input method holds is rebuilt with another composing
      // range and nothing else: the closer is still where pairing put it.
      k.controller.composing = const TextRange(start: 0, end: 1);
      await tester.pump();
      await k.type(')');

      expect(k.line, '()');
      expect(k.caret, 2);

      await teardownEditor(tester);
    });

    testWidgets('a caret move forgets the auto-inserted closer', (
      tester,
    ) async {
      final k = await pumpEditor(tester, '');

      await k.type('(');
      expect(k.line, '()');
      k.controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      await tester.pump();
      k.controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 1,
      );
      await tester.pump();
      await k.type(')');

      expect(k.line, '())');

      await teardownEditor(tester);
    });

    testWidgets('a programmatic edit forgets it too', (tester) async {
      final k = await pumpEditor(tester, '');

      await k.type('(');
      k.controller.replaceSelection('x');
      await tester.pump();
      expect(k.line, '(x)');
      await k.type(')');

      expect(k.line, '(x))');

      await teardownEditor(tester);
    });
  });

  group('a Backspace between a pair', () {
    testWidgets('deletes both halves and hands the input method the new '
        'line', (tester) async {
      final k = await pumpEditor(tester, '');
      await k.type('(');
      expect(k.line, '()');

      await k.backspace();

      expect(k.line, '');
      expect(k.caret, 0);
      // The keyboard removed `(` alone; without this push it would still
      // hold `)` and its next key would edit text that is gone.
      final pushed = tester.testTextInput.log
          .lastWhere((call) => call.method == 'TextInput.setEditingState')
          .arguments as Map;
      expect(pushed['text'], '​');
      expect(pushed['selectionBase'], 1);
      expect(pushed['selectionExtent'], 1);

      await teardownEditor(tester);
    });
  });

  group('wrapping a selection', () {
    for (final symbol in ['*', '_', '~', '=', '(', '"', '\'']) {
      testWidgets('`$symbol` wraps it and keeps it selected', (tester) async {
        final k = await pumpEditor(tester, 'a word b');
        k.controller.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 2,
          extentIndex: 0,
          extentOffset: 6,
        );
        await tester.pump();

        await k.type(symbol);

        final closer = symbol == '(' ? ')' : symbol;
        expect(k.line, 'a ${symbol}word$closer b');
        expect(
          k.controller.selection,
          const CodeLineSelection(
            baseIndex: 0,
            baseOffset: 3,
            extentIndex: 0,
            extentOffset: 7,
          ),
        );

        await teardownEditor(tester);
      });
    }

    testWidgets('an emphasis symbol without a selection is typed alone', (
      tester,
    ) async {
      final k = await pumpEditor(tester, 'a ');

      await k.type('*');
      await k.type('_');

      expect(k.line, 'a *_');

      await teardownEditor(tester);
    });
  });
}

/// A soft keyboard over [controller]'s first line: each key is one delta
/// against the input method's view of it (`​` + the line, offsets
/// shifted by one), inserted at the caret or replacing the selection.
class _Keyboard {
  _Keyboard(this.tester, this.controller);

  final WidgetTester tester;
  final CodeLineEditingController controller;

  String get line => controller.codeLines[0].text;

  int get caret => controller.selection.extentOffset;

  Future<void> typeAt(int offset, String text) async {
    controller.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: offset,
    );
    await tester.pump();
    await type(text);
  }

  /// One Backspace at a collapsed caret, as Gboard sends it: a deletion
  /// of the unit before the caret in the input method's view.
  Future<void> backspace() async {
    final caret = controller.selection.extentOffset + 1;
    await _send({
      'oldText': '​$line',
      'deltaText': '',
      'deltaStart': caret - 1,
      'deltaEnd': caret,
      'selectionBase': caret - 1,
      'selectionExtent': caret - 1,
      'selectionAffinity': 'TextAffinity.downstream',
      'selectionIsDirectional': false,
      'composingBase': -1,
      'composingExtent': -1,
    });
  }

  Future<void> _send(Map<String, Object> delta) async {
    final setClient = tester.testTextInput.log.lastWhere(
      (call) => call.method == 'TextInput.setClient',
    );
    final client = (setClient.arguments as List)[0] as int;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall('TextInputClient.updateEditingStateWithDeltas', [
          client,
          {
            'deltas': [delta],
          },
        ]),
      ),
      (_) {},
    );
    await tester.pump();
  }

  /// [composing] is in the input method's view (the prefix at 0), as a
  /// keyboard that composes a word sends it.
  Future<void> type(String text, {TextRange composing = TextRange.empty}) async {
    final selection = controller.selection;
    final start = selection.startOffset + 1;
    final end = selection.endOffset + 1;
    await _send({
      'oldText': '​$line',
      'deltaText': text,
      'deltaStart': start,
      'deltaEnd': end,
      'selectionBase': start + text.length,
      'selectionExtent': start + text.length,
      'selectionAffinity': 'TextAffinity.downstream',
      'selectionIsDirectional': false,
      'composingBase': composing.start,
      'composingExtent': composing.end,
    });
  }
}
