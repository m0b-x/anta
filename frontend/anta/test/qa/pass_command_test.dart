import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/qa/qa.dart'
    show
        ExpectCommand,
        FleetCommand,
        PassCommand,
        QaCommand,
        QaCommandRunner,
        QaContext,
        ScrollToCommand,
        SetCommand,
        ShareCommand,
        ShotCommand,
        StepsCommand,
        WaitCommand,
        passExitCode,
        resolveCaptures,
        shardIncompleteness;
import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/agent_protocol.dart';
import '../../tool/qa/src/apk_build.dart';
import '../../tool/qa/src/cancel.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/device_select.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/guest_state.dart';
import '../../tool/qa/src/pass_report.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/recovery.dart' show ceilingMessage;
import '../../tool/qa/src/shell_batch.dart';
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
  _FakeContext(
    super.globalResults, {
    required super.paths,
    this.deviceId = 'emulator-5556',
  });

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

  /// What each read of a ring in progress answers, in order; the last
  /// repeats.
  List<bool> ringing = const [false];
  int ringReads = 0;

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

  /// The Ctrl+C events a test sends; none unless it sets them.
  Stream<ProcessSignal> signals = const Stream.empty();

  /// What a Ctrl+C handler exited with; the process never ends under test.
  final Completer<int> exited = Completer<int>();

  @override
  Stream<ProcessSignal> interrupts() => signals;

  @override
  Future<Never> exitInterrupted(int code) {
    if (!exited.isCompleted) exited.complete(code);
    return Completer<Never>().future;
  }

  @override
  Future<ChildOutcome> runSelf(
    List<String> arguments, {
    String? logPath,
    Duration? timeout,
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

  @override
  Future<bool?> appRinging() async =>
      ringing[(ringReads++).clamp(0, ringing.length - 1)];
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

/// `14:05`, as a stop request's label prints a local time.
String _hhmm(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  final local = at.toLocal();
  return '${two(local.hour)}:${two(local.minute)}';
}

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
    final request = RunRequest(
      executable,
      arguments,
      binary: binary,
      stdin: stdin,
    );
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
    // `fleet boot`'s wait: sys.boot_completed and device_provisioned, both 1.
    if (request.line.startsWith('adb -s emulator-5556 shell ') &&
        request.line.contains(batchSeparator)) {
      return const RunOutcome(
        0,
        '1\n$batchSeparator\n1\n$batchSeparator\n',
        '',
      );
    }
    if (executable == 'powershell.exe' && arguments.last == qemuListScript) {
      return RunOutcome(
        0,
        down
            ? ''
            : '4242\tFFFF\tBelowNormal\tqemu-system-x86_64.exe -avd anta_qa_1 -port 5556',
        '',
      );
    }
    return defaultOutcome;
  }
}

class _World {
  _World({
    String reseed = 'flow',
    String manifest = '',
    required Map<String, String> flows,
  }) {
    root = Directory.systemTemp.createTempSync('anta_qa_pass_');
    paths = QaPaths(root.path);
    final suite = Directory(joinPath(paths.flowsDir, ['demo']))
      ..createSync(recursive: true);
    File(joinPath(suite.path, ['_suite.txt'])).writeAsStringSync(
      'fixture=f.json\nreseed=$reseed\nprelude=_prelude.txt\n$manifest',
    );
    File(
      joinPath(suite.path, ['_prelude.txt']),
    ).writeAsStringSync('tap id:prelude\n');
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
  List<bool> ringing = const [false];
  final List<String> taps = [];

  /// The guest's hold as a `held` step found it, mid-pass.
  final List<GuestHold?> holds = [];

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

  /// How many `die` steps take the guest down with them before it stays
  /// up; each removes the guest's state file the way an outside `fleet
  /// stop` does.
  int dieTimes = 1;
  int deaths = 0;

  /// A failing reseed also takes the guest down.
  bool reseedKillsGuest = false;

  /// How long a `hang` step sleeps before it prints `woke up`, and how
  /// many times it does before it answers at once.
  Duration hangFor = const Duration(milliseconds: 600);
  int hangTimes = 1 << 30;
  int hangs = 0;

  /// How long each reseed takes before it answers.
  Duration? reseedDelay;

  /// How long a `stuck` step sleeps, deaf to any cancellation.
  Duration stuckFor = const Duration(milliseconds: 600);

  /// How long `pass` waits for an attempt it cancelled.
  Duration abandonGrace = const Duration(seconds: 15);

  /// Ctrl+C as a `sigint` step or the quiet end ([interruptOnQuiet])
  /// sends it.
  final StreamController<ProcessSignal> signals =
      StreamController<ProcessSignal>.broadcast();
  bool interruptOnQuiet = false;

  /// anta_qa_1 up on emulator-5556 with 45 launches on its current boot —
  /// due a recycle — and the same count on file for [others]. On a
  /// [windows] host its qemu runs at `BelowNormal`.
  void wearGuest({List<String> others = const [], bool windows = false}) {
    final avds = Directory(joinPath(root.path, ['avd']))..createSync();
    File(joinPath(avds.path, ['anta_qa_1.ini'])).writeAsStringSync('path=x\n');
    final avd = Directory(joinPath(avds.path, ['anta_qa_1.avd']))..createSync();
    File(
      joinPath(avd.path, ['config.ini']),
    ).writeAsStringSync('hw.ramSize=2048\n');
    for (final serial in ['emulator-5556', ...others]) {
      File(paths.launchesJsonFor(serial))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'launches': 45, 'sinceBoot': true, 'bootId': _bootId}),
        );
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

  /// anta_qa_1 created on a Windows host but not running: adb lists
  /// nothing on emulator-5556 until a `fleet boot` child brings it up.
  void downGuest() {
    final avds = Directory(joinPath(root.path, ['avd']))..createSync();
    File(joinPath(avds.path, ['anta_qa_1.ini'])).writeAsStringSync('path=x\n');
    final avd = Directory(joinPath(avds.path, ['anta_qa_1.avd']))..createSync();
    File(joinPath(avd.path, ['config.ini'])).writeAsStringSync('x=1\n');
    final runner = guest = _GuestRunner(events)..down = true;
    fleet = FleetHost(
      runner: runner,
      adb: Adb(executable: 'adb', runner: runner),
      avdHome: avds.path,
      sdkRoot: null,
      windows: true,
      pollEvery: Duration.zero,
    );
  }

  /// anta_qa_1 created and up on emulator-5556, on a Windows host unless
  /// [windows] is false: the guest a pass may recover.
  void upGuest({bool windows = true}) {
    downGuest();
    guest!.down = false;
    if (!windows) {
      fleet = FleetHost(
        runner: guest!,
        adb: Adb(executable: 'adb', runner: guest!),
        avdHome: fleet!.avdHome,
        sdkRoot: null,
        windows: false,
        pollEvery: Duration.zero,
      );
    }
  }

  /// The children `pass` started, as `child: …` events.
  List<String> get children =>
      events.where((e) => e.startsWith('child: ')).toList();

  /// What the last pass logged.
  String passLog() {
    final report = File(paths.latestPassFor('demo')).readAsStringSync().trim();
    return File(
      joinPath(File(report).parent.path, ['pass.log']),
    ).readAsStringSync();
  }

  /// The one pass directory there is, for a pass that wrote no report.
  Directory onlyPassDir() =>
      Directory(paths.passRoot).listSync().whereType<Directory>().single;

