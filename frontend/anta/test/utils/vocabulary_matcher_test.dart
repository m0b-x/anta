import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/folder_search_service.dart';
import 'package:anta/utils/vocabulary_matcher.dart';

/// Ranking rules for the suggestion bar.
///
/// The tie-break matters as much as the scoring: candidates arrive ordered by
/// `(vocabularySortOrder, itemSortOrder)`, and that order — the user's own —
/// must survive inside every score tier.
void main() {
  VocabularyCandidate candidate(
    String term, {
    String vocabularyId = 'v1',
    String vocabularyName = 'Exercises',
    int vocabularySortOrder = 0,
    int itemSortOrder = 0,
  }) {
    return VocabularyCandidate(
      term: term,
      foldedTerm: normalizeForSearch(term),
      vocabularyId: vocabularyId,
      vocabularyName: vocabularyName,
      vocabularySortOrder: vocabularySortOrder,
      itemSortOrder: itemSortOrder,
    );
  }

  List<String> terms(List<VocabularyCandidate> results) => [
    for (final result in results) result.term,
  ];

  group('scoring', () {
    test('prefix beats word-start beats substring beats subsequence', () {
      final candidates = [
        // Subsequence only: b…e…n scattered across the term.
        candidate('Barbell Row Negative', itemSortOrder: 0),
        // Substring, mid-word — 'ben' is preceded by a letter.
        candidate('Overbenched Hold', itemSortOrder: 1),
        candidate('Incline Bench Press', itemSortOrder: 2),
        candidate('Bench Press', itemSortOrder: 3),
      ];

      final results = VocabularyMatcher.match(candidates, 'ben');

      expect(terms(results), [
        'Bench Press',
        'Incline Bench Press',
        'Overbenched Hold',
        'Barbell Row Negative',
      ]);
    });

    test('a subsequence spanning words still matches', () {
      final candidates = [candidate('Bench Press')];

      expect(terms(VocabularyMatcher.match(candidates, 'benchp')), [
        'Bench Press',
      ]);
    });

    test('a term that shares no ordered letters is excluded', () {
      final candidates = [candidate('Bench Press'), candidate('Deadlift')];

      expect(VocabularyMatcher.match(candidates, 'zzz'), isEmpty);
    });

    test('the user list order breaks ties inside a tier', () {
      final candidates = [
        candidate('Bench Press', itemSortOrder: 0),
        candidate('Bench Dips', itemSortOrder: 1),
        candidate('Bench Row', itemSortOrder: 2),
      ];

      expect(terms(VocabularyMatcher.match(candidates, 'bench')), [
        'Bench Press',
        'Bench Dips',
        'Bench Row',
      ]);
    });
  });

  group('folding', () {
    test('ignores case', () {
      final candidates = [candidate('Bench Press')];

      expect(VocabularyMatcher.match(candidates, 'BENCH'), hasLength(1));
    });

    test('ignores diacritics in both directions', () {
      final candidates = [
        candidate('Împins la piept'),
        candidate('Genuflexiuni'),
      ];

      expect(terms(VocabularyMatcher.match(candidates, 'impins')), [
        'Împins la piept',
      ]);
      expect(terms(VocabularyMatcher.match(candidates, 'Genuflexiuni')), [
        'Genuflexiuni',
      ]);
    });

    test('trims the query, so a trailing space still filters', () {
      final candidates = [candidate('Bench Press'), candidate('Deadlift')];

      expect(terms(VocabularyMatcher.match(candidates, 'bench ')), [
        'Bench Press',
      ]);
    });
  });

  group('scoping and limits', () {
    test('an empty query returns the head of the list unfiltered', () {
      final candidates = [
        for (var i = 0; i < 20; i++) candidate('Term $i', itemSortOrder: i),
      ];

      final results = VocabularyMatcher.match(candidates, '');

      expect(results, hasLength(VocabularyMatcher.maxResults));
      expect(results.first.term, 'Term 0');
    });

    test('results are capped even when everything matches', () {
      final candidates = [
        for (var i = 0; i < 20; i++) candidate('Bench $i', itemSortOrder: i),
      ];

      expect(
        VocabularyMatcher.match(candidates, 'bench'),
        hasLength(VocabularyMatcher.maxResults),
      );
    });

    test('a vocabulary id narrows the result to that list', () {
      final candidates = [
        candidate('Bench Press', vocabularyId: 'v1'),
        candidate(
          'Bench Sandwich',
          vocabularyId: 'v2',
          vocabularyName: 'Meals',
        ),
      ];

      expect(terms(VocabularyMatcher.match(candidates, 'bench')), [
        'Bench Press',
        'Bench Sandwich',
      ]);
      expect(
        terms(
          VocabularyMatcher.match(candidates, 'bench', vocabularyIds: {'v2'}),
        ),
        ['Bench Sandwich'],
      );
    });

    test('several ids scope to their union, in candidate order', () {
      final candidates = [
        candidate('Bench Press', vocabularyId: 'v1'),
        candidate(
          'Bench Sandwich',
          vocabularyId: 'v2',
          vocabularyName: 'Meals',
        ),
        candidate(
          'Bench Client',
          vocabularyId: 'v3',
          vocabularyName: 'Clients',
        ),
      ];

      expect(
        terms(
          VocabularyMatcher.match(
            candidates,
            'bench',
            vocabularyIds: {'v1', 'v3'},
          ),
        ),
        ['Bench Press', 'Bench Client'],
      );
    });

    /// A caller that resolved a scope to nothing must not fall through to
    /// searching everything — that decision belongs upstream, where the raw
    /// run is still available.
    test('an empty id set matches nothing, while null is unscoped', () {
      final candidates = [candidate('Bench Press')];

      expect(
        VocabularyMatcher.match(candidates, 'bench', vocabularyIds: const {}),
        isEmpty,
      );
      expect(
        VocabularyMatcher.match(candidates, '', vocabularyIds: const {}),
        isEmpty,
      );
      expect(
        VocabularyMatcher.match(candidates, 'bench', vocabularyIds: null),
        hasLength(1),
      );
    });

    test('an empty candidate list or a zero limit yields nothing', () {
      expect(VocabularyMatcher.match(const [], 'bench'), isEmpty);
      expect(
        VocabularyMatcher.match([candidate('Bench Press')], 'bench', limit: 0),
        isEmpty,
      );
    });
  });
}
