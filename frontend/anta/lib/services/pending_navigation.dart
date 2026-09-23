import 'package:flutter/foundation.dart';

import '../models/alert_payload.dart';

/// Where a tap on an alert should land (**A12**).
///
/// Sealed so a new destination has to be handled everywhere it is switched on,
/// rather than silently falling through to "open the calendar".
sealed class AlertIntent {
  const AlertIntent();

  /// What [PendingNavigationQueue] dedupes on. A cold-start tap is delivered
  /// twice by the notification plugin — once through the response callback
  /// and once through the launch details — within a few milliseconds, and an
  /// intent that carries a payload keys on its os id so the two halves cannot
  /// disagree; an intent about no entry at all keys on a constant of its own.
  Object get dedupeKey;

  /// Whether a repeat of [dedupeKey] inside
  /// [PendingNavigationQueue.doubleDeliveryWindow] of the last drain is the
  /// second half of a double delivery rather than a new request. True for
  /// everything the platform can hand over twice; false for a foreground
  /// gesture the user may well repeat at once.
  bool get collapsesAfterDrain => true;
}

/// An intent about one platform entry, carrying the payload it rang or was
/// tapped under.
sealed class AlertEntryIntent extends AlertIntent {
  final AlertPayload payload;

  const AlertEntryIntent({required this.payload});

  /// The platform entry the tap came from. Read off the payload so the two
  /// halves of a double delivery cannot disagree.
  int get osId => payload.osId;

  @override
  Object get dedupeKey => osId;
}

/// A reminder or a "Missed" notice was tapped: show the event on its own day,
/// detail sheet open.
///
/// Never an acknowledgement in the A3 sense. "Remove after it rings" is about
/// the **alarm** being stopped; someone tapping a "10 min before" reminder is
/// looking at the event, and deleting it under them would also cancel the very
/// alarm the switch was set for.
final class OpenEventIntent extends AlertEntryIntent {
  const OpenEventIntent({required super.payload});
}

/// An alarm is ringing (or was tapped): show the alarm page.
///
/// The alarm page is deliberately **not** a `NavDestination`: a restored last
/// location must never reopen a ring that is long over.
final class OpenAlarmIntent extends AlertEntryIntent {
  const OpenAlarmIntent({required super.payload});
}

/// Skip on an upcoming-alarm notice (OS-3, **B6**): the next fire of this
/// alarm is not wanted — a recurring event's occurrence is cancelled, a
/// one-time event's alert switched off — and the calendar says so with an
/// Undo.
///
/// A foreground intent by design: the background isolate never writes the
/// database, so Skip opens the app and the calendar page applies it. Keyed
/// apart from the notice's Open, which shares the os id.
final class SkipNextFireIntent extends AlertEntryIntent {
  const SkipNextFireIntent({required super.payload});

  @override
  Object get dedupeKey => 'skip:$osId';
}

/// *Open note* on the session chip (OS-5, **B8**): the session an alarm was
/// stopped for is under way and the user wants what they wrote for it — the
/// event's linked note when it has one, else the event on its day.
///
/// Keyed apart from the alarm's other intents, which share the os id: a chip
/// tapped while the ring's own page is still queued is a second destination,
/// not a duplicate of the first.
final class OpenSessionIntent extends AlertEntryIntent {
  const OpenSessionIntent({required super.payload});

  @override
  Object get dedupeKey => 'session:$osId';

  /// Decodes what the activity hands over — the payload JSON the chip was
  /// posted with — and refuses anything else, so a malformed extra opens
  /// nothing rather than something.
  static OpenSessionIntent? fromPlatform(Object? arguments) {
    if (arguments is! String) return null;
    final payload = AlertPayload.decode(arguments);
    return payload == null ? null : OpenSessionIntent(payload: payload);
  }
}

/// The phone's own "next alarm" surface was tapped — the lock-screen line or
/// Quick Settings, which launch the show intent every alarm-clock entry
/// carries (`AlarmService.ACTION_SHOW`, Patch 1 of the `alarm` fork): show the
/// Alerts hub (**B2**).
///
/// Payload-less, because the phone is saying "you have an alarm" rather than
/// naming one; the answer is the list that holds every armed alarm and offers
/// the switch and *Cancel snooze*. It dedupes against another hub intent and
/// against nothing else.
final class OpenAlertsHubIntent extends AlertIntent {
  const OpenAlertsHubIntent();

  /// The one key every hub intent shares. A string, so it can never collide
  /// with an os id.
  static const String key = 'alerts-hub';

  @override
  Object get dedupeKey => key;
}

