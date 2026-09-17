import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'src/adb.dart';
import 'src/agent_client.dart';
import 'src/app_ids.dart';
import 'src/device.dart';
import 'src/device_select.dart';
import 'src/doctor.dart';
import 'src/dump_cache.dart';
import 'src/errors.dart';
import 'src/gestures.dart';
import 'src/ios_device.dart';
import 'src/log_parse.dart';
import 'src/macos_device.dart';
import 'src/paths.dart';
import 'src/poll.dart';
import 'src/process_runner.dart';
import 'src/runner.dart';
import 'src/self_build.dart';
import 'src/shell_batch.dart';
import 'src/shell_words.dart';
import 'src/shots.dart';
import 'src/simctl.dart';
import 'src/target.dart';
import 'src/ui_tree.dart';
import 'src/vm_service_client.dart';

Future<void> main(List<String> arguments) async {
  final runner = QaCommandRunner();
  var code = 0;
  try {
    await _refreshSelf(arguments);
    code = await runner.run(arguments) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(e.usage);
    code = exitUsage;
  } on QaException catch (e) {
    stderr.writeln('qa: ${e.message}');
    code = e.code;
  } finally {
    await runner.dispose().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

/// Rebuilds the compiled tool when its sources have moved on.
///
/// Skipped under `dart run`, which is always current, and for `build-exe`,
/// which would otherwise compile twice.
Future<void> _refreshSelf(List<String> arguments) async {
  if (arguments.contains('build-exe')) return;
  try {
    await refreshQaExe(
      paths: QaPaths.locate(),
      runner: const RealProcessRunner(),
    );
  } on QaException catch (e) {
    stderr.writeln('qa: self-rebuild failed, running the old exe: ${e.message}');
  }
}

class QaCommandRunner extends CommandRunner<int> {
  QaCommandRunner()
      : super(
          'qa',
          'Drive the ANTA app on an Android emulator, an iOS simulator or the '
              'macOS desktop build from the command line.\n'
              'Fast path: ./tool/qa/qa <verb> (tool\\qa\\qa.cmd on Windows; '
              'compiles itself on first use)\n'
              'Portable: dart run tool/qa/qa.dart <verb>',
        ) {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Android serial, simulator UDID or name, `ios`, `android` or '
            '`macos`. Falls back to ANTA_QA_DEVICE, then the sole attached '
            'device (a booted simulator or an adb device).',
      )
      ..addOption(
        'via',
        allowed: ['auto', 'agent', 'native'],
        help: 'See-and-act layer: the in-app agent over the VM service, or '
            'the native one (adb + uiautomator, Android only). `auto` is '
            'native on Android and the agent elsewhere; ANTA_QA_VIA overrides.',
      )
      ..addFlag('verbose', help: 'Echo every process invocation to stderr.');

    addCommand(DevicesCommand());
    addCommand(StateCommand());
    addCommand(DoctorCommand());
    addCommand(BootCommand());
    addCommand(WakeCommand());
    addCommand(UnphoneCommand());
    addCommand(RunAppCommand());
    addCommand(RelaunchCommand());
    addCommand(AttachCommand());
    addCommand(StopCommand());
    addCommand(KillRunCommand());
    addCommand(DtdCommand());
    addCommand(LaunchCommand());
    addCommand(ShotCommand());
    addCommand(DumpCommand());
    addCommand(TapCommand());
    addCommand(LongPressCommand());
    addCommand(TextCommand());
    addCommand(WaitCommand());
    addCommand(ScrollToCommand());
    addCommand(TypeCommand());
    addCommand(KeyCommand());
    addCommand(SwipeCommand());
    addCommand(DragCommand());
    addCommand(ClearCommand());
    addCommand(LookCommand());
    addCommand(ExpectCommand());
    addCommand(StepsCommand());
    addCommand(ReloadCommand());
    addCommand(RestartCommand());
    addCommand(PerfCommand());
    addCommand(LogCommand());
    addCommand(ErrorsCommand());
    addCommand(AgentCommand());
    addCommand(BuildExeCommand());
  }

  QaContext? _context;

  /// Prefix put in front of every output line, so `steps` can indent the
  /// verbs it dispatches without each verb knowing about it.
  String outputPrefix = '';

  /// The single context every verb in this process shares.
  ///
  /// One device resolution, one `Device`, one agent connection, one
  /// screen-size cache, one dump cache — which is the whole point of running
  /// several verbs per process.
  QaContext contextFor(ArgResults globals) => _context ??= QaContext(globals);

  Future<void> dispose() async => _context?.dispose();
}

/// A resolved target plus the tree it came from and where that tree came from.
class TargetLookup {
  const TargetLookup({
    required this.resolved,
    this.tree,
    this.provenance,
  });

  final ResolvedTarget resolved;

  /// Null for a raw coordinate, which needs no tree at all.
  final UiTree? tree;

  /// `(#12 from the dump 4 s ago)` when the tree came out of the cache.
  final String? provenance;

  String get description => provenance == null
      ? resolved.description
      : '${resolved.description}  $provenance';
}

/// Outcome of polling the screen for a target.
class WaitOutcome {
  const WaitOutcome({required this.satisfied, this.found, this.lastTree});

  final bool satisfied;
  final ResolvedTarget? found;
  final UiTree? lastTree;
}

class QaContext {
  QaContext(this.globalResults);

  final ArgResults globalResults;

  late final QaPaths paths = QaPaths.locate();
  late final bool verbose = globalResults['verbose'] as bool? ?? false;
  late final ProcessRunner runner = RealProcessRunner(verbose: verbose);
  late final SdkTools sdk = SdkTools();
  late final Simctl? simctl =
      xcrunAvailable() ? Simctl(runner: runner) : null;
  late final ViaMode via = parseViaMode(
    globalResults['via'] as String? ?? Platform.environment['ANTA_QA_VIA'],
  );

  List<AdbDevice>? _adbDevices;
  String? adbFailure;
  List<SimDevice>? _simulators;
  String? simctlFailure;
  DeviceRef? _ref;
  Device? _device;
  Adb? _adb;
  AgentClient? _agent;
  UiDriver? _driver;

  /// Every adb row, or an empty list when adb is missing or not answering
  /// (which [adbFailure] then explains).
  Future<List<AdbDevice>> adbDevices() async {
    final cached = _adbDevices;
    if (cached != null) return cached;
    final adbPath = sdk.findAdb();
    if (adbPath == null) {
      adbFailure = 'adb not found (set ANDROID_HOME / ANDROID_SDK_ROOT or put it on PATH)';
      return _adbDevices = const [];
    }
    try {
      return _adbDevices = await Adb(executable: adbPath, runner: runner)
          .devices(timeout: const Duration(seconds: 20));
    } on QaException catch (e) {
      adbFailure = e.message;
      return _adbDevices = const [];
    }
  }

  Future<List<SimDevice>> simulators() async {
    final cached = _simulators;
    if (cached != null) return cached;
    final tool = simctl;
    if (tool == null) return _simulators = const [];
    try {
      return _simulators = await tool.devices();
    } on QaException catch (e) {
      simctlFailure = e.message;
      return _simulators = const [];
    }
  }

  String? get explicitDevice {
    final flag = globalResults['device'] as String?;
    if (flag != null && flag.isNotEmpty) return flag;
    final env = Platform.environment['ANTA_QA_DEVICE'];
    return env == null || env.isEmpty ? null : env;
  }

  /// Which platform probes a device hint needs: an adb serial never needs
  /// `simctl list`, a simulator UDID never needs `adb devices` (which can
  /// take seconds to start a cold daemon), the desktop needs neither.
  static (bool adb, bool sims) probesFor(String? hint) {
    if (hint == null) return (true, true);
    final lower = hint.toLowerCase();
    if (lower == macosDeviceId) return (false, false);
    if (lower == 'ios' || RegExp(r'^[0-9a-f-]{36}$').hasMatch(lower)) {
      return (false, true);
    }
    if (lower == 'android' ||
        lower.startsWith('emulator-') ||
        RegExp(r'^[0-9a-z]{6,}$').hasMatch(lower) ||
        lower.contains(':')) {
      return (true, false);
    }
    return (true, true);
  }

  Future<DeviceRef> ref() async {
    final cached = _ref;
    if (cached != null) return cached;
    final hint = explicitDevice;
    final (wantAdb, wantSims) = probesFor(hint);
    final results = await Future.wait<List<Object>>([
      wantAdb ? adbDevices() : Future.value(const <AdbDevice>[]),
      wantSims ? simulators() : Future.value(const <SimDevice>[]),
    ]);
    try {
      return _ref = selectDevice(
        explicit: hint,
        envValue: null,
        adbDevices: results[0].cast<AdbDevice>(),
        simulators: results[1].cast<SimDevice>(),
        hostIsMac: Platform.isMacOS,
      );
    } on DeviceFailure catch (e) {
      final adbNote = adbFailure;
      final simNote = simctlFailure;
      if (adbNote == null && simNote == null) rethrow;
      throw DeviceFailure(
        '${e.message}'
        '${adbNote == null ? '' : '\n  adb: $adbNote'}'
        '${simNote == null ? '' : '\n  simctl: $simNote'}',
      );
    }
  }

  Future<Adb> adb() async {
    final existing = _adb;
    if (existing != null) return existing;
    final selected = await ref();
    if (selected.kind != DeviceKind.android) {
      throw UnsupportedOnPlatform('adb', selected.label);
    }
    return _adb = Adb(
      executable: sdk.requireAdb(),
      runner: runner,
      serial: selected.id,
    );
  }

  Future<Device> device() async {
    final existing = _device;
    if (existing != null) return existing;
    final selected = await ref();
    switch (selected.kind) {
      case DeviceKind.android:
        return _device = AndroidDevice(await adb());
      case DeviceKind.ios:
        final sim = (await simulators()).firstWhere((s) => s.udid == selected.id);
        return _device = IosDevice(simctl: simctl!, sim: sim);
      case DeviceKind.macos:
        return _device = MacosDevice.locate(paths: paths, runner: runner);
    }
  }

  Future<AndroidDevice> android() async {
    final dev = await device();
    if (dev is AndroidDevice) return dev;
    throw UnsupportedOnPlatform('this verb', dev.label, instead: 'it is Android only');
  }

  /// The URIs the last `run`, `attach` or `relaunch` recorded for **this**
  /// device: one file per device id, so a simulator and the desktop app can
  /// be driven in the same session without either stealing the other's
  /// connection.
  Future<String?> recordedVmUri() async =>
      _readUri(paths.vmTxtFor((await ref()).id));

  Future<String?> recordedDtdUri() async =>
      _readUri(paths.dtdTxtFor((await ref()).id));

  Future<void> recordUris({required String? vm, required String? dtd}) async {
    final id = (await ref()).id;
    paths.ensureBuildQa();
    File(paths.vmTxtFor(id)).writeAsStringSync(vm ?? '');
    File(paths.dtdTxtFor(id)).writeAsStringSync(dtd ?? '');
  }

  static String? _readUri(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync().trim();
    return text.isEmpty ? null : text;
  }

  /// The in-app agent, over the VM service URI the last `run`, `attach` or
  /// `relaunch` recorded.
  Future<AgentClient> agent() async {
    final existing = _agent;
    if (existing != null && !existing.vm.isClosed) return existing;
    final dev = await device();
    final recorded = await recordedVmUri();
    VmServiceClient? vm;
    DeviceFailure? failure;
    if (recorded != null) {
      try {
        vm = await VmServiceClient.connect(recorded, timeout: const Duration(seconds: 4));
      } on DeviceFailure catch (e) {
        failure = e;
      }
    }
    if (vm == null) {
      final discovered = await _discoverAgent(dev, recorded);
      if (discovered != null) {
        vm = discovered;
      } else if (recorded == null) {
        throw DeviceFailure(
          'no VM service URI recorded for ${dev.id} — run `qa run` (full) or '
          '`qa relaunch` (fast) first; every see-and-act verb reaches the app '
          'through it',
        );
      } else {
        throw DeviceFailure(
          '${failure!.message}. The recorded run is gone (app quit? restarted '
          'by hand?) — run `qa relaunch`',
        );
      }
    }
    return _agent = AgentClient(vm, appPackage: dev.packageId);
  }

  /// An app that is running but was not started by this tool (an IDE run, a
  /// tap on the icon) still announces its VM service in the platform log;
  /// finding it there is cheaper than asking for a relaunch.
  Future<VmServiceClient?> _discoverAgent(Device dev, String? recorded) async {
    final String? announced;
    try {
      announced = await dev.discoverVmServiceUri();
    } on QaException {
      return null;
    }
    if (announced == null || announced == recorded) return null;
    try {
      final vm = await VmServiceClient.connect(announced, timeout: const Duration(seconds: 3));
      await vm.call('getVM', const {}, const Duration(seconds: 5));
      await recordUris(vm: announced, dtd: await recordedDtdUri());
      stderr.writeln('qa: recovered the VM service URI from the ${dev.kind.label} '
          'log ($announced) — recorded for ${dev.id}');
      return vm;
    } on DeviceFailure {
      return null;
    }
  }

  /// Keeps the documents directory the app reported, so markers for a
  /// desktop launch land where the app actually reads them.
  Future<void> rememberDocuments(AgentInfo info) async {
    final path = info.documentsPath;
    if (path == null || path.isEmpty) return;
    final dev = await device();
    final file = File(paths.documentsCache(dev.id));
    if (file.existsSync() && file.readAsStringSync().trim() == path) return;
    paths.ensureBuildQa();
    file.writeAsStringSync(path);
  }

  Future<void> requireInstalled(Device dev) async {
    if (await dev.isInstalled()) return;
    throw DeviceFailure(
      '${dev.packageId} is not installed on ${dev.label} — ${dev.installHint}',
    );
  }

  Future<AgentClient> adoptAgent(VmServiceClient vm) async {
    await _agent?.close();
    final dev = await device();
    return _agent = AgentClient(vm, appPackage: dev.packageId);
  }

  Future<AgentClient?> agentOrNull() async {
    try {
      return await agent();
    } on QaException {
      return null;
    }
  }

  Future<AgentInfo?> agentInfoOrNull({bool refresh = false}) async =>
      (await agentInfoOrFailure(refresh: refresh)).info;

  /// One `info` round trip with its outcome and cost, for `doctor`.
  Future<({AgentInfo? info, String? failure, int ms})> agentInfoOrFailure({
    bool refresh = false,
  }) async {
    final started = DateTime.now();
    try {
      final client = await agent();
      final info = await client.info(refresh: refresh);
      await rememberDocuments(info);
      return (info: info, failure: null, ms: DateTime.now().difference(started).inMilliseconds);
    } on QaException catch (e) {
      return (info: null, failure: e.message, ms: DateTime.now().difference(started).inMilliseconds);
    }
  }

  Future<UiDriver> driver() async {
    final existing = _driver;
    if (existing != null) return existing;
    final dev = await device();
    switch (via) {
      case ViaMode.native:
        final native = dev.nativeDriver;
        if (native == null) {
          throw UnsupportedOnPlatform(
            '--via native',
            dev.label,
            instead: 'this platform has no native input path; the agent is '
                'the only layer here',
          );
        }
        return _driver = native;
      case ViaMode.agent:
        return _driver = await agent();
      case ViaMode.auto:
        return _driver = dev.nativeDriver ?? await agent();
    }
  }

  Future<DeviceProbe> probe() async {
    final dev = await device();
    final info = dev.nativeDriver == null ? await agentInfoOrNull(refresh: true) : null;
    return dev.probe(info);
  }

  /// A fresh dump, cached to disk (unless [cache] is off, for the inner
  /// iterations of a poll) so later `#N` targets mean this tree.
  Future<UiTree> dump({bool cache = true}) async {
    final captured = await (await driver()).dump();
    if (cache) writeDumpCache(paths, captured.raw);
    return captured.tree;
  }

  /// A screenshot from the layer that has one: the device's own capture
  /// where the platform offers it, the agent's render of the Flutter view
  /// otherwise (or on request).
  Future<List<int>> screenshotPng({ViaMode via = ViaMode.auto}) async {
    final dev = await device();
    final native = via != ViaMode.agent && dev.hasNativeCapture;
    if (via == ViaMode.native && !dev.hasNativeCapture) {
      return dev.screencapPng();
    }
    return native ? dev.screencapPng() : (await agent()).screenshotPng();
  }

  /// Resolves a target, dumping only when the target form needs a tree.
  Future<TargetLookup> lookup(String target, {int? nth}) async {
    if (isPointTarget(target)) {
      return TargetLookup(
        resolved: const TargetResolver(UiTree([])).resolve(target),
      );
    }
    if (isIndexTarget(target)) {
      final cached = readDumpCache(paths);
      if (cached == null) {
        throw TargetFailure(
          'no previous dump — run `dump` first or target by label',
        );
      }
      final tree = cached.tree;
      return TargetLookup(
        resolved: TargetResolver(tree).resolve(target, nth: nth),
        tree: tree,
        provenance: '($target from the dump '
            '${describeAge(cached.ageFrom(DateTime.now()))})',
      );
    }
    final tree = await dump();
    return TargetLookup(
      resolved: TargetResolver(tree).resolve(target, nth: nth),
      tree: tree,
    );
  }

  /// Polls the screen until [wanted] appears (or disappears) or time runs out.
  Future<WaitOutcome> pollFor(
    String wanted, {
    required bool gone,
    required Duration timeout,
    int? nth,
  }) async {
    final interval = (await driver()).pollInterval;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final tree = await dump(cache: false);
      ResolvedTarget? found;
      try {
        found = TargetResolver(tree).resolve(wanted, nth: nth);
        if (found.node?.hidden ?? false) found = null;
      } on TargetFailure catch (e) {
        if (!gone && e.message.contains('ambiguous')) {
          throw TargetFailure(
            'wait cannot settle on "$wanted": ${e.message}\n'
            'Waiting would never resolve this — pick one match with --nth, '
            'or target by id:',
          );
        }
        found = null;
      }
      final done = (gone && found == null) ||
          (!gone && found != null) ||
          !DateTime.now().isBefore(deadline);
      if (done) {
        final captured = await (await driver()).dump();
        writeDumpCache(paths, captured.raw);
        ResolvedTarget? settled = found;
        if (found != null) {
          try {
            settled = TargetResolver(captured.tree).resolve(wanted, nth: nth);
          } on TargetFailure {
            settled = found;
          }
        }
        return WaitOutcome(
          satisfied: (gone && found == null) || (!gone && found != null),
          found: settled,
          lastTree: captured.tree,
        );
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<void> dispose() async {
    await _agent?.close();
  }
}

abstract class QaCommand extends Command<int> {
  QaContext get context =>
      (runner! as QaCommandRunner).contextFor(globalResults!);

  String get _prefix => (runner! as QaCommandRunner).outputPrefix;

  void out(String line) => _write(stdout, line);

  void warn(String line) => _write(stderr, line);

  void _write(IOSink sink, String line) {
    if (_prefix.isEmpty) {
      sink.writeln(line);
      return;
    }
    for (final part in line.split('\n')) {
      sink.writeln('$_prefix$part');
    }
  }

  /// Says so when the screen belongs to something other than ANTA.
  ///
  /// A crash, a keyguard or a system dialog all present as "the label is not
  /// there", and this turns that into one line instead of two more calls.
  /// Agent trees always belong to the app, so only uiautomator dumps can warn.
  void warnIfForeign(UiTree? tree) {
    if (tree == null || tree.source != UiTreeSource.uiautomator) return;
    final package = tree.foregroundPackage;
    if (package == null || package == antaPackage) return;
    warn('warning: foreground is $package, not $antaPackage '
        '(crashed? keyguard? a system dialog?)');
  }

  int? intOption(String name) {
    final raw = argResults?[name] as String?;
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null) throw UsageFailure('--$name must be an integer');
    return value;
  }

  String requireRest(String what) {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) throw UsageFailure('$name needs $what');
    return rest.join(' ');
  }
}

/// Adds `--wait`, `--wait-gone`, `--shot`, `--dump` and `--settle` to a verb
/// that acts on the app, so acting and verifying cost one call instead of two.
void addPostActionOptions(ArgParser parser) {
  parser
    ..addOption('wait',
        help: 'After acting, poll until this target appears.')
    ..addOption('wait-gone',
        help: 'After acting, poll until this target disappears.')
    ..addOption('wait-timeout',
        defaultsTo: '10', help: 'Seconds --wait/--wait-gone polls for.')
    ..addOption('settle',
        help: 'Milliseconds to pause before --shot/--dump when not waiting '
            '(default 300 on the adb path, 0 on the agent path, which '
            'already waits for the frame).')
    ..addOption('shot', help: 'Take a screenshot afterwards, under this name.')
    ..addFlag('dump',
        negatable: false, help: 'Print the interesting nodes afterwards.');
}

/// The act-then-verify tail shared by every acting verb.
mixin PostActions on QaCommand {
  Future<void> runPostActions() async {
    final waitTarget = argResults!['wait'] as String?;
    final goneTarget = argResults!['wait-gone'] as String?;
    if ((waitTarget?.isNotEmpty ?? false) && (goneTarget?.isNotEmpty ?? false)) {
      throw UsageFailure('pass --wait or --wait-gone, not both');
    }
    final ctx = context;
    String? waitFailure;
    if ((waitTarget?.isNotEmpty ?? false) ||
        (goneTarget?.isNotEmpty ?? false)) {
      final gone = goneTarget?.isNotEmpty ?? false;
      final wanted = (gone ? goneTarget : waitTarget)!;
      final seconds = intOption('wait-timeout') ?? 10;
      final outcome = await ctx.pollFor(
        wanted,
        gone: gone,
        timeout: Duration(seconds: seconds),
      );
      if (outcome.satisfied) {
        out(gone ? 'gone: "$wanted"' : 'found: ${outcome.found!.description}');
      } else {
        warnIfForeign(outcome.lastTree);
        waitFailure = waitTimeoutMessage(
          wanted: wanted,
          gone: gone,
          seconds: seconds,
          tree: outcome.lastTree,
        );
      }
    } else {
      final settle = intOption('settle') ??
          (await ctx.driver()).settleAfterAction.inMilliseconds;
      if (settle > 0) {
        await Future<void>.delayed(Duration(milliseconds: settle));
      }
    }

    final shotName = argResults!['shot'] as String?;
    var tookShot = false;
    if (shotName != null && shotName.isNotEmpty) {
      out(await captureShot(
        ctx.screenshotPng,
        ctx.paths,
        name: shotName,
      ));
      tookShot = true;
    }
    if (argResults!['dump'] as bool) {
      final tree = await ctx.dump();
      warnIfForeign(tree);
      for (final node in tree.nodes.where((n) => n.interesting)) {
        out(node.describe());
      }
    }
    if (waitFailure != null) {
      throw TargetFailure(
        tookShot
            ? '$waitFailure The screenshot above was taken after the timeout, '
                'so it shows what the screen was actually on.'
            : waitFailure,
      );
    }
  }
}

/// What a timed-out wait says, with the screen it gave up on.
String waitTimeoutMessage({
  required String wanted,
  required bool gone,
  required int seconds,
  required UiTree? tree,
}) {
  final head = gone
      ? '"$wanted" was still present after ${seconds}s.'
      : '"$wanted" did not appear within ${seconds}s.';
  if (tree == null) return head;
  return '$head foreground=${tree.foregroundPackage ?? 'unknown'}. '
      '${TargetResolver(tree).onScreenListing()}';
}

class DevicesCommand extends QaCommand {
  DevicesCommand() {
    argParser.addFlag('all',
        negatable: false, help: 'Include simulators that are shut down.');
  }

  @override
  String get name => 'devices';

  @override
  String get description =>
      'List what can be driven: adb devices, booted simulators, the desktop.';

  @override
  Future<int> run() async {
    final ctx = context;
    final adbDevices = await ctx.adbDevices();
    final sims = await ctx.simulators();
    String? macosBuilt;
    if (Platform.isMacOS) {
      final desktop = MacosDevice.locate(paths: ctx.paths, runner: ctx.runner);
      macosBuilt = await desktop.isInstalled()
          ? 'built: ${desktop.bundlePath}'
          : 'not built yet — `qa run -d macos` builds it';
    }
    final lines = describeDevices(
      adbDevices: adbDevices,
      simulators: sims,
      hostIsMac: Platform.isMacOS,
      all: argResults!['all'] as bool,
      macosBuilt: macosBuilt,
    );
    if (ctx.adbFailure != null && adbDevices.isEmpty) {
      warn('android: ${ctx.adbFailure}');
    }
    if (ctx.simctlFailure != null) warn('ios: ${ctx.simctlFailure}');
    for (final line in lines) {
      out(line);
    }
    if (lines.isEmpty) out('no devices attached');
    final attached = adbDevices.isNotEmpty || sims.any((s) => s.booted);
    if (!attached && (ctx.adbFailure != null || ctx.simctlFailure != null)) {
      return exitDevice;
    }
    return 0;
  }
}

class StateCommand extends QaCommand {
  StateCommand() {
    argParser.addFlag('json', negatable: false, help: 'Emit a JSON object.');
  }

  @override
  String get name => 'state';

  @override
  String get description =>
      'Report the device, the screen, the app process, the foreground '
      'activity, wake/lock/IME and the run files — in one round trip.';

  @override
  Future<int> run() async {
    final ctx = context;
    final device = await ctx.device();
    final probe = await ctx.probe();
    final size = probe.screen;
    final dtd = await ctx.recordedDtdUri() ?? '';
    final vm = await ctx.recordedVmUri() ?? '';
    final logExists = File(ctx.paths.runLog).existsSync();
    final driverName = device.nativeDriver == null || ctx.via == ViaMode.agent
        ? 'agent'
        : (ctx.via == ViaMode.native ? 'adb' : 'adb (auto)');

    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ').convert({
        'device': device.id,
        'kind': device.kind.label,
        'label': device.label,
        'pid': probe.appPid,
        'resumedActivity': probe.resumedActivity,
        'foreground': probe.foregroundPackage,
        'lifecycle': probe.lifecycle,
        'awake': probe.awake,
        'locked': probe.locked,
        'ime': probe.imeShown,
        'physical': size == null ? null : '${size.physicalWidth}x${size.physicalHeight}',
        'override': size != null && size.isOverridden ? '${size.width}x${size.height}' : null,
        'density': size?.density,
        'dp': size == null ? null : '${size.widthDp}x${size.heightDp}',
        'driver': driverName,
        'runLog': logExists ? ctx.paths.runLog : null,
        'dtd': dtd.isEmpty ? null : dtd,
        'vm': vm.isEmpty ? null : vm,
      }));
      return 0;
    }
    out('device=${device.id} (${device.kind.label})  '
        'app=${probe.appPid == null ? 'not running' : 'pid ${probe.appPid}'}  '
        '${probe.lifecycle == null ? 'resumed=${probe.resumedActivity ?? 'unknown'}  ' : 'lifecycle=${probe.lifecycle}  '}'
        'foreground=${probe.foregroundPackage ?? 'unknown'}  '
        'awake=${DeviceProbe.flag(probe.awake, 'yes', 'no')}  '
        'locked=${DeviceProbe.flag(probe.locked, 'yes', 'no')}  '
        'ime=${DeviceProbe.flag(probe.imeShown, 'up', 'down')}  '
        'screen=${size ?? '? (agent down)'}  driver=$driverName  run.log=${logExists ? 'yes' : 'no'}  '
        'dtd=${dtd.isEmpty ? 'no' : dtd}  vm=${vm.isEmpty ? 'no' : vm}');
    return 0;
  }
}

