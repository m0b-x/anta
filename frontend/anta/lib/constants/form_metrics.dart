import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'row_metrics.dart';

abstract final class FormMetrics {
  static const double sheetRadius = 28;

  /// The tallest any calendar sheet gets: the form sheets' fixed height, the
  /// box of both fillers and the clamp on every sub-sheet. One number, so the
  /// sheets in the detail loop never disagree about where the top edge sits.
  static const double sheetHeightFactor = 0.92;

  /// A form sheet's own drag (`FormSheetFrame`): the fling speed past which a
  /// downward drag on the chrome dismisses whatever its length, the share of
  /// the sheet's height a slower drag has to cover to dismiss, and the spring
  /// back to rest after one that fell short. The editor's numbers, hoisted so
  /// every form sheet dismisses alike.
  static const double sheetDismissVelocity = 700;
  static const double sheetDismissFraction = 0.25;
  static const Duration sheetSnapBackDuration = Duration(milliseconds: 150);
  static const double handleStripHeight = 22;
  static const double handleWidth = 32;
  static const double handleHeight = 4;
  static const double headerHeight = 48;
  static const double headerTitleSize = 17;

  /// The lines the title may take once a header that opts in
  /// (`FormSheetHeader.stackTitleAtLargeText`) has set it on a line of its
  /// own under the ✕ and the action, because it did not fit beside them.
  static const int headerTitleMaxLines = 2;

  /// The air under a title on its own line before the body, so the body's
  /// first row does not read as the title's second line.
  static const double headerStackedTitleBottomPadding = 8;

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

  /// Under the caption band a filler pins beneath its header — the day
  /// list's card line — so the chip row after it starts clear of the text.
  static const double headerCaptionBottomPadding = 8;
  static const double bodyTop = 8;
  static const double bodyBottom = 24;

  static const double rowMinHeight = RowMetrics.singleLineMinHeight;
  static const double twoLineRowMinHeight = RowMetrics.twoLineMinHeight;
  static const double titleRowMinHeight = 56;

  /// The title row's own geometry (`FormTitleRow`, and the Look sheet's Icon
  /// row, the same 56 dp avatar row with a label · value pair in the field's
  /// place): the air above and below its 40 dp avatar, which is what makes
  /// the row 56; the inset that drops the field's first 26 px line onto the
  /// avatar's centre line; and the gap between the field and the counter
  /// under it.
  static const double titleRowVerticalPadding = 8;
  static const double titleFieldTopInset = 7;
  static const double titleCounterTopInset = 2;

  /// The value a sheet leads with — the quick alarm's time — and the line it
  /// sits on.
  static const double heroValueSize = 40;
  static const double heroValueLineHeight = 46;

  /// The hero row (`FormHeroRow`): the two-line row's padding around a
  /// [heroValueLineHeight] line, the 2 dp line gap and an 18 px caption line.
  static const double heroRowMinHeight = 84;

  /// The stepper row's value box (`FormStepperRow`). A floor rather than the
  /// text's own width, so the minus button does not slide under the thumb as
  /// "9 weeks" becomes "10 weeks".
  static const double stepperValueMinWidth = 96;

  /// The room between a typeable stepper value and the underline that says
  /// it can be typed into, above and below the digits alike so they keep
  /// the line a plain value sits on.
  static const double stepperFieldUnderlineGap = 2;

  /// The box a row's leading widget sits in — an `EventAvatar`'s diameter —
  /// so a row that carries one keeps the title row's 56 dp shape and its
  /// divider indent whatever the widget draws.
  static const double rowLeadingSize = 40;

  /// The event title as the editor's field and the detail sheet's heading
  /// draw it, so Edit and Back never resize the one line the eye is on.
  static const double titleFontSize = 20;
  static const double titleLineHeight = 1.3;
  static const double glyphSize = RowMetrics.glyphSize;
  static const double chevronSize = RowMetrics.chevronSize;
  static const double gap = RowMetrics.gap;
  static const double labelSize = RowMetrics.titleFontSize;

  /// The line a 15 px label sits on. The search row pads its field to the
  /// row's height around it, so a tap anywhere in the 48 dp row focuses the
  /// field rather than only its 20 px of text.
  static const double labelLineHeight = 20;
  static const EdgeInsets searchFieldPadding = EdgeInsets.symmetric(
    vertical: (rowMinHeight - labelLineHeight) / 2,
  );
  static const double captionSize = RowMetrics.secondLineFontSize;

  /// The line every caption sits on (`FormCaption` and the rows' own caption
  /// lines in `form_rows.dart`): tighter than the body's, so a title and its
  /// caption line fit one 48 dp target together — the period nav's title over
  /// its count.
  static const double captionLineHeight = 18;

