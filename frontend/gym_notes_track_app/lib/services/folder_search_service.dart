import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gym_notes_track_app/constants/search_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/isolate_data.dart';
import '../models/note_metadata.dart';
import 'note_storage_service.dart';

/// Top-level function for isolate processing (required by compute()).
///
/// Tokenizes through the same [searchTokens] the main-isolate
/// [SearchIndex] uses — `compute` isolates share all code, including
/// `SearchConstants`, so there is exactly one normalization. (A private
/// isolate-local diacritics map used to live here; it drifted from the
/// shared one — no Romanian entries — so notes bulk-indexed on launch
/// folded differently than the query side and never matched.)
Map<String, dynamic> _buildIndexInIsolate(List<NoteIndexData> notesData) {
  final wordToNoteIds = <String, Set<String>>{};
  final termFrequency = <String, Map<String, int>>{};

  for (final note in notesData) {
    final words = searchTokens('${note.title} ${note.content}');

    termFrequency[note.id] = {};

    for (final word in words) {
      wordToNoteIds.putIfAbsent(word, () => {});
      wordToNoteIds[word]!.add(note.id);

      termFrequency[note.id]!.putIfAbsent(word, () => 0);
      termFrequency[note.id]![word] = termFrequency[note.id]![word]! + 1;
    }
  }

  return {
    'wordToNoteIds': wordToNoteIds.map((k, v) => MapEntry(k, v.toList())),
    'termFrequency': termFrequency,
  };
}

String removeDiacritics(String text) {
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    buffer.write(SearchConstants.diacriticsMap[char] ?? char);
  }
  return buffer.toString();
}

String normalizeForSearch(String text, {bool caseSensitive = false}) {
  String normalized = removeDiacritics(text);
  if (!caseSensitive) {
    normalized = normalized.toLowerCase();
  }
  return normalized;
}

final RegExp _searchTokenRegex = RegExp(r'\b\w{2,}\b');

/// Every word occurrence of [text] as the search index stores and looks
/// words up: folded through [normalizeForSearch], split on word boundaries,
/// minimum two characters. **Duplicates preserved** — the index counts them
/// as term frequency, so a note mentioning "squat" five times outranks one
/// that mentions it once.
///
/// The single tokenizer for **both** sides of the index — the isolate bulk
/// build and the main-isolate [SearchIndex] — so the two can never fold
/// differently again.
List<String> searchTokens(String text) {
  final normalized = normalizeForSearch(text);
  return _searchTokenRegex
      .allMatches(normalized)
      .map((m) => m.group(0)!)
      .toList(growable: false);
}

/// Unique words of [text]: [searchTokens] deduplicated. The query-side
/// shape — a query word matters once no matter how often it is typed.
Set<String> tokenizeForSearch(String text) => searchTokens(text).toSet();

class SearchResult {
  final NoteMetadata metadata;
  final List<SearchMatch> matches;
  final double relevanceScore;

  const SearchResult({
    required this.metadata,
    required this.matches,
    required this.relevanceScore,
  });
}

class SearchMatch {
  final String text;
  final int startIndex;
  final int endIndex;
  final SearchMatchType type;

  const SearchMatch({
    required this.text,
    required this.startIndex,
    required this.endIndex,
    required this.type,
  });
}

enum SearchMatchType { title, content }

class SearchFilter {
  final String? folderId;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int? minContentLength;
  final int? maxContentLength;
  final bool caseSensitive;

  const SearchFilter({
    this.folderId,
    this.fromDate,
    this.toDate,
    this.minContentLength,
    this.maxContentLength,
    this.caseSensitive = false,
  });

  bool matches(NoteMetadata metadata) {
    if (folderId != null && metadata.folderId != folderId) {
      return false;
    }

    if (fromDate != null && metadata.updatedAt.isBefore(fromDate!)) {
      return false;
    }

    if (toDate != null && metadata.updatedAt.isAfter(toDate!)) {
      return false;
    }

    if (minContentLength != null &&
        metadata.contentLength < minContentLength!) {
      return false;
    }

    if (maxContentLength != null &&
        metadata.contentLength > maxContentLength!) {
      return false;
    }

    return true;
  }
}

