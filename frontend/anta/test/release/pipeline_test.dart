import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/src/abi.dart';
import '../../tool/release/src/pipeline.dart';

const Toolchain _tools = Toolchain(flutter: 'flutter', dart: 'dart');

void main() {
  test('the default build is incremental: codegen, l10n, then the APK', () {
    final steps = planBuild(const BuildOptions(), _tools);
    expect(
      steps.map((s) => s.kind),
      [StepKind.codegen, StepKind.l10n, StepKind.buildApk],
    );
    expect(
      steps.last.line,
      'flutter build apk --release --obfuscate '
      '--split-debug-info=build/debug-info',
    );
  });

  test('--clean puts flutter clean first, before code generation', () {
    expect(
      planBuild(const BuildOptions(clean: true), _tools).map((s) => s.kind),
      [StepKind.clean, StepKind.codegen, StepKind.l10n, StepKind.buildApk],
    );
  });

  test('--no-gen leaves only the APK build', () {
    expect(
      planBuild(const BuildOptions(codegen: false), _tools).map((s) => s.kind),
      [StepKind.buildApk],
    );
  });

  test('a narrowed ABI passes --target-platform', () {
    final step = planBuild(const BuildOptions(abi: TargetAbi.arm64), _tools).last;
    expect(step.arguments, containsAllInOrder(['--target-platform', 'android-arm64']));
    expect(step.label, contains('arm64-v8a'));
  });

  test('--allow-debug-signing reaches Gradle as a -P project property', () {
    final step = planBuild(const BuildOptions(allowDebugSigning: true), _tools).last;
    expect(step.arguments.last, '-PantaAllowDebugSigning=true');
    expect(step.arguments, isNot(contains('ORG_GRADLE_PROJECT_antaAllowDebugSigning')));
  });

  test('build_runner keeps --delete-conflicting-outputs for older versions', () {
    expect(
      codegenStep(_tools).line,
      'dart run build_runner build --delete-conflicting-outputs',
    );
  });

  test('gen --watch is build_runner watch alone', () {
    expect(planGen(_tools, watch: true).map((s) => s.kind), [StepKind.codegenWatch]);
    expect(
      planGen(_tools, watch: false).map((s) => s.kind),
      [StepKind.codegen, StepKind.l10n],
    );
  });

  test('clean is flutter clean then pub get', () {
    expect(planClean(_tools).map((s) => s.kind), [StepKind.clean, StepKind.pubGet]);
  });

  test('withAbi keeps the other options', () {
    final options = const BuildOptions(
      clean: true,
      codegen: false,
      allowDebugSigning: true,
    ).withAbi(TargetAbi.x64);
    expect(options.abi, TargetAbi.x64);
    expect(options.clean, isTrue);
    expect(options.codegen, isFalse);
    expect(options.allowDebugSigning, isTrue);
  });
}
