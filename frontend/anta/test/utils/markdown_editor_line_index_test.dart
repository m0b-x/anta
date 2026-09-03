import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/markdown_editor_line_index.dart';

/// Equivalence suite for [MarkdownEditorLineIndex]'s incremental passes.
///
/// The index is fed a brand-new [CodeLines] after every edit and decides,
/// from per-segment backing-list identity, whether to rescan a suffix or
/// rebuild. That decision is invisible from the outside, so the only
/// meaningful assertion is: after any sequence of real editor mutations,
/// an index that has been incrementally updated answers *identically* to
/// a fresh index built on the same [CodeLines], for every line.
///
/// Edits are driven through the real `CodeLineEditingController` API
/// (`edit` / `applyNewLine` / `deleteSelectionLines`), not by hand-rolled
/// `CodeLines` surgery, so the segment-sharing shape the index depends on
/// is exactly the one the app produces. Seeds are fixed.
void main() {
  group('training-log corpus', () {
    test('spans several 256-line segments and holds every construct', () {
      final lines = buildTrainingLog();
      expect(lines.length, greaterThan(600));
      final CodeLines codeLines = codeLinesOf(lines);
      expect(codeLines.segments.length, greaterThanOrEqualTo(3));
      expect(lines.where((l) => l.startsWith('```')).length, greaterThan(4));
      expect(lines.where((l) => l.startsWith(r'$')).length, greaterThan(20));
      expect(lines.where((l) => l.contains('- [ ]')).length, greaterThan(10));
      expect(lines.where((l) => l.contains('- [x]')).length, greaterThan(10));

      final index = newIndex(money: true);
      final indeterminate = <int>[
        for (int i = 0; i < codeLines.length; i++)
          if (index.taskIndeterminate(codeLines, i)) i,
      ];
      expect(indeterminate, isNotEmpty,
          reason: 'the corpus must exercise taskIndeterminate');
      final interior = <int>[
        for (int i = 0; i < codeLines.length; i++)
          if (index.fenceRoleAt(codeLines, i) == MarkdownFenceRole.interior) i,
      ];
      expect(interior, isNotEmpty);
      final money = <int>[
        for (int i = 0; i < codeLines.length; i++)
          if (index.moneyValueAt(codeLines, i) != null) i,
      ];
      expect(money, isNotEmpty);
    });

    test('a single-line edit really takes the incremental path', () {
      // Guards the premise of every equivalence test below: if `edit`
      // broke segment sharing, `_ensure` would rebuild from scratch each
      // time and the suite would prove nothing about the incremental
      // passes. One `[]=` must change exactly one segment's backing-list
      // identity, keep every length, and keep the document length.
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog()),
      );
      addTearDown(controller.dispose);
      final CodeLines before = controller.codeLines;
      final List<List<CodeLine>> beforeLists = [
        for (final s in before.segments) s.codeLines,
      ];

      _replaceLine(controller, 257, '- edited line');

      final CodeLines after = controller.codeLines;
      expect(after.length, before.length);
      expect(after.segments.length, before.segments.length);
      final changed = <int>[];
      for (int s = 0; s < after.segments.length; s++) {
        expect(after.segments[s].length, before.segments[s].length);
        if (!identical(after.segments[s].codeLines, beforeLists[s])) {
          changed.add(s);
        }
      }
      expect(changed, [1], reason: 'line 257 lives in segment 1 only');
    });

    test('a fence-free document keeps a null fence array (all roles none)', () {
      final lines = [
        for (int i = 0; i < 300; i++) '- set $i x 5',
      ];
      final CodeLines codeLines = codeLinesOf(lines);
      final index = newIndex(money: true);
      for (int i = 0; i < codeLines.length; i++) {
        expect(index.fenceRoleAt(codeLines, i), MarkdownFenceRole.none);
      }
    });
  });

  for (final bool money in [true, false]) {
    final String suffix = money ? 'money on' : 'money off';

    group('incremental == fresh ($suffix)', () {
      test('a no-op rewrap of the same lines changes nothing', () {
        final index = newIndex(money: money);
        var codeLines = codeLinesOf(buildTrainingLog());
        expectMatchesFresh(index, codeLines, money: money, reason: 'initial');
        codeLines = CodeLines.from(codeLines);
        expectMatchesFresh(index, codeLines, money: money, reason: 'rewrapped');
      });

      for (final _EditKind kind in _EditKind.values) {
        test('${kind.name} at 255/256/257/511/512', () {
          final controller = CodeLineEditingController(
            codeLines: codeLinesOf(buildTrainingLog()),
          );
          addTearDown(controller.dispose);
          final index = newIndex(money: money);
          expectMatchesFresh(index, controller.codeLines,
              money: money, reason: 'initial');

          final rng = Random(20260903);
          for (final int target in _boundaryTargets) {
            _applyEdit(controller, target, kind, rng);
            expectMatchesFresh(
              index,
              controller.codeLines,
              money: money,
              reason: '${kind.name} @ $target',
            );
          }
        });
      }

      test('seeded mixed edits, boundary + random lines', () {
        final controller = CodeLineEditingController(
          codeLines: codeLinesOf(buildTrainingLog()),
        );
        addTearDown(controller.dispose);
        final index = newIndex(money: money);
        final rng = Random(4242);

        for (int step = 0; step < 60; step++) {
          final int target = step < _boundaryTargets.length
              ? _boundaryTargets[step]
              : rng.nextInt(controller.codeLines.length);
          final _EditKind kind =
              _EditKind.values[rng.nextInt(_EditKind.values.length)];
          _applyEdit(controller, target, kind, rng);
          expectMatchesFresh(
            index,
            controller.codeLines,
            money: money,
            reason: 'step $step: ${kind.name} @ $target',
          );
        }
      });

      test('repeated edits inside one segment stay equivalent', () {
        final controller = CodeLineEditingController(
          codeLines: codeLinesOf(buildTrainingLog()),
        );
        addTearDown(controller.dispose);
        final index = newIndex(money: money);
        for (int i = 0; i < 30; i++) {
          _replaceLine(controller, 300, '- rep $i x ${i + 1}');
          expectMatchesFresh(index, controller.codeLines,
              money: money, reason: 'in-segment edit $i');
        }
      });

      test('an opening fence typed mid-document flips every role below it', () {
        final controller = CodeLineEditingController(
          codeLines: codeLinesOf(buildTrainingLog()),
        );
        addTearDown(controller.dispose);
        final index = newIndex(money: money);
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'initial');

        // A lone opening fence at 256 leaves the rest of the document
        // inside a fence: every task/money line below it goes inert.
        _replaceLine(controller, 256, '```');
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'fence opened at 256');
        expect(
          index.fenceRoleAt(controller.codeLines, 256),
          MarkdownFenceRole.delimiter,
        );
        expect(
          index.fenceRoleAt(controller.codeLines, controller.codeLines.length - 1),
          MarkdownFenceRole.interior,
        );

        // Closing it again restores every role below.
        _replaceLine(controller, 600, '```');
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'fence closed at 600');

        // And removing the opener re-flips the whole span once more.
        _replaceLine(controller, 256, '- back to a plain bullet');
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'opener removed');
      });

      test('a task subtree toggled below its parent updates the parent', () {
        // The parent sits above the edited line, so this is the case a
        // suffix-proof-only pass would get wrong: state flows downward but
        // the *result* for an earlier line changes.
        final lines = <String>[
          for (int i = 0; i < 300; i++) 'filler $i',
          '- [ ] parent',
          '  - [x] a',
          '  - [ ] b',
          '  - [ ] c',
          '',
          for (int i = 0; i < 300; i++) 'tail $i',
        ];
        final controller =
            CodeLineEditingController(codeLines: codeLinesOf(lines));
        addTearDown(controller.dispose);
        final index = newIndex(money: money);
        expect(index.taskIndeterminate(controller.codeLines, 300), isTrue);

        _replaceLine(controller, 301, '  - [ ] a');
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'all children unchecked');
        expect(index.taskIndeterminate(controller.codeLines, 300), isFalse);

        _replaceLine(controller, 302, '  - [x] b');
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'one child checked again');
        expect(index.taskIndeterminate(controller.codeLines, 300), isTrue);

        _replaceLine(controller, 301, '  - [x] a');
        _replaceLine(controller, 303, '  - [x] c');
        expectMatchesFresh(index, controller.codeLines,
            money: money, reason: 'all children checked');
        expect(index.taskIndeterminate(controller.codeLines, 300), isFalse);
      });
    });
  }

  group('money pass specifics', () {
    test('an op typed at the top re-folds every balance below it', () {
      final lines = <String>[
        r'$= 1000',
        for (int i = 0; i < 700; i++) ...[
          if (i % 5 == 0) r'$+ 10' else 'note line $i',
          if (i % 37 == 0) r'$$',
        ],
      ];
      final controller =
          CodeLineEditingController(codeLines: codeLinesOf(lines));
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      final int last = _lastMoneyLine(index, controller.codeLines);
      expect(last, greaterThan(600), reason: 'the tail must carry a money row');
      final int? before = index.moneyValueAt(controller.codeLines, last);

      _replaceLine(controller, 0, r'$= 2000');
      expectMatchesFresh(index, controller.codeLines,
          money: true, reason: 'set row changed at line 0');
      final int? after = index.moneyValueAt(controller.codeLines, last);
      expect(after, isNotNull);
      expect(after, isNot(before));
    });

    test('target declaration and status survive incremental rescans', () {
      final lines = <String>[
        r'$= 500',
        r'$! 300',
        for (int i = 0; i < 600; i++)
          i % 4 == 0 ? r'$- 1' : 'line $i',
        r'$!',
        r'$?',
        r'$^ 3',
        r'$~ 2',
      ];
      final controller =
          CodeLineEditingController(codeLines: codeLinesOf(lines));
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(index, controller.codeLines,
          money: true, reason: 'initial');

      _replaceLine(controller, 1, r'$! 900');
      expectMatchesFresh(index, controller.codeLines,
          money: true, reason: 'target raised');

      _replaceLine(controller, 1, 'no target here any more');
      expectMatchesFresh(index, controller.codeLines,
          money: true, reason: 'target removed');

      _replaceLine(controller, 300, r'$= 42');
      expectMatchesFresh(index, controller.codeLines,
          money: true, reason: 'checkpoint inserted mid-document');
    });

    test('configureMoney toggled mid-stream rebuilds correctly', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog()),
      );
      addTearDown(controller.dispose);
      final index = MarkdownEditorLineIndex(maxScannedLineLength: 4096)
        ..configureMoney(enabled: true, startCents: 0);
      expectMatchesFresh(index, controller.codeLines,
          money: true, reason: 'money on');

      _replaceLine(controller, 257, r'$+ 77.77 side job');
      index.configureMoney(enabled: false, startCents: 0);
      expectMatchesFresh(index, controller.codeLines,
          money: false, reason: 'money turned off after an edit');

      _replaceLine(controller, 258, r'$- 5 bus');
      index.configureMoney(enabled: true, startCents: 12345);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        startCents: 12345,
        reason: 'money turned back on with a new start balance',
      );
    });
  });

  group('query shape', () {
    // The index is not window-driven — every accessor calls `_ensure` and
    // scans whole passes — but the app only ever asks about the visible
    // window during layout, so an index that has *only* ever been asked
    // about a window must still answer the whole document identically.
    test('window-only queries leave the index in the same state', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog()),
      );
      addTearDown(controller.dispose);
      final windowed = newIndex(money: true);
      final rng = Random(77);

      for (int step = 0; step < 25; step++) {
        final int target = step < _boundaryTargets.length
            ? _boundaryTargets[step]
            : rng.nextInt(controller.codeLines.length);
        _applyEdit(controller, target, _EditKind.values[step % 4], rng);
        // Simulate `performLayout` asking only about ~40 visible lines.
        final CodeLines lines = controller.codeLines;
        final int start = min(rng.nextInt(lines.length), lines.length - 1);
        for (int i = start; i < min(start + 40, lines.length); i++) {
          windowed.fenceRoleAt(lines, i);
          windowed.taskIndeterminate(lines, i);
          windowed.moneyValueAt(lines, i);
        }
      }

      expectMatchesFresh(windowed, controller.codeLines,
          money: true, reason: 'after window-only querying');
    });
  });
}

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

