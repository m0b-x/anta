import 'dart:async';

import 'package:anta/controllers/alert_ring_controller.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/utils/alert_planner.dart';
import 'package:anta/utils/digest_planner.dart';

/// A gateway standing in for a phone behind its lock screen: it counts the
/// unlock requests and answers each the same way.
class LockedGateway extends NoOpAlertGateway {
  LockedGateway({required this.unlocks});

  final bool unlocks;

  int unlockRequests = 0;

  @override
  Future<bool> dismissLockScreen() async {
    unlockRequests++;
    return unlocks;
  }
}

/// A gateway whose only behaviour is reporting that a ring ended elsewhere.
class EndingGateway extends NoOpAlertGateway {
  final StreamController<AlertRingEnd> ends =
      StreamController<AlertRingEnd>.broadcast();

  @override
  Stream<AlertRingEnd> get ringEnded => ends.stream;
}

/// A gateway that writes down every call that would reach the platform — an
/// arm, a cancel, a stopped ring, the session chip, the unlock — for the
/// guide's preview, which must make none.
class RecordingGateway extends NoOpAlertGateway {
  final List<String> calls = <String>[];

  @override
  Future<bool> schedule(
    PlannedFire fire,
    AlertPayload payload, {
    DateTime? noticeAt,
  }) async {
    calls.add('schedule');
    return true;
  }

  @override
  Future<bool> scheduleDigest(PlannedDigest fire, AlertPayload payload) async {
    calls.add('scheduleDigest');
    return true;
  }

  @override
  Future<void> cancel(int osId) async => calls.add('cancel');

  @override
  Future<void> stopRinging(int osId) async => calls.add('stopRinging');

  @override
  Future<void> showMissed(AlertPayload payload) async =>
      calls.add('showMissed');

  @override
  Future<bool> showSessionChip(
    AlertPayload payload, {
    required DateTime startedAt,
    DateTime? endsAt,
    int? progress,
    bool refresh = false,
    bool linkedNote = false,
  }) async {
    calls.add('showSessionChip');
    return false;
  }

  @override
  Future<void> clearSessionChip() async => calls.add('clearSessionChip');

  @override
  Future<bool> dismissLockScreen() async {
    calls.add('dismissLockScreen');
    return true;
  }
}

/// A controller that already knows which database is open.
///
/// The real one asks `DatabaseManager`, which needs `path_provider`; what
/// that answer decides — the Open row's face, whether the remove row is
/// filled — is the one thing on the page the payload cannot decide by
/// itself, so the answer is supplied rather than the whole harness stood up.
/// Everything else is the real controller, [AlertRingController.keep]
/// included.
class FakeRingController extends AlertRingController {
  FakeRingController(AlertPayload payload, {required this.active})
    : super(payload: payload);

  final String active;

  @override
  String? get activeDatabase => active;

  @override
  bool get fromOtherDatabase => active != payload.database;

  @override
  Future<void> load() async {}
}

/// One thing the alarm page can ask of its controller.
enum RingRequest { stop, snooze, keep, unlock, activateDatabase }

/// A controller the suite scripts and reads back, for what the page does
/// *with* its controller rather than what the controller then does.
///
/// It writes down every request in the order the page made it, answers the two
/// questions that lead out of the page — the unlock and the database switch —
/// the way the test says, and can keep a Stop, a Snooze, a Keep or an unlock
/// in flight, which is the only way to look at the page in between: the real
/// controller's calls all fail fast in a test and are over within the same
/// frame.
///
/// **The database is unknown until it is resolved**, as it is on a phone,
/// where the name comes back from a read a frame after the page is up. With
/// `active` the page's own `load` resolves it, one turn of the event loop
/// after the first build; without it nothing does until [resolveDatabase],
/// which is how a suite looks at the page before the answer.
///
/// **No guard of its own.** The real controller ignores a second Stop, Snooze
/// or Keep; this one records it, so a suite sees what the *page* let through.
/// Nothing here reaches a service, a database or a gateway.
class ScriptedRingController extends AlertRingController {
  ScriptedRingController(
    AlertPayload payload, {
    String? active,
    this.unlocks = true,
    this.switches = true,
  }) : _loads = active,
       super(payload: payload);

