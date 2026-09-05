import '../constants/markdown_constants.dart';
import 'markdown_line_shape.dart';

/// The **preview's** ratio table for markdown line heights.
///
/// Determines the relative height of each line from its markdown shape
/// and is used for positioning inside the preview — double-tap line
/// detection above all. Its only caller is
/// `LineBasedMarkdownBuilder.getLineHeightScales`, and every ratio here
/// (H6 at 0.875, rules and empty lines at 0.5, fence lines at 0.9)
/// describes what the *preview* draws.
///
/// **Not for the live editor.** That surface renders H5/H6, horizontal
/// rules, empty lines and fence lines at the base size, so these ratios
/// would misplace anything anchored to an editor line; editor geometry
/// comes from the render's `lineHeightOfLine` / `lineHeightAtOffset`
/// instead. The table also predates `LineMarkdownStyle.flattenHeadings`
/// and does not apply it: with flattened headings the preview draws
/// every heading at the normal size while this still reports the
/// per-level ratio.
class MarkdownLineHeightCalculator {
  MarkdownLineHeightCalculator._();

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
    // Check if inside code block - code uses slightly smaller font
    if (isInsideCodeBlock) {
      return MarkdownConstants.codeBlockScale;
    }

    // Empty line - renders with fontSize * emptyLineScale, so half the normal height
    if (line.trimLeft().isEmpty) {
      return MarkdownConstants.emptyLineScale;
    }

    // Headings and horizontal rules come from the shared
    // [MarkdownLineShape] probes, the same ones
    // LineBasedMarkdownBuilder.buildLine dispatches on — `#tag` (no
    // space) and `#######` (7+) are NOT headings, they render as normal
    // paragraphs, so they must use the normal scale to keep double-tap
    // line mapping aligned with what is actually drawn.
    final heading = MarkdownLineShape.headingAt(line);
    if (heading != null) {
      switch (heading.level) {
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

    if (MarkdownLineShape.isHorizontalRule(line)) {
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
