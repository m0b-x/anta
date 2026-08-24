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

  /// Alpha multiplier applied to every painted colour, used by the grid to
  /// fade the markers of days belonging to an adjacent month.
  ///
  /// A parameter rather than an `Opacity` wrapper at the call site: `Opacity`
  /// allocates an offscreen compositing layer per outside day, and this is
  /// only ever a colour change. Multiplies rather than sets, so a marker
  /// colour that already carries alpha keeps its relative weight.
  final double opacity;

  const CalendarDayBars({
    super.key,
    required this.bars,
    this.maxBars = 3,
    this.style = CalendarMarkerStyle.bars,
    this.barHeight = 3,
    this.spacing = 1.5,
    this.horizontalInset = 6,
    this.opacity = 1.0,
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

  /// Minimum contrast **ratio** between a marker and the cell surface before
  /// it gets a hairline outline so it stays visible.
  ///
  /// A ratio — `(L+0.05)/(L'+0.05)` — and deliberately not the raw luminance
  /// *delta* this replaced (2026-08-23). A delta means opposite things at the
  /// two ends of the scale: against white (lum 0.948) a gap of 0.09 is an
  /// invisible 1.05:1, while against a dark surface (lum 0.007) the same gap
  /// is a perfectly readable 2.06:1. Tuned on white, the old 0.22 delta
  /// therefore outlined **six of the twelve** built-in marker colours in dark
  /// mode — every saturated colour sits low on the luminance scale — and none
  /// in light mode, which is exactly backwards from what it was for.
  static const double _minContrastRatio = 1.6;

  /// Memoized `Color.computeLuminance()`: three `pow()` calls per invocation,
  /// and the grid asks for one per marker per cell on every rebuild. Bounded
  /// and cleared wholesale like `FastingCalendar`'s per-year maps — the key
  /// space is the set of category colours, so it never approaches the cap.
  static final Map<int, double> _luminanceCache = {};
  static const int _luminanceCacheCap = 64;

  static double _luminanceOf(Color color) {
    final key = color.toARGB32();
    final cached = _luminanceCache[key];
    if (cached != null) return cached;
    if (_luminanceCache.length >= _luminanceCacheCap) _luminanceCache.clear();
    return _luminanceCache[key] = color.computeLuminance();
  }

  /// WCAG relative-contrast ratio between two already-resolved luminances,
  /// matching `MarkdownColorPalette._contrastRatio`.
  static double _contrastRatio(double a, double b) {
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    return (hi + 0.05) / (lo + 0.05);
  }

  Color _fade(Color color) =>
      opacity == 1.0 ? color : color.withValues(alpha: color.a * opacity);

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || maxBars <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final hasOverflow = bars.length > maxBars;
    // Reserve the last slot for the "+N" indicator when overflowing.
    final visibleCount = hasOverflow ? maxBars - 1 : bars.length;
    final hiddenCount = hasOverflow ? bars.length - visibleCount : 0;
    // Reference luminance of the calendar cell background, resolved once per
    // cell and shared by every marker in it.
    final surfaceLum = _luminanceOf(theme.colorScheme.surface);
    final outlineColor = _fade(
      theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );

    Border? outlineFor(Color color) {
      if (_contrastRatio(_luminanceOf(color), surfaceLum) >=
          _minContrastRatio) {
        return null;
      }
      // 1px centred, never the old 0.5px inset. Half a logical pixel is half a
      // *device* pixel at dpr 1.0 (desktop), which paints as a washed-out grey
      // smear rather than a line — and being inset it also ate a third of a
      // 3px bar's fill. Centred keeps the fill intact and stays inside the
      // 1.5px inter-bar gap (0.5px of overhang per side).
      return Border.all(
        color: outlineColor,
        strokeAlign: BorderSide.strokeAlignCenter,
      );
    }

    // One semantics node for the whole strip, not one per marker (**5.6**).
    //
    // Primarily an accessibility fix and only incidentally a render-object
    // saving: a 3px bar inside a calendar cell is not a useful focus target,
    // so a screen reader used to stop on each of up to `maxBars` unlabelled
    // slivers per cell — 42 cells' worth — and read them one at a time with
    // no sense of which day they belonged to. Merged, the cell announces
    // "Leg day, Dentist, +2" once.
    //
    // The overflow chip's own `Text` semantics is folded into the same label
    // rather than dropped: `+N` is exactly what it announced before, so
    // nothing a user could hear has been lost, and no invented string needs
    // localizing. [ExcludeSemantics] is what stops that `Text` from also
    // surfacing as a second node inside this one.
    final label = [
      for (var i = 0; i < visibleCount; i++) bars[i].semanticLabel,
      if (hasOverflow) '+$hiddenCount',
    ].join(', ');

    Widget labelled(Widget strip) => Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(child: strip),
    );

    if (style == CalendarMarkerStyle.dots) {
      return labelled(
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < visibleCount; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: _fade(bars[i].color),
                  shape: BoxShape.circle,
                  border: outlineFor(bars[i].color),
                ),
              ),
            ],
            if (hasOverflow) ...[
              if (visibleCount > 0) const SizedBox(width: 3),
              _OverflowChip(
                count: hiddenCount,
                color: _fade(theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );
    }

    return labelled(
      Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < visibleCount; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              Container(
                height: barHeight,
                decoration: BoxDecoration(
                  color: _fade(bars[i].color),
                  borderRadius: BorderRadius.circular(barHeight),
                  border: outlineFor(bars[i].color),
                ),
              ),
            ],
            if (hasOverflow) ...[
              if (visibleCount > 0) SizedBox(height: spacing),
              _OverflowChip(
                count: hiddenCount,
                color: _fade(theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
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
