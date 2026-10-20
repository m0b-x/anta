/// Shared, widget-free markdown chunking algorithm.
///
/// This is the single source of truth for how note content is divided
/// into render chunks. Both the preview renderer
/// ([LineBasedMarkdownBuilder]) and the editor's debug chunk overlay
/// ([EditorChunkOverlay]) consume it so their chunk boundaries are
/// guaranteed to match — a chunk shown in the editor overlay maps to
/// exactly the same source lines as the corresponding preview chunk.
///
/// The algorithm scans for multi-line blocks (fenced code today) and
/// then walks the document forward, accumulating roughly [chunkSize]
/// lines per chunk while only ending a chunk on a block boundary so an
/// atomic block is never bisected.
library;

import 'markdown_callout_syntax.dart';
import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';

/// Kinds of multi-line block recognized by the chunker. Single-line
/// content (paragraphs, headings, list items, blockquotes, rules,
/// single table rows) is intentionally **not** modeled — it is handled
/// implicitly line-by-line, keeping the block list sparse.
///
/// [callout] is a `>`-run whose first line is `> [!TYPE]`
/// (GitHub-style admonition); it is non-atomic so very long callouts
/// keep virtualizing, and the per-line offsets of its content are
/// unchanged from a plain blockquote.
///
/// [comment] is a `%%` block comment, from a `%%` line through the next
/// one (or the end); its lines render as nothing but their line slot.
///
/// [frontMatter] is a YAML properties block ([MarkdownChunker.frontMatterEnd]),
/// only ever at line `0`; like a comment it keeps only its line slots.
enum MarkdownBlockKind { codeFence, callout, comment, frontMatter }

/// A contiguous run of source lines forming one logical markdown block.
///
/// [startLine] is inclusive, [endLine] exclusive. [atomic] controls
/// chunking: an atomic block is never split across a chunk boundary
/// (used by future single-widget blocks such as tables/math), whereas a
/// non-atomic block (fenced code) renders line-by-line and may be
/// divided so virtualization survives very large blocks.
class MarkdownBlock {
  final MarkdownBlockKind kind;
  final int startLine;
  final int endLine;
  final bool atomic;

  const MarkdownBlock({
    required this.kind,
    required this.startLine,
    required this.endLine,
    required this.atomic,
  });

  /// Whether [lineIndex] falls within this block.
  bool contains(int lineIndex) => lineIndex >= startLine && lineIndex < endLine;
}

/// The result of a chunk-layout pass: the sparse multi-line [blocks]
/// and the sorted [chunkStartLines] (chunk `i` spans
/// `[chunkStartLines[i], chunkStartLines[i + 1])`, the last ending at
/// the document's line count).
class MarkdownChunkLayout {
  final List<MarkdownBlock> blocks;
  final List<int> chunkStartLines;

  const MarkdownChunkLayout({
    required this.blocks,
    required this.chunkStartLines,
  });
}

/// Pure functions that compute markdown chunk boundaries.
class MarkdownChunker {
  MarkdownChunker._();

  /// Hard cap on the chunk size produced by [adaptiveChunkSize].
  ///
  /// Line-precision scroll lands on the chunk containing a target line
  /// and interpolates an alignment within it, so larger chunks make
  /// scrolling coarser. 100 lines per chunk keeps the worst-case
  /// landing error to roughly one screen height even on huge documents
  /// while still capping the total item count of the virtualized list.
  static const int maxAdaptiveChunkSize = 100;

  /// Scales [baseChunkSize] up for very large documents so the chunk
  /// count (and therefore the virtualized list's item count) stays
  /// bounded. Never returns below [baseChunkSize] or above
  /// [maxAdaptiveChunkSize].
  static int adaptiveChunkSize(int lineCount, int baseChunkSize) {
    final int scaled;
    if (lineCount < 1000) {
      scaled = baseChunkSize;
    } else if (lineCount < 10000) {
      scaled = baseChunkSize * 2;
    } else if (lineCount < 50000) {
      scaled = baseChunkSize * 5;
    } else {
      scaled = baseChunkSize * 10;
    }
    if (scaled < baseChunkSize) return baseChunkSize;
    if (scaled > maxAdaptiveChunkSize) return maxAdaptiveChunkSize;
    return scaled;
  }

  /// The [blockStateAfter] / [fenceStateAfter] state outside every
  /// fence and block comment — the state a document starts in.
  static const int outsideBlock = 0;

