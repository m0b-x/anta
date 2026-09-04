import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/editor_edit_tracker.dart';
import 'package:anta/utils/editor_width_calculator.dart';

/// The tracker is the only thing standing between a controller
/// notification and an edit the user did not type, so each of its three
/// decisions is pinned here against a real [CodeLineEditingController]:
///
/// * a growth past [EditorEditTracker.pasteThreshold] is a paste and gets
///   reflowed to the editor's width — and only over the lines the paste
///   actually landed on;
/// * Enter on a list line continues (or ends) that list, merged into the
///   Enter's own undo step — at any nesting depth, which means meeting
///   re_editor's own auto-indent rather than assuming column 0;
/// * anything happening under [EditorEditTracker.runGuarded] is the page
///   editing on purpose, and must not be diffed at all.
///
/// Widths are measured with the test font, which is monospace — the guard
/// in [_Harness] states that, and it is what makes the expected break
/// points below exact rather than approximate.
class _Harness {
  _Harness(String text, {this.autoBreak = true, bool measurable = true}) {
    editor = CodeLineEditingController.fromText(text);
    calculator = EditorWidthCalculator(
      config: EditorWidthConfig(editorContainerKey: GlobalKey(), fontSize: 10),
      editorPadding: EdgeInsets.zero,
    );
    // Ten glyphs wide: every line of ten characters or fewer fits.
    availableWidth = calculator.measureTextWidth('0123456789');
    tracker = EditorEditTracker(
      controller: editor,
      autoBreakLongLines: () => autoBreak,
      pasteContext: () => measurable
          ? (calculator: calculator, availableWidth: availableWidth)
          : null,
      onLinesReformatted: reformatted.add,
    );
    tracker.syncLength();
  }

  bool autoBreak;
  final List<int> reformatted = [];

  late final CodeLineEditingController editor;
  late final EditorWidthCalculator calculator;
  late final double availableWidth;
  late final EditorEditTracker tracker;

  List<String> get lines => [
    for (final line in editor.codeLines.toList()) line.text,
  ];

  /// Types (or pastes) [text] at [index]/[offset], the way the editor would
  /// deliver it: the controller edits, then the page's listener runs.
  void insertAt(int index, int offset, String text) {
    editor.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
    editor.replaceSelection(text);
    tracker.onTextChanged();
  }

  /// Presses Enter at [index]/[offset] and lets the listener react.
  void pressEnter(int index, int offset) {
    editor.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
    editor.applyNewLine();
    tracker.onTextChanged();
  }

