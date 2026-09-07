import 'package:flutter/material.dart';

/// Centralized colors for the calendar's **contextual** (non-event) day bars
/// and summary entries.
///
/// Per-category colors are no longer defined here — categories are
/// data-driven (see `CalendarCategory.colorValue` / `CategoryService`), so a
/// category's tint comes from its persisted row. The seed colors for built-in
/// categories live in `CalendarCategories.builtInSeeds`.
///
/// To add a new non-event bar kind (e.g. "training cycle", "deload week"):
///   Prefer writing a custom `DayBarProvider` over extending this class.
abstract final class CalendarColors {
  static const Color weekend = Color(0xFFB0BEC5); // blue grey 200
  static const Color publicHoliday = Color(0xFFFFB300); // amber 600

  /// Liturgical violet; used for fasting-day rows and the grid's subtle
  /// fasting tint so both surfaces read as one system.
  static const Color fasting = Color(0xFF8E24AA); // purple 600

  /// Opacity applied to an occurrence the user marked as missed, on every
  /// surface that fades one (grid bars, day-panel rows, agenda rows, timeline
  /// blocks). Matches the outside-month fade so a missed day reads as
  /// "still there, just not the point" rather than as an error.
  static const double missedEventAlpha = 0.35;

  /// Sign colors for the money surfaces (day bar, day summary, month header
  /// net). One definition so the three surfaces cannot drift apart.
  static const Color moneyPositive = Color(0xFF2E7D32); // green 800
  static const Color moneyNegative = Color(0xFFC62828); // red 800

  /// Strength of the day-cell wash per event priority, indexed by
  /// `priority - kMinEventPriority` (P1 first, P5 last). Priority is what the
  /// wash *encodes* — a stronger colour is a more important day — so the
  /// ramp has to stay monotonic and the P1 end has to read as emphasis
  /// without swallowing the day number.
  ///
  /// One table for both themes, like the flat fasting wash and the tonal
  /// today chip: at these alphas the wash never approaches the contrast floor
  /// of the (unchanged) `onSurface` day number. If a specific swatch ever
  /// proves illegible, resolve it once and cache — never per cell.
  static const List<double> eventTintAlphaByPriority = [
    0.28,
    0.22,
    0.16,
    0.12,
    0.08,
  ];

  /// Strength of the fasting wash. Lives here rather than inline in the day
  /// cell so every tint source is resolved before it reaches the painter.
  static const double fastingTintAlpha = 0.10;

  /// Strength of the runner-up source's edge stripe when the user asked to
  /// see both. Far above the wash alphas on purpose — a 3px stripe at wash
  /// strength is invisible, which would make "show both" read as "off".
  static const double cellEdgeAlpha = 0.55;

  /// What the resolved wash alpha is multiplied by under
  /// `CalendarCellStyle.outline`, dropping the fill to a whisper —
  /// roughly `[0.098, 0.077, 0.056, 0.042, 0.028]`.
  ///
  /// Applied to the **resolved** wash rather than replacing it, so the
  /// priority ramp survives the scaling. It lives here beside the ramp it
  /// scales rather than inline in the painter for the same reason
  /// [eventTintAlphaByPriority] does: every number that decides how strong a
  /// calendar tint reads is comparable at a glance in one place, and a style
  /// constant buried in a `BoxDecoration` is one nobody re-tunes against the
  /// ramp it has to stay under.
  static const double outlineStyleWashScale = 0.35;

  /// What the resolved wash alpha is multiplied by to get that style's 1px
  /// border, clamped to 1.0 — roughly `[0.59, 0.46, 0.34, 0.25, 0.17]`.
  ///
  /// Deliberately derived from the wash rather than from [cellEdgeAlpha]:
  /// that one is a flat 0.55 for every priority, and reusing it here would
  /// flatten the ramp exactly where the near-invisible fill has stopped being
  /// able to show it — the border *is* the priority signal in this style.
  /// Same reason for living here rather than in the painter.
  static const double outlineStyleBorderScale = 2.1;

  /// Curated swatch palette offered when a user picks an explicit per-event
  /// color override, and by the category editor. Stored as 32-bit ARGB ints
  /// so they round-trip through SQLite and backup without any platform
  /// `Color` dependency. One list, so the two pickers cannot drift apart.
  static const List<int> swatchPalette = [
    0xFF1E88E5, // blue
    0xFF00ACC1, // cyan
    0xFF00897B, // teal
    0xFF43A047, // green
    0xFF7CB342, // light green
    0xFFC0CA33, // lime
    0xFFFDD835, // yellow
    0xFFFB8C00, // orange
    0xFFF4511E, // deep orange
    0xFFE53935, // red
    0xFFD81B60, // pink
    0xFFEC407A, // rose
    0xFF8E24AA, // purple
    0xFF5E35B1, // deep purple
    0xFF3949AB, // indigo
    0xFF6D4C41, // brown
    0xFF546E7A, // blue grey
    0xFF757575, // grey
  ];
}
