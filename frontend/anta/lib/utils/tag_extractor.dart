import '../constants/analytics_metrics.dart';
import 'lru_cache.dart';
import 'markdown_link_patterns.dart';
import 'markdown_tag_syntax.dart';

final LruCache<String, List<String>> _cache = LruCache(
  maxSize: AnalyticsMetrics.tagCacheSize,
);

/// The `#tags` of [text] as typed, without `#`, in order of first
/// appearance; a tag typed twice in one text is listed once.
///
/// The editor's and the preview's own grammar ([MarkdownTagSyntax]), so the
/// report finds exactly the tags the owner sees highlighted — and, as the
/// inline grammar places them, never one inside a code span (`` `#a` ``)
/// or a bare URL (`https://a.b/#frag`), which bind before a tag does.
/// Cached by the text, `countTasks`'s shape: a shared description is
/// tokenised once however many days show it; a text with no `#` never
/// reaches the cache.
List<String> extractTags(String? text) {
  if (text == null || !text.contains('#')) return const [];
  final cached = _cache.get(text);
  if (cached != null) return cached;
  final tags = <String>[];
  final seen = <String>{};
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text.codeUnitAt(i);
    if (c == _backtick) {
      i = _codeSpanEnd(text, i);
      continue;
    }
    if ((c == _lowerH || c == _lowerW) &&
        MarkdownTagSyntax.isWordBoundaryBefore(text, i)) {
      final end = MarkdownLinkPatterns.matchBareUrlEnd(text, i);
      if (end >= 0) {
        i = end;
        continue;
      }
    }
    if (c == _hash && MarkdownTagSyntax.isWordBoundaryBefore(text, i)) {
      final end = MarkdownTagSyntax.tryParseTagAt(text, i);
      if (end != null) {
        final tag = text.substring(i + 1, end);
        if (seen.add(tag)) tags.add(tag);
        i = end;
        continue;
      }
    }
    i++;
  }
  final result = tags.isEmpty
      ? const <String>[]
      : List<String>.unmodifiable(tags);
  _cache.put(text, result);
  return result;
}

const int _backtick = 0x60;
const int _hash = 0x23;
const int _lowerH = 0x68;
const int _lowerW = 0x77;

/// Where scanning resumes after the backtick run at [start]: past the code
/// span it opens — closed by the next run of exactly its length, the inline
/// grammar's rule — or past the run alone when it never closes, since an
/// unclosed run is literal. The grammar's own scan lives in a module that
/// pulls in the painting layer, which the pure report fold may not import;
/// this is its rule without the ghost runs, which a report text never
/// carries in practice.
int _codeSpanEnd(String text, int start) {
  final n = text.length;
  var r = start + 1;
  while (r < n && text.codeUnitAt(r) == _backtick) {
    r++;
  }
  final fence = r - start;
  var j = r;
  while (j < n) {
    if (text.codeUnitAt(j) != _backtick) {
      j++;
      continue;
    }
    var k = j + 1;
    while (k < n && text.codeUnitAt(k) == _backtick) {
      k++;
    }
    if (k - j == fence) return k;
    j = k;
  }
  return r;
}
