import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/qa/qa.dart'
    show
        ExpectCommand,
        PassCommand,
        QaCommand,
        QaCommandRunner,
        QaContext,
        ScrollToCommand,
        ShotCommand,
        StepsCommand,
        WaitCommand,
        passExitCode,
        shardIncompleteness;
import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/device_select.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/pass_report.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/ui_tree.dart';
import 'fake_process_runner.dart';

/// The one device a scripted pass runs on; everything else a verb could ask
/// of it is a test bug, so it fails loudly.
class _FakeDevice implements Device {
  _FakeDevice([this.id = 'emulator-5556']);

  @override
  DeviceKind get kind => id == 'macos' ? DeviceKind.macos : DeviceKind.android;

  @override
  final String id;

  @override
  String get label => '${kind == DeviceKind.macos ? 'macOS' : 'Android'} $id';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A context with no device behind it: a fixed screen, a fixed tree, and a
/// record of what `pass` asked for around each flow.
class _FakeContext extends QaContext {
  _FakeContext(super.globalResults, {required super.paths, this.deviceId = 'emulator-5556'});

  final String deviceId;

  /// The fleet a pass on a fleet serial reads; null is a host with no AVDs.
  FleetHost? fleet;

  /// Sees each child `qa` a verb starts, which never runs, and says how it
  /// exited.
  int Function(List<String> arguments)? onChild;

  int errorClears = 0;
  final List<String?> errorStamps = [];
  final List<({int out, int err})?> runLogOffsetsSeen = [];

  /// What each `dumpsys alarm` count answers, in order; the last repeats.
  List<int> armed = const [0];
  int alarmCounts = 0;

  static final List<int> _png = img.encodePng(img.Image(width: 8, height: 8));

  @override
  Future<Device> device() async => _FakeDevice(deviceId);

  @override
  FleetHost fleetHost() {
    final inert = FakeProcessRunner();
    return fleet ??
        FleetHost(
          runner: inert,
          adb: Adb(executable: 'adb', runner: inert),
          avdHome: joinPath(paths.projectRoot, ['no-avds']),
          sdkRoot: null,
          windows: false,
        );
  }

  @override
  Future<ChildOutcome> runSelf(
    List<String> arguments, {
    String? logPath,
    required void Function(String line, bool isError) onLine,
  }) async {
    return ChildOutcome(
      exitCode: onChild?.call(arguments) ?? 0,
      took: Duration.zero,
      started: true,
    );
  }

  @override
  Future<UiTree> dump({bool cache = true}) async => const UiTree([]);

  @override
  Future<List<int>> screenshotPng({ViaMode via = ViaMode.auto}) async => _png;

  @override
  Future<void> clearAgentErrors() async => errorClears++;

  @override
  Future<int?> armedAppAlarms() async =>
      armed[(alarmCounts++).clamp(0, armed.length - 1)];
}

/// A verb whose outcome the test scripts: it prints through the same
/// `out` the real verbs use, so `pass` captures its lines per step.
class _Verb extends QaCommand {
  _Verb(
    this.name,
    this.act, {
    List<String> flags = const [],
    List<String> options = const [],
  }) {
    for (final flag in flags) {
      argParser.addFlag(flag, negatable: false);
    }
    for (final option in options) {
      argParser.addMultiOption(option);
    }
  }

  @override
  final String name;

  final Future<int> Function(_Verb verb, List<String> rest) act;

  @override
  String get description => 'scripted $name';

  @override
  Future<int> run() => act(this, argResults!.rest);
}

const _bootId = '0c3a9d5e-6f1b-4c2a-9e7d-1b2c3d4e5f60';

/// adb as fleet guest anta_qa_1 answers it on emulator-5556: up until its
/// console is told to stop, then gone until the recycle's boot brings it
/// back ([down]). Every line lands in [events].
class _GuestRunner extends FakeProcessRunner {
  _GuestRunner(this.events);

