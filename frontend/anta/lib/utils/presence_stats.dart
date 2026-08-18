import 'package:equatable/equatable.dart';

import '../constants/event_presence.dart';
import '../models/calendar_event.dart';
import 'event_agenda.dart';

/// How a presence-tracking event is actually going.
///
/// [attended] / [total] cover the trailing [PresenceAdherence.windowDays];
/// the streaks are counted over the longer [PresenceAdherence.lookbackDays]
/// so a good run is not truncated by the window the ratio uses.
class PresenceStats extends Equatable {
  final int attended;
  final int total;
  final int currentStreak;
  final int longestStreak;

  const PresenceStats({
    required this.attended,
    required this.total,
    required this.currentStreak,
    required this.longestStreak,
  });

  @override
  List<Object?> get props => [attended, total, currentStreak, longestStreak];
}

/// Adherence arithmetic over an event's own recurrence and the absence marks
/// the user made.
///
/// Pure and derived: absences are already persisted, so there is nothing to
/// migrate, nothing to cache and nothing to keep in sync. The cost is one
/// backward walk of at most [lookbackDays] days, each costing an `occursOn`
/// call plus one static facade probe.
abstract final class PresenceAdherence {
  /// Window the attended/total ratio covers. Trailing rather than
  /// month-to-date: "1/1" on the first of the month is noise, while a
  /// trailing window always says something.
  static const int windowDays = 30;

  /// How far back the streaks look. Matches `EventAgenda.maxRangeDays`, the
  /// range every other calendar scan clamps to.
  static const int lookbackDays = EventAgenda.maxRangeDays;

  /// Stats for [event] as of [today], or `null` when the event does not track
  /// presence or has no occurrence in the lookback window.
  ///
  /// Occurrences after [today] are excluded throughout: presence may be
  /// marked ahead of time, and a future day the user pre-marked has not
  /// happened yet, so counting it would report a miss that has not occurred.
  ///
  /// [overrideDay] / [overrideMissed] let a caller that has just toggled a day
  /// see the result before the write reaches the facade — the detail sheet
  /// updates its toggle optimistically, and numbers that lagged it by a frame
  /// would read as the toggle having done nothing.
  static PresenceStats? compute(
    CalendarEvent event, {
    required DateTime today,
    DateTime? overrideDay,
    bool? overrideMissed,
  }) {
    if (!EventPresence.appliesTo(event)) return null;

    final override = overrideDay == null || overrideMissed == null
        ? null
        : EventAgenda.dateOnly(overrideDay);

    final end = EventAgenda.dateOnly(today);
    final windowStart = end.subtract(const Duration(days: windowDays - 1));

    var attended = 0;
    var total = 0;
    var currentStreak = 0;
    var longestStreak = 0;
    var running = 0;
    var streakOpen = true;
    var sawOccurrence = false;

    for (var i = 0; i < lookbackDays; i++) {
      final day = end.subtract(Duration(days: i));
      if (!event.occursOn(day)) continue;
      sawOccurrence = true;

      final missed = day == override
          ? overrideMissed!
          : EventPresence.isMissed(event.id, day);
      if (!day.isBefore(windowStart)) {
        total++;
        if (!missed) attended++;
      }

      if (missed) {
        // Walking backwards, so the first miss closes the current streak;
        // every later one only ends a candidate for the longest.
        if (running > longestStreak) longestStreak = running;
        running = 0;
        streakOpen = false;
      } else {
        running++;
        if (streakOpen) currentStreak = running;
      }
    }
    if (!sawOccurrence) return null;
    if (running > longestStreak) longestStreak = running;

    return PresenceStats(
      attended: attended,
      total: total,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
    );
  }
}
