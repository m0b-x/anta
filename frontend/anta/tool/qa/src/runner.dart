import 'dart:convert';
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

/// Engine switches a bare launch passes so the debug build behaves as under
/// `flutter run` (asserts on) and its VM service answers on a known port with
/// no auth token — which is what lets the agent be reached without scraping
/// a log for the URI.
const List<String> _engineSwitches = [
  'enable-dart-profiling',
  'enable-checked-mode',
  'verify-entry-points',
  'disable-service-auth-codes',
];

/// `am start` extras: the Android embedding reads these from the intent.
List<String> androidLaunchExtras(int vmServicePort) => [
      for (final flag in _engineSwitches) ...['--ez', flag, 'true'],
      '--ei',
      'vm-service-port',
      '$vmServicePort',
    ];

/// App argv for `xcrun simctl launch`: the iOS embedding reads switches from
/// `NSProcessInfo.arguments`.
List<String> iosLaunchArguments(int vmServicePort) => [
      for (final flag in _engineSwitches) '--$flag',
      '--vm-service-port=$vmServicePort',
    ];

/// Environment for a desktop launch: the embedding reads
/// `FLUTTER_ENGINE_SWITCHES` and `FLUTTER_ENGINE_SWITCH_<n>`.
Map<String, String> desktopEngineEnvironment(int vmServicePort) {
  final switches = [
    for (final flag in _engineSwitches) '$flag=true',
    'vm-service-port=$vmServicePort',
  ];
  return {
    'FLUTTER_ENGINE_SWITCHES': '${switches.length}',
    for (var i = 0; i < switches.length; i++)
      'FLUTTER_ENGINE_SWITCH_${i + 1}': switches[i],
  };
}

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

/// How far back a recorded logcat stamp is dated.
///
/// `adb logcat -T` compares against the **device** clock, and the emulator's
/// runs a couple of seconds behind the host: a stamp taken on the host at the
/// moment of launch is in the guest's future, so the lines the launch is about
/// to print are filtered out and the wait looks like the app said nothing. A
/// margin costs a few extra lines and removes the whole class of failure.
const Duration logcatStampMargin = Duration(seconds: 15);

/// Timestamp in the `MM-DD HH:MM:SS.mmm` shape `adb logcat -T` accepts,
/// already backdated by [logcatStampMargin].
String logcatStamp(DateTime now) => rawLogcatStamp(now.subtract(logcatStampMargin));

/// The same format with no margin applied, for tests and for callers that
/// have their own clock-skew story.
String rawLogcatStamp(DateTime now) {
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
}) =>
    writeWrapperScript(
      paths: paths,
      baseName: 'run_cmd',
      executable: flutterExecutable,
      arguments: arguments,
      posixLogPath: paths.runLog,
      idleStdin: true,
    );

