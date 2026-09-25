import 'package:flutter/material.dart';

import 'row_metrics.dart';

abstract final class FormMetrics {
  static const double sheetRadius = 28;
  static const double handleStripHeight = 22;
  static const double handleWidth = 32;
  static const double handleHeight = 4;
  static const double headerHeight = 48;
  static const double headerTitleSize = 17;
  static const double bodyTop = 8;
  static const double bodyBottom = 24;

  static const double rowMinHeight = RowMetrics.singleLineMinHeight;
  static const double twoLineRowMinHeight = RowMetrics.twoLineMinHeight;
  static const double titleRowMinHeight = 56;
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
