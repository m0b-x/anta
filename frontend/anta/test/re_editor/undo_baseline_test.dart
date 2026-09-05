import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The undo baseline: a controller is constructed around an empty document,
/// and every seeding write used to be `set text` — a revocable op — so a
/// freshly opened note always had exactly one undo step, whose target was
/// that empty document. Pressing undo before typing anything wiped the note
/// (and auto-save persisted the wipe).
///
/// `loadText` is the fix, in the fork rather than at every call site: it is
/// the load operation, never undoable, and it drops the history recorded
/// before it, so undo can only ever land on the loaded text.
void main() {
  void applyEdit(CodeLineEditingController controller, String text) {
    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: CodeLines.fromText(text),
        selection: CodeLineSelection.collapsed(index: 0, offset: text.length),
      );
    });
  }

  group('loadText', () {
    test('a freshly seeded controller has nothing to undo', () {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      controller.loadText('first line\nsecond line');

      expect(controller.text, 'first line\nsecond line');
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);

      // And an undo pressed anyway is a no-op, not a wipe.
      controller.undo();
      expect(controller.text, 'first line\nsecond line');
    });

    test('set text, by contrast, is an edit the empty document sits under', () {
      // The shape of the bug loadText exists for: pinned so the difference
      // between the two writes stays deliberate.
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      controller.text = 'first line';

      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.text, '');
    });

    test('the first undo after an edit lands on the loaded text', () {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      controller.loadText('loaded');
      applyEdit(controller, 'loaded and typed');
      expect(controller.canUndo, isTrue);

      controller.undo();

      expect(controller.text, 'loaded');
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      controller.undo();
      expect(controller.text, 'loaded', reason: 'never below the baseline');
    });

    test('a mid-session load drops both the undo and the redo chain', () {
      final controller = CodeLineEditingController.fromText('start');
      addTearDown(controller.dispose);

      applyEdit(controller, 'edit 1');
      applyEdit(controller, 'edit 2');
      controller.undo();
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);

      controller.loadText('swapped in');

      expect(controller.text, 'swapped in');
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      controller.undo();
      controller.redo();
      expect(controller.text, 'swapped in');
    });

    test('loading an empty string is the blank baseline', () {
      final controller = CodeLineEditingController.fromText('start');
      addTearDown(controller.dispose);

      controller.loadText('');

      expect(controller.codeLines.length, 1);
      expect(controller.text, '');
      expect(controller.canUndo, isFalse);

      applyEdit(controller, 'typed');
      controller.undo();
      expect(controller.text, '');
      expect(controller.canUndo, isFalse);
    });

    test('a load resets the selection to the document start', () {
      final controller = CodeLineEditingController.fromText('start');
      addTearDown(controller.dispose);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );

      controller.loadText('a\nb');

      expect(controller.selection.baseIndex, 0);
      expect(controller.selection.baseOffset, 0);
    });

    test('a listener sees the load exactly once', () {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.loadText('loaded');

      expect(notifications, 1);
    });
  });

  group('selection-only changes', () {
    test('a caret move after a load is not an undo step', () {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      controller.loadText('first line\nsecond line');

      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 3,
      );

      expect(controller.canUndo, isFalse);
      controller.undo();
      expect(controller.text, 'first line\nsecond line');
      expect(controller.selection.baseIndex, 1);
      expect(controller.selection.baseOffset, 3);
    });

    test('typing after a caret move undoes to the loaded text', () {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      controller.loadText('first line\nsecond line');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 'first line'.length,
      );

      controller.replaceSelection(' typed');
      expect(controller.text, 'first line typed\nsecond line');
      expect(controller.canUndo, isTrue);

      controller.undo();

      expect(controller.text, 'first line\nsecond line');
      expect(controller.canUndo, isFalse);
      expect(controller.selection.baseOffset, 'first line'.length);
    });

    test('a caret move after an undo keeps the redo chain', () {
      final controller = CodeLineEditingController.fromText('start');
      addTearDown(controller.dispose);
      applyEdit(controller, 'edit 1');
      applyEdit(controller, 'edit 2');
      controller.undo();
      expect(controller.canRedo, isTrue);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );

      expect(controller.canRedo, isTrue);
      controller.redo();
      expect(controller.text, 'edit 2');
    });

    test('an IME composing change is not an undo step either', () {
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);
      controller.loadText('abc');

      controller.composing = const TextRange(start: 0, end: 2);

      expect(controller.canUndo, isFalse);
    });
  });

  group('fromTextAsync', () {
    test('the async load is the baseline too', () async {
      final controller = CodeLineEditingController.fromTextAsync('async text');
      addTearDown(controller.dispose);

      await pumpEventQueue();

      expect(controller.text, 'async text');
      expect(controller.canUndo, isFalse);
      controller.undo();
      expect(controller.text, 'async text');
    });
  });
}