  final List<String> events;
  bool down = false;

  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  }) async {
    final request = RunRequest(executable, arguments, binary: binary, stdin: stdin);
    calls.add(request);
    events.add(request.line);
    switch (request.line) {
      case 'adb devices -l':
        return RunOutcome(
          0,
          'List of devices attached\n${down ? '' : 'emulator-5556 device\n'}',
          '',
        );
      case 'adb -s emulator-5556 emu avd name':
        return const RunOutcome(0, 'anta_qa_1\r\nOK', '');
      case 'adb -s emulator-5556 shell getprop sys.boot_completed':
        return const RunOutcome(0, '1', '');
      case 'adb -s emulator-5556 shell cat /proc/sys/kernel/random/boot_id':
        return const RunOutcome(0, '$_bootId\n', '');
      case 'adb -s emulator-5556 emu kill':
        down = true;
        return const RunOutcome(0, 'OK', '');
    }
    if (executable == 'powershell.exe' && arguments.last == qemuListScript) {
      return RunOutcome(
        0,
        down ? '' : '4242\tFFFF\tBelowNormal\tqemu-system-x86_64.exe -avd anta_qa_1 -port 5556',
        '',
      );
    }
    return defaultOutcome;
  }
}

class _World {
  _World({String reseed = 'flow', required Map<String, String> flows}) {
    root = Directory.systemTemp.createTempSync('anta_qa_pass_');
    paths = QaPaths(root.path);
    final suite = Directory(joinPath(paths.flowsDir, ['demo']))..createSync(recursive: true);
    File(joinPath(suite.path, ['_suite.txt']))
        .writeAsStringSync('fixture=f.json\nreseed=$reseed\nprelude=_prelude.txt\n');
    File(joinPath(suite.path, ['_prelude.txt'])).writeAsStringSync('tap id:prelude\n');
    flows.forEach((name, steps) {
      File(joinPath(suite.path, ['$name.txt'])).writeAsStringSync(steps);
    });
  }

  late final Directory root;
  late final QaPaths paths;
  _FakeContext? context;

  /// 1-based reseeds that fail, counted over the whole pass.
  Set<int> failingReseeds = {};
  bool preludeFails = false;
  int reseeds = 0;

  /// `relaunch --fresh` with no seed: the pass leaving its device quiet.
  int quiets = 0;
  bool quietFails = false;
  List<int> armed = const [0];
  final List<String> taps = [];

  /// `report.json` as a `peek` step found it, mid-pass.
  final List<Map<String, dynamic>> peeks = [];

  /// The device the pass runs on.
  String deviceId = 'emulator-5556';

  /// Every adb line the fleet answered, each child `qa` and each relaunch,
  /// in the order the pass made them.
  final List<String> events = [];

  FleetHost? fleet;
  _GuestRunner? guest;

  /// The exit of the recycle's `fleet boot` child; non-zero leaves the
  /// guest down.
  int bootExit = 0;

