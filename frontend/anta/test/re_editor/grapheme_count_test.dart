import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// S5 — the stats bar's character count, taken per line so a pause walks
/// only the changed lines, must equal the whole-document grapheme walk it
/// replaced; and a load from lines split off the UI isolate seeds the
/// joined text instead of joining it again.
void main() {
  group('CodeLines.graphemeCount', () {
    const fixtures = <String>[
      '',
      'plain',
      'one\ntwo\n\nfour\n',
      'café\nnaïve',
      'é\ńlead',
      '👍👍\n👍🏽 ok\n🇷🇴🇩🇪',
      '👨‍👩‍👧 family\nzwj 👩‍💻',
      '\n\n\n',
      'tab\there\n  indent',
    ];

    for (final text in fixtures) {
      test('equals the whole walk for ${text.codeUnits.length} units', () {
        final controller = CodeLineEditingController.fromText(text);
        addTearDown(controller.dispose);

        expect(
          controller.codeLines.graphemeCount,
          controller.text.characters.length,
        );
      });
    }

    test('stays exact across an edit', () {
      final controller = CodeLineEditingController.fromText('a\nbé\nc');
      addTearDown(controller.dispose);
      expect(controller.codeLines.graphemeCount, 6);

      controller.text = 'a\nbé👍🏽\nc\nd';

      expect(
        controller.codeLines.graphemeCount,
        controller.text.characters.length,
      );
    });
  });

  group('loadCodeLines', () {
    test(
      'holds the lines and answers text with the string it was given',
      () async {
        const content = 'first\nsecond\nthird';
        final controller = CodeLineEditingController();
        addTearDown(controller.dispose);
        final lines = await content.codeLinesAsync;

        controller.loadCodeLines(lines, content);

        expect(controller.lineCount, 3);
        expect(identical(controller.text, content), isTrue);
        expect(controller.canUndo, isFalse);
      },
    );

    test('a text with carriage returns is joined, never seeded', () async {
      const content = 'first\r\nsecond';
      final controller = CodeLineEditingController();
      addTearDown(controller.dispose);

      controller.loadCodeLines(content.codeLines, content);

      expect(controller.text, 'first\nsecond');
    });
  });
}
