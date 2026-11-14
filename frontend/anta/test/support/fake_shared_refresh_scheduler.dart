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

  /// What the platform says of a slot's work when asked; null — cannot
  /// tell — unless a test scripts it. Each question is recorded in [asked],
  /// apart from [calls]: asking changes nothing.
  bool? Function(SharedRefreshSlot slot)? standing;
  final List<SharedRefreshSlot> asked = [];

  @override
  Future<bool?> stands(SharedRefreshSlot slot) async {
    asked.add(slot);
    return standing?.call(slot);
  }

  /// Recorded as `message:<pair>`, with `:expedited` after it when it was
  /// and `:behind` when it was asked behind the work that runs — otherwise
  /// it takes the place of whatever stands.
  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  }) async {
    _mayFail();
    calls.add(
      'message:$pairId${expedited ? ':expedited' : ''}'
      '${behindRunning ? ':behind' : ''}',
    );
  }
}
