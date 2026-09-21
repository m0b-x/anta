import 'package:equatable/equatable.dart';

import '../constants/alert_constants.dart';
import '../constants/event_alerts.dart';
import '../models/alert_sound.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';

/// One alert, on one occurrence, at one instant — the unit the scheduler
/// diffs and the gateway hands to the platform.
///
/// [day] is the **date-only UTC** occurrence day (what `occursOnUtcDay`
/// answers about); [fireAt] is a **local** wall-clock instant. The two are
/// deliberately different kinds of `DateTime` and are never converted into one
/// another: the day says which occurrence this is, the instant says when the
/// phone speaks. Running one through the other is how an alert ends up a day
/// or an hour out.
class PlannedFire extends Equatable {
  final CalendarEvent event;
  final EventAlert alert;

  /// Occurrence day, date-only UTC.
  final DateTime day;

  /// Local instant the platform is asked to fire at.
  final DateTime fireAt;

  final AlertKind kind;

  /// The sound this fire will be armed with, already resolved against the
  /// `alert_sound` setting — so the gateway is handed a decision rather than
  /// two values and a rule, and never reads a setting of its own.
  ///
  /// Defaults to the bundled sound: a fire nobody named a sound for is a fire
  /// that rings the one sound every install has.
  final AlertSound sound;

  const PlannedFire({
    required this.event,
    required this.alert,
    required this.day,
    required this.fireAt,
    this.kind = AlertKind.scheduled,
    this.sound = const AlertSoundBundled(),
  });

  @override
  List<Object?> get props => [event.id, alert.id, day, fireAt, kind, sound];
}

/// Turns events and their alerts into the bounded list of instants the OS
/// should hold. **Pure**: no database, no facade writes, no clock of its own.
///
/// [plan] takes `now` as a parameter — the codebase's first clock seam. Every
/// caller reads `DateTime.now()` exactly once and hands the same value in, so
/// a plan is a function of its inputs and a test can place the horizon
/// anywhere without touching the system clock.
///
/// What it never plans (**§2.6**) falls out of the inputs rather than being
/// re-checked here: a skipped occurrence, an occurrence past `endDate` and a
/// tombstoned event are all denied by [CalendarEvent.occursOnUtcDay], which is
/// the one choke point the whole calendar already goes through. A disabled
/// alert is the single exclusion this file owns.
abstract final class AlertPlanner {
  /// The bounded, merged, soonest-first plan.
  ///
  /// Walks each alerted event day by day from `today` (date-only UTC of [now])
  /// for at most [AlertHorizon.days] days, collecting up to
  /// [AlertHorizon.perAlert] occurrence days per **enabled** alert whose fire
  /// instant is still ahead of [now], then merges every candidate by instant
  /// and truncates to [AlertHorizon.total].
  ///
  /// Rules that read `PublicHolidays` (workdays, holidays-only) are re-walked
  /// on every call, which is what makes a holiday-profile change reach the OS
  /// — nothing here caches, deliberately.
  static List<PlannedFire> plan({
    required List<CalendarEvent> events,
    required Map<String, List<EventAlert>> alertsByEvent,
    required AlertSettings defaults,
    required AlertHorizon horizon,
    required DateTime now,
  }) {
    if (events.isEmpty || alertsByEvent.isEmpty) return const [];
    final today = DateTime.utc(now.year, now.month, now.day);
    final candidates = <PlannedFire>[];

    for (final event in events) {
      final alerts = alertsByEvent[event.id];
      if (alerts == null || alerts.isEmpty) continue;
      final enabled = [
        for (final alert in alerts)
          if (alert.enabled) alert,
      ];
      if (enabled.isEmpty) continue;

      final taken = List<int>.filled(enabled.length, 0);
      var remaining = enabled.length * horizon.perAlert;

      for (var offset = 0; offset < horizon.days && remaining > 0; offset++) {
        // UTC arithmetic: a date-only UTC day plus whole days has no DST to
        // trip over, which is the reason occurrence days are UTC at all.
        final day = today.add(Duration(days: offset));
        if (!event.occursOnUtcDay(day)) continue;
        for (var i = 0; i < enabled.length; i++) {
          if (taken[i] >= horizon.perAlert) continue;
          final fireAt = fireInstant(
            event: event,
            alert: enabled[i],
            day: day,
            defaults: defaults,
          );
          if (!fireAt.isAfter(now)) continue;
          candidates.add(
            PlannedFire(
              event: event,
              alert: enabled[i],
              day: day,
              fireAt: fireAt,
              // Resolved here rather than in the gateway: `defaults` is
              // already the one place the alert-level and app-level answers
              // meet, and a fire that carries its own sound is a fire the
              // scheduler can diff without reading a setting a second time.
              sound: AlertSound.resolve(
                alert: enabled[i].sound,
                setting: defaults.sound,
              ),
            ),
          );
          taken[i]++;
          remaining--;
        }
      }
    }

    // `List.sort` is not stable in Dart and several alerts routinely share an
    // instant (five alerts "at start" on one event, two events at 09:00), so
    // the tie-break is spelled out — otherwise which entries survive the
    // `total` truncation would change between two identical reconciles, and
    // the diff would cancel and re-register the same set forever.
    candidates.sort((a, b) {
      final byInstant = a.fireAt.compareTo(b.fireAt);
      if (byInstant != 0) return byInstant;
      final byEvent = a.event.id.compareTo(b.event.id);
      if (byEvent != 0) return byEvent;
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      return a.alert.id.compareTo(b.alert.id);
    });

    if (candidates.length <= horizon.total) return candidates;
    return candidates.sublist(0, horizon.total);
  }

  /// The instant one [alert] fires for [event]'s occurrence on [day].
  ///
  /// Which offset set applies is decided by `event.time == null` — the
  /// **derived** all-day flag, never the persisted mirror column — so an event
  /// flipped between timed and all-day is described by the offsets that still
  /// mean something without either set being rewritten.
  ///
  /// Both branches rebuild the day's `y/m/d` as a **local** wall clock and put
  /// the minute in the constructor's minute slot rather than adding a
  /// `Duration` to local midnight. That is the whole of **A14**: local midnight
  /// carries the pre-transition UTC offset, so adding absolute minutes across a
  /// DST boundary lands an hour off the wall clock the user set (07:00 becomes
  /// 08:00 on the spring-forward day and 06:00 on the fall-back one), while the
  /// constructor keeps the wall clock and normalises a time inside a spring gap
  /// forward to the next valid instant. It also normalises an out-of-range
  /// minute, which is what lets a "1 day before" offset and a `daysBefore`
  /// anchor both be expressed as a plain minute count.
  static DateTime fireInstant({
    required CalendarEvent event,
    required EventAlert alert,
    required DateTime day,
    required AlertSettings defaults,
  }) {
    final time = event.time;
    if (time == null) {
      final anchor = day.subtract(Duration(days: alert.daysBefore));
      final minute =
          alert.dayMinute ??
          defaults.allDayDefault?.dayMinute ??
          kDefaultAlertDayMinute;
      return DateTime(anchor.year, anchor.month, anchor.day, 0, minute);
    }
    return DateTime(
      day.year,
      day.month,
      day.day,
      0,
      time.startMinute - alert.offsetMinutes,
    );
  }
}
