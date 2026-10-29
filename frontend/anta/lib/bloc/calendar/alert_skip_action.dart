import '../../constants/event_alerts.dart';
import '../../constants/event_skips.dart';
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
/// An alert the one-time event inherits from its category (**v42**) is not
/// the event's to switch off — that would silence every event in the
/// category — so Skip opts this event out of its category's alerts
/// (`categoryAlerts = false`, the D3 switch) and Undo opts it back in.
///
/// Null when there is nothing honest to do: the occurrence day is already
/// behind [today] (a notice that outlived its alarm), the alert the notice
/// names is gone or already off (the apply would be a silent no-op and the
/// snackbar's Undo would re-enable nothing), or the recurring event's
/// occurrence is already cancelled — a notice sits on the shade for up to the
/// lead time, long enough for the user to cancel that day from the day list,
/// and then Undo would resurrect the occurrence they cancelled.
abstract final class AlertSkipAction {
  static ({CalendarPageEvent apply, CalendarPageEvent undo})? resolve({
    required CalendarEvent event,
    required AlertPayload payload,
    required DateTime today,
  }) {
    if (payload.dayUtc.isBefore(today)) return null;
    final alert = EventAlerts.effectiveFor(event)
        .where((candidate) => candidate.id == payload.alertId)
        .firstOrNull;
    if (alert == null || !alert.enabled) return null;
    if (event.rule is OneTimeRecurrence) {
      if (alert.categoryId != null) {
        // Event-wide by design: the opt-out is one flag per event (D3), so a
        // Skip on one of two inherited alerts silences both — and Undo
        // restores both. Narrowing it to the alert the notice named would
        // mean a new persisted shape, for a notice action.
        return (
          apply: UpdateCalendarEvent(
            event: event.copyWith(categoryAlerts: false),
          ),
          undo: UpdateCalendarEvent(
            event: event.copyWith(categoryAlerts: true),
          ),
        );
      }
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
    if (EventSkips.isSkipped(event.id, day)) return null;
    return (
      apply: SetOccurrenceSkipped(eventId: event.id, day: day),
      undo: ClearOccurrenceSkipped(eventId: event.id, day: day),
    );
  }
}
