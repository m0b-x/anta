/// Ranking of vocabulary terms against what the user has typed so far.
///
/// Pure and allocation-light: the editor calls this on every keystroke while a
/// suggestion session is open, over a candidate list held in memory by the
/// `Vocabularies` facade.
///
/// Folding goes through [normalizeForSearch], the app's single diacritic/case
/// table — "împins" matches "impins", "Bench" matches "bench". Terms are stored
/// and shown verbatim and only ever *matched* folded, the canonicalization
/// policy the tag roadmap sets for user-authored strings.
library;

import '../services/folder_search_service.dart';
import 'fuzzy_rank.dart';

/// One term, pre-folded, with everything the suggestion bar needs to render it.
///
/// [foldedTerm] is computed once when the facade publishes its cache, never per
/// keystroke.
class VocabularyCandidate {
  final String term;
  final String foldedTerm;
  final String vocabularyId;
  final String vocabularyName;
  final int vocabularySortOrder;
  final int itemSortOrder;

  const VocabularyCandidate({
    required this.term,
    required this.foldedTerm,
    required this.vocabularyId,
    required this.vocabularyName,
    required this.vocabularySortOrder,
    required this.itemSortOrder,
  });
}

class VocabularyMatcher {
  VocabularyMatcher._();

  /// How many pills the bar shows. Beyond this the user is better served by
  /// typing another character than by scrolling.
  static const int maxResults = 8;

  /// Tiering lives in [FuzzyRank], shared with the agenda's suggestion chip.
  static const int _scorePrefix = FuzzyRank.tierPrefix;
  static const int _tiers = FuzzyRank.tiers;

  /// Ranks [candidates] against [query].
  ///
  /// An empty [query] — the state right after the trigger character, or a ghost
  /// that has just been engaged — returns the head of the list unfiltered, so
  /// the bar always has something to show.
  ///
  /// [vocabularyIds] scopes the result to those lists — how an engaged
  /// `{{exercise}}` ghost narrows itself to the Exercises vocabulary, and how a
  /// `@exercises,meals:oat` trigger narrows itself to the two it names. `null`
  /// is unscoped; an empty set matches nothing, since a caller that resolved a
  /// scope to nothing must not silently search everything.
  ///
  /// [candidates] is expected to arrive already ordered by
  /// `(vocabularySortOrder, itemSortOrder)`; results preserve that order inside
  /// each score tier, so the user's own list order is the tie-break.
  static List<VocabularyCandidate> match(
    List<VocabularyCandidate> candidates,
    String query, {
    Set<String>? vocabularyIds,
    int limit = maxResults,
  }) {
    if (limit <= 0 || candidates.isEmpty) return const [];

    final folded = normalizeForSearch(query.trim());

    if (folded.isEmpty) {
      final head = <VocabularyCandidate>[];
      for (final candidate in candidates) {
        if (vocabularyIds != null &&
            !vocabularyIds.contains(candidate.vocabularyId)) {
          continue;
        }
        head.add(candidate);
        if (head.length == limit) break;
      }
      return head;
    }

    final buckets = List<List<VocabularyCandidate>?>.filled(_tiers, null);
    var bestCount = 0;

    for (final candidate in candidates) {
      if (vocabularyIds != null &&
          !vocabularyIds.contains(candidate.vocabularyId)) {
        continue;
      }
      final score = FuzzyRank.score(candidate.foldedTerm, folded);
      if (score < 0) continue;

      (buckets[score] ??= <VocabularyCandidate>[]).add(candidate);

      if (score == _scorePrefix && ++bestCount == limit) break;
    }

    final results = <VocabularyCandidate>[];
    for (final bucket in buckets) {
      if (bucket == null) continue;
      for (final candidate in bucket) {
        results.add(candidate);
        if (results.length == limit) return results;
      }
    }
    return results;
  }
}
