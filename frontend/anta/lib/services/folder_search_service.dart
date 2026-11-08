import 'dart:async';

import 'package:anta/constants/search_constants.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../database/database.dart';
import '../models/item_label.dart';
import '../models/note_change.dart';
import '../models/note_metadata.dart';
import '../utils/markdown_tag_syntax.dart';
import '../utils/tag_extractor.dart';
import 'body_search_indexer.dart';
import 'note_storage_service.dart';

/// [SearchConstants.diacriticsMap] keyed by UTF-16 code unit instead of
/// one-character `String`, derived (never hand-transcribed: an isolate-local
/// copy once drifted from it — no Romanian entries — and the notes it
/// indexed never matched a query) from the canonical map so the two can
/// never disagree.
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

/// A run of two or more Unicode letters, digits or underscores. Unicode, not
/// `\w`, so Cyrillic, Greek and CJK words are words too (D6 Q4); maximal
/// runs need no `\b`, which stays ASCII-only even in Unicode mode.
final RegExp _searchTokenRegex = RegExp(r'[\p{L}\p{N}_]{2,}', unicode: true);

/// Every word occurrence of [text] as the body index stores and looks words
/// up: folded through [normalizeForSearch], split into runs of letters and
/// digits, minimum two characters. **Duplicates preserved** — the scorer
/// counts them as term frequency, so a note mentioning "squat" five times
/// outranks one that mentions it once.
///
/// The single tokenizer for the projection, the query and the scorer, so
/// the three can never fold differently.
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

/// Whether a query [word] may match anywhere inside a word of the note, not
/// only at its start: three characters or more, counted in code points as
/// the trigram index counts them.
bool _matchesInsideWords(String word) => word.runes.length >= 3;

/// What the body index stores for a note: the [searchTokens] of its title
/// and body, each preceded and followed by one space. A query word of three
/// or more characters, which holds no space, can then only match inside one
/// token; a two-character word, sent with its leading space, only at a
/// token's start — the rules [searchScore] decides a hit by.
String searchProjection(String title, String body) =>
    ' ${searchTokens('$title $body').join(' ')} ';

/// What the body index's `title` column stores: the title's [searchTokens]
/// alone, spaced as [searchProjection] spaces them, so the quick search can
/// weigh a title hit above a body hit and match a short word at a title
/// token's start.
String titleProjection(String title) => ' ${searchTokens(title).join(' ')} ';

/// What the body index's `tags` column stores: the `#tags` [body] carries
/// under the editor's own grammar ([extractTags], uncached: every text is
/// read once here), folded through [normalizeForSearch], each written with
/// its `#` and followed by one space. A tag is then matched whole between
/// `" #"` and a space, or by a prefix after `" #"` — three characters even
/// for a one-letter prefix, which a trigram needs — and never inside a
/// longer tag.
String tagProjection(String body) {
  final tags = {
    for (final tag in extractTags(body, cache: false)) normalizeForSearch(tag),
  };
  return tags.isEmpty
      ? ' '
      : ' ${[for (final tag in tags) '#$tag'].join(' ')} ';
}

/// The FTS5 clauses requiring every tag in [tags] (folded, without `#`) in
/// the `tags` column: [whole] for the full search, which names the tag
/// exactly, and otherwise as a prefix, so `#l`, `#le` and `#leg` already
/// narrow while `#legday` is being typed. Empty when [tags] is.
String tagMatchExpression(Iterable<String> tags, {required bool whole}) => [
  for (final tag in tags) whole ? 'tags : " #$tag "' : 'tags : " #$tag"',
].join(' AND ');

/// The FTS5 expression that finds the projections holding every one of
/// [words]: each a quoted phrase, AND-ed, a two-character word with the
/// leading space that pins it to a token's start. Words come from
/// [searchTokens] — letters, digits and underscores — so nothing in them
/// needs escaping. Confined to the `body` column, the projection this
/// search was built on, so the quick search's columns change nothing here.
String bodyMatchExpression(Iterable<String> words) => [
  for (final word in words)
    _matchesInsideWords(word) ? 'body : "$word"' : 'body : " $word"',
].join(' AND ');

