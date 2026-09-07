import 'package:flutter/material.dart';

/// The geometry every app bar in the browser/editor family is drawn to.
///
/// One toolbar height across the app is the point: the browser's collapsed
/// large bar, the selection bar that replaces it, the search field bar, the
/// editor bar and the settings bar all settle at [toolbarHeight], so swapping
/// one for another moves nothing but the bar's own contents.
class AppBarMetrics {
  /// The height of every bar's toolbar row, status bar excluded.
  static const double toolbarHeight = 48.0;

  /// Bar glyphs — leading, actions and the search field's clear button.
  static const double glyphSize = 22.0;

  /// The collapsed title, the editor title and the settings title.
  static const double titleFontSize = 17.0;

  /// The weight those titles share. Bold reads as a heading in a bar that is
  /// already the shortest line on the screen.
  static const FontWeight titleFontWeight = FontWeight.w500;

  /// The browser's large title, the line it occupies, and the tracking that
  /// keeps 28 px from looking loose (−0.01 em).
  static const double largeTitleFontSize = 28.0;
  static const double largeTitleHeight = 1.15;
  static const double largeTitleLetterSpacing = -0.28;

  /// Below the large title, and above it on a page with no eyebrow.
  static const double largeTitleBottomPadding = 14.0;
  static const double largeTitleTopPaddingAtRoot = 8.0;

  /// Left and right of the large title, and of the eyebrow above it.
  static const double largeTitlePadding = 20.0;
  static const double eyebrowPadding = 21.0;

  /// The parent-folder line between the toolbar and the large title: one
  /// line, no band above or below it.
  static const double eyebrowHeight = 22.0;
  static const double eyebrowFontSize = 13.0;

  /// The save-status slot in the editor's bar. Fixed so the title never
  /// reflows when an 8 dp dot becomes a 14 dp cloud.
  static const double saveStatusSlotSize = 14.0;
  static const double saveStatusDotSize = 8.0;
  static const double saveStatusGap = 8.0;
}
