/// Layout metrics for the in-note find/replace bar and its match list sheet.
class NoteSearchMetrics {
  static const double fieldHeight = 48.0;
  static const double fieldRadius = 24.0;
  static const double touchTarget = 48.0;
  static const double iconButtonWidthCompact = 44.0;

  // Match counter: a tinted cap on the field's trailing edge — same height and
  // radius as the field, flush to its right, so it closes the pill off rather
  // than floating inside it.
  static const double counterChipHeight = fieldHeight;
  static const double counterChipRadius = fieldRadius;
  static const double counterMinWidth = 52.0;
  static const double counterMinWidthCompact = 44.0;
  static const double counterCaretSize = 12.0;
  static const int maxDisplayedMatches = 999;

  // In-field clear button. Tune all three values here to resize the X.
  static const double clearButtonWidth = 36.0;
  static const double clearButtonHeight = 36.0;
  static const double clearButtonIconSize = 18.0;
  // Narrow variant for small phones with the replace row open.
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
