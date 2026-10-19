/// Link grammar shared between the preview renderer (which turns
/// matches into tappable spans), the paste line-breaker (which protects
/// matches from being split mid-URL), the live editor span builder
/// (which tints matches in place), and the editor's tap interception
/// (which resolves whether a tap landed on a concealed link).
///
/// Four link shapes live here: the `[text](url)` construct, the bare
/// autolink character class, the `<scheme:…>` / `<name@host.tld>` angle
/// autolink, and the `[[title]]` wiki link that points at another note
/// by its title.
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

  /// Index where the destination begins: past the `(`, any blanks after
  /// it, and the `<` of an angle destination.
  final int destStart;

  /// Index just past the destination: before the `>` of an angle
  /// destination, and before the blanks and the title that may follow.
  final int destEnd;

  const MarkdownInlineLink({
    required this.start,
    required this.textEnd,
    required this.urlEnd,
    required this.destStart,
    required this.destEnd,
  });

  /// Index where the link text begins (just past the `[`).
  int get textStart => start + 1;

  /// Index where the url begins (just past the `(`).
  int get urlStart => textEnd + 2;

  /// Index just past the closing `)`.
  int get end => urlEnd + 1;

  /// The destination of [line] — what a tap opens, never the title and
  /// never the angle brackets around it.
  String urlOf(String line) => line.substring(destStart, destEnd);
}

/// A matched `<https://…>` or `<name@host.tld>` angle autolink with
/// source offsets. Its inside is literal: what is shown is what opens.
class MarkdownAutolink {
  /// Index of the opening `<`.
  final int start;

  /// Index of the closing `>`.
  final int innerEnd;

  /// Whether the inside is a bare address, which opens as `mailto:`.
  final bool isEmail;

  const MarkdownAutolink({
    required this.start,
    required this.innerEnd,
    required this.isEmail,
  });

  /// Index just past the `<`.
  int get innerStart => start + 1;

  /// Index just past the closing `>`.
  int get end => innerEnd + 1;
}

/// A matched `[[title]]` or `[[title|alias]]` wiki link with source
/// offsets.
///
/// The title is the lookup key; the alias, when there is one, is only
/// what the reader sees in its place.
class MarkdownWikiLink {
  /// Index of the first `[` of the opening `[[`.
  final int start;

  /// Index where the title begins, just past the `[[`.
  final int titleStart;

  /// Index just past the title: the `|` of an alias form, otherwise the
  /// first `]` of the closing `]]`.
  final int titleEnd;

  /// Index just past the `|` when the alias holds a non-blank unit, or
  /// null — `[[a|]]` and `[[a| ]]` show their title like `[[a]]` does.
  final int? aliasStart;

  /// Index of the first `]` of the closing `]]`.
  final int closeStart;

  const MarkdownWikiLink({
    required this.start,
    required this.titleStart,
    required this.titleEnd,
    required this.closeStart,
    this.aliasStart,
  });

  /// Index just past the closing `]]`.
  int get end => closeStart + 2;

  /// The raw title between the brackets of [line] — the lookup key,
  /// exactly as typed.
  String titleOf(String line) => line.substring(titleStart, titleEnd);
}

/// What a `[[wiki link]]` title points at once Obsidian's suffixes are
/// read: the note, and the heading inside it to land on.
///
/// The suffixes are `#heading`, `#^block` / `^block` and a trailing
/// `.md`. Block ids are not tracked anywhere, so a block reference opens
/// its note and lands nowhere in particular.
class MarkdownWikiTarget {
  /// The trimmed title exactly as typed — always looked up first, so a
  /// note whose own name holds a `#` or a `^` keeps resolving.
  final String title;

  /// The note part: [title] cut at its first `#` or `^`, trimmed, with a
  /// trailing `.md` dropped. Empty for `[[#heading]]`, which names the
  /// note it is written in.
  final String note;