/// Writes one wrapper script that a detached start can own.
///
/// [idleStdin] is the third Windows trap and belongs only to `flutter run`:
/// the idle loop on the left of the pipe writes nothing and never exits, so
/// stdin stays open without ever delivering a keystroke. A resident runner on
/// Windows quits the moment stdin reports end-of-file, which is what a
/// redirected file or a closed pipe hands it seconds after startup. The
/// emulator does not read stdin at all, so it gets a plain invocation. On
/// POSIX the tool keeps running with stdin at `/dev/null` (checked on macOS,
/// 2026-09-16), so the script `exec`s the tool directly and the recorded pid
/// is the real one.
File writeWrapperScript({
  required QaPaths paths,
  required String baseName,
  required String executable,
  required List<String> arguments,
  required String posixLogPath,
  bool idleStdin = false,
  Map<String, String> environment = const {},
}) {
  paths.ensureBuildQa();
  final quoted = arguments.map(_quote).join(' ');
  if (Platform.isWindows) {
    final file = File(joinPath(paths.buildQa, ['$baseName.bat']));
    final idle = idleStdin
        ? '(for /l %%i in (1,0,2) do @ping -n 61 127.0.0.1 >nul) | '
        : '';
    final exports = environment.entries
        .map((e) => 'set "${e.key}=${e.value}"\r\n')
        .join();
    file.writeAsStringSync(
      '@echo off\r\n'
      'cd /d "${paths.projectRoot}"\r\n'
      '$exports'
      '$idle"$executable" $quoted\r\n',
    );
    return file;
  }
  final file = File(joinPath(paths.buildQa, ['$baseName.sh']));
  final exports = environment.entries
      .map((e) => "export ${e.key}='${e.value.replaceAll("'", r"'\''")}'\n")
      .join();
  file.writeAsStringSync(
    '#!/bin/sh\n'
    'cd "${paths.projectRoot}" || exit 3\n'
    '$exports'
    'exec "$executable" $quoted > "$posixLogPath" 2>&1\n',
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
Future<int> startWrapperDetached({
  required QaPaths paths,
  required File wrapper,
  required String logPath,
  required String errPath,
  required String pidPath,
}) async {
  if (!Platform.isWindows) {
    final process = await Process.start(
      '/bin/sh',
      [wrapper.path],
      mode: ProcessStartMode.detached,
      workingDirectory: paths.projectRoot,
    );
    File(pidPath).writeAsStringSync('${process.pid}');
    return process.pid;
  }
  String quote(String value) => value.replaceAll("'", "''");
  final pidFile = File(pidPath);
  if (pidFile.existsSync()) pidFile.deleteSync();
  await Process.start(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$p = Start-Process -FilePath 'cmd.exe' "
          "-ArgumentList '/c','\"${quote(wrapper.path)}\"' "
          "-RedirectStandardOutput '${quote(logPath)}' "
          "-RedirectStandardError '${quote(errPath)}' "
          '-PassThru; '
          "Set-Content -Path '${quote(pidPath)}' -Value \$p.Id",
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
  throw DeviceFailure('the wrapper never reported a pid into $pidPath');
}

/// Whether a pid is still running, without signalling it.
///
/// `boot` polls this so a launcher that died on its first second aborts the
/// wait instead of sitting out six minutes.
Future<bool> isProcessAlive(int pid, ProcessRunner runner) async {
  if (Platform.isWindows) {
    final result = await runner.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'if (Get-Process -Id $pid -ErrorAction SilentlyContinue) '
            "{ 'alive' } else { 'gone' }",
      ],
      timeout: const Duration(seconds: 20),
    );
    return result.stdout.contains('alive');
  }
  final result = await runner.run(
    '/bin/sh',
    ['-c', 'kill -0 $pid'],
    timeout: const Duration(seconds: 10),
  );
  return result.ok;
}

/// Starts a background `flutter` command and waits for its service URIs.
Future<LaunchResult> launchDetached({
  required QaPaths paths,
  required String flutterExecutable,
  required List<String> arguments,
  Duration timeout = const Duration(minutes: 8),
  void Function(String)? onProgress,
  void Function(Duration elapsed, String lastLine)? onHeartbeat,
  Duration heartbeat = const Duration(seconds: 20),
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
  File(paths.runStamp).writeAsStringSync(logcatStamp(DateTime.now()));

  final wrapper = writeLaunchWrapper(
    paths: paths,
    flutterExecutable: flutterExecutable,
    arguments: arguments,
  );
  final pid = await startWrapperDetached(
    paths: paths,
    wrapper: wrapper,
    logPath: paths.runLog,
    errPath: paths.runErr,
    pidPath: paths.runPid,
  );

  final started = DateTime.now();
  final deadline = started.add(timeout);
  const softGrace = Duration(seconds: 20);
  DateTime? softSeenAt;
  var lastReported = '';
  var lastBeat = started;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final text = readRunLog(paths);
    if (onHeartbeat != null &&
        DateTime.now().difference(lastBeat) >= heartbeat) {
      lastBeat = DateTime.now();
      final lines = text.trimRight().split('\n');
      onHeartbeat(DateTime.now().difference(started), lines.last.trim());
    }
    final uris = extractUris(text);
    if (uris.complete) {
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

String _tail(String text, {int lines = 25}) => tailLines(text, lines: lines);

/// The last [lines] lines of a log, for an error message that has to show its
/// working.
String tailLines(String text, {int lines = 25}) {
  final all = text.trimRight().split('\n');
  return redactSecrets(
    all.sublist(all.length > lines ? all.length - lines : 0).join('\n'),
  );
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
    final alive = await isProcessAlive(pid, runner);
    if (!alive) return null;
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

/// The same query without the kill, so `doctor` can report orphans without
/// changing anything until `--fix` says so.
const String orphanedDdsListScript = r'''
Get-CimInstance Win32_Process -Filter "Name='dart.exe'" |
  Where-Object { $_.CommandLine -like '*development-service*' } |
  Where-Object { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) } |
  ForEach-Object { $_.ProcessId }
''';

/// Pids of `dart development-service` processes whose parent is gone, from
/// `ps -axo pid=,ppid=,command=`: on POSIX an orphan is re-parented to pid 1.
List<int> parseOrphanedServices(String psOutput) {
  final orphans = <int>[];
  for (final raw in psOutput.split('\n')) {
    final line = raw.trim();
    if (!line.contains('development-service')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    final pid = int.tryParse(parts[0]);
    final ppid = int.tryParse(parts[1]);
    if (pid == null || ppid != 1) continue;
    orphans.add(pid);
  }
  return orphans;
}

/// Orphaned development services, listed without killing anything.
Future<List<int>> listOrphanedServices(ProcessRunner runner) async {
  if (Platform.isWindows) {
    final result = await runner.run(
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
  final result = await runner.run(
    '/bin/ps',
    ['-axo', 'pid=,ppid=,command='],
    timeout: const Duration(seconds: 15),
  );
  return parseOrphanedServices(result.stdout);
}

/// Kills leftover Dart Development Service processes that no longer have a
/// parent, and returns their pids.
///
/// A `flutter run` killed with `taskkill` can leave its DDS behind holding the
/// app's VM service. The next run's own DDS then cannot attach and the launch
/// dies with "Error connecting to the service protocol". Only true orphans are
/// touched, so a `flutter run` the owner has going is never disturbed.
Future<List<int>> reapOrphanedServices(ProcessRunner runner) async {
  if (!Platform.isWindows) {
    final orphans = await listOrphanedServices(runner);
    for (final pid in orphans) {
      await runner.run('/bin/kill', ['-KILL', '$pid'],
          timeout: const Duration(seconds: 10));
    }
    return orphans;
  }
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
String readRunLog(QaPaths paths) => readLogPair(paths.runLog, paths.runErr);

/// The emulator's own output, captured the same way for the same reason.
String readEmulatorLog(QaPaths paths) =>
    readLogPair(paths.emulatorLog, paths.emulatorErr);

/// Both halves of a captured process log, joined; a missing or unreadable
/// half is simply absent.
String readLogPair(String outPath, String errPath) =>
    [_readFile(outPath), _readFile(errPath)]
        .where((text) => text.isNotEmpty)
        .join('\n');

/// The bytes a log gained since [offset], for a wait that polls a growing
/// file without re-reading what it has already seen.
String readAppended(String path, int offset) {
  final file = File(path);
  if (!file.existsSync()) return '';
  final length = file.lengthSync();
  if (length <= offset) return '';
  final handle = file.openSync();
  try {
    handle.setPositionSync(offset);
    final bytes = handle.readSync(length - offset);
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  } finally {
    handle.closeSync();
  }
}

String _readFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return '';
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return '';
  }
}
