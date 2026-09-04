import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The mobile gesture path's [CodeEditorTapInterceptor] contract: a claimed
/// tap fires the callback once, leaves the selection untouched, never
/// focuses the editor, and a held-down claim that turns into a long press
/// is cancelled rather than firing. Widget tests run with `kIsAndroid` true,
/// so `_CodeSelectionGestureDetector` builds its `GestureDetector` branch
/// (onTapDown/onTapUp/onLongPress*), which is what every case below
/// exercises.
///
/// The widget-test font advances every glyph by the font size, so a tap's
/// column position is exact, but the vertical position of each line is read
/// back from the editor's own [CodeIndicatorValueNotifier] rather than
/// assumed, since no explicit `fontHeight` is set here.
void main() {
  const fontSize = 14.0;
  const document = 'abcdefghij\nklmnopqrst\nuvwxyz';

  Offset positionOf(
    WidgetTester tester,
    CodeIndicatorValueNotifier notifier,
    int line,
    int column,
  ) {
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    final paragraphs =
        notifier.value?.paragraphs ?? const <CodeLineRenderParagraph>[];
    final paragraph = paragraphs.firstWhere((p) => p.index == line);
    return origin +
        Offset(
          column * fontSize + 2,
          paragraph.top + paragraph.height / 2,
        );
  }

  Future<
    ({
      CodeLineEditingController controller,
      FocusNode focusNode,
      CodeIndicatorValueNotifier notifier,
      List<CodeLinePosition> taps,
    })
  >
  pumpEditor(WidgetTester tester, {required String text}) async {
    final controller = CodeLineEditingController.fromText(text);
    final focusNode = FocusNode();
    final taps = <CodeLinePosition>[];
    late CodeIndicatorValueNotifier notifier;
    addTearDown(() {
      focusNode.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            focusNode: focusNode,
            autofocus: false,
            padding: EdgeInsets.zero,
            style: const CodeEditorStyle(fontSize: fontSize),
            tapInterceptor: CodeEditorTapInterceptor(
              shouldIntercept: (pos) => pos.index == 0 && pos.offset < 3,
              onTap: taps.add,
            ),
            indicatorBuilder: (context, editing, chunk, valueNotifier) {
              notifier = valueNotifier;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (
      controller: controller,
      focusNode: focusNode,
      notifier: notifier,
      taps: taps,
    );
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  void expectSameSelection(CodeLineSelection a, CodeLineSelection b) {
    expect(a.baseIndex, b.baseIndex);
    expect(a.baseOffset, b.baseOffset);
    expect(a.extentIndex, b.extentIndex);
    expect(a.extentOffset, b.extentOffset);
  }

  testWidgets('a claimed tap fires once and leaves the selection identical',
      (tester) async {
    final e = await pumpEditor(tester, text: document);
    final before = e.controller.selection;

    await tester.tapAt(positionOf(tester, e.notifier, 0, 1));
    await tester.pump();

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));
    expectSameSelection(e.controller.selection, before);

    await teardownEditor(tester);
  });

  testWidgets('two consecutive claimed taps both fire', (tester) async {
    final e = await pumpEditor(tester, text: document);

    await tester.tapAt(positionOf(tester, e.notifier, 0, 1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(positionOf(tester, e.notifier, 0, 1));
    await tester.pump();

    expect(e.taps.length, 2);

    await teardownEditor(tester);
  });

  testWidgets('a claimed tap never focuses the editor', (tester) async {
    final e = await pumpEditor(tester, text: document);
    expect(e.focusNode.hasFocus, isFalse);

    await tester.tapAt(positionOf(tester, e.notifier, 0, 1));
    await tester.pump();
    expect(e.focusNode.hasFocus, isFalse);
    await tester.pump();
    expect(e.focusNode.hasFocus, isFalse);

    await tester.tapAt(positionOf(tester, e.notifier, 2, 9));
    await tester.pump();
    expect(e.focusNode.hasFocus, isTrue);

    await teardownEditor(tester);
  });

  testWidgets('a long press on a zone cancels the claim', (tester) async {
    final e = await pumpEditor(tester, text: document);

    final gesture = await tester.startGesture(
      positionOf(tester, e.notifier, 0, 1),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    expect(e.taps, isEmpty);

    await teardownEditor(tester);
  });

  testWidgets('a non-zone tap is not intercepted', (tester) async {
    final e = await pumpEditor(tester, text: document);

    await tester.tapAt(positionOf(tester, e.notifier, 1, 9));
    await tester.pump();

    expect(e.taps, isEmpty);
    expect(e.controller.selection.baseIndex, 1);
    expect(e.controller.selection.baseOffset, 9);

    await teardownEditor(tester);
  });
}