  /// anta_qa_1 up on emulator-5556 with 45 launches on its current boot —
  /// due a recycle — and the same count on file for [others]. On a
  /// [windows] host its qemu runs at `BelowNormal`.
  void wearGuest({List<String> others = const [], bool windows = false}) {
    final avds = Directory(joinPath(root.path, ['avd']))..createSync();
    File(joinPath(avds.path, ['anta_qa_1.ini'])).writeAsStringSync('path=x\n');
    final avd = Directory(joinPath(avds.path, ['anta_qa_1.avd']))..createSync();
    File(joinPath(avd.path, ['config.ini'])).writeAsStringSync('hw.ramSize=2048\n');
    for (final serial in ['emulator-5556', ...others]) {
      File(paths.launchesJsonFor(serial))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'launches': 45, 'sinceBoot': true, 'bootId': _bootId}));
    }
    final runner = guest = _GuestRunner(events);
    fleet = FleetHost(
      runner: runner,
      adb: Adb(executable: 'adb', runner: runner),
      avdHome: avds.path,
      sdkRoot: null,
      windows: windows,
      pollEvery: Duration.zero,
    );
  }

  /// What the last pass logged.
  String passLog() {
    final report = File(paths.latestPassFor('demo')).readAsStringSync().trim();
    return File(joinPath(File(report).parent.path, ['pass.log'])).readAsStringSync();
  }

  /// The one pass directory there is, for a pass that wrote no report.
  Directory onlyPassDir() =>
      Directory(paths.passRoot).listSync().whereType<Directory>().single;

  QaCommandRunner runner() => QaCommandRunner(
        contextFactory: (ArgResults globals) => context =
            _FakeContext(globals, paths: paths, deviceId: deviceId)
              ..armed = armed
              ..fleet = fleet
              ..onChild = (arguments) {
                events.add('child: ${arguments.join(' ')}');
                if (bootExit == 0) guest?.down = false;
                return bootExit;
              },
        commands: [
          PassCommand(),
          ShotCommand(),
          StepsCommand(),
          _Verb('relaunch', (verb, _) async {
            events.add('relaunch');
            if ((verb.argResults!['seed'] as List<String>).isEmpty) {
              quiets++;
              if (quietFails) throw DeviceFailure('the reset was refused');
              verb.out('[qa] reset: ok');
              return 0;
            }
            reseeds++;
            if (failingReseeds.contains(reseeds)) {
              throw DeviceFailure('the seed was not imported');
            }
            verb.out('[qa] seed: imported');
            return 0;
          }, flags: const ['fresh'], options: const ['seed', 'setting']),
          _Verb('tap', (verb, rest) async {
            final target = rest.join(' ');
            taps.add(target);
            if (target == 'id:prelude' && preludeFails) {
              throw TargetFailure('no node matches "id:prelude"');
            }
            verb.out('tapped $target');
            return 0;
          }),
          _Verb('expect', (verb, rest) async {
            if (rest.contains('missing')) {
              throw TargetFailure('1 expectation(s) failed after 5s:\n  missing "missing"');
            }
            verb.out('ok  present  "${rest.join(' ')}"');
            return 0;
          }),
          _Verb('peek', (verb, _) async {
            final latest = File(paths.latestPassFor('demo')).readAsStringSync();
            peeks.add(jsonDecode(File(latest).readAsStringSync()) as Map<String, dynamic>);
            return 0;
          }),
          _Verb('errors', (verb, _) async {
            context!.errorStamps.add(context!.errorsSinceStamp);
            context!.runLogOffsetsSeen.add(context!.runLogOffsets);
            verb.out('agent: boom in this flow');
            return 0;
          }),
          _Verb('crash', (verb, _) async => throw StateError('a bug in a verb')),
          _Verb('grow', (verb, _) async {
            File(paths.runLog).writeAsStringSync('this flow\n', mode: FileMode.append);
            return 0;
          }),
        ],
      );

  Future<(int, PassReport)> pass([List<String> extra = const []]) async {
    final qa = runner();
    final code = await qa.run(['-d', 'emulator-5556', 'pass', 'demo', ...extra]) ?? 0;
    final latest = File(paths.latestPassFor('demo')).readAsStringSync();
    return (code, PassReport.decode(File(latest).readAsStringSync()));
  }

  void dispose() => root.deleteSync(recursive: true);
}

/// An agent on an app that has just been relaunched: its first [notYet]
/// dumps fail the way the real agent's do before the semantics tree
/// exists, then it answers with one node, `id:ready`.
class _StartingAgent implements UiDriver {
  _StartingAgent(this.notYet, {this.failure = 'no semantics tree yet (semantics enabled: true)'});

  int notYet;
  final String failure;
  int dumps = 0;

  @override
  String get name => 'agent';

  @override
  Duration get pollInterval => const Duration(milliseconds: 10);

