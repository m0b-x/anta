import 'package:equatable/equatable.dart';

import '../constants/public_holidays.dart';

/// Sealed hierarchy of recurrence rules for a calendar event.
///
/// All rules are pure value objects. [occursOn] takes a normalized date-only
/// UTC [day] plus the event's anchor [start] date and returns whether the
/// rule produces an occurrence on that day.
///
/// By default a rule never fires before [start]. When [retroactive] is set the
/// pre-start guard is lifted and the rule's periodic phase extends backwards
/// through time — a yearly check-up added today then also shows in every
/// previous year. Every phase test below is written so this works without a
/// back-projected anchor: Dart's `%` is Euclidean (a negative dividend still
/// yields the correct non-negative residue) and [_weekIndex] floors toward
/// negative infinity. Do **not** "fix" this by shifting [start] backwards by
/// whole periods instead — a day-31 or Feb-29 anchor silently rolls over into
/// the next month when reconstructed as a `DateTime`, corrupting the phase.
///
/// To add a new rule:
///   1. Add a new `final class` here extending [RecurrenceRule].
///   2. Add a case in `RecurrenceFormatter.format` (services).
///   3. Add a case in `EventEditorSheet` (state init + build mapping).
sealed class RecurrenceRule extends Equatable {
  const RecurrenceRule();

  bool occursOn(DateTime day, DateTime start, {bool retroactive = false});

  /// Days inside `[from, to]` (inclusive, both date-only UTC) that this rule
  /// *may* fire on, or `null` when it cannot usefully prune itself.
  ///
  /// A **superset** contract, never a membership decision: every day for which
  /// [occursOn] is true must appear here, but the reverse is not required.
  /// Callers validate each candidate through `CalendarEvent.occursOnUtcDay`
  /// anyway (which is also where the `endDate` clamp and cancelled
  /// occurrences live), so an extra day costs one check while a missing day
  /// silently deletes an occurrence from the user's calendar.
  ///
  /// `null` means "scan me against every day", **not** "I never fire" and not
  /// "every day in the window". The distinction is load-bearing: a caller
  /// buckets a returned iterable into a per-day map, and for a rule that fires
  /// (nearly) daily that map costs far more than the scan it would replace.
  /// `null` keeps such a rule on exactly the pre-existing scan path.
  ///
  /// The returned order is unspecified — callers bucket by day.
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) => null;

  /// Whether [retroactive] can change this rule's output. False for the rules
  /// whose membership is exact (one-time, explicit date sets), which lets the
  /// editor hide the scope control instead of showing a dead toggle.
  bool get supportsRetroactive => true;

  /// Whole periods between [start] and [day] in this rule's own unit
  /// (days / weeks / months / years), or `null` for rules without a periodic
  /// unit. Pure display math for the occurrence-count feature — it never
  /// participates in [occursOn]. Both arguments must be date-only UTC, like
  /// every other date in this file. May be negative for retroactive
  /// occurrences before [start]; callers suppress non-positive values.
  int? elapsedPeriods(DateTime day, DateTime start) => null;

  @override
  List<Object?> get props => const [];
}

/// Shared pre-start guard. Returns true when [day] must be rejected because it
/// precedes the anchor and the rule is not [retroactive].
bool _beforeStart(DateTime day, DateTime start, bool retroactive) {
  return !retroactive && day.isBefore(start);
}

/// Monday-aligned epoch for stable "every N weeks" math. 2000-01-03 is a
/// Monday and predates the calendar's representable range, so the week
/// index of any in-range date is well defined and weeks are counted from a
/// fixed grid rather than from each event's start (which keeps interval
/// phase consistent regardless of the anchor's weekday).
final DateTime _weekEpoch = DateTime.utc(2000, 1, 3);

/// Whole weeks between [_weekEpoch] and [day], flooring toward negative
/// infinity so dates before the epoch still index monotonically.
int _weekIndex(DateTime day) {
  final days = day.difference(_weekEpoch).inDays;
  return days >= 0 ? days ~/ 7 : -((-days + 6) ~/ 7);
}

/// First day of `[from, to]` a start-guarded rule may fire on — the
/// [candidateDaysIn] mirror of [_beforeStart], and used by exactly the rules
/// that call it. [OneTimeRecurrence] and [SpecificDatesRecurrence] have no
/// pre-start guard and must never clamp.
DateTime _candidateFloor(DateTime from, DateTime start, bool retroactive) =>
    (!retroactive && from.isBefore(start)) ? start : from;

const _daysPerMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// Real length of a month, so a generator never constructs a rolled-over date:
/// `DateTime.utc(2026, 2, 31)` is March 3, which `occursOn` would reject on
/// `day.day != start.day` anyway — emitting it is pure waste, and reconstructing
/// an anchor that way is the corruption the class doc warns against.
int _daysInMonth(int year, int month) =>
    month == DateTime.february && _isLeapYear(year)
    ? 29
    : _daysPerMonth[month - 1];