  /// The settings kit's rows on the browser's heights: a label line over a
  /// caption line inside this much air is a [twoLineRowMinHeight] row, and a
  /// one-line row still reaches [rowMinHeight] through the tile's minimum.
  static const double settingsRowVerticalPadding =
      (twoLineRowMinHeight - labelLineHeight - captionLineHeight) / 2;

  /// Developer options' denser rows (`SettingsSectionStyle.compact`): a
  /// debugging page holds many switches and reads as a list of flags.
  static const double settingsCompactRowVerticalPadding = 8;

  /// A settings tile's sides: the group's inset at the start, the tighter
  /// row end where a switch or a value carries its own optical margin.
  static const EdgeInsetsDirectional settingsRowPadding =
      EdgeInsetsDirectional.only(
        start: RowMetrics.groupInset,
        end: rowEndPadding,
      );

  /// A settings row the kit draws without a tile — a segmented choice, a
  /// slider — padded as a tile pads its text, so the titles line up.
  static const EdgeInsetsDirectional settingsControlRowPadding =
      EdgeInsetsDirectional.fromSTEB(
        RowMetrics.groupInset,
        settingsRowVerticalPadding,
        rowEndPadding,
        settingsRowVerticalPadding,
      );

  /// Between a settings row's text and the control drawn under it.
  static const double settingsControlGap = 8;

  /// A settings row's full-width button (the Test alarm): air above and
  /// below its label and at its sides. Material's own has no vertical air
  /// and a fixed 40 dp minimum, so at text scale 2.0 its words touched the
  /// outline; the row adds the label's scaled line to this for its minimum.
  static const EdgeInsetsDirectional settingsButtonPadding =
      EdgeInsetsDirectional.symmetric(
        horizontal: rowEndPadding,
        vertical: settingsButtonVerticalPadding,
      );
  static const double settingsButtonVerticalPadding = 10;

  /// A settings tile's leading slot and the gap after it — the stock
  /// Material 3 tile's, a 24 dp glyph and 16 dp — held in the kit's
  /// `ListTileTheme`, so a row that measures its own text column
  /// (`SettingsYieldingTile`) starts its title where its neighbours do.
  static const double settingsLeadingWidth = 24;
  static const double settingsTitleGap = 16;

  /// The column a kit tile's title starts in, from the group's edge: a
  /// settings row that belongs to the row above it (a tradition's look row,
  /// its Multi-day fasts switch) carries no glyph of its own and starts its
  /// title here, under that row's title — with a glyph its text column was
  /// 144 dp at text scale 2.0 on a 360 dp phone, narrower than one German
  /// word. [subRowInset] is the form rows' column, four short of it.
  static const double settingsSubRowInset =
      RowMetrics.groupInset + settingsLeadingWidth + settingsTitleGap;

  /// Narrower than this beside its title — at text scale 1.0, scaled with
  /// the text — a settings value is a column of broken words and goes under
  /// the description instead: a fixed width squeezed the holiday set to
  /// "Chr…" in German at 2.0.
  static const double settingsValueMinBesideWidth = 96;

  /// Between a settings row's description and a value that went under it.
  static const double settingsValueUnderGap = 4;

  /// Breathing room on the height a value must fit beside its title: the
  /// text engine rounds a line's height, and a value a hair over the cap
  /// would be cut by that hair.
  static const double settingsValueCapTolerance = 0.5;

  /// A settings section folding open or shut: long enough to read as one
  /// motion, short enough that a fold never feels like waiting for the row
  /// you were reaching for.
  static const Duration settingsFoldDuration = Duration(milliseconds: 180);

  /// The held-back rows the Sync page lists before one "And n more" row: a
  /// screenful or two, enough to recognise what is stuck, never a list a
  /// rules change could grow into the hundreds.
  static const int syncHeldBackShown = 20;

  /// A held-back row's name lines: a long note title stays recognisable and
  /// the reason under it never goes below the fold of one row.
  static const int syncHeldBackTitleLines = 2;

  /// Around a settings page's search field above its list: the group's
  /// sides, air under the bar, and a short step down to the first header,
  /// whose own height is the rest of the gap.
  static const EdgeInsets settingsSearchPadding = EdgeInsets.fromLTRB(
    RowMetrics.groupInset,
    12,
    RowMetrics.groupInset,
    4,
  );
  static const double counterSize = 12;

  /// The colour dot before a row's value — what Icon & color reads back —
  /// at the browser's label dot, so a colour dot is one size on every row
  /// that shows one.
  static const double valueDotSize = RowMetrics.labelDotSize;
  static const double trailingIconSize = 20;
  static const double trailingButtonSize = 48;

