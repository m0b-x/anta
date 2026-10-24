import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/qa.dart' show FleetCommand, QaCommandRunner, QaContext;
import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/apk_build.dart';
import '../../tool/qa/src/doctor.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/shell_batch.dart';
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

const _bootA = '0c3a9d5e-6f1b-4c2a-9e7d-1b2c3d4e5f60';
const _bootB = '7d1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6';

/// A context whose fleet is [host], so a fleet verb runs over a fake.
class _FleetContext extends QaContext {
  _FleetContext(super.globalResults, {required super.paths, required this.host});

  final FleetHost host;

  @override
  FleetHost fleetHost() => host;
}

ApkRecord _record(
  DateTime builtAt, {
  String hash = 'abc1234',
  DateTime? installedAt,
  bool? driver = true,
  bool? qa = true,
}) =>
    ApkRecord(
      apk: 'app-debug.apk',
      gitHash: hash,
      dirty: false,
      builtAt: builtAt,
      defines: const [],
      installedAt: installedAt,
      driver: driver,
      qa: qa,
    );

FleetMember _member(
  int index, {
  FleetState state = FleetState.device,
  ApkRecord? installed,
  String? heldBy,
  QemuProcess? qemu,
  FleetLaunches? launches,
  int? gpuBytes,
}) =>
    FleetMember(
      index: index,
      created: state != FleetState.notCreated,
      state: state,
      installed: installed,
      heldBy: heldBy,
      qemu: qemu,
      launches: launches,
      gpuBytes: gpuBytes,
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

    test('the emulator boots windowed on its own port with the host GPU', () {
      for (var index = 1; index <= fleetMaxIndex; index++) {
        expect(fleetEmulatorArgs(index), isNot(contains('-no-window')),
            reason: 'a windowless qemu spins a host core while the guest idles');
      }
      expect(fleetEmulatorArgs(2), [
        '-avd',
        'anta_qa_2',
        '-port',
        '5558',
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
          keepState: true,
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
          '--no-recycle',
          '--label=nightly',
          '--stop-on-fail',
          '--keep-state',
        ],
      );
      expect(
        fleetPassChildArgs(
          serial: 'emulator-5556',
          suite: 'alerts',
          shard: null,
          jsonPath: 'a.json',
        ),
        ['-d', 'emulator-5556', 'pass', 'alerts', '--json=a.json', '--no-recycle'],
        reason: 'a one-guest fleet pass has no --shard, and its child still never recycles',
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

    test('only flow and shard verdicts, and the quiet line, are echoed live', () {
      expect(isPassProgressLine('=== 00_open: ok in 2104 ms'), isTrue);
      expect(isPassProgressLine('=== 22_palette: FAILED (exit 2) in 9000 ms'), isTrue);
      expect(isPassProgressLine('pass: 9/9 green in 230.0 s on emulator-5556 — report x'), isTrue);
      expect(isPassProgressLine('device left quiet (0 alarms armed) in 5.4 s'), isTrue);
      expect(isPassProgressLine('device not left quiet: relaunch --fresh: exit 3'), isTrue);
      expect(isPassProgressLine('[quiet] relaunch --fresh'), isFalse);
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

  group('pass grants', () {
    test('a fleet guest is granted POST_NOTIFICATIONS, each grant logged', () async {
      final runner = FakeProcessRunner();
      final lines = await applyPassGrants(
        Adb(executable: 'adb', runner: runner, serial: 'emulator-5558'),
        'emulator-5558',
      );
      expect(runner.lines, [
        'adb -s emulator-5558 shell pm grant com.alexzamfir.anta android.permission.POST_NOTIFICATIONS',
      ]);
      expect(lines, ['granted: POST_NOTIFICATIONS on emulator-5558']);
    });

    test('a refused grant says so with what pm printed', () async {
      final runner = FakeProcessRunner(
        defaultOutcome: const RunOutcome(255, '', 'Exception occurred while executing grant'),
      );
      final lines = await applyPassGrants(
        Adb(executable: 'adb', runner: runner, serial: 'emulator-5556'),
        'emulator-5556',
      );
      expect(lines.single,
          'not granted: POST_NOTIFICATIONS on emulator-5556 — Exception occurred while executing grant');
    });

    test('only a console that names a fleet AVD is granted unasked', () {
      expect(grantsPassPermissions(asked: false, consoleAvd: 'anta_qa_1'), isTrue);
      expect(grantsPassPermissions(asked: false, consoleAvd: 'anta_qa_3'), isTrue);
      // The owner's AVD on a fleet port is still the owner's.
      for (final avd in ['Pixel_9_Pro', 'anta_qa_x', null]) {
        expect(grantsPassPermissions(asked: false, consoleAvd: avd), isFalse, reason: avd);
        expect(grantsPassPermissions(asked: true, consoleAvd: avd), isTrue, reason: avd);
      }
    });
  });

  group('windows', () {
    const windowed =
        '25780\tFFFF\tD:\\Sdk\\emulator\\qemu\\windows-x86_64\\qemu-system-x86_64.exe '
        '-avd anta_qa_3 -port 5560 -no-audio -no-boot-anim -no-snapshot -no-metrics -gpu host\r\n';

    test('a fleet qemu is found under either binary; -no-window marks it headless', () {
      final found = parseQemuList(_qemuWindows + windowed);
      expect(found.map((q) => (q.avd, q.port, q.window)), [
        ('anta_qa_1', 5556, QemuWindow.headless),
        ('Pixel_9_Pro', null, null),
        ('anta_qa_3', 5560, null),
      ]);
      expect(
        parseQemuList('  412 /sdk/emulator/qemu/darwin-aarch64/qemu-system-aarch64-headless '
                '-avd anta_qa_2 -port 5558\n')
            .single
            .window,
        QemuWindow.headless,
      );
    });

    test('the window list parses by pid and ignores noise', () {
      expect(
        parseQemuWindows('19584 visible\r\n25780 minimized\r\n11712 headless\r\n'
            '30000 pending\r\n#< CLIXML\r\n31000 sideways\r\n'),
        {
          19584: QemuWindow.visible,
          25780: QemuWindow.minimized,
          11712: QemuWindow.headless,
          30000: QemuWindow.pending,
        },
      );
    });

    test('the window scripts minimize with SW_MINIMIZE and confirm with IsIconic', () {
      final script = minimizeWindowScript(25780);
      expect(script, contains('Get-Process -Id 25780'));
      expect(script, contains('MainWindowHandle'));
      expect(script, contains('ShowWindow(\$h, 6)'));
      expect(script, contains('IsIconic(\$h)'));
      expect(script, contains('AddSeconds(20)'));
      expect(qemuWindowScript, contains("Get-Process -Name 'qemu-system*'"));
      expect(qemuWindowScript, contains("-like '*headless*'"));
      final encoded = encodePowerShell(script);
      expect(encoded, isNot(contains('"')));
      final bytes = base64.decode(encoded);
      expect(
        String.fromCharCodes([
          for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
        ]),
        script,
      );
    });

    test('the host minimizes over -EncodedCommand and reads the windows', () async {
      final runner = _RespondingRunner((r) {
        if (r.executable != 'powershell.exe') return null;
        if (r.arguments.last == qemuListScript) {
          return const RunOutcome(0, _qemuWindows + windowed, '');
        }
        if (r.arguments.last == encodePowerShell(qemuWindowScript)) {
          return const RunOutcome(0, '11712 headless\r\n19584 visible\r\n25780 minimized\r\n', '');
        }
        if (r.arguments.last == encodePowerShell(minimizeWindowScript(25780))) {
          return const RunOutcome(0, 'minimized\r\n', '');
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
      expect(await host.minimize(25780), QemuWindow.minimized);
      expect(runner.calls.last.arguments, contains('-EncodedCommand'));
      final plain = await host.qemuProcesses();
      expect(plain.map((q) => q.window), [QemuWindow.headless, null, null]);
      final known = await host.qemuProcesses(windowStates: true);
      expect(known.map((q) => q.window),
          [QemuWindow.headless, QemuWindow.visible, QemuWindow.minimized]);

      final mac = FleetHost(
        runner: FakeProcessRunner(),
        adb: Adb(executable: 'adb', runner: FakeProcessRunner()),
        avdHome: '.',
        sdkRoot: null,
        windows: false,
      );
      expect(await mac.minimize(1), isNull);
    });

    test('status shows the window; doctor warns on a headless fleet qemu', () {
      const minimized = QemuProcess(
          pid: 25780, avd: 'anta_qa_3', affinity: 0xFFFF, window: QemuWindow.minimized);
      const headless = QemuProcess(
          pid: 11712, avd: 'anta_qa_1', affinity: 0xFFFF, window: QemuWindow.headless);
      final line = fleetStatusLine(_member(3, qemu: minimized), null, showAffinity: true);
      expect(line, endsWith('qemu 25780 affinity=0xFFFF priority=? window=minimized'));
      expect(_member(3, qemu: minimized).toJson(null)['window'], 'minimized');

      expect(checkFleet([_member(3, qemu: minimized)], pinMask: 0xFFFF).status, CheckStatus.ok);
      final warn = checkFleet([_member(1, qemu: headless), _member(3, qemu: minimized)],
          pinMask: 0xFFFF);
      expect(warn.status, CheckStatus.warn);
      expect(warn.detail, contains('anta_qa_1 device pinned headless'));
      expect(warn.fix, contains('re-boot it windowed: `qa fleet stop anta_qa_1`, `qa fleet boot anta_qa_1`'));
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
      expect(line, endsWith('qemu 11712 affinity=0xFFFF priority=? window=headless'),
          reason: 'a list from before the priority column reads it as unknown');
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

    test('a device whose record is not a QA driver build is left out', () {
      final at = DateTime.utc(2026, 10, 23, 12);
      final pick = pickPassDevices(
        members: [
          _member(1, installed: _record(at, driver: false)),
          _member(2, installed: _record(at, qa: false)),
          _member(3, installed: _record(at, driver: null, qa: null)),
        ],
        built: _record(at),
        suite: 'calendar',
        shardable: true,
      );
      expect(pick.members, isEmpty);
      expect(pick.refused, everyElement(contains('not a QA driver build')));
      expect(isCurrentInstall(_record(at, driver: false), _record(at)), isFalse);
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

  group('health', () {
    const gb = 1024 * 1024 * 1024;

    test('a guest past 40 launches or 8 GiB of GPU memory is due a recycle', () {
      expect(recycleReason(_member(1)), isNull);
      expect(
        recycleReason(_member(1, launches: const FleetLaunches(count: 40, sinceBoot: true))),
        isNull,
      );
      expect(
        recycleReason(_member(1, launches: const FleetLaunches(count: 41, sinceBoot: true))),
        '41 app launches since boot (over 40)',
      );
      expect(
        recycleReason(_member(1, launches: const FleetLaunches(count: 41, sinceBoot: false))),
        startsWith('41+ app launches'),
      );
      expect(recycleReason(_member(1, gpuBytes: 8 * gb)), isNull);
      expect(recycleReason(_member(1, gpuBytes: 9 * gb)),
          'its qemu holds 9216 MB of GPU memory (over 8192 MB)');
    });

    test('--no-recycle only warns; recycling lists the worn guests', () {
      final members = [
        _member(1, launches: const FleetLaunches(count: 52, sinceBoot: true)),
        _member(2, gpuBytes: 2 * gb),
        _member(3, gpuBytes: 40 * gb),
      ];
      final on = planRecycle(members, enabled: true);
      expect(on.recycle.map((m) => m.index), [1, 3]);
      expect(on.lines.first, startsWith('recycling anta_qa_1 (emulator-5556): 52 app launches'));
      final off = planRecycle(members, enabled: false);
      expect(off.recycle, isEmpty);
      expect(off.lines, everyElement(startsWith('warning: ')));
      expect(off.lines.last, contains('--no-recycle keeps it running'));
    });

    test('the launch count resets at boot and counts each launch', () {
      final dir = Directory.systemTemp.createTempSync('anta_fleet_launches_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = joinPath(dir.path, ['launches_emulator-5556.json']);
      expect(FleetLaunches.read(path), isNull);
      expect(FleetLaunches.record(path, DateTime.now()).label, '1+',
          reason: 'a guest booted before the counter existed');
      FleetLaunches.reset(path, DateTime.now());
      FleetLaunches.record(path, DateTime.now());
      final after = FleetLaunches.record(path, DateTime.now());
      expect((after.count, after.sinceBoot, after.label), (2, true, '2'));
    });

    test('the launch count is keyed by the boot id: a new boot starts it again', () {
      final dir = Directory.systemTemp.createTempSync('anta_fleet_launches_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = joinPath(dir.path, ['launches_emulator-5554.json']);
      final now = DateTime.now();
      FleetLaunches.record(path, now, bootId: _bootA);
      final same = FleetLaunches.record(path, now, bootId: _bootA);
      expect((same.count, same.sinceBoot, same.bootId), (2, false, _bootA));
      final unread = FleetLaunches.record(path, now);
      expect((unread.count, unread.bootId), (3, _bootA), reason: 'an unread id keeps counting');
      final rebooted = FleetLaunches.record(path, now, bootId: _bootB);
      expect((rebooted.count, rebooted.sinceBoot, rebooted.label), (1, false, '1+'),
          reason: 'the counter saw that boot already under way, as it sees a new device');
      expect(FleetLaunches.read(path)!.ofBoot(_bootB)?.count, 1);
      expect(FleetLaunches.read(path)!.ofBoot(_bootA), isNull);
      expect(FleetLaunches.read(path)!.ofBoot(null), isNull);
      File(path).writeAsStringSync('{"launches": 30, "sinceBoot": true}');
      final legacy = FleetLaunches.record(path, now, bootId: _bootB);
      expect((legacy.count, legacy.bootId), (31, _bootB),
          reason: 'a file from before the key is taken for this boot');
      FleetLaunches.reset(path, now, bootId: _bootA);
      expect(FleetLaunches.read(path)!.ofBoot(_bootA)?.count, 0);
      expect(FleetLaunches.read(path)!.sinceBoot, isTrue, reason: 'only a reset watched the boot');
    });

    test('a launch is counted on its boot, and only a fleet guest\'s 41st warns', () async {
      final dir = Directory.systemTemp.createTempSync('anta_fleet_launches_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final paths = QaPaths(dir.path);
      var bootId = _bootA;
      final runner = _RespondingRunner((r) =>
          r.line == 'adb -s emulator-5556 shell cat /proc/sys/kernel/random/boot_id'
              ? RunOutcome(0, '$bootId\n', '')
              : null);
      final device = Adb(executable: 'adb', runner: runner, serial: 'emulator-5556');
      var asked = 0;
      Future<String?> launch({required bool fleet}) => recordLaunch(
            device,
            'emulator-5556',
            paths,
            fleetGuest: () {
              asked++;
              return fleet;
            },
          );
      File(paths.launchesJsonFor('emulator-5556'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'launches': 39, 'sinceBoot': true, 'bootId': _bootA}));
      expect(await launch(fleet: true), isNull);
      expect(asked, 0, reason: 'the AVD directory is read only at the threshold');
      expect(await launch(fleet: true),
          'warning: 41 app launches on emulator-5556 since its boot — the guest slows '
          'with every one; the next reseeding `qa pass` on it recycles it first');
      expect(FleetLaunches.read(paths.launchesJsonFor('emulator-5556'))!.bootId, _bootA);
      File(paths.launchesJsonFor('emulator-5556'))
          .writeAsStringSync(jsonEncode({'launches': 40, 'sinceBoot': true, 'bootId': _bootA}));
      expect(await launch(fleet: false), isNull, reason: 'a port without its AVD is not the fleet\'s');
      bootId = _bootB;
      expect(await launch(fleet: true), isNull);
      expect(FleetLaunches.read(paths.launchesJsonFor('emulator-5556'))!.count, 1,
          reason: 'the device rebooted');
    });

    test('status shows a count only for the boot the guest is on now', () async {
      final temp = Directory.systemTemp.createTempSync('anta_qa_fleet_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final avds = Directory(joinPath(temp.path, ['avd']))..createSync();
      _writeAvd(avds, 'anta_qa_1', 'hw.ramSize=2048\n');
      final paths = QaPaths(temp.path);
      final runner = _RespondingRunner((r) => switch (r.line) {
            'adb devices -l' => const RunOutcome(0, 'emulator-5556 device\n', ''),
            'adb -s emulator-5556 emu avd name' => const RunOutcome(0, 'anta_qa_1\r\nOK', ''),
            'adb -s emulator-5556 shell getprop sys.boot_completed' =>
              const RunOutcome(0, '1', ''),
            'adb -s emulator-5556 shell cat /proc/sys/kernel/random/boot_id' =>
              const RunOutcome(0, '$_bootB\n', ''),
            _ when r.executable == 'powershell.exe' => const RunOutcome(0, _qemuWindows, ''),
            _ => null,
          });
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: avds.path,
        sdkRoot: null,
        windows: true,
      );
      void onFile(String bootId) => File(paths.launchesJsonFor('emulator-5556'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'launches': 45, 'sinceBoot': true, 'bootId': bootId}));

      onFile(_bootA);
      var member = (await host.members(upTo: 1, paths: paths)).single;
      expect(member.bootId, _bootB);
      expect(member.launches, isNull);
      expect(recycleReason(member), isNull, reason: 'an earlier boot\'s 45 are not this one\'s');
      expect(fleetStatusLine(member, null, showAffinity: false), isNot(contains('launches=')));
      expect(member.toJson(null), containsPair('bootId', _bootB));
      expect(member.toJson(null), containsPair('launches', null));

      onFile(_bootB);
      member = (await host.members(upTo: 1, paths: paths)).single;
      expect(member.launches?.count, 45);
      expect(fleetStatusLine(member, null, showAffinity: false), contains('launches=45'));
      expect(member.toJson(null), containsPair('launches', 45));
      expect(recycleReason(member), startsWith('45 app launches'));

      File(paths.launchesJsonFor('emulator-5556'))
          .writeAsStringSync(jsonEncode({'launches': 45, 'sinceBoot': true}));
      member = (await host.members(upTo: 1, paths: paths)).single;
      expect(recycleReason(member), startsWith('45 app launches'),
          reason: 'a count from before the key is this boot\'s, as record takes it');
    });

    test('status and doctor show launches and GPU memory; doctor warns when worn', () {
      const qemu = QemuProcess(pid: 1, avd: 'anta_qa_1', port: 5556, window: QemuWindow.minimized);
      final worn = _member(1,
          qemu: qemu,
          launches: const FleetLaunches(count: 45, sinceBoot: true),
          gpuBytes: 3 * gb);
      expect(fleetStatusLine(worn, null, showAffinity: false),
          endsWith('qemu 1 window=minimized  launches=45 gpu=3072 MB'));
      final check = checkFleet([worn]);
      expect(check.status, CheckStatus.warn);
      expect(check.detail, contains('due a recycle'));
      expect(check.fix, contains('`qa fleet stop anta_qa_1`, `qa fleet boot anta_qa_1`'));
      expect(checkFleet([_member(1, qemu: qemu)]).status, CheckStatus.ok);
    });

    test('the GPU counter is summed per pid over its adapters', () {
      expect(
        parseGpuMemory('pid_25460_luid_0x0_0x13f7c_phys_0 104013160448\r\n'
            'pid_25460_luid_0x0_0x15426_phys_0 5\r\n'
            'pid_25764_luid_0x0_0x13f7c_phys_0 3000000\r\nnoise\n'),
        {25460: 104013160453, 25764: 3000000},
      );
      expect(gpuMemoryScript([12]), contains(r'pid_12_*'));
    });

    test('a qemu that burns no CPU while off adb is hung; unread is not', () {
      expect(isIdleQemu(0.5, 0.5), isTrue);
      expect(isIdleQemu(10.0, 13.2), isFalse);
      expect(isIdleQemu(null, 0.5), isFalse);
    });
  });

  group('fleet boot', () {
    /// `fleet boot` of [names] over guests that are already up, the first
    /// answering its console as [firstReports]; what it ran and printed.
    Future<(int, FakeProcessRunner, List<String>)> boot(
      List<String> names, {
      String firstReports = 'anta_qa_1',
    }) async {
      final temp = Directory.systemTemp.createTempSync('anta_qa_fleet_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final avds = Directory(joinPath(temp.path, ['avd']))..createSync();
      for (final name in ['anta_qa_1', 'anta_qa_2', 'anta_qa_3']) {
        _writeAvd(avds, name, 'hw.ramSize=2048\n');
      }
      final sdk = Directory(joinPath(temp.path, ['sdk', 'emulator']))..createSync(recursive: true);
      File(joinPath(sdk.path, ['emulator'])).writeAsStringSync('');
      final runner = _RespondingRunner((r) {
        if (r.line == 'adb devices -l') {
          return const RunOutcome(
              0, 'emulator-5556 device\nemulator-5558 device\nemulator-5560 device\n', '');
        }
        for (final (serial, name) in [
          ('emulator-5556', firstReports),
          ('emulator-5558', 'anta_qa_2'),
          ('emulator-5560', 'anta_qa_3'),
        ]) {
          if (r.line == 'adb -s $serial emu avd name') return RunOutcome(0, '$name\r\nOK', '');
          if (r.line.startsWith('adb -s $serial shell ') && r.line.contains(batchSeparator)) {
            return const RunOutcome(0, '1\n$batchSeparator\n1\n$batchSeparator\n', '');
          }
        }
        return null;
      });
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: avds.path,
        sdkRoot: joinPath(temp.path, ['sdk']),
        windows: false,
      );
      final lines = <String>[];
      final qa = QaCommandRunner(
        contextFactory: (globals) =>
            _FleetContext(globals, paths: QaPaths(temp.path), host: host),
        commands: [FleetCommand()],
      )..lineSink = (line, {required prefix, required isError}) => lines.add(line);
      final code = await qa.run(
        ['fleet', 'boot', ...names, '--no-affinity', '--visible', '--priority', 'below'],
      );
      return (code ?? 0, runner as FakeProcessRunner, lines);
    }

    test('a failed guest ends the boot: the rest are not started, the recipe names them',
        () async {
      final (code, runner, lines) =
          await boot(['anta_qa_1', 'anta_qa_2', 'anta_qa_3'], firstReports: 'Pixel_9_Pro');
      expect(code, exitDevice);
      expect(runner.lines.where((l) => l.contains('emulator-5558') || l.contains('emulator-5560')),
          isEmpty);
      expect(lines, contains(startsWith('failed: anta_qa_1 emulator-5556')));
      expect(lines, contains('stopped at anta_qa_1 (anta_qa_2, anta_qa_3 not started) — '
          '`qa fleet stop anta_qa_1 --force`, then '
          '`qa fleet boot anta_qa_1 anta_qa_2 anta_qa_3`'));
      expect(lines, contains('priority: not set — never set off Windows'),
          reason: 'the option is accepted and ignored off Windows');
    });

    test('boots the guests one at a time, the next once the last is up', () async {
      final (code, runner, lines) = await boot(['anta_qa_1', 'anta_qa_2']);
      expect(code, 0);
      final calls = runner.lines;
      final lastOfFirst = calls.lastIndexWhere((l) => l.contains('emulator-5556'));
      final firstOfSecond = calls.indexWhere((l) => l.contains('emulator-5558'));
      expect(firstOfSecond, greaterThan(lastOfFirst),
          reason: 'anta_qa_2 is not asked anything before anta_qa_1 is ready');
      final ready = lines.where((l) => l.startsWith('ready: ')).toList();
      expect(ready, [
        startsWith('ready: anta_qa_1 emulator-5556'),
        startsWith('ready: anta_qa_2 emulator-5558'),
      ]);
    });
  });

  group('priority', () {
    test('the pin sets the class in the same PowerShell call and reads both back', () {
      final both = pinScript(42, mask: 0xFFFF, priority: 'BelowNormal');
      expect(both, contains('ProcessorAffinity = [IntPtr][int64]65535'));
      expect(both, contains("PriorityClass = 'BelowNormal'"));
      expect(both, isNot(contains('"')), reason: '-Command mangles double quotes');
      final classOnly = pinScript(42, priority: 'Normal');
      expect(classOnly, isNot(contains('ProcessorAffinity = ')));
      expect(classOnly, contains("PriorityClass = 'Normal'"));
      expect(parsePinReadback('FFFF BelowNormal\r\n'), (mask: 0xFFFF, priority: 'BelowNormal'));
      expect(parsePinReadback(''), (mask: null, priority: null));
    });

    test('the option maps to a class on Windows and is ignored elsewhere', () {
      expect(fleetPriority(windows: true, option: 'below').priority, 'BelowNormal');
      expect(fleetPriority(windows: true, option: 'normal').priority, 'Normal');
      final mac = fleetPriority(windows: false, option: 'below');
      expect((mac.priority, mac.reason), (null, 'never set off Windows'));
    });

    test('status shows the class the process list reads', () {
      final qemu = parseQemuList(
        '4242\tFFFF\tBelowNormal\tqemu-system-x86_64.exe -avd anta_qa_1 -port 5556 -gpu host\r\n',
      ).single;
      expect((qemu.pid, qemu.avd, qemu.affinity, qemu.priority), (4242, 'anta_qa_1', 0xFFFF, 'BelowNormal'));
      final member = _member(1, qemu: qemu);
      expect(fleetStatusLine(member, null, showAffinity: true),
          contains('qemu 4242 affinity=0xFFFF priority=BelowNormal'));
      expect(member.toJson(null), containsPair('priority', 'BelowNormal'));
    });

    test('a recycle\'s boot child keeps the class the guest ran with', () {
      const below = QemuProcess(pid: 1, avd: 'anta_qa_1', priority: 'BelowNormal');
      const high = QemuProcess(pid: 1, avd: 'anta_qa_1', priority: 'High');
      expect(fleetBootChildArgs('anta_qa_1', priority: priorityOptionOf(below)),
          ['fleet', 'boot', 'anta_qa_1', '--priority=below']);
      expect(priorityOptionOf(const QemuProcess(pid: 1, avd: 'anta_qa_1', priority: 'Normal')),
          'normal');
      expect(priorityOptionOf(high), isNull, reason: 'a class fleet boot never sets');
      expect(fleetBootChildArgs('anta_qa_1', priority: priorityOptionOf(null)),
          ['fleet', 'boot', 'anta_qa_1']);
    });
  });

  group('fleet stop --force', () {
    test('kills only a qemu whose command line names that AVD on its port', () {
      const hung = QemuProcess(pid: 27548, avd: 'anta_qa_2', port: 5558);
      expect(forceStopRefusal(hung, 2), isNull);
      expect(forceStopRefusal(hung, 3), contains('not anta_qa_3'));
      expect(forceStopRefusal(const QemuProcess(pid: 1, avd: 'Pixel_9_Pro', port: 5558), 2),
          contains('runs "Pixel_9_Pro"'));
      expect(forceStopRefusal(const QemuProcess(pid: 1, avd: 'anta_qa_2', port: 5554), 2),
          contains('not its fleet port 5558'));
      expect(forceStopRefusal(const QemuProcess(pid: 1, avd: 'anta_qa_2'), 2),
          contains('no -port'));
    });

    test('the kill script re-reads the command line and matches the name whole', () {
      final script = forceStopScript(27548, 'anta_qa_2');
      expect(script, contains("-Filter 'ProcessId=27548'"));
      expect(script, contains(r"-match '-avd\s+\W?anta_qa_2\b'"));
      expect(script, contains('Stop-Process -Id 27548 -Force'));
      expect(script, isNot(contains('"')), reason: '-Command mangles double quotes');
      final pattern = RegExp(r'-avd\s+\W?anta_qa_2\b');
      expect(pattern.hasMatch('qemu.exe -avd anta_qa_2 -port 5558'), isTrue);
      expect(pattern.hasMatch('qemu.exe -avd "anta_qa_2" -port 5558'), isTrue);
      expect(pattern.hasMatch('qemu.exe -avd anta_qa_23 -port 5600'), isFalse);
    });

    test('off adb and refused, nothing is killed; on adb it stops through the console',
        () async {
      final runner = FakeProcessRunner();
      runner.script('adb devices -l', const RunOutcome(0, 'List of devices attached\n', ''));
      runner.script(
        'powershell.exe -NoProfile -NonInteractive -Command $qemuListScript',
        const RunOutcome(0, '27548\tFFFF\tqemu-system-x86_64.exe -avd anta_qa_2 -port 5600', ''),
      );
      final host = FleetHost(
        runner: runner,
        adb: Adb(executable: 'adb', runner: runner),
        avdHome: '.',
        sdkRoot: null,
        windows: true,
        pollEvery: Duration.zero,
      );
      await expectLater(host.forceStop(2), throwsA(isA<DeviceFailure>()));
      expect(runner.lines.where((l) => l.contains('Stop-Process')), isEmpty);
    });
  });

  test('overlong digit runs are refused as usage, not a crash', () {
    expect(fleetIndexOfSerial('emulator-${'9' * 40}'), isNull);
    expect(() => parseFleetArgument('emulator-${'5' * 40}', serials: true),
        throwsA(isA<UsageFailure>()));
  });
}
