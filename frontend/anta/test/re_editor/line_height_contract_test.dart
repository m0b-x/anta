import 'package:anta/constants/markdown_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The render's per-line height contract. Anything anchored to a
/// specific line — caret, selection handles, the IME caret rect, the
/// scroll helpers — reads [CodeFieldRenderForTesting.lineHeightOfLine]
/// or [CodeFieldRenderForTesting.lineHeightAtOffset], never the flat
/// base `lineHeight`, which is only a whole-viewport estimate.
///
/// The render class is library-private, so these tests reach it through
/// the fork's `CodeFieldRenderForTesting` seam rather than by type.
void main() {
  const double viewportWidth = 300.0;
  const double viewportHeight = 220.0;

  // No trailing newline: the last line of the text IS the last line of
  // the document, which is what the clamp tests below anchor on.
  String document(int lines) =>
      [for (var i = 0; i < lines; i++) 'line $i'].join('\n');

  CodeFieldRenderForTesting renderOf(WidgetTester tester) {
    return CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
  }

  testWidgets('lineHeightOfLine answers per line, and lineHeightAtOffset '
      'clamps to the window', (tester) async {
    // Six lines all fit the viewport, so the display window is the whole
    // document and both its edges are scaled — a clamp that fell back to
    // the base height would be visible.
    final ScrollEditor e = await pumpScrollEditor(
      tester,
      text: document(6),
      width: viewportWidth,
      height: viewportHeight,
      scaledLines: const {0, 5},
    );
    await settle(tester);

    final CodeFieldRenderForTesting render = renderOf(tester);
    final double base = render.lineHeight;
    final double scaled = displayedParagraphAt(
      e.notifier,
      5,
    )!.preferredLineHeight;
    expect(scaled, greaterThan(base));

    expect(render.lineHeightOfLine(5), scaled);
    expect(render.lineHeightOfLine(0), scaled);
    expect(render.lineHeightOfLine(3), base);
    expect(
      render.lineHeightOfLine(50),
      base,
      reason: 'no such line: fall back to the base height',
    );

    expect(
      render.lineHeightAtOffset(const Offset(10, -80)),
      scaled,
      reason: 'above the window clamps to the first paragraph',
    );
    expect(
      render.lineHeightAtOffset(const Offset(10, viewportHeight + 400)),
      scaled,
      reason: 'below the window clamps to the last paragraph',
    );
    expect(
      render.lineHeightAtOffset(const Offset(10, 2.5 * 20)),
      base,
      reason: 'inside the window it answers the paragraph actually there',
    );

    await teardownEditor(tester);
  });

  testWidgets('an existing but off-window line falls back to the base '
      'height', (tester) async {
    final ScrollEditor e = await pumpScrollEditor(
      tester,
      text: document(200),
      width: viewportWidth,
      height: viewportHeight,
      scaledLines: const {2},
    );
    await settle(tester);

    final CodeFieldRenderForTesting render = renderOf(tester);
    final int lastShown = displayedParagraphs(e.notifier).last.index;
    expect(lastShown, lessThan(150));

    expect(render.lineHeightOfLine(2), greaterThan(render.lineHeight));
    expect(displayedParagraphAt(e.notifier, 150), isNull);
    expect(render.lineHeightOfLine(150), render.lineHeight);

    await teardownEditor(tester);
  });

  // The live editor renders inline `` `code` `` a touch smaller than the
  // prose around it (MarkdownConstants.inlineCodeScale), as a *child*
  // run under an unchanged root span. That is only safe because the
  // fork builds every paragraph with a `StrutStyle(forceStrutHeight:
  // true)` taken from the ROOT span's font size, so a smaller child
  // cannot shrink — or otherwise move — the line. These two cases are
  // the proof: if the scale ever started reaching the line box, caret
  // and selection geometry on every code-carrying line would drift.
  group('a smaller child run never changes the line height', () {
    const double scale = MarkdownConstants.inlineCodeScale;

    Future<ScrollEditor> pumpWithCode(
      WidgetTester tester, {
      required int line,
      required bool wholeLine,
    }) {
      return pumpScrollEditor(
        tester,
        text: document(6),
        width: viewportWidth,
        height: viewportHeight,
        spanBuilder:
            ({
              required BuildContext context,
              required int index,
              required CodeLine codeLine,
              required TextSpan textSpan,
              required TextStyle style,
            }) {
              if (index != line) {
                return TextSpan(text: codeLine.text, style: style);
              }
              // The root keeps the base size, family and height; only
              // the children shrink — exactly the shape the inline
              // emitter produces for a `` `code` `` run.
              final TextStyle code = style.copyWith(
                fontSize: style.fontSize! * scale,
              );
              return TextSpan(
                style: style,
                children: wholeLine
                    ? <TextSpan>[TextSpan(text: codeLine.text, style: code)]
                    : <TextSpan>[
                        TextSpan(text: 'a ', style: style),
                        TextSpan(text: 'code', style: code),
                        TextSpan(text: ' b', style: style),
                      ],
              );
            },
      );
    }

    testWidgets('a 0.9x child inside a base root keeps the base height', (
      tester,
    ) async {
      final ScrollEditor e = await pumpWithCode(
        tester,
        line: 2,
        wholeLine: false,
      );
      await settle(tester);

      final CodeFieldRenderForTesting render = renderOf(tester);
      expect(render.lineHeightOfLine(2), render.lineHeight);
      expect(render.lineHeightOfLine(2), render.lineHeightOfLine(3));
      expect(
        displayedParagraphAt(e.notifier, 2)!.preferredLineHeight,
        displayedParagraphAt(e.notifier, 3)!.preferredLineHeight,
        reason: 'the strut is taken from the root span, not from a child',
      );

      await teardownEditor(tester);
    });

    testWidgets('a whole line of 0.9x children keeps the base height', (
      tester,
    ) async {
      final ScrollEditor e = await pumpWithCode(
        tester,
        line: 4,
        wholeLine: true,
      );
      await settle(tester);

      final CodeFieldRenderForTesting render = renderOf(tester);
      expect(render.lineHeightOfLine(4), render.lineHeight);
      expect(
        displayedParagraphAt(e.notifier, 4)!.preferredLineHeight,
        displayedParagraphAt(e.notifier, 0)!.preferredLineHeight,
      );

      await teardownEditor(tester);
    });
  });
}
