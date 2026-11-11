import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'adb.dart';
import 'errors.dart';
import 'fleet.dart';
import 'guest_state.dart';
import 'paths.dart';
import 'process_runner.dart';
import 'quiet.dart';
import 'runner.dart';

/// `0` keeps `fleet boot` from starting the idle guard.
const String guardEnv = 'ANTA_QA_GUARD';

/// Seconds between two of the guard's polls; for tests and the live check.
const String guardPollEnv = 'ANTA_QA_GUARD_POLL_SECONDS';

/// Minutes a fleet guest may sit unused before the guard stops it; `0`
/// turns the idle stop off (a hung guest is still force-stopped).
const String idleMinutesEnv = 'ANTA_QA_IDLE_MINUTES';

/// A poll a minute costs nothing measurable and stops an idle guest
/// within a minute of its limit.
const Duration guardPoll = Duration(seconds: 60);

/// How long a qemu must stay off adb and idle, sampled at every poll,
/// before the guard calls it hung and force-stops it.
const Duration hungGuestLimit = Duration(minutes: 3);

/// How long a live hold keeps the guard off its guest after its holder's
/// last heartbeat ([GuestHold.lastBeat]). A pass beats at every flow and a
/// flow ends at its ceiling (six minutes), so a hold silent this long
/// belongs to a process that is stuck, and its guest is judged like any
/// other — idle or hung — however long the pass was allowed to run.
const Duration holdTrustLimit = Duration(hours: 3);

/// Whether [hold] still keeps the guard off its guest at [now]
/// ([holdTrustLimit]); whether its holder runs is asked apart. A state
/// file that does not read always protects.
bool holdProtects(GuestHold hold, DateTime now) =>
    hold.unreadable || now.difference(hold.lastBeat) < holdTrustLimit;

/// Polls in a row that find no fleet guest up before the guard exits: one
/// alone could fall in the gap between a recycle's stop and its boot.
const int guardEmptyPolls = 2;

/// Polls in a row whose fleet read failed before the guard gives up: a
/// guard that cannot see the fleet cannot stop anything either, and must
/// not live forever.
const int guardFailedPolls = 10;

/// The hidden flag a guard passes the guard it hands over to, so the new
/// one appends to the log instead of truncating the story so far.
const String guardHandedOverFlag = 'handed-over';

/// Past this size `guard.log` starts over, so a guard that runs for days
/// never fills the disk.
const int guardLogLimitBytes = 256 * 1024;

/// What the environment asks of the guard.
class GuardSettings {
  const GuardSettings({
    required this.enabled,
    required this.poll,
    required this.idleLimit,
  });

  factory GuardSettings.from(Map<String, String> env) {
    final minutes = int.tryParse(env[idleMinutesEnv]?.trim() ?? '');
    final seconds = int.tryParse(env[guardPollEnv]?.trim() ?? '');
    return GuardSettings(
      enabled: env[guardEnv]?.trim() != '0',
      poll: seconds != null && seconds > 0
          ? Duration(seconds: seconds)
          : guardPoll,
      idleLimit: minutes == null || minutes < 0
          ? guestIdleLimit
          : minutes == 0
          ? null
          : Duration(minutes: minutes),
    );
  }

  final bool enabled;
  final Duration poll;

  /// Null when the idle stop is off.
  final Duration? idleLimit;
}

/// `idle limit 30 min`, or `idle limit off`.
String idleLimitLabel(Duration? limit) =>
    limit == null ? 'idle limit off' : 'idle limit ${limit.inMinutes} min';

/// What `guard.pid` (in [QaPaths.fleetState]) holds: the guard's pid and the settings it
/// runs with, which `fleet status` shows (they come from the environment
/// of whichever `fleet boot` started it, not from the caller's).
class GuardRecord {
  const GuardRecord({
    required this.pid,
    required this.idleLimit,
    required this.poll,
  });

  final int pid;
  final Duration? idleLimit;
  final Duration poll;

  static GuardRecord? parse(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final pid = int.tryParse(lines.first);
    if (pid == null) return null;
    int? field(String key) => [
      for (final line in lines.skip(1))
        if (line.startsWith('$key='))
          int.tryParse(line.substring(key.length + 1)),
    ].nonNulls.firstOrNull;
    final idle = field('idle');
    final poll = field('poll');
    return GuardRecord(
      pid: pid,
      idleLimit: idle == null
          ? guestIdleLimit
          : idle == 0
          ? null
          : Duration(minutes: idle),
      poll: poll == null || poll <= 0 ? guardPoll : Duration(seconds: poll),
    );
  }

