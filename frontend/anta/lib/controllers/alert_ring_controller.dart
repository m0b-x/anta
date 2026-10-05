import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../services/alert_gateway.dart';
import '../services/alert_keep_notice.dart';
import '../services/alert_removal_notice.dart';
import '../services/alert_scheduler.dart';
import '../services/calendar_event_service.dart';
import '../services/database_manager.dart';
import '../services/session_chip.dart';

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

  /// Keep's write is on its way to the database.
  bool _keeping = false;

  /// The event is kept, in the database: Keep's write has come back, or
  /// [load] found the event already kept.
  bool _kept = false;

  bool _busy = false;

  bool _stopped = false;

  bool _endedElsewhere = false;

  bool _disposed = false;

  StreamSubscription<AlertRingEnd>? _ringEnded;

  Future<CalendarEvent?> Function(String eventId) _findEvent = _registeredEvent;

  Future<void> Function(CalendarEvent event) _saveEvent = _registeredSave;

  Future<void> Function(AlertPayload payload) _removeEvent = _registeredRemoval;

  /// The database the app is actually in, once it is known. Null until then,
  /// which is what keeps the page from claiming anything about the event —
  /// that Stop removes it, that it can be kept, that it lives elsewhere —
  /// before it knows whose event this is.
  String? get activeDatabase => _activeDatabase;

  /// Whether this alarm belongs to a database other than the one that is open
  /// (**A9**). False while [activeDatabase] is still unknown.
  bool get fromOtherDatabase =>
      _activeDatabase != null && _activeDatabase != payload.database;

  /// Whether the event has been kept: Keep was pressed (**A3**) **and its
  /// write has come back** — or it had been kept already when this ring came
  /// up ([load]). The page says "kept" off this, so it never says so about a
  /// write that is still on its way or that failed.
  bool get keepEvent => _kept;

  /// Whether the event will be deleted when Stop is pressed.
  ///
  /// False from the moment Keep is pressed, before its write has landed: a
  /// Stop that overtakes the write must not delete an event the user has
  /// just asked to keep. True again if that write fails. False as well for a
  /// ring whose event [load] found already kept, whatever its payload says.
  bool get willRemoveEvent =>
      payload.removeAfterAlert && !_keeping && !_kept && !payload.isTest;

  bool get busy => _busy;

  /// Whether Stop has already run. The page pops on it; the flag is what keeps
  /// a double tap from stopping twice.
  bool get stopped => _stopped;

  /// Whether this ring ended by a route the page did not take — Stop or
  /// Snooze on the platform's notification, the Silence-after timeout, or
  /// its entry cancelled under it. The page closes on it, whatever the
  /// cause: a screen still offering Stop for a ring that is over cannot be
  /// left by the back gesture. What such an ending owes — for a cancelled
  /// entry, nothing — is `main.dart`'s to settle, which hears of it too.
  bool get endedElsewhere => _endedElsewhere;

  /// Resolves what the payload cannot carry: which database is open *now*
  /// and, for an alarm whose payload says Stop removes its event, whether the
  /// event still says so. Called once from `initState`.
  ///
  /// The second because a payload is as old as its arming, and [keep] writes
  /// the event and re-arms nothing. A ring armed before a Keep — the same
  /// alarm snoozed on its notification, which the plugin re-arms as it
  /// stands, or a second alarm of the event — still carries the claim, and
  /// the page said "Stop also removes this event" beside a live Keep about an
  /// event kept ten minutes earlier. Stop removed nothing, since the
  /// acknowledgement reads the event's own flag: the sentence was simply
  /// false. Such a ring starts as kept.
  ///
  /// **One notification, one state.** The page fills its remove row the
  /// moment it knows the alarm is the open database's, so the name is held
  /// back until the event has answered: told the name first, the page would
  /// draw the claim and take it back a moment later.
  Future<void> load() async {
    _listenForRingEnd();
    final String active;
    try {
      final manager = await DatabaseManager.getInstance();
      active = manager.getActiveDatabaseName();
    } catch (e) {
      debugPrint('[AlertRingController] active database unknown: $e');
      return;
    }
    if (await _keptBeforeThisRing(active)) _kept = true;
    _activeDatabase = active;
    // The lookup can outlast the page, which disposes the controller it made.
    if (!_disposed) notifyListeners();
  }

  /// Whether the event this ring says Stop removes no longer carries the
  /// flag, in [active] — the open database, which is not published yet.
  ///
  /// Asked only where the claim would be drawn: for an alarm of the open
  /// database that is still one Stop removes. Another database's alarm is
  /// never looked up, for the reason [_resolveEvent] gives — the event with
  /// that id here is somebody else's. It only reads, and it only ever takes
  /// the claim away: an event that is not there, or a lookup that throws,
  /// leaves the payload's word standing.
  Future<bool> _keptBeforeThisRing(String active) async {
    if (!willRemoveEvent || active != payload.database) return false;
    try {
      final event = await _findEvent(payload.eventId);
      return event != null && !event.removeAfterAlert;
    } catch (e) {
      debugPrint('[AlertRingController] event lookup at ring start failed: $e');
      return false;
    }
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
    _disposed = true;
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
  /// at 07:20 for a session already acknowledged. Then the session chip
  /// (OS-5), while the event is still there to say when the session ends.
  /// Last, A3's removal.
  ///
  /// **Whether that removal happens is decided at the press, and may only
  /// narrow afterwards.** The steps before it take a while, and a Keep whose
  /// write is still out when Stop is pressed has already said "remove
  /// nothing". If that write then fails, [keep] takes the press back — for
  /// the *next* Stop: read only at the end, [willRemoveEvent] would have
  /// handed the removal to this one as well, and removed an event the user
  /// asked to keep a moment before stopping. It is read again at the end for
  /// the other direction alone: an event that turned out to be kept in the
  /// meantime is not removed.
  Future<void> stop() async {
    if (_busy || _stopped) return;
    final removeAtPress = willRemoveEvent;
    _busy = true;
    notifyListeners();
    try {
      final scheduler = await AlertScheduler.getInstance();
      await scheduler.stop(payload.osId);
      await scheduler.cancelSnoozeForAlert(payload.alertId, payload.dayUtc);
    } catch (e) {
      debugPrint('[AlertRingController] stop failed: $e');
    }
    await SessionChip.instance.show(payload);
    if (removeAtPress && willRemoveEvent) await _removeEvent(payload);
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
  ///
  /// Three moments, and the page draws each one. From the press
  /// [willRemoveEvent] is false, so nothing Stop does in the meantime removes
  /// the event. [keepEvent] turns true only when the write has come back —
  /// until then "kept" would be a promise, and a Stop on the notification
  /// reads the event's own flag, not this one. And a write that throws, or
  /// that finds no event to write to, takes it all back: [willRemoveEvent]
  /// is true again and Keep can be pressed again, because the event is still
  /// one that Stop removes.
  ///
  /// The calendar is told only once the write is in — the service tells
  /// nobody, and the bloc above the calendar would go on showing the event
  /// as "removed after it rings".
  Future<void> keep() async {
    if (!willRemoveEvent) return;
    _keeping = true;
    notifyListeners();
    var saved = false;
    try {
      final event = await _resolveEvent();
      if (event != null) {
        await _saveEvent(event.copyWith(removeAfterAlert: false));
        saved = true;
      }
    } catch (e) {
      debugPrint('[AlertRingController] keep failed: $e');
    }
    _keeping = false;
    _kept = saved;
    if (saved) AlertKeepNotice.instance.publish();
    // The page may have closed under the write — Stop does not wait for it —
    // and it disposes the controller it made.
    if (!_disposed) notifyListeners();
  }

  /// Gets the phone past its lock screen before an action that leads **into**
  /// the app — Open event, the database switch — and answers whether it is
  /// unlocked now.
  ///
  /// Asked first and with the ring still going, on purpose: the alarm page is
  /// the only thing allowed above a locked keyguard, so the PIN prompt has to
  /// come up over it. Stopping first would end the ring, send the app back
  /// behind the lock screen, and leave the event opening where nobody can see
  /// it. A refusal leaves the user on the page with the alarm still theirs to
  /// stop. True wherever there is no lock screen to get past.
  Future<bool> unlock() async {
    if (!GetIt.I.isRegistered<AlertGateway>()) return true;
    return GetIt.I<AlertGateway>().dismissLockScreen();
  }

  /// Makes this alarm's database the active one. The caller shows the dialog
  /// that says so and closes the app; nothing switches underneath a running
  /// process.
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

  /// A3 through the one acknowledgement path a Stop on the platform's own
  /// alarm notification also takes ([AlertAcknowledgement]): the delete, the
  /// Undo notice **and the reconcile after it** — [stop] re-planned the event
  /// before the delete, so without that second pass a one-time event with
  /// two alarms would keep its later one armed in the OS for an event that
  /// no longer exists. The reminder tier never takes it: its Done runs with
  /// no database, and its tap only opens the event.
  static Future<void> _registeredRemoval(AlertPayload payload) =>
      AlertAcknowledgement.apply(payload);

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
    if (activeDatabase != payload.database) return null;
    return _findEvent(payload.eventId);
  }

  static Future<CalendarEvent?> _registeredEvent(String eventId) async {
    try {
      final service = await CalendarEventService.getInstance();
      for (final event in service.events) {
        if (event.id == eventId) return event;
      }
    } catch (e) {
      debugPrint('[AlertRingController] event lookup failed: $e');
    }
    return null;
  }

  static Future<void> _registeredSave(CalendarEvent event) async =>
      (await CalendarEventService.getInstance()).upsert(event);

  /// Swaps the two things [keep] reaches a database through — finding the
  /// event, saving it — for test doubles. Without them the write cannot be
  /// held in flight or made to fail, and what [keep] promises at each of its
  /// three moments is exactly what would go untested. [load] asks after the
  /// event through the same lookup.
  ///
  /// [removeEvent] stands in for the removal [stop] ends in, for the suite
  /// that counts them: whether a Stop removes is decided against a Keep that
  /// may still be in flight, and the real removal needs a database to show
  /// that it ran. Left out, Stop removes as it ships.
  @visibleForTesting
  void configureForTesting({
    required Future<CalendarEvent?> Function(String eventId) findEvent,
    required Future<void> Function(CalendarEvent event) saveEvent,
    Future<void> Function(AlertPayload payload)? removeEvent,
  }) {
    _findEvent = findEvent;
    _saveEvent = saveEvent;
    if (removeEvent != null) _removeEvent = removeEvent;
  }
}
