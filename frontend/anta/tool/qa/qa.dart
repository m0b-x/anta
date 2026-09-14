import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'src/adb.dart';
import 'src/device.dart';
import 'src/doctor.dart';
import 'src/dump_cache.dart';
import 'src/errors.dart';
import 'src/gestures.dart';
import 'src/input_text.dart';
import 'src/log_parse.dart';
import 'src/markers.dart';
import 'src/paths.dart';
import 'src/process_runner.dart';
import 'src/runner.dart';
import 'src/self_build.dart';
import 'src/shell_batch.dart';
import 'src/shell_words.dart';
import 'src/shots.dart';
import 'src/target.dart';
import 'src/ui_tree.dart';

Future<void> main(List<String> arguments) async {
  final runner = QaCommandRunner();
  try {
    await _refreshSelf(arguments);
    final code = await runner.run(arguments) ?? 0;
    exitCode = code;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(e.usage);
    exitCode = exitUsage;
  } on QaException catch (e) {
    stderr.writeln('qa: ${e.message}');
    exitCode = e.code;
  }
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
          'Drive the ANTA app on a device from the command line.\n'
              'Fast path: tool\\qa\\qa.cmd <verb> (compiles itself on first use)\n'
              'Portable: dart run tool/qa/qa.dart <verb>',
        ) {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device serial. Falls back to ANTA_QA_DEVICE, then the sole '
            'attached device.',
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
    addCommand(StepsCommand());
    addCommand(LogcatCommand());
    addCommand(ErrorsCommand());
    addCommand(BuildExeCommand());
  }

  QaContext? _context;

  /// Prefix put in front of every output line, so `steps` can indent the
  /// verbs it dispatches without each verb knowing about it.
  String outputPrefix = '';

  /// The single context every verb in this process shares.
  ///
  /// One serial resolution, one `Device`, one screen-size cache, one dump
  /// cache — which is the whole point of running several verbs per process.
  QaContext contextFor(ArgResults globals) => _context ??= QaContext(globals);
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

  Adb? _adb;
  AndroidDevice? _device;

  Future<Adb> adb() async {
    final existing = _adb;
    if (existing != null) return existing;
    final executable = sdk.requireAdb();
    final bare = Adb(executable: executable, runner: runner);
    final serial = selectSerial(
      explicit: globalResults['device'] as String?,
      envValue: Platform.environment['ANTA_QA_DEVICE'],
      available: await bare.devices(),
    );
    return _adb = bare.withSerial(serial);
  }

  Future<AndroidDevice> device() async => _device ??= AndroidDevice(await adb());

  Future<DeviceProbe> probe() async => (await device()).probe();

  /// A fresh dump, cached to disk so later `#N` targets mean this tree.
  Future<UiTree> dump() async {
    final xml = await (await device()).dumpUiXml();
    writeDumpCache(paths, xml);
    return UiTree.parse(xml);
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
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final tree = await dump();
      ResolvedTarget? found;
      try {
        found = TargetResolver(tree).resolve(wanted, nth: nth);
      } on TargetFailure {
        found = null;
      }
      if (gone && found == null) {
        return WaitOutcome(satisfied: true, lastTree: tree);
      }
      if (!gone && found != null) {
        return WaitOutcome(satisfied: true, found: found, lastTree: tree);
      }
      if (!DateTime.now().isBefore(deadline)) {
        return WaitOutcome(satisfied: false, lastTree: tree);
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
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
  void warnIfForeign(UiTree? tree) {
    final package = tree?.foregroundPackage;
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
        defaultsTo: '300',
        help: 'Milliseconds to pause before --shot/--dump when not waiting.')
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
      final settle = intOption('settle') ?? 300;
      if (settle > 0) {
        await Future<void>.delayed(Duration(milliseconds: settle));
      }
    }

    final shotName = argResults!['shot'] as String?;
    var tookShot = false;
    if (shotName != null && shotName.isNotEmpty) {
      out(await captureShot(await ctx.device(), ctx.paths, name: shotName));
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
  @override
  String get name => 'devices';

  @override
  String get description => 'List attached devices.';

  @override
  Future<int> run() async {
    final ctx = context;
    final adb = Adb(executable: ctx.sdk.requireAdb(), runner: ctx.runner);
    final devices = await adb.devices();
    if (devices.isEmpty) {
      out('no devices attached');
      return 0;
    }
    for (final device in devices) {
      out(device.toString());
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
    final probe = await device.probe();
    final size = probe.screen;
    final dtdFile = File(ctx.paths.dtdTxt);
    final dtd = dtdFile.existsSync() ? dtdFile.readAsStringSync().trim() : '';
    final logExists = File(ctx.paths.runLog).existsSync();

    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ').convert({
        'device': device.id,
        'pid': probe.appPid,
        'resumedActivity': probe.resumedActivity,
        'foreground': probe.foregroundPackage,
        'awake': probe.awake,
        'locked': probe.locked,
        'ime': probe.imeShown,
        'physical': '${size.physicalWidth}x${size.physicalHeight}',
        'override': size.isOverridden ? '${size.width}x${size.height}' : null,
        'density': size.density,
        'dp': '${size.widthDp}x${size.heightDp}',
        'runLog': logExists ? ctx.paths.runLog : null,
        'dtd': dtd.isEmpty ? null : dtd,
      }));
      return 0;
    }
    out('device=${device.id}  '
        'app=${probe.appPid == null ? 'not running' : 'pid ${probe.appPid}'}  '
        'resumed=${probe.resumedActivity ?? 'unknown'}  '
        'foreground=${probe.foregroundPackage ?? 'unknown'}  '
        'awake=${DeviceProbe.flag(probe.awake, 'yes', 'no')}  '
        'locked=${DeviceProbe.flag(probe.locked, 'yes', 'no')}  '
        'ime=${DeviceProbe.flag(probe.imeShown, 'up', 'down')}  '
        'screen=$size  run.log=${logExists ? 'yes' : 'no'}  '
        'dtd=${dtd.isEmpty ? 'no' : dtd}');
    return 0;
  }
}

