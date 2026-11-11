import 'errors.dart';
import 'fleet.dart';
import 'pass_report.dart';
import 'suite.dart';

/// How long one flow — its reseed, prelude and steps together — may run
/// before `pass` calls it a device failure (H7). Every step has a timeout
/// of its own, but a websocket or a process that never answers has none
/// above it; the slowest calendar flow on a worn guest took about 90 s.
const Duration defaultFlowCeiling = Duration(seconds: 360);

/// `--max-minutes`' default: the newest flow already running finishes, the
/// rest are skipped. A worn guest ran the whole calendar suite in 633 s, so
/// a pass this long is stuck, not slow.
const int defaultPassMinutes = 45;

/// How long `pass` waits for an attempt it cancelled at its ceiling to
/// return before anything else drives the device — the evidence, the
/// recovery, the next flow. Its step in flight throws at its next device
/// call, so this is milliseconds; an attempt still out after it ends the
/// pass, since two attempts must never drive the runner at once.
const Duration abandonedFlowGrace = Duration(seconds: 15);

/// What a flow that ran past its [ceiling] fails with; [where] is what it
/// was doing (`step 4`, `its reseed`). It says device failure in so many
/// words, so the red is never read as the app's.
String ceilingMessage(Duration ceiling, String where) {
  final seconds = ceiling.inMilliseconds % 1000 == 0
      ? '${ceiling.inSeconds}'
      : (ceiling.inMilliseconds / 1000).toString();
  return 'device failure: the flow ran past its ceiling of $seconds s '
      '(reseed, prelude and steps together) in $where — the device or the '
      'harness stopped answering';
}

/// Why a flow's failure is the fleet's to answer for rather than the
/// app's (H8), or null when it is the app's: a ceiling, a seed that did
/// not go in, or a step that exited 3 (the device or the harness, never a
/// target that was not found).
String? deviceFailureCause(
  FlowFailure failure, {
  required bool ceiling,
  required bool reseedFailed,
}) {
  if (ceiling) return 'ceiling';
  if (reseedFailed) return 'reseed';
  if (failure.exitCode == exitDevice) return 'device';
  return null;
}

/// What is wrong with the fleet guest [member] as one probe sees it, or
/// null when it is on adb, has finished booting and its qemu runs: the one
/// state a pass can go on running flows against.
String? guestTrouble(FleetMember? member) {
  if (member == null) return 'not listed';
  if (member.heldBy != null) return 'answers as ${member.heldBy}';
  final trouble = switch (member.state) {
    FleetState.device => null,
    // A qemu alive and off adb reads as booting too: a hung guest.
    FleetState.booting => 'off adb or still booting',
    FleetState.offline => 'offline',
    FleetState.stopped => 'not on adb',
    FleetState.notCreated => 'not created',
  };
  if (trouble != null) return trouble;
  if (member.qemu == null) return 'its qemu is gone';
  return null;
}

/// What a pass may still spend on recovering its guest: once per flow,
/// twice per pass, and a `reseed=suite` suite restarts whole at most once.
/// A guest that fails more often than that is not going to be healed by
/// another boot, and a pass that keeps booting hides the fact.
class RecoveryBudget {
  RecoveryBudget({this.perPass = 2});

  final int perPass;
  int _spent = 0;
  bool _suiteRestarted = false;
  final Set<String> _flows = {};

  int get spent => _spent;

  /// Why no recovery is left for [flow] under [reseed], or null when one
  /// is. [perFlow] is true when it is the flow's own allowance that is
  /// spent — its rerun failed again, which is red, and the pass goes on —
  /// and false when the pass's is, which stops the pass. The flow's is
  /// asked first: a rerun that fails after the pass's last recovery is
  /// that flow's red (H8), and the pass stops only when a further flow
  /// needs a recovery the budget no longer has.
  ({String reason, bool perFlow})? refusal(String flow, ReseedMode reseed) {
    if (reseed == ReseedMode.flow && _flows.contains(flow)) {
      return (reason: '$flow already ran again once', perFlow: true);
    }
    if (_spent >= perPass) {
      return (
        reason:
            'the recovery budget is spent ($perPass per pass) — the guest '
            'keeps failing',
        perFlow: false,
      );
    }
    if (reseed == ReseedMode.suite && _suiteRestarted) {
      return (
        reason:
            'the suite already restarted once after a recovery — the guest '
            'keeps failing',
        perFlow: false,
      );
    }
    return null;
  }

  void spend(String flow, ReseedMode reseed) {
    _spent++;
    _flows.add(flow);
    if (reseed == ReseedMode.suite) _suiteRestarted = true;
  }
}

/// What a recovery does under [reseed]: a `reseed=flow` suite runs the
/// failed flow again on a fresh seed; a `reseed=suite` suite starts over
/// from its first flow, because its fixtures are clock-relative and its
/// flows build on each other; a `reseed=none` pass only brings the guest
/// back — the state its flows ran on went with the old guest.
String recoveryAction(ReseedMode reseed) => switch (reseed) {
  ReseedMode.flow => 'rerun',
  ReseedMode.suite => 'restart suite',
  ReseedMode.none => 'stop',
};
