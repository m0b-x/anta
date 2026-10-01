import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// `CodeScrollController.revealInAncestors` — the editor's caret brought on
/// screen by the scrollables **around** the editor.
///
/// The editor's own `makeVisible` stops at its viewport, which is the whole
/// story for a full-height editor and half of it for one embedded in a
/// form: there the caret can sit comfortably inside the editor's box while
/// the box itself is behind the keyboard. The fixture is that form in
/// miniature — a fixed-height editor between two spacers in a scroll view
/// shorter than the three together.
void main() {
  const double viewportHeight = 300;
  const double editorHeight = 110;
  const double above = 400;
  const double below = 400;

  Future<
    ({
      CodeLineEditingController controller,
      CodeScrollController scroll,
      ScrollController outer,
    })
  >
  pumpEmbedded(WidgetTester tester, {required String text}) async {
    final controller = CodeLineEditingController.fromText(text);
    final scroll = CodeScrollController();
    final outer = ScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      controller.dispose();
      scroll.dispose();
      outer.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: viewportHeight,
              child: SingleChildScrollView(
                controller: outer,
                child: Column(
                  children: [
                    const SizedBox(height: above),
                    SizedBox(
                      height: editorHeight,
                      child: CodeEditor(
                        controller: controller,
                        scrollController: scroll,
                        focusNode: focusNode,
                        autofocus: false,
                        padding: EdgeInsets.zero,
                        style: const CodeEditorStyle(fontSize: kTestFontSize),
                      ),
                    ),
                    const SizedBox(height: below),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return (controller: controller, scroll: scroll, outer: outer);
  }

  double lineHeightOf(WidgetTester tester) => CodeFieldRenderForTesting.of(
    tester.renderObject(find.byType(CodeEditor)),
  ).lineHeight;

  const CodeLinePosition firstLine = CodeLinePosition(index: 0, offset: 0);

  testWidgets('a caret below the fold scrolls the ancestor just far enough', (
    tester,
  ) async {
    final e = await pumpEmbedded(tester, text: 'one\ntwo\nthree');
    final double lineHeight = lineHeightOf(tester);
    expect(e.outer.offset, 0);

    final bool revealed = e.scroll.revealInAncestors(firstLine);
    await tester.pump();

    expect(revealed, isTrue);
    expect(
      e.outer.offset,
      moreOrLessEquals(above + lineHeight - viewportHeight),
      reason: 'the caret line ends flush with the viewport, no further',
    );
    await teardownEditor(tester);
  });

  testWidgets('the margin rides along on the side that had to move', (
    tester,
  ) async {
    final e = await pumpEmbedded(tester, text: 'one\ntwo\nthree');
    final double lineHeight = lineHeightOf(tester);

    e.scroll.revealInAncestors(
      firstLine,
      margin: const EdgeInsets.symmetric(vertical: 13),
    );
    await tester.pump();

    expect(
      e.outer.offset,
      moreOrLessEquals(above + lineHeight + 13 - viewportHeight),
    );
    await teardownEditor(tester);
  });

  testWidgets('a caret above the viewport is brought back down to it', (
    tester,
  ) async {
    final e = await pumpEmbedded(tester, text: 'one\ntwo\nthree');
    e.outer.jumpTo(above + editorHeight + 100);
    await tester.pump();

    final bool revealed = e.scroll.revealInAncestors(
      firstLine,
      margin: const EdgeInsets.symmetric(vertical: 13),
    );
    await tester.pump();

    expect(revealed, isTrue);
    expect(e.outer.offset, moreOrLessEquals(above - 13));
    await teardownEditor(tester);
  });

  testWidgets('a caret already on screen moves nothing', (tester) async {
    final e = await pumpEmbedded(tester, text: 'one\ntwo\nthree');
    e.outer.jumpTo(above - 50);
    await tester.pump();

    final bool revealed = e.scroll.revealInAncestors(
      firstLine,
      margin: const EdgeInsets.symmetric(vertical: 13),
    );
    await tester.pump();

    expect(revealed, isTrue);
    expect(e.outer.offset, above - 50);
    await teardownEditor(tester);
  });

  testWidgets('an animated reveal lands on the same offset', (tester) async {
    final e = await pumpEmbedded(tester, text: 'one\ntwo\nthree');
    final double lineHeight = lineHeightOf(tester);

    e.scroll.revealInAncestors(
      firstLine,
      duration: const Duration(milliseconds: 100),
      curve: Curves.fastOutSlowIn,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final double target = above + lineHeight - viewportHeight;
    expect(e.outer.offset, greaterThan(0));
    expect(e.outer.offset, lessThan(target));

    await tester.pump(const Duration(milliseconds: 60));
    expect(e.outer.offset, moreOrLessEquals(target));
    await teardownEditor(tester);
  });

  testWidgets('a line the editor has not scrolled to reveals nothing', (
    tester,
  ) async {
    final String text = List.generate(60, (i) => 'line $i').join('\n');
    final e = await pumpEmbedded(tester, text: text);

    // Line 50 is far outside a five-line box that still sits at its top:
    // its place is the editor's to find first, and until then the ancestor
    // has no spot inside the box to go to.
    final bool revealed = e.scroll.revealInAncestors(
      const CodeLinePosition(index: 50, offset: 0),
    );
    await tester.pump();

    expect(revealed, isFalse);
    expect(e.outer.offset, 0);
    await teardownEditor(tester);
  });

  testWidgets('once the editor has scrolled to the line, the ancestor follows '
      'to where it is drawn', (tester) async {
    final String text = List.generate(60, (i) => 'line $i').join('\n');
    final e = await pumpEmbedded(tester, text: text);
    const CodeLinePosition target = CodeLinePosition(index: 50, offset: 0);

    e.scroll.makeVisible(target);
    await settle(tester);
    final bool revealed = e.scroll.revealInAncestors(target);
    await tester.pump();

    expect(revealed, isTrue);
    // The editor parks the line at its own bottom edge, so that is the
    // edge the ancestor has to show.
    expect(
      e.outer.offset,
      moreOrLessEquals(above + editorHeight - viewportHeight, epsilon: 1),
    );
    await teardownEditor(tester);
  });

  test('a controller bound to no editor reveals nothing', () {
    final scroll = CodeScrollController();
    addTearDown(scroll.dispose);
    expect(scroll.revealInAncestors(firstLine), isFalse);
  });
}
