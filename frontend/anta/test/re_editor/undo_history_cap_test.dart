import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// P8: the fork's undo history is a doubly-linked list of whole
/// `CodeLineEditingValue`s — every step pins a complete document snapshot,
/// so an uncapped chain grows for as long as a note stays open.
///
/// The cap (200 steps behind the current value) is asserted only through the
/// public controller API, so the linked-list plumbing stays free to change:
/// what is pinned is how many `undo()` calls a long session still answers,
/// where they land, and that nothing else about undo/redo moved.
void main() {
  const int cap = 200;

  /// One revocable edit, the shape every app-level structural edit uses.
  void applyEdit(CodeLineEditingController controller, String text) {
    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: CodeLines.fromText(text),
        selection: CodeLineSelection.collapsed(index: 0, offset: text.length),
      );
    });
  }

  /// Undoes until the controller says there is nothing left, and reports how
  /// many steps that took.
  int undoToTheEnd(CodeLineEditingController controller) {
    var steps = 0;
    while (controller.canUndo) {
      controller.undo();
      steps++;
      if (steps > 10000) {
        fail('undo never bottomed out');
      }
    }
    return steps;
  }

  test('a long session keeps exactly $cap undo steps', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= 250; i++) {
      applyEdit(controller, 'edit $i');
    }
    expect(controller.text, 'edit 250');

    expect(undoToTheEnd(controller), cap);
    // 250 edits, 200 of them still reachable: the oldest survivor is the
    // value the 50th edit produced. 'start' and edits 1..49 are gone.
    expect(controller.text, 'edit 50');
    expect(controller.canUndo, isFalse);
  });

  test('below the cap every edit is still undoable', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= 50; i++) {
      applyEdit(controller, 'edit $i');
    }

    expect(undoToTheEnd(controller), 50);
    expect(controller.text, 'start');
  });

  test('exactly at the cap the initial value is still reachable', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= cap; i++) {
      applyEdit(controller, 'edit $i');
    }

    expect(undoToTheEnd(controller), cap);
    expect(controller.text, 'start');
  });

  test('one edit past the cap drops the initial value', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= cap + 1; i++) {
      applyEdit(controller, 'edit $i');
    }

    expect(undoToTheEnd(controller), cap);
    expect(controller.text, 'edit 1');
  });

  test('redo still walks back up the surviving chain', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= 250; i++) {
      applyEdit(controller, 'edit $i');
    }

    undoToTheEnd(controller);
    expect(controller.text, 'edit 50');

    var steps = 0;
    while (controller.canRedo) {
      controller.redo();
      steps++;
    }
    expect(steps, cap);
    expect(controller.text, 'edit 250');
  });

  test('a new edit after an undo drops the redo branch', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    applyEdit(controller, 'edit 1');
    applyEdit(controller, 'edit 2');
    applyEdit(controller, 'edit 3');

    controller.undo();
    expect(controller.text, 'edit 2');
    expect(controller.canRedo, isTrue);

    applyEdit(controller, 'branched');
    expect(controller.canRedo, isFalse);
    expect(controller.text, 'branched');

    controller.undo();
    expect(controller.text, 'edit 2');
  });

  test('the window is measured from where editing resumed after an undo', () {
    // The cap counts steps behind the *current* node, not behind the
    // deepest node ever reached: undoing and then editing drops the redo
    // chain, and the surviving history is whatever is still below the
    // point editing resumed at.
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= 250; i++) {
      applyEdit(controller, 'edit $i');
    }
    // 250 edits, capped: the oldest survivor is the 50th edit's value.
    for (var i = 0; i < 150; i++) {
      controller.undo();
    }
    expect(controller.text, 'edit 100');

    applyEdit(controller, 'branched');
    expect(controller.canRedo, isFalse);

    // 'branched' sits one step above 'edit 100', and 'edit 50' is still
    // the oldest survivor, so 51 steps are left.
    expect(undoToTheEnd(controller), 51);
    expect(controller.text, 'edit 50');
  });

  test('eviction resumes from the branch a new edit started', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= 250; i++) {
      applyEdit(controller, 'edit $i');
    }
    for (var i = 0; i < 150; i++) {
      controller.undo();
    }
    applyEdit(controller, 'branched');

    // 'branched' is 51 steps above the oldest survivor, so the next 200
    // edits push the window past it and 'branched' becomes the bottom.
    for (var i = 1; i <= 200; i++) {
      applyEdit(controller, 'after $i');
    }

    expect(undoToTheEnd(controller), cap);
    expect(controller.text, 'branched');
  });

  test('clearHistory drops every step and keeps the content', () {
    final controller = CodeLineEditingController.fromText('start');
    addTearDown(controller.dispose);

    for (var i = 1; i <= 10; i++) {
      applyEdit(controller, 'edit $i');
    }
    expect(controller.canUndo, isTrue);

    controller.clearHistory();

    expect(controller.canUndo, isFalse);
    expect(controller.canRedo, isFalse);
    expect(controller.text, 'edit 10');

    applyEdit(controller, 'after clear');
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.text, 'edit 10');
    expect(controller.canUndo, isFalse);
  });
}
