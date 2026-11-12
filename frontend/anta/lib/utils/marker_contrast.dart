import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'lru_cache.dart';

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

  /// The WCAG graphics floor for a mark drawn by its outline alone — a
  /// partner's outlined avatar, a hollow grid marker. A filled mark carries
  /// its colour in its area; a ring has only its stroke, so it must reach
  /// what a non-text graphic needs on its own.
  static const double hollowMinContrastRatio = 3.0;

  /// Above this ground luminance the walk darkens, below it lightens — the
  /// point where black and white text read equally well on a ground.
  static const double _darkenAboveLuminance = 0.18;
  static const double _lightnessStep = 0.04;
  static const int _maxLightnessSteps = 20;

  /// Room for every marker × ground pair of a busy month of washed cells,
  /// so the grid's rebuilds never evict what the next frame asks again.
  static const int atLeastCacheCap = 256;

  static final LruCache<(int, int), Color> _atLeastCache = LruCache(
    maxSize: atLeastCacheCap,
  );

  @visibleForTesting
  static int get atLeastCacheLength => _atLeastCache.length;

  /// [color] where it reaches [hollowMinContrastRatio] against [ground],
  /// else the first colour on a walk of its HSL lightness that does — the
  /// walk `MarkdownColorPalette._ensureContrast` takes.
  ///
  /// One rule for every colour, built-in or custom: the category colours are
  /// one value for both themes, so a per-colour light/dark pair would leave
  /// a user's own colours uncovered. [ground] is what the mark actually sits
  /// on — on a washed day cell the composite of the wash and the surface,
  /// since a colour checked only against the plain surface measured 1.45:1
  /// there. Memoised: the grid asks per marker per cell on every rebuild,
  /// and the key space is categories × grounds — least recently used out
  /// first, never cleared wholesale.
  ///
  /// Measured on the pair as painted, 8 bits a channel — the key's own
  /// colours: a blended ground carries fractions the screen rounds away, and
  /// a walk stopped on them drew 2.99:1.
  static Color atLeast(Color color, Color ground) {
    final key = (color.toARGB32(), ground.toARGB32());
    final cached = _atLeastCache.get(key);
    if (cached != null) return cached;
    final drawn = _walk(Color(key.$1), Color(key.$2));
    _atLeastCache.put(key, drawn);
    return drawn;
  }

  static Color _walk(Color color, Color ground) {
    final groundLum = luminanceOf(ground);
    bool reaches(Color c) =>
        contrastRatio(c.computeLuminance(), groundLum) >=
        hollowMinContrastRatio;
    if (reaches(color)) return color;
    final darken = groundLum > _darkenAboveLuminance;
    var hsl = HSLColor.fromColor(color);
    for (var i = 0; i < _maxLightnessSteps; i++) {
      final next = darken
          ? hsl.lightness - _lightnessStep
          : hsl.lightness + _lightnessStep;
      if (next <= 0.0 || next >= 1.0) break;
      hsl = hsl.withLightness(next);
      final candidate = Color(hsl.toColor().toARGB32());
      if (reaches(candidate)) return candidate;
    }
    return Color(hsl.toColor().toARGB32());
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
