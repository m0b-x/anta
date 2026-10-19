import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The controller's `edit(TextEditingValue)` — the only door a soft
/// keyboard has into the document. The input method sees the base line
/// alone (`_CodeInputController._buildTextEditingValue`), so every value
/// here is that one line's text as the keyboard would send it back.
void main() {
  CodeLineEditingController controllerOf(String text) {
    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    return controller;
  }

  group('a multi-line commit over a selection across lines', () {
    test('forward: the base line prefix is not pasted twice', () {
      final controller = controllerOf('abc\ndef');
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 1,
        extentIndex: 1,
        extentOffset: 1,
      );

      // The IME held `abc` with `bc` selected and pasted `X\nY` over it.
      controller.edit(
        const TextEditingValue(
          text: 'aX\nY',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );

      expect(controller.text, 'aX\nYef');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 1),
      );
    });

    test('backward: the base line suffix is not pasted twice', () {
      final controller = controllerOf('abc\ndef');
      controller.selection = const CodeLineSelection(
        baseIndex: 1,
        baseOffset: 1,
        extentIndex: 0,
        extentOffset: 1,
      );

      // The IME held `def` with `d` selected and pasted `X\nY` over it.
      controller.edit(
        const TextEditingValue(
          text: 'X\nYef',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(controller.text, 'aX\nYef');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 1),
      );
    });

    test('a paste whose text ends like the end line is still kept whole', () {
      final controller = controllerOf('abc\ndef');
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 1,
        extentIndex: 1,
        extentOffset: 1,
      );

      controller.edit(
        const TextEditingValue(
          text: 'aX\nef',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      expect(controller.text, 'aX\nefef');
    });

    test('a commit over a selection on one line is unchanged', () {
      final controller = controllerOf('abc');
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 1,
        extentIndex: 0,
        extentOffset: 2,
      );

      controller.edit(
        const TextEditingValue(
          text: 'aX\nYc',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );

      expect(controller.text, 'aX\nYc');
    });
  });

  group('a soft keyboard Backspace', () {
    // A frozen grouping clock: on the real Stopwatch a stall past 500 ms
    // between two Backspaces would open a second undo node.
    setUp(() => debugUndoGroupingClock = () => Duration.zero);
    tearDown(() => debugUndoGroupingClock = null);

    CodeLineEditingController caretAt(String text, int offset) {
      final controller = controllerOf(text);
      controller.selection = CodeLineSelection.collapsed(
        index: 0,
        offset: offset,
      );
      return controller;
    }

    void backspace(CodeLineEditingController controller) {
      final line = controller.codeLines[0].text;
      final caret = controller.selection.extentOffset;
      controller.edit(
        TextEditingValue(
          text: line.substring(0, caret - 1) + line.substring(caret),
          selection: TextSelection.collapsed(offset: caret - 1),
        ),
      );
    }

    test('deletes both halves of an empty pair', () {
      final controller = caretAt('a()', 2);

      backspace(controller);

      expect(controller.text, 'a');
      expect(controller.selection.extentOffset, 1);
    });

    test('deletes a whole indent unit', () {
      final controller = caretAt('    x', 4);

      backspace(controller);

      expect(controller.text, '  x');
      expect(controller.selection.extentOffset, 2);
    });

    test('a run of them is one typing undo node, not one per unit', () {
      // Typing then deleting is two steps since E18 (an insert/delete
      // switch opens one); the Backspaces among themselves stay one.
      final controller = caretAt('ab', 2);

      for (final typed in ['abc', 'abcd']) {
        controller.edit(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
      }
      backspace(controller);
      backspace(controller);
      expect(controller.text, 'ab');

      controller.undo();
      expect(controller.text, 'abcd');
      controller.undo();
      expect(controller.text, 'ab');
    });

    test('a non-ASCII unit is removed exactly as the keyboard sent it', () {
      // The keyboard removed the combining accent alone; the editor's own
      // Backspace would take the whole grapheme with it.
      final controller = caretAt('é', 2);

      backspace(controller);

      expect(controller.text, 'e');
    });

    test('an ASCII unit after a Prepend character is removed alone', () {
      // U+0600 + `1` is one grapheme (UAX #29 GB9b): the editor's own
      // Backspace would take the Prepend character with the digit.
      final controller = caretAt('؀1', 2);

      backspace(controller);

      expect(controller.text, '؀');
      expect(controller.selection.extentOffset, 1);
    });

    test("deletes one half of a '' pair: a single quote does not pair", () {
      final controller = caretAt("a''", 2);

      backspace(controller);

      expect(controller.text, "a'");
      expect(controller.selection.extentOffset, 1);

      // The pairs that still auto-close still delete together.
      for (final pair in ['""', '``']) {
        final paired = caretAt('a$pair', 2);
        backspace(paired);
        expect(paired.text, 'a', reason: pair);
      }
    });

    test('a composing rewrite is applied as sent', () {
      final controller = caretAt('a()', 2);

      controller.edit(
        const TextEditingValue(
          text: 'a)',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );

      expect(controller.text, 'a)');
    });
  });
}
