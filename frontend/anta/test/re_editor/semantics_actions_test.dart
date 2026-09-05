import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

void main() {
  const double viewportWidth = 300.0;
  const double viewportHeight = 200.0;

  const String document = 'line 0\nline 1\nline 2\nline 3';

  Future<
    ({
      CodeLineEditingController controller,
      FocusNode focusNode,
      CodeIndicatorValueNotifier notifier,
    })
  >
  pumpEditor(WidgetTester tester, {bool readOnly = false}) async {
    final controller = CodeLineEditingController.fromText(document);
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
                readOnly: readOnly,
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

  testWidgets('the text field node exposes tap, which focuses and opens the '
      'keyboard', (tester) async {
    final handle = tester.ensureSemantics();
    final methods = watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);

    expect(e.focusNode.hasFocus, isFalse);
    expect(
      textFieldNode().getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    methods.clear();
    tester.semantics.performAction(textField(), SemanticsAction.tap);
    await flushDeferredWork(tester);

    expect(e.focusNode.hasFocus, isTrue);
    expect(
      e.controller.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 0),
    );
    expect(methods, contains('TextInput.setClient'));
    expect(methods, contains('TextInput.show'));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a second tap does not reset a caret the user moved', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);

    tester.semantics.performAction(textField(), SemanticsAction.tap);
    await flushDeferredWork(tester);

    e.controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 3,
    );
    await settle(tester);

    tester.semantics.performAction(textField(), SemanticsAction.tap);
    await flushDeferredWork(tester);

    expect(
      e.controller.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 3),
    );
    expect(e.focusNode.hasFocus, isTrue);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('on macOS accessibility focus requests focus without opening '
      'the keyboard', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final handle = tester.ensureSemantics();
      final methods = watchTextInput(tester);
      final e = await pumpEditor(tester);
      await settle(tester);

      expect(e.focusNode.hasFocus, isFalse);
      expect(
        textFieldNode().getSemanticsData().hasAction(
          SemanticsAction.didGainAccessibilityFocus,
        ),
        isTrue,
      );

      methods.clear();
      tester.semantics.performAction(
        textField(),
        SemanticsAction.didGainAccessibilityFocus,
      );
      await flushDeferredWork(tester);

      expect(e.focusNode.hasFocus, isTrue);
      expect(methods, isNot(contains('TextInput.show')));
      expect(methods, isNot(contains('TextInput.setClient')));

      handle.dispose();
      await teardownEditor(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('off macOS the node carries no accessibility focus action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);

    expect(
      textFieldNode().getSemanticsData().hasAction(
        SemanticsAction.didGainAccessibilityFocus,
      ),
      isFalse,
      reason:
          'material/text_field.dart plumbs this on macOS only: elsewhere '
          'a screen reader sweeping past the field would take keyboard focus '
          'and never give it back',
    );
    expect(
      find.semantics.byAction(SemanticsAction.didGainAccessibilityFocus),
      findsNothing,
    );
    expect(e.focusNode.hasFocus, isFalse);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a read only editor still focuses on tap but never asks for the '
      'keyboard', (tester) async {
    final handle = tester.ensureSemantics();
    final methods = watchTextInput(tester);
    final e = await pumpEditor(tester, readOnly: true);
    await settle(tester);

    methods.clear();
    tester.semantics.performAction(textField(), SemanticsAction.tap);
    await flushDeferredWork(tester);

    expect(e.focusNode.hasFocus, isTrue);
    expect(methods, isNot(contains('TextInput.show')));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('the node carrying the actions still carries the visible window '
      'value', (tester) async {
    final handle = tester.ensureSemantics();
    watchTextInput(tester);
    final e = await pumpEditor(tester);
    await settle(tester);

    final SemanticsNode node = textFieldNode();
    final SemanticsData data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.setSelection), isTrue);
    expect(node.value, expectedWindow(e.notifier, e.controller));
    expect(node.value, startsWith('line 0'));

    handle.dispose();
    await teardownEditor(tester);
  });
}
