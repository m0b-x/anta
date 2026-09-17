import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../services/alert_gateway.dart';
import '../services/alert_removal_notice.dart';
import '../services/alert_scheduler.dart';
import '../services/calendar_event_service.dart';
import '../services/database_manager.dart';

/// Everything the alarm page does, with no widgets in it.
///
/// A page-owned plain class in the `NoteSaveCoordinator` shape rather than a
/// BLoC: there is one screen, one payload and four buttons, and a ring is not
/// a stream of events worth routing. It is a [ChangeNotifier] only because the
/// database name and the "keep this event" decision both arrive after the
/// first frame.
///
/// **Service-direct**, like `CalendarCategoriesPage`: it talks to
/// `AlertScheduler` and `CalendarEventService` without a bloc in between, and
/// every call is best-effort — an alarm ringing in a process that cannot open
/// a database must still be stoppable, which is the whole reason the page
/// renders from [payload] alone.
class AlertRingController extends ChangeNotifier {
  AlertRingController({required this.payload});

  /// What the platform handed over. The single source for everything drawn.
  final AlertPayload payload;

  String? _activeDatabase;

  bool _keepEvent = false;

  bool _busy = false;

  bool _stopped = false;

  bool _endedElsewhere = false;

  StreamSubscription<AlertRingEnd>? _ringEnded;

  /// The database the app is actually in, once it is known. Null until then,
  /// which is what keeps the A9 chip from flashing on every ring.
  String? get activeDatabase => _activeDatabase;

  /// Whether this alarm belongs to a database other than the one that is open
  /// (**A9**). False while [activeDatabase] is still unknown.
  bool get fromOtherDatabase =>
      _activeDatabase != null && _activeDatabase != payload.database;

  /// Whether the user asked to keep an event that would otherwise be removed
  /// once the alarm is acknowledged (**A3**).
  bool get keepEvent => _keepEvent;

  /// Whether the event will be deleted when Stop is pressed.
  bool get willRemoveEvent =>
      payload.removeAfterAlert && !_keepEvent && !payload.isTest;

  bool get busy => _busy;

  /// Whether Stop has already run. The page pops on it; the flag is what keeps
  /// a double tap from stopping twice.
  bool get stopped => _stopped;

  /// Whether this ring ended by a route the page did not take — Stop on the
  /// platform's notification, or the Silence-after timeout. The page closes on
  /// it: a screen still offering Stop for a ring that is over cannot be left
  /// by the back gesture, and `main.dart` has already settled the ring.
  bool get endedElsewhere => _endedElsewhere;

  /// Resolves the one thing the payload cannot carry: which database is open
  /// *now*. Called once from `initState`.
  Future<void> load() async {
    _listenForRingEnd();
    try {
      final manager = await DatabaseManager.getInstance();
      _activeDatabase = manager.getActiveDatabaseName();
    } catch (e) {
      debugPrint('[AlertRingController] active database unknown: $e');
      return;
    }
    notifyListeners();
  }

  void _listenForRingEnd() {
    if (_ringEnded != null || !GetIt.I.isRegistered<AlertGateway>()) return;
    _ringEnded = GetIt.I<AlertGateway>().ringEnded.listen((end) {
      if (end.payload.osId != payload.osId || _stopped) return;
      _stopped = true;
      _endedElsewhere = true;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    unawaited(_ringEnded?.cancel());
    super.dispose();
  }

  /// Stops the ring and settles the registration.
  ///
  /// Three things, in order. The scheduler's [AlertScheduler.stop] silences the
  /// platform, marks the row `stopped` and re-plans the event so the next
  /// occurrence is armed again. Then any **standing snooze of the same alert on
  /// the same day** is cancelled — `stop` deliberately does not, because it is
  /// about one platform entry while this is about the user's intent: an alert
  /// snoozed at 07:00 and stopped at its 07:10 ring must not ring a third time
  /// at 07:20 for a session already acknowledged. Last, A3's removal.
  Future<void> stop() async {
    if (_busy || _stopped) return;
    _busy = true;
    notifyListeners();
    try {
      final scheduler = await AlertScheduler.getInstance();
      await scheduler.stop(payload.osId);
      await scheduler.cancelSnoozeForAlert(payload.alertId, payload.dayUtc);
    } catch (e) {
      debugPrint('[AlertRingController] stop failed: $e');
    }
    if (willRemoveEvent) await _removeEvent();
    _stopped = true;
    _busy = false;
    notifyListeners();
  }

  /// Re-arms this alert [AlertPayload.snoozeMinutes] from now, as a
  /// registration of its own (**A8**).
  Future<void> snooze() async {
    if (_busy || _stopped) return;
    _busy = true;
    notifyListeners();
    try {
      await (await AlertScheduler.getInstance()).snooze(
        payload.osId,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[AlertRingController] snooze failed: $e');
    }
    _stopped = true;
    _busy = false;
    notifyListeners();
  }

  /// Clears the event's "remove after it rings" flag **before** Stop, so an
  /// alarm the user wants to keep survives being acknowledged.
  ///
  /// Persisted rather than held in memory: the page can be dismissed by the
  /// system at any moment while an alarm is ringing, and a decision that only
  /// lived here would be lost with it.
  Future<void> keep() async {
    if (_keepEvent) return;
    _keepEvent = true;
    notifyListeners();
    final event = await _resolveEvent();
    if (event == null) return;
    try {
      final service = await CalendarEventService.getInstance();
      await service.upsert(event.copyWith(removeAfterAlert: false));
    } catch (e) {
      debugPrint('[AlertRingController] keep failed: $e');
    }
  }

  /// Makes this alarm's database the active one. The caller shows the app's
  /// existing restart dialog; nothing switches underneath a running process.
  Future<bool> activateDatabase() async {
    try {
      final manager = await DatabaseManager.getInstance();
      await manager.setActiveDatabaseName(payload.database);
      return true;
    } catch (e) {
      debugPrint('[AlertRingController] database switch failed: $e');
      return false;
    }
  }

  /// A3 through the one acknowledgement path the reminder tier's tap and Done
  /// also take: the delete, the Undo notice **and the reconcile after it** —
  /// [stop] re-planned the event before the delete, so without that second
  /// pass a one-time event with two alarms would keep its later one armed in
  /// the OS for an event that no longer exists.
  Future<void> _removeEvent() => AlertAcknowledgement.apply(payload);

  /// The event this ring belongs to, or null when it is not this database's to
  /// touch.
  ///
  /// The database check is the load-bearing half, and it is deliberately
  /// **positive**: an alarm from *work* can ring while *personal* is open, and
  /// deleting "the event with that id" would then delete whatever happens to
  /// carry it here. An unresolved [activeDatabase] therefore reads as "not
  /// ours" rather than as "probably ours" — a ring that fails to delete an
  /// event is a nuisance, one that deletes the wrong event is not.
  Future<CalendarEvent?> _resolveEvent() async {
    if (payload.isTest) return null;
    if (_activeDatabase != payload.database) return null;
    try {
      final service = await CalendarEventService.getInstance();
      for (final event in service.events) {
        if (event.id == payload.eventId) return event;
      }
    } catch (e) {
      debugPrint('[AlertRingController] event lookup failed: $e');
    }
    return null;
  }
}