  /// The [blockStateAfter] state inside a `%%` block comment. Every open
  /// fence packs to at least 6 ([fenceOpenerOf]), so the two never meet.
  static const int insideComment = 1;

  /// The [blockStateAfter] state inside a front matter block, which only
  /// [frontMatterEnd] can open — the opener at line `0` is a front
  /// matter only when a closer follows, which no one-line step can know —
  /// and which [blockStateAfter] closes at its `---` or `...` line.
  static const int insideFrontMatter = 2;

  /// The line after the front matter that opens the document, or `0`
  /// when there is none: line `0` is `---` with no indent, a later line
  /// is `---` or `...` with no indent (trailing blanks aside, as for every
  /// marker), and every line between them — at least one — is a YAML-ish
  /// property: `key: value`, `key:` or `- item`, indented by spaces or
  /// not. The first property is a key: YAML front matter is a mapping, so
  /// a `- item` only continues a key's list, and a list framed by two rules
  /// at the top of a note stays a list. A blank line, a fence or comment
  /// delimiter, or any other shape breaks the candidate, so a `---` rule
  /// above prose stays a rule. The scan stops at the first line that
  /// closes or breaks the block, so it costs no more than the block is
  /// long.
  static int frontMatterEnd(int lineCount, String Function(int index) lineAt) =>
      frontMatterEndAt(frontMatterStop(lineCount, lineAt), lineCount, lineAt);

  /// The line [frontMatterEnd]'s scan stops at: the closer, the first line
  /// that breaks the candidate, `0` when line `0` opens none, or
  /// [lineCount] when the properties run to the end. No line below it is
  /// read, so an edit below it cannot change [frontMatterEnd] — the bound
  /// the editor's line index re-reads within.
  static int frontMatterStop(int lineCount, String Function(int index) lineAt) {
    if (lineCount < 3 || !_isFrontMatterMarker(lineAt(0), _kDash)) return 0;
    for (int i = 1; i < lineCount; i++) {
      final String line = lineAt(i);
      if (i > 1 && isFrontMatterCloser(line)) return i;
      if (!_isFrontMatterProperty(line, itemAllowed: i > 1)) return i;
    }
    return lineCount;
  }

  /// [frontMatterEnd] from a [frontMatterStop] already read, so a caller
  /// that needs both scans once: the stop closes a front matter only when
  /// it is a closer below the first property.
  static int frontMatterEndAt(
    int stop,
    int lineCount,
    String Function(int index) lineAt,
  ) => stop > 1 && stop < lineCount && isFrontMatterCloser(lineAt(stop))
      ? stop + 1
      : 0;

  /// Whether [line] closes an open front matter: `---` or `...` with no
  /// indent and nothing but blanks after it.
  static bool isFrontMatterCloser(String line) =>
      _isFrontMatterMarker(line, _kDash) || _isFrontMatterMarker(line, _kDot);

  /// `ccc` at the start of [line], then nothing but blanks.
  static bool _isFrontMatterMarker(String line, int c) =>
      line.length >= 3 &&
      line.codeUnitAt(0) == c &&
      line.codeUnitAt(1) == c &&
      line.codeUnitAt(2) == c &&
      _blankFrom(line, 3);

  /// A YAML-ish property line: spaces, then `- ` (or a bare `-`), or a
  /// key of letters, digits, `_`, `-`, `.`, spaces or any non-ASCII unit,
  /// led by a letter, digit, `_` or non-ASCII unit, then `:` at the end or
  /// before a blank. The lead keeps every markdown construct out — a
  /// `#`, `>`, `$`, `%`, `|`, a backtick or a tilde never starts a key.
  /// Allocation-free. [itemAllowed] is false for the first property, which
  /// must be a key.
  static bool _isFrontMatterProperty(String line, {required bool itemAllowed}) {
    final int n = line.length;
    int i = 0;
    while (i < n && line.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i >= n) return false;
    final int lead = line.codeUnitAt(i);
    if (lead == _kDash) {
      return itemAllowed && (i + 1 == n || line.codeUnitAt(i + 1) == 0x20);
    }
    if (!_isKeyLead(lead)) return false;
    for (int j = i + 1; j < n; j++) {
      final int c = line.codeUnitAt(j);
      if (c == _kColon) {
        if (j + 1 == n) return true;
        final int after = line.codeUnitAt(j + 1);
        return after == 0x20 || after == 0x09 || after == 0x0D;
      }
      if (!_isKeyLead(c) && c != _kDash && c != _kDot && c != 0x20) {
        return false;
      }
    }
    return false;
  }

