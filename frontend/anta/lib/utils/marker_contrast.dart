import 'package:flutter/painting.dart';

/// Shared contrast rules for the calendar's small colour markers — the bottom
/// marker strip (`CalendarDayBars`) and the left-edge rail
/// (`CalendarDayRail`).
///
/// Extracted rather than copied: the logic was retuned once already
/// (2026-08-23) and a second copy would silently keep the version that was
/// wrong.
class MarkerContrast {
  const MarkerContrast._();

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
  static const double minContrastRatio = 1.6;

  /// Memoized `Color.computeLuminance()`: three `pow()` calls per invocation,
  /// and the grid asks for one per marker per cell on every rebuild. Bounded
  /// and cleared wholesale like `FastingCalendar`'s per-year maps — the key
  /// space is the set of category colours, so it never approaches the cap.
  static final Map<int, double> _luminanceCache = {};
  static const int _luminanceCacheCap = 64;

  static double luminanceOf(Color color) {
    final key = color.toARGB32();
    final cached = _luminanceCache[key];
    if (cached != null) return cached;
    if (_luminanceCache.length >= _luminanceCacheCap) _luminanceCache.clear();
    return _luminanceCache[key] = color.computeLuminance();
  }

  /// WCAG relative-contrast ratio between two already-resolved luminances,
  /// matching `MarkdownColorPalette._contrastRatio`.
  static double contrastRatio(double a, double b) {
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The hairline for [color] against a cell whose luminance is
  /// [surfaceLuminance], or `null` when the marker already stands on its own.
  ///
  /// [outlineColor] arrives already faded by the caller — outside-month days
  /// fade through colours, never an `Opacity` layer.
  static Border? outlineFor(
    Color color, {
    required double surfaceLuminance,
    required Color outlineColor,
  }) {
    if (contrastRatio(luminanceOf(color), surfaceLuminance) >=
        minContrastRatio) {
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
}
