import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'src/adb.dart';
import 'src/agent_client.dart';
import 'src/apk_build.dart';
import 'src/app_ids.dart';
import 'src/device.dart';
import 'src/device_select.dart';
import 'src/doctor.dart';
import 'src/dump_cache.dart';
import 'src/errors.dart';
import 'src/fleet.dart';
import 'src/gestures.dart';
import 'src/ios_device.dart';
import 'src/log_parse.dart';
import 'src/macos_device.dart';
import 'src/pass_report.dart';
import 'src/paths.dart';
import 'src/agent_protocol.dart';
import 'src/placeholders.dart';
import 'src/seed.dart';
import 'src/poll.dart';
import 'src/process_runner.dart';
import 'src/runner.dart';
import 'src/self_build.dart';
import 'src/shell_batch.dart';
import 'src/shell_words.dart';
import 'src/shots.dart';
import 'src/simctl.dart';
import 'src/suite.dart';
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
  /// [contextFactory] and [commands] are the test seam: a suite runs `pass`
  /// or `steps` over scripted verbs and a context with a fake device,
  /// instead of the full verb set against whatever is attached.
  QaCommandRunner({
    QaContext Function(ArgResults globals)? contextFactory,
    List<Command<int>>? commands,
  })  : _contextFactory = contextFactory ?? QaContext.new,
        super(
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
            'the native one (adb + uiautomator, Android only). `auto` is the '
            'agent wherever it answers on the VM URI a launch recorded, and '
            'adb on Android when it does not; ANTA_QA_VIA overrides. Given '
            'on one step of `steps` or `pass`, it holds for that step only.',
      )
      ..addFlag('verbose', help: 'Echo every process invocation to stderr.');

    if (commands != null) {
      commands.forEach(addCommand);
      return;
    }
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
    addCommand(FlowsCommand());
    addCommand(PassCommand());
    addCommand(BuildCommand());
    addCommand(InstallCommand());
    addCommand(FleetCommand());
    addCommand(ReloadCommand());
    addCommand(RestartCommand());
    addCommand(PerfCommand());
    addCommand(LogCommand());
    addCommand(ErrorsCommand());
    addCommand(AgentCommand());
    addCommand(SetCommand());
    addCommand(BuildExeCommand());
  }

  final QaContext Function(ArgResults globals) _contextFactory;
  QaContext? _context;

  /// Prefix put in front of every output line, so `steps` can indent the
  /// verbs it dispatches without each verb knowing about it.
  String outputPrefix = '';

  /// When set, sees every line a verb prints, with the indent it was printed
  /// under kept apart, so `pass` can keep a log and attribute output to the
  /// step that printed it.
  void Function(String line, {required String prefix, required bool isError})?
      lineSink;

  /// The single context every verb in this process shares.
  ///
  /// One device resolution, one `Device`, one agent connection, one
  /// screen-size cache, one dump cache — which is the whole point of running
  /// several verbs per process.
  QaContext contextFor(ArgResults globals) => _context ??= _contextFactory(globals);

  Future<void> dispose() async => _context?.dispose();
}

/// A resolved target plus the tree it came from and where that tree came from.
class TargetLookup {
  const TargetLookup({
    required this.resolved,
    this.tree,
    this.provenance,
    this.revealed = false,
    this.revealNote,
  });

  final ResolvedTarget resolved;

  /// Whether the app scrolled the node into view before [resolved] was read.
  final bool revealed;

  /// [RevealOutcome.note]: the revealed node was found again by its label,
  /// not by its id.
  final String? revealNote;

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
  /// [paths] roots the harness somewhere other than the package it runs
  /// from: a test's temporary tree.
  QaContext(this.globalResults, {QaPaths? paths}) : _paths = paths;

  final ArgResults globalResults;

  final QaPaths? _paths;
  late final QaPaths paths = _paths ?? QaPaths.locate();
  late final bool verbose = globalResults['verbose'] as bool? ?? false;
  late final ProcessRunner runner = RealProcessRunner(verbose: verbose);
  late final SdkTools sdk = SdkTools();
  late final Simctl? simctl =
      xcrunAvailable() ? Simctl(runner: runner) : null;
  late final ViaMode via = parseViaMode(
    globalResults['via'] as String? ?? Platform.environment['ANTA_QA_VIA'],
  );

  /// A `--via` written on the verb being dispatched, which differs from
  /// [via] only for one step of `steps` or `pass` (`swipe … --via native`,
  /// a real touch where the agent's synthetic one is not enough): the
  /// context is shared by every step, so without this the step's own
  /// choice would be silently dropped.
  ViaMode? stepVia;

  /// Set by `pass` while it gathers a failed flow's evidence: `errors` then
  /// reads `run.log` only when the one `flutter run` slot belongs to this
  /// device, so another device's crash is never filed against the flow.
  bool runLogForThisDeviceOnly = false;

  /// Set by `pass` while it gathers a failed flow's evidence: the logcat
  /// stamp the flow started at, so `errors` reports what this flow
  /// printed rather than what earlier flows on the same app did.
  String? errorsSinceStamp;

  /// Where the context says something about a choice it made on its own
  /// (the `auto` driver falling back); every verb points it at its own
  /// stderr, so a note lands under the step that caused it.
  void Function(String line)? notice;

  List<AdbDevice>? _adbDevices;
  String? adbFailure;
  List<SimDevice>? _simulators;
  String? simctlFailure;
  DeviceRef? _ref;
  Device? _device;
  Adb? _adb;
  AgentClient? _agent;
  UiDriver? _driver;

