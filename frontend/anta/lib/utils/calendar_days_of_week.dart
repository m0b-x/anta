import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

/// The weekday row above a month grid — the calendar page's and the Dates
/// sheet's: one height and one label style, so the two grids cannot drift.
///
/// Hoisted in the fix round of Tier 1 (`docs/calendar-language-tier-1-roadmap.md`,
/// D24): the sheet had left `table_calendar`'s default weekday style in
/// place, which carries no size of its own and so inherits the sheet's
/// `bodyMedium` — at 200 % a 28 px label in a 24 dp row was cut through the
/// middle. The page's `labelMedium` at 600 sits whole in the same row.
abstract final class CalendarDaysOfWeek {
  /// `TableCalendar.daysOfWeekHeight` on both grids.
  static const double height = 24;

  /// `TableCalendar.daysOfWeekStyle` on both grids: the weekend labels take
  /// the error colour only while the appearance highlights weekends, the
  /// same switch that tints the weekend day cells.
  static DaysOfWeekStyle style(
    ThemeData theme, {
    required bool highlightWeekends,
  }) {
    final colorScheme = theme.colorScheme;
    final weekday = theme.textTheme.labelMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );
    return DaysOfWeekStyle(
      weekdayStyle: weekday,
      weekendStyle: highlightWeekends
          ? weekday.copyWith(color: colorScheme.error.withValues(alpha: 0.85))
          : weekday,
    );
  }
}