  void dispose() => editor.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the width assumptions this file rests on', () {
    test('ten test-font glyphs fit and eleven do not', () {
      final h = _Harness('x');

      expect(
        h.calculator.measureTextWidth('mmmmmmmmm'),
        lessThanOrEqualTo(h.availableWidth),
      );
      expect(
        h.calculator.measureTextWidth('mmmmmmmmmmm'),
        greaterThan(h.availableWidth),
      );

      h.dispose();
    });
  });

  group('paste reflow', () {
    test('breaks the pasted line and leaves the rest alone', () {
      final h = _Harness('head\ntail');

      h.insertAt(0, 4, ' aaaa bbbb cccc dddd eeee');

      expect(h.lines, ['head aaaa', 'bbbb cccc', 'dddd eeee', 'tail']);
      expect(h.reformatted, [1]);
      // The caret lands at the end of the reformatted block.
      expect(h.editor.selection.baseIndex, 2);
      expect(h.editor.selection.baseOffset, 'dddd eeee'.length);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('paste and reflow are one undo step', () {
      final h = _Harness('head\ntail');

      h.insertAt(0, 4, ' aaaa bbbb cccc dddd eeee');
      expect(h.lines, hasLength(4));

      h.editor.undo();

      expect(h.lines, ['head', 'tail']);

      h.dispose();
    });

    test('an insert at or below the threshold is typing, not a paste', () {
      final h = _Harness('head\ntail');

      // Exactly `pasteThreshold` characters: the diff must be strictly
      // greater before anything is reflowed, over-long line or not.
      const typed = ' aaaa bbbb cccc dddd';
      expect(typed.length, EditorEditTracker.pasteThreshold);
      h.insertAt(0, 4, typed);

      expect(h.lines, ['head aaaa bbbb cccc dddd', 'tail']);
      expect(h.reformatted, isEmpty);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('a shrinking edit is never reflowed', () {
      final h = _Harness('head aaaa bbbb cccc dddd eeee\ntail');

      h.editor.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 4,
        extentIndex: 0,
        extentOffset: 29,
      );
      h.editor.replaceSelection('');
      h.tracker.onTextChanged();

      expect(h.lines, ['head', 'tail']);
      expect(h.reformatted, isEmpty);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('auto-break off leaves a pasted over-long line alone', () {
      final h = _Harness('head\ntail', autoBreak: false);

      h.insertAt(0, 4, ' aaaa bbbb cccc dddd eeee');

      expect(h.lines, ['head aaaa bbbb cccc dddd eeee', 'tail']);
      expect(h.reformatted, isEmpty);
      // The length is still resynced, or the next keystroke diffs stale.
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('an unmeasurable editor leaves a pasted line alone', () {
      final h = _Harness('head\ntail', measurable: false);

      h.insertAt(0, 4, ' aaaa bbbb cccc dddd eeee');

      expect(h.lines, ['head aaaa bbbb cccc dddd eeee', 'tail']);
      expect(h.reformatted, isEmpty);

      h.dispose();
    });

    test('a multi-line paste reflows every line it landed on', () {
      final h = _Harness('head\ntail');

      h.insertAt(0, 4, ' aaaa bbbb cccc\ndddd eeee ffff');

      expect(h.lines, ['head aaaa', 'bbbb cccc', 'dddd eeee', 'ffff', 'tail']);
      expect(h.reformatted, [2]);

      h.dispose();
    });

    test('nothing over-long means no reflow and no snackbar', () {
      final h = _Harness('head\ntail');

      h.insertAt(0, 4, '\nshort\nalso okay');

      expect(h.lines, ['head', 'short', 'also okay', 'tail']);
      expect(h.reformatted, isEmpty);

      h.dispose();
    });
  });

  group('Enter on a top-level list line', () {
    test('continues the list prefix onto the new line', () {
      final h = _Harness('- squat 5x5\nplain');

      h.pressEnter(0, '- squat 5x5'.length);

      expect(h.lines, ['- squat 5x5', '- ', 'plain']);
      expect(h.editor.selection.baseIndex, 1);
      expect(h.editor.selection.baseOffset, 2);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('the continuation is part of the Enter undo step', () {
      final h = _Harness('- squat 5x5\nplain');

      h.pressEnter(0, '- squat 5x5'.length);
      expect(h.lines[1], '- ');

      h.editor.undo();

      expect(h.lines, ['- squat 5x5', 'plain']);

      h.dispose();
    });

    test('increments an ordered marker', () {
      final h = _Harness('3. third\nplain');

      h.pressEnter(0, '3. third'.length);

      expect(h.lines, ['3. third', '4. ', 'plain']);
      expect(h.editor.selection.baseOffset, '4. '.length);

      h.dispose();
    });

    test('continues a task item unchecked', () {
      final h = _Harness('- [x] done\nplain');

      h.pressEnter(0, '- [x] done'.length);

      expect(h.lines, ['- [x] done', '- [ ] ', 'plain']);

      h.dispose();
    });

    test('Enter on an empty item drops the item line', () {
      final h = _Harness('- \nplain');

      h.pressEnter(0, 2);

      expect(h.lines, ['', 'plain']);
      expect(h.editor.selection.baseIndex, 0);
      expect(h.editor.selection.baseOffset, 0);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('dropping the empty item is part of the Enter undo step', () {
      final h = _Harness('- \nplain');

      h.pressEnter(0, 2);
      expect(h.lines, ['', 'plain']);

      h.editor.undo();

      expect(h.lines, ['- ', 'plain']);

      h.dispose();
    });

    test('a plain line gets no prefix', () {
      final h = _Harness('just prose\nplain');

      h.pressEnter(0, 'just prose'.length);

      expect(h.lines, ['just prose', '', 'plain']);

      h.dispose();
    });

    test('Enter on the very first line is left to the editor', () {
      final h = _Harness('- squat 5x5');

      // The caret ends up on line 1 here too, but line 0 above it is the
      // list line only because the split created it — there is nothing to
      // continue from above line 0.
      h.pressEnter(0, 0);

      expect(h.lines, ['', '- squat 5x5']);

      h.dispose();
    });
  });

  /// re_editor's `applyNewLine` copies the previous line's leading spaces
  /// onto the line it creates and parks the caret after them, so a nested
  /// item never reaches the tracker with the caret at column 0. The
  /// continuation has to meet it where it lands, and strip that copy before
  /// applying a prefix that already carries the indentation itself.
  group('Enter on a nested list line', () {
    test('continues a nested bullet at its own depth', () {
      final h = _Harness('  - nested\nplain');

      h.pressEnter(0, '  - nested'.length);

      expect(h.lines, ['  - nested', '  - ', 'plain']);
      expect(h.editor.selection.baseIndex, 1);
      expect(h.editor.selection.baseOffset, 4);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('continues a deeply nested task unchecked', () {
      final h = _Harness('    - [ ] deep\nplain');

      h.pressEnter(0, '    - [ ] deep'.length);

      expect(h.lines, ['    - [ ] deep', '    - [ ] ', 'plain']);
      expect(h.editor.selection.baseOffset, '    - [ ] '.length);

      h.dispose();
    });

    test('increments a nested ordered marker', () {
      final h = _Harness('  3. step\nplain');

      h.pressEnter(0, '  3. step'.length);

      expect(h.lines, ['  3. step', '  4. ', 'plain']);
      expect(h.editor.selection.baseOffset, '  4. '.length);

      h.dispose();
    });

    test('Enter mid-item splits the item and keeps the depth', () {
      final h = _Harness('  - nested\nplain');

      h.pressEnter(0, '  - nes'.length);

      expect(h.lines, ['  - nes', '  - ted', 'plain']);
      expect(h.editor.selection.baseOffset, 4);

      h.dispose();
    });

    test('the nested continuation is one undo step with the Enter', () {
      final h = _Harness('  - nested\nplain');

      h.pressEnter(0, '  - nested'.length);
      expect(h.lines[1], '  - ');

      h.editor.undo();

      expect(h.lines, ['  - nested', 'plain']);

      h.dispose();
    });

    test('Enter on a nested empty item drops it back to column 0', () {
      final h = _Harness('  - \nplain');

      h.pressEnter(0, '  - '.length);

      // The copied indentation goes with the marker line, so ending a
      // nested list looks exactly like ending a top-level one.
      expect(h.lines, ['', 'plain']);
      expect(h.editor.selection.baseIndex, 0);
      expect(h.editor.selection.baseOffset, 0);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('dropping the nested empty item is one undo step', () {
      final h = _Harness('  - \nplain');

      h.pressEnter(0, '  - '.length);
      expect(h.lines, ['', 'plain']);

      h.editor.undo();

      expect(h.lines, ['  - ', 'plain']);

      h.dispose();
    });

    test('a tab-indented item keeps its tab', () {
      // The fork's auto-indent copies spaces only, so nothing was copied
      // here — the whole indent comes from the prefix instead.
      final h = _Harness('\t- nested\nplain');

      h.pressEnter(0, '\t- nested'.length);

      expect(h.lines, ['\t- nested', '\t- ', 'plain']);
      expect(h.editor.selection.baseOffset, 3);

      h.dispose();
    });

    test('an indented plain line keeps the auto-indent, untouched', () {
      final h = _Harness('  plain prose\nplain');

      h.pressEnter(0, '  plain prose'.length);

      expect(h.lines, ['  plain prose', '  ', 'plain']);
      expect(h.editor.selection.baseOffset, 2);

      h.dispose();
    });

    test('a caret at the indent column of an unrelated line is ignored', () {
      final h = _Harness('  - item\nxy');

      // One typed character leaves the caret at column 2 of line 1 — the
      // same column the split would have used — but line 1 does not start
      // with the item's indentation, so nothing may be continued onto it.
      h.insertAt(1, 1, 'z');

      expect(h.lines, ['  - item', 'xzy']);
      expect(h.editor.selection.baseOffset, 2);

      h.dispose();
    });

    test('a caret past the end of a short line is ignored', () {
      final h = _Harness('    - item\nab');

      // A shape `applyNewLine` can never produce — the line below the item
      // is shorter than the item's indentation — reached by growing the
      // document and then parking the caret there. Comparing indentation
      // must not run off the end of the line.
      h.editor.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 10,
      );
      h.editor.replaceSelection('!');
      h.editor.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 4,
      );
      h.tracker.onTextChanged();

      expect(h.lines, ['    - item!', 'ab']);

      h.dispose();
    });
  });

  group('runGuarded', () {
    test('raises the guard for the duration of the op', () {
      final h = _Harness('head');
      bool seenInside = false;

      h.tracker.runGuarded(() => seenInside = h.tracker.isProcessing);

      expect(seenInside, isTrue);
      expect(h.tracker.isProcessing, isFalse);

      h.dispose();
    });

    test('swallows the notification the op fires', () {
      final h = _Harness('- squat 5x5\nplain');

      h.tracker.runGuarded(() {
        h.editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 11,
        );
        h.editor.applyNewLine();
        // What the page's listener would deliver, synchronously, mid-op.
        h.tracker.onTextChanged();
      });

      // No list continuation: the tracker never diffed this edit.
      expect(h.lines, ['- squat 5x5', '', 'plain']);

      h.dispose();
    });

    test('never reflows a programmatic insert as a paste', () {
      final h = _Harness('head\ntail');

      h.tracker.runGuarded(() {
        h.editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 4,
        );
        h.editor.replaceSelection(' aaaa bbbb cccc dddd eeee');
        h.tracker.onTextChanged();
      });

      expect(h.lines, ['head aaaa bbbb cccc dddd eeee', 'tail']);
      expect(h.reformatted, isEmpty);

      h.dispose();
    });

    test('resyncs the length, so the next keystroke is not a paste', () {
      final h = _Harness('head\ntail');

      h.tracker.runGuarded(() {
        h.editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 4,
        );
        h.editor.replaceSelection(' aaaa bbbb cccc dddd eeee');
      });
      expect(h.tracker.previousTextLength, h.editor.textLength);

      // One more character: without the resync this would diff as a
      // 26-character paste and reflow the line.
      h.insertAt(0, 29, '!');

      expect(h.lines, ['head aaaa bbbb cccc dddd eeee!', 'tail']);
      expect(h.reformatted, isEmpty);

      h.dispose();
    });

    test('lowers the guard even when the op throws', () {
      final h = _Harness('head');

      expect(
        () => h.tracker.runGuarded(() => throw StateError('boom')),
        throwsStateError,
      );
      expect(h.tracker.isProcessing, isFalse);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });
  });

  group('reformatInserted', () {
    /// Over-long on its own, so an untouched copy of it above and below the
    /// insert proves the reflow stayed inside the inserted range.
    const overlong = 'wwww xxxx yyyy zzzz';

    test('reflows only the lines the insert landed on', () {
      final h = _Harness('$overlong\nhead\n$overlong');
      final before = h.editor.textLength;

      h.tracker.runGuarded(() {
        h.editor.selection = const CodeLineSelection.collapsed(
          index: 1,
          offset: 4,
        );
        h.editor.replaceSelection(' aaaa bbbb cccc dddd');
      });
      h.tracker.reformatInserted(beforeLength: before);

      expect(h.lines, [overlong, 'head aaaa', 'bbbb cccc', 'dddd', overlong]);
      expect(h.reformatted, [1]);
      expect(h.tracker.previousTextLength, h.editor.textLength);

      h.dispose();
    });

    test('an insert that added nothing is not reflowed', () {
      final h = _Harness('$overlong\nhead');

      h.tracker.reformatInserted(beforeLength: h.editor.textLength);

      expect(h.lines, [overlong, 'head']);
      expect(h.reformatted, isEmpty);

      h.dispose();
    });

    test('respects the auto-break setting', () {
      final h = _Harness('head\ntail', autoBreak: false);
      final before = h.editor.textLength;

      h.tracker.runGuarded(() {
        h.editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 4,
        );
        h.editor.replaceSelection(' aaaa bbbb cccc dddd');
      });
      h.tracker.reformatInserted(beforeLength: before);

      expect(h.lines, ['head aaaa bbbb cccc dddd', 'tail']);
      expect(h.reformatted, isEmpty);

      h.dispose();
    });
  });
}