/// The FTS5 expression behind a quick search: every word of three or more
/// characters anywhere in the title or the body; a shorter word only at the
/// start of a title token, since a trigram cannot hold it alone and a body
/// token's start is too broad to be worth a hit while typing; and every tag
/// in [tags] (folded, without `#`) by prefix. Empty when there is nothing
/// to match. [QuickQuery] holds the same rules in Dart.
String quickMatchExpression(Iterable<String> words, Iterable<String> tags) => [
  for (final word in words)
    _matchesInsideWords(word) ? '{title body} : "$word"' : 'title : " $word"',
  if (tags.isNotEmpty) tagMatchExpression(tags, whole: false),
].join(' AND ');

/// [quickMatchExpression] with every word confined to the `title` column:
/// the title hits, which the quick search reads apart so the cut never
/// drops one. Empty when [words] is — a tag alone names no title.
String quickTitleExpression(Iterable<String> words, Iterable<String> tags) {
  if (words.isEmpty) return '';
  return [
    for (final word in words)
      _matchesInsideWords(word) ? 'title : "$word"' : 'title : " $word"',
    if (tags.isNotEmpty) tagMatchExpression(tags, whole: false),
  ].join(' AND ');
}

/// A query as the quick search reads it: the [words] of the text around
/// its `#tags`, and the [tags], folded, without `#`. Holds in Dart the
/// rules [quickMatchExpression] gives the index — the one matcher the
/// title-first grouping and the newest-notes scan both use, so neither can
/// judge a note otherwise than the index does.
class QuickQuery {
  final Set<String> words;
  final Set<String> tags;

  const QuickQuery._(this.words, this.tags);

  factory QuickQuery.parse(String query) {
    final (:tags, :rest) = splitQueryTags(query);
    return QuickQuery._(tokenizeForSearch(rest), tags);
  }

  /// Nothing to search for: no word of two characters or more, no tag.
  bool get isEmpty => words.isEmpty && tags.isEmpty;

  String get titleMatch => quickTitleExpression(words, tags);

  String get match => quickMatchExpression(words, tags);

  /// A title hit: every word matches a token of [title] — at its start for
  /// a two-character word, anywhere inside it for a longer one. False for
  /// a query of tags alone.
  bool titleHolds(String title) {
    if (words.isEmpty) return false;
    final titleTokens = searchTokens(title);
    return words.every((word) => _tokenHolds(titleTokens, word));
  }

  /// Whether a note showing [title] and [preview] is a hit: every word in a
  /// title token, or — three characters or more — inside a preview token,
  /// and every tag carried by the preview, by prefix.
  bool holds(String title, String preview) {
    if (isEmpty) return false;
    if (tags.isNotEmpty) {
      final carried = tagProjection(preview);
      if (!tags.every((tag) => carried.contains(' #$tag'))) return false;
    }
    final titleTokens = searchTokens(title);
    final previewTokens = words.any(_matchesInsideWords)
        ? searchTokens(preview)
        : const <String>[];
    return words.every(
      (word) =>
          _tokenHolds(titleTokens, word) ||
          (_matchesInsideWords(word) && _tokenHolds(previewTokens, word)),
    );
  }

  static bool _tokenHolds(List<String> tokens, String word) {
    final inside = _matchesInsideWords(word);
    return tokens.any(
      (token) => inside ? token.contains(word) : token.startsWith(word),
    );
  }
}

/// [query] cut into the `#tags` it names — folded, without `#` — and the
/// text around them, read with the editor's tag grammar so a query tag is
/// exactly what a note's tag is.
({Set<String> tags, String rest}) splitQueryTags(String query) {
  if (!query.contains('#')) return (tags: const {}, rest: query);
  final tags = <String>{};
  final rest = StringBuffer();
  var i = 0;
  while (i < query.length) {
    final unit = query.codeUnitAt(i);
    if (unit == 0x23 && MarkdownTagSyntax.isWordBoundaryBefore(query, i)) {
      final end = MarkdownTagSyntax.tryParseTagAt(query, i);
      if (end != null) {
        tags.add(normalizeForSearch(query.substring(i + 1, end)));
        rest.write(' ');
        i = end;
        continue;
      }
    }
    rest.writeCharCode(unit);
    i++;
  }
  return (tags: tags, rest: rest.toString());
}