  @override
  Future<UiDump> dump() async {
    dumps++;
    if (notYet > 0) {
      notYet--;
      throw DeviceFailure('agent dump: $failure');
    }
    return const UiDump(
      raw: '{}',
      tree: UiTree([
        UiNode(
          index: 0,
          parentIndex: -1,
          depth: 0,
          className: 'button',
          text: 'Ready',
          contentDesc: '',
          resourceId: 'ready',
          packageName: 'com.alexzamfir.anta',
          bounds: UiRect(0, 0, 100, 100),
          clickable: true,
          longClickable: false,
          enabled: true,
          focused: false,
          focusable: true,
          checked: false,
          checkable: false,
          selected: false,
          scrollable: false,
        ),
      ], source: UiTreeSource.agent),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StartingContext extends QaContext {
  _StartingContext(super.globalResults, {required super.paths, required this.starting});

  final _StartingAgent starting;

  @override
  Future<DeviceRef> ref() async => const DeviceRef(
        kind: DeviceKind.android,
        id: 'emulator-5556',
        label: 'Android emulator-5556',
      );

  @override
  Future<Device> device() async => _FakeDevice();

  @override
  Future<UiDriver> driver() async => starting;
}

void main() {
  group('qa pass over scripted verbs', () {
    test('a green suite exits 0 with a final, complete report', () async {
      final world = _World(flows: {
        '01_open': 'tap "A"\nexpect "B"\n',
        '02_next': 'expect "C"\n',
      });
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      expect(report.partial, isFalse);
      expect(report.flows.map((f) => f.status), [FlowStatus.passed, FlowStatus.passed]);
      expect(report.flows.first.steps.map((s) => s.line), ['tap "A"', 'expect "B"']);
      expect(world.reseeds, 2, reason: 'reseed=flow seeds every flow');
      expect(world.taps.where((t) => t == 'id:prelude'), hasLength(2));
      expect(world.context!.errorClears, 2, reason: 'each flow starts with an empty buffer');
    });

    test('a red flow, a malformed step and a later flow: the pass keeps going', () async {
      final world = _World(flows: {
        '01_open': 'tap "A"\n',
        '02_red': 'tap "A"\nexpect "missing"\ntap "never"\n',
        '03_parse': 'tap "Day\nexpect "B"\n',
        '04_last': 'peek\nexpect "B"\n',
      });
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitTarget);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.passed,
        FlowStatus.failed,
        FlowStatus.failed,
        FlowStatus.passed,
      ]);

      final red = report.flows[1];
      expect(red.steps, hasLength(2), reason: 'a flow stops at its own first failure');
      expect(red.failure!.step, 2);
      expect(red.failure!.exitCode, exitTarget);
      expect(red.failure!.message, contains('missing "missing"'));
      for (final evidence in [red.failure!.shot, red.failure!.dump, red.failure!.errors]) {
        expect(evidence, isNotNull);
        expect(File(evidence!).existsSync(), isTrue);
      }
      expect(File(red.failure!.errors!).readAsStringSync(), contains('agent: boom in this flow'));
      expect(world.context!.errorStamps, hasLength(2));
      expect(world.context!.errorStamps, everyElement(isNotNull),
          reason: "the evidence's errors start at the flow's own stamp");
      expect(world.context!.errorsSinceStamp, isNull);

      final parse = report.flows[2];
      expect(parse.steps.single.ok, isFalse);
      expect(parse.steps.single.output, contains('unbalanced'));
      expect(parse.failure!.step, 1);
      expect(parse.failure!.exitCode, exitUsage);
      expect(parse.failure!.line, 'tap "Day');

      expect(world.peeks, hasLength(1));
      final midPass = world.peeks.single;
      expect(midPass['partial'], isTrue);
      expect((midPass['flows'] as List).map((f) => (f as Map)['name']),
          ['01_open', '02_red', '03_parse']);
      expect(report.partial, isFalse);
    });

    test('a pass keeps its screenshots at the device size; a lone qa shot halves', () async {
      final world = _World(flows: {'01_shot': 'shot s1\nshot --scale 0.25 s2\nexpect "missing"\n'});
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitTarget);
      final flow = report.flows.single;
      int widthOf(String path) => img.decodePng(File(path).readAsBytesSync())!.width;
      final shots = flow.steps.take(2).map((s) => s.output.trim()).toList();
      expect(widthOf(shots[0]), 8, reason: 'a shot step in a pass is not resized');
      expect(widthOf(shots[1]), 2, reason: 'an explicit --scale still holds');
      expect(widthOf(flow.failure!.shot!), 8);

      final alone = joinPath(world.root.path, ['alone']);
      await world.runner().run(['-d', 'emulator-5556', 'shot', '--out', alone, 'a']);
      final file = Directory(alone).listSync().whereType<File>().single;
      expect(widthOf(file.path), 4, reason: 'outside a pass the default stays half size');
    });

    test('a failed reseed and a failed prelude are step 0, told apart by their line', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n', '03_c': 'tap "C"\n'})
        ..failingReseeds = {1};
      addTearDown(world.dispose);
      var (code, report) = await world.pass();
      expect(code, exitTarget);
      final reseed = report.flows.first.failure!;
      expect(reseed.step, 0);
      expect(reseed.line, startsWith('relaunch --fresh --seed f.json'));
      expect(reseed.exitCode, exitDevice);
      expect(report.flows.skip(1).map((f) => f.status), everyElement(FlowStatus.passed));

      world
        ..failingReseeds = {}
        ..preludeFails = true;
      (code, report) = await world.pass(['--only', '01_a']);
      expect(code, exitTarget);
      final prelude = report.flows.single.failure!;
      expect(prelude.step, 0);
      expect(prelude.line, '_prelude.txt: tap id:prelude');
      expect(report.flows.single.preludeMs, isNotNull);
    });

