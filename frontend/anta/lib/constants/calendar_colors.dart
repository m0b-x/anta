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

  /// Curated swatch palette offered when a user picks an explicit per-event
  /// color override. Stored as 32-bit ARGB ints so they round-trip through
  /// SQLite and backup without any platform `Color` dependency. Mirrors the
  /// category editor's palette for a consistent picking experience.
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