class BootCommand extends QaCommand {
  BootCommand() {
    argParser
      ..addOption('avd',
          help: 'Android AVD name; selects the Android path. Defaults to the '
              'only AVD installed when no simulator tooling exists.')
      ..addOption('sim',
          help: 'iOS simulator name or UDID to boot (ANTA_QA_SIM). Required '
              'when none is booted and more than one is installed.')
      ..addFlag('cold', negatable: false, help: 'Android: cold boot (no snapshot).')
      ..addFlag('phone',
          negatable: false,
          help: 'Android: override the resolution to 1080x2400 (360x800 dp).');
  }

  @override
  String get name => 'boot';

  @override
  String get description =>
      'Start a simulator or emulator if none is attached and wait until it '
      'is ready. Never restarts one that is already up.';

  @override
  Future<int> run() async {
    final ctx = context;
    final avd = argResults!['avd'] as String?;
    final sim = argResults!['sim'] as String? ?? Platform.environment['ANTA_QA_SIM'];
    final hint = ctx.explicitDevice;
    final (hintAdb, hintSims) = QaContext.probesFor(hint);
    if (hint != null && hintAdb && !hintSims) return _bootAndroid(ctx, avd);
    if (hint != null && !hintAdb && !hintSims) {
      throw UnsupportedOnPlatform('boot', 'the macOS desktop app',
          instead: '`qa run -d macos` builds and starts it');
    }
    final wantsAndroid = (avd != null && avd.isNotEmpty) ||
        ctx.simctl == null ||
        (sim == null &&
            !(hint != null && hintSims && !hintAdb) &&
            (await ctx.adbDevices()).any((d) => d.usable));
    if (wantsAndroid) return _bootAndroid(ctx, avd);
    if (argResults!['cold'] as bool || argResults!['phone'] as bool) {
      throw UnsupportedOnPlatform('--cold / --phone', 'the iOS simulator',
          instead: 'pick a different simulator with --sim');
    }
    return _bootSimulator(ctx, sim);
  }

