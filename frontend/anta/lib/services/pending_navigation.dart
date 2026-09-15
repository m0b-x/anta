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

/// A reminder was tapped: show the event on its own day, detail sheet open.
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
  /// same alert (a snooze carries its own id) must not be swallowed forever.
  Set<int> _lastDrained = const {};

  bool get isEmpty => _queued.isEmpty;

  int get length => _queued.length;

  /// Queues [intent] unless its [AlertIntent.osId] is already queued or was
  /// handed out by the previous drain. Notifies listeners only when something
  /// was actually added.
  void enqueue(AlertIntent intent) {
    final osId = intent.osId;
    if (_lastDrained.contains(osId)) return;
    if (!_queuedIds.add(osId)) return;
    _queued.add(intent);
    notifyListeners();
  }

  /// Hands over everything queued, in arrival order, and empties the queue.
  List<AlertIntent> drain() {
    if (_queued.isEmpty) return const [];
    final drained = List<AlertIntent>.unmodifiable(_queued);
    _queued.clear();
    _lastDrained = Set<int>.unmodifiable(_queuedIds);
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
  }
}