  /// The `auto` choice on a device with a native layer, made once per
  /// process: a `pass` or `steps` with `--via auto` on some steps would
  /// otherwise pay the 2 s probe on every one of them.
  UiDriver? _autoDriver;

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
    final adopted = AgentClient(vm, appPackage: dev.packageId);
    // A relaunch inside one process (`pass` reseeding between flows) would
    // otherwise leave the cached driver on the client just closed, and an
    // `auto` choice made before any URI was recorded on adb for good. The
    // app was just launched with this agent, so `auto` takes it unprobed.
    if (_driver is AgentClient) {
      _driver = adopted;
    } else if (via == ViaMode.auto) {
      _driver = null;
    }
    if (dev.nativeDriver != null) _autoDriver = adopted;
    return _agent = adopted;
  }

  /// Drops the agent a launch could not bring up, so the next step does
  /// not talk to a closed client: `auto` decides again (and, with no VM
  /// recorded any more, falls back to adb at once), `agent` fails with the
  /// relaunch hint.
  Future<void> forgetAgent() async {
    await _agent?.close();
    _agent = null;
    if (_driver is AgentClient) _driver = null;
    if (_autoDriver is AgentClient) _autoDriver = null;
  }

  /// Empties the agent's error buffer when an agent is already connected;
  /// `pass` does this at each flow's start so a failure's evidence holds
  /// only that flow's errors. Never connects just for this.
  Future<void> clearAgentErrors() async {
    final agent = _agent;
    if (agent == null || agent.vm.isClosed) return;
    try {
      await agent.errors(clear: true).timeout(const Duration(seconds: 3));
    } on QaException {
      return;
    } on TimeoutException {
      return;
    }
  }

  /// The app's alarms Android holds armed on this device (`dumpsys alarm`,
  /// read-only), or null on a platform without that list.
  Future<int?> armedAppAlarms() async {
    final dev = await device();
    if (dev is! AndroidDevice) return null;
    return countArmedAlarms(await dev.adb.shell(['dumpsys', 'alarm']), dev.packageId);
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
    final step = stepVia;
    if (step != null && step != via) return _driverFor(step);
    final existing = _driver;
    if (existing != null) return existing;
    return _driver = await _driverFor(via);
  }

  Future<UiDriver> _driverFor(ViaMode mode) async {
    final dev = await device();
    switch (mode) {
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
        return native;
      case ViaMode.agent:
        return agent();
      case ViaMode.auto:
        final native = dev.nativeDriver;
        if (native == null) return agent();
        final decided = _autoDriver;
        if (decided != null) return decided;
        final recorded = await recordedVmUri();
        final answering = recorded == null ? null : await _agentIfAnswering(recorded);
        final choice = chooseDriver(
          hasNative: true,
          vmRecorded: recorded != null,
          agentAnswers: answering != null,
        );
        if (choice == ViaMode.agent) return _autoDriver = answering!;
        notice?.call(autoFallbackNote(vmRecorded: recorded != null, deviceId: dev.id));
        return _autoDriver = native;
    }
  }

  /// Settles the `auto` choice from an `info` round trip a verb already made
  /// (`doctor` asks the agent for its own check), so it is not probed twice.
  Future<void> decideAutoFrom({required bool agentAnswered}) async {
    final native = (await device()).nativeDriver;
    if (native == null || _autoDriver != null) return;
    final agent = _agent;
    _autoDriver = agentAnswered && agent != null && !agent.vm.isClosed ? agent : native;
  }

  /// The agent when it answers `info` within [_autoProbe] on the [recorded]
  /// VM URI, else null: the `auto` choice must not hang a verb on an app
  /// that has gone away. Unlike [agent] it never searches the platform log
  /// for another URI, and a connection it gives up on is closed, so nothing
  /// it started finishes (or prints) in the middle of a later verb.
  Future<AgentClient?> _agentIfAnswering(String recorded) async {
    final deadline = DateTime.now().add(_autoProbe);
    Duration left() {
      final remaining = deadline.difference(DateTime.now());
      return remaining.isNegative ? Duration.zero : remaining;
    }

    final existing = _agent;
    VmServiceClient? opened;
    try {
      final AgentClient client;
      if (existing != null && !existing.vm.isClosed) {
        client = existing;
      } else {
        opened = await VmServiceClient.connect(recorded, timeout: _autoProbe);
        client = AgentClient(opened, appPackage: (await device()).packageId);
      }
      await client.info().timeout(left());
      return _agent = client;
    } on QaException {
      await opened?.close();
      return null;
    } on TimeoutException {
      await opened?.close();
      return null;
    }
  }

  static const Duration _autoProbe = Duration(seconds: 2);

  /// The `driver=` word `state` and `doctor` print.
  Future<String> driverLabel() async {
    final dev = await device();
    if (dev.nativeDriver == null) return 'agent';
    return switch (via) {
      ViaMode.native => 'adb',
      ViaMode.agent => 'agent',
      ViaMode.auto => '${await driver() is AgentClient ? 'agent' : 'adb'} (auto)',
    };
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
    if (cache) writeDumpCache(paths, (await ref()).id, captured.raw);
    return captured.tree;
  }

  /// The device id when one resolves, for a verb that can still work from
  /// the shared files without a device (`dump --cached`).
  Future<String?> deviceIdOrNull() async {
    try {
      return (await ref()).id;
    } on QaException {
      return null;
    }
  }

  /// Where screenshots land when a verb is not told otherwise: `qa pass`
  /// points this at its own run directory so a flow's `--shot` stays with
  /// the report it belongs to.
  String? shotsDirOverride;

  /// The scale a screenshot takes when its verb is not told one: `qa pass`
  /// sets [passShotScale] for its run.
  double? shotScaleOverride;

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

  /// Resolves a target for a verb that acts on it, dumping only when the
  /// target form needs a tree; a match out of view — a label, an `id:`, or
  /// a `#N` whose dump carries its semantics id — is brought in first on
  /// the agent path (see [resolveOnScreen]). [reveal] off is for a verb
  /// that only reads (`text`), which must not scroll the app.
  Future<TargetLookup> lookup(String target, {int? nth, bool reveal = true}) async {
    if (isPointTarget(target)) {
      return TargetLookup(
        resolved: const TargetResolver(UiTree([])).resolve(target),
      );
    }
    if (isIndexTarget(target)) {
      final cached = readDumpCache(paths, await deviceIdOrNull());
      if (cached == null) {
        throw TargetFailure(
          'no previous dump — run `dump` first or target by label',
        );
      }
      final tree = cached.tree;
      final provenance = '($target from the dump '
          '${describeAge(cached.ageFrom(DateTime.now()))})';
      if (!reveal) {
        return TargetLookup(
          resolved: TargetResolver(tree).resolve(target, nth: nth),
          tree: tree,
          provenance: provenance,
        );
      }
      // The new dump stays out of the cache: the `#N` numbers the reader
      // holds mean the dump they read.
      final outcome = await resolveOnScreen(target, tree,
          nth: nth, redump: () => dump(cache: false));
      if (outcome.revealed && !outcome.onScreen) {
        throw TargetFailure(offScreenAfterReveal(target));
      }
      return TargetLookup(
        resolved: outcome.resolved,
        tree: outcome.tree,
        provenance: provenance,
        revealed: outcome.revealed,
      );
    }
    final tree = await dump();
    if (!reveal) {
      return TargetLookup(resolved: TargetResolver(tree).resolve(target, nth: nth), tree: tree);
    }
    final outcome = await resolveOnScreen(target, tree, nth: nth);
    if (outcome.revealed && !outcome.onScreen) {
      throw TargetFailure(offScreenAfterReveal(target));
    }
    return TargetLookup(
      resolved: outcome.resolved,
      tree: outcome.tree,
      revealed: outcome.revealed,
      revealNote: outcome.note,
    );
  }

  /// [resolveRevealing] with the reveal step the current driver has: the
  /// agent's `reveal` op, or none on the adb path.
  Future<RevealOutcome> resolveOnScreen(
    String target,
    UiTree tree, {
    int? nth,
    Future<UiTree> Function()? redump,
  }) async {
    final current = await driver();
    return resolveRevealing(
      target,
      tree,
      nth: nth,
      reveal: current is AgentClient ? (node) => _reveal(current, node) : null,
      redump: redump ?? dump,
    );
  }

  static Future<void> _reveal(AgentClient agent, UiNode node) async {
    await agent.requireCurrentProtocol();
    final id = node.semanticsId;
    if (id == null) {
      throw DeviceFailure('the dump names no semantics id for '
          '${node.describe()}, so the app cannot be asked to show it');
    }
    await agent.reveal(id);
  }

  /// Polls the screen until [wanted] appears (or disappears) or time runs
  /// out, by the presence rule of [presentMatch].
  Future<WaitOutcome> pollFor(
    String wanted, {
    required bool gone,
    required Duration timeout,
    int? nth,
  }) async {
    final interval = (await driver()).pollInterval;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final tree = (await dumpWhileStarting(until: deadline)).tree;
      final found = presentMatch(tree, wanted, gone: gone, nth: nth);
      final done = (gone && found == null) ||
          (!gone && found != null) ||
          !DateTime.now().isBefore(deadline);
      if (done) {
        final captured = await dumpWhileStarting(
          until: DateTime.now().add(startingGrace),
          cache: true,
        );
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

  /// A fresh dump from the driver that reads an app still starting
  /// ([isAppStartingUp]: no semantics tree yet, no first frame yet) as
  /// "not yet" and asks again until [until]; past it, that failure stands.
  /// A `wait` right after a relaunch otherwise failed at once instead of
  /// polling for its timeout. [cache] keeps it as the dump later `#N`
  /// targets mean, as [dump] does.
  Future<UiDump> dumpWhileStarting({required DateTime until, bool cache = false}) async {
    while (true) {
      try {
        final captured = await (await driver()).dump();
        if (cache) writeDumpCache(paths, (await ref()).id, captured.raw);
        return captured;
      } on QaException catch (e) {
        if (!isAppStartingUp(e) || !DateTime.now().isBefore(until)) rethrow;
      }
      await Future<void>.delayed(_startingRetry);
    }
  }

  static const Duration _startingRetry = Duration(milliseconds: 250);

  /// How long a verb with no timeout of its own (`scroll-to`), or a
  /// poll's closing dump, rides out an app still starting.
  static const Duration startingGrace = Duration(seconds: 10);

  Future<void> dispose() async {
    await _agent?.close();
  }
}

abstract class QaCommand extends Command<int> {
  QaContext get context {
    final globals = globalResults!;
    final ctx = (runner! as QaCommandRunner).contextFor(globals);
    ctx.stepVia =
        globals.wasParsed('via') ? parseViaMode(globals['via'] as String?) : null;
    ctx.notice = warn;
    return ctx;
  }

  String get _prefix => (runner! as QaCommandRunner).outputPrefix;

  void out(String line) => _write(stdout, line);

  void warn(String line) => _write(stderr, line);

  void _write(IOSink sink, String line) {
    final tee = (runner! as QaCommandRunner).lineSink;
    if (tee != null) {
      for (final part in line.split('\n')) {
        tee(part, prefix: _prefix, isError: identical(sink, stderr));
      }
    }
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
        out(gone ? 'gone: "$wanted"' : 'found: ${describeFound(outcome.found!)}');
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
        scale: ctx.shotScaleOverride ?? defaultShotScale,
        outDir: ctx.shotsDirOverride,
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

/// The node `wait` (or, with [gone], `wait --gone`) counts as present in one
/// poll, or null. A node the framework holds scrolled out of view is
/// present: it is on the page, and an acting verb brings it in. One that is
/// only outside the screen (a route still sliding in) is not yet, so a wait
/// keeps polling. Gone means no node matches at all: an ambiguous label is
/// still there, whichever of its matches is meant.
ResolvedTarget? presentMatch(
  UiTree tree,
  String wanted, {
  required bool gone,
  int? nth,
}) {
  final resolver = TargetResolver(tree);
  try {
    final found = resolver.resolve(wanted, nth: nth);
    final node = found.node;
    if (!gone && node != null && !node.countsAsPresent) return null;
    return found;
  } on TargetFailure catch (e) {
    if (!e.message.contains('ambiguous')) return null;
    if (gone) return resolver.fromNode(resolver.matchingNodes(wanted).first);
    throw TargetFailure(
      'wait cannot settle on "$wanted": ${e.message}\n'
      'Waiting would never resolve this — pick one match with --nth, '
      'or target by id:',
    );
  }
}

/// A present match as `wait` and `--wait` report it, saying so when it is
/// only in the tree, scrolled out of view.
String describeFound(ResolvedTarget found) =>
    '${found.description}${scrolledOutNote(found.node)}';

/// The suffix every presence report puts after a match that is in the tree
/// but not on screen, so a passing check still says where the node was.
String scrolledOutNote(UiNode? node) =>
    (node?.hidden ?? false) ? '  (scrolled out of view)' : '';

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
    final driverName = await ctx.driverLabel();

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
      final booting = await _emulatorStartedHere(ctx, avd);
      if (booting == null) {
        throw DeviceFailure(
          '${attached.map((d) => unusableDeviceMessage(d.serial, d.state)).join('; ')}. '
          'Nothing here can fix that: a wedged guest needs the owner to close '
          'the emulator window and cold-boot it.',
        );
      }
      out('emulator pid ${booting.pid} (started by this tool) is still booting — waiting');
      await awaitEmulatorBoot(ctx, bare, booting.pid, booting.avd, progress: warn);
    } else {
      final started = await _startEmulator(ctx, avd);
      await awaitEmulatorBoot(ctx, bare, started.pid, started.avd, progress: warn);
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
  ///
  /// Without `--avd` only `emulator.pid` counts — the owner's path, where
  /// the AVD was never named — never a fleet emulator's pid file: waiting
  /// on another AVD's boot would report the wrong device as ready.
  Future<({int pid, String? avd})?> _emulatorStartedHere(
    QaContext ctx,
    String? avd,
  ) async {
    final file = File(bootPidPath(ctx.paths, avd));
    if (!file.existsSync()) return null;
    final pid = int.tryParse(file.readAsStringSync().trim());
    if (pid == null || !await isProcessAlive(pid, ctx.runner)) return null;
    return (pid: pid, avd: avd == null || avd.isEmpty ? null : avd);
  }

  /// Starts the emulator through the same wrapper machinery `run` uses, so its
  /// output lands in a file this tool can read back when the boot fails.
  ///
  /// Its log and pid are keyed the way it was asked for — by AVD with
  /// `--avd`, under the plain `emulator.*` names without — so a second
  /// `boot` asked the same way finds the one still coming up; the wrapper
  /// script is always per AVD, so two boots never rewrite each other's.
  Future<({int pid, String? avd})> _startEmulator(
    QaContext ctx,
    String? requested,
  ) async {
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
    final keyed = requested == null || requested.isEmpty ? null : avd;
    ctx.paths.ensureBuildQa();
    final logPath = ctx.paths.emulatorLogFor(keyed);
    final errPath = ctx.paths.emulatorErrFor(keyed);
    File(logPath).writeAsStringSync('');
    File(errPath).writeAsStringSync('');
    final wrapper = writeWrapperScript(
      paths: ctx.paths,
      baseName: emulatorWrapperName(avd),
      executable: emulator,
      arguments: [
        '-avd',
        avd,
        if (argResults!['cold'] as bool) '-no-snapshot-load',
      ],
      posixLogPath: logPath,
    );
    final pid = await startWrapperDetached(
      paths: ctx.paths,
      wrapper: wrapper,
      logPath: logPath,
      errPath: errPath,
      pidPath: bootPidPath(ctx.paths, keyed),
    );
    out('starting emulator $avd (pid $pid, log $logPath)');
    return (pid: pid, avd: keyed);
  }
}

/// The pid file `boot` records and waits on: the AVD's own with `--avd`,
/// the plain `emulator.pid` without — never another AVD's, so a plain
/// `boot` cannot mistake a fleet emulator coming up for the owner's.
String bootPidPath(QaPaths paths, String? avd) =>
    paths.emulatorPidFor(avd == null || avd.isEmpty ? null : avd);

/// The wrapper script one AVD boots through, shared by `boot` and
/// `fleet boot`: one per AVD, so two boots never rewrite each other's.
String emulatorWrapperName(String avd) => 'emulator_cmd_${QaPaths.safeId(avd)}';

/// Waits for the guest, failing the moment the emulator says it will not
/// come up or its process disappears.
///
/// With [serial] only that device counts, so one fleet boot is not
/// satisfied by another emulator that is already up. [fatalLogLines] off
/// leaves the verdict to the process: several emulators starting at once
/// log hypervisor lines that look fatal and are not (the WHPX trap), and
/// one that really will not come up exits. [pid] null skips the process
/// check for an emulator this tool did not start.
Future<void> awaitEmulatorBoot(
  QaContext ctx,
  Adb bare,
  int? pid,
  String? avd, {
  String? serial,
  bool fatalLogLines = true,
  required void Function(String line) progress,
}) async {
  final started = DateTime.now();
  final deadline = started.add(const Duration(minutes: 6));
  var lastProgress = started;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final log = readEmulatorLog(ctx.paths, avd);
    final fatal = fatalLogLines ? emulatorFatalLine(log) : null;
    if (fatal != null) {
      throw DeviceFailure(
        'the emulator refused to start: $fatal\n${tailLines(log, lines: 15)}',
      );
    }
    if (pid != null && !await isProcessAlive(pid, ctx.runner)) {
      throw DeviceFailure(
        'the emulator process (pid $pid) exited before the device came up.\n'
        '${tailLines(log, lines: 15)}',
      );
    }
    final all = await bare.devices();
    final devices =
        serial == null ? all : all.where((d) => d.serial == serial).toList();
    final usable = devices.where((d) => d.usable).toList();
    final state = usable.isNotEmpty
        ? 'device up, waiting for boot_completed'
        : (devices.isEmpty
            ? 'device offline, still waiting'
            : 'device ${devices.first.state}, still waiting');
    if (DateTime.now().difference(lastProgress).inSeconds >= 15) {
      lastProgress = DateTime.now();
      progress('boot: ${DateTime.now().difference(started).inSeconds} s — $state');
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
    '${tailLines(readEmulatorLog(ctx.paths, avd), lines: 15)}',
  );
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
              '(relative paths resolve against the package root). '
              '{{today+N}} / {{day+N}} / {{weekday+N}} placeholders are '
              'resolved against the run\'s clock first.')
      ..addMultiOption('setting',
          help: 'Override a settings key in the seed before it is pushed, as '
              'key=value; repeatable. E.g. --setting locale=de '
              '--setting theme_mode=dark.');
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
      final prepared = prepareSeed(
        ctx.paths,
        path,
        deviceId: device.id,
        settings: argResults!['setting'] as List<String>,
      );
      await device.pushSeed(prepared.path);
      out('qa_seed.json pushed from $path${prepared.describe()}');
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
      // The client of the app just stopped is closed; left cached as the
      // driver it would fail every later step of this process.
      await ctx.forgetAgent();
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
      await ctx.forgetAgent();
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
    final started = DateTime.now();
    final code = await launch('run');
    if (device is AndroidDevice) await _recordInstalled(ctx, device, started);
    await reportQaMarkers(
      ctx: ctx,
      stamp: File(ctx.paths.runStamp).readAsStringSync().trim(),
      includeRunLog: true,
    );
    return code;
  }

  /// `flutter run` built and installed the debug APK, so the device now
  /// carries this tree, not whatever `qa install` put there before: without
  /// this record a later `pass` warned about a stale build that was not.
  Future<void> _recordInstalled(QaContext ctx, Device device, DateTime started) async {
    final extra = argResults!['define'] as List<String>;
    installedRecordForRun(
      paths: ctx.paths,
      git: await gitBuildState(ctx.runner, ctx.paths.projectRoot),
      runStarted: started,
      defines: [if (argResults!['qa'] as bool) ...qaDefines, ...extra],
      installedAt: DateTime.now(),
    ).write(ctx.paths.installedJsonFor(device.id));
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
        : !argResults!.wasParsed('scale') && ctx.shotScaleOverride != null
            ? ctx.shotScaleOverride!
            : (double.tryParse(argResults!['scale'] as String) ??
                (throw UsageFailure('--scale must be a number')));
    final via = parseViaMode(argResults!['via'] as String?);
    final path = await captureShot(
      () => ctx.screenshotPng(via: via),
      ctx.paths,
      name: rest.isEmpty ? 'shot' : rest.first,
      scale: scale,
      outDir: argResults!['out'] as String? ?? ctx.shotsDirOverride,
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
          help: "Print the device's last dump from "
              'build/qa/last_dump_<device>.txt without touching the device.');
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
      final cached = readDumpCache(ctx.paths, await ctx.deviceIdOrNull());
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
    final hidden = tree.nodes.where((n) => n.outOfView).length;
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

  Future<TargetLookup> target({bool reveal = true}) async {
    final lookup = await context.lookup(requireRest('a target'),
        nth: intOption('nth'), reveal: reveal);
    if (lookup.revealed) out('revealed: ${lookup.resolved.description}');
    final note = lookup.revealNote;
    if (note != null) warn('note: $note');
    return lookup;
  }
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
    if (node != null && node.outOfView) {
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
  String get description =>
      'Print the text of a target node, scrolled out of view or not; it '
      'never scrolls the app.';

  @override
  Future<int> run() async {
    final lookup = await target(reveal: false);
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
  String get description =>
      'Poll the accessibility tree until a target appears (a row scrolled '
      'out of view counts), or with --gone until no node matches at all.';

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
      out(gone ? 'gone: "$wanted"' : 'found: ${describeFound(outcome.found!)}');
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
  /// The longest a swipe's fling is waited out before the next dump: a
  /// strong fling under iOS physics runs about 1.5 s, and the agent returns
  /// early the moment the frames stop.
  static const int _flingSettleMs = 2500;

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
  String get description =>
      'Bring a target on screen: on the agent path the app is first asked to '
      'scroll it into view, then (or on adb) swipes inside a scrollable '
      'until it shows up.';

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
    var revealTried = false;
    final starting = DateTime.now().add(QaContext.startingGrace);
    for (var attempt = 0; attempt <= maxSwipes; attempt++) {
      var screen = tree =
          (await ctx.dumpWhileStarting(until: starting, cache: true)).tree;
      if (attempt == 0) warnIfForeign(screen);
      try {
        final found = TargetResolver(screen).resolve(wanted, nth: nth);
        if (found.node == null || !found.node!.outOfView) {
          out('found after $attempt swipe(s): ${found.description}');
          return 0;
        }
        // A row the tree already holds is one `reveal` away; only a row
        // beyond the cache extent, absent from the tree, needs the swipes.
        if (!revealTried && driver is AgentClient) {
          revealTried = true;
          try {
            final outcome = await ctx.resolveOnScreen(wanted, screen, nth: nth);
            screen = tree = outcome.tree;
            final note = outcome.note;
            if (note != null) warn('note: $note');
            if (outcome.onScreen) {
              out('found after reveal: ${outcome.resolved.description}');
              return 0;
            }
          } on DeviceFailure catch (e) {
            warn('scroll-to: ${e.message}; swiping instead');
          }
        }
      } on TargetFailure catch (e) {
        if (e.message.contains('ambiguous')) rethrow;
      }
      if (attempt == maxSwipes) break;
      final scrollable = container == null
          ? screen.firstScrollable
          : TargetResolver(screen).resolve(container).node;
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
      // The agent's swipe op settles for at most 500 ms and a fling under
      // iOS physics outlives that: the dump would then see a row the fling is
      // still carrying (so the row a flow found ends up at the viewport's
      // edge, or off it) and the next tap's pointer-down stops the list
      // instead of pressing the row (15_templates on the iPhone 17 Pro
      // simulator, 2026-10-03). The settle op returns as soon as no frame is
      // scheduled, so a scroll that stopped on its own costs nothing here.
      final agent = driver.name == 'agent' ? await ctx.agentOrNull() : null;
      if (agent != null) {
        await agent.settle(ms: _flingSettleMs);
      } else {
        await Future<void>.delayed(
          driver.name == 'agent'
              ? const Duration(milliseconds: 150)
              : const Duration(milliseconds: 400),
        );
      }
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
    final nth = intOption('nth');
    var from = await ctx.lookup(rest[0], nth: nth);
    if (from.revealed) out('revealed: ${from.resolved.description}');
    final fromNote = from.revealNote;
    if (fromNote != null) warn('note: $fromNote');
    warnIfForeign(from.tree);
    final TargetLookup to;
    if (isPointTarget(rest[1]) || isIndexTarget(rest[1])) {
      to = await ctx.lookup(rest[1]);
    } else {
      final outcome =
          await ctx.resolveOnScreen(rest[1], from.tree ?? await ctx.dump());
      if (outcome.revealed) {
        if (!outcome.onScreen) throw TargetFailure(offScreenAfterReveal(rest[1]));
        out('revealed: ${outcome.resolved.description}');
        final toNote = outcome.note;
        if (toNote != null) warn('note: $toNote');
        from = afterDropReveal(rest[0], from, outcome.tree, nth, note: (line) => warn('note: $line'));
      }
      to = TargetLookup(resolved: outcome.resolved, tree: outcome.tree);
    }
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

  /// Bringing the drop target into view scrolled the screen under the
  /// dragged row, so its point is read again from the tree after the scroll:
  /// by the row's semantics id, which the scroll cannot reassign the way it
  /// reshuffles which duplicate a label and `--nth` land on. Only a row
  /// whose id is gone (or a uiautomator row, which has none) falls back to
  /// its label, once, and [note] says so.
  static TargetLookup afterDropReveal(
    String target,
    TargetLookup before,
    UiTree tree,
    int? nth, {
    required void Function(String line) note,
  }) {
    if (isPointTarget(target)) return before;
    final id = before.resolved.node?.semanticsId;
    final byId = id == null ? null : tree.bySemanticsId(id);
    final ResolvedTarget again;
    if (byId != null) {
      again = TargetResolver(tree).fromNode(byId);
    } else if (isIndexTarget(target)) {
      throw TargetFailure('revealing the drop target scrolled the screen, so '
          '$target from the earlier dump no longer names a row — name the '
          'dragged row by label or id');
    } else {
      if (id != null) {
        note('the dragged row (semantics id $id) is not in the new dump; '
            '"$target" was resolved again by its label');
      }
      again = TargetResolver(tree).resolve(target, nth: nth);
    }
    if (again.node?.outOfView ?? false) {
      throw TargetFailure('"$target" and the drop target do not fit on '
          'screen together — drag in two steps');
    }
    return TargetLookup(resolved: again, tree: tree);
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
      outDir: argResults!['out'] as String? ?? ctx.shotsDirOverride,
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
      ..addMultiOption('absent',
          help: 'A target no node may match, scrolled out of view included. '
              'Repeatable.')
      ..addOption('timeout', defaultsTo: '5', help: 'Seconds to keep re-checking.');
  }

  @override
  String get name => 'expect';

  @override
  String get description =>
      'Assert several targets are present (a row scrolled out of view '
      'counts) and --absent ones match nothing, in one call; exits 2 listing '
      'every miss.';

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
      tree = (await ctx.dumpWhileStarting(until: deadline, cache: true)).tree;
      misses = expectMisses(tree, present: present, absent: absent);
      if (misses.isEmpty || !DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(interval);
    }
    warnIfForeign(tree);
    for (final target in present) {
      if (!misses.any((m) => m.startsWith('missing "$target"'))) {
        out('ok  present  "$target"${scrolledOutNote(_matchOf(tree, target))}');
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

  /// The one node [target] names, or null when it is ambiguous or missing.
  static UiNode? _matchOf(UiTree tree, String target) {
    try {
      return TargetResolver(tree).resolve(target).node;
    } on TargetFailure {
      return null;
    }
  }
}

/// Which expectations a tree does not satisfy, worded for the failure line.
///
/// Presence is "some match counts as present" (see [UiNode.countsAsPresent]),
/// scrolled out of view or not: Flutter keeps a row the sheet has scrolled
/// past in the tree, and a check that counted it missing made flows fail on
/// the fold. An ambiguous label is present when any of its matches is. So
/// `--absent` means no node matches at all, not merely off screen, and an
/// ambiguous label is never absent.
List<String> expectMisses(
  UiTree tree, {
  required List<String> present,
  required List<String> absent,
}) {
  final resolver = TargetResolver(tree);
  final misses = <String>[];
  for (final target in present) {
    if (isPointTarget(target)) continue;
    if (!resolver.matchingNodes(target).any((n) => n.countsAsPresent)) {
      misses.add('missing "$target"');
    }
  }
  for (final target in absent) {
    final matches = resolver.matchingNodes(target);
    if (matches.isEmpty) continue;
    misses.add(matches.every((n) => n.outOfView)
        ? 'unexpected "$target" is present (scrolled out of view)'
        : 'unexpected "$target" is on screen');
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

/// What one step of a step file did, for a caller that keeps a record.
class StepRun {
  const StepRun({
    required this.n,
    required this.line,
    required this.code,
    required this.elapsed,
    this.message,
  });

  /// 1-based position among the step lines.
  final int n;

  /// The line as run, placeholders resolved.
  final String line;
  final int code;
  final Duration elapsed;

  /// The failure's own message, when the verb threw one.
  final String? message;
}

/// The step loop `steps` runs, shared with `pass` so a pass flow behaves
/// exactly like `steps --file` while its caller times and records each step.
mixin StepLoop on QaCommand {
  /// Runs [steps] in order, printing `[n/N] line` before each and stopping
  /// at the first failure unless [keepGoing]; returns the first non-zero
  /// code. [onStepStart] fires after the header line, [onStepEnd] after the
  /// verb returned or failed.
  Future<int> runStepLines(
    List<String> steps, {
    required bool keepGoing,
    void Function(int n, String line)? onStepStart,
    void Function(StepRun run)? onStepEnd,
  }) async {
    final qaRunner = runner! as QaCommandRunner;
    var firstFailure = 0;
    for (var index = 0; index < steps.length; index++) {
      var line = steps[index];
      List<String> words;
      QaException? malformed;
      try {
        line = resolvePlaceholders(line);
        words = splitShellWords(line);
        if (words.isNotEmpty && words.first == 'steps') {
          throw UsageFailure('a step cannot itself be `steps`');
        }
      } on QaException catch (e) {
        // A line that cannot be run is that step failing, not the run
        // ending: a pass must still reach its other flows and its report.
        words = const [];
        malformed = e;
      }
      if (words.isEmpty && malformed == null) continue;
      out('[${index + 1}/${steps.length}] $line');
      onStepStart?.call(index + 1, line);
      final started = DateTime.now();
      final (code, message) = malformed == null
          ? await runOneStep(qaRunner, words)
          : _malformedStep(qaRunner, malformed);
      onStepEnd?.call(StepRun(
        n: index + 1,
        line: line,
        code: code,
        elapsed: DateTime.now().difference(started),
        message: message,
      ));
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

  /// Dispatches one verb indented under its step line; a failure becomes
  /// its exit code and message instead of ending the process.
  Future<(int, String?)> runOneStep(
    QaCommandRunner qaRunner,
    List<String> words,
  ) async {
    final previous = qaRunner.outputPrefix;
    qaRunner.outputPrefix = '$previous  ';
    try {
      return (await qaRunner.run(words) ?? 0, null);
    } on UsageException catch (e) {
      warn('qa: ${e.message}');
      return (exitUsage, e.message);
    } on QaException catch (e) {
      warn('qa: ${e.message}');
      return (e.code, e.message);
    } on Exception catch (e) {
      // A socket or file error a verb did not translate is still one
      // step's failure; ending the process here would lose a pass's report.
      warn('qa: $e');
      return (exitDevice, '$e');
    } finally {
      qaRunner.outputPrefix = previous;
    }
  }

  /// Reports a step line that never reached a verb, indented like one.
  (int, String?) _malformedStep(QaCommandRunner qaRunner, QaException e) {
    final previous = qaRunner.outputPrefix;
    qaRunner.outputPrefix = '$previous  ';
    try {
      warn('qa: ${e.message}');
    } finally {
      qaRunner.outputPrefix = previous;
    }
    return (e.code, e.message);
  }
}

class StepsCommand extends QaCommand with StepLoop {
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
      'Run several verbs in one process, sharing the device connection. '
      '{{today+N}}, {{day+N}} and {{weekday+N}} in a step resolve against '
      'the run\'s clock (see tool/qa/src/placeholders.dart).';

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

    return runStepLines(
      steps,
      keepGoing: argResults!['keep-going'] as bool,
    );
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

/// `qa flows calendar` — every `*.txt` under `tool/qa/flows/calendar/` but
/// the suite's own `_*.txt`, in name order, each as its own `steps --file`.
/// It runs them on one shared state; `qa pass` is the reseeding runner.
class FlowsCommand extends QaCommand {
  FlowsCommand() {
    argParser
      ..addFlag('keep-going',
          negatable: false,
          help: 'Run every flow even after one fails; exit with the first '
              'non-zero code.')
      ..addFlag('list',
          negatable: false, help: 'List the flows without running them.')
      ..addFlag('prelude',
          negatable: false,
          help: "Run the suite's prelude before a single flow too (it runs "
              'by itself for a whole directory and for the first flow).');
  }

  @override
  String get name => 'flows';

  @override
  String get description =>
      'Run every step file of a flow directory under tool/qa/flows/ in name '
      'order (e.g. `qa flows calendar`), or one flow by its file name '
      '(`qa flows calendar/03_dates`).';

  @override
  String get invocation => 'qa flows <directory>[/<flow>] [--keep-going] [--prelude]';

  /// The step files a flow argument names, in name order.
  static List<File> resolveFlows(String flowsDir, String argument) {
    final normalized = argument.replaceAll('\\', '/');
    final slash = normalized.indexOf('/');
    final dirName = slash < 0 ? normalized : normalized.substring(0, slash);
    final flowName = slash < 0 ? null : normalized.substring(slash + 1);
    final dir = Directory('$flowsDir${Platform.pathSeparator}$dirName');
    if (!dir.existsSync()) {
      final known = Directory(flowsDir).existsSync()
          ? Directory(flowsDir)
              .listSync()
              .whereType<Directory>()
              .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
              .toList()
          : const <String>[];
      throw UsageFailure(
        'no flow directory "$dirName" under $flowsDir'
        '${known.isEmpty ? '' : ' (known: ${known.join(', ')})'}',
      );
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => isFlowFileName(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (flowName == null) {
      if (files.isEmpty) throw UsageFailure('no *.txt flows in ${dir.path}');
      return files;
    }
    final wanted = flowName.endsWith('.txt') ? flowName : '$flowName.txt';
    final match = files.where((f) => f.uri.pathSegments.last == wanted);
    if (match.isEmpty) {
      throw UsageFailure(
        'no flow "$flowName" in ${dir.path} (have: '
        '${files.map((f) => f.uri.pathSegments.last).join(', ')})',
      );
    }
    return match.toList();
  }

  /// The suite's prelude when [argument] names a whole directory or the
  /// suite's first flow (in name order), or any single flow with [force]:
  /// the first flow starts where the prelude ends, so the documented
  /// `relaunch --fresh --seed …` then `flows calendar/00_open` still lands
  /// on the calendar. Any other single flow runs from wherever the app is.
  static File? preludeFor(String flowsDir, String argument, {bool force = false}) {
    final normalized = argument.replaceAll('\\', '/');
    final slash = normalized.indexOf('/');
    final suite = slash < 0 ? normalized : normalized.substring(0, slash);
    final manifest = File(joinPath(flowsDir, [suite, SuiteManifest.fileName]));
    if (!manifest.existsSync()) return null;
    final prelude = SuiteManifest.parse(manifest.readAsStringSync(), suite: suite).prelude;
    if (prelude == null) return null;
    if (slash >= 0 && !force) {
      final flow = flowNameOf(normalized.substring(slash + 1));
      final names = Directory(joinPath(flowsDir, [suite]))
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(isFlowFileName)
          .map(flowNameOf)
          .toList()
        ..sort();
      if (names.isEmpty || names.first != flow) return null;
    }
    return File(joinPath(flowsDir, [suite, prelude]));
  }

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageFailure('flows takes exactly one argument, the flow directory');
    }
    final files = resolveFlows(ctx.paths.flowsDir, rest.single);
    if (argResults!['list'] as bool) {
      for (final file in files) {
        out(file.path);
      }
      return 0;
    }
    final qaRunner = runner! as QaCommandRunner;
    final prelude = preludeFor(ctx.paths.flowsDir, rest.single,
        force: argResults!['prelude'] as bool);
    if (prelude != null) {
      out('=== prelude: ${prelude.uri.pathSegments.last}');
      final code = await qaRunner.run(['steps', '--file', prelude.path]) ?? 0;
      if (code != 0) {
        out('flows: the prelude failed (exit $code), no flow ran');
        return code;
      }
    }
    final keepGoing = argResults!['keep-going'] as bool;
    var firstFailure = 0;
    final failed = <String>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final label = file.uri.pathSegments.last;
      out('=== flow ${index + 1}/${files.length}: $label');
      final started = DateTime.now();
      final code = await qaRunner.run(['steps', '--file', file.path]) ?? 0;
      final took = DateTime.now().difference(started).inMilliseconds;
      out('=== $label: ${code == 0 ? 'ok' : 'FAILED (exit $code)'} in $took ms');
      if (code == 0) continue;
      failed.add(label);
      if (firstFailure == 0) firstFailure = code;
      if (!keepGoing) {
        out('flows: stopped at ${index + 1}/${files.length}');
        return code;
      }
    }
    if (failed.isNotEmpty) {
      out('flows: ${failed.length} of ${files.length} failed: ${failed.join(', ')}');
    } else {
      out('flows: all ${files.length} passed');
    }
    return firstFailure;
  }
}

/// `qa pass calendar` — a whole suite in one call, every flow from the
/// state its `_suite.txt` names, with a `report.json` an agent can triage
/// and `--shard i/n` to spread one suite over several devices.
/// How `pass` left its device: the closing relaunch's time, the app's
/// alarms still armed (null when not counted), and why it failed, if it did.
typedef _Quiet = ({int ms, int? alarms, String? failure});

class PassCommand extends QaCommand with StepLoop {
  PassCommand() {
    argParser
      ..addMultiOption('only',
          splitCommas: false,
          help: 'Run only this flow (its file name, with or without .txt). '
              'Repeatable.')
      ..addOption('shard',
          help: 'i/n: run the flows whose 0-based index mod n is i-1, for one '
              'of n devices. Refused when the suite says shard=no.')
      ..addFlag('reseed',
          defaultsTo: true,
          help: 'Put the fixture back as the manifest says; --no-reseed runs '
              'every flow on what the app holds now.')
      ..addFlag('stop-on-fail',
          negatable: false, help: 'Skip the remaining flows after a failure.')
      ..addFlag('keep-state',
          negatable: false,
          help: 'Leave the app as the last flow left it, seed and armed '
              'alarms included (to look at a red flow by hand), instead of '
              'ending with `relaunch --fresh`.')
      ..addOption('json', help: 'Also write the report to this path.')
      ..addOption('label', help: 'Free text stored in the report.')
      ..addOption('summary',
          help: 'Print the summary of an existing report.json and exit.')
      ..addFlag('merge',
          negatable: false,
          help: 'Merge the report.json files given as arguments (the shards '
              'of one suite) into one report under build/qa/pass and print '
              'it; warns about missing or repeated flows.');
  }

  @override
  String get name => 'pass';

  @override
  String get description =>
      'Run a flow suite under tool/qa/flows/ as one device pass: reseed per '
      'its _suite.txt, run its prelude, keep going past a failure, end with '
      'the app on an empty QA database so no seeded alarm rings afterwards, '
      'and write build/qa/pass/<suite>_<stamp>_<device>/report.json.';

  @override
  String get invocation =>
      'qa pass <suite>[/<flow>] [--only <flow>]… [--shard i/n] [--no-reseed] '
      '[--stop-on-fail] [--keep-state] [--json <path>] [--label <text>]\n'
      '       qa pass --summary <report.json>\n'
      '       qa pass --merge <a.json> <b.json>…';

  /// Lines a step printed, while one is running; stderr lines marked `! `.
  List<String>? _capture;

  /// How far before its start a flow's logcat window opens: enough for the
  /// emulator's clock running a couple of seconds behind the host, far
  /// less than [logcatStampMargin], which would reach back into the
  /// previous flow on a suite that keeps one app.
  static const Duration _flowStampMargin = Duration(seconds: 3);

  @override
  Future<int> run() async {
    final summary = argResults!['summary'] as String?;
    if (summary != null && summary.isNotEmpty) return _printSummary(summary);
    if (argResults!['merge'] as bool) return _merge(argResults!.rest);
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageFailure('pass takes exactly one argument, the suite '
          '(e.g. `qa pass calendar`)');
    }
    return _runPass(rest.single);
  }

  int _printSummary(String path) {
    final file = File(context.paths.resolve(path));
    if (!file.existsSync()) throw UsageFailure('no report at ${file.path}');
    final report = PassReport.decode(file.readAsStringSync());
    summaryLines(report, reportPath: file.absolute.path).forEach(out);
    return report.allPassed ? 0 : exitTarget;
  }

  int _merge(List<String> inputs) {
    if (inputs.isEmpty) throw UsageFailure('--merge needs the report.json files to merge');
    final paths = context.paths;
    final files = [for (final input in inputs) File(paths.resolve(input))];
    for (final file in files) {
      if (!file.existsSync()) throw UsageFailure('no report at ${file.path}');
    }
    final reports = [
      for (final file in files) PassReport.decode(file.readAsStringSync()),
    ];
    final merged = mergeReports(reports);
    final repeated = duplicateFlowNames(reports);
    if (repeated.isNotEmpty) {
      warn('warning: ${repeated.length} flow(s) appear in more than one '
          'report; kept the one given last: ${repeated.join(', ')}');
    }
    final missing = _missingFromSuite(merged);
    if (missing != null && missing.isNotEmpty) {
      warn('warning: the merged reports do not cover "${merged.suite}": '
          '${missing.length} flow(s) missing: ${missing.join(', ')}');
    }
    final target = File(joinPath(paths.passRoot, [
      '${QaPaths.safeId(merged.suite)}_${shotStamp(DateTime.now())}_merged.json',
    ]))
      ..parent.createSync(recursive: true);
    target.writeAsStringSync(merged.encode());
    File(paths.latestPassFor(merged.suite)).writeAsStringSync(target.absolute.path);
    summaryLines(merged, reportPath: target.absolute.path).forEach(out);
    return merged.allPassed ? 0 : exitTarget;
  }

  /// The suite's flows [merged] lacks, against every flow a whole-suite
  /// pass would run; null when the suite is not under the flows directory
  /// (reports from another checkout), which leaves nothing to compare.
  List<String>? _missingFromSuite(PassReport merged) {
    final List<String> expected;
    try {
      final paths = context.paths;
      final manifest = SuiteManifest.load(paths.flowsDir, merged.suite);
      expected = selectFlows(_flowNames(paths.flowsDir, merged.suite), manifest: manifest);
    } on UsageFailure {
      return null;
    } on FileSystemException {
      return null;
    }
    final have = {for (final flow in merged.flows) flow.name};
    return [for (final name in expected) if (!have.contains(name)) name];
  }

  static List<String> _flowNames(String flowsDir, String suite) =>
      Directory(joinPath(flowsDir, [suite]))
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(isFlowFileName)
          .map(flowNameOf)
          .toList();

  Future<int> _runPass(String argument) async {
    final ctx = context;
    final paths = ctx.paths;
    final normalized = argument.replaceAll('\\', '/');
    final slash = normalized.indexOf('/');
    final suite = slash < 0 ? normalized : normalized.substring(0, slash);
    final manifest = SuiteManifest.load(paths.flowsDir, suite);
    final fixture = manifest.fixture;
    if (fixture == null) {
      throw UsageFailure('${SuiteManifest.fileName} of "$suite" names no '
          'fixture= — `qa pass` needs one');
    }
    final suiteDir = joinPath(paths.flowsDir, [suite]);
    final available = _flowNames(paths.flowsDir, suite);
    final shardArg = argResults!['shard'] as String?;
    final shard = shardArg == null || shardArg.isEmpty ? null : parseShard(shardArg);
    final selected = selectFlows(
      available,
      manifest: manifest,
      wanted: [
        if (slash >= 0) normalized.substring(slash + 1),
        ...argResults!['only'] as List<String>,
      ],
      shard: shard,
    );
    if (selected.isEmpty) {
      throw UsageFailure('nothing to run: shard ${shardArg ?? ''} of '
          '${available.length} flow(s) in "$suite" is empty');
    }
    final preludeName = manifest.prelude;
    List<String>? prelude;
    if (preludeName != null) {
      final file = File(joinPath(suiteDir, [preludeName]));
      if (!file.existsSync()) {
        throw UsageFailure('${SuiteManifest.fileName} of "$suite" names '
            'prelude=$preludeName, which is not in $suiteDir');
      }
      prelude = parseStepLines(file.readAsStringSync());
    }
    final reseed = (argResults!['reseed'] as bool) ? manifest.reseed : ReseedMode.none;

    final device = await ctx.device();
    final started = DateTime.now();
    final passDir = Directory(paths.passDirFor(suite, shotStamp(started), device.id))
      ..createSync(recursive: true);
    final log = File(joinPath(passDir.path, ['pass.log'])).openWrite();
    final qaRunner = runner! as QaCommandRunner;
    qaRunner.lineSink = (line, {required prefix, required isError}) {
      log.writeln('$prefix$line');
      _capture?.add(isError ? '! $line' : line);
    };
    ctx.shotsDirOverride = passDir.path;
    ctx.shotScaleOverride = passShotScale;
    try {
      final installed = ApkRecord.read(paths.installedJsonFor(device.id));
      if (installed != null) {
        final stale = staleBuildWarning(
          installed,
          newestSource(apkSourceRoots(paths)),
          projectRoot: paths.projectRoot,
        );
        if (stale != null) warn(stale);
      }
      out('pass: $suite — ${selected.length} flow(s)'
          '${shard == null ? '' : ' (shard ${shard.$1}/${shard.$2})'} on '
          '${device.id}, reseed ${reseed.name} — ${passDir.path}');

      final reportFile = File(joinPath(passDir.path, ['report.json']));
      final copy = argResults!['json'] as String?;
      // Written after every flow and once more at the end, so a pass that
      // is killed (or whose host dies) late still leaves what it finished.
      PassReport writeReport(
        List<FlowRecord> flows, {
        required bool partial,
        _Quiet? quiet,
      }) {
        final report = PassReport(
          suite: suite,
          label: argResults!['label'] as String?,
          device: PassDevice(id: device.id, label: device.label, platform: device.kind.label),
          host: Platform.operatingSystem,
          started: started,
          finished: DateTime.now(),
          shard: shard,
          reseed: reseed.name,
          fixture: fixture,
          prelude: preludeName,
          build: installed?.toJson(),
          flows: flows,
          partial: partial,
          quietMs: quiet?.ms,
          quietAlarms: quiet?.alarms,
          quietFailure: quiet?.failure,
        );
        final encoded = report.encode();
        reportFile.writeAsStringSync(encoded);
        File(paths.latestPassFor(suite)).writeAsStringSync(reportFile.absolute.path);
        if (copy != null && copy.isNotEmpty) {
          File(paths.resolve(copy))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(encoded);
        }
        return report;
      }

      final flows = await _runFlows(
        qaRunner,
        suite: suite,
        selected: selected,
        manifest: manifest,
        reseed: reseed,
        prelude: prelude,
        passDir: passDir.path,
        onFlowDone: (done) => writeReport(done, partial: true),
      );
      final quiet = argResults!['keep-state'] as bool ? null : await _leaveQuiet(qaRunner);
      final report = writeReport(flows, partial: false, quiet: quiet);
      summaryLines(report, reportPath: reportFile.absolute.path).forEach(out);
      if (report.allPassed) return 0;
      final reseedBroke = flows.any((f) =>
          f.failure != null && f.failure!.step == 0 && f.failure!.line.startsWith('relaunch '));
      final nothingRan = flows.every((f) => f.steps.isEmpty);
      return reseedBroke && nothingRan ? exitDevice : exitTarget;
    } finally {
      qaRunner.lineSink = null;
      ctx.shotsDirOverride = null;
      ctx.shotScaleOverride = null;
      await log.flush();
      await log.close();
    }
  }

  /// How long the app's launch reconcile gets to cancel what the last seed
  /// armed before the count stands.
  static const Duration _quietWait = Duration(seconds: 10);

  /// Starts the app once more on an empty QA database, so its launch
  /// reconcile cancels every alarm the fixture armed and nothing rings
  /// between passes (a seeded guest rang "Leg day" under the next suite on
  /// 2026-10-23), then counts what the device still holds armed.
  Future<_Quiet> _leaveQuiet(QaCommandRunner qaRunner) async {
    final ctx = context;
    const words = ['relaunch', '--fresh'];
    out('[quiet] ${words.join(' ')}');
    final at = DateTime.now();
    int took() => DateTime.now().difference(at).inMilliseconds;
    _capture = [];
    final (code, message) = await runOneStep(qaRunner, words);
    final printed = _takeCapture();
    if (code != 0) {
      return (
        ms: took(),
        alarms: null,
        failure: '${words.join(' ')}: ${message ?? _lastLine(printed) ?? 'exit $code'}',
      );
    }
    int? alarms;
    try {
      alarms = await ctx.armedAppAlarms();
      while (alarms != null && alarms > 0 && DateTime.now().difference(at) < _quietWait) {
        await Future<void>.delayed(const Duration(seconds: 1));
        alarms = await ctx.armedAppAlarms();
      }
    } on QaException catch (e) {
      warn('quiet: the armed alarms could not be counted: ${e.message}');
      alarms = null;
    }
    return (ms: took(), alarms: alarms, failure: null);
  }

  Future<List<FlowRecord>> _runFlows(
    QaCommandRunner qaRunner, {
    required String suite,
    required List<String> selected,
    required SuiteManifest manifest,
    required ReseedMode reseed,
    required List<String>? prelude,
    required String passDir,
    void Function(List<FlowRecord> done)? onFlowDone,
  }) async {
    final ctx = context;
    final suiteDir = joinPath(ctx.paths.flowsDir, [suite]);
    final stopOnFail = argResults!['stop-on-fail'] as bool;
    final records = <FlowRecord>[];
    var stopReason = '';
    var reseedFailures = 0;
    for (var index = 0; index < selected.length; index++) {
      final name = selected[index];
      if (stopReason.isNotEmpty) {
        records.add(FlowRecord(name: name, status: FlowStatus.skipped));
        continue;
      }
      out('=== flow ${index + 1}/${selected.length}: $name');
      final flowStarted = DateTime.now();
      // What this flow's failure evidence may blame on it starts here: under
      // reseed=suite the app (and its error buffer) outlives earlier flows.
      final errorsStamp = rawLogcatStamp(flowStarted.subtract(_flowStampMargin));
      await ctx.clearAgentErrors();
      int? reseedMs;
      int? preludeMs;
      FlowFailure? failure;
      final steps = <StepRecord>[];

      final reseeds = reseed == ReseedMode.flow || (reseed == ReseedMode.suite && index == 0);
      if (reseeds) {
        final words = [
          'relaunch',
          '--fresh',
          '--seed',
          manifest.fixture!,
          for (final setting in manifest.settings) ...['--setting', setting],
        ];
        final line = words.join(' ');
        out('[reseed] $line');
        _capture = [];
        final at = DateTime.now();
        final (code, message) = await runOneStep(qaRunner, words);
        reseedMs = DateTime.now().difference(at).inMilliseconds;
        final printed = _takeCapture();
        if (code != 0) {
          failure = FlowFailure(
            step: 0,
            line: line,
            exitCode: code,
            message: message ?? _lastLine(printed) ?? 'exit $code',
          );
        }
      }

      final runsPrelude = prelude != null &&
          failure == null &&
          (reseeds || (reseed == ReseedMode.none && index == 0));
      if (runsPrelude) {
        final at = DateTime.now();
        StepRun? failed;
        await runStepLines(
          prelude,
          keepGoing: false,
          onStepStart: (_, _) => _capture = [],
          onStepEnd: (step) {
            final printed = _takeCapture();
            if (step.code != 0) {
              failed = step;
              failure = FlowFailure(
                step: 0,
                line: '${manifest.prelude}: ${step.line}',
                exitCode: step.code,
                message: step.message ?? _lastLine(printed) ?? 'exit ${step.code}',
              );
            }
          },
        );
        preludeMs = DateTime.now().difference(at).inMilliseconds;
        if (failed != null) out('prelude: stopped at ${failed!.n}');
      }

      if (failure == null) {
        final file = File(joinPath(suiteDir, ['$name.txt']));
        await runStepLines(
          parseStepLines(file.readAsStringSync()),
          keepGoing: false,
          onStepStart: (_, _) => _capture = [],
          onStepEnd: (step) {
            final printed = _takeCapture();
            steps.add(StepRecord(
              n: step.n,
              line: step.line,
              ms: step.elapsed.inMilliseconds,
              ok: step.code == 0,
              output: printed.join('\n').trim(),
            ));
            if (step.code != 0) {
              failure = FlowFailure(
                step: step.n,
                line: step.line,
                exitCode: step.code,
                message: step.message ?? _lastLine(printed) ?? 'exit ${step.code}',
              );
            }
          },
        );
      }

      final took = DateTime.now().difference(flowStarted).inMilliseconds;
      final failed = failure;
      out('=== $name: ${failed == null ? 'ok' : 'FAILED (exit ${failed.exitCode})'} in $took ms');
      records.add(FlowRecord(
        name: name,
        status: failed == null ? FlowStatus.passed : FlowStatus.failed,
        durationMs: took,
        reseedMs: reseedMs,
        preludeMs: preludeMs,
        steps: steps,
        failure: failed == null
            ? null
            : await _evidence(qaRunner, failed, name, passDir, errorsStamp: errorsStamp),
      ));
      onFlowDone?.call(List.unmodifiable(records));
      if (failed == null) {
        reseedFailures = 0;
        continue;
      }
      final reseedFailed = failed.step == 0 && reseeds && preludeMs == null;
      reseedFailures = reseedFailed ? reseedFailures + 1 : 0;
      if (stopOnFail) {
        stopReason = '--stop-on-fail';
      } else if (reseedFailed && reseed == ReseedMode.suite) {
        stopReason = 'the suite seed did not go in';
      } else if (reseedFailures >= 2) {
        stopReason = 'two reseeds in a row failed';
      }
      if (stopReason.isNotEmpty) {
        out('pass: skipping the remaining ${selected.length - index - 1} flow(s) — $stopReason');
      }
    }
    return records;
  }

  /// The screen, its nodes and the error sources at the moment a flow
  /// failed, next to the report; each part that cannot be had is left null.
  Future<FlowFailure> _evidence(
    QaCommandRunner qaRunner,
    FlowFailure failure,
    String name,
    String passDir, {
    required String errorsStamp,
  }) async {
    final ctx = context;
    final base = 'fail_${sanitiseName(name)}';
    out('[failure] the screen, its nodes and the errors into $passDir');
    String? shot;
    String? dump;
    String? errors;
    try {
      final taken = await captureShot(
        ctx.screenshotPng,
        ctx.paths,
        name: base,
        scale: passShotScale,
        outDir: passDir,
      );
      shot = File(taken).renameSync(joinPath(passDir, ['$base.png'])).absolute.path;
    } on Object catch (e) {
      warn('pass: no failure screenshot ($e)');
    }
    try {
      final tree = await ctx.dump();
      final file = File(joinPath(passDir, ['${base}_dump.txt']))
        ..writeAsStringSync(
          tree.nodes.where((n) => n.interesting).map((n) => n.describe()).join('\n'),
        );
      dump = file.absolute.path;
    } on Object catch (e) {
      warn('pass: no failure dump ($e)');
    }
    _capture = [];
    ctx.runLogForThisDeviceOnly = true;
    ctx.errorsSinceStamp = errorsStamp;
    final int code;
    try {
      (code, _) = await runOneStep(qaRunner, ['errors']);
    } finally {
      ctx.runLogForThisDeviceOnly = false;
      ctx.errorsSinceStamp = null;
    }
    final printed = _takeCapture();
    if (code == 0 || printed.isNotEmpty) {
      final file = File(joinPath(passDir, ['${base}_errors.txt']))
        ..writeAsStringSync(printed.join('\n'));
      errors = file.absolute.path;
    }
    return failure.withEvidence(shot: shot, dump: dump, errors: errors);
  }

  List<String> _takeCapture() {
    final printed = _capture ?? const <String>[];
    _capture = null;
    return printed;
  }

  static String? _lastLine(List<String> printed) {
    for (final line in printed.reversed) {
      final trimmed = line.replaceFirst(RegExp(r'^! '), '').trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

/// Refuses a verb that only makes sense for an Android device when `-d`
/// names something else; with no `-d` there is nothing to refuse.
Future<void> requireAndroidTarget(QaContext ctx, String verb) async {
  final hint = ctx.explicitDevice;
  if (hint == null) return;
  final (adb, sims) = QaContext.probesFor(hint);
  if (adb && !sims) return;
  final ref = adb ? await ctx.ref() : null;
  if (ref != null && ref.kind == DeviceKind.android) return;
  throw UnsupportedOnPlatform(
    verb,
    ref?.label ?? hint,
    instead: 'it builds the Android APK; `qa run -d macos/ios` builds and '
        'starts the app there',
  );
}

/// `qa build` — the QA driver APK, built once for every emulator to install.
class BuildCommand extends QaCommand {
  BuildCommand() {
    argParser
      ..addMultiOption('define',
          help: 'Extra --dart-define, as K=V. Repeatable.')
      ..addFlag('driver',
          defaultsTo: true,
          help: 'Build $driverTarget so the QA agent and Flutter Driver work.')
      ..addFlag('force',
          negatable: false,
          help: 'Build even while the `flutter run` behind run.pid is up.');
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build the QA debug APK (flutter build apk --debug with the ANTA_QA '
      'defines and the driver entry point) and record it in build/qa/apk.json '
      'for `qa install`. Android only; never starts `flutter run`.';

  @override
  String get invocation => 'qa build [--define K=V]… [--no-driver] [--force]';

  @override
  Future<int> run() async {
    final ctx = context;
    await requireAndroidTarget(ctx, 'build');
    final refusal = await buildRefusal(ctx.paths, ctx.runner,
        force: argResults!['force'] as bool);
    if (refusal != null) throw UsageFailure(refusal);
    final extra = argResults!['define'] as List<String>;
    final args = buildApkArgs(driver: argResults!['driver'] as bool, extraDefines: extra);
    final flutter = findFlutter();
    out('flutter ${args.join(' ')}');
    final started = DateTime.now();
    final heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      warn('still building (${DateTime.now().difference(started).inSeconds} s)');
    });
    final RunOutcome result;
    try {
      result = await ctx.runner.run(
        flutter,
        args,
        timeout: const Duration(minutes: 20),
        workingDirectory: ctx.paths.projectRoot,
      );
    } finally {
      heartbeat.cancel();
    }
    final seconds = DateTime.now().difference(started).inSeconds;
    if (!result.ok) {
      throw DeviceFailure('flutter build apk failed (exit ${result.exitCode}) '
          'after $seconds s:\n${tailLines(result.combined)}');
    }
    final apk = File(ctx.paths.debugApk);
    if (!apk.existsSync()) {
      throw DeviceFailure('flutter build apk succeeded but ${apk.path} is not there');
    }
    final git = await gitBuildState(ctx.runner, ctx.paths.projectRoot);
    final record = ApkRecord(
      apk: apk.absolute.path,
      gitHash: git.hash,
      dirty: git.dirty,
      builtAt: started,
      defines: [...qaDefines, ...extra],
    )..write(ctx.paths.apkJson);
    final mb = (apk.lengthSync() / (1024 * 1024)).toStringAsFixed(0);
    out('built ${record.apk} ($mb MB) in $seconds s at '
        '${record.gitHash ?? 'no git hash'}${record.dirty ? ' (dirty tree)' : ''}');
    out('recorded ${ctx.paths.apkJson} — `qa -d <serial> install` puts it on a device');
    return 0;
  }
}

/// `qa install` — puts the built APK on one device without building, so
/// a fleet of emulators shares one build.
class InstallCommand extends QaCommand with StepLoop {
  InstallCommand() {
    argParser
      ..addOption('apk',
          help: 'The APK to install; defaults to the one build/qa/apk.json records.')
      ..addFlag('grant',
          negatable: false,
          help: 'Grant what a pass needs (POST_NOTIFICATIONS) on a device '
              'outside the fleet too; a fleet guest always gets it.');
  }

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install the APK `qa build` made on the selected Android device '
      '(adb install -r -t: the app data stays), grant a fleet guest what a '
      'pass needs, launch it once so its documents directory exists for '
      'the markers, and stop it.';

  @override
  String get invocation => 'qa install [--apk <path>] [--grant]';

  @override
  Future<int> run() async {
    final ctx = context;
    final device = await ctx.device();
    if (device is! AndroidDevice) {
      throw UnsupportedOnPlatform('install', device.label,
          instead: '`qa run -d macos/ios` builds and installs there');
    }
    final apkOption = argResults!['apk'] as String?;
    final ApkRecord record;
    if (apkOption != null && apkOption.isNotEmpty) {
      final file = File(ctx.paths.resolve(apkOption));
      if (!file.existsSync()) throw UsageFailure('no APK at ${file.path}');
      final recorded = ApkRecord.read(ctx.paths.apkJson);
      record = recorded != null && File(recorded.apk).absolute.path == file.absolute.path
          ? recorded
          : ApkRecord(
              apk: file.absolute.path,
              gitHash: null,
              dirty: false,
              builtAt: file.lastModifiedSync(),
              defines: const [],
            );
    } else {
      record = ApkRecord.require(ctx.paths.apkJson);
      if (!File(record.apk).existsSync()) {
        throw UsageFailure('${ctx.paths.apkJson} names ${record.apk}, which is '
            'gone — run `qa build` again');
      }
    }
    final args = installApkArgs(record.apk);
    out('adb -s ${device.id} ${args.join(' ')}');
    final started = DateTime.now();
    final result = await device.adb.raw(args, timeout: const Duration(minutes: 5));
    if (!result.ok || !result.stdout.contains('Success')) {
      throw DeviceFailure('adb install failed on ${device.id}: ${result.combined}');
    }
    out('installed in ${DateTime.now().difference(started).inMilliseconds} ms');
    if (grantsPassPermissions(device.id, asked: argResults!['grant'] as bool)) {
      (await applyPassGrants(device.adb, device.id)).forEach(out);
    }
    final qaRunner = runner! as QaCommandRunner;
    final (code, message) = await runOneStep(qaRunner, ['launch']);
    if (code != 0) {
      throw DeviceFailure('installed, but the first launch failed: ${message ?? 'exit $code'}');
    }
    await device.forceStop();
    out('stopped ${device.packageId} on ${device.label}');
    final installed = record.installed(DateTime.now())
      ..write(ctx.paths.installedJsonFor(device.id));
    out('recorded ${ctx.paths.installedJsonFor(device.id)} '
        '(${installed.gitHash ?? 'no git hash'}, built ${installed.builtAt.toIso8601String()})');
    return 0;
  }
}

/// The fleet's view of this host, from the SDK and AVD directory this
/// context sees.
FleetHost fleetHostFor(QaContext ctx) => FleetHost(
      runner: ctx.runner,
      adb: Adb(executable: ctx.sdk.requireAdb(), runner: ctx.runner),
      avdHome: fleetAvdHome(Platform.environment, windows: Platform.isWindows),
      sdkRoot: fleetSdkRoot(ctx.sdk),
      windows: Platform.isWindows,
    );

/// `qa fleet` — minimized emulators named `anta_qa_<N>`, each on its own
/// port, so several agents can each own one and a pass can be sharded
/// across them in one call. The owner's own AVDs are listed, never acted on.
class FleetCommand extends QaCommand {
  FleetCommand() {
    addSubcommand(FleetCreateCommand());
    addSubcommand(FleetBootCommand());
    addSubcommand(FleetStatusCommand());
    addSubcommand(FleetStopCommand());
    addSubcommand(FleetInstallCommand());
    addSubcommand(FleetPassCommand());
  }

  @override
  String get name => 'fleet';

  @override
  String get description =>
      'Minimized emulators anta_qa_<N> on console port 5554+2N for several '
      'agents at once: create, boot, status, stop, install, pass.';
}

/// What every fleet verb shares: the host view and the child `qa` launcher.
abstract class FleetSubcommand extends QaCommand {
  int get capacity => fleetCapacity(Platform.numberOfProcessors);

  String? get _parentVia =>
      globalResults!.wasParsed('via') ? globalResults!['via'] as String? : null;

  bool get _parentVerbose => globalResults!['verbose'] as bool? ?? false;

  /// Runs this tool again with [arguments], printing the lines [echo]
  /// accepts (all of them without it) under `[tag]`.
  Future<ChildOutcome> runChild(
    QaContext ctx,
    List<String> arguments, {
    required String tag,
    String? logPath,
    bool Function(String line, bool isError)? echo,
  }) {
    final self = qaSelfCommand(
      resolvedExecutable: Platform.resolvedExecutable,
      qaExe: ctx.paths.qaExe,
      qaExeExists: File(ctx.paths.qaExe).existsSync(),
      script: joinPath(ctx.paths.toolQaDir, ['qa.dart']),
    );
    return runQaChild(
      executable: self.executable,
      arguments: [...self.leading, ...arguments],
      workingDirectory: ctx.paths.projectRoot,
      logPath: logPath,
      onLine: (line, isError) {
        if (echo != null && !echo(line, isError)) return;
        isError ? warn('[$tag] $line') : out('[$tag] $line');
      },
    );
  }

  /// The fleet indices the verb's arguments name, or every created one
  /// with `--all`.
  List<int> namedIndices(FleetHost host, {required String verb}) {
    final rest = argResults!.rest;
    final all = argResults!['all'] as bool;
    if (all && rest.isNotEmpty) {
      throw UsageFailure('fleet $verb takes AVD names or --all, not both');
    }
    if (!all && rest.isEmpty) {
      throw UsageFailure('fleet $verb needs AVD names (anta_qa_2, or 2) or --all');
    }
    final indices = all
        ? host.createdIndices()
        : ({for (final argument in rest) parseFleetArgument(argument)}.toList()
          ..sort());
    if (indices.isEmpty) {
      throw UsageFailure('no fleet AVD exists yet — `qa fleet create` makes them');
    }
    return indices;
  }
}

class FleetCreateCommand extends FleetSubcommand {
  FleetCreateCommand() {
    argParser
      ..addOption('count',
          help: 'How many fleet AVDs (anta_qa_1..N). Defaults to what this '
              'host runs at once: (threads - $fleetReservedThreads for flutter '
              'test - $ownerEmulatorThreads for the owner\'s emulator) / '
              '$fleetVcpus.')
      ..addFlag('force',
          negatable: false, help: 'Allow --count above that capacity.')
      ..addFlag('retune',
          negatable: false,
          help: 'Rewrite the fleet keys of an existing AVD whose config.ini '
              'drifted from the spec (it takes effect on its next boot).');
  }

  @override
  String get name => 'create';

  @override
  String get description =>
      'Make the missing fleet AVDs with avdmanager: the image $ownerReferenceAvd '
      'uses, the $fleetDeviceProfile profile, 2 GB, 4 vCPU, 6 GB data, cold '
      'boot. Existing AVDs are reported (and with --retune retuned), never '
      'replaced or removed.';

  @override
  String get invocation => 'qa fleet create [--count N] [--force] [--retune]';

  @override
  Future<int> run() async {
    final ctx = context;
    final host = fleetHostFor(ctx);
    final threads = Platform.numberOfProcessors;
    final count = fleetCount(
      requested: intOption('count'),
      threads: threads,
      force: argResults!['force'] as bool,
    );
    out('fleet: $count AVD(s) in ${host.avdHome} (this host runs '
        '${fleetCapacity(threads)} at once on $threads threads)');
    String? image;
    var imageChosen = false;
    String? chooseImage() {
      if (imageChosen) return image;
      imageChosen = true;
      final owner = File(host.configPath(ownerReferenceAvd));
      return image = chooseFleetImage(
        ownerConfig:
            owner.existsSync() ? splitConfig(owner.readAsStringSync()) : null,
        installedApis: host.installedImageApis(),
      );
    }

    var failed = false;
    for (var index = 1; index <= count; index++) {
      try {
        out(await host.create(
          index,
          retune: argResults!['retune'] as bool,
          image: chooseImage,
        ));
      } on QaException catch (e) {
        failed = true;
        warn('failed: ${fleetName(index)} — ${e.message}');
      }
    }
    return failed ? exitDevice : 0;
  }
}

class FleetBootCommand extends FleetSubcommand {
  FleetBootCommand() {
    argParser
      ..addFlag('all', negatable: false, help: 'Every fleet AVD that exists.')
      ..addFlag('affinity',
          defaultsTo: true,
          help: 'Windows: pin each fleet qemu to the P-cores of a hybrid CPU '
              '($fleetAffinityEnv=<hex> sets the mask). --no-affinity leaves '
              'the scheduler alone.')
      ..addFlag('visible',
          negatable: false,
          help: 'Windows: leave the emulator window up instead of minimizing it.');
  }

  @override
  String get name => 'boot';

  @override
  String get description =>
      'Boot fleet AVDs on their own ports, in parallel, each in a window '
      'that is minimized at once (a -no-window qemu spins a host core while '
      'idle); wait until each is booted and provisioned, then pin it to the '
      'P-cores. One that is already up is left running (pinned, minimized).';

  @override
  String get invocation =>
      'qa fleet boot <anta_qa_N|N>… | --all [--no-affinity] [--visible]';

  @override
  Future<int> run() async {
    final ctx = context;
    final host = fleetHostFor(ctx);
    final indices = namedIndices(host, verb: 'boot');
    for (final index in indices) {
      if (!host.isCreated(fleetName(index))) {
        throw UsageFailure('${fleetName(index)} does not exist — '
            '`qa fleet create --count $index` makes it');
      }
    }
    final emulator = host.emulatorPath ??
        (throw DeviceFailure('emulator binary not found under '
            '${host.sdkRoot ?? 'the Android SDK'}'));
    final topology = await host.cpuTopology();
    final affinity = fleetAffinity(
      windows: Platform.isWindows,
      disabled: !(argResults!['affinity'] as bool),
      override: Platform.environment[fleetAffinityEnv],
      cores: topology?.cores,
      threads: topology?.threads,
    );
    out(affinity.mask == null
        ? 'affinity: not pinning — ${affinity.reason}'
        : 'affinity: pinning to ${hexMask(affinity.mask!)} — ${affinity.reason}');
    final devices = await host.adb.devices();
    final qemus = await host.qemuProcesses();
    final minimize = !(argResults!['visible'] as bool);
    final booted = await Future.wait([
      for (final index in indices)
        _bootOne(ctx, host, emulator, index, devices, qemus, affinity.mask,
            minimize: minimize),
    ]);
    return booted.every((ok) => ok) ? 0 : exitDevice;
  }

  Future<bool> _bootOne(
    QaContext ctx,
    FleetHost host,
    String emulator,
    int index,
    List<AdbDevice> devices,
    List<QemuProcess> qemus,
    int? mask, {
    required bool minimize,
  }) async {
    final name = fleetName(index);
    final serial = fleetSerial(index);
    final port = fleetPort(index);
    final started = DateTime.now();
    void progress(String line) => warn('[$name] $line');
    String took() =>
        '${(DateTime.now().difference(started).inMilliseconds / 1000).toStringAsFixed(1)} s';
    try {
      final row = devices.where((d) => d.serial == serial).firstOrNull;
      final running = qemus.where((q) => q.avd == name).firstOrNull;
      final String how;
      if (row != null) {
        final reported = await host.avdNameOn(serial);
        if (reported != name) {
          throw DeviceFailure('$serial (port $port) is held by '
              '${reported == null ? 'an emulator that does not name its AVD' : '"$reported"'}, '
              'not $name — left alone');
        }
        await awaitEmulatorBoot(ctx, host.adb, running?.pid, name,
            serial: serial, fatalLogLines: false, progress: progress);
        how = 'already up';
      } else if (running != null) {
        if (running.port != null && running.port != port) {
          throw DeviceFailure('$name already runs on port ${running.port} '
              '(qemu ${running.pid}), not its fleet port $port — left alone');
        }
        out('[$name] qemu ${running.pid} is already coming up — waiting');
        await awaitEmulatorBoot(ctx, host.adb, running.pid, name,
            serial: serial, fatalLogLines: false, progress: progress);
        how = 'up after ${took()}';
      } else {
        ctx.paths.ensureBuildQa();
        final logPath = ctx.paths.emulatorLogFor(name);
        final errPath = ctx.paths.emulatorErrFor(name);
        File(logPath).writeAsStringSync('');
        File(errPath).writeAsStringSync('');
        final wrapper = writeWrapperScript(
          paths: ctx.paths,
          baseName: emulatorWrapperName(name),
          executable: emulator,
          arguments: fleetEmulatorArgs(index),
          posixLogPath: logPath,
        );
        final pid = await startWrapperDetached(
          paths: ctx.paths,
          wrapper: wrapper,
          logPath: logPath,
          errPath: errPath,
          pidPath: ctx.paths.emulatorPidFor(name),
        );
        out('[$name] starting on $serial (pid $pid, log $logPath)');
        final early = _onceUp(host, name, mask: mask, minimize: minimize);
        await awaitEmulatorBoot(ctx, host.adb, pid, name,
            serial: serial, fatalLogLines: false, progress: progress);
        await early;
        how = 'booted in ${took()}';
      }
      try {
        await host.keepAwake(serial);
      } on QaException catch (e) {
        progress('the screen may still time out: ${e.message}');
      }
      final window = await _window(host, name, minimize: minimize);
      final pinned = await _pin(host, name, mask);
      out('ready: $name $serial window=$window pinned=$pinned ($how)');
      return true;
    } on QaException catch (e) {
      warn('failed: $name $serial — ${e.message}');
      return false;
    }
  }

  /// Pins a just-started qemu the moment it shows up, so the boot itself
  /// runs on the P-cores too, and minimizes its window as soon as it opens,
  /// so it does not sit on the owner's desktop for the boot; [_pin] and
  /// [_window] confirm both once the guest is up.
  Future<void> _onceUp(
    FleetHost host,
    String name, {
    required int? mask,
    required bool minimize,
  }) async {
    if (mask == null && (!minimize || !host.windows)) return;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final qemu =
          (await host.qemuProcesses()).where((q) => q.avd == name).firstOrNull;
      if (qemu != null) {
        if (mask != null) await host.pin(qemu.pid, mask);
        if (minimize) await host.minimize(qemu.pid);
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// The `window=` word of the ready line: minimizes the window when asked
  /// (again, since the emulator can bring it back while it boots), and
  /// says what the window is; a headless qemu stays headless until it is
  /// stopped and booted again.
  Future<String> _window(FleetHost host, String name, {required bool minimize}) async {
    if (!host.windows) return 'n/a';
    final qemu = (await host.qemuProcesses(windowStates: true))
        .where((q) => q.avd == name)
        .firstOrNull;
    if (qemu == null) return '? (its qemu was not found)';
    if (qemu.window == QemuWindow.headless) {
      return 'headless (started -no-window; `qa fleet stop $name` then '
          '`qa fleet boot $name` opens it windowed)';
    }
    if (!minimize || qemu.window == QemuWindow.minimized) {
      return qemu.window?.name ?? '?';
    }
    return (await host.minimize(qemu.pid))?.name ?? '?';
  }

  Future<String> _pin(FleetHost host, String name, int? mask) async {
    if (mask == null) return 'no';
    final qemu =
        (await host.qemuProcesses()).where((q) => q.avd == name).firstOrNull;
    if (qemu == null) return 'no (its qemu was not found)';
    if (qemu.affinity == mask) return hexMask(mask);
    final read = await host.pin(qemu.pid, mask);
    if (read == mask) return hexMask(mask);
    return 'no (Windows kept ${read == null ? 'its own mask' : hexMask(read)})';
  }
}

class FleetStatusCommand extends FleetSubcommand {
  FleetStatusCommand() {
    argParser.addFlag('json', negatable: false, help: 'Emit the fleet as JSON.');
  }

  @override
  String get name => 'status';

  @override
  String get description =>
      'One line per fleet AVD: serial, state, the installed build (stale '
      'when apk.json is newer), its qemu, that qemu\'s affinity and window '
      '(minimized, visible or headless); the owner\'s AVDs follow as '
      '`owner`, never acted on.';

  @override
  String get invocation => 'qa fleet status [--json]';

  @override
  Future<int> run() async {
    final ctx = context;
    final host = fleetHostFor(ctx);
    final qemus = await host.qemuProcesses(windowStates: true);
    final members =
        await host.members(upTo: capacity, paths: ctx.paths, qemus: qemus);
    final built = ApkRecord.read(ctx.paths.apkJson);
    final owners = host.avdNames().where((n) => fleetIndexOf(n) == null).toList();
    QemuProcess? qemuOf(String avd) =>
        qemus.where((q) => q.avd == avd).firstOrNull;
    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ').convert({
        'fleet': [for (final member in members) member.toJson(built)],
        'owner': [
          for (final avd in owners)
            {
              'name': avd,
              'running': qemuOf(avd) != null,
              'qemuPid': qemuOf(avd)?.pid,
              'port': qemuOf(avd)?.port,
            },
        ],
        'build': built?.toJson(),
      }));
      return 0;
    }
    for (final member in members) {
      out(fleetStatusLine(member, built, showAffinity: Platform.isWindows));
    }
    for (final avd in owners) {
      out(ownerStatusLine(avd, qemuOf(avd)));
    }
    out(built == null
        ? 'build: none recorded — `qa fleet install --build` makes one'
        : 'build: ${built.gitHash ?? 'no git hash'}${built.dirty ? ' (dirty tree)' : ''} '
            'built ${built.builtAt.toLocal().toIso8601String()} — ${ctx.paths.apkJson}');
    return 0;
  }
}

class FleetStopCommand extends FleetSubcommand {
  FleetStopCommand() {
    argParser.addFlag('all', negatable: false, help: 'Every fleet AVD that exists.');
  }

  @override
  String get name => 'stop';

  @override
  String get description =>
      'Shut fleet AVDs down through their console (adb emu kill), each only '
      'after its console names that fleet AVD, and wait until it is gone. '
      'Any other emulator is refused.';

  @override
  String get invocation => 'qa fleet stop <anta_qa_N|N>… | --all';

  @override
  Future<int> run() async {
    final host = fleetHostFor(context);
    var failed = false;
    for (final index in namedIndices(host, verb: 'stop')) {
      try {
        out(await host.stop(index));
      } on QaException catch (e) {
        failed = true;
        warn('refused: ${fleetName(index)} — ${e.message}');
      }
    }
    return failed ? exitDevice : 0;
  }
}

class FleetInstallCommand extends FleetSubcommand {
  FleetInstallCommand() {
    argParser.addFlag('build',
        negatable: false,
        help: 'Run `qa build` first (also done when build/qa/apk.json is missing).');
  }

  @override
  String get name => 'install';

  @override
  String get description =>
      'Put the recorded QA build on every booted fleet device at once '
      '(`qa -d <serial> install` each); a device that already carries it '
      'is skipped. Every one gets what a pass needs granted '
      '(POST_NOTIFICATIONS).';

  @override
  String get invocation => 'qa fleet install [--build]';

  @override
  Future<int> run() async {
    final ctx = context;
    final host = fleetHostFor(ctx);
    final members = await host.members(upTo: capacity, paths: ctx.paths);
    final ready = members.where((m) => m.ready).toList();
    if (ready.isEmpty) {
      throw DeviceFailure('no fleet device is up — `qa fleet boot --all` first');
    }
    var built = ApkRecord.read(ctx.paths.apkJson);
    if (argResults!['build'] as bool || built == null) {
      out(built == null ? 'no build/qa/apk.json — building first' : 'building first');
      final outcome = await runChild(
        ctx,
        fleetBuildChildArgs(via: _parentVia, verbose: _parentVerbose),
        tag: 'build',
      );
      if (outcome.exitCode != 0) {
        throw DeviceFailure('qa build failed (exit ${outcome.exitCode}) — nothing installed');
      }
      built = ApkRecord.read(ctx.paths.apkJson) ??
          (throw DeviceFailure('qa build recorded no ${ctx.paths.apkJson}'));
    }
    final targets = <FleetMember>[];
    for (final member in ready) {
      if (isCurrentInstall(member.installed, built)) {
        out('${member.serial}  ${member.name}  current: '
            '${appStatus(member.installed, built)}');
        // A guest that already carries the build still needs what a pass
        // needs granted; the install children grant on their own.
        (await applyPassGrants(host.adb.withSerial(member.serial), member.serial))
            .forEach(out);
      } else {
        targets.add(member);
      }
    }
    if (targets.isEmpty) return 0;
    final outcomes = await Future.wait([
      for (final member in targets)
        runChild(
          ctx,
          fleetInstallChildArgs(member.serial,
              via: _parentVia, verbose: _parentVerbose),
          tag: member.serial,
        ),
    ]);
    var failed = false;
    for (var i = 0; i < targets.length; i++) {
      final outcome = outcomes[i];
      final seconds = (outcome.took.inMilliseconds / 1000).toStringAsFixed(1);
      if (outcome.exitCode != 0) failed = true;
      out('${targets[i].serial}  ${targets[i].name}  '
          '${outcome.exitCode == 0 ? 'installed' : 'FAILED (exit ${outcome.exitCode})'} '
          'in $seconds s');
    }
    return failed ? exitDevice : 0;
  }
}

class FleetPassCommand extends FleetSubcommand {
  FleetPassCommand() {
    argParser
      ..addOption('devices',
          help: 'Comma-separated fleet AVDs to use (anta_qa_1,2 or '
              'emulator-5556); default every booted one.')
      ..addOption('label', help: 'Free text stored in every report.')
      ..addFlag('stop-on-fail',
          negatable: false,
          help: 'Each shard skips its remaining flows after a failure.')
      ..addFlag('keep-state',
          negatable: false,
          help: 'Each shard leaves its app as its last flow left it instead '
              'of ending on an empty QA database.');
  }

  @override
  String get name => 'pass';

  @override
  String get description =>
      'Shard a flow suite over the booted fleet devices in one call: one '
      '`qa -d <serial> pass <suite> --shard i/n` per device, each flow\'s '
      'verdict live, one merged report.';

  @override
  String get invocation =>
      'qa fleet pass <suite> [--devices a,b,…] [--label <text>] [--stop-on-fail] '
      '[--keep-state]';

  @override
  Future<int> run() async {
    final ctx = context;
    final rest = argResults!.rest;
    if (rest.length != 1 || rest.single.contains('/') || rest.single.contains('\\')) {
      throw UsageFailure('fleet pass takes exactly one suite (e.g. `qa fleet '
          'pass calendar`); `qa -d <serial> pass <suite>/<flow>` runs one flow');
    }
    final suite = rest.single;
    final manifest = SuiteManifest.load(ctx.paths.flowsDir, suite);
    final devicesArg = argResults!['devices'] as String?;
    final wanted = devicesArg == null || devicesArg.trim().isEmpty
        ? null
        : [
            for (final part in devicesArg.split(','))
              if (part.trim().isNotEmpty) parseFleetArgument(part, serials: true),
          ];
    final host = fleetHostFor(ctx);
    final members = await host.members(upTo: capacity, paths: ctx.paths);
    final pick = pickPassDevices(
      members: members,
      built: ApkRecord.read(ctx.paths.apkJson),
      suite: suite,
      shardable: manifest.shard,
      wanted: wanted,
    );
    pick.warnings.forEach(warn);
    for (final reason in pick.refused) {
      warn('left out: $reason');
    }
    if (pick.members.isEmpty) {
      throw DeviceFailure('no fleet device to run "$suite" on — '
          '`qa fleet boot --all`, then `qa fleet install`');
    }
    if (pick.note != null) out(pick.note!);
    final dir = Directory(
      ctx.paths.passDirFor(suite, shotStamp(DateTime.now()), 'fleet'),
    )..createSync(recursive: true);
    final count = pick.members.length;
    out('fleet pass: $suite over $count device(s) '
        '(${pick.members.map((m) => m.serial).join(', ')}) — ${dir.path}');
    final shards = [
      for (var i = 0; i < count; i++)
        (
          member: pick.members[i],
          shard: count > 1 ? (i + 1, count) : null,
          json: joinPath(dir.path, ['shard-${i + 1}.json']),
          log: joinPath(dir.path, ['shard-${i + 1}.log']),
        ),
    ];
    final outcomes = await Future.wait([
      for (final shard in shards)
        runChild(
          ctx,
          fleetPassChildArgs(
            serial: shard.member.serial,
            suite: suite,
            shard: shard.shard,
            jsonPath: shard.json,
            label: argResults!['label'] as String?,
            stopOnFail: argResults!['stop-on-fail'] as bool,
            keepState: argResults!['keep-state'] as bool,
            via: _parentVia,
            verbose: _parentVerbose,
          ),
          tag: shard.member.serial,
          logPath: shard.log,
          echo: (line, isError) =>
              isPassProgressLine(line) || (isError && line.startsWith('qa: ')),
        ),
    ]);
    final reports = <PassReport?>[];
    final couldNotRun = <String>[];
    for (var i = 0; i < shards.length; i++) {
      final file = File(shards[i].json);
      PassReport? report;
      if (file.existsSync()) {
        try {
          report = PassReport.decode(file.readAsStringSync());
        } on QaException {
          report = null;
        }
      }
      if (report == null) {
        couldNotRun.add('${shards[i].member.serial} (exit '
            '${outcomes[i].exitCode}, log ${shards[i].log})');
      }
      reports.add(report);
    }
    final ran = reports.nonNulls.toList();
    PassReport? merged;
    if (ran.isNotEmpty) {
      merged = mergeReports(ran);
      final reportFile = File(joinPath(dir.path, ['report.json']))
        ..writeAsStringSync(merged.encode());
      File(ctx.paths.latestPassFor(suite)).writeAsStringSync(reportFile.absolute.path);
      summaryLines(merged, reportPath: reportFile.absolute.path).forEach(out);
    }
    out('per device:');
    for (var i = 0; i < shards.length; i++) {
      final shard = shards[i];
      final seconds = (outcomes[i].took.inMilliseconds / 1000).toStringAsFixed(1);
      final flows = reports[i]?.flows.length;
      out('  ${shard.member.serial}  ${shard.member.name}  '
          '${shard.shard == null ? 'whole suite' : 'shard ${shard.shard!.$1}/${shard.shard!.$2}'}  '
          '${flows ?? '-'} flow(s)  $seconds s  exit ${outcomes[i].exitCode}');
    }
    if (couldNotRun.isNotEmpty) {
      warn('could not run: ${couldNotRun.join('; ')}');
      return exitDevice;
    }
    return merged!.allPassed ? 0 : exitTarget;
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
    final device = await ctx.device();
    if (File(ctx.paths.runLog).existsSync()) {
      final deviceFile = File(ctx.paths.deviceTxt);
      final skip = ctx.runLogForThisDeviceOnly
          ? runLogSkipNote(
              runDevice: deviceFile.existsSync()
                  ? deviceFile.readAsStringSync().trim()
                  : null,
              deviceId: device.id,
            )
          : null;
      if (skip != null) {
        out(skip);
      } else {
        sources[ctx.paths.runLog] = errorLines(readRunLog(ctx.paths), limit: limit);
      }
    }
    final since = ctx.errorsSinceStamp;
    final platformLog = device.kind == DeviceKind.android
        ? await device.qaLogText(since: since)
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

/// Null when `run.log` belongs to [deviceId] — `device.txt` ([runDevice])
/// names the device the one `flutter run` slot serves — otherwise the line
/// that says why it was left out of a pass's evidence.
String? runLogSkipNote({required String? runDevice, required String deviceId}) {
  if (runDevice == deviceId) return null;
  if (runDevice == null || runDevice.isEmpty) {
    return 'run.log: belongs to no recorded run, skipped';
  }
  return 'run.log: belongs to $runDevice, skipped';
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
    final mismatch = agentVersionMismatch(info.protocolVersion);
    if (mismatch != null) warn('warning: $mismatch');
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

/// `qa set text-scale=2.0 locale=de theme=dark` — the accessibility matrix
/// without a rebuild or a relaunch. Goes through the agent's `set` op: text
/// scale is a QA-only override, locale and theme are the app's own settings.
class SetCommand extends QaCommand {
  @override
  String get name => 'set';

  @override
  String get description =>
      'Override the running QA build: text-scale=<factor|off>, '
      'locale=<code|system>, theme=<light|dark|system>. Several at once.';

  @override
  String get invocation => 'qa set text-scale=2.0 [locale=de] [theme=dark]';

  static Map<String, Object?> parseAssignments(List<String> rest) {
    if (rest.isEmpty) {
      throw UsageFailure(
        'set needs at least one of text-scale=, locale=, theme=',
      );
    }
    final args = <String, Object?>{};
    for (final raw in rest) {
      final at = raw.indexOf('=');
      if (at <= 0) throw UsageFailure('set takes key=value (got "$raw")');
      final key = raw.substring(0, at).trim().toLowerCase();
      final value = raw.substring(at + 1).trim();
      switch (key) {
        case 'text-scale':
        case 'textscale':
        case 'scale':
          if (value == 'off' || value == 'none' || value.isEmpty) {
            args[AgentKeys.textScale] = null;
          } else {
            final factor = double.tryParse(value);
            if (factor == null || factor <= 0 || factor > 4) {
              throw UsageFailure(
                'text-scale must be a factor between 0 and 4, or off '
                '(got "$value")',
              );
            }
            args[AgentKeys.textScale] = factor;
          }
        case 'locale':
        case 'language':
          args[AgentKeys.locale] = value.isEmpty ? 'system' : value;
        case 'theme':
        case 'theme-mode':
        case 'thememode':
          if (!const {'light', 'dark', 'system'}.contains(value)) {
            throw UsageFailure('theme must be light, dark or system (got "$value")');
          }
          args[AgentKeys.themeMode] = value;
        default:
          throw UsageFailure('set does not know "$key" (text-scale, locale, theme)');
      }
    }
    return args;
  }

  @override
  Future<int> run() async {
    final ctx = context;
    final args = parseAssignments(argResults!.rest);
    final agent = await ctx.agent();
    final result = await agent.op(AgentOps.set, args);
    final scale = result[AgentKeys.textScale];
    out('set  text-scale=${scale ?? 'platform'}  '
        'locale=${result[AgentKeys.locale] ?? 'system'}  '
        'theme=${result[AgentKeys.themeMode] ?? '?'}');
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

  ({AgentInfo? info, String? failure, int ms})? _agentFetched;

  /// The agent's `info`, asked once per run: `--fix` collects twice, and
  /// none of its repairs touches the app, so a second probe could only
  /// cost another wait on an agent that is not there.
  Future<({AgentInfo? info, String? failure, int ms})> _agentInfo(QaContext ctx) async =>
      _agentFetched ??= await ctx.agentInfoOrFailure(refresh: true);

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
    final fetched = vmUri == null
        ? (info: null, failure: null, ms: 0)
        : await _agentInfo(ctx);
    await ctx.decideAutoFrom(agentAnswered: fetched.info != null);
    results.add(_agentCheck(
      vmUri,
      fetched,
      required: ctx.via == ViaMode.agent,
      driver: await ctx.driverLabel(),
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
    final fetched = await _agentInfo(ctx);
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
    final fetched = await _agentInfo(ctx);
    results.add(checkAppRunning(await device.probe(fetched.info), device.packageId));
    results.add(_agentCheck(await ctx.recordedVmUri(), fetched, required: true));
    if (await device.isInstalled()) results.add(await _markersCheck(device));
    return results;
  }

  /// [driver] is the `driver=` word on a platform with a native layer,
  /// where the agent line also says which layer the verbs will use.
  CheckResult _agentCheck(
    String? vmUri,
    ({AgentInfo? info, String? failure, int ms}) fetched, {
    required bool required,
    String? driver,
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
          : CheckResult.ok('agent', 'not in use (driver=${driver ?? 'adb'}); '
              '`qa relaunch` or `qa run` records a VM URI the agent answers on');
    }
    final info = fetched.info;
    if (info != null) {
      return checkAgent(
        vmUri: vmUri,
        failure: null,
        roundTripMs: fetched.ms,
        summary: '${info.describe()}${driver == null ? '' : '  driver=$driver'}',
        qaMode: info.qaMode,
        cloud: info.cloud,
        protocolVersion: info.protocolVersion,
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
            fix: 'driver=${driver ?? 'adb'} meanwhile; ${result.fix}',
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
    final fleet = await _fleetCheck(ctx);
    if (fleet != null) results.add(fleet);
    return results;
  }

  /// The `fleet` line, or null on a host with no Android SDK or AVDs.
  Future<CheckResult?> _fleetCheck(QaContext ctx) async {
    if (ctx.sdk.findAdb() == null) return null;
    try {
      final host = fleetHostFor(ctx);
      if (host.avdNames().isEmpty) return null;
      final topology = await host.cpuTopology();
      final affinity = fleetAffinity(
        windows: Platform.isWindows,
        disabled: false,
        override: Platform.environment[fleetAffinityEnv],
        cores: topology?.cores,
        threads: topology?.threads,
      );
      final members = await host.members(
        upTo: fleetCapacity(Platform.numberOfProcessors),
        paths: ctx.paths,
        devices: await ctx.adbDevices(),
      );
      return checkFleet(members, pinMask: affinity.mask);
    } on QaException catch (e) {
      return CheckResult(
        name: 'fleet',
        status: CheckStatus.warn,
        detail: 'could not read the fleet: ${e.message}',
      );
    }
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
