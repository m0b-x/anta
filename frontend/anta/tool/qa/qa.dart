import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'src/adb.dart';
import 'src/device.dart';
import 'src/errors.dart';
import 'src/gestures.dart';
import 'src/input_text.dart';
import 'src/log_parse.dart';
import 'src/markers.dart';
import 'src/paths.dart';
import 'src/process_runner.dart';
import 'src/runner.dart';
import 'src/shots.dart';
import 'src/target.dart';
import 'src/ui_tree.dart';

Future<void> main(List<String> arguments) async {
  final runner = QaCommandRunner();
  try {
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

class QaCommandRunner extends CommandRunner<int> {
  QaCommandRunner()
      : super(
          'qa',
          'Drive the ANTA app on a device from the command line.\n'
              'Run with: dart run tool/qa/qa.dart <verb>\n'
              'Compile for speed: dart compile exe tool/qa/qa.dart -o build/qa/qa.exe',
        ) {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device serial. Falls back to ANTA_QA_DEVICE, then the sole '
            'attached device, then $defaultSerial.',
      )
      ..addFlag('verbose', help: 'Echo every process invocation to stderr.');

    addCommand(DevicesCommand());
    addCommand(StateCommand());
    addCommand(BootCommand());
    addCommand(UnphoneCommand());
    addCommand(RunAppCommand());
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
    addCommand(LogcatCommand());
    addCommand(ErrorsCommand());
  }
}

class QaContext {
  QaContext(this.globalResults);

  final ArgResults globalResults;

  late final QaPaths paths = QaPaths.locate();
  late final bool verbose = globalResults['verbose'] as bool? ?? false;
  late final ProcessRunner runner = RealProcessRunner(verbose: verbose);
  late final SdkTools sdk = SdkTools();

  Adb? _adb;
  Device? _device;

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

  Future<Device> device() async => _device ??= AndroidDevice(await adb());

  Future<UiTree> dump() async => (await device()).dumpUi();

  Future<ResolvedTarget> resolve(String target, {int? nth}) async =>
      TargetResolver(await dump()).resolve(target, nth: nth);
}

abstract class QaCommand extends Command<int> {
  QaContext get context => QaContext(globalResults!);

  void out(String line) => stdout.writeln(line);

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
      'Report the device, the app process, the foreground activity and the run files.';

  @override
  Future<int> run() async {
    final ctx = context;
    final adb = await ctx.adb();
    final device = AndroidDevice(adb);
    final size = await device.screenSize();
    final pid = await device.appPid(antaPackage);
    final activities = await adb.shellLenient(['dumpsys', 'activity', 'activities']);
    final resumed = _resumedActivity(activities);
    final dtdFile = File(ctx.paths.dtdTxt);
    final dtd = dtdFile.existsSync() ? dtdFile.readAsStringSync().trim() : '';
    final logExists = File(ctx.paths.runLog).existsSync();

    if (argResults!['json'] as bool) {
      out(const JsonEncoder.withIndent('  ').convert({
        'device': device.id,
        'pid': pid,
        'resumedActivity': resumed,
        'physical': '${size.physicalWidth}x${size.physicalHeight}',
        'override': size.isOverridden ? '${size.width}x${size.height}' : null,
        'density': size.density,
        'dp': '${size.widthDp}x${size.heightDp}',
        'runLog': logExists ? ctx.paths.runLog : null,
        'dtd': dtd.isEmpty ? null : dtd,
      }));
      return 0;
    }
    out('device=${device.id}  app=${pid == null ? 'not running' : 'pid $pid'}  '
        'resumed=${resumed ?? 'unknown'}  screen=$size  '
        'run.log=${logExists ? 'yes' : 'no'}  dtd=${dtd.isEmpty ? 'no' : dtd}');
    return 0;
  }

  static String? _resumedActivity(String dumpsys) {
    for (final line in dumpsys.split('\n')) {
      if (!line.contains('mResumedActivity') &&
          !line.contains('topResumedActivity')) {
        continue;
      }
      final match = RegExp(r'([A-Za-z0-9_.]+/[A-Za-z0-9_.]+)').firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
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
    final attached = (await bare.devices()).where((d) => d.usable).toList();
    if (attached.isNotEmpty) {
      out('emulator already up: ${attached.map((d) => d.serial).join(', ')} '
          '(never killed or restarted by this tool)');
    } else {
      await _startEmulator(ctx);
      await _awaitBoot(bare);
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

  Future<void> _startEmulator(QaContext ctx) async {
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
    out('starting emulator $avd...');
    await Process.start(
      emulator,
      ['-avd', avd, if (argResults!['cold'] as bool) '-no-snapshot-load'],
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> _awaitBoot(Adb bare) async {
    final deadline = DateTime.now().add(const Duration(minutes: 6));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final devices = (await bare.devices()).where((d) => d.usable).toList();
      if (devices.isEmpty) continue;
      final serial = devices.first.serial;
      final adb = bare.withSerial(serial);
      final booted = (await adb.shellLenient(['getprop', 'sys.boot_completed'])).trim();
      if (booted != '1') continue;
      final provisioned =
          (await adb.shellLenient(['settings', 'get', 'global', 'device_provisioned']))
              .trim();
      if (provisioned == '1') return;
    }
    throw DeviceFailure('emulator did not finish booting within 6 minutes');
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
      onProgress: ctx.verbose ? (line) => stderr.writeln('  $line') : null,
    );
    out('pid=${result.pid}  log=${result.logPath}');
    out('dtd=${result.uris.dtd}');
    out('vm=${result.uris.vmService}');
    return 0;
  }
}

class RunAppCommand extends LaunchingCommand {
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
    if (argResults!['fresh'] as bool) {
      await dropResetMarker(adb);
      out('qa_reset marker dropped');
    }
    final seed = argResults!['seed'] as String?;
    if (seed != null && seed.isNotEmpty) {
      final path = ctx.paths.resolve(seed);
      await pushSeed(adb, path);
      out('qa_seed.json pushed from $path');
    }
    await AndroidDevice(adb).forceStop(antaPackage);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return launch('run');
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

class LaunchCommand extends QaCommand {
  @override
  String get name => 'launch';

  @override
  String get description =>
      'Start the already installed build with `am start` (no flutter run).';

  @override
  Future<int> run() async {
    await (await context.device()).launchActivity(antaActivity);
    out('launched $antaActivity');
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
      ..addFlag('json', negatable: false, help: 'Emit the nodes as JSON.');
  }

  @override
  String get name => 'dump';

  @override
  String get description =>
      'Print the accessibility tree as one compact line per node.';

  @override
  Future<int> run() async {
    final tree = await context.dump();
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
        '${all ? '' : ' (pass --all for the rest)'}');
    return 0;
  }
}

abstract class TargetCommand extends QaCommand {
  TargetCommand() {
    argParser.addOption('nth',
        help: 'Pick the Nth match (0-based) when a label is ambiguous.');
  }

  Future<ResolvedTarget> target() async =>
      context.resolve(requireRest('a target'), nth: intOption('nth'));
}

class TapCommand extends TargetCommand {
  @override
  String get name => 'tap';

  @override
  String get description =>
      'Tap a target: a label, `id:foo`, `#12` or `x,y`.';

  @override
  Future<int> run() async {
    final ctx = context;
    final tree = await ctx.dump();
    final resolved =
        TargetResolver(tree).resolve(requireRest('a target'), nth: intOption('nth'));
    final node = resolved.node;
    var point = (resolved.x, resolved.y);
    var description = resolved.description;
    if (node != null && !node.clickable) {
      final clickable = tree.clickableSelfOrAncestor(node);
      if (clickable != null && clickable.index != node.index) {
        point = (clickable.bounds.centreX, clickable.bounds.centreY);
        description = '${node.label} via ${clickable.describe()}';
      }
    }
    await (await ctx.device()).tap(point.$1, point.$2);
    out('tapped ${point.$1},${point.$2}  $description');
    return 0;
  }
}

class LongPressCommand extends TargetCommand {
  LongPressCommand() {
    argParser.addOption('ms', defaultsTo: '800', help: 'Press duration.');
  }

  @override
  String get name => 'longpress';

  @override
  String get description => 'Long-press a target (a swipe with no travel).';

  @override
  Future<int> run() async {
    final ctx = context;
    final resolved = await target();
    final ms = intOption('ms') ?? 800;
    await (await ctx.device())
        .swipePath(SwipePath(resolved.x, resolved.y, resolved.x, resolved.y, ms));
    out('long-pressed ${resolved.x},${resolved.y} for ${ms}ms  ${resolved.description}');
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
    final resolved = await target();
    final node = resolved.node;
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
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    final nth = intOption('nth');
    while (true) {
      ResolvedTarget? found;
      try {
        found = TargetResolver(await ctx.dump()).resolve(wanted, nth: nth);
      } on TargetFailure {
        found = null;
      }
      if (gone && found == null) {
        out('gone: "$wanted"');
        return 0;
      }
      if (!gone && found != null) {
        out('found: ${found.description}');
        return 0;
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw TargetFailure(
          gone
              ? '"$wanted" was still present after ${seconds}s'
              : '"$wanted" did not appear within ${seconds}s',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
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

    for (var attempt = 0; attempt <= maxSwipes; attempt++) {
      final tree = await ctx.dump();
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
    throw TargetFailure('"$wanted" not reachable after $maxSwipes swipe(s)');
  }
}

class TypeCommand extends QaCommand {
  TypeCommand() {
    argParser.addFlag('enter',
        negatable: false, help: 'Send ENTER after the text.');
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
    await device.typeText(text);
    if (argResults!['enter'] as bool) {
      await device.key('enter');
    }
    out('typed "$text"${argResults!['enter'] as bool ? ' + ENTER' : ''}');
    return 0;
  }
}

class KeyCommand extends QaCommand {
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
    return 0;
  }
}

class SwipeCommand extends QaCommand {
  SwipeCommand() {
    argParser
      ..addOption('from', help: 'Start point as x,y. Defaults to the centre.')
      ..addOption('dist', help: 'Travel in pixels. Defaults to half the screen.')
      ..addOption('ms', defaultsTo: '300', help: 'Duration of the gesture.');
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
    return 0;
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
    argParser.addOption('lines', defaultsTo: '50', help: 'Keep the last N hits.');
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
    final sources = <String, List<String>>{};
    if (File(ctx.paths.runLog).existsSync()) {
      sources[ctx.paths.runLog] = errorLines(readRunLog(ctx.paths), limit: limit);
    }
    final adb = await ctx.adb();
    final pid = await AndroidDevice(adb).appPid(antaPackage);
    // Scoped to the app's own process: an unrelated crash (a racing
    // `uiautomator` among them) would otherwise read as an app error.
    final logcat = await adb.raw(
      [
        'logcat',
        '-d',
        '-v',
        'time',
        if (pid != null) '--pid=$pid' else ...['-s', 'flutter:*'],
      ],
      timeout: const Duration(seconds: 60),
    );
    sources[pid == null ? 'logcat' : 'logcat(pid $pid)'] =
        errorLines(logcat.combined, limit: limit);

    sources.forEach((name, hits) {
      if (hits.isEmpty) {
        out('no errors in $name');
        return;
      }
      for (final line in hits) {
        out('$name: $line');
      }
    });
    return 0;
  }
}