  /// The heading to centre on, or null: the last `#` segment of the
  /// fragment, so `[[Note#Week#Day 1]]` lands on `Day 1` as Obsidian's
  /// heading paths do.
  final String? heading;

  /// The whole fragment after the first `#` — cut at a `^` block
  /// reference, trimmed — or null. A heading that itself holds a `#`
  /// (`## Week #3`, `## C# basics`) is only found by this reading, so
  /// a caller tries it before [heading]; the two are equal when the
  /// fragment holds no further `#`.
  final String? wholeHeading;

  const MarkdownWikiTarget({
    required this.title,
    required this.note,
    this.heading,
    this.wholeHeading,
  });

  /// Whether reading the suffixes changed what to look up.
  bool get hasSuffix => note != title;

  /// Looks the target up through [lookup]: [title] as typed first, then,
  /// when that names nothing and a suffix was read, [note]. The record's
  /// flag says the note part found it — only then does [wholeHeading]
  /// apply. The editor page and the event sheets resolve in this order.
  Future<(T?, bool)> resolve<T extends Object>(
    Future<T?> Function(String title) lookup,
  ) async {
    final byTitle = await lookup(title);
    if (byTitle != null || !hasSuffix || note.isEmpty) return (byTitle, false);
    final byNote = await lookup(note);
    return (byNote, byNote != null);
  }

  /// Reads [rawTitle] — the title a tapped link hands over, untrimmed.
  static MarkdownWikiTarget parse(String rawTitle) {
    final title = rawTitle.trim();
    var cut = title.length;
    for (int i = 0; i < title.length; i++) {
      final int c = title.codeUnitAt(i);
      if (c == 0x23 || c == 0x5E) {
        cut = i;
        break;
      }
    }
    var note = title.substring(0, cut).trim();
    if (note.length > 3 && note.toLowerCase().endsWith('.md')) {
      note = note.substring(0, note.length - 3).trimRight();
    }
    String? heading;
    String? wholeHeading;
    if (cut < title.length && title.codeUnitAt(cut) == 0x23) {
      final fragment = title.substring(cut + 1);
      if (!fragment.startsWith('^')) {
        final segment = fragment.substring(fragment.lastIndexOf('#') + 1);
        final int caret = segment.indexOf('^');
        final text = (caret < 0 ? segment : segment.substring(0, caret)).trim();
        if (text.isNotEmpty) heading = text;
        final int wholeCaret = fragment.indexOf('^');
        final whole =
            (wholeCaret < 0 ? fragment : fragment.substring(0, wholeCaret))
                .trim();
        if (whole.isNotEmpty) wholeHeading = whole;
      }
    }
    return MarkdownWikiTarget(
      title: title,
      note: note,
      heading: heading,
      wholeHeading: wholeHeading,
    );
  }

  /// The texts a heading [fragment] (a [wholeHeading]) is looked up by,
  /// in order: the whole fragment, then its last `#` segment when that
  /// differs — so `Week #3` finds `## Week #3` and `Week 1#Day 2` still
  /// lands on `## Day 2`.
  static List<String> headingReadingsOf(String fragment) {
    final whole = fragment.trim();
    final last = whole.substring(whole.lastIndexOf('#') + 1).trim();
    return [
      if (whole.isNotEmpty) whole,
      if (last.isNotEmpty && last != whole) last,
    ];
  }
}

class MarkdownLinkPatterns {
  MarkdownLinkPatterns._();

  /// The picture glyph both surfaces show in place of the `!` of an
  /// `![alt](url)` image or a `![[file]]` embed — images are never
  /// loaded inline, so this is all of the image there is. One UTF-16
  /// code unit, so the editor substitutes it for the `!` 1:1.
  static const String imageGlyph = '▣';

