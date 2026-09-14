import 'dart:io';

import 'adb.dart';
import 'errors.dart';

/// Package id of the app under test.
const String antaPackage = 'com.alexzamfir.anta';

/// Main activity component, for `am start -n`.
const String antaActivity = '$antaPackage/.MainActivity';

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
