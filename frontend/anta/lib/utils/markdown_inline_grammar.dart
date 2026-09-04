import 'package:flutter/foundation.dart';

import '../constants/markdown_constants.dart';
import 'ghost_text.dart';
import 'markdown_color_syntax.dart';
import 'markdown_link_patterns.dart';
import 'markdown_tag_syntax.dart';

/// The one inline grammar both render surfaces consume — emphasis,
/// strikethrough, highlight, inline code, backslash escapes — together
/// with the placement rules for the constructs that already own their
/// own module (ghosts, `[text](url)` links, bare URLs, `#tag`s,
/// `{name:text}` colours). The preview drops markers, the live editor
/// conceals them, the editor's tap zones resolve against it; none of
/// them may re-scan for any of these constructs on their own.
///
/// [MarkdownInlineGrammar.tokenize] is a pure function of
/// `text.substring(start, end)` plus the ghost runs intersecting that
/// range: nothing outside the range is ever read, so the range edges
/// behave exactly like line edges. That is what lets the preview parse
/// substrings and the editor parse ranges of the full line and still
/// agree, and what lets a consumer recurse into a container's inner
/// range and find precisely the nested tokens the outer pass would
/// have nested there.
///
/// Rules (CommonMark-ish, tuned for one-line logs):
///
/// * Atoms bind first, left to right: an escape (`\` + ASCII
///   punctuation, unless that punctuation opens a ghost — ghosts win),
///   a ghost run (`{{ … }}`, from [GhostText]), and a code span (a
///   backtick run closed by the next run of exactly the same length,
///   skipping runs inside ghosts; an unclosed run is literal). Nothing
///   inside an atom is scanned again.
/// * Then, at each position outside an atom: `![text](url)` /
///   `[text](url)` (structural characters must not sit inside an atom),
///   `{name:text}` (its closing brace likewise), `#tag` and bare URLs at
///   a word boundary (a URL stops at the next atom), and delimiter runs
///   of `*`, `_`, `~~`, `==`.
/// * A run can open when the next character is not whitespace and can
///   close when the previous one is not; `_` runs additionally need a
///   non-word character (or the range edge) on the outside. Openers and
///   closers pair like CommonMark's delimiter stack (nearest opener of
///   the same character, the rule of three for `*` and `_`, delimiters
///   between a matched pair drop out), an opener spending from the end
///   of its run and a closer from the start, so `***a**` is a literal
///   `*` followed by bold. Three matched on both sides give one
///   bold-italic token. `~~`/`==` pair two at a time; leftovers are
///   literal.
/// * Only top-level tokens are returned. A consumer recurses into an
///   emphasis, link-text or colour range and finds the nested tokens
///   there; code spans are literal all the way down.
class MarkdownInlineGrammar {
  MarkdownInlineGrammar._();

  /// Containers deeper than this render their inner range plain:
  /// [tokenize] returns no tokens at all once `depth` reaches it, on
  /// both surfaces alike, so pathological nesting is bounded without
  /// the two renderers ever disagreeing about where the cut is.
  static const int maxNestingDepth = 8;

