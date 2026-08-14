import 'markdown_chunker.dart';
import 'markdown_money_syntax.dart';

/// Shape probe for line-led markdown constructs whose meaning lives on
/// a single source line: money-ledger rows, headings, blockquote /
/// callout lines, table rows, and code-fence delimiters.
///
/// Single source of truth for the paste policies: the width
/// line-breaker never splits such a line (the tail would lose the lead
/// marker and the construct's meaning with it — a torn money row stops
/// counting, a torn table row breaks the table) and the list-aware
/// paste never prefixes one with a list marker (`- $+ 12.50` *is* a
/// money row nowadays, but prefixing pasted ledger lines would still
/// change what the user pasted, so the no-prefix rule stays). List
/// items are deliberately not covered: both consumers already have
/// their own list handling via `MarkdownListSyntax`, and wrapping long
/// list prose is exactly what the width breaker exists for — except a
/// **list-prefixed money row**, which is a money row first and must
/// stay intact like its unprefixed spelling.
///
/// Matched by shape only, mirroring the preview's line dispatch in
/// `LineBasedMarkdownBuilder`: `$`-led lines count only when the full
/// [MarkdownMoneySyntax.parse] accepts them, so plain text like
/// `$5 coffee` is not structural and keeps its plain-text treatment;
/// headings are 1–6 `#` + space or line end, which also covers
/// `## $$ …` header-prefixed money rows.
class MarkdownLineShape {
  MarkdownLineShape._();

  /// Mirrors `_MarkdownPatterns.tableRow` in the preview builder.
  static final _tableRow = RegExp(r'^\|.*\|$');

  /// Whether [line] is a line-led construct that must stay one intact,
  /// unprefixed source line to keep its meaning.
  static bool isLineLedConstruct(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    switch (trimmed.codeUnitAt(0)) {
      case 0x3E: // > — blockquote / callout
        return true;
      case 0x7C: // | — table row
        return _tableRow.hasMatch(trimmed);
      case 0x60: // ` — fence delimiter
        return MarkdownChunker.isFenceDelimiter(trimmed);
      case 0x24: // $ — money row (full shape parse, not just the probe)
        return MarkdownMoneySyntax.parse(trimmed) != null;
      case 0x23: // # — heading, incl. header-prefixed money rows
        var i = 1;
        while (i < trimmed.length && trimmed.codeUnitAt(i) == 0x23) {
          i++;
        }
        return i <= 6 && (i == trimmed.length || trimmed.codeUnitAt(i) == 0x20);
    }
    // List-prefixed money rows (`- $+ 12.50`, `1. $$`): the probe is
    // cheap and rejects ordinary list prose before the full parse runs.
    return MarkdownMoneySyntax.leadsWithMoney(trimmed) &&
        MarkdownMoneySyntax.parse(trimmed) != null;
  }
}
