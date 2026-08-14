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

/// Pure functions describing the callout grammar.
class MarkdownCalloutSyntax {
  MarkdownCalloutSyntax._();

  static const int _gt = 0x3E; // >
  static const int _space = 0x20; // ' '
  static const int _openBracket = 0x5B; // [
  static const int _bang = 0x21; // !

  /// Whether [line] is a blockquote line (optional indent + `>`). A
  /// callout block continues for as long as following lines are
  /// blockquote lines; the first non-blockquote line ends it.
  static bool isBlockquoteLine(String line) {
    final trimmed = line.trimLeft();
    return trimmed.isNotEmpty && trimmed.codeUnitAt(0) == _gt;
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
