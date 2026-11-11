import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/guard.dart';
import '../../tool/qa/src/guest_state.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/runner.dart' show Liveness;
import 'fake_process_runner.dart';

final DateTime _now = DateTime.utc(2026, 11, 11, 9);

/// Fleet guest [index] as one poll reads it: up and booted unless [state]
/// says otherwise, its qemu running unless [qemu] is false.
FleetMember _guest(
  int index, {
  FleetState state = FleetState.device,
  bool qemu = true,
  GuestState? file,
  GuestHold? hold,
  String? heldBy,
}) => FleetMember(
  index: index,
  created: true,
  state: state,
  qemu: qemu
      ? QemuProcess(
          pid: 4000 + index,
          avd: fleetName(index),
          port: fleetPort(index),
        )
      : null,
  guest: file,
  hold: hold,
  heldBy: heldBy,
);

GuestState _usedAgo(Duration ago, {bool keep = false}) => GuestState(
  bootedAt: _now.subtract(const Duration(hours: 2)),
  lastUsedAt: _now.subtract(ago),
  keep: keep,
);

GuardSnapshot _snap(
  List<FleetMember> members, {
  Set<String>? attached,
  bool adbAnswered = true,
  String? runDevice,
  Map<String, bool> idleOffAdb = const {},
}) => GuardSnapshot(
  members: members,
  attached:
      attached ??
      {
        for (final m in members)
          if (m.state == FleetState.device) m.serial,
      },
  adbAnswered: adbAnswered,
  runDevice: runDevice,
  idleOffAdb: idleOffAdb,
);

GuardDecision _only(GuardBrain brain, GuardSnapshot snapshot, [DateTime? at]) =>
    brain.decide(snapshot, at ?? _now).decisions.single;

/// The host the guard loop runs over: anta_qa_1 up on emulator-5556 until
/// its console is told to stop, the owner's emulator-5554 beside it. Pids
/// in [alive] answer as running.
class _HostRunner extends FakeProcessRunner {
  _HostRunner({Set<int> alive = const {}}) : alive = {...alive};

  final Set<int> alive;
  bool down = false;

  /// What the recorded-run probe answers on a Windows host; '' is a
  /// PowerShell that printed nothing.
  String runProbe = 'gone';

  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  }) async {
    final request = RunRequest(executable, arguments, binary: binary);
    calls.add(request);
    switch (request.line) {
      case 'adb devices -l':
        return RunOutcome(
          0,
          'List of devices attached\nemulator-5554 device\n'
              '${down ? '' : 'emulator-5556 device\n'}',
          '',
        );
      case 'adb -s emulator-5556 emu avd name':
        return const RunOutcome(0, 'anta_qa_1\r\nOK', '');
      case 'adb -s emulator-5556 shell getprop sys.boot_completed':
        return const RunOutcome(0, '1', '');
      case 'adb -s emulator-5556 emu kill':
        down = true;
        return const RunOutcome(0, 'OK', '');
      case '/bin/ps -axww -o pid=,command=':
        return RunOutcome(
          0,
          down ? '' : '4242 qemu-system-x86_64 -avd anta_qa_1 -port 5556',
          '',
        );
    }
    if (executable == 'powershell.exe' && arguments.last == qemuListScript) {
      return RunOutcome(
        0,
        down
            ? ''
            : '4242\tFFFF\tNormal\tqemu-system-x86_64.exe -avd anta_qa_1 -port 5556',
        '',
      );
    }
    if (RegExp(r"ProcessId=\d+'.*run_cmd\.bat").hasMatch(request.line)) {
      return RunOutcome(0, runProbe, '');
    }
    final probe = RegExp(r'Get-Process -Id (\d+) ').firstMatch(request.line);
    if (probe != null) {
      final pid = int.parse(probe.group(1)!);
      return RunOutcome(0, alive.contains(pid) ? 'alive' : 'gone', '');
    }
    final kill0 = RegExp(
      r'^/bin/sh -c kill -0 (\d+) ',
    ).firstMatch(request.line);
    if (kill0 != null) {
      final pid = int.parse(kill0.group(1)!);
      return RunOutcome(0, alive.contains(pid) ? 'alive' : 'gone', '');
    }
    return defaultOutcome;
  }
}