  /// Tries to parse a `[text](url)` link whose `[` sits at [open]:
  /// the first `]` closes the text, a `(` must follow immediately, and
  /// both parts are non-empty. The whole construct must close before
  /// [limit] (defaults to the line end), so callers scanning inside an
  /// inline segment never match past it.
  ///
  /// Inside the parens the destination is read as CommonMark does: an
  /// angle form `<…>` (no line break, no `<`), or a run without blanks
  /// whose parentheses balance — so `…/Foo_(bar))` keeps its last `)` —
  /// optionally followed by blanks and a `"…"`, `'…'` or `(…)` title
  /// before the closing `)`. Blanks right after the `(` are skipped.
  ///
  /// A backslash escapes the unit after it in the destination run and in
  /// the title, so `"say \"hi\""` is one title and `a\)b` one run.
  ///
  /// When that reading fails the link still closes at the first `)`, as
  /// every link did before destinations were read: no line that rendered
  /// a link stops rendering one, and an unbalanced `(` still ends the
  /// link there. Its destination is then the inside's first blank-free
  /// run — never a title the reading could not close.
  ///
  /// Image syntax is the caller's concern: this matcher does not look at
  /// what precedes [open], because `![alt](url)` is an image only when
  /// the grammar sees the `!`.
  static MarkdownInlineLink? matchInlineLinkAt(
    String text,
    int open, [
    int? limit,
  ]) => _matchLink(text, open, limit ?? text.length, false);

  /// [matchInlineLinkAt] for the bracket of an `![alt](url)` image, which
  /// may leave its alt empty: `![](url)` is the form pasted screenshots
  /// and exports carry, while `[](url)` stays literal text.
  static MarkdownInlineLink? matchImageAt(
    String text,
    int open, [
    int? limit,
  ]) => _matchLink(text, open, limit ?? text.length, true);

  static MarkdownInlineLink? _matchLink(
    String text,
    int open,
    int max,
    bool allowEmptyText,
  ) {
    final closeBracket = text.indexOf(']', open + 1);
    if (closeBracket < 0) return null;
    if (!allowEmptyText && closeBracket == open + 1) return null;
    if (closeBracket + 1 >= max) return null;
    if (text.codeUnitAt(closeBracket + 1) != 0x28) return null;
    final read = _readDestination(text, open, closeBracket, max);
    if (read != null) return read;
    final closeParen = text.indexOf(')', closeBracket + 2);
    if (closeParen <= closeBracket + 2) return null;
    if (closeParen >= max) return null;
    // The fallback's destination is its first blank-free run, so a title
    // the reading could not close (`'Bob's guide'`) is never opened.
    final destStart = _skipBlanks(text, closeBracket + 2, closeParen);
    var destEnd = destStart;
    while (destEnd < closeParen && text.codeUnitAt(destEnd) > _kSpace) {
      destEnd++;
    }
    return MarkdownInlineLink(
      start: open,
      textEnd: closeBracket,
      urlEnd: closeParen,
      destStart: destStart,
      destEnd: destEnd,
    );
  }

