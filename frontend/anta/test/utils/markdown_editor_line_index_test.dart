import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/markdown_callout_syntax.dart';
import 'package:anta/utils/markdown_editor_line_index.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart'
    show MarkdownEditorSpanBuilder;
import 'package:anta/utils/markdown_money_syntax.dart' show MarkdownMoneySyntax;

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
      expect(
        indeterminate,
        isNotEmpty,
        reason: 'the corpus must exercise taskIndeterminate',
      );
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

      final leads = <int>[
        for (int i = 0; i < codeLines.length; i++)
          if (index.calloutRoleAt(codeLines, i) == MarkdownCalloutRole.lead) i,
      ];
      final bodies = <int>[
        for (int i = 0; i < codeLines.length; i++)
          if (index.calloutRoleAt(codeLines, i) == MarkdownCalloutRole.body) i,
      ];
      expect(leads, isNotEmpty, reason: 'the corpus must hold callout leads');
      expect(bodies, isNotEmpty, reason: 'and their bodies');

      // The lead the corpus places directly under a fence *closer*: the
      // callout pass reads the fence roles first, so this line is a lead
      // and not the continuation of anything above the fence.
      final int afterFence = lines.indexOf('> [!WARNING] after fence');
      expect(afterFence, greaterThan(0));
      expect(lines[afterFence - 1], '```');
      expect(
        index.calloutRoleAt(codeLines, afterFence),
        MarkdownCalloutRole.lead,
      );
      expect(
        index.calloutRoleAt(codeLines, afterFence + 1),
        MarkdownCalloutRole.body,
      );
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

    test('every line of a fence-free document has role none', () {
      final lines = [for (int i = 0; i < 300; i++) '- set $i x 5'];
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
          expectMatchesFresh(
            index,
            controller.codeLines,
            money: money,
            reason: 'initial',
          );

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
          expectMatchesFresh(
            index,
            controller.codeLines,
            money: money,
            reason: 'in-segment edit $i',
          );
        }
      });

      test('an opening fence typed mid-document flips every role below it', () {
        final controller = CodeLineEditingController(
          codeLines: codeLinesOf(buildTrainingLog()),
        );
        addTearDown(controller.dispose);
        final index = newIndex(money: money);
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'initial',
        );

        // A lone opening fence at 256 leaves the rest of the document
        // inside a fence: every task/money line below it goes inert.
        _replaceLine(controller, 256, '```');
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'fence opened at 256',
        );
        expect(
          index.fenceRoleAt(controller.codeLines, 256),
          MarkdownFenceRole.delimiter,
        );
        expect(
          index.fenceRoleAt(
            controller.codeLines,
            controller.codeLines.length - 1,
          ),
          MarkdownFenceRole.interior,
        );

        // Closing it again restores every role below.
        _replaceLine(controller, 600, '```');
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'fence closed at 600',
        );

        // And removing the opener re-flips the whole span once more.
        _replaceLine(controller, 256, '- back to a plain bullet');
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'opener removed',
        );
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
        final controller = CodeLineEditingController(
          codeLines: codeLinesOf(lines),
        );
        addTearDown(controller.dispose);
        final index = newIndex(money: money);
        expect(index.taskIndeterminate(controller.codeLines, 300), isTrue);

        _replaceLine(controller, 301, '  - [ ] a');
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'all children unchecked',
        );
        expect(index.taskIndeterminate(controller.codeLines, 300), isFalse);

        _replaceLine(controller, 302, '  - [x] b');
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'one child checked again',
        );
        expect(index.taskIndeterminate(controller.codeLines, 300), isTrue);

        _replaceLine(controller, 301, '  - [x] a');
        _replaceLine(controller, 303, '  - [x] c');
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: money,
          reason: 'all children checked',
        );
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
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      final int last = _lastMoneyLine(index, controller.codeLines);
      expect(last, greaterThan(600), reason: 'the tail must carry a money row');
      final int? before = index.moneyValueAt(controller.codeLines, last);

      _replaceLine(controller, 0, r'$= 2000');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'set row changed at line 0',
      );
      final int? after = index.moneyValueAt(controller.codeLines, last);
      expect(after, isNotNull);
      expect(after, isNot(before));
    });

    test('target declaration and status survive incremental rescans', () {
      final lines = <String>[
        r'$= 500',
        r'$! 300',
        for (int i = 0; i < 600; i++) i % 4 == 0 ? r'$- 1' : 'line $i',
        r'$!',
        r'$?',
        r'$^ 3',
        r'$~ 2',
      ];
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      _replaceLine(controller, 1, r'$! 900');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'target raised',
      );

      _replaceLine(controller, 1, 'no target here any more');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'target removed',
      );

      _replaceLine(controller, 300, r'$= 42');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'checkpoint inserted mid-document',
      );
    });

    test('configureMoney toggled mid-stream rebuilds correctly', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog()),
      );
      addTearDown(controller.dispose);
      final index = MarkdownEditorLineIndex(maxScannedLineLength: 4096)
        ..configureMoney(enabled: true, startCents: 0);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'money on',
      );

      _replaceLine(controller, 257, r'$+ 77.77 side job');
      index.configureMoney(enabled: false, startCents: 0);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: false,
        reason: 'money turned off after an edit',
      );

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

    test(r'a $= typed above a $~ row re-folds its checkpoint window', () {
      // `$~ N` reads back through the anchor history, so a checkpoint
      // appearing above one changes its value without changing anything
      // about the row itself. Enter first (a delta of +1 that renumbers
      // every stored money line below), then the op typed on the new line.
      final List<String> source = buildTrainingLog(minLines: 1500);
      final int span = source.indexOf(r'$~ 2', 600);
      expect(span, greaterThan(0));
      expect(source[span - 1], r'$^ 2');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(source),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      controller.selection = CodeLineSelection.collapsed(
        index: span - 1,
        offset: controller.codeLines[span - 1].length,
      );
      controller.applyNewLine();
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a blank line opened above the span row',
      );

      _replaceLine(controller, span, r'$= 4200');
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a checkpoint typed above the span row',
      );
      expect(scan.rebuilt, isFalse);
    });

    test('a start-balance change while money is off keeps the built index', () {
      // The disabled money pass never reads the start balance, so
      // recording a new one must not throw away the fence and task
      // results. Handed the very same `CodeLines` instance the index does
      // nothing at all, which makes `debugLastScan` the exact probe: it
      // still describes the edit before the settings change.
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog()),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: false);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: false,
        reason: 'initial',
      );

      _replaceLine(controller, 257, '- edited while money is off');
      final scan = _scanOf(index, controller.codeLines);
      expect(scan.rebuilt, isFalse);

      index.configureMoney(enabled: false, startCents: 5);
      expect(
        _scanOf(index, controller.codeLines),
        scan,
        reason:
            'a start balance the disabled pass never reads must not '
            'invalidate the fence and task results',
      );

      index.configureMoney(enabled: true, startCents: 5);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        startCents: 5,
        reason: 'the recorded start balance seeds the enabled pass',
      );
    });
  });

  group('callout pass', () {
    // Callout membership is the third positional pass and the only one
    // whose result for a line is decided entirely by the lines above it,
    // so the seam proof and the fence interaction are the two things
    // worth pinning beyond plain equivalence.

    test('a lead typed into a plain-quote run flips every line below it', () {
      final lines = <String>[
        for (int i = 0; i < 520; i++) 'filler $i',
        for (int i = 0; i < 40; i++) '> quoted $i',
        for (int i = 0; i < 300; i++) 'tail $i',
      ];
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );
      for (int i = 520; i < 560; i++) {
        expect(
          index.calloutRoleAt(controller.codeLines, i),
          MarkdownCalloutRole.none,
          reason: 'a plain quote run is no callout: line $i',
        );
      }

      _replaceLine(controller, 530, '> [!TIP] lead');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a lead typed mid-run',
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 529),
        MarkdownCalloutRole.none,
        reason: 'the quotes above the lead are untouched',
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 530),
        MarkdownCalloutRole.lead,
      );
      for (int i = 531; i < 560; i++) {
        expect(
          index.calloutRoleAt(controller.codeLines, i),
          MarkdownCalloutRole.body,
          reason: 'line $i',
        );
      }
      expect(
        index.calloutRoleAt(controller.codeLines, 560),
        MarkdownCalloutRole.none,
        reason: 'the first non-quote line ends the block',
      );

      _replaceLine(controller, 530, '> quoted 10');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'the lead removed again',
      );
      for (int i = 520; i < 560; i++) {
        expect(
          index.calloutRoleAt(controller.codeLines, i),
          MarkdownCalloutRole.none,
          reason: 'line $i',
        );
      }
    });

    test('a fence opened above a callout swallows its lead', () {
      final lines = <String>[
        for (int i = 0; i < 100; i++) 'filler $i',
        'plain a',
        'plain b',
        '> [!TIP] lead',
        '> body',
        'after',
        for (int i = 0; i < 300; i++) 'tail $i',
      ];
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(
        index.calloutRoleAt(controller.codeLines, 102),
        MarkdownCalloutRole.lead,
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 103),
        MarkdownCalloutRole.body,
      );

      _replaceLine(controller, 100, '```');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a fence opened above the block',
      );
      expect(
        index.fenceRoleAt(controller.codeLines, 102),
        MarkdownFenceRole.interior,
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 102),
        MarkdownCalloutRole.none,
        reason: 'a fenced lead is code, not a callout',
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 103),
        MarkdownCalloutRole.none,
      );

      _replaceLine(controller, 101, '```');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'the fence closed above the block again',
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 102),
        MarkdownCalloutRole.lead,
      );
      expect(
        index.calloutRoleAt(controller.codeLines, 103),
        MarkdownCalloutRole.body,
      );
    });

    test('a keystroke in a body line rescans one segment, whatever k', () {
      const int segments = 12;
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(_calloutSegments(segments)),
      );
      addTearDown(controller.dispose);
      expect(controller.codeLines.segments.length, segments);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      for (final int k in <int>[0, 5, segments - 1]) {
        final int line = k * 256 + 1;
        expect(
          index.calloutRoleAt(controller.codeLines, line),
          MarkdownCalloutRole.body,
          reason: 'the fixture must put a body line at $line',
        );
        _replaceLine(controller, line, '> body one $k typed');
        final scan = _scanOf(index, controller.codeLines);
        expectMatchesFresh(
          index,
          controller.codeLines,
          money: true,
          reason: 'keystroke in segment $k',
        );
        expect(scan.rebuilt, isFalse);
        expect(
          scan.callout,
          1,
          reason:
              'segment $k: the callout pass must stop at the first seam, '
              'so its cost cannot depend on k',
        );
      }
    });

    test('changing a lead type re-scans only until the block ends', () {
      const int segments = 12;
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(_calloutSegments(segments)),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      const int k = 5;
      const int lead = k * 256;
      _replaceLine(controller, lead, '> [!WARNING] block $k');
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'the lead retyped as another type',
      );
      expect(scan.rebuilt, isFalse);
      expect(
        scan.callout,
        1,
        reason:
            'the fixture opens and closes the block inside segment $k, so '
            'the next seam already has its proven entry state and the pass '
            'stops there. A block that spanned a 256-line seam could '
            'legitimately take 2 — this one cannot',
      );
      for (final int line in <int>[lead, lead + 1, lead + 2]) {
        expect(
          MarkdownEditorLineIndex.calloutTypeOf(
            index.calloutAt(controller.codeLines, line),
          ),
          MarkdownCalloutType.warning,
          reason: 'every line of the block carries the new type: $line',
        );
      }
    });

    test('a callout-free document stores no roles at all', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(<String>[
          for (int i = 0; i < 900; i++) '- set $i x 5',
        ]),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      for (int i = 0; i < controller.codeLines.length; i++) {
        expect(index.calloutAt(controller.codeLines, i), 0);
        expect(
          index.calloutRoleAt(controller.codeLines, i),
          MarkdownCalloutRole.none,
        );
      }

      // The pass still runs — it just never allocates the array.
      _replaceLine(controller, 300, '- set 300 x 6');
      final scan = _scanOf(index, controller.codeLines);
      expect(scan.rebuilt, isFalse);
      expect(scan.callout, 1);
      for (int i = 0; i < controller.codeLines.length; i++) {
        expect(index.calloutAt(controller.codeLines, i), 0);
      }
    });

    test('the packed role and type decode for every pair', () {
      final lines = <String>[
        for (final MarkdownCalloutType type in MarkdownCalloutType.values) ...[
          '> [!${type.name.toUpperCase()}] lead',
          '> body',
          '',
        ],
      ];
      final CodeLines codeLines = codeLinesOf(lines);
      final index = newIndex(money: false);

      for (int t = 0; t < MarkdownCalloutType.values.length; t++) {
        final MarkdownCalloutType type = MarkdownCalloutType.values[t];
        final int lead = index.calloutAt(codeLines, t * 3);
        final int body = index.calloutAt(codeLines, t * 3 + 1);
        expect(
          MarkdownEditorLineIndex.calloutRoleOf(lead),
          MarkdownCalloutRole.lead,
          reason: '${type.name} lead',
        );
        expect(MarkdownEditorLineIndex.calloutTypeOf(lead), type);
        expect(
          MarkdownEditorLineIndex.calloutRoleOf(body),
          MarkdownCalloutRole.body,
          reason: '${type.name} body',
        );
        expect(MarkdownEditorLineIndex.calloutTypeOf(body), type);
        expect(index.calloutAt(codeLines, t * 3 + 2), 0);
      }

      expect(
        MarkdownEditorLineIndex.calloutRoleOf(0),
        MarkdownCalloutRole.none,
      );
      expect(MarkdownEditorLineIndex.calloutTypeOf(0), isNull);
    });

    test('Enter in a body and deleting the lead stay equivalent', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(_calloutSegments(8)),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      const int lead = 5 * 256;
      controller.selection = const CodeLineSelection.collapsed(
        index: lead + 2,
        offset: 3,
      );
      controller.applyNewLine();
      final enterScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'Enter inside a body line',
      );
      expect(enterScan.rebuilt, isFalse);

      controller.selection = const CodeLineSelection.collapsed(
        index: lead,
        offset: 0,
      );
      controller.deleteSelectionLines();
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'the lead line deleted',
      );
      expect(
        index.calloutRoleAt(controller.codeLines, lead),
        MarkdownCalloutRole.none,
        reason: 'with no lead the rest of the block is a plain quote',
      );
    });

    test('a callout block pasted over a fence stays equivalent', () {
      final List<String> source = buildTrainingLog(minLines: 3000);
      final int opener = source.indexOf('```dart', 600);
      expect(opener, greaterThan(0));
      expect(source[opener + 3], '```');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(source),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      controller.selection = CodeLineSelection(
        baseIndex: opener,
        baseOffset: 0,
        extentIndex: opener + 3,
        extentOffset: controller.codeLines[opener + 3].length,
      );
      controller.replaceSelection(
        '> [!CAUTION] pasted lead\n'
        '> pasted body\n'
        '>> pasted deeper\n'
        '> [!NOTE] pasted inner',
      );

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a callout block pasted over a whole fence',
      );
      expect(scan.rebuilt, isFalse);
      expect(
        index.calloutRoleAt(controller.codeLines, opener),
        MarkdownCalloutRole.lead,
      );
      for (final int line in <int>[opener + 1, opener + 2, opener + 3]) {
        expect(
          index.calloutRoleAt(controller.codeLines, line),
          MarkdownCalloutRole.body,
          reason: 'line $line',
        );
      }
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
          windowed.calloutAt(lines, i);
          windowed.taskIndeterminate(lines, i);
          windowed.moneyValueAt(lines, i);
        }
      }

      expectMatchesFresh(
        windowed,
        controller.codeLines,
        money: true,
        reason: 'after window-only querying',
      );
    });
  });

  group('suffix proof', () {
    // Every pass stops at the first seam whose entry state it can prove
    // unchanged, so an edit near the top of a 12+ segment document must
    // cost the same as one near the bottom. `debugLastScan` reports what
    // the last `_ensure` actually scanned; equivalence is still asserted
    // on top of every count, because a proof that fires when it should
    // not is exactly the bug these counts would otherwise hide.

    test('a plain-paragraph edit in segment 0 stops at the first seam', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog(minLines: 3000)),
      );
      addTearDown(controller.dispose);
      expect(controller.codeLines.segments.length, greaterThanOrEqualTo(12));
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );
      expect(controller.codeLines[2].text, 'Bodyweight 78.4 kg.');

      _replaceLine(controller, 2, 'Bodyweight 79.1 kg.');
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'paragraph edited in segment 0',
      );
      expect(scan.rebuilt, isFalse);
      expect(scan.fence, lessThanOrEqualTo(2));
      expect(scan.tasks, lessThanOrEqualTo(2));
      expect(scan.money, lessThanOrEqualTo(2));
    });

    test('toggling a task child inside segment 1 shifts counts, not scans', () {
      final List<String> lines = buildTrainingLog(minLines: 3000);
      final int parent = _findMixedTaskParent(lines, 256, 511);
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.taskIndeterminate(controller.codeLines, parent), isTrue);

      // The whole subtree lives in segment 1, so checking the one
      // unchecked child resolves the parent — a *result* change with an
      // unchanged frame stack at the segment-2 seam.
      _replaceLine(controller, parent + 2, '  - [x] main lift');
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'child checked in segment 1',
      );
      expect(index.taskIndeterminate(controller.codeLines, parent), isFalse);
      expect(scan.rebuilt, isFalse);
      expect(scan.tasks, lessThanOrEqualTo(2));

      // A second edit at the bottom of the document: if the count shift
      // applied above was wrong, this rescan resumes from a bogus offset.
      final int bottom = controller.codeLines.length - 20;
      _replaceLine(controller, bottom, '- [ ] tail task');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'then an edit in the last segment',
      );
    });

    test('a task subtree straddling a segment boundary stays equivalent', () {
      final lines = <String>[
        for (int i = 0; i < 254; i++) 'filler $i',
        '- [ ] parent',
        '  - [x] a',
        '  - [ ] b',
        '  - [ ] c',
        '',
        for (int i = 0; i < 600; i++) 'tail $i',
      ];
      expect(lines[254], '- [ ] parent');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.taskIndeterminate(controller.codeLines, 254), isTrue);

      // Parent + first child in segment 0, the other two children in
      // segment 1. Checking line 257 changes a result that belongs to a
      // line in the *previous* segment.
      _replaceLine(controller, 257, '  - [x] c');
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'child checked across the boundary',
      );
      expect(scan.rebuilt, isFalse);
      expect(scan.tasks, lessThanOrEqualTo(3));

      _replaceLine(controller, 256, '  - [x] b');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'all children checked',
      );
      expect(index.taskIndeterminate(controller.codeLines, 254), isFalse);
    });

    test('an entry history rewritten to the same balance still re-folds', () {
      // Equal seam scalars are not a proof. `$= 0 / $+ 100 / $+ 50` and
      // `$= 0 / $- 50 / $+ 200` end on the same balance (150) with the
      // same history length, the same period start and no target — but
      // `$^ 1` reads *into* the history, so its value changes from 50 to
      // 200.
      final lines = <String>[
        r'$= 0',
        r'$+ 100',
        r'$+ 50',
        for (int i = 0; i < 509; i++) 'filler $i',
        r'$^ 1',
        for (int i = 0; i < 400; i++) 'tail $i',
      ];
      expect(lines[512], r'$^ 1');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.moneyValueAt(controller.codeLines, 512), 5000);

      controller.selection = CodeLineSelection(
        baseIndex: 1,
        baseOffset: 0,
        extentIndex: 2,
        extentOffset: controller.codeLines[2].length,
      );
      controller.replaceSelection('\$- 50\n\$+ 200');
      expect(controller.codeLines.length, lines.length);
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'two ops rewritten, same seam balance',
      );
      expect(index.moneyValueAt(controller.codeLines, 512), 20000);
      expect(scan.rebuilt, isFalse);
      expect(scan.money, controller.codeLines.segments.length);
    });

    test('a checkpoint rewritten to the same balance still re-folds', () {
      // Same trap on the *anchor* history: `$= 100 / $= 200` and
      // `$= 150 / $= 200` agree on every seam scalar, but `$~ 2` measures
      // back to the older checkpoint and drops from 100 to 50.
      final lines = <String>[
        r'$= 100',
        r'$= 200',
        for (int i = 0; i < 510; i++) 'filler $i',
        r'$~ 2',
        for (int i = 0; i < 400; i++) 'tail $i',
      ];
      expect(lines[512], r'$~ 2');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.moneyValueAt(controller.codeLines, 512), 10000);

      _replaceLine(controller, 0, r'$= 150');
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'first checkpoint rewritten',
      );
      expect(index.moneyValueAt(controller.codeLines, 512), 5000);
      expect(scan.rebuilt, isFalse);
      expect(scan.money, controller.codeLines.segments.length);
    });

    test('a seam where only the anchor slice differs still re-folds', () {
      // The sharpest form of the checkpoint trap, and the only case the
      // anchor comparison loop in the money seam proof catches on its
      // own: across the rewritten rows the balance, period start, target
      // scalars, both history *lengths* and the entry history *element
      // for element* are all unchanged. `$= 50 / $+ 50 / $= 100` and
      // `$+ 50 / $= 100 / $= 100` both leave the entry history
      // [0, 5000, 10000, 10000] with period start 3 and balance 10000 —
      // only the anchors move, [0, 5000, 10000] to [0, 10000, 10000], so
      // the `$~ 2` row measuring back to the middle checkpoint drops from
      // 50.00 to 0.
      final lines = <String>[
        r'$= 50',
        r'$+ 50',
        r'$= 100',
        for (int i = 0; i < 509; i++) 'filler $i',
        r'$~ 2',
        for (int i = 0; i < 400; i++) 'tail $i',
      ];
      expect(lines[512], r'$~ 2');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(
        index.moneyValueAt(controller.codeLines, 512),
        5000,
        reason: r'the fixture must start with the $~ 2 row at 50.00',
      );

      controller.selection = CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 2,
        extentOffset: controller.codeLines[2].length,
      );
      controller.replaceSelection('\$+ 50\n\$= 100\n\$= 100');
      expect(controller.codeLines.length, lines.length);
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'three rows rewritten, only the anchors move',
      );
      expect(index.moneyValueAt(controller.codeLines, 512), 0);
      expect(scan.rebuilt, isFalse);
      expect(scan.money, controller.codeLines.segments.length);
    });

    test('an op amount re-folds below, a display label stops early', () {
      final lines = <String>[
        r'$= 1000',
        r'$+ 50 bonus',
        r'$$ running total',
        for (int i = 0; i < 509; i++) 'filler $i',
        r'$$ still going',
        for (int i = 0; i < 400; i++) 'tail $i',
      ];
      expect(lines[512], r'$$ still going');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.moneyValueAt(controller.codeLines, 512), 105000);
      final int segments = controller.codeLines.segments.length;

      _replaceLine(controller, 1, r'$+ 75 bonus');
      final opScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'op amount changed at the top',
      );
      expect(index.moneyValueAt(controller.codeLines, 512), 107500);
      expect(opScan.money, segments);

      _replaceLine(controller, 2, r'$$ running total so far');
      final labelScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'display row label changed',
      );
      expect(labelScan.rebuilt, isFalse);
      expect(labelScan.money, lessThanOrEqualTo(2));
      expect(labelScan.tasks, lessThanOrEqualTo(2));
    });
  });

  group('structural edits keep the incremental path', () {
    // `Enter`, a line delete and a paste all change segment *lengths*.
    // They used to fall through to a whole-document rebuild; now they are
    // the same prefix/suffix splice a keystroke takes.

    CodeLineEditingController freshController() {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog(minLines: 3000)),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('Enter in the middle of segment 5 splices, never rebuilds', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      const int target = 5 * 256 + 100;
      final String text = controller.codeLines[target].text;
      controller.selection = CodeLineSelection.collapsed(
        index: target,
        offset: text.length ~/ 2,
      );
      controller.applyNewLine();

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'Enter inside segment 5',
      );
      expect(scan.rebuilt, isFalse);
      expect(scan.fence, lessThanOrEqualTo(3));
      expect(scan.tasks, lessThanOrEqualTo(3));
      expect(scan.money, lessThanOrEqualTo(3));
    });

    test('deleting a line in segment 5 splices, never rebuilds', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      const int target = 5 * 256 + 100;
      controller.selection = CodeLineSelection.collapsed(
        index: target,
        offset: 0,
      );
      controller.deleteSelectionLines();

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'line deleted in segment 5',
      );
      expect(scan.rebuilt, isFalse);
      expect(scan.fence, lessThanOrEqualTo(3));
      expect(scan.tasks, lessThanOrEqualTo(3));
      expect(scan.money, lessThanOrEqualTo(3));
    });

    test('Enter at the very last line appends without rebuilding', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      final int last = controller.codeLines.length - 1;
      controller.selection = CodeLineSelection.collapsed(
        index: last,
        offset: controller.codeLines[last].length,
      );
      controller.applyNewLine();

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'Enter appended at EOF',
      );
      expect(scan.rebuilt, isFalse);
    });

    test('Enter on line 0 and deleting line 0 stay equivalent', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      controller.applyNewLine();
      final enterScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'Enter on line 0',
      );
      expect(enterScan.rebuilt, isFalse);

      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      controller.deleteSelectionLines();
      final deleteScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'line 0 deleted',
      );
      expect(deleteScan.rebuilt, isFalse);
    });

    test('undo after an Enter stays equivalent', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      const int target = 5 * 256 + 100;
      controller.selection = CodeLineSelection.collapsed(
        index: target,
        offset: 3,
      );
      controller.applyNewLine();
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'Enter applied',
      );

      controller.undo();
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'undone',
      );
      expect(scan.rebuilt, isFalse);
    });

    test('a multi-line paste across two segments stays equivalent', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      controller.selection = CodeLineSelection(
        baseIndex: 250,
        baseOffset: 0,
        extentIndex: 262,
        extentOffset: controller.codeLines[262].length,
      );
      controller.replaceSelection(
        '- [ ] pasted parent\n'
        '  - [x] pasted a\n'
        '  - [ ] pasted b\n'
        '\n'
        '\$= 4200 pasted reset\n'
        '\$+ 12.50 pasted\n'
        '\$\$\n'
        '```\n'
        'pasted fence body\n'
        '```\n'
        'pasted tail',
      );

      // Whether this splices or rebuilds depends on how many segment
      // backing lists the paste happens to preserve; only equivalence is
      // guaranteed. In practice it splices: `replaceSelection` rebuilds
      // through `sublines` + `addFrom`, which share every untouched
      // segment's backing list.
      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'multi-line paste across a boundary',
      );
      expect(scan.rebuilt, isFalse);
    });

    test('an Enter above a straddling subtree renumbers stored state', () {
      // A task parent at 1022 with children at 1023/1024/1025 straddles
      // the segment 3/4 boundary, and a `$$` row sits below it. An Enter
      // in segment 2 shifts every line below by one: the stored frame
      // snapshots and the money line indices must be renumbered, or the
      // seam proofs below fire against stale line numbers.
      final lines = <String>[
        r'$= 500',
        for (int i = 1; i < 1022; i++)
          i == 10 ? r'$+ 25 side job' : 'filler $i',
        '- [ ] parent',
        '  - [x] a',
        '  - [ ] b',
        '  - [ ] c',
        '',
        for (int i = 0; i < 74; i++) 'mid $i',
        r'$$',
        for (int i = 0; i < 400; i++) 'tail $i',
      ];
      expect(lines[1022], '- [ ] parent');
      expect(lines[1101], r'$$');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.taskIndeterminate(controller.codeLines, 1022), isTrue);
      expect(index.moneyValueAt(controller.codeLines, 1101), 52500);

      const int target = 2 * 256 + 100;
      controller.selection = CodeLineSelection.collapsed(
        index: target,
        offset: 3,
      );
      controller.applyNewLine();

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'Enter in segment 2 above the subtree',
      );
      expect(scan.rebuilt, isFalse);
      final fresh = newIndex(money: true);
      expect(
        index.taskIndeterminate(controller.codeLines, 1023),
        fresh.taskIndeterminate(controller.codeLines, 1023),
      );
      expect(index.taskIndeterminate(controller.codeLines, 1023), isTrue);
      expect(
        index.moneyValueAt(controller.codeLines, 1102),
        fresh.moneyValueAt(controller.codeLines, 1102),
      );
      expect(index.moneyValueAt(controller.codeLines, 1102), 52500);
    });

    test('deleting one whole segment leaves an empty new middle', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );
      final int segmentsBefore = controller.codeLines.segments.length;

      controller.selection = const CodeLineSelection(
        baseIndex: 256,
        baseOffset: 0,
        extentIndex: 512,
        extentOffset: 0,
      );
      controller.replaceSelection('');

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'segment 1 deleted whole',
      );
      expect(scan.rebuilt, isFalse);
      expect(controller.codeLines.segments.length, segmentsBefore - 1);

      _replaceLine(controller, 700, '- [ ] tail task');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'then an edit below the splice',
      );
    });

    test('truncating the tail at a segment boundary (p == n < m)', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      final int last = controller.codeLines.length - 1;
      controller.selection = CodeLineSelection(
        baseIndex: 512,
        baseOffset: 0,
        extentIndex: last,
        extentOffset: controller.codeLines[last].length,
      );
      controller.replaceSelection('');

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'everything below 512 removed',
      );
      expect(scan.rebuilt, isFalse);

      _replaceLine(controller, 100, '- [x] still fine');
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'edit above the truncation',
      );
    });

    test('the same backing list at two segment indexes', () {
      // Backing-list identity is the dirty flag, so a document where one
      // list is reachable at two indexes is the adversarial case for the
      // prefix/suffix match.
      final CodeLines base = codeLinesOf(buildTrainingLog());
      final index = newIndex(money: true);
      expectMatchesFresh(index, base, money: true, reason: 'base');

      final CodeLines duplicated = CodeLines.from(base)..addFrom(base, 0, 256);
      final lists = [for (final s in duplicated.segments) s.codeLines];
      expect(
        identical(lists.first, lists.last),
        isTrue,
        reason: 'the fixture must actually alias one backing list',
      );
      expectMatchesFresh(
        index,
        duplicated,
        money: true,
        reason: 'segment 0 appended a second time',
      );

      final CodeLines front = CodeLines(<CodeLineSegment>[
        base.segments[0].cloneShallowDirty(),
        for (final CodeLineSegment s in base.segments) s.cloneShallowDirty(),
      ]);
      expectMatchesFresh(
        index,
        front,
        money: true,
        reason: 'segment 0 duplicated at the front',
      );

      expectMatchesFresh(
        index,
        CodeLines.from(base),
        money: true,
        reason: 'back to the base shape',
      );
    });

    test('a whole segment prepended leaves an empty old middle', () {
      // Old `[A, B, …]` becomes new `[X, A, B, …]`: the prefix match ends
      // at p = 0 and the suffix match covers every old segment, so the
      // splice's old middle is empty and its `replaceRange` removes
      // nothing. The captured entry state has to be detached from
      // `_states` for that branch — the object it was captured from
      // survives the splice at `p + newMiddleCount`, where the
      // renumbering loop and all three passes write.
      final CodeLines base = codeLinesOf(buildTrainingLog(minLines: 1500));
      final index = newIndex(money: true);
      expectMatchesFresh(index, base, money: true, reason: 'base');

      final CodeLines front = CodeLines(<CodeLineSegment>[
        CodeLineSegment.of(
          codeLines: <CodeLine>[
            CodeLine('- [ ] inserted parent'),
            CodeLine('  - [x] child'),
            CodeLine(r'$= 777'),
          ],
        ),
        for (final CodeLineSegment s in base.segments) s.cloneShallowDirty(),
      ]);
      expect(front.length, base.length + 3);
      expect(front.segments.length, base.segments.length + 1);

      final scan = _scanOf(index, front);
      expectMatchesFresh(
        index,
        front,
        money: true,
        reason: 'a fresh segment spliced in at the front',
      );
      expect(scan.rebuilt, isFalse);
    });

    test('a multi-line paste starting inside a fence stays equivalent', () {
      // Half the pasted rows land above the closing fence the paste
      // itself carries and stay inert; the rows below it are live, and
      // the block's original closer becomes an opener that flips every
      // role beneath it.
      final List<String> source = buildTrainingLog(minLines: 3000);
      final int body = source.indexWhere(
        (l) => l.startsWith('final int reps = '),
        600,
      );
      expect(body, greaterThan(0));
      expect(source[body - 1], '```dart');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(source),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );
      expect(
        index.fenceRoleAt(controller.codeLines, body),
        MarkdownFenceRole.interior,
      );

      controller.selection = CodeLineSelection.collapsed(
        index: body,
        offset: controller.codeLines[body].length,
      );
      controller.replaceSelection(
        '\n'
        '- [ ] inert parent\n'
        '  - [x] inert a\n'
        '  - [ ] inert b\n'
        '\$= 4200 inert\n'
        '```\n'
        '- [ ] live parent\n'
        '  - [x] live a\n'
        '  - [ ] live b\n'
        '\$+ 12.50 live',
      );

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a paste landing inside a fence',
      );
      expect(scan.rebuilt, isFalse);
    });

    test('deleting a whole fence, then only a closer, stays equivalent', () {
      final List<String> source = buildTrainingLog(minLines: 3000);
      final int opener = source.indexOf('```dart', 600);
      expect(opener, greaterThan(0));
      expect(source[opener + 3], '```');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(source),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      controller.selection = CodeLineSelection(
        baseIndex: opener,
        baseOffset: 0,
        extentIndex: opener + 4,
        extentOffset: 0,
      );
      controller.replaceSelection('');
      final wholeScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'opener, body and closer removed together',
      );
      expect(wholeScan.rebuilt, isFalse);

      // The next block, now missing its closer: every role, task row and
      // money row below it goes inert.
      final int next = source.indexOf('```dart', opener + 4) - 4;
      expect(controller.codeLines[next].text, '```dart');
      expect(controller.codeLines[next + 3].text, '```');
      controller.selection = CodeLineSelection(
        baseIndex: next + 3,
        baseOffset: 0,
        extentIndex: next + 4,
        extentOffset: 0,
      );
      controller.replaceSelection('');
      final closerScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'only the closing fence removed',
      );
      expect(closerScan.rebuilt, isFalse);
      expect(
        index.fenceRoleAt(
          controller.codeLines,
          controller.codeLines.length - 1,
        ),
        MarkdownFenceRole.interior,
      );
    });

    test('a replacement that orphans a stored task frame stays equivalent', () {
      // The parent sits in segment 0 and its children run past line 256,
      // so segment 1's stored entry frame points back at the parent's
      // line. A multi-line replacement with a non-zero delta *above* that
      // line leaves the stored line inside the replaced range `[a, b)`,
      // where `_TaskSnapshot.orphaned` must mark it unmatchable rather
      // than shifting it onto some unrelated row.
      final lines = <String>[
        for (int i = 0; i < 253; i++) 'filler $i',
        '- [ ] parent',
        '  - [x] c0',
        '  - [ ] c1',
        '  - [x] c2',
        '  - [ ] c3',
        '  - [x] c4',
        '',
        for (int i = 0; i < 600; i++) 'tail $i',
      ];
      expect(lines[253], '- [ ] parent');
      expect(lines[256], '  - [x] c2');
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(lines),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expect(index.taskIndeterminate(controller.codeLines, 253), isTrue);

      controller.selection = CodeLineSelection(
        baseIndex: 254,
        baseOffset: 0,
        extentIndex: 255,
        extentOffset: controller.codeLines[255].length,
      );
      controller.replaceSelection('  - [x] c0\n  - [ ] c1\n  - [x] c1b');
      expect(controller.codeLines.length, lines.length + 1);

      final scan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'a child row split under a straddling parent',
      );
      expect(scan.rebuilt, isFalse);
      final fresh = newIndex(money: true);
      expect(
        index.debugIndeterminate(controller.codeLines),
        fresh.debugIndeterminate(controller.codeLines),
      );
      expect(index.taskIndeterminate(controller.codeLines, 253), isTrue);
    });

    test('replacing and then deleting the very last line stays equivalent', () {
      final controller = freshController();
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      final int last = controller.codeLines.length - 1;
      _replaceLine(controller, last, r'$+ 33.33 last line');
      final replaceScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'last line replaced',
      );
      expect(replaceScan.rebuilt, isFalse);

      controller.selection = CodeLineSelection.collapsed(
        index: last,
        offset: 0,
      );
      controller.deleteSelectionLines();
      expect(controller.codeLines.length, last);
      final deleteScan = _scanOf(index, controller.codeLines);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'last line deleted',
      );
      expect(deleteScan.rebuilt, isFalse);
    });
  });

  group('degenerate documents', () {
    test('the document collapses to one line and then to none', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog(minLines: 1500)),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'initial',
      );

      final int last = controller.codeLines.length - 1;
      controller.selection = CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: last,
        extentOffset: controller.codeLines[last].length,
      );
      controller.replaceSelection('x');
      expect(controller.codeLines.length, 1);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'select-all replaced by one line',
      );

      // A zero-line document has no segment at all: every pass must run
      // its empty loop without touching a start index it does not have.
      final CodeLines empty = CodeLines.empty();
      expect(empty.length, 0);
      expect(index.fenceRoleAt(empty, 0), MarkdownFenceRole.none);
      expect(index.moneyValueAt(empty, 0), isNull);
      expect(index.taskIndeterminate(empty, 0), isFalse);
      expect(index.debugIndeterminate(empty), isEmpty);
      expectMatchesFresh(index, empty, money: true, reason: 'no lines left');
    });
  });

  group('indeterminate set', () {
    // `expectMatchesFresh` only asks about lines that exist, so it cannot
    // see a stale entry the incremental splice forgot to remove — a line
    // that a delete pushed past the end of the document, say. Comparing
    // the whole set against a freshly built index closes that gap, and
    // the `assert`s inside the splice catch a duplicate the moment one
    // would be inserted.
    test('survives 120 seeded mixed edits set-for-set', () {
      final controller = CodeLineEditingController(
        codeLines: codeLinesOf(buildTrainingLog(minLines: 3000)),
      );
      addTearDown(controller.dispose);
      final index = newIndex(money: true);
      final rng = Random(90210);

      for (int step = 0; step < 120; step++) {
        final int target = step < _boundaryTargets.length
            ? _boundaryTargets[step]
            : rng.nextInt(controller.codeLines.length);
        final _EditKind kind =
            _EditKind.values[rng.nextInt(_EditKind.values.length)];
        _applyEdit(controller, target, kind, rng);

        final fresh = newIndex(money: true);
        expect(
          index.debugIndeterminate(controller.codeLines),
          fresh.debugIndeterminate(controller.codeLines),
          reason: 'step $step: ${kind.name} @ $target',
        );
      }

      expect(index.debugIndeterminate(controller.codeLines), isNotEmpty);
      expectMatchesFresh(
        index,
        controller.codeLines,
        money: true,
        reason: 'after 120 seeded edits',
      );
    });
  });

  group('shared constants', () {
    test('the money parser and the span builder share one length bound', () {
      // The money pass carries no length guard of its own: it relies on
      // `MarkdownMoneySyntax.parse` refusing oversized lines at exactly
      // the limit past which the span builder renders raw.
      expect(
        MarkdownEditorSpanBuilder.maxStyledLineLength,
        MarkdownMoneySyntax.maxLineLength,
      );
    });
  });
}

