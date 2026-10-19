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
    final controller = controllerAt('intro\n- milk', index: 1, offset: 4);

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
    final controller = controllerAt('- milk', index: 0, offset: 6);

    ListIndentAction.apply(controller, outdent: false);
    expect(controller.text, '  - milk');

    controller.undo();
    expect(controller.text, '- milk');
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
}
