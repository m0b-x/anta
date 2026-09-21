import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../qa/src/adb.dart';
import '../qa/src/doctor.dart' show checkAdbServer;
import '../qa/src/paths.dart';
import '../qa/src/process_runner.dart';
import '../qa/src/runner.dart' show findFlutter;
import '../qa/src/self_build.dart' show findDart;
import 'src/abi.dart';
import 'src/doctor.dart';
import 'src/errors.dart';
import 'src/gradle_daemons.dart';
import 'src/host.dart';
import 'src/install.dart';
import 'src/locks.dart';
import 'src/pipeline.dart';
import 'src/signing.dart';

Future<void> main(List<String> arguments) async {
  var code = 0;
  try {
    code = await ReleaseCommandRunner().run(arguments) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln('');
    stderr.writeln(e.usage);
    code = exitUsage;
  } on QaException catch (e) {
    stderr.writeln('release: ${e.message}');
    code = e.code;
  }
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

class ReleaseCommandRunner extends CommandRunner<int> {
  ReleaseCommandRunner()
      : super(
          'release',
          'Builds and installs the ANTA release APK, the same way on Windows '
              'and macOS.',
        ) {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Echo every command before it runs.',
    );
    addCommand(BuildCommand());
    addCommand(InstallCommand());
    addCommand(DoctorCommand());
    addCommand(GenCommand());
    addCommand(CleanCommand());
  }
}

abstract class _ReleaseCommand extends Command<int> {
  bool get verbose => globalResults?['verbose'] == true;

  late final QaPaths paths = QaPaths.locate();

  late final Host host =
      Host(projectRoot: paths.projectRoot, verbose: verbose);

  late final ProcessRunner processes = RealProcessRunner(verbose: verbose);

  Future<void> runSteps(List<Step> steps) async {
    for (var i = 0; i < steps.length; i++) {
      await host.runStep(steps[i], index: i + 1, total: steps.length);
      if (steps[i].kind == StepKind.clean) await host.ensureDeleted('build');
    }
  }

  /// Refuses a release that would not be signed like the installed app, frees
  /// the locks a rebuild trips over, runs the plan and returns the APK.
  Future<File> buildApk(BuildOptions options) async {
    final signing = readSigningStatus(paths.projectRoot);
    if (!signing.ready) {
      if (!options.allowDebugSigning) {
        throw BuildFailure('${signing.describe()}.\n$signingRemedy');
      }
      stdout.writeln(
        'warning: ${signing.describe()}; building it debug-signed because '
        'of --allow-debug-signing. It will not install over the real app.',
      );
    }
    final missing = missingFirebaseFiles(paths.projectRoot);
    if (missing.isNotEmpty) {
      throw BuildFailure(
        'missing ${missing.join(' and ')} (gitignored): run `flutterfire '
        'configure --platforms=android,ios` or copy them from another '
        'checkout.',
      );
    }
    final notes = await releaseBuildLocks(
      projectRoot: paths.projectRoot,
      runner: processes,
      scope: options.clean ? DaemonScope.all : DaemonScope.staleOnly,
    );
    for (final note in notes) {
      stdout.writeln('locks: $note');
    }
    await runSteps(planBuild(options, host.toolchain));
    final apk = File(joinPath(paths.projectRoot, apkPathParts));
    if (!apk.existsSync()) {
      throw BuildFailure(
        'flutter build apk finished but ${apk.path} is not there',
      );
    }
    final megabytes = (apk.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    stdout.writeln();
    stdout.writeln('APK: ${apk.path} ($megabytes MB)');
    stdout.writeln('Symbols for stack traces: $debugInfoDir/');
    return apk;
  }
}

void _addBuildOptions(ArgParser parser, {required bool forInstall}) {
  parser
    ..addOption(
      'abi',
      allowed: const ['all', 'arm64', 'arm', 'x64'],
      help: forInstall
          ? 'ABI to build for. Default: whatever the target device reports.'
          : 'ABIs to build for. Default: all, a fat APK.',
    )
    ..addFlag('arm64', negatable: false, help: 'Shorthand for --abi arm64.')
    ..addFlag(
      'clean',
      negatable: false,
      help: '`flutter clean` first (cold Gradle and build_runner, about twice '
          'as slow).',
    )
    ..addFlag(
      'gen',
      defaultsTo: true,
      help: 'Run build_runner and gen-l10n before building.',
    )
    ..addFlag(
      'allow-debug-signing',
      negatable: false,
      help: 'Build without the release keystore. The APK is debug-signed and '
          'cannot install over the real app.',
    );
}

BuildOptions _buildOptions(ArgResults results, {required TargetAbi fallback}) {
  final abiOption = results['abi'] as String?;
  final abi = results['arm64'] == true
      ? TargetAbi.arm64
      : abiOption == null
          ? fallback
          : TargetAbi.parse(abiOption);
  return BuildOptions(
    abi: abi,
    clean: results['clean'] as bool,
    codegen: results['gen'] as bool,
    allowDebugSigning: results['allow-debug-signing'] as bool,
  );
}

class BuildCommand extends _ReleaseCommand {
  BuildCommand() {
    _addBuildOptions(argParser, forInstall: false);
    argParser.addFlag(
      'open',
      defaultsTo: true,
      help: 'Show the output folder afterwards.',
    );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Generate code, then build the obfuscated release APK.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final apk =
        await buildApk(_buildOptions(results, fallback: TargetAbi.all));
    if (results['open'] as bool) host.openFolder(apk.parent.path);
    return 0;
  }
}

class InstallCommand extends _ReleaseCommand {
  InstallCommand() {
    _addBuildOptions(argParser, forInstall: true);
    argParser.addOption(
      'device',
      abbr: 'd',
      help: 'adb serial to install on. Default: the only phone attached '
          '(an emulator only when no phone is).',
    );
  }

