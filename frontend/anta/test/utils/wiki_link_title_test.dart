import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/wiki_link_title.dart';

void main() {
  const limit = WikiLinkTitle.maxDisplayLength;

  group('WikiLinkTitle.forDisplay', () {
    test('trims the surrounding whitespace', () {
      expect(
        WikiLinkTitle.forDisplay('  Squat Progression \n'),
        'Squat '
        'Progression',
      );
      expect(WikiLinkTitle.forDisplay('   '), '');
      expect(WikiLinkTitle.forDisplay(''), '');
    });

    test('leaves a title at or under the limit alone', () {
      expect(WikiLinkTitle.forDisplay('Groceries'), 'Groceries');
      final exact = 'a' * limit;
      expect(WikiLinkTitle.forDisplay(exact), exact);
    });

    test('elides one cluster past the limit', () {
      final shown = WikiLinkTitle.forDisplay('a' * (limit + 1));

      expect(shown, '${'a' * (limit - 1)}…');
      expect(shown.characters.length, limit);
    });

    test('measures the limit after trimming, not before', () {
      // The title is exactly at the limit; only the padding pushes the raw
      // string past it, and trimming first is what keeps the title whole.
      final padded = '  ${'b' * limit}  ';
      expect(padded.length, greaterThan(limit));
      expect(WikiLinkTitle.forDisplay(padded), 'b' * limit);
    });

    test('never splits a surrogate pair at the cut', () {
      // One cluster, two code units: the cut lands exactly between the
      // 79th and 80th of them, which is where a code-unit substring breaks.
      const emoji = '\u{1F4AA}';
      final shown = WikiLinkTitle.forDisplay(emoji * (limit + 5));

      expect(shown, '${emoji * (limit - 1)}…');
      expect(shown.characters.length, limit);
      // A half-eaten pair leaves an unpaired surrogate behind.
      expect(shown.runes.any((r) => r >= 0xD800 && r <= 0xDFFF), isFalse);
    });

    test('never splits a combining mark from its base at the cut', () {
      // `e` + U+0301 combining acute: one cluster, two code points.
      const cluster = 'é';
      final shown = WikiLinkTitle.forDisplay(cluster * (limit + 5));

      expect(shown, '${cluster * (limit - 1)}…');
      expect(shown.characters.length, limit);
      // The ellipsis follows a complete cluster, never a bare accent.
      expect(shown.endsWith('$cluster…'), isTrue);
      expect(shown.runes.last, 0x2026);
    });

    test('a ZWJ family emoji counts as the one cluster it renders as', () {
      // Seven code points, eleven code units, one grapheme cluster.
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}‍\u{1F466}';
      expect(family.characters.length, 1);
      expect(family.length, 11);

      // Well past the limit in code units, well under it in clusters.
      final short = family * 10;
      expect(short.length, greaterThan(limit));
      expect(WikiLinkTitle.forDisplay(short), short);

      final shown = WikiLinkTitle.forDisplay(family * (limit + 5));
      expect(shown, '${family * (limit - 1)}…');
      expect(shown.characters.length, limit);
    });
  });
}