  /// Tokenizes `[start, end)` of [text]. [ghosts] are the ghost runs of
  /// the whole [text] (as [GhostText.findGhosts] returns them); when
  /// omitted they are computed from [text]. [palette] resolves colour
  /// names for `{name:text}` and `==name:text==`. Returns the top-level
  /// tokens in source order, non-overlapping, each within the range —
  /// or an empty list once [depth] reaches [maxNestingDepth].
  static List<InlineToken> tokenize(
    String text, {
    int start = 0,
    int? end,
    List<GhostMatch>? ghosts,
    required MarkdownColorPalette palette,
    int depth = 0,
  }) {
    if (depth >= maxNestingDepth) return const [];
    final int hi = end ?? text.length;
    if (start >= hi || !hasCandidates(text, start, hi)) return const [];
    final List<GhostMatch> runs =
        ghosts ??
        (GhostText.mightContain(text)
            ? GhostText.findGhosts(text)
            : const <GhostMatch>[]);

    final List<InlineToken>? atoms = _scanAtoms(text, start, hi, runs);
    final List<InlineToken> atomList = atoms ?? const <InlineToken>[];

    List<InlineToken>? constructs;
    List<_Delim>? delims;
    final int atomCount = atomList.length;
    int ai = 0;
    int p = start;
    while (p < hi) {
      while (ai < atomCount && atomList[ai].end <= p) {
        ai++;
      }
      if (ai < atomCount && atomList[ai].start <= p) {
        p = atomList[ai].end;
        ai++;
        continue;
      }
      final int nextAtom = ai < atomCount ? atomList[ai].start : hi;
      final int c = text.codeUnitAt(p);

      if (c == _kBang) {
        if (p + 1 < hi && text.codeUnitAt(p + 1) == _kOpenBracket) {
          final link = _tryLink(text, p, p + 1, hi, atomList, true);
          if (link != null) {
            (constructs ??= <InlineToken>[]).add(link);
            p = link.end;
            continue;
          }
        }
        p++;
        continue;
      }

      if (c == _kOpenBracket) {
        final link = _tryLink(text, p, p, hi, atomList, false);
        if (link != null) {
          (constructs ??= <InlineToken>[]).add(link);
          p = link.end;
          continue;
        }
        p++;
        continue;
      }

      if (c == _kOpenBrace) {
        final match = MarkdownColorSyntax.matchAt(text, p, palette, hi);
        if (match != null && !_inAtom(atomList, match.innerEnd)) {
          (constructs ??= <InlineToken>[]).add(
            InlineColor(
              start: p,
              end: match.end,
              innerStart: match.innerStart,
              innerEnd: match.innerEnd,
              spec: match.spec,
            ),
          );
          p = match.end;
          continue;
        }
        p++;
        continue;
      }

      if (c == _kHash) {
        if (p == start || MarkdownTagSyntax.isWordBoundaryBefore(text, p)) {
          final int? raw = MarkdownTagSyntax.tryParseTagAt(text, p);
          if (raw != null) {
            final int tagEnd = raw < hi ? raw : hi;
            if (tagEnd > p + 1) {
              (constructs ??= <InlineToken>[]).add(
                InlineTag(start: p, end: tagEnd),
              );
              p = tagEnd;
              continue;
            }
          }
        }
        p++;
        continue;
      }

      if (c == _kLowerH || c == _kLowerW) {
        if (p == start || MarkdownTagSyntax.isWordBoundaryBefore(text, p)) {
          final int urlEnd = MarkdownLinkPatterns.matchBareUrlEnd(
            text,
            p,
            nextAtom,
          );
          if (urlEnd >= 0) {
            (constructs ??= <InlineToken>[]).add(
              InlineUrl(start: p, end: urlEnd),
            );
            p = urlEnd;
            continue;
          }
        }
        p++;
        continue;
      }

      if (c == _kStar || c == _kUnderscore || c == _kTilde || c == _kEquals) {
        int r = p + 1;
        while (r < nextAtom && text.codeUnitAt(r) == c) {
          r++;
        }
        final int runLength = r - p;
        if ((c == _kTilde || c == _kEquals) && runLength < 2) {
          p = r;
          continue;
        }
        final int prev = p > start ? text.codeUnitAt(p - 1) : -1;
        final int next = r < hi ? text.codeUnitAt(r) : -1;
        bool canOpen = next != -1 && !isSpace(next);
        bool canClose = prev != -1 && !isSpace(prev);
        if (c == _kUnderscore) {
          if (canOpen && prev != -1 && isWordChar(prev)) canOpen = false;
          if (canClose && next != -1 && isWordChar(next)) canClose = false;
        }
        (delims ??= <_Delim>[]).add(
          _Delim(c, p, r, runLength, canOpen, canClose),
        );
        p = r;
        continue;
      }

      p++;
    }

    final List<InlineToken>? pairs = delims == null
        ? null
        : _pairDelimiters(text, delims, palette);

    final int count =
        atomCount + (constructs?.length ?? 0) + (pairs?.length ?? 0);
    if (count == 0) return const [];
    final List<InlineToken> all = <InlineToken>[];
    if (atoms != null) all.addAll(atoms);
    if (constructs != null) all.addAll(constructs);
    if (pairs != null) all.addAll(pairs);
    _sortTokens(all);

    int write = 0;
    int coverEnd = start;
    for (int i = 0; i < all.length; i++) {
      final InlineToken token = all[i];
      if (token.start < coverEnd) continue;
      coverEnd = token.end;
      all[write++] = token;
    }
    if (write != all.length) all.length = write;
    return all;
  }