/// Forces the pending `_ensure` and returns what it did. Every accessor
/// runs `_ensure`, and a second call with the same [CodeLines] is a
/// no-op that leaves the record untouched, so this may be read before or
/// after [expectMatchesFresh].
({bool rebuilt, int fence, int callout, int tasks, int money}) _scanOf(
  MarkdownEditorLineIndex index,
  CodeLines lines,
) {
  index.fenceRoleAt(lines, 0);
  return index.debugLastScan;
}

/// The line of a `- [ ] session` parent whose whole five-line subtree
/// lies inside `[start, end]` and whose children are mixed (two checked,
/// one not) — the shape that renders indeterminate.
int _findMixedTaskParent(List<String> lines, int start, int end) {
  for (int i = start; i + 4 <= end; i++) {
    if (!lines[i].startsWith('- [ ] session ')) continue;
    if (lines[i + 1] == '  - [x] warmup' &&
        lines[i + 2] == '  - [ ] main lift' &&
        lines[i + 3] == '  - [x] cooldown' &&
        lines[i + 4] == '- [x] logged') {
      return i;
    }
  }
  throw StateError('no mixed task subtree inside [$start, $end]');
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
    switch (i % 8) {
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
          '- '
              r'$+ 10 snack',
          '',
        ]);
      case 7:
        // A callout block (lead, plain body, a `>>` body, and a nested
        // lead that is body text of the outer block), then a fence whose
        // closer is immediately followed by a second lead — the shape
        // where the callout pass has to read the fence roles first. Ten
        // lines, so the cycle stays odd and its blocks keep landing on
        // different segment boundaries.
        out.addAll([
          '> [!TIP] Rest $i',
          '> keep the bar loose',
          '>> nested note',
          '> [!NOTE] inner lead',
          '',
          '```',
          'inert $i',
          '```',
          '> [!WARNING] after fence',
          '> body',
        ]);
    }
    i++;
  }
  return out;
}

