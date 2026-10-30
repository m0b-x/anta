import '../constants/report_metrics.dart';
import '../models/calendar_report.dart';
import 'lru_cache.dart';
import 'markdown_list_syntax.dart';

/// The cache's stand-in for "no task item": [LruCache] cannot store a null,
/// and a real count always has at least one item.
const ReportTaskCount _noTasks = ReportTaskCount(0, 0);

final LruCache<String, ReportTaskCount> _cache = LruCache(
  maxSize: ReportMetrics.taskCountCacheSize,
);

/// The task progress of [text] — ticked of total task items — or null when
/// it holds none (D27).
///
/// Counts every task line the engine's list grammar ([MarkdownListSyntax])
/// recognises, per line (D27): a box inside a fenced block counts, one behind
/// a quote prefix does not. A custom state (`[-]`, `[>]`) is open, as the
/// preview's tick says. Cached by the text, so a shared description is parsed
/// once however many days show it.
ReportTaskCount? countTasks(String? text) {
  if (text == null || text.isEmpty) return null;
  final cached = _cache.get(text);
  if (cached != null) return identical(cached, _noTasks) ? null : cached;
  var ticked = 0;
  var total = 0;
  for (final line in text.split('\n')) {
    final item = MarkdownListSyntax.parse(line);
    if (item == null || item.kind != MarkdownListKind.task) continue;
    total++;
    if (item.checked) ticked++;
  }
  final count = total == 0 ? _noTasks : ReportTaskCount(ticked, total);
  _cache.put(text, count);
  return identical(count, _noTasks) ? null : count;
}
