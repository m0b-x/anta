import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/apk_build.dart';
import '../../tool/qa/src/doctor.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import 'fake_process_runner.dart';

/// A fake whose answers depend on the request and on what came before it,
/// for the waits that poll until something changes.
class _RespondingRunner extends FakeProcessRunner {
  _RespondingRunner(this.respond);

  final RunOutcome? Function(RunRequest request) respond;

  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  }) async {
    final request =
        RunRequest(executable, arguments, binary: binary, stdin: stdin);
    calls.add(request);
    return respond(request) ?? defaultOutcome;
  }
}

const _qemuWindows =
    '11712\tFFFF\tD:\\Sdk\\emulator\\qemu\\windows-x86_64\\qemu-system-x86_64-headless.exe '
    '-avd anta_qa_1 -port 5556 -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics -gpu host\r\n'
    '19584\tFFFFFF\tD:\\Sdk\\emulator\\qemu\\windows-x86_64\\qemu-system-x86_64.exe '
    '-avd Pixel_9_Pro -no-snapshot-load\r\n';

ApkRecord _record(DateTime builtAt, {String hash = 'abc1234', DateTime? installedAt}) =>
    ApkRecord(
      apk: 'app-debug.apk',
      gitHash: hash,
      dirty: false,
      builtAt: builtAt,
      defines: const [],
      installedAt: installedAt,
    );

FleetMember _member(
  int index, {
  FleetState state = FleetState.device,
  ApkRecord? installed,
  String? heldBy,
  QemuProcess? qemu,
}) =>
    FleetMember(
      index: index,
      created: state != FleetState.notCreated,
      state: state,
      installed: installed,
      heldBy: heldBy,
      qemu: qemu,
    );

void _writeAvd(Directory home, String name, String config) {
  File(joinPath(home.path, ['$name.ini'])).writeAsStringSync('path=x\n');
  final dir = Directory(joinPath(home.path, ['$name.avd']))..createSync();
  File(joinPath(dir.path, ['config.ini'])).writeAsStringSync(config);
}