const List<int> _boundaryTargets = [255, 256, 257, 511, 512];

/// A deterministic training-log document: headings, bullets, nested
/// bullets, ordered lists, task subtrees (mixed / all-checked / none-
/// checked so `taskIndeterminate` is exercised in all three shapes),
/// fenced code blocks, blank lines and every money row kind, including a
/// bulleted one. Blocks repeat on a period that is coprime with 256, so
/// segment boundaries land on different constructs.
List<String> buildTrainingLog({int minLines = 700}) {
  final out = <String>[];
  int i = 0;
  while (out.length < minLines) {
    switch (i % 7) {
      case 0:
        out.addAll(['## Week ${i ~/ 7 + 1}', '', 'Bodyweight 78.4 kg.', '']);
      case 1:
        out.addAll([
          '- squat 5x5',
          '  - warmup 40 kg',
          '    - bar only',
          '  - working 80 kg',
          '- bench 3x8',
          '',
        ]);
      case 2:
        final int variant = (i ~/ 7) % 3;
        out.add('- [ ] session $i');
        out.add(variant == 2 ? '  - [ ] warmup' : '  - [x] warmup');
        out.add(variant == 1 ? '  - [x] main lift' : '  - [ ] main lift');
        out.add(variant == 2 ? '  - [ ] cooldown' : '  - [x] cooldown');
        out.addAll(['- [x] logged', '']);
      case 3:
        out.addAll([
          '```dart',
          'final int reps = $i;',
          r'print(reps); // $= 999 is inert in here',
          '```',
          '',
        ]);
      case 4:
        out.addAll([
          '\$= ${1000 + i}',
          r'$+ 50 bonus',
          r'$- 12.50 coffee',
          r'$$',
          r'$?',
          '',
        ]);
      case 5:
        out.addAll([
          '1. first block',
          '2. second block',
          '   1. nested detail',
          '',
        ]);
      case 6:
        out.addAll([
          r'$! 500',
          r'$!',
          r'$^ 2',
          r'$~ 2',
          '- ' r'$+ 10 snack',
          '',
        ]);
    }
    i++;
  }
  return out;
}

