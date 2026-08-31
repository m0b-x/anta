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
/// Cheap to paint, like `CalendarDayBars`: plain `Container`s, no animations,
/// no `CustomPainter`, no `Opacity` (see [opacity]). It is **not** as cheap to
/// build — unlike `CalendarDayBars` it wraps its marks in a `LayoutBuilder`,
/// so with the rail on every visible cell defers a subtree build to layout.
/// Deliberate: capacity depends on a height the widget's three call sites
/// compute differently, and adapting is worth one layout-phase build for an
/// opt-in channel. If the rail ever becomes a default, thread the height down
/// from `_rowHeight` instead.
///
/// When [marks] outnumbers the slots that fit, the last slot becomes a neutral
/// overflow affordance — a half-height segment or a small hollow dot — and the
/// exact `+N` goes into the semantics label only. There is no room beside a
/// 3px rail for a number.
class CalendarDayRail extends StatelessWidget {
  final List<DayRailMark> marks;
  final DayRailStyle style;

  /// User cap from `calendarMaxDayRailMarks` (1-5). The rail additionally
  /// clamps against its measured height, so a short row can never overflow.
  final int maxMarks;

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
    this.opacity = 1.0,
  });

  /// Width of a [DayRailStyle.line] segment, and of the rail lane itself.
  static const double lineWidth = 3;
  static const double lineGap = 2;

  /// Below this a segment stops reading as a mark and becomes a smudge; it is
  /// what the height clamp counts slots against.
  static const double minLineSegment = 3;

  /// Diameter of a [DayRailStyle.dot] mark.
  static const double dotSize = 5;
  static const double dotGap = 3;

  /// Width of the rail lane for [style], so the cell can position it without
  /// knowing how either style paints.
  ///
  /// The lane's **left** edge is fixed at the same x whatever the style and
  /// whether or not the fasting stripe beside it is present — a rail that slid
  /// sideways across months would violate the stable-layout rule. Only the
  /// right edge differs, and only because a 5px circle cannot be drawn 3px
  /// wide (and a hollow missed dot needs 1px of that for its outline).
  static double railWidth(DayRailStyle style) => switch (style) {
    DayRailStyle.none => 0,
    DayRailStyle.line => lineWidth,
    DayRailStyle.dot => dotSize,
  };

  /// How many marks fit in [height] for [style].
  static int capacityFor(double height, DayRailStyle style) {
    final (size, gap) = switch (style) {
      DayRailStyle.none => (0.0, 0.0),
      DayRailStyle.line => (minLineSegment, lineGap),
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
    if (marks.isEmpty || style == DayRailStyle.none || maxMarks <= 0) {
      return const SizedBox.shrink();
    }

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
    // user's cap is only ever an upper bound — a short row wins.
    final capacity = capacityFor(height, style);
    final slots = maxMarks < capacity ? maxMarks : capacity;
    if (slots <= 0) return const SizedBox.shrink();

    // The overflow affordance takes the last slot, exactly as the "+N"
    // chip does in the marker strip — except when that is the *only*
    // slot. The marker strip's chip can afford to stand alone because it
    // draws a number; the rail's cannot (a 3px lane has nowhere to put
    // one), so at one slot a neutral blob would replace the day's top
    // commitment with strictly less information than it carried. The
    // count is not lost either way: it rides the semantics label.
    final visibleCount = marks.length <= slots
        ? marks.length
        : (slots == 1 ? 1 : slots - 1);
    final hiddenCount = marks.length - visibleCount;
    final hasOverflow = hiddenCount > 0 && slots > 1;

    // One merged node for the whole rail, never one per mark: a 3px
    // sliver is not a useful focus target, and a day already contributes
    // a second marker node for the bottom strip. Missed state rides the
    // mark's own label (`"<title>, missed"`), so colour is never the only
    // carrier.
    final label = [
      for (var i = 0; i < visibleCount; i++) marks[i].semanticLabel,
      if (hiddenCount > 0) '+$hiddenCount',
    ].join(', ');

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
            neutral: neutral,
            outlineFor: outlineFor,
          );

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: strip),
    );
  }

  Widget _lines({
    required int visibleCount,
    required bool hasOverflow,
    required Color neutral,
    required Border? Function(Color) outlineFor,
  }) {
    final slots = visibleCount + (hasOverflow ? 1 : 0);
    final segment = (height - (slots - 1) * lineGap) / slots;
    final radius = BorderRadius.circular(lineWidth / 2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleCount; i++) ...[
          if (i > 0) const SizedBox(height: lineGap),
          SizedBox(
            height: segment,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _paint(marks[i].color, missed: marks[i].missed),
                borderRadius: radius,
                border: outlineFor(marks[i].color),
              ),
            ),
          ),
        ],
        if (hasOverflow) ...[
          // `hasOverflow` implies more than one slot, so visibleCount is at
          // least 1 and the gap is unconditional — unlike the marker strip,
          // where `maxBars - 1` can genuinely be zero.
          const SizedBox(height: lineGap),
          SizedBox(
            height: segment,
            child: Center(
              child: SizedBox(
                // Explicit width, not the Column's stretch: `Center` hands
                // down *loose* constraints, and a childless `DecoratedBox`
                // takes `constraints.smallest` — so without this the
                // affordance lays out 3px tall and 0px wide, i.e. invisible.
                width: lineWidth,
                height: segment / 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: neutral,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
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
