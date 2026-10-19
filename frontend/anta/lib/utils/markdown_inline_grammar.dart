import 'package:flutter/foundation.dart';

import '../constants/markdown_constants.dart';
import 'ghost_text.dart';
import 'markdown_color_syntax.dart';
import 'markdown_link_patterns.dart';
import 'markdown_tag_syntax.dart';

/// The one inline grammar both render surfaces consume — emphasis,
/// strikethrough, highlight, inline code, backslash escapes — together
/// with the placement rules for the constructs that already own their
/// own module (ghosts, `[text](url)` links, `[[title]]` wiki links,
/// `<…>` autolinks, bare URLs, `#tag`s, `{name:text}` colours). The
/// preview drops markers, the live editor conceals them, the editor's
/// tap zones resolve against it; none of them may re-scan for any of
/// these constructs on their own.
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
/// * Then, at each position outside an atom: `[[title]]` wiki links
///   (probed on a doubled `[` — `![[` too, an embed — before the link
///   rule, and rejected when any atom would start inside them),
///   `![text](url)` / `[text](url)` (structural characters must not sit
///   inside an atom), `<…>` autolinks (rejected like wiki links),
///   `{name:text}` (its closing brace likewise), `#tag` and bare URLs at
///   a word boundary (a URL stops at the next atom), HTML entities that
///   decode to one unit (a URL or code span keeps its `&` literal), and
///   delimiter runs of `*`, `_`, `~~`, `==`.
/// * A run can open when the next character is not whitespace and can
///   close when the previous one is not; `_` runs additionally need a
///   non-word character (or the range edge) on the outside, and a single
///   `*` between two ASCII digits does neither. Openers and
///   closers pair like CommonMark's delimiter stack (nearest opener of
///   the same character, the rule of three for `*` and `_`, delimiters
///   between a matched pair drop out), an opener spending from the end
///   of its run and a closer from the start, so `***a**` is a literal
///   `*` followed by bold. Three matched on both sides give one
///   bold-italic token. `~~`/`==` pair two at a time; leftovers are
///   literal.
/// * Only top-level tokens are returned. A consumer recurses into an
///   emphasis, link-text or colour range and finds the nested tokens
///   there; code spans and wiki-link titles are literal all the way
///   down.
class MarkdownInlineGrammar {
  MarkdownInlineGrammar._();

  /// Containers deeper than this render their inner range plain:
  /// [tokenize] returns only the range's ghost runs once `depth` reaches
  /// it, on both surfaces alike, so pathological nesting is bounded
  /// without the two renderers ever disagreeing about where the cut is.
  /// Ghosts survive the cut because they are placeholders, never
  /// styling — a run left un-concealed would leak its `{{` `}}` into the
  /// preview and its name into the editor.
  static const int maxNestingDepth = 8;

  /// Tokenizes `[start, end)` of [text]. [ghosts] are the ghost runs of
  /// the whole [text] (as [GhostText.findGhosts] returns them); when
  /// omitted they are computed from [text]. [palette] resolves colour
  /// names for `{name:text}` and `==name:text==`. Returns the top-level
  /// tokens in source order, non-overlapping, each within the range —
  /// or only the range's ghost runs once [depth] reaches
  /// [maxNestingDepth].
  static List<InlineToken> tokenize(
    String text, {
    int start = 0,
    int? end,
    List<GhostMatch>? ghosts,
    required MarkdownColorPalette palette,
    int depth = 0,
  }) {
    final int hi = end ?? text.length;
    if (start >= hi || !hasCandidates(text, start, hi)) return const [];
    final List<GhostMatch> runs =
        ghosts ??
        (GhostText.mightContain(text)
            ? GhostText.findGhosts(text)
            : const <GhostMatch>[]);
    if (depth >= maxNestingDepth) return _ghostsOnly(runs, start, hi);

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
          // `![[file]]` is Obsidian's embed: probed before the image
          // rule, in the order a doubled `[` is probed below.
          final wiki = _tryWikiLink(text, p + 1, hi, nextAtom, true);
          if (wiki != null) {
            (constructs ??= <InlineToken>[]).add(wiki);
            p = wiki.end;
            continue;
          }
          final link = _tryLink(text, p, p + 1, hi, atomList, ai, true);
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
        if (p + 1 < hi && text.codeUnitAt(p + 1) == _kOpenBracket) {
          final wiki = _tryWikiLink(text, p, hi, nextAtom, false);
          if (wiki != null) {
            (constructs ??= <InlineToken>[]).add(wiki);
            p = wiki.end;
            continue;
          }
        }
        final link = _tryLink(text, p, p, hi, atomList, ai, false);
        if (link != null) {
          (constructs ??= <InlineToken>[]).add(link);
          p = link.end;
          continue;
        }
        p++;
        continue;
      }

