/// Shared, widget-free grammar for GitHub-style callouts / admonitions
/// (`> [!TIP]`, `> [!WARNING]`, …).
///
/// This is the single source of truth consumed by both the chunker
/// ([MarkdownChunker], which marks a `>`-run led by `> [!TYPE]` as a
/// `MarkdownBlockKind.callout`) and the preview renderer
/// ([LineBasedMarkdownBuilder], which styles each callout line). Keeping
/// the grammar here guarantees the block scan and the renderer can never
/// disagree about what is a callout — mirroring how [MarkdownListSyntax]
/// and [GhostText] are each a single source of truth.
///
/// Colours are intentionally NOT defined here so this stays a pure,
/// Flutter-free, testable grammar; the shared palette lives in
/// `MarkdownConstants.calloutAccent` (used by preview and live editor).
library;

import 'markdown_list_syntax.dart';

/// The recognised callout kinds. The first five mirror GitHub's
/// admonitions; [success] and [pr] are gym-log additions ("hit every
/// set", "new personal record"); the rest are Obsidian's own kinds.
/// New kinds are appended, never inserted: the editor's line index packs
/// `index + 1` per line, and appending keeps every existing value.
enum MarkdownCalloutType {
  note,
  tip,
  important,
  warning,
  caution,
  success,
  pr,
  example,
  question,
  danger,
  bug,
  todo,
  quote,
  abstract,
  failure,
}

/// A parsed callout lead line (`> [!TYPE] optional title`).
class MarkdownCalloutLead {
  /// The callout kind: a recognised token or alias, or [MarkdownCalloutType.note]
  /// for any other word, so an unknown `[!word]` still reads as a callout.
  final MarkdownCalloutType type;

  /// The optional inline title after `[!TYPE]` and its fold marker
  /// (already trimmed). Empty when the lead line is just `> [!TYPE]`.
  final String title;

  /// The title shown when [title] is empty: the token's own text between
  /// `[!` and `]`, title-cased unit for unit (`WARNING` → `Warning`), so
  /// the editor can paint it over exactly those code units and the
  /// preview can map it onto them. Content-level, like a fence's language
  /// label, so never localized. Built on first read: the block scans
  /// (the chunker, the line index) parse leads for [type] alone.
  late final String label = MarkdownCalloutSyntax._labelOf(_word, type);

  /// The token's raw text between `[!` and `]`, [label]'s source.
  final String _word;

  /// Line-relative offset of the `-` or `+` fold marker right after the
  /// token's `]`, or `-1` when the lead carries none. Folding is not
  /// built; the marker is chrome both surfaces hide.
  final int foldMarker;

  /// Line-relative offset where [title] begins, so the renderer can add
  /// the line's source-start offset and keep search highlighting aligned
  /// on the title text.
  final int titleStart;

  /// Line-relative offset of the `[!TYPE]` token's opening `[`, so the
  /// live editor can tint the token in place without re-scanning.
  final int tokenStart;

  /// Line-relative offset just past the token's closing `]`.
  final int tokenEnd;

  /// Line-relative offset where [label]'s units begin (past `[!`).
  int get labelStart => tokenStart + 2;

  /// Line-relative offset just past the token chrome: past the fold
  /// marker when there is one, else [tokenEnd].
  int get chromeEnd => foldMarker < 0 ? tokenEnd : foldMarker + 1;

  MarkdownCalloutLead({
    required this.type,
    required this.title,
    required String word,
    required this.foldMarker,
    required this.titleStart,
    required this.tokenStart,
    required this.tokenEnd,
  }) : _word = word;
}

/// The nested-quote shape of one blockquote line: [depth] `>` markers
/// standing at the line columns in [markerOffsets], with the quoted
/// content starting at [contentStart] (past the last `>` and the single
/// space that may follow it).
///
/// Produced by [MarkdownCalloutSyntax.quoteMarkers] and consumed by both
/// surfaces, so a `>> a` reads as two bars followed by `a` in the
/// preview and in the live editor alike.
class MarkdownQuoteShape {
  /// How many `>` markers lead the line (at least one).
  final int depth;