void main() {
  group('capacity', () {
    test('threads minus 8 for flutter test and 4 for the owner, 4 each', () {
      expect(fleetCapacity(24), 3);
      expect(fleetCapacity(32), 5);
      expect(fleetCapacity(16), 1);
      expect(fleetCapacity(8), 1, reason: 'never below one');
    });

    test('--count defaults to the capacity and needs --force above it', () {
      expect(fleetCount(threads: 24, force: false), 3);
      expect(fleetCount(requested: 2, threads: 24, force: false), 2);
      expect(
        () => fleetCount(requested: 4, threads: 24, force: false),
        throwsA(isA<UsageFailure>()),
      );
      expect(fleetCount(requested: 4, threads: 24, force: true), 4);
      expect(
        () => fleetCount(requested: 0, threads: 24, force: true),
        throwsA(isA<UsageFailure>()),
      );
    });
  });

  group('ports and names', () {
    test('AVD N sits on console port 5554 + 2N', () {
      expect(fleetPort(1), 5556);
      expect(fleetSerial(1), 'emulator-5556');
      expect(fleetSerial(2), 'emulator-5558');
      expect(fleetSerial(3), 'emulator-5560');
      expect(fleetName(3), 'anta_qa_3');
    });

    test('a serial maps back to its index; the owner\'s port never does', () {
      expect(fleetIndexOfSerial('emulator-5558'), 2);
      expect(fleetIndexOfSerial('emulator-5554'), isNull);
      expect(fleetIndexOfSerial('emulator-5557'), isNull);
      expect(fleetIndexOfSerial('192.168.1.4:5555'), isNull);
    });

    test('only anta_qa_<N> is a fleet name', () {
      expect(fleetIndexOf('anta_qa_1'), 1);
      expect(fleetIndexOf('anta_qa_12'), 12);
      expect(fleetIndexOf('anta_qa_0'), isNull);
      expect(fleetIndexOf('anta_qa_01'), isNull);
      expect(fleetIndexOf('anta_qa_'), isNull);
      expect(fleetIndexOf('Pixel_9_Pro'), isNull);
      expect(fleetIndexOf('xanta_qa_1'), isNull);
    });

    test('a verb takes a name or a number, never another emulator', () {
      expect(parseFleetArgument('anta_qa_2'), 2);
      expect(parseFleetArgument('3'), 3);
      expect(() => parseFleetArgument('Pixel_9_Pro'), throwsA(isA<UsageFailure>()));
      expect(() => parseFleetArgument('emulator-5554'), throwsA(isA<UsageFailure>()));
      expect(() => parseFleetArgument('emulator-5556'), throwsA(isA<UsageFailure>()),
          reason: 'serials only where the verb allows them');
      expect(() => parseFleetArgument('0'), throwsA(isA<UsageFailure>()));
      expect(parseFleetArgument('emulator-5556', serials: true), 1);
      expect(
        () => parseFleetArgument('emulator-5554', serials: true),
        throwsA(isA<UsageFailure>()),
      );
    });
  });

  group('affinity', () {
    test('a hybrid part pins to its P-core threads', () {
      expect(hybridAffinityMask(cores: 16, threads: 24), 0xFFFF);
      expect(hybridAffinityMask(cores: 10, threads: 12), 0xF);
    });

    test('a part that is not hybrid is not pinned', () {
      expect(hybridAffinityMask(cores: 8, threads: 16), isNull);
      expect(hybridAffinityMask(cores: 8, threads: 8), isNull);
      expect(hybridAffinityMask(cores: 0, threads: 0), isNull);
    });

    test('the override wins, --no-affinity and macOS never pin', () {
      expect(fleetAffinity(windows: true, disabled: false, cores: 16, threads: 24).mask, 0xFFFF);
      expect(
        fleetAffinity(windows: true, disabled: false, override: '0x00ff', cores: 16, threads: 24).mask,
        0xFF,
      );
      expect(fleetAffinity(windows: true, disabled: false, override: 'FFF').mask, 0xFFF);
      expect(
        fleetAffinity(windows: true, disabled: true, override: 'FFFF', cores: 16, threads: 24).mask,
        isNull,
      );
      expect(
        fleetAffinity(windows: false, disabled: false, override: 'FFFF', cores: 16, threads: 24).mask,
        isNull,
      );
      expect(fleetAffinity(windows: true, disabled: false, cores: 8, threads: 16).mask, isNull);
      expect(fleetAffinity(windows: true, disabled: false).mask, isNull);
      expect(
        () => fleetAffinity(windows: true, disabled: false, override: 'nope'),
        throwsA(isA<UsageFailure>()),
      );
      expect(
        () => fleetAffinity(windows: true, disabled: false, override: '0'),
        throwsA(isA<UsageFailure>()),
      );
    });

    test('masks print as upper-case hex', () {
      expect(hexMask(0xFFFF), '0xFFFF');
      expect(parseCpuTopology('16 24'), (cores: 16, threads: 24));
      expect(parseCpuTopology(''), isNull);
    });
  });

  group('config.ini', () {
    const avdmanagerConfig = [
      'PlayStore.enabled=no',
      'hw.ramSize=1536M',
      'hw.cpu.ncore = 2',
      'hw.lcd.density=420',
      'image.sysdir.1=system-images\\android-36\\google_apis_playstore\\x86_64\\',
    ];

    test('tuneConfig rewrites the fleet keys in place and appends the rest', () {
      final tuned = tuneConfig(avdmanagerConfig);
      expect(tuned.sublist(0, 5), [
        'PlayStore.enabled=no',
        'hw.ramSize=2048',
        'hw.cpu.ncore=4',
        'hw.lcd.density=480',
        'image.sysdir.1=system-images\\android-36\\google_apis_playstore\\x86_64\\',
      ]);
      for (final entry in fleetConfigSpec.entries) {
        expect(configValue(tuned, entry.key), entry.value, reason: entry.key);
      }
      expect(tuned.length, avdmanagerConfig.length + fleetConfigSpec.length - 3);
      expect(tuneConfig(tuned), tuned, reason: 'idempotent');
      expect(configDrift(tuned), isEmpty);
    });

    test('configDrift names each key that differs or is missing', () {
      final drift = configDrift(avdmanagerConfig);
      expect(drift, contains('hw.ramSize=1536M (fleet: 2048)'));
      expect(drift, contains('hw.cpu.ncore=2 (fleet: 4)'));
      expect(drift, contains('hw.gpu.mode unset (fleet: auto)'));
      expect(drift.length, fleetConfigSpec.length);
    });

    test('the file keeps its line ends', () {
      final lines = splitConfig('a=1\r\nb=2\r\n\r\n');
      expect(lines, ['a=1', 'b=2']);
      expect(joinConfig(lines, crlf: true), 'a=1\r\nb=2\r\n');
      expect(joinConfig(lines, crlf: false), 'a=1\nb=2\n');
    });

    test('the image comes from the owner\'s AVD, else the single install', () {
      expect(
        imagePackageFromConfig(avdmanagerConfig),
        'system-images;android-36;google_apis_playstore;x86_64',
      );
      expect(
        chooseFleetImage(ownerConfig: avdmanagerConfig, installedApis: const []),
        'system-images;android-36;google_apis_playstore;x86_64',
      );
      expect(
        chooseFleetImage(ownerConfig: null, installedApis: const ['android-35']),
        'system-images;android-35;google_apis_playstore;x86_64',
      );
      expect(
        () => chooseFleetImage(ownerConfig: null, installedApis: const []),
        throwsA(isA<DeviceFailure>()),
      );
      expect(
        () => chooseFleetImage(
          ownerConfig: const ['hw.ramSize=2048'],
          installedApis: const ['android-35', 'android-36'],
        ),
        throwsA(isA<DeviceFailure>()),
      );
    });
  });

  group('argument vectors', () {
    test('avdmanager makes the AVD on the Pixel 9 Pro profile, never --force', () {
      expect(
        avdCreateArgs('anta_qa_3', 'system-images;android-36;google_apis_playstore;x86_64'),
        [
          'create',
          'avd',
          '-n',
          'anta_qa_3',
          '-k',
          'system-images;android-36;google_apis_playstore;x86_64',
          '-d',
          'pixel_9_pro',
        ],
      );
      expect(avdCreateStdin, 'no\n');
    });

    test('the emulator boots headless on its own port with the host GPU', () {
      expect(fleetEmulatorArgs(2), [
        '-avd',
        'anta_qa_2',
        '-port',
        '5558',
        '-no-window',
        '-no-audio',
        '-no-boot-anim',
        '-no-snapshot',
        '-no-metrics',
        '-gpu',
        'host',
      ]);
    });

    test('the console is asked its AVD name, then to stop', () {
      expect(emuAvdNameArgs, ['emu', 'avd', 'name']);
      expect(emuKillArgs, ['emu', 'kill']);
      expect(parseEmuAvdName('anta_qa_1\r\nOK\r\n'), 'anta_qa_1');
      expect(parseEmuAvdName('OK'), isNull);
      expect(parseEmuAvdName('KO: unknown command'), isNull);
      expect(parseEmuAvdName('error: device not found'), isNull);
    });

    test('a pass shard is the tool itself with -d, --shard and --json', () {
      expect(
        fleetPassChildArgs(
          serial: 'emulator-5558',
          suite: 'calendar',
          shard: (2, 3),
          jsonPath: 'out/shard-2.json',
          label: 'nightly',
          stopOnFail: true,
          via: 'agent',
        ),
        [
          '-d',
          'emulator-5558',
          '--via=agent',
          'pass',
          'calendar',
          '--shard=2/3',
          '--json=out/shard-2.json',
          '--label=nightly',
          '--stop-on-fail',
        ],
      );
      expect(
        fleetPassChildArgs(
          serial: 'emulator-5556',
          suite: 'alerts',
          shard: null,
          jsonPath: 'a.json',
        ),
        ['-d', 'emulator-5556', 'pass', 'alerts', '--json=a.json'],
      );
      expect(fleetInstallChildArgs('emulator-5560'), ['-d', 'emulator-5560', 'install']);
      expect(fleetBuildChildArgs(verbose: true), ['--verbose', 'build']);
    });

    test('a child is the compiled exe, or `dart run qa.dart` under dart', () {
      final exe = qaSelfCommand(
        resolvedExecutable: r'C:\anta\build\qa\qa.exe',
        qaExe: r'C:\anta\build\qa\qa.exe',
        qaExeExists: true,
        script: r'C:\anta\tool\qa\qa.dart',
      );
      expect(exe.executable, r'C:\anta\build\qa\qa.exe');
      expect(exe.leading, isEmpty);
      final dart = qaSelfCommand(
        resolvedExecutable: r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe',
        qaExe: r'C:\anta\build\qa\qa.exe',
        qaExeExists: true,
        script: r'C:\anta\tool\qa\qa.dart',
      );
      expect(dart.executable, r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe');
      expect(dart.leading, ['run', r'C:\anta\tool\qa\qa.dart']);
    });

    test('only flow and shard verdicts are echoed live', () {
      expect(isPassProgressLine('=== 00_open: ok in 2104 ms'), isTrue);
      expect(isPassProgressLine('=== 22_palette: FAILED (exit 2) in 9000 ms'), isTrue);
      expect(isPassProgressLine('pass: 9/9 green in 230.0 s on emulator-5556 — report x'), isTrue);
      expect(isPassProgressLine('=== flow 3/9: 06_matrix'), isFalse);
      expect(isPassProgressLine('[2/5] tap "Day"'), isFalse);
    });

    test('the SDK root sits two levels above adb', () {
      expect(
        sdkRootFromAdb(['D:', 'Sdk', 'platform-tools', 'adb.exe'].join(Platform.pathSeparator)),
        ['D:', 'Sdk'].join(Platform.pathSeparator),
      );
      expect(
        fleetAvdHome(const {'USERPROFILE': r'C:\Users\me'}, windows: true),
        joinPath(r'C:\Users\me', ['.android', 'avd']),
      );
      expect(fleetAvdHome(const {'ANDROID_AVD_HOME': '/avds', 'HOME': '/h'}, windows: false), '/avds');
    });
  });

  group('keep awake', () {
    FleetHost hostOn(FakeProcessRunner runner) => FleetHost(
          runner: runner,
          adb: Adb(executable: 'adb', runner: runner),
          avdHome: '.',
          sdkRoot: null,
          windows: true,
        );

    test('a booted fleet device gets the longest timeout and stay-awake', () async {
      final runner = FakeProcessRunner();
      await hostOn(runner).keepAwake('emulator-5558');
      expect(runner.lines, [
        'adb -s emulator-5558 shell settings put system screen_off_timeout 2147483647',
        'adb -s emulator-5558 shell svc power stayon true',
      ]);
    });

    test("the owner's emulator, or any non-fleet serial, is never touched", () async {
      final runner = FakeProcessRunner();
      for (final serial in ['emulator-5554', 'emulator-5557', 'R58M123ABC']) {
        await expectLater(hostOn(runner).keepAwake(serial), throwsA(isA<UsageFailure>()));
      }
      expect(runner.lines, isEmpty);
    });
  });

  group('stop guard', () {
    test('refuses a console that names another AVD, and emits no kill', () async {
      final runner = _RespondingRunner((r) {
        if (r.line == 'adb devices -l') {
          return const RunOutcome(0, 'List of devices attached\nemulator-5556 device\n', '');
        }
        if (r.line == 'adb -s emulator-5556 emu avd name') {
          return const RunOutcome(0, 'Pixel_9_Pro\r\nOK', '');
        }
        return null;
      });
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: '.',
        sdkRoot: null,
        windows: true,
      );
      await expectLater(
        host.stop(1),
        throwsA(isA<DeviceFailure>().having(
          (e) => e.message,
          'message',
          contains('reports AVD "Pixel_9_Pro", not anta_qa_1'),
        )),
      );
      expect(runner.lines.where((l) => l.contains('emu kill')), isEmpty);
    });

    test('stopRefusal passes only the AVD the verb named', () {
      expect(stopRefusal(expected: 'anta_qa_2', serial: 'emulator-5558', reported: 'anta_qa_2'), isNull);
      expect(stopRefusal(expected: 'anta_qa_2', serial: 'emulator-5558', reported: null), contains('reports AVD nothing'));
      expect(stopRefusal(expected: 'anta_qa_2', serial: 'emulator-5558', reported: 'anta_qa_3'), isNotNull);
    });

    test('a named fleet AVD is killed through its console and waited for', () async {
      var killed = false;
      final runner = _RespondingRunner((r) {
        if (r.line == 'adb devices -l') {
          return RunOutcome(
            0,
            'List of devices attached\nemulator-5554 device\n'
            '${killed ? '' : 'emulator-5560 device\n'}',
            '',
          );
        }
        if (r.line == 'adb -s emulator-5560 emu avd name') {
          return const RunOutcome(0, 'anta_qa_3\r\nOK', '');
        }
        if (r.line == 'adb -s emulator-5560 emu kill') {
          killed = true;
          return const RunOutcome(0, 'OK: killing emulator, bye bye', '');
        }
        return null;
      });
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: '.',
        sdkRoot: null,
        windows: true,
        pollEvery: Duration.zero,
      );
      expect(await host.stop(3), startsWith('stopped: anta_qa_3 (emulator-5560)'));
      expect(runner.lines.where((l) => l.contains('emu kill')), ['adb -s emulator-5560 emu kill']);
      expect(runner.lines.where((l) => l.contains('emulator-5554')), isEmpty);
    });

    test('a fleet AVD that is not running is nothing to stop', () async {
      final runner = FakeProcessRunner()
        ..script('adb devices -l', const RunOutcome(0, 'List of devices attached\n', ''));
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: '.',
        sdkRoot: null,
        windows: false,
      );
      expect(await host.stop(2), 'stopped: anta_qa_2 was not running');
      expect(runner.lines.where((l) => l.contains('emu')), isEmpty);
    });
  });

  group('status', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('anta_qa_fleet_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('parses the Windows process list with affinity, and ps without', () {
      final windows = parseQemuList(_qemuWindows);
      expect(windows.map((q) => (q.pid, q.avd, q.port, q.affinity)), [
        (11712, 'anta_qa_1', 5556, 0xFFFF),
        (19584, 'Pixel_9_Pro', null, 0xFFFFFF),
      ]);
      final ps = parseQemuList(
        '  412 /sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64-headless -avd anta_qa_2 -port 5558\n'
        '  413 /usr/bin/login -f me\n',
      );
      expect(ps.single.avd, 'anta_qa_2');
      expect(ps.single.port, 5558);
      expect(ps.single.affinity, isNull);
    });

    test('the state follows adb, the guest and the process list', () {
      FleetState of({bool created = true, String? adb, bool? boot, bool qemu = false}) =>
          fleetStateOf(created: created, adbState: adb, bootCompleted: boot, qemuAlive: qemu);
      expect(of(created: false), FleetState.notCreated);
      expect(of(), FleetState.stopped);
      expect(of(qemu: true), FleetState.booting);
      expect(of(adb: 'device', boot: false, qemu: true), FleetState.booting);
      expect(of(adb: 'device', boot: true, qemu: true), FleetState.device);
      expect(of(adb: 'offline', qemu: true), FleetState.offline);
    });

    test('members reads the AVD directory, adb, the console and installs', () async {
      final avds = Directory(joinPath(temp.path, ['avd']))..createSync();
      _writeAvd(avds, 'anta_qa_1', 'hw.ramSize=2048\n');
      _writeAvd(avds, 'anta_qa_2', 'hw.ramSize=2048\n');
      _writeAvd(avds, 'Pixel_9_Pro', 'hw.ramSize=2048\n');
      final paths = QaPaths(temp.path)..ensureBuildQa();
      final built = DateTime.utc(2026, 10, 23, 14);
      _record(built, installedAt: DateTime.utc(2026, 10, 23, 15))
          .write(paths.installedJsonFor('emulator-5556'));
      final runner = _RespondingRunner((r) {
        if (r.line == 'adb devices -l') {
          return const RunOutcome(
            0,
            'List of devices attached\nemulator-5554 device\nemulator-5556 device\n',
            '',
          );
        }
        if (r.line == 'adb -s emulator-5556 emu avd name') {
          return const RunOutcome(0, 'anta_qa_1\r\nOK', '');
        }
        if (r.line == 'adb -s emulator-5556 shell getprop sys.boot_completed') {
          return const RunOutcome(0, '1', '');
        }
        if (r.executable == 'powershell.exe' && r.arguments.last == qemuListScript) {
          return const RunOutcome(0, _qemuWindows, '');
        }
        return null;
      });
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: avds.path,
        sdkRoot: null,
        windows: true,
      );
      expect(host.avdNames(), ['Pixel_9_Pro', 'anta_qa_1', 'anta_qa_2']);
      expect(host.createdIndices(), [1, 2]);
      final members = await host.members(upTo: 3, paths: paths);
      expect(members.map((m) => (m.name, m.state)), [
        ('anta_qa_1', FleetState.device),
        ('anta_qa_2', FleetState.stopped),
        ('anta_qa_3', FleetState.notCreated),
      ]);
      expect(members.first.qemu?.pid, 11712);
      expect(members.first.installed?.gitHash, 'abc1234');
      expect(runner.lines.where((l) => l.contains('emulator-5554')), isEmpty,
          reason: 'the owner\'s emulator is never asked anything');

      final line = fleetStatusLine(members.first, _record(built), showAffinity: true);
      expect(line, startsWith('anta_qa_1   emulator-5556   device'));
      expect(line, contains('app installed abc1234'));
      expect(line, endsWith('qemu 11712 affinity=0xFFFF'));
      expect(fleetStatusLine(members[1], null, showAffinity: true), contains('app not installed'));
      expect(fleetStatusLine(members[2], null, showAffinity: true), contains('not created'));
      expect(ownerStatusLine('Pixel_9_Pro', parseQemuList(_qemuWindows).last),
          contains('running (qemu 19584)'));
    });

    test('a port held by another AVD is reported, not taken for the fleet\'s', () async {
      final avds = Directory(joinPath(temp.path, ['avd']))..createSync();
      _writeAvd(avds, 'anta_qa_1', 'hw.ramSize=2048\n');
      final runner = FakeProcessRunner()
        ..script('adb devices -l', const RunOutcome(0, 'emulator-5556 device\n', ''))
        ..script('adb -s emulator-5556 emu avd name', const RunOutcome(0, 'Pixel_9_Pro_XL\nOK', ''));
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: avds.path,
        sdkRoot: null,
        windows: false,
      );
      final member = (await host.members(upTo: 1, paths: QaPaths(temp.path))).single;
      expect(member.heldBy, 'Pixel_9_Pro_XL');
      expect(member.ready, isFalse);
      expect(member.stateText, 'port held by Pixel_9_Pro_XL');
    });

    test('an install older than apk.json is stale', () {
      final old = _record(DateTime.utc(2026, 10, 23, 10), hash: 'old1111');
      final now = _record(DateTime.utc(2026, 10, 23, 12), hash: 'new2222');
      expect(appStatus(null, now), 'not installed');
      expect(appStatus(old, now), startsWith('stale old1111'));
      expect(appStatus(old, now), contains('apk.json has new2222'));
      expect(appStatus(now, now), startsWith('installed new2222'));
      expect(isCurrentInstall(now, now), isTrue);
      expect(isCurrentInstall(old, now), isFalse);
      expect(isCurrentInstall(old, null), isFalse);
    });

    test('doctor names every AVD and warns about an unpinned one', () {
      const pinned = QemuProcess(pid: 1, avd: 'anta_qa_1', affinity: 0xFFFF);
      const unpinned = QemuProcess(pid: 2, avd: 'anta_qa_2', affinity: 0xFFFFFF);
      final ok = checkFleet([
        _member(1, qemu: pinned),
        _member(2, state: FleetState.stopped),
        _member(3, state: FleetState.notCreated),
      ], pinMask: 0xFFFF);
      expect(ok.status, CheckStatus.ok);
      expect(ok.detail, '3 AVDs: anta_qa_1 device pinned, anta_qa_2 stopped, anta_qa_3 not created');
      final warn = checkFleet([_member(1, qemu: pinned), _member(2, qemu: unpinned)], pinMask: 0xFFFF);
      expect(warn.status, CheckStatus.warn);
      expect(warn.fix, contains('qa fleet boot anta_qa_2'));
      expect(
        checkFleet([_member(1, qemu: unpinned)]).status,
        CheckStatus.ok,
        reason: 'no mask on a host that is not hybrid',
      );
      expect(
        checkFleet([_member(1, state: FleetState.notCreated)]).detail,
        contains('qa fleet create'),
      );
    });
  });

  group('create', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('anta_qa_fleet_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('reports drift and leaves an existing AVD alone without --retune', () async {
      _writeAvd(temp, 'anta_qa_1', 'hw.ramSize=1536\r\nhw.cpu.ncore=4\r\n');
      final runner = FakeProcessRunner();
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: temp.path,
        sdkRoot: null,
        windows: true,
      );
      final config = File(host.configPath('anta_qa_1'));
      final before = config.readAsStringSync();
      final report = await host.create(1, retune: false, image: () => fail('no image needed'));
      expect(report, contains('differs from the fleet spec: hw.ramSize=1536 (fleet: 2048)'));
      expect(config.readAsStringSync(), before);
      expect(runner.calls, isEmpty);

      final retuned = await host.create(1, retune: true, image: () => fail('no image needed'));
      expect(retuned, startsWith('retuned: anta_qa_1'));
      final after = config.readAsStringSync();
      expect(after, contains('hw.ramSize=2048\r\n'));
      expect(configDrift(splitConfig(after)), isEmpty);
      expect(await host.create(1, retune: false, image: () => null),
          'exists: anta_qa_1 — matches the fleet spec');
    });

    test('a missing AVD is made with avdmanager, answered no, then tuned', () async {
      final sdk = Directory(joinPath(temp.path, ['sdk']))..createSync();
      final avds = Directory(joinPath(temp.path, ['avd']))..createSync();
      final bin = Directory(joinPath(sdk.path, ['cmdline-tools', 'latest', 'bin']))
        ..createSync(recursive: true);
      final manager = File(joinPath(bin.path, ['avdmanager.bat']))..writeAsStringSync('');
      final runner = _RespondingRunner((r) {
        if (r.executable != manager.path) return null;
        _writeAvd(avds, 'anta_qa_3', 'hw.ramSize=1536M\nhw.lcd.density=420\n');
        return const RunOutcome(0, '', '');
      });
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: avds.path,
        sdkRoot: sdk.path,
        windows: true,
      );
      final report = await host.create(
        3,
        retune: false,
        image: () => 'system-images;android-36;google_apis_playstore;x86_64',
      );
      expect(report, startsWith('created: anta_qa_3'));
      final call = runner.calls.single;
      expect(call.arguments, avdCreateArgs('anta_qa_3', 'system-images;android-36;google_apis_playstore;x86_64'));
      expect(call.stdin, 'no\n');
      final config = splitConfig(File(host.configPath('anta_qa_3')).readAsStringSync());
      expect(configDrift(config), isEmpty);
    });

    test('a failed avdmanager is reported, not retried', () async {
      final sdk = Directory(joinPath(temp.path, ['sdk']))..createSync();
      final bin = Directory(joinPath(sdk.path, ['cmdline-tools', 'latest', 'bin']))
        ..createSync(recursive: true);
      File(joinPath(bin.path, ['avdmanager.bat'])).writeAsStringSync('');
      final runner = FakeProcessRunner(
        defaultOutcome: const RunOutcome(1, '', 'Error: Package path is not valid'),
      );
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: temp.path,
        sdkRoot: sdk.path,
        windows: true,
      );
      await expectLater(
        host.create(2, retune: false, image: () => 'system-images;x'),
        throwsA(isA<DeviceFailure>()),
      );
      expect(runner.calls, hasLength(1));
    });
  });

  group('fleet pass picks', () {
    final built = _record(DateTime.utc(2026, 10, 23, 12), hash: 'new2222');
    final current = _record(DateTime.utc(2026, 10, 23, 12), hash: 'new2222');
    final old = _record(DateTime.utc(2026, 10, 23, 9), hash: 'old1111');

    test('every ready device with an install; a stale one with a warning', () {
      final pick = pickPassDevices(
        members: [
          _member(1, installed: current),
          _member(2, installed: old),
          _member(3, state: FleetState.stopped, installed: current),
        ],
        built: built,
        suite: 'calendar',
        shardable: true,
      );
      expect(pick.members.map((m) => m.name), ['anta_qa_1', 'anta_qa_2']);
      expect(pick.warnings.single, contains('anta_qa_2 runs old1111'));
      expect(pick.refused, isEmpty);
      expect(pick.note, isNull);
    });

    test('a device with nothing installed is left out', () {
      final pick = pickPassDevices(
        members: [_member(1, installed: current), _member(2)],
        built: built,
        suite: 'calendar',
        shardable: true,
      );
      expect(pick.members.map((m) => m.name), ['anta_qa_1']);
      expect(pick.refused.single, contains('anta_qa_2 (emulator-5558): nothing installed'));
    });

    test('a port held by another AVD is never picked', () {
      final pick = pickPassDevices(
        members: [_member(1, installed: current, heldBy: 'Pixel_9_Pro_XL')],
        built: built,
        suite: 'calendar',
        shardable: true,
      );
      expect(pick.members, isEmpty);
    });

    test('shard=no runs whole on the first device and says so', () {
      final pick = pickPassDevices(
        members: [_member(1, installed: current), _member(2, installed: current)],
        built: built,
        suite: 'alerts',
        shardable: false,
      );
      expect(pick.members.map((m) => m.name), ['anta_qa_1']);
      expect(pick.note, contains('"alerts" says shard=no'));
    });

    test('--devices narrows the pick and names the ones that are not up', () {
      final pick = pickPassDevices(
        members: [
          _member(1, installed: current),
          _member(2, installed: current),
          _member(3, state: FleetState.stopped),
        ],
        built: built,
        suite: 'calendar',
        shardable: true,
        wanted: [2, 3, 2],
      );
      expect(pick.members.map((m) => m.name), ['anta_qa_2']);
      expect(pick.refused.single, contains('anta_qa_3: not up (stopped)'));
    });

    test('without apk.json every install is used with a warning', () {
      final pick = pickPassDevices(
        members: [_member(1, installed: old)],
        built: null,
        suite: 'calendar',
        shardable: true,
      );
      expect(pick.members, hasLength(1));
      expect(pick.warnings.single, contains('no build/qa/apk.json'));
    });
  });
}
