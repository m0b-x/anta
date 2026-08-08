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

/// Single-occurrence event. Fires only on its [start] date.
final class OneTimeRecurrence extends RecurrenceRule {
  const OneTimeRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) =>
      day == start;

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

  @override
  int elapsedPeriods(DateTime day, DateTime start) => day.year - start.year;

  @override
  List<Object?> get props => [interval];
}

/// Every Mon–Fri that is NOT a public holiday.
final class WorkdaysRecurrence extends RecurrenceRule {
  const WorkdaysRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    if (day.weekday > DateTime.friday) return false;
    return !PublicHolidays.isHoliday(day);
  }
}

/// Every Saturday and Sunday on or after [start].
final class WeekendsRecurrence extends RecurrenceRule {
  const WeekendsRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    return day.weekday >= DateTime.saturday;
  }
}

/// Fires only on public holidays on or after [start].
final class PublicHolidaysOnlyRecurrence extends RecurrenceRule {
  const PublicHolidaysOnlyRecurrence();

  @override
  bool occursOn(DateTime day, DateTime start, {bool retroactive = false}) {
    if (_beforeStart(day, start, retroactive)) return false;
    return PublicHolidays.isHoliday(day);
  }
}