  /// Reads a CommonMark destination and optional title from just past
  /// the `(` that follows [closeBracket] up to the closing `)`, never
  /// reading at or past [max]. Null when the inside is not of that shape
  /// — an empty destination included — which leaves the decision to the
  /// first-`)` fallback.
  static MarkdownInlineLink? _readDestination(
    String text,
    int open,
    int closeBracket,
    int max,
  ) {
    int p = _skipBlanks(text, closeBracket + 2, max);
    if (p >= max) return null;
    final int destStart;
    final int destEnd;
    if (text.codeUnitAt(p) == _kLessThan) {
      int q = p + 1;
      while (q < max) {
        final int c = text.codeUnitAt(q);
        if (c == _kGreaterThan) break;
        if (c == _kLessThan || c == _kNewline || c == _kReturn) return null;
        q++;
      }
      if (q >= max || q == p + 1) return null;
      destStart = p + 1;
      destEnd = q;
      p = q + 1;
    } else {
      int depth = 0;
      int q = p;
      while (q < max) {
        final int c = text.codeUnitAt(q);
        if (c <= _kSpace) break;
        if (c == _kBackslash &&
            q + 1 < max &&
            text.codeUnitAt(q + 1) > _kSpace) {
          q += 2;
          continue;
        }
        if (c == _kOpenParen) {
          depth++;
        } else if (c == _kCloseParen) {
          if (depth == 0) break;
          depth--;
        }
        q++;
      }
      if (depth != 0 || q == p) return null;
      destStart = p;
      destEnd = q;
      p = q;
    }
    final int afterDest = p;
    p = _skipBlanks(text, p, max);
    if (p >= max) return null;
    final int c = text.codeUnitAt(p);
    if (p > afterDest &&
        (c == _kDoubleQuote || c == _kSingleQuote || c == _kOpenParen)) {
      final int closer = c == _kOpenParen ? _kCloseParen : c;
      int q = p + 1;
      while (q < max && text.codeUnitAt(q) != closer) {
        final int t = text.codeUnitAt(q);
        if (c == _kOpenParen && t == _kOpenParen) return null;
        q += t == _kBackslash && q + 1 < max ? 2 : 1;
      }
      if (q >= max) return null;
      p = _skipBlanks(text, q + 1, max);
      if (p >= max) return null;
    }
    if (text.codeUnitAt(p) != _kCloseParen) return null;
    return MarkdownInlineLink(
      start: open,
      textEnd: closeBracket,
      urlEnd: p,
      destStart: destStart,
      destEnd: destEnd,
    );
  }

  /// The first index at or after [from] that is neither a space nor a
  /// tab, or [max].
  static int _skipBlanks(String text, int from, int max) {
    int p = from;
    while (p < max) {
      final int c = text.codeUnitAt(p);
      if (c != _kSpace && c != _kTab) break;
      p++;
    }
    return p;
  }

