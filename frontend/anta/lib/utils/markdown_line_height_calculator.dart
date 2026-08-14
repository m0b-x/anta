import '../constants/markdown_constants.dart';

/// Utility class for calculating markdown line height scales.
///
/// This calculator determines the relative height of each line based on its
/// markdown content type. Used for accurate positioning in preview mode,
/// particularly for double-tap line detection.
class MarkdownLineHeightCalculator {
  MarkdownLineHeightCalculator._();

  /// Horizontal rule pattern (---, ***, ___)
  static final _horizontalRulePattern = RegExp(r'^[-*_]{3,}\s*$');

  /// Calculate the height scale for a single line based on its content type.
  /// Returns the actual rendered height ratio relative to normal text (1.0).
  ///
  /// Calculation: Each line's pixel height = baseFontSize * fontScale * lineHeight
  /// Since lineHeight (1.5) is constant, the ratio simplifies to fontScale.
  /// Normal text has fontScale 1.0, H1 has fontScale 2.0, etc.
  ///
  /// Supported markdown types:
  /// - Headings (H1-H6): Use heading scale constants
  /// - Empty lines: Use emptyLineScale (0.5)
  /// - Horizontal rules (---, ***, ___): Use horizontalRuleScale (0.5)
  /// - Code blocks (inside ```): Use codeBlockScale (0.9)
  /// - Images, tables, lists, blockquotes, paragraphs: Use normalLineScale (1.0)
  ///
  /// Parameters:
  /// - [line]: The raw line content
  /// - [isInsideCodeBlock]: Whether this line is inside a code fence block
  static double getLineHeightScale(
    String line, {
    bool isInsideCodeBlock = false,
  }) {
    final trimmed = line.trimLeft();

    // Check if inside code block - code uses slightly smaller font
    if (isInsideCodeBlock) {
      return MarkdownConstants.codeBlockScale;
    }

    // Empty line - renders with fontSize * emptyLineScale, so half the normal height
    if (trimmed.isEmpty) {
      return MarkdownConstants.emptyLineScale;
    }

    // Headings: 1–6 leading '#' that must be followed by a space or be
    // the whole line (CommonMark). This mirrors the renderer's heading
    // rule in LineBasedMarkdownBuilder.buildLine — `#tag` (no space) and
    // `#######` (7+) are NOT headings, they render as normal paragraphs
    // (and may contain `#tag`s), so they must use the normal scale to
    // keep double-tap line mapping aligned with what is actually drawn.
    if (trimmed.startsWith('#')) {
      int hashes = 0;
      while (hashes < trimmed.length && trimmed.codeUnitAt(hashes) == 0x23) {
        hashes++;
      }
      final followedBySpaceOrEol =
          hashes == trimmed.length || trimmed.codeUnitAt(hashes) == 0x20;
      if (hashes <= 6 && followedBySpaceOrEol) {
        switch (hashes) {
          case 1:
            return MarkdownConstants.h1Scale; // 2.0
          case 2:
            return MarkdownConstants.h2Scale; // 1.5
          case 3:
            return MarkdownConstants.h3Scale; // 1.25
          case 4:
            return MarkdownConstants.h4Scale; // 1.125
          case 5:
            return MarkdownConstants.h5Scale; // 1.0
          default:
            return MarkdownConstants.h6Scale; // 0.875
        }
      }
    }

    // Horizontal rule (---, ***, ___) - renders at half height
    if (_horizontalRulePattern.hasMatch(trimmed)) {
      return MarkdownConstants.horizontalRuleScale;
    }

    // All other content uses normal scale:
    // - Images (![alt](url))
    // - Tables (| cell | cell |)
    // - Checkbox lists (- [x] item)
    // - Unordered lists (- item, * item, + item)
    // - Ordered lists (1. item)
    // - Blockquotes (> text)
    // - Code fence markers (```)
    // - Regular paragraphs with inline formatting
    return MarkdownConstants.normalLineScale;
  }
}
