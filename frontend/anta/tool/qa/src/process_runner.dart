import 'dart:convert';
import 'dart:io';

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
  const RunRequest(this.executable, this.arguments, {this.binary = false});

  final String executable;
  final List<String> arguments;
  final bool binary;

  String get line => ([executable, ...arguments]).join(' ');

  @override
  String toString() => line;
}

/// Abstraction over process execution so verbs can be unit tested.
abstract class ProcessRunner {
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
  });
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
  }) async {
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
    final outChunks = <int>[];
    final errChunks = <int>[];
    final outDone = process.stdout.listen(outChunks.addAll).asFuture<void>();
    final errDone = process.stderr.listen(errChunks.addAll).asFuture<void>();
    final int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on Object {
      process.kill(ProcessSignal.sigkill);
      throw DeviceFailure(
        'timed out after ${timeout.inSeconds}s: $executable ${arguments.join(' ')}',
      );
    }
    await Future.wait([outDone, errDone]);
    return RunOutcome(
      code,
      binary ? '' : _decode(outChunks),
      _decode(errChunks),
      bytes: binary ? outChunks : null,
    );
  }

  static String _decode(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: true).convert(bytes).trimRight();
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true).trimRight();
    }
  }
}
