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

  static const int _scorePrefix = 0;
  static const int _scoreWordStart = 1;
  static const int _scoreSubstring = 2;
  static const int _scoreSubsequence = 3;
  static const int _tiers = 4;

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
      final score = _score(candidate.foldedTerm, folded);
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

  /// Lower is better; `-1` means no match.
  static int _score(String term, String query) {
    if (term.startsWith(query)) return _scorePrefix;

    final index = term.indexOf(query);
    if (index > 0) {
      return _isWordStart(term, index) ? _scoreWordStart : _scoreSubstring;
    }

    return _isSubsequence(term, query) ? _scoreSubsequence : -1;
  }

  static bool _isWordStart(String term, int index) {
    final previous = term.codeUnitAt(index - 1);
    return !_isWordChar(previous);
  }

  static bool _isWordChar(int c) {
    if (c >= 0x30 && c <= 0x39) return true;
    if (c >= 0x61 && c <= 0x7A) return true;
    if (c >= 0x41 && c <= 0x5A) return true;
    return c > 0x7F;
  }

  static bool _isSubsequence(String term, String query) {
    final termLength = term.length;
    final queryLength = query.length;
    if (queryLength > termLength) return false;

    var q = 0;
    for (var t = 0; t < termLength && q < queryLength; t++) {
      if (term.codeUnitAt(t) == query.codeUnitAt(q)) q++;
    }
    return q == queryLength;
  }
}
