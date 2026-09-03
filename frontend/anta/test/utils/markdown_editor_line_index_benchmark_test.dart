@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/markdown_editor_line_index.dart';

/// Keystroke cost of [MarkdownEditorLineIndex] on a 10k-line note.
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) because wall-clock numbers are not a pass/fail
/// signal. Run it deliberately:
///
/// ```powershell
/// flutter test test/utils/markdown_editor_line_index_benchmark_test.dart --tags benchmark --run-skipped
/// ```
///
/// What it measures, and why the shape matters: `_scanFence` has a suffix
/// proof (it stops as soon as it re-enters an unchanged segment with the
/// same fence parity), but `_scanTasks` and `_scanMoney` do not — both
/// loop `for (s = first; s < n)` to the end of the document. So the cost
/// of one keystroke depends on **where** the caret is: an edit in segment
/// 0 rescans all 40 segments, an edit in segment 39 rescans one. The
/// three `k` rows below are exactly that gradient, and they are the
/// baseline the P3 suffix-proof fix (review doc §3 Session 3) is measured
/// against — after the fix, k=0 should collapse towards k=39.
///
/// Two columns are timed per row:
///
///   * `mutate` — `CodeLines.from` + one `[]=`, the fork-side cost of a
///     single-line edit (the P1 surface), for context only;
///   * `index` — the index's own work: the `_ensure` triggered by the
///     first `fenceRoleAt` of the layout pass plus a 40-line visible
///     window of `fenceRoleAt`/`taskIndeterminate`/`moneyValueAt`, which
///     is what `performLayout` actually asks for.
///
/// Assertions are catastrophe-only: they catch a hang, not a regression.
/// Read the printed table.
void main() {
  const int docLines = 40 * 256; // 10,240 lines = 40 full segments.
  const int iterations = 200;
  const List<int> segmentsUnderTest = [0, 20, 39];

  group('line index keystroke cost — $docLines lines, $iterations keystrokes',
      () {
    final rows = <_Row>[];

    for (final bool money in [false, true]) {
      for (final int k in segmentsUnderTest) {
        test('segment k=$k, money ${money ? 'on' : 'off'}', () {
          rows.add(_measure(
            docLines: docLines,
            iterations: iterations,
            segment: k,
            money: money,
          ));
          final _Row row = rows.last;
          // Catastrophe-only bound: a keystroke that costs more than
          // 100 ms of index work on a 10k-line note is a hang, not a
          // regression.
          expect(row.indexUs, lessThan(100000));
          expect(row.mutateUs, lessThan(100000));
        });
      }
    }

    tearDownAll(() {
      // ignore: avoid_print
      print('\n=== MarkdownEditorLineIndex keystroke cost '
          '($docLines lines, $iterations keystrokes) ===');
      // ignore: avoid_print
      print('  money | k  | edited line | mutate us | index us | total us');
      for (final _Row r in rows) {
        // ignore: avoid_print
        print('  ${(r.money ? 'on' : 'off').padRight(5)} '
            '| ${r.segment.toString().padLeft(2)} '
            '| ${r.editedLine.toString().padLeft(11)} '
            '| ${r.mutateUs.toStringAsFixed(1).padLeft(9)} '
            '| ${r.indexUs.toStringAsFixed(1).padLeft(8)} '
            '| ${(r.mutateUs + r.indexUs).toStringAsFixed(1).padLeft(8)}');
      }
      // ignore: avoid_print
      print('  (cold full build: '
          '${rows.map((r) => '${r.money ? 'on' : 'off'}/k${r.segment}='
              '${r.coldUs.toStringAsFixed(0)}us').join(', ')})');
      // ignore: avoid_print
      print('  k is the 256-line segment holding the edited line. '
            '_scanTasks/_scanMoney have no suffix proof, so k=0 rescans '
            'all 40 segments and k=39 rescans one.\n');
    });
  });
}

class _Row {
  final bool money;
  final int segment;
  final int editedLine;
  final double mutateUs;
  final double indexUs;
  final double coldUs;

