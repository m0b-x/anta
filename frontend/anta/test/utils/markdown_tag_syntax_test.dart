import 'package:anta/utils/markdown_tag_syntax.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tag text [MarkdownTagSyntax.tryParseTagAt] claims for the `#` at
/// [i], or null when it claims none.
String? tagAt(String text, int i) {
  final end = MarkdownTagSyntax.tryParseTagAt(text, i);
  return end == null ? null : text.substring(i, end);
}

void main() {
  group('tryParseTagAt', () {
    test('letter-led bodies are tags', () {
      expect(tagAt('#gym', 0), '#gym');
      expect(tagAt('#squat_day-2', 0), '#squat_day-2');
      expect(tagAt('#ăstăzi', 0), '#ăstăzi');
    });

    test('an inner slash joins the body', () {
      expect(tagAt('#program/5x5', 0), '#program/5x5');
      expect(tagAt('#gym/legs/heavy now', 0), '#gym/legs/heavy');
    });

    test('a trailing or doubled slash is not part of the tag', () {
      expect(tagAt('#program/', 0), '#program');
      expect(tagAt('#program/ next', 0), '#program');
      expect(tagAt('#a//b', 0), '#a');
      expect(tagAt('#a/.', 0), '#a');
    });

    test('digit-led bodies holding a letter are tags', () {
      expect(tagAt('#5x5', 0), '#5x5');
      expect(tagAt('#1rm', 0), '#1rm');
      expect(tagAt('#531a', 0), '#531a');
      expect(tagAt('#2026/review', 0), '#2026/review');
    });

    test('all-digit bodies stay prose', () {
      expect(tagAt('#123', 0), isNull);
      expect(tagAt('#3', 0), isNull);
      expect(tagAt('set #1', 4), isNull);
      expect(tagAt('#12-3', 0), isNull);
      expect(tagAt('#2026/10', 0), isNull);
    });

    test('a body must start with a letter or a digit', () {
      expect(tagAt('#', 0), isNull);
      expect(tagAt('#_x', 0), isNull);
      expect(tagAt('#-x', 0), isNull);
      expect(tagAt('#/x', 0), isNull);
      expect(tagAt('# x', 0), isNull);
    });
  });
}