  /// The `[text](url)` link (never an image) whose run strictly contains
  /// [offset] — `start < offset < end`, so the construct's outermost
  /// boundary offsets belong to caret placement — at any nesting depth,
  /// or `null`. Resolves against exactly what [tokenize] would render.
  static InlineLink? linkAt(
    String text,
    int offset, {
    required MarkdownColorPalette palette,
  }) {
    if (offset <= 0 || offset >= text.length) return null;
    final List<GhostMatch> ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];
    final InlineToken? found = _walk(
      text,
      0,
      text.length,
      ghosts,
      palette,
      0,
      offset,
      false,
    );
    return found is InlineLink ? found : null;
  }

  /// The `#tag` whose run strictly contains [offset] at any nesting
  /// depth, or `null`. Tags inside code spans and ghosts are not tags.
  static InlineTag? tagAt(
    String text,
    int offset, {
    required MarkdownColorPalette palette,
  }) {
    if (offset <= 0 || offset >= text.length) return null;
    final List<GhostMatch> ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];
    final InlineToken? found = _walk(
      text,
      0,
      text.length,
      ghosts,
      palette,
      0,
      offset,
      true,
    );
    return found is InlineTag ? found : null;
  }

  /// Whether `[start, end)` holds a code unit that can open any token —
  /// `* ~ ` _ = # [ \ {` or a bare-URL scheme lead (`ht`, `ww`; a lone
  /// `h`/`w` would defeat the check on every prose line). The one-pass
  /// quick reject in front of [tokenize], and the pre-check a renderer
  /// may use to skip inline work on the common construct-free line. An
  /// image's `!` needs no entry: it is a token only when `[` follows.
  static bool hasCandidates(String text, [int start = 0, int? end]) {
    final int hi = end ?? text.length;
    for (int i = start; i < hi; i++) {
      final int c = text.codeUnitAt(i);
      if (c == _kStar ||
          c == _kTilde ||
          c == _kBacktick ||
          c == _kUnderscore ||
          c == _kEquals ||
          c == _kHash ||
          c == _kOpenBracket ||
          c == _kBackslash ||
          c == _kOpenBrace) {
        return true;
      }
      if ((c == _kLowerH || c == _kLowerW) && i + 1 < hi) {
        final int n = text.codeUnitAt(i + 1);
        if ((c == _kLowerH && n == _kLowerT) ||
            (c == _kLowerW && n == _kLowerW)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Whitespace for flanking purposes.
  static bool isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  /// A word character for the `_` flanking rule: ASCII letters and
  /// digits, `_` itself, and every non-ASCII code unit — so `snake_case`
  /// and `ș_a_` alike never open emphasis.
  static bool isWordChar(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5F ||
      c > 0x7F;

  static const int _kBang = 0x21; // !
  static const int _kHash = 0x23; // #
  static const int _kStar = 0x2A; // *
  static const int _kEquals = 0x3D; // =
  static const int _kOpenBracket = 0x5B; // [
  static const int _kBackslash = 0x5C; // \
  static const int _kUnderscore = 0x5F; // _
  static const int _kBacktick = 0x60; // `
  static const int _kLowerH = 0x68; // h
  static const int _kLowerT = 0x74; // t
  static const int _kLowerW = 0x77; // w
  static const int _kOpenBrace = 0x7B; // {
  static const int _kTilde = 0x7E; // ~

  /// Phase 1: the opaque runs of `[start, hi)` — escapes, ghosts and
  /// code spans — in source order, or `null` when there are none.
  static List<InlineToken>? _scanAtoms(
    String text,
    int start,
    int hi,
    List<GhostMatch> ghosts,
  ) {
    List<InlineToken>? atoms;
    final int ghostCount = ghosts.length;
    int gi = 0;
    int p = start;
    while (p < hi) {
      while (gi < ghostCount && ghosts[gi].end <= p) {
        gi++;
      }
      final int c = text.codeUnitAt(p);
      if (c == _kBackslash) {
        final int escaped = p + 1;
        if (escaped < hi &&
            MarkdownConstants.isEscapablePunctuation(
              text.codeUnitAt(escaped),
            ) &&
            !_inGhost(ghosts, gi, escaped)) {
          (atoms ??= <InlineToken>[]).add(InlineEscape(start: p));
          p = escaped + 1;
          continue;
        }
        p++;
        continue;
      }
      if (gi < ghostCount && ghosts[gi].start == p) {
        final GhostMatch g = ghosts[gi];
        assert(g.end <= hi, 'a ghost may never straddle a tokenized range');
        (atoms ??= <InlineToken>[]).add(InlineGhost(g));
        p = g.end < hi ? g.end : hi;
        gi++;
        continue;
      }
      if (c == _kBacktick) {
        int r = p + 1;
        while (r < hi && text.codeUnitAt(r) == _kBacktick) {
          r++;
        }
        final int close = _findFence(text, r, hi, r - p, ghosts);
        if (close < 0) {
          p = r;
          continue;
        }
        (atoms ??= <InlineToken>[]).add(
          InlineCode(
            start: p,
            end: close + (r - p),
            innerStart: r,
            innerEnd: close,
          ),
        );
        p = close + (r - p);
        continue;
      }
      p++;
    }
    return atoms;
  }

  /// Start of the backtick run of exactly [fence] length that closes a
  /// code span, searching `[from, hi)` and skipping runs inside a ghost,
  /// or `-1` when the span never closes.
  static int _findFence(
    String text,
    int from,
    int hi,
    int fence,
    List<GhostMatch> ghosts,
  ) {
    int j = from;
    while (j < hi) {
      if (text.codeUnitAt(j) != _kBacktick) {
        j++;
        continue;
      }
      int r = j + 1;
      while (r < hi && text.codeUnitAt(r) == _kBacktick) {
        r++;
      }
      if (r - j == fence && !_inGhost(ghosts, 0, j)) return j;
      j = r;
    }
    return -1;
  }

  /// Whether [offset] falls inside a ghost at or after index [from].
  static bool _inGhost(List<GhostMatch> ghosts, int from, int offset) {
    for (int i = from; i < ghosts.length; i++) {
      final GhostMatch g = ghosts[i];
      if (g.start > offset) return false;
      if (offset < g.end) return true;
    }
    return false;
  }

  /// Whether [offset] falls inside one of the (sorted, disjoint) atoms.
  static bool _inAtom(List<InlineToken> atoms, int offset) {
    for (int i = 0; i < atoms.length; i++) {
      final InlineToken a = atoms[i];
      if (a.start > offset) return false;
      if (offset < a.end) return true;
    }
    return false;
  }

  /// A `[text](url)` whose `[` sits at [open], reported as starting at
  /// [tokenStart] (the `!` for an image). Rejected when any structural
  /// character sits inside an atom.
  static InlineLink? _tryLink(
    String text,
    int tokenStart,
    int open,
    int hi,
    List<InlineToken> atoms,
    bool isImage,
  ) {
    final MarkdownInlineLink? match = MarkdownLinkPatterns.matchInlineLinkAt(
      text,
      open,
      hi,
    );
    if (match == null) return null;
    if (_inAtom(atoms, match.textEnd) ||
        _inAtom(atoms, match.textEnd + 1) ||
        _inAtom(atoms, match.urlEnd)) {
      return null;
    }
    return InlineLink(
      start: tokenStart,
      end: match.end,
      textStart: match.textStart,
      textEnd: match.textEnd,
      urlStart: match.urlStart,
      urlEnd: match.urlEnd,
      isImage: isImage,
    );
  }

  /// Phase 3: CommonMark's "process emphasis" over the delimiter stack.
  static List<InlineToken>? _pairDelimiters(
    String text,
    List<_Delim> delims,
    MarkdownColorPalette palette,
  ) {
    List<InlineToken>? pairs;
    for (int ci = 0; ci < delims.length; ci++) {
      final _Delim closer = delims[ci];
      if (!closer.canClose) continue;
      final bool twoWide = closer.char == _kTilde || closer.char == _kEquals;
      while (closer.hi - closer.lo > 0) {
        if (twoWide && closer.hi - closer.lo < 2) break;
        int oi = ci - 1;
        _Delim? opener;
        while (oi >= 0) {
          final _Delim candidate = delims[oi];
          if (candidate.active &&
              candidate.char == closer.char &&
              candidate.canOpen &&
              candidate.hi - candidate.lo > 0) {
            if (twoWide) {
              if (candidate.hi - candidate.lo >= 2) {
                opener = candidate;
                break;
              }
            } else if (!((candidate.canClose || closer.canOpen) &&
                (candidate.origLen + closer.origLen) % 3 == 0 &&
                !(candidate.origLen % 3 == 0 && closer.origLen % 3 == 0))) {
              opener = candidate;
              break;
            }
          }
          oi--;
        }
        if (opener == null) break;

        final int openRemaining = opener.hi - opener.lo;
        final int closeRemaining = closer.hi - closer.lo;
        final int use = twoWide
            ? 2
            : (openRemaining >= 3 && closeRemaining >= 3)
            ? 3
            : (openRemaining >= 2 && closeRemaining >= 2)
            ? 2
            : 1;
        final int innerStart = opener.hi;
        final int innerEnd = closer.lo;
        final InlineEmphasisKind kind;
        if (closer.char == _kTilde) {
          kind = InlineEmphasisKind.strikethrough;
        } else if (closer.char == _kEquals) {
          kind = InlineEmphasisKind.highlight;
        } else {
          kind = use == 3
              ? InlineEmphasisKind.boldItalic
              : use == 2
              ? InlineEmphasisKind.bold
              : InlineEmphasisKind.italic;
        }
        int contentStart = innerStart;
        MarkdownColorSpec? tintSpec;
        if (kind == InlineEmphasisKind.highlight) {
          final tint = MarkdownColorSyntax.matchHighlightPrefix(
            text,
            innerStart,
            innerEnd,
            palette,
          );
          if (tint != null) {
            contentStart = tint.contentStart;
            tintSpec = tint.spec;
          }
        }
        (pairs ??= <InlineToken>[]).add(
          InlineEmphasis(
            kind: kind,
            start: innerStart - use,
            end: innerEnd + use,
            innerStart: innerStart,
            innerEnd: innerEnd,
            contentStart: contentStart,
            tintSpec: tintSpec,
          ),
        );

        opener.hi -= use;
        closer.lo += use;
        for (int k = oi + 1; k < ci; k++) {
          delims[k].active = false;
        }
        if (opener.hi - opener.lo == 0) opener.active = false;
      }
    }
    return pairs;
  }

  /// Sorts by start ascending, then by end descending so a container
  /// always precedes what it encloses. Insertion sort: token lists are
  /// short and this keeps the hot path closure-free.
  static void _sortTokens(List<InlineToken> tokens) {
    for (int i = 1; i < tokens.length; i++) {
      final InlineToken token = tokens[i];
      int j = i - 1;
      while (j >= 0 &&
          (tokens[j].start > token.start ||
              (tokens[j].start == token.start && tokens[j].end < token.end))) {
        tokens[j + 1] = tokens[j];
        j--;
      }
      tokens[j + 1] = token;
    }
  }

  /// Depth-first search for the innermost link ([wantTag] false) or tag
  /// ([wantTag] true) whose run strictly contains [offset].
  static InlineToken? _walk(
    String text,
    int start,
    int end,
    List<GhostMatch> ghosts,
    MarkdownColorPalette palette,
    int depth,
    int offset,
    bool wantTag,
  ) {
    final List<InlineToken> tokens = tokenize(
      text,
      start: start,
      end: end,
      ghosts: ghosts,
      palette: palette,
      depth: depth,
    );
    for (int i = 0; i < tokens.length; i++) {
      final InlineToken token = tokens[i];
      if (token.start > offset) break;
      if (offset >= token.end) continue;
      if (token is InlineTag) {
        return wantTag && token.containsStrict(offset) ? token : null;
      }
      if (token is InlineLink) {
        if (!wantTag && !token.isImage && token.containsStrict(offset)) {
          return token;
        }
        return _descend(
          text,
          token.textStart,
          token.textEnd,
          ghosts,
          palette,
          depth,
          offset,
          wantTag,
        );
      }
      if (token is InlineEmphasis) {
        return _descend(
          text,
          token.contentStart,
          token.innerEnd,
          ghosts,
          palette,
          depth,
          offset,
          wantTag,
        );
      }
      if (token is InlineColor) {
        return _descend(
          text,
          token.innerStart,
          token.innerEnd,
          ghosts,
          palette,
          depth,
          offset,
          wantTag,
        );
      }
      return null;
    }
    return null;
  }

  static InlineToken? _descend(
    String text,
    int start,
    int end,
    List<GhostMatch> ghosts,
    MarkdownColorPalette palette,
    int depth,
    int offset,
    bool wantTag,
  ) {
    if (offset < start || offset >= end) return null;
    return _walk(text, start, end, ghosts, palette, depth + 1, offset, wantTag);
  }
}

/// One delimiter run on the emphasis stack. `[lo, hi)` shrinks as the
/// run is spent — a closer spends from the front, an opener from the
/// back — while [origLen] keeps the run's original length for the rule
/// of three.
class _Delim {
  final int char;
  final int origLen;
  final bool canOpen;
  final bool canClose;
  int lo;
  int hi;
  bool active = true;

  _Delim(
    this.char,
    this.lo,
    this.hi,
    this.origLen,
    this.canOpen,
    this.canClose,
  );
}

/// What an emphasis-style delimiter pair means.
enum InlineEmphasisKind { boldItalic, bold, italic, strikethrough, highlight }

/// One top-level inline construct in `[start, end)` of the tokenized
/// text. Offsets are indexes into the tokenized string, never shifted.
@immutable
sealed class InlineToken {
  /// First code unit of the construct (its opening marker, if any).
  final int start;

  /// One past the last code unit of the construct.
  final int end;

  const InlineToken({required this.start, required this.end});

  /// Whether [offset] lies strictly inside the run.
  bool containsStrict(int offset) => offset > start && offset < end;
}

/// `\` followed by one escapable punctuation character. Renders the
/// character literally; the backslash is chrome.
final class InlineEscape extends InlineToken {
  const InlineEscape({required super.start}) : super(end: start + 2);

  /// Index of the escaped character.
  int get charStart => start + 1;
}

/// A `{{ … }}` ghost run, opaque to every other rule.
final class InlineGhost extends InlineToken {
  final GhostMatch match;

  InlineGhost(this.match) : super(start: match.start, end: match.end);
}

/// A backtick code span. `[innerStart, innerEnd)` is literal content.
final class InlineCode extends InlineToken {
  final int innerStart;
  final int innerEnd;

  const InlineCode({
    required super.start,
    required super.end,
    required this.innerStart,
    required this.innerEnd,
  });

  /// Length of the backtick fence on either side.
  int get fenceLength => innerStart - start;
}

/// `[text](url)` — or `![text](url)` when [isImage], in which case
/// [start] is the `!`. Link text `[textStart, textEnd)` is a nested
/// range; the url is literal.
final class InlineLink extends InlineToken {
  final int textStart;
  final int textEnd;
  final int urlStart;
  final int urlEnd;
  final bool isImage;

  const InlineLink({
    required super.start,
    required super.end,
    required this.textStart,
    required this.textEnd,
    required this.urlStart,
    required this.urlEnd,
    required this.isImage,
  });

  /// Index of the opening `[`.
  int get bracketStart => textStart - 1;

  String urlOf(String text) => text.substring(urlStart, urlEnd);
}

/// `{name:text}` with a resolved colour. `[innerStart, innerEnd)` is a
/// nested range; `[start, innerStart)` and `[innerEnd, end)` are chrome.
final class InlineColor extends InlineToken {
  final int innerStart;
  final int innerEnd;
  final MarkdownColorSpec spec;

  const InlineColor({
    required super.start,
    required super.end,
    required this.innerStart,
    required this.innerEnd,
    required this.spec,
  });
}

/// A `#tag` token, leading `#` included.
final class InlineTag extends InlineToken {
  const InlineTag({required super.start, required super.end});

  String tagOf(String text) => text.substring(start, end);
}

/// A bare `http://`, `https://` or `www.` URL.
final class InlineUrl extends InlineToken {
  const InlineUrl({required super.start, required super.end});

  /// The launch target: `www.` links gain an `https://` scheme.
  String hrefOf(String text) {
    final raw = text.substring(start, end);
    return raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
  }
}

/// A matched delimiter pair. Markers are `[start, innerStart)` and
/// `[innerEnd, end)` (equal length). For a highlight with a resolved
/// `name:` prefix, [tintSpec] is the colour and `[innerStart,
/// contentStart)` is the prefix — chrome too; otherwise [contentStart]
/// equals [innerStart]. `[contentStart, innerEnd)` is the nested range.
final class InlineEmphasis extends InlineToken {
  final InlineEmphasisKind kind;
  final int innerStart;
  final int innerEnd;
  final int contentStart;
  final MarkdownColorSpec? tintSpec;

  const InlineEmphasis({
    required this.kind,
    required super.start,
    required super.end,
    required this.innerStart,
    required this.innerEnd,
    int? contentStart,
    this.tintSpec,
  }) : contentStart = contentStart ?? innerStart;

  int get markerLength => innerStart - start;
}