  /// The drag handle's target at a reorderable row's start — the trailing
  /// button's size mirrored, so a row that can be lifted keeps its two other
  /// targets exactly where every other row has them. The text column after
  /// it is [dividerIndentGlyph]: the glyph rows' column, so the search row
  /// and the action row above and below line up with the names.
  static const double dragHandleSlot = trailingButtonSize;

  /// The handle's ≡ inside [dragHandleSlot]: Material's default icon size,
  /// a step above [trailingIconSize] so the grip reads as something to hold
  /// rather than one more button.
  static const double dragHandleGlyphSize = 24;

  /// The "clear the search to reorder" line under a reorderable list's search
  /// field: its lock glyph, the gap to the words and the air under them —
  /// a caption's scale, so the line reads as a note on the field above.
  static const double reorderHintGlyphSize = 14;
  static const double reorderHintGlyphGap = 6;
  static const double reorderHintBottomPadding = 8;

  /// A colour dot's painted circle (`ColorSwatchDot`), inside the trailing
  /// button's 48 dp target: 44, so the circles read as dots while a field of
  /// them still keeps Material's target floor.
  static const double swatchDiameter = 44;

  /// Between the strip's dots — the Look sheet's own number, hoisted (Tier 3,
  /// D13): 2, so eighteen colours fit three runs of a phone's width.
  static const double swatchSpacing = 2;

  /// Above and below the strip inside its row (`FormSwatchRow`): each target
  /// already carries 2 dp of air around its circle, so the row needs less
  /// above than a text row and a little more below, where the next hairline
  /// would otherwise sit on the last run's targets.
  static const double swatchRowTopPadding = 8;
  static const double swatchRowBottomPadding = 12;
  static const double subRowInset = RowMetrics.dividerIndentWithGlyph;
  static const double rowEndPadding = 12;
  static const double pairVerticalPadding = 6;
  static const double pairRunSpacing = 2;

  /// The lines a row's value may take before it ellipsizes — the value of a
  /// label · value pair, a description read back as a row. Two, so a long
  /// value still reads as a value and its row never turns into a paragraph.
  static const int valueMaxLines = 2;

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

  /// One line of the description sheet's status band as a multiple of
  /// `bodySmall`'s scaled font size — a hair over the 1.33 the style draws
  /// with, so the lines the band reserves (the subject, a two-line caption or
  /// over-limit message) hold their text with air rather than clipping a
  /// descender at 200 %.
  static const double statusLineFactor = 1.4;

  /// The lines the time pad's caption band holds at every text scale: "Endet
  /// um 19:30 · 1 Std. 30 Min." wraps once at 200 % on a 360 dp phone, and
  /// a one-line band cut it to "1 Std. 30 Mi…". Two, never more — the
  /// caption is one clause, and the band is sized from the style alone so
  /// nothing under it moves as the digits change.
  static const int timePadCaptionLines = 2;

  /// The lines a period navigation title may take — the Dates sheet's
  /// "September 2026" over its grid, which drops the year when ellipsized at
  /// one line at 200 %. Two, so the row stays a row and never a paragraph.
  static const int periodTitleMaxLines = 2;

  /// The period nav's tappable title: its ink reaches past the text by a
  /// chip's air on the left and hugs the drop-down glyph on the right, so
  /// the glyph sits against the today slot rather than floating.
  static const EdgeInsets periodNavTitlePadding = EdgeInsets.fromLTRB(
    8,
    2,
    2,
    2,
  );

  /// Around the nav's row: the chevrons' own 48 dp targets carry the air at
  /// the sides and above, so only a sliver separates the row from what it
  /// heads.
  static const EdgeInsets periodNavPadding = EdgeInsets.fromLTRB(4, 0, 4, 4);

  /// The nav's chevrons and Today glyph: Material's button glyph, larger than
  /// a row's trailing 20 because they are the row's only controls.
  static const double periodNavGlyphSize = 24;

  /// Either side of a mini month grid (`AgendaMonthGrid`, the overview's and
  /// the day list's Month mode): a sliver, so the seven columns keep nearly
  /// the whole width (Tier 3 D6).
  static const double miniGridSidePadding = 4;

  /// Under a mini grid's marker bars, lifting them off the cell's bottom
  /// edge.
  static const double miniGridMarkerGap = 4;

  /// A caption under a whole group rather than inside a row — the no-match
  /// line of a searchable list — set in like a section label above one.
  static const EdgeInsets groupCaptionPadding = EdgeInsets.fromLTRB(
    RowMetrics.sectionLabelInset,
    bodyTop,
    RowMetrics.sectionLabelInset,
    0,
  );

  static const double dividerIndentGlyph = RowMetrics.dividerIndentWithGlyph;
  static const double dividerIndentPlain = RowMetrics.dividerIndentPlain;
  static const double dividerIndentTitle = 70;

