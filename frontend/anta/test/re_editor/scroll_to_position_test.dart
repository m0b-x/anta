import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The render's "scroll this position into view" helpers.
///
/// Both post-layout helpers are written against the caret, and the caret
/// is drawn the paragraph's own height tall — so a line the span builder
/// scaled (a markdown header) needs its own height in the bottom-edge
/// test and in the jump, not the flat base height every other line has.
/// The first two groups pin that; the third pins the off-screen jump's
/// arithmetic, which has to measure from the LAST displayed line and
/// CENTRE by subtracting half a viewport.
///
/// The last group is the layout-time variant behind opening a note at its
/// stored position: `CodeScrollController.makeCenterIfInvisibleOnLayout`
/// is consumed inside the render's layout, so the frame that comes out of
/// it — the editor's very first frame, when armed before the mount —
/// already shows the line, with nothing painted at the top first.
void main() {
  const double viewportWidth = 300.0;
  const double viewportHeight = 220.0;
  const int lineCount = 60;
  const int scaledLine = 20;

  String plainDocument() {
    final buffer = StringBuffer();
    for (var i = 0; i < lineCount; i++) {
      buffer.writeln('line $i');
    }
    return buffer.toString();
  }

  String wrappingDocument() {
    final buffer = StringBuffer();
    for (var i = 0; i < 200; i++) {
      if (i % 4 == 0) {
        buffer.writeln('$i ${'wrapped ' * 6}');
      } else {
        buffer.writeln('$i short');
      }
    }
    return buffer.toString();
  }

  /// A fixture whose [scaledLine] is twice as tall as every other line
  /// and parked with its top inside the viewport but its bottom clipped
  /// — the exact window in which the flat base height reports "visible"
  /// and the line's own height does not.
  Future<ScrollEditor> pumpClippedScaledLine(WidgetTester tester) async {
    final ScrollEditor e = await pumpScrollEditor(
      tester,
      text: plainDocument(),
      width: viewportWidth,
      height: viewportHeight,
      scaledLines: const {scaledLine},
    );
    await settle(tester);
    final double base = displayedParagraphs(
      e.notifier,
    ).first.preferredLineHeight;
    e.scroll.verticalScroller.position.jumpTo(
      scaledLine * base - (viewportHeight - base * 1.5),
    );
    await settle(tester);

    final CodeLineRenderParagraph parked = displayedParagraphAt(
      e.notifier,
      scaledLine,
    )!;
    expect(
      parked.preferredLineHeight,
      greaterThan(base),
      reason: 'the fixture line must actually be scaled',
    );
    expect(
      parked.top,
      lessThan(viewportHeight - base),
      reason: 'the flat base-height test must read this line as visible',
    );
    expect(
      parked.bottom,
      greaterThan(viewportHeight),
      reason: 'while the line is in fact clipped by the bottom edge',
    );
    return e;
  }

  void expectFullyVisible(CodeIndicatorValueNotifier notifier, int index) {
    final CodeLineRenderParagraph paragraph = displayedParagraphAt(
      notifier,
      index,
    )!;
    expect(paragraph.top, greaterThanOrEqualTo(-0.01));
    expect(
      paragraph.bottom,
      lessThanOrEqualTo(viewportHeight + 0.01),
      reason: 'the whole line must fit, not just its first base row',
    );
  }

  testWidgets('makePositionVisible clears the bottom edge by the scaled '
      'line\'s own height', (tester) async {
    final ScrollEditor e = await pumpClippedScaledLine(tester);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: scaledLine, offset: 0),
    );
    await settle(tester);

    expectFullyVisible(e.notifier, scaledLine);
    await teardownEditor(tester);
  });

  testWidgets('makePositionCenterIfInvisible re-centres a scaled line the '
      'base height calls visible', (tester) async {
    final ScrollEditor e = await pumpClippedScaledLine(tester);
    final double before = pixelsOf(e.scroll);

    e.controller.makePositionCenterIfInvisible(
      const CodeLinePosition(index: scaledLine, offset: 0),
    );
    expect(
      pixelsOf(e.scroll),
      isNot(before),
      reason: 'a clipped line must move the viewport',
    );
    await settle(tester);

    expectFullyVisible(e.notifier, scaledLine);
    await teardownEditor(tester);
  });

  testWidgets('centring a line below the window measures from the last '
      'displayed line and subtracts half a viewport', (tester) async {
    final ScrollEditor e = await pumpScrollEditor(
      tester,
      text: wrappingDocument(),
      width: viewportWidth,
      height: viewportHeight,
    );
    expect(pixelsOf(e.scroll), 0.0);

    final CodeLineRenderParagraph last = displayedParagraphs(e.notifier).last;
    final double lineHeight = last.preferredLineHeight;
    const int target = 100;
    final double expected =
        last.bottom + lineHeight * (target - last.index) - viewportHeight / 2;

    e.controller.makePositionCenterIfInvisible(
      const CodeLinePosition(index: target, offset: 0),
    );

    expect(pixelsOf(e.scroll), closeTo(expected, lineHeight));
    final ScrollPosition position = e.scroll.verticalScroller.position;
    expect(position.pixels, greaterThanOrEqualTo(0.0));
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));

    await settle(tester);
    expect(displayedParagraphAt(e.notifier, target), isNotNull);
    await teardownEditor(tester);
  });

  group('makeCenterIfInvisibleOnLayout', () {
    /// Centred means the line's bottom sits at the viewport's middle,
    /// give or take the line: the below-window estimate and the exact
    /// pass both place it there.
    void expectCentred(CodeIndicatorValueNotifier notifier, int index) {
      final CodeLineRenderParagraph paragraph = displayedParagraphAt(
        notifier,
        index,
      )!;
      expect(
        paragraph.bottom,
        closeTo(viewportHeight / 2, paragraph.height),
        reason: 'the line must be centred, not merely visible',
      );
    }

    testWidgets('armed before the editor exists, the first frame already '
        'shows the line centred', (tester) async {
      const int target = 40;
      final CodeScrollController scroll = CodeScrollController();
      addTearDown(scroll.dispose);
      scroll.makeCenterIfInvisibleOnLayout(
        const CodeLinePosition(index: target, offset: 0),
      );

      final ScrollEditor e = await pumpScrollEditor(
        tester,
        text: plainDocument(),
        width: viewportWidth,
        height: viewportHeight,
        scaledLines: const {target},
        scroll: scroll,
        framesAfterMount: 0,
      );

      expect(pixelsOf(e.scroll), greaterThan(0.0));
      expect(displayedParagraphAt(e.notifier, target), isNotNull);
      expectFullyVisible(e.notifier, target);
      expectCentred(e.notifier, target);

      // The layout consumed the request: later frames leave it alone.
      final double landed = pixelsOf(e.scroll);
      await settle(tester);
      expect(pixelsOf(e.scroll), landed);
      await teardownEditor(tester);
    });

    testWidgets('walks past the flat estimate when the lines in between '
        'wrap taller than the base height', (tester) async {
      const int target = 100;
      final CodeScrollController scroll = CodeScrollController();
      addTearDown(scroll.dispose);
      scroll.makeCenterIfInvisibleOnLayout(
        const CodeLinePosition(index: target, offset: 0),
      );

      final ScrollEditor e = await pumpScrollEditor(
        tester,
        text: wrappingDocument(),
        width: viewportWidth,
        height: viewportHeight,
        scroll: scroll,
        framesAfterMount: 0,
      );

      expect(displayedParagraphAt(e.notifier, target), isNotNull);
      expectFullyVisible(e.notifier, target);
      expectCentred(e.notifier, target);
      final ScrollPosition position = e.scroll.verticalScroller.position;
      expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
      await teardownEditor(tester);
    });

    testWidgets('armed on a mounted editor, it lands in the next layout — '
        'not synchronously, not after retries', (tester) async {
      const int target = 100;
      final ScrollEditor e = await pumpScrollEditor(
        tester,
        text: wrappingDocument(),
        width: viewportWidth,
        height: viewportHeight,
      );
      expect(pixelsOf(e.scroll), 0.0);

      e.scroll.makeCenterIfInvisibleOnLayout(
        const CodeLinePosition(index: target, offset: 0),
      );
      expect(
        pixelsOf(e.scroll),
        0.0,
        reason: 'nothing scrolls until the render lays out',
      );

      await tester.pump();

      expect(displayedParagraphAt(e.notifier, target), isNotNull);
      expectFullyVisible(e.notifier, target);
      expectCentred(e.notifier, target);
      await teardownEditor(tester);
    });

    testWidgets('a line already fully visible leaves the viewport where it '
        'is', (tester) async {
      final ScrollEditor e = await pumpScrollEditor(
        tester,
        text: plainDocument(),
        width: viewportWidth,
        height: viewportHeight,
      );

      e.scroll.makeCenterIfInvisibleOnLayout(
        const CodeLinePosition(index: 2, offset: 0),
      );
      await tester.pump();

      expect(pixelsOf(e.scroll), 0.0);
      await teardownEditor(tester);
    });

    testWidgets('a later request replaces an unconsumed one', (tester) async {
      final CodeScrollController scroll = CodeScrollController();
      addTearDown(scroll.dispose);
      scroll.makeCenterIfInvisibleOnLayout(
        const CodeLinePosition(index: 55, offset: 0),
      );
      scroll.makeCenterIfInvisibleOnLayout(
        const CodeLinePosition(index: 30, offset: 0),
      );

      final ScrollEditor e = await pumpScrollEditor(
        tester,
        text: plainDocument(),
        width: viewportWidth,
        height: viewportHeight,
        scroll: scroll,
        framesAfterMount: 0,
      );

      expect(displayedParagraphAt(e.notifier, 30), isNotNull);
      expectCentred(e.notifier, 30);
      expect(displayedParagraphAt(e.notifier, 55), isNull);
      await teardownEditor(tester);
    });
  });
}