  /// What [load] resolves the open database to, or null to leave it unknown.
  final String? _loads;

  /// What [unlock] answers: whether the phone got past its lock screen.
  final bool unlocks;

  /// What [activateDatabase] answers: whether the switch went through.
  final bool switches;

  /// Every request the page made, oldest first.
  final List<RingRequest> requests = <RingRequest>[];

  String? _active;

  Completer<void>? _held;

  Completer<bool>? _heldKeep;

  Completer<void>? _heldUnlock;

  bool _busy = false;

  bool _stopped = false;

  bool _keeping = false;

  bool _kept = false;

  bool _endedElsewhere = false;

  /// Says which database is open, the way the real controller's `load` does
  /// when its read comes back.
  ///
  /// With [kept], the event was found there already kept — a Keep taken on
  /// an earlier ring of it — and the page is told both in the one
  /// notification, as the real controller tells them: the page must never
  /// draw "Stop also removes this event" for a moment first.
  void resolveDatabase(String name, {bool kept = false}) {
    _active = name;
    if (kept) _kept = true;
    notifyListeners();
  }

  /// Keeps the next Stop or Snooze in flight — [busy] true, the ring not yet
  /// over — until [release].
  void hold() => _held = Completer<void>();

  /// Lets a held Stop or Snooze finish.
  void release() {
    _held?.complete();
    _held = null;
  }

  /// Keeps the next Keep's write in flight until [releaseKeep].
  void holdKeep() => _heldKeep = Completer<bool>();

  /// Lets a held Keep's write come back: saved when [ok], else failed — a
  /// write that threw, or an event that was not there to write to.
  void releaseKeep({required bool ok}) {
    _heldKeep?.complete(ok);
    _heldKeep = null;
  }

  /// Keeps the next unlock unanswered — the PIN prompt up, on a phone —
  /// until [releaseUnlock].
  void holdUnlock() => _heldUnlock = Completer<void>();

  /// Lets a held unlock be answered, with [unlocks].
  void releaseUnlock() {
    _heldUnlock?.complete();
    _heldUnlock = null;
  }

  /// What the real controller does when the gateway reports this ring over —
  /// Stop on its notification, the Silence-after timeout: the ring counts as
  /// stopped, and the page is told it ended by a route it did not take.
  void endElsewhere() {
    _stopped = true;
    _endedElsewhere = true;
    notifyListeners();
  }

  @override
  String? get activeDatabase => _active;

  @override
  bool get fromOtherDatabase => _active != null && _active != payload.database;

  @override
  bool get busy => _busy;

  @override
  bool get stopped => _stopped;

  @override
  bool get endedElsewhere => _endedElsewhere;

  @override
  bool get keepEvent => _kept;

  @override
  bool get willRemoveEvent =>
      payload.removeAfterAlert && !_keeping && !_kept && !payload.isTest;

  @override
  Future<void> load() async {
    final name = _loads;
    if (name == null) return;
    // Never inside the build that mounted the page: the real answer is a
    // database read away.
    await null;
    resolveDatabase(name);
  }

  @override
  Future<void> stop() => _end(RingRequest.stop);

  @override
  Future<void> snooze() => _end(RingRequest.snooze);

  /// The shape both of the real controller's endings have: busy, the work,
  /// then stopped and no longer busy, with a notification on either side.
  Future<void> _end(RingRequest request) async {
    requests.add(request);
    _busy = true;
    notifyListeners();
    await _held?.future;
    _stopped = true;
    _busy = false;
    notifyListeners();
  }

  /// The shape the real controller's Keep has: nothing is removed from the
  /// press on, and the event counts as kept only once the write is back —
  /// or the press is taken back when the write failed.
  @override
  Future<void> keep() async {
    requests.add(RingRequest.keep);
    _keeping = true;
    notifyListeners();
    final saved = await (_heldKeep?.future ?? Future<bool>.value(true));
    _keeping = false;
    _kept = saved;
    notifyListeners();
  }

  @override
  Future<bool> unlock() async {
    requests.add(RingRequest.unlock);
    await _heldUnlock?.future;
    return unlocks;
  }

  @override
  Future<bool> activateDatabase() async {
    requests.add(RingRequest.activateDatabase);
    return switches;
  }
}
