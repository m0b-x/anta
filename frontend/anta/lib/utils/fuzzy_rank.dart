/// Tiered approximate matching, shared by the editor's vocabulary suggestion
/// bar and the agenda's "did you mean" chip.
///
/// Four tiers, best first: a prefix of the candidate, a hit at a word start, a
/// hit anywhere, and finally an ordered character subsequence — which is what
/// lets "gtlnt" reach "Great Lent" and "orthodx" reach "Orthodox".
///
/// Deliberately separate from the agenda's *filtering* grammar
/// (`event_search_query.dart`), which stays exact-substring: this ranks a small
/// catalogue to suggest a correction, it never decides what a query matches.
library;

import '../services/folder_search_service.dart';

class FuzzyRank {
  FuzzyRank._();

  static const int tierPrefix = 0;
  static const int tierWordStart = 1;
  static const int tierSubstring = 2;
  static const int tierSubsequence = 3;
  static const int tiers = 4;

  /// Lower is better; `-1` means no match. Both arguments must already be
  /// folded through [normalizeForSearch].
  static int score(String term, String query) {
    if (term.startsWith(query)) return tierPrefix;

    final index = term.indexOf(query);
    if (index > 0) {
      return _isWordStart(term, index) ? tierWordStart : tierSubstring;
    }

    return _isSubsequence(term, query) ? tierSubsequence : -1;
  }

  /// The best [limit] of [candidates] for [query], strongest tier first and
  /// input order preserved inside a tier.
  ///
  /// Folds both sides itself, so callers hand it display strings. That is
  /// affordable because it runs over a catalogue of dozens, and only when a
  /// search has already come back empty.
  static List<String> best(
    Iterable<String> candidates,
    String query, {
    int limit = 3,
  }) {
    final folded = normalizeForSearch(query.trim());
    if (limit <= 0 || folded.isEmpty) return const [];

    final buckets = List<List<String>?>.filled(tiers, null);
    final seen = <String>{};
    for (final candidate in candidates) {
      if (candidate.isEmpty || !seen.add(candidate)) continue;
      final tier = score(normalizeForSearch(candidate), folded);
      if (tier < 0) continue;
      (buckets[tier] ??= <String>[]).add(candidate);
    }

    final results = <String>[];
    for (final bucket in buckets) {
      if (bucket == null) continue;
      for (final candidate in bucket) {
        results.add(candidate);
        if (results.length == limit) return results;
      }
    }
    return results;
  }

  static bool _isWordStart(String term, int index) {
    return !_isWordChar(term.codeUnitAt(index - 1));
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