  static GuardRecord? read(String path) {
    final file = File(path);
    try {
      return file.existsSync() ? parse(file.readAsStringSync()) : null;
    } on FileSystemException {
      return null;
    }
  }

  String encode() =>
      '$pid\nidle=${idleLimit?.inMinutes ?? 0}\npoll=${poll.inSeconds}\n';
}

/// PowerShell that says what [pid] is: `ours` while its command line runs
/// `fleet guard`, `other` when the pid now belongs to something else,
/// `gone` when nothing has it. A pid file outlives its process, and Windows
/// hands pids out again, so a pid alone never proves a guard runs.
String guardProbeScript(int pid) =>
    "\$p = Get-CimInstance Win32_Process -Filter 'ProcessId=$pid'; "
    "if (\$null -eq \$p) { 'gone' } "
    "elseif (\$p.CommandLine -like '*fleet guard*') { 'ours' } else { 'other' }";

/// [guardProbeScript]'s answer, or null when PowerShell gave none.
Future<String?> probeGuard(int pid, ProcessRunner runner) async {
  final result = await runner.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    guardProbeScript(pid),
  ], timeout: const Duration(seconds: 20));
  final said = result.stdout.trim();
  return const {'ours', 'other', 'gone'}.contains(said) ? said : null;
}

/// The guard `guard.pid` names while that pid still runs `fleet guard`;
/// null otherwise.
Future<GuardRecord?> runningGuard(QaPaths paths, ProcessRunner runner) async {
  final record = GuardRecord.read(paths.guardPid);
  if (record == null) return null;
  return await probeGuard(record.pid, runner) == 'ours' ? record : null;
}

/// The `guard:` line of `fleet status`.
String guardStatusLine(GuardRecord? running, {required bool enabled}) {
  if (running != null) {
    return 'guard: running (pid ${running.pid}, '
        '${idleLimitLabel(running.idleLimit)})';
  }
  return enabled ? 'guard: not running' : 'guard: not running ($guardEnv=0)';
}

/// `fleet status --json`'s `guard` object.
Map<String, Object?> guardStatusJson(
  GuardRecord? running, {
  required bool enabled,
}) => {
  'enabled': enabled,
  'running': running != null,
  'pid': running?.pid,
  'idleLimitMinutes': running == null
      ? null
      : running.idleLimit?.inMinutes ?? 0,
  'pollSeconds': running?.poll.inSeconds,
};

/// Claims `guard.pid` for [self] unless a guard may already hold it, in
/// which case false: a guard is single-instance. Only a file shown to name
/// a pid that is gone or no longer a guard is taken over; one whose pid
/// could not be checked, or that does not read, is left to the guard it
/// may belong to — that guard keeps watching, and the next `fleet boot`
/// tries again.
Future<bool> claimGuard(
  QaPaths paths,
  GuardRecord self,
  Future<String?> Function(int pid) probe,
) async {
  final current = readGuardFile(paths.guardPid);
  if (current is GuardFileUnreadable) return false;
  final record = current is GuardFileRecord ? current.record : null;
  if (record != null && record.pid != self.pid) {
    final said = await probe(record.pid);
    if (said != 'gone' && said != 'other') return false;
  }
  return writeFileAtomically(paths.guardPid, self.encode());
}

/// What `guard.pid` is on disk. A guard writes it whole through a rename
/// ([writeFileAtomically]), so a file that reads but names no pid is
/// garbage, while one that will not read may still be a live guard's.
sealed class GuardFile {
  const GuardFile();
}

final class GuardFileMissing extends GuardFile {
  const GuardFileMissing();
}

final class GuardFileUnreadable extends GuardFile {
  const GuardFileUnreadable(this.why);

  final String why;
}

/// Read, with [record] null when it names no pid.
final class GuardFileRecord extends GuardFile {
  const GuardFileRecord(this.record);

  final GuardRecord? record;
}

GuardFile readGuardFile(String path) {
  try {
    return GuardFileRecord(GuardRecord.parse(File(path).readAsStringSync()));
  } on PathNotFoundException {
    return const GuardFileMissing();
  } on FileSystemException catch (e) {
    return GuardFileUnreadable(e.message);
  }
}

