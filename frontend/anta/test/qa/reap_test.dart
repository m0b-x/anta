import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/qa.dart' show FleetCommand, QaCommandRunner, QaContext;
import '../../tool/qa/qa.dart' as qa show reapVerdict;
import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/doctor.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/guest_state.dart';
import '../../tool/qa/src/pass_history.dart' show defaultHistoryReports;
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/quiet.dart';
import '../../tool/qa/src/reap.dart';
import '../../tool/qa/src/runner.dart' show Liveness, recordedRunProbeScript;
import '../../tool/qa/src/self_build.dart';
import 'fake_process_runner.dart';

/// The host a reap runs over: fleet guest anta_qa_1 up on emulator-5556
/// until its console is told to stop, anta_qa_2 created and stopped, the
/// owner's emulator-5554 attached. Pids in [alive] answer as running.
class _HostRunner extends FakeProcessRunner {
  _HostRunner({
    Set<int> alive = const {},
    this.handlers = '',
    this.wrapper = '',
    this.avdName = 'anta_qa_1\r\nOK',
  }) : alive = {...alive};

  final Set<int> alive;

  /// Pids whose probe cannot answer: PowerShell prints nothing for them.
  final Set<int> unknown = {};

  /// Live pids that run something other than the harness's wrapper.
  final Set<int> others = {};
  final String handlers;

  /// This checkout's launch wrapper, which a live run's `ps` line names.
  final String wrapper;

  /// What the crash handler kill script answers, call by call.
  String Function() killAnswers = () => 'killed';

  /// What anta_qa_1's console says its AVD is.
  final String avdName;
  bool down = false;

  /// anta_qa_1 is on adb but its console takes no `emu kill`.
  bool consoleDead = false;

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
    final line = request.line;
    switch (line) {
      case 'adb devices -l':
        return RunOutcome(
          0,
          'List of devices attached\nemulator-5554 device\n'
              '${down ? '' : 'emulator-5556 device\n'}',
          '',
        );
      case 'adb -s emulator-5556 emu avd name':
        return RunOutcome(0, avdName, '');
      case 'adb -s emulator-5556 shell getprop sys.boot_completed':
        return const RunOutcome(0, '1', '');
      case 'adb -s emulator-5556 emu kill':
        if (consoleDead) {
          return const RunOutcome(
            1,
            '',
            'error: could not connect to TCP port 5556',
          );
        }
        down = true;
        return const RunOutcome(0, 'OK', '');
    }
    final ps = RegExp(r'^/bin/ps -o command= -p (\d+)$').firstMatch(line);
    if (ps != null) {
      final pid = int.parse(ps.group(1)!);
      if (others.contains(pid)) {
        return const RunOutcome(0, '/usr/bin/vim notes.txt', '');
      }
      return alive.contains(pid)
          ? RunOutcome(0, '/bin/sh $wrapper', '')
          : const RunOutcome(1, '', '');
    }
    if (executable == 'powershell.exe') {
      final script = arguments.last;
      if (script == qemuListScript) {
        return RunOutcome(
          0,
          down
              ? ''
              : '4242\tFFFF\tNormal\tqemu-system-x86_64.exe -avd anta_qa_1 -port 5556',
          '',
        );
      }
      if (script.startsWith('Get-CimInstance Win32_Process -Filter')) {
        return RunOutcome(0, handlers, '');
      }
      if (script.contains('Stop-Process')) {
        return RunOutcome(0, killAnswers(), '');
      }
      final guard = RegExp(r"ProcessId=(\d+)'.*fleet guard").firstMatch(script);
      if (guard != null) {
        final pid = int.parse(guard.group(1)!);
        return RunOutcome(0, alive.contains(pid) ? 'ours' : 'other', '');
      }
      final run = RegExp(r"ProcessId=(\d+)'.*run_cmd\.bat").firstMatch(script);
      if (run != null) {
        final pid = int.parse(run.group(1)!);
        return RunOutcome(0, alive.contains(pid) ? 'ours' : 'gone', '');
      }
      final probe = RegExp(r'Get-Process -Id (\d+) ').firstMatch(script);
      if (probe != null) {
        final pid = int.parse(probe.group(1)!);
        if (unknown.contains(pid)) return const RunOutcome(1, '', '');
        return RunOutcome(0, alive.contains(pid) ? 'alive' : 'gone', '');
      }
    }
    final kill0 = RegExp(r'^/bin/sh -c kill -0 (\d+) ').firstMatch(line);
    if (kill0 != null) {
      final pid = int.parse(kill0.group(1)!);
      if (unknown.contains(pid)) return const RunOutcome(1, '', '');
      return RunOutcome(0, alive.contains(pid) ? 'alive' : 'gone', '');
    }
    return defaultOutcome;
  }
}

class _World {
  _World({
    Set<int> alive = const {},
    String handlers = '',
    String avdName = 'anta_qa_1\r\nOK',
    this.windows = true,
  }) {
    root = Directory.systemTemp.createTempSync('anta_qa_reap_');
    paths = QaPaths(root.path)..ensureBuildQa();
    paths.ensureFleetState();
    final avds = Directory(joinPath(root.path, ['avd']))..createSync();
    for (final name in ['anta_qa_1', 'anta_qa_2']) {
      File(joinPath(avds.path, ['$name.ini'])).writeAsStringSync('path=x\n');
      final dir = Directory(joinPath(avds.path, ['$name.avd']))..createSync();
      File(joinPath(dir.path, ['config.ini'])).writeAsStringSync('x=1\n');
    }
    runner = _HostRunner(
      alive: alive,
      handlers: handlers,
      wrapper: paths.runWrapperFor(windows: false),
      avdName: avdName,
    );
    host = FleetHost(
      runner: runner,
      adb: Adb(executable: 'adb', runner: runner),
      avdHome: avds.path,
      sdkRoot: joinPath(root.path, ['sdk']),
      windows: windows,
      pollEvery: Duration.zero,
    );
  }

