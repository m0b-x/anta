import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// A colour-only change to the editor's base text style is below
/// [RenderComparison.layout], so the render takes the cheap
/// `markNeedsPaint` branch — but the colour is baked into the
/// `ui.Paragraph`s the provider built, and the provider is only reached
/// from the highlighter during LAYOUT. The theme flip (light <-> dark
/// `textColor`) therefore has to invalidate those paragraphs itself.
void main() {
  Future<CodeIndicatorValueNotifier> pumpWithColor(
    WidgetTester tester,
    Color color,
    CodeLineEditingController controller,
    void Function(CodeIndicatorValueNotifier) capture,
  ) async {
    late CodeIndicatorValueNotifier notifier;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: CodeEditor(
              controller: controller,
              autofocus: false,
              padding: EdgeInsets.zero,
              style: CodeEditorStyle(fontSize: kTestFontSize, textColor: color),
              indicatorBuilder: (context, editing, chunk, valueNotifier) {
                notifier = valueNotifier;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    capture(notifier);
    return notifier;
  }

  testWidgets('a colour-only text style change rebuilds the displayed '
      'paragraphs', (tester) async {
    final controller = CodeLineEditingController.fromText(
      'first line\nsecond line\nthird line',
    );
    addTearDown(controller.dispose);

    late CodeIndicatorValueNotifier notifier;
    await pumpWithColor(
      tester,
      const Color(0xFF101010),
      controller,
      (value) => notifier = value,
    );
    await settle(tester);
    final List<IParagraph> before = displayedParagraphs(
      notifier,
    ).map((p) => p.paragraph).toList();
    expect(before, isNotEmpty);

    await pumpWithColor(
      tester,
      const Color(0xFFF0F0F0),
      controller,
      (value) => notifier = value,
    );
    await tester.pump();

    final List<IParagraph> after = displayedParagraphs(
      notifier,
    ).map((p) => p.paragraph).toList();
    expect(after, hasLength(before.length));
    for (var i = 0; i < before.length; i++) {
      expect(
        identical(after[i], before[i]),
        isFalse,
        reason:
            'line $i still draws the ui.Paragraph built with the old '
            'colour',
      );
    }
    await teardownEditor(tester);
  });
}
