import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;

import '../constants/alert_constants.dart';
import '../constants/event_skips.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../services/event_time_formatter.dart';
import 'alert_planner.dart';

/// What the calendar says once a save has changed an event's alerts: how long
/// until the next one — "Alarm in 2 h 50 min", the confirmation a phone's own
/// clock gives when an alarm is set.
///
/// **Pure**, and on the planner's clock seam: the caller reads
/// `DateTime.now()` once and hands the same value to [afterSave] and
/// [message].
abstract final class AlertCountdown {
  /// How many days ahead the next fire is looked for.
  ///
  /// Wider than [kAlertHorizon] on purpose. That one bounds what the phone is
  /// asked to hold today; this one answers a question about the event — an
  /// appointment three months out has a next reminder, armed once it comes
  /// inside the scheduler's window.
  static const int lookAheadDays = 366;

  /// The soonest fire [alerts] make for [event] after [now], or null when
  /// there is none: no enabled alert, or no occurrence inside [lookAheadDays]
  /// whose alert is still ahead.
  ///
  /// [skippedDays] is the editor's whole cancelled-day set, when it reported
  /// one. Its writes are dispatched, not awaited, so `EventSkips` — which the
  /// planner reads through `occursOnUtcDay` — may not carry them yet: a fire
  /// on one of those days is passed over here, as the detail loop's
  /// `_occurrenceSurvives` reads the result rather than the facade. A day the
  /// same edit *restored* is the gap that leaves, on both.
  static PlannedFire? nextFire({
    required CalendarEvent event,
    required List<EventAlert> alerts,
    required AlertSettings defaults,
    required DateTime now,
    Set<DateTime>? skippedDays,
  }) {
    if (alerts.isEmpty) return null;
    final skipped = skippedDays == null || !EventSkips.appliesTo(event)
        ? const <DateTime>{}
        : skippedDays;
    // One fire per alert answers the question, plus one for every day that
    // may be passed over below.
    final perAlert = skipped.length + 1;
    final plan = AlertPlanner.plan(
      events: [event],
      alertsByEvent: {event.id: alerts},
      defaults: defaults,
      horizon: AlertHorizon(
        perAlert: perAlert,
        days: lookAheadDays,
        total: alerts.length * perAlert,
      ),
      now: now,
    );
    for (final fire in plan) {
      if (!skipped.contains(fire.day)) return fire;
    }
    return null;
  }

  /// The fire to announce after [event] was saved with [alerts], or null to
  /// say nothing.
  ///
  /// Something is said when the save changed what the phone does next: the
  /// alert set is not the one the event had, or its next fire is at another
  /// instant — the time, the date or the rule moved under alerts nobody
  /// touched. A rename says nothing: a confirmation on every save of an event
  /// that happens to carry an alert is one nobody reads.
  ///
  /// [previousEvent] and [previousAlerts] are the event as it was opened;
  /// both are left out for a new one.
  static PlannedFire? afterSave({
    required CalendarEvent event,
    required List<EventAlert> alerts,
    required AlertSettings defaults,
    required DateTime now,
    CalendarEvent? previousEvent,
    List<EventAlert> previousAlerts = const [],
    Set<DateTime>? skippedDays,
  }) {
    final next = nextFire(
      event: event,
      alerts: alerts,
      defaults: defaults,
      now: now,
      skippedDays: skippedDays,
    );
    if (next == null) return null;
    if (previousEvent == null || !listEquals(previousAlerts, alerts)) {
      return next;
    }
    final before = nextFire(
      event: previousEvent,
      alerts: previousAlerts,
      defaults: defaults,
      now: now,
    );
    return before?.fireAt == next.fireAt ? null : next;
  }

  /// "Alarm in 2 h 50 min", "Reminder in 45 min", "Alarm in 3 days 4 h".
  ///
  /// Under a day the wait is rounded **up** to the minute, so it agrees with
  /// the subtraction the reader does in their head — at 05:00:20 an alarm for
  /// 07:00 is "in 2 h", not "in 1 h 59 min" — and can never read zero. From a
  /// day on, minutes say nothing and it is rounded to the hour.
  static String message(PlannedFire fire, DateTime now, AppLocalizations l10n) {
    final kind = fire.alert.isAlarm
        ? l10n.eventAlertModeRing
        : l10n.eventAlertModeNotify;
    final until = fire.fireAt.difference(now);
    final minutes = math.max(
      1,
      (until.inSeconds / Duration.secondsPerMinute).ceil(),
    );
    if (minutes < EventAlert.minutesPerDay) {
      return l10n.eventAlertCountdown(
        kind,
        EventTimeFormatter.formatDuration(minutes, l10n),
      );
    }
    final hours =
        (minutes + Duration.minutesPerHour ~/ 2) ~/ Duration.minutesPerHour;
    final days = hours ~/ Duration.hoursPerDay;
    final rest = hours % Duration.hoursPerDay;
    return rest == 0
        ? l10n.eventAlertCountdownDays(days, kind)
        : l10n.eventAlertCountdownDaysHours(days, kind, rest);
  }
}
