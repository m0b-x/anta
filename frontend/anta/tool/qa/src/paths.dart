import 'dart:io';

/// Filesystem layout the QA harness writes into, rooted at the Flutter package.
class QaPaths {
  /// [fleetState] defaults to `build/qa/fleet` under [projectRoot], so a
  /// test's paths never reach the host-wide directory; the tool itself
  /// always comes through [QaPaths.locate].
  QaPaths(this.projectRoot, {String? fleetState})
    : fleetState = fleetState ?? _join(projectRoot, ['build', 'qa', 'fleet']);

  factory QaPaths.locate([Directory? start]) {
    final fleet = hostFleetStateDir(
      Platform.environment,
      windows: Platform.isWindows,
      macos: Platform.isMacOS,
    );
    var dir = start ?? Directory.current;
    for (var depth = 0; depth < 8; depth++) {
      if (File(_join(dir.path, ['pubspec.yaml'])).existsSync()) {
        return QaPaths(dir.absolute.path, fleetState: fleet);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return QaPaths(
      (start ?? Directory.current).absolute.path,
      fleetState: fleet,
    );
  }

  final String projectRoot;

  /// Where everything that describes the fleet lives: the guest state
  /// files, the guard's pid file, log and exe copies. The fleet is one per
  /// machine while checkouts are many (worktrees under `%TEMP%`), so a
  /// guard or a `reap` from any checkout must see the holds every other
  /// checkout took ([hostFleetStateDir]).
  final String fleetState;

  String get buildQa => _join(projectRoot, ['build', 'qa']);
  String get shotsDir => _join(buildQa, ['shots']);
  String get runLog => _join(buildQa, ['run.log']);
  String get runErr => _join(buildQa, ['run.err']);
  String get runPid => _join(buildQa, ['run.pid']);
  String get runStamp => _join(buildQa, ['run.started']);
  String dtdTxtFor(String deviceId) =>
      _join(buildQa, ['dtd_${safeId(deviceId)}.txt']);
  String vmTxtFor(String deviceId) =>
      _join(buildQa, ['vm_${safeId(deviceId)}.txt']);

  /// The dump `#N` targets resolve against, one per device so two `qa`
  /// processes on two devices never read each other's tree.
  String lastDumpFor(String deviceId) =>
      _join(buildQa, ['last_dump_${safeId(deviceId)}.txt']);

  /// The shared dump older tools wrote; read once as a fallback.
  String get lastDump => _join(buildQa, ['last_dump.txt']);
  String get legacyLastDump => _join(buildQa, ['last_dump.xml']);
  String get runVmTxt => _join(buildQa, ['run.vm']);
  String get appLog => _join(buildQa, ['app.log']);
  String get appErr => _join(buildQa, ['app.err']);
  String get appPid => _join(buildQa, ['app.pid']);
  String get deviceTxt => _join(buildQa, ['device.txt']);
  String get emulatorLog => emulatorLogFor(null);
  String get emulatorErr => emulatorErrFor(null);
  String get emulatorPid => emulatorPidFor(null);

  /// The emulator's own files, per AVD when its name is known, so two
  /// emulators booted by this tool keep their logs and pids apart.
  String emulatorLogFor(String? avd) =>
      _join(buildQa, ['${_emulatorBase(avd)}.log']);
  String emulatorErrFor(String? avd) =>
      _join(buildQa, ['${_emulatorBase(avd)}.err']);
  String emulatorPidFor(String? avd) =>
      _join(buildQa, ['${_emulatorBase(avd)}.pid']);

  static String _emulatorBase(String? avd) =>
      avd == null || avd.isEmpty ? 'emulator' : 'emulator_${safeId(avd)}';
  String get toolQaDir => _join(projectRoot, ['tool', 'qa']);
  String get pubspecLock => _join(projectRoot, ['pubspec.lock']);
  String get fixturesDir => _join(toolQaDir, ['fixtures']);
  String get flowsDir => _join(toolQaDir, ['flows']);
  String get seedResolved => _join(buildQa, ['seed_resolved.json']);

  /// The resolved seed for one device: a clock-relative fixture resolved
  /// for one emulator must not be overwritten by a second one's relaunch
  /// before it is pushed.
  String seedResolvedFor(String deviceId) =>
      _join(buildQa, ['seed_resolved_${safeId(deviceId)}.json']);

  /// Where `qa pass` writes its runs, one directory per run.
  String get passRoot => _join(buildQa, ['pass']);

  String passDirFor(String suite, String stamp, String deviceId) =>
      _join(passRoot, ['${safeId(suite)}_${stamp}_${safeId(deviceId)}']);

  /// Holds the path of the newest report for [suite].
  String latestPassFor(String suite) =>
      _join(passRoot, ['latest_${safeId(suite)}.txt']);

  /// What the last `qa build` produced, and what `qa install` put on a device.
  String get apkJson => _join(buildQa, ['apk.json']);

  String installedJsonFor(String deviceId) =>
      _join(buildQa, ['installed_${safeId(deviceId)}.json']);

  /// How many times the app was launched on a fleet guest since its boot:
  /// the health count `fleet pass` recycles a guest by.
  String launchesJsonFor(String deviceId) =>
      _join(buildQa, ['launches_${safeId(deviceId)}.json']);

  /// One fleet guest's life: booted at, last used at, and the pass or
  /// install holding it (`guest_state.dart`).
  String guestStateFor(String avd) =>
      _join(fleetState, ['guest_${safeId(avd)}.json']);

  /// A stop someone asked for on a held guest, until its next boot
  /// (`StopRequest` in `guest_state.dart`).
  String stopRequestFor(String avd) =>
      _join(fleetState, ['stop_${safeId(avd)}.json']);

  /// The idle guard's pid and settings, and its log (`guard.dart`).
  String get guardPid => _join(fleetState, ['guard.pid']);
  String get guardLog => _join(fleetState, ['guard.log']);

  /// The copy of [qaExe] a guard runs from, named by the exe's
  /// modification time in milliseconds, so a running guard never holds the
  /// file the self-rebuild swaps.
  String guardExeFor(int stamp) =>
      _join(fleetState, ['guard_$stamp${Platform.isWindows ? '.exe' : ''}']);

  /// The launch wrapper `qa run` starts (`runner.dart`): the recorded run
  /// is this checkout's only while its command line names this file.
  String runWrapperFor({required bool windows}) =>
      _join(buildQa, ['run_cmd.${windows ? 'bat' : 'sh'}']);

  Directory ensureFleetState() =>
      Directory(fleetState)..createSync(recursive: true);

  /// The APK `flutter build apk --debug` writes.
  String get debugApk => _join(projectRoot, [
    'build',
    'app',
    'outputs',
    'flutter-apk',
    'app-debug.apk',
  ]);

  /// Compiled tool, and the two names the in-place self-rebuild swaps through.
  String get qaExe => _join(buildQa, [Platform.isWindows ? 'qa.exe' : 'qa']);
  String get qaExeNew => '$qaExe.new';
  String get rebuildLock => _join(buildQa, ['rebuild.lock']);
  String get qaExeOld => '$qaExe.old';

  String documentsCache(String deviceId) =>
      _join(buildQa, ['documents_${safeId(deviceId)}.txt']);

  /// [id] made safe for a file name: a serial with a colon (`host:5555`)
  /// still gives one flat name.
  static String safeId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');

  String get macosAppInfo =>
      _join(projectRoot, ['macos', 'Runner', 'Configs', 'AppInfo.xcconfig']);

  String macosBundle(String productName) => _join(projectRoot, [
    'build',
    'macos',
    'Build',
    'Products',
    'Debug',
    '$productName.app',
  ]);

  Directory ensureBuildQa() => Directory(buildQa)..createSync(recursive: true);

  Directory ensureShots() => Directory(shotsDir)..createSync(recursive: true);

  String resolve(String relativeOrAbsolute) {
    final file = File(relativeOrAbsolute);
    if (file.isAbsolute) return file.path;
    return _join(projectRoot, [relativeOrAbsolute]);
  }
}

/// Overrides the host-wide fleet state directory ([QaPaths.fleetState]).
const String fleetStateEnv = 'ANTA_QA_FLEET_STATE';

/// The host-wide fleet state directory for this user: [fleetStateEnv]
/// when set, else `%LOCALAPPDATA%\anta-qa\fleet` on Windows,
/// `~/Library/Application Support/anta-qa/fleet` on macOS and
/// `$XDG_STATE_HOME/anta-qa/fleet` (`~/.local/state`) elsewhere; null only
/// when the environment names no home at all.
String? hostFleetStateDir(
  Map<String, String> env, {
  required bool windows,
  required bool macos,
}) {
  String? named(String key) {
    final value = env[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final override = named(fleetStateEnv);
  if (override != null) return override;
  if (windows) {
    final local = named('LOCALAPPDATA');
    final profile = named('USERPROFILE');
    final base =
        local ??
        (profile == null ? null : _join(profile, ['AppData', 'Local']));
    return base == null ? null : _join(base, ['anta-qa', 'fleet']);
  }
  final home = named('HOME');
  if (macos) {
    return home == null
        ? null
        : _join(home, ['Library', 'Application Support', 'anta-qa', 'fleet']);
  }
  final state =
      named('XDG_STATE_HOME') ??
      (home == null ? null : _join(home, ['.local', 'state']));
  return state == null ? null : _join(state, ['anta-qa', 'fleet']);
}

String _join(String base, List<String> parts) =>
    ([base, ...parts]).join(Platform.pathSeparator);

String joinPath(String base, List<String> parts) => _join(base, parts);
