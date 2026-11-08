import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// S5 — find on a large note. The position mapper walks the text once
/// instead of re-walking the lines per match, and a run overtaken by a
/// newer edit is dropped instead of queued behind it. No cap: every match
/// stays, so next/previous keep reaching the last one.

/// The lookup the mapper replaced, kept as the reference it must agree with.
CodeLinePosition _naive(List<String> lines, int index) {
  var start = 0;
  var line = 0;
  var offset = -1;
  for (; line < lines.length; line++) {
    if (index <= start + lines[line].length) {
      offset = index - start;
      break;
    }
    start += lines[line].length + 1;
  }
  return CodeLinePosition(index: line, offset: offset);
}

void _expectAgrees(String text, RegExp pattern) {
  final lines = text.split('\n');
  final matches = pattern.allMatches(text).toList();
  final mapped = CodeFindPositions.map(text, matches);

  expect(mapped, hasLength(matches.length));
  for (var i = 0; i < matches.length; i++) {
    final start = _naive(lines, matches[i].start);
    final end = _naive(lines, matches[i].end);
    final got = mapped[i];
    if (got.baseIndex != start.index ||
        got.baseOffset != start.offset ||
        got.extentIndex != end.index ||
        got.extentOffset != end.offset) {
      fail('match $i at ${matches[i].start}..${matches[i].end}: got $got');
    }
  }
}

void main() {
  group('CodeFindPositions.map', () {
    test('agrees with the line-by-line lookup on 30,000 matches', () {
      final text = List.generate(
        10000,
        (i) => i.isEven ? 'set rep rep rep rep rep $i' : 'rest',
      ).join('\n');
      final pattern = RegExp('rep|rest');

      expect(pattern.allMatches(text).length, 30000);
      _expectAgrees(text, pattern);
    });

    test('matches across a line break and at its edge map as before', () {
      const text = 'alpha\nbeta\n\ngamma\n';
      _expectAgrees(text, RegExp(r'a\nb'));
      _expectAgrees(text, RegExp(r'a$', multiLine: true));
      _expectAgrees(text, RegExp(r'\n'));
      _expectAgrees(text, RegExp(r'^', multiLine: true));
      _expectAgrees(text, RegExp(r'beta\n\ngam'));
    });

    test('steps over each code unit at most once', () {
      final text = List.generate(5000, (i) => 'rep $i rep').join('\n');

      final mapped = CodeFindPositions.map(
        text,
        RegExp('rep').allMatches(text),
      );

      expect(mapped, hasLength(10000));
      expect(CodeFindPositions.lastSteps, lessThanOrEqualTo(text.length));
    });
  });

  group('LatestWinsQueue', () {
    late List<String> started;
    late Map<String, Completer<String>> runs;
    late List<String> delivered;
    late LatestWinsQueue<String, String> queue;

    setUp(() {
      started = [];
      runs = {};
      delivered = [];
      queue = LatestWinsQueue<String, String>((req) {
        started.add(req);
        return (runs[req] = Completer<String>()).future;
      });
    });

    void run(String req) => queue.run(req, delivered.add);

    test('an edit during a run drops the stale result', () async {
      run('a');
      run('b');
      run('c');
      expect(started, ['a'], reason: 'one run at a time');

      runs['a']!.complete('result a');
      await pumpEventQueue();

      expect(delivered, isEmpty, reason: 'a newer request overtook a');
      expect(started, ['a', 'c'], reason: 'only the newest waiting one runs');

      runs['c']!.complete('result c');
      await pumpEventQueue();

      expect(delivered, ['result c']);
    });

    test('a run with nothing behind it is delivered', () async {
      run('a');
      runs['a']!.complete('result a');
      await pumpEventQueue();

      run('b');
      runs['b']!.complete('result b');
      await pumpEventQueue();

      expect(delivered, ['result a', 'result b']);
    });

    test('a failed run frees the queue for the next one', () async {
      run('a');
      runs['a']!.completeError(StateError('isolate gone'));
      await pumpEventQueue();

      run('b');
      expect(started, ['a', 'b']);
      runs['b']!.complete('result b');
      await pumpEventQueue();

      expect(delivered, ['result b']);
    });

    test('a closed queue delivers nothing', () async {
      run('a');
      queue.close();
      runs['a']!.complete('result a');
      await pumpEventQueue();

      expect(delivered, isEmpty);
    });
  });

  // An undo back to the text the current result covers queues no run, so
  // the run the edit started still delivers, over text that is gone.
  test('a result an undo overtook is dropped, the current one kept', () async {
    final edit = CodeLineEditingController.fromText('alpha belt\nbelt two');
    final find = CodeFindController(edit, const CodeFindValue.empty());
    addTearDown(() {
      find.dispose();
      edit.dispose();
    });

    // The search runs on a real isolate.
    Future<void> settled() async {
      for (var i = 0; i < 100 && find.value?.searching != false; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // The overtaken run's delivery, if any, lands within this.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    find.findInputController.text = 'belt';
    await settled();
    final before = find.value!.result!;
    expect(before.matches, hasLength(2));

    edit.selection = const CodeLineSelection.collapsed(index: 1, offset: 8);
    edit.replaceSelection(' belt');
    edit.undo();
    expect(edit.text, 'alpha belt\nbelt two');
    await settled();

    final result = find.value!.result!;
    expect(result.dirty, isFalse);
    expect(result.matches, before.matches);
  });
}
