import 'package:flutter/material.dart';

import 'row_metrics.dart';

abstract final class FormMetrics {
  static const double sheetRadius = 28;

  /// The tallest any calendar sheet gets: the editor's fixed height and the
  /// clamp on every content-tall sheet (Repeat, Icon & color, the detail
  /// sheet). One number, so the sheets in the detail loop never disagree
  /// about where the top edge sits.
  static const double sheetHeightFactor = 0.92;
  static const double handleStripHeight = 22;
  static const double handleWidth = 32;
  static const double handleHeight = 4;
  static const double headerHeight = 48;
  static const double headerTitleSize = 17;

  /// The header's text action — a sub-sheet's Done, the detail sheet's Edit.
  /// The trailing inset is tighter than the editor's 12 because a text
  /// button carries its own horizontal padding where a filled one does not.
  static const double headerActionFontSize = 14;
  static const EdgeInsets headerActionPadding = EdgeInsets.symmetric(
    horizontal: 12,
  );
  static const double headerActionInset = 8;

  /// The most of the header a trailing action may take. Past it the label
  /// ellipsizes instead of pushing the row past the sheet — reached only by
  /// a large accessibility scale on a narrow phone, where a 28 px
  /// "Bearbeiten" beside a 48 dp close button otherwise overflows.
  static const double headerActionMaxShare = 0.6;
  static const double bodyTop = 8;
  static const double bodyBottom = 24;

  static const double rowMinHeight = RowMetrics.singleLineMinHeight;
  static const double twoLineRowMinHeight = RowMetrics.twoLineMinHeight;
  static const double titleRowMinHeight = 56;

  /// The event title as the editor's field and the detail sheet's heading
  /// draw it, so Edit and Back never resize the one line the eye is on.
  static const double titleFontSize = 20;
  static const double titleLineHeight = 1.3;
  static const double glyphSize = RowMetrics.glyphSize;
  static const double chevronSize = RowMetrics.chevronSize;
  static const double gap = RowMetrics.gap;
  static const double labelSize = RowMetrics.titleFontSize;
  static const double captionSize = RowMetrics.secondLineFontSize;
  static const double counterSize = 12;
  static const double trailingIconSize = 20;
  static const double trailingButtonSize = 48;
  static const double subRowInset = RowMetrics.dividerIndentWithGlyph;
  static const double rowEndPadding = 12;
  static const double pairVerticalPadding = 6;
  static const double pairRunSpacing = 2;

  /// A caption line that belongs to the row above it (the next occurrences
  /// after "Next occurrence", the adherence lines under the presence chips):
  /// the pair's own 6 dp already separates it from the value, so only the
  /// bottom needs air.
  static const double rowCaptionBottomPadding = 10;

  /// The description cell shared by the editor (a re_editor surface) and the
  /// detail sheet (a markdown preview): 15 px over a 22 px line, 13 dp above
  /// and below, so one line is exactly a 48 dp row.
  static const double descriptionFontSize = 15;
  static const double descriptionLineHeight = 22;
  static const double descriptionCellPadding = 13;

  /// Under a description cell's caption — the editor's over-the-limit line,
  /// the detail sheet's inert-box line — so the two cells end alike.
  static const double descriptionCaptionBottomPadding = 12;

  static const double dividerIndentGlyph = RowMetrics.dividerIndentWithGlyph;
  static const double dividerIndentPlain = RowMetrics.dividerIndentPlain;
  static const double dividerIndentTitle = 70;

  static const double chipHeight = 32;
  static const double chipRadius = 8;
  static const double chipFontSize = 14;
  static const double chipTapTarget = 48;
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(horizontal: 14);
  static const EdgeInsets chipRowPadding = EdgeInsets.fromLTRB(
    subRowInset,
    8,
    12,
    12,
  );
  static const double chipSpacing = 8;

  static const double menuRowHeight = 44;
  static const double menuIconSize = 20;
  static const double menuRadius = 12;
  static const EdgeInsets menuPadding = EdgeInsets.symmetric(vertical: 6);

  static const double disabledOpacity = 0.38;
}
