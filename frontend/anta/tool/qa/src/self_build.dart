import 'dart:io';

import 'errors.dart';
import 'paths.dart';
import 'process_runner.dart';

/// Environment variable that turns the automatic rebuild off entirely.
const String noSelfRebuildEnv = 'QA_NO_SELF_REBUILD';

/// What [decideRebuild] concluded about the exe currently running.
class RebuildDecision {
  const RebuildDecision({required this.rebuild, this.reason});

  final bool rebuild;

  /// The newest source that is younger than the exe, when [rebuild] is true.
  final String? reason;

  static const RebuildDecision no = RebuildDecision(rebuild: false);
}

/// Whether the compiled `qa` binary is older than the sources it was built
/// from.
///
/// [aot] is false when the tool is running under `dart run`, which always has
/// the current sources and therefore never rebuilds. [exeModified] being null
/// means the exe is gone, which the wrapper scripts handle before Dart starts,
/// so it is treated as "nothing to compare" rather than as stale.
RebuildDecision decideRebuild({
  required bool aot,
  required bool disabled,
  required DateTime? exeModified,
  required Map<String, DateTime> sourceModified,
}) {
  if (!aot || disabled || exeModified == null) return RebuildDecision.no;
  String? newest;
  DateTime? newestAt;
  sourceModified.forEach((path, modified) {
    if (!modified.isAfter(exeModified)) return;
    if (newestAt == null || modified.isAfter(newestAt!)) {
      newest = path;
      newestAt = modified;
    }
  });
  if (newest == null) return RebuildDecision.no;
  return RebuildDecision(rebuild: true, reason: newest);
}

/// Modification times of everything the compiled exe is built from.
Map<String, DateTime> qaSourceTimes(QaPaths paths) {
  final times = <String, DateTime>{};
  final dir = Directory(paths.toolQaDir);
  if (dir.existsSync()) {
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      times[entity.path] = entity.statSync().modified;
    }
  }
  final lock = File(paths.pubspecLock);
  if (lock.existsSync()) times[lock.path] = lock.statSync().modified;
  return times;
}

/// Locates a real `dart` binary, never the `.bat` shim.
///
/// `Process.start` on Windows goes through `CreateProcess`, which cannot run a
/// batch file, and `dart` on PATH here **is** `dart.bat`. The VM running this
/// code is the best answer when there is one; otherwise the Flutter SDK's own
/// `dart-sdk` cache has the executable the shim would have called.
String findDart({Map<String, String>? environment}) {
  final resolved = Platform.resolvedExecutable;
  if (_isDartLauncher(resolved) && File(resolved).existsSync()) return resolved;
  final env = environment ?? Platform.environment;
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final separator = Platform.isWindows ? ';' : ':';
  for (final dir in (env['PATH'] ?? env['Path'] ?? '').split(separator)) {
    if (dir.isEmpty) continue;
    final candidate = joinPath(dir, [name]);
    if (File(candidate).existsSync()) return candidate;
  }
  for (final key in const ['FLUTTER_ROOT', 'DART_SDK']) {
    final root = env[key];
    if (root == null || root.isEmpty) continue;
    for (final parts in [
      ['bin', 'cache', 'dart-sdk', 'bin', name],
      ['bin', name],
    ]) {
      final candidate = joinPath(root, parts);
      if (File(candidate).existsSync()) return candidate;
    }
  }
  final flutterBin = _flutterBinOnPath(env, separator);
  if (flutterBin != null) {
    final candidate =
        joinPath(flutterBin, ['cache', 'dart-sdk', 'bin', name]);
    if (File(candidate).existsSync()) return candidate;
  }
  throw DeviceFailure(
    'no dart executable found. Put the Dart or Flutter SDK bin directory on '
    'PATH, or set FLUTTER_ROOT.',
  );
}

String? _flutterBinOnPath(Map<String, String> env, String separator) {
  final shim = Platform.isWindows ? 'flutter.bat' : 'flutter';
  for (final dir in (env['PATH'] ?? env['Path'] ?? '').split(separator)) {
    if (dir.isEmpty) continue;
    if (File(joinPath(dir, [shim])).existsSync()) return dir;
  }
  return null;
}

/// Compiles `tool/qa/qa.dart` to [output] and returns how long it took.
Future<Duration> compileQaExe({
  required QaPaths paths,
  required ProcessRunner runner,
  required String output,
}) async {
  paths.ensureBuildQa();
  final started = DateTime.now();
  final result = await runner.run(
    findDart(),
    [
      'compile',
      'exe',
      joinPath('tool', ['qa', 'qa.dart']),
      '-o',
      output,
    ],
    timeout: const Duration(minutes: 5),
    workingDirectory: paths.projectRoot,
  );
  if (!result.ok) {
    throw DeviceFailure(
      'dart compile exe failed (${result.exitCode}):\n${result.combined}',
    );
  }
  return DateTime.now().difference(started);
}

/// Replaces the running exe with a freshly compiled one and keeps going.
///
/// Windows will not delete or overwrite a running image but it will happily
/// **rename** one, so the swap is: build beside it, move the running file out
/// of the way, move the new one into place. The displaced `.old` cannot be
/// deleted while this process is alive, so it is left for the next start to
/// clear — which [clearStaleExe] does.
Future<void> swapInNewExe(QaPaths paths) async {
  final current = File(paths.qaExe);
  final built = File(paths.qaExeNew);
  if (!built.existsSync()) {
    throw DeviceFailure('the rebuild produced no ${paths.qaExeNew}');
  }
  if (current.existsSync()) {
    final old = File(paths.qaExeOld);
    if (old.existsSync()) {
      try {
        old.deleteSync();
      } on FileSystemException catch (e) {
        throw DeviceFailure(
          'cannot replace ${paths.qaExeOld} (another qa still running?): '
          '${e.osError?.message ?? e.message}',
        );
      }
    }
    current.renameSync(paths.qaExeOld);
  }
  built.renameSync(paths.qaExe);
}

/// Deletes the displaced exe a previous self-rebuild had to leave behind.
void clearStaleExe(QaPaths paths) {
  final old = File(paths.qaExeOld);
  if (!old.existsSync()) return;
  try {
    old.deleteSync();
  } on FileSystemException {
    return;
  }
}

/// Runs the staleness check for a real invocation, rebuilding when needed.
///
/// Returns the message that was reported, or null when nothing happened, so
/// the caller can stay silent on the common path.
Future<String?> refreshQaExe({
  required QaPaths paths,
  required ProcessRunner runner,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final resolved = Platform.resolvedExecutable;
  final aot = !_isDartLauncher(resolved);
  final decision = decideRebuild(
    aot: aot,
    disabled: (env[noSelfRebuildEnv] ?? '').isNotEmpty,
    exeModified: aot && File(resolved).existsSync()
        ? File(resolved).statSync().modified
        : null,
    sourceModified: aot ? qaSourceTimes(paths) : const {},
  );
  if (aot) clearStaleExe(paths);
  if (!decision.rebuild) return null;
  final message =
      'qa: sources changed since qa.exe was built — rebuilding…';
  stderr.writeln(message);
  await compileQaExe(paths: paths, runner: runner, output: paths.qaExeNew);
  await swapInNewExe(paths);
  return message;
}

bool _isDartLauncher(String executable) {
  final name = executable.split(RegExp(r'[\\/]')).last.toLowerCase();
  return name == 'dart' || name == 'dart.exe';
}
