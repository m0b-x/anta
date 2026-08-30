/// The days the calendar's **presentation** layer treats as the weekend —
/// one source for `TableCalendar.weekendDays` (which styles the day-of-week
/// header) and for every surface that paints or annotates a weekend day
/// itself: `CalendarDayCell.isWeekend`, the weekend day bar and the day
/// panel's weekend summary entry.
///
/// The package parameter and the cell logic used to hold this set
/// independently — the package's own `[saturday, sunday]` default on one
/// side, an inline `weekday == saturday || weekday == sunday` on the other —
/// which agreed only by coincidence, and only one of the two was reachable
/// from app code.
///
/// Deliberately **not** consumed by `WeekendsRecurrence`, `FastingCalendar`
/// or `HolidaySeeds`: those answer "which days does this event fall on" and
/// "what does this tradition/jurisdiction observe", which are data semantics
/// fixed at Sat–Sun (and at their own liturgical/legal rules) regardless of
/// what the grid chooses to shade.
abstract final class CalendarWeekend {
  /// Weekend weekdays as `DateTime` weekday constants, in the shape
  /// `TableCalendar.weekendDays` takes.
  static const List<int> days = [DateTime.saturday, DateTime.sunday];

  /// Whether [day] falls on the weekend. Cheap enough for the 42-cell grid
  /// path: a two-element scan over a const list, no allocation.
  static bool isWeekend(DateTime day) => days.contains(day.weekday);
}
