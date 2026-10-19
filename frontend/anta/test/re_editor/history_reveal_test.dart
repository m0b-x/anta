import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// Undo and redo restore a caret together with the text, and the view has
/// to follow it: after the frame the restored value lays out, the caret
/// line is on screen even when the viewport had been scrolled far away
/// from the edit in the meantime.
void main() {
  const double viewportHeight = 220.0;
  const int editedLine = 50;

  String document() {
    final buffer = StringBuffer();
    for (var i = 0; i < 60; i++) {
      buffer.writeln('line $i');
    }
    return buffer.toString();
  }

  Future<ScrollEditor> editFarDownThenScrollToTop(WidgetTester tester) async {
    final e = await pumpScrollEditor(
      tester,
      text: document(),
      width: 300,
      height: viewportHeight,
    );
    await settle(tester);
    e.controller.selection = const CodeLineSelection.collapsed(
      index: editedLine,
      offset: 0,
    );
    e.controller.replaceSelection('x');
    await settle(tester);
    expect(displayedParagraphAt(e.notifier, editedLine), isNotNull);

    e.scroll.verticalScroller.position.jumpTo(0);
    await settle(tester);
    expect(pixelsOf(e.scroll), 0);
    return e;
  }

  void expectCaretLineOnScreen(ScrollEditor e) {
    final paragraph = displayedParagraphAt(e.notifier, editedLine);
    expect(paragraph, isNotNull, reason: 'the caret line is not laid out');
    expect(paragraph!.top, greaterThanOrEqualTo(-0.01));
    expect(paragraph.bottom, lessThanOrEqualTo(viewportHeight + 0.01));
  }

  testWidgets('undo scrolls the restored caret into view', (tester) async {
    final e = await editFarDownThenScrollToTop(tester);

    e.controller.undo();
    await settle(tester);

    expect(e.controller.selection.extentIndex, editedLine);
    expectCaretLineOnScreen(e);

    await teardownEditor(tester);
  });

  testWidgets('redo scrolls the restored caret into view', (tester) async {
    final e = await editFarDownThenScrollToTop(tester);
    e.controller.undo();
    await settle(tester);
    e.scroll.verticalScroller.position.jumpTo(0);
    await settle(tester);

    e.controller.redo();
    await settle(tester);

    expect(e.controller.selection.extentIndex, editedLine);
    expectCaretLineOnScreen(e);

    await teardownEditor(tester);
  });

  testWidgets('undo and redo with nothing to restore leave the view where '
      'it is', (tester) async {
    final e = await editFarDownThenScrollToTop(tester);
    expect(e.controller.canRedo, isFalse);

    e.controller.redo();
    await settle(tester);
    expect(pixelsOf(e.scroll), 0, reason: 'nothing to redo');

    e.controller.undo();
    await settle(tester);
    e.scroll.verticalScroller.position.jumpTo(0);
    await settle(tester);
    expect(e.controller.canUndo, isFalse);

    e.controller.undo();
    await settle(tester);
    expect(pixelsOf(e.scroll), 0, reason: 'nothing to undo');

    await teardownEditor(tester);
  });
}