class BootCommand extends QaCommand {
  BootCommand() {
    argParser
      ..addOption('avd', help: 'AVD name. Defaults to the only one installed.')
      ..addFlag('cold', negatable: false, help: 'Cold boot (no snapshot).')
      ..addFlag('phone',
          negatable: false,
          help: 'Override the resolution to 1080x2400 (360x800 dp at 480 dpi).');
  }

  @override
  String get name => 'boot';

  @override
  String get description =>
      'Start the emulator if none is attached and wait until it is provisioned.';

  @override
  Future<int> run() async {
    final ctx = context;
    final bare = Adb(executable: ctx.sdk.requireAdb(), runner: ctx.runner);
    final attached = await bare.devices();
    final usable = attached.where((d) => d.usable).toList();
    if (usable.isNotEmpty) {
      out('emulator already up: ${usable.map((d) => d.serial).join(', ')} '
          '(never killed or restarted by this tool)');
    } else if (attached.isNotEmpty) {
      throw DeviceFailure(
        '${attached.map((d) => unusableDeviceMessage(d.serial, d.state)).join('; ')}. '
        'Nothing here can fix that: a wedged guest needs the owner to close '
        'the emulator window and cold-boot it.',
      );
    } else {
      final pid = await _startEmulator(ctx);
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

  /// Starts the emulator through the same wrapper machinery `run` uses, so its
  /// output lands in a file this tool can read back when the boot fails.
  Future<int> _startEmulator(QaContext ctx) async {
    final emulator = ctx.sdk.requireEmulator();
    var avd = argResults!['avd'] as String?;
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
      'Wake the screen and dismiss the keyguard, then report awake/locked.';

  @override
  Future<int> run() async {
    final ctx = context;
    final adb = await ctx.adb();
    await adb.shellBatch(const [
      ShellCommand(['input', 'keyevent', 'KEYCODE_WAKEUP']),
      ShellCommand(['wm', 'dismiss-keyguard']),
    ]);
    final probe = await (await ctx.device()).probe();
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
  String get description => 'Reset any `wm size` override back to physical.';

  @override
  Future<int> run() async {
    final adb = await context.adb();
    await adb.shellLenient(['wm', 'size', 'reset']);
    out('wm size reset: ${await AndroidDevice(adb).screenSize()}');
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
          help: 'Use $driverTarget so Flutter Driver commands work.')
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
    final killed = await killRecordedRun(ctx.paths, ctx.runner);
    if (killed != null) out('killed the previous run (pid $killed)');
    final orphans = await reapOrphanedServices(ctx.runner);
    if (orphans.isNotEmpty) {
      out('reaped orphaned dart development-service: ${orphans.join(', ')}');
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
    );
    out('pid=${result.pid}  log=${result.logPath}');
    out('dtd=${result.uris.dtd}');
    out('vm=${result.uris.vmService}');
    return 0;
  }
}

/// Waits for the `[qa]` lines a QA launch prints as it consumes its markers,
/// prints them, and fails when one that was asked for never arrives.
mixin QaMarkerReporting on QaCommand {
  Future<void> reportQaMarkers({
    required QaContext ctx,
    required String stamp,
    required bool wantedReset,
    required bool wantedSeed,
    required bool includeRunLog,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!wantedReset && !wantedSeed) return;
    final deadline = DateTime.now().add(timeout);
    var markers = const QaMarkerLines();
    var expired = false;
    while (true) {
      markers = parseQaMarkers(await _markerText(ctx, stamp, includeRunLog));
      final complete = (!wantedReset || markers.reset != null) &&
          (!wantedSeed || markers.seed != null);
      if (complete || expired) {
        // One more read after a short pause: the three lines land within about
        // half a second of each other, so the poll that first sees `reset` is
        // usually a beat early for `seed` and `onboarding`.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        markers = parseQaMarkers(await _markerText(ctx, stamp, includeRunLog));
        break;
      }
      if (!DateTime.now().isBefore(deadline)) {
        expired = true;
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    for (final line in markers.all) {
      out('[qa] $line');
    }
    if (markers.seedFailed) {
      throw DeviceFailure(
        'the seed was not imported: ${markers.seed}. The database is not the '
        'one this run asked for — fix the fixture before reading the screen.',
      );
    }
    final missing = <String>[
      if (wantedReset && markers.reset == null) 'reset',
      if (wantedSeed && markers.seed == null) 'seed',
    ];
    if (missing.isNotEmpty) {
      throw DeviceFailure(
        'no `[qa] ${missing.join('` and no `[qa] ')}` line appeared within '
        '${timeout.inSeconds}s (watched '
        '${lastMarkerPid == null ? 'no app process' : 'pid $lastMarkerPid'}) — '
        'the app may not have consumed the marker (is this a QA build? '
        '`qa state` shows the process; `qa logcat` shows what it said).',
      );
    }
  }

  /// The pid the last poll scoped its logcat read to, for the error message.
  int? lastMarkerPid;

  /// The launch's own log text.
  ///
  /// Scoping to the app's pid is what makes this reliable: the pid is new
  /// after every force-stop, so a previous launch's `[qa]` lines cannot be
  /// mistaken for this one's, and nothing depends on the host and the guest
  /// agreeing about the time. The pid is re-read every poll rather than
  /// latched, because the first poll can still catch the process that is on
  /// its way out. The timestamp filter is the fallback for the window where
  /// there is no process at all.
  Future<String> _markerText(
    QaContext ctx,
    String stamp,
    bool includeRunLog,
  ) async {
    final fromLog = includeRunLog ? readRunLog(ctx.paths) : '';
    final parsed = parseQaMarkers(fromLog);
    if (parsed.reset != null && parsed.seed != null) return fromLog;
    final pid = await (await ctx.device()).appPid(antaPackage);
    lastMarkerPid = pid;
    final logcat = await (await ctx.adb()).raw(
      [
        'logcat',
        '-d',
        '-v',
        'time',
        if (pid != null)
          '--pid=$pid'
        else ...['-T', stamp, '-s', 'flutter:V'],
      ],
      timeout: const Duration(seconds: 60),
    );
    return '$fromLog\n${logcat.combined}';
  }
}

class RunAppCommand extends LaunchingCommand with QaMarkerReporting {
  RunAppCommand() {
    argParser
      ..addFlag('fresh',
          negatable: false,
          help: 'Drop the qa_reset marker so the next QA launch wipes the qa db.')
      ..addOption('seed',
          help: 'Full-backup JSON to push as qa_seed.json '
              '(relative paths resolve against the package root).');
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Force-stop the app, then start a detached `flutter run` in QA mode.';

  @override
  Future<int> run() async {
    final ctx = context;
    await clearPreviousRun(ctx);
    final adb = await ctx.adb();
    final fresh = argResults!['fresh'] as bool;
    if (fresh) {
      await dropResetMarker(adb);
      out('qa_reset marker dropped');
    }
    final seed = argResults!['seed'] as String?;
    final seeded = seed != null && seed.isNotEmpty;
    if (seeded) {
      final path = ctx.paths.resolve(seed);
      await pushSeed(adb, path);
      out('qa_seed.json pushed from $path');
    }
    await (await ctx.device()).forceStop(antaPackage);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final code = await launch('run');
    await reportQaMarkers(
      ctx: ctx,
      stamp: File(ctx.paths.runStamp).readAsStringSync().trim(),
      wantedReset: fresh,
      wantedSeed: seeded,
      includeRunLog: true,
    );
    return code;
  }
}

class RelaunchCommand extends QaCommand
    with PostActions, QaMarkerReporting {
  RelaunchCommand() {
    argParser
      ..addFlag('fresh',
          negatable: false, help: 'Drop the qa_reset marker first.')
      ..addOption('seed', help: 'Full-backup JSON to push as qa_seed.json.');
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'relaunch';

  @override
  String get description =>
      'Force-stop and restart the installed build, applying the QA markers — '
      'the fast reset when Flutter Driver is not needed.';

  @override
  Future<int> run() async {
    final ctx = context;
    final adb = await ctx.adb();
    final device = await ctx.device();
    if (!await device.isInstalled()) {
      throw DeviceFailure('$antaPackage is not installed — run `qa run`');
    }
    final fresh = argResults!['fresh'] as bool;
    if (fresh) {
      await dropResetMarker(adb);
      out('qa_reset marker dropped');
    }
    final seed = argResults!['seed'] as String?;
    final seeded = seed != null && seed.isNotEmpty;
    if (seeded) {
      final path = ctx.paths.resolve(seed);
      await pushSeed(adb, path);
      out('qa_seed.json pushed from $path');
    }
    final stamp = logcatStamp(DateTime.now());
    await device.forceStop(antaPackage);
    await device.launchActivity(antaActivity);
    out('relaunched $antaActivity');
    await reportQaMarkers(
      ctx: ctx,
      stamp: stamp,
      wantedReset: fresh,
      wantedSeed: seeded,
      includeRunLog: false,
    );
    out('note: the flutter run behind run.log has lost the device — '
        '`qa attach` when you need DTD/Driver again');
    await runPostActions();
    return 0;
  }
}

class AttachCommand extends LaunchingCommand {
  @override
  String get name => 'attach';

  @override
  String get description =>
      'Attach to an already running app and capture its DTD/VM URIs.';

  @override
  Future<int> run() async {
    await clearPreviousRun(context);
    return launch('attach');
  }
}

class StopCommand extends QaCommand {
  @override
  String get name => 'stop';

  @override
  String get description => 'Force-stop the app on the device.';

  @override
  Future<int> run() async {
    await (await context.device()).forceStop(antaPackage);
    out('force-stopped $antaPackage');
    return 0;
  }
}

class KillRunCommand extends QaCommand {
  @override
  String get name => 'kill-run';

  @override
  String get description => 'Kill the detached `flutter run` recorded in run.pid.';

  @override
  Future<int> run() async {
    final ctx = context;
    final pid = await killRecordedRun(ctx.paths, ctx.runner);
    out(pid == null ? 'no run.pid — nothing to kill' : 'killed run pid $pid');
    final orphans = await reapOrphanedServices(ctx.runner);
    if (orphans.isNotEmpty) {
      out('reaped orphaned dart development-service: ${orphans.join(', ')}');
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
      'Print the Dart Tooling Daemon URI captured by the last run.';

  @override
  Future<int> run() async {
    final ctx = context;
    final file =
        File((argResults!['vm'] as bool) ? ctx.paths.vmTxt : ctx.paths.dtdTxt);
    if (!file.existsSync() || file.readAsStringSync().trim().isEmpty) {
      throw DeviceFailure('no URI recorded yet — run `qa run` or `qa attach` first');
    }
    out(file.readAsStringSync().trim());
    return 0;
  }
}

class LaunchCommand extends QaCommand with PostActions {
  LaunchCommand() {
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'launch';

  @override
  String get description =>
      'Start the already installed build with `am start` (no flutter run).';

  @override
  Future<int> run() async {
    final device = await context.device();
    if (!await device.isInstalled()) {
      throw DeviceFailure('$antaPackage is not installed — run `qa run`');
    }
    await device.launchActivity(antaActivity);
    out('launched $antaActivity');
    await runPostActions();
    return 0;
  }
}

class ShotCommand extends QaCommand {
  ShotCommand() {
    argParser
      ..addOption('scale', defaultsTo: '0.5', help: 'Downscale factor, 0 < f <= 1.')
      ..addFlag('full', negatable: false, help: 'No downscale (same as --scale 1).')
      ..addOption('out', help: 'Directory to write into.');
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
    final path = await captureShot(
      await ctx.device(),
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
          negatable: false, help: 'Include nodes with no label and no flags.')
      ..addFlag('json', negatable: false, help: 'Emit the nodes as JSON.')
      ..addFlag('cached',
          negatable: false,
          help: 'Print the last dump from build/qa/last_dump.xml without '
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
    out('${nodes.length} node(s) of ${tree.nodes.length}'
        '${all ? '' : ' (pass --all for the rest)'}'
        '${age == null ? '' : '  [cached, taken $age]'}');
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
    if (tree != null && node != null && !node.clickable) {
      final clickable = tree.clickableSelfOrAncestor(node);
      if (clickable != null && clickable.index != node.index) {
        point = (clickable.bounds.centreX, clickable.bounds.centreY);
        description = '${node.label} via ${clickable.describe()}';
      }
    }
    await (await ctx.device()).tap(point.$1, point.$2);
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
  String get description => 'Long-press a target (a swipe with no travel).';

  @override
  Future<int> run() async {
    final ctx = context;
    final lookup = await target();
    warnIfForeign(lookup.tree);
    final resolved = lookup.resolved;
    final ms = intOption('ms') ?? 800;
    await (await ctx.device())
        .swipePath(SwipePath(resolved.x, resolved.y, resolved.x, resolved.y, ms));
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
  String get description => 'Swipe inside a scrollable until a target shows up.';

  @override
  Future<int> run() async {
    final ctx = context;
    final wanted = requireRest('a target');
    final maxSwipes = intOption('max') ?? 8;
    final container = argResults!['in'] as String?;
    final direction =
        (argResults!['up'] as bool) ? SwipeDirection.down : SwipeDirection.up;
    final device = await ctx.device();
    final nth = intOption('nth');

    UiTree? tree;
    for (var attempt = 0; attempt <= maxSwipes; attempt++) {
      tree = await ctx.dump();
      if (attempt == 0) warnIfForeign(tree);
      try {
        final found = TargetResolver(tree).resolve(wanted, nth: nth);
        out('found after $attempt swipe(s): ${found.description}');
        return 0;
      } on TargetFailure catch (e) {
        if (e.message.contains('ambiguous')) rethrow;
      }
      if (attempt == maxSwipes) break;
      final scrollable = container == null
          ? tree.firstScrollable
          : TargetResolver(tree).resolve(container).node;
      final bounds = scrollable?.bounds;
      final size = await device.screenSize();
      final path = buildSwipe(
        left: bounds?.left ?? 0,
        top: bounds?.top ?? 0,
        width: bounds?.width ?? size.width,
        height: bounds?.height ?? size.height,
        direction: direction,
      );
      await device.swipePath(path);
      await Future<void>.delayed(const Duration(milliseconds: 400));
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
    argParser.addFlag('enter',
        negatable: false, help: 'Send ENTER after the text.');
    addPostActionOptions(argParser);
  }

  @override
  String get name => 'type';

  @override
  String get description =>
      'Type ASCII text into the focused field (`adb shell input text`).';

  @override
  Future<int> run() async {
    final ctx = context;
    final text = requireRest('some text');
    final device = await ctx.device();
    final imeShown = await device.typeTextChecked(text);
    final enter = argResults!['enter'] as bool;
    if (enter) await device.key('enter');
    out('typed "$text"${enter ? ' + ENTER' : ''}');
    if (imeShown == false) {
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
      'Send a key event: back, home, enter, del, tab, esc or a raw KEYCODE_*.';

  @override
  Future<int> run() async {
    final key = requireRest('a key name');
    await (await context.device()).key(key);
    out('sent ${resolveKeycode(key)}');
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
    final device = await ctx.device();
    final size = await device.screenSize();
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
    await device.swipePath(path);
    out('swiped ${direction.name}: $path');
    await runPostActions();
    return 0;
  }
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

class LogcatCommand extends QaCommand {
  LogcatCommand() {
    argParser
      ..addOption('lines', defaultsTo: '200', help: 'Tail this many lines.')
      ..addFlag('since-launch',
          negatable: false, help: 'Only lines since the last `qa run`.')
      ..addFlag('all', negatable: false, help: 'Do not filter to app lines.');
  }

  @override
  String get name => 'logcat';

  @override
  String get description => 'Dump the device log, filtered to the app by default.';

  /// `adb logcat`, not `adb shell logcat`: the device shell would split the
  /// space inside a `-T "MM-DD HH:MM:SS.mmm"` timestamp into two arguments.

  @override
  Future<int> run() async {
    final ctx = context;
    final adb = await ctx.adb();
    final args = <String>['logcat', '-d', '-v', 'time'];
    if (argResults!['since-launch'] as bool) {
      final stamp = File(ctx.paths.runStamp);
      if (!stamp.existsSync()) {
        throw DeviceFailure('no run.started stamp — run `qa run` first');
      }
      args.addAll(['-T', stamp.readAsStringSync().trim()]);
    }
    final result = await adb.raw(args, timeout: const Duration(seconds: 60));
    var lines = result.combined.split('\n');
    if (!(argResults!['all'] as bool)) lines = filterLogcat(lines);
    final limit = intOption('lines') ?? 200;
    if (lines.length > limit) lines = lines.sublist(lines.length - limit);
    for (final line in lines) {
      out(line.trimRight());
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
          help: 'Show the known-noise lines that are hidden by default.');
  }

  @override
  String get name => 'errors';

  @override
  String get description =>
      'Grep the run log and the device log for exceptions and [anta]/[qa] lines.';

  /// The device log is read as well as `run.log`: when the VM service
  /// handshake loses its race the app keeps running but its `print`s never
  /// reach `flutter run`, so they exist only in logcat.
  @override
  Future<int> run() async {
    final ctx = context;
    final limit = intOption('lines') ?? 50;
    final showAll = argResults!['all'] as bool;
    final sources = <String, List<String>>{};
    if (File(ctx.paths.runLog).existsSync()) {
      sources[ctx.paths.runLog] = errorLines(readRunLog(ctx.paths), limit: limit);
    }
    final adb = await ctx.adb();
    final resolvedPid = (await (await ctx.device()).probe()).appPid;
    // Scoped to the app's own process: an unrelated crash (a racing
    // `uiautomator` among them) would otherwise read as an app error.
    final logcat = await adb.raw(
      [
        'logcat',
        '-d',
        '-v',
        'time',
        if (resolvedPid != null) '--pid=$resolvedPid' else ...['-s', 'flutter:*'],
      ],
      timeout: const Duration(seconds: 60),
    );
    sources[resolvedPid == null ? 'logcat' : 'logcat(pid $resolvedPid)'] =
        errorLines(logcat.combined, limit: limit);

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
        out('$name: $line${!showAll || !isKnownNoise(line) ? '' : '  (known noise)'}');
      }
      if (!showAll && noise.isNotEmpty) {
        out('$name: ${noise.length} known-noise line(s) hidden (--all to show)');
      }
    });
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
              'Never restarts the emulator and never touches app data.')
      ..addFlag('json', negatable: false, help: 'Emit the checks as JSON.');
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check adb, the device, the app and the host run state, and say what to '
      'do about anything that is off.';

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

    final adbPath = ctx.sdk.findAdb();
    var devices = const <AdbDevice>[];
    String? adbFailure;
    if (adbPath != null) {
      try {
        devices = await Adb(executable: adbPath, runner: ctx.runner)
            .devices(timeout: const Duration(seconds: 5));
      } on QaException catch (e) {
        adbFailure = e.message;
      }
    }
    results.add(checkAdbServer(
      adbPath: adbPath,
      failure: adbFailure,
      deviceCount: devices.length,
    ));
    results.add(checkDeviceAttached(devices));

    if (devices.any((d) => d.usable)) {
      results.addAll(await _deviceChecks(ctx));
    }
    results.addAll(await _hostChecks(ctx));
    return results;
  }

  Future<List<CheckResult>> _deviceChecks(QaContext ctx) async {
    final results = <CheckResult>[];
    final adb = await ctx.adb();
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
    final probe = await (await ctx.device()).probe();
    results.add(checkAwake(probe));
    results.add(checkScreenOverride(probe));
    results.add(checkAppInstalled(pmPath: outputs[2], runAsId: outputs[3]));
    results.add(checkAppRunning(probe, antaPackage));

    final started = DateTime.now();
    var dumped = false;
    try {
      await (await ctx.device()).dumpUiXml();
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
    return results;
  }

  Future<List<CheckResult>> _hostChecks(QaContext ctx) async {
    final results = <CheckResult>[];
    final pidFile = File(ctx.paths.runPid);
    final recordedPid = pidFile.existsSync()
        ? int.tryParse(pidFile.readAsStringSync().trim())
        : null;
    final alive =
        recordedPid == null ? false : await isProcessAlive(recordedPid, ctx.runner);
    final orphans = await _listOrphans(ctx);
    results.add(checkHostRun(
      recordedPid: recordedPid,
      pidAlive: alive,
      orphanedServices: orphans,
    ));
    final dtdFile = File(ctx.paths.dtdTxt);
    results.add(checkDtd(
      dtd: dtdFile.existsSync() ? dtdFile.readAsStringSync() : '',
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

  /// Orphaned development services, listed without killing anything.
  Future<List<int>> _listOrphans(QaContext ctx) async {
    if (!Platform.isWindows) return const [];
    final result = await ctx.runner.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', orphanedDdsListScript],
      timeout: const Duration(seconds: 30),
    );
    return result.stdout
        .split('\n')
        .map((line) => int.tryParse(line.trim()))
        .whereType<int>()
        .toList();
  }

  Future<List<String>> _applyFixes(List<CheckResult> results) async {
    final ctx = context;
    final applied = <String>[];
    for (final result in results) {
      final fix = result.fixVerb;
      if (fix == null) continue;
      switch (fix) {
        case DoctorFix.wake:
          final adb = await ctx.adb();
          await adb.shellBatch(const [
            ShellCommand(['input', 'keyevent', 'KEYCODE_WAKEUP']),
            ShellCommand(['wm', 'dismiss-keyguard']),
          ]);
          applied.add('woke the screen and dismissed the keyguard');
        case DoctorFix.unphone:
          await (await ctx.adb()).shellLenient(['wm', 'size', 'reset']);
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