  late final Directory root;
  late final QaPaths paths;
  late final _HostRunner runner;
  late final FleetHost host;
  final bool windows;
  int runStops = 0;

  String file(String name) => joinPath(paths.buildQa, [name]);

  void write(String name, String text) =>
      File(file(name)).writeAsStringSync(text);

  bool exists(String name) => File(file(name)).existsSync();

  /// The host-wide fleet directory's files.
  String fleetFile(String name) => joinPath(paths.fleetState, [name]);

  void writeFleet(String name, String text) =>
      File(fleetFile(name)).writeAsStringSync(text);

  bool existsFleet(String name) => File(fleetFile(name)).existsSync();

  /// What `reap` quiets a guest with; null quiets nothing.
  Future<GuestQuiet?> Function(FleetMember member)? quiet;

  HostReaper reaper() => HostReaper(
    paths: paths,
    runner: runner,
    host: host,
    windows: windows,
    quiet: quiet,
    isAlive: (pid) async {
      onProbe?.call(pid);
      return runner.unknown.contains(pid)
          ? Liveness.unknown
          : runner.alive.contains(pid)
          ? Liveness.alive
          : Liveness.gone;
    },
    stopRun: () async {
      runStops++;
      final run = File(paths.runPid);
      if (!run.existsSync()) return const [];
      final pid = int.parse(run.readAsStringSync());
      run.deleteSync();
      runner.alive.remove(pid);
      return ['killed run pid $pid'];
    },
  );

  /// Called before every liveness answer: where a test makes a file vanish
  /// between the survey's listing and its read.
  void Function(int pid)? onProbe;

  Future<(List<String>, ({List<String> left, bool failed}))> reap({
    bool dryRun = false,
    bool force = false,
    bool prune = false,
  }) async {
    final lines = <String>[];
    final outcome = await reaper().reap(
      dryRun: dryRun,
      force: force,
      prune: prune,
      say: lines.add,
    );
    return (lines, outcome);
  }

  void dispose() => root.deleteSync(recursive: true);
}