  @override
  String get name => 'install';

  @override
  String get description =>
      "Build for the attached phone's ABI and install it over USB.";

  @override
  Future<int> run() async {
    final results = argResults!;
    final adb = Adb(executable: SdkTools().requireAdb(), runner: processes);
    final devices = await adb.devices();
    final serial = selectInstallSerial(
      explicit: results['device'] as String?,
      devices: devices,
    );
    final device = adb.withSerial(serial);
    var options = _buildOptions(results, fallback: TargetAbi.all);
    if (results['abi'] == null && results['arm64'] != true) {
      final reported =
          await device.shellLenient(['getprop', 'ro.product.cpu.abi']);
      final abi = TargetAbi.fromDeviceAbi(reported);
      if (abi == null) {
        stdout.writeln(
          '$serial reports ABI "${reported.trim()}", which has no single '
          'Flutter target; building all ABIs.',
        );
      } else {
        options = options.withAbi(abi);
      }
    }
    final model = devices.firstWhere((d) => d.serial == serial).model;
    stdout.writeln(
      'Target: $serial${model == null ? '' : ' ($model)'}, '
      '${options.abi.label}',
    );
    final apk = await buildApk(options);
    stdout.writeln();
    stdout.writeln('Installing on $serial...');
    final result = await device.raw(
      ['install', '-r', apk.path],
      timeout: const Duration(minutes: 5),
    );
    final output = result.combined;
    if (!result.ok || output.contains('Failure')) {
      throw DeviceFailure(
        installFailureMessage(
          classifyInstallFailure(output),
          serial: serial,
          output: output,
        ),
      );
    }
    stdout.writeln('Installed on $serial.');
    return 0;
  }
}

class DoctorCommand extends _ReleaseCommand {
  DoctorCommand() {
    argParser.addFlag(
      'fix',
      negatable: false,
      help: 'Stop Gradle daemons of other versions.',
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check what a release build and install need on this machine.';

  @override
  Future<int> run() async {
    final root = paths.projectRoot;
    final results = <CheckResult>[
      checkTool(
        'flutter',
        _tryFind(findFlutter),
        fix: 'put the Flutter SDK bin directory on PATH or set FLUTTER_ROOT',
      ),
      checkTool(
        'dart',
        _tryFind(findDart),
        fix: 'put the Dart or Flutter SDK bin directory on PATH',
      ),
      checkSigning(readSigningStatus(root)),
      checkFirebaseConfig(missingFirebaseFiles(root)),
    ];
    final wrapper = File(joinPath(
      root,
      ['android', 'gradle', 'wrapper', 'gradle-wrapper.properties'],
    ));
    final version = wrapper.existsSync()
        ? wrapperVersion(wrapper.readAsStringSync())
        : null;
    var daemons = await listGradleDaemons(processes);
    if (argResults!['fix'] as bool) {
      final stopped = stopDaemons(staleDaemons(daemons, keepVersion: version));
      if (stopped.isNotEmpty) {
        stdout.writeln('stopped Gradle daemon(s) pid ${stopped.join(', ')}');
        daemons = await listGradleDaemons(processes);
      }
    }
    results.add(checkGradleDaemons(wrapperVersion: version, daemons: daemons));
    if (Platform.isWindows) {
      results.add(checkExplorerWindows(await explorerWindowsUnder(
        joinPath(root, ['build']),
        processes,
        close: false,
      )));
    }
    final adbPath = SdkTools().findAdb();
    List<AdbDevice> devices = const [];
    String? adbFailure;
    if (adbPath != null) {
      try {
        devices = await Adb(executable: adbPath, runner: processes).devices();
      } on QaException catch (e) {
        adbFailure = e.message;
      }
    }
    results
      ..add(checkAdbServer(
        adbPath: adbPath,
        failure: adbFailure,
        deviceCount: devices.length,
      ))
      ..add(checkInstallTarget(devices));
    for (final result in results) {
      stdout.writeln(result.describe());
    }
    return anyFailed(results) ? exitUsage : 0;
  }

  static String? _tryFind(String Function() find) {
    try {
      return find();
    } on QaException {
      return null;
    }
  }
}

class GenCommand extends _ReleaseCommand {
  GenCommand() {
    argParser.addFlag(
      'watch',
      negatable: false,
      help: 'Keep build_runner watching instead of a one-off build.',
    );
  }

  @override
  String get name => 'gen';

  @override
  String get description => 'Run build_runner and gen-l10n.';

  @override
  Future<int> run() async {
    await runSteps(
      planGen(host.toolchain, watch: argResults!['watch'] as bool),
    );
    return 0;
  }
}

class CleanCommand extends _ReleaseCommand {
  @override
  String get name => 'clean';

  @override
  String get description =>
      'flutter clean, drop .dart_tool and fetch packages again, after freeing '
      'the Windows file locks that make a clean fail.';

  @override
  Future<int> run() async {
    final notes = await releaseBuildLocks(
      projectRoot: paths.projectRoot,
      runner: processes,
      scope: DaemonScope.all,
    );
    for (final note in notes) {
      stdout.writeln('locks: $note');
    }
    final steps = planClean(host.toolchain);
    await host.runStep(steps[0], index: 1, total: steps.length);
    await host.ensureDeleted('build');
    await host.ensureDeleted('.dart_tool');
    await host.runStep(steps[1], index: 2, total: steps.length);
    stdout.writeln();
    stdout.writeln('Clean. `release gen` regenerates the .g.dart files.');
    return 0;
  }
}
