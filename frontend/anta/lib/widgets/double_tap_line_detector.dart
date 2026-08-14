import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';

/// Callback when user double-taps a line in preview.
/// Parameters: lineIndex (0-based), columnOffset (0-based)
typedef DoubleTapLineCallback = void Function(int lineIndex, int columnOffset);

/// Detects double-tap on a chunk and calculates the source line index.
/// Uses actual rendered chunk height and line-specific height scales
/// (headers are taller, empty lines shorter) for accurate line detection.
class DoubleTapLineDetector extends StatelessWidget {
  /// First source line (inclusive) contained in this chunk.
  final int chunkStartLine;

  /// Number of source lines contained in this chunk.
  final int chunkLineCount;

  /// Total number of lines in the document
  final int totalLines;

  /// Base font size for fallback calculations
  final double fontSize;

  /// Callback when a line is double-tapped
  final DoubleTapLineCallback onDoubleTapLine;

  /// The child widget to wrap with double-tap detection
  final Widget child;

  /// Height scales for each line in this chunk (e.g., 2.0 for H1, 0.5 for empty)
  final List<double> lineHeightScales;

  const DoubleTapLineDetector({
    super.key,
    required this.chunkStartLine,
    required this.chunkLineCount,
    required this.totalLines,
    required this.fontSize,
    required this.onDoubleTapLine,
    required this.child,
    required this.lineHeightScales,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap in LayoutBuilder to get actual rendered size for accurate calculation
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: (details) {
            _handleDoubleTap(context, details.localPosition, constraints);
          },
          child: child,
        );
      },
    );
  }

  void _handleDoubleTap(
    BuildContext context,
    Offset localPosition,
    BoxConstraints constraints,
  ) {
    // Lines contained in this specific chunk, sourced from the builder's
    // block-aligned chunk table.
    final linesInThisChunk = chunkLineCount;

    if (linesInThisChunk <= 0) {
      onDoubleTapLine(chunkStartLine.clamp(0, totalLines - 1), 0);
      return;
    }

    // Get the actual rendered height of this chunk widget
    final renderBox = context.findRenderObject() as RenderBox?;
    final actualChunkHeight = renderBox?.size.height ?? 0;

    int lineWithinChunk;

    if (actualChunkHeight > 0 &&
        lineHeightScales.isNotEmpty &&
        linesInThisChunk > 0) {
      // Use weighted line heights for accurate detection
      // Calculate total scale weight for this chunk
      double totalScaleWeight = 0;
      for (
        int i = 0;
        i < lineHeightScales.length && i < linesInThisChunk;
        i++
      ) {
        totalScaleWeight += lineHeightScales[i];
      }

      if (totalScaleWeight > 0) {
        // Calculate the height per unit of scale
        final heightPerScaleUnit = actualChunkHeight / totalScaleWeight;

        // Find which line the tap falls in by accumulating heights
        double accumulatedHeight = 0;
        lineWithinChunk = 0;

        for (
          int i = 0;
          i < lineHeightScales.length && i < linesInThisChunk;
          i++
        ) {
          final lineHeight = lineHeightScales[i] * heightPerScaleUnit;
          if (localPosition.dy < accumulatedHeight + lineHeight) {
            lineWithinChunk = i;
            break;
          }
          accumulatedHeight += lineHeight;
          lineWithinChunk = i;
        }
      } else {
        // Fallback to simple average if scales are all zero
        final avgLineHeight = actualChunkHeight / linesInThisChunk;
        lineWithinChunk = (localPosition.dy / avgLineHeight).floor();
      }
    } else {
      // Fallback to estimated line height
      final estimatedLineHeight = fontSize * MarkdownConstants.lineHeight;
      lineWithinChunk = (localPosition.dy / estimatedLineHeight).floor();
    }

    // Clamp to valid range within this chunk
    final clampedLineWithinChunk = lineWithinChunk.clamp(
      0,
      linesInThisChunk - 1,
    );
    final absoluteLineIndex = chunkStartLine + clampedLineWithinChunk;

    // Ensure we don't exceed total lines
    final finalLineIndex = absoluteLineIndex.clamp(0, totalLines - 1);

    // Column offset is 0 (start of line) - accurate column would require
    // text layout introspection which is complex with styled markdown spans
    const columnOffset = 0;

    onDoubleTapLine(finalLineIndex, columnOffset);
  }
}
