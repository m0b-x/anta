import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The desktop gesture path's [CodeEditorTapInterceptor] contract —
/// `_CodeSelectionGestureDetector`'s `Listener` (onPointerDown/Move/Up/
/// Cancel) wrapping the desktop `GestureDetector` in
/// `packages/re_editor/lib/src/_code_selection.dart`. Unlike the mobile
/// `GestureDetector.onTapDown/onTapUp` path (see the plain
/// `tap_interceptor_test.dart` twin, which this file does not import from —
/// helpers below are copied, not shared), the desktop claim is tied to a
/// pointer id and tracks raw pointer movement against a slop distance
/// itself: a mouse move past [kPrecisePointerHitSlop] from the down offset
/// releases the claim into a real drag selection anchored at the original
/// down position, while a move that stays inside it keeps the claim alive
/// for the eventual pointer-up.
///
/// **Platform trap.** `kIsAndroid` / `kIsIOS` are top-level `final`s in the
/// fork, resolved on first read and then fixed for the whole test process,
/// so `debugDefaultTargetPlatformOverride` has to be set before the first
/// editor is built anywhere in this file. The idiom below is copied
/// verbatim from `modern_editor_wrapper_desktop_indent_test.dart`: force
/// both finals to resolve against a desktop platform inside `setUpAll`,
/// then clear the override immediately — the binding fails a test that
/// leaves a foundation debug variable set across a test body, and nothing
/// here needs it set beyond that first read.
///
/// The widget-test font advances every glyph by the font size, so
/// [positionOf] (copied from the mobile twin) reads each line's pixel
/// geometry back from the editor's own [CodeIndicatorValueNotifier] rather
/// than assuming a fixed line height.
///
/// **Timer trap.** The claim-release path schedules its eventual focus
/// request via `Future(...)`, i.e. a zero-duration `Timer`, not a
/// microtask. `AutomatedTestWidgetsFlutterBinding.pump()` with no argument
/// only flushes microtasks; it never elapses the fake clock, so a bare
/// `pump()` never runs that Timer. Observing the resulting focus needs
/// `pump(Duration.zero)` instead.
void main() {
  const fontSize = 14.0;
  const document = 'abcdefghij\nklmnopqrst\nuvwxyz';

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(kIsAndroid, isFalse);
    expect(kIsIOS, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

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

  testWidgets('a claimed press cancelled by the pointer never fires', (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: document);
    final zoneCell = positionOf(tester, e.notifier, 0, 1);

    final gesture = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(e.taps, isEmpty);

    await tester.tapAt(zoneCell, kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));

    await teardownEditor(tester);
  });

  testWidgets('a second press while a claim is live is refused', (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: document);
    final zoneCell = positionOf(tester, e.notifier, 0, 1);
    final otherCell = positionOf(tester, e.notifier, 2, 3);

    final g1 = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    final g2 = await tester.startGesture(
      otherCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(e.taps, isEmpty);
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 3);

    await g2.up();
    await tester.pump();

    expect(e.taps, isEmpty);

    await g1.up();
    await tester.pump();

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));

    await teardownEditor(tester);
  });

  testWidgets('moving past the slop releases the claim and drags a '
      'selection', (tester) async {
    final e = await pumpEditor(tester, text: document);
    final zoneCell = positionOf(tester, e.notifier, 0, 1);
    final dragTarget = positionOf(tester, e.notifier, 1, 6);
    expect(e.focusNode.hasFocus, isFalse);

    final gesture = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    await gesture.moveTo(zoneCell + const Offset(kPrecisePointerHitSlop * 4, 0));
    await tester.pump();
    await gesture.moveTo(
      zoneCell + const Offset(kPrecisePointerHitSlop * 4 + 20, 0),
    );
    await tester.pump();
    await gesture.moveTo(dragTarget);
    await tester.pump();

    await gesture.up();
    await tester.pump();

    expect(e.taps, isEmpty);
    expect(e.controller.selection.isCollapsed, isFalse);
    expect(e.controller.selection.baseIndex, 0);
    expect(e.controller.selection.baseOffset, 1);
    expect(e.controller.selection.extentIndex, 1);
    expect(e.controller.selection.extentOffset, 6);

    await tester.pump(Duration.zero);
    expect(e.focusNode.hasFocus, isTrue);

    await teardownEditor(tester);
  });

  testWidgets('a move within the slop keeps the claim', (tester) async {
    final e = await pumpEditor(tester, text: document);
    final zoneCell = positionOf(tester, e.notifier, 0, 1);

    final gesture = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(kPrecisePointerHitSlop / 2, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));

    await teardownEditor(tester);
  });

  testWidgets('a plain click on a zone fires and leaves the selection '
      'untouched', (tester) async {
    final e = await pumpEditor(tester, text: document);
    final zoneCell = positionOf(tester, e.notifier, 0, 1);
    final before = e.controller.selection;

    await tester.tapAt(zoneCell, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump();

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));
    expectSameSelection(e.controller.selection, before);
    expect(e.focusNode.hasFocus, isFalse);

    await teardownEditor(tester);
  });
}