/// Removes `guard.pid` when it still names [pid].
void releaseGuard(QaPaths paths, int pid) {
  if (GuardRecord.read(paths.guardPid)?.pid != pid) return;
  try {
    File(paths.guardPid).deleteSync();
  } on FileSystemException {
    return;
  }
}

/// The stamp in a guard copy's file name ([QaPaths.guardExeFor]), or null
/// when [executable] is no such copy (a guard under `dart run`).
int? guardExeStamp(String executable) {
  final name = executable.split(RegExp(r'[\\/]')).last;
  final match = RegExp(r'^guard_(\d+)(?:\.exe)?$').firstMatch(name);
  return match == null ? null : int.parse(match.group(1)!);
}

/// PowerShell that starts [exe] as `fleet guard` with a hidden console of
/// its own and prints its pid. Without `-Redirect*` `Start-Process` goes
/// through ShellExecute, which hands the guard none of this process's
/// handles — it never holds the caller's stdout open — and the guard's
/// own children (PowerShell, adb) inherit its hidden console instead of
/// each opening a window.
String guardStartScript(
  String exe,
  String workingDirectory, {
  bool handedOver = false,
}) {
  String quote(String value) => value.replaceAll("'", "''");
  return "\$p = Start-Process -FilePath '${quote(exe)}' "
      "-ArgumentList 'fleet','guard'${handedOver ? ",'--$guardHandedOverFlag'" : ''} "
      "-WorkingDirectory '${quote(workingDirectory)}' "
      '-WindowStyle Hidden -PassThru; \$p.Id';
}

/// Starts a guard from a copy of `qa.exe` and returns its pid.
///
/// The copy is what keeps the self-rebuild working: Windows renames a
/// running exe but will not delete one, so a guard running `qa.exe` itself
/// would sit in `qa.exe.old` after one rebuild and make the next one fail.
/// A guard runs from `guard_<stamp>.exe` instead, hands over to a new copy
/// when `qa.exe` changes ([FleetGuard.exeChanged]), and every start clears
/// the copies no guard runs from any more.
Future<int> startGuard(
  QaPaths paths,
  ProcessRunner runner, {
  bool handedOver = false,
}) async {
  final source = File(paths.qaExe);
  if (!source.existsSync()) {
    throw DeviceFailure(
      'no ${paths.qaExe} to run the guard from — `qa build-exe` makes it',
    );
  }
  final stamp = source.statSync().modified.millisecondsSinceEpoch;
  final exe = File(paths.guardExeFor(stamp));
  paths.ensureFleetState();
  if (!exe.existsSync()) {
    final partial = '${exe.path}.tmp';
    source.copySync(partial);
    File(partial).renameSync(exe.path);
  }
  clearGuardCopies(paths, keep: exe.path);
  final result = await runner.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    guardStartScript(exe.path, paths.projectRoot, handedOver: handedOver),
  ], timeout: const Duration(seconds: 30));
  final pid = int.tryParse(result.stdout.trim().split('\n').last.trim());
  if (!result.ok || pid == null) {
    throw DeviceFailure(
      'the guard did not start: '
      '${result.combined.isEmpty ? 'exit ${result.exitCode}' : result.combined}',
    );
  }
  return pid;
}

/// Deletes every guard copy but [keep]; one a guard still runs from will
/// not go and is left for a later start.
void clearGuardCopies(QaPaths paths, {String? keep}) {
  for (final copy in guardCopies(paths)) {
    if (copy == keep) continue;
    try {
      File(copy).deleteSync();
    } on FileSystemException {
      continue;
    }
  }
}

/// The guard copies in the fleet directory, finished or half-copied.
List<String> guardCopies(QaPaths paths) {
  final dir = Directory(paths.fleetState);
  if (!dir.existsSync()) return const [];
  return [
    for (final file in dir.listSync().whereType<File>())
      if (isGuardCopyName(file.uri.pathSegments.last)) file.path,
  ];
}

/// Whether [name] is a guard copy's file name, finished or half-copied.
bool isGuardCopyName(String name) =>
    RegExp(r'^guard_\d+(?:\.exe)?(?:\.tmp)?$').hasMatch(name);

