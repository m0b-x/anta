import 'agenda_day_list.dart';
import 'calendar_appearance.dart';
import 'overview_period.dart';

/// The report's Period menu, in order (R): the overview's calendar units and
/// rolling presets without All time (D18), plus the four relative rows —
/// each its This row stepped once, so nothing new is persisted and ◄ / ►
/// keep stepping from there. [custom] opens the range picker.
enum ReportPeriodChoice {
  thisWeek,
  lastWeek,
  nextWeek,
  thisMonth,
  lastMonth,
  nextMonth,
  thisYear,
  last12Months,
  last90Days,
  custom;

  /// The period this row stands for. A relative row at the calendar's edge,
  /// where its step has no neighbour, is its This row. [custom] has no
  /// period of its own and throws.
  OverviewPeriod periodFor({
    required DateTime today,
    required CalendarWeekStart weekStart,
    required AgendaYearBounds years,
  }) {
    OverviewPeriod base(OverviewPeriodChoice choice) =>
        OverviewPeriod.fromChoice(choice, today: today, weekStart: weekStart);
    OverviewPeriod step(OverviewPeriodChoice choice, int direction) {
      final period = base(choice);
      return period.stepped(
            direction: direction,
            today: today,
            yearBounds: years,
          ) ??
          period;
    }

    return switch (this) {
      thisWeek => base(OverviewPeriodChoice.thisWeek),
      lastWeek => step(OverviewPeriodChoice.thisWeek, -1),
      nextWeek => step(OverviewPeriodChoice.thisWeek, 1),
      thisMonth => base(OverviewPeriodChoice.thisMonth),
      lastMonth => step(OverviewPeriodChoice.thisMonth, -1),
      nextMonth => step(OverviewPeriodChoice.thisMonth, 1),
      thisYear => base(OverviewPeriodChoice.thisYear),
      last12Months => base(OverviewPeriodChoice.last12Months),
      last90Days => base(OverviewPeriodChoice.last90Days),
      custom => throw ArgumentError.value(
        this,
        'choice',
        'a custom period comes from the picker',
      ),
    };
  }

  /// The row the menu checks for [period]: the week or month holding today,
  /// the one before it or the one after it by their rows, this year and the
  /// presets by theirs, anything else — a paged unit further away, a
  /// stepped preset, a custom span — as Custom. A relative row that fell
  /// back to its This row at the calendar's edge never claims that period:
  /// the This row precedes it in [values] and answers first.
  static ReportPeriodChoice checkedFor(
    OverviewPeriod period, {
    required DateTime today,
    required CalendarWeekStart weekStart,
    required AgendaYearBounds years,
  }) {
    for (final choice in values) {
      if (choice == custom) continue;
      final candidate = choice.periodFor(
        today: today,
        weekStart: weekStart,
        years: years,
      );
      if (candidate == period) return choice;
    }
    return custom;
  }
}
