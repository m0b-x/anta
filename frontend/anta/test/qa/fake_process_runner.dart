import '../../tool/qa/src/process_runner.dart';

/// Records every invocation and replays scripted outcomes; never runs adb.
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner({this.defaultOutcome = const RunOutcome(0, '', '')});

  final RunOutcome defaultOutcome;
  final List<RunRequest> calls = <RunRequest>[];
  final Map<String, RunOutcome> scripted = <String, RunOutcome>{};

  void script(String commandLine, RunOutcome outcome) {
    scripted[commandLine] = outcome;
  }

  @override
  Future<RunOutcome> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    bool binary = false,
    String? workingDirectory,
  }) async {
    final request = RunRequest(executable, arguments, binary: binary);
    calls.add(request);
    return scripted[request.line] ?? defaultOutcome;
  }

  List<String> get lines => calls.map((c) => c.line).toList();
}
