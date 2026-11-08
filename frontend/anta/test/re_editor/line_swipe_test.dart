import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The mobile gesture path's [CodeEditorLineSwipeHandler] contract: a
/// horizontal touch drag on a line the handler accepts fires once, at
/// [CodeEditor.lineSwipeDistance] of travel, in the travel's direction,
/// and leaves the selection, focus and toolbar alone; on any other line,
/// for a mouse, a vertical drag, a long press or a read-only editor, the
/// gesture arena resolves as it did before the swipe existed. Widget tests
/// run with `kIsAndroid` true, so `_CodeSelectionGestureDetector` builds
/// its touch branch, which is what every case exercises.
void main() {
  const document = 'abcd efgh ijkl\nmnop qrst uvwx\nyz';

  testWidgets('a right swipe on the accepted line fires once, toRight, '
      'and leaves selection, focus and toolbar untouched', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document);
    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(e.focusNode.hasFocus, isTrue);
    final before = e.controller.selection;
    final shownBefore = e.toolbar.shows;

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 3),
      const Offset(60, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(e.swipes, [(0, true)]);
    expectSameSelection(e.controller.selection, before);
    expect(e.focusNode.hasFocus, isTrue);
    expect(e.toolbar.shows, shownBefore);
    expect(
      e.ancestorDragStarts.value,
      0,
      reason: 'the swipe owns an accepted line\'s horizontal drag',
    );

    await teardownEditor(tester);
  });

  testWidgets('a left swipe fires toRight: false and never focuses', (
    tester,
  ) async {
    final e = await _pumpSwipeEditor(tester, text: document);
    final before = e.controller.selection;

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 9),
      const Offset(-60, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(e.swipes, [(0, false)]);
    expectSameSelection(e.controller.selection, before);
    expect(e.focusNode.hasFocus, isFalse);

    await teardownEditor(tester);
  });

  testWidgets('fires mid-drag, once, not again on more travel or release', (
    tester,
  ) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 1),
    );
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(e.swipes, isEmpty);
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(e.swipes, [(0, true)], reason: '50 px from pointer-down');
    await gesture.moveBy(const Offset(100, 0));
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(e.swipes, [(0, true)]);

    await teardownEditor(tester);
  });

  testWidgets('a 20 px drag fires nothing', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 3),
      const Offset(20, 0),
    );
    await tester.pump();

    expect(e.swipes, isEmpty);

    await teardownEditor(tester);
  });

  testWidgets('a refused line fires nothing and its drag reaches the '
      'ancestor', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 1, 3),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(e.swipes, isEmpty);
    expect(e.ancestorDragStarts.value, 1);
    expect(e.downs, [1], reason: 'asked once, for the line under the down');

    await teardownEditor(tester);
  });

  testWidgets('a mouse drag fires nothing and is never offered', (
    tester,
  ) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 3),
      const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(e.swipes, isEmpty);
    expect(e.downs, isEmpty);

    await teardownEditor(tester);
  });

  testWidgets('a read-only editor never offers the swipe', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document, readOnly: true);

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 3),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(e.swipes, isEmpty);
    expect(e.downs, isEmpty);
    expect(e.ancestorDragStarts.value, 1);

    await teardownEditor(tester);
  });

  testWidgets('a vertical drag on the accepted line scrolls and fires '
      'nothing', (tester) async {
    final long = List<String>.generate(60, (i) => 'line $i').join('\n');
    final e = await _pumpSwipeEditor(tester, text: long, height: 200);
    expect(e.scroll.verticalScroller.position.pixels, 0);

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 3),
      const Offset(0, -150),
    );
    await settle(tester);

    expect(e.swipes, isEmpty);
    expect(e.scroll.verticalScroller.position.pixels, greaterThan(0));

    await teardownEditor(tester);
  });

  testWidgets('a long press on the accepted line still selects the word', (
    tester,
  ) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 6),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(e.swipes, isEmpty);
    final selection = e.controller.selection;
    expect(selection.startIndex, 0);
    expect(selection.endIndex, 0);
    expect(selection.startOffset, 5);
    expect(selection.endOffset, 9);

    await teardownEditor(tester);
  });

  testWidgets('a claimed tap that turns into a swipe drops the claim and '
      'swipes', (tester) async {
    final e = await _pumpSwipeEditor(
      tester,
      text: document,
      interceptZone: true,
    );

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 1),
    );
    // Past the tap's press timeout, so tap-down has claimed the zone.
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(e.taps, isEmpty);
    expect(e.swipes, [(0, true)]);

    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 0));
    await tester.pump();
    expect(e.taps.length, 1, reason: 'the dropped claim left nothing live');

    await teardownEditor(tester);
  });

  group('a drag that never fired leaves the next swipe free', () {
    testWidgets('after a 20 px drag', (tester) async {
      final e = await _pumpSwipeEditor(tester, text: document);

      await tester.dragFrom(
        zoneCellOf(tester, e.notifier, 0, 3),
        const Offset(20, 0),
      );
      await tester.pump();
      await tester.dragFrom(
        zoneCellOf(tester, e.notifier, 0, 3),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(e.swipes, [(0, true)]);

      await teardownEditor(tester);
    });

    testWidgets('after a long press', (tester) async {
      final e = await _pumpSwipeEditor(tester, text: document);

      final press = await tester.startGesture(
        zoneCellOf(tester, e.notifier, 0, 6),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
      await press.up();
      await tester.pump(const Duration(milliseconds: 400));
      // Clear of the word's handles, whose targets reach into the line.
      await tester.dragFrom(
        zoneCellOf(tester, e.notifier, 0, 13),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(e.swipes, [(0, true)]);

      await teardownEditor(tester);
    });

    testWidgets('after a vertical drag', (tester) async {
      final e = await _pumpSwipeEditor(tester, text: document);

      await tester.dragFrom(
        zoneCellOf(tester, e.notifier, 0, 3),
        const Offset(0, 60),
      );
      await settle(tester);
      expect(e.swipes, isEmpty);
      await tester.dragFrom(
        zoneCellOf(tester, e.notifier, 0, 3),
        const Offset(60, 0),
      );
      await tester.pump();

      expect(e.swipes, [(0, true)]);

      await teardownEditor(tester);
    });
  });

  testWidgets('a second finger is refused while the first owns the swipe', (
    tester,
  ) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    final first = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 1),
    );
    await first.moveBy(const Offset(25, 0));
    await tester.pump();
    final second = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 8),
    );
    await second.moveBy(const Offset(30, 0));
    await second.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(e.swipes, isEmpty, reason: 'the second finger is not the swipe');
    expect(e.downs, [0], reason: 'the second down is never offered');

    await first.moveBy(const Offset(30, 0));
    await tester.pump();
    await second.up();
    await first.up();
    await tester.pump();

    expect(e.swipes, [(0, true)]);

    await teardownEditor(tester);
  });

  testWidgets('a stylus swipe fires', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 0, 3),
      const Offset(60, 0),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();

    expect(e.swipes, [(0, true)]);

    await teardownEditor(tester);
  });

  testWidgets('a diagonal swipe that leaves the vertical slop behind fires', (
    tester,
  ) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 1),
    );
    await gesture.moveBy(const Offset(30, 10));
    await gesture.moveBy(const Offset(30, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(e.swipes, [(0, true)]);

    await teardownEditor(tester);
  });

  testWidgets('a long press then a sideways move extends the selection and '
      'fires nothing', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document);

    final gesture = await tester.startGesture(
      zoneCellOf(tester, e.notifier, 0, 6),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
    expect(e.controller.selection.endOffset, 9);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(e.swipes, isEmpty);
    final selection = e.controller.selection;
    expect(selection.startOffset, 5);
    expect(selection.endIndex, 0);
    expect(selection.endOffset, greaterThan(9));

    await teardownEditor(tester);
  });

  testWidgets('a drag that starts in a shown handle\'s target moves the '
      'caret and fires nothing', (tester) async {
    // No ancestor drag: it would win the touch slop before the handle's
    // pan slop and hide whether the handle got the drag.
    final e = await _pumpSwipeEditor(
      tester,
      text: document,
      ancestorDrag: false,
    );
    await tester.tapAt(zoneCellOf(tester, e.notifier, 0, 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      e.controller.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 4),
    );

    // The collapsed handle's pan recognizer listens on this rect.
    final target = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RawGestureDetector &&
            widget.gestures.containsKey(PanGestureRecognizer),
      ),
    );
    final line = displayedParagraphs(
      e.notifier,
    ).firstWhere((p) => p.index == 0);
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    // Inside the handle's target and still on the accepted line, so both
    // recognizers would see the touch.
    final down = Offset(target.center.dx, target.top + 2);
    expect(down.dy, lessThan(origin.dy + line.top + line.height));
    final asked = e.downs.length;

    final gesture = await tester.startGesture(down);
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(e.swipes, isEmpty);
    expect(
      e.downs.length,
      asked,
      reason: 'refused before the handler is asked',
    );
    final selection = e.controller.selection;
    expect(selection.isCollapsed, isTrue);
    expect(selection.extentIndex, 0);
    expect(selection.extentOffset, greaterThan(4));

    await teardownEditor(tester);
    // The handle's auto-scroll poll ends one tick after the dispose.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('a drag below the last line fires nothing', (tester) async {
    final e = await _pumpSwipeEditor(tester, text: document, acceptLine: 2);
    final last = displayedParagraphs(
      e.notifier,
    ).firstWhere((p) => p.index == 2);
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    final below = origin + Offset(30, last.top + last.height + 60);

    await tester.dragFrom(below, const Offset(60, 0));
    await tester.pump();

    expect(e.swipes, isEmpty);
    expect(e.downs, isEmpty, reason: 'refused before the handler is asked');

    await tester.dragFrom(
      zoneCellOf(tester, e.notifier, 2, 0),
      const Offset(60, 0),
    );
    await tester.pump();
    expect(e.swipes, [(2, true)], reason: 'the line itself still swipes');

    await teardownEditor(tester);
  });
}

