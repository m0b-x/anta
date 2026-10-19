import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/list_aware_paste.dart';

/// `ListAwarePaste.transform` is the whole policy behind the list-aware
/// paste — the controller around it does nothing but read the clipboard,
/// the caret line and the fence flag — and it is a pure function, so
/// every rule is pinned here without a widget tree or a controller.
///
/// The policy is deliberately conservative: it either turns *every*
/// pasted line into a sibling of the caret's item or it changes nothing
/// but the line breaks. Each bail-out below is one way "nothing but the
/// line breaks" is reached, and the point of testing them one at a time
/// is that a paste can never come out half-transformed.
void main() {
  /// The transform as the controller calls it: a collapsed caret at the
  /// end of [caretLine], which is where a paste normally lands.
  String pasteInto(
    String caretLine,
    String pasted, {
    int? caretOffset,
    bool collapsed = true,
    bool inFence = false,
  }) {
    return ListAwarePaste.transform(
      caretLine: caretLine,
      caretOffset: caretOffset ?? caretLine.length,
      collapsed: collapsed,
      pasted: pasted,
      inFence: inFence,
    );
  }

  group('line-break normalisation', () {
    test('CRLF and bare CR both become LF', () {
      expect(pasteInto('prose', 'a\r\nb\rc'), 'a\nb\nc');
    });

    test('it happens even when nothing else does', () {
      // Every bail-out below returns the *normalised* text, never the raw
      // clipboard string: the editor's document is LF-only.
      expect(pasteInto('- item', 'a\r\nb', inFence: true), 'a\nb');
      expect(pasteInto('prose', 'a\r\nb'), 'a\nb');
    });

    test('a single-line paste is passed straight through', () {
      expect(pasteInto('- item', 'just one line'), 'just one line');
    });
  });

  group('the caret has to be in a list item\'s content', () {
    test('a plain caret line changes nothing', () {
      expect(pasteInto('just prose', 'a\nb'), 'a\nb');
    });

    test('a non-collapsed selection changes nothing', () {
      expect(pasteInto('- item', 'a\nb', collapsed: false), 'a\nb');
    });

    test('a caret inside the marker changes nothing', () {
      // Offset 1 is between `-` and the space: left of the item's
      // content, so the paste is not continuing an item at all.
      expect(pasteInto('- item', 'a\nb', caretOffset: 1), 'a\nb');
    });

    test('a caret exactly at the content start does transform', () {
      expect(pasteInto('- item', 'a\nb', caretOffset: 2), 'a\n- b');
    });
  });

  group('what the pasted text itself vetoes', () {
    test('a pasted line that is already a list item', () {
      expect(pasteInto('- item', 'a\n- b'), 'a\n- b');
      expect(pasteInto('- item', 'a\n1. b'), 'a\n1. b');
      expect(pasteInto('- item', 'a\n- [ ] b'), 'a\n- [ ] b');
    });

    test('a pasted line-led construct', () {
      for (final led in const <String>[
        '## heading',
        '> quoted',
        '| a | b |',
        '```dart',
        r'$+ 12.50 lunch',
      ]) {
        expect(
          pasteInto('- item', 'a\n$led'),
          'a\n$led',
          reason: 'prefixed a line-led construct: "$led"',
        );
      }
    });

    test('a pasted horizontal rule', () {
      // A rule is not a list line and has no lead marker of its own, so
      // nothing but the rule predicate stops `- ---` coming out.
      for (final rule in const <String>['---', '***', '___', '------']) {
        expect(
          pasteInto('- item', 'a\n$rule'),
          'a\n$rule',
          reason: 'prefixed a horizontal rule: "$rule"',
        );
      }
    });

    test('a spaced rule caret line lends no bullet to a paste', () {
      for (final rule in const <String>['- - -', '* * *']) {
        expect(
          pasteInto(rule, 'a\nb'),
          'a\nb',
          reason: 'continued a rule as a list: "$rule"',
        );
      }
    });

    test('a paste whose only extra line is blank', () {
      // Nothing to continue onto: the blank line ends the list before the
      // first sibling would be created.
      expect(pasteInto('- item', 'a\n'), 'a\n');
      expect(pasteInto('- item', 'a\n\n'), 'a\n\n');
    });
  });

  group('a fenced caret line', () {
    test('never grows markers, whatever the caret line looks like', () {
      // Inside a ``` fence `- item` is source text, not a list item.
      expect(pasteInto('- item', 'a\nb', inFence: true), 'a\nb');
      expect(pasteInto('1. item', 'a\nb', inFence: true), 'a\nb');
      expect(pasteInto('- [ ] item', 'a\nb', inFence: true), 'a\nb');
    });
  });

  group('the transform itself', () {
    test('bullets keep the caret item\'s marker and indent', () {
      expect(pasteInto('  * squat', 'a\nb\nc'), 'a\n  * b\n  * c');
    });

    test('ordered items keep counting from the caret item', () {
      expect(pasteInto('3. third', 'a\nb\nc'), 'a\n4. b\n5. c');
    });

    test('ordered items keep their delimiter', () {
      expect(pasteInto('3) third', 'a\nb'), 'a\n4) b');
    });

    test('tasks continue unchecked, whatever the caret item is', () {
      expect(pasteInto('- [x] done', 'a\nb'), 'a\n- [ ] b');
    });

    test('the first pasted line joins the caret item as it is', () {
      // It lands inside the item the caret is already in, so prefixing it
      // would put a second marker on that line.
      expect(pasteInto('- item', 'first\nsecond'), 'first\n- second');
    });

    test('each pasted line is left-trimmed before the marker goes on', () {
      expect(pasteInto('- item', 'a\n    b'), 'a\n- b');
    });

    test('a blank line stops the transform for good', () {
      // A blank line ends a markdown list, so everything past it pastes
      // raw — including lines that look continuable again.
      expect(pasteInto('- item', 'a\nb\n\nc\nd'), 'a\n- b\n\nc\nd');
    });

    test('one trailing line break is dropped, not left as a bare line', () {
      // A list copied whole ends with its last line's break; kept, the
      // caret would land on an unmarked line under the new items.
      expect(pasteInto('- x', 'a\nb\n'), 'a\n- b');
      expect(pasteInto('- x', 'a\r\nb\r\n'), 'a\n- b');
      // Two breaks are a blank line, which ends the list; what follows it
      // pastes as written, its closing break included.
      expect(pasteInto('- x', 'a\nb\n\n'), 'a\n- b\n\n');
    });

    test('a tail past a blank line keeps its closing line break', () {
      expect(pasteInto('- x', 'a\nb\n\npara\n'), 'a\n- b\n\npara\n');
      expect(pasteInto('- x', 'a\nb\n\npara'), 'a\n- b\n\npara');
    });
  });

  /// The keyboard's own paste key: a multi-line `edit()` holding the input
  /// method's view of the base line with the clipboard spliced in.
  group('the keyboard\'s paste key', () {
    ListAwarePasteController controllerOf(
      String text, {
      bool Function(int lineIndex)? isFenceLine,
    }) {
      final controller = ListAwarePasteController(
        delegate: CodeLineEditingController.fromText(text),
        isFenceLine: isFenceLine,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    void commit(ListAwarePasteController controller, String lineText) {
      controller.edit(
        TextEditingValue(
          text: lineText,
          selection: TextSelection.collapsed(offset: lineText.length),
        ),
      );
    }

    test('continues the caret item, as one undo step', () {
      final controller = controllerOf('- a');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      commit(controller, '- aX\nY');

      expect(controller.text, '- aX\n- Y');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 3),
      );
      controller.undo();
      expect(controller.text, '- a');
    });

    test('leaves a paste outside a list to the editor', () {
      final controller = controllerOf('a');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 1,
      );

      commit(controller, 'aX\nY');

      expect(controller.text, 'aX\nY');
    });

    test('leaves a fenced list line alone', () {
      final controller = controllerOf('- a', isFenceLine: (_) => true);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      commit(controller, '- aX\nY');

      expect(controller.text, '- aX\nY');
    });

    test('a paste over a selection across lines keeps both directions '
        'whole', () {
      // Over a selection the transform bails, and the editor's own cut of
      // the commit applies: forward the base line's prefix, backward its
      // suffix, each held once.
      final forward = controllerOf('- abc\n- def');
      forward.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 3,
        extentIndex: 1,
        extentOffset: 3,
      );
      commit(forward, '- aX\nY');
      expect(forward.text, '- aX\nYef');

      final backward = controllerOf('- abc\n- def');
      backward.selection = const CodeLineSelection(
        baseIndex: 1,
        baseOffset: 3,
        extentIndex: 0,
        extentOffset: 3,
      );
      backward.edit(
        const TextEditingValue(
          text: 'X\nYef',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(backward.text, '- aX\nYef');
    });
  });
}