/// The relevance of a note to the query [words], or null when it is not a
/// hit. A hit has, for every word, a token starting with it or, for a word
/// of three or more characters, containing it. Each word scores twice its
/// count as a whole token, or else the count of the first token (in reading
/// order) that contains it — the rules of the in-memory index this replaced,
/// which the five search suites pin.
double? searchScore(String title, String body, Set<String> words) {
  if (words.isEmpty) return null;
  final terms = <String, int>{};
  for (final token in searchTokens('$title $body')) {
    terms[token] = (terms[token] ?? 0) + 1;
  }

  var score = 0.0;
  for (final word in words) {
    final whole = terms[word];
    if (whole != null) {
      score += whole * 2.0;
      continue;
    }
    final inside = _matchesInsideWords(word);
    int? firstContaining;
    var hit = false;
    for (final entry in terms.entries) {
      final contains = entry.key.contains(word);
      if (contains) firstContaining ??= entry.value;
      if (entry.key.startsWith(word) || (inside && contains)) {
        hit = true;
        break;
      }
    }
    if (!hit) return null;
    score += firstContaining!;
  }
  return score;
}

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

  /// The colour labels a note may carry to survive the filter, OR-ed
  /// together. **Empty is no filter at all** — unlike [folderIds], where the
  /// empty set is a scope that matches nothing: a label filter is built by
  /// tapping chips, and having tapped none means "every colour, and none".
  final Set<ItemLabel> labels;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int? minContentLength;
  final int? maxContentLength;
  final bool caseSensitive;

  const SearchFilter({
    this.folderIds,
    this.labels = const {},
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

    if (labels.isNotEmpty && !labels.contains(metadata.label)) {
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

class FolderSearchService {
  static const int _quickSearchPageSize = 300;

  /// How many hits a per-keystroke pass shows. Declared here rather than as a
  /// bare default on [quickSearch] so the bloc that calls it can name the
  /// same number instead of keeping a copy that could drift from it.
  static const int quickHitLimit = 10;

  final NoteStorageService _storageService;
  final Future<BodySearchIndexer> Function() _indexerForActiveDatabase;
  final Duration _indexBudget;

  StreamSubscription<NoteChange>? _changesSubscription;

  bool _isInitialized = false;

  /// A failed read of the body index by a keystroke was logged, and no read
  /// has succeeded since.
  bool _quickIndexFailureLogged = false;

  /// [indexer] resolves the body index of the active database —
  /// [BodySearchIndexer.getInstance] in the app, a test's own instance in a
  /// suite. [indexBudget] is how long a full search waits for a running
  /// drain before it answers from what is indexed.
  FolderSearchService({
    required NoteStorageService storageService,
    Future<BodySearchIndexer> Function()? indexer,
    Duration indexBudget = SearchConstants.bodyIndexSearchBudget,
  }) : _storageService = storageService,
       _indexerForActiveDatabase = indexer ?? BodySearchIndexer.getInstance,
       _indexBudget = indexBudget {
    _changesSubscription = _storageService.changes.listen(_onNoteChanged);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  /// Completes once the active database's body index has caught up — the
  /// moment a search that came back incomplete is worth running again.
  Future<void> whenIndexed() async =>
      (await _indexerForActiveDatabase()).whenIdle();

  /// Every write — an editor save, a restore, an import, a sync pull —
  /// reaches the index as a flag on the active indexer and nothing more; the
  /// next search probes the ledger regardless, so a change that reached no
  /// indexer is still found, and a save does no indexing work.
  void _onNoteChanged(NoteChange change) => BodySearchIndexer.markActiveDirty();

  /// Starts the body index catching up when notes moved since it last did,
  /// without waiting — the search surface calls it as it opens, so the
  /// drain runs while the user starts typing and no keystroke starts one.
  Future<void> catchUpIndex() async =>
      (await _indexerForActiveDatabase()).catchUp();

  /// Brings the body index up to date and waits for it.
  Future<void> buildIndex() async {
    await initialize();
    await (await _indexerForActiveDatabase()).drain();
  }

  /// [searchWithCoverage]'s results alone.
  Future<List<SearchResult>> search(
    String query, {
    SearchFilter? filter,
    int limit = 50,
    bool caseSensitive = false,
  }) async => (await searchWithCoverage(
    query,
    filter: filter,
    limit: limit,
    caseSensitive: caseSensitive,
  )).results;

  /// Every note whose title and body hold all the query's words, best first,
  /// and whether the body index was still being filled when the candidates
  /// were read — so some notes may be missing — decided at that moment
  /// rather than after the scoring, which a broad query makes long.
  ///
  /// The body index narrows the notes to the candidates in one statement,
  /// with the folder and colour filters in SQL; their bodies are then read a
  /// page at a time and scored in Dart by [searchScore], which also confirms
  /// each hit, so a note edited since it was indexed is never a false hit.
  /// Only the notes that survive the cut to [limit] are read again for their
  /// match offsets. While the index is still being filled the search waits
  /// [_indexBudget] at most, then answers from what is indexed.
  ///
  /// A `#tag` in the query narrows to the notes carrying that whole tag —
  /// `#legday` never finds `#legdays` — while its name still counts as a
  /// word, so a tag tap and Enter list what typing it listed.
  Future<({List<SearchResult> results, bool incomplete})> searchWithCoverage(
    String query, {
    SearchFilter? filter,
    int limit = 50,
    bool caseSensitive = false,
  }) async {
    await initialize();

    const nothing = (results: <SearchResult>[], incomplete: false);
    if (query.trim().isEmpty) return nothing;
    final words = tokenizeForSearch(query);
    final tags = splitQueryTags(query).tags;
    if (words.isEmpty && tags.isEmpty) return nothing;
    final folderIds = filter?.folderIds;
    if (folderIds != null && folderIds.isEmpty) return nothing;

    final indexer = await _indexerForActiveDatabase();
    final incomplete = !await indexer.ensureFresh(_indexBudget);
    final candidates = await indexer.candidates(
      words,
      tags: tags,
      folderIds: folderIds,
      labels: filter?.labels ?? const {},
    );

    final eligible = <NoteMetadata>[
      for (final note in candidates)
        if (_metadataOf(note) case final metadata
            when filter == null || filter.matches(metadata))
          metadata,
    ];

    final ranked = <({NoteMetadata metadata, double score})>[];
    for (final page in pagesByBytes(
      eligible,
      (metadata) => metadata.contentLength,
      SearchConstants.bodyScoringPageBytes,
      maxItems: SearchConstants.bodyPageMaxNotes,
    )) {
      final bodies = await indexer.bodies([for (final m in page) m.id]);
      final scores = await _scorePage(
        indexer,
        [for (final m in page) (m.title, bodies[m.id] ?? '')],
        words,
        tags,
      );
      for (final (i, metadata) in page.indexed) {
        final score = scores[i];
        if (score != null) ranked.add((metadata: metadata, score: score));
      }
    }

    ranked.sort(_byRelevance);

    final effectiveCaseSensitive = filter?.caseSensitive ?? caseSensitive;
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

    return (
      results: (await Future.wait(futures)).toList(),
      incomplete: incomplete,
    );
  }

  /// [quickSearchWithCoverage]'s results alone.
  Future<List<SearchResult>> quickSearch(
    String query, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
    int limit = quickHitLimit,
    bool caseSensitive = false,
  }) async => (await quickSearchWithCoverage(
    query,
    folderIds: folderIds,
    labels: labels,
    limit: limit,
    caseSensitive: caseSensitive,
  )).results;

  /// The per-keystroke hits (D6): every note whose title and body hold all
  /// the query's words, from the body index, merged with a title-and-preview
  /// scan of the [_quickSearchPageSize] newest notes, which finds a note the
  /// index has not projected yet. [folderIds] is a whole subtree (see
  /// [SearchFilter.folderIds]); `null` searches everywhere.
  ///
  /// Three statements per keystroke and no body read: a title-only `MATCH`
  /// and a title-and-body `MATCH`, each ranked by `bm25()` and cut to
  /// [limit] in SQL, and the newest page (whose count the repository
  /// keeps). FTS5's bm25 folds a column's weight into one saturating term
  /// count per row, so a body repeating a word can outscore a title naming
  /// it once; reading the title hits apart keeps every one inside the cut.
  /// [QuickQuery] decides in Dart what the index decides in SQL — a word
  /// under three characters matches a title token's start only, words are
  /// AND-ed, a `#tag` narrows by prefix — for the scan and for the grouping:
  /// title hits first, each group in the index's order with the scan's extra
  /// finds after it, newest first.
  ///
  /// Never waits for the index and never starts a drain — the surface kicks
  /// one when it opens ([catchUpIndex]): while the index may be behind, or
  /// could not be read, the answer says [incomplete], so a later keystroke
  /// may find more. The index is folded and case-blind, and so is the scan;
  /// [caseSensitive] applies to the highlighted offsets only.
  ///
  /// [labels] is the colour filter, OR-ed across the set and empty for no
  /// filter. It **narrows** a typed query and never stands in for one: an
  /// empty query finds nothing here whatever the filter says, because
  /// "everything red" is a listing rather than a search and [labelledNotes]
  /// answers it out of SQLite instead of out of one page.
  Future<({List<SearchResult> results, bool incomplete})>
  quickSearchWithCoverage(
    String query, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
    int limit = quickHitLimit,
    bool caseSensitive = false,
  }) async {
    await initialize();

    const nothing = (results: <SearchResult>[], incomplete: false);
    if (query.trim().isEmpty) return nothing;
    if (folderIds != null && folderIds.isEmpty) return nothing;

    final quick = QuickQuery.parse(query);
    if (quick.isEmpty) return nothing;

    final indexer = await _indexerForActiveDatabase();
    final behind = indexer.mayBeBehind;
    final (indexed, recent) = await (
      _readQuickIndex(indexer, quick, folderIds, labels, limit),
      _storageService.loadNotesPaginated(pageSize: _quickSearchPageSize),
    ).wait;

    final candidates = <SearchResult>[];
    final seen = <String>{};
    for (final (:note, :score) in indexed.hits) {
      final metadata = _metadataOf(note);
      seen.add(metadata.id);
      candidates.add(
        SearchResult(
          metadata: metadata,
          matches: _rowMatches(query, metadata, caseSensitive),
          // bm25 is better the lower it is.
          relevanceScore: -score,
        ),
      );
    }
    candidates.addAll(
      _scanRecent(
        recent.notes,
        query: query,
        quick: quick,
        seen: seen,
        folderIds: folderIds,
        labels: labels,
        caseSensitive: caseSensitive,
      ),
    );

    final titleHits = <SearchResult>[];
    final otherHits = <SearchResult>[];
    for (final hit in candidates) {
      (quick.titleHolds(hit.metadata.title) ? titleHits : otherHits).add(hit);
    }
    return (
      results: [...titleHits, ...otherHits].take(limit).toList(),
      incomplete: switch (indexed.state) {
        _QuickIndexRead.read => behind,
        // The scan is all there is, and nothing more will come.
        _QuickIndexRead.absent => false,
        // The scan answered alone this time.
        _QuickIndexRead.failed => true,
      },
    );
  }

  /// The index's quick hits for [quick], and whether it was read, has no
  /// index on this database, or threw — a transient failure the scan
  /// answers around, logged once until a read succeeds again so a run of
  /// keystrokes does not flood the log.
  Future<({List<({Note note, double score})> hits, _QuickIndexRead state})>
  _readQuickIndex(
    BodySearchIndexer indexer,
    QuickQuery quick,
    Set<String>? folderIds,
    Set<ItemLabel> labels,
    int limit,
  ) async {
    try {
      final hits = await indexer.quickMatches(
        quick.titleMatch,
        quick.match,
        folderIds: folderIds,
        labels: labels,
        limit: limit,
      );
      _quickIndexFailureLogged = false;
      return hits == null
          ? (hits: _noQuickHits, state: _QuickIndexRead.absent)
          : (hits: hits, state: _QuickIndexRead.read);
    } catch (e) {
      if (!_quickIndexFailureLogged) {
        _quickIndexFailureLogged = true;
        debugPrint('[FolderSearchService] quick index read failed: $e');
      }
      return (hits: _noQuickHits, state: _QuickIndexRead.failed);
    }
  }

  /// The quick rule ([QuickQuery.holds]) over the newest page, newest first,
  /// skipping the notes in [seen]. Kept beside the index so a note it has
  /// not projected yet is still found while typing.
  List<SearchResult> _scanRecent(
    List<NoteMetadata> notes, {
    required String query,
    required QuickQuery quick,
    required Set<String> seen,
    required Set<String>? folderIds,
    required Set<ItemLabel> labels,
    required bool caseSensitive,
  }) {
    final results = <SearchResult>[];
    for (final metadata in notes) {
      if (seen.contains(metadata.id)) continue;
      if (folderIds != null && !folderIds.contains(metadata.folderId)) {
        continue;
      }
      if (labels.isNotEmpty && !labels.contains(metadata.label)) {
        continue;
      }
      if (!quick.holds(metadata.title, metadata.preview)) continue;
      results.add(
        SearchResult(
          metadata: metadata,
          matches: _rowMatches(query, metadata, caseSensitive),
          relevanceScore: 0,
        ),
      );
    }
    return results;
  }

  /// What a quick hit's row paints: [query] in the title, then in the
  /// preview — the only body text a quick hit has in hand.
  List<SearchMatch> _rowMatches(
    String query,
    NoteMetadata metadata,
    bool caseSensitive,
  ) => [
    ..._findMatchesInText(
      query,
      metadata.title,
      SearchMatchType.title,
      caseSensitive: caseSensitive,
    ),
    ..._findMatchesInText(
      query,
      metadata.preview,
      SearchMatchType.content,
      caseSensitive: caseSensitive,
    ),
  ];

  /// Every note wearing one of [labels], newest first, as search results with
  /// nothing highlighted — the listing a colour chip produces with the field
  /// empty, and the total the header above it counts.
  ///
  /// Not a [quickSearch] with an empty query: nothing is being searched for,
  /// so there is no text to score, no offsets to paint, and no reason to read
  /// a page of notes the colour was never going to keep. The colour is a
  /// `WHERE` clause here, which is what lets [limit] mean "rows shown" and
  /// lets a red note older than the newest few hundred still be listed.
  ///
  /// [folderIds] is a whole subtree; an empty set matches nothing. An empty
  /// [labels] returns nothing, the way [quickSearch] with an empty query
  /// does — with no colour picked there is no listing to make.
  Future<({List<SearchResult> results, int total})> labelledNotes({
    required Set<ItemLabel> labels,
    Set<String>? folderIds,
    int limit = 50,
  }) async {
    await initialize();

    if (labels.isEmpty) return (results: const <SearchResult>[], total: 0);
    if (folderIds != null && folderIds.isEmpty) {
      return (results: const <SearchResult>[], total: 0);
    }

    final listing = await _storageService.labelledNotes(
      labels: labels,
      folderIds: folderIds,
      limit: limit,
    );

    return (
      results: [
        for (final metadata in listing.notes)
          SearchResult(
            metadata: metadata,
            matches: const [],
            relevanceScore: 0,
          ),
      ],
      total: listing.total,
    );
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

  Future<void> close() async {
    await _changesSubscription?.cancel();
    _changesSubscription = null;
  }

  /// Best score first; equal scores newest first, then by id, so a page of
  /// ties reads the same on every run.
  static int _byRelevance(
    ({NoteMetadata metadata, double score}) a,
    ({NoteMetadata metadata, double score}) b,
  ) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byDate = b.metadata.updatedAt.compareTo(a.metadata.updatedAt);
    if (byDate != 0) return byDate;
    return a.metadata.id.compareTo(b.metadata.id);
  }

  static NoteMetadata _metadataOf(Note note) => NoteMetadata(
    id: note.id,
    folderId: note.folderId,
    title: note.title,
    preview: note.preview,
    contentLength: note.contentLength,
    chunkCount: note.chunkCount,
    isCompressed: note.isCompressed,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    position: note.position,
    label: ItemLabel.fromStorage(note.label),
  );
}

const List<({Note note, double score})> _noQuickHits = [];

/// What became of a keystroke's read of the body index.
enum _QuickIndexRead { read, absent, failed }

/// [searchScore] of each note, null as well where the body does not carry
/// every one of [tags] whole; a query of tags alone scores each carrier 0.
List<double?> _scoreAll(
  List<(String, String)> notes,
  Set<String> words,
  Set<String> tags,
) => [
  for (final (title, body) in notes)
    if (tags.isNotEmpty && !_carriesWhole(body, tags))
      null
    else if (words.isEmpty)
      0.0
    else
      searchScore(title, body, words),
];

bool _carriesWhole(String body, Set<String> tags) {
  final carried = tagProjection(body);
  return tags.every((tag) => carried.contains(' #$tag '));
}

/// Top-level so the closure handed to an isolate captures the page, the
/// words and the tags alone, never the service.
Future<List<double?>> _scorePage(
  BodySearchIndexer indexer,
  List<(String, String)> notes,
  Set<String> words,
  Set<String> tags,
) {
  var bytes = 0;
  for (final (title, body) in notes) {
    bytes += title.length + body.length;
  }
  return indexer.offIsolate(bytes, () => _scoreAll(notes, words, tags));
}
