import 'dart:io';

import '../../qa/src/paths.dart';
import '../../qa/src/runner.dart' show findFlutter;
import '../../qa/src/self_build.dart' show findDart;
import 'errors.dart';
import 'pipeline.dart';

/// Runs pipeline steps in the project with their output on the terminal.
class Host {
  Host({required this.projectRoot, this.verbose = false});

  final String projectRoot;
  final bool verbose;

  Toolchain? _toolchain;

  Toolchain get toolchain =>
      _toolchain ??= Toolchain(flutter: findFlutter(), dart: findDart());

  Future<void> runStep(
    Step step, {
    required int index,
    required int total,
  }) async {
    stdout.writeln();
    stdout.writeln('[$index/$total] ${step.label}');
    if (verbose) stdout.writeln('+ ${step.line}');
    await stdout.flush();
    final code = await runStreaming(step.executable, step.arguments);
    if (code != 0) {
      throw BuildFailure('${step.label} failed (exit $code): ${step.line}');
    }
  }

  /// Starts [executable] with the terminal as its stdio and returns its exit
  /// code.
  ///
  /// `flutter` on Windows is `flutter.bat`, which `CreateProcess` cannot run
  /// directly, so it goes through `cmd /c`; `dart` is the real VM binary.
  Future<int> runStreaming(String executable, List<String> arguments) async {
    final viaCmd =
        Platform.isWindows && executable.toLowerCase().endsWith('.bat');
    final Process process;
    try {
      process = await Process.start(
        viaCmd ? 'cmd.exe' : executable,
        viaCmd ? ['/c', executable, ...arguments] : arguments,
        workingDirectory: projectRoot,
        mode: ProcessStartMode.inheritStdio,
      );
    } on ProcessException catch (e) {
      throw BuildFailure('cannot run "$executable": ${e.message}');
    }
    return process.exitCode;
  }

  /// Deletes [relative] under the project, waiting out Windows' lazy handle
  /// release, and fails loudly when something still holds it.
  ///
  /// `flutter clean` prints "Failed to remove build" and still exits 0, so
  /// the check has to be ours.
  Future<void> ensureDeleted(String relative, {int attempts = 5}) async {
    final dir = Directory(joinPath(projectRoot, [relative]));
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!dir.existsSync()) return;
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (!dir.existsSync()) return;
    throw BuildFailure(
      '$relative/ could not be deleted: a process still holds a file in it '
      '(an IDE, an Explorer window, a Gradle daemon, or the QA emulator, '
      'whose launcher and log live under build/qa). Close it and retry.',
    );
  }

  /// Shows [path] in the desktop's file manager without waiting on it;
  /// `explorer.exe` exits 1 even when it succeeds.
  void openFolder(String path) {
    final (executable, arguments) = Platform.isWindows
        ? ('explorer.exe', [path])
        : Platform.isMacOS
            ? ('open', [path])
            : ('xdg-open', [path]);
    Process.start(executable, arguments, mode: ProcessStartMode.detached)
        .ignore();
  }
}
