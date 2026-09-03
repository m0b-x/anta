import 'package:table_calendar/table_calendar.dart';

import '../models/calendar_appearance.dart';

/// Maps the app's week-start setting onto `table_calendar`'s enum. Shared by
/// every grid the app renders — the calendar page, its neighbour-month
/// prewarm, the date picker sheet and the agenda drill-down's mini month — so
/// none of them can disagree on a month's first visible day.
StartingDayOfWeek startingDayOfWeekFor(CalendarWeekStart weekStart) {
  return switch (weekStart) {
    CalendarWeekStart.monday => StartingDayOfWeek.monday,
    CalendarWeekStart.saturday => StartingDayOfWeek.saturday,
    CalendarWeekStart.sunday => StartingDayOfWeek.sunday,
  };
}

/// `DateTime.weekday` value the grid's first column holds.
int firstWeekdayOf(CalendarWeekStart weekStart) {
  return switch (weekStart) {
    CalendarWeekStart.monday => DateTime.monday,
    CalendarWeekStart.saturday => DateTime.saturday,
    CalendarWeekStart.sunday => DateTime.sunday,
  };
}

/// Column a day falls in, given the week start — 0 for the leftmost column.
int weekdayColumnOf(DateTime day, CalendarWeekStart weekStart) {
  return (day.weekday - firstWeekdayOf(weekStart)) % 7;
}
