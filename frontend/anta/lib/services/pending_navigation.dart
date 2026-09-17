import 'package:flutter/foundation.dart';

import '../models/alert_payload.dart';

/// Where a tap on an alert should land (**A12**).
///
/// Sealed so a new destination has to be handled everywhere it is switched on,
/// rather than silently falling through to "open the calendar".
sealed class AlertIntent {
  final AlertPayload payload;

  const AlertIntent({required this.payload});

  /// The platform entry the tap came from. Also the dedupe key: a cold-start
  /// tap is delivered twice by the notification plugin — once through the
  /// response callback and once through the launch details — within a few
  /// milliseconds. Read off the payload so the two cannot disagree.
  int get osId => payload.osId;
}

/// A reminder or a "Missed" notice was tapped: show the event on its own day,
/// detail sheet open.
///
/// Never an acknowledgement in the A3 sense. "Remove after it rings" is about
/// the **alarm** being stopped; someone tapping a "10 min before" reminder is
/// looking at the event, and deleting it under them would also cancel the very
/// alarm the switch was set for.
final class OpenEventIntent extends AlertIntent {
  const OpenEventIntent({required super.payload});
}

/// An alarm is ringing (or was tapped): show the alarm page.
///
/// Defined now and routed to nothing — the page itself is Session 3. The
/// alarm page is deliberately **not** a `NavDestination`: a restored last
/// location must never reopen a ring that is long over.
final class OpenAlarmIntent extends AlertIntent {
  const OpenAlarmIntent({required super.payload});
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

  /// Ids currently queued. Cleared into [_lastDrained] on every drain.
  final Set<int> _queuedIds = {};

  /// Ids handed out by the previous drain, kept so the second half of a
  /// double delivery is still recognised when the first half has already been
  /// drained. Only the last batch is remembered — a genuinely new ring of the
  /// same alert must not be swallowed forever.
  Set<int> _lastDrained = const {};

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

  /// Queues [intent] unless its [AlertIntent.osId] is already queued or was
  /// handed out by the previous drain. Notifies listeners only when something
  /// was actually added.
  void enqueue(AlertIntent intent) {
    final osId = intent.osId;
    if (_isEcho(osId)) return;
    if (!_queuedIds.add(osId)) return;
    _queued.add(intent);
    notifyListeners();
  }

  /// Whether [osId] is the second half of a delivery already handed over, as
  /// opposed to a genuinely new ring that happens to share an id.
  bool _isEcho(int osId) {
    if (!_lastDrained.contains(osId)) return false;
    final at = _lastDrainedAt;
    if (at == null) return false;
    return clock().difference(at) < doubleDeliveryWindow;
  }

  /// Hands over everything queued, in arrival order, and empties the queue.
  List<AlertIntent> drain() {
    if (_queued.isEmpty) return const [];
    final drained = List<AlertIntent>.unmodifiable(_queued);
    _queued.clear();
    _lastDrained = Set<int>.unmodifiable(_queuedIds);
    _lastDrainedAt = clock();
    _queuedIds.clear();
    return drained;
  }

  /// Drops everything, dedupe memory included. Test-only: the queue is a
  /// process-global static, so a suite that leaves an intent behind would
  /// navigate in the next one.
  @visibleForTesting
  void clearForTesting() {
    _queued.clear();
    _queuedIds.clear();
    _lastDrained = const {};
    _lastDrainedAt = null;
    clock = DateTime.now;
  }
}
