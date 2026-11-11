import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/markers.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/runner.dart';
import 'fake_process_runner.dart';

/// A runner whose every call fails the way a timed-out one does.
class _ThrowingRunner implements ProcessRunner {
  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  }) async => throw DeviceFailure('timed out after 20s: $executable');
}

void main() {
  group('buildFlutterArgs', () {
    test('run carries the QA defines, the driver target and --print-dtd', () {
      final args = buildFlutterArgs(command: 'run', deviceId: 'emulator-5554');
      expect(args, [
        'run',
        '--print-dtd',
        '-d',
        'emulator-5554',
        '-t',
        'test_driver/main_driver.dart',
        '--dart-define=ANTA_QA=true',
        '--dart-define=ANTA_QA_DB=qa',
      ]);
    });

    test('--no-qa drops only the QA defines', () {
      final args = buildFlutterArgs(command: 'run', deviceId: 'x', qa: false);
      expect(args, isNot(contains('--dart-define=ANTA_QA=true')));
      expect(args, containsAllInOrder(['-t', driverTarget]));
    });

    test('--no-driver drops only the driver target', () {
      final args = buildFlutterArgs(
        command: 'run',
        deviceId: 'x',
        driver: false,
      );
      expect(args, isNot(contains('-t')));
      expect(args, contains('--dart-define=ANTA_QA=true'));
    });

    test('attach never takes a target', () {
      final args = buildFlutterArgs(command: 'attach', deviceId: 'x');
      expect(args.first, 'attach');
      expect(args, isNot(contains('-t')));
      expect(args, contains('--print-dtd'));
    });

    test('extra defines are appended verbatim', () {
      final args = buildFlutterArgs(
        command: 'run',
        deviceId: 'x',
        extraDefines: ['ANTA_QA_SKIP_ONBOARDING=false', 'FOO=bar'],
      );
      expect(args.last, '--dart-define=FOO=bar');
      expect(args, contains('--dart-define=ANTA_QA_SKIP_ONBOARDING=false'));
    });
  });

  group('logcatStamp', () {
    test('is the MM-DD HH:MM:SS.mmm shape adb logcat -T accepts', () {
      final stamp = rawLogcatStamp(DateTime(2026, 9, 13, 17, 42, 3, 7));
      expect(stamp, '09-13 17:42:03.007');
    });

    test('backdates by the clock-skew margin', () {
      final now = DateTime(2026, 9, 13, 17, 42, 3, 7);
      expect(logcatStamp(now), rawLogcatStamp(now.subtract(logcatStampMargin)));
      expect(logcatStamp(now), '09-13 17:41:48.007');
    });

    test('the margin is large enough for the emulator clock drift', () {
      expect(logcatStampMargin.inSeconds, greaterThanOrEqualTo(10));
    });
  });

  group('writeWrapperScript', () {
    late Directory temp;
    late QaPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_');
      paths = QaPaths(temp.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('the emulator wrapper has no idle stdin pipe', () {
      final file = writeWrapperScript(
        paths: paths,
        baseName: 'emulator_cmd',
        executable: 'emulator',
        arguments: const ['-avd', 'Pixel'],
        posixLogPath: paths.emulatorLog,
      );
      final script = file.readAsStringSync();
      expect(script, contains('-avd Pixel'));
      expect(script, isNot(contains('ping -n 61')));
    });

    test('the flutter wrapper keeps the idle stdin pipe on Windows', () {
      final file = writeWrapperScript(
        paths: paths,
        baseName: 'run_cmd',
        executable: 'flutter',
        arguments: const ['run'],
        posixLogPath: paths.runLog,
        idleStdin: true,
      );
      final script = file.readAsStringSync();
      if (Platform.isWindows) {
        expect(script, contains('ping -n 61'));
      } else {
        expect(script, contains('exec "flutter" run'));
      }
    });
  });

  group('writeLaunchWrapper', () {
    late Directory temp;
    late QaPaths paths;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('anta_qa_');
      paths = QaPaths(temp.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('the wrapper carries the whole flutter command line', () {
      final file = writeLaunchWrapper(
        paths: paths,
        flutterExecutable: 'flutter',
        arguments: buildFlutterArgs(command: 'run', deviceId: 'emulator-5554'),
      );
      final script = file.readAsStringSync();
      expect(script, contains('--print-dtd'));
      expect(script, contains('--dart-define=ANTA_QA=true'));
      expect(script, contains('-t test_driver/main_driver.dart'));
      if (!Platform.isWindows) {
        // Only POSIX redirects inside the wrapper; on Windows Start-Process
        // owns stdout and stderr so that nothing of the caller is inherited.
        expect(script, contains(paths.runLog));
        expect(script, contains('2>&1'));
      }
    });

    test('it changes into the package root first', () {
      final script = writeLaunchWrapper(
        paths: paths,
        flutterExecutable: 'flutter',
        arguments: const ['run'],
      ).readAsStringSync();
      expect(script, contains(paths.projectRoot));
    });

    test('the wrapper holds stdin open with an idle pipe', () {
      final script = writeLaunchWrapper(
        paths: paths,
        flutterExecutable: 'flutter',
        arguments: const ['run'],
      ).readAsStringSync();
      if (Platform.isWindows) {
        // A resident `flutter run` quits the moment stdin reports EOF, which
        // is what a file or a closed pipe gives it seconds after startup.
        expect(script, contains('for /l'));
        expect(script, contains('|'));
        expect(
          script.indexOf('|'),
          lessThan(script.indexOf('flutter')),
          reason: 'the idle loop must feed flutter, not the other way round',
        );
      }
    });

    test('an argument with a space is quoted', () {
      final script = writeLaunchWrapper(
        paths: paths,
        flutterExecutable: 'flutter',
        arguments: const ['run', '--dart-define=NAME=two words'],
      ).readAsStringSync();
      expect(script, contains('"--dart-define=NAME=two words"'));
    });

    test('killRecordedRun is a no-op with no run.pid', () async {
      paths.ensureBuildQa();
      final ended = await killRecordedRun(paths, FakeProcessRunner());
      expect((ended.killed, ended.note), (null, null));
    });

    group('killRecordedRun on Windows', () {
      String probe(int pid) =>
          'powershell.exe -NoProfile -NonInteractive -Command '
          '${recordedRunProbeScript(pid, paths.runWrapperFor(windows: true))}';

      FakeProcessRunner answering(String said) =>
          FakeProcessRunner()..script(probe(4242), RunOutcome(0, said, ''));

      setUp(() {
        paths.ensureBuildQa();
        File(paths.runPid).writeAsStringSync('4242');
      });

      test(
        'takes the whole tree down while the pid is still the run',
        () async {
          final fake = answering('ours');
          final ended = await killRecordedRun(paths, fake, windows: true);
          expect(ended.killed, 4242);
          expect(File(paths.runPid).existsSync(), isFalse);
          expect(fake.lines, [probe(4242), 'taskkill /PID 4242 /T /F']);
        },
      );

      test('the probe names this checkout\'s wrapper by its full path', () {
        final wrapper = paths.runWrapperFor(windows: true);
        final script = recordedRunProbeScript(4242, wrapper);
        expect(script, contains("IndexOf('$wrapper'"));
        expect(
          script,
          isNot(contains('*run_cmd.bat*')),
          reason: 'another checkout\'s run is not this one\'s to kill',
        );
        expect(
          recordedRunProbeScript(1, r"D:\it's\run_cmd.bat"),
          contains(r"IndexOf('D:\it''s\run_cmd.bat'"),
        );
      });

      test('a kill that failed keeps run.pid for the next try', () async {
        final fake = answering('ours')
          ..script(
            'taskkill /PID 4242 /T /F',
            const RunOutcome(1, '', 'ERROR: Access is denied.'),
          );
        final ended = await killRecordedRun(paths, fake, windows: true);
        expect(ended.killed, isNull);
        expect(ended.note, contains('could not kill run pid 4242'));
        expect(File(paths.runPid).existsSync(), isTrue);
      });

      test(
        'a pid that now belongs to something else loses only its file',
        () async {
          final fake = answering('other');
          final ended = await killRecordedRun(paths, fake, windows: true);
          expect(ended.killed, isNull);
          expect(
            ended.note,
            contains('is no longer the harness\'s run (left running)'),
          );
          expect(File(paths.runPid).existsSync(), isFalse);
          expect(fake.lines.where((l) => l.startsWith('taskkill')), isEmpty);
        },
      );

      test('a pid that is gone loses its file', () async {
        final ended = await killRecordedRun(
          paths,
          answering('gone'),
          windows: true,
        );
        expect(ended.note, 'forgot run.pid: pid 4242 is gone');
        expect(File(paths.runPid).existsSync(), isFalse);
      });

      test('a probe with no answer kills nothing and keeps the file', () async {
        final fake = answering('');
        final ended = await killRecordedRun(paths, fake, windows: true);
        expect(ended.killed, isNull);
        expect(ended.note, contains('could not be checked'));
        expect(File(paths.runPid).existsSync(), isTrue);
        expect(fake.lines.where((l) => l.startsWith('taskkill')), isEmpty);
      });
    });

    group('killRecordedRun off Windows', () {
      const ps = '/bin/ps -o command= -p 4242';
      setUp(() {
        paths.ensureBuildQa();
        File(paths.runPid).writeAsStringSync('4242');
      });

      test(
        'a live pid that does not run this checkout\'s wrapper is never signalled',
        () async {
          final fake = FakeProcessRunner()
            ..script(ps, const RunOutcome(0, '/usr/bin/vim notes.txt', ''));
          final ended = await killRecordedRun(paths, fake, windows: false);
          expect(ended.killed, isNull);
          expect(ended.note, contains('no longer the harness\'s run'));
          expect(fake.lines.where((l) => l.contains('kill')), isEmpty);
        },
      );

      test('the wrapper\'s pid is sent a TERM, then forgotten', () async {
        final fake = FakeProcessRunner()
          ..script(
            ps,
            RunOutcome(0, '/bin/sh ${paths.runWrapperFor(windows: false)}', ''),
          );
        final ended = await killRecordedRun(paths, fake, windows: false);
        expect(ended.killed, 4242);
        expect(fake.lines.last, '/bin/kill -TERM 4242');
        expect(File(paths.runPid).existsSync(), isFalse);
      });

      test('a ps that could not answer keeps the file', () async {
        final fake = FakeProcessRunner()
          ..script(ps, const RunOutcome(1, '', 'ps: not permitted'));
        final ended = await killRecordedRun(paths, fake, windows: false);
        expect(ended.note, contains('could not be checked'));
        expect(File(paths.runPid).existsSync(), isTrue);
      });
    });
  });

  group('RealProcessRunner', () {
    test(
      'a call that times out takes its grandchildren down too',
      () async {
        // A cmd that starts a ping: the ping is the grandchild a plain kill
        // of the cmd leaves running. The address is this test's own mark.
        const mark = '127.0.0.47';
        await expectLater(
          const RealProcessRunner().run('cmd.exe', [
            '/c',
            'ping -n 30 $mark > nul',
          ], timeout: const Duration(seconds: 2)),
          throwsA(isA<DeviceFailure>()),
        );
        final left = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "@(Get-CimInstance Win32_Process -Filter 'Name=''PING.EXE''' | "
              "Where-Object { \$_.CommandLine -like '*$mark*' }).Count",
        ]);
        expect((left.stdout as String).trim(), '0');
      },
      skip: Platform.isWindows ? false : 'the tree kill is Windows-only',
    );
  });

  group('processLiveness', () {
    const windowsProbe =
        'powershell.exe -NoProfile -NonInteractive -Command '
        "if (Get-Process -Id 42 -ErrorAction SilentlyContinue) "
        "{ 'alive' } else { 'gone' }";

    test('only a plain answer is alive or gone', () async {
      for (final (said, expected) in [
        ('alive', Liveness.alive),
        ('gone\r\n', Liveness.gone),
        ('', Liveness.unknown),
        ('Get-Process : blocked by policy', Liveness.unknown),
      ]) {
        final fake = FakeProcessRunner()
          ..script(windowsProbe, RunOutcome(0, said, ''));
        expect(
          await processLiveness(42, fake, windows: true),
          expected,
          reason: said,
        );
      }
    });

    test('a probe that errors or times out is unknown, never gone', () async {
      expect(
        await processLiveness(42, _ThrowingRunner(), windows: true),
        Liveness.unknown,
      );
      final fake = FakeProcessRunner()
        ..script(
          '/bin/sh -c ${posixLivenessScript(42)}',
          const RunOutcome(0, 'alive', ''),
        );
      expect(await processLiveness(42, fake, windows: false), Liveness.alive);
      expect(
        await processLiveness(43, fake, windows: false),
        Liveness.unknown,
        reason: 'no output proves nothing',
      );
    });
  });

  group('the timeout kill', () {
    test('adb loses only its direct child, everything else its tree', () {
      for (final adb in ['adb', 'adb.exe', r'C:\Sdk\platform-tools\adb.exe']) {
        expect(
          treeKillsOnTimeout(adb),
          isFalse,
          reason: '$adb may have started the shared server on 5037',
        );
      }
      for (final other in ['cmd.exe', 'flutter.bat', 'powershell.exe']) {
        expect(treeKillsOnTimeout(other), isTrue, reason: other);
      }
    });
  });

  group('the fleet state directory', () {
    test('is one per user, never per checkout', () {
      expect(
        hostFleetStateDir(
          const {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
          windows: true,
          macos: false,
        ),
        endsWith(['anta-qa', 'fleet'].join(Platform.pathSeparator)),
      );
      expect(
        hostFleetStateDir(
          const {'LOCALAPPDATA': r'C:\L'},
          windows: true,
          macos: false,
        ),
        startsWith(r'C:\L'),
      );
      expect(
        hostFleetStateDir(
          const {'HOME': '/Users/me'},
          windows: false,
          macos: true,
        ),
        startsWith('/Users/me${Platform.pathSeparator}Library'),
      );
      expect(
        hostFleetStateDir(
          const {'HOME': '/home/me', 'XDG_STATE_HOME': '/state'},
          windows: false,
          macos: false,
        ),
        startsWith('/state'),
      );
    });

    test('$fleetStateEnv overrides it', () {
      expect(
        hostFleetStateDir(
          const {fleetStateEnv: r'D:\x', 'LOCALAPPDATA': r'C:\L'},
          windows: true,
          macos: false,
        ),
        r'D:\x',
      );
    });

    test('holds the guest and guard files; the run stays per checkout', () {
      final paths = QaPaths(r'D:\repo', fleetState: r'C:\fleet');
      for (final shared in [
        paths.guestStateFor('anta_qa_1'),
        paths.guardPid,
        paths.guardLog,
        paths.guardExeFor(1),
      ]) {
        expect(shared, startsWith(r'C:\fleet'));
      }
      for (final own in [paths.runPid, paths.apkJson, paths.passRoot]) {
        expect(own, startsWith(r'D:\repo'));
      }
      expect(
        QaPaths(r'D:\repo').fleetState,
        startsWith(r'D:\repo'),
        reason: 'a test\'s paths never reach the host-wide directory',
      );
    });
  });

  group('QaPaths', () {
    test('everything lands under build/qa of the package root', () {
      final paths = QaPaths(r'D:\repo');
      expect(paths.buildQa, endsWith('qa'));
      expect(paths.runLog, contains('run.log'));
      expect(paths.shotsDir, contains('shots'));
      expect(paths.fixturesDir, contains('fixtures'));
    });

    test('what two devices could collide on is named per device', () {
      final paths = QaPaths('/repo');
      String name(String path) => path.split(RegExp(r'[\\/]')).last;
      expect(
        name(paths.lastDumpFor('emulator-5556')),
        'last_dump_emulator-5556.txt',
      );
      expect(
        name(paths.seedResolvedFor('emulator-5556')),
        'seed_resolved_emulator-5556.json',
      );
      expect(
        name(paths.installedJsonFor('192.168.1.5:5555')),
        'installed_192.168.1.5_5555.json',
      );
      expect(name(paths.emulatorPidFor('anta_qa_1')), 'emulator_anta_qa_1.pid');
      expect(name(paths.emulatorLogFor('anta_qa_1')), 'emulator_anta_qa_1.log');
      expect(name(paths.emulatorErrFor('anta_qa_1')), 'emulator_anta_qa_1.err');
      expect(name(paths.emulatorLogFor(null)), 'emulator.log');
      expect(paths.emulatorPid, paths.emulatorPidFor(null));
      expect(
        name(paths.passDirFor('calendar', '20261023_101500', 'emulator-5556')),
        'calendar_20261023_101500_emulator-5556',
      );
      expect(
        paths.passDirFor('calendar', 's', 'd'),
        startsWith(paths.passRoot),
      );
      expect(name(paths.latestPassFor('calendar')), 'latest_calendar.txt');
    });

    test('locate walks up to the package root from a subdirectory', () {
      final paths = QaPaths.locate(Directory('test/qa'));
      expect(File('${paths.projectRoot}/pubspec.yaml').existsSync(), isTrue);
    });

    test('resolve leaves an absolute path alone', () {
      final paths = QaPaths(Directory.current.path);
      final absolute = File('pubspec.yaml').absolute.path;
      expect(paths.resolve(absolute), absolute);
      expect(
        paths.resolve('tool/qa/fixtures/basic.json'),
        startsWith(paths.projectRoot),
      );
    });
  });

  group('marker commands', () {
    test('--fresh touches qa_reset inside the app sandbox via run-as', () {
      expect(resetMarkerCommands(), [
        [
          'shell',
          'run-as',
          'com.alexzamfir.anta',
          'touch',
          '/data/user/0/com.alexzamfir.anta/app_flutter/qa_reset',
        ],
      ]);
    });

    test('--seed stages in /data/local/tmp, then copies under run-as', () {
      final commands = markerPushCommands(
        localPath: r'D:\repo\tool\qa\fixtures\basic.json',
        markerName: seedMarker,
      );
      expect(commands, hasLength(3));
      expect(commands[0], [
        'push',
        r'D:\repo\tool\qa\fixtures\basic.json',
        '/data/local/tmp/anta_qa_seed.json',
      ]);
      expect(commands[1], [
        'shell',
        'run-as',
        'com.alexzamfir.anta',
        'cp',
        '/data/local/tmp/anta_qa_seed.json',
        '/data/user/0/com.alexzamfir.anta/app_flutter/qa_seed.json',
      ]);
      expect(commands[2], [
        'shell',
        'rm',
        '-f',
        '/data/local/tmp/anta_qa_seed.json',
      ]);
    });

    test('the staging file never lands in the app sandbox directly', () {
      final commands = markerPushCommands(
        localPath: 'x.json',
        markerName: seedMarker,
      );
      expect(commands.first[2], startsWith(stagingDir));
      expect(commands.first[2], isNot(contains(antaDocsDir)));
    });

    test(
      'applyCommands sends each vector through adb with the serial',
      () async {
        final fake = FakeProcessRunner();
        final adb = Adb(
          executable: 'adb',
          runner: fake,
          serial: 'emulator-5554',
        );
        await applyCommands(adb, resetMarkerCommands());
        expect(
          fake.lines.single,
          'adb -s emulator-5554 shell run-as com.alexzamfir.anta touch '
          '/data/user/0/com.alexzamfir.anta/app_flutter/qa_reset',
        );
      },
    );

    test('a run-as refusal is reported as a device failure', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
          0,
          '',
          'run-as: package not debuggable: com.alexzamfir.anta',
        ),
      );
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(
        () => applyCommands(adb, resetMarkerCommands()),
        throwsA(
          isA<DeviceFailure>()
              .having((e) => e.code, 'code', exitDevice)
              .having((e) => e.message, 'message', contains('debug build')),
        ),
      );
    });

    test('a non-zero exit is reported as a device failure', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(1, '', 'boom'),
      );
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(
        () => applyCommands(adb, resetMarkerCommands()),
        throwsA(isA<DeviceFailure>()),
      );
    });

    test('a pending seed is removed inside the sandbox and reported', () async {
      final fake = FakeProcessRunner();
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(await discardSeed(adb), isTrue);
      expect(
        fake.lines.single,
        'adb -s e shell run-as com.alexzamfir.anta rm '
        '/data/user/0/com.alexzamfir.anta/app_flutter/qa_seed.json',
      );
    });

    test('no pending seed reads as none, not as a failure', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
          1,
          '',
          'rm: /data/user/0/com.alexzamfir.anta/app_flutter/qa_seed.json: '
              'No such file or directory',
        ),
      );
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(await discardSeed(adb), isFalse);
    });

    test('a run-as refusal while discarding is a device failure', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
          1,
          '',
          'run-as: package not debuggable: com.alexzamfir.anta',
        ),
      );
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(() => discardSeed(adb), throwsA(isA<DeviceFailure>()));
    });

    test('a seed waiting on the host side is deleted once', () async {
      final dir = Directory.systemTemp.createTempSync('anta_qa_discard_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(
        '${dir.path}${Platform.pathSeparator}$seedMarker',
      ).writeAsStringSync('{}');
      expect(await discardSeedAt(dir.path), isTrue);
      expect(pendingMarkersAt(dir.path), isEmpty);
      expect(await discardSeedAt(dir.path), isFalse);
    });
  });
}
