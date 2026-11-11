import 'dart:io';

import 'adb.dart';
import 'app_ids.dart';
import 'errors.dart';

export 'app_ids.dart' show antaActivity, antaPackage;

/// App documents directory the Flutter app reads its QA markers from.
const String antaDocsDir = '/data/user/0/$antaPackage/app_flutter';

/// Marker that makes the next QA launch wipe the QA prefs and `qa.db*`.
const String resetMarker = 'qa_reset';

/// Marker holding a full-backup JSON the next QA launch imports.
const String seedMarker = 'qa_seed.json';

/// Staging directory: `run-as` can read `/data/local/tmp`, so a push lands
/// there first and is copied into the app sandbox from inside `run-as`.
const String stagingDir = '/data/local/tmp';

/// The `adb` argument vectors that place one marker file in the app sandbox.
///
/// Split out from execution so the command shape can be unit tested.
List<List<String>> markerPushCommands({
  required String localPath,
  required String markerName,
  String packageId = antaPackage,
}) {
  final staged = '$stagingDir/anta_$markerName';
  return [
    ['push', localPath, staged],
    ['shell', 'run-as', packageId, 'cp', staged, '$antaDocsDir/$markerName'],
    ['shell', 'rm', '-f', staged],
  ];
}

/// The `adb` argument vector that drops the empty `qa_reset` marker.
List<List<String>> resetMarkerCommands({String packageId = antaPackage}) => [
  ['shell', 'run-as', packageId, 'touch', '$antaDocsDir/$resetMarker'],
];

Future<void> applyCommands(Adb adb, List<List<String>> commands) async {
  for (final args in commands) {
    final result = await adb.raw(args, timeout: const Duration(seconds: 60));
    if (!result.ok || result.combined.contains('run-as: ')) {
      throw DeviceFailure(
        'adb ${args.join(' ')} failed: ${result.combined.isEmpty ? 'exit ${result.exitCode}' : result.combined}\n'
        'Hint: `run-as` only works on a debug build of $antaPackage that is '
        'already installed.',
      );
    }
  }
}

Future<void> dropResetMarker(Adb adb, {String packageId = antaPackage}) =>
    applyCommands(adb, resetMarkerCommands(packageId: packageId));

/// The `adb` argument vector that removes a pending `qa_seed.json`. No
/// `-f`: the "No such file" answer is how [discardSeed] tells a seed that
/// was waiting from none, in the one call.
List<String> discardSeedCommand({String packageId = antaPackage}) => [
  'shell',
  'run-as',
  packageId,
  'rm',
  '$antaDocsDir/$seedMarker',
];

/// Removes a `qa_seed.json` that no launch consumed yet and says whether
/// there was one. A seedless `--fresh` launch must come up empty: a reseed
/// cancelled after its push left one behind, and the quiet launch that
/// followed imported it and armed its alarms again.
Future<bool> discardSeed(Adb adb, {String packageId = antaPackage}) async {
  final args = discardSeedCommand(packageId: packageId);
  final result = await adb.raw(args, timeout: const Duration(seconds: 60));
  if (result.combined.contains('No such file')) return false;
  if (!result.ok || result.combined.contains('run-as: ')) {
    throw DeviceFailure(
      'adb ${args.join(' ')} failed: ${result.combined.isEmpty ? 'exit ${result.exitCode}' : result.combined}',
    );
  }
  return true;
}

Future<void> pushSeed(
  Adb adb,
  String localPath, {
  String packageId = antaPackage,
}) async {
  final file = File(localPath);
  if (!file.existsSync()) {
    throw UsageFailure('seed fixture not found: $localPath');
  }
  await applyCommands(
    adb,
    markerPushCommands(
      localPath: file.absolute.path,
      markerName: seedMarker,
      packageId: packageId,
    ),
  );
}

/// Drops the reset marker straight into a documents directory on the host
/// filesystem — the iOS simulator's data container, or the macOS sandbox.
Future<void> dropResetMarkerAt(
  String documentsDir, {
  bool mustExist = false,
}) async {
  final dir = await _markerDirectory(documentsDir, mustExist: mustExist);
  await File(
    '${dir.path}${Platform.pathSeparator}$resetMarker',
  ).writeAsBytes(const []);
}

/// Copies a seed fixture into a documents directory on the host filesystem.
Future<void> pushSeedTo(
  String documentsDir,
  String localPath, {
  bool mustExist = false,
}) async {
  final file = File(localPath);
  if (!file.existsSync()) {
    throw UsageFailure('seed fixture not found: $localPath');
  }
  final dir = await _markerDirectory(documentsDir, mustExist: mustExist);
  await file.copy('${dir.path}${Platform.pathSeparator}$seedMarker');
}

Future<Directory> _markerDirectory(
  String path, {
  required bool mustExist,
}) async {
  final dir = Directory(path);
  if (await dir.exists()) return dir;
  if (mustExist || !await dir.parent.exists()) {
    throw DeviceFailure(
      'the app documents directory does not exist yet: $path — launch the app '
      'once (`qa run`), then drop markers with `qa relaunch --fresh --seed …`',
    );
  }
  return dir.create();
}

/// Removes a pending seed from a documents directory on the host, as
/// [discardSeed] does on Android; false when none was waiting.
Future<bool> discardSeedAt(String documentsDir) async {
  final file = File('$documentsDir${Platform.pathSeparator}$seedMarker');
  try {
    await file.delete();
    return true;
  } on PathNotFoundException {
    return false;
  }
}

/// Which marker files are waiting in a documents directory on the host.
List<String> pendingMarkersAt(String documentsDir) => [
  for (final name in const [resetMarker, seedMarker])
    if (File('$documentsDir${Platform.pathSeparator}$name').existsSync()) name,
];
