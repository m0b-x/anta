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
  static const EdgeInsets menuPadding = EdgeInsets.symmetric(vertical: 6);

  /// A short choice menu's floor — the editor's Priority, the filter sheet's
  /// Repeat and Time of day: three to five glyph-and-word rows. Content grows
  /// it up to [menuMaxWidth].
  static const double menuWidth = 220;

  /// The widest a row's menu may grow past its own floor when a label needs
  /// it — the header menus' cap, shared: at 200 % "Wiederkehrend" does not
  /// fit 220 and broke mid-word on the device.
  static const double menuMaxWidth = AppTheme.menuMaxWidth;

  static const double disabledOpacity = 0.38;
}
