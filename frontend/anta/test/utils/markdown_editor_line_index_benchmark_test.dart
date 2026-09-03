@Tags(['benchmark'])
library;

import 'package:flutter/services.dart';
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
/// What it measures, and why the shape matters. All three passes now stop
/// at the first seam whose entry state they can prove unchanged, so the
/// cost of one keystroke should **not** depend on where the caret is: the
/// `k` rows (the 256-line segment holding the edited line) are that
/// claim's regression guard. Before the Session 3 suffix-proof work
/// `_scanTasks` and `_scanMoney` looped to the end of the document and
/// k=0 cost 8-11x k=39; the two should now read within noise of each
/// other.
///
/// The second group covers the structural shape — a real `applyNewLine`
/// and `deleteSelectionLines` through a `CodeLineEditingController`,
/// which change segment lengths. That used to force a whole-document
/// `_rebuildAll`; it is now the same prefix/suffix splice as a keystroke.
///
/// Columns timed per keystroke row:
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
  const int structuralIterations = 50;
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
      print('  k is the 256-line segment holding the edited line. Every '
            'pass stops at the first proven seam, so all three k rows '
            'should read the same; a gradient means a proof stopped '
            'firing. The FIRST row of each money block still reads ~2x '
            'the others whatever k it is — that row pays the isolate\'s '
            'JIT; reverse `segmentsUnderTest` to confirm before blaming '
            'k.\n');
    });
  });

  group('line index structural-edit cost — $docLines lines, '
      '$structuralIterations enters', () {
    final rows = <_StructuralRow>[];

    for (final bool money in [false, true]) {
      for (final int k in segmentsUnderTest) {
        test('enter/delete in segment k=$k, money ${money ? 'on' : 'off'}', () {
          rows.add(_measureStructural(
            docLines: docLines,
            iterations: structuralIterations,
            segment: k,
            money: money,
          ));
          final _StructuralRow row = rows.last;
          // Catastrophe-only bound, same spirit as the keystroke rows.
          expect(row.enterIndexUs, lessThan(200000));
          expect(row.deleteIndexUs, lessThan(200000));
          expect(row.enterMutateUs, lessThan(200000));
          expect(row.deleteMutateUs, lessThan(200000));
        });
      }
    }

    tearDownAll(() {
      // ignore: avoid_print
      print('\n=== MarkdownEditorLineIndex structural-edit cost '
          '($docLines lines, $structuralIterations enter+delete pairs) ===');
      // ignore: avoid_print
      print('  money | k  | edited line | enter mut | enter idx '
          '| del mut | del idx | enter total');
      for (final _StructuralRow r in rows) {
        // ignore: avoid_print
        print('  ${(r.money ? 'on' : 'off').padRight(5)} '
            '| ${r.segment.toString().padLeft(2)} '
            '| ${r.editedLine.toString().padLeft(11)} '
            '| ${r.enterMutateUs.toStringAsFixed(1).padLeft(9)} '
            '| ${r.enterIndexUs.toStringAsFixed(1).padLeft(9)} '
            '| ${r.deleteMutateUs.toStringAsFixed(1).padLeft(7)} '
            '| ${r.deleteIndexUs.toStringAsFixed(1).padLeft(7)} '
            '| ${(r.enterMutateUs + r.enterIndexUs)
                .toStringAsFixed(1)
                .padLeft(11)}');
      }
      // ignore: avoid_print
      print('  Each iteration: applyNewLine mid-line + 40-line layout query, '
          'then deleteSelectionLines of the split-off line + query. '
          'Segment lengths change, so this is the path that used to force '
          '_rebuildAll.\n');
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

class _StructuralRow {
  final bool money;
  final int segment;
  final int editedLine;
  final double enterMutateUs;
  final double enterIndexUs;
  final double deleteMutateUs;
  final double deleteIndexUs;

  _StructuralRow({
    required this.money,
    required this.segment,
    required this.editedLine,
    required this.enterMutateUs,
    required this.enterIndexUs,
    required this.deleteMutateUs,
    required this.deleteIndexUs,
  });
}

/// The structural shape: a real `applyNewLine` through a
/// `CodeLineEditingController` (caret mid-line), then the 40-line layout
/// query, then `deleteSelectionLines` of the split-off line and another
/// query. Both edits change segment lengths — the case that used to fall
/// straight through to `_rebuildAll`. The edited line is restored to its
/// canonical text outside both stopwatches, so the document stays the
/// same shape across iterations.
_StructuralRow _measureStructural({
  required int docLines,
  required int iterations,
  required int segment,
  required bool money,
}) {
  const String canonical = '- working set 5x5 at eighty kilograms';
  final int editedLine = segment * 256 + 128;
  final List<String> text = _buildNote(docLines, money: money);
  text[editedLine] = canonical;

  final controller = CodeLineEditingController(
    codeLines: CodeLines.of(text.map(CodeLine.new)),
  );
  final index = MarkdownEditorLineIndex(maxScannedLineLength: 4096)
    ..configureMoney(enabled: money, startCents: 0);
  index.fenceRoleAt(controller.codeLines, 0);

  void restore() {
    controller.selection = CodeLineSelection.collapsed(
      index: editedLine,
      offset: controller.codeLines[editedLine].length,
    );
    controller.edit(
      const TextEditingValue(
        text: canonical,
        selection: TextSelection.collapsed(offset: canonical.length),
      ),
    );
    _layoutQuery(index, controller.codeLines);
  }

  void enter() {
    controller.selection = CodeLineSelection.collapsed(
      index: editedLine,
      offset: canonical.length ~/ 2,
    );
    controller.applyNewLine();
  }

  void deleteSplit() {
    controller.selection =
        CodeLineSelection.collapsed(index: editedLine + 1, offset: 0);
    controller.deleteSelectionLines();
  }

  // Warm-up, not timed — see the note in `_measure`.
  for (int i = 0; i < 100; i++) {
    enter();
    _layoutQuery(index, controller.codeLines);
    deleteSplit();
    _layoutQuery(index, controller.codeLines);
    restore();
  }

  final enterMutate = Stopwatch();
  final enterIndex = Stopwatch();
  final deleteMutate = Stopwatch();
  final deleteIndex = Stopwatch();
  for (int i = 0; i < iterations; i++) {
    enterMutate.start();
    enter();
    enterMutate.stop();
    enterIndex.start();
    _layoutQuery(index, controller.codeLines);
    enterIndex.stop();

    deleteMutate.start();
    deleteSplit();
    deleteMutate.stop();
    deleteIndex.start();
    _layoutQuery(index, controller.codeLines);
    deleteIndex.stop();

    restore();
  }
  controller.dispose();

  return _StructuralRow(
    money: money,
    segment: segment,
    editedLine: editedLine,
    enterMutateUs: enterMutate.elapsedMicroseconds / iterations,
    enterIndexUs: enterIndex.elapsedMicroseconds / iterations,
    deleteMutateUs: deleteMutate.elapsedMicroseconds / iterations,
    deleteIndexUs: deleteIndex.elapsedMicroseconds / iterations,
  );
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

  // Warm-up keystrokes, not timed. Long enough that the first row of the
  // table does not pay for JIT-ing the scan paths on everyone's behalf —
  // with a 20-keystroke warm-up the first row measured ~2x the others
  // whatever `k` it happened to be.
  index.fenceRoleAt(lines, 0);
  for (int i = 0; i < 200; i++) {
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
///
/// A balanced ``` pair every 200 lines keeps the per-line fence array
/// allocated. Without one `_fence` stays null and a structural edit
/// never pays its `replaceRange` memmove, which is O(document lines) per
/// Enter — the single most expensive thing an Enter does. Neither
/// delimiter ever lands on a line the benchmark edits (100/105 mod 200
/// vs 128, 5248, 10112).
List<String> _buildNote(int count, {required bool money}) {
  final out = List<String>.filled(count, '');
  for (int i = 0; i < count; i++) {
    final int inCycle = i % 200;
    if (inCycle == 100 || inCycle == 105) {
      out[i] = '```';
      continue;
    }
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
