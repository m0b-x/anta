import 'dart:io';

import 'errors.dart';
import 'log_parse.dart';
import 'paths.dart';
import 'process_runner.dart';

/// Dart-defines that switch the app into its isolated QA mode.
const List<String> qaDefines = [
  'ANTA_QA=true',
  'ANTA_QA_DB=qa',
];

/// Entry point that installs the Flutter Driver extension.
const String driverTarget = 'test_driver/main_driver.dart';

/// Builds the `flutter run` / `flutter attach` argument vector.
List<String> buildFlutterArgs({
  required String command,
  required String deviceId,
  bool qa = true,
  bool driver = true,
  List<String> extraDefines = const [],
}) {
  return [
    command,
    '--print-dtd',
    '-d',
    deviceId,
    if (command == 'run' && driver) ...['-t', driverTarget],
    if (qa)
      for (final define in qaDefines) '--dart-define=$define',
    for (final define in extraDefines) '--dart-define=$define',
  ];
}

/// Result of launching a detached `flutter run`.
class LaunchResult {
  const LaunchResult({
    required this.pid,
    required this.uris,
    required this.logPath,
  });

  final int pid;
  final RunUris uris;
  final String logPath;
}

/// Timestamp in the `MM-DD HH:MM:SS.mmm` shape `adb logcat -T` accepts.
String logcatStamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(now.month)}-${two(now.day)} ${two(now.hour)}:'
      '${two(now.minute)}:${two(now.second)}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}

/// Writes the OS-specific wrapper that redirects the run's output to the log.
///
/// A wrapper is used so the child survives this CLI exiting: the wrapper owns
/// the redirection, so nothing is ever written to the pipes this process
/// leaves behind. On Windows `taskkill /T` takes the `cmd` tree down; on POSIX
/// `exec` replaces the shell so the recorded pid is the real one.
File writeLaunchWrapper({
  required QaPaths paths,
  required String flutterExecutable,
  required List<String> arguments,
}) {
  paths.ensureBuildQa();
  final quoted = arguments.map(_quote).join(' ');
  if (Platform.isWindows) {
    final file = File(joinPath(paths.buildQa, ['run_cmd.bat']));
    // The idle loop on the left of the pipe writes nothing and never exits, so
    // `flutter run`'s stdin stays open without ever delivering a keystroke. A
    // resident runner quits the moment stdin reports end-of-file, which is
    // what a redirected file or a closed pipe hands it seconds after startup.
    file.writeAsStringSync(
      '@echo off\r\n'
      'cd /d "${paths.projectRoot}"\r\n'
      '(for /l %%i in (1,0,2) do @ping -n 61 127.0.0.1 >nul) | '
      '"$flutterExecutable" $quoted\r\n',
    );
    return file;
  }
  final file = File(joinPath(paths.buildQa, ['run_cmd.sh']));
  file.writeAsStringSync(
    '#!/bin/sh\n'
    'cd "${paths.projectRoot}" || exit 3\n'
    'exec "$flutterExecutable" $quoted > "${paths.runLog}" 2>&1\n',
  );
  Process.runSync('chmod', ['+x', file.path]);
  return file;
}

String _quote(String arg) =>
    arg.contains(' ') || arg.isEmpty ? '"$arg"' : arg;

/// Finds the `flutter` launcher, preferring the one on PATH.
String findFlutter({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final separator = Platform.isWindows ? ';' : ':';
  for (final dir in (env['PATH'] ?? env['Path'] ?? '').split(separator)) {
    if (dir.isEmpty) continue;
    final candidate = joinPath(dir, [name]);
    if (File(candidate).existsSync()) return candidate;
  }
  final root = env['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    final candidate = joinPath(root, ['bin', name]);
    if (File(candidate).existsSync()) return candidate;
  }
  throw DeviceFailure(
    'flutter launcher not found on PATH. Add the Flutter SDK bin directory to '
    'PATH or set FLUTTER_ROOT.',
  );
}

/// Starts the wrapper so that it outlives this process and holds no handle of
/// the shell that invoked us, and returns its pid.
///
/// Windows wants three things at once and no single start mode gives all
/// three. `flutter.bat` writes nothing at all under `DETACHED_PROCESS`, so a
/// plain detached start looks like a hang. A plain non-detached start inherits
/// the calling shell's stdout handle, so the shell never sees end-of-output
/// and the caller's prompt never returns. And a start that hands the child a
/// **console** makes `flutter run` take it for an interactive terminal, read
/// its key commands from stdin, see end-of-file and quit seconds after
/// printing its URIs.
///
/// `Start-Process` with stdout and stderr redirected to files gives the first
/// two; the third is the wrapper's business — see the idle pipe in
/// [writeLaunchWrapper]. Stdin is deliberately **not** redirected: pointing it
/// at a file stops `cmd` from building that pipe at all, and the run dies
/// anyway.
///
/// The launcher itself is started normally, not detached: `powershell.exe`
/// needs a console host as much as `flutter.bat` does, and dies silently
/// without one. Its own stdout is never read — the pid comes back through a
/// file, so nothing here waits on a pipe the long-lived tree also holds, which
/// is what would otherwise keep the caller's shell from returning.
Future<int> _startWrapper(QaPaths paths, File wrapper) async {
  if (!Platform.isWindows) {
    final process = await Process.start(
      '/bin/sh',
      [wrapper.path],
      mode: ProcessStartMode.detached,
      workingDirectory: paths.projectRoot,
    );
    return process.pid;
  }
  String quote(String value) => value.replaceAll("'", "''");
  final pidFile = File(paths.runPid);
  if (pidFile.existsSync()) pidFile.deleteSync();
  await Process.start(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$p = Start-Process -FilePath 'cmd.exe' "
          "-ArgumentList '/c','\"${quote(wrapper.path)}\"' "
          "-RedirectStandardOutput '${quote(paths.runLog)}' "
          "-RedirectStandardError '${quote(paths.runErr)}' "
          '-PassThru; '
          "Set-Content -Path '${quote(paths.runPid)}' -Value \$p.Id",
    ],
    mode: ProcessStartMode.normal,
  );
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!pidFile.existsSync()) continue;
    final pid = int.tryParse(pidFile.readAsStringSync().trim());
    if (pid != null) return pid;
  }
  throw DeviceFailure(
    'the run wrapper never reported a pid into ${paths.runPid}',
  );
}