void main() {
  group('settings', () {
    test('the defaults: on, a poll a minute, thirty idle minutes', () {
      final settings = GuardSettings.from(const {});
      expect(settings.enabled, isTrue);
      expect(settings.poll, guardPoll);
      expect(settings.idleLimit, guestIdleLimit);
    });

    test('the environment overrides each; 0 turns the idle stop off', () {
      final settings = GuardSettings.from(const {
        guardEnv: '0',
        guardPollEnv: '20',
        idleMinutesEnv: '2',
      });
      expect(settings.enabled, isFalse);
      expect(settings.poll, const Duration(seconds: 20));
      expect(settings.idleLimit, const Duration(minutes: 2));
      expect(GuardSettings.from(const {idleMinutesEnv: '0'}).idleLimit, isNull);
    });

    test('a value that is not a count falls back to the default', () {
      final settings = GuardSettings.from(const {
        guardPollEnv: 'soon',
        idleMinutesEnv: '-3',
      });
      expect(settings.poll, guardPoll);
      expect(settings.idleLimit, guestIdleLimit);
    });

    test('the pid file carries the settings fleet status shows', () {
      const record = GuardRecord(
        pid: 812,
        idleLimit: Duration(minutes: 2),
        poll: Duration(seconds: 20),
      );
      final back = GuardRecord.parse(record.encode())!;
      expect(back.pid, 812);
      expect(back.idleLimit, const Duration(minutes: 2));
      expect(back.poll, const Duration(seconds: 20));
      expect(GuardRecord.parse('812\nidle=0\npoll=60\n')!.idleLimit, isNull);
      expect(GuardRecord.parse('not a pid'), isNull);
      expect(
        guardStatusLine(back, enabled: true),
        'guard: running (pid 812, idle limit 2 min)',
      );
      expect(guardStatusLine(null, enabled: true), 'guard: not running');
      expect(
        guardStatusLine(null, enabled: false),
        'guard: not running ($guardEnv=0)',
      );
    });

    test('a guard copy is told by its name', () {
      expect(
        guardExeStamp(r'D:\anta\build\qa\guard_1794381490000.exe'),
        1794381490000,
      );
      expect(guardExeStamp('/anta/build/qa/guard_12'), 12);
      expect(guardExeStamp(r'D:\anta\build\qa\qa.exe'), isNull);
      expect(
        guardExeStamp(r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe'),
        isNull,
      );
    });
  });

  group('the guard\'s decisions', () {
    late GuardBrain brain;
    setUp(() => brain = GuardBrain(idleLimit: const Duration(minutes: 30)));

    test('a guest idle past the limit with no hold is stopped', () {
      final decision = _only(
        brain,
        _snap([_guest(1, file: _usedAgo(const Duration(minutes: 31)))]),
      );
      expect(decision.action, GuardAction.stop);
      expect(
        decision.line,
        'anta_qa_1: idle 31m, limit 30 min, no hold — stopping it',
      );
    });

    test('a guest used within the limit is left up', () {
      final decision = _only(
        brain,
        _snap([_guest(1, file: _usedAgo(const Duration(minutes: 29)))]),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.kind, 'idle-wait');
    });

    test('a live hold keeps an idle guest up', () {
      final decision = _only(
        brain,
        _snap([
          _guest(
            1,
            file: _usedAgo(const Duration(hours: 3)),
            hold: _Holds.pass,
          ),
        ]),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.why, startsWith('held by pass pid 77'));
    });

    test('a hold three hours old no longer keeps a guest up', () {
      GuestHold heldFor(Duration age) =>
          GuestHold(pid: 77, verb: 'pass', since: _now.subtract(age));
      final idle = _usedAgo(const Duration(minutes: 31));
      final young = _only(
        brain,
        _snap([
          _guest(
            1,
            file: idle,
            hold: heldFor(holdTrustLimit - const Duration(minutes: 1)),
          ),
        ]),
      );
      expect(young.action, GuardAction.keep);
      expect(young.kind, 'held');
      final stale = _only(
        brain,
        _snap([_guest(1, file: idle, hold: heldFor(holdTrustLimit))]),
      );
      expect(
        stale.action,
        GuardAction.stop,
        reason: 'a pass is bounded at 45 minutes; a hold this old is stuck',
      );
      expect(holdTrustLimit, const Duration(hours: 3));

      // A stuck holder's hung guest is force-stopped like anyone's.
      final hung = GuardBrain(idleLimit: const Duration(minutes: 30));
      final off = _snap(
        [
          _guest(
            1,
            state: FleetState.booting,
            hold: heldFor(const Duration(hours: 4)),
          ),
        ],
        attached: const {},
        idleOffAdb: const {'anta_qa_1': true},
      );
      hung.decide(off, _now);
      expect(
        _only(hung, off, _now.add(hungGuestLimit)).action,
        GuardAction.forceStop,
      );
    });

    test('the device of a live recorded flutter run counts as held', () {
      final decision = _only(
        brain,
        _snap([
          _guest(1, file: _usedAgo(const Duration(hours: 3))),
        ], runDevice: 'emulator-5556'),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.kind, 'run');
      expect(
        _only(
          GuardBrain(idleLimit: const Duration(minutes: 30)),
          _snap([
            _guest(1, file: _usedAgo(const Duration(hours: 3))),
          ], runDevice: 'emulator-5558'),
        ).action,
        GuardAction.stop,
        reason: 'a run on another device holds nothing here',
      );
    });

    test('--keep-up keeps an idle guest up', () {
      final decision = _only(
        brain,
        _snap([
          _guest(1, file: _usedAgo(const Duration(hours: 3), keep: true)),
        ]),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.kind, 'keep');
    });

    test('an idle limit of 0 stops nothing for being idle', () {
      final decision = _only(
        GuardBrain(idleLimit: null),
        _snap([_guest(1, file: _usedAgo(const Duration(hours: 9)))]),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.why, 'idle stop off ($idleMinutesEnv=0)');
    });

    test(
      'a guest with no state file is timed from when the guard first saw it',
      () {
        final first = _only(brain, _snap([_guest(1)]));
        expect(first.action, GuardAction.keep);
        final later = _only(
          brain,
          _snap([_guest(1)]),
          _now.add(const Duration(minutes: 30)),
        );
        expect(later.action, GuardAction.stop);
      },
    );

    test(
      'a qemu off adb and idle is force-stopped after three minutes of it',
      () {
        final hung = _guest(
          1,
          state: FleetState.booting,
          file: _usedAgo(Duration.zero, keep: true),
        );
        GuardSnapshot idle() =>
            _snap([hung], idleOffAdb: const {'anta_qa_1': true});
        expect(_only(brain, idle()).kind, 'hung-wait');
        expect(
          _only(brain, idle(), _now.add(const Duration(minutes: 2))).action,
          GuardAction.keep,
        );
        final third = _only(
          brain,
          idle(),
          _now.add(const Duration(minutes: 3)),
        );
        expect(
          third.action,
          GuardAction.forceStop,
          reason: '--keep-up does not protect a hung guest',
        );
        expect(third.why, 'off adb and idle for 3m — hung; force-stopping it');
      },
    );

    test(
      'a qemu off adb that burns CPU is coming up, and resets the clock',
      () {
        final booting = _guest(1, state: FleetState.booting);
        _only(brain, _snap([booting], idleOffAdb: const {'anta_qa_1': true}));
        final busy = _only(
          brain,
          _snap([booting], idleOffAdb: const {'anta_qa_1': false}),
          _now.add(const Duration(minutes: 2)),
        );
        expect(busy.kind, 'coming-up');
        final idleAgain = _only(
          brain,
          _snap([booting], idleOffAdb: const {'anta_qa_1': true}),
          _now.add(const Duration(minutes: 4)),
        );
        expect(
          idleAgain.action,
          GuardAction.keep,
          reason: 'the three minutes start over',
        );
      },
    );

    test('a held guest off adb is the holder\'s to recover', () {
      final decision = _only(
        brain,
        _snap(
          [_guest(1, state: FleetState.booting, hold: _Holds.pass)],
          idleOffAdb: const {'anta_qa_1': true},
        ),
        _now.add(const Duration(hours: 1)),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.kind, 'held');
    });

    test('without an answer from adb nothing is stopped', () {
      final decision = _only(
        brain,
        _snap(
          [_guest(1, file: _usedAgo(const Duration(hours: 3)))],
          adbAnswered: false,
          attached: const {},
        ),
      );
      expect(decision.action, GuardAction.keep);
      expect(decision.kind, 'adb');
    });

    test('a guest on adb that is still booting is left alone', () {
      final decision = _only(
        brain,
        _snap(
          [
            _guest(
              1,
              state: FleetState.booting,
              file: _usedAgo(const Duration(hours: 3)),
            ),
          ],
          attached: const {'emulator-5556'},
        ),
      );
      expect(decision.kind, 'booting');
    });

    test('a fleet port another AVD holds is never judged', () {
      final turn = brain.decide(
        _snap([
          _guest(
            1,
            heldBy: 'Pixel_9_Pro',
            file: _usedAgo(const Duration(hours: 3)),
          ),
        ]),
        _now,
      );
      expect(turn.decisions, isEmpty);
    });

    test('it exits after two polls in a row with no guest up', () {
      final stopped = _guest(1, state: FleetState.stopped, qemu: false);
      final up = _guest(1, file: _usedAgo(Duration.zero));
      expect(brain.decide(_snap([stopped]), _now).exit, isFalse);
      expect(
        brain.decide(_snap([up]), _now).emptyPolls,
        0,
        reason:
            'a recycle\'s gap between its stop and its boot is one poll at most',
      );
      final first = brain.decide(_snap([stopped]), _now);
      expect((first.emptyPolls, first.exit), (1, false));
      final second = brain.decide(_snap([stopped]), _now);
      expect((second.emptyPolls, second.exit), (2, true));
    });
  });

  group('one guard at a time', () {
    late Directory temp;
    late QaPaths paths;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_guard_');
      paths = QaPaths(temp.path)
        ..ensureBuildQa()
        ..ensureFleetState();
    });
    tearDown(() => temp.deleteSync(recursive: true));

    const self = GuardRecord(
      pid: 200,
      idleLimit: Duration(minutes: 30),
      poll: guardPoll,
    );

    test('a live guard keeps a second one from starting', () async {
      File(paths.guardPid).writeAsStringSync('100\n');
      expect(await claimGuard(paths, self, (_) async => 'ours'), isFalse);
      expect(GuardRecord.read(paths.guardPid)!.pid, 100);
    });

    test('a pid that is gone or no longer a guard is taken over', () async {
      for (final said in ['gone', 'other']) {
        File(paths.guardPid).writeAsStringSync('100\n');
        expect(
          await claimGuard(paths, self, (_) async => said),
          isTrue,
          reason: said,
        );
        expect(GuardRecord.read(paths.guardPid)!.pid, 200);
      }
    });

    test(
      'a pid that could not be checked is left to the guard it may be',
      () async {
        File(paths.guardPid).writeAsStringSync('100\n');
        expect(await claimGuard(paths, self, (_) async => null), isFalse);
        expect(GuardRecord.read(paths.guardPid)!.pid, 100);
        final line = await ensureGuard(
          paths: paths,
          runner: FakeProcessRunner(),
          windows: true,
          settings: GuardSettings.from(const {}),
          start: () async => throw StateError('no second guard'),
        );
        expect(
          line,
          'guard: guard.pid names pid 100, which could not be checked — no '
          'second guard started',
        );
      },
    );

    test('a file that reads but names no pid is taken over', () async {
      File(paths.guardPid).writeAsStringSync('');
      expect(await claimGuard(paths, self, (_) async => null), isTrue);
      expect(GuardRecord.read(paths.guardPid)!.pid, 200);
    });

    test('releasing leaves a newer guard\'s file alone', () {
      File(paths.guardPid).writeAsStringSync('300\n');
      releaseGuard(paths, 200);
      expect(File(paths.guardPid).existsSync(), isTrue);
      releaseGuard(paths, 300);
      expect(File(paths.guardPid).existsSync(), isFalse);
    });

    test('the probe names a guard by its command line, never by its pid', () {
      final script = guardProbeScript(4711);
      expect(script, contains("'ProcessId=4711'"));
      expect(script, contains("CommandLine -like '*fleet guard*'"));
      expect(
        script,
        isNot(contains('"')),
        reason: 'powershell -Command mangles double quotes',
      );
    });

    test('the start runs a copy, hidden, as fleet guard', () {
      final script = guardStartScript(r"D:\it's\guard_1.exe", r'D:\anta');
      expect(script, contains(r"-FilePath 'D:\it''s\guard_1.exe'"));
      expect(script, contains("-ArgumentList 'fleet','guard' "));
      expect(script, contains('-WindowStyle Hidden'));
      expect(
        script,
        isNot(contains('-Redirect')),
        reason: 'a redirect would inherit handles',
      );
      expect(
        guardStartScript('g.exe', '.', handedOver: true),
        contains("-ArgumentList 'fleet','guard','--$guardHandedOverFlag' "),
      );
    });

    test(
      'fleet boot starts a guard only when none runs and it is enabled',
      () async {
        final runner = FakeProcessRunner();
        const enabled = GuardSettings(
          enabled: true,
          poll: guardPoll,
          idleLimit: guestIdleLimit,
        );
        var starts = 0;
        Future<int> start() async =>
            ++starts == 1 ? 900 : throw StateError('twice');
        expect(
          await ensureGuard(
            paths: paths,
            runner: runner,
            windows: false,
            settings: enabled,
            start: start,
          ),
          isNull,
          reason: 'off Windows there is no guard',
        );
        expect(
          await ensureGuard(
            paths: paths,
            runner: runner,
            windows: true,
            settings: const GuardSettings(
              enabled: false,
              poll: guardPoll,
              idleLimit: guestIdleLimit,
            ),
            start: start,
          ),
          startsWith('guard: off ($guardEnv=0)'),
        );
        expect(
          await ensureGuard(
            paths: paths,
            runner: runner,
            windows: true,
            settings: enabled,
            start: start,
          ),
          startsWith('guard: started (pid 900, idle limit 30 min, poll 60 s)'),
        );
        File(paths.guardPid).writeAsStringSync('900\nidle=30\npoll=60\n');
        runner.script(
          'powershell.exe -NoProfile -NonInteractive -Command ${guardProbeScript(900)}',
          const RunOutcome(0, 'ours', ''),
        );
        expect(
          await ensureGuard(
            paths: paths,
            runner: runner,
            windows: true,
            settings: enabled,
            start: start,
          ),
          'guard: running (pid 900, idle limit 30 min)',
        );
        expect(starts, 1);
      },
    );

    test('a failed start is a warning, not a failed boot', () async {
      final line = await ensureGuard(
        paths: paths,
        runner: FakeProcessRunner(),
        windows: true,
        settings: GuardSettings.from(const {}),
      );
      expect(line, startsWith('warning: guard not started — no '));
    });

    test('every copy but the one kept is cleared', () {
      for (final name in [
        'guard_1.exe',
        'guard_2.exe',
        'guard_3.exe.tmp',
        'qa.exe',
      ]) {
        File(joinPath(paths.fleetState, [name])).writeAsStringSync('x');
      }
      final keep = joinPath(paths.fleetState, ['guard_2.exe']);
      clearGuardCopies(paths, keep: keep);
      expect(guardCopies(paths), [keep]);
      expect(File(joinPath(paths.fleetState, ['qa.exe'])).existsSync(), isTrue);
    });
  });

  group('the log', () {
    late Directory temp;
    setUp(
      () => temp = Directory.systemTemp.createTempSync('anta_qa_guard_log_'),
    );
    tearDown(() => temp.deleteSync(recursive: true));

    test('a keep is written once per kind, an action every time', () {
      final path = joinPath(temp.path, ['guard.log']);
      File(path).writeAsStringSync('an older guard\n');
      final log = GuardLog(path, clock: () => _now)..start();
      final member = _guest(1);
      for (var i = 0; i < 3; i++) {
        log.decision(
          GuardDecision(
            member,
            GuardAction.keep,
            'idle-wait',
            'idle ${i}m of 30 min — left up',
          ),
        );
      }
      log.decision(
        GuardDecision(member, GuardAction.stop, 'idle', 'stopping it'),
      );
      log.decision(
        GuardDecision(
          member,
          GuardAction.keep,
          'idle-wait',
          'idle 0s of 30 min — left up',
        ),
      );
      final lines = File(path).readAsLinesSync();
      expect(lines.map((l) => l.substring(20)), [
        'anta_qa_1: idle 0m of 30 min — left up',
        'anta_qa_1: stopping it',
        'anta_qa_1: idle 0s of 30 min — left up',
      ]);
    });

    test('past its limit the log starts over', () {
      final path = joinPath(temp.path, ['guard.log']);
      File(path).writeAsStringSync('x' * (guardLogLimitBytes + 1));
      GuardLog(path).write('next');
      expect(File(path).lengthSync(), lessThan(200));
      expect(File(path).readAsStringSync(), contains('log restarted past'));
    });
  });

  group('the loop', () {
    late Directory temp;
    late QaPaths paths;
    late _HostRunner runner;
    late FleetHost host;
    late List<String> logged;
    late DateTime clock;

    FleetHost hostOn({required bool windows}) => FleetHost(
      runner: runner,
      adb: Adb(executable: 'adb', runner: runner),
      avdHome: joinPath(temp.path, ['avd']),
      sdkRoot: null,
      windows: windows,
      pollEvery: Duration.zero,
    );

    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_guard_loop_');
      paths = QaPaths(temp.path)..ensureBuildQa();
      final avds = Directory(joinPath(temp.path, ['avd']))..createSync();
      File(
        joinPath(avds.path, ['anta_qa_1.ini']),
      ).writeAsStringSync('path=x\n');
      final dir = Directory(joinPath(avds.path, ['anta_qa_1.avd']))
        ..createSync();
      File(joinPath(dir.path, ['config.ini'])).writeAsStringSync('x=1\n');
      runner = _HostRunner();
      host = hostOn(windows: false);
      logged = [];
      clock = _now;
      paths.ensureFleetState();
      File(paths.guardPid).writeAsStringSync('$pid\nidle=30\npoll=60\n');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    FleetGuard guard({
      bool Function()? exeChanged,
      Future<void> Function()? handOver,
      Future<Liveness> Function(int pid)? isAlive,
      Future<String?> Function(int pid)? probeOtherGuard,
      Future<void> Function()? onSleep,
    }) => FleetGuard(
      host: host,
      paths: paths,
      settings: GuardSettings.from(const {}),
      log: _ListLog(joinPath(temp.path, ['guard.log']), logged),
      pid: pid,
      isAlive:
          isAlive ??
          (p) async =>
              runner.alive.contains(p) ? Liveness.alive : Liveness.gone,
      probeOtherGuard: probeOtherGuard ?? (_) async => 'ours',
      clock: () => clock,
      sleep: (_) async {
        clock = clock.add(const Duration(minutes: 1));
        await onSleep?.call();
      },
      exeChanged: exeChanged,
      handOver: handOver,
    );

    /// anta_qa_1 last used [ago] before the clock.
    void usedAgo(Duration ago) => GuestState.booted(
      paths.guestStateFor('anta_qa_1'),
      clock.subtract(ago),
    );

    bool stopped() => runner.lines.contains('adb -s emulator-5556 emu kill');

    test(
      'stops an idle guest gracefully, then exits once nothing is left',
      () async {
        final state = paths.guestStateFor('anta_qa_1');
        GuestState.booted(state, _now.subtract(const Duration(minutes: 31)));
        expect(await guard().run(), 0);
        expect(runner.lines, contains('adb -s emulator-5556 emu kill'));
        expect(
          runner.lines.where((l) => l.contains('emulator-5554 emu')),
          isEmpty,
          reason: 'the owner\'s emulator is never acted on',
        );
        expect(File(state).existsSync(), isFalse);
        expect(
          File(paths.guardPid).existsSync(),
          isFalse,
          reason: 'the pid file goes with the guard',
        );
        expect(logged, [
          startsWith('guard: pid $pid, poll 60 s, idle limit 30 min'),
          'anta_qa_1: idle 31m, limit 30 min, no hold — stopping it',
          startsWith('anta_qa_1: stopped: anta_qa_1 (emulator-5556) in '),
          'no fleet guest up (1/2)',
          'no fleet guest up for 2 polls — exiting',
        ]);
      },
    );

    test('a guest a pass took after the poll read it is left up', () async {
      final state = paths.guestStateFor('anta_qa_1');
      GuestState.booted(state, _now.subtract(const Duration(minutes: 31)));
      final loop = guard();
      final decision = loop.brain
          .decide(await loop.snapshot(), _now)
          .decisions
          .single;
      expect(decision.action, GuardAction.stop);
      runner.alive.add(77);
      GuestState.take(
        state,
        GuestHold(
          pid: 77,
          verb: 'pass',
          since: _now.subtract(const Duration(hours: 1)),
        ),
      );
      await loop.act(decision);
      expect(runner.lines, isNot(contains('adb -s emulator-5556 emu kill')));
      expect(logged.last, 'anta_qa_1: used since this poll read it — left up');
      expect(File(state).existsSync(), isTrue);
    });

    test('a guest a verb used after the poll read it is left up', () async {
      final state = paths.guestStateFor('anta_qa_1');
      GuestState.booted(state, _now.subtract(const Duration(minutes: 31)));
      final loop = guard();
      final decision = loop.brain
          .decide(await loop.snapshot(), _now)
          .decisions
          .single;
      GuestState.touch(state, _now);
      await loop.act(decision);
      expect(runner.lines, isNot(contains('adb -s emulator-5556 emu kill')));
    });

    test('a guard whose pid file names another guard exits at once', () async {
      File(paths.guardPid).writeAsStringSync('${pid + 1}\n');
      expect(await guard().run(), 0);
      expect(logged.last, 'guard.pid names pid ${pid + 1} now — exiting');
      expect(runner.lines, isNot(contains('adb devices -l')));
      expect(
        File(paths.guardPid).existsSync(),
        isTrue,
        reason: 'the other guard\'s file stays',
      );
    });

    test('a rebuilt qa.exe hands the watch over to a new guard', () async {
      GuestState.booted(paths.guestStateFor('anta_qa_1'), _now);
      var handedOver = 0;
      expect(
        await guard(
          exeChanged: () => true,
          handOver: () async => handedOver++,
        ).run(),
        0,
      );
      expect(handedOver, 1);
      expect(
        logged.last,
        'qa.exe was rebuilt — handing over to a guard on the new build',
      );
      expect(
        File(paths.guardPid).existsSync(),
        isFalse,
        reason: 'released before the new guard claims it',
      );
      expect(runner.lines, isNot(contains('adb -s emulator-5556 emu kill')));
    });

    test('a decision that throws is logged and skipped, never fatal', () async {
      usedAgo(const Duration(minutes: 31));
      final loop = guard(
        isAlive: (_) async => throw StateError('the probe blew up'),
      );
      final decision = loop.brain
          .decide(await loop.snapshot(), clock)
          .decisions
          .single;
      // Taken an hour ago by its own clock, so only the holder's probe can
      // tell whether it still protects the guest.
      GuestState.take(
        paths.guestStateFor('anta_qa_1'),
        GuestHold(
          pid: 77,
          verb: 'pass',
          since: clock.subtract(const Duration(hours: 1)),
        ),
      );
      await loop.act(decision);
      expect(logged.last, 'anta_qa_1: failed — Bad state: the probe blew up');
      expect(stopped(), isFalse);
    });

    test(
      'a guard.pid that does not name another live guard never ends it',
      () async {
        runner.down = true;
        for (final (text, said) in [
          ('${pid + 1}\n', null),
          ('', 'ours'),
          ('${pid + 1}\n', 'gone'),
        ]) {
          logged.clear();
          File(paths.guardPid).writeAsStringSync(text);
          expect(await guard(probeOtherGuard: (_) async => said).run(), 0);
          expect(
            logged.last,
            'no fleet guest up for 2 polls — exiting',
            reason: '"$text" probed $said',
          );
        }
        expect(
          logged,
          contains(
            'guard.pid named pid ${pid + 1}, which is no guard — claimed it back',
          ),
        );
      },
    );

    test(
      'a hold is trusted by its heartbeat on the guard\'s own clock',
      () async {
        clock = DateTime.utc(2031, 1, 1, 12);
        usedAgo(const Duration(hours: 5));
        final state = paths.guestStateFor('anta_qa_1');
        runner.alive.add(77);
        GuestState.take(
          state,
          GuestHold(
            pid: 77,
            verb: 'pass',
            since: clock.subtract(const Duration(hours: 5)),
          ),
        );
        GuestState.beat(state, 77, clock.subtract(const Duration(minutes: 5)));
        // The heartbeat is fresh: a five-hour pass that is still working.
        final kept = guard(exeChanged: () => true, handOver: () async {});
        await kept.run();
        expect(stopped(), isFalse);
        expect(logged, contains(startsWith('anta_qa_1: held by pass pid 77')));

        // Silent past the limit, the hold is a stuck process's.
        File(paths.guardPid).writeAsStringSync('$pid\n');
        GuestState.take(
          state,
          GuestHold(
            pid: 77,
            verb: 'pass',
            since: clock.subtract(const Duration(hours: 4)),
          ),
        );
        GuestState.touch(state, clock.subtract(const Duration(hours: 4)));
        expect(await guard().run(), 0);
        expect(stopped(), isTrue);
      },
    );

    group('on a Windows host', () {
      setUp(() => host = hostOn(windows: true));

      test(
        'a run probe that could not answer keeps the run\'s guest up',
        () async {
          usedAgo(const Duration(minutes: 31));
          File(paths.runPid).writeAsStringSync('8200');
          File(paths.deviceTxt).writeAsStringSync('emulator-5556');
          runner.runProbe = '';
          await guard(exeChanged: () => true, handOver: () async {}).run();
          expect(stopped(), isFalse);
          expect(
            logged,
            contains('anta_qa_1: the recorded flutter run is on it'),
          );
        },
      );

      test('a live run on no known device keeps every guest up', () async {
        usedAgo(const Duration(minutes: 31));
        File(paths.runPid).writeAsStringSync('8200');
        runner.runProbe = 'ours';
        await guard(exeChanged: () => true, handOver: () async {}).run();
        expect(stopped(), isFalse);
        expect(logged, contains(contains('could not be placed')));
      });

      test(
        'a run that landed on the guest after the poll keeps it up',
        () async {
          usedAgo(const Duration(minutes: 31));
          final loop = guard();
          final decision = loop.brain
              .decide(await loop.snapshot(), clock)
              .decisions
              .single;
          expect(decision.action, GuardAction.stop);
          File(paths.runPid).writeAsStringSync('8200');
          File(paths.deviceTxt).writeAsStringSync('emulator-5556');
          runner.runProbe = 'ours';
          await loop.act(decision);
          expect(stopped(), isFalse);
          expect(
            logged.last,
            'anta_qa_1: the recorded flutter run is on it — left up',
          );
        },
      );

      test('a guest nobody runs on is stopped as before', () async {
        usedAgo(const Duration(minutes: 31));
        expect(await guard().run(), 0);
        expect(stopped(), isTrue);
      });
    });
  });
}

/// Fixed holds the decision tests share.
abstract final class _Holds {
  static final GuestHold pass = GuestHold(pid: 77, verb: 'pass', since: _now);
}

/// A [GuardLog] that also hands every line to [lines], without its stamp.
class _ListLog extends GuardLog {
  _ListLog(super.path, this.lines);

  final List<String> lines;

  @override
  void write(String line) {
    lines.add(line);
    super.write(line);
  }
}
