import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:anta/constants/search_constants.dart';
import '../models/isolate_data.dart';
import '../models/note_change.dart';
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

/// [SearchConstants.diacriticsMap] keyed by UTF-16 code unit instead of
/// one-character `String`, derived (never hand-transcribed — see the comment
/// on [_buildIndexInIsolate] for what a second, drifted table costs) from the
/// canonical map so the two can never disagree.
final Map<int, String> _diacriticsByCodeUnit = {
  for (final entry in SearchConstants.diacriticsMap.entries)
    entry.key.codeUnitAt(0): entry.value,
};

/// Folds every code unit >= U+00C0 that appears in [SearchConstants.diacriticsMap]
/// to its plain-ASCII form (`'ß' -> 'ss'`, `'Æ' -> 'AE'`, ...), unchanged
/// otherwise.
///
/// Iterates `codeUnits`, not one-character substrings: `String.write` per
/// character allocated a throwaway String per code unit for a map lookup that
/// almost always misses (plain text has none of these). Every key in the map
/// is a single code unit in U+00C0..U+017E plus the Romanian comma-below
/// block U+0218-U+021B, so code units <= 0xBF skip the lookup entirely and go
/// straight to the buffer.
///
/// Surrogate pairs (emoji, astral-plane text) are two code units each in
/// U+D800..U+DFFF — outside every map key's range — so neither half matches
/// and both round-trip unchanged, exactly like the old per-`String` version
/// (which likewise never combined a pair into one rune before lookup).
String removeDiacritics(String text) {
  StringBuffer? buffer;

  for (int i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final replacement = unit <= 0xBF ? null : _diacriticsByCodeUnit[unit];

    if (replacement == null) {
      // No fold needed: only write to the buffer once one exists (i.e.
      // once an earlier code unit already folded), otherwise skip work
      // entirely for the common plain-text case.
      buffer?.writeCharCode(unit);
      continue;
    }

    // First actual fold: only now is a buffer worth allocating. Back-fill
    // everything seen so far unchanged, then write the replacement.
    buffer ??= StringBuffer()..write(text.substring(0, i));
    buffer.write(replacement);
  }

  return buffer?.toString() ?? text;
}

String normalizeForSearch(String text, {bool caseSensitive = false}) {
  String normalized = removeDiacritics(text);
  if (!caseSensitive) {
    normalized = normalized.toLowerCase();
  }
  return normalized;
}

/// [normalizeForSearch]'s output together with the map back to the text it
/// came from.
///
/// Neither half of the normalisation is length-preserving — `ß` folds to two
/// characters, and lowercasing `İ` yields two — so an offset found in the
/// normalised string is not an offset into the raw one. Highlighting used to
/// apply the normalised offsets to the raw text directly, which slid the
/// highlight by one character per fold that had grown before it.
class NormalizedText {
  final String value;

  /// Raw index for each normalised index, with one extra entry at the end so
  /// a match's end offset maps too. Null when the two are one-to-one, which
  /// is every string that folds to its own length.
  final List<int>? _rawIndex;

  const NormalizedText._(this.value, this._rawIndex);

  factory NormalizedText.of(String text, {bool caseSensitive = false}) {
    final normalized = normalizeForSearch(text, caseSensitive: caseSensitive);
    if (normalized.length == text.length) {
      return NormalizedText._(normalized, null);
    }

    final buffer = StringBuffer();
    final rawIndex = <int>[];
    var rawOffset = 0;
    for (final rune in text.runes) {
      final folded = normalizeForSearch(
        String.fromCharCode(rune),
        caseSensitive: caseSensitive,
      );
      buffer.write(folded);
      for (var i = 0; i < folded.length; i++) {
        rawIndex.add(rawOffset);
      }
      rawOffset += rune > 0xFFFF ? 2 : 1;
    }
    rawIndex.add(text.length);
    return NormalizedText._(buffer.toString(), rawIndex);
  }

  /// The raw offset [index] in [value] came from.
  int rawIndexOf(int index) {
    final map = _rawIndex;
    if (map == null) return index;
    if (index >= map.length) return map.isEmpty ? 0 : map.last;
    return map[index];
  }
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
  /// The folder subtree a search is confined to: the scoped folder's id plus
  /// every descendant, as [FolderStorageService.subtreeIds] builds it. `null`
  /// searches everywhere; an **empty** set matches nothing, which is what a
  /// scope pointing at a folder that has since been deleted must do.
  final Set<String>? folderIds;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int? minContentLength;
  final int? maxContentLength;
  final bool caseSensitive;

