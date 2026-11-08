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

  /// The shape readers a host reads a soft keyboard's Space from: a typed
  /// space, and the double-space period that rewrites the one before it.
  group('a soft keyboard Space', () {
    CodeLineEditingController caretAt(String text, int offset) {
      final controller = controllerOf(text);
      controller.selection = CodeLineSelection.collapsed(
        index: 0,
        offset: offset,
      );
      return controller;
    }

    TextEditingValue line(String text, int caret, {TextRange? composing}) =>
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret),
          composing: composing ?? TextRange.empty,
        );

    group('isSingleInsert', () {
      test('one space at the caret, the caret after it', () {
        final controller = caretAt('- a', 2);

        expect(controller.isSingleInsert(line('-  a', 3), 0x20), isTrue);
        expect(controller.isSingleInsert(line('-  a', 3), 0x2E), isFalse);
      });

      test('not while the controller is already composing', () {
        final controller = caretAt('- ab', 4);
        controller.composing = const TextRange(start: 2, end: 4);

        expect(controller.isSingleInsert(line('- ab ', 5), 0x20), isFalse);
      });

      test('not with a composing region on the commit', () {
        final controller = caretAt('- ', 2);

        expect(
          controller.isSingleInsert(
            line('-  ', 3, composing: const TextRange(start: 2, end: 3)),
            0x20,
          ),
          isFalse,
        );
      });

      test('not over a selection replaced by the space', () {
        final controller = controllerOf('- ab');
        controller.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 2,
          extentIndex: 0,
          extentOffset: 4,
        );

        expect(controller.isSingleInsert(line('-  ', 3), 0x20), isFalse);
      });

      test('not for a two-unit commit', () {
        final controller = caretAt('- ', 2);

        expect(controller.isSingleInsert(line('-   ', 4), 0x20), isFalse);
      });

      test('not for a space inserted before the caret', () {
        final controller = caretAt('-a', 2);

        // `-a` → `- a`: one space more, but at 1, not at the caret.
        expect(controller.isSingleInsert(line('- a', 2), 0x20), isFalse);
        expect(controller.isSingleInsert(line('- a', 3), 0x20), isFalse);
      });
    });

    group('isDoubleSpacePeriod', () {
      test('the space before the caret rewritten as `. `', () {
        final controller = caretAt('- [ ] ', 6);

        expect(controller.isDoubleSpacePeriod(line('- [ ]. ', 7)), isTrue);
        expect(
          controller.isSingleInsert(line('- [ ]. ', 7), 0x20),
          isFalse,
          reason: 'the shape a typed space is not',
        );
      });

      test('with text after the caret kept', () {
        final controller = caretAt('ab c', 3);

        expect(controller.isDoubleSpacePeriod(line('ab. c', 4)), isTrue);
      });

      test('not while the controller is already composing', () {
        final controller = caretAt('ab ', 3);
        controller.composing = const TextRange(start: 0, end: 2);

        expect(controller.isDoubleSpacePeriod(line('ab. ', 4)), isFalse);
      });

      test('not with a composing region on the commit', () {
        final controller = caretAt('ab ', 3);

        expect(
          controller.isDoubleSpacePeriod(
            line('ab. ', 4, composing: const TextRange(start: 0, end: 3)),
          ),
          isFalse,
        );
      });

      test('not over a selection', () {
        final controller = controllerOf('ab ');
        controller.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 2,
          extentIndex: 0,
          extentOffset: 3,
        );

        expect(controller.isDoubleSpacePeriod(line('ab. ', 4)), isFalse);
      });

      test('not when the unit before the caret is no space', () {
        final controller = caretAt('abc', 3);

        // `c` rewritten as `. ` is a correction, not the period.
        expect(controller.isDoubleSpacePeriod(line('ab. ', 4)), isFalse);
      });

      test('not for a period typed after the space', () {
        final controller = caretAt('ab ', 3);

        expect(controller.isDoubleSpacePeriod(line('ab . ', 5)), isFalse);
        expect(controller.isDoubleSpacePeriod(line('ab .', 4)), isFalse);
      });

      test('not for a space rewritten away from the caret', () {
        final controller = caretAt('a b ', 4);

        // The space at 1, not the one before the caret.
        expect(controller.isDoubleSpacePeriod(line('a. b ', 5)), isFalse);
        expect(controller.isDoubleSpacePeriod(line('a. b ', 3)), isFalse);
      });
    });
  });
}
