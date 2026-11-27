import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/text_fit.dart';

/// The cut every title and name takes to fit its column: on whole
/// user-perceived characters, counted in UTF-16 code units, never past the
/// limit, and never to nothing while a part of a character still fits.
void main() {
  group('cut', () {
    test('a text that fits comes back as it is', () {
      expect(TextFit.cut('abc', 3), 'abc');
      expect(TextFit.cut('abc', 10), 'abc');
      expect(TextFit.cut('', 5), '');
    });

    test('an ASCII text is cut to the limit', () {
      expect(TextFit.cut('abcdef', 4), 'abcd');
    });

    test('never leaves half of a surrogate pair', () {
      // The limit falls between the emoji's two code units.
      expect(TextFit.cut('ab😀c', 3), 'ab');
      expect(TextFit.cut('ab😀c', 4), 'ab😀');
    });

    test('keeps an accent with its letter', () {
      // "é" as e + U+0301: the limit falls between the two.
      expect(TextFit.cut('abéz', 3), 'ab');
      expect(TextFit.cut('abéz', 4), 'abé');
    });

    test('keeps an emoji sequence whole', () {
      // Two people joined by U+200D: five code units.
      const family = '\u{1F468}‍\u{1F469}';
      expect(TextFit.cut('x${family}y', 4), 'x');
      expect(TextFit.cut('x${family}y', 6), 'x$family');
    });

    test('keeps a flag whole', () {
      // Two regional indicators: four code units, one character.
      const flag = '\u{1F1F7}\u{1F1F4}';
      expect(TextFit.cut('x${flag}y', 3), 'x');
      expect(TextFit.cut('x${flag}y', 5), 'x$flag');
    });

    test('a text that is one character past the limit keeps the code units '
        'that fit, a surrogate pair whole', () {
      final accents = 'e${'́' * 300}';
      expect(TextFit.cut(accents, 255), 'e${'́' * 254}');
      // A base of two code units is never split.
      final wide = '😀${'́' * 10}';
      expect(TextFit.cut(wide, 5), '😀${'́' * 3}');
      expect(TextFit.cut(wide, 1), '');
    });
  });

  group('withSuffix', () {
    test('a base that fits beside the suffix is kept whole', () {
      expect(TextFit.withSuffix('abc', ' (2)', 10), 'abc (2)');
    });

    test('the base is cut so that it and the suffix fit, on whole '
        'characters', () {
      expect(TextFit.withSuffix('abcdef', ' (2)', 7), 'abc (2)');
      expect(TextFit.withSuffix('ab😀c', ' (2)', 7), 'ab (2)');
    });

    test('a suffix that fills the limit stands alone', () {
      expect(TextFit.withSuffix('abc', ' (2)', 4), ' (2)');
    });

    test('a suffix longer than the limit is cut to it', () {
      expect(TextFit.withSuffix('abcdef', ' (10)', 3), ' (1');
      expect(TextFit.withSuffix('', ' (10)', 3), ' (1');
    });
  });
}