/// What `fleet boot` says about the guard once a guest is ready, starting
/// one when none runs; null off Windows, where the guard does not exist.
Future<String?> ensureGuard({
  required QaPaths paths,
  required ProcessRunner runner,
  required bool windows,
  required GuardSettings settings,
  Future<int> Function()? start,
}) async {
  if (!windows) return null;
  if (!settings.enabled) {
    return 'guard: off ($guardEnv=0) — nothing stops an idle guest; '
        '`qa reap` when you are done';
  }
  if (File(paths.guardPid).existsSync()) {
    final record = GuardRecord.read(paths.guardPid);
    final said = record == null ? null : await probeGuard(record.pid, runner);
    if (record != null && said == 'ours') {
      return guardStatusLine(record, enabled: true);
    }
    // A new guard would not claim a file it cannot judge ([claimGuard]),
    // so starting one would only print a start that never took.
    if (said == null) {
      return 'guard: guard.pid ${record == null ? 'does not read' : 'names pid ${record.pid}, which could not be checked'} '
          '— no second guard started';
    }
  }
  try {
    final pid = await (start ?? () => startGuard(paths, runner))();
    return 'guard: started (pid $pid, ${idleLimitLabel(settings.idleLimit)}, '
        'poll ${settings.poll.inSeconds} s) — log ${paths.guardLog}';
  } on QaException catch (e) {
    return 'warning: guard not started — ${e.message}';
  } on FileSystemException catch (e) {
    return 'warning: guard not started — ${e.message} (${e.path})';
  }
}

/// What the guard knows of the recorded `flutter run`: [device] while that
/// run is (or may be) alive — a `qa run` session driven through the Dart
/// MCP makes no `qa` calls, so its device's guest would otherwise look
/// idle — and [unknown] when a run that may be alive cannot be placed on a
/// device: then no guest can be stopped.
typedef RecordedRun = ({String? device, bool unknown});

/// The recorded run as [RecordedRun] says. A probe that could not answer
/// counts as a live run: a guest stopped under a developer's `qa run` is
/// the failure this check exists to prevent.
Future<RecordedRun> recordedRunDevice(
  QaPaths paths,
  ProcessRunner runner, {
  required bool windows,
}) async {
  String? read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on PathNotFoundException {
      return '';
    } on FileSystemException {
      return null;
    }
  }

  const none = (device: null, unknown: false);
  final pidText = read(paths.runPid);
  if (pidText != null && pidText.isEmpty) return none;
  final pid = pidText == null ? null : int.tryParse(pidText);
  if (pidText != null && pid == null) return none;
  final said = pid == null
      ? null
      : await probeRecordedRun(pid, paths, runner, windows: windows);
  if (said == 'gone' || said == 'other') return none;
  final device = read(paths.deviceTxt);
  return device == null || device.isEmpty
      ? (device: null, unknown: true)
      : (device: device, unknown: false);
}

/// Whether [member]'s qemu runs while adb does not list it as usable: a
/// guest still coming up, or a hung one.
bool isOffAdb(FleetMember member, Set<String> attached) =>
    member.qemu != null && !attached.contains(member.serial);

/// What the guard sees at one poll.
class GuardSnapshot {
  const GuardSnapshot({
    required this.members,
    required this.attached,
    required this.adbAnswered,
    this.runDevice,
    this.runUnknown = false,
    this.idleOffAdb = const {},
  });

  /// The fleet, each member's live hold filled in.
  final List<FleetMember> members;

  /// The serials adb lists as usable.
  final Set<String> attached;

  /// False when `adb devices` failed: then no guest can be told apart from
  /// a hung one, and the guard stops nothing.
  final bool adbAnswered;

  /// The device of a live recorded `flutter run` ([recordedRunDevice]).
  final String? runDevice;

  /// A recorded run that may be alive could not be placed on a device:
  /// no guest is stopped this poll.
  final bool runUnknown;

  /// Per AVD name, whether its qemu off adb was idle over this poll's
  /// [staleQemuSample] ([isIdleQemu]); a guest that was not sampled is
  /// absent.
  final Map<String, bool> idleOffAdb;
}

enum GuardAction { keep, stop, forceStop, quiet }

/// What the guard does about one guest at one poll, and why.
class GuardDecision {
  const GuardDecision(this.member, this.action, this.kind, this.why);

  final FleetMember member;
  final GuardAction action;

  /// The reason's kind (`idle`, `held`, `hung`, …): the log writes a keep
  /// only when its kind changes, so a guest idling for half an hour costs
  /// one line, not thirty.
  final String kind;
  final String why;

  String get line => '${member.name}: $why';
}

