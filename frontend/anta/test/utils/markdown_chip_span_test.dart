import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/markdown_chip_span.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_editor_emitter.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';

/// A suggestion pill previews its term the way the live editor will
/// render it, at the pill's own size: the editor's colours and conceal
/// rule, headings flattened to a level, raw where the editor stays raw.
void main() {
  const style = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Color(0xFF223344),
    letterSpacing: 0.25,
  );
  final flat = style.copyWith(letterSpacing: 0);
  const palette = MarkdownColorPalette.presets;
  final light = AppTheme.light();

  MarkdownChipSpan chip(
    String term, {
    ThemeData? theme,
    bool headings = true,
  }) => MarkdownChipSpan.build(
    term: term,
    style: style,
    theme: theme ?? light,
    palette: palette,
    headings: headings,
  );

  bool isConcealed(TextStyle? style) =>
      style?.color == EditorSpanEmitter.transparent &&
      style?.fontSize == EditorSpanEmitter.concealedFontSize;

  List<TextSpan> leaves(InlineSpan span) {
    final out = <TextSpan>[];
    span.visitChildren((child) {
      if (child is TextSpan && (child.text?.isNotEmpty ?? false)) {
        out.add(child);
      }
      return true;
    });
    return out;
  }

  TextSpan leaf(MarkdownChipSpan chip, String text) =>
      leaves(chip.span).singleWhere((span) => span.text == text);

  void expectRaw(MarkdownChipSpan chip, String term) {
    expect(chip.headingLevel, isNull);
    final span = chip.span as TextSpan;
    expect(span.text, term);
    expect(span.children, isNull);
    expect(span.style, style);
  }

  test('a plain term keeps its text and style and has no level', () {
    final result = chip('Bench press');
    expect(result.headingLevel, isNull);
    expect(result.span.toPlainText(), 'Bench press');
    expect(leaves(result.span).map((span) => span.style), everyElement(flat));
  });

  test('bold content is bold and its markers are concealed, not dropped', () {
    final result = chip('**Bench** press');
    expect(result.span.toPlainText(), '**Bench** press');
    expect(leaf(result, 'Bench').style!.fontWeight, FontWeight.bold);
    final markers = leaves(
      result.span,
    ).where((span) => span.text == '**').toList();
    expect(markers, hasLength(2));
    for (final marker in markers) {
      expect(marker.style!.color, EditorSpanEmitter.transparent);
      expect(marker.style!.fontSize, EditorSpanEmitter.concealedFontSize);
    }
    expect(leaf(result, ' press').style, flat);
  });

  test('a tag takes the theme primary', () {
    final result = chip('#push');
    expect(result.headingLevel, isNull);
    expect(result.span.toPlainText(), '#push');
    expect(leaf(result, '#push').style!.color, light.colorScheme.primary);
  });

  test('a colour run takes the palette colour for the theme brightness', () {
    final red = palette.lookup('red')!;
    expect(
      leaf(chip('{red:fail}'), 'fail').style!.color,
      red.text(dark: false),
    );
    expect(
      leaf(chip('{red:fail}', theme: AppTheme.dark()), 'fail').style!.color,
      red.text(dark: true),
    );
  });

  test('a heading drops its hashes, keeps the size and reports its level', () {
    final result = chip('# Bench');
    expect(result.headingLevel, 1);
    expect(result.span.toPlainText(), 'Bench');
    for (final span in leaves(result.span)) {
      expect(span.style!.fontWeight, MarkdownConstants.headingWeight);
      expect(span.style!.fontSize, style.fontSize);
    }
  });

  test('a closing hash run is not heading content', () {
    final result = chip('## Week 3 ##');
    expect(result.headingLevel, 2);
    expect(result.span.toPlainText(), 'Week 3');
  });

  test('a level-six heading reports level 6', () {
    final result = chip('###### x');
    expect(result.headingLevel, 6);
    expect(result.span.toPlainText(), 'x');
  });

  test('a tag is not a heading', () {
    expect(chip('#tag').headingLevel, isNull);
    expect(chip('#tag').span.toPlainText(), '#tag');
  });

  test('an empty heading stays raw, so a pill is never blank', () {
    expectRaw(chip('#'), '#');
    expectRaw(chip('# '), '# ');
    expectRaw(chip('###'), '###');
  });

  test('a ghost renders with its text preserved', () {
    final result = chip('{{exercise}} 3x8');
    expect(result.headingLevel, isNull);
    expect(result.span.toPlainText(), '{{exercise}} 3x8');
  });

  test('a term past the editor styling cap stays raw', () {
    final term = 'a' * (MarkdownEditorSpanBuilder.maxStyledLineLength + 1);
    expectRaw(chip('**$term**'), '**$term**');
  });

  test('a term at exactly the styling cap is still styled', () {
    final inner = 'a' * (MarkdownEditorSpanBuilder.maxStyledLineLength - 4);
    final result = chip('**$inner**');
    expect(result.span.toPlainText(), '**$inner**');
    expect(leaf(result, inner).style!.fontWeight, FontWeight.bold);
  });

  test('a ghost dims its inner run from the pill colour', () {
    final result = chip('{{exercise}} 3x8');
    expect(
      leaf(result, 'exercise').style!.color,
      style.color!.withValues(alpha: EditorSpanEmitter.dimAlpha),
    );
  });

  test('bold inside a heading keeps the heading weight', () {
    final result = chip('# **bold**');
    expect(result.headingLevel, 1);
    expect(
      leaf(result, 'bold').style!.fontWeight,
      MarkdownConstants.headingWeight,
    );
  });

  test('a trailing backslash stays visible, never a hard break', () {
    final result = chip(r'Bench\');
    expect(result.span.toPlainText(), r'Bench\');
    expect(
      leaves(result.span).where((span) => isConcealed(span.style)),
      isEmpty,
    );
  });

  test('a term that renders only concealed chrome stays raw', () {
    expectRaw(chip('%%note%%'), '%%note%%');
    expectRaw(chip('# %%x%%'), '# %%x%%');
  });

  test('an empty-text link is literal text, so it already shows', () {
    final result = chip('[](url)');
    expect(result.span.toPlainText(), '[](url)');
    expect(
      leaves(result.span).where((span) => !isConcealed(span.style)),
      isNotEmpty,
    );
  });

  test('without headings a heading term renders as inline prose', () {
    final result = chip('# Bench', headings: false);
    expect(result.headingLevel, isNull);
    expect(result.span.toPlainText(), '# Bench');
  });

  test('the rendering drops letter spacing; a raw fallback keeps it', () {
    expect(chip('**Row**').span.style!.letterSpacing, 0);
    expect(chip('#').span.style!.letterSpacing, style.letterSpacing);
  });
}
