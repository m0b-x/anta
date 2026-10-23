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
        WaitCommand;
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/device_select.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/pass_report.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/ui_tree.dart';

/// The one device a scripted pass runs on; everything else a verb could ask
/// of it is a test bug, so it fails loudly.
class _FakeDevice implements Device {
  @override
  DeviceKind get kind => DeviceKind.android;

  @override
  String get id => 'emulator-5556';

  @override
  String get label => 'Android emulator-5556';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A context with no device behind it: a fixed screen, a fixed tree, and a
/// record of what `pass` asked for around each flow.
class _FakeContext extends QaContext {
  _FakeContext(super.globalResults, {required super.paths});

  int errorClears = 0;
  final List<String?> errorStamps = [];

  /// What each `dumpsys alarm` count answers, in order; the last repeats.
  List<int> armed = const [0];
  int alarmCounts = 0;

  static final List<int> _png = img.encodePng(img.Image(width: 8, height: 8));

  @override
  Future<Device> device() async => _FakeDevice();

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

  QaCommandRunner runner() => QaCommandRunner(
        contextFactory: (ArgResults globals) =>
            context = _FakeContext(globals, paths: paths)..armed = armed,
        commands: [
          PassCommand(),
          ShotCommand(),
          StepsCommand(),
          _Verb('relaunch', (verb, _) async {
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
            verb.out('agent: boom in this flow');
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
