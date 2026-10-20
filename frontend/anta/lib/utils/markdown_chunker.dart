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
enum MarkdownBlockKind { codeFence, callout, comment }

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
  /// The one test every surface reads for "a non-blank line follows",
  /// the condition under which a trailing `\` is a hard break rather
  /// than text: CommonMark breaks a line only inside a paragraph.
  static bool isBlankLine(String line) => line.trim().isEmpty;

  /// Whether a [blockStateAfter] / [fenceStateAfter] state is inside a
  /// code fence.
  static bool isFenceState(int state) => state > insideComment;

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
  /// unclosed comment runs to the end like an unclosed fence.
  static int blockStateAfter(String line, int state) {
    if (state == insideComment) {
      return isCommentDelimiter(line) ? outsideBlock : insideComment;
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

    int i = 0;
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
