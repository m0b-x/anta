import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// How typing is cut into undo steps. Typing arrives as `edit()` calls
/// (a soft keyboard's whole view of the caret line); consecutive ones
/// extend one step while they stay on one line, keep one direction
/// (inserting or deleting) and come within 500 ms of each other — the
/// CodeMirror grouping — so Undo steps back by bursts, not by whole lines.
/// An input method's multi-line commit and every programmatic op are
/// steps of their own, and typing after one never extends it.
///
/// The clock is the fork's test seam ([debugUndoGroupingClock]), so a
/// pause costs no real time.
void main() {
  late Duration now;

  setUp(() {
    now = Duration.zero;
    debugUndoGroupingClock = () => now;
  });

  tearDown(() {
    debugUndoGroupingClock = null;
  });

  CodeLineEditingController loaded(String text) {
    final controller = CodeLineEditingController();
    addTearDown(controller.dispose);
    controller.loadText(text);
    return controller;
  }

  /// Rewrites the caret line to [line] with the caret at its end, as a
  /// keyboard does for each key, [after] the previous keystroke.
  void type(
    CodeLineEditingController controller,
    String line, {
    Duration after = const Duration(milliseconds: 100),
  }) {
    now += after;
    controller.edit(
      TextEditingValue(
        text: line,
        selection: TextSelection.collapsed(offset: line.length),
      ),
    );
  }

  List<String> undoAll(CodeLineEditingController controller) {
    final texts = <String>[];
    while (controller.canUndo) {
      controller.undo();
      texts.add(controller.text);
    }
    return texts;
  }

  test('a burst of typing is one step', () {
    final controller = loaded('');

    for (final line in ['a', 'ab', 'abc']) {
      type(controller, line);
    }

    expect(undoAll(controller), ['']);
  });

  test('a pause longer than 500 ms starts a new step', () {
    final controller = loaded('');

    type(controller, 'a');
    type(controller, 'ab');
    type(controller, 'ab ', after: const Duration(milliseconds: 500));
    type(controller, 'ab c', after: const Duration(milliseconds: 501));
    type(controller, 'ab cd');

    expect(undoAll(controller), ['ab ', '']);
  });

  test('switching between inserting and deleting starts a new step', () {
    final controller = loaded('');

    type(controller, 'a');
    type(controller, 'ab');
    type(controller, 'abc');
    type(controller, 'ab');
    type(controller, 'a');
    type(controller, 'ax');

    expect(undoAll(controller), ['a', 'abc', '']);
  });

  test('a multi-line commit is a step of its own', () {
    final controller = loaded('');

    type(controller, 'ab');
    // The keyboard's paste key: its view of the line, with `X\nY` added.
    now += const Duration(milliseconds: 50);
    controller.edit(
      const TextEditingValue(
        text: 'abX\nY',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(controller.text, 'abX\nY');
    type(controller, 'Yz');

    expect(undoAll(controller), ['abX\nY', 'ab', '']);
  });

  test('typing after a programmatic op starts a new step', () {
    final controller = loaded('');

    type(controller, 'ab');
    controller.replaceSelection('X');
    expect(controller.text, 'abX');
    type(controller, 'abXc');

    expect(undoAll(controller), ['abX', 'ab', '']);
  });

  test('a caret-only update on another line does not swallow the next '
      "line's step", () {
    // An input method update that changes no text (here: a composing
    // range on the line the caret was moved to) used to claim the line,
    // so the first real keystroke there extended the previous line's
    // step and one Undo reverted both lines.
    final controller = loaded('\n');

    type(controller, 'a');
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 0,
    );
    controller.edit(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      ),
    );
    type(controller, 'b');

    expect(undoAll(controller), ['a\n', '\n']);
  });

  test('a held hardware Backspace inside a line is one step', () {
    final controller = loaded('abcdef');
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 6,
    );

    for (var i = 0; i < 4; i++) {
      now += const Duration(milliseconds: 50);
      controller.deleteBackward();
    }
    expect(controller.text, 'ab');

    expect(undoAll(controller), ['abcdef']);
  });

  test('a hardware Backspace that merges lines is a step of its own', () {
    final controller = loaded('ab\ncd');
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 2,
    );

    for (var i = 0; i < 3; i++) {
      now += const Duration(milliseconds: 50);
      controller.deleteBackward();
    }
    expect(controller.text, 'ab');
    now += const Duration(milliseconds: 50);
    controller.deleteBackward();
    expect(controller.text, 'a');

    expect(undoAll(controller), ['ab', 'ab\n', 'ab\ncd']);
  });

  test('a hardware Backspace over a selection is a step of its own', () {
    final controller = loaded('abcd');
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 4,
    );
    now += const Duration(milliseconds: 50);
    controller.deleteBackward();
    controller.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 2,
    );
    now += const Duration(milliseconds: 50);
    controller.deleteBackward();
    expect(controller.text, 'c');

    expect(undoAll(controller), ['abc', 'abcd']);
  });

  test('caret moves still fold into the current step', () {
    final controller = loaded('');

    type(controller, 'abc');
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 1,
    );

    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.text, '');
    expect(controller.canUndo, isFalse);
  });
}
