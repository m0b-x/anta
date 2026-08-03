import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';
import 'ghost_text.dart';
import 'markdown_callout_syntax.dart';
import 'markdown_chunker.dart';
import 'markdown_color_syntax.dart';
import 'markdown_line_height_calculator.dart';
import 'markdown_link_patterns.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';
import 'markdown_tag_syntax.dart';
import 'money_display_config.dart';

typedef LinkTapCallback = void Function(String url);
typedef CheckboxTapCallback = void Function(int start, int end, bool isChecked);

/// Invoked when a ghost-text run is engaged in the preview. [start] and
/// [end] are absolute source offsets covering the whole `{{ … }}` run
/// (markers included) so the caller can delete it and navigate.
typedef GhostTapCallback = void Function(int start, int end);

/// Invoked when a `#tag` is tapped in the preview. [tag] is the full
/// matched token including the leading `#`, so the caller can search for
/// it verbatim across notes.
typedef TagTapCallback = void Function(String tag);

/// Invoked when a `$$` total or `$?` net-change row is tapped in the
/// preview. [lineIndex] identifies the tapped money line so the caller
/// can collect and present the ledger entries feeding its value.
typedef MoneyTapCallback = void Function(int lineIndex);

/// Style configuration for line-based markdown rendering.
class LineMarkdownStyle {
  final double baseFontSize;
  final Color textColor;
  final Color primaryColor;
  final Color codeBackground;
  final Color blockquoteColor;
  final Color highlightColor;
  final Color currentHighlightColor;

  /// Colour for ghost-text placeholders (`{{ … }}`), rendered dimmed.
  final Color ghostColor;

  /// Background colour for `==highlighted==` ("marker"/highlighter) text.
  /// Distinct from [highlightColor] (search) so the two never read the
  /// same.
  final Color markColor;

  /// Whether the active theme is dark. Lets the renderer pick the
  /// light/dark variant of semantic palettes (e.g. callout accents)
  /// without re-deriving brightness from a colour's luminance.
  final bool isDark;

  const LineMarkdownStyle({
    required this.baseFontSize,
    required this.textColor,
    required this.primaryColor,
    required this.codeBackground,
    required this.blockquoteColor,
    required this.highlightColor,
    required this.currentHighlightColor,
    required this.ghostColor,
    required this.markColor,
    required this.isDark,
  });

  factory LineMarkdownStyle.fromTheme(ThemeData theme, double fontSize) {
    final isDark = theme.brightness == Brightness.dark;
    final base = theme.textTheme.bodyLarge?.color ?? Colors.black;
    return LineMarkdownStyle(
      baseFontSize: fontSize,
      textColor: base,
      primaryColor: theme.colorScheme.primary,
      codeBackground: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      blockquoteColor: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      highlightColor: theme.colorScheme.primaryContainer,
      currentHighlightColor: theme.colorScheme.primary.withValues(alpha: 0.5),
      ghostColor: base.withValues(alpha: 0.45),
      markColor: isDark
          ? MarkdownConstants.markBackgroundDark
          : MarkdownConstants.markBackgroundLight,
      isDark: isDark,
    );
  }
}

/// Renders markdown line-by-line for precise scroll positioning.
/// Lines are grouped into chunks for better performance with large documents.
///
/// Performance optimizations for large documents (100k+ lines):
/// - LRU cache limits memory usage for chunk spans
/// - Lazy code block detection (computed per-chunk, not upfront)
/// - Adaptive chunk sizing based on document size
/// - Line offsets computed once, lines split lazily
class LineBasedMarkdownBuilder {
  final LineMarkdownStyle style;
  final LinkTapCallback? onLinkTap;
  final CheckboxTapCallback? onCheckboxTap;
  final GhostTapCallback? onGhostTap;
  final TagTapCallback? onTagTap;
  final MoneyTapCallback? onMoneyTap;
  final List<TextRange>? searchHighlights;
  final int? currentHighlightIndex;

  /// The money ledger's display configuration — master switch, start
  /// balance, currency, localized error strings — as one value-equal
  /// object. Display-only inputs: parsing and arithmetic stay
  /// currency-agnostic. When disabled, `$` lines never enter the money
  /// dispatch branch and the ledger fold in [prepare] is skipped.
  final MoneyDisplayConfig moneyConfig;

  /// Resolved colour set for `{name:text}` runs and `==name:text==`
  /// highlights. Presets-only unless the user defined custom colours.
  final MarkdownColorPalette colorPalette;

  /// Number of lines per chunk - configurable for balance between precision and performance
  final int linesPerChunk;

  /// Maximum number of chunks to keep in cache (LRU eviction)
  static const int _maxCachedChunks = 50;

  /// Threshold for "large document" optimizations
  static const int _largeDocumentThreshold = 10000;

  // Precomputed line offsets for fast lookup
  List<int> _lineOffsets = [];
  String _source = '';

  /// Lazily populated lines - only extracted when needed
  List<String>? _lines;
  int _lineCount = 0;

  /// LRU cache for built chunk spans (chunkIndex -> spans)
  /// Uses a simple LRU by tracking access order
  final Map<int, List<InlineSpan>> _chunkCache = {};
  final List<int> _cacheAccessOrder = [];

  /// Cache for gesture recognizers to prevent memory leaks
  final Map<String, TapGestureRecognizer> _linkRecognizers = {};
  final Map<int, TapGestureRecognizer> _checkboxRecognizers = {};

  /// Sparse, sorted, non-overlapping list of multi-line blocks (e.g.
  /// fenced code). Single-line content is represented implicitly (any
  /// line not covered by a span is its own one-line block), so this
  /// stays O(number of multi-line blocks) regardless of document size.
  ///
  /// Drives two things: (1) code-fence membership lookups (replacing
  /// the old per-chunk code-block state caches) and (2) block-aligned
  /// chunk boundaries so an atomic block is never bisected by a chunk.
  List<MarkdownBlock> _multiLineBlocks = const [];

  /// Start line (inclusive) of each chunk. Chunk `i` spans
  /// `[_chunkStartLines[i], _chunkStartLines[i + 1])` with the final
  /// chunk ending at [_lineCount]. Built once in [prepare] by walking
  /// blocks so boundaries land on block edges (atomic blocks are kept
  /// whole; splittable blocks like code fences may still be divided).
  List<int> _chunkStartLines = const [];

  /// Display value (cents) for each money line, keyed by line index:
  /// the running balance after the line, or for `$?` delta lines the
  /// net change since the last `$=` anchor. `null` when the note has no
  /// money lines. Computed once per [prepare] by folding
  /// [MarkdownMoneySyntax] ops top to bottom, so chunk rebuilds always
  /// read a consistent whole-document ledger.
  Map<int, int>? _moneyValues;

  LineBasedMarkdownBuilder({
    required this.style,
    this.onLinkTap,
    this.onCheckboxTap,
    this.onGhostTap,
    this.onTagTap,
    this.onMoneyTap,
    this.searchHighlights,
    this.currentHighlightIndex,
    this.moneyConfig = MoneyDisplayConfig.disabled,
    this.colorPalette = MarkdownColorPalette.presets,
    this.linesPerChunk = 10,
  });

  /// Precompute line offsets for the source text.
  /// For large documents, lines are extracted lazily to reduce memory pressure.
  /// Returns list of lines for rendering.
  List<String> prepare(String source) {
    _source = source;
    clearCache(); // Also disposes recognizers and clears code block cache

    // Compute line offsets in a single pass without splitting
    // This is O(n) but doesn't allocate 100k string objects
    _lineOffsets = [0];
    _lineCount = 0;

    for (int i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) {
        // '\n'
        _lineOffsets.add(i + 1);
        _lineCount++;
      }
    }
    // Account for last line if no trailing newline
    if (source.isEmpty || source.codeUnitAt(source.length - 1) != 10) {
      _lineCount++;
    }

    // For small documents, pre-split lines (faster access)
    // For large documents, extract lazily to save memory
    if (_lineCount < _largeDocumentThreshold) {
      _lines = source.split('\n');
    } else {
      _lines = null; // Will extract on demand
    }

    // Classify multi-line blocks (fenced code today) and compute
    // block-aligned chunk boundaries via the shared chunker so the
    // editor's debug overlay can reproduce identical boundaries.
    _buildChunkLayout();

    // Fold the money ledger after block classification so fence-inert
    // lines are known. One pass over the source; only `$`-led lines
    // outside multi-line blocks pay for a parse.
    _computeMoneyLedger();

