/// The calendar subsystem's navigable date domain — the single source of
/// truth for the grid, the day pickers and the month/year jump wheel, so a
/// date reachable in one surface is always reachable in the others.
///
/// [earliest] is **1900 for a reason**: it is exactly where the Julian
/// calendar's lag behind the Gregorian becomes the 13 days that
/// `LiturgicalComputus.julianToGregorianOffset` returns for the 1900–2099
/// window (it was 12 through the 1800s, and the function degrades to a flat
/// 13 below its domain). Flooring here keeps every Orthodox-Easter-derived
/// holiday and fasting date correct instead of silently off by a day.
///
/// Width costs nothing at runtime: `TableCalendar` pages months lazily, the
/// year wheel builds its rows through a `ListWheelChildBuilderDelegate`,
/// `FastingCalendar` computes a year on first touch (O(365) of O(1) date
/// math, memoized, bounded cache), and `PublicHolidays.holidayOn` answers
/// years outside the seeded window from a static fixed-date map — one map
/// probe, no database, no seeding.
abstract final class CalendarBounds {
  /// First navigable day. Reaches back far enough to anchor a birthday on a
  /// real birth year, which the occurrence-count age depends on.
  static final DateTime earliest = DateTime.utc(1900, 1, 1);

  /// Last navigable day.
  static final DateTime latest = DateTime.utc(2100, 12, 31);
}
