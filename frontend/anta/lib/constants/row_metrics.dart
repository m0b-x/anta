import 'package:flutter/material.dart';

/// The geometry every grouped browser row is drawn to — folder rows, note
/// rows, the root's smart rows and the search surface's results.
///
/// The sibling of [AppBarMetrics](app_bar_metrics.dart): one place for the
/// numbers the mock fixes, so the four row kinds cannot drift apart. Rows
/// share a rounded group, and what separates one group from the next is a
/// single gap ([groupGap]) carried by the group's last row — never a second
/// pad on the label above the next one.
class RowMetrics {
  /// Left and right of every group, and of the section label above it.
  static const double groupInset = 16.0;

  /// The rounded card a run of rows shares.
  static const double groupRadius = 14.0;

  /// Between one group and the next. Sits under the group's last row so the
  /// first group starts flush with the list.
  static const double groupGap = 18.0;

  /// The hairline between two rows of one group starts past the leading
  /// glyph on rows that have one, and at the group edge on rows that do not.
  static const double dividerIndentWithGlyph = 52.0;
  static const double dividerIndentPlain = 16.0;

  /// The "FOLDERS" / "NOTES" / "RECENT" label above a group.
  static const double sectionLabelFontSize = 11.0;
  static const FontWeight sectionLabelFontWeight = FontWeight.w500;
  static const double sectionLabelLetterSpacing = 0.88;

  /// The label's own inset inside [groupInset], and the air below it.
  static const double sectionLabelInset = 4.0;
  static const double sectionLabelBottomPadding = 6.0;

  /// A folder row, a smart row: one line, glyph, name, count, chevron.
  static const double singleLineMinHeight = 48.0;

  /// A note row or a search result: title over a second line.
  static const double twoLineMinHeight = 62.0;

  /// Inside a one-line row. The right side is tighter because the chevron
  /// carries its own optical margin.
  static const EdgeInsets singleLinePadding = EdgeInsets.only(
    left: groupInset,
    right: 12,
  );

  /// Inside a two-line row.
  static const EdgeInsets twoLinePadding = EdgeInsets.symmetric(
    horizontal: groupInset,
    vertical: 9,
  );

  /// Between a row's own parts — glyph to name, name to count, count to
  /// chevron.
  static const double gap = 14.0;

  /// Between the two lines of a note row.
  static const double lineGap = 2.0;

  /// The leading glyph on a folder or smart row.
  static const double glyphSize = 22.0;

  /// The chevron that says a row opens something.
  static const double chevronSize = 18.0;

  /// The bare descendant count on a folder or smart row.
  static const double countFontSize = 14.0;

  /// Reserved for the count so a late answer changes nothing above or below
  /// it — three tabular digits at [countFontSize].
  static const double countMinWidth = 26.0;

  /// A row's own name or title.
  static const double titleFontSize = 15.0;

  /// The date-and-preview line under a note title, and a result's path line.
  static const double secondLineFontSize = 13.0;

  /// The folder chain above a note's second line, drawn only where a listing
  /// spans folders.
  static const double pathLaneFontSize = 11.0;

  /// The browser's create bar and the selection action bar that replaces it:
  /// one height, so entering selection moves no row.
  static const double bottomBarHeight = 52.0;

  /// The tap target of each bar button, and the glyph inside it.
  static const double bottomBarButtonSize = 48.0;
  static const double bottomBarGlyphSize = 22.0;

  /// "3 folders, 5 notes", centred between the buttons.
  static const double bottomBarCountFontSize = 13.0;
}