/// One poll's outcome.
class GuardTurn {
  const GuardTurn({
    required this.decisions,
    required this.emptyPolls,
    required this.exit,
  });

  final List<GuardDecision> decisions;

  /// Polls in a row that found no fleet guest up, this one included.
  final int emptyPolls;
  final bool exit;
}

/// The guard's decisions, apart from everything it reads and does, so a
/// test can say what it does with a fleet, its state files, a clock and
/// the limits. It remembers across polls what one poll cannot tell: since
/// when a qemu has been off adb and idle, and when it first saw a guest
/// that has no state file to date its last use.
class GuardBrain {
  GuardBrain({required this.idleLimit, this.hungLimit = hungGuestLimit});

  /// Null when the idle stop is off.
  final Duration? idleLimit;
  final Duration hungLimit;

  final Map<String, DateTime> _hungSince = {};
  final Map<String, DateTime> _firstSeen = {};
  int _emptyPolls = 0;

  GuardTurn decide(GuardSnapshot snapshot, DateTime now) {
    // A port another AVD holds is not a fleet guest of ours to judge.
    final up = [
      for (final member in snapshot.members)
        if (member.created && member.heldBy == null && member.up) member,
    ];
    final names = {for (final member in up) member.name};
    _hungSince.removeWhere((name, _) => !names.contains(name));
    _firstSeen.removeWhere((name, _) => !names.contains(name));
    if (up.isEmpty) {
      _emptyPolls++;
      return GuardTurn(
        decisions: const [],
        emptyPolls: _emptyPolls,
        exit: _emptyPolls >= guardEmptyPolls,
      );
    }
    _emptyPolls = 0;
    return GuardTurn(
      decisions: [for (final member in up) _decide(member, snapshot, now)],
      emptyPolls: 0,
      exit: false,
    );
  }

  GuardDecision _decide(FleetMember member, GuardSnapshot at, DateTime now) {
    final name = member.name;
    final firstSeen = _firstSeen.putIfAbsent(name, () => now);
    GuardDecision keep(String kind, String why) =>
        GuardDecision(member, GuardAction.keep, kind, why);
    if (!at.adbAnswered) {
      _hungSince.remove(name);
      return keep('adb', 'adb did not answer — nothing is stopped this poll');
    }
    // The holder owns the guest's recovery, a hung one's included: a pass
    // that lost its guest recovers it, or fails its flow and frees it.
    final hold = member.hold;
    if (hold != null && holdProtects(hold, now)) {
      _hungSince.remove(name);
      return keep('held', 'held by ${hold.label}');
    }
    if (at.runDevice == member.serial) {
      _hungSince.remove(name);
      return keep('run', 'the recorded flutter run is on it');
    }
    if (at.runUnknown) {
      _hungSince.remove(name);
      return keep(
        'run-unknown',
        'the recorded flutter run could not be placed — nothing is stopped '
            'this poll',
      );
    }
    if (isOffAdb(member, at.attached)) {
      if (at.idleOffAdb[name] != true) {
        _hungSince.remove(name);
        return keep('coming-up', 'not on adb and busy — coming up');
      }
      final hung = now.difference(_hungSince.putIfAbsent(name, () => now));
      if (hung >= hungLimit) {
        return GuardDecision(
          member,
          GuardAction.forceStop,
          'hung',
          'off adb and idle for ${idleLabel(hung)} — hung; force-stopping it',
        );
      }
      return keep(
        'hung-wait',
        'off adb and idle (force stop after ${hungLimit.inMinutes} min of it)',
      );
    }
    _hungSince.remove(name);
    if (member.state != FleetState.device) {
      return keep('booting', 'on adb, still booting');
    }
    // A hold on file whose holder is gone — not one that could not be
    // checked, which [FleetHost.withHolds] keeps — was never released: its
    // pass was killed with the seed's alarms armed, and they ring within
    // minutes, long before any idle limit. Only a pass seeds; an install or
    // a run that died armed nothing of its own.
    final dead = member.guest?.hold;
    if (dead != null && dead.verb == 'pass' && member.hold == null) {
      return GuardDecision(
        member,
        GuardAction.quiet,
        'dead-hold',
        '${dead.verb} pid ${dead.pid} is gone and never released it — '
            'quieting it',
      );
    }
    if (member.guest?.keep ?? false) return keep('keep', 'kept up (--keep-up)');
    final limit = idleLimit;
    if (limit == null) {
      return keep('no-limit', 'idle stop off ($idleMinutesEnv=0)');
    }
    final idle = member.guest?.idleAge(now) ?? now.difference(firstSeen);
    if (idle >= limit) {
      return GuardDecision(
        member,
        GuardAction.stop,
        'idle',
        'idle ${idleLabel(idle)}, limit ${limit.inMinutes} min, no hold — '
            'stopping it',
      );
    }
    return keep(
      'idle-wait',
      'idle ${idleLabel(idle)} of ${limit.inMinutes} min — left up',
    );
  }
}

