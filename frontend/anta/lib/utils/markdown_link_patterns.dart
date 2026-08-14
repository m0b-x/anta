/// Link grammar shared between the preview renderer (which turns
/// matches into tappable spans), the paste line-breaker (which protects
/// matches from being split mid-URL), the live editor span builder
/// (which tints matches in place), and the editor's tap interception
/// (which resolves whether a tap landed on a concealed link).
///
/// Keeping a single source of truth for the bare-URL character class
/// guarantees that anything the preview will render as a link is also
/// preserved as one unbroken token after a paste reformat, and styled
/// with the same extent in the live editor. Drift between the regexes
/// used to manifest as URLs that rendered as links in preview mode but
/// got chopped into fragments during paste, leaving only the first
/// fragment clickable.
/// A matched inline `[text](url)` link with source offsets.
class MarkdownInlineLink {
  /// Index of the opening `[`.
  final int start;

  /// Index of the `]` closing the link text.
  final int textEnd;

  /// Index of the `)` closing the url.
  final int urlEnd;

  const MarkdownInlineLink({
    required this.start,
    required this.textEnd,
    required this.urlEnd,
  });

  /// Index where the link text begins (just past the `[`).
  int get textStart => start + 1;

  /// Index where the url begins (just past the `(`).
  int get urlStart => textEnd + 2;

  /// Index just past the closing `)`.
  int get end => urlEnd + 1;

  /// The raw url between the parens of [line].
  String urlOf(String line) => line.substring(urlStart, urlEnd);
}

class MarkdownLinkPatterns {
  MarkdownLinkPatterns._();

  /// Tries to parse a `[text](url)` link whose `[` sits at [open]:
  /// the first `]` closes the text, a `(` must follow immediately, the
  /// first `)` closes the url, and both parts are non-empty. The whole
  /// construct must close before [limit] (defaults to the line end), so
  /// callers scanning inside an inline segment never match past it.
  ///
  /// Image syntax is the caller's concern: this matcher does not look at
  /// what precedes [open], because the preview treats a mid-line
  /// `![alt](url)` as `!` + link while the live editor leaves it raw.
  static MarkdownInlineLink? matchInlineLinkAt(
    String text,
    int open, [
    int? limit,
  ]) {
    final max = limit ?? text.length;
    final closeBracket = text.indexOf(']', open + 1);
    if (closeBracket <= open + 1) return null;
    if (closeBracket + 1 >= max) return null;
    if (text.codeUnitAt(closeBracket + 1) != 0x28) return null;
    final closeParen = text.indexOf(')', closeBracket + 2);
    if (closeParen <= closeBracket + 2) return null;
    if (closeParen >= max) return null;
    return MarkdownInlineLink(
      start: open,
      textEnd: closeBracket,
      urlEnd: closeParen,
    );
  }

  /// Bare autolink character class.
  ///
  /// Matches `http://...`, `https://...`, or `www....` URLs that stop at
  /// whitespace or the bracket/paren/angle characters that commonly
  /// terminate a URL inside prose. Trailing punctuation is stripped by
  /// [matchBareUrlEnd] when the match is converted to a styled span.
  static final RegExp bareUrl = RegExp(
    r'https?://[^\s<>()\[\]]+|www\.[^\s<>()\[\]]+',
  );

  /// GFM-style trailing punctuation trimmed from bare autolinks so a
  /// sentence like `see https://example.com.` doesn't include the
  /// period: `.` `,` `;` `:` `!` `?` `)` `]` `'` `"`.
  static bool isTrailingPunctuation(int codeUnit) =>
      codeUnit == 0x2E ||
      codeUnit == 0x2C ||
      codeUnit == 0x3B ||
      codeUnit == 0x3A ||
      codeUnit == 0x21 ||
      codeUnit == 0x3F ||
      codeUnit == 0x29 ||
      codeUnit == 0x5D ||
      codeUnit == 0x27 ||
      codeUnit == 0x22;

  /// Returns the end (exclusive) of a bare autolink opening at [start],
  /// or `-1`. Matches [bareUrl] anchored at [start], clamps to [limit]
  /// when given (so a URL inside an inline segment never styles past the
  /// segment's closing marker), trims trailing punctuation, and requires
  /// at least one character beyond the `http(s)://` / `www.` prefix to
  /// survive the trim — a bare scheme is never a link.
  static int matchBareUrlEnd(String text, int start, [int? limit]) {
    final int prefix;
    if (text.startsWith('https://', start)) {
      prefix = 8;
    } else if (text.startsWith('http://', start)) {
      prefix = 7;
    } else if (text.startsWith('www.', start)) {
      prefix = 4;
    } else {
      return -1;
    }
    final match = bareUrl.matchAsPrefix(text, start);
    if (match == null) return -1;
    var end = match.end;
    final max = limit ?? text.length;
    if (end > max) end = max;
    while (end > start && isTrailingPunctuation(text.codeUnitAt(end - 1))) {
      end--;
    }
    return end - start > prefix ? end : -1;
  }
}