  /// Tries to parse a `[[title]]` wiki link whose first `[` sits at
  /// [open]: `[[` opens it, the title is the run up to the first `]`,
  /// and a second `]` must close it before [limit] (defaults to the line
  /// end) — so `[[a]]]` is a wiki link followed by a literal `]`.
  ///
  /// The title is a flat run: no `[`, `]`, `|`, CR or LF may appear in
  /// it, and at least one unit must be neither a space nor a tab, so
  /// `[[]]` and `[[ ]]` stay literal.
  ///
  /// One `|` after a non-blank title opens the alias, Obsidian's
  /// `[[title|alias]]`: the alias is a flat run under the same rules,
  /// a second `|` included, so `[[a|b|c]]` stays literal. A blank alias
  /// is no alias — `[[a|]]` is a link to `a` that shows `a`.
  ///
  /// Bounds safety: the scan never reads a code unit at or past [limit]
  /// at all, where [matchInlineLinkAt] probes for the text's `]` with
  /// `indexOf` first and rejects the hit afterwards.
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
    var pipe = -1;
    var aliasHasContent = false;
    for (int i = titleStart; i < max; i++) {
      final int c = text.codeUnitAt(i);
      if (c == _kCloseBracket) {
        if (!hasContent) return null;
        if (i + 1 >= max) return null;
        if (text.codeUnitAt(i + 1) != _kCloseBracket) return null;
        return MarkdownWikiLink(
          start: open,
          titleStart: titleStart,
          titleEnd: pipe < 0 ? i : pipe,
          closeStart: i,
          aliasStart: aliasHasContent ? pipe + 1 : null,
        );
      }
      if (c == _kPipe) {
        if (pipe >= 0 || !hasContent) return null;
        pipe = i;
        continue;
      }
      if (c == _kOpenBracket || c == _kNewline || c == _kReturn) {
        return null;
      }
      if (c != _kSpace && c != _kTab) {
        if (pipe < 0) {
          hasContent = true;
        } else {
          aliasHasContent = true;
        }
      }
    }
    return null;
  }

  /// Tries to parse an angle autolink whose `<` sits at [open], closed
  /// by the first `>` before [limit] (defaults to the line end): either
  /// a URI whose scheme is one the app opens — `http:`, `https:`,
  /// `mailto:`, `tel:`, any case, with something after the colon — or a
  /// bare address `name@host.tld` with at least one dot in the host.
  ///
  /// The inside holds no blank, control unit or `<`, so prose such as
  /// `a <b> c`, `x < y > z` or `<javascript:…>` stays literal. Like
  /// [matchWikiLinkAt] the scan never reads at or past [limit].
  static MarkdownAutolink? matchAutolinkAt(
    String text,
    int open, [
    int? limit,
  ]) {
    final max = limit ?? text.length;
    if (open < 0 || open >= max) return null;
    if (text.codeUnitAt(open) != _kLessThan) return null;
    final innerStart = open + 1;
    var close = -1;
    var colon = -1;
    for (int i = innerStart; i < max; i++) {
      final int c = text.codeUnitAt(i);
      if (c == _kGreaterThan) {
        close = i;
        break;
      }
      if (c <= _kSpace || c == _kLessThan || c == 0x7F) return null;
      if (c == _kColon && colon < 0) colon = i;
    }
    if (close <= innerStart) return null;
    if (colon > innerStart && colon + 1 < close) {
      for (final scheme in _autolinkSchemes) {
        if (_equalsIgnoreAsciiCase(text, innerStart, colon, scheme)) {
          return MarkdownAutolink(start: open, innerEnd: close, isEmail: false);
        }
      }
    }
    if (_isEmailAddress(text, innerStart, close)) {
      return MarkdownAutolink(start: open, innerEnd: close, isEmail: true);
    }
    return null;
  }

  /// The schemes an angle autolink may carry — exactly the ones the
  /// note editor's link opener accepts, so nothing renders as a link
  /// that a tap would then refuse.
  static const List<String> _autolinkSchemes = [
    'http',
    'https',
    'mailto',
    'tel',
  ];

  /// Whether `[start, end)` of [text] is [lower] in any ASCII case,
  /// compared in place: the tokenizer probes every `<` of a line, so
  /// nothing is allocated per candidate.
  static bool _equalsIgnoreAsciiCase(
    String text,
    int start,
    int end,
    String lower,
  ) {
    if (end - start != lower.length) return false;
    for (int i = 0; i < lower.length; i++) {
      final int c = text.codeUnitAt(start + i);
      final int folded = c >= 0x41 && c <= 0x5A ? c + 0x20 : c;
      if (folded != lower.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// Whether `[start, end)` is `local@host.tld`: a local part of letters,
  /// digits and `.!#$%&'*+/=?^_{|}~-`, one `@`, and a host of at least
  /// two dot-separated labels of letters, digits and inner hyphens.
  static bool _isEmailAddress(String text, int start, int end) {
    int at = start;
    while (at < end && text.codeUnitAt(at) != _kAt) {
      at++;
    }
    if (at <= start || at >= end - 1) return false;
    for (int i = start; i < at; i++) {
      if (!_isEmailLocalUnit(text.codeUnitAt(i))) return false;
    }
    var labels = 0;
    var labelStart = at + 1;
    for (int i = at + 1; i <= end; i++) {
      final int c = i < end ? text.codeUnitAt(i) : _kDot;
      if (c == _kDot) {
        if (i == labelStart) return false;
        if (text.codeUnitAt(labelStart) == _kHyphen) return false;
        if (text.codeUnitAt(i - 1) == _kHyphen) return false;
        labels++;
        labelStart = i + 1;
        continue;
      }
      if (!_isAsciiAlphanumeric(c) && c != _kHyphen) return false;
    }
    return labels >= 2;
  }

  static bool _isAsciiAlphanumeric(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A);

  /// Letters, digits and `.!#$%&'*+/=?^_{|}~-`.
  static bool _isEmailLocalUnit(int c) {
    if (_isAsciiAlphanumeric(c)) return true;
    switch (c) {
      case 0x2E || 0x21 || 0x23 || 0x24 || 0x25 || 0x26 || 0x27 || 0x2A:
      case 0x2B || 0x2F || 0x3D || 0x3F || 0x5E || 0x5F || 0x7B || 0x7C:
      case 0x7D || 0x7E || 0x2D:
        return true;
    }
    return false;
  }

  static const int _kTab = 0x09;
  static const int _kNewline = 0x0A;
  static const int _kReturn = 0x0D;
  static const int _kSpace = 0x20;
  static const int _kDoubleQuote = 0x22;
  static const int _kSingleQuote = 0x27;
  static const int _kOpenParen = 0x28;
  static const int _kCloseParen = 0x29;
  static const int _kHyphen = 0x2D;
  static const int _kDot = 0x2E;
  static const int _kColon = 0x3A;
  static const int _kLessThan = 0x3C;
  static const int _kGreaterThan = 0x3E;
  static const int _kAt = 0x40;
  static const int _kOpenBracket = 0x5B;
  static const int _kBackslash = 0x5C;
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
  /// The optional `|…` part covers the alias form, whose alias holds
  /// spaces just as often as a title does.
  static final RegExp wikiLink = RegExp(
    r'\[\[[^\[\]|\r\n]*(?:\|[^\[\]|\r\n]*)?\]\]',
  );

  /// Bare autolink character class.
  ///
  /// Matches `http://...`, `https://...`, or `www....` URLs that stop at
  /// whitespace or the bracket/angle characters that commonly terminate
  /// a URL inside prose. Parentheses stay in the class so the paste
  /// reformatter protects `…/Squat_(exercise)` whole; [matchBareUrlEnd]
  /// decides which of them belong to the link, and strips trailing
  /// punctuation, when the match is converted to a styled span.
  static final RegExp bareUrl = RegExp(
    r'https?://[^\s<>\[\]]+|www\.[^\s<>\[\]]+',
  );

  /// GFM-style trailing punctuation trimmed from bare autolinks so a
  /// sentence like `see https://example.com.` doesn't include the
  /// period: `.` `,` `;` `:` `!` `?` `]` `'` `"`. A `)` is not in the
  /// set: [matchBareUrlEnd] already ends a URL at a `)` that closes
  /// nothing, and one that closes a `(` of the URL is part of it.
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
      codeUnit == 0x5D ||
      codeUnit == 0x27 ||
      codeUnit == 0x22 ||
      codeUnit == 0x2A ||
      codeUnit == 0x5F ||
      codeUnit == 0x7E;

  /// Returns the end (exclusive) of a bare autolink opening at [start],
  /// or `-1`. Matches [bareUrl] anchored at [start], clamps to [limit]
  /// when given (so a URL inside an inline segment never styles past the
  /// segment's closing marker), keeps only balanced parentheses, trims
  /// trailing punctuation, and requires at least one character beyond
  /// the `http(s)://` / `www.` prefix to survive the trim — a bare
  /// scheme is never a link.
  ///
  /// Parentheses balance the way prose reads them: a `)` that closes no
  /// `(` of the URL ends it there, so `(see https://x.y).` gives the
  /// sentence its `)`, while `…/Squat_(exercise)` keeps its own; a `(`
  /// the URL never closes ends it before that `(`, exactly where the
  /// class used to stop.
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
    var depth = 0;
    var firstUnclosed = -1;
    for (int i = start + prefix; i < end; i++) {
      final int c = text.codeUnitAt(i);
      if (c == _kOpenParen) {
        if (depth == 0) firstUnclosed = i;
        depth++;
      } else if (c == _kCloseParen) {
        if (depth == 0) {
          end = i;
          break;
        }
        depth--;
      }
    }
    if (depth > 0) end = firstUnclosed;
    while (end > start && isTrailingPunctuation(text.codeUnitAt(end - 1))) {
      end--;
    }
    return end - start > prefix ? end : -1;
  }
}
