import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';
import 'markdown_line_shape.dart';
import 'markdown_link_patterns.dart';

/// Configuration for editor width calculation
class EditorWidthConfig {
  final GlobalKey editorContainerKey;
  final GlobalKey? lineNumbersKey;
  final GlobalKey? scrollIndicatorKey;
  final double fontSize;
  final double lineHeight;

  /// Font family to use for text measurement.
  /// Must match the font family used by the code editor (re_editor).
  final String? fontFamily;

  /// Additional safety margin for font rendering differences
  final double safetyMargin;

  const EditorWidthConfig({
    required this.editorContainerKey,
    this.lineNumbersKey,
    this.scrollIndicatorKey,
    required this.fontSize,
    this.lineHeight = MarkdownConstants.lineHeight,
    this.fontFamily,
    this.safetyMargin = 2.0,
  });
}

/// Result of smart line breaking operation
class LineBreakResult {
  final List<String> lines;
  final int linesModified;

  const LineBreakResult({required this.lines, required this.linesModified});
}

/// Identity of an ASCII advance table: everything about the measuring style
/// that can move a glyph's advance.
typedef _AdvanceTableKey = (
  double fontSize,
  double lineHeight,
  String? fontFamily,
);

/// Utility class for calculating available text width in the editor
/// and measuring text pixel widths for paste line breaking.
///
/// Supports smart line breaking that:
/// - Skips code blocks (``` fenced blocks)
/// - Respects markdown syntax (links, images, inline code, bold/italic)
/// - Breaks at word boundaries when possible
class EditorWidthCalculator {
  final EditorWidthConfig config;

  /// Cached editor padding from the CodeEditor widget
  final EdgeInsets editorPadding;

  // Regex patterns for markdown syntax that shouldn't be broken
  static final _linkPattern = RegExp(r'\[([^\]]*)\]\([^)]+\)');
  static final _imagePattern = RegExp(r'!\[([^\]]*)\]\([^)]+\)');
  static final _inlineCodePattern = RegExp(r'`[^`]+`');
  static final _boldPattern = RegExp(r'\*\*[^*]+\*\*|__[^_]+__');
  static final _italicPattern = RegExp(r'\*[^*]+\*|_[^_]+_');
  static final _codeBlockFencePattern = RegExp(r'^```');

  /// Bare URL pattern shared with [LineBasedMarkdownBuilder] so the paste
  /// reformatter never splits a URL the preview would render as a link.
  static final _bareUrlPattern = MarkdownLinkPatterns.bareUrl;

  /// Cached TextPainter reused across measurements to avoid re-allocation.
  late final TextPainter _textPainter;

  /// Per-glyph advance tables for printable ASCII, keyed by the style triple
  /// that decides them. Static because the page builds a fresh calculator per
  /// paste while the font rarely changes, and bounded because a stale table
  /// costs 95 doubles: one paste sees one size, so eight is already generous.
  static final Map<_AdvanceTableKey, List<double>> _advanceTables = {};

  static const int _maxAdvanceTables = 8;
  static const int _asciiFirst = 0x20;
  static const int _asciiLast = 0x7E;

  /// Number of [measureTextWidth] layouts run so far.
  ///
  /// The pre-filter in [lineExceedsWidth] exists to keep this number flat for
  /// lines that obviously fit; the tests assert exactly that. One-off glyph
  /// measurements taken to build an advance table are deliberately not
  /// counted — they are per style, not per line.
  @visibleForTesting
  static int debugLayoutCount = 0;

  EditorWidthCalculator({required this.config, required this.editorPadding})
    : _textPainter = TextPainter(
        text: const TextSpan(text: ''),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      );

