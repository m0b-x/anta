import '../../constants/event_alerts.dart';
import '../../models/alert_payload.dart';
import '../../models/calendar_event.dart';
import '../../models/recurrence_rule.dart';
import 'calendar_event.dart';

/// What Skip on an upcoming-alarm notice means for the event it announces
/// (OS-3, **B6**), as the bloc event that applies it and the one that undoes
/// it.
///
/// Skipping tomorrow's 06:00 must not mean editing the event: a recurring
/// event has its one occurrence cancelled (`SetOccurrenceSkipped`, which
/// takes the alarm off the platform through the reconcile the handler already
/// runs), and a one-time event — which cannot be skipped, only deleted — has
/// the alert itself switched off instead, the hub's own move. The pair is
/// resolved together so the snackbar's Undo is always the exact inverse.
///
/// Null when there is nothing honest to do: the occurrence day is already
/// behind [today] (a notice that outlived its alarm), or the one-time event's
/// alert is gone or already off (`ToggleEventAlert` would be a silent no-op
/// and the snackbar's Undo would re-enable nothing).
abstract final class AlertSkipAction {
  static ({CalendarPageEvent apply, CalendarPageEvent undo})? resolve({
    required CalendarEvent event,
    required AlertPayload payload,
    required DateTime today,
  }) {
    if (payload.dayUtc.isBefore(today)) return null;
    if (event.rule is OneTimeRecurrence) {
      final alert = EventAlerts.alertsFor(event.id)
          .where((candidate) => candidate.id == payload.alertId)
          .firstOrNull;
      if (alert == null || !alert.enabled) return null;
      return (
        apply: ToggleEventAlert(
          eventId: event.id,
          alertId: payload.alertId,
          enabled: false,
        ),
        undo: ToggleEventAlert(
          eventId: event.id,
          alertId: payload.alertId,
          enabled: true,
        ),
      );
    }
    final day = payload.dayUtc;
    return (
      apply: SetOccurrenceSkipped(eventId: event.id, day: day),
      undo: ClearOccurrenceSkipped(eventId: event.id, day: day),
    );
  }
}
