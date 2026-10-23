import 'dart:io';

/// Filesystem layout the QA harness writes into, rooted at the Flutter package.
class QaPaths {
  QaPaths(this.projectRoot);

  factory QaPaths.locate([Directory? start]) {
    var dir = start ?? Directory.current;
    for (var depth = 0; depth < 8; depth++) {
      if (File(_join(dir.path, ['pubspec.yaml'])).existsSync()) {
        return QaPaths(dir.absolute.path);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return QaPaths((start ?? Directory.current).absolute.path);
  }

  final String projectRoot;

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
  String emulatorLogFor(String? avd) => _join(buildQa, ['${_emulatorBase(avd)}.log']);
  String emulatorErrFor(String? avd) => _join(buildQa, ['${_emulatorBase(avd)}.err']);
  String emulatorPidFor(String? avd) => _join(buildQa, ['${_emulatorBase(avd)}.pid']);

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

  /// The APK `flutter build apk --debug` writes.
  String get debugApk => _join(
        projectRoot,
        ['build', 'app', 'outputs', 'flutter-apk', 'app-debug.apk'],
      );

  /// Compiled tool, and the two names the in-place self-rebuild swaps through.
  String get qaExe =>
      _join(buildQa, [Platform.isWindows ? 'qa.exe' : 'qa']);
  String get qaExeNew => '$qaExe.new';
  String get rebuildLock => _join(buildQa, ['rebuild.lock']);
  String get qaExeOld => '$qaExe.old';

  String documentsCache(String deviceId) =>
      _join(buildQa, ['documents_${safeId(deviceId)}.txt']);

  /// [id] made safe for a file name: a serial with a colon (`host:5555`)
  /// still gives one flat name.
  static String safeId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');

  String get macosAppInfo => _join(projectRoot, ['macos', 'Runner', 'Configs', 'AppInfo.xcconfig']);

  String macosBundle(String productName) => _join(
        projectRoot,
        ['build', 'macos', 'Build', 'Products', 'Debug', '$productName.app'],
      );

  Directory ensureBuildQa() => Directory(buildQa)..createSync(recursive: true);

  Directory ensureShots() => Directory(shotsDir)..createSync(recursive: true);

  String resolve(String relativeOrAbsolute) {
    final file = File(relativeOrAbsolute);
    if (file.isAbsolute) return file.path;
    return _join(projectRoot, [relativeOrAbsolute]);
  }
}

String _join(String base, List<String> parts) =>
    ([base, ...parts]).join(Platform.pathSeparator);

String joinPath(String base, List<String> parts) => _join(base, parts);