  _Row({
    required this.money,
    required this.segment,
    required this.editedLine,
    required this.mutateUs,
    required this.indexUs,
    required this.coldUs,
  });
}

_Row _measure({
  required int docLines,
  required int iterations,
  required int segment,
  required bool money,
}) {
  final int editedLine = segment * 256 + 128;
  final List<String> text = _buildNote(docLines, money: money);
  text[editedLine] = '- plain working set';

  CodeLines lines = CodeLines.of(text.map(CodeLine.new));
  final index = MarkdownEditorLineIndex(maxScannedLineLength: 4096)
    ..configureMoney(enabled: money, startCents: 0);

  // Warm-up keystrokes, not timed (they also JIT every scan path).
  index.fenceRoleAt(lines, 0);
  for (int i = 0; i < 20; i++) {
    lines = _typeAt(lines, editedLine, '- warm $i');
    _layoutQuery(index, lines);
  }

  // Cold full build on a warm VM, for context: this is what a structural
  // edit — Enter, paste, line delete — costs today, and what P2 forces on
  // every list Enter and checkbox toggle.
  final coldWatch = Stopwatch();
  for (int i = 0; i < 5; i++) {
    final cold = MarkdownEditorLineIndex(maxScannedLineLength: 4096)
      ..configureMoney(enabled: money, startCents: 0);
    coldWatch.start();
    cold.fenceRoleAt(lines, 0);
    coldWatch.stop();
  }
  final double coldUs = coldWatch.elapsedMicroseconds / 5;

  final mutateWatch = Stopwatch();
  final indexWatch = Stopwatch();
  for (int i = 0; i < iterations; i++) {
    mutateWatch.start();
    lines = _typeAt(lines, editedLine, '- working set $i x 5');
    mutateWatch.stop();

    indexWatch.start();
    _layoutQuery(index, lines);
    indexWatch.stop();
  }

  return _Row(
    money: money,
    segment: segment,
    editedLine: editedLine,
    mutateUs: mutateWatch.elapsedMicroseconds / iterations,
    indexUs: indexWatch.elapsedMicroseconds / iterations,
    coldUs: coldUs,
  );
}

/// One single-line keystroke, the exact mutation shape the controller's
/// `edit` produces on the same-line path: `CodeLines.from` (all segments
/// dirty, backing lists shared) then one `[]=` (clones just that
/// segment's list).
CodeLines _typeAt(CodeLines lines, int index, String text) {
  final CodeLines next = CodeLines.from(lines);
  next[index] = CodeLine(text);
  return next;
}

/// What `performLayout` asks the index for: the first visible line forces
/// the rescan, then ~40 visible lines are queried on all three passes.
void _layoutQuery(MarkdownEditorLineIndex index, CodeLines lines) {
  for (int i = 0; i < 40; i++) {
    index.fenceRoleAt(lines, i);
    index.taskIndeterminate(lines, i);
    index.moneyValueAt(lines, i);
  }
}

/// A 10k-line training-log note: bullets, nested bullets, task subtrees
/// and headings, with money rows every 10th line in the `money: true`
/// variant and none at all in the `money: false` one — "money rows
/// present vs absent", the same document shape otherwise.
List<String> _buildNote(int count, {required bool money}) {
  final out = List<String>.filled(count, '');
  for (int i = 0; i < count; i++) {
    if (money && i % 10 == 3) {
      out[i] = switch (i % 70) {
        3 => r'$= 1200',
        13 => r'$+ 50 bonus',
        23 => r'$- 12.50 coffee',
        33 => r'$$',
        43 => r'$?',
        53 => r'$^ 3',
        _ => r'$- 4.20 tram',
      };
      continue;
    }
    out[i] = switch (i % 10) {
      0 => '- squat 5x5',
      1 => '  - warmup 40 kg',
      2 => '  - working 80 kg',
      4 => '- [ ] session ${i ~/ 10}',
      5 => '  - [x] warmup',
      6 => '  - [ ] main lift',
      7 => '  - [x] cooldown',
      8 => '',
      _ => '- accessory work',
    };
  }
  return out;
}
