import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

void main() {
  const double viewportWidth = 300.0;
  const double viewportHeight = 200.0;
  const int lineCount = 200;

  String buildDocument() {
    final buffer = StringBuffer();
    for (var i = 0; i < lineCount; i++) {
      if (i % 7 == 0) {
        buffer.write('line $i ${'padding ' * 8}');
      } else {
        buffer.write('line $i');
      }
      if (i != lineCount - 1) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  Future<
    ({
      CodeLineEditingController controller,
      FocusNode focusNode,
      CodeIndicatorValueNotifier notifier,
    })
  >
  pumpEditor(WidgetTester tester) async {
    final controller = CodeLineEditingController.fromText(buildDocument());
    final scroll = CodeScrollController();
    final focusNode = FocusNode();
    late CodeIndicatorValueNotifier notifier;
    addTearDown(() {
      focusNode.dispose();
      scroll.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: viewportWidth,
              height: viewportHeight,
              child: CodeEditor(
                controller: controller,
                scrollController: scroll,
                focusNode: focusNode,
                autofocus: false,
                wordWrap: true,
                padding: EdgeInsets.zero,
                style: const CodeEditorStyle(fontSize: kTestFontSize),
                indicatorBuilder: (context, editing, chunk, valueNotifier) {
                  notifier = valueNotifier;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (controller: controller, focusNode: focusNode, notifier: notifier);
  }

  Future<List<int>> scrollToWindowBelowTop(
    WidgetTester tester,
    CodeLineEditingController controller,
    CodeIndicatorValueNotifier notifier,
  ) async {
    controller.makePositionVisible(
      const CodeLinePosition(index: 120, offset: 0),
    );
    await settle(tester);
    final indices = displayedIndices(notifier);
    expect(indices.length, greaterThan(2));
    expect(indices.first, greaterThan(0));
    return indices;
  }

  void setSelection(WidgetTester tester, int base, int extent) {
    tester.semantics.performAction(
      textField(),
      SemanticsAction.setSelection,
      args: <String, int>{'base': base, 'extent': extent},
    );
  }

  testWidgets('setSelection offsets are relative to the announced window, not '
      'the document', (tester) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final int first = indices.first;

    setSelection(tester, 3, 3);
    await flushDeferredWork(tester);

    expect(
      e.controller.selection,
      CodeLineSelection.collapsed(index: first, offset: 3),
    );
    expect(e.controller.selection.isCollapsed, isTrue);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a range spanning the first newline of the window becomes a two '
      'line selection', (tester) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final int first = indices.first;
    final int second = indices[1];
    final int firstLength = e.controller.codeLines[first].text.length;

    setSelection(tester, 2, firstLength + 1 + 4);
    await flushDeferredWork(tester);

    expect(
      e.controller.selection,
      CodeLineSelection(
        baseIndex: first,
        baseOffset: 2,
        extentIndex: second,
        extentOffset: 4,
      ),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an offset landing on a newline resolves to the end of the line '
      'before it', (tester) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final int first = indices.first;
    final int firstLength = e.controller.codeLines[first].text.length;

    setSelection(tester, firstLength, firstLength);
    await flushDeferredWork(tester);

    expect(
      e.controller.selection,
      CodeLineSelection.collapsed(index: first, offset: firstLength),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an offset past the end of the window clamps to the last visible '
      'line', (tester) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final int last = indices.last;
    final int lastLength = e.controller.codeLines[last].text.length;
    final int windowLength = expectedWindow(e.notifier, e.controller).length;

    setSelection(tester, windowLength + 500, windowLength + 500);
    await flushDeferredWork(tester);

    expect(
      e.controller.selection,
      CodeLineSelection.collapsed(index: last, offset: lastLength),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('select all over the announced value stops at the window edges', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);

    final indices = displayedIndices(e.notifier);
    expect(indices.first, 0);
    expect(indices.last, lessThan(lineCount - 1));
    final int lastLength = e.controller.codeLines[indices.last].text.length;
    final String window = expectedWindow(e.notifier, e.controller);
    expect(textFieldNode().value, window);

    setSelection(tester, 0, window.length);
    await flushDeferredWork(tester);

    expect(
      e.controller.selection,
      CodeLineSelection(
        baseIndex: indices.first,
        baseOffset: 0,
        extentIndex: indices.last,
        extentOffset: lastLength,
      ),
      reason:
          'the window is what was announced, so select all can only cover '
          'the displayed lines',
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a base after the extent stays a reversed selection', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final int first = indices.first;
    final int second = indices[1];
    final int firstLength = e.controller.codeLines[first].text.length;

    setSelection(tester, firstLength + 1 + 4, 2);
    await flushDeferredWork(tester);

    final CodeLineSelection selection = e.controller.selection;
    expect(selection.baseIndex, second);
    expect(selection.baseOffset, 4);
    expect(selection.extentIndex, first);
    expect(selection.extentOffset, 2);
    expect(selection.start, CodeLinePosition(index: first, offset: 2));
    expect(selection.end, CodeLinePosition(index: second, offset: 4));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('the announced textSelection is the controller selection mapped '
      'back into the window', (tester) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final int first = indices.first;
    final int second = indices[1];
    final int firstLength = e.controller.codeLines[first].text.length;

    e.controller.selection = CodeLineSelection(
      baseIndex: first,
      baseOffset: 1,
      extentIndex: second,
      extentOffset: 5,
    );
    await settle(tester);

    expect(
      textFieldNode().textSelection,
      TextSelection(baseOffset: 1, extentOffset: firstLength + 1 + 5),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a caret outside the window is not announced at all', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    expect(indices, isNot(contains(0)));

    e.controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    await tester.pump();

    final SemanticsNode node = textFieldNode();
    expect(displayedIndices(e.notifier), isNot(contains(0)));
    expect(node.textSelection, isNull);
    expect(node.value, expectedWindow(e.notifier, e.controller));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a selection with one end off screen is not announced either', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    expect(indices, isNot(contains(0)));

    e.controller.selection = CodeLineSelection(
      baseIndex: indices.first,
      baseOffset: 1,
      extentIndex: 0,
      extentOffset: 0,
    );
    await tester.pump();

    final SemanticsNode node = textFieldNode();
    expect(
      node.textSelection,
      isNull,
      reason:
          'the extent has no offset in the announced window, so no '
          'selection can be expressed against it',
    );
    expect(node.value, expectedWindow(e.notifier, e.controller));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('setSelection changes no text and never asks for the keyboard', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final methods = watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);
    final indices = await scrollToWindowBelowTop(
      tester,
      e.controller,
      e.notifier,
    );
    final String text = e.controller.text;
    final String window = expectedWindow(e.notifier, e.controller);
    expect(textFieldNode().value, window);

    methods.clear();
    setSelection(tester, 3, 8);
    await flushDeferredWork(tester);
    await settle(tester);

    expect(e.controller.text, text);
    expect(displayedIndices(e.notifier), indices);
    expect(textFieldNode().value, window);
    expect(methods, isNot(contains('TextInput.show')));
    expect(e.focusNode.hasFocus, isFalse);

    handle.dispose();
    await teardownEditor(tester);
  });
}
