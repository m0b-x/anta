import 'package:equatable/equatable.dart';

import '../models/event_alert.dart';

/// The unit a custom alert offset is counted in. Only ever a *view* of the
/// number an alert stores — minutes before the start for a timed event, whole
/// days before for an all-day one — so a unit can never be persisted out of
/// step with a number.
enum AlertOffsetUnit {
  minutes(1, 59),
  hours(Duration.minutesPerHour, 23),
  days(EventAlert.minutesPerDay, 30);

  /// Minutes in one of this unit.
  final int multiplier;

  /// The ceiling the stepper counts to in this unit. Generous rather than
  /// principled: the horizon (30 days) is what actually bounds a usable
  /// offset, and these only keep the stepper from running away under a held
  /// finger.
  final int max;

  const AlertOffsetUnit(this.multiplier, this.max);
}

/// A custom alert offset as the Custom control counts it: a number in a unit,
/// stepped one at a time between [min] and the unit's ceiling.
///
/// Pure, so the rules are table-tested with no widget in sight and the sheet
/// only shows what these say: which unit a stored value opens in, what a unit
/// change does to the number, and that an all-day event counts in days and
/// nothing else.
class AlertOffset extends Equatable {
  /// The floor in every unit. "At start" and "on the day" are choices of
  /// their own, never something the stepper counts down to.
  static const int min = 1;

  final AlertOffsetUnit unit;
  final int value;

  /// Whether the event is all-day, which pins [unit] to days: an all-day
  /// alert stores whole days and a time of day, so hours and minutes before
  /// it mean nothing.
  final bool allDay;

  const AlertOffset._(this.unit, this.value, this.allDay);

  /// What the control opens on for a [stored] offset — minutes before the
  /// start for a timed event, whole days before for an all-day one.
  ///
  /// A timed offset opens in its natural unit ([naturalUnitOf]). Either kind
  /// opens with the number clamped into that unit's range and never under
  /// [min], so a value the stepper cannot count — "at start", 90 minutes,
  /// 36 hours — opens on one it can.
  factory AlertOffset.seed(int stored, {required bool allDay}) {
    final minutes = allDay ? stored * EventAlert.minutesPerDay : stored;
    final unit = allDay ? AlertOffsetUnit.days : naturalUnitOf(minutes);
    return AlertOffset._(
      unit,
      _clamp(minutes ~/ unit.multiplier, unit),
      allDay,
    );
  }

  /// Days when [minutes] is a whole number of days, hours when it is a whole
  /// number of hours, else minutes. Zero is no number of anything and reads
  /// as minutes.
  static AlertOffsetUnit naturalUnitOf(int minutes) {
    if (minutes > 0 && minutes % EventAlert.minutesPerDay == 0) {
      return AlertOffsetUnit.days;
    }
    if (minutes > 0 && minutes % Duration.minutesPerHour == 0) {
      return AlertOffsetUnit.hours;
    }
    return AlertOffsetUnit.minutes;
  }

  static int _clamp(int value, AlertOffsetUnit unit) =>
      value.clamp(min, unit.max);

  /// The same number in [unit], clamped into its range: 45 minutes becomes
  /// 23 hours, never a fraction of one. An all-day offset stays in days.
  AlertOffset withUnit(AlertOffsetUnit unit) {
    if (allDay) return this;
    return AlertOffset._(unit, _clamp(value, unit), allDay);
  }

  bool get canDecrement => value > min;

  bool get canIncrement => value < unit.max;

  /// One step down, or this offset at the floor.
  AlertOffset get decremented =>
      canDecrement ? AlertOffset._(unit, value - 1, allDay) : this;

  /// One step up, or this offset at the unit's ceiling.
  AlertOffset get incremented =>
      canIncrement ? AlertOffset._(unit, value + 1, allDay) : this;

  /// The offset in minutes, whatever it is counted in.
  int get minutes => value * unit.multiplier;

  /// The number the alert stores: [EventAlert.offsetMinutes] for a timed
  /// event, [EventAlert.daysBefore] for an all-day one — what [AlertOffset.seed]
  /// takes, after the clamp.
  int get stored => allDay ? value : minutes;

  @override
  List<Object?> get props => [unit, value, allDay];
}