/// A document whose every 256-line segment opens with one callout block
/// (lead, two body lines, the blank that ends it) and is filled out to
/// exactly one segment. A line's segment index is therefore `line ~/ 256`
/// and the block never straddles a seam, which is what lets the seam
/// proofs aim a keystroke at a chosen segment.
List<String> _calloutSegments(int segments) => <String>[
  for (int s = 0; s < segments; s++) ...[
    '> [!TIP] block $s',
    '> body one $s',
    '> body two $s',
    '',
    for (int i = 0; i < 252; i++) 'filler $s-$i',
  ],
];

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
    final int ca = index.calloutAt(lines, i);
    final int cb = fresh.calloutAt(lines, i);
    if (ca != cb) mismatches.add('line $i callout: $ca != $cb');
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
    reason:
        '$reason — incremental index diverged from a fresh one '
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

enum _EditKind { replace, enterSplit, deleteLine, fenceToggle, calloutToggle }

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
      controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: offset,
      );
      controller.applyNewLine();
    case _EditKind.deleteLine:
      if (controller.codeLines.length <= 1) return;
      controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: 0,
      );
      controller.deleteSelectionLines();
    case _EditKind.fenceToggle:
      final String text = controller.codeLines[index].text;
      _replaceLine(
        controller,
        index,
        text.trimLeft().startsWith('```') ? 'was a fence line' : '```',
      );
    case _EditKind.calloutToggle:
      // A three-state cycle over the callout grammar's own transitions:
      // plain line -> lead -> plain quote body -> plain line. Every step
      // flips the role of every contiguous `>` line below it.
      final String text = controller.codeLines[index].text;
      final String next;
      if (MarkdownCalloutSyntax.parseLead(text) != null) {
        next = '> toggled body';
      } else if (MarkdownCalloutSyntax.isBlockquoteLine(text)) {
        next = 'toggled';
      } else {
        next = '> [!TIP] toggled';
      }
      _replaceLine(controller, index, next);
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
