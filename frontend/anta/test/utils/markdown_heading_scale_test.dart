import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:anta/utils/markdown_line_height_calculator.dart';

/// E11, revised by E24 of the editor QoL review — heading sizes, set once
/// in [MarkdownConstants] so the live editor, the deprecated preview and
/// the line-height calculator cannot disagree. At the 16 px base: h1 24,
/// h2 20.8, h3 18.4, h4 16.8, all at weight 600; h5 and h6 sit at the
/// base size and separate themselves by colour as well.
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

  test('the shared scales land on the review pixel sizes', () {
    expect(base * MarkdownConstants.h1Scale, 24.0);
    expect(base * MarkdownConstants.h2Scale, closeTo(20.8, 1e-9));
    expect(base * MarkdownConstants.h3Scale, closeTo(18.4, 1e-9));
    expect(base * MarkdownConstants.h4Scale, closeTo(16.8, 1e-9));
    expect(MarkdownConstants.h5Scale, 1.0);
    expect(MarkdownConstants.h6Scale, 1.0);
    expect(MarkdownConstants.headingWeight, FontWeight.w600);
  });

  test('every level steps down from the one above it to the base', () {
    const scales = [
      MarkdownConstants.h1Scale,
      MarkdownConstants.h2Scale,
      MarkdownConstants.h3Scale,
      MarkdownConstants.h4Scale,
      MarkdownConstants.h5Scale,
    ];
    for (var i = 1; i < scales.length; i++) {
      expect(scales[i], lessThan(scales[i - 1]), reason: 'h${i + 1}');
    }
    expect(MarkdownConstants.h5Scale, MarkdownConstants.h6Scale);
  });

  test('an h1 line is 1.5x the base at w600', () {
    final span = renderHeading('# Warm up');
    expect(span.style?.fontSize, base * MarkdownConstants.h1Scale);
    expect(span.style?.fontSize, 24.0);
    expect(span.style?.fontWeight, FontWeight.w600);
  });

  test('an h2 line is 1.3x the base at w600', () {
    final span = renderHeading('## Working sets');
    expect(span.style?.fontSize, base * MarkdownConstants.h2Scale);
    expect(span.style?.fontWeight, FontWeight.w600);
  });

  test('h3 and h4 sit between h2 and the base', () {
    expect(
      renderHeading('### three').style?.fontSize,
      base * MarkdownConstants.h3Scale,
    );
    expect(
      renderHeading('#### four').style?.fontSize,
      base * MarkdownConstants.h4Scale,
    );
  });

  test('h5 and h6 keep the base size', () {
    for (final line in ['##### five', '###### six']) {
      expect(renderHeading(line).style?.fontSize, base, reason: line);
    }
  });

  test('the line-height calculator reads the same scales', () {
    double scale(String line) =>
        MarkdownLineHeightCalculator.getLineHeightScale(line);
    expect(scale('# a'), MarkdownConstants.h1Scale);
    expect(scale('## a'), MarkdownConstants.h2Scale);
    expect(scale('### a'), MarkdownConstants.h3Scale);
    expect(scale('#### a'), MarkdownConstants.h4Scale);
    expect(scale('###### a'), MarkdownConstants.h6Scale);
    // A heading past a quote's `>` run is drawn at its own scale too.
    expect(scale('> # Week 3'), MarkdownConstants.h1Scale);
    expect(scale('> > ## Legs'), MarkdownConstants.h2Scale);
    expect(scale('> plain quote'), MarkdownConstants.normalLineScale);
    expect(scale('>'), MarkdownConstants.normalLineScale);
  });

  test('the body line height is the mock 1.55', () {
    expect(MarkdownConstants.lineHeight, 1.55);
  });
}
