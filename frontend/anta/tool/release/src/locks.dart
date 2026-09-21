import 'dart:io';

import '../../qa/src/paths.dart';
import '../../qa/src/process_runner.dart';
import 'gradle_daemons.dart';

/// Which Gradle daemons to stop before a build.
enum DaemonScope {
  /// Only daemons of another Gradle version than the wrapper's; the current
  /// one stays warm for the incremental build.
  staleOnly,

  /// Every daemon, before a clean build that wants nothing holding build/.
  all,
}

/// Frees what a rebuild would otherwise trip over and says what it did.
///
/// Two processes routinely hold files under build/ between runs on Windows:
/// a Gradle daemon of a previous wrapper version and the Explorer window
/// `build` opens on the output folder. Both make `flutter clean` skip the
/// tree (while still exiting 0) and the next R8 pass fail on its own
/// classes.dex.
Future<List<String>> releaseBuildLocks({
  required String projectRoot,
  required ProcessRunner runner,
  required DaemonScope scope,
  bool? windows,
  bool Function(int pid)? kill,
}) async {
  final onWindows = windows ?? Platform.isWindows;
  final notes = <String>[];
  final wrapper = File(joinPath(
    projectRoot,
    ['android', 'gradle', 'wrapper', 'gradle-wrapper.properties'],
  ));
  final version =
      wrapper.existsSync() ? wrapperVersion(wrapper.readAsStringSync()) : null;
  final daemons = await listGradleDaemons(runner, windows: onWindows);
  final targets = staleDaemons(
    daemons,
    keepVersion: scope == DaemonScope.all ? null : version,
  );
  if (targets.isNotEmpty) {
    final stopped =
        kill == null ? stopDaemons(targets) : stopDaemons(targets, kill: kill);
    final why = scope == DaemonScope.all
        ? 'before the clean build'
        : 'not running Gradle ${version ?? '?'}';
    notes.add(
      'stopped ${stopped.length} Gradle daemon(s) $why: pid '
      '${stopped.join(', ')}',
    );
  }
  if (onWindows) {
    final closed = await explorerWindowsUnder(
      joinPath(projectRoot, ['build']),
      runner,
      close: true,
    );
    if (closed > 0) notes.add('closed $closed Explorer window(s) under build\\');
  }
  return notes;
}

/// Counts, and with [close] quits, the Explorer windows parked inside
/// [directory].
Future<int> explorerWindowsUnder(
  String directory,
  ProcessRunner runner, {
  required bool close,
}) async {
  final result = await runner.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      explorerScript(directory, close: close),
    ],
    timeout: const Duration(seconds: 40),
  );
  return result.ok ? int.tryParse(result.stdout.trim()) ?? 0 : 0;
}

/// A PowerShell one-liner over the Shell.Application COM object; it carries
/// no double quotes so no shell in between can re-tokenise it.
String explorerScript(String directory, {required bool close}) {
  final root = directory.replaceAll("'", "''");
  final action = close ? r'$w.Quit(); ' : '';
  return "\$root = '$root'; \$n = 0; "
      '\$shell = New-Object -ComObject Shell.Application; '
      'foreach (\$w in @(\$shell.Windows())) { '
      'try { \$p = \$w.Document.Folder.Self.Path } catch { continue }; '
      'if (\$p -and \$p.StartsWith(\$root, '
      '[StringComparison]::OrdinalIgnoreCase)) { $action\$n++ } }; \$n';
}