/// Starts a background `flutter` command and waits for its service URIs.
Future<LaunchResult> launchDetached({
  required QaPaths paths,
  required String flutterExecutable,
  required List<String> arguments,
  Duration timeout = const Duration(minutes: 4),
  void Function(String)? onProgress,
}) async {
  paths.ensureBuildQa();
  try {
    File(paths.runLog).writeAsStringSync('');
    File(paths.runErr).writeAsStringSync('');
  } on FileSystemException {
    throw DeviceFailure(
      'another `flutter run` still holds ${paths.runLog}. '
      'Run `qa kill-run` first, or pass --no-kill-previous if that pid is '
      'not ours.',
    );
  }
  File(paths.dtdTxt).writeAsStringSync('');
  File(paths.vmTxt).writeAsStringSync('');
  File(paths.runStamp).writeAsStringSync(logcatStamp(DateTime.now()));

  final wrapper = writeLaunchWrapper(
    paths: paths,
    flutterExecutable: flutterExecutable,
    arguments: arguments,
  );
  final pid = await _startWrapper(paths, wrapper);

  final deadline = DateTime.now().add(timeout);
  const softGrace = Duration(seconds: 20);
  DateTime? softSeenAt;
  var lastReported = '';
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final text = readRunLog(paths);
    final uris = extractUris(text);
    if (uris.complete) {
      File(paths.dtdTxt).writeAsStringSync(uris.dtd!);
      File(paths.vmTxt).writeAsStringSync(uris.vmService!);
      return LaunchResult(pid: pid, uris: uris, logPath: paths.runLog);
    }
    final failure = launchFailureLine(text);
    if (failure != null) {
      throw DeviceFailure(
        'flutter ${arguments.first} failed: $failure\n${_tail(text)}',
      );
    }
    final soft = softLaunchFailureLine(text);
    if (soft != null) {
      softSeenAt ??= DateTime.now();
      if (DateTime.now().difference(softSeenAt) > softGrace) {
        throw DeviceFailure(
          'flutter ${arguments.first} did not recover from: $soft\n'
          'Re-run; the VM service handshake loses a race after a force-stop.\n'
          '${_tail(text)}',
        );
      }
    }
    if (onProgress != null) {
      final tail = text.trimRight().split('\n').last.trim();
      if (tail.isNotEmpty && tail != lastReported) {
        lastReported = tail;
        onProgress(tail);
      }
    }
  }
  throw DeviceFailure(
    'flutter ${arguments.first} did not report its service URIs within '
    '${timeout.inMinutes} minutes. Last log lines:\n${_tail(readRunLog(paths))}',
  );
}

String _tail(String text, {int lines = 25}) {
  final all = text.trimRight().split('\n');
  return all.sublist(all.length > lines ? all.length - lines : 0).join('\n');
}

/// Kills the `flutter run` recorded in `run.pid`, if any, and returns its pid.
///
/// On Windows the recorded pid is the `cmd` wrapper, so the whole tree goes.
Future<int?> killRecordedRun(QaPaths paths, ProcessRunner runner) async {
  final file = File(paths.runPid);
  if (!file.existsSync()) return null;
  final pid = int.tryParse(file.readAsStringSync().trim());
  file.deleteSync();
  if (pid == null) return null;
  if (Platform.isWindows) {
    await runner.run('taskkill', ['/PID', '$pid', '/T', '/F'],
        timeout: const Duration(seconds: 20));
  } else {
    try {
      Process.killPid(pid, ProcessSignal.sigterm);
    } on Object {
      return null;
    }
  }
  return pid;
}

/// PowerShell that kills every `dart development-service` whose parent process
/// is gone, and prints the pids it killed, one per line.
const String _orphanedDdsScript = r'''
Get-CimInstance Win32_Process -Filter "Name='dart.exe'" |
  Where-Object { $_.CommandLine -like '*development-service*' } |
  Where-Object { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $_.ProcessId }
''';

/// Kills leftover Dart Development Service processes that no longer have a
/// parent, and returns their pids.
///
/// A `flutter run` killed with `taskkill` can leave its DDS behind holding the
/// app's VM service. The next run's own DDS then cannot attach and the launch
/// dies with "Error connecting to the service protocol". Only true orphans are
/// touched, so a `flutter run` the owner has going is never disturbed.
Future<List<int>> reapOrphanedServices(ProcessRunner runner) async {
  if (!Platform.isWindows) return const [];
  final result = await runner.run(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', _orphanedDdsScript],
    timeout: const Duration(seconds: 30),
  );
  return result.stdout
      .split('\n')
      .map((line) => int.tryParse(line.trim()))
      .whereType<int>()
      .toList();
}

/// The run's output: stdout and stderr are separate files on Windows, because
/// `Start-Process` refuses to point both at one.
String readRunLog(QaPaths paths) =>
    [_readFile(paths.runLog), _readFile(paths.runErr)]
        .where((text) => text.isNotEmpty)
        .join('\n');

String _readFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return '';
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return '';
  }
}
