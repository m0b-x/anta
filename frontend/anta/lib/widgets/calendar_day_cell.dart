import 'package:flutter/material.dart';

import '../models/calendar_appearance.dart';
import '../models/day_cell_tint.dart';
import '../models/day_rail_mark.dart';
import 'calendar_day_rail.dart';

/// Day-number cell for the calendar grid.
///
/// The number sits in a fixed-size chip anchored to the **top** of the cell,
/// leaving the bottom strip exclusively to the day markers (bars/dots), so
/// the today/selected highlight can never collide with event markers.
///
/// Also used by the calendar settings page to render a live preview of the
/// current appearance options.
class CalendarDayCell extends StatelessWidget {
  /// Diameter of the day-number chip.
  static const double chipSize = 34;

  /// Diameter of that chip while the **inset** (`dot`) rail lane is on.
  ///
  /// The gutter that lane needs does not exist at phone widths: on a 360dp
  /// screen the cell is 51.43 wide, so a 34px chip `Align(topCenter)`-centred
  /// puts the circle's leftmost point at x = 8.71 — and the `dot` lane runs to
  /// x = 10. Rather than move the day number (which the whole grid, and the
  /// weekday header above it, align to) the *decoration* yields: 4px off the
  /// diameter buys 2px of clearance on each side. Below ~340dp the lane still
  /// overlaps; nothing that keeps a legible chip fixes that, and it is one or
  /// two cells per screen.
  ///
  /// `line` does **not** pay this any more. It shares the tint edge stripe's
  /// lane, which ends at 4.5 — clear of a full-size chip at every width the
  /// grid supports — so the rail's most-used style no longer costs the day
  /// number 4px.
  ///
  /// Applied per *style*, never per cell — a chip that shrank only on days
  /// carrying marks would make today's circle a different size from
  /// yesterday's.
  static const double railChipSize = 30;

  static double chipDiameterFor(DayRailStyle railStyle) =>
      railStyle == DayRailStyle.dot ? railChipSize : chipSize;

  /// Vertical space reserved above the marker strip: top inset + chip + gap.
  ///
  /// Deliberately **not** a function of [chipDiameterFor]: a smaller chip is
  /// re-centred inside the same zone, so enabling the rail cannot change the
  /// row height and resize the whole grid.
  static const double chipZoneHeight = 4 + chipSize + 2;

  /// Rail height in a default row — a 62px row less the 4px top inset and the
  /// 20px a three-bar marker strip takes. Only a fallback: both call sites
  /// that actually draw a rail compute it from the row they are building.
  static const double defaultRailHeight = 38;

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool isOutside;
  final bool isWeekend;
  final CalendarTodayStyle todayStyle;
  final bool highlightWeekends;

  /// Effective highlight accent (theme primary or the user's custom color).
  final Color accent;

  /// Background decoration, already resolved by `CellTintResolver` — the cell
  /// stays a dumb painter and never learns which source won, what a fasting
  /// tradition is, or how priority maps to strength. Both colours arrive with
  /// their alpha applied.
  final DayCellTint tint;

  /// Recolours and bolds the day number for a fasting tradition using the
  /// "strong" display style. Not a tint layer — the number is the cell's own
  /// job — so it stays a separate parameter.
  final Color? fastingNumberColor;

  /// Marks for the left-edge rail, already resolved by `DayRailResolver`.
  ///
  /// Still a separate *channel* from [tint] — the tint edge stripe means "a
  /// second tint source applies here and lost the wash", a rail mark means
  /// "this commitment is on this day, and here is whether you kept it" — but
  /// since 2026-09-01 the two share one **lane** in `line` style: the marks
  /// take half of it and the stripe the other half
  /// ([CalendarDayRail.baseColor], placed by [railBasePosition]). Attribution
  /// survives because the bands are never blended and the split never moves
  /// without the user asking; what goes away is the second vertical line the
  /// cell used to grow inside itself, which is what made the rail read as
  /// clutter.
  final List<DayRailMark> railMarks;
  final DayRailStyle railStyle;
  final int maxRailMarks;

  /// Which end of the `line` lane the tint runner-up's band takes. The two
  /// halves stay equal either way; this only moves the split.
  final DayRailBasePosition railBasePosition;

  /// The rail lane's height, from [railLaneHeight].
  ///
  /// Supplied rather than measured: the rail would otherwise need a
  /// `LayoutBuilder` per visible cell to learn a number the grid already
  /// computed. It differs per style, which is why callers go through
  /// [railLaneHeight] rather than subtracting by hand.
  ///
  /// `null` means "this cell draws no rail", which is what the date picker —
  /// the one call site that passes no [railMarks] — leaves it at. Drawing a
  /// lane without a height is a caller bug: capacity would quietly fall back
  /// to [defaultRailHeight], so an assert catches it in debug rather than
  /// letting a wrong mark count ship. Trading the `LayoutBuilder` away means
  /// nothing self-corrects here any more.
  final double? railHeight;

