import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cancel.dart';
import 'errors.dart';

/// Outcome of one external process invocation.
class RunOutcome {
  const RunOutcome(this.exitCode, this.stdout, this.stderr, {this.bytes});

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<int>? bytes;

  bool get ok => exitCode == 0;

  String get combined => [stdout, stderr].where((s) => s.isNotEmpty).join('\n');
}

/// A record of one invocation, kept so tests can assert on command shape.
class RunRequest {
  const RunRequest(
    this.executable,
    this.arguments, {
    this.binary = false,
    this.stdin,
  });

  final String executable;
  final List<String> arguments;
  final bool binary;
  final String? stdin;

  String get line => ([executable, ...arguments]).join(' ');

  @override
  String toString() => line;
}

/// Abstraction over process execution so verbs can be unit tested.
abstract class ProcessRunner {
  /// [stdin], when given, is written to the process and its input closed —
  /// the answer to a prompt a tool asks even when every flag is passed
  /// (`avdmanager create avd` and its custom hardware profile).
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  });
}

/// `taskkill`'s arguments for [pid] and every process under it, forced.
List<String> treeKillArgs(int pid) => ['/PID', '$pid', '/T', '/F'];

/// Whether a timed-out call to [executable] may take its whole process
/// tree down. Not for `adb`: an `adb` that found no server starts the one
/// on port 5037 as its own child, and that server is the one the owner's
/// `Pixel_9_Pro` is driven through — a tree kill would cut it off. adb
/// keeps the old kill of the direct child; everything else (a `flutter
/// build` and its Gradle and Dart children) loses its tree.
bool treeKillsOnTimeout(String executable) {
  final name = executable.split(RegExp(r'[\\/]')).last.toLowerCase();
  return name != 'adb' && name != 'adb.exe';
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner({this.verbose = false});

  final bool verbose;

  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
    String? stdin,
  }) async {
    // A cancelled attempt starts no process, and the one it has running is
    // killed rather than left to wait out its timeout beside the pass's
    // rerun (cancel.dart).
    final token = CancelToken.current;
    token?.check();
    if (verbose) {
      stderr.writeln('+ $executable ${arguments.join(' ')}');
    }
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      throw DeviceFailure('cannot run "$executable": ${e.message}');
    }
    // Drained before stdin is written: a child that prints more than a pipe
    // holds before it reads would otherwise block on its stdout while this
    // side waits for stdin to close.
    final outChunks = <int>[];
    final errChunks = <int>[];
    final outDone = process.stdout.listen(outChunks.addAll).asFuture<void>();
    final errDone = process.stderr.listen(errChunks.addAll).asFuture<void>();
    if (stdin != null) {
      process.stdin.write(stdin);
      await process.stdin.close();
    }
    final stopOnCancel = token?.onCancel(
      () => unawaited(_kill(process, executable)),
    );
    final int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on Object {
      if (token?.isCancelled ?? false) throw Cancelled(token!.reason!);
      await _kill(process, executable);
      throw DeviceFailure(
        'timed out after ${timeout.inSeconds}s: $executable ${arguments.join(' ')}',
      );
    } finally {
      stopOnCancel?.call();
    }
    token?.check();
    await Future.wait([outDone, errDone]);
    return RunOutcome(
      code,
      binary ? '' : _decode(outChunks),
      _decode(errChunks),
      bytes: binary ? outChunks : null,
    );
  }

  /// On Windows a kill reaches only the direct child: a timed-out `flutter
  /// build` left its Gradle and Dart children running. The tree goes
  /// first, the child after it in case the tree kill missed.
  static Future<void> _kill(Process process, String executable) async {
    if (Platform.isWindows && treeKillsOnTimeout(executable)) {
      await _killTree(process.pid);
    }
    process.kill(ProcessSignal.sigkill);
  }

  static Future<void> _killTree(int pid) async {
    try {
      await Process.run(
        'taskkill',
        treeKillArgs(pid),
      ).timeout(const Duration(seconds: 20));
    } on Object {
      return;
    }
  }

  static String _decode(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes).trimRight();
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true).trimRight();
    }
  }
}