CodeLines codeLinesOf(List<String> lines) =>
    CodeLines.of(lines.map(CodeLine.new));

MarkdownEditorLineIndex newIndex({required bool money, int startCents = 0}) {
  final index = MarkdownEditorLineIndex(maxScannedLineLength: 4096);
  index.configureMoney(enabled: money, startCents: startCents);
  return index;
}

/// Compares [index]'s answers for every line against a fresh index built
/// on the same [lines]. This is the whole point of the suite.
void expectMatchesFresh(
  MarkdownEditorLineIndex index,
  CodeLines lines, {
  required bool money,
  int startCents = 0,
  required String reason,
}) {
  final fresh = newIndex(money: money, startCents: startCents);
  final int n = lines.length;
  final mismatches = <String>[];
  for (int i = 0; i < n; i++) {
    final MarkdownFenceRole a = index.fenceRoleAt(lines, i);
    final MarkdownFenceRole b = fresh.fenceRoleAt(lines, i);
    if (a != b) mismatches.add('line $i fence: $a != $b');
    final bool ta = index.taskIndeterminate(lines, i);
    final bool tb = fresh.taskIndeterminate(lines, i);
    if (ta != tb) mismatches.add('line $i task: $ta != $tb');
    final int? ma = index.moneyValueAt(lines, i);
    final int? mb = fresh.moneyValueAt(lines, i);
    if (ma != mb) mismatches.add('line $i money: $ma != $mb');
    if (mismatches.length > 8) break;
  }
  expect(
    mismatches,
    isEmpty,
    reason: '$reason — incremental index diverged from a fresh one '
        '(${mismatches.length} shown, line text at first: '
        '${mismatches.isEmpty ? '' : _lineTextOf(lines, mismatches.first)})',
  );
}

