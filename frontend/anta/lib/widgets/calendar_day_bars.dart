import 'package:flutter/material.dart';

import '../models/calendar_appearance.dart';
import '../models/day_bar.dart';

/// Renders the per-day event markers inside a calendar day cell, either as a
/// vertical stack of thin colored bars or as a centered row of colored dots
/// (selected by [style]).
///
/// Designed to be cheap: plain `Container`s with no animations. Use through
/// `TableCalendar.calendarBuilders.markerBuilder`.
///
/// When [bars] contains more than [maxBars] entries, the first
/// `maxBars - 1` markers are rendered followed by a compact "+N" overflow
/// indicator that takes the slot of the last marker. The widget never grows
/// beyond [maxBars] visual slots so calendar cells keep a stable height.
class CalendarDayBars extends StatelessWidget {
  final List<DayBar> bars;
  final int maxBars;
  final CalendarMarkerStyle style;
  final double barHeight;
  final double spacing;
  final double horizontalInset;

  const CalendarDayBars({
    super.key,
    required this.bars,
    this.maxBars = 3,
    this.style = CalendarMarkerStyle.bars,
    this.barHeight = 3,
    this.spacing = 1.5,
    this.horizontalInset = 6,
  });

  /// Diameter of a single dot in [CalendarMarkerStyle.dots] mode.
  static const double dotSize = 5;

  /// Height of the marker strip for [maxBars] markers in the given [style],
  /// used by the calendar page to compute a collision-free row height. The
  /// "+N" overflow chip (9px text) is taller than a dot/bar, so both styles
  /// reserve room for it.
  static double stripHeight(int maxBars, CalendarMarkerStyle style) {
    if (maxBars <= 0) return 0;
    return switch (style) {
      CalendarMarkerStyle.bars => maxBars * 3 + (maxBars - 1) * 1.5 + 4,
      CalendarMarkerStyle.dots => 9,
    };
  }

  /// Below this luminance delta against the cell surface, a marker gets a
  /// hairline outline so pale / low-contrast colors stay visible.
  static const double _lowContrastThreshold = 0.22;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || maxBars <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final hasOverflow = bars.length > maxBars;
    // Reserve the last slot for the "+N" indicator when overflowing.
    final visibleCount = hasOverflow ? maxBars - 1 : bars.length;
    final hiddenCount = hasOverflow ? bars.length - visibleCount : 0;
    // Reference luminance of the calendar cell background, used to outline
    // markers whose color is too close to it (e.g. a pale custom color).
    final surfaceLum = theme.colorScheme.surface.computeLuminance();
    final outlineColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    Border? outlineFor(Color color) {
      return (color.computeLuminance() - surfaceLum).abs() <
              _lowContrastThreshold
          ? Border.all(color: outlineColor, width: 0.5)
          : null;
    }

    if (style == CalendarMarkerStyle.dots) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Semantics(
              label: bars[i].semanticLabel,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: bars[i].color,
                  shape: BoxShape.circle,
                  border: outlineFor(bars[i].color),
                ),
              ),
            ),
          ],
          if (hasOverflow) ...[
            if (visibleCount > 0) const SizedBox(width: 3),
            _OverflowChip(
              count: hiddenCount,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visibleCount; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            Semantics(
              label: bars[i].semanticLabel,
              child: Container(
                height: barHeight,
                decoration: BoxDecoration(
                  color: bars[i].color,
                  borderRadius: BorderRadius.circular(barHeight),
                  border: outlineFor(bars[i].color),
                ),
              ),
            ),
          ],
          if (hasOverflow) ...[
            if (visibleCount > 0) SizedBox(height: spacing),
            _OverflowChip(
              count: hiddenCount,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _OverflowChip extends StatelessWidget {
  final int count;
  final Color color;

  const _OverflowChip({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      '+$count',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        height: 1.0,
        color: color,
      ),
    );
  }
}
