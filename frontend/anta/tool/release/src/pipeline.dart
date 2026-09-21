import 'abi.dart';

/// The two launchers every step goes through.
class Toolchain {
  const Toolchain({required this.flutter, required this.dart});

  final String flutter;
  final String dart;
}

enum StepKind { clean, codegen, codegenWatch, l10n, buildApk, pubGet }

/// One external command of the pipeline.
class Step {
  const Step(this.kind, this.label, this.executable, this.arguments);

  final StepKind kind;
  final String label;
  final String executable;
  final List<String> arguments;

  String get line => [executable, ...arguments].join(' ');
}

class BuildOptions {
  const BuildOptions({
    this.abi = TargetAbi.all,
    this.clean = false,
    this.codegen = true,
    this.allowDebugSigning = false,
  });

  final TargetAbi abi;

  /// `flutter clean` first: a cold Gradle and a cold build_runner, roughly
  /// twice the wall-clock of the incremental default.
  final bool clean;

  final bool codegen;

  /// Build even without the release keystore; the APK is then debug-signed and
  /// cannot install over the real app.
  final bool allowDebugSigning;

  BuildOptions withAbi(TargetAbi abi) => BuildOptions(
        abi: abi,
        clean: clean,
        codegen: codegen,
        allowDebugSigning: allowDebugSigning,
      );
}

/// Where `flutter build apk` leaves the release APK, whatever the ABI set.
const List<String> apkPathParts = [
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-release.apk',
];

const String debugInfoDir = 'build/debug-info';

/// The Gradle project property `android/app/build.gradle.kts` reads to allow
/// a debug-signed release. It travels as `flutter build apk -P<name>=true`;
/// the `ORG_GRADLE_PROJECT_` environment route never reaches the Gradle the
/// Flutter tool launches (checked 2026-09-21).
const String allowDebugSigningProperty = 'antaAllowDebugSigning';

Step cleanStep(Toolchain tools) => Step(
      StepKind.clean,
      'Cleaning the previous build',
      tools.flutter,
      const ['clean'],
    );

Step codegenStep(Toolchain tools, {bool watch = false}) => Step(
      watch ? StepKind.codegenWatch : StepKind.codegen,
      watch
          ? 'Watching Drift sources (Ctrl+C to stop)'
          : 'Generating Drift code',
      tools.dart,
      [
        'run',
        'build_runner',
        watch ? 'watch' : 'build',
        '--delete-conflicting-outputs',
      ],
    );

Step l10nStep(Toolchain tools) => Step(
      StepKind.l10n,
      'Generating localizations',
      tools.flutter,
      const ['gen-l10n'],
    );

Step pubGetStep(Toolchain tools) => Step(
      StepKind.pubGet,
      'Fetching packages',
      tools.flutter,
      const ['pub', 'get'],
    );

Step buildApkStep(Toolchain tools, BuildOptions options) => Step(
      StepKind.buildApk,
      'Building the release APK (${options.abi.label})',
      tools.flutter,
      [
        'build',
        'apk',
        '--release',
        ...options.abi.buildFlags,
        '--obfuscate',
        '--split-debug-info=$debugInfoDir',
        if (options.allowDebugSigning) '-P$allowDebugSigningProperty=true',
      ],
    );

List<Step> planBuild(BuildOptions options, Toolchain tools) => [
      if (options.clean) cleanStep(tools),
      if (options.codegen) codegenStep(tools),
      if (options.codegen) l10nStep(tools),
      buildApkStep(tools, options),
    ];

List<Step> planGen(Toolchain tools, {required bool watch}) => watch
    ? [codegenStep(tools, watch: true)]
    : [codegenStep(tools), l10nStep(tools)];

List<Step> planClean(Toolchain tools) => [cleanStep(tools), pubGetStep(tools)];