  /// The line column of each `>`, in source order; [depth] entries.
  final List<int> markerOffsets;

  /// Line-relative offset where the quoted content begins.
  final int contentStart;

  const MarkdownQuoteShape({
    required this.depth,
    required this.markerOffsets,
    required this.contentStart,
  });
}

/// Pure functions describing the callout grammar.
class MarkdownCalloutSyntax {
  MarkdownCalloutSyntax._();

  static const int _gt = 0x3E; // >
  static const int _space = 0x20; // ' '
  static const int _tab = 0x09; // '\t'
  static const int _cr = 0x0D; // '\r'
  static const int _openBracket = 0x5B; // [
  static const int _bang = 0x21; // !
  static const int _minus = 0x2D; // -
  static const int _plus = 0x2B; // +

  /// Whether [c] is one of the ASCII code units [String.trimLeft] trims:
  /// the space plus the `\t\n\v\f\r` run at `0x09..0x0D`. Every other
  /// whitespace Dart trims is non-ASCII, so a scanner that skips these
  /// in place and defers anything `>= 0x80` to [String.trimLeft] agrees
  /// with the trimming form on every input.
  static bool _isAsciiTrimmed(int c) => c == _space || (c >= _tab && c <= _cr);

  /// Whether [line] is a blockquote line (optional indent + `>`). A
  /// callout block continues for as long as following lines are
  /// blockquote lines; the first non-blockquote line ends it.
  ///
  /// Allocation-free on the common path: the leading run of ASCII
  /// whitespace is walked in place and any other ASCII character answers
  /// the question immediately. Exotic (non-ASCII) leading whitespace
  /// falls back to [String.trimLeft], so the semantics are byte-identical
  /// to the trimming form for every input.
  ///
  /// Paired with [quoteMarkers]: `quoteMarkers(line) != null` exactly
  /// when this returns `true`, so a caller may gate on the cheap probe
  /// and rely on the shape being there.
  static bool isBlockquoteLine(String line) {
    final n = line.length;
    var i = 0;
    while (i < n) {
      final c = line.codeUnitAt(i);
      if (_isAsciiTrimmed(c)) {
        i++;
        continue;
      }
      if (c == _gt) return true;
      if (c < 0x80) return false;
      final trimmed = line.trimLeft();
      return trimmed.isNotEmpty && trimmed.codeUnitAt(0) == _gt;
    }
    return false;
  }

  /// The one per-line transition of the callout block scan: given the
  /// type of the block [open] on entry (`null` when none is), the type
  /// of the block covering [line], or `null` when [line] leaves no block
  /// open.
  ///
  /// A block is a lead line (`> [!TYPE]`) followed by every contiguous
  /// blockquote line: a nested lead inside an open block is body text of
  /// the outer block, and a blank or non-quote line ends it.
  ///
  /// Fences are the caller's business — the chunker consumes fences
  /// first and the editor's line index checks the fence role first — so
  /// a fenced line must be fed as "ends the block": the caller resets
  /// [open] to `null` on fence lines instead of calling this.
  ///
  /// Costs one allocation-free [isBlockquoteLine] probe per line;
  /// [parseLead] — which allocates a `trimLeft` on an indented line —
  /// runs only on `>`-led lines while no block is open. The gate is not
  /// just an optimization made safe by luck: a lead line is a blockquote
  /// line by construction, so `parseLead != null` implies
  /// [isBlockquoteLine], and refusing everything else changes nothing.
  static MarkdownCalloutType? blockStep(
    String line,
    MarkdownCalloutType? open,
  ) {
    if (!isBlockquoteLine(line)) return null;
    if (open != null) return open;
    return parseLead(line)?.type;
  }

