import '../constants/markdown_constants.dart';
import 'ghost_text.dart';
import 'markdown_chunker.dart';
import 'markdown_link_patterns.dart';
import 'markdown_list_syntax.dart';
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

  /// The index of the first cell boundary of the table row [line] at or
  /// after [from], or `-1` when none is left. The single cell splitter
  /// for the editor, the preview and the plain text, so a row has the
  /// same cells on every surface; chain it from `0` and from one past
  /// each boundary it returns.
  ///
  /// A boundary is a `|` that the inline grammar would leave as plain
  /// text: an escaped `\|` is a literal pipe, as GFM spells one inside a
  /// cell; the alias pipe of a `[[Title|alias]]` wiki link
  /// ([MarkdownLinkPatterns.matchWikiLinkAt]) belongs to the link; and a
  /// `|` inside one of the line's (sorted, non-overlapping) [ghosts] is
  /// that placeholder's content. The rules mirror the tokenizer's atoms
  /// (escapes, ghosts, code spans) in both directions, so a cell never
  /// cuts a token the cell's own tokenize would build, and never keeps a
  /// `|` that tokenize leaves as plain text: an escape needs escapable
  /// punctuation and never reaches into a ghost; a `[` inside a closed
  /// code span opens no wiki link; and a wiki link that overlaps a ghost
  /// or holds an atom is refused, as `_tryWikiLink` refuses it.
  ///
  /// An unescaped `|` inside a code span is still a boundary, as in GFM,
  /// so a code span never reaches across one. Two corners stay apart from
  /// GFM, accepted as rare: an escaped `\|` inside a code span shows its
  /// `\` (code content is literal, where GFM unescapes the row first),
  /// and a `[[a|b]]` spelled inside code keeps its pipe, since the code
  /// span cannot close across the alias pipe. Obsidian splits a cell at
  /// an unescaped alias pipe, also in `![[photo.png|100]]`, and spells the
  /// alias `[[Note\|alias]]`; here the alias pipe stays in the link, and
  /// that escaped spelling holds an atom, so it renders as raw text and
  /// never opens a note named `Note\`.
  static int nextTableCellPipe(
    String line,
    int from, [
    List<GhostMatch> ghosts = const <GhostMatch>[],
  ]) {
    final n = line.length;
    var gi = _firstGhostEndingAfter(ghosts, from);
    var i = from;
    while (i < n) {
      while (gi < ghosts.length && ghosts[gi].end <= i) {
        gi++;
      }
      final nextGhost = gi < ghosts.length ? ghosts[gi].start : n;
      if (nextGhost <= i) {
        i = ghosts[gi].end;
        continue;
      }
      final c = line.codeUnitAt(i);
      if (c == 0x7C) return i;
      if (c == 0x5C &&
          i + 1 < nextGhost &&
          MarkdownConstants.isEscapablePunctuation(line.codeUnitAt(i + 1))) {
        i += 2;
        continue;
      }
      if (c == 0x60) {
        final close = _codeSpanEnd(line, i, i, ghosts, gi);
        i = close >= 0 ? close : _runEnd(line, i);
        continue;
      }
      if (c == 0x5B) {
        final wiki = MarkdownLinkPatterns.matchWikiLinkAt(line, i);
        if (wiki != null &&
            wiki.end <= nextGhost &&
            !_atomOpensWithin(line, i + 1, wiki.end, ghosts, gi)) {
          i = wiki.end;
          continue;
        }
      }
      i++;
    }
    return -1;
  }

  /// The first of the sorted, non-overlapping [ghosts] that ends after
  /// [from] — a binary search, so a scan resumed at every boundary of a
  /// placeholder-heavy row does not rewalk the ghosts behind it.
  static int _firstGhostEndingAfter(List<GhostMatch> ghosts, int from) {
    var lo = 0;
    var hi = ghosts.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ghosts[mid].end <= from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// End of the backtick run that starts at [i].
  static int _runEnd(String line, int i) {
    var r = i + 1;
    while (r < line.length && line.codeUnitAt(r) == 0x60) {
      r++;
    }
    return r;
  }

  /// End of the code span whose opening backtick run starts at [open], or
  /// `-1` when no run of the same length closes it before a cell
  /// boundary `|` at or after [pipesFrom]. Content is literal, as in the
  /// tokenizer's fence search, except that escape pairs are stepped over
  /// the way the cell scan steps over them (so `\\|` still stops it) and
  /// ghosts are skipped whole; [gi] is the scan's ghost cursor.
  static int _codeSpanEnd(
    String line,
    int open,
    int pipesFrom,
    List<GhostMatch> ghosts,
    int gi,
  ) {
    final n = line.length;
    final opened = _runEnd(line, open);
    final fence = opened - open;
    var j = opened;
    while (j < n) {
      while (gi < ghosts.length && ghosts[gi].end <= j) {
        gi++;
      }
      if (gi < ghosts.length && ghosts[gi].start <= j) {
        j = ghosts[gi].end;
        continue;
      }
      final c = line.codeUnitAt(j);
      if (c == 0x7C && j >= pipesFrom) return -1;
      if (c == 0x5C &&
          j + 1 < n &&
          line.codeUnitAt(j + 1) != 0x60 &&
          MarkdownConstants.isEscapablePunctuation(line.codeUnitAt(j + 1))) {
        j += 2;
        continue;
      }
      if (c == 0x60) {
        final r = _runEnd(line, j);
        if (r - j == fence) return r;
        j = r;
        continue;
      }
      j++;
    }
    return -1;
  }

  /// Whether a tokenizer atom — an escape or a closed code span — opens
  /// in `[lo, hi)`, the inside of a wiki link that ends at [hi] and
  /// overlaps no ghost. A code span there may close past [hi], before
  /// the next boundary, as the cell's own tokenize would let it.
  static bool _atomOpensWithin(
    String line,
    int lo,
    int hi,
    List<GhostMatch> ghosts,
    int gi,
  ) {
    var j = lo;
    while (j < hi) {
      final c = line.codeUnitAt(j);
      if (c == 0x5C &&
          j + 1 < line.length &&
          MarkdownConstants.isEscapablePunctuation(line.codeUnitAt(j + 1))) {
        return true;
      }
      if (c == 0x60) {
        if (_codeSpanEnd(line, j, hi, ghosts, gi) >= 0) return true;
        j = _runEnd(line, j);
        continue;
      }
      j++;
    }
    return false;
  }

  /// `---` / `***` / `___` (three or more of one marker), spaces or tabs
  /// allowed between the markers (`- - -`), indent and trailing blanks
  /// allowed. The single horizontal-rule predicate for the preview, the
  /// live editor, the line-height calculator and the list grammar, which
  /// refuses every line this accepts.
  ///
  /// A code-unit loop rather than a regex: the list grammar's
  /// allocation-free [MarkdownListSyntax.scanListShape] and the editor's
  /// per-line dispatch ask it of every bullet line.
  static bool isHorizontalRule(String line) {
    final n = line.length;
    var i = 0;
    while (i < n && _isBlank(line.codeUnitAt(i))) {
      i++;
    }
    if (i >= n) return false;
    final marker = line.codeUnitAt(i);
    if (marker != 0x2D && marker != 0x2A && marker != 0x5F) return false;
    var count = 0;
    for (; i < n; i++) {
      final c = line.codeUnitAt(i);
      if (c == marker) {
        count++;
      } else if (!_isBlank(c)) {
        return false;
      }
    }
    return count >= 3;
  }

  /// The ATX heading [line] is, or `null`: after optional indent, one to
  /// six `#` followed by a space or the line end — so `#tag` and
  /// `#######` are prose, and a bare `###` is an empty heading. A closing
  /// run of `#` after a space (`## Week 3 ##`) is not content; see
  /// [MarkdownHeadingMatch.contentEnd]. The single heading predicate for
  /// every surface.
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
        contentEnd: n,
      );
    }
    if (line.codeUnitAt(i) != 0x20) return null;
    final contentStart = i + 1;
    return MarkdownHeadingMatch(
      level: level,
      hashStart: hashStart,
      contentStart: contentStart,
      contentEnd: _closingSequenceStart(line, contentStart),
    );
  }

  /// Where a heading's content ends: before an optional closing run of
  /// `#` (trailing blanks after it allowed) that is preceded by a blank
  /// or is the whole content, and before the blanks in front of that
  /// run. Without such a run the content runs to the line end, so
  /// `## C#` and `## Title##` keep their hashes.
  static int _closingSequenceStart(String line, int contentStart) {
    final n = line.length;
    var e = n;
    while (e > contentStart && _isBlank(line.codeUnitAt(e - 1))) {
      e--;
    }
    var k = e;
    while (k > contentStart && line.codeUnitAt(k - 1) == 0x23) {
      k--;
    }
    if (k == e) return n;
    if (k > contentStart && !_isBlank(line.codeUnitAt(k - 1))) return n;
    while (k > contentStart && _isBlank(line.codeUnitAt(k - 1))) {
      k--;
    }
    return k;
  }

  static bool _isBlank(int c) => c == 0x20 || c == 0x09;

  /// The heading level a setext underline under a text line gives it:
  /// `1` for a run of three or more `=`, `2` for one of `-`, `0` when
  /// [line] is no underline. Up to three spaces of indent and trailing
  /// blanks are allowed, nothing between the markers — so `- - -` is only
  /// ever a rule, while `---` is an underline or a rule depending on the
  /// line above ([setextLevelOf]).
  static int setextUnderlineLevel(String line) {
    final n = line.length;
    var i = 0;
    while (i < n && i < 3 && line.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i >= n) return 0;
    final marker = line.codeUnitAt(i);
    if (marker != 0x3D && marker != 0x2D) return 0;
    var j = i;
    while (j < n && line.codeUnitAt(j) == marker) {
      j++;
    }
    if (j - i < 3) return 0;
    for (var k = j; k < n; k++) {
      if (!_isBlank(line.codeUnitAt(k))) return 0;
    }
    return marker == 0x3D ? 1 : 2;
  }

  /// Whether [line] can carry a setext underline: a plain paragraph line
  /// — not blank, not a [isLineLedConstruct] (rules, quotes, headings,
  /// tables, fences, money rows), not a list item, and no underline
  /// itself, so `===` under `===` is text. Whether the line sits inside a
  /// fence or a comment is positional; the caller checks that.
  static bool isSetextTextLine(String line) =>
      !MarkdownChunker.isBlankLine(line) &&
      setextUnderlineLevel(line) == 0 &&
      !isLineLedConstruct(line) &&
      MarkdownListSyntax.scanListShape(line) < 0;

  /// The setext heading level of [line] given the line after it, or `0`:
  /// [nextLine] is an underline ([setextUnderlineLevel]) and [line] a
  /// [isSetextTextLine]. The sibling of [headingAt] for the one heading
  /// form a single line cannot answer. Only the line directly above the
  /// underline becomes the heading, where CommonMark takes the whole
  /// paragraph: the editor reads lines, not paragraphs, so the lines
  /// before it stay prose — and an indented line, a list item's
  /// continuation or a bare `-` marker is a text line like any other,
  /// since the grammar models no lazy continuation. The heading menu, the
  /// header-level rewrite and the `[[Note#heading]]` target read
  /// [headingAt] only, so they leave a setext heading alone: it shows no
  /// level, a picked level prefixes `#`s (the underline then reads as a
  /// rule), and a wiki link cannot land on it.
  static int setextLevelOf(String line, String? nextLine) {
    if (nextLine == null) return 0;
    final level = setextUnderlineLevel(nextLine);
    if (level == 0) return 0;
    return isSetextTextLine(line) ? level : 0;
  }

  /// Whether [line] is a line-led construct that must stay one intact,
  /// unprefixed source line to keep its meaning: a horizontal rule, a
  /// blockquote / callout, a table row, a fence delimiter (``` or ~~~), a
  /// `%%` block comment marker, a heading, or a money row (bare,
  /// heading-prefixed or list-prefixed).
  static bool isLineLedConstruct(String line) {
    // Each predicate reads the raw line, as both dispatchers call it, so
    // a lead only `trim` strips (a no-break space) cannot make a line
    // line-led here and prose on screen; the lead char only routes.
    final lead = line.length - line.trimLeft().length;
    if (lead >= line.length) return false;
    // A rule is a run of one marker with no word boundary in it, so the
    // width breaker would happily cut `-` * 60 into six lines and the
    // list-aware paste would prefix it into `- ---`. Tested before the
    // switch because a rule's lead char is also a bullet marker.
    if (isHorizontalRule(line)) return true;
    switch (line.codeUnitAt(lead)) {
      case 0x3E: // > — blockquote / callout
        return true;
      case 0x7C: // | — table row
        return isTableRow(line);
      case 0x60: // ` — fence delimiter
      case 0x7E: // ~ — fence delimiter
        return MarkdownChunker.isFenceDelimiter(line);
      case 0x25: // % — block comment marker
        return MarkdownChunker.isCommentDelimiter(line);
      case 0x24: // $ — money row (full shape parse, not just the probe)
        return MarkdownMoneySyntax.parse(line) != null;
      case 0x23: // # — heading, or a space-less money heading (`##$$`)
        return headingAt(line) != null ||
            (MarkdownMoneySyntax.leadsWithMoney(line) &&
                MarkdownMoneySyntax.parse(line) != null);
    }
    // List-prefixed money rows (`- $+ 12.50`, `1. $$`): the probe is
    // cheap and rejects ordinary list prose before the full parse runs.
    return MarkdownMoneySyntax.leadsWithMoney(line) &&
        MarkdownMoneySyntax.parse(line) != null;
  }
}

/// An ATX heading's shape on one line: [level] hashes starting at
/// [hashStart] (after any indent), content from [contentStart] (past
/// the single space, or the line end for a bare `###`) to [contentEnd].
class MarkdownHeadingMatch {
  final int level;
  final int hashStart;
  final int contentStart;

  /// One past the last content code unit: the line end, or the start of
  /// the blanks before a closing `#` run (`## Week 3 ##` ends after `3`),
  /// so every surface conceals or drops `[contentEnd, line end)` alike.
  /// Never below [contentStart].
  final int contentEnd;

  const MarkdownHeadingMatch({
    required this.level,
    required this.hashStart,
    required this.contentStart,
    required this.contentEnd,
  });

  /// One past the last hash.
  int get hashEnd => hashStart + level;
}