  QaCommandRunner runner() => QaCommandRunner(
    contextFactory: (ArgResults globals) =>
        context = _FakeContext(globals, paths: paths, deviceId: deviceId)
          ..armed = armed
          ..ringing = ringing
          ..fleet = fleet
          ..signals = signals.stream
          ..onChild = (arguments) {
            events.add('child: ${arguments.join(' ')}');
            if (bootExit == 0) guest?.down = false;
            return bootExit;
          },
    commands: [
      PassCommand(abandonGrace: abandonGrace),
      ShotCommand(),
      StepsCommand(),
      _Verb(
        'relaunch',
        (verb, _) async {
          events.add('relaunch');
          if ((verb.argResults!['seed'] as List<String>).isEmpty) {
            quiets++;
            if (interruptOnQuiet) {
              signals.add(ProcessSignal.sigint);
              // Long enough for a handler that would run to have run.
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            if (quietFails) throw DeviceFailure('the reset was refused');
            verb.out('[qa] reset: ok');
            return 0;
          }
          reseeds++;
          final delay = reseedDelay;
          if (delay != null) await Future<void>.delayed(delay);
          if (failingReseeds.contains(reseeds)) {
            if (reseedKillsGuest) guest?.down = true;
            throw DeviceFailure('the seed was not imported');
          }
          verb.out('[qa] seed: imported');
          return 0;
        },
        flags: const ['fresh'],
        options: const ['seed', 'setting'],
      ),
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
          throw TargetFailure(
            '1 expectation(s) failed after 5s:\n  missing "missing"',
          );
        }
        verb.out('ok  present  "${rest.join(' ')}"');
        return 0;
      }),
      _Verb('peek', (verb, _) async {
        final latest = File(paths.latestPassFor('demo')).readAsStringSync();
        peeks.add(
          jsonDecode(File(latest).readAsStringSync()) as Map<String, dynamic>,
        );
        return 0;
      }),
      _Verb('errors', (verb, _) async {
        events.add('errors');
        context!.errorStamps.add(context!.errorsSinceStamp);
        context!.runLogOffsetsSeen.add(context!.runLogOffsets);
        verb.out('agent: boom in this flow');
        return 0;
      }),
      _Verb('crash', (verb, _) async => throw StateError('a bug in a verb')),
      _Verb('die', (verb, _) async {
        if (deaths < dieTimes) {
          deaths++;
          guest?.down = true;
          GuestState.forget(paths.guestStateFor('anta_qa_1'));
          throw DeviceFailure('adb: device \'emulator-5556\' not found');
        }
        verb.out('alive');
        return 0;
      }),
      _Verb(
        'fail3',
        (verb, _) async =>
            throw DeviceFailure('the agent did not answer the dump'),
      ),
      // Waits the way the real verbs wait between polls, so a cancelled
      // attempt's hang ends at once.
      _Verb('hang', (verb, _) async {
        if (hangs++ >= hangTimes) return 0;
        try {
          await pause(hangFor);
        } on Cancelled {
          events.add('hang: cancelled');
          rethrow;
        }
        verb.out('woke up');
        events.add('hang: woke up');
        return 0;
      }),
      // A step that ignores every cancellation.
      _Verb('stuck', (verb, _) async {
        await Future<void>.delayed(stuckFor);
        events.add('stuck: woke up');
        return 0;
      }),
      _Verb('sigint', (verb, _) async {
        events.add('sigint');
        signals.add(ProcessSignal.sigint);
        return 0;
      }),
      // Someone stops the guest on purpose under the pass: the request on
      // file, then the guest gone, as `fleet stop --force` leaves it.
      _Verb('stopped', (verb, _) async {
        StopRequest.record(
          paths.stopRequestFor('anta_qa_1'),
          StopRequest(
            by: 'fleet stop --force',
            pid: 4711,
            at: DateTime.now(),
            checkout: r'D:\other\anta',
          ),
        );
        guest?.down = true;
        GuestState.forget(paths.guestStateFor('anta_qa_1'));
        throw DeviceFailure('adb: device \'emulator-5556\' not found');
      }),
      _Verb('pause', (verb, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return 0;
      }),
      _Verb('held', (verb, _) async {
        holds.add(GuestState.read(paths.guestStateFor('anta_qa_1'))?.hold);
        return 0;
      }),
      _Verb('grow', (verb, _) async {
        File(
          paths.runLog,
        ).writeAsStringSync('this flow\n', mode: FileMode.append);
        return 0;
      }),
    ],
  );

  Future<(int, PassReport)> pass([List<String> extra = const []]) async {
    final qa = runner();
    final code =
        await qa.run(['-d', 'emulator-5556', 'pass', 'demo', ...extra]) ?? 0;
    final latest = File(paths.latestPassFor('demo')).readAsStringSync();
    return (code, PassReport.decode(File(latest).readAsStringSync()));
  }

  /// A pass a Ctrl+C ends: the code its handler exited with (the pass's
  /// own run never returns once the handler owns the ending) and the
  /// report as the handler left it.
  Future<(int, PassReport)> interruptedPass([
    List<String> extra = const [],
  ]) async {
    final qa = runner();
    context = null;
    unawaited(qa.run(['-d', 'emulator-5556', 'pass', 'demo', ...extra]));
    while (context == null) {
      await Future<void>.delayed(Duration.zero);
    }
    final code = await context!.exited.future.timeout(
      const Duration(seconds: 10),
    );
    final latest = File(paths.latestPassFor('demo')).readAsStringSync();
    return (code, PassReport.decode(File(latest).readAsStringSync()));
  }

  void dispose() => root.deleteSync(recursive: true);
}