void main() {
  final now = DateTime.utc(2026, 11, 11, 9);

  group('guest state', () {
    late Directory temp;
    late String path;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_guest_');
      path = joinPath(temp.path, ['guest_anta_qa_1.json']);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('a hold taken during another process\'s update is not lost', () async {
      GuestState.booted(path, now);
      // Another process is mid-update: it has the lock and has read the
      // file, and writes its change a moment later.
      final lock = lockStateFile(path, wait: Duration.zero)!;
      final hold = GuestHold(pid: 77, verb: 'pass', since: now);
      final taking = Isolate.run(() => GuestState.take(path, hold));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      writeFileAtomically(
        path,
        jsonEncode(
          GuestState(bootedAt: now, lastUsedAt: now, keep: true).toJson(),
        ),
      );
      lock.deleteSync();
      expect(await taking, isTrue);
      final state = GuestState.read(path)!;
      expect(state.keep, isTrue, reason: 'the other process\'s change stands');
      expect(state.hold?.pid, 77, reason: 'and the hold went on top of it');
      expect(File('$path.lock').existsSync(), isFalse);
    });

    test('a qa run holds its fleet guest until it is let go', () {
      final root = joinPath(temp.path, ['checkout']);
      final paths = QaPaths(root)..ensureFleetState();
      final state = paths.guestStateFor('anta_qa_1');
      expect(takeRunHold(paths, 'emulator-5554', 300), isFalse);
      expect(takeRunHold(paths, 'emulator-5556', 300), isTrue);
      final hold = GuestState.read(state)!.hold!;
      expect((hold.verb, hold.pid, hold.checkout), ('run', 300, root));

      expect(
        releaseRunHold(paths, 'emulator-5556', wrapperPid: 301),
        isFalse,
        reason: 'another run\'s end is not this one\'s',
      );
      expect(
        releaseRunHold(
          QaPaths(temp.path, fleetState: paths.fleetState),
          'emulator-5556',
        ),
        isFalse,
        reason: 'a worktree lets go of its own run only',
      );
      expect(releaseRunHold(paths, 'emulator-5556'), isTrue);
      expect(GuestState.read(state)!.hold, isNull);

      GuestState.take(state, GuestHold(pid: 77, verb: 'pass', since: now));
      expect(
        releaseRunHold(paths, 'emulator-5556'),
        isFalse,
        reason: 'a pass\'s hold is never a run\'s to clear',
      );
      expect(GuestState.read(state)!.hold?.pid, 77);
    });

    test('a heartbeat gives up on a busy lock; a stale one is taken over', () {
      GuestState.booted(path, now);
      final lock = lockStateFile(path, wait: Duration.zero)!;
      final later = now.add(const Duration(minutes: 1));
      final started = DateTime.now();
      expect(GuestState.touch(path, later), isFalse);
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 3)),
      );
      expect(GuestState.read(path)!.lastUsedAt, now);

      // Left by a process that died inside its update.
      lock.setLastModifiedSync(
        DateTime.now().subtract(stateLockStale * 2),
      );
      expect(
        GuestState.take(path, GuestHold(pid: 77, verb: 'pass', since: later)),
        isTrue,
      );
      expect(GuestState.read(path)!.hold?.pid, 77);
    });

    test(
      'a boot, a use, a hold and its release round-trip through the file',
      () {
        expect(GuestState.read(path), isNull);
        GuestState.booted(path, now);
        expect(GuestState.read(path)!.bootedAt, now);
        final hold = GuestHold(
          pid: 77,
          verb: 'pass',
          since: now.add(const Duration(minutes: 5)),
        );
        GuestState.take(path, hold);
        final held = GuestState.read(path)!;
        expect(
          (held.hold!.pid, held.hold!.verb, held.hold!.since),
          (77, 'pass', hold.since),
        );
        expect(held.bootedAt, now, reason: 'a hold keeps the boot');

        GuestState.booted(path, now.add(const Duration(minutes: 6)));
        expect(
          GuestState.read(path)!.hold?.pid,
          77,
          reason: 'a recycle boots the guest its pass still holds',
        );

        GuestState.release(path, 99, now.add(const Duration(minutes: 7)));
        expect(
          GuestState.read(path)!.hold?.pid,
          77,
          reason: 'only the holder clears it',
        );

        final done = now.add(const Duration(minutes: 20));
        GuestState.release(path, 77, done);
        final released = GuestState.read(path)!;
        expect(released.hold, isNull);
        expect(
          released.lastUsedAt,
          done,
          reason: 'the pass used it until it ended',
        );
        expect(GuestState.forget(path), isTrue);
        expect(File(path).existsSync(), isFalse);
        expect(GuestState.forget(path), isFalse);
      },
    );

    test('the idle age runs from the last use, else from the boot', () {
      expect(const GuestState().idleAge(now), isNull);
      expect(
        GuestState(
          bootedAt: now.subtract(const Duration(hours: 1)),
        ).idleAge(now),
        const Duration(hours: 1),
      );
      expect(
        GuestState(
          bootedAt: now.subtract(const Duration(hours: 1)),
          lastUsedAt: now.subtract(const Duration(minutes: 4)),
        ).idleAge(now),
        const Duration(minutes: 4),
      );
      expect(
        GuestState(
          lastUsedAt: now.add(const Duration(seconds: 5)),
        ).idleAge(now),
        Duration.zero,
      );
      expect(idleLabel(const Duration(seconds: 35)), '35s');
      expect(idleLabel(const Duration(minutes: 12)), '12m');
      expect(idleLabel(const Duration(hours: 2, minutes: 5)), '2h05m');
    });

    test('a hold whose holder is gone holds nothing', () {
      final state = GuestState(
        hold: GuestHold(pid: 5, verb: 'pass', since: now),
      );
      expect(state.liveHold(holderAlive: true)?.pid, 5);
      expect(state.liveHold(holderAlive: false), isNull);
    });

    test('a damaged file reads as unknown and is never replaced by less', () {
      File(path).writeAsStringSync('{"hold":{"pid":77,"verb":"pass",');
      final read = GuestState.read(path)!;
      expect(read.unreadable, isTrue, reason: 'a torn file is not "no hold"');
      expect(GuestState.touch(path, now), isFalse);
      expect(
        GuestState.take(path, GuestHold(pid: 5, verb: 'pass', since: now)),
        isFalse,
      );
      expect(
        File(path).readAsStringSync(),
        '{"hold":{"pid":77,"verb":"pass",',
        reason: 'a writer that cannot read the file leaves it as it is',
      );
      expect(GuestState.parse('[1]'), isNull);
      expect(GuestState.parse('{"hold":{"pid":"x"}}')!.hold, isNull);
    });

    test('a write lands whole through a rename and leaves no temp file', () {
      GuestState.take(
        path,
        GuestHold(pid: 77, verb: 'pass', since: now, checkout: r'D:\wt'),
      );
      expect(temp.listSync().map((e) => e.uri.pathSegments.last), [
        'guest_anta_qa_1.json',
      ]);
      final hold = GuestState.read(path)!.hold!;
      expect(hold.checkout, r'D:\wt');
      expect(hold.label, endsWith(r' from D:\wt'));
    });

    test('a heartbeat moves the holder\'s beat and the last use', () {
      GuestState.take(path, GuestHold(pid: 77, verb: 'pass', since: now));
      final later = now.add(const Duration(hours: 4));
      GuestState.beat(path, 77, later);
      var read = GuestState.read(path)!;
      expect((read.hold!.since, read.hold!.lastBeat), (now, later));
      expect(read.lastUsedAt, later);
      GuestState.beat(path, 99, later.add(const Duration(minutes: 1)));
      read = GuestState.read(path)!;
      expect(read.hold!.lastBeat, later, reason: 'only the holder beats');
    });

    test(
      'a restart\'s boot keeps --keep-up; only removing the file clears it',
      () {
        GuestState.booted(path, now, keep: true);
        GuestState.booted(path, now.add(const Duration(minutes: 1)));
        expect(
          GuestState.read(path)!.keep,
          isTrue,
          reason: 'a recovery or a recycle boots through a plain child',
        );
        GuestState.forget(path);
        GuestState.booted(path, now.add(const Duration(minutes: 2)));
        expect(GuestState.read(path)!.keep, isFalse);
      },
    );

    test('only a fleet serial has a state file', () {
      final paths = QaPaths(temp.path);
      expect(
        guestStatePathFor(paths, 'emulator-5558'),
        paths.guestStateFor('anta_qa_2'),
      );
      expect(guestStatePathFor(paths, 'emulator-5554'), isNull);
      expect(
        guestStatePathFor(paths, 'emulator-5680'),
        isNull,
        reason: 'ANTA_Personal\'s port is never a fleet guest\'s',
      );
      expect(fleetIndexOf('anta_qa_63'), isNull);
      expect(() => parseFleetArgument('63'), throwsA(isA<UsageFailure>()));
      expect(guestStatePathFor(paths, 'R5CT30ABCDE'), isNull);
      expect(guestStatePathFor(paths, 'macos'), isNull);
    });

    test(
      'status shows the idle age and the live holder of a guest that is up',
      () {
        final member = FleetMember(
          index: 1,
          created: true,
          state: FleetState.device,
          qemu: const QemuProcess(pid: 4242, avd: 'anta_qa_1', port: 5556),
          guest: GuestState(
            lastUsedAt: now.subtract(const Duration(minutes: 42)),
          ),
        ).withHold(GuestHold(pid: 77, verb: 'pass', since: now));
        final line = fleetStatusLine(
          member,
          null,
          showAffinity: false,
          now: now,
        );
        expect(line, contains('idle=42m'));
        expect(line, contains('held by pass pid 77 since'));
        expect(member.toJson(null)['hold'], containsPair('pid', 77));
        expect(member.toJson(null).containsKey('idleSeconds'), isTrue);
      },
    );
  });

  group('scripts', () {
    const sdk = r'D:\Sdk\emulator';

    test(
      'the crash handler scripts hold no double quote and match the emulator directory',
      () {
        final list = crashHandlerListScript(sdk);
        final kill = crashHandlerKillScript(31, sdk);
        for (final script in [
          list,
          kill,
          recordedRunProbeScript(31, r'D:\anta\build\qa\run_cmd.bat'),
        ]) {
          expect(
            script,
            isNot(contains('"')),
            reason: '-Command mangles double quotes',
          );
        }
        expect(
          list,
          contains(r"StartsWith('D:\Sdk\emulator\'"),
          reason: 'the trailing separator keeps emulator2 out',
        );
        expect(list, contains("'crashpad_handler.exe'"));
        expect(list, isNot(contains('Stop-Process')));
        expect(kill, contains("-Filter 'ProcessId=31'"));
        expect(kill, contains('Stop-Process -Id 31 -Force'));
        expect(
          kill,
          contains('CreationDate -gt'),
          reason: 'a parent pid reused by a newer process counts as gone',
        );
      },
    );

    test('parses the orphans the list printed', () {
      expect(
        parseCrashHandlers(
          '31\t9\tD:\\Sdk\\emulator\\crashpad_handler.exe\r\nnoise\n',
        ),
        [
          isA<CrashHandler>().having((h) => (h.pid, h.parentPid), 'pids', (
            31,
            9,
          )),
        ],
      );
      expect(parseCrashHandlers(''), isEmpty);
    });

    test('a run probe tells the harness run from a reused pid', () {
      final script = recordedRunProbeScript(
        8200,
        r'D:\anta\build\qa\run_cmd.bat',
      );
      expect(script, contains(r"IndexOf('D:\anta\build\qa\run_cmd.bat'"));
      expect(script, contains("'ours'"));
    });

    test('pruning keeps the newest twenty per suite and leaves odd names', () {
      expect(
        keptPassDirs,
        defaultHistoryReports,
        reason: 'qa pass --history reads what --prune keeps',
      );
      final names = [
        for (var i = 0; i < 22; i++)
          'alerts_202611${(i + 1).toString().padLeft(2, '0')}_120000_000_emulator-5556',
        'alerts_pair_20261101_120000_000_emulator-5556',
        'calendar_20261023_183638_360_fleet',
        'scratch',
      ];
      expect(prunablePassDirs(names), [
        'alerts_20261101_120000_000_emulator-5556',
        'alerts_20261102_120000_000_emulator-5556',
      ]);
      expect(prunablePassDirs(names, keep: 0), hasLength(24));
    });

    test('URI files are matched to emulator serials only', () {
      expect(
        emulatorUriFiles([
          'vm_emulator-5556.txt',
          'dtd_emulator-5554.txt',
          'vm_macos.txt',
          'last_dump_emulator-5556.txt',
        ]),
        {
          'vm_emulator-5556.txt': 'emulator-5556',
          'dtd_emulator-5554.txt': 'emulator-5554',
        },
      );
    });

    test('the timeout tree kill is forced and recursive', () {
      expect(treeKillArgs(42), ['/PID', '42', '/T', '/F']);
    });
  });

  group('reap', () {
    late _World world;
    tearDown(() => world.dispose());

    test(
      'stops a guest nobody holds and leaves the host clean in one call',
      () async {
        world = _World(alive: {300});
        world.write('emulator_anta_qa_1.pid', '100');
        world.write('emulator_anta_qa_2.pid', '200');
        world.write('emulator.pid', '300');
        world.write('vm_emulator-5556.txt', 'http://x');
        world.write('vm_emulator-5558.txt', 'http://y');
        world.write('vm_emulator-5554.txt', 'http://z');
        world.writeFleet('guest_anta_qa_2.json', '{}');
        GuestState.booted(world.paths.guestStateFor('anta_qa_1'), now);
        final (lines, outcome) = await world.reap();
        expect(lines.first, startsWith('stopped: anta_qa_1 (emulator-5556)'));
        expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
        expect(
          world.runner.lines.where((l) => l.contains('Stop-Process')),
          isEmpty,
          reason: 'a guest on adb stops through its console',
        );
        expect(world.existsFleet('guest_anta_qa_1.json'), isFalse);
        expect(world.existsFleet('guest_anta_qa_2.json'), isFalse);
        expect(world.exists('emulator_anta_qa_1.pid'), isFalse);
        expect(world.exists('emulator_anta_qa_2.pid'), isFalse);
        expect(
          world.exists('emulator.pid'),
          isTrue,
          reason: 'its process is alive',
        );
        expect(world.exists('vm_emulator-5556.txt'), isFalse);
        expect(world.exists('vm_emulator-5558.txt'), isFalse);
        expect(
          world.exists('vm_emulator-5554.txt'),
          isTrue,
          reason: 'attached',
        );
        expect(outcome.left, isEmpty);
        expect(outcome.failed, isFalse);
        expect(
          qa.reapVerdict(
            left: outcome.left,
            dryRun: false,
            actions: lines.length,
          ),
          'reap: clean',
        );
      },
    );

    test(
      'a guest a live pass holds is skipped without --force and stopped with it',
      () async {
        world = _World(alive: {77});
        GuestState.take(
          world.paths.guestStateFor('anta_qa_1'),
          GuestHold(pid: 77, verb: 'pass', since: now),
        );
        var (lines, outcome) = await world.reap();
        expect(
          lines,
          contains(
            startsWith('skip: anta_qa_1 (emulator-5556) — held by pass pid 77'),
          ),
        );
        expect(
          world.runner.lines,
          isNot(contains('adb -s emulator-5556 emu kill')),
        );
        expect(outcome.left, [startsWith('anta_qa_1 held by pass pid 77')]);
        expect(
          outcome.failed,
          isFalse,
          reason: 'nothing that was tried failed',
        );
        expect(
          qa.reapVerdict(left: outcome.left, dryRun: false, actions: 1),
          startsWith('reap: left — anta_qa_1 held by pass pid 77'),
        );

        (lines, outcome) = await world.reap(force: true);
        expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
        expect(outcome.left, isEmpty);
      },
    );

    test(
      'the hold of the run reap ends goes with it; another checkout\'s stays',
      () async {
        world = _World(alive: {8200});
        world.write('run.pid', '8200');
        takeRunHold(world.paths, 'emulator-5556', 8200);
        final (lines, outcome) = await world.reap();
        expect(lines.first, 'killed run pid 8200');
        expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
        expect(outcome.left, isEmpty);

        world.dispose();
        world = _World(alive: {8300});
        GuestState.take(
          world.paths.guestStateFor('anta_qa_1'),
          GuestHold(
            pid: 8300,
            verb: 'run',
            since: now,
            checkout: r'D:\wt\anta',
          ),
        );
        final (_, other) = await world.reap();
        expect(other.left, [startsWith('anta_qa_1 held by run pid 8300')]);
      },
    );

    group('quiets a guest before it stops it', () {
      late List<String> quieted;
      void quietWith(GuestQuiet result) {
        quieted = [];
        world.quiet = (member) async {
          quieted.add(member.name);
          expect(
            world.runner.lines,
            isNot(contains('adb -s emulator-5556 emu kill')),
            reason: 'the quiet comes before the stop',
          );
          return result;
        };
      }

      test('says what it cancelled, then stops', () async {
        world = _World();
        quietWith(const GuestQuiet(before: 3, after: 0, relaunched: true));
        final (lines, outcome) = await world.reap();
        expect(quieted, ['anta_qa_1']);
        expect(lines.take(2), [
          'quiet: 3 alarm(s) on anta_qa_1 cancelled before the stop',
          startsWith('stopped: anta_qa_1 (emulator-5556)'),
        ]);
        expect(outcome.failed, isFalse);
      });

      test('a guest with nothing armed stops with its usual lines', () async {
        world = _World();
        quietWith(const GuestQuiet(before: 0));
        final (lines, _) = await world.reap();
        expect(lines.first, startsWith('stopped: anta_qa_1 (emulator-5556)'));
      });

      test('a quiet that fails warns and the stop goes ahead', () async {
        world = _World();
        quietWith(const GuestQuiet(failure: 'the relaunch exited 3'));
        final (lines, outcome) = await world.reap();
        expect(lines.first, startsWith('warning: quiet: anta_qa_1 was not'));
        expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
        expect(outcome.failed, isFalse);
      });

      test('a held guest is never quieted, even with --force', () async {
        world = _World(alive: {77});
        quietWith(const GuestQuiet(before: 3, after: 0, relaunched: true));
        GuestState.take(
          world.paths.guestStateFor('anta_qa_1'),
          GuestHold(pid: 77, verb: 'pass', since: now),
        );
        await world.reap(force: true);
        expect(quieted, isEmpty);
        expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
      });

      test('a dry run quiets nothing', () async {
        world = _World();
        quietWith(const GuestQuiet(before: 3, after: 0, relaunched: true));
        await world.reap(dryRun: true);
        expect(quieted, isEmpty);
      });
    });

    test('a hold whose pass died holds nothing', () async {
      world = _World();
      GuestState.take(
        world.paths.guestStateFor('anta_qa_1'),
        GuestHold(pid: 77, verb: 'pass', since: now),
      );
      await world.reap();
      expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
    });

    test('a dry run says everything and changes nothing', () async {
      world = _World(
        handlers: '31\t9\tD:\\sdk\\emulator\\crashpad_handler.exe',
      );
      world.write('emulator_anta_qa_2.pid', '200');
      world.write('run.pid', '8200');
      final (lines, outcome) = await world.reap(dryRun: true, prune: true);
      expect(
        lines,
        contains('would stop anta_qa_1 (emulator-5556, qemu 4242)'),
      );
      expect(
        lines,
        contains('would remove emulator_anta_qa_2.pid (pid 200 is gone)'),
      );
      expect(
        lines,
        contains(startsWith('would end orphaned emulator crash handler 31')),
      );
      expect(
        world.runner.lines.where(
          (l) => l.contains('emu kill') || l.contains('Stop-Process'),
        ),
        isEmpty,
      );
      expect(world.exists('emulator_anta_qa_2.pid'), isTrue);
      expect(world.exists('run.pid'), isTrue);
      expect(world.runStops, 0);
      expect(
        qa.reapVerdict(left: outcome.left, dryRun: true, actions: lines.length),
        startsWith('reap: dry run'),
      );
    });

    test('ends an orphaned crash handler and touches no forward', () async {
      world = _World(
        handlers: '31\t9\tD:\\sdk\\emulator\\crashpad_handler.exe',
      );
      final (lines, _) = await world.reap();
      expect(
        lines,
        contains('ended orphaned emulator crash handler 31 (parent 9 gone)'),
      );
      expect(
        world.runner.lines.where((l) => l.contains('forward')),
        isEmpty,
        reason: 'adb drops a stopped emulator\'s forwards by itself',
      );
    });

    test('a live guard stays; it exits once no guest is left', () async {
      world = _World(alive: {900});
      world.writeFleet('guard.pid', '900\nidle=30\npoll=60\n');
      world.writeFleet('guard_1.exe', 'x');
      final (lines, outcome) = await world.reap();
      expect(
        lines,
        contains(
          'guard pid 900 exits by itself within 120 s (no fleet guest is left)',
        ),
      );
      expect(world.existsFleet('guard.pid'), isTrue);
      expect(
        world.existsFleet('guard_1.exe'),
        isTrue,
        reason: 'the guard runs from it',
      );
      expect(outcome.left, isEmpty);
    });

    test(
      'a guard.pid whose pid is no longer a guard is removed, with the copies',
      () async {
        world = _World();
        world.writeFleet('guard.pid', '901\n');
        world.writeFleet('guard_1.exe', 'x');
        world.writeFleet('guard_2.exe.tmp', 'x');
        final (lines, _) = await world.reap();
        expect(
          lines,
          contains('removed guard.pid (pid 901 is no longer a guard)'),
        );
        expect(lines, contains('removed guard_1.exe (no guard runs from it)'));
        expect(world.existsFleet('guard.pid'), isFalse);
        expect(world.existsFleet('guard_1.exe'), isFalse);
        expect(world.existsFleet('guard_2.exe.tmp'), isFalse);
      },
    );

    test('the old per-checkout fleet files are removed', () async {
      world = _World(alive: {900});
      for (final name in [
        'guest_anta_qa_1.json',
        'guard.pid',
        'guard.log',
        'guard_1.exe',
      ]) {
        world.write(name, '900\n');
      }
      world.write('apk.json', '{}');
      final (lines, _) = await world.reap();
      for (final name in [
        'guest_anta_qa_1.json',
        'guard.pid',
        'guard.log',
        'guard_1.exe',
      ]) {
        expect(world.exists(name), isFalse, reason: name);
        expect(
          lines,
          contains(startsWith('removed $name (fleet state now lives in')),
        );
      }
      expect(world.exists('apk.json'), isTrue, reason: 'per checkout');
    });

    test(
      'a hold whose holder could not be checked protects its guest',
      () async {
        world = _World();
        world.runner.unknown.add(77);
        GuestState.take(
          world.paths.guestStateFor('anta_qa_1'),
          GuestHold(pid: 77, verb: 'pass', since: now),
        );
        final (lines, outcome) = await world.reap();
        expect(
          world.runner.lines,
          isNot(contains('adb -s emulator-5556 emu kill')),
        );
        expect(lines, contains(contains('held by pass pid 77')));
        expect(lines, contains(contains('(its process could not be checked)')));
        expect(outcome.left, isNotEmpty);
      },
    );

    test('a state file that does not read protects its guest', () async {
      world = _World();
      world.writeFleet('guest_anta_qa_1.json', '{"hold":');
      final (lines, _) = await world.reap();
      expect(
        world.runner.lines,
        isNot(contains('adb -s emulator-5556 emu kill')),
      );
      expect(lines, contains(contains('held by an unreadable state file')));
      expect(world.existsFleet('guest_anta_qa_1.json'), isTrue);
    });

    test('a pid file whose owner could not be checked is kept', () async {
      world = _World();
      world.runner.unknown.add(200);
      world.write('emulator_anta_qa_2.pid', '200');
      await world.reap();
      expect(world.exists('emulator_anta_qa_2.pid'), isTrue);
    });

    test('a fleet qemu on a port that answers as something else is reported, '
        'and reap is not clean', () async {
      for (final answer in ['Pixel_9_Pro\r\nOK', '']) {
        world = _World(avdName: answer);
        final (lines, outcome) = await world.reap();
        expect(
          lines,
          contains(startsWith('left: anta_qa_1 (emulator-5556, qemu 4242)')),
          reason: answer,
        );
        expect(outcome.left, contains(contains('anta_qa_1 qemu 4242')));
        expect(outcome.failed, isTrue);
        expect(
          world.runner.lines.where(
            (l) => l.contains('emu kill') || l.contains('Stop-Process'),
          ),
          isEmpty,
        );
        world.dispose();
      }
      world = _World();
    });

    test('a failed crash handler kill stays failed after a mismatch', () async {
      world = _World(
        handlers:
            '31\t9\tD:\\sdk\\emulator\\crashpad_handler.exe\n'
            '32\t9\tD:\\sdk\\emulator\\crashpad_handler.exe',
      );
      var said = 0;
      world.runner.killAnswers = () => ++said == 1 ? '' : 'mismatch';
      final (_, outcome) = await world.reap();
      expect(outcome.failed, isTrue);
      expect(outcome.left, ['crash handler 31']);
    });

    test('a file that vanishes under the survey is no failure', () async {
      world = _World(
        handlers: '31\t9\tD:\\sdk\\emulator\\crashpad_handler.exe',
      );
      world.write('emulator_anta_qa_1.pid', '100');
      world.write('emulator_anta_qa_2.pid', '200');
      world.write('emulator_anta_qa_3.pid', '300');
      // The second pid file goes between the listing and its read; the
      // third, found stale, goes before reap removes it.
      world.onProbe = (pid) {
        final second = File(world.file('emulator_anta_qa_2.pid'));
        if (pid == 100 && second.existsSync()) second.deleteSync();
      };
      world.runner.killAnswers = () {
        final third = File(world.file('emulator_anta_qa_3.pid'));
        if (third.existsSync()) third.deleteSync();
        return 'killed';
      };
      final (lines, outcome) = await world.reap();
      expect(outcome.failed, isFalse);
      expect(lines.where((l) => l.startsWith('failed')), isEmpty);
      expect(
        lines,
        contains(startsWith('removed emulator_anta_qa_3.pid (pid 300 is gone')),
      );
    });

    test(
      'a run.pid the harness no longer owns is forgotten, never killed',
      () async {
        world = _World();
        world.write('run.pid', '8200');
        final (lines, _) = await world.reap();
        expect(lines, contains(startsWith('remove run.pid: pid 8200 is')));
        expect(world.exists('run.pid'), isFalse);
        expect(
          world.runStops,
          1,
          reason: 'kill-run then forgets the dead run\'s URIs',
        );
      },
    );

    test('off Windows only the run and the files are reaped', () async {
      world = _World(windows: false, alive: {8200});
      world.write('run.pid', '8200');
      world.write('emulator.pid', '1');
      final (lines, outcome) = await world.reap();
      expect(world.runStops, 1);
      expect(
        world.runner.lines.where(
          (l) => l.startsWith('adb') || l.startsWith('powershell'),
        ),
        isEmpty,
      );
      expect(world.exists('emulator.pid'), isFalse);
      expect(lines, contains('removed emulator.pid (pid 1 is gone)'));
      expect(outcome.failed, isFalse);
    });

    test('a boot lock is removed only when its owner is gone', () async {
      String lock(int pid) => jsonEncode({
        'pid': pid,
        'avd': 'anta_qa_2',
        'at': DateTime.now().toIso8601String(),
        'checkout': '/elsewhere',
      });
      world = _World(windows: false, alive: {8300});
      world.writeFleet('boot.lock', lock(8300));
      await world.reap();
      expect(world.existsFleet('boot.lock'), isTrue, reason: 'a live boot');
      world.runner.unknown.add(8301);
      world.writeFleet('boot.lock', lock(8301));
      await world.reap();
      expect(world.existsFleet('boot.lock'), isTrue, reason: 'unchecked');
      world.writeFleet('boot.lock', lock(8302));
      final (lines, _) = await world.reap();
      expect(world.existsFleet('boot.lock'), isFalse);
      expect(
        lines,
        contains('removed boot.lock (pid 8302 booting anta_qa_2 is gone)'),
      );
    });

    test(
      'off Windows a live pid is the run only while it runs this checkout\'s '
      'wrapper',
      () async {
        world = _World(windows: false, alive: {8200});
        world.runner.others.add(8200);
        world.write('run.pid', '8200');
        final (lines, _) = await world.reap(dryRun: true);
        expect(
          lines,
          contains(
            'would remove run.pid: pid 8200 is no longer the harness\'s run '
            '(left running)',
          ),
        );
        expect(
          lines.where((l) => l.contains('stop the recorded flutter run')),
          isEmpty,
        );
      },
    );

    test('a rebuild lock older than its time to live is stale', () async {
      world = _World(windows: false);
      final lock = File(world.paths.rebuildLock)..writeAsStringSync('');
      lock.setLastModifiedSync(DateTime.now().subtract(rebuildLockTtl * 2));
      await world.reap();
      expect(lock.existsSync(), isFalse);
    });

    test('prune deletes old pass directories only', () async {
      world = _World(windows: false);
      for (var i = 1; i <= keptPassDirs + 1; i++) {
        Directory(
          joinPath(world.paths.passRoot, [
            'demo_202611${i.toString().padLeft(2, '0')}_120000_000_emulator-5556',
          ]),
        ).createSync(recursive: true);
      }
      File(world.paths.latestPassFor('demo')).writeAsStringSync('x');
      final (lines, _) = await world.reap(prune: true);
      expect(lines, ['pruned pass/demo_20261101_120000_000_emulator-5556']);
      expect(File(world.paths.latestPassFor('demo')).existsSync(), isTrue);
    });
  });

  group('doctor', () {
    test('leftovers name reap', () {
      expect(
        checkLeftovers(
          idleGuests: [],
          orphanedCrashHandlers: [],
          stalePidFiles: [],
        ).status,
        CheckStatus.ok,
      );
      final warn = checkLeftovers(
        idleGuests: ['anta_qa_1 idle=42m'],
        orphanedCrashHandlers: [31],
        stalePidFiles: ['emulator.pid'],
      );
      expect(warn.status, CheckStatus.warn);
      expect(
        warn.detail,
        'idle fleet guests: anta_qa_1 idle=42m; orphaned emulator crash handlers: 31; stale pid files: emulator.pid',
      );
      expect(warn.fix, startsWith('`qa reap`'));
    });

    test('a guest up with no guard running is a warning', () {
      final warn = checkLeftovers(
        idleGuests: [],
        orphanedCrashHandlers: [],
        stalePidFiles: [],
        unguardedGuests: ['anta_qa_1'],
      );
      expect(warn.status, CheckStatus.warn);
      expect(
        warn.detail,
        'no idle guard runs while anta_qa_1 is up (`qa fleet boot` of a '
        'guest that is up starts one)',
      );
    });

    test('armed app alarms on a guest no one holds are a leftover', () {
      final warn = checkLeftovers(
        idleGuests: [],
        orphanedCrashHandlers: [],
        stalePidFiles: [],
        armedGuests: ['anta_qa_1 (3)', 'anta_qa_2 (0, ringing)'],
      );
      expect(warn.status, CheckStatus.warn);
      expect(
        warn.detail,
        startsWith(
          'app alarms armed or ringing on fleet guests no one holds: '
          'anta_qa_1 (3), anta_qa_2 (0, ringing)',
        ),
      );
      expect(warn.fix, startsWith('`qa reap`'));
    });
  });

  test(
    'a guest on adb whose console is dead falls through to the guarded kill',
    () async {
      final world = _World();
      addTearDown(world.dispose);
      world.runner
        ..consoleDead = true
        ..killAnswers = () {
          world.runner.down = true;
          return 'killed';
        };
      final said = await world.host.forceStop(1);
      expect(
        said,
        startsWith(
          'stopped: anta_qa_1 (qemu 4242 killed, its console stop failed: ',
        ),
      );
      final kill = world.runner.lines.singleWhere(
        (l) => l.contains('Stop-Process'),
      );
      expect(kill, contains('anta_qa_1'), reason: 'the AVD guard stays');
      expect(kill, isNot(contains('5554')));
    },
  );

  test('fleet stop forgets the guest\'s state file', () async {
    final world = _World(windows: false);
    addTearDown(world.dispose);
    GuestState.booted(world.paths.guestStateFor('anta_qa_1'), now);
    final qaRunner = QaCommandRunner(
      contextFactory: (globals) =>
          _FleetContext(globals, paths: world.paths, host: world.host),
      commands: [FleetCommand()],
    )..lineSink = (line, {required prefix, required isError}) {};
    expect(await qaRunner.run(['fleet', 'stop', '1']), 0);
    expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
    expect(world.existsFleet('guest_anta_qa_1.json'), isFalse);
    expect(
      world.existsFleet('stop_anta_qa_1.json'),
      isFalse,
      reason: 'no hold, so no pass to tell',
    );
  });

  group('fleet stop quiets a guest no one holds', () {
    late _World world;
    late List<String> said;
    late List<String> quieted;
    late _FleetContext ctx;

    Future<int?> stop(List<String> args) {
      ctx = _FleetContext(
        QaCommandRunner().argParser.parse(const []),
        paths: world.paths,
        host: world.host,
      )..quiet = (serial) async {
          quieted.add(serial);
          expect(
            world.runner.lines,
            isNot(contains('adb -s emulator-5556 emu kill')),
            reason: 'the quiet comes before the stop',
          );
          return const GuestQuiet(before: 3, after: 0, relaunched: true);
        };
      return (QaCommandRunner(
        contextFactory: (_) => ctx,
        commands: [FleetCommand()],
      )..lineSink = (line, {required prefix, required isError}) =>
          said.add(line)).run(['fleet', 'stop', ...args]);
    }

    setUp(() {
      world = _World(windows: false, alive: {300});
      said = [];
      quieted = [];
    });
    tearDown(() => world.dispose());

    test('says what it cancelled, then stops', () async {
      expect(await stop(['1']), 0);
      expect(quieted, ['emulator-5556']);
      expect(
        ctx.alwaysAsked,
        [true],
        reason: 'the count cannot see what a force-stopped app stores',
      );
      expect(said, [
        'quiet: 3 alarm(s) on anta_qa_1 cancelled before the stop',
        startsWith('stopped: anta_qa_1 (emulator-5556)'),
      ]);
    });

    test('--as-crash stands in for a crash and quiets nothing', () async {
      expect(await stop(['1', '--force', '--as-crash']), 0);
      expect(quieted, isEmpty);
    });

    test('a held guest is its holder\'s: --force stops it unquieted', () async {
      GuestState.take(
        world.paths.guestStateFor('anta_qa_1'),
        GuestHold(pid: 300, verb: 'pass', since: now),
      );
      expect(await stop(['1', '--force']), 0);
      expect(quieted, isEmpty);
    });

    test('a port another emulator answers on is never quieted', () async {
      world.dispose();
      world = _World(windows: false, avdName: 'Pixel_9_Pro\r\nOK');
      await stop(['1']);
      expect(quieted, isEmpty);
    });
  });

  group('a stop someone asks for on a held guest', () {
    late _World world;
    late List<String> said;
    QaCommandRunner fleetRunner() => QaCommandRunner(
      contextFactory: (globals) =>
          _FleetContext(globals, paths: world.paths, host: world.host),
      commands: [FleetCommand()],
    )..lineSink = (line, {required prefix, required isError}) => said.add(line);

    setUp(() {
      world = _World(windows: false, alive: {300});
      said = [];
      GuestState.take(
        world.paths.guestStateFor('anta_qa_1'),
        GuestHold(pid: 300, verb: 'pass', since: now, checkout: r'D:\wt\anta'),
      );
    });
    tearDown(() => world.dispose());

    StopRequest? request() =>
        StopRequest.read(world.paths.stopRequestFor('anta_qa_1'));

    test('a plain fleet stop refuses it and names the holder and its '
        'checkout', () async {
      expect(await fleetRunner().run(['fleet', 'stop', '1']), exitDevice);
      expect(
        said.single,
        startsWith(r'refused: anta_qa_1 — held by pass pid 300 since '),
      );
      expect(said.single, contains(r'from D:\wt\anta'));
      expect(said.single, contains('`qa fleet stop anta_qa_1 --force`'));
      expect(
        world.runner.lines,
        isNot(contains('adb -s emulator-5556 emu kill')),
      );
      expect(world.existsFleet('guest_anta_qa_1.json'), isTrue);
      expect(request(), isNull);
    });

    test('a holder that cannot be checked protects the same way', () async {
      world.runner
        ..alive.remove(300)
        ..unknown.add(300);
      expect(await fleetRunner().run(['fleet', 'stop', '1']), exitDevice);
      expect(said.single, contains('its process could not be checked'));
    });

    test('--force stops it and records who asked, before the stop', () async {
      expect(await fleetRunner().run(['fleet', 'stop', '1', '--force']), 0);
      expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
      final asked = request()!;
      expect(asked.by, 'fleet stop --force');
      expect(asked.pid, pid);
      expect(asked.checkout, world.paths.projectRoot);
    });

    test('--force --as-crash stops it and records nothing', () async {
      expect(
        await fleetRunner().run([
          'fleet',
          'stop',
          '1',
          '--force',
          '--as-crash',
        ]),
        0,
      );
      expect(world.runner.lines, contains('adb -s emulator-5556 emu kill'));
      expect(request(), isNull);
      await expectLater(
        fleetRunner().run(['fleet', 'stop', '1', '--as-crash']),
        throwsA(isA<UsageFailure>()),
      );
    });

    test(
      'reap --force records the request; a plain reap leaves the guest',
      () async {
        // The fleet half of reap runs on Windows only.
        final host = _World(alive: {300});
        addTearDown(host.dispose);
        GuestState.take(
          host.paths.guestStateFor('anta_qa_1'),
          GuestHold(pid: 300, verb: 'pass', since: now),
        );
        StopRequest? asked() =>
            StopRequest.read(host.paths.stopRequestFor('anta_qa_1'));
        final (skipped, _) = await host.reap();
        expect(skipped, contains(startsWith('skip: anta_qa_1')));
        expect(asked(), isNull);
        await host.reap(force: true);
        expect(host.runner.down, isTrue);
        expect(asked()?.by, 'reap --force');
        expect(asked()?.checkout, host.paths.projectRoot);
      },
    );
  });
}

class _FleetContext extends QaContext {
  _FleetContext(
    super.globalResults, {
    required super.paths,
    required this.host,
  });

  final FleetHost host;

  /// Answers [quietFleetGuest] in place of a child relaunch.
  Future<GuestQuiet> Function(String serial)? quiet;

  /// The `always` of every [quietFleetGuest] call, in order.
  final List<bool> alwaysAsked = [];

  @override
  FleetHost fleetHost() => host;

  @override
  Future<GuestQuiet> quietFleetGuest(String serial, {bool always = false}) {
    alwaysAsked.add(always);
    return quiet?.call(serial) ?? super.quietFleetGuest(serial, always: always);
  }
}
