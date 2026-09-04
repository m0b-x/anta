import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  const double fontSize = 14.0;
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
      CodeScrollController scroll,
      CodeIndicatorValueNotifier notifier,
    })
  >
  pumpEditor(WidgetTester tester, String text) async {
    final controller = CodeLineEditingController.fromText(text);
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
                style: const CodeEditorStyle(fontSize: fontSize),
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
    return (controller: controller, scroll: scroll, notifier: notifier);
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  List<int> displayedIndices(CodeIndicatorValueNotifier notifier) {
    final paragraphs =
        notifier.value?.paragraphs ?? const <CodeLineRenderParagraph>[];
    return paragraphs.map((p) => p.index).toList();
  }

  String expectedWindow(
    CodeIndicatorValueNotifier notifier,
    CodeLineEditingController controller,
  ) {
    return displayedIndices(
      notifier,
    ).map((index) => controller.codeLines[index].text).join('\n');
  }

  SemanticsNode textFieldNode() {
    final finder = find.semantics.byFlag(SemanticsFlag.isTextField);
    expect(finder, findsOne);
    return finder.evaluate().single;
  }

  testWidgets('the announced value is the visible window, not the document',
      (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, buildDocument());
    await settle(tester);

    final indices = displayedIndices(e.notifier);
    expect(indices, isNotEmpty);
    expect(indices.first, 0);
    expect(indices.length, lessThan(lineCount));

    final window = expectedWindow(e.notifier, e.controller);
    expect(textFieldNode().value, window);
    expect(find.semantics.byValue(window), findsOne);
    expect(find.semantics.byValue(e.controller.text), findsNothing);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('scrolling moves the announced value to the new window',
      (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, buildDocument());
    await settle(tester);
    final firstWindow = expectedWindow(e.notifier, e.controller);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 120, offset: 0),
    );
    await settle(tester);

    final indices = displayedIndices(e.notifier);
    expect(indices, contains(120));
    expect(indices.first, greaterThan(0));

    final secondWindow = expectedWindow(e.notifier, e.controller);
    expect(secondWindow, isNot(firstWindow));
    expect(textFieldNode().value, secondWindow);
    expect(find.semantics.byValue(secondWindow), findsOne);
    expect(find.semantics.byValue(firstWindow), findsNothing);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('the semantics value never rebuilds the whole-document string',
      (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, buildDocument());
    await settle(tester);

    CodeLines.debugAsStringCalls = 0;
    await settle(tester);
    expect(CodeLines.debugAsStringCalls, 0);

    e.controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    e.controller.replaceSelection('x');
    await settle(tester);

    expect(CodeLines.debugAsStringCalls, 0);
    expect(textFieldNode().value, startsWith('xline 0'));
    expect(
      textFieldNode().value,
      expectedWindow(e.notifier, e.controller),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an empty document announces an empty value', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, '');
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(textFieldNode().value, '');
    expect(expectedWindow(e.notifier, e.controller), '');

    handle.dispose();
    await teardownEditor(tester);
  });
}