class SearchIndex {
  Map<String, Set<String>> _wordToNoteIds = {};
  Map<String, Map<String, int>> _termFrequency = {};
  // Sorted list of unique words for binary search prefix matching
  List<String> _sortedWords = [];
  bool _isBuilt = false;

  bool get isBuilt => _isBuilt;

  void addNote(String noteId, String title, String content) {
    // Occurrence list, not a set: the loop below counts duplicates into
    // real term frequencies (a set fed every TF as 1, which made the
    // relevance scorer's frequency weighting a constant).
    final words = searchTokens('$title $content');

    _termFrequency[noteId] = {};

    for (final word in words) {
      _wordToNoteIds.putIfAbsent(word, () => {});
      _wordToNoteIds[word]!.add(noteId);

      _termFrequency[noteId]!.putIfAbsent(word, () => 0);
      _termFrequency[noteId]![word] = _termFrequency[noteId]![word]! + 1;
    }
  }

  void removeNote(String noteId) {
    _termFrequency.remove(noteId);

    for (final entry in _wordToNoteIds.entries) {
      entry.value.remove(noteId);
    }

    _wordToNoteIds.removeWhere((_, noteIds) => noteIds.isEmpty);
    // Invalidate sorted words cache
    _sortedWords = [];
  }

  /// Optimized search using binary search for prefix matching
  Set<String> search(String query, {bool caseSensitive = false}) {
    final normalizedQuery = normalizeForSearch(
      query,
      caseSensitive: caseSensitive,
    );
    final queryWords = _tokenize(normalizedQuery);

    if (queryWords.isEmpty) return {};

    // Ensure sorted words cache is built
    if (_sortedWords.isEmpty && _wordToNoteIds.isNotEmpty) {
      _sortedWords = _wordToNoteIds.keys.toList()..sort();
    }

    Set<String>? result;

    for (final word in queryWords) {
      final matchingIds = _findMatchingNoteIds(word);

      if (result == null) {
        result = matchingIds;
      } else {
        result = result.intersection(matchingIds);
      }

      // Early exit if no matches
      if (result.isEmpty) return {};
    }

    return result ?? {};
  }

  /// Find note IDs matching a word using binary search for prefix matches
  Set<String> _findMatchingNoteIds(String word) {
    final matchingIds = <String>{};

    // Exact match first (most common case)
    final exactMatch = _wordToNoteIds[word];
    if (exactMatch != null) {
      matchingIds.addAll(exactMatch);
    }

    // Binary search for prefix matches
    if (_sortedWords.isNotEmpty) {
      final startIdx = _lowerBound(_sortedWords, word);

      // Check words that start with our query word
      for (int i = startIdx; i < _sortedWords.length; i++) {
        final indexedWord = _sortedWords[i];
        if (!indexedWord.startsWith(word)) break;

        final noteIds = _wordToNoteIds[indexedWord];
        if (noteIds != null) {
          matchingIds.addAll(noteIds);
        }
      }

      // Also check for words that contain our query (substring match)
      // Only do this for longer query words to avoid too many matches
      if (word.length >= 3) {
        for (final entry in _wordToNoteIds.entries) {
          if (entry.key.contains(word) && !entry.key.startsWith(word)) {
            matchingIds.addAll(entry.value);
          }
        }
      }
    }

    return matchingIds;
  }

