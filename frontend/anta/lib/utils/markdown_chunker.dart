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
enum MarkdownBlockKind { codeFence, callout }

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

  /// Whether [line] is a ``` code-fence delimiter: optional space/tab
  /// indent, then three backticks. The single fence grammar — shared by
  /// the preview's block scan below and the editor's positional line
  /// index ([MarkdownEditorLineIndex]), so the two surfaces can never
  /// disagree about where a fence starts. Allocation-free (no trim).
  static bool isFenceDelimiter(String line) {
    int i = 0;
    while (i < line.length) {
      final int c = line.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) break;
      i++;
    }
    return line.startsWith('```', i);
  }

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

  /// Scans the source once for multi-line blocks: fenced code (```),
  /// including an unterminated fence that runs to the end of the
  /// document, and callouts (a `>`-run led by `> [!TYPE]`). Both are
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

      // Fenced code block: ``` … ``` (or an unterminated fence to EOF).
      if (isFenceDelimiter(line)) {
        final start = i;
        i++;
        while (i < lineCount && !isFenceDelimiter(lineAt(i))) {
          i++;
        }
        // Include the closing fence line when present; otherwise the
        // fence runs to the end of the document.
        final end = i < lineCount ? i + 1 : lineCount;
        blocks.add(
          MarkdownBlock(
            kind: MarkdownBlockKind.codeFence,
            startLine: start,
            endLine: end,
            atomic: false,
          ),
        );
        i = end;
        continue;
      }

      // Callout: a blockquote run whose first line is `> [!TYPE]`. The
      // cheap `>`-prefix pre-filter keeps the common (non-quote) path to a
      // single trimLeft per line — parseLead (which re-trims) only runs on
      // blockquote lines. Continues across contiguous blockquote lines;
      // the first non-blockquote line (or EOF) ends it.
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('>') &&
          MarkdownCalloutSyntax.parseLead(line) != null) {
        final start = i;
        i++;
        while (i < lineCount &&
            MarkdownCalloutSyntax.isBlockquoteLine(lineAt(i))) {
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
