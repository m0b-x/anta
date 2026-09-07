import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:anta/utils/markdown_line_height_calculator.dart';

/// E11 — heading sizes, set once in [MarkdownConstants] so the live
/// editor, the deprecated preview and the line-height calculator cannot
/// disagree. At the 16 px base the mock draws h1 22 / h2 18, both at
/// weight 500; h4 and below sit at the base size and separate themselves
/// by colour instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const base = 16.0;
  const baseStyle = TextStyle(
    fontSize: base,
    height: 1.4,
    color: Color(0xFF202124),
  );
  final context = EditorRenderContext.fromTheme(
    ThemeData(useMaterial3: true, brightness: Brightness.light),
    baseStyle,
  );

  TextSpan renderHeading(String line) {
    final controller = CodeLineEditingController.fromText('pad\n$line\npad');
    addTearDown(controller.dispose);
    final builder = MarkdownEditorSpanBuilder()..bind(controller);
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    final span = builder.build(
      context: context,
      index: 1,
      codeLine: controller.codeLines[1],
    );
    expect(span, isNotNull, reason: line);
    return span!;
  }

  test('the shared scales land on the mock pixel sizes', () {
    expect(base * MarkdownConstants.h1Scale, 22.0);
    expect(base * MarkdownConstants.h2Scale, 18.0);
    expect(base * MarkdownConstants.h3Scale, 17.0);
    expect(MarkdownConstants.h4Scale, 1.0);
    expect(MarkdownConstants.h5Scale, 1.0);
    expect(MarkdownConstants.h6Scale, 1.0);
    expect(MarkdownConstants.headingWeight, FontWeight.w500);
  });

  test('an h1 line is 1.375x the base at w500', () {
    final span = renderHeading('# Warm up');
    expect(span.style?.fontSize, base * MarkdownConstants.h1Scale);
    expect(span.style?.fontSize, 22.0);
    expect(span.style?.fontWeight, MarkdownConstants.headingWeight);
  });

  test('an h2 line is 1.125x the base at w500', () {
    final span = renderHeading('## Working sets');
    expect(span.style?.fontSize, base * MarkdownConstants.h2Scale);
    expect(span.style?.fontSize, 18.0);
    expect(span.style?.fontWeight, MarkdownConstants.headingWeight);
  });

  test('h4 and below keep the base size', () {
    for (final line in ['#### four', '##### five', '###### six']) {
      expect(renderHeading(line).style?.fontSize, base, reason: line);
    }
  });

  test('the line-height calculator reads the same scales', () {
    double scale(String line) =>
        MarkdownLineHeightCalculator.getLineHeightScale(line);
    expect(scale('# a'), MarkdownConstants.h1Scale);
    expect(scale('## a'), MarkdownConstants.h2Scale);
    expect(scale('### a'), MarkdownConstants.h3Scale);
    expect(scale('###### a'), MarkdownConstants.h6Scale);
  });

  test('the body line height is the mock 1.55', () {
    expect(MarkdownConstants.lineHeight, 1.55);
  });
}