  const CalendarDayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isOutside,
    required this.isWeekend,
    required this.todayStyle,
    required this.highlightWeekends,
    required this.accent,
    this.tint = DayCellTint.empty,
    this.fastingNumberColor,
    this.railMarks = const [],
    this.railStyle = DayRailStyle.none,
    this.maxRailMarks = 3,
    this.railBasePosition = DayRailBasePosition.bottom,
    this.railHeight,
  });

  /// Alpha multiplier for a day belonging to an adjacent month. Shared with
  /// the marker strip so the cell and its bars fade by the same amount.
  static const double outsideAlpha = 0.35;

  /// Left inset of the **inset** (`dot`) rail lane, measured from the cell
  /// edge — the lane that sits beside the edge stripe rather than in it.
  ///
  /// Fixed whether or not the stripe is present: a lane that slid left when
  /// the stripe is absent would shift under the user across months.
  static const double railLeft = 5;

  /// The cell's edge lane: left inset, width, and the inset at each end.
  ///
  /// This is where the tint runner-up's stripe has always been drawn —
  /// `left: 0, top: 4, bottom: 4, width: 3` inside the tinted container's
  /// 1.5px margin — expressed in *cell* coordinates so the `line` rail can be
  /// positioned there by the outer `Stack`, which has no margin. The two must
  /// agree to the pixel or the lane splits in half the moment a fasting day
  /// also carries marks.
  ///
  /// It clears the bottom marker strip horizontally (the strip insets
  /// `CalendarDayBars.defaultHorizontalInset` = 6, this lane ends at 4.5), so
  /// unlike the inset lane it runs the cell's full height.
  static const double edgeLaneLeft = 1.5;
  static const double edgeLaneWidth = CalendarDayRail.lineWidth;
  static const double edgeLaneInset = 5.5;

  /// The lane height [railStyle] gets inside a row of [rowHeight] whose bottom
  /// marker strip is [stripHeight] tall.
  ///
  /// One helper for both call sites (the grid and the settings preview)
  /// because the two must not drift — the preview's whole job is to be the
  /// grid — and because the answer is no longer one subtraction:
  ///
  /// - `line` lives in the edge lane, which the strip never reaches, so it
  ///   takes the whole row less [edgeLaneInset] at each end.
  /// - `dot` lives in the inset lane, which the strip *does* reach. The strip
  ///   is a sibling subtree painted after the cell, so it wins wherever they
  ///   meet; without this reservation it paints straight over the lane's
  ///   bottom dots.
  static double railLaneHeight({
    required double rowHeight,
    required double stripHeight,
    required DayRailStyle railStyle,
  }) => railStyle == DayRailStyle.line
      ? rowHeight - edgeLaneInset * 2
      : rowHeight - 8 - stripHeight;

  /// Text color that stays legible on top of [accent], whatever the user
  /// picked (the accent is customizable, so `onPrimary` is not enough).
  ///
  /// Reads the **un-faded** [accent] on purpose: this is a brightness
  /// estimate, and fading first pushes a mid-tone accent across the threshold
  /// and inverts an outside day's number from white to black87.
  Color get _onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
      ? Colors.white
      : Colors.black87;

  /// Applies the outside-month fade to one colour.
  ///
  /// Replaces an `Opacity` wrapper around the whole cell. `Opacity` allocates
  /// an offscreen compositing layer per outside day — 22-26 of them per page
  /// paint across the grid and the marker strip — for what is only ever a
  /// colour change. Multiplies rather than sets, because [tint]'s colours
  /// already arrive with their own alpha applied.
  Color _fade(Color color) =>
      isOutside ? color.withValues(alpha: color.a * outsideAlpha) : color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filledToday =
        isToday && !isSelected && todayStyle == CalendarTodayStyle.filled;
    final strongFasting = fastingNumberColor != null;
    Color numberColor;
    if (isSelected || filledToday) {
      numberColor = _onAccent;
    } else if (isToday) {
      numberColor = accent;
    } else if (strongFasting) {
      numberColor = fastingNumberColor!;
    } else if (highlightWeekends && isWeekend) {
      numberColor = colorScheme.error.withValues(alpha: 0.85);
    } else {
      numberColor = colorScheme.onSurface;
    }
    // The number sits *on top of* the chip, so fading the two independently
    // destroys the contrast between them — the digit washes out against its
    // own background. That only happens where the chip is opaque; everywhere
    // else the chip paints on transparency, where per-colour alpha and
    // `Opacity` are exactly equivalent. So this one branch keeps the composite
    // fade, at a cost of at most two layers per grid (an outside day can be
    // today or selected, not twenty-six of them).
    final onOpaqueChip = isSelected || filledToday;
    final fadeComposite = isOutside && onOpaqueChip;
    if (!onOpaqueChip) numberColor = _fade(numberColor);
    final chipAccent = fadeComposite ? accent : _fade(accent);

    final numberStyle = theme.textTheme.bodyMedium!.copyWith(
      color: numberColor,
      fontWeight: isToday || isSelected || strongFasting
          ? FontWeight.w700
          : FontWeight.w500,
      height: 1.0,
    );

    final diameter = chipDiameterFor(railStyle);

    Widget chip;
    if (isSelected && isToday) {
      // Filled selection core plus a detached ring: "selected, and it is
      // today" reads at a glance without a second color.
      chip = Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: chipAccent, width: 1.6),
        ),
        alignment: Alignment.center,
        child: Container(
          width: diameter - 7,
          height: diameter - 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: chipAccent),
          alignment: Alignment.center,
          child: Text('${day.day}', style: numberStyle),
        ),
      );
    } else {
      final decoration = isSelected
          ? BoxDecoration(shape: BoxShape.circle, color: chipAccent)
          : isToday
          ? switch (todayStyle) {
              CalendarTodayStyle.tonal => BoxDecoration(
                shape: BoxShape.circle,
                color: _fade(accent.withValues(alpha: 0.16)),
              ),
              CalendarTodayStyle.ring => BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: chipAccent, width: 1.6),
              ),
              CalendarTodayStyle.filled => BoxDecoration(
                shape: BoxShape.circle,
                color: chipAccent,
              ),
            }
          : null;
      chip = Container(
        width: diameter,
        height: diameter,
        decoration: decoration,
        alignment: Alignment.center,
        child: Text('${day.day}', style: numberStyle),
      );
    }

    if (fadeComposite) {
      chip = Opacity(opacity: outsideAlpha, child: chip);
    }

    Widget cell = Align(
      alignment: Alignment.topCenter,
      child: Padding(
        // The rail's smaller chip is re-centred in the zone the full-size one
        // occupies, so turning the rail on shrinks the circle without moving
        // the digit inside it. With the rail off this is exactly `top: 4`.
        padding: EdgeInsets.only(top: 4 + (chipSize - diameter) / 2),
        child: chip,
      ),
    );
    final rawWash = tint.wash;
    final rawEdge = tint.edge;
    final wash = rawWash == null ? null : _fade(rawWash);
    // In `line` style the runner-up's stripe stops being a stripe of its own
    // and becomes the bottom band of the shared edge lane. It goes to the rail
    // **unfaded**: the lane fades once, uniformly, through the rail's
    // `opacity`, and fading here as well would dim the band twice on an
    // adjacent-month day.
    final laneBase = railStyle == DayRailStyle.line ? rawEdge : null;
    final edge = (rawEdge == null || laneBase != null)
        ? null
        : _fade(rawEdge);
    if (wash != null || edge != null) {
      cell = Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: BorderRadius.circular(10),
        ),
        // A non-uniform `Border` cannot carry a `borderRadius`, so the
        // runner-up's stripe is stacked rather than drawn as a side.
        child: edge == null
            ? cell
            : Stack(
                children: [
                  cell,
                  Positioned(
                    left: 0,
                    top: 4,
                    bottom: 4,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: edge,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }
    // The rail cannot join the tint `Stack` above — that one only exists when
    // the day is tinted, and in `line` style the lane has to be positioned in
    // cell coordinates rather than inside that container's margin — so it
    // wraps whatever the cell turned out to be. An untinted day with no marks
    // stays the single bare `Align` it has always been.
    final drawsLane =
        railStyle != DayRailStyle.none &&
        (railMarks.isNotEmpty || laneBase != null);
    if (!drawsLane) return cell;
    assert(
      railHeight != null,
      'CalendarDayCell drew a rail lane with no railHeight. The rail sizes '
      'itself from this number instead of measuring, so it would silently fall '
      'back to defaultRailHeight and show the wrong number of marks. Use '
      'CalendarDayCell.railLaneHeight.',
    );
    final laneHeight = railHeight ?? defaultRailHeight;
    final inEdgeLane = railStyle == DayRailStyle.line;
    return Stack(
      children: [
        cell,
        Positioned(
          left: inEdgeLane ? edgeLaneLeft : railLeft,
          top: inEdgeLane ? edgeLaneInset : 4,
          height: laneHeight,
          width: inEdgeLane
              ? edgeLaneWidth
              : CalendarDayRail.railWidth(railStyle),
          child: CalendarDayRail(
            marks: railMarks,
            style: railStyle,
            maxMarks: maxRailMarks,
            height: laneHeight,
            baseColor: laneBase,
            basePosition: railBasePosition,
            opacity: isOutside ? outsideAlpha : 1.0,
          ),
        ),
      ],
    );
  }
}