int _lastMoneyLine(MarkdownEditorLineIndex index, CodeLines lines) {
  for (int i = lines.length - 1; i >= 0; i--) {
    if (index.moneyValueAt(lines, i) != null) return i;
  }
  return -1;
}

String _lineTextOf(CodeLines lines, String mismatch) {
  final int? i = int.tryParse(mismatch.split(' ')[1]);
  if (i == null || i < 0 || i >= lines.length) return '?';
  return '"${lines[i].text}"';
}

// ---------------------------------------------------------------------------
// Edits, driven through the real controller API
// ---------------------------------------------------------------------------

enum _EditKind { replace, enterSplit, deleteLine, fenceToggle }

const List<String> _replacements = [
  '- [x] done now',
  '- [ ] pending now',
  '  - [x] child done',
  '  - [ ] child pending',
  'plain paragraph line',
  r'$+ 99.99 raise',
  r'$= 4200 reset',
  r'$$ running total: $',
  r'$- 3.25 tram',
  '',
  '### Heading now',
  '- bullet now',
  '1. ordered now',
];

void _applyEdit(
  CodeLineEditingController controller,
  int rawIndex,
  _EditKind kind,
  Random rng,
) {
  final int index = rawIndex.clamp(0, controller.codeLines.length - 1);
  switch (kind) {
    case _EditKind.replace:
      _replaceLine(
        controller,
        index,
        _replacements[rng.nextInt(_replacements.length)],
      );
    case _EditKind.enterSplit:
      final String text = controller.codeLines[index].text;
      final int offset = text.isEmpty ? 0 : rng.nextInt(text.length + 1);
      controller.selection =
          CodeLineSelection.collapsed(index: index, offset: offset);
      controller.applyNewLine();
    case _EditKind.deleteLine:
      if (controller.codeLines.length <= 1) return;
      controller.selection =
          CodeLineSelection.collapsed(index: index, offset: 0);
      controller.deleteSelectionLines();
    case _EditKind.fenceToggle:
      final String text = controller.codeLines[index].text;
      _replaceLine(
        controller,
        index,
        text.trimLeft().startsWith('```') ? 'was a fence line' : '```',
      );
  }
}

/// The single-line IME path: collapsed selection on the line, then
/// `edit` with the whole new line text — exactly what the editor does per
/// keystroke, and the mutation shape (`CodeLines.from` + one `[]=`) the
/// index's incremental path is built for.
void _replaceLine(
  CodeLineEditingController controller,
  int rawIndex,
  String text,
) {
  final int index = rawIndex.clamp(0, controller.codeLines.length - 1);
  controller.selection = CodeLineSelection.collapsed(
    index: index,
    offset: controller.codeLines[index].length,
  );
  controller.edit(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}
