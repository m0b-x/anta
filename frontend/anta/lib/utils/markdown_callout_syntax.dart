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

/// The recognised callout kinds. The first five mirror GitHub's
/// admonitions; [success] and [pr] are gym-log additions ("hit every
/// set", "new personal record").
enum MarkdownCalloutType { note, tip, important, warning, caution, success, pr }

/// A parsed callout lead line (`> [!TYPE] optional title`).
class MarkdownCalloutLead {
  /// The recognised callout kind.
  final MarkdownCalloutType type;

  /// The optional inline title after `[!TYPE]` (already trimmed). Empty
  /// when the lead line is just `> [!TYPE]`.
  final String title;

  /// Line-relative offset where [title] begins, so the renderer can add
  /// the line's source-start offset and keep search highlighting aligned
  /// on the title text.
  final int titleStart;

  /// Line-relative offset of the `[!TYPE]` token's opening `[`, so the
  /// live editor can tint the token in place without re-scanning.
  final int tokenStart;

  /// Line-relative offset just past the token's closing `]`.
  final int tokenEnd;

  const MarkdownCalloutLead({
    required this.type,
    required this.title,
    required this.titleStart,
    required this.tokenStart,
    required this.tokenEnd,
  });
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
  static const int _openBracket = 0x5B; // [
  static const int _bang = 0x21; // !

  /// Whether [line] is a blockquote line (optional indent + `>`). A
  /// callout block continues for as long as following lines are
  /// blockquote lines; the first non-blockquote line ends it.
  ///
  /// Allocation-free on the common path: the leading run of spaces and
  /// tabs is walked in place and any other ASCII character answers the
  /// question immediately. Exotic (non-ASCII) leading whitespace falls
  /// back to [String.trimLeft], so the semantics are byte-identical to
  /// the trimming form for every input.
  static bool isBlockquoteLine(String line) {
    final n = line.length;
    var i = 0;
    while (i < n) {
      final c = line.codeUnitAt(i);
      if (c == _space || c == _tab) {
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
  static MarkdownCalloutType? blockStep(
    String line,
    MarkdownCalloutType? open,
  ) {
    if (open != null && isBlockquoteLine(line)) return open;
    return parseLead(line)?.type;
  }

  /// The nested-quote shape of [line], or `null` when it is not a
  /// blockquote line.
  ///
  /// After optional space/tab indent the line carries a run of `>`
  /// markers, each optionally followed by a single space (`>`, `>>`,
  /// `> >`, `> > >`); the run stops at the first character that is
  /// neither, so `> [!TIP]` is depth 1 and `>  a` (two spaces) keeps the
  /// second space as content. Only quote lines pay the small allocation.
  static MarkdownQuoteShape? quoteMarkers(String line) {
    final n = line.length;
    var i = 0;
    while (i < n) {
      final c = line.codeUnitAt(i);
      if (c != _space && c != _tab) break;
      i++;
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

  /// Maps a `[!TYPE]` token (case-insensitive, surrounding spaces
  /// ignored) to a [MarkdownCalloutType], or `null` when unrecognised so
  /// an unknown `[!FOO]` stays a plain blockquote instead of a callout.
  static MarkdownCalloutType? typeFromToken(String token) {
    switch (token.trim().toLowerCase()) {
      case 'note':
        return MarkdownCalloutType.note;
      case 'tip':
        return MarkdownCalloutType.tip;
      case 'important':
        return MarkdownCalloutType.important;
      case 'warning':
        return MarkdownCalloutType.warning;
      case 'caution':
        return MarkdownCalloutType.caution;
      case 'success':
        return MarkdownCalloutType.success;
      case 'pr':
        return MarkdownCalloutType.pr;
      default:
        return null;
    }
  }

  /// Tries to parse [line] as a callout lead line (`> [!TYPE]` with an
  /// optional trailing title). Returns `null` when the line is not a
  /// recognised callout lead, so plain blockquotes are untouched.
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

    final type = typeFromToken(trimmed.substring(i + 2, close));
    if (type == null) return null;

    int t = close + 1;
    while (t < trimmed.length && trimmed.codeUnitAt(t) == _space) {
      t++;
    }
    return MarkdownCalloutLead(
      type: type,
      title: trimmed.substring(t).trimRight(),
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
    }
  }
}
