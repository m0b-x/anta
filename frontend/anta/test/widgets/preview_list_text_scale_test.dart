import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_color_syntax.dart';

import '../goldens/support/golden_fonts.dart';

/// A preview list row is a `WidgetSpan` holding its own `Text`. The
/// paragraph scales an inline widget by the text scale, so a `Text` inside
/// that also read the scale from `MediaQuery` would draw at its square:
/// 4x at 2.0. Pins that one line of a task row is as tall on screen as one
/// line of a plain paragraph under the same scale.
void main() {
  testWidgets('a task row scales its text once, like a paragraph', (
    tester,
  ) async {
    await tester.runAsync(loadGoldenFonts);
    const source = 'plain\n- [ ] task';
    final builder = LineBasedMarkdownBuilder(
      style: LineMarkdownStyle.fromTheme(ThemeData(), 16),
      colorPalette: MarkdownColorPalette.presets,
    );
    addTearDown(builder.dispose);
    builder.prepare(source);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            textScaler: TextScaler.linear(2.0),
          ),
          child: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontFamily: 'Roboto'),
                  children: [
                    builder.buildLine('plain', 0),
                    const TextSpan(text: '\n'),
                    builder.buildLine('- [ ] task', 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    RichText paragraph(bool Function(String text) where) =>
        tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && where(w.text.toPlainText()),
          ),
        );
    final outer = tester.renderObject<RenderParagraph>(
      find.byWidget(paragraph((t) => t.startsWith('plain'))),
    );
    // Both lines carry the same font size and line height, so their line
    // boxes compare whatever the glyphs: the plain line's full line box in
    // the outer paragraph, the task's one-line paragraph as drawn on screen.
    final plainLine = outer
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
          boxHeightStyle: ui.BoxHeightStyle.max,
        )
        .single
        .toRect()
        .height;
    final taskLine = tester
        .getRect(find.byWidget(paragraph((t) => t == 'task')))
        .height;

    expect(taskLine / plainLine, closeTo(1.0, 0.05));
  });
}
