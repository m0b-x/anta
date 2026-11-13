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

  /// A drawer row's leading glyph: the stock Material 3 tile's, which fills
  /// the settings kit's leading slot, so the drawer's titles start where the
  /// hub's do.
  static const double drawerGlyphSize = 24.0;

  /// The drawer's account avatar: a disc as wide as [drawerGlyphSize], so
  /// the account row's name starts where every place's title does.
  static const double drawerAvatarRadius = drawerGlyphSize / 2;

  /// The text-scale factor from which the account row's status line is
  /// given two lines. Android's first step above 100 %, 115 %, scales 13 sp
  /// non-linearly to about 1.16, where one line of the drawer's 196 dp text
  /// column on a 360 phone already cuts most German lines and "Paused —
  /// daily limit reached"; 1.1 sits under that step and above 1.0.
  static const double drawerStatusTwoLineTextScale = 1.1;

  /// The factor from which it is given three. Android's 180 % step gives
  /// about 1.77 at 13 sp, where two lines cut "Zuletzt synchronisiert
  /// 15:09"; 1.7 sits under it and above the 150 % step's 1.54, which two
  /// lines hold. Decided by the scale, never by measuring the line, so the
  /// row is one height in every state.
  static const double drawerStatusThreeLineTextScale = 1.7;

  /// Before the 48 dp drag handle of a reorderable content row (the
  /// categories page): the handle's own target carries the rest of the
  /// optical margin, so a full [groupInset] would push the name past the
  /// column that keeps every built-in name whole at 2.0 on a 360 screen.
  static const double reorderHandleLead = 4.0;

  /// Where a reorderable row's text and hairline start beside an avatar:
  /// [reorderHandleLead] + the 48 dp handle + the 40 dp avatar + [gap].
  static const double reorderAvatarTextInset = 106.0;

  /// The same start beside a [glyphSize] glyph, the leading a large text
  /// scale takes instead of the avatar: [reorderHandleLead] + 48 + 22 +
  /// [gap].
  static const double reorderGlyphTextInset = 88.0;

  /// Where a row's text and hairline start beside a 40 dp avatar when the
  /// row has no reorder handle — a partner's category on the categories
  /// page: [groupInset] + 40 + [gap].
  static const double avatarTextInset = 70.0;

  /// The text-scale factor from which a reorderable row's leading drops the
  /// 40 dp avatar for a [glyphSize] glyph: the 18 dp it frees keeps every
  /// built-in category's name on one line at 2.0 in all three languages
  /// (linear 1.3 keeps the avatar; linear 2.0 and Android's 200 %, a factor
  /// of 1.8, take the glyph). Decided by the scale, never by measuring
  /// names, so a row never changes shape with its data.
  static const double compactLeadingTextScale = 1.6;

  /// The chevron that says a row opens something.
  static const double chevronSize = 18.0;

  /// The colour-label dot at a row's trailing edge. Drawn only on a labelled
  /// row — an unlabelled one reserves nothing, so turning a label on is the
  /// only thing that ever moves the name beside it.
  static const double labelDotSize = 10.0;

  /// The colour-label stripe on a row's leading edge, the dot's alternative.
  static const double labelStripeWidth = 3.0;

  /// How far the stripe stops short of the row's top and bottom, so a run of
  /// labelled rows reads as separate marks rather than one continuous bar.
  static const double labelStripeInset = 8.0;

  /// Only the stripe's right-hand corners round: its left edge is flush with
  /// the group's, where the group's own clip rounds it on an end row.
  static const double labelStripeRadius = 3.0;

  /// The partner's face in the share badge an event avatar wears: a 20 dp
  /// disc, large enough for a photo to read, small enough to sit on the
  /// avatar's rim without reaching the title.
  static const double partnerAvatarRadius = 10.0;

  /// The share sign — the "mine" badge's glyph, and the bare glyph a row
  /// without an event avatar carries.
  static const double shareMarkSize = 14.0;

  /// The air around a share mark — the sign on what I share, the partner's
  /// face: from a row's mark to the count after it, where the mark reads as
  /// one more fact of the row, and from the sign to the title it follows in
  /// the note editor's bar.
  static const double shareMarkGap = 8.0;

  /// The partner's face at the start of a note row's or a search result's
  /// second line: a 16 dp disc on a 13 sp line, never taller than the line
  /// from text scale 1.3 up, so the row keeps the height of a note of mine.
  static const double partnerFaceInlineRadius = 8.0;

  /// From that inline face to the date after it.
  static const double partnerFaceInlineGap = 4.0;

  /// The category glyph inside a partner's 20 dp outlined ring on the Alerts
  /// hub's rows: at [shareMarkSize] the glyph touched the 1.5 dp ring.
  static const double shareRingIconSize = 12.0;

  /// The `rowGroup` ring that parts the share badge from the avatar under
  /// it; the badge's outer disc is `2 × (partnerAvatarRadius + this)`.
  static const double shareBadgeHalo = 2.0;

  /// `SharedReadOnlyLine`: the group's side inset, and a vertical pad that
  /// keeps the 20 dp face clear of the band's edges at one line.
  static const EdgeInsets sharedLinePadding = EdgeInsets.symmetric(
    horizontal: groupInset,
    vertical: 6,
  );

  /// From the face to the text of `SharedReadOnlyLine`.
  static const double sharedLineGap = 8.0;

  /// A long name or an address wraps; past three lines it is cut, so the
  /// line never takes the body's room at large text.
  static const int sharedLineMaxLines = 3;

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
  static const double bottomBarHeight = 60.0;

  /// The tap target of each bar button, and the glyph inside it. A step
  /// bigger than the mock draws them: both create buttons sit at the left
  /// edge, where the thumb of the hand holding the phone reaches them.
  static const double bottomBarButtonSize = 54.0;
  static const double bottomBarGlyphSize = 28.0;

  /// The air between the bar's left edge and the first button.
  static const double bottomBarInset = 4.0;

  /// "3 folders, 5 notes", centred on the bar behind the buttons.
  static const double bottomBarCountFontSize = 13.0;

  /// The hairline between two rows of a group, and the space it takes.
  static const double dividerThickness = 1.0;

  /// The widest a folded section's "12 options" may grow beside its title,
  /// as a share of the header: past it the count wraps, so a long German
  /// title at 2.0 is never squeezed to a letter a line.
  static const double settingsCountMaxShare = 1 / 3;

  /// The widest a section's status words ("Updated 2 min ago") may reserve
  /// beside its title, as a share of the header: a status is a sentence
  /// where the count is a number, and past half the title would wrap a word
  /// a line.
  static const double settingsStatusMaxShare = 1 / 2;

  /// The least of a settings row's text column a value beside the title may
  /// leave to the title and its description: under it the value goes under
  /// the description, since a value of 197 px left "All-day events" one
  /// word a line and its caption seven lines tall at 1.0 on a 360 phone.
  static const double settingsValueMinTextShare = 1 / 2;

  /// The most steps a settings slider reads out to size its caption's slot
  /// from every reading: a caption whose longest reading falls mid-range
  /// ("1410 minutes before" against "24 hours before") moved the slider
  /// under the finger when only the ends were measured. Past it, the ends.
  static const int sliderReadingTemplatesMax = 200;

  /// "No matches": the air above and below it and its glyph.
  static const double emptyStatePadding = 48.0;
  static const double emptyStateGlyphSize = 48.0;

  /// How far down the screen the launch states' glyph slot sits. Anchored
  /// to the screen rather than centred with what follows it, so the failed
  /// state, taller by its next step, Retry and detail, moves neither the
  /// slot nor the title when it replaces a spinner; a quarter keeps Retry in
  /// view at 2.0 on a 360 × 780 phone.
  static const double launchSlotTopShare = 1 / 4;
}
