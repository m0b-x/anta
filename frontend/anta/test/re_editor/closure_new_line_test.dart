import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Enter between a bracket pair. The code-editor convention opens an
/// indented line inside the pair; in markdown the pair is a `[[link]]`, a
/// `{{ghost}}` or a task box right after auto-pairing, so the fork leaves
/// it off unless `CodeLineOptions.expandClosuresOnNewLine` asks for it.
void main() {
  CodeLineEditingController caretAt(
    String text,
    int offset, [
    CodeLineOptions options = const CodeLineOptions(),
  ]) {
    final controller = CodeLineEditingController.fromText(text, options);
    addTearDown(controller.dispose);
    controller.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: offset,
    );
    return controller;
  }

  test('by default Enter inside a pair is a plain line break', () {
    for (final (text, caret, expected) in [
      ('[[]]', 2, '[[\n]]'),
      ('{{}}', 2, '{{\n}}'),
      ('- []', 3, '- [\n]'),
      ('f()', 2, 'f(\n)'),
    ]) {
      final controller = caretAt(text, caret);

      controller.applyNewLine();

      expect(controller.text, expected, reason: text);
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 0),
        reason: text,
      );
    }
  });

  test('the option restores the indented line inside the pair', () {
    final controller = caretAt(
      '{}',
      1,
      const CodeLineOptions(expandClosuresOnNewLine: true),
    );

    controller.applyNewLine();

    expect(controller.text, '{\n  \n}');
    expect(
      controller.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 2),
    );
  });
}
