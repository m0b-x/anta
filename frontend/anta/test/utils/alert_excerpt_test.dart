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
    expect(alertExcerptFor('![shot](https://x/y.png) after'), 'after');
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
}