  /// Get the available width for text in the editor by measuring actual widget sizes
  double? getAvailableTextWidth() {
    // Measure the editor container width
    final containerWidth = _measureWidgetWidth(config.editorContainerKey);
    if (containerWidth == null) return null;

    // Measure line numbers width (if key provided and widget exists)
    final lineNumbersWidth = config.lineNumbersKey != null
        ? _measureWidgetWidth(config.lineNumbersKey!) ?? 0.0
        : 0.0;

    // NOTE: Scroll indicator width is NOT deducted here because the
    // editor's right padding (editorScrollbarPadding) already reserves
    // space for the scroll-progress indicator overlay.

    // Calculate total deduction
    final horizontalPadding = editorPadding.left + editorPadding.right;
    final totalDeduction =
        lineNumbersWidth + horizontalPadding + config.safetyMargin;

    final availableWidth = containerWidth - totalDeduction;

    return availableWidth > 0 ? availableWidth : null;
  }

  /// Measure the pixel width of a string using the editor's font
  double measureTextWidth(String text) {
    debugLayoutCount++;
    return _measureRaw(text);
  }

  /// Check if a line exceeds the available width.
  ///
  /// A paste asks this once per pasted line, and almost every line of an
  /// ordinary note obviously fits — so an all-printable-ASCII line is first
  /// summed from a per-glyph advance table (measured once per style, filled
  /// lazily per glyph) and only measured for real when that sum does not
  /// already settle it.
  ///
  /// **Why the sum is a safe "it fits" proof.** Shaping a run never makes it
  /// wider than the sum of its glyphs' isolated advances: ligatures merge
  /// glyphs and kerning is almost always negative, so the shaped width is at
  /// most the sum, except for the rare positive kerning pair — a sub-pixel
  /// adjustment already absorbed by [EditorWidthConfig.safetyMargin], which
  /// was deducted from [availableWidth] upstream. Each table entry is a
  /// painter measurement of its glyph alone, taken with the same style and
  /// the same painter as the whole-line measurement, so both sides of the
  /// comparison see the same fractional advances (`TextPainter.width` is not
  /// rounded to the pixel grid). Anything else — one non-ASCII code unit, or
  /// a sum that reaches [availableWidth] — falls through to the exact
  /// measurement, so the answer can only ever be the painter's.
  bool lineExceedsWidth(String lineText, double availableWidth) {
    if (lineText.isEmpty) return false;
    if (_asciiFitPrefix(lineText, availableWidth) == lineText.length) {
      return false;
    }
    return measureTextWidth(lineText) > availableWidth;
  }

