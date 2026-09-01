import 'package:flutter/material.dart';

import '../constants/calendar_colors.dart';
import '../models/calendar_appearance.dart';
import '../models/day_rail_mark.dart';
import '../utils/marker_contrast.dart';

/// Vertical rail painted along the left edge of a calendar day cell — the
/// calendar's **multi-source** presence channel.
///
/// The cell wash (`CellTintResolver`) picks exactly one event per day on
/// purpose, so a day carrying three tracked commitments reads as one. The rail
/// carries one mark per commitment, and each mark says whether it was kept.
///
/// [DayRailStyle.line] renders as **one unbroken bar**, not a stack of
/// separated slivers: the marks are colour bands butted against each other,
/// with only the lane's two outer ends rounded. It shares its lane with the
/// tint runner-up ([baseColor]) — see that field — so a fasting day carrying
/// commitments shows one object at the cell's edge instead of two competing
/// ones inside it. [DayRailStyle.dot] keeps its own inset lane and its gaps;
/// discrete pips are what that style *is*.
///
/// Cheap to paint, like `CalendarDayBars`: plain `Container`s, no animations,
/// no `CustomPainter`, no `Opacity` (see [opacity]), and — since the bands
/// carry their own corner radii — no `ClipRRect` layer to round the lane's
/// ends. Capacity comes from [height] rather than a `LayoutBuilder`, so the
/// widget builds in the ordinary build phase.
///
/// When [marks] outnumbers the slots that fit, the last slot becomes a neutral
/// overflow band and the exact `+N` goes into the semantics label only. There
/// is no room beside a 3px rail for a number.
class CalendarDayRail extends StatelessWidget {
  final List<DayRailMark> marks;
  final DayRailStyle style;

  /// User cap from `calendarMaxDayRailMarks` (1-5). The rail additionally
  /// clamps against its measured height, so a short row can never overflow.
  final int maxMarks;

  /// The tint runner-up's colour — the fasting stripe under the `both`
  /// conflict setting — drawn as a fixed band at the **bottom** of the lane,
  /// below every mark. `null` when the day has no runner-up tint, or when the
  /// cell draws the stripe itself ([DayRailStyle.dot], which keeps its own
  /// inset lane).
  ///
  /// A base band rather than a slot: a fast is a condition the whole day sits
  /// on, not a commitment competing for the cap, so it must never displace a
  /// mark.
  ///
  /// Arrives **unfaded**, like [DayRailMark.color] — [opacity] fades the whole
  /// lane uniformly, and folding the outside-month alpha in here would fade it
  /// twice.
  final Color? baseColor;

  /// Which end of the lane [baseColor] takes. Ignored when there is no base,
  /// and in [DayRailStyle.dot], which has no band to place.
  final DayRailBasePosition basePosition;

  /// Alpha multiplier applied to every painted colour, used by the grid to
  /// fade the rail of days belonging to an adjacent month.
  ///
  /// A parameter rather than an `Opacity` wrapper, for the same reason
  /// `CalendarDayBars` takes one: `Opacity` allocates an offscreen
  /// compositing layer per outside day, and this is only ever a colour
  /// change. Multiplies rather than sets.
  final double opacity;

  /// The lane's height, supplied by the caller rather than measured.
  ///
  /// `CalendarDayCell` positions the rail with an explicit height, so the box
  /// this widget lands in is already known one layer up — measuring it back
  /// with a `LayoutBuilder` would put a deferred subtree build on every
  /// visible cell of a grid tuned over five perf phases, to learn a number the
  /// caller computed.
  final double height;

  const CalendarDayRail({
    super.key,
    required this.marks,
    required this.style,
    required this.maxMarks,
    required this.height,
    this.baseColor,
    this.basePosition = DayRailBasePosition.bottom,
    this.opacity = 1.0,
  });

  /// Width of a [DayRailStyle.line] lane.
  ///
  /// Equal to the tint edge stripe's width on purpose: the line rail *is* that
  /// stripe's lane, so the two can only read as one object if they are the
  /// same width. Change one and change the other.
  static const double lineWidth = 3;

  /// Below this a band stops reading as a mark and becomes a smudge; it is
  /// what the height clamp counts slots against.
  static const double minLineSegment = 3;

  /// The share of the lane [baseColor] takes when marks share it — an **equal
  /// half**.
  ///
  /// The two are one question each: "is this a fasting day" and "what is on
  /// it". Neither is a sub-answer of the other, so neither gets the smaller
  /// half. Hierarchy is carried by *weight*, not area: the band paints at
  /// `CalendarColors.cellEdgeAlpha` (0.55) against marks at full alpha, so the
  /// commitments still read first at equal size — which is why the equal split
  /// does not flatten the two into one undifferentiated bar.
  ///
  /// With no marks at all the band takes the whole lane, and the result is
  /// pixel-identical to the stripe the cell used to draw.
  static const double baseShare = 0.5;