/// The guard's log: one line per decision, stamped, truncated when a guard
/// starts and again past [guardLogLimitBytes].
class GuardLog {
  GuardLog(this.path, {DateTime Function()? clock}) : _clock = clock;

  final String path;
  final DateTime Function()? _clock;

  /// The last keep kind written per guest.
  final Map<String, String> _lastKind = {};

  void start() {
    try {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    } on FileSystemException {
      return;
    }
  }

  void write(String line) {
    final at = (_clock?.call() ?? DateTime.now()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
    try {
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > guardLogLimitBytes) {
        file.writeAsStringSync(
          '$stamp log restarted past ${guardLogLimitBytes ~/ 1024} KB\n',
        );
      }
      file.writeAsStringSync('$stamp $line\n', mode: FileMode.append);
    } on FileSystemException {
      return;
    }
  }

  /// Writes [decision], a keep only when its kind is new for that guest.
  void decision(GuardDecision decision) {
    final name = decision.member.name;
    if (decision.action == GuardAction.keep &&
        _lastKind[name] == decision.kind) {
      return;
    }
    _lastKind[name] = decision.kind;
    write(decision.line);
  }
}

/// The guard's loop over the real fleet: read it, decide, act, sleep —
/// until no fleet guest is left. Every stop goes through [FleetHost.stop]
/// or the guarded [FleetHost.forceStop]; the guard kills nothing itself.
class FleetGuard {
  FleetGuard({
    required this.host,
    required this.paths,
    required this.settings,
    required this.log,
    required this.pid,
    this.upTo = 0,
    Future<Liveness> Function(int pid)? isAlive,
    Future<String?> Function(int pid)? probeOtherGuard,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.exeChanged,
    this.handOver,
    this.quiet,
  }) : _isAlive =
           isAlive ??
           ((p) => processLiveness(p, host.runner, windows: host.windows)),
       _probeGuard = probeOtherGuard ?? ((p) => probeGuard(p, host.runner)),
       _clock = clock ?? DateTime.now,
       _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
       brain = GuardBrain(idleLimit: settings.idleLimit);

  final FleetHost host;
  final QaPaths paths;
  final GuardSettings settings;
  final GuardLog log;

  /// This guard's own pid, the one `guard.pid` must keep naming.
  final int pid;

  /// The fleet size `fleet status` reads up to.
  final int upTo;
  final GuardBrain brain;
  final Future<Liveness> Function(int pid) _isAlive;
  final Future<String?> Function(int pid) _probeGuard;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;

  /// True once the self-rebuild has replaced `qa.exe`: the guard then
  /// hands over ([handOver]) and exits, so the fleet is never watched by a
  /// stale build for longer than a poll.
  final bool Function()? exeChanged;
  final Future<void> Function()? handOver;

  /// Cancels the app's alarms on a guest ([quietGuest] through a child of
  /// the guard's own exe copy), [always] relaunching: before an idle stop,
  /// and at once on a guest whose pass died holding it. Null quiets
  /// nothing.
  final Future<GuestQuiet> Function(String serial, {required bool always})?
  quiet;