  /// Length of the longest prefix of [text] that is all printable ASCII and
  /// whose summed table advances stay within [maxWidth] — so a prefix that
  /// **provably fits**, by the upper-bound argument on [lineExceedsWidth].
  ///
  /// Stops at the first non-ASCII code unit (that prefix still fits, it just
  /// cannot be extended), so a result equal to `text.length` means the whole
  /// string is settled: all ASCII and within the width.
  int _asciiFitPrefix(String text, double maxWidth) {
    final table = _advanceTable();
    double total = 0;
    for (int i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < _asciiFirst || unit > _asciiLast) return i;
      final index = unit - _asciiFirst;
      var advance = table[index];
      if (advance < 0) {
        advance = _measureRaw(String.fromCharCode(unit));
        table[index] = advance;
      }
      total += advance;
      if (total > maxWidth) return i;
    }
    return text.length;
  }

  /// The advance table for this calculator's style, created empty (`-1` per
  /// glyph) on first use. Passing [_maxAdvanceTables] drops every table
  /// rather than tracking an LRU order: font changes come in bursts of one.
  List<double> _advanceTable() {
    final key = (config.fontSize, config.lineHeight, config.fontFamily);
    final existing = _advanceTables[key];
    if (existing != null) return existing;
    if (_advanceTables.length >= _maxAdvanceTables) _advanceTables.clear();
    final table = List<double>.filled(_asciiLast - _asciiFirst + 1, -1);
    _advanceTables[key] = table;
    return table;
  }

  /// Lay [text] out and read its width, without counting the layout: only
  /// per-line measurements belong in [debugLayoutCount].
  double _measureRaw(String text) {
    _textPainter.text = TextSpan(text: text, style: _getTextStyle());
    _textPainter.layout();
    return _textPainter.width;
  }

  /// Smart line breaking for all lines, respecting code blocks and markdown syntax.
  /// Returns the result with new lines and count of modified lines.
  LineBreakResult breakLinesSmartly(List<String> lines, double maxWidth) {
    final result = <String>[];
    int linesModified = 0;
    bool inCodeBlock = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // Toggle code block state
      if (_codeBlockFencePattern.hasMatch(trimmed)) {
        inCodeBlock = !inCodeBlock;
        result.add(line);
        continue;
      }

      // Skip lines inside code blocks
      if (inCodeBlock) {
        result.add(line);
        continue;
      }

      // Check if line needs breaking
      if (line.isEmpty || !lineExceedsWidth(line, maxWidth)) {
        result.add(line);
        continue;
      }

      // Line-led constructs (money rows, headings, quotes/callouts,
      // table rows) are never width-broken: the split tail would lose
      // the lead marker and the construct's meaning with it. Checked
      // only for lines that would actually break, so fitting lines
      // never pay the shape probe.
      if (MarkdownLineShape.isLineLedConstruct(trimmed)) {
        result.add(line);
        continue;
      }

      // Break the line respecting markdown syntax
      final brokenLines = _breakLineRespectingMarkdown(line, maxWidth);
      if (brokenLines.length > 1) {
        linesModified++;
      }
      result.addAll(brokenLines);
    }

    return LineBreakResult(lines: result, linesModified: linesModified);
  }

  /// Break a single line respecting markdown syntax.
  ///
  /// The caller has already established that [line] is non-empty and wider
  /// than [maxWidth], so the whole line is never re-measured on entry. A
  /// line that does fit still comes back as `[line]`: the loop below simply
  /// never runs.
  List<String> _breakLineRespectingMarkdown(String line, double maxWidth) {
    if (line.isEmpty) return [line];

    // Find all protected ranges (markdown syntax that shouldn't be broken)
    final protectedRanges = _findProtectedRanges(line);

    final result = <String>[];
    var remaining = line;
    var offset = 0;

    while (remaining.isNotEmpty && lineExceedsWidth(remaining, maxWidth)) {
      // Find the optimal break point
      int breakPoint = findBreakPoint(remaining, maxWidth);

      if (breakPoint <= 0) {
        // Can't fit even one character, force at least one
        breakPoint = 1;
      }

      // Adjust break point to respect protected ranges
      breakPoint = _adjustBreakPointForProtectedRanges(
        offset,
        breakPoint,
        protectedRanges,
        remaining.length,
      );

      // Try to break at a word boundary (space) if possible
      // but only if it doesn't put us inside a protected range
      final spaceIndex = remaining.lastIndexOf(' ', breakPoint);
      if (spaceIndex > 0) {
        final adjustedSpaceIndex = _adjustBreakPointForProtectedRanges(
          offset,
          spaceIndex,
          protectedRanges,
          remaining.length,
        );
        if (adjustedSpaceIndex == spaceIndex) {
          breakPoint = spaceIndex;
        }
      }

      // Ensure we make progress
      if (breakPoint <= 0) breakPoint = 1;

      result.add(remaining.substring(0, breakPoint).trimRight());
      // Track the leading-whitespace `trimLeft` strips so `offset` stays in
      // sync with the original-line coordinates that `protectedRanges` is
      // expressed in. Without this correction, breaking at a space before a
      // protected range (e.g. the space before a URL) leaves `offset` one
      // short, and the next iteration's protected-range check would be
      // off-by-one inside the URL — splitting it mid-token.
      final preTrimSuffix = remaining.substring(breakPoint);
      remaining = preTrimSuffix.trimLeft();
      offset += breakPoint + (preTrimSuffix.length - remaining.length);
    }

    if (remaining.isNotEmpty) {
      result.add(remaining);
    }

    return result;
  }

  /// Find all ranges in the line that shouldn't be broken (markdown syntax)
  List<_Range> _findProtectedRanges(String line) {
    final ranges = <_Range>[];

    // Find all patterns and add their ranges.
    // Images must come before links (they share the [text](url) syntax).
    // Bare URLs come last so a markdown link [text](https://...) is
    // already covered by _linkPattern and the URL portion is not
    // double-counted.
    for (final pattern in [
      _imagePattern,
      _linkPattern,
      _inlineCodePattern,
      _boldPattern,
      _italicPattern,
      _bareUrlPattern,
    ]) {
      for (final match in pattern.allMatches(line)) {
        ranges.add(_Range(match.start, match.end));
      }
    }

    // Sort by start position and merge overlapping ranges
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return _mergeOverlappingRanges(ranges);
  }

  /// Merge overlapping ranges
  List<_Range> _mergeOverlappingRanges(List<_Range> ranges) {
    if (ranges.isEmpty) return ranges;

    final merged = <_Range>[ranges.first];

    for (int i = 1; i < ranges.length; i++) {
      final current = ranges[i];
      final last = merged.last;

      if (current.start <= last.end) {
        // Overlapping or adjacent, merge
        merged[merged.length - 1] = _Range(
          last.start,
          current.end > last.end ? current.end : last.end,
        );
      } else {
        merged.add(current);
      }
    }

    return merged;
  }

  /// Adjust break point to not break inside protected markdown ranges
  int _adjustBreakPointForProtectedRanges(
    int lineOffset,
    int breakPoint,
    List<_Range> protectedRanges,
    int remainingLength,
  ) {
    final absoluteBreakPoint = lineOffset + breakPoint;

    for (final range in protectedRanges) {
      // If break point is inside a protected range, move it before the range
      if (absoluteBreakPoint > range.start && absoluteBreakPoint < range.end) {
        final adjustedBreakPoint = range.start - lineOffset;
        // Prefer breaking just before the protected range.
        if (adjustedBreakPoint > 0) {
          return adjustedBreakPoint;
        }
        // Can't break before — try breaking just after the range.
        final afterRange = range.end - lineOffset;
        if (afterRange < remainingLength) {
          return afterRange;
        }
        // The protected range covers the rest of `remaining` (e.g. a bare
        // URL that fills the line end with no trailing text).  Signal that
        // no break is possible by returning `remainingLength`; the caller
        // will emit the whole remaining as one unbroken line and exit the
        // while loop.
        return remainingLength;
      }
    }

    return breakPoint;
  }

  /// How many leading characters of [text] fit within [maxWidth].
  ///
  /// The search is seeded with the ASCII prefix that provably fits (see
  /// [_asciiFitPrefix]) rather than with 0. Since prefix widths grow with
  /// length, the largest fitting prefix is at or past that seed, so the
  /// binary search above it converges on exactly the same answer — it just
  /// starts with a chunk of the range already ruled in, which for a line
  /// only slightly over the width collapses the search to one or two
  /// layouts. Non-ASCII text seeds at the first non-ASCII code unit and so
  /// searches as before.
  @visibleForTesting
  int findBreakPoint(String text, double maxWidth) {
    int low = _asciiFitPrefix(text, maxWidth);
    int high = text.length;

    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final substring = text.substring(0, mid);
      if (measureTextWidth(substring) <= maxWidth) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return low;
  }

  TextStyle _getTextStyle() {
    return TextStyle(
      fontSize: config.fontSize,
      height: config.lineHeight,
      fontFamily: config.fontFamily,
    );
  }

  double? _measureWidgetWidth(GlobalKey key) {
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size.width;
  }
}

/// Simple range class for tracking protected text ranges
class _Range {
  final int start;
  final int end;

  const _Range(this.start, this.end);
}
