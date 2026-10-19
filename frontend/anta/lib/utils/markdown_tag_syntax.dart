/// Shared, widget-free grammar for inline `#tag` tokens.
///
/// This is the single source of truth consumed by both the preview
/// renderer ([LineBasedMarkdownBuilder]) and the live editor span builder
/// ([MarkdownEditorSpanBuilder]), so the two surfaces can never disagree
/// about what is a tag — mirroring how [MarkdownListSyntax],
/// [MarkdownCalloutSyntax], and [GhostText] are each a single source of
/// truth.
///
/// A tag is `#` at a word boundary followed by a body of letters,
/// combining marks, numbers, `_`, `-` and inner `/` (`#program/5x5`),
/// Unicode-aware so accented / non-Latin tags stay intact. The body
/// starts with a letter or a digit and holds at least one letter, so
/// `#5x5` and `#1rm` are tags while `#3` / `set #1` / `#123` never are.
library;

/// Pure functions describing the `#tag` grammar.
class MarkdownTagSyntax {
  MarkdownTagSyntax._();

  /// Matches a single Unicode letter (any script), so `#tag` accepts
  /// accented / non-Latin letters — de: ä ö ü ß, ro: ă â î ș ț, etc. —
  /// not just ASCII a–z. ASCII is fast-pathed in [isLetter]; this regex
  /// only runs for non-ASCII code units, and a lone surrogate simply
  /// yields no match (BMP letters cover every supported language).
  static final RegExp _unicodeLetterRe = RegExp(r'\p{L}', unicode: true);

  /// Matches one Unicode "tag-body" code unit: a letter (`L`), combining
  /// mark (`M`), or number (`N`) of any script. Beyond [_unicodeLetterRe]
  /// this also keeps NFD-decomposed accents (base letter + combining
  /// mark, e.g. `a` + U+0301) and non-ASCII digits inside a tag. ASCII is
  /// fast-pathed in [isTagChar]; this only runs for non-ASCII code units.
  static final RegExp _unicodeTagBodyRe = RegExp(
    r'[\p{L}\p{M}\p{N}]',
    unicode: true,
  );

  static bool _isAsciiAlphaNumeric(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A); // a-z

  static bool isLetter(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c > 0x7F && _unicodeLetterRe.hasMatch(String.fromCharCode(c)));

  /// Characters allowed in a `#tag` body (after the letter-led start):
  /// ASCII letters/digits, `_`, `-`, and any Unicode letter / combining
  /// mark / number (so accented, NFD, and non-Latin tags stay intact).
  static bool isTagChar(int c) =>
      _isAsciiAlphaNumeric(c) ||
      c == 0x5F /* _ */ ||
      c == 0x2D /* - */ ||
      (c > 0x7F && _unicodeTagBodyRe.hasMatch(String.fromCharCode(c)));

  /// Whether the character before [i] is a word boundary, so an inline
  /// token (`#tag`, bare autolink) may start here. ASCII alphanumerics
  /// AND Unicode letters count as word characters, so a `#` glued to an
  /// accented word (`café#x`) is not a tag — matching the Unicode-aware
  /// tag body in [isTagChar].
  static bool isWordBoundaryBefore(String text, int i) {
    if (i == 0) return true;
    final prev = text.codeUnitAt(i - 1);
    return !_isAsciiAlphaNumeric(prev) && !isLetter(prev);
  }

  /// Returns the end index (exclusive) of a `#tag` starting at the `#`
  /// at [i], or `null` when it is not a tag. The body starts with a
  /// letter or a digit and must hold a letter somewhere, so set numbers
  /// and counts (`set #1`, `#123`) stay prose while `#5x5` is a tag. A
  /// `/` belongs to the body only between tag characters, so a sentence
  /// ending `#a/` or a path-like `#a//b` keeps its slash as text.
  static int? tryParseTagAt(String text, int i) {
    final n = text.length;
    final firstIdx = i + 1;
    if (firstIdx >= n) return null;
    final first = text.codeUnitAt(firstIdx);
    var sawLetter = isLetter(first);
    if (!sawLetter && !_isDigit(first)) return null;
    int j = firstIdx + 1;
    while (j < n) {
      final c = text.codeUnitAt(j);
      if (c == 0x2F /* / */ ) {
        if (j + 1 < n && isTagChar(text.codeUnitAt(j + 1))) {
          j++;
          continue;
        }
        break;
      }
      if (!isTagChar(c)) break;
      if (!sawLetter) sawLetter = isLetter(c);
      j++;
    }
    return sawLetter ? j : null;
  }

  /// Matches one non-ASCII Unicode number, so a digit-led body accepts
  /// the same digits [isTagChar] does inside a tag.
  static final RegExp _unicodeDigitRe = RegExp(r'\p{N}', unicode: true);

  static bool _isDigit(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c > 0x7F && _unicodeDigitRe.hasMatch(String.fromCharCode(c)));
}
