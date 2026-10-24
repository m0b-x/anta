import 'dart:async';

/// Where the engine's deferred work — the push debounce, the back-off and
/// quota retries — gets its timers. A seam so tests fire them by hand: Drift
/// never completes under `FakeAsync`, so the engine's suites cannot fake
/// time itself.
abstract interface class SyncScheduler {
  /// Runs [callback] once after [delay], unless the returned timer is
  /// cancelled first.
  Timer schedule(Duration delay, void Function() callback);
}

/// The app's scheduler: a plain [Timer].
class TimerSyncScheduler implements SyncScheduler {
  const TimerSyncScheduler();

  @override
  Timer schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}