  Future<int> _bootSimulator(QaContext ctx, String? wanted) async {
    final simctl = ctx.simctl!;
    final sims = await simctl.devices();
    final booted = sims.where((s) => s.booted).toList();
    SimDevice? target;
    if (wanted != null && wanted.isNotEmpty) {
      final lower = wanted.toLowerCase();
      final matches = sims
          .where((s) => s.udid.toLowerCase() == lower || s.name.toLowerCase() == lower)
          .toList();
      if (matches.isEmpty) {
        throw UsageFailure(
          'no simulator named "$wanted". Installed: '
          '${sims.where((s) => s.isAvailable).map((s) => s.name).join(', ')}',
        );
      }
      target = matches.firstWhere((s) => s.booted, orElse: () => matches.first);
    } else if (booted.isNotEmpty) {
      target = booted.first;
    } else {
      final phones = sims.where((s) => s.isAvailable && s.isIPhone).toList();
      if (phones.length == 1) {
        target = phones.single;
      } else {
        throw UsageFailure(
          'no simulator is booted; pass --sim <name|udid> (or set ANTA_QA_SIM). '
          'Installed: ${(phones.isEmpty ? sims : phones).map((s) => s.name).join(', ')}',
        );
      }
    }
    if (target.booted) {
      out('simulator already up: ${target.name} (${target.udid}) — never '
          'shut down or restarted by this tool');
    } else {
      out('booting ${target.name} (${target.udid})…');
      await simctl.boot(target.udid);
      await simctl.openSimulatorApp(target.udid);
      await simctl.waitBooted(target.udid);
    }
    out('ready: ${target.udid}  ${target.name} (${target.runtime})');
    return 0;
  }

  Future<int> _bootAndroid(QaContext ctx, String? avd) async {
    final bare = Adb(executable: ctx.sdk.requireAdb(), runner: ctx.runner);
    final attached = await bare.devices();
    final usable = attached.where((d) => d.usable).toList();
    if (usable.isNotEmpty) {
      out('emulator already up: ${usable.map((d) => d.serial).join(', ')} '
          '(never killed or restarted by this tool)');
    } else if (attached.isNotEmpty) {
      final booting = await _emulatorStartedHere(ctx);
      if (booting == null) {
        throw DeviceFailure(
          '${attached.map((d) => unusableDeviceMessage(d.serial, d.state)).join('; ')}. '
          'Nothing here can fix that: a wedged guest needs the owner to close '
          'the emulator window and cold-boot it.',
        );
      }
      out('emulator pid $booting (started by this tool) is still booting — waiting');
      await _awaitBoot(ctx, bare, booting);
    } else {
      final pid = await _startEmulator(ctx, avd);
      await _awaitBoot(ctx, bare, pid);
    }
    final adb = await ctx.adb();
    if (argResults!['phone'] as bool) {
      await adb.shellLenient(['wm', 'size', '1080x2400']);
      out('wm size set to 1080x2400 (360x800 dp) — run `unphone` before you finish');
    }
    final device = AndroidDevice(adb);
    out('ready: ${device.id}  ${await device.screenSize()}');
    return 0;
  }

  /// The pid recorded by a previous `boot`, when that emulator is still alive.
  Future<int?> _emulatorStartedHere(QaContext ctx) async {
    final file = File(ctx.paths.emulatorPid);
    if (!file.existsSync()) return null;
    final pid = int.tryParse(file.readAsStringSync().trim());
    if (pid == null || !await isProcessAlive(pid, ctx.runner)) return null;
    return pid;
  }

  /// Starts the emulator through the same wrapper machinery `run` uses, so its
  /// output lands in a file this tool can read back when the boot fails.
  Future<int> _startEmulator(QaContext ctx, String? requested) async {
    final emulator = ctx.sdk.requireEmulator();
    var avd = requested;
    if (avd == null || avd.isEmpty) {
      final listed = await ctx.runner.run(emulator, ['-list-avds'],
          timeout: const Duration(seconds: 30));
      final names = listed.stdout
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.contains(' '))
          .toList();
      if (names.isEmpty) {
        throw DeviceFailure('no AVDs installed (emulator -list-avds is empty)');
      }
      if (names.length > 1) {
        throw UsageFailure(
          'more than one AVD; pass --avd. Available: ${names.join(', ')}',
        );
      }
      avd = names.single;
    }
    ctx.paths.ensureBuildQa();
    File(ctx.paths.emulatorLog).writeAsStringSync('');
    File(ctx.paths.emulatorErr).writeAsStringSync('');
    final wrapper = writeWrapperScript(
      paths: ctx.paths,
      baseName: 'emulator_cmd',
      executable: emulator,
      arguments: [
        '-avd',
        avd,
        if (argResults!['cold'] as bool) '-no-snapshot-load',
      ],
      posixLogPath: ctx.paths.emulatorLog,
    );
    final pid = await startWrapperDetached(
      paths: ctx.paths,
      wrapper: wrapper,
      logPath: ctx.paths.emulatorLog,
      errPath: ctx.paths.emulatorErr,
      pidPath: ctx.paths.emulatorPid,
    );
    out('starting emulator $avd (pid $pid, log ${ctx.paths.emulatorLog})');
    return pid;
  }

  /// Waits for the guest, failing the moment the emulator says it will not
  /// come up or its process disappears.
  Future<void> _awaitBoot(QaContext ctx, Adb bare, int pid) async {
    final started = DateTime.now();
    final deadline = started.add(const Duration(minutes: 6));
    var lastProgress = started;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final log = readEmulatorLog(ctx.paths);
      final fatal = emulatorFatalLine(log);
      if (fatal != null) {
        throw DeviceFailure(
          'the emulator refused to start: $fatal\n${tailLines(log, lines: 15)}',
        );
      }
      if (!await isProcessAlive(pid, ctx.runner)) {
        throw DeviceFailure(
          'the emulator process (pid $pid) exited before the device came up.\n'
          '${tailLines(log, lines: 15)}',
        );
      }
      final devices = await bare.devices();
      final usable = devices.where((d) => d.usable).toList();
      final state = usable.isNotEmpty
          ? 'device up, waiting for boot_completed'
          : (devices.isEmpty
              ? 'device offline, still waiting'
              : 'device ${devices.first.state}, still waiting');
      if (DateTime.now().difference(lastProgress).inSeconds >= 15) {
        lastProgress = DateTime.now();
        warn('boot: ${DateTime.now().difference(started).inSeconds} s — $state');
      }
      if (usable.isEmpty) continue;
      final adb = bare.withSerial(usable.first.serial);
      final props = await adb.shellBatch(const [
        ShellCommand(['getprop', 'sys.boot_completed']),
        ShellCommand(['settings', 'get', 'global', 'device_provisioned']),
      ]);
      if (props[0].trim() != '1') continue;
      if (props[1].trim() == '1') return;
    }
    throw DeviceFailure(
      'emulator did not finish booting within 6 minutes.\n'
      '${tailLines(readEmulatorLog(ctx.paths), lines: 15)}',
    );
  }
}