/// Single-occurrence event. Fires only on its [start] date.
final class OneTimeRecurrence extends RecurrenceRule {
  const OneTimeRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) =>
      day == start;

  /// No pre-start clamp: [occursOn] is a bare `day == start`, so [retroactive]
  /// cannot change the answer.
  @override
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) {
    if (start.isBefore(from) || start.isAfter(to)) return const <DateTime>[];
    return <DateTime>[start];
  }

  @override
  bool get supportsRetroactive => false;
}

/// Fires on an explicit set of one-off [dates] (each date-only UTC).
///
/// Models a one-time event the user pinned to several specific days at once
/// ("available on these dates"). Membership is exact and independent of
/// [start]; an empty set never fires (the editor guards against this). The
/// owning event's [start] is conventionally the earliest date in the set.
final class SpecificDatesRecurrence extends RecurrenceRule {
  final Set<DateTime> dates;

  const SpecificDatesRecurrence({required this.dates});

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) =>
      dates.contains(day);

  /// Membership is exact and independent of [start], so there is no pre-start
  /// clamp here — a pinned date may legitimately precede the anchor. [dates] is
  /// insertion-ordered, not sorted, which the unordered result contract allows.
  @override
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) => <DateTime>[
    for (final date in dates)
      if (!date.isBefore(from) && !date.isAfter(to)) date,
  ];

  @override
  bool get supportsRetroactive => false;

  @override
  List<Object?> get props => [dates];
}

/// Fires every [interval] days on or after [start] (1 = every day).
final class DailyRecurrence extends RecurrenceRule {
  final int interval;

  const DailyRecurrence({this.interval = 1}) : assert(interval >= 1);

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    if (interval <= 1) return true;
    return day.difference(start).inDays % interval == 0;
  }

  /// `null` at `interval <= 1`: the rule fires on every day from the anchor on,
  /// so there is nothing to prune and bucketing the whole window would cost far
  /// more than the scan.
  @override
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) {
    if (interval <= 1) return null;
    final floor = _candidateFloor(from, start, retroactive);
    if (floor.isAfter(to)) return const <DateTime>[];
    // Euclidean `%`: a floor before the anchor still yields a non-negative
    // residue, so the retroactive sequence keeps the anchor's phase without
    // back-projecting `start`.
    final phase = floor.difference(start).inDays % interval;
    var day = phase == 0 ? floor : floor.add(Duration(days: interval - phase));
    final days = <DateTime>[];
    while (!day.isAfter(to)) {
      days.add(day);
      day = day.add(Duration(days: interval));
    }
    return days;
  }

  @override
  int elapsedPeriods(DateTime day, DateTime start) =>
      day.difference(start).inDays;

  @override
  List<Object?> get props => [interval];
}

/// Fires every [interval] weeks on the selected [weekdays] (1=Mon..7=Sun).
///
/// An empty weekday set never fires; the editor guards against this. With
/// [interval] > 1 only the matching weeks fire (e.g. an A/B split every
/// two weeks), counted on a fixed Monday-aligned grid anchored at [start]'s
/// week.
final class WeeklyRecurrence extends RecurrenceRule {
  final Set<int> weekdays;
  final int interval;

  const WeeklyRecurrence({required this.weekdays, this.interval = 1})
    : assert(interval >= 1);

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    if (!weekdays.contains(day.weekday)) return false;
    if (interval <= 1) return true;
    return (_weekIndex(day) - _weekIndex(start)) % interval == 0;
  }

  /// Empty [weekdays] yields **nothing**, never everything — [occursOn]'s
  /// `weekdays.contains` fails for all seven, so the rule fires on no day at
  /// all. All seven weekdays at `interval <= 1` is the opposite extreme and
  /// returns `null` (every day; nothing to prune).
  ///
  /// The week phase is taken from [_weekIndex] on the fixed Monday grid, never
  /// by stepping seven days from [start]: the two agree only when the anchor's
  /// own week index happens to line up, and diverging silently flips an A/B
  /// week.
  @override
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) {
    if (weekdays.isEmpty) return const <DateTime>[];
    // Bucketing a candidate costs about twice what validating one does, so a
    // rule covering half its cycle or more is cheaper left in the dense scan
    // than indexed. Measured: six-of-seven weekdays bucketed runs 2.6-6.3x
    // slower than scanning, and a user can configure exactly that even though
    // no built-in does.
    if (2 * weekdays.length >= DateTime.daysPerWeek * interval) return null;
    final floor = _candidateFloor(from, start, retroactive);
    if (floor.isAfter(to)) return const <DateTime>[];
    final startWeek = _weekIndex(start);
    final step = Duration(days: DateTime.daysPerWeek * interval);
    final days = <DateTime>[];
    for (final weekday in weekdays) {
      var day = floor.add(
        Duration(days: (weekday - floor.weekday) % DateTime.daysPerWeek),
      );
      if (interval > 1) {
        final phase = (_weekIndex(day) - startWeek) % interval;
        if (phase != 0) {
          day = day.add(
            Duration(days: (interval - phase) * DateTime.daysPerWeek),
          );
        }
      }
      while (!day.isAfter(to)) {
        days.add(day);
        day = day.add(step);
      }
    }
    return days;
  }

  @override
  int elapsedPeriods(DateTime day, DateTime start) =>
      _weekIndex(day) - _weekIndex(start);

  @override
  List<Object?> get props => [weekdays, interval];
}