  /// Diameter of a [DayRailStyle.dot] mark.
  static const double dotSize = 5;
  static const double dotGap = 3;

  /// Width of the rail lane for [style], so the cell can position it without
  /// knowing how either style paints.
  ///
  /// The lane's **left** edge is fixed at the same x whatever the day carries —
  /// a rail that slid sideways across months would violate the stable-layout
  /// rule. The two styles differ because a 5px circle cannot be drawn 3px wide
  /// (and a hollow missed dot needs 1px of that for its outline), which is also
  /// why only `line` can share the edge stripe's lane.
  static double railWidth(DayRailStyle style) => switch (style) {
    DayRailStyle.none => 0,
    DayRailStyle.line => lineWidth,
    DayRailStyle.dot => dotSize,
  };

  /// How tall the [baseColor] band is in a lane of [height] that also carries
  /// marks — half of it, by [baseShare].
  static double baseBandFor(double height) => height * baseShare;

  /// How many marks fit in [height] for [style].
  ///
  /// `line` counts against no gap — its bands touch — so a lane sized for the
  /// user's cap is never the binding constraint; the clamp exists for short
  /// rows, where it still is.
  static int capacityFor(double height, DayRailStyle style) {
    final (size, gap) = switch (style) {
      DayRailStyle.none => (0.0, 0.0),
      DayRailStyle.line => (minLineSegment, 0.0),
      DayRailStyle.dot => (dotSize, dotGap),
    };
    if (size <= 0) return 0;
    final slots = ((height + gap) / (size + gap)).floor();
    return slots < 0 ? 0 : slots;
  }

  Color _paint(Color color, {bool missed = false}) {
    final factor = opacity * (missed ? CalendarColors.missedEventAlpha : 1.0);
    return factor == 1.0 ? color : color.withValues(alpha: color.a * factor);
  }