class WakeCommand extends QaCommand {
  @override
  String get name => 'wake';

  @override
  String get description =>
      'Android: wake the screen and dismiss the keyguard, then report awake/locked.';

  @override
  Future<int> run() async {
    final ctx = context;
    final device = await ctx.android();
    await device.wake();
    final probe = await device.probe();
    out('awake=${DeviceProbe.flag(probe.awake, 'yes', 'no')}  '
        'locked=${DeviceProbe.flag(probe.locked, 'yes', 'no')}  '
        'foreground=${probe.foregroundPackage ?? 'unknown'}');
    return 0;
  }
}

class UnphoneCommand extends QaCommand {
  @override
  String get name => 'unphone';

  @override
  String get description => 'Android: reset any `wm size` override back to physical.';

  @override
  Future<int> run() async {
    final device = await context.android();
    out('wm size reset: ${await device.resetScreenOverride()}');
    return 0;
  }
}

abstract class LaunchingCommand extends QaCommand {
  LaunchingCommand() {
    argParser
      ..addFlag('qa',
          defaultsTo: true,
          help: 'Pass the ANTA_QA dart-defines (isolated qa database).')
      ..addFlag('driver',
          defaultsTo: true,
          help: 'Use $driverTarget so the QA agent and Flutter Driver work.')
      ..addMultiOption('define',
          help: 'Extra --dart-define, as K=V. Repeatable.')
      ..addFlag('kill-previous',
          defaultsTo: true,
          help: 'Kill the run recorded in run.pid before starting a new one.');
  }

  /// Clears anything a previous run left behind that would block a new one.
  ///
  /// This runs before the app is force-stopped, so the orphaned service has
  /// already let go of the VM service by the time the new run needs it.
  Future<void> clearPreviousRun(QaContext ctx) async {
    if (!(argResults!['kill-previous'] as bool)) return;
    for (final line in await endRecordedRun(ctx)) {
      out(line);
    }
  }

  Future<int> launch(String command, {List<String> extraArgs = const []}) async {
    final ctx = context;
    final device = await ctx.device();
    final args = [
      ...buildFlutterArgs(
        command: command,
        deviceId: device.id,
        qa: argResults!['qa'] as bool,
        driver: argResults!['driver'] as bool,
        extraDefines: argResults!['define'] as List<String>,
      ),
      ...extraArgs,
    ];
    out('flutter ${args.join(' ')}');
    final result = await launchDetached(
      paths: ctx.paths,
      flutterExecutable: findFlutter(),
      arguments: args,
      onProgress: ctx.verbose ? (line) => warn('  $line') : null,
      onHeartbeat: (elapsed, lastLine) => warn(
        'still waiting for flutter $command (${elapsed.inSeconds} s)'
        '${lastLine.isEmpty ? '' : ': $lastLine'}',
      ),
    );
    await ctx.recordUris(vm: result.uris.vmService, dtd: result.uris.dtd);
    File(ctx.paths.deviceTxt).writeAsStringSync(device.id);
    File(ctx.paths.runVmTxt).writeAsStringSync(result.uris.vmService ?? '');
    out('pid=${result.pid}  log=${result.logPath}');
    out('dtd=${result.uris.dtd}');
    out('vm=${result.uris.vmService}');
    return 0;
  }
}

/// The `[qa]` outcome of one launch, from the agent's typed entries when it
/// answered and from log text otherwise.
class MarkerReport {
  const MarkerReport({
    required this.lines,
    required this.hasReset,
    required this.hasSeed,
    required this.seedFailed,
    required this.resetFailed,
    required this.source,
  });

  factory MarkerReport.fromOutcomes(AgentInfo info) => MarkerReport(
        lines: info.qaLog,
        hasReset: info.qaOutcomes.any((o) => o.kind == 'reset'),
        hasSeed: info.qaOutcomes.any((o) => o.kind == 'seed'),
        seedFailed: info.qaOutcomes.any((o) => o.kind == 'seed' && !o.ok),
        resetFailed: info.qaOutcomes.any((o) => o.kind == 'reset' && !o.ok),
        source: 'agent',
      );

  factory MarkerReport.fromText(String text, String source) {
    final parsed = parseQaMarkers(text);
    return MarkerReport(
      lines: parsed.all,
      hasReset: parsed.reset != null,
      hasSeed: parsed.seed != null,
      seedFailed: parsed.seedFailed,
      resetFailed: parsed.resetFailed,
      source: source,
    );
  }

  final List<String> lines;
  final bool hasReset;
  final bool hasSeed;
  final bool seedFailed;
  final bool resetFailed;
  final String source;

  bool satisfies({required bool reset, required bool seed}) =>
      (!reset || hasReset) && (!seed || hasSeed);
}

/// Shared by `run` and `relaunch`: the marker flags, their delivery, and the
/// wait for the app to report what it did with them.
mixin QaMarkers on QaCommand {
  void addMarkerOptions(ArgParser parser) {
    parser
      ..addFlag('fresh',
          negatable: false,
          help: 'Drop the qa_reset marker so the next QA launch wipes the qa db.')
      ..addOption('seed',
          help: 'Full-backup JSON to push as qa_seed.json '
              '(relative paths resolve against the package root).');
  }

  bool get wantsFresh => argResults!['fresh'] as bool;

  bool get wantsSeed => (argResults!['seed'] as String?)?.isNotEmpty ?? false;

  /// Places the requested markers; the app must be installed for there to be
  /// a documents directory to put them in.
  Future<void> applyMarkers(QaContext ctx, Device device) async {
    if (!wantsFresh && !wantsSeed) return;
    if (!await device.isInstalled()) {
      throw DeviceFailure(
        '${device.packageId} is not installed on ${device.label}, so there is '
        'nowhere to put the markers yet — run a plain `qa run` first, then '
        '`qa relaunch --fresh${wantsSeed ? ' --seed ${argResults!['seed']}' : ''}`',
      );
    }
    if (wantsFresh) {
      await device.dropResetMarker();
      out('qa_reset marker dropped');
    }
    if (wantsSeed) {
      final path = ctx.paths.resolve(argResults!['seed'] as String);
      await device.pushSeed(path);
      out('qa_seed.json pushed from $path');
    }
  }

  /// Waits for the `[qa]` lines, prints them, and fails when one that was
  /// asked for never arrives or the seed was rejected.
  Future<void> reportQaMarkers({
    required QaContext ctx,
    required String stamp,
    required bool includeRunLog,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!wantsFresh && !wantsSeed) return;
    final device = await ctx.device();
    var report = await _readMarkers(ctx, device, stamp, includeRunLog);
    final deadline = DateTime.now().add(timeout);
    while (!report.satisfies(reset: wantsFresh, seed: wantsSeed) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      report = await _readMarkers(ctx, device, stamp, includeRunLog);
    }
    if (report.source != 'agent' &&
        report.satisfies(reset: wantsFresh, seed: wantsSeed) &&
        !report.lines.any((l) => l.startsWith('onboarding'))) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      report = await _readMarkers(ctx, device, stamp, includeRunLog);
    }
    for (final line in report.lines) {
      out('[qa] $line');
    }
    if (report.resetFailed) {
      throw DeviceFailure(
        'the reset was refused (${report.lines.where((l) => l.startsWith('reset')).join('; ')}). '
        'The build is pointed at the owner database — never drive it; check '
        'the ANTA_QA_DB define.',
      );
    }
    if (report.seedFailed) {
      throw DeviceFailure(
        'the seed was not imported (${report.lines.where((l) => l.startsWith('seed')).join('; ')}). '
        'The database is not the one this run asked for — fix the fixture '
        'before reading the screen.',
      );
    }
    final missing = <String>[
      if (wantsFresh && !report.hasReset) 'reset',
      if (wantsSeed && !report.hasSeed) 'seed',
    ];
    if (missing.isNotEmpty) {
      throw DeviceFailure(
        'no `[qa] ${missing.join('` and no `[qa] ')}` line appeared within '
        '${timeout.inSeconds}s (asked the ${report.source}) — the app may not '
        'have consumed the marker (is this a QA build? `qa state` shows the '
        'process; `qa log` shows what it said).',
      );
    }
  }

  /// The agent is authoritative for its own process, so once it answers the
  /// logs are not consulted at all; before that the run log and the platform
  /// log are the only sources there are.
  Future<MarkerReport> _readMarkers(
    QaContext ctx,
    Device device,
    String stamp,
    bool includeRunLog,
  ) async {
    final info = await ctx.agentInfoOrNull(refresh: true);
    if (info != null) return MarkerReport.fromOutcomes(info);
    final parts = <String>[
      if (includeRunLog) readRunLog(ctx.paths),
      await device.qaLogText(stamp: stamp),
    ];
    return MarkerReport.fromText(
      parts.join('\n'),
      includeRunLog ? 'run log and ${device.logName}' : device.logName,
    );
  }
}

/// Starts the installed build with a deterministic VM service port and waits
/// until the agent answers, so the next verb has somewhere to talk to.
mixin InstalledLaunch on QaCommand {
  Future<AgentClient?> launchInstalled(
    QaContext ctx, {
    Duration vmTimeout = const Duration(seconds: 45),
  }) async {
    final device = await ctx.device();
    final port = await pickFreePort();
    final launch = await device.launchApp(vmServicePort: port);
    out('launched: ${launch.description}');
    final startedAt = DateTime.now();
    final VmServiceClient vm;
    try {
      vm = await waitForVmService(
        launch.vmServiceUri,
        timeout: vmTimeout,
        stillWorthWaiting: () async {
          if (DateTime.now().difference(startedAt) < const Duration(seconds: 6)) {
            return true;
          }
          return await device.appPid() != null;
        },
      );
    } on DeviceFailure catch (e) {
      await ctx.recordUris(vm: null, dtd: null);
      if (device.nativeDriver != null) {
        warn('warning: the VM service never answered on port $port (${e.message}) '
            '— not a debug build? The adb path still works; `qa run` installs '
            'the driver build.');
        return null;
      }
      throw DeviceFailure(
        '${e.message}\nThe app was started but its VM service never answered '
        'on port $port — is the installed build a debug build? `qa run` '
        'installs one.',
      );
    }
    await ctx.recordUris(vm: launch.vmServiceUri, dtd: null);
    out('vm=${launch.vmServiceUri}  (no DTD after a bare launch — `qa attach` '
        'when you need hot reload or the Dart MCP)');
    final agent = await ctx.adoptAgent(vm);
    vm.driverWait = const Duration(seconds: 15);
    try {
      var info = await agent.info(refresh: true);
      if (!info.firstFrame) {
        final drawn = await pollUntil<AgentInfo>(
          timeout: const Duration(seconds: 20),
          interval: const Duration(milliseconds: 100),
          probe: () async {
            final again = await agent.info(refresh: true);
            return again.firstFrame ? again : null;
          },
        );
        if (drawn == null) {
          warn('warning: the app has not drawn a frame ${20}s after launch — '
              'verbs may fail until it does');
        } else {
          info = drawn;
        }
      }
      await ctx.rememberDocuments(info);
      out('agent: ${info.describe()}  (first frame after '
          '${DateTime.now().difference(startedAt).inMilliseconds} ms)');
      if (!info.qaMode) {
        warn('warning: the running build is NOT a QA build — it is reading the '
            'owner database. Install one with `qa run`.');
      }
      if (info.cloud ?? false) {
        warn('warning: this build can reach Firebase (ANTA_QA_CLOUD) — it acts '
            'as whoever is signed in on this install. Do not screenshot or '
            'dump account screens, and do not touch pairing.');
      }
      return agent;
    } on DeviceFailure catch (e) {
      if (device.nativeDriver == null) {
        throw DeviceFailure(
          '${e.message}\nOn ${device.label} every see-and-act verb needs the '
          'agent, so install the driver build with `qa run`.',
        );
      }
      warn('warning: no QA agent in the running build (${e.message}) — the adb '
          'path still works; `qa run` installs the driver build');
      return null;
    }
  }
}

