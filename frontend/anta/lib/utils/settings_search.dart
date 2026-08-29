import 'package:flutter/services.dart' show TextRange;

import '../constants/search_constants.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;

/// Folded text paired with a map back to the source offsets.
///
/// [normalizeForSearch] is **not** length preserving — `SearchConstants`
/// maps `ß` to `ss`, `æ` to `ae`, `Þ` to `TH` — so a span located in folded
/// text lands on the wrong characters if applied to the source directly.
/// [sourceIndex] records which source index produced each folded code unit,
/// so `ß` contributes its own index twice and highlights stay aligned.
///
/// This is the shared fold plus bookkeeping, never a second diacritics
/// table: the mapping is read from [SearchConstants.diacriticsMap] and the
/// result is asserted to equal [normalizeForSearch].
class FoldedText {
  final String value;
  final List<int> sourceIndex;

  const FoldedText._(this.value, this.sourceIndex);

  factory FoldedText.of(String source) {
    final buffer = StringBuffer();
    final indices = <int>[];
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      final folded = (SearchConstants.diacriticsMap[char] ?? char)
          .toLowerCase();
      buffer.write(folded);
      for (var k = 0; k < folded.length; k++) {
        indices.add(i);
      }
    }
    final value = buffer.toString();
    assert(
      value == normalizeForSearch(source),
      'FoldedText drifted from normalizeForSearch for "$source"',
    );
    assert(value.length == indices.length);
    return FoldedText._(value, indices);
  }

  /// Maps a half-open range in [value] back to a half-open source range.
  TextRange toSourceRange(int foldedStart, int foldedEnd) {
    if (foldedStart >= foldedEnd || sourceIndex.isEmpty) {
      return TextRange.empty;
    }
    final start = sourceIndex[foldedStart];
    // The last folded unit of the match may be one of several emitted by a
    // single source character; the source range has to cover that whole
    // character, hence +1 on its index rather than the next one's start.
    final end = sourceIndex[foldedEnd - 1] + 1;
    return TextRange(start: start, end: end);
  }
}

/// A parsed settings filter query: the folded, whitespace-split tokens.
///
/// Deliberately keeps single-character tokens. The note index's
/// `searchTokens` drops anything shorter than two characters because it
/// counts term frequency; that rule is wrong for a live filter, where
/// typing one letter should already narrow the list. Only the *fold* is
/// shared — tokenization is free to differ per surface.
class SettingsQuery {
  final List<String> tokens;

  const SettingsQuery(this.tokens);

  static const SettingsQuery empty = SettingsQuery(<String>[]);

  factory SettingsQuery.parse(String raw) {
    final folded = normalizeForSearch(raw).trim();
    if (folded.isEmpty) return empty;
    return SettingsQuery(
      folded.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList(),
    );
  }

  bool get isEmpty => tokens.isEmpty;
  bool get isNotEmpty => tokens.isNotEmpty;
}

/// Where a query matched an entry, in source offsets ready for highlighting.
class SettingsMatch {
  final List<TextRange> titleSpans;
  final List<TextRange> descriptionSpans;

  const SettingsMatch({
    this.titleSpans = const [],
    this.descriptionSpans = const [],
  });
}

/// Matches [query] against one settings entry, or returns null.
///
/// Every token must hit the title, the description or a keyword — an AND,
/// so extra words narrow rather than widen. Keywords are matched but never
/// rendered, so they contribute no spans.
///
/// [sectionMatched] short-circuits to a spanless match: when the query hits
/// a section's own title, the whole section stays visible, which is what
/// people expect when they search for a heading.
SettingsMatch? matchSettingsEntry(
  SettingsQuery query, {
  required String title,
  String? description,
  List<String> keywords = const [],
  bool sectionMatched = false,
}) {
  if (query.isEmpty || sectionMatched) return const SettingsMatch();

  final foldedTitle = FoldedText.of(title);
  final foldedDescription = description == null
      ? null
      : FoldedText.of(description);
  final foldedKeywords = keywords
      .map((k) => normalizeForSearch(k))
      .where((k) => k.isNotEmpty)
      .toList();

  final titleSpans = <TextRange>[];
  final descriptionSpans = <TextRange>[];

  for (final token in query.tokens) {
    final inTitle = _spansOf(foldedTitle, token);
    final inDescription = foldedDescription == null
        ? const <TextRange>[]
        : _spansOf(foldedDescription, token);
    final inKeywords = foldedKeywords.any((k) => k.contains(token));

    if (inTitle.isEmpty && inDescription.isEmpty && !inKeywords) return null;

    titleSpans.addAll(inTitle);
    descriptionSpans.addAll(inDescription);
  }

  return SettingsMatch(
    titleSpans: _merge(titleSpans),
    descriptionSpans: _merge(descriptionSpans),
  );
}

/// True when [query] matches any of [fields] — the shape used by list
/// filters that render their own rows and need no spans.
///
/// Pass [preFolded] when the caller hands over strings that have already been
/// through [normalizeForSearch] — a static index built once rather than
/// re-derived per keystroke, as `CalendarIcons.searchTextOf` is. It skips the
/// fold rather than changing the grammar, so an indexed surface and an ad-hoc
/// one cannot answer the same query differently. The claim is asserted in
/// debug, in the register of [FoldedText]'s own drift assert.
bool matchesSettingsQuery(
  SettingsQuery query,
  Iterable<String> fields, {
  bool preFolded = false,
}) {
  if (query.isEmpty) return true;
  assert(
    !preFolded || fields.every((f) => f == normalizeForSearch(f)),
    'matchesSettingsQuery: preFolded fields must already be normalized',
  );
  final folded = [
    for (final field in fields)
      if (field.isNotEmpty) preFolded ? field : normalizeForSearch(field),
  ];
  if (folded.isEmpty) return false;
  return query.tokens.every((t) => folded.any((f) => f.contains(t)));
}

/// Occurrences of [token] in [text], mapped back to source offsets.
///
/// When the token starts a word anywhere in the text, only word-start hits
/// are reported — highlighting "set" inside "offset" while a real
/// "Settings" match sits in the same string reads as a bug.
List<TextRange> _spansOf(FoldedText text, String token) {
  final all = <int>[];
  var from = 0;
  while (true) {
    final at = text.value.indexOf(token, from);
    if (at < 0) break;
    all.add(at);
    from = at + 1;
  }
  if (all.isEmpty) return const [];

  final wordStarts = all.where((at) => _isWordStart(text.value, at)).toList();
  final chosen = wordStarts.isNotEmpty ? wordStarts : all;
  return chosen
      .map((at) => text.toSourceRange(at, at + token.length))
      .where((r) => r != TextRange.empty)
      .toList();
}

bool _isWordStart(String text, int index) {
  if (index == 0) return true;
  final previous = text.codeUnitAt(index - 1);
  final isAlphanumeric =
      (previous >= 48 && previous <= 57) || (previous >= 97 && previous <= 122);
  return !isAlphanumeric;
}

/// Sorts and merges overlapping spans so highlighting never paints a range
/// twice (which would double the background alpha).
List<TextRange> _merge(List<TextRange> spans) {
  if (spans.length < 2) return spans;
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <TextRange>[sorted.first];
  for (final span in sorted.skip(1)) {
    final last = merged.last;
    if (span.start <= last.end) {
      if (span.end > last.end) {
        merged[merged.length - 1] = TextRange(start: last.start, end: span.end);
      }
    } else {
      merged.add(span);
    }
  }
  return merged;
}
