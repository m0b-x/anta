import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/vocabulary_trigger.dart';

/// The half of the feature that must never misfire.
///
/// A suggestion bar that opens on `3x8 @ 60kg` or on an email address would
/// make the trigger character unusable in ordinary text, so most of this file
/// is about what does **not** start a session.
void main() {
  VocabularyTriggerMatch? matchAt(String line, int caret, {String trigger = '@'}) {
    return VocabularyTrigger.matchAt(line, caret, trigger: trigger);
  }

  group('opens a session', () {
    test('on a bare trigger at the line start', () {
      final match = matchAt('@', 1);

      expect(match, isNotNull);
      expect(match!.triggerOffset, 0);
      expect(match.query, '');
      expect(match.queryEnd, 1);
    });

    test('on a trigger after whitespace', () {
      final match = matchAt('- 3x8 @ben', 10);

      expect(match, isNotNull);
      expect(match!.triggerOffset, 6);
      expect(match.query, 'ben');
    });

    test('after a list marker', () {
      final match = matchAt('- @squ', 6);

      expect(match?.triggerOffset, 2);
      expect(match?.query, 'squ');
    });

    test('with one internal space, so two-word terms can be typed', () {
      final match = matchAt('@bench p', 8);

      expect(match, isNotNull);
      expect(match!.query, 'bench p');
    });

    test('with a trailing space, so the bar does not blink mid-phrase', () {
      final match = matchAt('@bench ', 7);

      expect(match?.query, 'bench ');
    });

    test('with the caret inside the query, not only at its end', () {
      final match = matchAt('@bench', 4);

      expect(match, isNotNull);
      expect(match!.query, 'ben');
      expect(match.queryEnd, 4);
    });

    test('on a configured non-default trigger', () {
      final match = matchAt('sets: ;squ', 10, trigger: ';');

      expect(match?.triggerOffset, 6);
      expect(match?.query, 'squ');
    });
  });

  group('scope segments', () {
    test('a leading name before the colon becomes the scope', () {
      final match = matchAt('@exercise:ben', 13);

      expect(match, isNotNull);
      expect(match!.scopeTokens, ['exercise']);
      expect(match.query, 'ben');
      expect(match.triggerOffset, 0);
    });

    test('commas name several lists', () {
      final match = matchAt('@exercises,meals:oat', 20);

      expect(match?.scopeTokens, ['exercises', 'meals']);
      expect(match?.query, 'oat');
    });

    test('tokens are trimmed and blanks dropped, never folded', () {
      final match = matchAt('@Exercises ,,Meals:oat', 22);

      expect(match?.scopeTokens, ['Exercises', 'Meals']);
    });

    test('an empty scope segment is an ordinary query for the rest', () {
      final match = matchAt('@:ben', 5);

      expect(match?.scopeTokens, isEmpty);
      expect(match?.query, 'ben');
    });

    test('a scope with nothing typed after it keeps an empty query', () {
      final match = matchAt('@exercise:', 10);

      expect(match?.scopeTokens, ['exercise']);
      expect(match?.query, '');
    });

    test('no colon leaves the shape it has always had', () {
      final match = matchAt('@ben', 4);

      expect(match?.scopeTokens, isEmpty);
      expect(match?.query, 'ben');
    });

    test('the split is of the run, so prose colons are never a scope', () {
      final match = matchAt('sets: @ben', 10);

      expect(match?.triggerOffset, 6);
      expect(match?.scopeTokens, isEmpty);
      expect(match?.query, 'ben');
    });

    test('the split does not depend on which character triggered', () {
      final match = matchAt(';exercise:ben', 13, trigger: ';');

      expect(match?.scopeTokens, ['exercise']);
      expect(match?.query, 'ben');
    });

    /// The one shape scoping cannot reach. With `:` configured as the trigger,
    /// the separating colon is itself a mid-word trigger occurrence, and the
    /// guard that keeps `a@b.com` out of the feature fires first. Widening it
    /// would trade a working invariant for a syntax that is still available on
    /// every other trigger character.
    test('a colon trigger cannot carry a scope, by the mid-word guard', () {
      expect(matchAt(':exercise:ben', 13, trigger: ':'), isNull);
    });

    test('the raw run stays recoverable for an unresolvable scope', () {
      const line = '- 3x8 @zzz:ben';
      final match = matchAt(line, 14);

      expect(
        line.substring(match!.triggerOffset + 1, match.queryEnd),
        'zzz:ben',
      );
    });
  });

  group('leaves ordinary text alone', () {
    test('when the trigger is followed by a space (a weight annotation)', () {
      expect(matchAt('3x8 @ 60kg', 10), isNull);
      expect(matchAt('3x8 @ ', 6), isNull);
    });

    test('when the trigger sits mid-word (an email or a set shorthand)', () {
      expect(matchAt('alex@example.com', 16), isNull);
      expect(matchAt('5x5@100kg', 9), isNull);
    });

    test('after a second space ends the query', () {
      expect(matchAt('@bench press x', 14), isNull);
    });

    test('when there is no trigger at all', () {
      expect(matchAt('bench press', 11), isNull);
    });

    test('past the maximum query length', () {
      final line = '@${'a' * (VocabularyTrigger.maxQueryLength + 5)}';

      expect(matchAt(line, line.length), isNull);
    });

    test('inside a ghost run, which owns its own session', () {
      const line = '- {{@exercise}} 3x8';

      expect(matchAt(line, 13), isNull);
    });

    test('for a caret at or before the line start', () {
      expect(matchAt('@ben', 0), isNull);
      expect(matchAt('@ben', 99), isNull);
    });

    test('for a multi-character trigger, which cannot be typed as one key', () {
      expect(matchAt('::ben', 5, trigger: '::'), isNull);
    });
  });
}
