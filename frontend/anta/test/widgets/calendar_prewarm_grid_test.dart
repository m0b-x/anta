import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/utils/calendar_week_start.dart';

/// Guards the one piece of hand-rolled arithmetic in 3.4's neighbour-month
/// prewarm.
///
/// `gridDaysForMonth` reimplements `CalendarCore._getDaysBefore` from
/// `table_calendar` — a pub.dev package, not a fork, so nothing makes the two
/// stay in step. If they drift, the prewarm warms days the grid never paints
/// and every painted day stays cold: a pure performance regression that no
/// other test would notice, because the grid still renders correctly.
///
/// The package's rule is
/// `(firstDay.weekday + 7 - getWeekdayNumber(startingDayOfWeek)) % 7`, where
/// `getWeekdayNumber` is `StartingDayOfWeek.values.indexOf(w) + 1` — so
/// `monday` is 1 and `sunday` is 7, matching `DateTime.weekday`.
void main() {
  int expectedStartWeekday(StartingDayOfWeek start) =>
      StartingDayOfWeek.values.indexOf(start) + 1;

  const weekStarts = {
    CalendarWeekStart.monday: StartingDayOfWeek.monday,
    CalendarWeekStart.saturday: StartingDayOfWeek.saturday,
    CalendarWeekStart.sunday: StartingDayOfWeek.sunday,
  };

  test('the app week-start setting maps onto the package enum', () {
    for (final entry in weekStarts.entries) {
      expect(startingDayOfWeekFor(entry.key), entry.value);
    }
  });

  group('gridDaysForMonth', () {
    // Deliberately awkward months: one starting exactly on Monday (2026-06),
    // a February in a non-leap year, a leap February, a 31-day month starting
    // on a Sunday (2026-11), and a December so the year rolls over.
    final months = [
      DateTime.utc(2026, 6),
      DateTime.utc(2026, 2),
      DateTime.utc(2024, 2),
      DateTime.utc(2026, 11),
      DateTime.utc(2026, 12),
    ];

    for (final start in StartingDayOfWeek.values) {
      for (final month in months) {
        final label = '${month.year}-${month.month} from ${start.name}';

        test('$label starts on the configured weekday', () {
          final days = gridDaysForMonth(month, start);
          expect(days.first.weekday, expectedStartWeekday(start));
        });

        test('$label spans exactly the prewarm window, consecutively', () {
          final days = gridDaysForMonth(month, start);
          expect(days, hasLength(prewarmGridDayCount));
          for (var i = 1; i < days.length; i++) {
            expect(
              days[i].difference(days[i - 1]).inDays,
              1,
              reason: 'day $i must follow the previous one',
            );
          }
          expect(days.every((d) => d.isUtc), isTrue);
        });

        test('$label is a superset of the month it anchors', () {
          final days = gridDaysForMonth(month, start).toSet();
          final length = DateTime.utc(
            month.year,
            month.month + 1,
          ).difference(month).inDays;
          for (var i = 0; i < length; i++) {
            expect(
              days,
              contains(DateTime.utc(month.year, month.month, 1 + i)),
              reason: 'every real day of the month must be warmed',
            );
          }
        });

        test('$label starts within one week before the 1st', () {
          final first = gridDaysForMonth(month, start).first;
          expect(first.isAfter(month), isFalse);
          expect(month.difference(first).inDays, lessThan(7));
        });
      }
    }
  });
}