/// Fires every [interval] months on the same day-of-month as [start].
/// Naturally skips months that don't have that day (e.g. day 31 in
/// February).
final class MonthlyRecurrence extends RecurrenceRule {
  final int interval;

  const MonthlyRecurrence({this.interval = 1}) : assert(interval >= 1);

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    if (day.day != start.day) return false;
    if (interval <= 1) return true;
    final months = (day.year - start.year) * 12 + (day.month - start.month);
    return months % interval == 0;
  }

  /// One candidate per month the window touches, skipped when the month is
  /// shorter than the anchor's day-of-month — the generator side of
  /// [occursOn]'s `day.day != start.day` clamp.
  @override
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) {
    final floor = _candidateFloor(from, start, retroactive);
    if (floor.isAfter(to)) return const <DateTime>[];
    final days = <DateTime>[];
    var year = floor.year;
    var month = floor.month;
    while (year < to.year || (year == to.year && month <= to.month)) {
      final months = (year - start.year) * 12 + (month - start.month);
      if (interval <= 1 || months % interval == 0) {
        if (start.day <= _daysInMonth(year, month)) {
          final day = DateTime.utc(year, month, start.day);
          if (!day.isBefore(floor) && !day.isAfter(to)) days.add(day);
        }
      }
      if (month == DateTime.december) {
        month = DateTime.january;
        year++;
      } else {
        month++;
      }
    }
    return days;
  }

  @override
  int elapsedPeriods(DateTime day, DateTime start) =>
      (day.year - start.year) * 12 + (day.month - start.month);

  @override
  List<Object?> get props => [interval];
}

/// Fires every [interval] years on the same (month, day) as [start].
/// Anchoring on Feb 29 naturally limits the rule to leap years.
final class YearlyRecurrence extends RecurrenceRule {
  final int interval;

  const YearlyRecurrence({this.interval = 1}) : assert(interval >= 1);

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    if (day.month != start.month || day.day != start.day) return false;
    if (interval <= 1) return true;
    return (day.year - start.year) % interval == 0;
  }

  /// One candidate per year the window touches. A Feb-29 anchor exists only in
  /// leap years, so those are skipped outright: `DateTime.utc(2027, 2, 29)`
  /// rolls into March 1, which [occursOn] rejects on `day.day != start.day`.
  /// Every other `(month, day)` pair is valid in every year.
  @override
  Iterable<DateTime>? candidateDaysIn(
    DateTime from,
    DateTime to,
    DateTime start, {
    bool retroactive = false,
  }) {
    final floor = _candidateFloor(from, start, retroactive);
    if (floor.isAfter(to)) return const <DateTime>[];
    final anchoredOnLeapDay =
        start.month == DateTime.february && start.day == 29;
    final days = <DateTime>[];
    for (var year = floor.year; year <= to.year; year++) {
      if (interval > 1 && (year - start.year) % interval != 0) continue;
      if (anchoredOnLeapDay && !_isLeapYear(year)) continue;
      final day = DateTime.utc(year, start.month, start.day);
      if (!day.isBefore(floor) && !day.isAfter(to)) days.add(day);
    }
    return days;
  }

  @override
  int elapsedPeriods(DateTime day, DateTime start) => day.year - start.year;

  @override
  List<Object?> get props => [interval];
}

/// Every Mon–Fri that is NOT a public holiday.
///
/// Keeps the inherited `null` [candidateDaysIn]: membership depends on the
/// mutable, revision-tracked `PublicHolidays` facade, so a generated day set
/// would be an index over an input that changes with no event dispatched.
final class WorkdaysRecurrence extends RecurrenceRule {
  const WorkdaysRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    if (day.weekday > DateTime.friday) return false;
    return !PublicHolidays.isHoliday(day);
  }
}

/// Every Saturday and Sunday on or after `start`.
///
/// Keeps the inherited `null` [candidateDaysIn] — two days in seven is dense
/// enough that the pre-existing scan stays the cheaper path.
final class WeekendsRecurrence extends RecurrenceRule {
  const WeekendsRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    return day.weekday >= DateTime.saturday;
  }
}

/// Fires only on public holidays on or after `start`.
///
/// Must keep the inherited `null` [candidateDaysIn]. Its membership is the
/// mutable, revision-tracked `PublicHolidays` facade — a profile switch, a
/// suppression, a backup restore or a database switch all change it with
/// nothing dispatched — so folding it into a cached day index would put a
/// mutable input inside the index, which is exactly the bug
/// `CalendarBloc._syncHolidayGeneration` exists to avoid.
final class PublicHolidaysOnlyRecurrence extends RecurrenceRule {
  const PublicHolidaysOnlyRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    return PublicHolidays.isHoliday(day);
  }
}
