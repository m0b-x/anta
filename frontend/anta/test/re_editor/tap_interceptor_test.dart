import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/editor_test_support.dart';

/// The mobile gesture path's [CodeEditorTapInterceptor] contract: a claimed
/// tap fires the callback once, leaves the selection untouched, never
/// focuses the editor, and a held-down claim that turns into a long press
/// is cancelled rather than firing. Widget tests run with `kIsAndroid` true,
/// so `_CodeSelectionGestureDetector` builds its `GestureDetector` branch
/// (onTapDown/onTapUp/onLongPress*), which is what every case below
/// exercises.
///
/// The editor, the fake zone (line 0, offsets 0-2) and the cell geometry
/// come from `support/editor_test_support.dart`, shared with the desktop
/// twin so both paths are exercised against the same fixture.
void main() {
  const document = 'abcdefghij\nklmnopqrst\nuvwxyz';

  testWidgets('a claimed tap fires once and leaves the selection identical', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    final before = e.controller.selection;

    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 1));
    await tester.pump();

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));
    expectSameSelection(e.controller.selection, before);

    await teardownEditor(tester);
  });

  testWidgets('two consecutive claimed taps both fire', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);

    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 1));
    await tester.pump();

    expect(e.taps.length, 2);

    await teardownEditor(tester);
  });

  testWidgets('a claimed tap never focuses the editor', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);
    expect(e.focusNode.hasFocus, isFalse);

    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 1));
    await tester.pump();
    expect(e.focusNode.hasFocus, isFalse);
    await tester.pump(Duration.zero);
    expect(e.focusNode.hasFocus, isFalse);

    await tester.tapAt(zoneCellOf(tester, e.notifier, 2, 9));
    await tester.pump();
    expect(e.focusNode.hasFocus, isTrue);

    await teardownEditor(tester);
  });

  testWidgets('a long press on a zone cancels the claim', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 2),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(e.taps, isEmpty);

    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 0));
    await tester.pump();

    expect(
      e.taps.length,
      1,
      reason:
          'the cancelled claim must have been cleared before the next '
          'press, or the leaked one is what fires',
    );
    expect(e.taps.single.index, 0);
    expect(
      e.taps.single.offset,
      0,
      reason: 'the position of this tap, not the long press two cells away',
    );

    await teardownEditor(tester);
  });

  testWidgets('a non-zone tap is not intercepted', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);

    await tester.tapAt(zoneCellOf(tester, e.notifier, 1, 9));
    await tester.pump();

    expect(e.taps, isEmpty);
    expect(e.controller.selection.baseIndex, 1);
    expect(e.controller.selection.baseOffset, 9);

    await teardownEditor(tester);
  });
}
