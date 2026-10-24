import 'dart:async';

import 'package:anta/services/sync/sync_scheduler.dart';

/// A [SyncScheduler] whose timers fire only when the test says so: the
/// engine's suites run Drift, which never completes under `FakeAsync`, so
/// time is advanced by firing the recorded timers instead.
class ManualSyncScheduler implements SyncScheduler {
  /// Every timer scheduled, in order, fired and cancelled ones included.
  final List<ManualSyncTimer> timers = [];

  /// The delays of the timers still waiting, in schedule order.
  List<Duration> get pending => [
    for (final timer in timers)
      if (timer.isActive) timer.delay,
  ];

  @override
  Timer schedule(Duration delay, void Function() callback) {
    final timer = ManualSyncTimer._(delay, callback);
    timers.add(timer);
    return timer;
  }

  /// Fires every waiting timer of [delay] — every waiting timer when null —
  /// in schedule order, and returns how many fired.
  int fire([Duration? delay]) {
    final due = [
      for (final timer in timers)
        if (timer.isActive && (delay == null || timer.delay == delay)) timer,
    ];
    for (final timer in due) {
      timer._fire();
    }
    return due.length;
  }
}

class ManualSyncTimer implements Timer {
  final Duration delay;
  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  ManualSyncTimer._(this.delay, this._callback);

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void _fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }
}