  @override
  Widget build(BuildContext context) {
    if (style == DayRailStyle.none) return const SizedBox.shrink();
    // The dot lane is the cell's inset one and never carries the stripe, so a
    // base colour handed to it is dropped rather than drawn in the wrong place.
    final base = style == DayRailStyle.line ? baseColor : null;
    final hasMarks = marks.isNotEmpty && maxMarks > 0;
    if (!hasMarks && base == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final surfaceLum = MarkerContrast.luminanceOf(theme.colorScheme.surface);
    final outlineColor = _paint(
      theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );
    final neutral = _paint(theme.colorScheme.onSurfaceVariant);

    Border? outlineFor(Color color) => MarkerContrast.outlineFor(
      color,
      surfaceLuminance: surfaceLum,
      outlineColor: outlineColor,
    );

    // The row height is a page-level computation the rail has no say in
    // (`_rowHeight` sizes for the chip zone and the bottom strip), so the
    // user's cap is only ever an upper bound — a short row wins. The base band
    // is subtracted first: it is not a slot, so it must not be able to take one
    // and it must not lend the marks the room it occupies.
    final baseHeight = base == null
        ? 0.0
        : (hasMarks ? baseBandFor(height) : height);
    final capacity = hasMarks ? capacityFor(height - baseHeight, style) : 0;
    final slots = maxMarks < capacity ? maxMarks : capacity;

    // The overflow affordance takes the last slot, exactly as the "+N"
    // chip does in the marker strip — except when that is the *only*
    // slot. The marker strip's chip can afford to stand alone because it
    // draws a number; the rail's cannot (a 3px lane has nowhere to put
    // one), so at one slot a neutral blob would replace the day's top
    // commitment with strictly less information than it carried. The
    // count is not lost either way: it rides the semantics label.
    final visibleCount = slots <= 0
        ? 0
        : (marks.length <= slots
              ? marks.length
              : (slots == 1 ? 1 : slots - 1));
    final hiddenCount = visibleCount == 0 ? 0 : marks.length - visibleCount;
    final hasOverflow = hiddenCount > 0 && slots > 1;

    final strip = style == DayRailStyle.dot
        ? _dots(
            visibleCount: visibleCount,
            hasOverflow: hasOverflow,
            neutral: neutral,
            outlineFor: outlineFor,
          )
        : _lines(
            visibleCount: visibleCount,
            hasOverflow: hasOverflow,
            baseHeight: baseHeight,
            base: base,
            neutral: neutral,
            outlineFor: outlineFor,
          );

    // A lane carrying only the base band is the tint edge stripe wearing a
    // different widget: it is decoration for a wash the day panel already
    // spells out, and it never had a semantics node. Only marks earn one.
    if (visibleCount == 0) return ExcludeSemantics(child: strip);

    // One merged node for the whole rail, never one per mark: a 3px
    // sliver is not a useful focus target, and a day already contributes
    // a second marker node for the bottom strip. Missed state rides the
    // mark's own label (`"<title>, missed"`), so colour is never the only
    // carrier.
    final label = [
      for (var i = 0; i < visibleCount; i++) marks[i].semanticLabel,
      if (hiddenCount > 0) '+$hiddenCount',
    ].join(', ');

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: strip),
    );
  }

  /// One unbroken bar: every band is flush against its neighbour and only the
  /// lane's outer ends are rounded.
  ///
  /// The radii live on the end bands rather than on a `ClipRRect` around the
  /// column, so rounding the lane costs no clip layer on a 42-cell path. For
  /// the same reason a low-contrast band outlines the **whole lane** through
  /// one foreground decoration instead of itself: a per-band border would draw
  /// a horizontal hairline at every boundary, which is exactly the "several
  /// separate lines" look the single bar exists to avoid.
  Widget _lines({
    required int visibleCount,
    required bool hasOverflow,
    required double baseHeight,
    required Color? base,
    required Color neutral,
    required Border? Function(Color) outlineFor,
  }) {
    final markSlots = visibleCount + (hasOverflow ? 1 : 0);
    final segment = markSlots == 0 ? 0.0 : (height - baseHeight) / markSlots;
    final bandCount = markSlots + (baseHeight > 0 ? 1 : 0);
    final end = Radius.circular(lineWidth / 2);

    Border? outline;
    final bands = <Widget>[];
    void band(Color color, double bandHeight, {Border? Function()? contrast}) {
      final index = bands.length;
      outline ??= contrast?.call();
      bands.add(
        SizedBox(
          height: bandHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.vertical(
                top: index == 0 ? end : Radius.zero,
                bottom: index == bandCount - 1 ? end : Radius.zero,
              ),
            ),
          ),
        ),
      );
    }

    void baseBand() {
      if (base != null) band(_paint(base), baseHeight);
    }

    if (basePosition == DayRailBasePosition.top) baseBand();
    for (var i = 0; i < visibleCount; i++) {
      final mark = marks[i];
      band(
        _paint(mark.color, missed: mark.missed),
        segment,
        contrast: () => outlineFor(mark.color),
      );
    }
    if (hasOverflow) {
      // Neutral *and* stepped back to the same weight the base band carries,
      // so the lane has exactly two levels of emphasis: marks at full alpha,
      // everything that is context behind them at `cellEdgeAlpha`. It also has
      // to stay distinguishable from a real mark in a muted category, and it
      // no longer has the half-height cue the separated slivers gave it.
      band(
        neutral.withValues(alpha: neutral.a * CalendarColors.cellEdgeAlpha),
        segment,
      );
    }
    // The marks keep their priority order within their own half whichever end
    // the base takes — only the split moves, never the ranking.
    if (basePosition == DayRailBasePosition.bottom) baseBand();

    final Widget lane = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: bands,
    );
    if (outline == null) return lane;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: outline,
        borderRadius: BorderRadius.circular(lineWidth / 2),
      ),
      child: lane,
    );
  }

  Widget _dots({
    required int visibleCount,
    required bool hasOverflow,
    required Color neutral,
    required Border? Function(Color) outlineFor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < visibleCount; i++) ...[
          if (i > 0) const SizedBox(height: dotGap),
          _dot(marks[i], outlineFor),
        ],
        if (hasOverflow) ...[
          const SizedBox(height: dotGap),
          SizedBox(
            width: dotSize - 2,
            height: dotSize - 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: neutral, width: 1),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// A missed dot is drawn **hollow** — the one style with room for a
  /// non-colour cue that a commitment was not kept.
  ///
  /// Hollow *instead of* faded, not as well as (D6 asked for both). A 1px
  /// ring already carries roughly a fifth of a filled 5px disc's ink, and
  /// stacking `missedEventAlpha` on top of it multiplies: on an adjacent-month
  /// day the two fades compound to 0.35 x 0.35 = 0.12 alpha on a hairline,
  /// which does not read as dimmed, it disappears. One strong cue per style is
  /// the rule — `line`, which has no shape to spare, keeps the alpha fade
  /// instead. Missed state is on the semantics label either way, so colour is
  /// never the only carrier.
  Widget _dot(DayRailMark mark, Border? Function(Color) outlineFor) {
    final color = _paint(mark.color);
    return SizedBox(
      width: dotSize,
      height: dotSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mark.missed ? null : color,
          shape: BoxShape.circle,
          border: mark.missed
              ? Border.all(color: color, width: 1)
              : outlineFor(mark.color),
        ),
      ),
    );
  }
}
