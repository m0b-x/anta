import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'paths.dart';
import 'process_runner.dart';
import 'runner.dart';

/// The `flutter build apk` vector for the QA build: the same defines and
/// entry point `qa run` uses, so an installed APK behaves like a `qa run`.
List<String> buildApkArgs({
  bool driver = true,
  List<String> extraDefines = const [],
}) =>
    [
      'build',
      'apk',
      '--debug',
      if (driver) ...['-t', driverTarget],
      for (final define in qaDefines) '--dart-define=$define',
      for (final define in extraDefines) '--dart-define=$define',
    ];

/// The `adb` arguments that put [apk] on a device over what is there:
/// `-r` keeps the app's data (the QA database and the owner's alike), `-t`
/// admits a debug build.
List<String> installApkArgs(String apk) => ['install', '-r', '-t', apk];

/// What `qa build` wrote to `build/qa/apk.json`, and what `qa install`
/// copies per device with the time it went on.
class ApkRecord {
  const ApkRecord({
    required this.apk,
    required this.gitHash,
    required this.dirty,
    required this.builtAt,
    required this.defines,
    this.installedAt,
    this.driver,
    this.qa,
  });

  factory ApkRecord.fromJson(Map<String, dynamic> json) => ApkRecord(
        apk: json['apk'] as String,
        gitHash: json['gitHash'] as String?,
        dirty: json['dirty'] as bool? ?? false,
        builtAt: DateTime.parse(json['builtAt'] as String),
        defines: (json['defines'] as List? ?? const []).cast<String>(),
        installedAt: json['installedAt'] == null
            ? null
            : DateTime.parse(json['installedAt'] as String),
        driver: json['driver'] as bool?,
        qa: json['qa'] as bool?,
      );

  final String apk;

  /// `git rev-parse --short HEAD`, or null outside a repository.
  final String? gitHash;

  /// Whether the tree had uncommitted changes when it was built.
  final bool dirty;
  final DateTime builtAt;
  final List<String> defines;
  final DateTime? installedAt;

  /// Whether the build's entry point is the driver (`--no-driver` makes it
  /// false), and whether it carries the ANTA_QA defines (`qa run --no-qa`
  /// makes it false); null in a record written before either was kept, or
  /// for an APK `install --apk` cannot vouch for.
  final bool? driver;
  final bool? qa;

  /// What a pass needs installed: the agent lives in the driver entry
  /// point, and only a QA build keeps off the owner's database. A record
  /// that cannot say both is not trusted.
  bool get isQaDriverBuild => driver == true && qa == true;

  ApkRecord installed(DateTime at) => ApkRecord(
        apk: apk,
        gitHash: gitHash,
        dirty: dirty,
        builtAt: builtAt,
        defines: defines,
        installedAt: at,
        driver: driver,
        qa: qa,
      );

  Map<String, dynamic> toJson() => {
        'apk': apk,
        'gitHash': gitHash,
        'dirty': dirty,
        'builtAt': builtAt.toUtc().toIso8601String(),
        'defines': defines,
        if (installedAt != null) 'installedAt': installedAt!.toUtc().toIso8601String(),
        'driver': driver,
        'qa': qa,
      };

  void write(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
  }

  /// The record at [path], or null when there is none or it is unreadable.
  static ApkRecord? read(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic>) return null;
      return ApkRecord.fromJson(json);
    } on Object {
      return null;
    }
  }

  /// [path]'s record, or a usage failure naming the verb that writes it.
  static ApkRecord require(String path) =>
      read(path) ??
      (throw UsageFailure('no build recorded at $path — run `qa build` first, '
          'or pass --apk <path>'));
}

/// The files and directories whose contents end up in the APK: the app,
/// the driver entry point, the Android project, the pubspec and its lock,
/// the assets, and every owned package's `lib/` and `android/`.
List<String> apkSourceRoots(QaPaths paths) {
  final root = paths.projectRoot;
  final packages = Directory(joinPath(root, ['packages']));
  final candidates = [
    joinPath(root, ['lib']),
    joinPath(root, ['test_driver']),
    joinPath(root, ['android']),
    joinPath(root, ['pubspec.yaml']),
    joinPath(root, ['pubspec.lock']),
    joinPath(root, ['assets']),
    if (packages.existsSync())
      for (final dir in packages.listSync().whereType<Directory>()) ...[
        joinPath(dir.path, ['lib']),
        joinPath(dir.path, ['android']),
      ],
  ];
  return [
    for (final path in candidates)
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) path,
  ];
}

