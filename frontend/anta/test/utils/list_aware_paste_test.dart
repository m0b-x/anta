import 'package:flutter_test/flutter_test.dart';

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
  });
}
