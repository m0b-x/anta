import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/markers.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/runner.dart';
import 'fake_process_runner.dart';

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
      final args =
          buildFlutterArgs(command: 'run', deviceId: 'x', qa: false);
      expect(args, isNot(contains('--dart-define=ANTA_QA=true')));
      expect(args, containsAllInOrder(['-t', driverTarget]));
    });

    test('--no-driver drops only the driver target', () {
      final args =
          buildFlutterArgs(command: 'run', deviceId: 'x', driver: false);
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
      expect(
        logcatStamp(now),
        rawLogcatStamp(now.subtract(logcatStampMargin)),
      );
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
      expect(await killRecordedRun(paths, FakeProcessRunner()), isNull);
    });

    test('killRecordedRun takes the whole tree down on Windows', () async {
      paths.ensureBuildQa();
      File(paths.runPid).writeAsStringSync('4242');
      final fake = FakeProcessRunner();
      final pid = await killRecordedRun(paths, fake);
      expect(pid, 4242);
      expect(File(paths.runPid).existsSync(), isFalse);
      if (Platform.isWindows) {
        expect(fake.lines.single, 'taskkill /PID 4242 /T /F');
      }
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

    test('locate walks up to the package root from a subdirectory', () {
      final paths = QaPaths.locate(Directory('test/qa'));
      expect(File('${paths.projectRoot}/pubspec.yaml').existsSync(), isTrue);
    });

    test('resolve leaves an absolute path alone', () {
      final paths = QaPaths(Directory.current.path);
      final absolute = File('pubspec.yaml').absolute.path;
      expect(paths.resolve(absolute), absolute);
      expect(paths.resolve('tool/qa/fixtures/basic.json'),
          startsWith(paths.projectRoot));
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
      expect(commands[2], ['shell', 'rm', '-f', '/data/local/tmp/anta_qa_seed.json']);
    });

    test('the staging file never lands in the app sandbox directly', () {
      final commands =
          markerPushCommands(localPath: 'x.json', markerName: seedMarker);
      expect(commands.first[2], startsWith(stagingDir));
      expect(commands.first[2], isNot(contains(antaDocsDir)));
    });

    test('applyCommands sends each vector through adb with the serial', () async {
      final fake = FakeProcessRunner();
      final adb =
          Adb(executable: 'adb', runner: fake, serial: 'emulator-5554');
      await applyCommands(adb, resetMarkerCommands());
      expect(fake.lines.single,
          'adb -s emulator-5554 shell run-as com.alexzamfir.anta touch '
          '/data/user/0/com.alexzamfir.anta/app_flutter/qa_reset');
    });

    test('a run-as refusal is reported as a device failure', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(
            0, '', 'run-as: package not debuggable: com.alexzamfir.anta'),
      );
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(
        () => applyCommands(adb, resetMarkerCommands()),
        throwsA(isA<DeviceFailure>()
            .having((e) => e.code, 'code', exitDevice)
            .having((e) => e.message, 'message', contains('debug build'))),
      );
    });

    test('a non-zero exit is reported as a device failure', () async {
      final fake =
          FakeProcessRunner(defaultOutcome: const RunOutcome(1, '', 'boom'));
      final adb = Adb(executable: 'adb', runner: fake, serial: 'e');
      expect(
        () => applyCommands(adb, resetMarkerCommands()),
        throwsA(isA<DeviceFailure>()),
      );
    });
  });
}
