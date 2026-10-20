import 'package:flutter/painting.dart';

import 'app_theme.dart';

/// The markdown bar's numbers — the editor's most tapped surface, so they
/// live in one place rather than as literals spread over its buttons, its
/// suggestion row and its reorder panel.
abstract final class MarkdownBarMetrics {
  /// Every bar button's hit area, laid edge to edge: the 48 dp target with
  /// no dead band between two buttons. The row grew from 40 to this once
  /// (the review's D1); the suggestion row shares the height.
  static const double buttonSize = 48;

  /// An icon button's glyph. It does not follow the system text size, by
  /// design: a scaled glyph would outgrow the row the suggestion bar shares.
  static const double glyphSize = 20;

  /// B, I and H, the shortcuts drawn as letters.
  static const double letterGlyphSize = 16;

  /// The space between the bar's scrolled content and the screen's edges.
  static const double sidePadding = 12;

  /// The band above and below the button row, inside the bar's surface,
  /// which the suggestion row keeps too.
  static const double verticalPadding = AppTheme.editorBarVerticalPadding;

  /// The hairline between the shortcut and the utility sections.
  static const double dividerHeight = 24;

  /// The space on either side of that hairline in the split bar.
  static const double dividerGap = 4;

  /// The same space in the single-row bar, which separates two kinds of
  /// button inside one scroll view rather than two sections.
  static const double singleRowDividerGap = 8;

  /// How far an edge fade reaches into a scroller that has more content
  /// beyond that edge — the strip's only cue that it scrolls.
  static const double edgeFadeExtent = 24;

  /// The suggestion row: the gap after a scoped session's label, the gap
  /// between two pills, a pill's side padding and the alpha of the list's
  /// name under a term.
  static const double suggestionScopeGap = 8;
  static const double suggestionPillGap = 6;
  static const double suggestionPillPadding = 14;
  static const double suggestionSourceAlpha = 0.7;

  /// The reorder panel's ceiling as a share of the height above the
  /// keyboard, so the editor it sits under always keeps the other half.
  static const double reorderPanelMaxShare = 0.5;

  /// The most of the reorder panel's cap its header may take before its
  /// title scrolls, so the chips below always keep the rest.
  static const double reorderHeaderMaxShare = 0.5;

  /// The padding around each section of reorder chips.
  static const EdgeInsets reorderSectionPadding = EdgeInsets.all(12);

  /// The gap between two reorder chips, along a run and between runs.
  static const double reorderChipSpacing = 8;

  /// The drop marker's width: the bar a dragged chip shows before its
  /// target. It stands in the spacing before that chip, as tall as the
  /// chip, and takes no width of its own, so no run reflows mid-drag.
  static const double reorderDropMarkerWidth = 4;

  /// The drop marker's corner radius.
  static const double reorderDropMarkerRadius = 2;

  /// The reorder panel's header: its padding, its drag glyph and the gap
  /// between the glyph, the title and Done.
  static const EdgeInsets reorderHeaderPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );
  static const double reorderHeaderGlyphSize = 20;
  static const double reorderHeaderGap = 8;

  /// The Utilities label over the panel's second section.
  static const EdgeInsets reorderSectionLabelPadding = EdgeInsets.only(
    left: 16,
    top: 8,
  );
  static const double reorderSectionLabelFontSize = 12;

  /// A reorder chip is a long-press target, so it is never shorter than a
  /// bar button.
  static const double reorderChipMinHeight = buttonSize;

  /// A reorder chip's padding, corner, glyphs, label and the gaps between
  /// its drag handle, its glyph and its label.
  static const EdgeInsets reorderChipPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );
  static const double reorderChipRadius = 10;
  static const double reorderChipGlyphSize = 18;
  static const double reorderChipLetterSize = 16;
  static const double reorderChipLabelFontSize = 13;
  static const double reorderChipHandleGap = 6;
  static const double reorderChipLabelGap = 8;

  /// A utility chip's drag handle, quieter than the glyph beside it.
  static const double reorderChipHandleAlpha = 0.6;

  /// The chip left in place while its copy is dragged.
  static const double reorderDraggedOpacity = 0.3;

  /// The copy under the finger, lifted off the panel.
  static const double reorderFeedbackElevation = 8;
  static const double reorderFeedbackRadius = 12;

  /// How near the panel's top or bottom edge a drag starts scrolling it,
  /// and the most it scrolls per tick at the edge itself.
  static const double reorderEdgeScrollZone = 60;
  static const double reorderAutoScrollStep = 12;
}
