import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

/// Every line of [paragraph] starts after a space, after a hyphen, after a
/// hard line break (a two-line value), or at a soft hyphen (U+00AD) — the
/// engine's legitimate break inside a long word, though it draws no hyphen
/// there — and never inside a word.
void expectBreaksBetweenWords(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  int? previous;
  double? previousTop;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == ' ' || text[i] == '\n' || text[i] == '\u00AD') continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isEmpty) continue;
    final top = boxes.first.top;
    if (previous != null && (top - previousTop!).abs() > 0.5) {
      final between = text.substring(previous + 1, i);
      expect(
        text[previous] == '-' ||
            between.contains(' ') ||
            between.contains('\n') ||
            between.contains('\u00AD'),
        isTrue,
        reason:
            '"$text" breaks inside a word: '
            '"${text.substring(0, i)}|${text.substring(i)}"',
      );
    }
    previous = i;
    previousTop = top;
  }
}

/// Every paragraph laid out on a settings page — top to bottom, the slot
/// templates too — is painted whole and holds its words: none is cut short
/// or at the side, none is narrower than its longest word where that word
/// fits the width it was given, and none breaks inside a word. A word wider
/// than its column has to break somewhere, so it passes only at a break
/// point it carries — a hyphen or U+00AD: "Entsc|hlafungsfasten" at de 2.0
/// passed while this check stood aside for such a word. Nothing overflows
/// on the way down. Shared by the settings pages' suites, which each scroll
/// one `ListView`.
///
/// [within] narrows the paragraphs checked to one row's, the page still
/// scrolled to its end for overflow: Calendar settings cuts two texts on
/// purpose at de/ro 2.0 — its search hint and the holiday set's shown name.
Future<void> expectPageWhole(WidgetTester tester, {Finder? within}) async {
  final list = find.byType(ListView);
  final paragraphs = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  for (var i = 0; i < 60; i++) {
    expect(tester.takeException(), isNull);
    for (final element in paragraphs.evaluate()) {
      final paragraph = element.renderObject;
      if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
      final text = paragraph.text.toPlainText();
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text"');
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
        reason: '"$text" is cut short',
      );
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.textSize.width - 0.01),
        reason: '"$text" is cut at the side',
      );
      final longestWord = paragraph.getMinIntrinsicWidth(double.infinity);
      if (longestWord <= paragraph.constraints.maxWidth) {
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(longestWord - 0.01),
          reason: '"$text" breaks inside a word',
        );
      }
      expectBreaksBetweenWords(paragraph);
    }
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    if (position.pixels >= position.maxScrollExtent) return;
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  fail('the page never reached its end');
}
