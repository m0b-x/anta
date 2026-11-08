import 'package:anta/services/folder_search_service.dart';

/// The in-memory inverted index the full search ran on until S11
/// (`docs/scalability-roadmap.md` §5.5), kept verbatim in its matching and
/// scoring as the oracle the body index is held to. Only the tokenizer is
/// today's: both sides moved to Unicode words together.
class LegacySearchIndex {
  final Map<String, Set<String>> _wordToNoteIds = {};
  final Map<String, Map<String, int>> _termFrequency = {};
  List<String> _sortedWords = [];

  void addNote(String noteId, String title, String content) {
    final terms = _termFrequency[noteId] = {};
    for (final word in searchTokens('$title $content')) {
      _wordToNoteIds.putIfAbsent(word, () => {}).add(noteId);
      terms[word] = (terms[word] ?? 0) + 1;
    }
    _sortedWords = [];
  }

  Set<String> search(String query) {
    final queryWords = tokenizeForSearch(normalizeForSearch(query));
    if (queryWords.isEmpty) return {};
    if (_sortedWords.isEmpty && _wordToNoteIds.isNotEmpty) {
      _sortedWords = _wordToNoteIds.keys.toList()..sort();
    }
    Set<String>? result;
    for (final word in queryWords) {
      final matching = _findMatchingNoteIds(word);
      result = result == null ? matching : result.intersection(matching);
      if (result.isEmpty) return {};
    }
    return result ?? {};
  }

  Set<String> _findMatchingNoteIds(String word) {
    final matchingIds = <String>{...?_wordToNoteIds[word]};
    final start = _lowerBound(_sortedWords, word);
    for (var i = start; i < _sortedWords.length; i++) {
      final indexed = _sortedWords[i];
      if (!indexed.startsWith(word)) break;
      matchingIds.addAll(_wordToNoteIds[indexed] ?? const {});
    }
    if (word.length >= 3) {
      for (final entry in _wordToNoteIds.entries) {
        if (entry.key.contains(word) && !entry.key.startsWith(word)) {
          matchingIds.addAll(entry.value);
        }
      }
    }
    return matchingIds;
  }

  int _lowerBound(List<String> sorted, String target) {
    var lo = 0;
    var hi = sorted.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (sorted[mid].compareTo(target) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  double getRelevanceScore(String noteId, String query) {
    final queryWords = tokenizeForSearch(normalizeForSearch(query));
    final noteTerms = _termFrequency[noteId];
    if (noteTerms == null || queryWords.isEmpty) return 0.0;

    var score = 0.0;
    var matchCount = 0;
    for (final word in queryWords) {
      if (noteTerms.containsKey(word)) {
        score += noteTerms[word]! * 2.0;
        matchCount++;
        continue;
      }
      for (final entry in noteTerms.entries) {
        if (entry.key.contains(word)) {
          score += entry.value;
          matchCount++;
          break;
        }
      }
    }
    if (matchCount == 0) return 0.0;
    return score * (matchCount / queryWords.length);
  }
}
