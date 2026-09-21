import 'dart:io';

import '../../qa/src/paths.dart';

/// Where a release build's signature would come from on this machine.
enum SigningState { ready, noProperties, incompleteProperties, keystoreMissing }

/// The keys `android/app/build.gradle.kts` reads from `key.properties`.
const List<String> requiredKeyProperties = [
  'storeFile',
  'storePassword',
  'keyAlias',
  'keyPassword',
];

/// Repo-relative locations of the two gitignored signing files.
const String keyPropertiesRelative = 'android/key.properties';
const String defaultKeystoreRelative = 'android/app/release-keystore.jks';

/// What to do about a machine that cannot release-sign.
///
/// The Mac trap of 2026-09-21: the files are gitignored, the Gradle script
/// used to fall back to the debug key silently, and the phone then refused the
/// APK because its signature differed from the installed app's.
const String signingRemedy =
    'Copy $keyPropertiesRelative and $defaultKeystoreRelative from the machine '
    'that builds the installed app (both are gitignored; keep the same '
    'relative paths). A debug-signed APK cannot install over the '
    'release-signed app, and uninstalling it would wipe its data. For a '
    'throwaway build that will never go near the real app, pass '
    '--allow-debug-signing.';

class SigningStatus {
  const SigningStatus._(
    this.state, {
    this.keystorePath,
    this.keyAlias,
    this.missingKeys = const [],
  });

  final SigningState state;
  final String? keystorePath;
  final String? keyAlias;
  final List<String> missingKeys;

  bool get ready => state == SigningState.ready;

  /// One line saying what a release build would be signed with, and why.
  String describe() => switch (state) {
        SigningState.ready =>
          'release keystore $keystorePath (alias $keyAlias)',
        SigningState.noProperties => '$keyPropertiesRelative is missing, so '
            'Gradle would sign the "release" APK with the debug key',
        SigningState.incompleteProperties =>
          '$keyPropertiesRelative lacks ${missingKeys.join(', ')}',
        SigningState.keystoreMissing => '$keyPropertiesRelative points at '
            '$keystorePath, which does not exist',
      };
}

/// Parses the `key=value` subset of Java properties that key.properties uses.
Map<String, String> parseKeyProperties(String text) {
  final map = <String, String>{};
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
    final separator = line.indexOf(RegExp('[=:]'));
    if (separator <= 0) continue;
    map[line.substring(0, separator).trim()] =
        line.substring(separator + 1).trim();
  }
  return map;
}

/// Resolves `storeFile` the way Gradle's `file()` does from the app module.
String resolveKeystorePath(String storeFile, {required String appModuleDir}) {
  if (File(storeFile).isAbsolute) return storeFile;
  return joinPath(appModuleDir, storeFile.split(RegExp(r'[\\/]')));
}

SigningStatus signingStatus({
  required String? propertiesText,
  required String appModuleDir,
  required bool Function(String path) exists,
}) {
  if (propertiesText == null) {
    return const SigningStatus._(SigningState.noProperties);
  }
  final properties = parseKeyProperties(propertiesText);
  final missing = requiredKeyProperties
      .where((key) => (properties[key] ?? '').isEmpty)
      .toList();
  if (missing.isNotEmpty) {
    return SigningStatus._(
      SigningState.incompleteProperties,
      missingKeys: missing,
    );
  }
  final keystore = resolveKeystorePath(
    properties['storeFile']!,
    appModuleDir: appModuleDir,
  );
  final alias = properties['keyAlias'];
  if (!exists(keystore)) {
    return SigningStatus._(
      SigningState.keystoreMissing,
      keystorePath: keystore,
      keyAlias: alias,
    );
  }
  return SigningStatus._(
    SigningState.ready,
    keystorePath: keystore,
    keyAlias: alias,
  );
}

SigningStatus readSigningStatus(String projectRoot) {
  final properties = File(joinPath(projectRoot, ['android', 'key.properties']));
  return signingStatus(
    propertiesText:
        properties.existsSync() ? properties.readAsStringSync() : null,
    appModuleDir: joinPath(projectRoot, ['android', 'app']),
    exists: (path) => File(path).existsSync(),
  );
}

/// The gitignored Firebase files a build needs, relative to the project root.
const List<String> firebaseConfigFiles = [
  'android/app/google-services.json',
  'lib/firebase_options.dart',
];

/// Which of [firebaseConfigFiles] this checkout lacks.
List<String> missingFirebaseFiles(
  String projectRoot, {
  bool Function(String path)? exists,
}) {
  final check = exists ?? (path) => File(path).existsSync();
  return [
    for (final relative in firebaseConfigFiles)
      if (!check(joinPath(projectRoot, relative.split('/')))) relative,
  ];
}
