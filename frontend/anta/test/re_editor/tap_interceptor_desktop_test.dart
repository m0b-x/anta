import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// The desktop gesture path's [CodeEditorTapInterceptor] contract —
/// `_CodeSelectionGestureDetector`'s `Listener` (onPointerDown/Move/Up/
/// Cancel) wrapping the desktop `GestureDetector` in
/// `packages/re_editor/lib/src/_code_selection.dart`. Unlike the mobile
/// `GestureDetector.onTapDown/onTapUp` path (see the plain
/// `tap_interceptor_test.dart` twin, which shares this file's editor and
/// cell geometry through `support/editor_test_support.dart`), the desktop
/// claim is tied to a pointer id and device and tracks raw pointer
/// movement against the slop itself: a mouse move past the slop on either
/// axis releases the claim into a real drag selection anchored at the
/// original down position, while a move that stays inside it on both axes
/// keeps the claim alive for the eventual pointer-up.
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
/// **Device trap.** Two `TestGesture`s of kind mouse share device 1, and
/// one mouse cannot hold two primary presses, so the interceptor drops a
/// same-device claim on the next press. A genuinely concurrent second
/// press therefore has to come from another device — [pressSecondMouse]
/// sends the down event by hand for that.
///
/// **Timer trap.** The claim-release path schedules its eventual focus
/// request via `Future(...)`, i.e. a zero-duration `Timer`, not a
/// microtask. `AutomatedTestWidgetsFlutterBinding.pump()` with no argument
/// only flushes microtasks; it never elapses the fake clock, so a bare
/// `pump()` never runs that Timer. Observing the resulting focus needs
/// `pump(Duration.zero)` instead.
void main() {
  const document = 'abcdefghij\nklmnopqrst\nuvwxyz';

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(kIsAndroid, isFalse);
    expect(kIsIOS, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<TestGesture> pressSecondMouse(
    WidgetTester tester,
    Offset at, {
    int pointer = 91,
    int device = 2,
  }) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: pointer,
    );
    await gesture.downWithCustomEvent(
      at,
      PointerDownEvent(
        pointer: pointer,
        kind: PointerDeviceKind.mouse,
        device: device,
        position: at,
      ),
    );
    return gesture;
  }

  testWidgets('a claimed press cancelled by the pointer never fires', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);

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

  testWidgets('a second press from another device while a claim is live is '
      'refused', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);
    final otherCell = zoneCellOf(tester, e.notifier, 2, 3);

    final g1 = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    final g2 = await pressSecondMouse(tester, otherCell);
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

  testWidgets('a cancel of a non-claiming pointer leaves the claim live', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);
    final otherCell = zoneCellOf(tester, e.notifier, 2, 3);

    final g1 = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    final g2 = await pressSecondMouse(tester, otherCell);
    await tester.pump();
    await g2.cancel();
    await tester.pump();

    expect(e.taps, isEmpty);

    await g1.up();
    await tester.pump();

    expect(
      e.taps.length,
      1,
      reason:
          "the refused pointer's cancel must not clear another "
          "pointer's claim",
    );
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));

    await teardownEditor(tester);
  });

  testWidgets('a new press from the claiming mouse drops a stranded claim', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);

    await tester.startGesture(zoneCell, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(e.taps, isEmpty);

    final second = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await second.up();
    await tester.pump();

    expect(
      e.taps.length,
      1,
      reason:
          'the stranded claim from the same mouse must be dropped so the '
          'new press can claim and fire',
    );
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));

    await teardownEditor(tester);
  });

  testWidgets('moving past the slop releases the claim and drags a '
      'selection', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);
    final dragTarget = zoneCellOf(tester, e.notifier, 1, 6);
    expect(e.focusNode.hasFocus, isFalse);

    final gesture = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    await gesture.moveTo(
      zoneCell + const Offset(kPrecisePointerHitSlop * 4, 0),
    );
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
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);

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

  testWidgets('a diagonal move inside the per-axis slop still fires the zone', (
    tester,
  ) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);
    final before = e.controller.selection;
    const jitter = Offset(
      kPrecisePointerHitSlop * 0.75,
      kPrecisePointerHitSlop * 0.75,
    );
    expect(jitter.distance, greaterThan(kPrecisePointerHitSlop));

    final gesture = await tester.startGesture(
      zoneCell,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(jitter);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      e.taps.length,
      1,
      reason:
          'both axes stayed inside the slop the drag recognizers use, so '
          'no drag can start: the claim must still fire',
    );
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));
    expectSameSelection(e.controller.selection, before);

    await tester.pump(Duration.zero);
    expect(e.focusNode.hasFocus, isFalse);

    await teardownEditor(tester);
  });

  testWidgets('a plain click on a zone fires and leaves the selection '
      'untouched', (tester) async {
    final e = await pumpZoneEditor(tester, text: document);
    final zoneCell = zoneCellOf(tester, e.notifier, 0, 1);
    final before = e.controller.selection;

    await tester.tapAt(zoneCell, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump(Duration.zero);

    expect(e.taps.length, 1);
    expect(e.taps.single.index, 0);
    expect(e.taps.single.offset, lessThan(3));
    expectSameSelection(e.controller.selection, before);
    expect(e.focusNode.hasFocus, isFalse);

    await teardownEditor(tester);
  });
}