class RunAppCommand extends LaunchingCommand with QaMarkers {
  RunAppCommand() {
    addMarkerOptions(argParser);
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Stop the app, then start a detached `flutter run` in QA mode (builds '
      'and installs; gives DTD + VM URIs).';

  @override
  Future<int> run() async {
    final ctx = context;
    await clearPreviousRun(ctx);
    final device = await ctx.device();
    await applyMarkers(ctx, device);
    await device.forceStop();
    final code = await launch('run');
    await reportQaMarkers(
      ctx: ctx,
      stamp: File(ctx.paths.runStamp).readAsStringSync().trim(),
      includeRunLog: true,
    );
    return code;
  }
}

class RelaunchCommand extends QaCommand
    with PostActions, QaMarkers, InstalledLaunch {
  RelaunchCommand() {
    addMarkerOptions(argParser);
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'relaunch';

  @override
  String get description =>
      'Stop and restart the installed build with the QA markers applied and '
      'the agent reachable — the fast reset (no build, no DTD).';

  @override
  Future<int> run() async {
    final ctx = context;
    final device = await ctx.device();
    await ctx.requireInstalled(device);
    await applyMarkers(ctx, device);
    final stamp = logcatStamp(DateTime.now());
    await device.forceStop();
    await launchInstalled(ctx);
    await reportQaMarkers(ctx: ctx, stamp: stamp, includeRunLog: false);
    final runDevice = File(ctx.paths.deviceTxt);
    if (File(ctx.paths.runPid).existsSync() &&
        runDevice.existsSync() &&
        runDevice.readAsStringSync().trim() == device.id) {
      out('note: the flutter run behind run.log has lost the app — '
          '`qa attach` when you need DTD again');
    }
    await runPostActions();
    return 0;
  }
}

class AttachCommand extends LaunchingCommand {
  @override
  String get name => 'attach';

  @override
  String get description =>
      'Attach `flutter attach` to the running app and capture its DTD/VM '
      'URIs. Uses the VM URI already known for the device (a relaunch, or the '
      "app's own log) so it never waits for a fresh announcement.";

  @override
  Future<int> run() async {
    final ctx = context;
    await clearPreviousRun(ctx);
    var known = await ctx.recordedVmUri();
    if (known == null) {
      try {
        known = await (await ctx.device()).discoverVmServiceUri();
      } on QaException {
        known = null;
      }
    }
    if (known != null) out('attaching to $known');
    return launch(
      'attach',
      extraArgs: known == null ? const [] : ['--debug-url=$known'],
    );
  }
}

class StopCommand extends QaCommand {
  @override
  String get name => 'stop';

  @override
  String get description => 'Stop the app on the device.';

  @override
  Future<int> run() async {
    final device = await context.device();
    await device.forceStop();
    out('stopped ${device.packageId} on ${device.label}');
    return 0;
  }
}

/// Ends the detached `flutter run` in `run.pid`, reaps what it leaves behind
/// and forgets the URIs it was serving: the VM URI a `flutter run` prints is
/// its DDS proxy, which dies with the tool, so a verb that kept using it
/// would fail with a connection error instead of a hint.
Future<List<String>> endRecordedRun(QaContext ctx) async {
  final lines = <String>[];
  final pid = await killRecordedRun(ctx.paths, ctx.runner);
  if (pid != null) lines.add('killed run pid $pid');
  final orphans = await reapOrphanedServices(ctx.runner);
  if (orphans.isNotEmpty) {
    lines.add('reaped orphaned dart development-service: ${orphans.join(', ')}');
  }
  final deviceFile = File(ctx.paths.deviceTxt);
  final runVmFile = File(ctx.paths.runVmTxt);
  if (deviceFile.existsSync()) {
    final id = deviceFile.readAsStringSync().trim();
    final runVm = runVmFile.existsSync() ? runVmFile.readAsStringSync().trim() : '';
    deviceFile.deleteSync();
    if (runVmFile.existsSync()) runVmFile.deleteSync();
    final vmFile = File(ctx.paths.vmTxtFor(id));
    final current = vmFile.existsSync() ? vmFile.readAsStringSync().trim() : '';
    if (id.isNotEmpty && current.isNotEmpty && current == runVm) {
      vmFile.writeAsStringSync('');
      final dtdFile = File(ctx.paths.dtdTxtFor(id));
      if (dtdFile.existsSync()) dtdFile.writeAsStringSync('');
      lines.add('forgot the URIs recorded for $id (they died with the run — '
          '`qa relaunch -d $id` brings the agent back in seconds)');
    } else if (id.isNotEmpty && current.isNotEmpty) {
      final dtdFile = File(ctx.paths.dtdTxtFor(id));
      if (dtdFile.existsSync()) dtdFile.writeAsStringSync('');
      lines.add('kept the VM URI for $id (a relaunch recorded it, not this run); '
          'the DTD is gone with the run');
    }
  }
  return lines;
}

class KillRunCommand extends QaCommand {
  @override
  String get name => 'kill-run';

  @override
  String get description =>
      'Kill the detached `flutter run` recorded in run.pid. A device app stays '
      'up; a desktop app started by that run dies with it (`qa relaunch` '
      'restarts it).';

  @override
  Future<int> run() async {
    final lines = await endRecordedRun(context);
    if (lines.isEmpty) {
      out('no run.pid — nothing to kill');
      return 0;
    }
    for (final line in lines) {
      out(line);
    }
    return 0;
  }
}

class DtdCommand extends QaCommand {
  DtdCommand() {
    argParser.addFlag('vm',
        negatable: false, help: 'Print the VM service URI instead.');
  }

  @override
  String get name => 'dtd';

  @override
  String get description =>
      'Print the Dart Tooling Daemon URI captured by the last run '
      '(--vm for the VM service URI the agent uses).';

  @override
  Future<int> run() async {
    final ctx = context;
    if (argResults!['vm'] as bool) {
      final vm = await ctx.recordedVmUri();
      if (vm == null) {
        throw DeviceFailure('no VM URI recorded yet — run `qa run`, `qa attach` or `qa relaunch` first');
      }
      out(vm);
      return 0;
    }
    final dtd = await ctx.recordedDtdUri();
    if (dtd == null) {
      final vm = await ctx.recordedVmUri();
      throw DeviceFailure(
        vm == null
            ? 'no URI recorded yet — run `qa run` or `qa attach` first'
            : 'no DTD after a bare launch (the VM service is $vm; `qa dtd --vm` '
                'prints it) — run `qa attach` for a DTD',
      );
    }
    out(dtd);
    return 0;
  }
}

class LaunchCommand extends QaCommand with PostActions, InstalledLaunch {
  LaunchCommand() {
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'launch';

  @override
  String get description =>
      'Bring the installed build to the front; start it (agent reachable) '
      'when it is not running.';

  @override
  Future<int> run() async {
    final ctx = context;
    final device = await ctx.device();
    await ctx.requireInstalled(device);
    if (await device.appPid() != null) {
      await device.bringToFront();
      out('brought ${device.packageId} to the front on ${device.label}');
    } else {
      await launchInstalled(ctx);
    }
    await runPostActions();
    return 0;
  }
}

class ShotCommand extends QaCommand {
  ShotCommand() {
    argParser
      ..addOption('scale', defaultsTo: '0.5', help: 'Downscale factor, 0 < f <= 1.')
      ..addFlag('full', negatable: false, help: 'No downscale (same as --scale 1).')
      ..addOption('out', help: 'Directory to write into.')
      ..addOption('via',
          allowed: ['native', 'agent'],
          help: 'native: the device capture (adb screencap, simctl io); agent: '
              'the Flutter view rendered by the app. Default native where '
              'it exists, agent on macOS.');
  }

  @override
  String get name => 'shot';

  @override
  String get description =>
      'Take a screenshot and print its path (Read that path to see the screen).';

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    final scale = (argResults!['full'] as bool)
        ? 1.0
        : (double.tryParse(argResults!['scale'] as String) ??
            (throw UsageFailure('--scale must be a number')));
    final via = parseViaMode(argResults!['via'] as String?);
    final path = await captureShot(
      () => ctx.screenshotPng(via: via),
      ctx.paths,
      name: rest.isEmpty ? 'shot' : rest.first,
      scale: scale,
      outDir: argResults!['out'] as String?,
    );
    out(path);
    return 0;
  }
}

class DumpCommand extends QaCommand {
  DumpCommand() {
    argParser
      ..addFlag('all',
          negatable: false, help: 'Include nodes with no label and no flags, and hidden ones.')
      ..addFlag('json', negatable: false, help: 'Emit the nodes as JSON.')
      ..addFlag('cached',
          negatable: false,
          help: 'Print the last dump from build/qa/last_dump.txt without '
              'touching the device.');
  }

  @override
  String get name => 'dump';

  @override
  String get description =>
      'Print the accessibility tree as one compact line per node.';

  @override
  Future<int> run() async {
    final ctx = context;
    final UiTree tree;
    String? age;
    if (argResults!['cached'] as bool) {
      final cached = readDumpCache(ctx.paths);
      if (cached == null) {
        throw TargetFailure(
          'no previous dump — run `dump` first or target by label',
        );
      }
      tree = cached.tree;
      age = describeAge(cached.ageFrom(DateTime.now()));
    } else {
      tree = await ctx.dump();
    }
    warnIfForeign(tree);
    final all = argResults!['all'] as bool;
    final nodes = all ? tree.nodes : tree.nodes.where((n) => n.interesting).toList();
    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ')
          .convert(nodes.map((n) => n.toJson()).toList()));
      return 0;
    }
    for (final node in nodes) {
      out(node.describe());
    }
    final hidden = tree.nodes.where((n) => n.hidden).length;
    out('${nodes.length} node(s) of ${tree.nodes.length}'
        '${all ? '' : ' (pass --all for the rest${hidden == 0 ? '' : ', $hidden off screen'})'}'
        '${age == null ? '' : '  [cached, taken $age]'}'
        '${tree.source == UiTreeSource.agent ? '  [agent]' : ''}');
    return 0;
  }
}

abstract class TargetCommand extends QaCommand {
  TargetCommand() {
    argParser.addOption('nth',
        help: 'Pick the Nth match (0-based) when a label is ambiguous.');
  }

  Future<TargetLookup> target() async =>
      context.lookup(requireRest('a target'), nth: intOption('nth'));
}

class TapCommand extends TargetCommand with PostActions {
  TapCommand() {
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'tap';

  @override
  String get description =>
      'Tap a target: a label, `id:foo`, `#12` or `x,y`.';

  @override
  Future<int> run() async {
    final ctx = context;
    final lookup = await target();
    warnIfForeign(lookup.tree);
    final node = lookup.resolved.node;
    var point = (lookup.resolved.x, lookup.resolved.y);
    var description = lookup.description;
    final tree = lookup.tree;
    if (node != null && node.hidden) {
      throw TargetFailure(
        '${node.describe()} is off screen — `scroll-to` it first',
      );
    }
    if (tree != null && node != null && !node.clickable) {
      final clickable = tree.clickableSelfOrAncestor(node);
      if (clickable != null && clickable.index != node.index) {
        point = (clickable.bounds.centreX, clickable.bounds.centreY);
        description = '${node.label} via ${clickable.describe()}';
      }
    }
    await (await ctx.driver()).tap(point.$1, point.$2);
    out('tapped ${point.$1},${point.$2}  $description');
    await runPostActions();
    return 0;
  }
}

class LongPressCommand extends TargetCommand with PostActions {
  LongPressCommand() {
    argParser.addOption('ms', defaultsTo: '800', help: 'Press duration.');
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'longpress';

  @override
  String get description => 'Long-press a target.';

  @override
  Future<int> run() async {
    final ctx = context;
    final lookup = await target();
    warnIfForeign(lookup.tree);
    final resolved = lookup.resolved;
    final ms = intOption('ms') ?? 800;
    await (await ctx.driver()).longPress(resolved.x, resolved.y, ms);
    out('long-pressed ${resolved.x},${resolved.y} for ${ms}ms  '
        '${lookup.description}');
    await runPostActions();
    return 0;
  }
}

class TextCommand extends TargetCommand {
  @override
  String get name => 'text';

