import 'dart:io';

import '../../qa/src/process_runner.dart';

/// One running Gradle daemon JVM.
class GradleDaemon {
  const GradleDaemon(this.pid, this.commandLine);

  final int pid;
  final String commandLine;

  /// Whether this daemon serves [version], judged from the jars on its
  /// command line.
  bool runsVersion(String version) {
    final escaped = RegExp.escape(version);
    return RegExp('gradle-daemon-main-$escaped\\.jar').hasMatch(commandLine) ||
        RegExp('[\\\\/]gradle-$escaped[\\\\/]').hasMatch(commandLine);
  }

  @override
  String toString() => 'pid $pid';
}

/// The Gradle version `gradle-wrapper.properties` pins, or null.
String? wrapperVersion(String wrapperPropertiesText) => RegExp(
      r'distributionUrl=.*?gradle-([0-9][0-9A-Za-z.\-]*?)-(?:all|bin)\.zip',
    ).firstMatch(wrapperPropertiesText)?.group(1);

/// Reads `<pid> <command line>` rows, keeping only Gradle daemons.
List<GradleDaemon> parseDaemonRows(String output) {
  final daemons = <GradleDaemon>[];
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (!line.contains('GradleDaemon')) continue;
    final match = RegExp(r'^(\d+)\s+(.*)$').firstMatch(line);
    if (match == null) continue;
    daemons.add(GradleDaemon(int.parse(match.group(1)!), match.group(2)!));
  }
  return daemons;
}

/// The daemons a build cannot use: every one when [keepVersion] is null,
/// otherwise those serving another Gradle than the wrapper's.
///
/// After a wrapper upgrade the previous version's daemon stays alive holding
/// handles under build/app/intermediates, and the next R8 pass on Windows
/// fails to delete its own classes.dex. `gradlew --stop` never reaches it: it
/// only stops daemons of the wrapper's own version.
List<GradleDaemon> staleDaemons(
  List<GradleDaemon> daemons, {
  required String? keepVersion,
}) =>
    keepVersion == null
        ? daemons
        : daemons.where((d) => !d.runsVersion(keepVersion)).toList();

/// The command that lists Gradle daemon JVMs with their command lines.
RunRequest daemonListingCommand({required bool windows}) => windows
    ? const RunRequest('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        _powershellListing,
      ])
    : const RunRequest('ps', ['-eo', 'pid=,command=']);

const String _powershellListing = 'Get-CimInstance Win32_Process | '
    "Where-Object { \$_.Name -eq 'java.exe' -and "
    "\$_.CommandLine -like '*GradleDaemon*' } | "
    'ForEach-Object { \$_.ProcessId.ToString() + [char]9 + \$_.CommandLine }';

Future<List<GradleDaemon>> listGradleDaemons(
  ProcessRunner runner, {
  bool? windows,
}) async {
  final request = daemonListingCommand(windows: windows ?? Platform.isWindows);
  final result = await runner.run(
    request.executable,
    request.arguments,
    timeout: const Duration(seconds: 40),
  );
  return result.ok ? parseDaemonRows(result.stdout) : const [];
}

/// Signals every daemon in [daemons] and returns the pids that took it.
List<int> stopDaemons(
  Iterable<GradleDaemon> daemons, {
  bool Function(int pid) kill = _terminate,
}) =>
    [
      for (final daemon in daemons)
        if (kill(daemon.pid)) daemon.pid,
    ];

bool _terminate(int pid) => Process.killPid(pid, ProcessSignal.sigterm);
