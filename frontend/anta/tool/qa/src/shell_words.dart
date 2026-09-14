import 'errors.dart';

/// Splits one `steps` line into argument tokens the way a POSIX shell would.
///
/// Double quotes and single quotes both group; a backslash escapes the next
/// character outside single quotes. This is what lets a step carry a label
/// with spaces — `tap "Search all notes"` — through a single argv slot.
List<String> splitShellWords(String line) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var started = false;
  var index = 0;

  void flush() {
    if (!started) return;
    tokens.add(buffer.toString());
    buffer.clear();
    started = false;
  }

  while (index < line.length) {
    final char = line[index];
    if (char == ' ' || char == '\t') {
      flush();
      index++;
      continue;
    }
    started = true;
    if (char == r'\') {
      if (index + 1 >= line.length) {
        throw UsageFailure('step ends with a dangling backslash: $line');
      }
      buffer.write(line[index + 1]);
      index += 2;
      continue;
    }
    if (char == '"' || char == "'") {
      final closing = line.indexOf(char, index + 1);
      if (closing == -1) {
        throw UsageFailure('unbalanced $char in step: $line');
      }
      if (char == "'") {
        buffer.write(line.substring(index + 1, closing));
        index = closing + 1;
        continue;
      }
      var scan = index + 1;
      while (scan < line.length) {
        final inner = line[scan];
        if (inner == r'\' && scan + 1 < line.length) {
          buffer.write(line[scan + 1]);
          scan += 2;
          continue;
        }
        if (inner == '"') break;
        buffer.write(inner);
        scan++;
      }
      if (scan >= line.length) {
        throw UsageFailure('unbalanced " in step: $line');
      }
      index = scan + 1;
      continue;
    }
    buffer.write(char);
    index++;
  }
  flush();
  return tokens;
}

/// Turns the body of a `--file` (or stdin) into the step lines to run.
///
/// Blank lines and `#` comments are dropped so a step file can be annotated.
List<String> parseStepLines(String text) {
  final steps = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;
    steps.add(line);
  }
  return steps;
}