  /// Binary search to find the first index where word >= target
  int _lowerBound(List<String> sorted, String target) {
    int lo = 0;
    int hi = sorted.length;

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

  double getRelevanceScore(
    String noteId,
    String query, {
    bool caseSensitive = false,
  }) {
    final normalizedQuery = normalizeForSearch(
      query,
      caseSensitive: caseSensitive,
    );
    final queryWords = _tokenize(normalizedQuery);
    final noteTerms = _termFrequency[noteId];

    if (noteTerms == null || queryWords.isEmpty) return 0.0;

    double score = 0.0;
    int matchCount = 0;

    for (final word in queryWords) {
      // Exact match bonus
      if (noteTerms.containsKey(word)) {
        score += noteTerms[word]! * 2.0;
        matchCount++;
        continue;
      }

      // Prefix/substring match
      for (final entry in noteTerms.entries) {
        if (entry.key.contains(word)) {
          score += entry.value;
          matchCount++;
          break; // Only count once per query word
        }
      }
    }

    if (matchCount == 0) return 0.0;

    // Boost score based on how many query words matched
    return score * (matchCount / queryWords.length);
  }

  Set<String> _tokenize(String text) => tokenizeForSearch(text);

  void markBuilt() {
    _isBuilt = true;
    // Pre-build sorted words cache
    _sortedWords = _wordToNoteIds.keys.toList()..sort();
  }

  void clear() {
    _wordToNoteIds.clear();
    _termFrequency.clear();
    _sortedWords = [];
    _isBuilt = false;
  }

  static const _kWordToNoteIds = 'wordToNoteIds';
  static const _kTermFrequency = 'termFrequency';

  Map<String, dynamic> toJson() => {
    _kWordToNoteIds: _wordToNoteIds.map((k, v) => MapEntry(k, v.toList())),
    _kTermFrequency: _termFrequency,
  };

  void fromJson(Map<String, dynamic> json) {
    _wordToNoteIds = (json[_kWordToNoteIds] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as List).cast<String>().toSet()),
    );
    _termFrequency = (json[_kTermFrequency] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as Map<String, dynamic>).cast<String, int>()),
    );
    _sortedWords = _wordToNoteIds.keys.toList()..sort();
    _isBuilt = true;
  }
}

class FolderSearchService {
  static const int _maxRecentSearches = 10;
  static const String _recentSearchesKey = 'recent_searches';

  final NoteStorageService _storageService;
  final SearchIndex _searchIndex = SearchIndex();

  List<String> _recentSearches = [];
  bool _isInitialized = false;
  bool _isIndexing = false;