    test('two reseeds failing in a row skip the rest; nothing ran is exit 3', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n', '03_c': 'tap "C"\n'})
        ..failingReseeds = {1, 2};
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitDevice);
      expect(report.flows.map((f) => f.status),
          [FlowStatus.failed, FlowStatus.failed, FlowStatus.skipped]);
      expect(world.reseeds, 2);
    });

    test('a reseed=suite seed that does not go in stops the suite', () async {
      final world = _World(
        reseed: 'suite',
        flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n'},
      )..failingReseeds = {1};
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitDevice);
      expect(report.flows.map((f) => f.status), [FlowStatus.failed, FlowStatus.skipped]);
    });

    test('reseed=suite seeds once and still clears the errors before each flow', () async {
      final world = _World(
        reseed: 'suite',
        flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n'},
      );
      addTearDown(world.dispose);
      final (code, _) = await world.pass();
      expect(code, 0);
      expect(world.reseeds, 1);
      expect(world.context!.errorClears, 2);
    });

    test('--stop-on-fail skips every flow after the first red', () async {
      final world = _World(flows: {
        '01_red': 'expect "missing"\n',
        '02_b': 'tap "B"\n',
        '03_c': 'tap "C"\n',
      });
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--stop-on-fail']);
      expect(code, exitTarget);
      expect(report.flows.map((f) => f.status),
          [FlowStatus.failed, FlowStatus.skipped, FlowStatus.skipped]);
      expect(world.quiets, 0, reason: 'the red flow\'s screen is what it stopped for');
      expect(report.quietMs, isNull);
      expect(report.quietSkipped, contains('--stop-on-fail'));
      expect(quietLine(report), startsWith('quiet relaunch skipped: the pass stopped'));
    });

    test('--stop-on-fail with nothing red still ends quiet', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'});
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--stop-on-fail']);
      expect(code, 0);
      expect(world.quiets, 1);
      expect(report.quietSkipped, isNull);
    });

    test('--no-reseed runs on the app as it is and leaves it so', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n'});
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--no-reseed']);
      expect(code, 0);
      expect(world.reseeds, 0);
      expect(world.quiets, 0);
      expect(report.reseed, 'none');
      expect(report.quietSkipped, contains('--no-reseed'));
    });

    test('a verb that throws an Error fails its step, and the pass goes on', () async {
      final world = _World(flows: {'01_bug': 'tap "A"\ncrash\ntap "never"\n', '02_b': 'tap "B"\n'});
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitTarget);
      expect(report.partial, isFalse);
      final bug = report.flows.first;
      expect(bug.status, FlowStatus.failed);
      expect(bug.failure!.step, 2);
      expect(bug.failure!.exitCode, exitDevice);
      expect(bug.failure!.message, contains('internal error: Bad state: a bug in a verb'));
      expect(report.flows.last.status, FlowStatus.passed);
      expect(world.taps, isNot(contains('"never"')));
    });

    test("a red flow's run.log evidence starts at the flow's own offset", () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_red': 'grow\nexpect "missing"\n'});
      addTearDown(world.dispose);
      world.paths.ensureBuildQa();
      File(world.paths.runLog).writeAsStringSync('an earlier crash\n');
      final (code, _) = await world.pass();
      expect(code, exitTarget);
      expect(world.context!.runLogOffsetsSeen.single,
          (out: 'an earlier crash\n'.length, err: 0));
      expect(world.context!.runLogOffsets, isNull, reason: 'cleared after the evidence');
    });

    test('--summary of a report still marked partial prints PARTIAL and exits 3', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'});
      addTearDown(world.dispose);
      final (_, report) = await world.pass();
      final killed = joinPath(world.root.path, ['killed.json']);
      File(killed).writeAsStringSync(
        report.encode().replaceFirst('"partial": false', '"partial": true'),
      );
      expect(await world.runner().run(['pass', '--summary', killed]), exitDevice);
      expect(passExitCode(PassReport.decode(File(killed).readAsStringSync())), exitDevice);
      expect(passExitCode(report), 0);
    });

    test('a fleet shard is incomplete when partial, short, or its exit disagrees', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_red': 'expect "missing"\n'});
      addTearDown(world.dispose);
      final (_, report) = await world.pass();
      final partial = PassReport.decode(
        report.encode().replaceFirst('"partial": false', '"partial": true'),
      );
      expect(shardIncompleteness(report, exitCode: exitTarget, expected: 2), isNull);
      expect(shardIncompleteness(partial, exitCode: exitTarget, expected: 2),
          'shard stopped after 2 of 2 flows');
      expect(shardIncompleteness(report, exitCode: exitTarget, expected: 3),
          'shard stopped after 2 of 3 flows');
      expect(shardIncompleteness(report, exitCode: 255, expected: 2),
          'shard exited 255 over a report that says 1/2 green');
      expect(shardIncompleteness(report, exitCode: 0, expected: 2), isNotNull,
          reason: 'exit 0 over a red report');
    });

    test('--json keeps a copy current after every flow', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_b': 'peek\n'});
      addTearDown(world.dispose);
      final copy = joinPath(world.root.path, ['shard.json']);
      final (code, _) = await world.pass(['--json', copy]);
      expect(code, 0);
      final written = PassReport.decode(File(copy).readAsStringSync());
      expect(written.partial, isFalse);
      expect(written.flows, hasLength(2));
    });

    test('the pass ends with relaunch --fresh and no seed, then counts the armed alarms',
        () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_red': 'expect "missing"\n'})
        ..armed = const [2, 0];
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitTarget, reason: 'leaving the device quiet does not change the verdict');
      expect(world.reseeds, 2);
      expect(world.quiets, 1);
      expect(world.context!.alarmCounts, 2, reason: 'counted again until the reconcile ran');
      expect(report.quietMs, isNotNull);
      expect(report.quietAlarms, 0);
      expect(report.quietFailure, isNull);
      final reportPath = File(world.paths.latestPassFor('demo')).readAsStringSync().trim();
      final log = File(joinPath(File(reportPath).parent.path, ['pass.log'])).readAsStringSync();
      expect(log, contains('[quiet] relaunch --fresh'));
      expect(log, contains('device left quiet (0 alarms armed) in '));
    });

    test('--keep-state leaves the app as the last flow had it', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'});
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--keep-state']);
      expect(code, 0);
      expect(world.quiets, 0);
      expect(world.context!.alarmCounts, 0);
      expect(report.quietMs, isNull);
      expect(report.quietAlarms, isNull);
    });

    test('a quiet relaunch that fails is reported, not counted, and keeps exit 0', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..quietFails = true;
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      expect(world.quiets, 1);
      expect(world.context!.alarmCounts, 0);
      expect(report.quietFailure, 'relaunch --fresh: the reset was refused');
      expect(report.quietAlarms, isNull);
    });
  });

  group('a pass on a worn fleet guest', () {
    test('recycles it — stop, then a fleet boot child — before the first reseed', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
      addTearDown(world.dispose);
      final (code, _) = await world.pass();
      expect(code, 0);
      final kill = world.events.indexOf('adb -s emulator-5556 emu kill');
      final boot = world.events.indexOf('child: fleet boot anta_qa_1');
      expect(kill, isNonNegative);
      expect(boot, greaterThan(kill));
      expect(world.events.indexOf('relaunch'), greaterThan(boot));
      expect(world.passLog(),
          contains('recycling anta_qa_1 (emulator-5556): 45 app launches since boot (over 40)'));
      expect(world.passLog(), contains('recycled anta_qa_1 (emulator-5556)'));
    });

    test('the report and its summary say the pass recycled, why and how long', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
      addTearDown(world.dispose);
      final (_, report) = await world.pass();
      expect(report.recycle?.reason, '45 app launches since boot (over 40)');
      expect(report.recycle?.ms, isNonNegative);
      expect(PassReport.decode(report.encode()).recycle, report.recycle);
      expect(world.passLog(),
          matches(RegExp(r'recycled in \d+\.\d s: 45 app launches since boot \(over 40\)')));
      final other = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
      addTearDown(other.dispose);
      final (_, fresh) = await other.pass(['--no-recycle']);
      expect(fresh.recycle, isNull);
      expect(fresh.toJson().containsKey('recycle'), isFalse);
    });

    test('the boot child keeps the priority class the guest ran with', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest(windows: true);
      addTearDown(world.dispose);
      final (code, _) = await world.pass();
      expect(code, 0);
      expect(world.events, contains('child: fleet boot anta_qa_1 --priority=below'));
    });

    test('a guest that does not come back ends the pass before any flow', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})
        ..wearGuest()
        ..bootExit = exitDevice;
      addTearDown(world.dispose);
      final code = await world.runner().run(['-d', 'emulator-5556', 'pass', 'demo']);
      expect(code, exitDevice);
      expect(world.events, contains('child: fleet boot anta_qa_1'));
      expect(world.events, isNot(contains('relaunch')), reason: 'no flow ran');
      final dir = world.onlyPassDir();
      expect(File(joinPath(dir.path, ['report.json'])).existsSync(), isFalse);
      expect(File(world.paths.latestPassFor('demo')).existsSync(), isFalse);
      expect(File(joinPath(dir.path, ['pass.log'])).readAsStringSync(),
          contains('the guest did not come back after its recycle — '
              '`qa fleet stop anta_qa_1 --force`, then `qa fleet boot anta_qa_1`'));
    });

    test('--no-recycle skips the wear check altogether', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
      addTearDown(world.dispose);
      final (code, _) = await world.pass(['--no-recycle']);
      expect(code, 0);
      expect(world.events.where((e) => e != 'relaunch'), isEmpty);
      expect(world.passLog(), isNot(contains('recycl')));
    });

    test('--no-reseed keeps the guest it has: its flows run on what the app holds', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
      addTearDown(world.dispose);
      final (code, _) = await world.pass(['--no-reseed']);
      expect(code, 0);
      expect(world.events, isEmpty, reason: 'no fleet read, no reseed, no quiet relaunch');
      expect(world.passLog(), isNot(contains('recycl')));
    });

    test('a shard never recycles: its fleet pass already did', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n', '03_c': 'tap "C"\n'})
        ..wearGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--shard', '1/3']);
      expect(code, 0);
      expect(report.flows.map((f) => f.name), ['01_a']);
      expect(world.events.where((e) => e != 'relaunch'), isEmpty,
          reason: 'not even the fleet is read');
      expect(world.passLog(), isNot(contains('recycl')));
    });

    test('the owner\'s emulator, a phone and macOS are never recycled, silently', () async {
      for (final device in ['emulator-5554', 'R5CT30ABCDE', 'macos']) {
        final world = _World(flows: {'01_a': 'tap "A"\n'})
          ..wearGuest(others: [device])
          ..deviceId = device;
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(code, 0, reason: device);
        expect(report.device?.id, device);
        expect(world.events.where((e) => e != 'relaunch'), isEmpty, reason: device);
        expect(world.passLog(), isNot(contains('recycl')), reason: device);
      }
    });
  });

  group('an app still starting is "not yet", within the timeout', () {
    late Directory root;
    late QaPaths paths;
    setUp(() {
      root = Directory.systemTemp.createTempSync('anta_qa_starting_');
      paths = QaPaths(root.path);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<int> run(_StartingAgent agent, List<String> verb) async =>
        await QaCommandRunner(
          contextFactory: (globals) =>
              _StartingContext(globals, paths: paths, starting: agent),
          commands: [WaitCommand(), ExpectCommand(), ScrollToCommand()],
        ).run(['-d', 'emulator-5556', ...verb]) ??
        0;

    test('wait polls past two "no semantics tree yet" answers to the tree', () async {
      final agent = _StartingAgent(2);
      expect(await run(agent, ['wait', 'id:ready', '--timeout', '5']), 0);
      expect(agent.dumps, greaterThanOrEqualTo(3));
      expect(File(paths.lastDumpFor('emulator-5556')).existsSync(), isTrue);
    });

    test('expect and scroll-to ride it out the same way', () async {
      final expecting = _StartingAgent(2);
      expect(await run(expecting, ['expect', 'id:ready', '--timeout', '5']), 0);
      expect(expecting.dumps, 3);
      final scrolling = _StartingAgent(2, failure: 'the app has not drawn its first frame yet (still starting?)');
      expect(await run(scrolling, ['scroll-to', 'id:ready']), 0);
      expect(scrolling.dumps, 3);
    });

    test('past the timeout the failure stands, and any other failure at once', () async {
      final never = _StartingAgent(1 << 20);
      await expectLater(
        run(never, ['wait', 'id:ready', '--timeout', '1']),
        throwsA(isA<DeviceFailure>().having(
            (e) => e.message, 'message', contains('no semantics tree yet'))),
      );
      final broken = _StartingAgent(1, failure: 'the inspector produced no image');
      await expectLater(
        run(broken, ['wait', 'id:ready', '--timeout', '5']),
        throwsA(isA<DeviceFailure>()),
      );
      expect(broken.dumps, 1);
    });
  });

  group('qa steps', () {
    test('a malformed line fails its own step; --keep-going runs the next', () async {
      final world = _World(flows: const {});
      addTearDown(world.dispose);
      final expects = <String>[];
      final qa = QaCommandRunner(
        contextFactory: (globals) => _FakeContext(globals, paths: world.paths),
        commands: [
          StepsCommand(),
          _Verb('expect', (verb, rest) async {
            expects.add(rest.join(' '));
            return 0;
          }),
        ],
      );
      expect(await qa.run(['steps', '--keep-going', 'tap "Day', 'expect id:x']), exitUsage);
      expect(expects, ['id:x']);
      expect(await qa.run(['steps', 'tap "Day', 'expect id:y']), exitUsage);
      expect(expects, ['id:x'], reason: 'without --keep-going it stops at step 1');
    });
  });
}
