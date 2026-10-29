import 'package:flutter/widgets.dart';

/// The calendar guide's own numbers.
///
/// The guide is a settings-kit page of read rows: the kit draws the cards and
/// the language's metrics name the rest. What is left is what only a page
/// someone reads has — running text, a page heading, a hub row whose glyph
/// can give way to a long word — and it lives here, as the ring screen's
/// numbers live in `AlarmMetrics`, rather than in `FormMetrics`, which should
/// not grow for one page.
abstract final class GuideMetrics {
  /// A paragraph someone reads rather than a caption under a control: the
  /// kit's 12 px description is too small for that, and running text needs
  /// more line spacing than a one-line row.
  static const double paragraphFontSize = 14;
  static const double paragraphLineHeight = 1.4;

  /// The page heading's and the lead's side inset inside the list's own
  /// padding: the text then starts where the cards' rows start.
  static const double headingInset = 16;

  /// Under a page's heading, above its lead: one thought, so less than the
  /// gap the list keeps above its first card.
  static const double headingGap = 8;

  /// A hub row's padding, glyph and gaps, handed to its `ListTile` and read
  /// by the glyph rule's measurement, so the two cannot disagree. The values
  /// are Material 3's `ListTile` defaults: the row looks like Calendar
  /// settings' navigating rows.
  static const EdgeInsetsDirectional hubRowPadding = EdgeInsetsDirectional.only(
    start: 16,
    end: 24,
  );
  static const double hubGlyphSize = 24;
  static const double hubTitleGap = 16;

  /// The settings kit's row title, which the kit keeps private: the glyph
  /// rule measures a hub title's words in the style the kit draws them in,
  /// or it would drop the glyphs too early or let a word break. A test holds
  /// the two together, so a change in the kit fails there first.
  static const double hubTitleFontSize = 14;
  static const FontWeight hubTitleFontWeight = FontWeight.w500;

  /// The practice page's band under its bar: as tight as a banner can sit
  /// while its two lines still read as one block, the glyph a size under the
  /// bar's so the band never competes with the controls above it.
  static const double bannerVerticalPadding = 8;
  static const double bannerGlyphSize = 20;
  static const double bannerGap = 12;

  /// The band's first line, "Nothing here is saved.": the kit's row title
  /// weight at the paragraph size, on a 20 px line so the two lines keep
  /// Material's body rhythm. It never changes, so it is the band's anchor.
  static const double bannerTitleFontSize = 14;
  static const FontWeight bannerTitleFontWeight = FontWeight.w500;
  static const double bannerTitleLineHeight = 20;

  /// Material's own `MaterialBanner` clamp: past it the band would eat the
  /// grid the page exists to show, and its words are a reminder, not the
  /// content.
  static const double bannerMaxTextScale = 1.5;

  /// How much of a typed title a demo caption quotes before "…": a caption
  /// slot sized for any title would be as tall as the longest one anybody
  /// could type, so titles are cut and the slot is sized for the cut.
  static const int captionTitleMaxChars = 24;

  /// A "Try it" card's body inset: the kit's own row inset, so the lead-in
  /// starts where a read row's title starts in the card below it.
  static const double cardInset = 16;

  /// Lead-in to stage, then stage to caption: the stage belongs to the
  /// sentence that names it, the caption to the stage it reports on, so the
  /// second gap is the tighter one.
  static const double leadToStage = 12;
  static const double stageToCaption = 8;

  /// The stage: a sunken patch of the page's ground inside the card, its
  /// corners a step inside the card's, and the air its real widgets need
  /// from that hairline.
  static const double stageRadius = 12;
  static const double stagePadding = 12;

  /// The hairline round the stage: the ground alone barely separates from
  /// the card in dark (D29), and a line any heavier would read as a control.
  static const double stageOutline = 1;

  /// The kinds card's month of dots at twice the year tiles' size: a tile's
  /// matrix is a glance at one month of twelve, this one is the thing to
  /// watch, and its dots are drawn, so they scale without blur.
  static const double stageMatrixScale = 2;

  /// The setup card's sample week: the appearance page's preview, drawn on a
  /// stage narrower than that page — a 36 dp column a day on a 360 phone —
  /// cuts its Romanian "dum." off past 1.25. It is a picture of the grid, so
  /// it stops growing here, as the practice page's banner does.
  static const double sampleWeekMaxTextScale = 1.2;

  /// The demo grid's header, the calendar page's geometry: the title row
  /// tightened so the month name and its chevrons sit on one line.
  static const double practiceHeaderInset = 4;
  static const double practiceChevronPadding = 8;

  /// The air under the demo grid's marker strip, as the calendar page and
  /// the appearance preview leave it, so the bars sit where the real grid
  /// draws them.
  static const double practiceMarkerInset = 4;
}
