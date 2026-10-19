import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/alert_excerpt.dart';

/// The excerpt is what a reminder's expandable body shows, so it has to read
/// like text rather than like markdown — and it must be a projection over
/// the grammar modules, never a second scanner of any construct.
void main() {
  test('takes the first non-empty line, plain', () {
    expect(alertExcerptFor(null), '');
    expect(alertExcerptFor(''), '');
    expect(alertExcerptFor('\n\n  \nSquat day\nsecond line'), 'Squat day');
  });

  test('headings lose their hashes', () {
    expect(alertExcerptFor('## Leg day'), 'Leg day');
    expect(alertExcerptFor('## Week 3 ##'), 'Week 3');
    expect(alertExcerptFor('## Title##'), 'Title##');
    expect(alertExcerptFor('#Not a heading'), '#Not a heading');
  });

  test('list items lose their markers, task boxes included', () {
    expect(alertExcerptFor('- squat'), 'squat');
    expect(alertExcerptFor('1. bench'), 'bench');
    expect(alertExcerptFor('- [ ] warm up'), 'warm up');
    expect(alertExcerptFor('- [x] warm up'), 'warm up');
  });

  test('links keep their text, wiki links their title', () {
    expect(
      alertExcerptFor('See [the plan](https://example.com) and [[Session 1]]'),
      'See the plan and Session 1',
    );
    expect(
      alertExcerptFor('before ![chart](https://x/y.png) after'),
      'before chart after',
    );
    expect(alertExcerptFor('![](https://x/y.png) after'), 'after');
  });

  test('a wiki alias reads as shown and an autolink loses its brackets', () {
    expect(alertExcerptFor('Do [[Session 1|legs]] today'), 'Do legs today');
    expect(
      alertExcerptFor('Mail <me@example.com> now'),
      'Mail me@example.com now',
    );
  });

  test('money lines read as amount and label', () {
    expect(alertExcerptFor(r'$+ 12.50 coffee'), '+12.50 coffee');
    expect(alertExcerptFor(r'$- 8 lunch'), '−8 lunch');
    expect(alertExcerptFor(r'$= 100'), '100');
  });

  test('inline chrome goes, code and escapes stay literal', () {
    expect(
      alertExcerptFor('**bold** and *it* and ==hl== and `x` and \\*lit\\*'),
      'bold and it and hl and x and *lit*',
    );
  });

  test('a horizontal rule is no excerpt at all', () {
    expect(alertExcerptFor('---\nreal text'), 'real text');
  });

  test('fences and table rows are skipped, quotes and callouts stripped', () {
    expect(alertExcerptFor('```\ncode\n```\nafter'), 'code');
    expect(alertExcerptFor('| a | b |\n| --- | --- |\nreal text'), 'real text');
    expect(alertExcerptFor('> quoted words'), 'quoted words');
    expect(alertExcerptFor('> [!note] Remember the belt'), 'Remember the belt');
  });

  test('caps at the limit with an ellipsis', () {
    final long = List.filled(40, 'word').join(' ');
    final excerpt = alertExcerptFor(long);
    expect(excerpt.length, kAlertExcerptMaxLength);
    expect(excerpt, endsWith('…'));
  });

  group('a cut that lands inside a surrogate pair', () {
    // The cap counts code units, and an emoji is two of them. Half of one is
    // not text: the engine refuses the whole string, so the alarm page drew
    // a single replacement character where the line should be, and a
    // notification carried a stray one before its ellipsis.
    const emoji = '\u{1F4AA}';

    bool isSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDFFF;

    test('never keeps the lead half alone', () {
      // 118 units, then the pair on 118 and 119: the last unit the cut keeps
      // is its lead half.
      final head = 'a' * (kAlertExcerptMaxLength - 2);
      final excerpt = alertExcerptFor('$head$emoji and the rest of the line');

      expect(excerpt, '$head…');
      expect(excerpt.codeUnits.any(isSurrogate), isFalse);
    });

    test('keeps a pair that ends on the last unit kept', () {
      final head = 'a' * (kAlertExcerptMaxLength - 3);
      final excerpt = alertExcerptFor('$head$emoji and the rest of the line');

      expect(excerpt, '$head$emoji…');
      expect(excerpt.length, kAlertExcerptMaxLength);
    });

    test('leaves a line of nothing but emoji well formed', () {
      // Every other unit is a lead half, so the cut lands on one whichever
      // way the cap is counted — unless the line starts one unit off.
      for (final lead in ['', 'a']) {
        final excerpt = alertExcerptFor('$lead${emoji * 80}');
        final units = excerpt.codeUnits;

        expect(excerpt, endsWith('…'), reason: '"$lead"');
        expect(units.length, lessThanOrEqualTo(kAlertExcerptMaxLength));
        for (var i = 0; i < units.length; i++) {
          final unit = units[i];
          if (unit >= 0xD800 && unit <= 0xDBFF) {
            expect(
              i + 1 < units.length &&
                  units[i + 1] >= 0xDC00 &&
                  units[i + 1] <= 0xDFFF,
              isTrue,
              reason: 'a lead half with no trail at $i ("$lead")',
            );
          }
        }
      }
    });
  });
}
