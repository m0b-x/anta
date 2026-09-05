import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// An empty `CodeLines` can be built (`removeLine` on a one-line
/// document yields one) but never rendered: the render reads a first and a
/// last line. The controller's `codeLines` setter always mapped an empty
/// document onto the initial blank line; the `value` setter — the one the
/// app's structural edits write through — now does the same, so no caller
/// has to guard for it.
void main() {
  test('an empty value maps onto the initial blank line', () {
    final controller = CodeLineEditingController.fromText('only line');
    addTearDown(controller.dispose);

    controller.value = CodeLineEditingValue(
      codeLines: controller.codeLines.removeLine(0),
    );

    expect(controller.codeLines.length, 1);
    expect(controller.codeLines.first.text, '');
    expect(controller.text, '');
  });

  test('the codeLines setter keeps mapping an empty document', () {
    final controller = CodeLineEditingController.fromText('a\nb');
    addTearDown(controller.dispose);

    controller.codeLines = CodeLines.of(const <CodeLine>[]);

    expect(controller.codeLines.length, 1);
    expect(controller.text, '');
  });

  test('a non-empty value is published as given', () {
    final controller = CodeLineEditingController.fromText('a\nb');
    addTearDown(controller.dispose);
    final replaced = controller.codeLines.removeLine(0);

    controller.value = CodeLineEditingValue(codeLines: replaced);

    expect(identical(controller.codeLines, replaced), isTrue);
    expect(controller.text, 'b');
  });
}