  @override
  String get description => 'Print the text of a target node.';

  @override
  Future<int> run() async {
    final lookup = await target();
    warnIfForeign(lookup.tree);
    final node = lookup.resolved.node;
    if (node == null) throw TargetFailure('a coordinate target has no text');
    out(node.text.isNotEmpty ? node.text : node.contentDesc);
    return 0;
  }
}

class WaitCommand extends TargetCommand {
  WaitCommand() {
    argParser
      ..addFlag('gone', negatable: false, help: 'Wait for it to disappear.')
      ..addOption('timeout', defaultsTo: '10', help: 'Seconds to poll for.');
  }

  @override
  String get name => 'wait';

  @override
  String get description => 'Poll the accessibility tree until a target appears.';

  @override
  Future<int> run() async {
    final ctx = context;
    final wanted = requireRest('a target');
    final gone = argResults!['gone'] as bool;
    final seconds = intOption('timeout') ?? 10;
    final outcome = await ctx.pollFor(
      wanted,
      gone: gone,
      timeout: Duration(seconds: seconds),
      nth: intOption('nth'),
    );
    warnIfForeign(outcome.lastTree);
    if (outcome.satisfied) {
      out(gone ? 'gone: "$wanted"' : 'found: ${outcome.found!.description}');
      return 0;
    }
    throw TargetFailure(waitTimeoutMessage(
      wanted: wanted,
      gone: gone,
      seconds: seconds,
      tree: outcome.lastTree,
    ));
  }
}

class ScrollToCommand extends TargetCommand {
  ScrollToCommand() {
    argParser
      ..addOption('max', defaultsTo: '8', help: 'Maximum swipes to try.')
      ..addOption('in', help: 'Target naming the scrollable to swipe inside.')
      ..addFlag('up',
          negatable: false, help: 'Scroll backwards (towards the top) instead.');
  }

  @override
  String get name => 'scroll-to';

  @override
  String get description => 'Swipe inside a scrollable until a target shows up on screen.';

  @override
  Future<int> run() async {
    final ctx = context;
    final wanted = requireRest('a target');
    final maxSwipes = intOption('max') ?? 8;
    final container = argResults!['in'] as String?;
    final direction =
        (argResults!['up'] as bool) ? SwipeDirection.down : SwipeDirection.up;
    final driver = await ctx.driver();
    final nth = intOption('nth');

    UiTree? tree;
    for (var attempt = 0; attempt <= maxSwipes; attempt++) {
      tree = await ctx.dump();
      if (attempt == 0) warnIfForeign(tree);
      try {
        final found = TargetResolver(tree).resolve(wanted, nth: nth);
        if (found.node == null || !found.node!.hidden) {
          out('found after $attempt swipe(s): ${found.description}');
          return 0;
        }
      } on TargetFailure catch (e) {
        if (e.message.contains('ambiguous')) rethrow;
      }
      if (attempt == maxSwipes) break;
      final scrollable = container == null
          ? tree.firstScrollable
          : TargetResolver(tree).resolve(container).node;
      final bounds = scrollable?.bounds;
      final size = await driver.screenSize();
      final path = buildSwipe(
        left: bounds?.left ?? 0,
        top: bounds?.top ?? 0,
        width: bounds?.width ?? size.width,
        height: bounds?.height ?? size.height,
        direction: direction,
      );
      await driver.swipePath(path);
      await Future<void>.delayed(
        driver.name == 'agent'
            ? const Duration(milliseconds: 150)
            : const Duration(milliseconds: 400),
      );
    }
    throw TargetFailure(
      '"$wanted" not reachable after $maxSwipes swipe(s). '
      'foreground=${tree?.foregroundPackage ?? 'unknown'}. '
      '${tree == null ? '' : TargetResolver(tree).onScreenListing()}',
    );
  }
}

class TypeCommand extends QaCommand with PostActions {
  TypeCommand() {
    argParser
      ..addFlag('enter',
          negatable: false, help: 'Send ENTER after the text.')
      ..addFlag('replace',
          negatable: false,
          help: 'Agent path: replace the field content instead of inserting '
              'at the caret.');
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'type';

  @override
  String get description =>
      'Type into the focused field: any Unicode through the agent, ASCII '
      'through `adb shell input text`.';

  @override
  Future<int> run() async {
    final ctx = context;
    final text = requireRest('some text');
    final driver = await ctx.driver();
    final outcome = await driver.typeText(
      text,
      replace: argResults!['replace'] as bool,
    );
    final enter = argResults!['enter'] as bool;
    String? sent;
    if (enter) sent = await driver.key('enter');
    final field = outcome.text == null
        ? ''
        : '  → field: "${outcome.text}" (caret ${outcome.selection})';
    out('typed "$text"${enter ? ' + ENTER${sent == null ? '' : ' ($sent)'}' : ''}$field');
    if (outcome.imeShown == false) {
      warn('warning: no keyboard is up — the text may go nowhere '
          '(tap a field first)');
    }
    await runPostActions();
    return 0;
  }
}

class KeyCommand extends QaCommand with PostActions {
  KeyCommand() {
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'key';

  @override
  String get description =>
      'Send a key: back, enter, tab, esc, del, up/down/left/right, a text '
      'action (done, search, newline…) or, on adb, a raw KEYCODE_*.';

  @override
  Future<int> run() async {
    final key = requireRest('a key name');
    final sent = await (await context.driver()).key(key);
    out('sent $sent');
    await runPostActions();
    return 0;
  }
}

class SwipeCommand extends QaCommand with PostActions {
  SwipeCommand() {
    argParser
      ..addOption('from', help: 'Start point as x,y. Defaults to the centre.')
      ..addOption('dist', help: 'Travel in pixels. Defaults to half the screen.')
      ..addOption('ms', defaultsTo: '300', help: 'Duration of the gesture.');
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'swipe';

  @override
  String get description =>
      'Swipe up/down/left/right (the finger direction; `up` scrolls content down).';

  @override
  Future<int> run() async {
    final ctx = context;
    final direction = parseSwipeDirection(requireRest('a direction'));
    final driver = await ctx.driver();
    final size = await driver.screenSize();
    int? fromX;
    int? fromY;
    final from = argResults!['from'] as String?;
    if (from != null && from.isNotEmpty) {
      final parts = from.split(',');
      if (parts.length != 2) throw UsageFailure('--from must be x,y');
      fromX = int.tryParse(parts[0].trim());
      fromY = int.tryParse(parts[1].trim());
      if (fromX == null || fromY == null) throw UsageFailure('--from must be x,y');
    }
    final path = buildSwipe(
      width: size.width,
      height: size.height,
      direction: direction,
      fromX: fromX,
      fromY: fromY,
      distance: intOption('dist'),
      durationMs: intOption('ms') ?? 300,
    );
    await driver.swipePath(path);
    out('swiped ${direction.name}: $path');
    await runPostActions();
    return 0;
  }
}

class DragCommand extends QaCommand with PostActions {
  DragCommand() {
    argParser
      ..addOption('hold',
          defaultsTo: '600',
          help: 'Milliseconds to hold before moving (a reorder needs > 500).')
      ..addOption('ms', defaultsTo: '400', help: 'Milliseconds the move takes.')
      ..addOption('nth', help: 'Pick the Nth match when the first target is ambiguous.');
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'drag';

  @override
  String get description =>
      'Press a target, hold, and drag it onto another target (agent path): '
      '`drag "Week 1" "Inbox"`, `drag #14 540,1800`.';

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    if (rest.length != 2) {
      throw UsageFailure('drag needs exactly two targets: <from> <to>');
    }
    final driver = await ctx.driver();
    final from = await ctx.lookup(rest[0], nth: intOption('nth'));
    warnIfForeign(from.tree);
    final to = isPointTarget(rest[1]) || isIndexTarget(rest[1])
        ? await ctx.lookup(rest[1])
        : TargetLookup(
            resolved: TargetResolver(from.tree ?? await ctx.dump()).resolve(rest[1]),
            tree: from.tree,
          );
    await driver.drag(
      from.resolved.x,
      from.resolved.y,
      to.resolved.x,
      to.resolved.y,
      holdMs: intOption('hold') ?? 600,
      moveMs: intOption('ms') ?? 400,
    );
    out('dragged ${from.resolved.x},${from.resolved.y} -> '
        '${to.resolved.x},${to.resolved.y}  ${from.description}  onto  '
        '${to.resolved.description}');
    await runPostActions();
    return 0;
  }
}

class ClearCommand extends QaCommand with PostActions {
  ClearCommand() {
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'clear';

  @override
  String get description =>
      'Empty the focused text field (agent path).';

  @override
  Future<int> run() async {
    await (await context.driver()).clear();
    out('cleared the focused field');
    await runPostActions();
    return 0;
  }
}

class LookCommand extends QaCommand {
  LookCommand() {
    argParser
      ..addOption('scale', defaultsTo: '0.5', help: 'Downscale factor, 0 < f <= 1.')
      ..addFlag('full', negatable: false, help: 'No downscale.')
      ..addFlag('all', negatable: false, help: 'Mark and list every node, not just the interesting ones.')
      ..addOption('out', help: 'Directory to write into.')
      ..addOption('via', allowed: ['native', 'agent'], help: 'Which layer takes the picture.');
  }

  @override
  String get name => 'look';

  @override
  String get description =>
      'One call to see the screen: a screenshot with every node boxed and '
      'tagged `#N`, followed by the matching dump lines.';

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    final scale = (argResults!['full'] as bool)
        ? 1.0
        : (double.tryParse(argResults!['scale'] as String) ??
            (throw UsageFailure('--scale must be a number')));
    final all = argResults!['all'] as bool;
    final via = parseViaMode(argResults!['via'] as String?);
    final results = await Future.wait<Object>([
      ctx.dump(),
      ctx.screenshotPng(via: via),
    ]);
    final tree = results[0] as UiTree;
    final png = results[1] as List<int>;
    warnIfForeign(tree);
    final path = await captureAnnotatedShot(
      () async => png,
      tree,
      ctx.paths,
      name: rest.isEmpty ? 'look' : rest.first,
      scale: scale,
      all: all,
      outDir: argResults!['out'] as String?,
    );
    out(path);
    final nodes = all ? tree.nodes : tree.nodes.where((n) => n.interesting).toList();
    for (final node in nodes) {
      out(node.describe());
    }
    out('${nodes.length} node(s) marked; orange = tappable, blue = text field, '
        'green = scrollable');
    return 0;
  }
}

class ExpectCommand extends QaCommand {
  ExpectCommand() {
    argParser
      ..addMultiOption('absent', help: 'A target that must NOT be on screen. Repeatable.')
      ..addOption('timeout', defaultsTo: '5', help: 'Seconds to keep re-checking.');
  }

  @override
  String get name => 'expect';

  @override
  String get description =>
      'Assert several targets are on screen (and --absent ones are not) in '
      'one call; exits 2 listing every miss.';