  /// `FormMeterRow`'s track: thin enough to read as a share under the text,
  /// not as a bar chart beside it, and unscaled, so large text grows only
  /// the lines that hold words.
  static const double meterHeight = 4;

  /// Between a meter row's caption and its track: the track belongs to the
  /// row's numbers, so it sits a little apart from the words above it.
  static const double meterGap = 6;

  /// The width of a meter's marker — a second share drawn upright across
  /// the track, last year's beside this one's: thin enough to read as a
  /// mark, never as a second bar.
  static const double meterMarkerWidth = 2;

  /// The `rowGroup` band on each side of the marker, so it stays apart from
  /// the fill it crosses (the marker against `primary` is 1.00:1 in dark).
  static const double meterMarkerRing = 1;

  /// How far the marker reaches past the track above and below: into
  /// [meterGap] and the row's padding, so the row's height never changes.
  static const double meterMarkerOverhang = 3;

  /// A chip's height while its label's line fits it, which is up to 160 %
  /// text; past that it is the chip's minimum and the chip grows with the
  /// line, so a label is never cut.
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

  /// The text scale a confirm dialog's title and its action labels stop
  /// growing at: past them a German or Romanian title, or a one-word label
  /// in a button, broke mid-word at 200 % (review D3-3). The body keeps the
  /// full scale and scrolls.
  static const double dialogTitleMaxTextScale = 1.2;
  static const double dialogActionMaxTextScale = 1.6;

  /// Between a progress dialog's line and its bar (the database import).
  static const double dialogProgressGap = 16;
  static const EdgeInsets menuPadding = EdgeInsets.symmetric(vertical: 6);

  /// Material's popup menu duration, so a menu on a route of the language's
  /// own opens and closes at the pace of every other menu.
  static const Duration menuTransition = Duration(milliseconds: 300);

  /// The step a label-sized menu's width rounds up to — the framework's
  /// `_kMenuWidthStep`, so a menu on a route of the language's own is as
  /// wide as its `showMenu` siblings.
  static const double menuWidthStep = 56;

  /// The largest text scale at which the heading menu's `#` marker is
  /// shown. Past it the marker's column squeezes the longest label (German
  /// "Überschrift 6" at 2.0) into mid-word breaks at the menu's 280 cap,
  /// and a decoration never costs a word (WCAG 1.4.4).
  static const double menuMarkerMaxScale = 1.3;

  /// A short choice menu's floor — the editor's Priority, the filter sheet's
  /// Repeat and Time of day: three to five glyph-and-word rows. Content grows
  /// it up to [menuMaxWidth].
  static const double menuWidth = 220;

  /// The widest a row's menu may grow past its own floor when a label needs
  /// it — the header menus' cap, shared: at 200 % "Wiederkehrend" does not
  /// fit 220 and broke mid-word on the device.
  static const double menuMaxWidth = AppTheme.menuMaxWidth;

  /// The scrubber's touch lane along a list's right edge: a 48 dp target a
  /// thumb finds without aiming at the 4 dp thumb itself.
  static const double scrubberLaneWidth = 48;

  /// The scrollbar's thumb under the lane — thin, it marks the place and the
  /// lane takes the touch.
  static const double scrubberThumbWidth = 4;

  /// The gap between the scrubber's bubble and its lane, so the finger in
  /// the lane never covers the label it is steering.
  static const double scrubberBubbleInset = 12;

  /// The bubble is a small floating surface, rounded like a menu.
  static const double scrubberBubbleRadius = menuRadius;
  static const EdgeInsets scrubberBubblePadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  /// The bubble leaves at the scrollbar's own pace; Flutter names no public
  /// constant for the scrollbar's fade, so the value is named here.
  static const Duration scrubberBubbleFade = Duration(milliseconds: 300);

  /// The Dates sheet's range summary — the span and its day count — on the
  /// sheet body's side inset.
  static const EdgeInsets rangeSummaryPadding = EdgeInsets.symmetric(
    horizontal: 16,
  );

  /// Under the Dates sheet's year tiles: the whole gap when a footer follows
  /// (several dates), else the gap over the bottom clearance.
  static const double yearViewBottomGap = 8;

  static const double disabledOpacity = 0.38;

  /// The spinner that stands in a settings row's leading glyph while its
  /// request runs: the glyph's box, so the row does not move.
  static const double rowBusyIndicatorSize = 24;
  static const double rowBusyIndicatorStroke = 2;

  /// A row whose own switch is off: still a control, so lighter than
  /// [disabledOpacity] — the Alerts hub's switched-off alert rows' 50 %.
  static const double switchedOffOpacity = 0.5;
}
