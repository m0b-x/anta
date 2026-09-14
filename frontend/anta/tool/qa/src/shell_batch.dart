import 'input_text.dart';

/// Line the device shell echoes between two commands of a batch.
///
/// It has to be something no probe output can contain, and it has to survive
/// `adb shell`'s own line-ending translation, so it sits alone on its line.
const String batchSeparator = '__QA_SEP__';

/// One command of a batched `adb shell` call.
///
/// [ShellCommand.args] is the common form: every token is single-quoted for
/// the device shell, exactly as `qa type` quotes what it types. [ShellCommand.raw]
/// exists because the cheap probes are pipelines — `dumpsys window 2>/dev/null
/// | grep -m1 isKeyguardShowing` — and quoting `|` or `2>` would make the
/// shell treat them as literals.
class ShellCommand {
  const ShellCommand(this.args) : raw = null;

  const ShellCommand.raw(String fragment)
      : raw = fragment,
        args = const <String>[];

  final List<String> args;
  final String? raw;

  /// The fragment this command contributes to the batch script.
  String get script => raw ?? args.map(shellSingleQuote).join(' ');
}

/// Builds the single shell script that runs every command and marks the
/// boundaries.
///
/// A separator follows **every** command, the last one included, so the number
/// of chunks does not depend on whether a command printed anything.
String buildBatchScript(List<ShellCommand> commands) {
  final parts = <String>[];
  for (final command in commands) {
    parts.add(command.script);
    parts.add('echo $batchSeparator');
  }
  return parts.join('; ');
}

/// Splits batched output back into one entry per command.
///
/// Short output (a shell that died half way) is padded with empty strings so
/// callers can index positionally without a length check.
List<String> splitBatchOutput(String output, int expected) {
  final chunks = <String>[];
  final buffer = <String>[];
  for (final line in output.split('\n')) {
    if (line.trim() == batchSeparator) {
      chunks.add(buffer.join('\n').trim());
      buffer.clear();
      continue;
    }
    buffer.add(line.trimRight());
  }
  while (chunks.length < expected) {
    chunks.add('');
  }
  return chunks.sublist(0, expected);
}