  @override
  Future<int> run() async {
    final ctx = context;
    final present = argResults!.rest;
    final absent = argResults!['absent'] as List<String>;
    if (present.isEmpty && absent.isEmpty) {
      throw UsageFailure('expect needs at least one target or --absent');
    }
    final seconds = intOption('timeout') ?? 5;
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    final interval = (await ctx.driver()).pollInterval;
    UiTree tree;
    List<String> misses;
    while (true) {
      tree = await ctx.dump();
      misses = expectMisses(tree, present: present, absent: absent);
      if (misses.isEmpty || !DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(interval);
    }
    warnIfForeign(tree);
    for (final target in present) {
      if (!misses.any((m) => m.startsWith('missing "$target"'))) {
        out('ok  present  "$target"');
      }
    }
    for (final target in absent) {
      if (!misses.any((m) => m.startsWith('unexpected "$target"'))) {
        out('ok  absent   "$target"');
      }
    }
    if (misses.isEmpty) return 0;
    throw TargetFailure(
      '${misses.length} expectation(s) failed after ${seconds}s:\n  '
      '${misses.join('\n  ')}\n${TargetResolver(tree).onScreenListing()}',
    );
  }
}

/// Which expectations a tree does not satisfy, worded for the failure line.
List<String> expectMisses(
  UiTree tree, {
  required List<String> present,
  required List<String> absent,
}) {
  final resolver = TargetResolver(tree);
  final misses = <String>[];
  bool found(String target) {
    try {
      return !(resolver.resolve(target).node?.hidden ?? false);
    } on TargetFailure catch (e) {
      return e.message.contains('ambiguous');
    }
  }

  for (final target in present) {
    if (!found(target)) misses.add('missing "$target"');
  }
  for (final target in absent) {
    if (found(target)) misses.add('unexpected "$target" is on screen');
  }
  return misses;
}

abstract class HotCodeCommand extends QaCommand with PostActions {
  HotCodeCommand() {
    argParser.addOption('timeout', defaultsTo: '90', help: 'Seconds to wait for the tool to report.');
    addPostActionOptions(argParser);
  }

  bool get fullRestart;

  @override
  Future<int> run() async {
    final ctx = context;
    if (Platform.isWindows) {
      throw UnsupportedOnPlatform(
        name,
        'Windows',
        instead: 'use the Dart MCP `hot_reload`/`hot_restart` over the DTD from `qa dtd`',
      );
    }
    final pidFile = File(ctx.paths.runPid);
    final pid = pidFile.existsSync() ? int.tryParse(pidFile.readAsStringSync().trim()) : null;
    if (pid == null || !await isProcessAlive(pid, ctx.runner)) {
      throw DeviceFailure(
        'no live `flutter run` to signal (run.pid ${pid == null ? 'missing' : '$pid is gone'}) '
        '— hot ${fullRestart ? 'restart' : 'reload'} needs the tool process from `qa run`',
      );
    }
    final logFile = File(ctx.paths.runLog);
    final before = logFile.existsSync() ? logFile.lengthSync() : 0;
    final signal = fullRestart ? ProcessSignal.sigusr2 : ProcessSignal.sigusr1;
    Process.killPid(pid, signal);
    final seconds = intOption('timeout') ?? 90;
    final started = DateTime.now();
    final outcome = await pollUntil<(bool, String)>(
      timeout: Duration(seconds: seconds),
      interval: const Duration(milliseconds: 250),
      probe: () => hotReloadOutcome(readAppended(ctx.paths.runLog, before)),
    );
    if (outcome != null) {
      final appended = readAppended(ctx.paths.runLog, before);
      final took = DateTime.now().difference(started).inMilliseconds;
      if (!outcome.$1) {
        throw DeviceFailure(
          'hot ${fullRestart ? 'restart' : 'reload'} failed after $took ms: ${outcome.$2}\n'
          '${tailLines(appended, lines: 12)}',
        );
      }
      out('${fullRestart ? 'restarted' : 'reloaded'} in $took ms: ${outcome.$2}');
      if (fullRestart) {
        final agent = await ctx.agentOrNull();
        if (agent != null) await agent.settle(ms: 800);
      }
      await runPostActions();
      return 0;
    }
    throw DeviceFailure(
      'the tool did not report the hot ${fullRestart ? 'restart' : 'reload'} within ${seconds}s '
      '(signalled pid $pid). Last log lines:\n${tailLines(readRunLog(ctx.paths), lines: 8)}',
    );
  }
}

class ReloadCommand extends HotCodeCommand {
  @override
  String get name => 'reload';

  @override
  String get description =>
      'Hot reload the running `flutter run` (SIGUSR1) after a code edit and '
      'wait for its report; `--wait`/`--shot` verify the result.';

  @override
  bool get fullRestart => false;
}

class RestartCommand extends HotCodeCommand {
  @override
  String get name => 'restart';

  @override
  String get description =>
      'Hot restart the running `flutter run` (SIGUSR2): state is reset, the '
      'QA database is kept, the agent stays reachable.';

  @override
  bool get fullRestart => true;
}

class PerfCommand extends QaCommand {
  PerfCommand() {
    argParser.addFlag('json', negatable: false, help: 'Emit the raw stats.');
  }

  @override
  String get name => 'perf';

  @override
  String get description =>
      'Frame timing from inside the app: `perf start`, drive the flow, then '
      '`perf stop` (or `perf read` mid-way) — p50/p90/max build, raster and '
      'total ms plus the jank count (frames over 16.7 ms).';

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    final action = rest.isEmpty ? 'read' : rest.first;
    if (!const ['start', 'stop', 'read'].contains(action)) {
      throw UsageFailure('perf takes start, stop or read');
    }
    final agent = await ctx.agent();
    final result = await agent.op('perf', {'action': action});
    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ').convert(result));
      return 0;
    }
    if (action == 'start') {
      out('recording frame timings — drive the flow, then `qa perf stop`');
      return 0;
    }
    out(describePerf(result));
    return 0;
  }
}

/// One line per phase, the way an agent wants to read a perf sample.
String describePerf(Map<String, dynamic> result) {
  String phase(String key) {
    final stats = result[key];
    if (stats is! Map) return '$key: -';
    return '$key p50 ${stats['p50']} ms  p90 ${stats['p90']} ms  max ${stats['max']} ms';
  }

  final frames = result['frames'] ?? 0;
  final elapsed = result['elapsedMs'] ?? 0;
  final jank = result['jank'] ?? 0;
  return 'frames=$frames over $elapsed ms  jank=$jank (build or raster over 16.7 ms)'
      '${result['recording'] == true ? '  [still recording]' : ''}\n'
      '  ${phase('build')}\n  ${phase('raster')}\n  ${phase('total')}';
}

class StepsCommand extends QaCommand {
  StepsCommand() {
    argParser
      ..addOption('file',
          help: 'Read one step per line from this file; `-` reads stdin.')
      ..addFlag('keep-going',
          negatable: false,
          help: 'Run every step even after one fails; exit with the first '
              'non-zero code.');
  }

  @override
  String get name => 'steps';

  @override
  String get description =>
      'Run several verbs in one process, sharing the device connection.';

  @override
  Future<int> run() async {
    final ctx = context;
    final steps = <String>[...argResults!.rest];
    final file = argResults!['file'] as String?;
    if (file != null && file.isNotEmpty) {
      steps.addAll(parseStepLines(
        file == '-' ? _readAllStdin() : _readStepFile(ctx.paths.resolve(file)),
      ));
    }
    if (steps.isEmpty) throw UsageFailure('steps needs at least one step');

    final qaRunner = runner! as QaCommandRunner;
    final keepGoing = argResults!['keep-going'] as bool;
    var firstFailure = 0;
    for (var index = 0; index < steps.length; index++) {
      final line = steps[index];
      final words = splitShellWords(line);
      if (words.isEmpty) continue;
      if (words.first == 'steps') {
        throw UsageFailure('a step cannot itself be `steps`');
      }
      out('[${index + 1}/${steps.length}] $line');
      final code = await _runStep(qaRunner, words);
      if (code == 0) continue;
      if (firstFailure == 0) firstFailure = code;
      if (!keepGoing) {
        out('steps: stopped at ${index + 1}/${steps.length}');
        return code;
      }
      out('steps: step ${index + 1}/${steps.length} failed, continuing');
    }
    return firstFailure;
  }

  Future<int> _runStep(QaCommandRunner qaRunner, List<String> words) async {
    qaRunner.outputPrefix = '  ';
    try {
      return await qaRunner.run(words) ?? 0;
    } on UsageException catch (e) {
      warn('qa: ${e.message}');
      return exitUsage;
    } on QaException catch (e) {
      warn('qa: ${e.message}');
      return e.code;
    } finally {
      qaRunner.outputPrefix = '';
    }
  }

  static String _readStepFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw UsageFailure('step file not found: $path');
    }
    return file.readAsStringSync();
  }

  static String _readAllStdin() {
    final buffer = StringBuffer();
    while (true) {
      final line = stdin.readLineSync();
      if (line == null) break;
      buffer.writeln(line);
    }
    return buffer.toString();
  }
}

class LogCommand extends QaCommand {
  LogCommand() {
    argParser
      ..addOption('lines', defaultsTo: '200', help: 'Tail this many lines.')
      ..addFlag('since-launch',
          negatable: false,
          help: 'Android: only lines since the last `qa run`.')
      ..addFlag('all', negatable: false, help: 'Do not filter to app lines.');
  }

  @override
  String get name => 'log';

  @override
  List<String> get aliases => const ['logcat'];

  @override
  String get description =>
      'Dump the platform log (logcat, the simulator unified log, or the '
      "desktop app's stdout), filtered to the app by default.";

  @override
  Future<int> run() async {
    final ctx = context;
    final device = await ctx.device();
    String? stamp;
    if (argResults!['since-launch'] as bool) {
      final file = File(ctx.paths.runStamp);
      if (!file.existsSync()) {
        throw DeviceFailure('no run.started stamp — run `qa run` first');
      }
      stamp = file.readAsStringSync().trim();
      if (device.kind != DeviceKind.android) {
        warn('note: --since-launch is a logcat filter; the ${device.kind.label} '
            'log covers the last ${device.kind == DeviceKind.ios ? '10 minutes' : 'launch'} instead');
      }
    }
    var lines = (await device.readLog(sinceStamp: stamp)).split('\n');
    if (!(argResults!['all'] as bool)) lines = filterLogcat(lines);
    final limit = intOption('lines') ?? 200;
    if (lines.length > limit) lines = lines.sublist(lines.length - limit);
    for (final line in lines) {
      out(redactSecrets(line.trimRight()));
    }
    out('${lines.length} line(s)');
    return 0;
  }
}

class ErrorsCommand extends QaCommand {
  ErrorsCommand() {
    argParser
      ..addOption('lines', defaultsTo: '50', help: 'Keep the last N hits.')
      ..addFlag('all',
          negatable: false,
          help: 'Show the known-noise lines that are hidden by default.')
      ..addFlag('clear',
          negatable: false,
          help: "Clear the agent's in-app error buffer after printing it.");
  }

  @override
  String get name => 'errors';

  @override
  String get description =>
      'Grep the run log, the platform log and the in-app error buffer for '
      'exceptions and [anta]/[qa] lines.';

  @override
  Future<int> run() async {
    final ctx = context;
    final limit = intOption('lines') ?? 50;
    final showAll = argResults!['all'] as bool;
    final sources = <String, List<String>>{};
    if (File(ctx.paths.runLog).existsSync()) {
      sources[ctx.paths.runLog] = errorLines(readRunLog(ctx.paths), limit: limit);
    }
    final device = await ctx.device();
    final platformLog = device.kind == DeviceKind.android
        ? await device.qaLogText()
        : await device.readLog();
    sources[device.logName] = errorLines(platformLog, limit: limit);
    final agent = await ctx.agentOrNull();
    if (agent != null) {
      try {
        final captured = await agent.errors(clear: argResults!['clear'] as bool);
        sources['agent'] = captured.length > limit
            ? captured.sublist(captured.length - limit)
            : captured;
      } on QaException catch (e) {
        warn('agent: ${e.message}');
      }
    }

    sources.forEach((name, hits) {
      final (real, noise) = partitionKnownNoise(hits);
      final shown = showAll ? hits : real;
      if (shown.isEmpty) {
        out('no errors in $name'
            '${noise.isEmpty ? '' : ' (${noise.length} known-noise line(s) '
                'hidden; --all to show)'}');
        return;
      }
      for (final line in shown) {
        out('$name: ${redactSecrets(line)}'
            '${!showAll || !isKnownNoise(line) ? '' : '  (known noise)'}');
      }
      if (!showAll && noise.isNotEmpty) {
        out('$name: ${noise.length} known-noise line(s) hidden (--all to show)');
      }
    });
    return 0;
  }
}

class AgentCommand extends QaCommand {
  AgentCommand() {
    argParser.addFlag('json', negatable: false, help: 'Emit the raw JSON.');
  }

