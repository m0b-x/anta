/// Link grammar shared between the preview renderer (which turns
/// matches into tappable spans), the paste line-breaker (which protects
/// matches from being split mid-URL), the live editor span builder
/// (which tints matches in place), and the editor's tap interception
/// (which resolves whether a tap landed on a concealed link).
///
/// Three link shapes live here: the `[text](url)` construct, the bare
/// autolink character class, and the `[[title]]` wiki link that points
/// at another note by its title.
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

/// A matched `[[title]]` wiki link with source offsets.
///
/// The title is the whole payload: there is no separate target, so what
/// the reader sees between the brackets is exactly the note title the
/// link resolves against.
class MarkdownWikiLink {
  /// Index of the first `[` of the opening `[[`.
  final int start;

  /// Index where the title begins, just past the `[[`.
  final int titleStart;

  /// Index of the first `]` of the closing `]]`.
  final int titleEnd;

  const MarkdownWikiLink({
    required this.start,
    required this.titleStart,
    required this.titleEnd,
  });

  /// Index just past the closing `]]`.
  int get end => titleEnd + 2;

  /// The raw title between the brackets of [line] — the lookup key,
  /// exactly as typed.
  String titleOf(String line) => line.substring(titleStart, titleEnd);
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

  /// Tries to parse a `[[title]]` wiki link whose first `[` sits at
  /// [open]: `[[` opens it, the title is the run up to the first `]`,
  /// and a second `]` must close it before [limit] (defaults to the line
  /// end) — so `[[a]]]` is a wiki link followed by a literal `]`.
  ///
  /// The title is a flat run: no `[`, `]`, `|`, CR or LF may appear in
  /// it, and at least one unit must be neither a space nor a tab, so
  /// `[[]]` and `[[ ]]` stay literal. `|` is reserved rather than used —
  /// excluding it now means an alias form can be added later without
  /// re-reading anything already typed as a title.
  ///
  /// Bounds safety: the scan never reads a code unit at or past [limit]
  /// at all, where [matchInlineLinkAt] probes with `indexOf` first and
  /// rejects the hit afterwards.
  ///
  /// Range/substring equality is a separate property, and one both
  /// matchers hold: matching inside `[open, limit)` of a line answers
  /// exactly what matching the corresponding substring answers. Here
  /// that follows from never reading past [limit]; in
  /// [matchInlineLinkAt] it follows from checking every `indexOf` hit
  /// against [limit] before using it. The grammar suite's
  /// `expectRangeEdge` pins it for both.
  static MarkdownWikiLink? matchWikiLinkAt(
    String text,
    int open, [
    int? limit,
  ]) {
    final max = limit ?? text.length;
    if (open < 0 || open + 1 >= max) return null;
    if (text.codeUnitAt(open) != _kOpenBracket) return null;
    if (text.codeUnitAt(open + 1) != _kOpenBracket) return null;
    final titleStart = open + 2;
    var hasContent = false;
    for (int i = titleStart; i < max; i++) {
      final int c = text.codeUnitAt(i);
      if (c == _kCloseBracket) {
        if (!hasContent) return null;
        if (i + 1 >= max) return null;
        if (text.codeUnitAt(i + 1) != _kCloseBracket) return null;
        return MarkdownWikiLink(
          start: open,
          titleStart: titleStart,
          titleEnd: i,
        );
      }
      if (c == _kOpenBracket ||
          c == _kPipe ||
          c == _kNewline ||
          c == _kReturn) {
        return null;
      }
      if (c != _kSpace && c != _kTab) hasContent = true;
    }
    return null;
  }

  static const int _kTab = 0x09;
  static const int _kNewline = 0x0A;
  static const int _kReturn = 0x0D;
  static const int _kSpace = 0x20;
  static const int _kOpenBracket = 0x5B;
  static const int _kCloseBracket = 0x5D;
  static const int _kPipe = 0x7C;

  /// The `[[title]]` *protection* shape, for the paste reformatter's
  /// width line-breaker alone: a wiki link holds spaces, so without a
  /// protected range `see [[the docs]] for more` breaks into
  /// `see [[the` / `docs]] for more` and the link is gone.
  ///
  /// Deliberately a superset of what [matchWikiLinkAt] accepts — it also
  /// matches a blank title, which is never a link — because the two
  /// errors are not symmetric: protecting a non-link costs one unbroken
  /// run of text, splitting a link costs the link. It is never a render
  /// or tap rule; what a wiki link *is* comes from [matchWikiLinkAt] and
  /// the inline grammar's placement pass, and nothing else may read this.
  static final RegExp wikiLink = RegExp(r'\[\[[^\[\]|\r\n]*\]\]');

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
  ///
  /// The emphasis markers `*` `_` `~` are trimmed too, as GFM's autolink
  /// extension does, so a URL wrapped in `*…*`, `**…**`, `~~…~~` or
  /// `_…_` gives its closing delimiter back to the emphasis instead of
  /// swallowing it — the inline grammar would otherwise see an unpaired
  /// opener and render the whole run raw. `=` is deliberately *not*
  /// trimmed: base64 `==` padding in a query string is real.
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
      codeUnit == 0x22 ||
      codeUnit == 0x2A ||
      codeUnit == 0x5F ||
      codeUnit == 0x7E;

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