  Future<int> run() async {
    log.write(
      'guard: pid $pid, poll ${settings.poll.inSeconds} s, '
      '${idleLimitLabel(settings.idleLimit)}, a hung guest force-stopped '
      'after ${hungGuestLimit.inMinutes} min',
    );
    var failed = 0;
    while (true) {
      if (!await _stillTheGuard()) return 0;
      final GuardSnapshot snapshot;
      try {
        snapshot = await this.snapshot();
        failed = 0;
        // Anything a poll throws is a poll that failed, never the guard's
        // end: a guard that dies leaves every guest unguarded.
      } on Object catch (e) {
        failed++;
        log.write('poll failed ($failed/$guardFailedPolls): $e');
        if (failed >= guardFailedPolls) {
          log.write('the fleet could not be read $failed times — exiting');
          releaseGuard(paths, pid);
          return exitDevice;
        }
        await _sleep(settings.poll);
        continue;
      }
      final turn = brain.decide(snapshot, _clock());
      for (final decision in turn.decisions) {
        log.decision(decision);
        if (decision.action != GuardAction.keep) await act(decision);
      }
      if (turn.exit) {
        log.write('no fleet guest up for ${turn.emptyPolls} polls — exiting');
        releaseGuard(paths, pid);
        return 0;
      }
      if (turn.emptyPolls > 0) {
        log.write('no fleet guest up (${turn.emptyPolls}/$guardEmptyPolls)');
      }
      if (exeChanged?.call() ?? false) {
        log.write(
          'qa.exe was rebuilt — handing over to a guard on the new build',
        );
        releaseGuard(paths, pid);
        try {
          await handOver?.call();
        } on Exception catch (e) {
          log.write('the new guard did not start: $e');
        }
        return 0;
      }
      await _sleep(settings.poll);
    }
  }

  /// Whether this guard keeps watching. Only a `guard.pid` that readably
  /// names another live guard ends it. A file that does not read, or names
  /// a pid that could not be checked, is read again at the next poll; one
  /// that is missing or names a pid that is gone or no longer a guard is
  /// claimed back, so the single-instance check keeps working.
  Future<bool> _stillTheGuard() async {
    void claim(String why) {
      final wrote = writeFileAtomically(
        paths.guardPid,
        GuardRecord(
          pid: pid,
          idleLimit: settings.idleLimit,
          poll: settings.poll,
        ).encode(),
      );
      log.write(
        wrote
            ? 'guard.pid $why — claimed it back'
            : 'guard.pid $why and could not be written — tried again at the '
                  'next poll',
      );
    }

    final GuardRecord record;
    switch (readGuardFile(paths.guardPid)) {
      case GuardFileMissing():
        claim('was missing');
        return true;
      case GuardFileUnreadable(:final why):
        log.write(
          'guard.pid does not read ($why) — read again at the next poll',
        );
        return true;
      case GuardFileRecord(record: null):
        claim('named no pid');
        return true;
      case GuardFileRecord(record: final GuardRecord read):
        record = read;
    }
    if (record.pid == pid) return true;
    switch (await _probeGuard(record.pid)) {
      case 'ours':
        log.write('guard.pid names pid ${record.pid} now — exiting');
        return false;
      case 'gone' || 'other':
        claim('named pid ${record.pid}, which is no guard');
        return true;
      default:
        log.write(
          'guard.pid names pid ${record.pid}, which could not be checked — '
          'read again at the next poll',
        );
        return true;
    }
  }

  /// The fleet as one poll sees it.
  Future<GuardSnapshot> snapshot() async {
    List<AdbDevice>? devices;
    try {
      devices = await host.adb.devices(timeout: const Duration(seconds: 20));
    } on QaException {
      devices = null;
    }
    final created = host.createdIndices();
    final members = await host.withHolds(
      await host.members(
        upTo: math.max(upTo, created.isEmpty ? 0 : created.last),
        paths: paths,
        devices: devices ?? const [],
      ),
    );
    final attached = {
      for (final device in devices ?? const <AdbDevice>[])
        if (device.usable) device.serial,
    };
    final now = _clock();
    final idle = <String, bool>{};
    if (devices != null) {
      for (final member in members) {
        final hold = member.hold;
        if (hold != null && holdProtects(hold, now)) continue;
        if (!isOffAdb(member, attached)) continue;
        final qemu = member.qemu!.pid;
        final before = await host.cpuSeconds(qemu);
        await _sleep(staleQemuSample);
        idle[member.name] = isIdleQemu(before, await host.cpuSeconds(qemu));
      }
    }
    final run = await recordedRunDevice(
      paths,
      host.runner,
      windows: host.windows,
    );
    return GuardSnapshot(
      members: members,
      attached: attached,
      adbAnswered: devices != null,
      runDevice: run.device,
      runUnknown: run.unknown,
      idleOffAdb: idle,
    );
  }

