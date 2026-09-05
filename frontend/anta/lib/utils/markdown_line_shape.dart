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

  /// A table row: after optional leading whitespace the line starts
  /// with `|` and, ignoring trailing whitespace, ends with `|`.
  static final _tableRowPattern = RegExp(r'^[ \t]*\|.*\|[ \t]*$');

  /// A table delimiter row (`| --- | :-: |`), tested against the
  /// trimmed line once [isTableRow] has accepted it.
  static final _tableSeparatorPattern = RegExp(r'^\|[\s:-]+\|[\s:|+-]*$');

  /// Whether [line] is a table row: after optional leading whitespace it
  /// starts with `|` and, ignoring trailing whitespace, ends with `|`,
  /// so a lone `|` is prose (the shape needs at least two code units).
  ///
  /// The single table-row predicate for the preview, the editor and the
  /// paste policies.
  static bool isTableRow(String line) => _tableRowPattern.hasMatch(line);

  /// Whether [line] is a table's delimiter row — a table row whose cells
  /// hold only dashes, colons and spacing (`| --- | :-: |`). Rendered as
  /// structure rather than content on both surfaces.
  static bool isTableSeparator(String line) =>
      isTableRow(line) && _tableSeparatorPattern.hasMatch(line.trim());

  /// `---` / `***` / `___` (three or more of one marker), indent and
  /// trailing blanks allowed. The single horizontal-rule predicate for
  /// the preview, the live editor and the line-height calculator.
  static final _horizontalRule = RegExp(r'^[ \t]*([-*_])\1{2,}[ \t]*$');

  /// Whether [line] is a horizontal rule.
  static bool isHorizontalRule(String line) => _horizontalRule.hasMatch(line);

  /// The ATX heading [line] is, or `null`: after optional indent, one to
  /// six `#` followed by a space or the line end — so `#tag` and
  /// `#######` are prose, and a bare `###` is an empty heading. The
  /// single heading predicate for every surface.
  static MarkdownHeadingMatch? headingAt(String line) {
    final n = line.length;
    var i = 0;
    while (i < n &&
        (line.codeUnitAt(i) == 0x20 || line.codeUnitAt(i) == 0x09)) {
      i++;
    }
    if (i >= n || line.codeUnitAt(i) != 0x23) return null;
    final hashStart = i;
    while (i < n && line.codeUnitAt(i) == 0x23) {
      i++;
    }
    final level = i - hashStart;
    if (level > 6) return null;
    if (i == n) {
      return MarkdownHeadingMatch(
        level: level,
        hashStart: hashStart,
        contentStart: n,
      );
    }
    if (line.codeUnitAt(i) != 0x20) return null;
    return MarkdownHeadingMatch(
      level: level,
      hashStart: hashStart,
      contentStart: i + 1,
    );
  }

  /// Whether [line] is a line-led construct that must stay one intact,
  /// unprefixed source line to keep its meaning: a horizontal rule, a
  /// blockquote / callout, a table row, a fence delimiter, a heading, or
  /// a money row (bare, heading-prefixed or list-prefixed).
  static bool isLineLedConstruct(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    // A rule is a run of one marker with no word boundary in it, so the
    // width breaker would happily cut `-` * 60 into six lines and the
    // list-aware paste would prefix it into `- ---`. Tested before the
    // switch because a rule's lead char is also a bullet marker.
    if (isHorizontalRule(trimmed)) return true;
    switch (trimmed.codeUnitAt(0)) {
      case 0x3E: // > — blockquote / callout
        return true;
      case 0x7C: // | — table row
        return isTableRow(trimmed);
      case 0x60: // ` — fence delimiter
        return MarkdownChunker.isFenceDelimiter(trimmed);
      case 0x24: // $ — money row (full shape parse, not just the probe)
        return MarkdownMoneySyntax.parse(trimmed) != null;
      case 0x23: // # — heading, or a space-less money heading (`##$$`)
        return headingAt(trimmed) != null ||
            (MarkdownMoneySyntax.leadsWithMoney(trimmed) &&
                MarkdownMoneySyntax.parse(trimmed) != null);
    }
    // List-prefixed money rows (`- $+ 12.50`, `1. $$`): the probe is
    // cheap and rejects ordinary list prose before the full parse runs.
    return MarkdownMoneySyntax.leadsWithMoney(trimmed) &&
        MarkdownMoneySyntax.parse(trimmed) != null;
  }
}

/// An ATX heading's shape on one line: [level] hashes starting at
/// [hashStart] (after any indent), content from [contentStart] (past
/// the single space, or the line end for a bare `###`).
class MarkdownHeadingMatch {
  final int level;
  final int hashStart;
  final int contentStart;

  const MarkdownHeadingMatch({
    required this.level,
    required this.hashStart,
    required this.contentStart,
  });

  /// One past the last hash.
  int get hashEnd => hashStart + level;
}
