import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';

/// A platform that records what it was asked, in order.
///
/// From the app, with no work running: `schedule:<delay>` and `cancel`.
/// While the work in a slot runs: `schedule@<slot written>:<delay>` and
/// `cancel@<slot cancelled>` — always the slot that is **not** running.
class FakeSharedRefreshScheduler implements SharedRefreshScheduler {
  final List<String> calls = [];

  /// The delays of the `schedule` calls alone.
  final List<Duration> scheduled = [];

  int cancels = 0;

  /// The next call throws once, as a platform that could not be reached.
  bool failNext = false;

  void _mayFail() {
    if (!failNext) return;
    failNext = false;
    throw StateError('no platform');
  }

  @override
  Future<void> schedule(Duration delay, {SharedRefreshSlot? runningIn}) async {
    _mayFail();
    calls.add(
      runningIn == null
          ? 'schedule:$delay'
          : 'schedule@${runningIn.other.name}:$delay',
    );
    scheduled.add(delay);
  }

  @override
  Future<void> cancel({SharedRefreshSlot? runningIn}) async {
    _mayFail();
    calls.add(runningIn == null ? 'cancel' : 'cancel@${runningIn.other.name}');
    cancels++;
  }

  /// Recorded as `message:<pair>`, with `:expedited` after it when it was.
  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
  }) async {
    _mayFail();
    calls.add('message:$pairId${expedited ? ':expedited' : ''}');
  }
}