  FolderSearchService({required NoteStorageService storageService})
    : _storageService = storageService;

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _loadRecentSearches();
    _isInitialized = true;
  }

  /// Build search index using isolate for heavy processing
  Future<void> buildIndex() async {
    if (_isIndexing) return; // Prevent concurrent indexing

    await initialize();
    _isIndexing = true;

    try {
      _searchIndex.clear();

      final paginatedNotes = await _storageService.loadNotesPaginated(
        pageSize: 1000,
      );

      final notesData = <NoteIndexData>[];
      for (final metadata in paginatedNotes.notes) {
        final content = await _storageService.loadNoteContent(metadata.id);
        notesData.add(
          NoteIndexData(
            id: metadata.id,
            title: metadata.title,
            content: content,
          ),
        );
      }

      // Build index in isolate for large datasets (>50 notes)
      if (notesData.length > 50) {
        final indexData = await compute(_buildIndexInIsolate, notesData);
        _searchIndex.fromJson(indexData);
      } else {
        for (final note in notesData) {
          _searchIndex.addNote(note.id, note.title, note.content);
        }
        _searchIndex.markBuilt();
      }
    } finally {
      _isIndexing = false;
    }
  }

  Future<void> updateIndex(String noteId, String title, String content) async {
    await initialize();
    _searchIndex.removeNote(noteId);
    _searchIndex.addNote(noteId, title, content);
  }

  Future<void> removeFromIndex(String noteId) async {
    await initialize();
    _searchIndex.removeNote(noteId);
  }

  Future<List<SearchResult>> search(
    String query, {
    SearchFilter? filter,
    int limit = 50,
    bool caseSensitive = false,
  }) async {
    await initialize();

    if (query.trim().isEmpty) return [];

    await _addToRecentSearches(query);

    if (!_searchIndex.isBuilt) {
      await buildIndex();
    }

    final effectiveCaseSensitive = filter?.caseSensitive ?? caseSensitive;
    final matchingIds = _searchIndex.search(
      query,
      caseSensitive: effectiveCaseSensitive,
    );

    if (matchingIds.isEmpty) return [];

    // Load all notes ONCE, not inside the loop
    final paginatedNotes = await _storageService.loadNotesPaginated(
      pageSize: 1000,
    );

    // Create a lookup map for O(1) access
    final notesMap = {for (final n in paginatedNotes.notes) n.id: n};

    final results = <SearchResult>[];

    // Process matches in parallel for better performance
    final futures = matchingIds.map((noteId) async {
      final metadata = notesMap[noteId];
      if (metadata == null) return null;

      if (filter != null && !filter.matches(metadata)) {
        return null;
      }

      final content = await _storageService.loadNoteContent(noteId);
      final matches = _findMatches(
        query,
        metadata.title,
        content,
        caseSensitive: effectiveCaseSensitive,
      );
      final relevanceScore = _searchIndex.getRelevanceScore(
        noteId,
        query,
        caseSensitive: effectiveCaseSensitive,
      );

      return SearchResult(
        metadata: metadata,
        matches: matches,
        relevanceScore: relevanceScore,
      );
    });

    final searchResults = await Future.wait(futures);
    results.addAll(searchResults.whereType<SearchResult>());

    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    return results.take(limit).toList();
  }

  Future<List<SearchResult>> quickSearch(
    String query, {
    String? folderId,
    int limit = 10,
    bool caseSensitive = false,
  }) async {
    await initialize();

    if (query.trim().isEmpty) return [];

    final paginatedNotes = await _storageService.loadNotesPaginated(
      folderId: folderId,
      pageSize: 100,
    );

    final normalizedQuery = normalizeForSearch(
      query,
      caseSensitive: caseSensitive,
    );
    final results = <SearchResult>[];

    for (final metadata in paginatedNotes.notes) {
      final normalizedTitle = normalizeForSearch(
        metadata.title,
        caseSensitive: caseSensitive,
      );
      final normalizedPreview = normalizeForSearch(
        metadata.preview,
        caseSensitive: caseSensitive,
      );

      if (normalizedTitle.contains(normalizedQuery) ||
          normalizedPreview.contains(normalizedQuery)) {
        final titleMatches = _findMatchesInText(
          query,
          metadata.title,
          SearchMatchType.title,
          caseSensitive: caseSensitive,
        );
        final previewMatches = _findMatchesInText(
          query,
          metadata.preview,
          SearchMatchType.content,
          caseSensitive: caseSensitive,
        );

        double score = 0.0;
        if (normalizedTitle.contains(normalizedQuery)) score += 2.0;
        if (normalizedPreview.contains(normalizedQuery)) score += 1.0;

        results.add(
          SearchResult(
            metadata: metadata,
            matches: [...titleMatches, ...previewMatches],
            relevanceScore: score,
          ),
        );
      }
    }

    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

    return results.take(limit).toList();
  }

  List<SearchMatch> _findMatches(
    String query,
    String title,
    String content, {
    bool caseSensitive = false,
  }) {
    final matches = <SearchMatch>[];

    matches.addAll(
      _findMatchesInText(
        query,
        title,
        SearchMatchType.title,
        caseSensitive: caseSensitive,
      ),
    );
    matches.addAll(
      _findMatchesInText(
        query,
        content,
        SearchMatchType.content,
        caseSensitive: caseSensitive,
      ),
    );

    return matches;
  }

  List<SearchMatch> _findMatchesInText(
    String query,
    String text,
    SearchMatchType type, {
    bool caseSensitive = false,
  }) {
    final matches = <SearchMatch>[];
    final normalizedQuery = normalizeForSearch(
      query,
      caseSensitive: caseSensitive,
    );
    final normalizedText = normalizeForSearch(
      text,
      caseSensitive: caseSensitive,
    );

    int index = 0;
    while (true) {
      final matchIndex = normalizedText.indexOf(normalizedQuery, index);
      if (matchIndex == -1) break;

      final contextStart = (matchIndex - 30).clamp(0, text.length);
      final contextEnd = (matchIndex + query.length + 30).clamp(0, text.length);

      matches.add(
        SearchMatch(
          text: text.substring(contextStart, contextEnd),
          startIndex: matchIndex - contextStart,
          endIndex: matchIndex - contextStart + query.length,
          type: type,
        ),
      );

      index = matchIndex + 1;

      if (matches.length >= 5) break;
    }

    return matches;
  }

  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  Future<void> _addToRecentSearches(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _recentSearches.remove(trimmed);
    _recentSearches.insert(0, trimmed);

    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
    }

    await _saveRecentSearches();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches.clear();
    await _saveRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final searchesString = prefs.getString(_recentSearchesKey);

    if (searchesString != null) {
      final List<dynamic> decoded = jsonDecode(searchesString);
      _recentSearches = decoded.cast<String>();
    }
  }

  Future<void> _saveRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentSearchesKey, jsonEncode(_recentSearches));
  }

  void dispose() {
    _searchIndex.clear();
  }
}
