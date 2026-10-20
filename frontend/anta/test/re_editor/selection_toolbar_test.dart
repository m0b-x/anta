import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The mobile selection toolbar (widget tests run on the Android path)
/// across the two things that used to strand it: a scroll hid it for
/// good, and "Select all" re-showed it at the anchors of the selection it
/// had just replaced.
void main() {
  final document = List.generate(80, (i) => 'line $i word').join('\n');
  const toolbarKey = Key('toolbar');
  const barKey = Key('bar');

  /// [fill] gives the editor the page above a 48 dp docked bar, so the
  /// keyboard inset shrinks it; [realToolbar] lays the toolbar out from its
  /// anchors the way Material does instead of parking it in a corner.
  Future<
    ({
      CodeLineEditingController controller,
      List<TextSelectionToolbarAnchors> anchors,
    })
  >
  pumpEditor(
    WidgetTester tester, {
    bool fill = false,
    bool realToolbar = false,
    String? text,
  }) async {
    final controller = CodeLineEditingController.fromText(text ?? document);
    final focusNode = FocusNode();
    final anchors = <TextSelectionToolbarAnchors>[];
    addTearDown(() {
      focusNode.dispose();
      controller.dispose();
    });
    final toolbar = MobileSelectionToolbarController(
      builder:
          ({
            required BuildContext context,
            required TextSelectionToolbarAnchors anchors,
            required CodeLineEditingController controller,
            required VoidCallback onDismiss,
            required VoidCallback onRefresh,
          }) {
            if (realToolbar) {
              return TextSelectionToolbar(
                anchorAbove: anchors.primaryAnchor,
                anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
                toolbarBuilder: (context, child) =>
                    Material(key: toolbarKey, child: child),
                children: [
                  TextButton(onPressed: onDismiss, child: const Text('copy')),
                ],
              );
            }
            // Small and in a corner, like the real toolbar, so it never
            // takes the drag that scrolls the editor.
            return Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 160,
                height: 40,
                child: Material(
                  key: toolbarKey,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          controller.selectAll();
                          onRefresh();
                        },
                        child: const Text('all'),
                      ),
                      TextButton(
                        onPressed: onDismiss,
                        child: const Text('copy'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
    );
    final editor = CodeEditor(
      controller: controller,
      focusNode: focusNode,
      autofocus: false,
      padding: EdgeInsets.zero,
      style: const CodeEditorStyle(fontSize: kTestFontSize),
      toolbarController: _RecordingToolbar(toolbar, anchors),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: fill
              ? Column(
                  children: [
                    Expanded(child: editor),
                    const SizedBox(key: barKey, height: 48),
                  ],
                )
              : Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(height: 300, child: editor),
                ),
        ),
      ),
    );
    await settle(tester);
    focusNode.requestFocus();
    await settle(tester);
    return (controller: controller, anchors: anchors);
  }

  /// Long-presses the word `word` on [line]: the press selects it and its
  /// release shows the toolbar.
  Future<void> longPressWord(
    WidgetTester tester,
    int line, {
    int column = 1,
  }) async {
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    final top = tester.getTopLeft(find.byType(CodeEditor));
    final x = ('line $line '.length + column) * kTestFontSize;
    final y = render.lineHeight * (line + 0.5);
    final gesture = await tester.startGesture(top + Offset(x, y));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);
  }

  testWidgets('a scroll hides the toolbar and its end brings it back over '
      'the selection', (tester) async {
    final e = await pumpEditor(tester);
    await longPressWord(tester, 4);
    expect(e.controller.selectedText, 'word');
    expect(find.byKey(toolbarKey), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CodeEditor)),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    expect(find.byKey(toolbarKey), findsNothing);

    await gesture.up();
    await settle(tester, 40);
    expect(e.controller.selectedText, 'word');
    expect(find.byKey(toolbarKey), findsOneWidget);

    await teardownEditor(tester);
  });

  testWidgets('a toolbar the user dismissed (Copy) stays down after a '
      'scroll', (tester) async {
    final e = await pumpEditor(tester);
    await longPressWord(tester, 4);
    expect(find.byKey(toolbarKey), findsOneWidget);

    await tester.tap(find.text('copy'));
    await settle(tester);
    expect(find.byKey(toolbarKey), findsNothing);
    expect(e.controller.selectedText, 'word');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CodeEditor)),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.up();
    await settle(tester, 40);

    expect(e.controller.selectedText, 'word');
    expect(find.byKey(toolbarKey), findsNothing);

    await teardownEditor(tester);
  });

  testWidgets('a scroll over a caret leaves its toolbar down', (tester) async {
    final e = await pumpEditor(tester);
    await longPressWord(tester, 4);
    e.controller.selection = const CodeLineSelection.collapsed(
      index: 4,
      offset: 0,
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CodeEditor)),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.up();
    await settle(tester, 40);

    expect(find.byKey(toolbarKey), findsNothing);

    await teardownEditor(tester);
  });

  testWidgets('Select all re-shows the toolbar anchored to the new '
      'selection', (tester) async {
    final e = await pumpEditor(tester);
    await longPressWord(tester, 4);
    final before = e.anchors.last;
    // A word in mid-viewport anchors to its own ends.
    expect(before.secondaryAnchor, isNotNull);

    await tester.tap(find.text('all'));
    await settle(tester);

    expect(e.controller.isAllSelected, isTrue);
    expect(find.byKey(toolbarKey), findsOneWidget);
    final after = e.anchors.last;
    expect(identical(after, before), isFalse);
    // The whole document spans the viewport, so the toolbar anchors to the
    // press instead of to either end.
    expect(after.secondaryAnchor, isNull);

    await teardownEditor(tester);
  });

  // U2.12 — the toolbar goes above the selection's start when it fits,
  // whichever end the press was nearer.
  testWidgets('a press near the end of a word still anchors the toolbar '
      'above its start', (tester) async {
    final e = await pumpEditor(tester);
    await longPressWord(tester, 4, column: 3);
    expect(e.controller.selectedText, 'word');

    final anchors = e.anchors.last;
    final top = tester.getTopLeft(find.byType(CodeEditor));
    expect(anchors.primaryAnchor.dy, greaterThanOrEqualTo(top.dy));
    expect(anchors.secondaryAnchor, isNotNull);
    expect(
      anchors.primaryAnchor.dx,
      lessThan(anchors.secondaryAnchor!.dx),
      reason: 'the primary anchor is the start of the word',
    );

    await teardownEditor(tester);
  });

  testWidgets('a selection on the last visible line keeps the below anchor '
      'a toolbar clear of the field bottom', (tester) async {
    final e = await pumpEditor(tester);
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    final rect = tester.getRect(find.byType(CodeEditor));
    final lastLine = (rect.height / render.lineHeight).floor() - 1;
    await longPressWord(tester, lastLine);
    expect(e.controller.selectedText, 'word');

    final below = e.anchors.last.secondaryAnchor;
    expect(below, isNotNull);
    expect(below!.dy, lessThanOrEqualTo(rect.bottom - 64 + 0.01));

    await teardownEditor(tester);
  });

  testWidgets('a selection on the first line, with no room above, lays the '
      'toolbar out below its end', (tester) async {
    final e = await pumpEditor(tester, realToolbar: true);
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    await longPressWord(tester, 0);
    expect(e.controller.selectedText, 'word');

    final toolbar = tester.getRect(find.byKey(toolbarKey));
    final top = tester.getTopLeft(find.byType(CodeEditor)).dy;
    expect(toolbar.top, greaterThanOrEqualTo(top + render.lineHeight));

    await teardownEditor(tester);
  });

  // The anchors and the "never over the bar" clamp were measured once at
  // show time, so a keyboard rising under a shown toolbar left it over the
  // bar, and one falling left it floating mid-screen.
  testWidgets('a shown toolbar re-anchors as the keyboard rises and falls, '
      'never over the docked bar', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    final e = await pumpEditor(tester, fill: true, realToolbar: true);
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    final rect = tester.getRect(find.byType(CodeEditor));
    final lastLine = (rect.height / render.lineHeight).floor() - 1;
    await longPressWord(tester, lastLine);
    expect(e.controller.selectedText, 'word');
    final shows = e.anchors.length;
    final shownAnchors = e.anchors.last;
    final shownRect = tester.getRect(find.byKey(toolbarKey));
    // The entry's root: a re-inserted entry mounts a new one.
    final wrapper = find.ancestor(
      of: find.byKey(toolbarKey),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_SelectionToolbarWrapper',
      ),
    );
    final shownToolbar = tester.element(wrapper);

    double barTop() => tester.getTopLeft(find.byKey(barKey)).dy;

    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    await settle(tester);
    expect(barTop(), lessThan(rect.bottom));
    expect(e.anchors.length, greaterThan(shows));
    expect(find.byKey(toolbarKey), findsOneWidget);
    expect(
      e.anchors.last.primaryAnchor.dy,
      moreOrLessEquals(barTop()),
      reason: 'the covered start waits at the shrunk field bottom',
    );
    expect(
      tester.getRect(find.byKey(toolbarKey)).bottom,
      lessThanOrEqualTo(barTop() + 0.01),
    );
    expect(
      tester.element(wrapper),
      same(shownToolbar),
      reason: 'a re-anchor rebuilds the shown entry, it never re-inserts it',
    );

    final raised = e.anchors.length;
    tester.view.resetViewInsets();
    await settle(tester);
    expect(barTop(), rect.bottom);
    expect(e.anchors.length, greaterThan(raised));
    expect(find.byKey(toolbarKey), findsOneWidget);
    expect(e.anchors.last.primaryAnchor, shownAnchors.primaryAnchor);
    expect(e.anchors.last.secondaryAnchor, shownAnchors.secondaryAnchor);
    expect(
      tester.getRect(find.byKey(toolbarKey)),
      shownRect,
      reason: 'back over the word, not left at the raised clamp',
    );

    await teardownEditor(tester);
  });

  // The caret's (Paste) toolbar had no clamp: a wrapped paragraph the
  // keyboard cut through left its caret row below the field, and the
  // re-anchor laid the toolbar out over the bar.
  testWidgets('a caret toolbar on a wrapped row the keyboard covers stays '
      'inside the field', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    final wrapped = 'x' * 600;
    final e = await pumpEditor(
      tester,
      fill: true,
      realToolbar: true,
      text: '\n$wrapped\n$wrapped',
    );
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    final top = tester.getTopLeft(find.byType(CodeEditor));
    final gesture = await tester.startGesture(
      top + Offset(kTestFontSize, render.lineHeight * 0.5),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);
    expect(e.controller.selection.isCollapsed, isTrue);
    expect(find.byKey(toolbarKey), findsOneWidget);

    e.controller.selection = CodeLineSelection.collapsed(
      index: 1,
      offset: wrapped.length,
    );
    await settle(tester);
    double barTop() => tester.getTopLeft(find.byKey(barKey)).dy;
    final rowTop = top.dy + render.lineHeight;
    final caretRowBottom =
        rowTop + render.lineHeight * (wrapped.length * kTestFontSize /
                tester.getSize(find.byType(CodeEditor)).width).ceil();
    // Keeps the wrapped paragraph's first row inside the shrunk field and
    // its caret row below it.
    final inset = barTop() - (rowTop + caretRowBottom) / 2;
    tester.view.viewInsets = FakeViewPadding(
      bottom: inset * tester.view.devicePixelRatio,
    );
    await settle(tester);
    expect(barTop(), lessThan(caretRowBottom - render.lineHeight));
    expect(find.byKey(toolbarKey), findsOneWidget);
    expect(e.anchors.last.primaryAnchor.dy, lessThanOrEqualTo(barTop()));
    expect(
      tester.getRect(find.byKey(toolbarKey)).bottom,
      lessThanOrEqualTo(barTop() + 0.01),
    );

    await teardownEditor(tester);
  });
}

/// The real mobile toolbar, recording the anchors each show is given.
class _RecordingToolbar implements SelectionToolbarController {
  _RecordingToolbar(this._inner, this._anchors);

  final SelectionToolbarController _inner;
  final List<TextSelectionToolbarAnchors> _anchors;

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
    _anchors.add(anchors);
    _inner.show(
      context: context,
      controller: controller,
      anchors: anchors,
      renderRect: renderRect,
      layerLink: layerLink,
      visibility: visibility,
      onRefresh: onRefresh,
      onDismiss: onDismiss,
    );
  }

  @override
  void hide(BuildContext context) => _inner.hide(context);
}
