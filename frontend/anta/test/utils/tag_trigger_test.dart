import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/tag_trigger.dart';

/// Where a `#tag` session opens. Everything the editor does not paint as a
/// tag must stay shut, so a heading, a set number or a link never brings the
/// bar up.
void main() {
  /// [line] with `|` marking the caret.
  TagTriggerMatch? at(String line) {
    final caret = line.indexOf('|');
    return TagTrigger.matchAt(line.replaceFirst('|', ''), caret);
  }

  (int, int, String)? shape(TagTriggerMatch? match) =>
      match == null ? null : (match.hashOffset, match.tagEnd, match.query);

  group('opens', () {
    test('at the first character after a # at the line start', () {
      expect(shape(at('#l|')), (0, 2, '#l'));
      expect(shape(at('#le|')), (0, 3, '#le'));
    });

    test('mid-line after a space and after punctuation', () {
      expect(shape(at('squats #le|')), (7, 10, '#le'));
      expect(shape(at('squats, (#le|')), (9, 12, '#le'));
      expect(shape(at('- [ ] #le|')), (6, 9, '#le'));
    });

    test('with the caret inside a tag: the range runs to the tag end, the '
        'query to the caret', () {
      expect(shape(at('#le|gday sets')), (0, 7, '#le'));
    });

    test('on nested, accented and digit-led tags', () {
      expect(shape(at('#program/5x|')), (0, 11, '#program/5x'));
      expect(shape(at('#Übung|')), (0, 6, '#Übung'));
      expect(shape(at('a #tracțiune|')), (2, 12, '#tracțiune'));
      expect(shape(at('#5x5|')), (0, 4, '#5x5'));
    });
  });

  group('stays shut', () {
    test('on a bare #, and on a caret before or on the #', () {
      expect(at('#|'), isNull);
      expect(at('squats #|'), isNull);
      expect(at('|#legday'), isNull);
      expect(at('a |#legday'), isNull);
    });

    test('on a heading, a number and a # glued to a word', () {
      expect(at('# |'), isNull);
      expect(at('# T|itle'), isNull);
      expect(at('## Title|'), isNull);
      expect(at('set #123|'), isNull);
      expect(at('#5|'), isNull, reason: 'a digit-led body needs a letter');
      expect(at('abc#le|'), isNull);
    });

    test('inside a code span, a URL and a ghost run', () {
      expect(at('`#le|`'), isNull);
      expect(at('see https://a.b/c#le|'), isNull);
      expect(at('{{#le|}}'), isNull);
    });

    test('on a line with no # at all', () {
      expect(at('just words|'), isNull);
      expect(at(''), isNull);
    });
  });
}
