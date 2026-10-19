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

  Future<
    ({
      CodeLineEditingController controller,
      List<TextSelectionToolbarAnchors> anchors,
    })
  >
  pumpEditor(WidgetTester tester) async {
    final controller = CodeLineEditingController.fromText(document);
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 300,
              child: CodeEditor(
                controller: controller,
                focusNode: focusNode,
                autofocus: false,
                padding: EdgeInsets.zero,
                style: const CodeEditorStyle(fontSize: kTestFontSize),
                toolbarController: _RecordingToolbar(toolbar, anchors),
              ),
            ),
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
  Future<void> longPressWord(WidgetTester tester, int line) async {
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    final top = tester.getTopLeft(find.byType(CodeEditor));
    final x = ('line $line '.length + 1) * kTestFontSize;
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
