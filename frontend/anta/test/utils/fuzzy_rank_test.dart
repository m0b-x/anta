import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/fuzzy_rank.dart';

/// [FuzzyRank] only ever *suggests* — the agenda's filtering grammar stays
/// exact-substring. What matters here is the ordering of the four tiers and
/// that a plausible typo still reaches its target, since a suggestion nobody
/// would have typed is worse than no suggestion at all.
void main() {
  group('tier ordering', () {
    test('a prefix outranks a word start, which outranks a bare substring', () {
      final ranked = FuzzyRank.best(
        const ['Unfasten belt', 'Morning fast', 'Fasting'],
        'fast',
        limit: 3,
      );

      expect(ranked, ['Fasting', 'Morning fast', 'Unfasten belt']);
    });

    test('a subsequence is the last resort, never a first choice', () {
      final ranked = FuzzyRank.best(
        const ['Great Lent', 'Lent'],
        'lent',
        limit: 2,
      );

      expect(
        ranked.first,
        'Lent',
        reason:
            'the exact prefix must win over the one that merely contains it',
      );
    });
  });

  group('typo recovery', () {
    test('a dropped letter still reaches its target', () {
      expect(FuzzyRank.best(const ['Orthodox', 'Catholic'], 'orthodx'), [
        'Orthodox',
      ]);
    });

    test('initials reach a multi-word name', () {
      expect(FuzzyRank.best(const ['Great Lent'], 'gtlnt'), ['Great Lent']);
    });

    test('a query longer than the candidate cannot match', () {
      expect(FuzzyRank.best(const ['Lent'], 'lentils'), isEmpty);
    });
  });

  group('folding', () {
    test('diacritics and case fold both ways', () {
      expect(FuzzyRank.best(const ['Postul Paștelui'], 'pastelui'), [
        'Postul Paștelui',
      ]);
      expect(FuzzyRank.best(const ['Sarbatoare'], 'SĂRBĂ'), ['Sarbatoare']);
    });
  });

  group('bounds', () {
    test('an empty or blank query suggests nothing', () {
      expect(FuzzyRank.best(const ['Lent'], ''), isEmpty);
      expect(FuzzyRank.best(const ['Lent'], '   '), isEmpty);
    });

    test('nothing plausible yields nothing rather than noise', () {
      expect(FuzzyRank.best(const ['Orthodox', 'Catholic'], 'zzzz'), isEmpty);
    });

    test('the limit is honoured across tiers', () {
      final ranked = FuzzyRank.best(
        const ['Fasting', 'Fast day', 'Morning fast', 'Breakfast'],
        'fast',
        limit: 2,
      );

      expect(ranked, hasLength(2));
    });

    test('a repeated candidate is offered once', () {
      expect(FuzzyRank.best(const ['Lent', 'Lent'], 'lent'), ['Lent']);
    });

    test('a zero limit yields nothing', () {
      expect(FuzzyRank.best(const ['Lent'], 'lent', limit: 0), isEmpty);
    });
  });
}
