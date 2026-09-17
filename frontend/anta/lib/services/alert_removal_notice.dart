import 'package:flutter/foundation.dart';

import '../constants/event_alerts.dart';
import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import 'alert_scheduler.dart';
import 'calendar_event_service.dart';
import 'database_manager.dart';

/// An event deleted because one of its alerts was acknowledged (**A3**), held
/// with everything needed to put it back.
typedef RemovedEventNotice = ({
  CalendarEvent event,
  List<EventAlert> alerts,
  DateTime at,
});

/// Publishes the events that A3 deleted, so the calendar can offer Undo.
///
/// A [ChangeNotifier] holding **one** pending notice rather than a stream: the
/// page that shows the snackbar is usually not even mounted when the removal
/// happens — an alarm page is over it, or the app was launched by the tap that
/// removed it — so the notice has to wait somewhere until there is a calendar
/// to show it on. Not in GetIt for the same reason [PendingNavigationQueue] is
/// not: the ring path reaches it from places that hold no container, and it
/// holds no database reference of its own.
///
/// The alerts ride along because the delete cascaded them: `upsert` resurrects
/// the event's own tombstone, but an alert row it tombstoned in the same
/// transaction would stay dead, and an event restored without the alarm that
/// removed it is not the event the user had.
class AlertRemovalNotice extends ChangeNotifier {
  static final AlertRemovalNotice instance = AlertRemovalNotice();

  /// How long a notice is worth showing. Beyond it the snackbar would be an
  /// offer to undo something the user has stopped thinking about — the ring
  /// they stopped was minutes ago and the calendar was somewhere else — so the
  /// notice is dropped rather than queued indefinitely.
  static const Duration freshness = Duration(minutes: 5);

  /// The clock the window is measured against. A seam, not a setting: a queue
  /// that reads the wall clock cannot be tested for either half of its rule.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  RemovedEventNotice? _pending;

  /// Whether there is a fresh notice waiting. Cheap enough for a listener.
  bool get hasPending => _pending != null;

  void publish(CalendarEvent event, List<EventAlert> alerts) {
    _pending = (event: event, alerts: alerts, at: clock());
    notifyListeners();
  }

  /// Hands over the pending notice and clears it, or returns null when there
  /// is none — or when it is older than [freshness].
  RemovedEventNotice? take() {
    final notice = _pending;
    _pending = null;
    if (notice == null) return null;
    if (clock().difference(notice.at) > freshness) return null;
    return notice;
  }

  /// Drops everything. Test-only: the notice is a process-global static, so a
  /// suite that leaves one behind would show a snackbar in the next one.
  @visibleForTesting
  void clearForTesting() {
    _pending = null;
    clock = DateTime.now;
  }
}

/// Applies A3 to one acknowledged alert: the event is soft-deleted, its alerts
/// go with it, the platform is re-reconciled and the calendar is told so it can
/// offer Undo.
///
/// Called from the alarm page's Stop and from the reminder tier's tap and Done
/// — the three acknowledgements §3.5 names. Every one of them is a user action
/// in the foreground; the background isolate that handles Done while the app is
/// dead cannot reach a database at all, so an event removed that way waits for
/// the next tap or the next ring.
///
/// The database check is the load-bearing half, and it is deliberately
/// **positive**: an alarm from *work* can ring while *personal* is open, and
/// deleting "the event with that id" would then delete whatever happens to
/// carry it here.
abstract final class AlertAcknowledgement {
  /// Returns whether the event was removed, so a caller about to open it can
  /// land on its day instead of on a detail sheet for something that is gone.
  static Future<bool> apply(AlertPayload payload) async {
    if (!payload.removeAfterAlert || payload.isTest) return false;
    try {
      final manager = await DatabaseManager.getInstance();
      if (manager.getActiveDatabaseName() != payload.database) return false;
      final service = await CalendarEventService.getInstance();
      CalendarEvent? target;
      for (final event in service.events) {
        if (event.id != payload.eventId) continue;
        target = event;
        break;
      }
      if (target == null) return false;
      // Captured **before** the delete: the cascade tombstones the alert rows,
      // and the facade is republished from what survives.
      final alerts = List<EventAlert>.of(EventAlerts.alertsFor(target.id));
      await service.deleteById(target.id);
      AlertRemovalNotice.instance.publish(target, alerts);
      await AlertScheduler.reconcileEventById(
        target.id,
        AlertReconcileReason.ringHandled,
      );
      return true;
    } catch (e) {
      debugPrint('[AlertAcknowledgement] removal failed: $e');
      return false;
    }
  }
}