  const SearchFilter({
    this.folderIds,
    this.fromDate,
    this.toDate,
    this.minContentLength,
    this.maxContentLength,
    this.caseSensitive = false,
  });

  bool matches(NoteMetadata metadata) {
    if (folderIds != null && !folderIds!.contains(metadata.folderId)) {
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
  static const int _quickSearchPageSize = 300;

  /// One page of the index build, looped until the last page comes back
  /// short. It used to be the whole build: a database with more notes than
  /// this indexed the first page and silently answered every later note's
  /// text with "no results".
  static const int _indexPageSize = 1000;

  /// Past this many notes changed behind the index's back, refreshing them
  /// one at a time costs more than rebuilding from scratch — which is what a
  /// backup restore or a sync pull looks like from here.
  static const int _staleRebuildThreshold = 200;

  final NoteStorageService _storageService;
  final SearchIndex _searchIndex = SearchIndex();

  /// Notes written since the index last saw them. The bloc reports its own
  /// writes through [updateIndex], but a restore, an import and a sync pull
  /// all reach storage without passing a bloc, so the note stream is what
  /// makes the index answer for those too.
  final Set<String> _staleNoteIds = {};

  StreamSubscription<NoteChange>? _changesSubscription;

  bool _isInitialized = false;
  bool _isIndexing = false;

  FolderSearchService({required NoteStorageService storageService})
    : _storageService = storageService {
    _changesSubscription = _storageService.changes.listen(_onNoteChanged);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  void _onNoteChanged(NoteChange change) {
    if (!_searchIndex.isBuilt) return;
    switch (change.type) {
      case NoteChangeType.deleted:
        _searchIndex.removeNote(change.noteId);
        _staleNoteIds.remove(change.noteId);
      case NoteChangeType.moved:
      case NoteChangeType.labelled:
        break;
      case NoteChangeType.created:
      case NoteChangeType.updated:
        _staleNoteIds.add(change.noteId);
    }
  }

  /// Brings the notes the index has been told about back up to date, or
  /// rebuilds outright when there are too many of them to be worth it.
  Future<void> _refreshStaleNotes() async {
    if (_staleNoteIds.isEmpty) return;
    final ids = _staleNoteIds.toList(growable: false);
    _staleNoteIds.clear();

    if (ids.length >= _staleRebuildThreshold) {
      await buildIndex();
      return;
    }

    for (final noteId in ids) {
      final metadata = await _storageService.getNoteMetadata(noteId);
      _searchIndex.removeNote(noteId);
      if (metadata == null) continue;
      final content = await _storageService.loadNoteContent(noteId);
      _searchIndex.addNote(noteId, metadata.title, content);
    }
  }

  /// Every live note's metadata, page by page.
  Future<List<NoteMetadata>> _loadAllNoteMetadata() async {
    final all = <NoteMetadata>[];
    var page = 1;
    while (true) {
      final result = await _storageService.loadNotesPaginated(
        page: page,
        pageSize: _indexPageSize,
      );
      all.addAll(result.notes);
      if (!result.hasMore || result.notes.isEmpty) break;
      page++;
    }
    return all;
  }

  /// Build search index using isolate for heavy processing
  Future<void> buildIndex() async {
    if (_isIndexing) return; // Prevent concurrent indexing

    await initialize();
    _isIndexing = true;

    try {
      _searchIndex.clear();
      _staleNoteIds.clear();

      final allNotes = await _loadAllNoteMetadata();

      final notesData = <NoteIndexData>[];
      for (final metadata in allNotes) {
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
    _staleNoteIds.remove(noteId);
  }

  Future<void> removeFromIndex(String noteId) async {
    await initialize();
    _searchIndex.removeNote(noteId);
    _staleNoteIds.remove(noteId);
  }

  Future<List<SearchResult>> search(
    String query, {
    SearchFilter? filter,
    int limit = 50,
    bool caseSensitive = false,
  }) async {
    await initialize();

    if (query.trim().isEmpty) return [];

    if (!_searchIndex.isBuilt) {
      await buildIndex();
    } else {
      await _refreshStaleNotes();
    }

    final effectiveCaseSensitive = filter?.caseSensitive ?? caseSensitive;
    final matchingIds = _searchIndex.search(
      query,
      caseSensitive: effectiveCaseSensitive,
    );

    if (matchingIds.isEmpty) return [];

    // Load all notes ONCE, not inside the loop
    final allNotes = await _loadAllNoteMetadata();

    // Create a lookup map for O(1) access
    final notesMap = {for (final n in allNotes) n.id: n};

    // Rank before loading anything. The relevance score comes off the index,
    // so the whole hit set can be ordered and cut to [limit] without touching
    // storage; only the notes that survive the cut pay for a content read. A
    // 60-hit query used to load 60 note bodies to show ten.
    final ranked = <({NoteMetadata metadata, double score})>[];
    for (final noteId in matchingIds) {
      final metadata = notesMap[noteId];
      if (metadata == null) continue;
      if (filter != null && !filter.matches(metadata)) continue;

      ranked.add((
        metadata: metadata,
        score: _searchIndex.getRelevanceScore(
          noteId,
          query,
          caseSensitive: effectiveCaseSensitive,
        ),
      ));
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));

    final futures = ranked.take(limit).map((entry) async {
      final content = await _storageService.loadNoteContent(entry.metadata.id);
      final matches = _findMatches(
        query,
        entry.metadata.title,
        content,
        caseSensitive: effectiveCaseSensitive,
      );

      return SearchResult(
        metadata: entry.metadata,
        matches: matches,
        relevanceScore: entry.score,
      );
    });

    return (await Future.wait(futures)).toList();
  }

  /// Title-and-preview pass over one page of notes, for the per-keystroke
  /// surface. [folderIds] is a whole subtree (see [SearchFilter.folderIds]);
  /// `null` searches everywhere.
  ///
  /// The page is always read unscoped and filtered in memory: the DAO can
  /// page by one folder id, not by a set, and the scoped folder's notes are
  /// spread across its descendants. [_quickSearchPageSize] is the ceiling
  /// that keeps this honest for v1.
  Future<List<SearchResult>> quickSearch(
    String query, {
    Set<String>? folderIds,
    int limit = 10,
    bool caseSensitive = false,
  }) async {
    await initialize();

    if (query.trim().isEmpty) return [];
    if (folderIds != null && folderIds.isEmpty) return [];

    final paginatedNotes = await _storageService.loadNotesPaginated(
      pageSize: _quickSearchPageSize,
    );

    final normalizedQuery = normalizeForSearch(
      query,
      caseSensitive: caseSensitive,
    );
    final results = <SearchResult>[];

    for (final metadata in paginatedNotes.notes) {
      if (folderIds != null && !folderIds.contains(metadata.folderId)) {
        continue;
      }

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
    if (normalizedQuery.isEmpty) return matches;
    final normalized = NormalizedText.of(text, caseSensitive: caseSensitive);
    final normalizedText = normalized.value;

    int index = 0;
    while (true) {
      final matchIndex = normalizedText.indexOf(normalizedQuery, index);
      if (matchIndex == -1) break;

      // Both ends come back through the map, so the snippet's offsets address
      // the raw text the row actually paints — never the folded one they were
      // found in, and never `query.length`, which is the length of what was
      // typed rather than of what matched.
      final rawStart = normalized.rawIndexOf(matchIndex);
      final rawEnd = normalized.rawIndexOf(matchIndex + normalizedQuery.length);
      final contextStart = (rawStart - 30).clamp(0, text.length);
      final contextEnd = (rawEnd + 30).clamp(0, text.length);

      matches.add(
        SearchMatch(
          text: text.substring(contextStart, contextEnd),
          startIndex: rawStart - contextStart,
          endIndex: rawEnd - contextStart,
          type: type,
        ),
      );

      index = matchIndex + 1;

      if (matches.length >= 5) break;
    }

    return matches;
  }

  /// Drops the index, so the next search rebuilds it.
  ///
  /// The note subscription deliberately outlives this: the service is an
  /// app-wide singleton and `OptimizedNoteBloc` is a factory, so one page
  /// closing its bloc must not leave the index unable to notice writes for
  /// the rest of the session.
  void dispose() {
    _searchIndex.clear();
    _staleNoteIds.clear();
  }

  Future<void> close() async {
    await _changesSubscription?.cancel();
    _changesSubscription = null;
    dispose();
  }
}
