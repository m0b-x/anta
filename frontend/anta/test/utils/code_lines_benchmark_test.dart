@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Pure-Dart timings for the `CodeLines` structural operations the editor runs
/// on the typing / Enter / paste path.
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) because wall-clock numbers are not a pass/fail signal.
/// Run it deliberately when you want the numbers:
///
/// ```powershell
/// flutter test test/utils/code_lines_benchmark_test.dart --tags benchmark --run-skipped
/// ```
///
/// The assertions are catastrophe-only — they catch an accidental O(n²), not a
/// 30% regression. Read the printed table for the real signal.
void main() {
  const int documentLines = 10000;
  final List<CodeLine> lines = _buildDocument(documentLines);

  test('CodeLines.of over $documentLines list lines', () {
    final elapsed = _best(() => CodeLines.of(lines));
    // ignore: avoid_print
    print('\n=== CodeLines ($documentLines lines) ===');
    // ignore: avoid_print
    print('  of()          ${elapsed.toString().padLeft(7)}us');
    expect(elapsed, lessThan(5000000));
  });

  test('add of one line to a $documentLines-line CodeLines', () {
    const int operations = 2000;
    final elapsed = _bestWithSetup(
      setup: () => CodeLines.of(lines),
      body: (codeLines) {
        for (int i = 0; i < operations; i++) {
          codeLines.add(CodeLine('- [ ] appended $i'));
        }
      },
    );
    // ignore: avoid_print
    print(
      '  add()         ${elapsed.toString().padLeft(7)}us  '
      '($operations ops, ${(elapsed / operations).toStringAsFixed(3)}us/op)',
    );
    expect(elapsed, lessThan(5000000));
  });

  test('from + []= mid-document, the per-keystroke shape', () {
    const int operations = 2000;
    final int middle = documentLines ~/ 2;
    final elapsed = _bestWithSetup(
      setup: () => CodeLines.of(lines),
      body: (codeLines) {
        var current = codeLines;
        for (int i = 0; i < operations; i++) {
          current = CodeLines.from(current);
          current[middle] = CodeLine('- [ ] squat 5x5 @100kg$i');
        }
      },
    );
    // ignore: avoid_print
    print(
      '  from()+[]=    ${elapsed.toString().padLeft(7)}us  '
      '($operations ops, ${(elapsed / operations).toStringAsFixed(3)}us/op)',
    );
    expect(elapsed, lessThan(5000000));
  });

  test('replaceLine mid-document', () {
    const int operations = 2000;
    final int middle = documentLines ~/ 2;
    final elapsed = _bestWithSetup(
      setup: () => CodeLines.of(lines),
      body: (codeLines) {
        var current = codeLines;
        for (int i = 0; i < operations; i++) {
          current = current.replaceLine(middle, CodeLine('- [x] replaced $i'));
        }
      },
    );
    // ignore: avoid_print
    print(
      '  replaceLine() ${elapsed.toString().padLeft(7)}us  '
      '($operations ops, ${(elapsed / operations).toStringAsFixed(3)}us/op)',
    );
    expect(elapsed, lessThan(5000000));
  });

  test('removeLine mid-document', () {
    const int operations = 2000;
    final int middle = documentLines ~/ 2;
    final elapsed = _bestWithSetup(
      setup: () => CodeLines.of(lines),
      body: (codeLines) {
        var current = codeLines;
        for (int i = 0; i < operations; i++) {
          current = current.removeLine(middle);
        }
      },
    );
    // ignore: avoid_print
    print(
      '  removeLine()  ${elapsed.toString().padLeft(7)}us  '
      '($operations ops, ${(elapsed / operations).toStringAsFixed(3)}us/op)',
    );
    expect(elapsed, lessThan(5000000));
  });

  test('[]= of one line mid-document', () {
    const int operations = 2000;
    final int middle = documentLines ~/ 2;
    final elapsed = _bestWithSetup(
      setup: () => CodeLines.of(lines),
      body: (codeLines) {
        for (int i = 0; i < operations; i++) {
          codeLines[middle] = CodeLine('- [x] replaced $i');
        }
      },
    );
    // ignore: avoid_print
    print(
      '  []=           ${elapsed.toString().padLeft(7)}us  '
      '($operations ops, ${(elapsed / operations).toStringAsFixed(3)}us/op)',
    );
    expect(elapsed, lessThan(5000000));
  });
}

List<CodeLine> _buildDocument(int count) => List<CodeLine>.generate(
  count,
  (i) => CodeLine('- [ ] squat 5x5 @${100 + i % 40}kg'),
);

/// Microseconds for [operation], best of three so a single GC pause does not
/// become the headline number.
int _best(void Function() operation) {
  var best = 1 << 62;
  for (int i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    operation();
    sw.stop();
    if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
  }
  return best;
}

int _bestWithSetup({
  required CodeLines Function() setup,
  required void Function(CodeLines codeLines) body,
}) {
  var best = 1 << 62;
  for (int i = 0; i < 3; i++) {
    final codeLines = setup();
    final sw = Stopwatch()..start();
    body(codeLines);
    sw.stop();
    if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
  }
  return best;
}