/// The Quick Settings tile or the launcher shortcut was tapped (OS-5, **B9**):
/// open the quick-alarm sheet, on today.
///
/// Payload-less like [OpenAlertsHubIntent], and for the same reason — the
/// phone is asking for a new alarm, not naming one. It dedupes against another
/// quick-alarm intent (the activity's own record and the warm push of one
/// tap) and against nothing else.
final class QuickAlarmIntent extends AlertIntent {
  const QuickAlarmIntent();

  static const String key = 'quick-alarm';

  @override
  Object get dedupeKey => key;

  /// A tile tapped again five seconds after the sheet it opened was
  /// dismissed is a second request, not an echo: one tap is delivered once
  /// (the activity's record for a cold start, the push for a warm one), and
  /// a batch already collapses the two if they ever met.
  @override
  bool get collapsesAfterDrain => false;
}

/// Holds alert taps that arrive before there is a `Navigator` to push onto.
///
/// A cold-start tap is delivered while `main()` is still running: the app has
/// no first frame, `AppNavigator.navigatorKey.currentState` is null, and the
/// navigator accessor force-unwraps it. Pushing from the callback therefore
/// crashes the launch it was supposed to complete. Everything enqueues here
/// instead, and `_MyAppState` drains once the navigator exists — after the
/// restore post-frame callback, so an alert wins over the remembered location
/// rather than landing under it.
///
/// A [ChangeNotifier] rather than a queue the app polls: an intent can arrive
/// long after launch (a warm tap), and the listener is what turns that into a
/// drain without anything having to run every frame.
class PendingNavigationQueue extends ChangeNotifier {
  /// The app-wide queue. Not in GetIt: the platform callbacks that fill it are
  /// static entry points with no access to a container, and it holds no
  /// database reference, so it is outside the `DatabaseLifecycle` contract
  /// too.
  static final PendingNavigationQueue instance = PendingNavigationQueue();

  final List<AlertIntent> _queued = [];

  /// Dedupe keys currently queued. Cleared into [_lastDrained] on every drain.
  final Set<Object> _queuedKeys = {};

  /// Keys handed out by the previous drain, kept so the second half of a
  /// double delivery is still recognised when the first half has already been
  /// drained. Only the last batch is remembered — a genuinely new ring of the
  /// same alert must not be swallowed forever.
  Set<Object> _lastDrained = const {};

  /// When [_lastDrained] was filled. Paired with [doubleDeliveryWindow]
  /// because "the last batch" alone is not a short enough memory: the os id of
  /// a snooze is a hash of (database, alert, day, kind), so snoozing the same
  /// alert twice on the same day re-arms it under the **same** id — and with
  /// no expiry the second ring is dropped as a duplicate of the first, hours
  /// later, with the phone making noise and no page to stop it.
  DateTime? _lastDrainedAt;

  /// How long a drained id keeps swallowing a repeat.
  ///
  /// The double delivery this exists for is the notification plugin's
  /// cold-start tap, measured at 8 ms apart (§10.1); a second of slack is two
  /// orders of magnitude of headroom, and anything arriving later is a new
  /// ring rather than an echo of an old one.
  static const Duration doubleDeliveryWindow = Duration(seconds: 5);

  /// The clock the window is measured against. A seam, not a setting: a queue
  /// that reads the wall clock cannot be tested for either half of its rule.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool get isEmpty => _queued.isEmpty;

  int get length => _queued.length;

  /// Queues [intent] unless its [AlertIntent.dedupeKey] is already queued or
  /// was handed out by the previous drain. Notifies listeners only when
  /// something was actually added.
  void enqueue(AlertIntent intent) {
    final key = intent.dedupeKey;
    if (intent.collapsesAfterDrain && _isEcho(key)) return;
    if (!_queuedKeys.add(key)) return;
    _queued.add(intent);
    notifyListeners();
  }

  /// Whether [key] is the second half of a delivery already handed over, as
  /// opposed to a genuinely new ring that happens to share an id.
  bool _isEcho(Object key) {
    if (!_lastDrained.contains(key)) return false;
    final at = _lastDrainedAt;
    if (at == null) return false;
    return clock().difference(at) < doubleDeliveryWindow;
  }

  /// Hands over everything queued, in arrival order, and empties the queue.
  List<AlertIntent> drain() {
    if (_queued.isEmpty) return const [];
    final drained = List<AlertIntent>.unmodifiable(_queued);
    _queued.clear();
    _lastDrained = Set<Object>.unmodifiable(_queuedKeys);
    _lastDrainedAt = clock();
    _queuedKeys.clear();
    return drained;
  }

  /// Drops everything, dedupe memory included. Test-only: the queue is a
  /// process-global static, so a suite that leaves an intent behind would
  /// navigate in the next one.
  @visibleForTesting
  void clearForTesting() {
    _queued.clear();
    _queuedKeys.clear();
    _lastDrained = const {};
    _lastDrainedAt = null;
    clock = DateTime.now;
  }
}