  static bool _isKeyLead(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c >= 0x80;

  /// The packed fence [line] would open, or [outsideBlock] when it opens
  /// none: any indent of spaces or tabs, then a run of three or more
  /// backticks whose info string (the rest of the line) holds no
  /// backtick — ```` ```npm i``` ```` is inline code, not a fence — or of
  /// three or more tildes with any info string. Packed as
  /// `(runLength << 1) | (tilde ? 1 : 0)`, so the state a scan carries
  /// is one comparable int that knows which closer ends it. The indent is
  /// unbounded because a fence under a list item sits at the item's
  /// content column (four spaces under a nested item, a tab in notes
  /// from Obsidian), which a stateless test cannot tell from top-level
  /// indented code — and ANTA renders no indented code (audit §3 row
  /// 3f), so the bound would only turn those fences into prose.
  /// Allocation-free (no trim).
  static int fenceOpenerOf(String line) {
    final int i = _blockIndent(line);
    if (i < 0) return outsideBlock;
    final int c = line.codeUnitAt(i);
    if (c != _kBacktick && c != _kTilde) return outsideBlock;
    int j = i + 1;
    while (j < line.length && line.codeUnitAt(j) == c) {
      j++;
    }
    final int run = j - i;
    if (run < 3) return outsideBlock;
    if (c == _kBacktick && line.indexOf('`', j) >= 0) return outsideBlock;
    return (run << 1) | (c == _kTilde ? 1 : 0);
  }

  /// Whether [line] closes the fence [opener] opened (a packed
  /// [fenceOpenerOf] value): any indent, a run of the opener's character
  /// at least as long as its run, then nothing but blanks — so ```` ```js ```` never closes, and `~~~` never
  /// closes a backtick fence.
  static bool closesFence(String line, int opener) {
    final int i = _blockIndent(line);
    if (i < 0) return false;
    final int c = (opener & 1) == 1 ? _kTilde : _kBacktick;
    int j = i;
    while (j < line.length && line.codeUnitAt(j) == c) {
      j++;
    }
    if (j - i < opener >> 1) return false;
    return _blankFrom(line, j);
  }

  /// Whether [line] opens or closes a `%%` block comment: any indent,
  /// `%%`, then nothing but blanks (trailing
  /// blanks are invisible in the editor, so they may not turn a marker
  /// into prose). A `%%note%%` line is an inline comment instead.
  static bool isCommentDelimiter(String line) {
    final int i = _blockIndent(line);
    if (i < 0 || i + 1 >= line.length) return false;
    return line.codeUnitAt(i) == _kPercent &&
        line.codeUnitAt(i + 1) == _kPercent &&
        _blankFrom(line, i + 2);
  }

  /// Whether [line] is shaped like a fence delimiter — it would open a
  /// fence outside one ([fenceOpenerOf]). The stateless question for a
  /// caller that reads one line alone; a caller walking lines in order
  /// steps [fenceStateAfter] instead, which also knows that ```` ```js ````
  /// inside a fence closes nothing.
  static bool isFenceDelimiter(String line) =>
      fenceOpenerOf(line) != outsideBlock;

  /// Whether [line] is blank — empty or whitespace by `trim`'s reading.
  static bool isBlankLine(String line) => line.trim().isEmpty;

  /// Whether [nextLine] continues the paragraph [line] ends — the one
  /// test every surface reads for a trailing `\`, which CommonMark breaks
  /// only inside a paragraph: elsewhere it stays text, so `- D:\a\` above
  /// `- D:\b\` keeps its backslash. The next line must hold prose: not
  /// blank, not a list item, not a [MarkdownLineShape.isLineLedConstruct]
  /// (headings, rules, fences, `%%` markers, tables, money rows). A quote
  /// line is continued only by a quote line whose content passes the same
  /// test and that is no deeper — a deeper `>` opens a nested quote, which
  /// interrupts the paragraph, where a shallower one is CommonMark's lazy
  /// continuation — and never by a callout lead, which opens a new block.
  /// A quote line never continues a non-quote one. [lineAfter], the line
  /// after [nextLine], rejects a setext heading's text line: the grammar
  /// makes only that one line the heading, so the paragraph ends above it.
  /// Whether either line sits in a fence or a comment is positional; the
  /// caller checks that.
  static bool continuesParagraph(
    String line,
    String? nextLine, [
    String? lineAfter,
  ]) {
    if (nextLine == null) return false;
    final bool quoted = MarkdownCalloutSyntax.isBlockquoteLine(line);
    if (quoted != MarkdownCalloutSyntax.isBlockquoteLine(nextLine)) {
      return false;
    }
    var restStart = 0;
    if (quoted) {
      final next = MarkdownCalloutSyntax.quoteMarkers(nextLine);
      final own = MarkdownCalloutSyntax.quoteMarkers(line);
      if (next != null && own != null && next.depth > own.depth) return false;
      if (MarkdownCalloutSyntax.parseLead(nextLine) != null) return false;
      restStart = next?.contentStart ?? 0;
    }
    final String rest = restStart == 0
        ? nextLine
        : nextLine.substring(restStart);
    return !isBlankLine(rest) &&
        MarkdownListSyntax.scanListShape(rest) < 0 &&
        !MarkdownLineShape.isLineLedConstruct(rest) &&
        MarkdownLineShape.setextLevelOf(nextLine, lineAfter) == 0;
  }

  /// Whether a [blockStateAfter] / [fenceStateAfter] state is inside a
  /// code fence.
  static bool isFenceState(int state) => state > insideFrontMatter;

  /// The fence state after [line] when [state] held before it: the one
  /// fence transition the preview's block scan, the editor's line index,
  /// the plain text and the width breaker step, so no surface can
  /// disagree about where a fence starts or ends. A line is a delimiter
  /// exactly when the state changes across it. Block comments are not
  /// seen — [blockStateAfter] adds them.
  static int fenceStateAfter(String line, int state) {
    if (state == outsideBlock) return fenceOpenerOf(line);
    return closesFence(line, state) ? outsideBlock : state;
  }

  /// [fenceStateAfter] with `%%` block comments: a comment opens only
  /// outside a fence (a `%%` line inside one is code), and nothing but
  /// the next `%%` line ends it (a fence line inside one is comment). An
  /// unclosed comment runs to the end like an unclosed fence. An open
  /// front matter ([insideFrontMatter], seeded by a caller that read
  /// [frontMatterEnd]) ends at its closer and opens nothing inside.
  static int blockStateAfter(String line, int state) {
    if (state == insideComment) {
      return isCommentDelimiter(line) ? outsideBlock : insideComment;
    }
    if (state == insideFrontMatter) {
      return isFrontMatterCloser(line) ? outsideBlock : insideFrontMatter;
    }
    final int next = fenceStateAfter(line, state);
    if (state == outsideBlock && next == outsideBlock) {
      return isCommentDelimiter(line) ? insideComment : outsideBlock;
    }
    return next;
  }

  /// Index of [line]'s first unit past its leading spaces and tabs, or
  /// `-1` for a line that is nothing but them.
  static int _blockIndent(String line) {
    int i = 0;
    while (i < line.length &&
        (line.codeUnitAt(i) == 0x20 || line.codeUnitAt(i) == 0x09)) {
      i++;
    }
    return i < line.length ? i : -1;
  }

  /// Whether [line] holds nothing but spaces, tabs and carriage returns
  /// from [from] on. A CR counts because the surfaces that split stored
  /// content on `\n` (the preview builder, the rows, the alert excerpt,
  /// the ledger) see `\r` at the end of every line of a CRLF import, and
  /// a closer or marker that carries one must still end its block.
  static bool _blankFrom(String line, int from) {
    for (int k = from; k < line.length; k++) {
      final int c = line.codeUnitAt(k);
      if (c != 0x20 && c != 0x09 && c != 0x0D) return false;
    }
    return true;
  }

  static const int _kBacktick = 0x60; // `
  static const int _kTilde = 0x7E; // ~
  static const int _kPercent = 0x25; // %
  static const int _kDash = 0x2D; // -
  static const int _kDot = 0x2E; // .
  static const int _kColon = 0x3A; // :

  /// Computes the full chunk layout for a document of [lineCount] lines.
  ///
  /// [chunkSize] is the **final** per-chunk line target; apply
  /// [adaptiveChunkSize] beforehand if adaptive scaling is desired (the
  /// preview renderer does). [lineAt] returns the raw text of a line —
  /// only the leading characters are inspected, so lazy line extraction
  /// stays cheap for very large documents.
  static MarkdownChunkLayout computeLayout({
    required int lineCount,
    required int chunkSize,
    required String Function(int lineIndex) lineAt,
  }) {
    final blocks = _scanBlocks(lineCount, lineAt);
    final starts = _computeChunkStarts(lineCount, chunkSize, blocks);
    return MarkdownChunkLayout(blocks: blocks, chunkStartLines: starts);
  }

  /// Scans the source once for multi-line blocks: fenced code (```, ~~~)
  /// and `%%` block comments, each including an unterminated block that
  /// runs to the end of the document, and callouts (a `>`-run led by
  /// `> [!TYPE]`). All are
  /// non-atomic (splittable) so virtualization of very large blocks is
  /// preserved. Blocks are emitted in source order (each is consumed
  /// whole before scanning resumes), so the list stays sorted by
  /// [MarkdownBlock.startLine] as the binary searches downstream require.
  static List<MarkdownBlock> _scanBlocks(
    int lineCount,
    String Function(int) lineAt,
  ) {
    final blocks = <MarkdownBlock>[];

    int i = frontMatterEnd(lineCount, lineAt);
    if (i > 0) {
      blocks.add(
        MarkdownBlock(
          kind: MarkdownBlockKind.frontMatter,
          startLine: 0,
          endLine: i,
          atomic: false,
        ),
      );
    }
    while (i < lineCount) {
      final line = lineAt(i);

      // Fenced code (``` … ``` or ~~~ … ~~~) and `%%` block comments, or
      // an unterminated one running to EOF.
      final open = blockStateAfter(line, outsideBlock);
      if (open != outsideBlock) {
        final start = i;
        i++;
        while (i < lineCount &&
            blockStateAfter(lineAt(i), open) != outsideBlock) {
          i++;
        }
        // Include the closing line when present; otherwise the block
        // runs to the end of the document.
        final end = i < lineCount ? i + 1 : lineCount;
        blocks.add(
          MarkdownBlock(
            kind: open == insideComment
                ? MarkdownBlockKind.comment
                : MarkdownBlockKind.codeFence,
            startLine: start,
            endLine: end,
            atomic: false,
          ),
        );
        i = end;
        continue;
      }

      // Callout: a blockquote run whose first line is `> [!TYPE]`.
      final type = MarkdownCalloutSyntax.blockStep(line, null);
      if (type != null) {
        final start = i;
        i++;
        while (i < lineCount &&
            MarkdownCalloutSyntax.blockStep(lineAt(i), type) == type) {
          i++;
        }
        blocks.add(
          MarkdownBlock(
            kind: MarkdownBlockKind.callout,
            startLine: start,
            endLine: i,
            atomic: false,
          ),
        );
        continue;
      }

      i++;
    }

    return blocks.isEmpty ? const [] : blocks;
  }

  /// Walks the document forward, accumulating ~[chunkSize] lines per
  /// chunk but only ending a chunk on a block boundary. Atomic blocks
  /// are kept whole (a chunk may overshoot the target); non-atomic
  /// blocks and plain lines may be divided at the target. Runs in
  /// O(chunks + blocks).
  static List<int> _computeChunkStarts(
    int lineCount,
    int chunkSize,
    List<MarkdownBlock> blocks,
  ) {
    if (lineCount <= 0) return const [0];
    final size = chunkSize < 1 ? 1 : chunkSize;

    final starts = <int>[];
    int line = 0;
    int blockIdx = 0;
    while (line < lineCount) {
      starts.add(line);
      final target = line + size;
      while (line < lineCount && line < target) {
        // Advance the block pointer past blocks fully behind `line`.
        while (blockIdx < blocks.length && blocks[blockIdx].endLine <= line) {
          blockIdx++;
        }
        final block =
            (blockIdx < blocks.length && blocks[blockIdx].startLine <= line)
            ? blocks[blockIdx]
            : null;
        if (block != null) {
          if (block.atomic) {
            // Keep atomic blocks whole even past the target.
            line = block.endLine;
          } else if (block.endLine <= target) {
            line = block.endLine;
          } else {
            line = target;
            break;
          }
        } else {
          // Plain lines: jump straight to the target or the next
          // multi-line block start, whichever comes first.
          final nextBlockStart = blockIdx < blocks.length
              ? blocks[blockIdx].startLine
              : lineCount;
          line = target < nextBlockStart ? target : nextBlockStart;
        }
      }
      // Guarantee forward progress.
      if (line <= starts.last) line = starts.last + 1;
    }
    return starts;
  }
}
