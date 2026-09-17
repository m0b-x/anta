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
      _join(buildQa, ['dtd_${_safe(deviceId)}.txt']);
  String vmTxtFor(String deviceId) =>
      _join(buildQa, ['vm_${_safe(deviceId)}.txt']);
  String get lastDump => _join(buildQa, ['last_dump.txt']);
  String get legacyLastDump => _join(buildQa, ['last_dump.xml']);
  String get runVmTxt => _join(buildQa, ['run.vm']);
  String get appLog => _join(buildQa, ['app.log']);
  String get appErr => _join(buildQa, ['app.err']);
  String get appPid => _join(buildQa, ['app.pid']);
  String get deviceTxt => _join(buildQa, ['device.txt']);
  String get emulatorLog => _join(buildQa, ['emulator.log']);
  String get emulatorErr => _join(buildQa, ['emulator.err']);
  String get emulatorPid => _join(buildQa, ['emulator.pid']);
  String get toolQaDir => _join(projectRoot, ['tool', 'qa']);
  String get pubspecLock => _join(projectRoot, ['pubspec.lock']);
  String get fixturesDir => _join(toolQaDir, ['fixtures']);

  /// Compiled tool, and the two names the in-place self-rebuild swaps through.
  String get qaExe =>
      _join(buildQa, [Platform.isWindows ? 'qa.exe' : 'qa']);
  String get qaExeNew => '$qaExe.new';
  String get rebuildLock => _join(buildQa, ['rebuild.lock']);
  String get qaExeOld => '$qaExe.old';

  String documentsCache(String deviceId) =>
      _join(buildQa, ['documents_${_safe(deviceId)}.txt']);

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');

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
