import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/shortcut_applier.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';

/// The applier's two halves, kept apart on purpose.
///
/// [ShortcutApplier.resolve] does all the awaiting (counter mutations,
/// date formatting) and hands back a string; the write is the caller's,
/// so the note editor can run it synchronously inside one undo entry and
/// one edit-tracker guard. A resolve that touched the document would put
/// the insert back in a microtask and lose both.
void main() {
  CodeLineEditingController controllerWith(String text, {int? line}) {
    final controller = CodeLineEditingController.fromText(text);
    controller.selection = CodeLineSelection.collapsed(
      index: line ?? 0,
      offset: 0,
    );
    return controller;
  }

  CustomMarkdownShortcut shortcut({
    required String insertType,
    String beforeText = '',
    String afterText = '',
  }) => CustomMarkdownShortcut(
    id: 'test-$insertType',
    label: 'test',
    iconCodePoint: 0xe000,
    iconFontFamily: 'MaterialIcons',
    beforeText: beforeText,
    afterText: afterText,
    insertType: insertType,
  );

  Future<int?> noCounter(String id, CounterOp op) async => null;

  group('resolve', () {
    test('returns the text without touching the document', () async {
      final controller = controllerWith('body');

      final text = await ShortcutApplier.resolve(
        controller: controller,
        shortcut: shortcut(
          insertType: 'wrap',
          beforeText: '**',
          afterText: '**',
        ),
        mutateCounter: noCounter,
      );

      expect(text, '**');
      expect(controller.text, 'body');
    });

    test('wraps the selection when there is one', () async {
      final controller = controllerWith('body');
      controller.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: 4,
      );

      final text = await ShortcutApplier.resolve(
        controller: controller,
        shortcut: shortcut(
          insertType: 'wrap',
          beforeText: '**',
          afterText: '**',
        ),
        mutateCounter: noCounter,
      );

      expect(text, '**body**');
      expect(controller.text, 'body');
    });

    test('returns null for the header shortcut', () async {
      final controller = controllerWith('# heading');

      final text = await ShortcutApplier.resolve(
        controller: controller,
        shortcut: shortcut(insertType: 'header'),
        mutateCounter: noCounter,
      );

      expect(text, isNull);
      expect(controller.text, '# heading');
    });
  });

  group('applyHeader', () {
    void expectCycle(String from, String to) {
      final controller = controllerWith(from);
      ShortcutApplier.applyHeader(controller);
      expect(controller.text, to, reason: '"$from" should cycle to "$to"');
    }

    test('plain text gains a level-1 heading', () {
      expectCycle('squat 5x5', '# squat 5x5');
    });

    test('each level adds one hash', () {
      expectCycle('# squat', '## squat');
      expectCycle('##### squat', '###### squat');
    });

    test('level six drops back to the bare content', () {
      expectCycle('###### squat', 'squat');
    });

    test('a bare hash run is an empty heading, so it cycles up', () {
      // `###` with no trailing space is a level-3 heading with empty
      // content per `MarkdownLineShape.headingAt` — the same call both
      // rendering surfaces make — so the toolbar takes it to `#### `.
      expectCycle('###', '#### ');
    });

    test('seven hashes are prose, not a heading', () {
      expectCycle('####### squat', '# ####### squat');
    });

    test('an indented heading keeps its indent', () {
      // `headingAt` allows leading whitespace; the rewrite must not
      // swallow it, or the line shifts left on every cycle.
      expectCycle('  ## squat', '  ### squat');
      expectCycle('  ###### squat', '  squat');
    });

    test('a hashtag is prose, not a heading', () {
      expectCycle('#squat', '# #squat');
    });

    test('the caret line is the one rewritten', () {
      final controller = controllerWith('first\n# second\nthird', line: 1);
      ShortcutApplier.applyHeader(controller);
      expect(controller.text, 'first\n## second\nthird');
    });
  });
}