      if (c == _kLessThan) {
        // Like a wiki link, an autolink's inside is literal, so any atom
        // opening inside it refuses the whole construct.
        final auto = MarkdownLinkPatterns.matchAutolinkAt(text, p, hi);
        if (auto != null && auto.end <= nextAtom) {
          (constructs ??= <InlineToken>[]).add(
            InlineAutolink(start: p, end: auto.end, isEmail: auto.isEmail),
          );
          p = auto.end;
          continue;
        }
        p++;
        continue;
      }

      if (c == _kOpenBrace) {
        final match = MarkdownColorSyntax.matchAt(text, p, palette, hi);
        if (match != null && !_inAtom(atomList, ai, match.innerEnd)) {
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

      if (c == _kAmpersand) {
        final InlineEntity? entity = _tryEntity(text, p, nextAtom);
        if (entity != null) {
          (constructs ??= <InlineToken>[]).add(entity);
          p = entity.end;
          continue;
        }
        // A well-formed numeric reference that does not decode stays
        // literal whole, so the `#x1F600` inside it never reads as a tag.
        p = _numericReference(text, p, nextAtom)?.end ?? p + 1;
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
        final int prev = p > start ? codePointBefore(text, p, start) : -1;
        final int next = r < hi ? codePointAt(text, r, hi) : -1;
        bool canOpen = next != -1 && !isSpace(next);
        bool canClose = prev != -1 && !isSpace(prev);
        if (c == _kUnderscore) {
          if (canOpen && prev != -1 && isWordChar(prev)) canOpen = false;
          if (canClose && next != -1 && isWordChar(next)) canClose = false;
        } else if (c == _kStar &&
            runLength == 1 &&
            _isAsciiDigit(prev) &&
            _isAsciiDigit(next)) {
          // A deliberate deviation from CommonMark (and Obsidian): a
          // single `*` between two digits is a multiplication in a gym
          // log, so `Squat 3*10, Bench 3*8` must not italicise
          // "10, Bench 3". Longer runs and `_` keep the standard rules.
          canOpen = false;
          canClose = false;
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
  ///
  /// The outermost match wins, which is what makes a tap inside a link
  /// nested in another construct open the link the editor drew there.
  ///
  /// Pass the line's ghost runs as [ghosts] when you already have them;
  /// they are scanned from [text] otherwise.
  static InlineLink? linkAt(
    String text,
    int offset, {
    required MarkdownColorPalette palette,
    List<GhostMatch>? ghosts,
  }) {
    if (offset <= 0 || offset >= text.length) return null;
    for (final InlineToken token in linksAndTags(
      text,
      palette: palette,
      ghosts: ghosts,
    )) {
      if (token is InlineLink && token.containsStrict(offset)) return token;
    }
    return null;
  }

  /// The `[[title]]` wiki link whose run strictly contains [offset] —
  /// `start < offset < end`, exactly like [linkAt], so the outer
  /// brackets' boundary offsets belong to caret placement — at any
  /// nesting depth, or `null`. Resolves against exactly what [tokenize]
  /// would render, so a title that never became a link (`[[a|b|c]]`, a
  /// title split by a code span) resolves to nothing.
  ///
  /// Pass the line's ghost runs as [ghosts] when you already have them;
  /// they are scanned from [text] otherwise.
  static InlineWikiLink? wikiLinkAt(
    String text,
    int offset, {
    required MarkdownColorPalette palette,
    List<GhostMatch>? ghosts,
  }) {
    if (offset <= 0 || offset >= text.length) return null;
    for (final InlineToken token in linksAndTags(
      text,
      palette: palette,
      ghosts: ghosts,
    )) {
      if (token is InlineWikiLink && token.containsStrict(offset)) return token;
    }
    return null;
  }

  /// The `#tag` whose run strictly contains [offset] at any nesting
  /// depth, or `null`. Tags inside code spans and ghosts are not tags.
  ///
  /// Pass the line's ghost runs as [ghosts] when you already have them;
  /// they are scanned from [text] otherwise.
  static InlineTag? tagAt(
    String text,
    int offset, {
    required MarkdownColorPalette palette,
    List<GhostMatch>? ghosts,
  }) {
    if (offset <= 0 || offset >= text.length) return null;
    for (final InlineToken token in linksAndTags(
      text,
      palette: palette,
      ghosts: ghosts,
    )) {
      if (token is InlineTag && token.containsStrict(offset)) return token;
    }
    return null;
  }

  /// Every `[text](url)` link, every `[[title]]` wiki link, every `<…>`
  /// autolink and every `#tag` [tokenize] renders in [text], at any
  /// nesting depth — the one
  /// descent behind [linkAt], [wikiLinkAt], [tagAt] and every caller
  /// that needs the constructs themselves instead of the one under a
  /// single offset, so no two of them can disagree about what the
  /// tokenizer would render.
  ///
  /// [ghosts] are the ghost runs of [text] (as [GhostText.findGhosts]
  /// returns them); a caller that already has them passes them through
  /// instead of paying for a second scan.
  ///
  /// Outermost first, siblings in source order, so a run nested in an
  /// earlier token follows it: an image is not a link but its text is
  /// still descended into, and a link's text is descended into as well,
  /// so a tag inside either is reported after the token that covers it
  /// and the caller applies its own precedence. A wiki link and an
  /// autolink are the exceptions — their insides are literal, so nothing
  /// is ever reported inside one.
  static List<InlineToken> linksAndTags(
    String text, {
    required MarkdownColorPalette palette,
    List<GhostMatch>? ghosts,
  }) {
    if (text.isEmpty) return const [];
    final List<GhostMatch> runs =
        ghosts ??
        (GhostText.mightContain(text)
            ? GhostText.findGhosts(text)
            : const <GhostMatch>[]);
    final List<InlineToken> found = <InlineToken>[];
    _collect(text, 0, text.length, runs, palette, 0, found);
    return found;
  }

  /// Whether `[start, end)` holds a code unit that can open any token —
  /// `* ~ ` _ = # [ \ { < &` (`[` covers `[[` too, since a wiki link opens
  /// on the same unit) or a bare-URL scheme lead (`ht`, `ww`; a lone
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
          c == _kOpenBrace ||
          c == _kLessThan ||
          c == _kAmpersand) {
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
  /// digits, `_` itself, and above 0x7F the code points Unicode files
  /// as letters, digits or combining marks — so `snake_case` and `ș_a_`
  /// never open emphasis while `„_foarte greu_“` and `—_x_` do, the
  /// quotes and dashes of Romanian and German prose being punctuation.
  /// [c] is a code point; a lone surrogate unit is no word character.
  static bool isWordChar(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5F ||
      (c > 0x7F && _unicodeWordChar.hasMatch(String.fromCharCode(c)));

  /// Unicode categories L, N and M. Consulted only for a non-ASCII
  /// neighbour of a `_` run, so the per-call string is off the common
  /// path.
  static final RegExp _unicodeWordChar = RegExp(
    r'[\p{L}\p{N}\p{M}]',
    unicode: true,
  );

  static bool _isAsciiDigit(int c) => c >= 0x30 && c <= 0x39;

  /// The code point ending just before [p], read whole when it is a
  /// surrogate pair that lies inside the range starting at [start] — the
  /// read [isWordChar] expects, so a caller outside the tokenizer judges
  /// a neighbour the way the flanking rule does.
  static int codePointBefore(String text, int p, int start) {
    final int low = text.codeUnitAt(p - 1);
    if (low >= 0xDC00 && low <= 0xDFFF && p - 2 >= start) {
      final int high = text.codeUnitAt(p - 2);
      if (high >= 0xD800 && high <= 0xDBFF) {
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
      }
    }
    return low;
  }

  /// The code point starting at [p], read whole when it is a surrogate
  /// pair that ends before [hi]; the counterpart of [codePointBefore].
  static int codePointAt(String text, int p, int hi) {
    final int high = text.codeUnitAt(p);
    if (high >= 0xD800 && high <= 0xDBFF && p + 1 < hi) {
      final int low = text.codeUnitAt(p + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
      }
    }
    return high;
  }

  /// Whether `[start, end)` ends in a hard line break: a `\` as its last
  /// unit that no token in [tokens] (the range's top-level tokens) covers
  /// — `a\\` ends in an escaped backslash, a code span or URL keeps its
  /// own — after some non-blank content, so a line that is only `\`
  /// stays text. Every surface asks it only of a depth-0 range that
  /// reaches the end of its source line, and never of a heading, a
  /// callout title or a money row — single-line constructs, where
  /// CommonMark keeps the `\` as text; the `\` is then chrome.
  static bool endsWithHardBreak(
    String text,
    int start,
    int end,
    List<InlineToken> tokens,
  ) {
    if (end - start < 2 || text.codeUnitAt(end - 1) != _kBackslash) {
      return false;
    }
    if (tokens.isNotEmpty && tokens.last.end >= end) return false;
    for (int i = end - 2; i >= start; i--) {
      if (!isSpace(text.codeUnitAt(i))) return true;
    }
    return false;
  }

  static const int _kBang = 0x21; // !
  static const int _kHash = 0x23; // #
  static const int _kAmpersand = 0x26; // &
  static const int _kSemicolon = 0x3B; // ;
  static const int _kStar = 0x2A; // *
  static const int _kLessThan = 0x3C; // <
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
        final int close = _findFence(text, r, hi, r - p, ghosts, gi);
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
  ///
  /// [firstGhost] is the atom scanner's ghost cursor: every ghost below
  /// it ends at or before the opening run, so it can never contain a
  /// candidate closer. The local copy only moves forward, which keeps
  /// the whole search linear in the number of ghosts instead of
  /// rescanning them from zero for every backtick run.
  static int _findFence(
    String text,
    int from,
    int hi,
    int fence,
    List<GhostMatch> ghosts,
    int firstGhost,
  ) {
    final int ghostCount = ghosts.length;
    int gi = firstGhost;
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
      if (r - j == fence) {
        while (gi < ghostCount && ghosts[gi].end <= j) {
          gi++;
        }
        if (!_inGhost(ghosts, gi, j)) return j;
      }
      j = r;
    }
    return -1;
  }

  /// The ghost runs contained in `[start, hi)` as tokens, in source
  /// order — everything [tokenize] still reports once the nesting depth
  /// is spent. A run may not straddle a range edge (the containers a
  /// consumer recurses into never split one), so a partial overlap is an
  /// assertion failure rather than a clipped token.
  static List<InlineToken> _ghostsOnly(
    List<GhostMatch> ghosts,
    int start,
    int hi,
  ) {
    List<InlineToken>? out;
    for (int i = 0; i < ghosts.length; i++) {
      final GhostMatch g = ghosts[i];
      if (g.end <= start) continue;
      if (g.start >= hi) break;
      assert(
        g.start >= start && g.end <= hi,
        'a ghost may never straddle a tokenized range',
      );
      (out ??= <InlineToken>[]).add(InlineGhost(g));
    }
    return out ?? const [];
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

  /// Whether [offset] falls inside one of the (sorted, disjoint) atoms
  /// at or after index [from].
  ///
  /// The main loop's atom cursor `ai` is always a valid [from]: it is
  /// advanced past every atom whose end is at or before the current
  /// position `p`, and every offset probed from there lies at or after
  /// `p` — so no atom below it can contain the offset, and the scan
  /// costs the atoms still ahead rather than the whole line's.
  static bool _inAtom(List<InlineToken> atoms, int from, int offset) {
    for (int i = from; i < atoms.length; i++) {
      final InlineToken a = atoms[i];
      if (a.start > offset) return false;
      if (offset < a.end) return true;
    }
    return false;
  }

  /// A `[text](url)` whose `[` sits at [open], reported as starting at
  /// [tokenStart] (the `!` for an image). Rejected when any structural
  /// character sits inside an atom; [firstAtom] is the main loop's atom
  /// cursor, the lower bound every one of those probes may start from
  /// (see [_inAtom]).
  static InlineLink? _tryLink(
    String text,
    int tokenStart,
    int open,
    int hi,
    List<InlineToken> atoms,
    int firstAtom,
    bool isImage,
  ) {
    final MarkdownInlineLink? match = isImage
        ? MarkdownLinkPatterns.matchImageAt(text, open, hi)
        : MarkdownLinkPatterns.matchInlineLinkAt(text, open, hi);
    if (match == null) return null;
    if (_inAtom(atoms, firstAtom, match.textEnd) ||
        _inAtom(atoms, firstAtom, match.textEnd + 1) ||
        _inAtom(atoms, firstAtom, match.urlEnd)) {
      return null;
    }
    return InlineLink(
      start: tokenStart,
      end: match.end,
      textStart: match.textStart,
      textEnd: match.textEnd,
      urlStart: match.urlStart,
      urlEnd: match.urlEnd,
      destStart: match.destStart,
      destEnd: match.destEnd,
      isImage: isImage,
    );
  }

  /// A `[[title]]` whose first `[` sits at [open], or `null` — refused
  /// when it would end past [nextAtom], i.e. when any atom opens inside
  /// it. An [embed] is reported from the `!` just before [open].
  static InlineWikiLink? _tryWikiLink(
    String text,
    int open,
    int hi,
    int nextAtom,
    bool embed,
  ) {
    final MarkdownWikiLink? wiki = MarkdownLinkPatterns.matchWikiLinkAt(
      text,
      open,
      hi,
    );
    if (wiki == null || wiki.end > nextAtom) return null;
    return InlineWikiLink(
      start: embed ? open - 1 : open,
      end: wiki.end,
      titleStart: wiki.titleStart,
      titleEnd: wiki.titleEnd,
      aliasStart: wiki.aliasStart,
      isEmbed: embed,
    );
  }

  /// The HTML entity whose `&` sits at [p], ending at or before [limit],
  /// or `null`: a name from [MarkdownConstants.htmlEntities], or a
  /// decimal (`&#169;`) or hex (`&#xA9;`) reference to one BMP code unit
  /// that draws as itself ([_decodesVisibly]) — the editor shows the
  /// decoded character in the `&`'s one unit, so anything wider stays
  /// literal.
  static InlineEntity? _tryEntity(String text, int p, int limit) {
    final int max = p + 10 < limit ? p + 10 : limit;
    int q = p + 1;
    if (q < max && text.codeUnitAt(q) == _kHash) {
      final ({int end, int value})? ref = _numericReference(text, p, limit);
      if (ref == null || !_decodesVisibly(ref.value)) return null;
      return InlineEntity(start: p, end: ref.end, char: ref.value);
    }
    final int nameStart = q;
    while (q < max && _isAsciiAlnum(text.codeUnitAt(q))) {
      q++;
    }
    if (q == nameStart || q >= max || text.codeUnitAt(q) != _kSemicolon) {
      return null;
    }
    final int? char =
        MarkdownConstants.htmlEntities[text.substring(nameStart, q)];
    if (char == null) return null;
    return InlineEntity(start: p, end: q + 1, char: char);
  }

  /// The well-formed numeric reference — `&#` or `&#x`, digits, `;`,
  /// ten units at most — whose `&` sits at [p] and that ends at or before
  /// [limit], with its value, or `null`. Whether it decodes is
  /// [_decodesVisibly]'s call.
  static ({int end, int value})? _numericReference(
    String text,
    int p,
    int limit,
  ) {
    final int max = p + 10 < limit ? p + 10 : limit;
    int q = p + 1;
    if (q >= max || text.codeUnitAt(q) != _kHash) return null;
    q++;
    bool hex = false;
    if (q < max && (text.codeUnitAt(q) | 0x20) == 0x78) {
      hex = true;
      q++;
    }
    final int digitsStart = q;
    int value = 0;
    while (q < max) {
      final int d = _digitValue(text.codeUnitAt(q), hex);
      if (d < 0) break;
      value = value * (hex ? 16 : 10) + d;
      q++;
    }
    if (q == digitsStart || q >= max || text.codeUnitAt(q) != _kSemicolon) {
      return null;
    }
    return (end: q + 1, value: value);
  }

  /// Whether a numeric reference's [value] decodes: one BMP unit that
  /// draws as itself. Controls (C0, DEL, C1), surrogates, format and bidi
  /// controls, the line and paragraph separators, combining marks and the
  /// noncharacters stay literal — in the `&`'s slot each would break the
  /// line, reorder it or fuse with a concealed marker, so the line would
  /// read or wrap differently between reveal states.
  static bool _decodesVisibly(int value) {
    if (value <= 0x1F || value > 0xFFFF) return false;
    if (value >= 0xD800 && value <= 0xDFFF) return false;
    if ((value >= 0xFDD0 && value <= 0xFDEF) || value >= 0xFFFE) {
      return false;
    }
    return value < 0x7F ||
        !_invisibleUnit.hasMatch(String.fromCharCode(value));
  }

  /// Unicode categories Cc, Cf, Zl, Zp and M. Consulted only for a
  /// numeric reference above 0x7E, so the per-call string is off the
  /// common path.
  static final RegExp _invisibleUnit = RegExp(
    r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{M}]',
    unicode: true,
  );

  /// The value of digit [c] in base 16 when [hex], else base 10, or -1.
  static int _digitValue(int c, bool hex) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (!hex) return -1;
    final int lower = c | 0x20;
    if (lower >= 0x61 && lower <= 0x66) return lower - 0x61 + 10;
    return -1;
  }

  static bool _isAsciiAlnum(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A);

  /// Number of `openers_bottom` classes: four delimiter characters times
  /// three closer lengths mod three times the two closer-can-open cases.
  static const int _openersBottomSlots = 24;

  /// The `openers_bottom` class of [closer] — its delimiter character,
  /// its run's original length mod three, and whether it can also open.
  ///
  /// Those are exactly the closer-side inputs the opener search reads,
  /// so once a search fails for one closer no later closer of the same
  /// class can succeed any lower: every other rejection reason (a spent,
  /// deactivated or non-opening run) only ever gets stronger.
  static int _openersBottomSlot(_Delim closer) {
    final int charSlot = closer.char == _kStar
        ? 0
        : closer.char == _kUnderscore
        ? 1
        : closer.char == _kTilde
        ? 2
        : 3;
    return charSlot * 6 + (closer.origLen % 3) * 2 + (closer.canOpen ? 1 : 0);
  }

  /// Phase 3: CommonMark's "process emphasis" over the delimiter stack,
  /// including its `openers_bottom` bound — without it every closer
  /// rescans every earlier delimiter and a line of unpairable runs costs
  /// O(n²). The table is allocated on the first failed search, so a line
  /// whose delimiters all pair still allocates nothing.
  static List<InlineToken>? _pairDelimiters(
    String text,
    List<_Delim> delims,
    MarkdownColorPalette palette,
  ) {
    List<InlineToken>? pairs;
    List<int>? openersBottom;
    for (int ci = 0; ci < delims.length; ci++) {
      final _Delim closer = delims[ci];
      if (!closer.canClose) continue;
      final bool twoWide = closer.char == _kTilde || closer.char == _kEquals;
      final int slot = _openersBottomSlot(closer);
      while (closer.hi - closer.lo > 0) {
        if (twoWide && closer.hi - closer.lo < 2) break;
        final int bottom = openersBottom == null ? -1 : openersBottom[slot];
        int oi = ci - 1;
        _Delim? opener;
        while (oi > bottom) {
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
        if (opener == null) {
          (openersBottom ??= List<int>.filled(_openersBottomSlots, -1))[slot] =
              ci - 1;
          if (!closer.canOpen) closer.active = false;
          break;
        }

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

  /// Depth-first collection of every link, wiki link, autolink and tag
  /// in `[start, end)`. A wiki link's title and an autolink's inside are
  /// literal, so the walk stops at the token instead of descending into
  /// it.
  static void _collect(
    String text,
    int start,
    int end,
    List<GhostMatch> ghosts,
    MarkdownColorPalette palette,
    int depth,
    List<InlineToken> out,
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
      if (token is InlineTag) {
        out.add(token);
      } else if (token is InlineLink) {
        if (!token.isImage) out.add(token);
        _collect(
          text,
          token.textStart,
          token.textEnd,
          ghosts,
          palette,
          depth + 1,
          out,
        );
      } else if (token is InlineWikiLink || token is InlineAutolink) {
        out.add(token);
      } else if (token is InlineEmphasis) {
        _collect(
          text,
          token.contentStart,
          token.innerEnd,
          ghosts,
          palette,
          depth + 1,
          out,
        );
      } else if (token is InlineColor) {
        _collect(
          text,
          token.innerStart,
          token.innerEnd,
          ghosts,
          palette,
          depth + 1,
          out,
        );
      }
    }
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

/// An HTML entity — `&amp;`, `&#169;`, `&#xA9;` — that decodes to one
/// UTF-16 unit. The decoded character stands in for the `&`; the rest of
/// the entity is chrome.
final class InlineEntity extends InlineToken {
  /// The decoded code unit, always a single BMP unit.
  final int char;

  const InlineEntity({
    required super.start,
    required super.end,
    required this.char,
  });

  /// [char] as a string, the text every surface renders.
  String get decoded => String.fromCharCode(char);
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

  /// Index just past the `(`: `[urlStart, urlEnd)` is the whole inside
  /// of the parens, destination, blanks and title alike — all chrome.
  final int urlStart;

  /// Index of the `)` closing the url.
  final int urlEnd;

  /// `[destStart, destEnd)` is the destination alone, without the
  /// angle brackets of `<…>` and without the title.
  final int destStart;

  /// See [destStart].
  final int destEnd;
  final bool isImage;

  const InlineLink({
    required super.start,
    required super.end,
    required this.textStart,
    required this.textEnd,
    required this.urlStart,
    required this.urlEnd,
    required this.destStart,
    required this.destEnd,
    required this.isImage,
  });

  /// Index of the opening `[`.
  int get bracketStart => textStart - 1;

  /// What the link opens: the destination of [text], never its title.
  String urlOf(String text) => text.substring(destStart, destEnd);
}

/// `<https://…>`, `<mailto:…>`, `<tel:…>` or `<name@host.tld>` — an
/// angle autolink. The brackets are chrome and the inside
/// `[innerStart, innerEnd)` is literal, never a nested range.
final class InlineAutolink extends InlineToken {
  /// Whether the inside is a bare address, which opens as `mailto:`.
  final bool isEmail;

  const InlineAutolink({
    required super.start,
    required super.end,
    required this.isEmail,
  });

  /// Index just past the `<`.
  int get innerStart => start + 1;

  /// Index of the closing `>`.
  int get innerEnd => end - 1;

  /// The launch target: the inside of [text], an address gaining its
  /// `mailto:` scheme.
  String hrefOf(String text) {
    final inner = text.substring(innerStart, innerEnd);
    return isEmail ? 'mailto:$inner' : inner;
  }
}

/// `[[title]]` — a wiki link to another note by title. The title
/// `[titleStart, titleEnd)` is literal (never a nested range): it is the
/// lookup key, so what renders is exactly what resolves — unless the
/// link carries an alias, `[[title|alias]]`, which is then shown in the
/// title's place ([displayStart], [displayEnd]) and is literal too.
///
/// An [isEmbed] link is Obsidian's `![[file]]`: [start] is the `!`,
/// which renders as a picture glyph, and the rest is the wiki link it
/// always was — nothing is ever loaded.
///
/// Placement: the construct is refused outright when any atom would open
/// inside it, and the atoms are exactly three — an escape (`\` before
/// ASCII punctuation, so `[[snake\_case]]` is not a wiki link at all,
/// only literal brackets around an escape, while `[[snake_case]]` is one
/// with a literal underscore in its title), a ghost run, and a code
/// span. Nothing else can start inside a title, which is why neither
/// surface ever needs a nested pass over one.
///
/// A wiki link can never sit inside a `[text](url)` link's text either:
/// [MarkdownLinkPatterns.matchInlineLinkAt] closes the text at the
/// *first* `]`, and a wiki link always carries `]]`. So `_collect` not
/// descending into a title and both emitters "never recursing into" one
/// are the same fact rather than two rules that could drift apart.
final class InlineWikiLink extends InlineToken {
  /// Index where the title begins, just past the `[[`.
  final int titleStart;

  /// Index just past the title: the `|` of an alias form, otherwise the
  /// first `]` of the closing `]]`.
  final int titleEnd;

  /// Index just past the `|` when a non-blank alias follows, or null.
  final int? aliasStart;

  /// Whether a `!` leads the link — see the class comment.
  final bool isEmbed;

  const InlineWikiLink({
    required super.start,
    required super.end,
    required this.titleStart,
    required this.titleEnd,
    this.aliasStart,
    this.isEmbed = false,
  });

  /// Index of the first `[` of the opening `[[`.
  int get bracketStart => isEmbed ? start + 1 : start;

  /// Index of the first `]` of the closing `]]`.
  int get closeStart => end - 2;

  /// Where the text the reader sees begins: the alias, else the title.
  int get displayStart => aliasStart ?? titleStart;

  /// Where that text ends.
  int get displayEnd => aliasStart == null ? titleEnd : closeStart;

  /// Strictly inside the brackets: the `!` of an embed is the picture
  /// glyph, not the link, so its boundary is the `[` exactly as it is
  /// for a plain `[[title]]`.
  @override
  bool containsStrict(int offset) => offset > bracketStart && offset < end;

  /// The raw title of [text] — the note title this link resolves
  /// against, with no markup of its own.
  String titleOf(String text) => text.substring(titleStart, titleEnd);

  /// The text of [text] the reader sees: the alias, else the title.
  String displayOf(String text) => text.substring(displayStart, displayEnd);
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