/// The paths `git status --porcelain` is asked about for a build's `dirty`
/// flag: what [apkSourceRoots] covers, so an edit to the harness or a doc
/// does not mark an APK dirty.
const List<String> apkGitPathspec = [
  'lib',
  'test_driver',
  'android',
  'packages',
  'pubspec.yaml',
  'pubspec.lock',
  'assets',
];

/// Whether [relative] (a path under a source root) is something a build
/// writes or touches on every run — Gradle's and Kotlin's caches, build
/// outputs, the SDK path Flutter rewrites, the plugin registrant it
/// regenerates — which would otherwise make every installed build look
/// stale the moment it was made.
bool _isBuildByproduct(String relative) {
  final segments = relative.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return false;
  if (segments.any((s) => s == 'build' || s.startsWith('.'))) return true;
  final name = segments.last;
  return name == 'local.properties' || name.startsWith('GeneratedPluginRegistrant');
}

/// The most recently modified file under [roots] (each a directory or a
/// single file), or null when there are no files at all.
({String path, DateTime modified})? newestSource(List<String> roots) {
  ({String path, DateTime modified})? newest;
  void consider(File file, String root) {
    if (_isBuildByproduct(file.path.substring(root.length))) return;
    final modified = file.statSync().modified;
    if (newest == null || modified.isAfter(newest!.modified)) {
      newest = (path: file.path, modified: modified);
    }
  }

  for (final root in roots) {
    final file = File(root);
    if (file.existsSync()) {
      consider(file, root);
      continue;
    }
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) consider(entity, root);
    }
  }
  return newest;
}

/// The commit a build is made from and whether [apkGitPathspec] has
/// uncommitted changes; a null hash outside a repository.
Future<({String? hash, bool dirty})> gitBuildState(
  ProcessRunner runner,
  String projectRoot,
) async {
  final hash = await runner.run('git', ['rev-parse', '--short', 'HEAD'],
      workingDirectory: projectRoot);
  final status = await runner.run(
      'git', ['status', '--porcelain', '--', ...apkGitPathspec],
      workingDirectory: projectRoot);
  return (
    hash: hash.ok && hash.stdout.trim().isNotEmpty ? hash.stdout.trim() : null,
    dirty: status.ok && status.stdout.trim().isNotEmpty,
  );
}

/// What `qa run` leaves in `installed_<device>.json`: the debug APK
/// `flutter run` built and installed, dated from the run's start (the
/// build cannot be newer), so a later `pass` warns only about edits made
/// after it.
ApkRecord installedRecordForRun({
  required QaPaths paths,
  required ({String? hash, bool dirty}) git,
  required DateTime runStarted,
  required List<String> defines,
  required DateTime installedAt,
  required bool driver,
  required bool qa,
}) =>
    ApkRecord(
      apk: File(paths.debugApk).absolute.path,
      gitHash: git.hash,
      dirty: git.dirty,
      builtAt: runStarted,
      defines: defines,
      installedAt: installedAt,
      driver: driver,
      qa: qa,
    );

/// Why `qa build` must not start now, or null: the `flutter run` behind
/// `run.pid` writes the same `build/app` and races `flutter build` on
/// `build/native_assets`, so two of them kill each other mid-build.
Future<String?> buildRefusal(
  QaPaths paths,
  ProcessRunner runner, {
  required bool force,
}) async {
  if (force) return null;
  final file = File(paths.runPid);
  if (!file.existsSync()) return null;
  final pid = int.tryParse(file.readAsStringSync().trim());
  if (pid == null || !await isProcessAlive(pid, runner)) return null;
  return 'a `flutter run` (pid $pid, run.pid) is up: it writes build/app '
      'too and the two race on build/native_assets — `qa kill-run` first, '
      'or --force';
}

/// The warning `pass` prints when a source changed after the installed
/// build was made, or null when the build is current. A pass on a stale
/// build tests code that is no longer the tree.
String? staleBuildWarning(
  ApkRecord build,
  ({String path, DateTime modified})? newest, {
  String? projectRoot,
}) {
  if (newest == null || !newest.modified.isAfter(build.builtAt)) return null;
  var shown = newest.path;
  if (projectRoot != null && shown.startsWith(projectRoot)) {
    shown = shown.substring(projectRoot.length).replaceFirst(RegExp(r'^[\\/]'), '');
  }
  return 'warning: a source of the APK changed after the installed build '
      '($shown at ${newest.modified.toIso8601String()}, built '
      '${build.builtAt.toLocal().toIso8601String()}) — `qa build` and '
      '`qa install` to test the tree';
}
