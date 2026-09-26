import '../constants/calendar_bounds.dart';

/// The step a picked date set is projected forward by.
enum DateStampUnit { week, month, year }

/// What one projection would add: the new dates, how many candidates were
/// dropped because that day does not exist there (a 31st in a short month,
/// Feb 29 outside a leap year, past the calendar's last day), and the latest
/// date it reaches.
class DateStampResult {
  final Set<DateTime> added;
  final int skipped;
  final DateTime? last;

  const DateStampResult({
    required this.added,
    required this.skipped,
    required this.last,
  });

  bool get isEmpty => added.isEmpty;
}

/// Stamps a set of date-only UTC days forward by a unit, [times] times each,
/// into plain dates. It only ever adds — nothing already picked is touched —
/// and a missing day is skipped rather than clamped, the same silence the
/// monthly rule keeps, so a projected set can never claim a day the source
/// pattern did not have.
abstract final class DateStamp {
  static const int minTimes = 1;
  static const int maxTimes = 24;

  static DateStampResult project(
    Set<DateTime> dates,
    DateStampUnit unit,
    int times, {
    DateTime? lastDate,
  }) {
    final bound = lastDate ?? CalendarBounds.latest;
    final added = <DateTime>{};
    var skipped = 0;
    DateTime? last;
    for (final date in dates) {
      for (var i = 1; i <= times; i++) {
        final next = _shift(date, unit, i);
        if (next == null || next.isAfter(bound)) {
          skipped++;
          continue;
        }
        if (dates.contains(next) || !added.add(next)) continue;
        if (last == null || next.isAfter(last)) last = next;
      }
    }
    return DateStampResult(added: added, skipped: skipped, last: last);
  }

  static DateTime? _shift(DateTime date, DateStampUnit unit, int by) {
    switch (unit) {
      case DateStampUnit.week:
        return DateTime.utc(date.year, date.month, date.day + 7 * by);
      case DateStampUnit.month:
        final total = date.month - 1 + by;
        return _sameDayOrNull(
          date.year + total ~/ 12,
          total % 12 + 1,
          date.day,
        );
      case DateStampUnit.year:
        return _sameDayOrNull(date.year + by, date.month, date.day);
    }
  }

  static DateTime? _sameDayOrNull(int year, int month, int day) {
    if (day > DateTime.utc(year, month + 1, 0).day) return null;
    return DateTime.utc(year, month, day);
  }
}