    return _lines ?? [];
  }

  /// Folds every money line's op into a running balance, top to bottom
  /// (grammar + arithmetic from [MarkdownMoneySyntax], shared with the
  /// editor's line index). The lead-character probe reads [_source]
  /// directly so non-money lines allocate nothing even on large
  /// documents.
  void _computeMoneyLedger() {
    _moneyValues = null;
    if (!moneyConfig.enabled) return;
    Map<int, int>? values;
    // All fold rules (error-inertness, history/checkpoint appends,
    // period moves) live in [MoneyFold] — never inline them here.
    final fold = MoneyFold(moneyConfig.startCents);
    final source = _source;
    for (var i = 0; i < _lineCount; i++) {
      final start = _lineOffsets[i];
      final end = i + 1 < _lineOffsets.length
          ? _lineOffsets[i + 1] - 1
          : source.length;
      if (!MarkdownMoneySyntax.leadsWithMoneyInRange(source, start, end)) {
        continue;
      }
      if (_blockForLine(i) != null) continue;
      final m = MarkdownMoneySyntax.parse(_getLine(i));
      if (m == null) continue;
      (values ??= <int, int>{})[i] = fold.step(m);
    }
    _moneyValues = values;
  }

  /// Delegates to [MarkdownChunker] to classify multi-line blocks and
  /// compute the block-aligned chunk table. [linesPerChunk] is already
  /// the adaptive size chosen by [MarkdownRenderService], so it is used
  /// directly as the chunk target here.
  void _buildChunkLayout() {
    final layout = MarkdownChunker.computeLayout(
      lineCount: _lineCount,
      chunkSize: linesPerChunk,
      lineAt: _getLine,
    );
    _multiLineBlocks = layout.blocks;
    _chunkStartLines = layout.chunkStartLines;
  }

  /// Get a specific line by index (lazy extraction for large docs)
  String _getLine(int lineIndex) {
    if (_lines != null) {
      return lineIndex < _lines!.length ? _lines![lineIndex] : '';
    }

    // Lazy extraction from source
    if (lineIndex < 0 || lineIndex >= _lineCount) return '';

    final start = _lineOffsets[lineIndex];
    final end = lineIndex + 1 < _lineOffsets.length
        ? _lineOffsets[lineIndex + 1] -
              1 // -1 to exclude newline
        : _source.length;

    if (start >= _source.length) return '';
    return _source.substring(start, end.clamp(start, _source.length));
  }

  /// Returns the multi-line block covering [lineIndex], or `null` when
  /// the line is plain single-line content. O(log n) binary search
  /// over the sparse [_multiLineBlocks] list.
  MarkdownBlock? _blockForLine(int lineIndex) {
    final blocks = _multiLineBlocks;
    if (blocks.isEmpty) return null;
    int low = 0;
    int high = blocks.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final b = blocks[mid];
      if (lineIndex < b.startLine) {
        high = mid - 1;
      } else if (lineIndex >= b.endLine) {
        low = mid + 1;
      } else {
        return b;
      }
    }
    return null;
  }

  /// Whether [lineIndex] is part of a fenced code block (including the
  /// opening and closing fence lines). Replaces the former per-chunk
  /// code-block state caches with a single block lookup.
  bool _lineInCodeFence(int lineIndex) {
    final block = _blockForLine(lineIndex);
    return block != null && block.kind == MarkdownBlockKind.codeFence;
  }

  /// The number of chunks. Driven by the block-aligned chunk table.
  int get chunkCount => _chunkStartLines.length;

  /// First source line (inclusive) of [chunkIndex].
  int chunkStartLine(int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex >= _chunkStartLines.length) return 0;
    return _chunkStartLines[chunkIndex];
  }

  /// Number of source lines contained in [chunkIndex].
  int chunkLineCount(int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex >= _chunkStartLines.length) return 0;
    final start = _chunkStartLines[chunkIndex];
    final end = chunkIndex + 1 < _chunkStartLines.length
        ? _chunkStartLines[chunkIndex + 1]
        : _lineCount;
    return end - start;
  }

  /// The chunk index that contains [lineIndex]. O(log n) binary search
  /// over [_chunkStartLines] — replaces the former
  /// `lineIndex ~/ linesPerChunk` assumption now that chunks are
  /// block-aligned and may hold variable line counts.
  int chunkIndexForLine(int lineIndex) {
    final starts = _chunkStartLines;
    if (starts.length <= 1) return 0;
    int low = 0;
    int high = starts.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lineIndex < starts[mid]) {
        high = mid - 1;
      } else if (mid + 1 < starts.length && lineIndex >= starts[mid + 1]) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return (low).clamp(0, starts.length - 1);
  }

  /// Whether this is a large document with lazy optimizations
  bool get isLargeDocument => _lineCount >= _largeDocumentThreshold;

  /// Total line count
  int get lineCount => _lineCount;

  /// Get chunk index for a given source offset.
  /// Uses binary search for O(log n) performance.
  int getChunkIndexForOffset(int sourceOffset) {
    final lineIndex = getLineIndexForOffset(sourceOffset);
    return chunkIndexForLine(lineIndex);
  }

  /// Get line index for a given source offset.
  int getLineIndexForOffset(int sourceOffset) {
    if (_lineOffsets.length < 2) return 0;

    int low = 0;
    int high = _lineOffsets.length - 2;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final lineStart = _lineOffsets[mid];
      final lineEnd = _lineOffsets[mid + 1];

      if (sourceOffset < lineStart) {
        high = mid - 1;
      } else if (sourceOffset >= lineEnd) {
        low = mid + 1;
      } else {
        return mid;
      }
    }

    return low.clamp(0, _lineOffsets.length - 2);
  }

  /// Get the source offset range for a given line index.
  List<int> getLineOffsetRange(int lineIndex) {
    if (lineIndex < 0 || lineIndex >= _lineOffsets.length - 1) {
      return [0, 0];
    }
    return [_lineOffsets[lineIndex], _lineOffsets[lineIndex + 1]];
  }

  /// Get the source offset range for a given chunk index.
  List<int> getChunkOffsetRange(int chunkIndex) {
    final startLine = chunkStartLine(chunkIndex);
    final endLine = startLine + chunkLineCount(chunkIndex);

    if (startLine >= _lineOffsets.length - 1) return [0, 0];

    final startOffset = _lineOffsets[startLine];
    final endOffset = endLine < _lineOffsets.length
        ? _lineOffsets[endLine]
        : _lineOffsets.last;

    return [startOffset, endOffset];
  }

  /// Build spans for a chunk of lines (cached with LRU eviction).
  List<InlineSpan> buildChunk(int chunkIndex) {
    // Check cache first and update LRU order
    if (_chunkCache.containsKey(chunkIndex)) {
      _updateCacheAccess(chunkIndex);
      return _chunkCache[chunkIndex]!;
    }

    final startLine = chunkStartLine(chunkIndex);
    final endLine = startLine + chunkLineCount(chunkIndex);

    final spans = <InlineSpan>[];

    for (int i = startLine; i < endLine; i++) {
      if (i >= _lineCount) break;

      final line = _getLine(i);
      final lineSpan = buildLine(line, i, chunkIndex);

      spans.add(lineSpan);

      // Add newline between lines (except after last line in chunk)
      if (i < endLine - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    _addToCache(chunkIndex, spans);
    return spans;
  }

  /// Add chunk to cache with LRU eviction
  void _addToCache(int chunkIndex, List<InlineSpan> spans) {
    // Evict oldest if at capacity
    while (_cacheAccessOrder.length >= _maxCachedChunks) {
      final oldestChunk = _cacheAccessOrder.removeAt(0);
      _chunkCache.remove(oldestChunk);
      // Also clean up related recognizers for this chunk
      _cleanupChunkRecognizers(oldestChunk);
    }

    _chunkCache[chunkIndex] = spans;
    _cacheAccessOrder.add(chunkIndex);
  }

  /// Update LRU access order
  void _updateCacheAccess(int chunkIndex) {
    _cacheAccessOrder.remove(chunkIndex);
    _cacheAccessOrder.add(chunkIndex);
  }

  /// Clean up recognizers for a specific chunk
  void _cleanupChunkRecognizers(int chunkIndex) {
    final startLine = chunkStartLine(chunkIndex);
    final endLine = startLine + chunkLineCount(chunkIndex);

    // Remove checkbox recognizers for this chunk's lines
    for (int i = startLine; i < endLine; i++) {
      final recognizer = _checkboxRecognizers.remove(i);
      recognizer?.dispose();
    }

    // Remove link/tag/ghost recognizers whose source offset falls inside
    // this chunk. For 'img:'/'tag:'/'ghost:' keys (and chunk-prefixed
    // ones) parts[1] is the numeric source offset used for the range test.
    _linkRecognizers.removeWhere((key, recognizer) {
      if (key.startsWith('$chunkIndex:') ||
          key.startsWith('img:') ||
          key.startsWith('tag:') ||
          key.startsWith('ghost:')) {
        // Check if the offset falls within this chunk
        final parts = key.split(':');
        if (parts.length >= 2) {
          final offset = int.tryParse(parts[1]);
          if (offset != null) {
            final chunkStart = _lineOffsets[startLine];
            final chunkEnd = endLine < _lineOffsets.length
                ? _lineOffsets[endLine]
                : _source.length;
            if (offset >= chunkStart && offset < chunkEnd) {
              recognizer.dispose();
              return true;
            }
          }
        }
      }
      return false;
    });
  }

  /// Clear the span cache and dispose gesture recognizers
  void clearCache() {
    _chunkCache.clear();
    _cacheAccessOrder.clear();
    // Dispose all gesture recognizers to prevent memory leaks
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
    for (final recognizer in _checkboxRecognizers.values) {
      recognizer.dispose();
    }
    _checkboxRecognizers.clear();
  }

  /// Dispose all resources - call when builder is no longer needed
  void dispose() {
    clearCache();
  }

  /// Get the relative height scale for each line in a chunk.
  /// Returns a list of scales representing actual rendered height ratios.
  /// Normal text = 1.0, H1 = 2.0, empty lines = 0.5, etc.
  /// These are actual height ratios, not font size multipliers.
  /// Used for accurate double-tap line detection.
  List<double> getLineHeightScales(int chunkIndex) {
    final startLine = chunkStartLine(chunkIndex);
    final endLine = startLine + chunkLineCount(chunkIndex);
    final scales = <double>[];

    for (int i = startLine; i < endLine; i++) {
      if (i >= _lineCount) break;
      final line = _getLine(i);
      final isInCodeBlock = _lineInCodeFence(i);
      scales.add(
        MarkdownLineHeightCalculator.getLineHeightScale(
          line,
          isInsideCodeBlock: isInCodeBlock,
        ),
      );
    }

    return scales;
  }

  /// Build a TextSpan for a single line with inline markdown formatting.
  TextSpan buildLine(String line, int lineIndex, [int? chunkIndex]) {
    // [_lineOffsets] holds one start offset per line. The final line of a
    // document with no trailing newline is still a valid index here, so
    // the guard is `< length` (mirroring [lineEnd]'s `+ 1 < length`); an
    // earlier `< length - 1` dropped the last line's offset to 0, which
    // corrupted search-highlight and tap offsets on that line.
    final lineStart = lineIndex < _lineOffsets.length
        ? _lineOffsets[lineIndex]
        : 0;
    final lineEnd = lineIndex + 1 < _lineOffsets.length
        ? _lineOffsets[lineIndex + 1] -
              1 // -1 to exclude newline
        : _source.length;

    final baseStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
    );

    // Detect line type and apply appropriate styling
    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;

    // Multi-line block lookup (single binary search). Code-fence lines
    // render monospaced; callout lines (`> [!TYPE]` runs) render with a
    // coloured left bar + icon + tint. The optional [chunkIndex] is
    // retained for call-site compatibility but no longer needed here.
    final block = _blockForLine(lineIndex);
    if (block != null && block.kind == MarkdownBlockKind.codeFence) {
      return _buildCodeBlockLine(line, trimmed, lineStart, lineEnd);
    }
    if (block != null && block.kind == MarkdownBlockKind.callout) {
      return _buildCalloutLine(line, lineIndex, block, lineStart, lineEnd);
    }

    // Check for different markdown patterns
    if (trimmed.isEmpty) {
      // Empty line - render as minimal height spacer
      return TextSpan(
        text: ' ',
        style: baseStyle.copyWith(
          fontSize: style.baseFontSize * MarkdownConstants.emptyLineScale,
        ),
      );
    }

    // Money ledger lines (`$+ 12.50 label`, `$$` total), optionally
    // header-prefixed (`## $$ label`). Grammar comes from the shared
    // [MarkdownMoneySyntax]; the running balance was folded once in
    // [prepare]. Cheap probe: only `$`-led (or `#…$`-led) lines parse;
    // a `#`-led line that fails the parse falls through to the normal
    // heading branch below.
    if (moneyConfig.enabled && MarkdownMoneySyntax.leadsWithMoney(line)) {
      final money = MarkdownMoneySyntax.parse(line);
      if (money != null) {
        return _buildMoneyLine(
          line,
          money,
          lineIndex,
          lineStart,
          lineEnd,
          baseStyle,
        );
      }
    }

    // Image detection (before links since they have similar syntax)
    final imageMatch = _MarkdownPatterns.image.firstMatch(trimmed);
    if (imageMatch != null) {
      return _buildImage(
        imageMatch.group(1) ?? '',
        imageMatch.group(2) ?? '',
        lineStart,
        lineEnd,
      );
    }

    // Table row detection
    if (_MarkdownPatterns.tableRow.hasMatch(trimmed)) {
      return _buildTableRow(trimmed, lineStart, lineEnd);
    }

    // ATX heading: 1–6 leading '#' that must be followed by a space or
    // be the entire line. `#tag` (no space) and `#######` (7+) are NOT
    // headings — they fall through to paragraph rendering (CommonMark).
    if (trimmed.startsWith('#')) {
      int hashes = 0;
      while (hashes < trimmed.length && trimmed.codeUnitAt(hashes) == 0x23) {
        hashes++;
      }
      final followedBySpaceOrEol =
          hashes == trimmed.length || trimmed.codeUnitAt(hashes) == 0x20;
      if (hashes <= 6 && followedBySpaceOrEol) {
        final hasSpace = hashes < trimmed.length;
        final contentOffset = lineStart + indent + hashes + (hasSpace ? 1 : 0);
        return _buildHeading(
          trimmed.substring(hashes).trim(),
          hashes,
          contentOffset,
          lineEnd,
        );
      }
    }

    // List items (bullet / ordered / task) via the shared syntax so the
    // preview and the editor agree on exactly what is a list. Offsets are
    // line-relative, so add [lineStart] for absolute source positions.
    final listItem = MarkdownListSyntax.parse(line);
    if (listItem != null) {
      switch (listItem.kind) {
        case MarkdownListKind.task:
          return _buildCheckboxLine(
            listItem.content,
            listItem.checked,
            listItem.level,
            lineStart + listItem.bracketStart,
            lineStart + listItem.contentStart,
            lineEnd,
            lineIndex,
          );
        case MarkdownListKind.bullet:
          return _buildListItem(
            listItem.content,
            listItem.level,
            lineStart + listItem.contentStart,
            lineEnd,
          );
        case MarkdownListKind.ordered:
          return _buildOrderedListItem(
            listItem.content,
            listItem.marker,
            listItem.delimiter,
            listItem.level,
            lineStart + listItem.contentStart,
            lineEnd,
          );
      }
    }

    // Blockquote
    if (trimmed.startsWith('>')) {
      // Calculate content offset: skip indent + '>' + optional space
      final afterArrow = trimmed.substring(1);
      final spaceAfter = afterArrow.startsWith(' ') ? 1 : 0;
      final contentOffset = lineStart + indent + 1 + spaceAfter;
      return _buildBlockquote(afterArrow.trim(), contentOffset, lineEnd);
    }

    // Horizontal rule
    if (_MarkdownPatterns.horizontalRule.hasMatch(trimmed)) {
      return _buildHorizontalRule();
    }

    // Code block marker (```)
    if (trimmed.startsWith('```')) {
      return TextSpan(
        text: line,
        style: baseStyle.copyWith(
          fontFamily: 'monospace',
          color: style.textColor.withValues(alpha: 0.6),
        ),
      );
    }

    // Regular paragraph - apply inline formatting
    return _buildInlineFormatted(line, baseStyle, lineStart, lineEnd);
  }

  TextSpan _buildHeading(
    String text,
    int level,
    int contentStart,
    int lineEnd,
  ) {
    final scale = switch (level) {
      1 => MarkdownConstants.h1Scale,
      2 => MarkdownConstants.h2Scale,
      3 => MarkdownConstants.h3Scale,
      4 => MarkdownConstants.h4Scale,
      5 => MarkdownConstants.h5Scale,
      _ => MarkdownConstants.h6Scale,
    };

    final headingStyle = TextStyle(
      fontSize: style.baseFontSize * scale,
      fontWeight: FontWeight.bold,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
    );

    return _buildInlineFormatted(text, headingStyle, contentStart, lineEnd);
  }

  TextSpan _buildCheckboxLine(
    String text,
    bool isChecked,
    int level,
    int bracketStart,
    int contentStart,
    int lineEnd,
    int lineIndex,
  ) {
    final checkboxChar = isChecked ? '☒' : '☐';

    final baseStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
    );

    final contentStyle = isChecked
        ? baseStyle.copyWith(
            color: style.textColor.withValues(alpha: 0.5),
            decoration: TextDecoration.lineThrough,
          )
        : baseStyle;

    // The bracket span "[x]" / "[ ]" is always 3 source chars wide.
    final bracketEnd = bracketStart + 3;

    // Cache checkbox recognizer by line index to prevent memory leaks
    TapGestureRecognizer? checkboxRecognizer;
    if (onCheckboxTap != null) {
      _checkboxRecognizers[lineIndex] ??= TapGestureRecognizer()
        ..onTap = () => onCheckboxTap!(bracketStart, bracketEnd, isChecked);
      checkboxRecognizer = _checkboxRecognizers[lineIndex];
    }

    // Add formatted content - use contentStart for correct highlighting
    final contentSpan = _buildInlineFormatted(
      text,
      contentStyle,
      contentStart,
      lineEnd,
    );

    // WidgetSpan gives a hanging indent so wrapped lines align under the
    // content; nesting is a left padding proportional to [level].
    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: EdgeInsets.only(left: _listIndent(level)),
            child: DefaultTextStyle(
              style: baseStyle,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: checkboxRecognizer?.onTap,
                    child: Text(
                      '$checkboxChar ',
                      style: baseStyle.copyWith(
                        color: isChecked
                            ? style.primaryColor
                            : style.textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Expanded(child: Text.rich(contentSpan, style: contentStyle)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _buildListItem(
    String text,
    int level,
    int contentStart,
    int lineEnd,
  ) {
    final bullet = _bulletForLevel(level);

    final baseStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
    );

    final contentSpan = _buildInlineFormatted(
      text,
      baseStyle,
      contentStart,
      lineEnd,
    );

    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: EdgeInsets.only(left: _listIndent(level)),
            child: DefaultTextStyle(
              style: baseStyle,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$bullet ',
                    style: baseStyle.copyWith(
                      color: style.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(child: Text.rich(contentSpan, style: baseStyle)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _buildOrderedListItem(
    String text,
    String number,
    String delimiter,
    int level,
    int contentStart,
    int lineEnd,
  ) {
    final baseStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
    );

    final contentSpan = _buildInlineFormatted(
      text,
      baseStyle,
      contentStart,
      lineEnd,
    );

    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: EdgeInsets.only(left: _listIndent(level)),
            child: DefaultTextStyle(
              style: baseStyle,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$number$delimiter ',
                    style: baseStyle.copyWith(
                      color: style.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(child: Text.rich(contentSpan, style: baseStyle)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Visual left-indent (in logical pixels) for a list item at the given
  /// nesting [level]. One em per level keeps nesting readable at any font
  /// size; this is decorative only and never affects source offsets.
  double _listIndent(int level) => level * style.baseFontSize;

  /// The bullet glyph for an unordered item at [level], cycling
  /// `•` → `◦` → `▪` so nesting depth is visually distinguishable.
  String _bulletForLevel(int level) {
    switch (level % 3) {
      case 0:
        return '•';
      case 1:
        return '◦';
      default:
        return '▪';
    }
  }

  TextSpan _buildBlockquote(String text, int contentStart, int lineEnd) {
    final quoteStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      fontStyle: FontStyle.italic,
      color: style.textColor.withValues(alpha: 0.8),
    );

    final children = <InlineSpan>[
      TextSpan(
        text: '┃ ',
        style: quoteStyle.copyWith(
          color: style.blockquoteColor,
          fontStyle: FontStyle.normal,
        ),
      ),
    ];

    final contentSpan = _buildInlineFormatted(
      text,
      quoteStyle,
      contentStart,
      lineEnd,
    );
    _appendFlattened(children, contentSpan);

    return TextSpan(children: children);
  }

  /// Builds one line of a callout block (`> [!TYPE]` run). [block] is the
  /// enclosing callout; [lineIndex] is the absolute source line.
  ///
  /// The callout type is resolved from the block's lead line so every
  /// body line shares the same accent. Rendering mirrors [_buildBlockquote]
  /// (a coloured left bar + flattened inline content) but adds the type's
  /// tint and an icon/label header on the lead line. Per-line content
  /// offsets are identical to a plain blockquote, so search highlighting
  /// and scroll mapping are unaffected.
  TextSpan _buildCalloutLine(
    String line,
    int lineIndex,
    MarkdownBlock block,
    int lineStart,
    int lineEnd,
  ) {
    // Resolve the callout type from the block's lead line (reuse [line]
    // when this IS the lead, avoiding a redundant lazy line extraction).
    final leadLine = lineIndex == block.startLine
        ? line
        : _getLine(block.startLine);
    final lead = MarkdownCalloutSyntax.parseLead(leadLine);
    final type = lead?.type ?? MarkdownCalloutType.note;
    final accent = _calloutAccent(type);
    final tint = accent.withValues(alpha: style.isDark ? 0.16 : 0.10);

    final lineStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
      backgroundColor: tint,
    );
    final accentStyle = lineStyle.copyWith(
      color: accent,
      fontWeight: FontWeight.bold,
    );

    // Coloured left bar (tinted background carries down every line so the
    // run reads as one block).
    final children = <InlineSpan>[TextSpan(text: '┃ ', style: accentStyle)];

    if (lineIndex == block.startLine) {
      // Lead line: icon + header. The `[!TYPE]` token is consumed as
      // decorative chrome (like emphasis markers); an optional custom
      // title stays offset-mapped so it is still searchable.
      children.add(
        TextSpan(
          text: '${MarkdownCalloutSyntax.iconFor(type)} ',
          style: lineStyle,
        ),
      );
      if (lead != null && lead.title.isNotEmpty) {
        _appendFlattened(
          children,
          _buildInlineFormatted(
            lead.title,
            accentStyle,
            lineStart + lead.titleStart,
            lineEnd,
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: MarkdownCalloutSyntax.labelFor(type),
            style: accentStyle,
          ),
        );
      }
    } else {
      // Body line: the content after the `>` marker, inline-formatted at
      // its true source offset (mirrors the blockquote offset maths).
      final trimmed = line.trimLeft();
      final indent = line.length - trimmed.length;
      final afterArrow = trimmed.startsWith('>')
          ? trimmed.substring(1)
          : trimmed;
      final spaceAfter = afterArrow.startsWith(' ') ? 1 : 0;
      final contentOffset = lineStart + indent + 1 + spaceAfter;
      _appendFlattened(
        children,
        _buildInlineFormatted(
          afterArrow.trim(),
          lineStyle,
          contentOffset,
          lineEnd,
        ),
      );
    }

    return TextSpan(children: children);
  }

  /// Builds a money-ledger row. The `$x` marker is consumed as
  /// decorative chrome (like a callout's `[!TYPE]` token) and replaced
  /// by a sign glyph in the op's accent; the amount stays an
  /// offset-mapped source run so search highlighting lands on it; the
  /// optional label renders inline-formatted at its true offset. Op
  /// rows carry a dimmed computed running balance; `$$` total rows show
  /// the balance itself, pill-tinted like a tag, red when negative.
  /// Computed values are not source text, so they carry no offsets and
  /// are invisible to search — by design.
  ///
  /// A heading prefix scales the whole row like [_buildHeading] (the
  /// hashes are chrome). A resolved accent token overrides the semantic
  /// accent for the value; an unresolved one renders literally at its
  /// source offset so nothing is silently eaten.
  TextSpan _buildMoneyLine(
    String line,
    MoneyLineMatch m,
    int lineIndex,
    int lineStart,
    int lineEnd,
    TextStyle baseStyle,
  ) {
    final dark = style.isDark;
    // The list-marker prefix is chrome *outside* the row's own styling:
    // it renders exactly like [_buildListItem]'s marker, so a bulleted
    // money row aligns with its plain siblings. Captured before the
    // heading/emphasis mutations below — a heading-scaled bullet is
    // bigger and an italic one leans, either of which breaks the list's
    // left edge.
    final listStyle = baseStyle;

    // Error rows render as a warning that keeps the typed source
    // visible and offset-mapped (search still lands on it, nothing the
    // user wrote disappears); the message trails as computed text like
    // the balance echoes. Heading scale is deliberately not applied —
    // a broken row renders compact.
    if (MarkdownMoneySyntax.hasError(m)) {
      final warn = MarkdownConstants.moneyWarning(dark: dark);
      final warnStyle = baseStyle.copyWith(
        color: warn,
        backgroundColor: warn.withValues(alpha: 0.1),
      );
      return _wrapMoneyList(
        line,
        m,
        TextSpan(
          children: [
            TextSpan(
              text: '! ',
              style: warnStyle.copyWith(fontWeight: FontWeight.bold),
            ),
            _applyHighlighting(
              line.substring(m.markerStart),
              warnStyle,
              lineStart + m.markerStart,
            ),
            TextSpan(
              text: '  — ${moneyConfig.errorText(m.error!)}',
              style: baseStyle.copyWith(color: warn.withValues(alpha: 0.7)),
            ),
          ],
        ),
        baseStyle,
        listStyle,
      );
    }

    final value = _moneyValues?[lineIndex] ?? 0;
    if (m.headerLevel > 0) {
      final scale = switch (m.headerLevel) {
        1 => MarkdownConstants.h1Scale,
        2 => MarkdownConstants.h2Scale,
        3 => MarkdownConstants.h3Scale,
        4 => MarkdownConstants.h4Scale,
        5 => MarkdownConstants.h5Scale,
        _ => MarkdownConstants.h6Scale,
      };
      baseStyle = baseStyle.copyWith(
        fontSize: style.baseFontSize * scale,
        fontWeight: FontWeight.bold,
      );
    }
    // An emphasis wrapper (`*$~ 2 x*`, `**$$**`) styles the whole row;
    // the marker runs themselves are chrome and are never emitted here
    // (every emission below is bounded by the reduced parse offsets).
    if (m.emphasisLen > 0) {
      baseStyle = baseStyle.copyWith(
        fontStyle: m.emphasisItalic ? FontStyle.italic : null,
        fontWeight: m.emphasisBold ? FontWeight.bold : null,
      );
    }
    MarkdownColorSpec? accentSpec;
    if (m.accentStart >= 0) {
      accentSpec = colorPalette.lookup(
        line.substring(m.accentStart, m.accentEnd),
      );
    }
    // One shared derivation of the row's shape — the editor builds the
    // same object from the same inputs, so the two surfaces cannot
    // disagree on regions, slot, or currency handling.
    final layout = MoneyRowLayout.of(line, m, moneyConfig.currencySymbol);
    final isDisplay = layout.isDisplay;
    // Glyph and semantic accent come from the shared palette — the
    // editor reads the same two functions, so the surfaces cannot
    // drift. A `$!` status row with no target above it warns instead of
    // reading green off the sentinel; a resolved accent token overrides
    // the semantic colour either way.
    final noTarget =
        m.kind == MoneyLineKind.remaining && MarkdownMoneySyntax.isNoTarget(value);
    Color accent = noTarget
        ? MarkdownConstants.moneyWarning(dark: dark)
        : MarkdownConstants.moneyAccent(
            m.kind,
            value,
            dark: dark,
            primary: style.primaryColor,
          );
    final chrome = MarkdownMoneySyntax.glyph(m.kind);
    if (accentSpec != null) {
      accent = accentSpec.text(dark: dark);
    }
    final accentStyle = baseStyle.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );
    // The label takes the row's accent — the resolved colour token when
    // there is one, otherwise the semantic sign colour (green on `$+`,
    // red on `$-`, …). Colour only: the base weight stays, so the value
    // still leads. The whole row reading as one colour is the point —
    // an accent that stopped at the number left the row looking
    // half-styled.
    final labelStyle = baseStyle.copyWith(color: accent);

    // Label-first rows (`$= Net worth: 5000`) read as an equation: the
    // op glyph renders where the `:` is rather than leading the row, so
    // the row shows `Net worth = 5000`. The `:` becomes chrome, exactly
    // like the `$=` marker it replaces. Amount-first rows keep the
    // glyph in front — the spelling picks the layout.
    final amountTrails = layout.labelFirst;
    final children = <InlineSpan>[
      if (!amountTrails) TextSpan(text: '$chrome ', style: accentStyle),
    ];
    final unresolvedAccent = m.accentStart >= 0 && accentSpec == null;
    final slot = layout.slot;
    final hasSlot = slot >= 0;

    // A value pinned at the clamp limit renders in the warning accent
    // on every path below — the number shown is the cap, not the
    // user's arithmetic.
    final pinned = MarkdownMoneySyntax.valuePinned(value);
    final warnColor = MarkdownConstants.moneyWarning(dark: dark);

    // The row's computed value, styled by how load-bearing it is:
    // display rows feature it as a tinted pill, op rows (and the
    // `$=`/`$!` declaration slot spellings) carry it as a dimmed echo
    // beside the amount that was typed. Built in one place so the slot
    // and default positions can never drift apart. [atSlot] only drops
    // the `=` lead-in that reads as an annotation at the end of a row
    // but as noise mid-sentence.
    InlineSpan buildValue({required bool atSlot}) {
      if (!isDisplay) {
        final text = MarkdownMoneySyntax.formatCentsWithSymbol(
          value,
          symbol: moneyConfig.currencySymbol,
          suffix: moneyConfig.currencySuffix,
        );
        return TextSpan(
          text: atSlot ? text : '  =  $text',
          style: baseStyle.copyWith(
            color: pinned
                ? warnColor
                : style.textColor.withValues(alpha: 0.5),
          ),
        );
      }
      // Every row whose colour encodes a sign also *shows* it (shared
      // `isSignedKind`): the direction rows and bare `$!`, whose `+`
      // reads as budget left and `-` as overspent. `$$` stays unsigned —
      // it is an absolute balance, not a move. With no target declared
      // the pill says so instead of formatting the sentinel as money.
      final signed = MarkdownMoneySyntax.isSignedKind(m.kind);
      // Like a pinned value, the "no target" chip keeps the warning
      // colour even under an accent token — it marks a measurement that
      // could not be made, and that outranks row styling.
      InlineSpan pill = TextSpan(
        text: noTarget
            ? ' no target '
            : signed
            ? ' ${MarkdownMoneySyntax.formatCentsSignedWithSymbol(value, symbol: moneyConfig.currencySymbol, suffix: moneyConfig.currencySuffix)} '
            : ' ${MarkdownMoneySyntax.formatCentsWithSymbol(value, symbol: moneyConfig.currencySymbol, suffix: moneyConfig.currencySuffix)} ',
        style: accentStyle.copyWith(
          color: pinned || noTarget ? warnColor : null,
          fontWeight: FontWeight.bold,
          backgroundColor: (pinned || noTarget ? warnColor : accent).withValues(
            alpha: 0.12,
          ),
        ),
      );
      if (onMoneyTap != null) {
        final recognizer = _linkRecognizers['money:$lineIndex'] ??=
            TapGestureRecognizer()..onTap = () => onMoneyTap!(lineIndex);
        pill = _attachRecognizer(pill as TextSpan, recognizer);
      }
      return pill;
    }

    if (!isDisplay && unresolvedAccent) {
      // An unresolved token is literal label text, so it takes the
      // label's colour rather than staying plain beside a tinted row.
      children.add(
        _applyHighlighting(
          line.substring(m.accentStart, m.accentEnd + 1),
          labelStyle,
          lineStart + m.accentStart,
        ),
      );
      children.add(TextSpan(text: ' ', style: baseStyle));
    }
    void emitAmount() {
      // A `$=` row is the one place where the typed operand *is* the
      // row's value — it sets the balance rather than moving it — so it
      // renders as a value: formatted to two decimals with the currency
      // in its configured prefix/suffix position, through the same
      // formatter every other value on every surface goes through. Every
      // other row keeps its operand raw (`$+ 50`) because its computed
      // annotation carries the currency instead; `$=` has no annotation
      // (appending `= 5000.00` beside a typed `5000` is a duplicate), so
      // before this it was the only row that showed a bare, currency-less
      // number — and it disagreed with its own `$= 5000 Net worth: $`
      // spelling, where the slot has always rendered the formatted value.
      // The number itself never changes: [value] equals the typed amount
      // for a `set` row by definition of the fold. `$! N` declarations
      // share the rule — a declaration's operand *is* the target it
      // declares — so a budget statement prints its currency too.
      final text =
          m.kind == MoneyLineKind.set || m.kind == MoneyLineKind.target
          ? MarkdownMoneySyntax.formatCentsWithSymbol(
              value,
              symbol: moneyConfig.currencySymbol,
              suffix: moneyConfig.currencySuffix,
            )
          : line.substring(m.amountStart, m.amountEnd);
      children.add(
        // The source offset still anchors search highlighting; a rendered
        // run that is not the same length as its source run only shifts
        // where the highlight ends, since the ranges clamp to it.
        _applyHighlighting(text, accentStyle, lineStart + m.amountStart),
      );
    }

    // Emits one text region at its true offsets, substituting the value
    // at the slot when it falls inside this region — the label proper
    // and a label-first row's free trailing text both route through
    // here, so a slot behaves identically wherever the row put it.
    void emitRegion(int from, int to) {
      if (from >= to) return;
      if (hasSlot && slot >= from && slot < to) {
        // The slot splits the region into two independently
        // inline-parsed runs at their true source offsets, so search
        // still lands on the text either side of the value.
        if (from < slot) {
          _appendFlattened(
            children,
            _buildInlineFormatted(
              line.substring(from, slot),
              labelStyle,
              lineStart + from,
              lineEnd,
            ),
          );
        }
        children.add(buildValue(atSlot: true));
        if (slot + 1 < to) {
          _appendFlattened(
            children,
            _buildInlineFormatted(
              line.substring(slot + 1, to),
              labelStyle,
              lineStart + slot + 1,
              lineEnd,
            ),
          );
        }
      } else {
        _appendFlattened(
          children,
          _buildInlineFormatted(
            line.substring(from, to),
            labelStyle,
            lineStart + from,
            lineEnd,
          ),
        );
      }
    }

    // [separator] is the gap from whatever precedes the label; a
    // label-first row puts it right after the chrome glyph, which
    // already carries its own trailing space.
    void emitLabel({bool separator = true}) {
      // An unresolved token on display rows folds back into the label so
      // the typed text stays visible at its exact offsets — starting from
      // whichever of the token or the count comes first, since the accent
      // may be written either before (`$~ teal: 2`) or after (`$~ 2 teal:`)
      // the count.
      //
      // Otherwise the label starts past an inline currency word
      // (`$= 500 lei`, `$+ 50 lei coffee`): the row's value already
      // prints the currency in its configured position, so echoing the
      // typed word would double it. Recognised only when it *is* this
      // note's currency, so every other word is still ordinary label
      // text — the rule lives in the grammar lib, shared with the
      // detail sheet.
      final from = isDisplay && unresolvedAccent
          ? (m.accentStart < m.amountStart ? m.accentStart : m.amountStart)
          : layout.labelFrom;
      // On a label-first row the trailing `:` is chrome — the op glyph
      // renders in its place — so it is not part of the label text.
      final to = layout.labelTo;
      if (from >= to) return;
      if (separator) children.add(TextSpan(text: ' ', style: baseStyle));
      emitRegion(from, to);
    }

    if (isDisplay) {
      // The `$^ N` / `$~ N` window count is syntax, not content: it
      // selects the window the row measures exactly as the accent token
      // selects its colour, so like that token it is chrome and never
      // painted — the row reads as the sentence the label writes. (The
      // editor still reveals it with the rest of the raw source when the
      // caret lands on the line, and the detail sheet lists the window
      // itself.) With an unresolved accent token the digits ride along
      // in the literal label run below instead, so nothing the parser
      // could not resolve is ever silently eaten.
      if (!hasSlot) children.add(buildValue(atSlot: false));
      emitLabel();
    } else if (amountTrails) {
      // Label-first (`$- Loss on trade: 5000`): the typed amount trails
      // its label instead of leading it, with the op glyph between them
      // in place of the `:`. Source order is what renders — both runs
      // keep their true offsets either way. A `$!` declaration is the
      // exception: written label-first it is a statement, not an
      // equation (`### $! yellow: Groceries: 500` should read
      // "Groceries: 500.00 lei", not sprout a target icon mid-header),
      // so the `:` stays visible text and no glyph renders at all.
      if (m.kind == MoneyLineKind.target) {
        emitRegion(layout.labelFrom, m.labelEnd);
        children.add(TextSpan(text: ' ', style: baseStyle));
      } else {
        emitLabel(separator: false);
        children.add(TextSpan(text: ' $chrome ', style: accentStyle));
      }
      emitAmount();
      // Free trailing text after the amount (`$= Worth: 500 lei as of
      // today`): the currency word is chrome when it is this note's
      // symbol — the value beside it already prints it — and everything
      // else renders at its true offsets, value slot included, so the
      // parser can never eat a word it did not understand.
      emitRegion(layout.trailingFrom, layout.contentEnd);
    } else {
      emitAmount();
      emitLabel();
    }
    // Default trailing position, used only when the label placed no
    // slot. `$=` and `$! N` declarations append nothing — their amount
    // already renders as the value it is (see [emitAmount]), so an
    // annotation beside it would just repeat the number — while an
    // explicit slot renders that same value wherever in the label the
    // row put it. The remaining budget lives on the bare `$!` status
    // row now, not beside the declaration.
    if (!hasSlot &&
        m.kind != MoneyLineKind.set &&
        m.kind != MoneyLineKind.target &&
        !isDisplay) {
      children.add(buildValue(atSlot: false));
    }
    return _wrapMoneyList(
      line,
      m,
      TextSpan(style: baseStyle, children: children),
      baseStyle,
      listStyle,
    );
  }

  /// Wraps a money row's span in list chrome — indent plus a synthetic
  /// bullet / the typed ordered number — when the row carries a
  /// list-marker prefix (`- $+ 50`, `1. $$`). Same [WidgetSpan] row as
  /// [_buildListItem] / [_buildOrderedListItem], so a bulleted money
  /// row aligns and hangs exactly like any other list item, while the
  /// money content inside keeps its true source offsets for search.
  ///
  /// [markerStyle] is the row's style *before* its heading/emphasis
  /// mutations, so the bullet matches a plain list item's exactly;
  /// [baseStyle] (the styled row) stays the default for the content.
  TextSpan _wrapMoneyList(
    String line,
    MoneyLineMatch m,
    TextSpan span,
    TextStyle baseStyle,
    TextStyle markerStyle,
  ) {
    if (m.listMarkerStart < 0) return span;
    final level = MarkdownListSyntax.indentLevel(line);
    final c = line.codeUnitAt(m.listMarkerStart);
    final ordered = c >= 0x30 && c <= 0x39;
    final marker = ordered
        ? '${line.substring(m.listMarkerStart, m.listMarkerEnd)} '
        : '${_bulletForLevel(level)} ';
    return TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: EdgeInsets.only(left: _listIndent(level)),
            child: DefaultTextStyle(
              style: baseStyle,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    marker,
                    style: markerStyle.copyWith(
                      color: style.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(child: Text.rich(span, style: baseStyle)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Appends [span] to [children], flattening one wrapper level. Every
  /// direct child of an inline-parsed span already carries its full
  /// (merged) style, so dropping the redundant outer wrapper preserves
  /// styling — the same technique [_buildBlockquote] uses.
  void _appendFlattened(List<InlineSpan> children, TextSpan span) {
    if (span.children != null) {
      children.addAll(span.children!);
    } else if (span.text != null) {
      children.add(span);
    }
  }

  /// The accent colour for a callout [type], in a light/dark variant
  /// chosen by [LineMarkdownStyle.isDark]. The tint background is derived
  /// from this accent at low alpha, so a single colour per type drives
  /// the bar, icon-label header, and band. Palette lives in
  /// [MarkdownConstants.calloutAccent], shared with the live editor.
  Color _calloutAccent(MarkdownCalloutType type) =>
      MarkdownConstants.calloutAccent(type, dark: style.isDark);

  TextSpan _buildHorizontalRule() {
    return TextSpan(
      text: '─' * 40,
      style: TextStyle(
        fontSize: style.baseFontSize * MarkdownConstants.horizontalRuleScale,
        color: style.textColor.withValues(alpha: 0.3),
        letterSpacing: 2,
      ),
    );
  }

  /// Build a code block line (content inside ``` fences)
  TextSpan _buildCodeBlockLine(
    String line,
    String trimmed,
    int lineStart,
    int lineEnd,
  ) {
    final codeStyle = TextStyle(
      fontSize: style.baseFontSize * MarkdownConstants.codeBlockScale,
      height: MarkdownConstants.lineHeight,
      fontFamily: 'monospace',
      color: style.textColor,
      backgroundColor: style.codeBackground,
    );

    // If this is a fence line (``` with optional language), style it differently
    if (trimmed.startsWith('```')) {
      final language = trimmed.length > 3 ? trimmed.substring(3).trim() : '';
      return TextSpan(
        text: language.isNotEmpty ? '// $language' : '',
        style: codeStyle.copyWith(
          color: style.textColor.withValues(
            alpha: MarkdownConstants.checkedTextOpacity,
          ),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Regular code content - apply highlighting for search
    return _applyHighlighting(line, codeStyle, lineStart);
  }

  /// Build an image placeholder (since TextSpan can't render actual images)
  /// Format: ![alt text](url)
  TextSpan _buildImage(String altText, String url, int lineStart, int lineEnd) {
    final imageStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.primaryColor,
      fontStyle: FontStyle.italic,
    );

    // Alt text starts at lineStart + 2 (after "![")
    final altTextOffset = lineStart + 2;
    final displayText = altText.isNotEmpty ? altText : 'Image';

    // Apply highlighting to alt text
    final highlightedAltText = _applyHighlighting(
      displayText,
      imageStyle.copyWith(decoration: TextDecoration.underline),
      altText.isNotEmpty
          ? altTextOffset
          : lineStart, // Use actual offset only if we have real alt text
    );

    // Wrap with tap recognizer if we have a link tap callback
    final children = <InlineSpan>[
      TextSpan(
        text: '🖼 ',
        style: imageStyle.copyWith(fontStyle: FontStyle.normal),
      ),
    ];

    if (onLinkTap != null) {
      // We need to wrap the highlighted text span with a recognizer
      // Create a new span that includes the recognizer
      _linkRecognizers['img:$lineStart:$url'] ??= TapGestureRecognizer()
        ..onTap = () => onLinkTap!(url);

      if (highlightedAltText.children != null &&
          highlightedAltText.children!.isNotEmpty) {
        // Has highlighting - need to add recognizer to each child
        for (final child in highlightedAltText.children!) {
          if (child is TextSpan) {
            children.add(
              TextSpan(
                text: child.text,
                style:
                    child.style ??
                    imageStyle.copyWith(decoration: TextDecoration.underline),
                recognizer: _linkRecognizers['img:$lineStart:$url'],
                children: child.children,
              ),
            );
          } else {
            children.add(child);
          }
        }
      } else {
        // No highlighting, simple text
        children.add(
          TextSpan(
            text: highlightedAltText.text ?? displayText,
            style: imageStyle.copyWith(decoration: TextDecoration.underline),
            recognizer: _linkRecognizers['img:$lineStart:$url'],
          ),
        );
      }
    } else {
      // No tap callback, just add the highlighted text
      if (highlightedAltText.children != null) {
        children.addAll(highlightedAltText.children!.cast<InlineSpan>());
      } else {
        children.add(highlightedAltText);
      }
    }

    return TextSpan(children: children);
  }

  /// Build a table row with proper cell offset tracking for search highlighting
  TextSpan _buildTableRow(String line, int lineStart, int lineEnd) {
    final baseStyle = TextStyle(
      fontSize: style.baseFontSize,
      height: MarkdownConstants.lineHeight,
      color: style.textColor,
    );

    // Check if this is a separator row (|---|---|)
    if (_MarkdownPatterns.tableSeparator.hasMatch(line)) {
      return TextSpan(
        text: '─' * 30,
        style: baseStyle.copyWith(
          color: style.textColor.withValues(alpha: 0.3),
          letterSpacing: 1,
        ),
      );
    }

    // Parse table cells while tracking their positions in the source
    final children = <InlineSpan>[];
    bool isFirst = true;

    // Split by | but track positions
    int searchStart = 0;
    while (searchStart < line.length) {
      // Find next |
      int pipePos = line.indexOf('|', searchStart);
      if (pipePos == -1) {
        // No more pipes, handle remaining content
        if (searchStart < line.length) {
          final remaining = line.substring(searchStart).trim();
          if (remaining.isNotEmpty) {
            if (!isFirst) {
              children.add(
                TextSpan(
                  text: ' │ ',
                  style: baseStyle.copyWith(
                    color: style.textColor.withValues(alpha: 0.4),
                  ),
                ),
              );
            }
            children.add(
              _buildInlineFormatted(
                remaining,
                baseStyle,
                lineStart +
                    searchStart +
                    (line.substring(searchStart).length -
                        line.substring(searchStart).trimLeft().length),
                lineEnd,
              ),
            );
          }
        }
        break;
      }

      // Content before this pipe
      if (pipePos > searchStart) {
        final cellContent = line.substring(searchStart, pipePos).trim();
        if (cellContent.isNotEmpty) {
          if (!isFirst) {
            children.add(
              TextSpan(
                text: ' │ ',
                style: baseStyle.copyWith(
                  color: style.textColor.withValues(alpha: 0.4),
                ),
              ),
            );
          }
          // Calculate where the trimmed content actually starts
          final rawContent = line.substring(searchStart, pipePos);
          final leadingSpaces =
              rawContent.length - rawContent.trimLeft().length;
          final cellOffset = lineStart + searchStart + leadingSpaces;

          children.add(
            _buildInlineFormatted(cellContent, baseStyle, cellOffset, lineEnd),
          );
          isFirst = false;
        }
      }

      searchStart = pipePos + 1;
    }

    if (children.isEmpty) {
      return TextSpan(text: line, style: baseStyle);
    }

    return TextSpan(style: baseStyle, children: children);
  }

  /// Build inline formatted text with bold, italic, code, links, and
  /// highlighting. [contentStart] is the source offset where [text]
  /// begins — critical so search highlighting lands on the right
  /// characters. Delegates to the recursive [_parseInline] scanner.
  ///
  /// [lineEnd] is retained for call-site compatibility and is unused.
  TextSpan _buildInlineFormatted(
    String text,
    TextStyle baseStyle,
    int contentStart,
    int lineEnd,
  ) {
    if (text.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }
    return _parseInline(text, baseStyle, contentStart);
  }

  /// Recursively parses inline markdown in [text] whose first character
  /// sits at source offset [contentStart]. Every leaf text run is routed
  /// through [_applyHighlighting] with its exact offset, so search
  /// highlighting stays aligned at any nesting depth.
  ///
  /// Improvements over the former single-pass regex:
  ///   * Nested emphasis (`**bold _italic_**`, `[**x**](url)`).
  ///   * Backslash escaping (`\*literal\*`).
  ///   * Intra-word underscores are not emphasis (`snake_case_word`).
  ///   * Inline code is literal (its content is never re-parsed).
  TextSpan _parseInline(String text, TextStyle baseStyle, int contentStart) {
    final children = <InlineSpan>[];
    final length = text.length;
    int i = 0;
    int runStart = 0;

    void flushRun(int end) {
      if (end > runStart) {
        children.add(
          _applyHighlighting(
            text.substring(runStart, end),
            baseStyle,
            contentStart + runStart,
          ),
        );
      }
    }

    while (i < length) {
      final c = text.codeUnitAt(i);

      // Backslash escape: emit the next punctuation char literally.
      if (c == _kBackslash &&
          i + 1 < length &&
          _isEscapablePunctuation(text.codeUnitAt(i + 1))) {
        flushRun(i);
        children.add(
          _applyHighlighting(
            text.substring(i + 1, i + 2),
            baseStyle,
            contentStart + i + 1,
          ),
        );
        i += 2;
        runStart = i;
        continue;
      }

      // Ghost text: {{ inner }} — dimmed placeholder, markers hidden.
      // Detected before other inline syntax so `{{` is never mistaken
      // for prose. Renders even without a tap handler (e.g. dialog
      // previews); the tap recognizer is attached only when engageable.
      if (c == _kOpenBrace) {
        final ghost = GhostText.matchAt(text, i);
        if (ghost != null) {
          flushRun(i);
          children.add(_buildGhostSpan(text, ghost, baseStyle, contentStart));
          i = ghost.end;
          runStart = i;
          continue;
        }
        // Coloured text: {name:content}. The `{name:` and `}` markers
        // are chrome (like `[!TYPE]` and the `$x` money ops); the
        // content keeps its source offsets and is parsed recursively so
        // emphasis, links, and nested colours all compose. An unknown
        // name never matches, so the braces stay literal text.
        final colored = MarkdownColorSyntax.matchAt(text, i, colorPalette);
        if (colored != null) {
          flushRun(i);
          children.add(
            _parseInline(
              text.substring(colored.innerStart, colored.innerEnd),
              baseStyle.copyWith(color: colored.spec.text(dark: style.isDark)),
              contentStart + colored.innerStart,
            ),
          );
          i = colored.end;
          runStart = i;
          continue;
        }
      }

      // Inline code span: `code` / ``co`de`` — literal, no nesting.
      if (c == _kBacktick) {
        final fence = _countRun(text, i, _kBacktick);
        final close = _findClosingBacktick(text, i + fence, fence);
        if (close != -1) {
          flushRun(i);
          final contentBegin = i + fence;
          children.add(
            _applyHighlighting(
              text.substring(contentBegin, close),
              baseStyle.copyWith(
                fontFamily: 'monospace',
                backgroundColor: style.codeBackground,
                fontSize: baseStyle.fontSize! * 0.9,
              ),
              contentStart + contentBegin,
            ),
          );
          i = close + fence;
          runStart = i;
          continue;
        }
      }

      // Link: [text](url) — link text is parsed recursively.
      if (c == _kOpenBracket) {
        final link = _tryParseLinkAt(text, i);
        if (link != null) {
          flushRun(i);
          final inner = _parseInline(
            text.substring(link.textStart, link.textEnd),
            baseStyle.copyWith(
              color: style.primaryColor,
              decoration: TextDecoration.underline,
            ),
            contentStart + link.textStart,
          );
          children.add(_wrapLinkSpan(inner, link.urlOf(text), contentStart + i));
          i = link.end;
          runStart = i;
          continue;
        }
      }

      // Emphasis / strong / strikethrough / highlight (`*`, `_`, `~`, `==`).
      if (c == _kStar || c == _kUnderscore || c == _kTilde || c == _kEquals) {
        final emphasis = _tryParseEmphasisAt(text, i);
        if (emphasis != null) {
          flushRun(i);
          var innerStart = emphasis.contentStart;
          var runStyle = _applyEmphasisStyle(baseStyle, emphasis.kind);
          // `==name:text==` tints the highlight and consumes `name:` as
          // chrome. An unresolved name keeps the default amber and
          // leaves the prefix as ordinary highlighted text, so plain
          // prose like `==note: see below==` is never eaten.
          if (emphasis.kind == _EmphasisKind.highlight) {
            final tint = MarkdownColorSyntax.matchHighlightPrefix(
              text,
              innerStart,
              emphasis.contentEnd,
              colorPalette,
            );
            if (tint != null) {
              runStyle = baseStyle.copyWith(
                backgroundColor: tint.spec.highlight(dark: style.isDark),
              );
              innerStart = tint.contentStart;
            }
          }
          children.add(
            _parseInline(
              text.substring(innerStart, emphasis.contentEnd),
              runStyle,
              contentStart + innerStart,
            ),
          );
          i = emphasis.end;
          runStart = i;
          continue;
        }
      }

      // Tag: #identifier (letter-led, at a word boundary) — tappable,
      // searches across notes. Letter-led so `#3` / `set #1` and `C#`
      // are never tags.
      if (c == _kHash && _isWordBoundaryBefore(text, i)) {
        final tagEnd = MarkdownTagSyntax.tryParseTagAt(text, i);
        if (tagEnd != null) {
          flushRun(i);
          children.add(_buildTagSpan(text, i, tagEnd, baseStyle, contentStart));
          i = tagEnd;
          runStart = i;
          continue;
        }
      }

      // Bare autolink: http://… https://… www.…
      if ((c == _kLowerH || c == _kLowerW) && _isWordBoundaryBefore(text, i)) {
        final auto = _tryParseBareUrlAt(text, i);
        if (auto != null) {
          flushRun(i);
          final inner = _applyHighlighting(
            text.substring(i, auto.end),
            baseStyle.copyWith(
              color: style.primaryColor,
              decoration: TextDecoration.underline,
            ),
            contentStart + i,
          );
          children.add(_wrapLinkSpan(inner, auto.url, contentStart + i));
          i = auto.end;
          runStart = i;
          continue;
        }
      }

      i++;
    }

    flushRun(length);

    if (children.isEmpty) {
      return _applyHighlighting(text, baseStyle, contentStart);
    }
    return TextSpan(style: baseStyle, children: children);
  }

  /// Applies the style delta for an emphasis [kind] on top of [base],
  /// so nested emphasis composes (e.g. strikethrough + bold).
  TextStyle _applyEmphasisStyle(TextStyle base, _EmphasisKind kind) {
    switch (kind) {
      case _EmphasisKind.boldItalic:
        return base.copyWith(
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        );
      case _EmphasisKind.bold:
        return base.copyWith(fontWeight: FontWeight.bold);
      case _EmphasisKind.italic:
        return base.copyWith(fontStyle: FontStyle.italic);
      case _EmphasisKind.strikethrough:
        return base.copyWith(decoration: TextDecoration.lineThrough);
      case _EmphasisKind.highlight:
        return base.copyWith(backgroundColor: style.markColor);
    }
  }

  /// Wraps a parsed link [inner] span with a cached tap recognizer.
  /// The recognizer is attached to every leaf so taps register even
  /// when the link text was split by nesting or search highlighting.
  InlineSpan _wrapLinkSpan(TextSpan inner, String url, int sourceOffset) {
    if (onLinkTap == null) return inner;
    final cacheKey = '$sourceOffset:$url';
    final recognizer = _linkRecognizers[cacheKey] ??= TapGestureRecognizer()
      ..onTap = () => onLinkTap!(url);
    return _attachRecognizer(inner, recognizer);
  }

  /// Returns a copy of [span] with [recognizer] set on every [TextSpan]
  /// node so hit-testing resolves to it at any leaf.
  InlineSpan _attachRecognizer(
    InlineSpan span,
    TapGestureRecognizer recognizer,
  ) {
    if (span is TextSpan) {
      return TextSpan(
        text: span.text,
        style: span.style,
        recognizer: recognizer,
        children: span.children
            ?.map((s) => _attachRecognizer(s, recognizer))
            .toList(),
      );
    }
    return span;
  }

  /// Tries to parse a `[text](url)` link starting at the `[` at [open].
  /// Grammar lives in [MarkdownLinkPatterns.matchInlineLinkAt], shared
  /// with the live editor's rendering and tap interception.
  MarkdownInlineLink? _tryParseLinkAt(String text, int open) =>
      MarkdownLinkPatterns.matchInlineLinkAt(text, open);

  /// Tries to parse an emphasis run (`*`, `_`, `~`) opening at [i].
  /// Applies CommonMark-style flanking so underscores never match
  /// intra-word and a run must wrap non-space content.
  _InlineEmphasis? _tryParseEmphasisAt(String text, int i) {
    final marker = text.codeUnitAt(i);
    final runLen = _countRun(text, i, marker);

    final int use;
    final _EmphasisKind kind;
    if (marker == _kTilde) {
      if (runLen < 2) return null; // single ~ is literal
      use = 2;
      kind = _EmphasisKind.strikethrough;
    } else if (marker == _kEquals) {
      if (runLen < 2) return null; // single = is literal
      use = 2;
      kind = _EmphasisKind.highlight;
    } else if (runLen >= 3) {
      use = 3;
      kind = _EmphasisKind.boldItalic;
    } else if (runLen == 2) {
      use = 2;
      kind = _EmphasisKind.bold;
    } else {
      use = 1;
      kind = _EmphasisKind.italic;
    }

    if (!_canOpenEmphasis(text, i, marker, use)) return null;

    final contentStart = i + use;
    int j = contentStart;
    while (j < text.length) {
      if (text.codeUnitAt(j) == marker) {
        final closeRun = _countRun(text, j, marker);
        if (closeRun >= use &&
            j > contentStart &&
            _canCloseEmphasis(text, j, marker, use)) {
          return _InlineEmphasis(
            kind: kind,
            contentStart: contentStart,
            contentEnd: j,
            end: j + use,
          );
        }
        j += closeRun;
      } else {
        j++;
      }
    }
    return null; // no valid closing run
  }

  /// Whether an emphasis run of [use] [marker]s at [i] can open: it must
  /// be followed by a non-space char, and underscores must sit at a left
  /// word boundary (so `a_b_` stays literal).
  bool _canOpenEmphasis(String text, int i, int marker, int use) {
    final afterIdx = i + use;
    if (afterIdx >= text.length) return false;
    if (_isSpace(text.codeUnitAt(afterIdx))) return false;
    if (marker == _kUnderscore &&
        i > 0 &&
        _isAlphaNumeric(text.codeUnitAt(i - 1))) {
      return false;
    }
    return true;
  }

  /// Whether an emphasis run of [use] [marker]s at [j] can close: it must
  /// be preceded by a non-space char, and underscores must sit at a right
  /// word boundary.
  bool _canCloseEmphasis(String text, int j, int marker, int use) {
    if (j == 0) return false;
    if (_isSpace(text.codeUnitAt(j - 1))) return false;
    if (marker == _kUnderscore) {
      final afterIdx = j + use;
      if (afterIdx < text.length &&
          _isAlphaNumeric(text.codeUnitAt(afterIdx))) {
        return false;
      }
    }
    return true;
  }

  /// Tries to match a bare URL at [i]. Extent and trailing-punctuation
  /// trim come from the shared [MarkdownLinkPatterns.matchBareUrlEnd] so
  /// preview, paste line-breaker, and live editor always agree.
  _InlineAutoLink? _tryParseBareUrlAt(String text, int i) {
    final end = MarkdownLinkPatterns.matchBareUrlEnd(text, i);
    if (end < 0) return null;
    final raw = text.substring(i, end);
    final href = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    return _InlineAutoLink(end: end, url: href);
  }

  /// Counts how many consecutive [marker] code units start at [i].
  static int _countRun(String text, int i, int marker) {
    int n = 0;
    while (i + n < text.length && text.codeUnitAt(i + n) == marker) {
      n++;
    }
    return n;
  }

  /// Finds a backtick run of exactly [fence] length at/after [from],
  /// returning its start index, or -1. CommonMark requires the closing
  /// run to match the opening length.
  static int _findClosingBacktick(String text, int from, int fence) {
    int j = from;
    while (j < text.length) {
      if (text.codeUnitAt(j) == _kBacktick) {
        final run = _countRun(text, j, _kBacktick);
        if (run == fence) return j;
        j += run;
      } else {
        j++;
      }
    }
    return -1;
  }

  /// Whether the character before [i] is a word boundary, so an inline
  /// token (`#tag`) or a bare autolink may start here. Delegates to the
  /// shared tag grammar so preview and live editor always agree.
  bool _isWordBoundaryBefore(String text, int i) =>
      MarkdownTagSyntax.isWordBoundaryBefore(text, i);

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isAlphaNumeric(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A); // a-z

  /// ASCII-punctuation test for backslash escaping; shared with the live
  /// editor via [MarkdownConstants.isEscapablePunctuation].
  static bool _isEscapablePunctuation(int c) =>
      MarkdownConstants.isEscapablePunctuation(c);

  // Inline-scanner code-unit constants.
  static const int _kBackslash = 0x5C; // \
  static const int _kBacktick = 0x60; // `
  static const int _kStar = 0x2A; // *
  static const int _kUnderscore = 0x5F; // _
  static const int _kTilde = 0x7E; // ~
  static const int _kEquals = 0x3D; // =
  static const int _kHash = 0x23; // #
  static const int _kOpenBracket = 0x5B; // [
  static const int _kOpenBrace = 0x7B; // {
  static const int _kLowerH = 0x68; // h
  static const int _kLowerW = 0x77; // w

  /// Builds the span for a `#tag`, tinted and (when [onTagTap] is set)
  /// tappable. The tag text — including the leading `#` — stays a normal
  /// offset-mapped text run so search highlighting still applies inside
  /// it; the recognizer is attached to every leaf.
  InlineSpan _buildTagSpan(
    String text,
    int start,
    int end,
    TextStyle baseStyle,
    int contentStart,
  ) {
    final tagText = text.substring(start, end);
    final tagStyle = baseStyle.copyWith(
      color: style.primaryColor,
      fontWeight: FontWeight.w600,
      backgroundColor: style.primaryColor.withValues(alpha: 0.12),
    );
    final span = _applyHighlighting(tagText, tagStyle, contentStart + start);
    if (onTagTap == null) return span;
    final cacheKey = 'tag:${contentStart + start}:$tagText';
    final recognizer = _linkRecognizers[cacheKey] ??= TapGestureRecognizer()
      ..onTap = () => onTagTap!(tagText);
    return _attachRecognizer(span, recognizer);
  }

  /// Builds the dimmed span for a ghost run. The `{{` / `}}` markers are
  /// hidden; only the inner text renders, tinted with [style.ghostColor]
  /// on top of [baseStyle] so it inherits the surrounding context
  /// (heading size, list style, etc.). Search highlighting still applies
  /// to the inner text via its true source offset. When [onGhostTap] is
  /// set, a cached tap recognizer is attached to every leaf so a tap
  /// anywhere on the placeholder engages it.
  InlineSpan _buildGhostSpan(
    String text,
    GhostMatch ghost,
    TextStyle baseStyle,
    int contentStart,
  ) {
    final inner = text.substring(ghost.innerStart, ghost.innerEnd);
    final ghostStyle = baseStyle.copyWith(color: style.ghostColor);
    final span = _applyHighlighting(
      inner,
      ghostStyle,
      contentStart + ghost.innerStart,
    );
    if (onGhostTap == null) return span;
    final absStart = contentStart + ghost.start;
    final absEnd = contentStart + ghost.end;
    final cacheKey = 'ghost:$absStart:$absEnd';
    final recognizer = _linkRecognizers[cacheKey] ??= TapGestureRecognizer()
      ..onTap = () => onGhostTap!(absStart, absEnd);
    return _attachRecognizer(span, recognizer);
  }

  /// Apply search highlighting to text.
  TextSpan _applyHighlighting(
    String text,
    TextStyle baseStyle,
    int sourceOffset,
  ) {
    if (searchHighlights == null || searchHighlights!.isEmpty || text.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final sourceEnd = sourceOffset + text.length;

    // Find overlapping highlights
    final overlapping = <_HighlightRange>[];
    for (int i = 0; i < searchHighlights!.length; i++) {
      final h = searchHighlights![i];
      if (h.start < sourceEnd && h.end > sourceOffset) {
        final relStart = (h.start - sourceOffset).clamp(0, text.length);
        final relEnd = (h.end - sourceOffset).clamp(0, text.length);
        overlapping.add(
          _HighlightRange(
            start: relStart,
            end: relEnd,
            isCurrent: i == currentHighlightIndex,
          ),
        );
      }
    }

    if (overlapping.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    overlapping.sort((a, b) => a.start.compareTo(b.start));

    final children = <TextSpan>[];
    int pos = 0;

    for (final range in overlapping) {
      if (range.start > pos) {
        children.add(TextSpan(text: text.substring(pos, range.start)));
      }

      final bgColor = range.isCurrent
          ? style.currentHighlightColor
          : style.highlightColor;
      children.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: TextStyle(backgroundColor: bgColor),
        ),
      );

      pos = range.end;
    }

    if (pos < text.length) {
      children.add(TextSpan(text: text.substring(pos)));
    }

    return TextSpan(style: baseStyle, children: children);
  }
}

class _HighlightRange {
  final int start;
  final int end;
  final bool isCurrent;

  _HighlightRange({
    required this.start,
    required this.end,
    required this.isCurrent,
  });
}

/// Inline emphasis variants produced by the recursive inline parser.
enum _EmphasisKind { boldItalic, bold, italic, strikethrough, highlight }

/// A parsed emphasis run: [contentStart, contentEnd) is the inner text,
/// [end] is the index just past the closing delimiter.
class _InlineEmphasis {
  final _EmphasisKind kind;
  final int contentStart;
  final int contentEnd;
  final int end;

  const _InlineEmphasis({
    required this.kind,
    required this.contentStart,
    required this.contentEnd,
    required this.end,
  });
}

/// A parsed bare autolink: [end] is the index just past the URL and
/// [url] is the launch target (scheme-normalized for `www.` links).
class _InlineAutoLink {
  final int end;
  final String url;

  const _InlineAutoLink({required this.end, required this.url});
}

/// Pre-compiled regex patterns for inline markdown (compiled once, reused)
class _MarkdownPatterns {
  static final horizontalRule = RegExp(r'^[-*_]{3,}\s*$');

  /// Image pattern: ![alt text](url)
  static final image = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$');

  /// Table row pattern: | cell | cell | or |cell|cell|
  static final tableRow = RegExp(r'^\|.*\|$');

  /// Table separator pattern: |---|---| or | --- | --- |
  static final tableSeparator = RegExp(r'^\|[\s:-]+\|[\s:|+-]*$');
}