/// An agent on an app that has just been relaunched: its first [notYet]
/// dumps fail the way the real agent's do before the semantics tree
/// exists, then it answers with one node, `id:ready`.
class _StartingAgent implements UiDriver {
  _StartingAgent(
    this.notYet, {
    this.failure = 'no semantics tree yet (semantics enabled: true)',
  });

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
  _StartingContext(
    super.globalResults, {
    required super.paths,
    required this.starting,
  });

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
      final world = _World(
        flows: {'01_open': 'tap "A"\nexpect "B"\n', '02_next': 'expect "C"\n'},
      );
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      expect(report.partial, isFalse);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.passed,
        FlowStatus.passed,
      ]);
      expect(report.flows.first.steps.map((s) => s.line), [
        'tap "A"',
        'expect "B"',
      ]);
      expect(world.reseeds, 2, reason: 'reseed=flow seeds every flow');
      expect(world.taps.where((t) => t == 'id:prelude'), hasLength(2));
      expect(
        world.context!.errorClears,
        2,
        reason: 'each flow starts with an empty buffer',
      );
    });

    test(
      'a pass on a fleet guest holds it while it runs and leaves it used',
      () async {
        final world = _World(flows: {'01_open': 'held\n'});
        addTearDown(world.dispose);
        final file = world.paths.guestStateFor('anta_qa_1');
        final before = DateTime.now();
        final (code, _) = await world.pass();
        expect(code, 0);
        expect(world.holds.single?.pid, pid, reason: 'held by this process');
        expect(world.holds.single?.verb, 'pass');
        final after = GuestState.read(file)!;
        expect(after.hold, isNull, reason: 'released when the pass ended');
        expect(after.lastUsedAt!.isBefore(before), isFalse);
      },
    );

    test('a pass on the owner\'s emulator writes no guest file', () async {
      final world = _World(flows: {'01_open': 'held\n'})
        ..deviceId = 'emulator-5554';
      addTearDown(world.dispose);
      await world.pass();
      expect(world.holds.single, isNull);
      for (final dir in [world.paths.buildQa, world.paths.fleetState]) {
        expect(
          Directory(dir).existsSync()
              ? Directory(
                  dir,
                ).listSync().where((e) => e.path.contains('guest_'))
              : const [],
          isEmpty,
          reason: dir,
        );
      }
    });

    test(
      'a pass beats its hold at every flow and names its checkout',
      () async {
        final world = _World(flows: {'01_open': 'held\n', '02_more': 'held\n'});
        addTearDown(world.dispose);
        final (code, _) = await world.pass();
        expect(code, 0);
        expect(world.holds, hasLength(2));
        final [first, second] = world.holds.map((h) => h!).toList();
        expect(
          first.beatAt,
          isNotNull,
          reason: 'a long pass must not go quiet',
        );
        expect(second.beatAt!.isBefore(first.beatAt!), isFalse);
        expect(second.checkout, world.paths.projectRoot);
      },
    );

    test(
      'a red flow, a malformed step and a later flow: the pass keeps going',
      () async {
        final world = _World(
          flows: {
            '01_open': 'tap "A"\n',
            '02_red': 'tap "A"\nexpect "missing"\ntap "never"\n',
            '03_parse': 'tap "Day\nexpect "B"\n',
            '04_last': 'peek\nexpect "B"\n',
          },
        );
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
        expect(
          red.steps,
          hasLength(2),
          reason: 'a flow stops at its own first failure',
        );
        expect(red.failure!.step, 2);
        expect(red.failure!.exitCode, exitTarget);
        expect(red.failure!.message, contains('missing "missing"'));
        for (final evidence in [
          red.failure!.shot,
          red.failure!.dump,
          red.failure!.errors,
        ]) {
          expect(evidence, isNotNull);
          expect(File(evidence!).existsSync(), isTrue);
        }
        expect(
          File(red.failure!.errors!).readAsStringSync(),
          contains('agent: boom in this flow'),
        );
        expect(world.context!.errorStamps, hasLength(2));
        expect(
          world.context!.errorStamps,
          everyElement(isNotNull),
          reason: "the evidence's errors start at the flow's own stamp",
        );
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
        expect((midPass['flows'] as List).map((f) => (f as Map)['name']), [
          '01_open',
          '02_red',
          '03_parse',
        ]);
        expect(report.partial, isFalse);
      },
    );

    test(
      'a pass keeps its screenshots at the device size; a lone qa shot halves',
      () async {
        final world = _World(
          flows: {
            '01_shot': 'shot s1\nshot --scale 0.25 s2\nexpect "missing"\n',
          },
        );
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(code, exitTarget);
        final flow = report.flows.single;
        int widthOf(String path) =>
            img.decodePng(File(path).readAsBytesSync())!.width;
        final shots = flow.steps.take(2).map((s) => s.output.trim()).toList();
        expect(
          widthOf(shots[0]),
          8,
          reason: 'a shot step in a pass is not resized',
        );
        expect(widthOf(shots[1]), 2, reason: 'an explicit --scale still holds');
        expect(widthOf(flow.failure!.shot!), 8);

        final alone = joinPath(world.root.path, ['alone']);
        await world.runner().run([
          '-d',
          'emulator-5556',
          'shot',
          '--out',
          alone,
          'a',
        ]);
        final file = Directory(alone).listSync().whereType<File>().single;
        expect(
          widthOf(file.path),
          4,
          reason: 'outside a pass the default stays half size',
        );
      },
    );

    test(
      'a failed reseed and a failed prelude are step 0, told apart by their line',
      () async {
        final world = _World(
          flows: {
            '01_a': 'tap "A"\n',
            '02_b': 'tap "B"\n',
            '03_c': 'tap "C"\n',
          },
        )..failingReseeds = {1};
        addTearDown(world.dispose);
        var (code, report) = await world.pass();
        expect(code, exitTarget);
        final reseed = report.flows.first.failure!;
        expect(reseed.step, 0);
        expect(reseed.line, startsWith('relaunch --fresh --seed f.json'));
        expect(reseed.exitCode, exitDevice);
        expect(
          report.flows.skip(1).map((f) => f.status),
          everyElement(FlowStatus.passed),
        );

        world
          ..failingReseeds = {}
          ..preludeFails = true;
        (code, report) = await world.pass(['--only', '01_a']);
        expect(code, exitTarget);
        final prelude = report.flows.single.failure!;
        expect(prelude.step, 0);
        expect(prelude.line, '_prelude.txt: tap id:prelude');
        expect(report.flows.single.preludeMs, isNotNull);
      },
    );

    test(
      'two reseeds failing in a row skip the rest; nothing ran is exit 3',
      () async {
        final world = _World(
          flows: {
            '01_a': 'tap "A"\n',
            '02_b': 'tap "B"\n',
            '03_c': 'tap "C"\n',
          },
        )..failingReseeds = {1, 2};
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(code, exitDevice);
        expect(report.flows.map((f) => f.status), [
          FlowStatus.failed,
          FlowStatus.failed,
          FlowStatus.skipped,
        ]);
        expect(world.reseeds, 2);
      },
    );

    test('a reseed=suite seed that does not go in stops the suite', () async {
      final world = _World(
        reseed: 'suite',
        flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n'},
      )..failingReseeds = {1};
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitDevice);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.failed,
        FlowStatus.skipped,
      ]);
    });

    test(
      'reseed=suite seeds once and still clears the errors before each flow',
      () async {
        final world = _World(
          reseed: 'suite',
          flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n'},
        );
        addTearDown(world.dispose);
        final (code, _) = await world.pass();
        expect(code, 0);
        expect(world.reseeds, 1);
        expect(world.context!.errorClears, 2);
      },
    );

    test('--stop-on-fail skips every flow after the first red', () async {
      final world = _World(
        flows: {
          '01_red': 'expect "missing"\n',
          '02_b': 'tap "B"\n',
          '03_c': 'tap "C"\n',
        },
      );
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--stop-on-fail']);
      expect(code, exitTarget);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.failed,
        FlowStatus.skipped,
        FlowStatus.skipped,
      ]);
      expect(
        world.quiets,
        0,
        reason: 'the red flow\'s screen is what it stopped for',
      );
      expect(report.quietMs, isNull);
      expect(report.quietSkipped, contains('--stop-on-fail'));
      expect(
        quietLine(report),
        startsWith('quiet relaunch skipped: the pass stopped'),
      );
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

    test(
      'a verb that throws an Error fails its step, and the pass goes on',
      () async {
        final world = _World(
          flows: {
            '01_bug': 'tap "A"\ncrash\ntap "never"\n',
            '02_b': 'tap "B"\n',
          },
        );
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(code, exitTarget);
        expect(report.partial, isFalse);
        final bug = report.flows.first;
        expect(bug.status, FlowStatus.failed);
        expect(bug.failure!.step, 2);
        expect(bug.failure!.exitCode, exitDevice);
        expect(
          bug.failure!.message,
          contains('internal error: Bad state: a bug in a verb'),
        );
        expect(report.flows.last.status, FlowStatus.passed);
        expect(world.taps, isNot(contains('"never"')));
      },
    );

    test(
      "a red flow's run.log evidence starts at the flow's own offset",
      () async {
        final world = _World(
          flows: {'01_a': 'tap "A"\n', '02_red': 'grow\nexpect "missing"\n'},
        );
        addTearDown(world.dispose);
        world.paths.ensureBuildQa();
        File(world.paths.runLog).writeAsStringSync('an earlier crash\n');
        final (code, _) = await world.pass();
        expect(code, exitTarget);
        expect(world.context!.runLogOffsetsSeen.single, (
          out: 'an earlier crash\n'.length,
          err: 0,
        ));
        expect(
          world.context!.runLogOffsets,
          isNull,
          reason: 'cleared after the evidence',
        );
      },
    );

    test(
      '--summary of a report still marked partial prints PARTIAL and exits 3',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'});
        addTearDown(world.dispose);
        final (_, report) = await world.pass();
        final killed = joinPath(world.root.path, ['killed.json']);
        File(killed).writeAsStringSync(
          report.encode().replaceFirst('"partial": false', '"partial": true'),
        );
        expect(
          await world.runner().run(['pass', '--summary', killed]),
          exitDevice,
        );
        expect(
          passExitCode(PassReport.decode(File(killed).readAsStringSync())),
          exitDevice,
        );
        expect(passExitCode(report), 0);
      },
    );

    test(
      'a fleet shard is incomplete when partial, short, or its exit disagrees',
      () async {
        final world = _World(
          flows: {'01_a': 'tap "A"\n', '02_red': 'expect "missing"\n'},
        );
        addTearDown(world.dispose);
        final (_, report) = await world.pass();
        final partial = PassReport.decode(
          report.encode().replaceFirst('"partial": false', '"partial": true'),
        );
        expect(
          shardIncompleteness(report, exitCode: exitTarget, expected: 2),
          isNull,
        );
        expect(
          shardIncompleteness(partial, exitCode: exitTarget, expected: 2),
          'shard stopped after 2 of 2 flows',
        );
        expect(
          shardIncompleteness(report, exitCode: exitTarget, expected: 3),
          'shard stopped after 2 of 3 flows',
        );
        expect(
          shardIncompleteness(report, exitCode: 255, expected: 2),
          'shard exited 255 over a report that says 1/2 green',
        );
        expect(
          shardIncompleteness(report, exitCode: 0, expected: 2),
          isNotNull,
          reason: 'exit 0 over a red report',
        );
      },
    );

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

    test(
      'the pass ends with relaunch --fresh and no seed, then counts the armed alarms',
      () async {
        final world = _World(
          flows: {'01_a': 'tap "A"\n', '02_red': 'expect "missing"\n'},
        )..armed = const [2, 0];
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(
          code,
          exitTarget,
          reason: 'leaving the device quiet does not change the verdict',
        );
        expect(world.reseeds, 2);
        expect(world.quiets, 1);
        expect(
          world.context!.alarmCounts,
          2,
          reason: 'counted again until the reconcile ran',
        );
        expect(report.quietMs, isNotNull);
        expect(report.quietAlarms, 0);
        expect(report.quietFailure, isNull);
        final reportPath = File(
          world.paths.latestPassFor('demo'),
        ).readAsStringSync().trim();
        final log = File(
          joinPath(File(reportPath).parent.path, ['pass.log']),
        ).readAsStringSync();
        expect(log, contains('[quiet] relaunch --fresh'));
        expect(log, contains('device left quiet (0 alarms armed) in '));
      },
    );

    test(
      'a ring the quiet relaunch did not end is no quiet, whatever the count',
      () async {
        // The alarm a pass rang has left the armed list: counted alone, the
        // guest read "0 alarms armed" with the alarm page up.
        final world = _World(flows: {'01_a': 'tap "A"\n'})
          ..ringing = const [true];
        addTearDown(world.dispose);
        final (_, report) = await world.pass();
        expect(report.quietAlarms, 0);
        expect(
          report.quietFailure,
          'an alarm of the app is still ringing after relaunch --fresh',
        );
        expect(world.passLog(), isNot(contains('device left quiet')));
        expect(
          world.passLog(),
          contains(
            'device not left quiet: an alarm of the app is still '
            'ringing',
          ),
        );
      },
    );

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

    test(
      'a quiet relaunch that fails is reported, not counted, and keeps exit 0',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})..quietFails = true;
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(code, 0);
        expect(world.quiets, 1);
        expect(world.context!.alarmCounts, 0);
        expect(report.quietFailure, 'relaunch --fresh: the reset was refused');
        expect(report.quietAlarms, isNull);
      },
    );
  });

  group('a pass on a worn fleet guest', () {
    test(
      'recycles it — stop, then a fleet boot child — before the first reseed',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
        addTearDown(world.dispose);
        final (code, _) = await world.pass();
        expect(code, 0);
        final kill = world.events.indexOf('adb -s emulator-5556 emu kill');
        final boot = world.events.indexOf(
          'child: fleet boot anta_qa_1 --no-quiet',
        );
        expect(kill, isNonNegative);
        expect(boot, greaterThan(kill));
        expect(world.events.indexOf('relaunch'), greaterThan(boot));
        expect(
          world.passLog(),
          contains(
            'recycling anta_qa_1 (emulator-5556): 45 app launches since boot (over 40)',
          ),
        );
        expect(world.passLog(), contains('recycled anta_qa_1 (emulator-5556)'));
      },
    );

    test(
      'the report and its summary say the pass recycled, why and how long',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
        addTearDown(world.dispose);
        final (_, report) = await world.pass();
        expect(report.recycle?.reason, '45 app launches since boot (over 40)');
        expect(report.recycle?.ms, isNonNegative);
        expect(PassReport.decode(report.encode()).recycle, report.recycle);
        expect(
          world.passLog(),
          matches(
            RegExp(
              r'recycled in \d+\.\d s: 45 app launches since boot \(over 40\)',
            ),
          ),
        );
        final other = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
        addTearDown(other.dispose);
        final (_, fresh) = await other.pass(['--no-recycle']);
        expect(fresh.recycle, isNull);
        expect(fresh.toJson().containsKey('recycle'), isFalse);
      },
    );

    test(
      'the boot child keeps the priority class the guest ran with',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})
          ..wearGuest(windows: true);
        addTearDown(world.dispose);
        final (code, _) = await world.pass();
        expect(code, 0);
        expect(
          world.events,
          contains('child: fleet boot anta_qa_1 --priority=below --no-quiet'),
        );
      },
    );

    test(
      'a guest that does not come back ends the pass before any flow',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})
          ..wearGuest()
          ..bootExit = exitDevice;
        addTearDown(world.dispose);
        final code = await world.runner().run([
          '-d',
          'emulator-5556',
          'pass',
          'demo',
        ]);
        expect(code, exitDevice);
        expect(
          world.events,
          contains('child: fleet boot anta_qa_1 --no-quiet'),
        );
        expect(
          world.events,
          isNot(contains('relaunch')),
          reason: 'no flow ran',
        );
        final dir = world.onlyPassDir();
        expect(File(joinPath(dir.path, ['report.json'])).existsSync(), isFalse);
        expect(File(world.paths.latestPassFor('demo')).existsSync(), isFalse);
        expect(
          File(joinPath(dir.path, ['pass.log'])).readAsStringSync(),
          contains(
            'the guest did not come back after its recycle — '
            '`qa fleet stop anta_qa_1 --force`, then `qa fleet boot anta_qa_1`',
          ),
        );
      },
    );

    test('--no-recycle skips the wear check altogether', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
      addTearDown(world.dispose);
      final (code, _) = await world.pass(['--no-recycle']);
      expect(code, 0);
      expect(world.events.where((e) => e != 'relaunch'), isEmpty);
      expect(world.passLog(), isNot(contains('recycl')));
    });

    test(
      '--no-reseed keeps the guest it has: its flows run on what the app holds',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
        addTearDown(world.dispose);
        final (code, _) = await world.pass(['--no-reseed']);
        expect(code, 0);
        expect(
          world.events,
          isEmpty,
          reason: 'no fleet read, no reseed, no quiet relaunch',
        );
        expect(world.passLog(), isNot(contains('recycl')));
      },
    );

    test('a shard never recycles: its fleet pass already did', () async {
      final world = _World(
        flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n', '03_c': 'tap "C"\n'},
      )..wearGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--shard', '1/3']);
      expect(code, 0);
      expect(report.flows.map((f) => f.name), ['01_a']);
      expect(
        world.events.where((e) => e != 'relaunch'),
        isEmpty,
        reason: 'not even the fleet is read',
      );
      expect(world.passLog(), isNot(contains('recycl')));
    });

    test(
      'the owner\'s emulator, a phone and macOS are never recycled, silently',
      () async {
        for (final device in ['emulator-5554', 'R5CT30ABCDE', 'macos']) {
          final world = _World(flows: {'01_a': 'tap "A"\n'})
            ..wearGuest(others: [device])
            ..deviceId = device;
          addTearDown(world.dispose);
          final (code, report) = await world.pass();
          expect(code, 0, reason: device);
          expect(report.device?.id, device);
          expect(
            world.events.where((e) => e != 'relaunch'),
            isEmpty,
            reason: device,
          );
          expect(world.passLog(), isNot(contains('recycl')), reason: device);
        }
      },
    );
  });

  group('a pass on a fleet guest that is not up', () {
    test('boots it through the fleet boot child, then runs', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..downGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      final boot = world.events.indexOf(
        'child: fleet boot anta_qa_1 --no-quiet',
      );
      expect(boot, isNonNegative);
      expect(world.events.indexOf('relaunch'), greaterThan(boot));
      expect(report.bootMs, isNonNegative);
      expect(report.toJson()['booted'], {'ms': report.bootMs});
      expect(PassReport.decode(report.encode()).bootMs, report.bootMs);
      expect(world.passLog(), contains('booted the guest in '));
      expect(report.recycle, isNull, reason: 'a fresh guest is not worn');
    });

    test('a guest that is up is not booted again', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..downGuest();
      world.guest!.down = false;
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      expect(world.events.where((e) => e.startsWith('child: ')), isEmpty);
      expect(report.bootMs, isNull);
      expect(report.toJson().containsKey('booted'), isFalse);
    });

    test(
      'a boot that fails ends the pass with exit 3 and the recipe',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})
          ..downGuest()
          ..bootExit = exitDevice;
        addTearDown(world.dispose);
        final lines = <String>[];
        final qa = world.runner()
          ..lineSink = (line, {required prefix, required isError}) =>
              lines.add(line);
        final code = await qa.run(['-d', 'emulator-5556', 'pass', 'demo']);
        expect(code, exitDevice);
        expect(world.events, isNot(contains('relaunch')));
        expect(
          lines,
          contains(
            'the guest did not boot (exit 3) — `qa fleet stop anta_qa_1 '
            '--force`, then `qa fleet boot anta_qa_1`, then run again',
          ),
        );
        expect(Directory(world.paths.passRoot).existsSync(), isFalse);
      },
    );

    test(
      'off Windows, as everywhere off the fleet, nothing is booted',
      () async {
        final world = _World(flows: {'01_a': 'tap "A"\n'})..wearGuest();
        world.guest!.down = true;
        addTearDown(world.dispose);
        await world.pass(['--no-recycle']);
        expect(world.events.where((e) => e.startsWith('child: ')), isEmpty);
        expect(world.events.where((e) => e.startsWith('adb ')), isEmpty);
      },
    );
  });

  group('ceilings (H7)', () {
    test(
      'a flow past its ceiling fails as a device failure; the abandoned '
      'attempt runs no further step and writes nothing into the report',
      () async {
        final world = _World(
          flows: {'01_hang': 'tap "A"\nhang\ntap "after"\n', '02_b': 'peek\n'},
        )..deviceId = 'emulator-5554';
        addTearDown(world.dispose);
        final (code, report) = await world.pass(['--flow-ceiling', '0.2']);
        expect(
          code,
          exitTarget,
          reason: 'a red, not a pass that could not finish',
        );
        final hung = report.flows.first;
        expect(hung.status, FlowStatus.failed);
        expect(hung.failure!.exitCode, exitDevice);
        expect(hung.failure!.step, 2);
        expect(hung.failure!.line, 'hang');
        expect(
          hung.failure!.message,
          ceilingMessage(const Duration(milliseconds: 200), 'step 2'),
        );
        expect(hung.failure!.message, startsWith('device failure: '));
        expect(hung.steps.map((s) => (s.line, s.ok)), [
          ('tap "A"', true),
          ('hang', false),
        ]);
        expect(world.taps, contains('A'));
        expect(world.taps, isNot(contains('after')));
        expect(
          world.passLog(),
          isNot(contains('woke up')),
          reason: 'the step in flight was stopped, not left running',
        );
        expect(
          world.events.where((e) => e.startsWith('hang') || e == 'errors'),
          ['hang: cancelled', 'errors'],
          reason:
              'the cancelled attempt has returned before the evidence drives '
              'the runner',
        );
        expect(
          world.events.indexOf('hang: cancelled'),
          lessThan(world.events.lastIndexOf('relaunch')),
          reason: 'and before the next flow\'s reseed',
        );
        expect(
          world.passLog(),
          allOf(
            contains('\n=== 01_hang: FAILED (exit 3) in '),
            contains('\npass: 1/2 green in '),
          ),
          reason: 'the step in flight does not keep its indent on the pass',
        );
        expect(world.peeks.single['flows'], hasLength(1));
        expect(report.flows.last.status, FlowStatus.passed);
        expect(report.infra, isEmpty, reason: 'not a fleet guest');
        expect(world.events.where((e) => e.startsWith('adb ')), isEmpty);
      },
    );

    test('an abandoned attempt that has not returned within the grace stops '
        'the pass: nothing else drives the runner beside it', () async {
      final world = _World(flows: {'01_stuck': 'stuck\n', '02_b': 'tap "B"\n'})
        ..deviceId = 'emulator-5554'
        ..stuckFor = const Duration(milliseconds: 900)
        ..abandonGrace = const Duration(milliseconds: 200);
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--flow-ceiling', '0.2']);
      expect(code, exitDevice);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.failed,
        FlowStatus.skipped,
      ]);
      expect(report.infraStop, contains('did not stop within 0.2 s'));
      expect(
        world.events,
        isNot(contains('errors')),
        reason: 'no evidence capture beside the attempt still out',
      );
      expect(world.taps, ['id:prelude'], reason: 'no later flow ran');
      expect(world.reseeds, 1);
    });

    test('a ceiling in the reseed is step 0 on the reseed line', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})
        ..deviceId = 'emulator-5554'
        ..reseedDelay = const Duration(milliseconds: 500);
      addTearDown(world.dispose);
      final (_, report) = await world.pass([
        '--flow-ceiling',
        '0.1',
        '--keep-state',
      ]);
      final failure = report.flows.single.failure!;
      expect(failure.step, 0);
      expect(failure.line, startsWith('relaunch --fresh --seed f.json'));
      expect(failure.message, contains('in its reseed'));
      expect(
        world.taps,
        isEmpty,
        reason: 'neither the prelude nor the flow ran',
      );
    });

    test(
      'flow_ceiling= in the suite sets it; --flow-ceiling overrides it',
      () async {
        final world = _World(
          manifest: 'flow_ceiling=0.2\n',
          flows: {'01_hang': 'hang\n'},
        )..deviceId = 'emulator-5554';
        addTearDown(world.dispose);
        var (code, report) = await world.pass();
        expect(
          report.flows.single.failure?.message,
          contains('ceiling of 0.2 s'),
        );
        (code, report) = await world.pass(['--flow-ceiling', '30']);
        expect(code, 0);
        expect(report.flows.single.status, FlowStatus.passed);
      },
    );

    test('a bad ceiling is refused before anything runs', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'});
      addTearDown(world.dispose);
      for (final args in [
        ['--flow-ceiling', '0'],
        ['--max-minutes', '-1'],
        ['--max-minutes', 'soon'],
      ]) {
        await expectLater(
          world.runner().run(['-d', 'emulator-5556', 'pass', 'demo', ...args]),
          throwsA(isA<UsageFailure>()),
          reason: args.join(' '),
        );
      }
      expect(world.reseeds, 0);
    });

    test('past --max-minutes the flow in flight finishes and the rest are '
        'skipped, exit 3; 0 turns the ceiling off', () async {
      final world = _World(
        flows: {'01_slow': 'pause\n', '02_b': 'tap "B"\n', '03_c': 'tap "C"\n'},
      );
      addTearDown(world.dispose);
      var (code, report) = await world.pass(['--max-minutes', '0.001']);
      expect(code, exitDevice);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.passed,
        FlowStatus.skipped,
        FlowStatus.skipped,
      ]);
      expect(
        report.infraStop,
        'the pass ran past its ceiling of 0.001 min (--max-minutes)',
      );
      expect(passExitCode(report), exitDevice);
      expect(world.quiets, 1, reason: 'the quiet end still runs');
      expect(world.passLog(), contains('stopped early: the pass ran past'));

      (code, report) = await world.pass(['--max-minutes', '0']);
      expect(code, 0);
      expect(report.infraStop, isNull);
    });
  });

  group('a pass that loses its fleet guest (H8)', () {
    test('a guest that dies under a flow is stopped, booted and the flow runs '
        'again: green, recovered, and the hold survives', () async {
      final world = _World(
        flows: {
          '01_a': 'tap "A"\n',
          '02_dies': 'die\nheld\n',
          '03_c': 'tap "C"\n',
        },
      )..upGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0, reason: 'a recovered flow counts as green');
      expect(report.flows.map((f) => (f.name, f.status, f.recovered)), [
        ('01_a', FlowStatus.passed, false),
        ('02_dies', FlowStatus.passed, true),
        ('03_c', FlowStatus.passed, false),
      ]);
      expect(world.children, ['child: fleet boot anta_qa_1 --no-quiet']);
      expect(world.reseeds, 4, reason: 'the rerun gets a fresh seed');
      final entry = report.infra.single;
      expect(
        (entry.flow, entry.cause, entry.guest, entry.action, entry.outcome),
        ('02_dies', 'device', 'not on adb', 'rerun', 'green'),
      );
      expect(entry.message, contains('not found'));
      expect(entry.ms, isNonNegative);
      expect(
        (entry.shot, entry.dump),
        (null, null),
        reason: 'a guest off adb has no screen to take',
      );
      expect(entry.errors, endsWith('fail_02_dies_attempt1_errors.txt'));
      expect(File(entry.errors!).existsSync(), isTrue);
      expect(
        world.holds.single?.pid,
        pid,
        reason: 'an outside fleet stop took the file; the pass took it again',
      );
      expect(
        GuestState.read(world.paths.guestStateFor('anta_qa_1'))?.hold,
        isNull,
      );
      final log = world.passLog();
      expect(
        log,
        contains('=== 02_dies: device failure (device, guest not on adb) in '),
      );
      expect(log, contains('no screen: anta_qa_1 is not on adb'));
      expect(log, contains('recover: 02_dies failed for the fleet'));
      expect(
        log,
        contains('=== flow 2/3: 02_dies (again, on the recovered guest)'),
      );
      expect(log, contains('pass: 3/3 green, 1 recovered in '));
      expect(log, contains('$recoveredMark  02_dies'));
    });

    test('an exit 3 on a guest that probes healthy stands as a red', () async {
      final world = _World(flows: {'01_a': 'fail3\n', '02_b': 'tap "B"\n'})
        ..upGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, exitTarget);
      expect(report.flows.first.status, FlowStatus.failed);
      expect(report.flows.first.failure!.shot, endsWith('fail_01_a.png'));
      expect(report.infra, isEmpty);
      expect(world.children, isEmpty);
      expect(world.events, contains('adb devices -l'), reason: 'it was probed');
      expect(world.events, isNot(contains('adb -s emulator-5556 emu kill')));
      expect(world.passLog(), contains('=== 01_a: FAILED (exit 3) in '));
    });

    test('a target failure (exit 2) is the app\'s: no probe at all', () async {
      final world = _World(flows: {'01_a': 'expect "missing"\n'})..upGuest();
      addTearDown(world.dispose);
      final (code, _) = await world.pass(['--no-recycle']);
      expect(code, exitTarget);
      expect(
        world.events.where((e) => e.startsWith('adb ')),
        ['adb devices -l'],
        reason: 'only the up-check before the pass; no probe after the red',
      );
    });

    test('a reseed that does not go in on a dead guest is recovered', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n', '02_b': 'tap "B"\n'})
        ..upGuest()
        ..failingReseeds = {2}
        ..reseedKillsGuest = true;
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      expect(report.infra.single.cause, 'reseed');
      expect(report.flows.last.recovered, isTrue);
    });

    test('a rerun that fails after the pass\'s last recovery is that flow\'s '
        'red, and the pass goes on (H8)', () async {
      final world = _World(
        flows: {'01_hang': 'hang\n', '02_hang': 'hang\n', '03_c': 'tap "C"\n'},
      )..upGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--flow-ceiling', '0.2']);
      expect(code, exitTarget);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.failed,
        FlowStatus.failed,
        FlowStatus.passed,
      ]);
      expect(report.infraStop, isNull);
      expect(world.children, hasLength(2));
      expect(world.taps, contains('C'));
    });

    test(
      'a ceiling recovers a healthy guest too; the second breach is red, '
      'and the pass stops when a further flow needs a third recovery',
      () async {
        final world = _World(
          flows: {
            '01_hang': 'hang\n',
            '02_hang': 'hang\n',
            '03_hang': 'hang\n',
            '04_d': 'tap "D"\n',
          },
        )..upGuest();
        addTearDown(world.dispose);
        final (code, report) = await world.pass(['--flow-ceiling', '0.2']);
        expect(code, exitDevice);
        expect(report.flows.map((f) => f.status), [
          FlowStatus.failed,
          FlowStatus.failed,
          FlowStatus.failed,
          FlowStatus.skipped,
        ]);
        expect(report.flows.map((f) => f.recovered), everyElement(isFalse));
        expect(world.children, hasLength(2));
        expect(
          world.events.where((e) => e == 'adb -s emulator-5556 emu kill'),
          hasLength(2),
          reason: 'a guest on adb is stopped gracefully',
        );
        expect(report.infra.map((e) => (e.flow, e.cause, e.guest, e.outcome)), [
          ('01_hang', 'ceiling', 'healthy', 'red'),
          ('02_hang', 'ceiling', 'healthy', 'red'),
        ]);
        expect(report.infraStop, contains('the recovery budget is spent'));
        expect(report.encode(), isNot(contains('woke up')));
        expect(world.passLog(), contains('stopped early: the recovery budget'));
      },
    );

    test('a ceiling\'s rerun goes green, and the abandoned step is stopped '
        'before the guest is stopped under it', () async {
      // Uncancelled, the first attempt would wake at 1.3 s, inside the
      // rerun's 0.6 s of pauses.
      final world =
          _World(flows: {'01_hang': 'hang\npause\npause\npause\npause\n'})
            ..upGuest()
            ..hangTimes = 1
            ..hangFor = const Duration(milliseconds: 1300);
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--flow-ceiling', '1']);
      expect(code, 0);
      expect(report.flows.single.recovered, isTrue);
      expect(
        (report.infra.single.cause, report.infra.single.guest),
        ('ceiling', 'healthy'),
      );
      expect(
        report.infra.single.shot,
        endsWith('fail_01_hang_attempt1.png'),
        reason: 'a healthy guest still has its screen',
      );
      expect(File(report.infra.single.dump!).existsSync(), isTrue);
      expect(world.passLog(), isNot(contains('woke up')));
      final cancelled = world.events.indexOf('hang: cancelled');
      expect(cancelled, isNonNegative);
      expect(
        cancelled,
        lessThan(world.events.indexOf('adb -s emulator-5556 emu kill')),
      );
      expect(cancelled, lessThan(world.events.indexOf('errors')));
      expect(
        RegExp(
          r'^\s+=== |^\s+pass: ',
          multiLine: true,
        ).hasMatch(world.passLog()),
        isFalse,
        reason: 'no pass line keeps the abandoned step\'s indent',
      );
    });

    test('a reseed=suite suite restarts from its first flow, once', () async {
      final world = _World(
        reseed: 'suite',
        flows: {'01_a': 'tap "A"\n', '02_dies': 'die\n', '03_c': 'tap "C"\n'},
      )..upGuest();
      addTearDown(world.dispose);
      var (code, report) = await world.pass();
      expect(code, 0);
      expect(world.reseeds, 2, reason: 'the seed again, from the first flow');
      expect(world.taps.where((t) => t == 'A'), hasLength(2));
      expect(report.flows.map((f) => (f.name, f.status, f.recovered)), [
        ('01_a', FlowStatus.passed, false),
        ('02_dies', FlowStatus.passed, true),
        ('03_c', FlowStatus.passed, false),
      ]);
      expect(report.infra.single.action, 'restart suite');

      world
        ..deaths = 0
        ..dieTimes = 2;
      (code, report) = await world.pass();
      expect(code, exitDevice);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.passed,
        FlowStatus.failed,
        FlowStatus.skipped,
      ]);
      expect(report.infraStop, contains('already restarted once'));
    });

    test('a reseed=none pass recovers the guest and stops', () async {
      final world = _World(flows: {'01_dies': 'die\n', '02_b': 'tap "B"\n'})
        ..upGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--no-reseed']);
      expect(code, exitDevice);
      expect(world.children, ['child: fleet boot anta_qa_1 --no-quiet']);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.failed,
        FlowStatus.skipped,
      ]);
      expect(
        (report.infra.single.action, report.infra.single.outcome),
        ('stop', 'stopped'),
      );
      expect(report.infraStop, startsWith('reseed=none'));
    });

    test(
      'a guest that does not boot again stops the pass with the recipe',
      () async {
        final world = _World(flows: {'01_dies': 'die\n', '02_b': 'tap "B"\n'})
          ..upGuest()
          ..bootExit = exitDevice;
        addTearDown(world.dispose);
        final (code, report) = await world.pass();
        expect(code, exitDevice);
        expect(report.flows.map((f) => f.status), [
          FlowStatus.failed,
          FlowStatus.skipped,
        ]);
        expect(report.infra.single.outcome, 'boot failed');
        expect(report.infraStop, contains('did not come back'));
        expect(
          world.passLog(),
          contains(
            '`qa fleet stop anta_qa_1 --force`, then `qa fleet boot anta_qa_1`',
          ),
        );
      },
    );

    test('the owner\'s emulator, a phone, a non-Windows host: a device failure '
        'stays a red, nothing is probed or booted', () async {
      for (final setup in <(String, void Function(_World))>[
        ('emulator-5554', (w) => w.deviceId = 'emulator-5554'),
        ('R5CT30ABCDE', (w) => w.deviceId = 'R5CT30ABCDE'),
        ('off Windows', (w) => w.upGuest(windows: false)),
      ]) {
        final world = _World(flows: {'01_dies': 'die\n', '02_b': 'tap "B"\n'});
        addTearDown(world.dispose);
        setup.$2(world);
        world.events.clear();
        final (code, report) = await world.pass(['--no-recycle']);
        expect(code, exitTarget, reason: setup.$1);
        expect(report.infra, isEmpty, reason: setup.$1);
        expect(report.flows.last.status, FlowStatus.passed, reason: setup.$1);
        expect(
          world.events.where((e) => e != 'relaunch' && e != 'errors'),
          isEmpty,
          reason: setup.$1,
        );
      }
    });

    test('a pass that never fails prints and reports as it did', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})..upGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      final json = jsonDecode(report.encode()) as Map<String, dynamic>;
      expect(json.containsKey('infra'), isFalse);
      expect(json.containsKey('infraStop'), isFalse);
      final log = world.passLog();
      expect(log, contains('=== 01_a: ok in '));
      expect(log, isNot(contains('recover')));
      expect(
        RegExp(
          r'pass: 1/1 green in \d+\.\d s on emulator-5556 — report ',
        ).hasMatch(log),
        isTrue,
      );
    });
  });

  group('a guest someone stopped on purpose', () {
    test('ends the pass with who stopped it: no recovery, no boot, exit 3, '
        'the rest skipped, the report written', () async {
      final world = _World(
        flows: {
          '01_a': 'tap "A"\n',
          '02_stop': 'stopped\n',
          '03_c': 'tap "C"\n',
        },
      )..upGuest();
      addTearDown(world.dispose);
      final (code, report) = await world.pass(['--no-recycle']);
      expect(code, exitDevice);
      expect(report.partial, isFalse);
      expect(report.flows.map((f) => f.status), [
        FlowStatus.passed,
        FlowStatus.failed,
        FlowStatus.skipped,
      ]);
      expect(report.infra, isEmpty, reason: 'nothing was recovered');
      expect(world.children, isEmpty, reason: 'the guest is not booted again');
      expect(
        world.events,
        isNot(contains('adb -s emulator-5556 emu kill')),
        reason: 'nor stopped by the pass',
      );
      final request = StopRequest.read(
        world.paths.stopRequestFor('anta_qa_1'),
      )!;
      expect(
        request.label,
        'fleet stop --force (pid 4711) at ${_hhmm(request.at)} from '
        r'D:\other\anta',
      );
      expect(
        report.infraStop,
        'anta_qa_1 was stopped by ${request.label} — nothing was recovered',
      );
      expect(report.quietSkipped, contains('stopped on request'));
      expect(world.quiets, 0);
      final log = world.passLog();
      expect(
        log,
        contains(
          '=== 02_stop: device failure (device, guest stopped on request)',
        ),
      );
      expect(log, contains('stopped early: anta_qa_1 was stopped by'));
      expect(log, contains('no screen: anta_qa_1 was stopped on request'));
    });

    test('a request older than the pass is an earlier pass\'s: the guest is '
        'recovered as a crash', () async {
      final world = _World(flows: {'01_dies': 'die\n'})..upGuest();
      addTearDown(world.dispose);
      StopRequest.record(
        world.paths.stopRequestFor('anta_qa_1'),
        StopRequest(
          by: 'reap --force',
          pid: 1,
          at: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      final (code, report) = await world.pass(['--no-recycle']);
      expect(code, 0);
      expect(report.flows.single.recovered, isTrue);
      expect(report.infraStop, isNull);
    });
  });

  group('Ctrl+C on a pass', () {
    test('stops the flow loop: the step in flight is cancelled, no flow, '
        'reseed or prelude starts after it, exit 130', () async {
      final world = _World(
        flows: {
          '01_a': 'tap "A"\n',
          '02_int': 'sigint\nhang\ntap "after"\n',
          '03_c': 'tap "C"\n',
          '04_d': 'tap "D"\n',
        },
      );
      addTearDown(world.dispose);
      final (code, report) = await world.interruptedPass();
      expect(code, 130);
      expect(report.partial, isTrue);
      expect(report.interrupted, isTrue);
      expect(report.flows.map((f) => f.name), [
        '01_a',
      ], reason: 'only the flows that had finished');
      final after = world.events.sublist(world.events.indexOf('sigint') + 1);
      expect(after, [
        'relaunch',
      ], reason: 'the quiet end\'s relaunch and nothing else: no reseed');
      expect(world.quiets, 1);
      expect(world.reseeds, 2);
      expect(
        world.taps.where((t) => t == 'id:prelude'),
        hasLength(2),
        reason: 'no prelude after the interrupt',
      );
      expect(world.taps, isNot(anyOf(contains('after'), contains('C'))));
    });

    test('during a step, cancels it at its next wait', () async {
      final world = _World(flows: {'01_int': 'hang\n', '02_b': 'tap "B"\n'})
        ..hangFor = const Duration(seconds: 5);
      addTearDown(world.dispose);
      final started = DateTime.now();
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 200),
          () => world.signals.add(ProcessSignal.sigint),
        ),
      );
      final (code, report) = await world.interruptedPass();
      expect(code, 130);
      expect(world.events, contains('hang: cancelled'));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 4)),
        reason: 'the five-second wait did not run out',
      );
      expect(report.flows, isEmpty);
      expect(world.taps, isNot(contains('B')));
    });

    test('after the flows returned, the pass\'s own ending stands: no '
        'second quiet end, no partial report, no 130', () async {
      final world = _World(flows: {'01_a': 'tap "A"\n'})
        ..interruptOnQuiet = true;
      addTearDown(world.dispose);
      final (code, report) = await world.pass();
      expect(code, 0);
      expect(report.partial, isFalse);
      expect(report.interrupted, isFalse);
      expect(world.quiets, 1);
      expect(world.context!.exited.isCompleted, isFalse);
      expect(
        world.passLog(),
        contains('interrupted — the pass is already ending'),
      );
    });
  });

  group('fleet verbs date and hold their guests', () {
    QaCommandRunner fleetRunner(_World world) => QaCommandRunner(
      contextFactory: (ArgResults globals) =>
          world.context = _FakeContext(globals, paths: world.paths)
            ..fleet = world.fleet
            ..onChild = (arguments) {
              world.events.add('child: ${arguments.join(' ')}');
              world.holds.add(
                GuestState.read(world.paths.guestStateFor('anta_qa_1'))?.hold,
              );
              return 0;
            },
      commands: [FleetCommand()],
    )..lineSink = (line, {required prefix, required isError}) {};

    test('fleet install holds every guest it installs on', () async {
      final world = _World(flows: const {})..wearGuest();
      addTearDown(world.dispose);
      ApkRecord(
        apk: 'app-debug.apk',
        gitHash: 'abc1234',
        dirty: false,
        builtAt: DateTime.utc(2026, 11, 11),
        defines: const [],
        driver: true,
        qa: true,
      ).write(world.paths.apkJson);
      final file = world.paths.guestStateFor('anta_qa_1');
      final code = await fleetRunner(
        world,
      ).run(['fleet', 'install', '--no-recycle']);
      expect(code, 0);
      expect(world.events, contains(startsWith('child: ')));
      expect(world.holds.single?.verb, 'fleet install');
      expect(world.holds.single?.pid, pid);
      expect(
        GuestState.read(file)!.hold,
        isNull,
        reason: 'released at the end',
      );
    });

    test('fleet boot dates a guest that is up and marks --keep-up', () async {
      final world = _World(flows: const {})..downGuest();
      world.guest!.down = false;
      final emulator = File(
        joinPath(world.root.path, ['sdk', 'emulator', 'emulator']),
      )..createSync(recursive: true);
      world.fleet = FleetHost(
        runner: world.guest!,
        adb: Adb(executable: 'adb', runner: world.guest!),
        avdHome: world.fleet!.avdHome,
        sdkRoot: emulator.parent.parent.path,
        windows: false,
        pollEvery: Duration.zero,
      );
      addTearDown(world.dispose);
      final file = world.paths.guestStateFor('anta_qa_1');
      final long = DateTime.now().subtract(const Duration(hours: 2));
      GuestState.booted(file, long);

      expect(
        await fleetRunner(world).run(['fleet', 'boot', '1', '--keep-up']),
        0,
      );
      final kept = GuestState.read(file)!;
      expect(kept.keep, isTrue);
      expect(kept.lastUsedAt!.isAfter(long), isTrue);
      expect(
        kept.bootedAt!.isAtSameMomentAs(long),
        isTrue,
        reason: 'it was already up, not booted',
      );

      expect(await fleetRunner(world).run(['fleet', 'boot', '1']), 0);
      expect(
        GuestState.read(file)!.keep,
        isTrue,
        reason: 'a plain boot of a guest that is up only dates it',
      );
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

    test(
      'wait polls past two "no semantics tree yet" answers to the tree',
      () async {
        final agent = _StartingAgent(2);
        expect(await run(agent, ['wait', 'id:ready', '--timeout', '5']), 0);
        expect(agent.dumps, greaterThanOrEqualTo(3));
        expect(File(paths.lastDumpFor('emulator-5556')).existsSync(), isTrue);
      },
    );

    test('expect and scroll-to ride it out the same way', () async {
      final expecting = _StartingAgent(2);
      expect(await run(expecting, ['expect', 'id:ready', '--timeout', '5']), 0);
      expect(expecting.dumps, 3);
      final scrolling = _StartingAgent(
        2,
        failure: 'the app has not drawn its first frame yet (still starting?)',
      );
      expect(await run(scrolling, ['scroll-to', 'id:ready']), 0);
      expect(scrolling.dumps, 3);
    });

    test(
      'past the timeout the failure stands, and any other failure at once',
      () async {
        final never = _StartingAgent(1 << 20);
        await expectLater(
          run(never, ['wait', 'id:ready', '--timeout', '1']),
          throwsA(
            isA<DeviceFailure>().having(
              (e) => e.message,
              'message',
              contains('no semantics tree yet'),
            ),
          ),
        );
        final broken = _StartingAgent(
          1,
          failure: 'the inspector produced no image',
        );
        await expectLater(
          run(broken, ['wait', 'id:ready', '--timeout', '5']),
          throwsA(isA<DeviceFailure>()),
        );
        expect(broken.dumps, 1);
      },
    );
  });

  group('qa steps', () {
    /// [lines] as a step file under [world]'s project, and its path.
    String stepFile(_World world, List<String> lines) {
      final file = File(joinPath(world.paths.projectRoot, ['steps.txt']))
        ..writeAsStringSync('${lines.join('\n')}\n');
      return file.path;
    }

    test(
      'a malformed line fails its own step; --keep-going runs the next',
      () async {
        final world = _World(flows: const {});
        addTearDown(world.dispose);
        final expects = <String>[];
        final qa = QaCommandRunner(
          contextFactory: (globals) =>
              _FakeContext(globals, paths: world.paths),
          commands: [
            StepsCommand(),
            _Verb('expect', (verb, rest) async {
              expects.add(rest.join(' '));
              return 0;
            }),
          ],
        );
        expect(
          await qa.run(['steps', '--keep-going', 'tap "Day', 'expect id:x']),
          exitUsage,
        );
        expect(expects, ['id:x']);
        expect(await qa.run(['steps', 'tap "Day', 'expect id:y']), exitUsage);
        expect(expects, [
          'id:x',
        ], reason: 'without --keep-going it stops at step 1');
      },
    );

    test('a step that names another device runs on a context of its own, '
        'which later steps naming that device share; a step naming none, or '
        'the process\'s own, stays on the first', () async {
      final world = _World(flows: const {});
      addTearDown(world.dispose);
      final made = <String?>[];
      final ran = <(String, QaContext)>[];
      final qa = QaCommandRunner(
        contextFactory: (globals) {
          made.add(globals['device'] as String?);
          return _FakeContext(globals, paths: world.paths);
        },
        commands: [
          StepsCommand(),
          _Verb('tap', (verb, rest) async {
            ran.add((rest.join(' '), verb.context));
            return 0;
          }),
        ],
      );

      expect(
        // From a file, as a flow is: on the command line a step that leads
        // with `-d` would be read as an option of `steps` itself.
        await qa.run([
          '-d',
          'emulator-5556',
          'steps',
          '--file',
          stepFile(world, [
            'tap id:own',
            '-d emulator-5558 tap id:other',
            '-d emulator-5556 tap id:own-named',
            '-d emulator-5558 tap id:other-again',
            'tap id:own-last',
          ]),
        ]),
        0,
      );

      expect(made, ['emulator-5556', 'emulator-5558']);
      final own = ran.first.$2;
      final other = ran[1].$2;
      expect(identical(own, other), isFalse);
      expect(
        [
          for (final (target, context) in ran)
            (target, identical(context, own)),
        ],
        [
          ('id:own', true),
          ('id:other', false),
          ('id:own-named', true),
          ('id:other-again', false),
          ('id:own-last', true),
        ],
      );
      expect(identical(ran[3].$2, other), isTrue);
    });

    test('{{var:name}} is what an earlier step captured, on any device; a '
        'name nothing captured fails its step before it types the '
        'placeholder', () async {
      final world = _World(flows: const {});
      addTearDown(world.dispose);
      final typed = <String>[];
      late final QaCommandRunner qa;
      qa = QaCommandRunner(
        contextFactory: (globals) => _FakeContext(globals, paths: world.paths),
        commands: [
          StepsCommand(),
          // Stands for `text <target> --capture invite` reading a code.
          _Verb('read', (verb, rest) async {
            qa.captures[rest.single] = 'K7M2-P4XQ';
            return 0;
          }),
          _Verb('type', (verb, rest) async {
            typed.add(rest.join(' '));
            return 0;
          }),
        ],
      );

      expect(
        await qa.run([
          'steps',
          '--file',
          stepFile(world, [
            'read invite',
            '-d emulator-5558 type "{{var:invite}}"',
            'type "code {{ var:invite }}!"',
          ]),
        ]),
        0,
      );
      expect(typed, ['K7M2-P4XQ', 'code K7M2-P4XQ!']);

      expect(await qa.run(['steps', 'type "{{var:missing}}"']), exitUsage);
      expect(typed, hasLength(2));
    });
  });

  group('captures and the share seam', () {
    test('resolveCaptures replaces every captured name and leaves the other '
        'placeholders to their own resolver', () {
      expect(
        resolveCaptures('type "{{var:a}}-{{var:b}} {{day+1}}"', const {
          'a': 'X',
          'b': 'Y',
        }),
        'type "X-Y {{day+1}}"',
      );
      expect(resolveCaptures('tap id:x', const {}), 'tap id:x');
      expect(
        () => resolveCaptures('type {{var:nope}}', const {}),
        throwsA(isA<UsageFailure>()),
      );
    });

    test('set account= names the next sign-in\'s emulator identity, and '
        'build puts the build\'s own back', () {
      expect(SetCommand.parseAssignments(['account=qa2:qa2@example.com']), {
        AgentKeys.account: 'qa2:qa2@example.com',
      });
      expect(SetCommand.parseAssignments(['account=build']), {
        AgentKeys.account: null,
      });
      for (final bad in [
        'account=qa2',
        'account=:x@example.com',
        'account=a:',
      ]) {
        expect(
          () => SetCommand.parseAssignments([bad]),
          throwsA(isA<UsageFailure>()),
          reason: bad,
        );
      }
    });

    test(
      'share takes a kind and a name of any length, shared unless --off',
      () {
        expect(
          ShareCommand.parseRequest([
            'event',
            'Lifting',
            'session',
          ], off: false),
          {
            AgentKeys.kind: 'event',
            AgentKeys.name: 'Lifting session',
            AgentKeys.on: true,
          },
        );
        expect(ShareCommand.parseRequest(['Folder', 'Training'], off: true), {
          AgentKeys.kind: 'folder',
          AgentKeys.name: 'Training',
          AgentKeys.on: false,
        });
        expect(ShareCommand.parseRequest(['category', 'Gym'], off: false), {
          AgentKeys.kind: 'category',
          AgentKeys.name: 'Gym',
          AgentKeys.on: true,
        });
        for (final bad in [
          <String>[],
          ['event'],
          ['note', 'Session 1'],
          ['folder', ' '],
        ]) {
          expect(
            () => ShareCommand.parseRequest(bad, off: false),
            throwsA(isA<UsageFailure>()),
            reason: '$bad',
          );
        }
      },
    );
  });
}
