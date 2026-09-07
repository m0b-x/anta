/// Layout metrics for the in-note find/replace bar and its match list sheet.
class NoteSearchMetrics {
  /// The bar itself: one flat 48 dp strip, the height every app bar is.
  static const double barHeight = 48.0;
  static const double barBorderWidth = 1.0;
  static const double queryFontSize = 15.0;
  static const double queryStartInset = 16.0;

  /// The trailing controls: 20 px glyphs in 40 x 44 targets.
  static const double iconSize = 20.0;
  static const double iconButtonWidth = 40.0;
  static const double touchTarget = 44.0;
  static const double iconButtonWidthCompact = 36.0;

  // Match counter: a small tinted pill at the end of the query, sized by
  // its digits — it reads as a count, not as a control-sized cap.
  static const double counterChipRadius = 10.0;
  static const double counterFontSize = 12.0;
  static const double counterPaddingH = 8.0;
  static const double counterPaddingV = 1.0;
  static const double counterCaretSize = 12.0;
  static const int maxDisplayedMatches = 999;

  /// The replace row's own field keeps a pill, since it is a second input
  /// under the bar rather than part of it.
  static const double fieldHeight = 40.0;
  static const double fieldRadius = 20.0;

  // In-field clear button on the replace row.
  static const double clearButtonWidth = 36.0;
  static const double clearButtonHeight = 36.0;
  static const double clearButtonIconSize = 18.0;
  static const double clearButtonWidthCompact = 32.0;
  static const double clearButtonHeightCompact = 32.0;

  // Below this width the controls narrow (never shorten) so the query stays
  // readable on a small phone.
  static const double compactWidthThreshold = 340.0;

  static const double sheetRadius = 16.0;
  static const double sheetHeightFactor = 0.6;
  static const double headerHeight = 56.0;
  static const double matchRowExtent = 64.0;
  static const double lineNumberWidth = 40.0;
  static const double currentMarkerWidth = 3.0;
  static const double candidateBorderWidth = 1.0;
  static const double grabberWidth = 32.0;
  static const double grabberHeight = 4.0;
  static const double maxTextScaleForFixedExtent = 1.5;

  // Jump-to-number field in the sheet header. The go button is wider than a
  // square icon button at the number field's expense — a bigger target for
  // the action that actually moves the note.
  static const double jumpFieldWidth = 88.0;
  static const double jumpFieldHeight = 40.0;
  static const double jumpFieldRadius = 12.0;
  static const int maxJumpDigits = 6;
  static const double jumpGoButtonWidth = 64.0;

  static const Duration barAnimation = Duration(milliseconds: 200);
  static const Duration navigateDebounce = Duration(milliseconds: 250);
  static const Duration messageDuration = Duration(seconds: 2);

  NoteSearchMetrics._();
}
