import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/list_indent_action.dart';

/// E9 — the bar's indent and outdent buttons run the wrapper's Tab path:
/// a single list line moves one grid step with the caret on the same
/// character, as one undo node; anything else is the fork's own indent.
void main() {
  CodeLineEditingController controllerAt(
    String text, {
    required int index,
    required int offset,
  }) {
    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
    return controller;
  }

  /// What the fork's own indent does to the same document and selection —
  /// the fallback must be exactly that, nothing of its own.
  String forkResult(
    String text,
    CodeLineSelection selection, {
    required bool outdent,
  }) {
    final reference = CodeLineEditingController.fromText(text);
    addTearDown(reference.dispose);
    reference.selection = selection;
    outdent ? reference.applyOutdent() : reference.applyIndent();
    return reference.text;
  }

  test('indent moves a list line one step and keeps the caret on its '
      'character', () {
    final controller = controllerAt('- eggs\n- milk', index: 1, offset: 4);

    ListIndentAction.apply(controller, outdent: false);

    expect(controller.codeLines[1].text, '  - milk');
    expect(
      controller.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 6),
    );
  });

  test('outdent moves a nested list line back one step', () {
    final controller = controllerAt('  - milk', index: 0, offset: 5);

    ListIndentAction.apply(controller, outdent: true);

    expect(controller.text, '- milk');
    expect(
      controller.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 3),
    );
  });

  test('a caret inside the indent clamps to the line start on outdent', () {
    final controller = controllerAt('  - milk', index: 0, offset: 1);

    ListIndentAction.apply(controller, outdent: true);

    expect(controller.text, '- milk');
    expect(controller.selection.extentOffset, 0);
  });

  test('a list indent is one undo node', () {
    final controller = controllerAt('- eggs\n- milk', index: 1, offset: 6);

    ListIndentAction.apply(controller, outdent: false);
    expect(controller.text, '- eggs\n  - milk');

    controller.undo();
    expect(controller.text, '- eggs\n- milk');
  });

  test('indent on a first item is a no-op that records nothing', () {
    for (final text in ['- milk', 'intro\n- milk']) {
      final index = text.split('\n').length - 1;
      final controller = controllerAt(text, index: index, offset: 4);

      ListIndentAction.apply(controller, outdent: false);

      expect(controller.text, text);
      expect(
        controller.selection,
        CodeLineSelection.collapsed(index: index, offset: 4),
      );
      expect(controller.canUndo, isFalse);
    }
  });

  test('indent stops one level under the item above', () {
    final controller = controllerAt('- eggs\n  - milk', index: 1, offset: 6);

    ListIndentAction.apply(controller, outdent: false);

    expect(controller.text, '- eggs\n  - milk');
    expect(controller.canUndo, isFalse);
  });

  test('outdent is never capped', () {
    final controller = controllerAt('intro\n    - milk', index: 1, offset: 7);

    ListIndentAction.apply(controller, outdent: true);

    expect(controller.text, 'intro\n  - milk');
    expect(controller.selection.extentOffset, 5);
  });

  test('Tab on a quoted item nests it after the quote run, never pads the '
      'caret', () {
    // The caret mid-word: the fork's indent would split `milk` there.
    final controller = controllerAt('> - eggs\n> - milk', index: 1, offset: 6);

    ListIndentAction.apply(controller, outdent: false);

    expect(controller.text, '> - eggs\n>   - milk');
    expect(
      controller.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 8),
    );
    controller.undo();
    expect(controller.text, '> - eggs\n> - milk');
  });

  test('a quoted item obeys the cap at its own quote depth', () {
    for (final text in ['> - milk', '- eggs\n> - milk', '> intro\n> - milk']) {
      final index = text.split('\n').length - 1;
      final controller = controllerAt(text, index: index, offset: 6);

      ListIndentAction.apply(controller, outdent: false);

      expect(controller.text, text);
      expect(controller.canUndo, isFalse);
    }
  });

  test('Shift-Tab on a quoted item outdents it and keeps the quote', () {
    final controller = controllerAt('>   - milk', index: 0, offset: 8);

    ListIndentAction.apply(controller, outdent: true);

    expect(controller.text, '> - milk');
    expect(controller.selection.extentOffset, 6);
  });

  test('a caret in the quote run stays put, one in the outdented indent '
      'clamps to the item', () {
    final inRun = controllerAt('> - eggs\n> - milk', index: 1, offset: 1);
    ListIndentAction.apply(inRun, outdent: false);
    expect(inRun.codeLines[1].text, '>   - milk');
    expect(inRun.selection.extentOffset, 1);

    final inIndent = controllerAt('>   - milk', index: 0, offset: 3);
    ListIndentAction.apply(inIndent, outdent: true);
    expect(inIndent.text, '> - milk');
    expect(inIndent.selection.extentOffset, 2);
  });

  test('outdent at column 0 changes nothing and records nothing', () {
    final controller = controllerAt('- milk', index: 0, offset: 3);

    ListIndentAction.apply(controller, outdent: true);

    expect(controller.text, '- milk');
    expect(
      controller.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 3),
    );
    expect(controller.canUndo, isFalse);
  });

  test('a plain line falls back to the fork indent', () {
    const text = 'plain words';
    const selection = CodeLineSelection.collapsed(index: 0, offset: 5);
    final controller = controllerAt(text, index: 0, offset: 5);

    ListIndentAction.apply(controller, outdent: false);

    expect(controller.text, forkResult(text, selection, outdent: false));
  });

  test('a fenced list line falls back to the fork indent', () {
    const text = '```\n- milk\n```';
    const selection = CodeLineSelection.collapsed(index: 1, offset: 2);
    final controller = controllerAt(text, index: 1, offset: 2);

    ListIndentAction.apply(
      controller,
      outdent: false,
      isFenceLine: (lineIndex) => lineIndex == 1,
    );

    expect(controller.text, forkResult(text, selection, outdent: false));
    expect(controller.codeLines[1].text, isNot('  - milk'));
  });

  test('a multi-line selection falls back to the fork indent', () {
    const text = '- milk\n- eggs';
    const selection = CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 1,
      extentOffset: 6,
    );
    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    controller.selection = selection;

    ListIndentAction.apply(controller, outdent: false);

    expect(controller.text, forkResult(text, selection, outdent: false));
    expect(controller.text, '  - milk\n  - eggs');
  });

  test('outdent on a plain indented line falls back to the fork outdent', () {
    const text = '    code';
    const selection = CodeLineSelection.collapsed(index: 0, offset: 6);
    final controller = controllerAt(text, index: 0, offset: 6);

    ListIndentAction.apply(controller, outdent: true);

    expect(controller.text, forkResult(text, selection, outdent: true));
  });

  group('tryApply', () {
    test('makes the list step and reports the change', () {
      final controller = controllerAt('- eggs\n- milk', index: 1, offset: 4);

      expect(ListIndentAction.tryApply(controller, outdent: false), isTrue);
      expect(controller.text, '- eggs\n  - milk');
      expect(controller.selection.extentOffset, 6);

      expect(ListIndentAction.tryApply(controller, outdent: true), isTrue);
      expect(controller.text, '- eggs\n- milk');
    });

    test('a list line the step leaves alone reports no change', () {
      final capped = controllerAt('intro\n- milk', index: 1, offset: 4);
      expect(ListIndentAction.tryApply(capped, outdent: false), isFalse);
      expect(capped.text, 'intro\n- milk');
      expect(capped.canUndo, isFalse);

      final atColumn0 = controllerAt('- milk', index: 0, offset: 4);
      expect(ListIndentAction.tryApply(atColumn0, outdent: true), isFalse);
      expect(atColumn0.canUndo, isFalse);
    });

    test('never falls back to the fork indent', () {
      final plain = controllerAt('plain words', index: 0, offset: 5);
      expect(ListIndentAction.tryApply(plain, outdent: false), isFalse);
      expect(plain.text, 'plain words');

      final fenced = controllerAt('```\n- milk\n```', index: 1, offset: 2);
      expect(
        ListIndentAction.tryApply(
          fenced,
          outdent: false,
          isFenceLine: (lineIndex) => lineIndex == 1,
        ),
        isFalse,
      );
      expect(fenced.text, '```\n- milk\n```');

      final multiLine = CodeLineEditingController.fromText('- milk\n- eggs');
      addTearDown(multiLine.dispose);
      multiLine.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 1,
        extentOffset: 6,
      );
      expect(ListIndentAction.tryApply(multiLine, outdent: false), isFalse);
      expect(multiLine.text, '- milk\n- eggs');
    });
  });
}
