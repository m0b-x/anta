/// Shared definition and scanning of "ghost text" — an inline,
/// single-line placeholder syntax `{{ inner }}` that renders greyed and
/// is removed (markers + inner) when the user engages it.
///
/// This is the single source of truth consumed by:
///   * the preview renderer (greys the inner text, hides the markers),
///   * the editor span builder (greys the whole `{{ … }}` run),
///   * the editor tap-to-remove logic, and
///   * the toolbar "insert ghost" action.
///
/// Keeping one matcher here guarantees all surfaces agree on exactly
/// what is (and isn't) a ghost.
library;

/// A ghost match within a single line of text. All offsets are relative
/// to the scanned string.
///
/// `[start, end)` covers the whole run including the `{{` / `}}`
/// markers; `[innerStart, innerEnd)` covers just the text between them.
class GhostMatch {
  /// Offset of the first `{` of the opening `{{`.
  final int start;

  /// Offset just past the last `}` of the closing `}}`.
  final int end;

  /// Offset of the first inner character (just after `{{`).
  final int innerStart;

  /// Offset just past the last inner character (just before `}}`).
  final int innerEnd;

  const GhostMatch({
    required this.start,
    required this.end,
    required this.innerStart,
    required this.innerEnd,
  });

  /// Whether [offset] falls strictly inside the whole run (excluding the
  /// two outer edges). Used by the editor so a tap that merely lands at
  /// the boundary while positioning the caret next to a ghost does not
  /// delete it; only a tap clearly *on* the ghost does.
  bool containsStrict(int offset) => offset > start && offset < end;

  /// The inner text of this ghost within [source].
  String innerOf(String source) => source.substring(innerStart, innerEnd);
}

/// Ghost text syntax + scanning helpers.
class GhostText {
  GhostText._();

  /// Opening / closing markers. Two characters each; chosen to avoid
  /// collision with existing markdown (`*_~` `` ` `` `[]` `#` `>` `-`)
  /// and with single-brace counter tokens (`{c1}` / `{c2}`).
  static const String open = '{{';
  static const String close = '}}';

  static const int _kOpenBrace = 0x7B; // {
  static const int _kCloseBrace = 0x7D; // }

  /// Whether [text] could contain a ghost (cheap pre-check so hot paths
  /// can skip the full scan). Only checks for the opening marker.
  static bool mightContain(String text) => text.contains(open);

  /// Scans a single [line] for non-nested ghost runs, left to right.
  ///
  /// A ghost is `{{` … `}}` with at least one inner character and no
  /// newline (callers pass one line at a time). Matching is greedy-left:
  /// the first `{{` pairs with the first following `}}`. Empty `{{}}` is
  /// not a ghost (rendered literally). Returns matches in order; empty
  /// when there are none.
  static List<GhostMatch> findGhosts(String line) {
    if (line.length < 4) return const [];
    List<GhostMatch>? matches;
    int i = 0;
    final n = line.length;
    while (i < n - 1) {
      if (line.codeUnitAt(i) == _kOpenBrace &&
          line.codeUnitAt(i + 1) == _kOpenBrace) {
        final innerStart = i + 2;
        final closeIdx = _indexOfClose(line, innerStart);
        if (closeIdx != -1 && closeIdx > innerStart) {
          (matches ??= <GhostMatch>[]).add(
            GhostMatch(
              start: i,
              end: closeIdx + 2,
              innerStart: innerStart,
              innerEnd: closeIdx,
            ),
          );
          i = closeIdx + 2;
          continue;
        }
      }
      i++;
    }
    return matches ?? const [];
  }

  /// Returns the ghost in [line] that strictly contains [offset], or
  /// `null`. Used by the editor to decide whether a tap landed on a
  /// ghost.
  static GhostMatch? ghostAtOffset(String line, int offset) {
    for (final g in findGhosts(line)) {
      if (g.containsStrict(offset)) return g;
      if (g.start > offset) break; // matches are sorted
    }
    return null;
  }

  /// If a ghost run begins exactly at [i] in [text], returns its match
  /// (offsets relative to [text]); otherwise `null`. Used by the inline
  /// markdown parser, which scans character-by-character.
  static GhostMatch? matchAt(String text, int i) {
    final n = text.length;
    if (i < 0 || i + 1 >= n) return null;
    if (text.codeUnitAt(i) != _kOpenBrace ||
        text.codeUnitAt(i + 1) != _kOpenBrace) {
      return null;
    }
    final innerStart = i + 2;
    final closeIdx = _indexOfClose(text, innerStart);
    if (closeIdx == -1 || closeIdx <= innerStart) return null;
    return GhostMatch(
      start: i,
      end: closeIdx + 2,
      innerStart: innerStart,
      innerEnd: closeIdx,
    );
  }

  /// Wraps [selection] as ghost text for insertion. When empty, returns
  /// markers with the caret-friendly form `{{  }}`.
  static String wrap(String selection) {
    final trimmed = selection.trim();
    if (trimmed.isEmpty) return '$open  $close';
    return '$open $trimmed $close';
  }

  /// Index of the first `}}` at/after [from], or -1.
  static int _indexOfClose(String line, int from) {
    final n = line.length;
    for (int j = from; j < n - 1; j++) {
      if (line.codeUnitAt(j) == _kCloseBrace &&
          line.codeUnitAt(j + 1) == _kCloseBrace) {
        return j;
      }
    }
    return -1;
  }
}