typedef _SwipeEditor = ({
  CodeLineEditingController controller,
  FocusNode focusNode,
  CodeScrollController scroll,
  CodeIndicatorValueNotifier notifier,
  List<(int, bool)> swipes,
  List<int> downs,
  List<CodeLinePosition> taps,
  ValueNotifier<int> ancestorDragStarts,
  _CountingToolbar toolbar,
});

/// A bare [CodeEditor] whose swipe handler accepts line [acceptLine] only,
/// inside an ancestor that counts horizontal drag starts (none with
/// [ancestorDrag] false). [interceptZone]
/// adds the tap fixture's interceptor (line 0, offsets 0-2).
Future<_SwipeEditor> _pumpSwipeEditor(
  WidgetTester tester, {
  required String text,
  bool readOnly = false,
  bool interceptZone = false,
  double height = 400,
  int acceptLine = 0,
  bool ancestorDrag = true,
}) async {
  final controller = CodeLineEditingController.fromText(text);
  final focusNode = FocusNode();
  final scroll = CodeScrollController();
  final ancestorDragStarts = ValueNotifier<int>(0);
  final swipes = <(int, bool)>[];
  final downs = <int>[];
  final taps = <CodeLinePosition>[];
  final toolbar = _CountingToolbar();
  late CodeIndicatorValueNotifier notifier;
  addTearDown(() {
    focusNode.dispose();
    scroll.dispose();
    controller.dispose();
    ancestorDragStarts.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: height,
            child: GestureDetector(
              onHorizontalDragStart: ancestorDrag
                  ? (_) => ancestorDragStarts.value++
                  : null,
              child: CodeEditor(
                controller: controller,
                focusNode: focusNode,
                scrollController: scroll,
                toolbarController: toolbar,
                autofocus: false,
                readOnly: readOnly,
                padding: EdgeInsets.zero,
                style: const CodeEditorStyle(fontSize: kTestFontSize),
                tapInterceptor: interceptZone
                    ? CodeEditorTapInterceptor(
                        shouldIntercept: (pos) =>
                            pos.index == 0 && pos.offset < 3,
                        onTap: taps.add,
                      )
                    : null,
                lineSwipeHandler: CodeEditorLineSwipeHandler(
                  shouldHandle: (down) {
                    downs.add(down.index);
                    return down.index == acceptLine;
                  },
                  onSwipe: (lineIndex, {required toRight}) =>
                      swipes.add((lineIndex, toRight)),
                ),
                indicatorBuilder: (context, editing, chunk, valueNotifier) {
                  notifier = valueNotifier;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (
    controller: controller,
    focusNode: focusNode,
    scroll: scroll,
    notifier: notifier,
    swipes: swipes,
    downs: downs,
    taps: taps,
    ancestorDragStarts: ancestorDragStarts,
    toolbar: toolbar,
  );
}

/// Counts how often the editor asks for its selection toolbar.
class _CountingToolbar implements SelectionToolbarController {
  int shows = 0;

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
    VoidCallback? onRefresh,
    VoidCallback? onDismiss,
  }) {
    shows++;
  }

  @override
  void hide(BuildContext context) {}
}