  @override
  String get name => 'agent';

  @override
  String get description =>
      'Talk to the in-app agent directly: `agent info` (platform, screen, '
      'lifecycle, QA mode, the [qa] lines) or `agent <op> [json-args]`.';

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    final op = rest.isEmpty ? 'info' : rest.first;
    final agent = await ctx.agent();
    final started = DateTime.now();
    Map<String, Object?> args = const {};
    if (rest.length > 1) {
      final decoded = jsonDecode(rest.sublist(1).join(' '));
      if (decoded is! Map<String, Object?>) {
        throw UsageFailure('agent args must be a JSON object');
      }
      args = decoded;
    }
    final result = await agent.op(op, args);
    final took = DateTime.now().difference(started).inMilliseconds;
    if (argResults!['json'] as bool || op != 'info') {
      out(const JsonEncoder.withIndent('  ').convert(result));
      out('($took ms)');
      return 0;
    }
    final info = AgentInfo.fromJson(result);
    out('${info.describe()}  ($took ms round trip, protocol v${info.protocolVersion}, '
        'up ${(info.uptimeMs / 1000).toStringAsFixed(1)} s)');
    out('documents: ${info.documentsPath ?? '?'}');
    if (info.qaLog.isEmpty) {
      out('[qa] lines: none this launch');
    } else {
      for (final line in info.qaLog) {
        out('[qa] $line');
      }
    }
    return 0;
  }
}

class BuildExeCommand extends QaCommand {
  @override
  String get name => 'build-exe';

  @override
  String get description =>
      'Compile tool/qa/qa.dart to the fast binary the wrappers run.';

  @override
  Future<int> run() async {
    final ctx = context;
    final took = await compileQaExe(
      paths: ctx.paths,
      runner: ctx.runner,
      output: ctx.paths.qaExeNew,
    );
    await swapInNewExe(ctx.paths);
    out('${ctx.paths.qaExe}  (${took.inMilliseconds} ms)');
    return 0;
  }
}

class DoctorCommand extends QaCommand {
  DoctorCommand() {
    argParser
      ..addFlag('fix',
          negatable: false,
          help: 'Apply the safe repairs: wake, unphone, kill a leftover '
              'uiautomator, clear a stale run.pid, reap orphaned services. '
              'Never restarts a device, never stops the app, never touches '
              'app data.')
      ..addFlag('json', negatable: false, help: 'Emit the checks as JSON.');
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the toolchain, the device, the app, the agent and the host run '
      'state, and say what to do about anything that is off.';

  @override
  Future<int> run() async {
    var results = await _collect();
    if (argResults!['fix'] as bool) {
      final applied = await _applyFixes(results);
      if (applied.isNotEmpty) {
        for (final line in applied) {
          out('fixed: $line');
        }
        results = await _collect();
      }
    }
    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ')
          .convert(results.map((r) => r.toJson()).toList()));
    } else {
      for (final result in results) {
        out(result.describe());
      }
    }
    return anyFailed(results) ? exitDevice : 0;
  }

  Future<List<CheckResult>> _collect() async {
    final ctx = context;
    final results = <CheckResult>[];
    DeviceRef? selected;
    try {
      selected = await ctx.ref();
    } on QaException catch (e) {
      final adbDevices = await ctx.adbDevices();
      if (ctx.adbFailure != null && ctx.sdk.findAdb() != null) {
        results.add(checkAdbServer(
          adbPath: ctx.sdk.findAdb(),
          failure: ctx.adbFailure,
          deviceCount: adbDevices.length,
        ));
      }
      results.add(CheckResult(
        name: 'device',
        status: CheckStatus.fail,
        detail: e.message,
        fix: 'run `qa devices` to see what is attached',
      ));
    }
    if (selected != null) {
      switch (selected.kind) {
        case DeviceKind.android:
          results.addAll(await _androidChecks(ctx));
        case DeviceKind.ios:
          results.addAll(await _iosChecks(ctx, selected));
        case DeviceKind.macos:
          results.addAll(await _macosChecks(ctx));
      }
    }
    results.addAll(await _hostChecks(ctx, selected?.kind));
    return results;
  }

  Future<List<CheckResult>> _androidChecks(QaContext ctx) async {
    final results = <CheckResult>[];
    final adbPath = ctx.sdk.findAdb();
    final devices = await ctx.adbDevices();
    results.add(checkAdbServer(
      adbPath: adbPath,
      failure: ctx.adbFailure,
      deviceCount: devices.length,
    ));
    results.add(checkDeviceAttached(devices));
    if (!devices.any((d) => d.usable)) return results;

    final adb = await ctx.adb();
    final device = await ctx.android();
    final outputs = await adb.shellBatch(const [
      ShellCommand(['getprop', 'sys.boot_completed']),
      ShellCommand(['settings', 'get', 'global', 'device_provisioned']),
      ShellCommand(['pm', 'path', antaPackage]),
      ShellCommand(['run-as', antaPackage, 'id']),
      ShellCommand.raw(leftoverUiautomatorProbe),
      ShellCommand.raw('df /data | tail -1'),
    ]);
    results.add(checkBootProps(
      bootCompleted: outputs[0],
      provisioned: outputs[1],
    ));
    final probe = await device.probe();
    results.add(checkAwake(probe));
    results.add(checkScreenOverride(probe));
    results.add(checkAppInstalled(pmPath: outputs[2], runAsId: outputs[3]));
    results.add(checkAppRunning(probe, antaPackage));

    final started = DateTime.now();
    var dumped = false;
    try {
      await device.dumpUiXml();
      dumped = true;
    } on QaException {
      dumped = false;
    }
    results.add(checkUiautomator(
      dumped: dumped,
      took: DateTime.now().difference(started),
      leftoverPids: outputs[4],
    ));
    results.add(checkDataSpace(outputs[5]));
    final vmUri = await ctx.recordedVmUri();
    results.add(_agentCheck(
      vmUri,
      vmUri == null
          ? (info: null, failure: null, ms: 0)
          : await ctx.agentInfoOrFailure(refresh: true),
      required: ctx.via == ViaMode.agent,
    ));
    results.add(await _markersCheck(device));
    return results;
  }

  Future<CheckResult> _markersCheck(Device device) async {
    try {
      return checkPendingMarkers(await device.pendingMarkers());
    } on QaException catch (e) {
      return CheckResult(
        name: 'markers',
        status: CheckStatus.warn,
        detail: 'could not list the documents directory: ${e.message}',
      );
    }
  }

  Future<List<CheckResult>> _iosChecks(QaContext ctx, DeviceRef selected) async {
    final results = <CheckResult>[];
    results.add(checkXcrun(available: ctx.simctl != null));
    final device = await ctx.device() as IosDevice;
    results.add(checkSimulator(
      name: device.sim.name,
      state: device.sim.state,
      runtime: device.sim.runtime,
    ));
    results.add(checkAppBundle(
      path: await device.appPath(),
      platform: 'simulator ${device.sim.name}',
      fix: device.installHint,
    ));
    final fetched = await ctx.agentInfoOrFailure(refresh: true);
    results.add(checkAppRunning(await device.probe(fetched.info), device.packageId));
    results.add(_agentCheck(await ctx.recordedVmUri(), fetched, required: true));
    results.add(await _markersCheck(device));
    return results;
  }

  Future<List<CheckResult>> _macosChecks(QaContext ctx) async {
    final results = <CheckResult>[];
    final device = await ctx.device() as MacosDevice;
    results.add(checkAppBundle(
      path: await device.isInstalled() ? device.bundlePath : null,
      platform: 'macOS desktop build',
      fix: device.installHint,
    ));
    final fetched = await ctx.agentInfoOrFailure(refresh: true);
    results.add(checkAppRunning(await device.probe(fetched.info), device.packageId));
    results.add(_agentCheck(await ctx.recordedVmUri(), fetched, required: true));
    if (await device.isInstalled()) results.add(await _markersCheck(device));
    return results;
  }

  CheckResult _agentCheck(
    String? vmUri,
    ({AgentInfo? info, String? failure, int ms}) fetched, {
    required bool required,
  }) {
    if (vmUri == null) {
      final result = checkAgent(
        vmUri: null,
        failure: null,
        roundTripMs: null,
        summary: null,
        qaMode: null,
      );
      return required
          ? result
          : CheckResult.ok('agent', 'not in use (adb path); `--via agent` needs `qa run`/`qa relaunch`');
    }
    final info = fetched.info;
    if (info != null) {
      return checkAgent(
        vmUri: vmUri,
        failure: null,
        roundTripMs: fetched.ms,
        summary: info.describe(),
        qaMode: info.qaMode,
        cloud: info.cloud,
      );
    }
    final result = checkAgent(
      vmUri: vmUri,
      failure: fetched.failure ?? 'no answer',
      roundTripMs: null,
      summary: null,
      qaMode: null,
    );
    return required
        ? result
        : CheckResult(
            name: 'agent',
            status: CheckStatus.warn,
            detail: result.detail,
            fix: 'only matters with `--via agent`; ${result.fix}',
          );
  }

  Future<List<CheckResult>> _hostChecks(QaContext ctx, DeviceKind? kind) async {
    final results = <CheckResult>[];
    final pidFile = File(ctx.paths.runPid);
    final recordedPid = pidFile.existsSync()
        ? int.tryParse(pidFile.readAsStringSync().trim())
        : null;
    final alive =
        recordedPid == null ? false : await isProcessAlive(recordedPid, ctx.runner);
    final orphans = await listOrphanedServices(ctx.runner);
    results.add(checkHostRun(
      recordedPid: recordedPid,
      pidAlive: alive,
      orphanedServices: orphans,
    ));
    results.add(checkDtd(
      dtd: kind == null ? '' : (await ctx.recordedDtdUri() ?? ''),
      runLogTail: tailLines(readRunLog(ctx.paths), lines: 5),
    ));
    final exe = File(ctx.paths.qaExe);
    final decision = decideRebuild(
      aot: true,
      disabled: false,
      exeModified: exe.existsSync() ? exe.statSync().modified : null,
      sourceModified: qaSourceTimes(ctx.paths),
    );
    results.add(checkExeFreshness(
      exists: exe.existsSync(),
      stale: decision.rebuild,
      staleSource: decision.reason,
    ));
    return results;
  }

  Future<List<String>> _applyFixes(List<CheckResult> results) async {
    final ctx = context;
    final applied = <String>[];
    for (final result in results) {
      final fix = result.fixVerb;
      if (fix == null) continue;
      switch (fix) {
        case DoctorFix.wake:
          await (await ctx.android()).wake();
          applied.add('woke the screen and dismissed the keyguard');
        case DoctorFix.unphone:
          await (await ctx.android()).resetScreenOverride();
          applied.add('reset the wm size override');
        case DoctorFix.killUiautomator:
          await (await ctx.adb()).shellLenient([killLeftoverUiautomator]);
          applied.add('killed the leftover uiautomator process');
        case DoctorFix.deleteRunPid:
          final file = File(ctx.paths.runPid);
          if (file.existsSync()) file.deleteSync();
          applied.add('deleted the stale run.pid');
        case DoctorFix.reapServices:
          final reaped = await reapOrphanedServices(ctx.runner);
          if (reaped.isNotEmpty) {
            applied.add('reaped dart development-service ${reaped.join(', ')}');
          }
      }
    }
    return applied;
  }
}