  /// Carries out a stop or a force stop [decide] chose, after reading again
  /// what the poll read ([_reasonToLeave]). Whatever goes wrong is logged
  /// and the guest left as it is: a failed decision is skipped, never the
  /// guard's end.
  Future<void> act(GuardDecision decision) async {
    final member = decision.member;
    try {
      if (decision.action == GuardAction.quiet) {
        await _quietDeadHold(member);
        return;
      }
      final why = await _reasonToLeave(decision);
      if (why != null) {
        log.write('${member.name}: $why — left up');
        return;
      }
      if (decision.action == GuardAction.stop && quiet != null) {
        // Always relaunched: the count cannot see what a force-stopped app
        // still stores for the boot receiver.
        final quieted = await quiet!(member.serial, always: true);
        if (quietWorthSaying(quieted)) {
          log.write(quieted.line(member.name, 'before the stop'));
        }
      }
      if (member.hold != null) {
        // A hold silent past its trust limit: the pass behind it, should it
        // wake, must end rather than boot the guest again.
        StopRequest.record(
          paths.stopRequestFor(member.name),
          stopRequestNow('the idle guard (its hold went silent)', paths),
        );
      }
      final said = decision.action == GuardAction.stop
          ? await host.stop(member.index)
          : await host.forceStop(member.index);
      GuestState.forget(paths.guestStateFor(member.name));
      log.write('${member.name}: $said');
    } on QaException catch (e) {
      log.write('${member.name}: failed — ${e.message}');
    } on Object catch (e) {
      log.write('${member.name}: failed — $e');
    }
  }

  /// Quiets a guest whose holder died without releasing it, then clears
  /// that hold, after reading again that the very hold is still on file,
  /// its holder still gone and no recorded run on the guest. A quiet that
  /// fails is logged and the hold cleared all the same: the guest is left
  /// for the idle stop, never quieted again at every poll.
  Future<void> _quietDeadHold(FleetMember member) async {
    final dead = member.guest?.hold;
    if (dead == null) return;
    final path = paths.guestStateFor(member.name);
    final fresh = GuestState.read(path);
    String? why;
    if (fresh == null || fresh.unreadable) {
      why = 'its state file is gone or does not read';
    } else if (fresh.hold?.pid != dead.pid) {
      why = 'its hold changed since this poll read it';
    } else if (await _isAlive(dead.pid) != Liveness.gone) {
      why = 'pid ${dead.pid} is not shown gone any more';
    } else {
      final run = await recordedRunDevice(
        paths,
        host.runner,
        windows: host.windows,
      );
      if (run.unknown) why = 'the recorded flutter run could not be placed';
      if (run.device == member.serial) why = 'the recorded flutter run is on it';
    }
    if (why != null) {
      log.write('${member.name}: $why — not quieted');
      return;
    }
    final quieter = quiet;
    if (quieter != null) {
      final quieted = await quieter(member.serial, always: true);
      log.write(quieted.line(member.name, 'after its holder died'));
    }
    final cleared = GuestState.update(
      path,
      (s) => s.hold?.pid == dead.pid ? s.copyWith(clearHold: true) : s,
    );
    log.write(
      cleared
          ? '${member.name}: the stale hold of ${dead.verb} pid ${dead.pid} '
                'cleared'
          : '${member.name}: the stale hold could not be cleared',
    );
  }

  /// Why [decision] must not be carried out after all, or null: a verb
  /// that used (for an idle stop) or took the guest since the poll read
  /// it, a state file that no longer reads, or a recorded run that is on
  /// the guest or cannot be placed. A holder or a run whose process could
  /// not be checked counts as live.
  Future<String?> _reasonToLeave(GuardDecision decision) async {
    final member = decision.member;
    final fresh = GuestState.read(paths.guestStateFor(member.name));
    if (fresh != null && fresh.unreadable) {
      return 'its state file does not read';
    }
    if (decision.action == GuardAction.stop) {
      final usedSince =
          fresh?.lastUsedAt != null &&
          fresh!.lastUsedAt!.isAfter(
            member.guest?.lastUsedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
      if (usedSince) return 'used since this poll read it';
    }
    final hold = fresh?.hold;
    if (hold != null && holdProtects(hold, _clock())) {
      switch (await _isAlive(hold.pid)) {
        case Liveness.alive:
          return 'used since this poll read it';
        case Liveness.unknown:
          return 'held by ${hold.asUnconfirmed().label}';
        case Liveness.gone:
          break;
      }
    }
    final run = await recordedRunDevice(
      paths,
      host.runner,
      windows: host.windows,
    );
    if (run.unknown) return 'the recorded flutter run could not be placed';
    if (run.device == member.serial) return 'the recorded flutter run is on it';
    return null;
  }
}