  /// The nested-quote shape of [line], or `null` when it is not a
  /// blockquote line.
  ///
  /// After optional whitespace indent the line carries a run of `>`
  /// markers, each optionally followed by a single space (`>`, `>>`,
  /// `> >`, `> > >`); the run stops at the first character that is
  /// neither, so `> [!TIP]` is depth 1 and `>  a` (two spaces) keeps the
  /// second space as content. Only quote lines pay the small allocation.
  ///
  /// The indent rule is [isBlockquoteLine]'s, exactly: ASCII whitespace
  /// is skipped in place and the first non-ASCII unit defers to
  /// [String.trimLeft]. That is the contract between the two — this
  /// returns non-`null` exactly when [isBlockquoteLine] returns `true`,
  /// so a line indented with an exotic space (a no-break space, an
  /// ideographic space) still gets a shape whose first marker offset is
  /// that trimmed indent.
  static MarkdownQuoteShape? quoteMarkers(String line) {
    final n = line.length;
    var i = 0;
    while (i < n) {
      final c = line.codeUnitAt(i);
      if (_isAsciiTrimmed(c)) {
        i++;
        continue;
      }
      if (c >= 0x80) i = line.length - line.trimLeft().length;
      break;
    }
    if (i >= n || line.codeUnitAt(i) != _gt) return null;

    var scan = i;
    var depth = 0;
    var contentStart = i;
    while (scan < n && line.codeUnitAt(scan) == _gt) {
      depth++;
      scan++;
      if (scan < n && line.codeUnitAt(scan) == _space) scan++;
      contentStart = scan;
    }

    final offsets = List<int>.filled(depth, 0);
    var at = i;
    for (var k = 0; k < depth; k++) {
      offsets[k] = at;
      at++;
      if (at < n && line.codeUnitAt(at) == _space) at++;
    }
    return MarkdownQuoteShape(
      depth: depth,
      markerOffsets: offsets,
      contentStart: contentStart,
    );
  }

  /// The list item inside the quote on [line], read by
  /// [MarkdownListSyntax.parse] on the remainder past the innermost `>`
  /// run, with [base] that remainder's line offset (add it to every item
  /// offset). `null` when [line] is no quote or its remainder no list
  /// item. The one reading the editor, its tap policy and the preview
  /// share, so `> - [ ] warm-up` has its box at the same units on all of
  /// them.
  ///
  /// A tab straight after the last `>` is that marker's separator, as a
  /// space is, not a level of indent: `>\t- a` is a top-level item, its
  /// tab outside the item. Pass [shape] when the caller already holds
  /// [quoteMarkers] for [line].
  static ({MarkdownListItem item, int base})? quotedListItem(
    String line, {
    MarkdownQuoteShape? shape,
  }) {
    final quote = shape ?? quoteMarkers(line);
    if (quote == null) return null;
    var base = quote.contentStart;
    if (base < line.length &&
        line.codeUnitAt(base) == _tab &&
        base == quote.markerOffsets.last + 1) {
      base++;
    }
    if (base >= line.length) return null;
    final rest = line.substring(base);
    if (MarkdownListSyntax.scanListShape(rest) < 0) return null;
    final item = MarkdownListSyntax.parse(rest);
    return item == null ? null : (item: item, base: base);
  }

