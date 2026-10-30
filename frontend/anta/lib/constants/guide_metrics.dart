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

  /// Where a page's heading stops growing (D51): a 20 px heading at 2.0 is
  /// 40 px and four lines in German — a fifth of a 780 screen before the
  /// first instruction. At 1.5 it is 30 px; the lead and the rows below it
  /// keep the full scale, since they are what she reads.
  static const double headingMaxTextScale = 1.5;

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

  /// Below Material's `MaterialBanner` 1.5 (D39): at 1.5 the German band
  /// still pushed the Day panel's presence button off a 360 × 780 phone in
  /// the month format. The band is chrome, a reminder rather than the
  /// content, and its one line that matters stays legible at 1.3.
  static const double bannerMaxTextScale = 1.3;

  /// How much of a typed title a demo caption quotes before "…": a caption
  /// slot sized for any title would be as tall as the longest one anybody
  /// could type, so titles are cut and the slot is sized for the cut.
  static const int captionTitleMaxChars = 24;

  /// A "Try it" card's body inset: the kit's own row inset, so the lead-in
  /// starts where a read row's title starts in the card below it.
  static const double cardInset = 16;

  /// Coach line to stage: the stage belongs to the sentence that says where
  /// to tap on it.
  static const double coachToStage = 12;

  /// Between the coach line and its skip button: the button's own 48 dp
  /// target already carries air round its glyph, so the gap stays small.
  static const double coachGap = 8;

  /// Where a card's coach line and its skip stop growing (D66), as the
  /// practice band's [bannerMaxTextScale] (D39): at 2.0 the German fasting
  /// line took seven lines, a 273 dp slot, and the line and the stage it
  /// points at never shared the screen. The stage below keeps the full
  /// scale; it is what she reads and taps.
  static const double coachMaxTextScale = 1.3;

  /// The stage: a patch of the page's ground inside the card — a step darker
  /// in dark, the same tone as the card in light, where the hairline alone
  /// draws its edge — its corners a step inside the card's, and the air its
  /// real widgets need from that hairline.
  static const double stageRadius = 12;
  static const double stagePadding = 12;

  /// The hairline round the stage: the ground alone barely separates from
  /// the card in dark (D29), and a line any heavier would read as a control.
  static const double stageOutline = 1;

  /// From this text scale up the stage runs edge to edge inside the card,
  /// its hairline only above and below (D29's alternative): inset twice, a
  /// 360 phone leaves its rows about 270 dp, and German breaks the real
  /// sheets' words — "Wiederhol|ung" at 2.0, "Wiederholungen" beside a
  /// switch already at 1.3 — which the full-width sheets never do. Below it
  /// the stage keeps its inset patch.
  static const double stageFullBleedTextScale = 1.3;

  /// The kinds and finding cards' month of dots: as large as the stage's
  /// width allows, in whole steps of the year tiles' size so the dots stay
  /// crisp, never under twice that size — a tile's matrix is a glance at one
  /// month of twelve, this one is the thing to watch — and never past four
  /// times it, where a dot would outgrow the rows around it.
  static const double stageMatrixMinScale = 2;
  static const double stageMatrixMaxScale = 4;

  /// The alerts card's limit, under the editor's: two shows a notification
  /// beside an alarm, and the stage reserves a row for each alert it can
  /// hold — the editor's five made it taller than a phone's screen at 2.0.
  static const int demoAlertCap = 2;

  /// The setup card's sample week: the appearance page's preview, drawn on a
  /// stage narrower than that page — a 36 dp column a day on a 360 phone —
  /// cuts its Romanian "dum." off past 1.25. It is a picture of the grid, so
  /// it stops growing here, as the practice page's banner does.
  static const double sampleWeekMaxTextScale = 1.2;

  /// The demo grid's header: the calendar page's title row, tightened at the
  /// sides so the month name and its chevrons sit on one line, and with no
  /// air above or below, where the chevrons' padding round a 24 px glyph
  /// makes the 48 dp target the real page's 40 dp ones fall short of.
  static const double practiceHeaderInset = 4;
  static const double practiceChevronPadding = 12;

  /// The air under the demo grid's marker strip, as the calendar page and
  /// the appearance preview leave it, so the bars sit where the real grid
  /// draws them.
  static const double practiceMarkerInset = 4;

  /// The screen page's panel card: the mode bar and the slot under it that
  /// each of the three bodies scrolls inside — about three of the Day
  /// panel's rows at 1.0 — so a mode switch changes what the slot holds and
  /// never the card's height. Under half a 732 dp viewport, so the page
  /// around it stays in reach.
  static const double panelStageHeight = 300;

  /// The panel slot grows with the text up to this scale, 390 dp, and no
  /// further (D69): the mode bar is the real one and grows with the text,
  /// and at 2.0 a fixed 300 left the Day body about 200 dp under it — not
  /// one whole row. 390 still sits under half a 732 dp viewport.
  static const double panelStageMaxTextScale = 1.3;

  /// The overview card's slot under its nav, one for Year, Month and List,
  /// each body scrolling inside it: at 1.0 about a mini month, the picked
  /// day's rows a scroll below it, or three rows of tiles — under half a
  /// 732 dp viewport, as the panel card's.
  static const double overviewStageBodyHeight = 360;

  /// The fasting card's day panel under its grid: the date and two rows at
  /// 1.0 — a fast with its rule and the weekend, the most a day here says
  /// unless several traditions are on — scrolling inside the slot past
  /// that, so a picked day changes the rows and never the card's height.
  static const double fastingPanelHeight = 220;
}
