import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// A long press on the mobile gesture path (widget tests run with
/// `kIsAndroid` true). On a word it selects the word; where there is no
/// word — an empty line always — it must still move the caret to the
/// press, because the toolbar the press ends with pastes at the caret.
void main() {
  const document = 'abcdefghij\n\nklmnopqrst';

  testWidgets('a long press on an empty line puts the caret there', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    e.controller.selection = const CodeLineSelection.collapsed(
      index: 2,
      offset: 4,
    );
    // Focused, as while editing: an unfocused editor already moves the
    // caret at tap-down, which hid the long-press gap.
    e.focusNode.requestFocus();
    await tester.pump();
    expect(e.focusNode.hasFocus, isTrue);

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 1, 0),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    expect(
      e.controller.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 0),
    );

    await teardownEditor(tester);
  });

  testWidgets('a long press on a word still selects the word', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    e.focusNode.requestFocus();
    await tester.pump();

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 2, 3),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    expect(
      e.controller.selection,
      const CodeLineSelection(
        baseIndex: 2,
        baseOffset: 0,
        extentIndex: 2,
        extentOffset: 10,
      ),
    );

    await teardownEditor(tester);
  });
}