  /// Maps a `[!TYPE]` token (case-insensitive, surrounding spaces
  /// ignored) to a [MarkdownCalloutType] — its own name or one of
  /// Obsidian's aliases — or `null` when the word names no kind;
  /// [parseLead] styles such a word as a [MarkdownCalloutType.note].
  static MarkdownCalloutType? typeFromToken(String token) {
    switch (token.trim().toLowerCase()) {
      case 'note':
      case 'info':
        return MarkdownCalloutType.note;
      case 'tip':
      case 'hint':
        return MarkdownCalloutType.tip;
      case 'important':
        return MarkdownCalloutType.important;
      case 'warning':
      case 'attention':
        return MarkdownCalloutType.warning;
      case 'caution':
        return MarkdownCalloutType.caution;
      case 'success':
      case 'check':
      case 'done':
        return MarkdownCalloutType.success;
      case 'pr':
        return MarkdownCalloutType.pr;
      case 'example':
        return MarkdownCalloutType.example;
      case 'question':
      case 'faq':
      case 'help':
        return MarkdownCalloutType.question;
      case 'danger':
      case 'error':
        return MarkdownCalloutType.danger;
      case 'bug':
        return MarkdownCalloutType.bug;
      case 'todo':
        return MarkdownCalloutType.todo;
      case 'quote':
      case 'cite':
        return MarkdownCalloutType.quote;
      case 'abstract':
      case 'summary':
      case 'tldr':
        return MarkdownCalloutType.abstract;
      case 'failure':
      case 'fail':
      case 'missing':
        return MarkdownCalloutType.failure;
      default:
        return null;
    }
  }

  /// Tries to parse [line] as a callout lead line (`> [!TYPE]` with an
  /// optional fold marker and trailing title). Returns `null` when the
  /// line is no lead, so plain blockquotes are untouched. Any type word in
  /// the token makes a lead — an unknown one styles as a note — and
  /// anything else ([_isTypeWord]) leaves the line a plain quote.
  ///
  /// A `-` or `+` directly after `]` is Obsidian's fold marker and is
  /// recorded, not titled; one after a blank is title text.
  ///
  /// Both the chunker (block start detection) and the renderer call this,
  /// so they can never disagree about what starts a callout.
  static MarkdownCalloutLead? parseLead(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.codeUnitAt(0) != _gt) return null;
    final indent = line.length - trimmed.length;

    int i = 1; // past '>'
    while (i < trimmed.length && trimmed.codeUnitAt(i) == _space) {
      i++;
    }
    // Expect the `[!` lead.
    if (i + 1 >= trimmed.length ||
        trimmed.codeUnitAt(i) != _openBracket ||
        trimmed.codeUnitAt(i + 1) != _bang) {
      return null;
    }
    final close = trimmed.indexOf(']', i + 2);
    if (close < 0) return null;

    final word = trimmed.substring(i + 2, close);
    if (!_isTypeWord(word)) return null;
    final type = typeFromToken(word) ?? MarkdownCalloutType.note;

