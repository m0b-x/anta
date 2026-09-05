import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

void main() {
  const double viewportWidth = 300.0;
  const double viewportHeight = 220.0;
  const int lineCount = 200;
  const int nearEndLine = 190;

  String buildDocument() {
    final buffer = StringBuffer();
    for (var i = 0; i < lineCount; i++) {
      if (i % 4 == 0) {
        buffer.writeln('$i ${'wrapped ' * 6}');
      } else {
        buffer.writeln('$i short');
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
    return (controller: controller, scroll: scroll, notifier: notifier);
  }

  bool showsLine(CodeIndicatorValueNotifier notifier, int index) {
    return displayedParagraphs(
      notifier,
    ).any((p) => p.index == index && p.bottom > 0 && p.top < viewportHeight);
  }

  double pixelsOf(CodeScrollController scroll) =>
      scroll.verticalScroller.position.pixels;

  void expectInRange(CodeScrollController scroll) {
    final position = scroll.verticalScroller.position;
    expect(position.pixels, greaterThanOrEqualTo(0.0));
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
  }

  testWidgets('a jump near the end of a wrapping document settles on the '
      'target line', (tester) async {
    final e = await pumpEditor(tester);
    expect(showsLine(e.notifier, 0), isTrue);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: nearEndLine, offset: 0),
    );
    expectInRange(e.scroll);
    await settle(tester);

    expect(showsLine(e.notifier, nearEndLine), isTrue);
    expectInRange(e.scroll);
    await teardownEditor(tester);
  });

  testWidgets('a jump below the viewport never leaves the scrollable range', (
    tester,
  ) async {
    final e = await pumpEditor(tester);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 100, offset: 0),
    );
    expectInRange(e.scroll);
    await settle(tester);
    expect(showsLine(e.notifier, 100), isTrue);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 140, offset: 0),
    );
    expectInRange(e.scroll);
    await settle(tester);

    expect(showsLine(e.notifier, 140), isTrue);
    expectInRange(e.scroll);
    await teardownEditor(tester);
  });

  testWidgets('a jump below the viewport measures from the last displayed '
      'line, not the first', (tester) async {
    final e = await pumpEditor(tester);
    expect(pixelsOf(e.scroll), 0.0);

    final List<CodeLineRenderParagraph> window = displayedParagraphs(
      e.notifier,
    );
    final CodeLineRenderParagraph last = window.last;
    expect(window.first.index, 0);
    expect(last.index, greaterThan(2));

    final double lineHeight = last.preferredLineHeight;
    const int target = 100;
    final double expected =
        last.bottom - viewportHeight + lineHeight * (target - last.index);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: target, offset: 0),
    );

    expect(pixelsOf(e.scroll), closeTo(expected, lineHeight));
    expectInRange(e.scroll);

    await settle(tester);
    expect(showsLine(e.notifier, target), isTrue);
    await teardownEditor(tester);
  });

  testWidgets('centering a position near the end stays inside the range', (
    tester,
  ) async {
    final e = await pumpEditor(tester);

    e.controller.makePositionCenterIfInvisible(
      const CodeLinePosition(index: nearEndLine, offset: 0),
    );
    expectInRange(e.scroll);
    await settle(tester);

    expect(showsLine(e.notifier, nearEndLine), isTrue);
    expectInRange(e.scroll);
    await teardownEditor(tester);
  });

  testWidgets('a jump back to the first line lands exactly on zero', (
    tester,
  ) async {
    final e = await pumpEditor(tester);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 60, offset: 0),
    );
    await settle(tester);
    expect(pixelsOf(e.scroll), greaterThan(0.0));

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 0, offset: 0),
    );
    expectInRange(e.scroll);
    await settle(tester);

    expect(pixelsOf(e.scroll), 0.0);
    expect(showsLine(e.notifier, 0), isTrue);
    expect(displayedParagraphs(e.notifier).first.index, 0);
    await teardownEditor(tester);
  });

  testWidgets('an offset a hair above the first line does not loop layout', (
    tester,
  ) async {
    final e = await pumpEditor(tester);
    expect(displayedParagraphs(e.notifier).first.index, 0);

    e.scroll.verticalScroller.position.jumpTo(-1.0);
    await settle(tester, 6);
    expect(tester.takeException(), isNull);
    expect(pixelsOf(e.scroll), greaterThan(-1.0));

    await settle(tester, 60);
    expect(pixelsOf(e.scroll), 0.0);
    expect(displayedParagraphs(e.notifier).first.index, 0);
    await teardownEditor(tester);
  });

  testWidgets('resting at the top does not restart layout every frame', (
    tester,
  ) async {
    final e = await pumpEditor(tester);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 60, offset: 0),
    );
    await settle(tester);
    e.controller.makePositionVisible(
      const CodeLinePosition(index: 0, offset: 0),
    );
    await settle(tester);

    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(pixelsOf(e.scroll), 0.0);
      expect(displayedParagraphs(e.notifier).first.index, 0);
    }
    await teardownEditor(tester);
  });
}
