import 'package:flutter/widgets.dart' show StringCharacters;

/// Cuts text to a column's length, counted in UTF-16 code units — the unit
/// Drift's `withLength` checks — on whole user-perceived characters, so a
/// cut never leaves half of a surrogate pair, an accent without its letter
/// or the dangling joiner of an emoji sequence.
abstract final class TextFit {
  /// [text] itself when it fits [limit] code units, else its longest prefix
  /// of whole characters that does.
  ///
  /// When not even its first character fits — one letter under hundreds of
  /// combining marks — its longest prefix of code units that keeps a
  /// surrogate pair whole: a name that is one enormous character keeps what
  /// fits of it rather than nothing, which a column that needs one character
  /// would refuse.
  static String cut(String text, int limit) {
    if (text.length <= limit) return text;
    final kept = StringBuffer();
    var length = 0;
    for (final character in text.characters) {
      length += character.length;
      if (length > limit) break;
      kept.write(character);
    }
    if (kept.isNotEmpty || limit <= 0) return kept.toString();
    final last = text.codeUnitAt(limit - 1);
    final splitsPair = last >= 0xD800 && last <= 0xDBFF;
    return text.substring(0, splitsPair ? limit - 1 : limit);
  }

  /// [base] cut so that it and [suffix] together fit [limit]. A [suffix]
  /// longer than [limit] on its own comes back alone, cut to [limit]: the
  /// result never passes the limit.
  static String withSuffix(String base, String suffix, int limit) {
    if (suffix.length > limit) return cut(suffix, limit);
    return '${cut(base, limit - suffix.length)}$suffix';
  }
}