    int t = close + 1;
    var fold = -1;
    if (t < trimmed.length) {
      final c = trimmed.codeUnitAt(t);
      if (c == _minus || c == _plus) fold = t++;
    }
    while (t < trimmed.length && trimmed.codeUnitAt(t) == _space) {
      t++;
    }
    return MarkdownCalloutLead(
      type: type,
      title: trimmed.substring(t).trimRight(),
      word: word,
      foldMarker: fold < 0 ? -1 : indent + fold,
      // [t] is line-relative to [trimmed]; add [indent] for the absolute
      // column inside the original [line].
      titleStart: indent + t,
      tokenStart: indent + i,
      tokenEnd: indent + close + 1,
    );
  }

  /// The colour-emoji icon for a callout [type]. Emoji (rather than a
  /// `WidgetSpan`) keeps the lead line a pure text run, matching the
  /// renderer's existing `🖼` image placeholder.
  static String iconFor(MarkdownCalloutType type) {
    switch (type) {
      case MarkdownCalloutType.note:
        return '📝';
      case MarkdownCalloutType.tip:
        return '💡';
      case MarkdownCalloutType.important:
        return '❗';
      case MarkdownCalloutType.warning:
        return '⚠️';
      case MarkdownCalloutType.caution:
        return '🛑';
      case MarkdownCalloutType.success:
        return '✅';
      case MarkdownCalloutType.pr:
        return '🏆';
      case MarkdownCalloutType.example:
        return '📋';
      case MarkdownCalloutType.question:
        return '❓';
      case MarkdownCalloutType.danger:
        return '⚡';
      case MarkdownCalloutType.bug:
        return '🐛';
      case MarkdownCalloutType.todo:
        return '🔲';
      case MarkdownCalloutType.quote:
        return '💬';
      case MarkdownCalloutType.abstract:
        return '📄';
      case MarkdownCalloutType.failure:
        return '❌';
    }
  }

  /// The default header label for a callout [type], shown when the lead
  /// line carries no custom title. Derived from the markdown token (like
  /// a code fence's language label), so it is content-level and not
  /// localized.
  static String labelFor(MarkdownCalloutType type) {
    switch (type) {
      case MarkdownCalloutType.note:
        return 'Note';
      case MarkdownCalloutType.tip:
        return 'Tip';
      case MarkdownCalloutType.important:
        return 'Important';
      case MarkdownCalloutType.warning:
        return 'Warning';
      case MarkdownCalloutType.caution:
        return 'Caution';
      case MarkdownCalloutType.success:
        return 'Success';
      case MarkdownCalloutType.pr:
        return 'PR';
      case MarkdownCalloutType.example:
        return 'Example';
      case MarkdownCalloutType.question:
        return 'Question';
      case MarkdownCalloutType.danger:
        return 'Danger';
      case MarkdownCalloutType.bug:
        return 'Bug';
      case MarkdownCalloutType.todo:
        return 'Todo';
      case MarkdownCalloutType.quote:
        return 'Quote';
      case MarkdownCalloutType.abstract:
        return 'Abstract';
      case MarkdownCalloutType.failure:
        return 'Failure';
    }
  }

  /// Whether [word] (the token's text between `[!` and `]`) can name a
  /// callout type: one run of letters, digits, `-` or `_`, with blanks
  /// only around it. A linked image's `[badge`, two words, a `#tag`, a
  /// code span or a URL names no type, so such a quote stays the plain
  /// quote it was before unknown words became leads.
  static bool _isTypeWord(String word) {
    final inner = word.trim();
    if (inner.isEmpty) return false;
    for (var k = 0; k < inner.length; k++) {
      final c = inner.codeUnitAt(k);
      if (c >= 0x80) {
        // Non-ASCII letters (`ß`, `İ`) name types too; a non-ASCII
        // blank inside the word splits it like a space.
        if (String.fromCharCode(c).trim().isEmpty) return false;
        continue;
      }
      final lower = c | 0x20;
      if ((lower >= 0x61 && lower <= 0x7A) ||
          (c >= 0x30 && c <= 0x39) ||
          c == _minus ||
          c == 0x5F) {
        continue;
      }
      return false;
    }
    return true;
  }

  /// [word] (the token's text between `[!` and `]`) title-cased in place:
  /// the first letter upper, the rest lower, one code unit for one, so the
  /// editor can paint it over the token's own units. A unit whose case
  /// mapping would change the length (`ß` → `SS`) keeps its spelling. A
  /// word naming its kind outright takes the kind's own casing when that
  /// has the same length (`[!pr]` reads `PR`, as before), its blanks kept
  /// as typed (`[! pr ]` reads ` PR `).
  static String _labelOf(String word, MarkdownCalloutType type) {
    final canonical = labelFor(type);
    final inner = word.trim();
    if (canonical.length == inner.length &&
        canonical.toLowerCase() == inner.toLowerCase()) {
      if (inner.length == word.length) return canonical;
      final skip = word.length - word.trimLeft().length;
      return '${word.substring(0, skip)}$canonical'
          '${word.substring(skip + inner.length)}';
    }
    final out = StringBuffer();
    var first = true;
    for (var k = 0; k < word.length; k++) {
      final unit = String.fromCharCode(word.codeUnitAt(k));
      final mapped = first ? unit.toUpperCase() : unit.toLowerCase();
      if (first && unit.trim().isNotEmpty) first = false;
      out.write(mapped.length == 1 ? mapped : unit);
    }
    return out.toString();
  }
}
