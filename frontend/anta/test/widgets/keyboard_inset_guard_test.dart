import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/keyboard_inset_guard.dart';

/// The guard is the app-wide answer to a keyboard inset that outlives its
/// keyboard: Android's embedding can leave `viewInsets.bottom` at the
/// keyboard's height after the keyboard has gone, and every surface that pads
/// by it — the folder page's create bar was the one reported — then floats
/// above an empty strip until the app is restarted.
///
/// What is pinned here is the wiring: that the corrected value is what the
/// routes below read, that a real keyboard and a real dismissal pass through
/// untouched, and that the tree keeps its shape. The decision itself is
/// `KeyboardInsetTrust`'s and has its own table.
void main() {
  const keyboard = 300.0;
  const navBar = 48.0;
  const surface = Size(400, 800);
  const window = KeyboardInsetGuard.settleWindow;

  /// A phone with a three-button navigation bar.
  ///
  /// `padding` is what the engine derives — `viewPadding - viewInsets`,
  /// floored at zero — so a keyboard inset, real or stale, swallows the
  /// navigation-bar inset exactly as it does on a device.
  void setInset(WidgetTester tester, double inset) {
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = FakeViewPadding(
      bottom: inset >= navBar ? 0 : navBar - inset,
    );
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
  }

  Future<({FocusNode field, FocusNode plain})> pumpGuard(
    WidgetTester tester, {
    VoidCallback? onSettled,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    setInset(tester, 0);

    final field = FocusNode(debugLabel: 'field');
    final plain = FocusNode(debugLabel: 'plain');
    addTearDown(field.dispose);
    addTearDown(plain.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            KeyboardInsetGuard(onSettled: onSettled, child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: field),
              Focus(focusNode: plain, child: const SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
    return (field: field, plain: plain);
  }

  /// What a route reads, as opposed to what the platform reported.
  MediaQueryData below(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byType(Scaffold)));

  MediaQueryData above(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byType(KeyboardInsetGuard)));

  /// A focus change is applied in a microtask, which `pump` only reaches
  /// after the frame it runs — so the rebuild the change asks for needs a
  /// frame of its own. On a device the next vsync is that frame.
  Future<void> focus(WidgetTester tester, FocusNode node) async {
    node.requestFocus();
    await tester.pump();
    await tester.pump();
  }

  Future<void> unfocus(WidgetTester tester, FocusNode node) async {
    node.unfocus();
    await tester.pump();
    await tester.pump();
  }

  /// A field focused and the keyboard fully up under it.
  Future<void> raiseKeyboard(WidgetTester tester, FocusNode field) async {
    await focus(tester, field);
    setInset(tester, keyboard);
    await tester.pump();
  }

  group('a real keyboard', () {
    testWidgets('reaches the routes untouched while a field holds the focus', (
      tester,
    ) async {
      final nodes = await pumpGuard(tester);
      await focus(tester, nodes.field);

      for (final inset in [40.0, 180.0, keyboard]) {
        setInset(tester, inset);
        await tester.pump(const Duration(milliseconds: 16));
        expect(below(tester).viewInsets.bottom, inset);
      }
      expect(below(tester).padding.bottom, 0);
      expect(
        identical(below(tester), above(tester)),
        isTrue,
        reason:
            'while the platform value is believed the data is handed on as '
            'it is, not rebuilt',
      );

      await tester.pump(window * 3);
      expect(
        below(tester).viewInsets.bottom,
        keyboard,
        reason: 'a keyboard that is simply up is never timed out',
      );
    });

    testWidgets('is followed down frame by frame when focus is dropped', (
      tester,
    ) async {
      final nodes = await pumpGuard(tester);
      await raiseKeyboard(tester, nodes.field);

      await unfocus(tester, nodes.field);
      expect(
        below(tester).viewInsets.bottom,
        keyboard,
        reason: 'the IME has not started leaving yet; nothing may jump',
      );

      for (final inset in [240.0, 150.0, 60.0, 0.0]) {
        setInset(tester, inset);
        await tester.pump(const Duration(milliseconds: 16));
        expect(below(tester).viewInsets.bottom, inset);
      }
      expect(below(tester).padding.bottom, navBar);
    });

    testWidgets('survives a dismissal whose frames are slow but keep coming', (
      tester,
    ) async {
      final nodes = await pumpGuard(tester);
      await raiseKeyboard(tester, nodes.field);
      await unfocus(tester, nodes.field);

      // Each frame arrives just inside the window: the clock restarts on
      // every one, so the inset is never mistaken for one at rest.
      final step = window - const Duration(milliseconds: 20);
      for (final inset in [250.0, 200.0, 150.0, 100.0]) {
        setInset(tester, inset);
        await tester.pump();
        await tester.pump(step);
        expect(below(tester).viewInsets.bottom, inset);
      }
    });

    testWidgets('is believed again the moment a field takes focus', (
      tester,
    ) async {
      final nodes = await pumpGuard(tester);
      setInset(tester, keyboard);
      await tester.pump();
      expect(below(tester).viewInsets.bottom, 0);

      await focus(tester, nodes.field);
      expect(
        below(tester).viewInsets.bottom,
        keyboard,
        reason:
            'refusing the inset under a focused field would hide the field '
            'behind its own keyboard',
      );
    });

    testWidgets('is believed under any focused node, text field or not', (
      tester,
    ) async {
      final nodes = await pumpGuard(tester);
      await focus(tester, nodes.plain);
      setInset(tester, keyboard);
      await tester.pump();
      await tester.pump(window * 2);

      expect(
        below(tester).viewInsets.bottom,
        keyboard,
        reason:
            'the guard cannot tell an input from a button by its focus node, '
            'and guessing wrong costs more than believing',
      );
    });
  });

  group('a stale inset', () {
    testWidgets('never reaches the routes when it appears with nothing '
        'focused, and the navigation-bar inset it had eaten is put back', (
      tester,
    ) async {
      await pumpGuard(tester);
      setInset(tester, keyboard);
      await tester.pump();

      expect(above(tester).viewInsets.bottom, keyboard);
      expect(above(tester).padding.bottom, 0);
      expect(below(tester).viewInsets.bottom, 0);
      expect(below(tester).padding.bottom, navBar);
      expect(below(tester).viewPadding.bottom, navBar);
    });

    testWidgets('left behind by a keyboard that never animated away is '
        'dropped once it has stood still for the settle window', (
      tester,
    ) async {
      final nodes = await pumpGuard(tester);
      await raiseKeyboard(tester, nodes.field);
      await unfocus(tester, nodes.field);

      await tester.pump(window - const Duration(milliseconds: 1));
      expect(below(tester).viewInsets.bottom, keyboard);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(below(tester).viewInsets.bottom, 0);
      expect(below(tester).padding.bottom, navBar);
    });

    testWidgets('is not kept alive by an unrelated MediaQuery change', (
      tester,
    ) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final nodes = await pumpGuard(tester);
      await raiseKeyboard(tester, nodes.field);
      await unfocus(tester, nodes.field);

      await tester.pump(window ~/ 2);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await tester.pump();
      expect(below(tester).viewInsets.bottom, keyboard);

      await tester.pump(window ~/ 2);
      await tester.pump();
      expect(
        below(tester).viewInsets.bottom,
        0,
        reason:
            'the settle clock restarts only when the inset, the focus or the '
            'lifecycle moves',
      );
    });

    testWidgets('is dropped at once when the app stops being resumed', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final nodes = await pumpGuard(tester);
      await raiseKeyboard(tester, nodes.field);
      await unfocus(tester, nodes.field);
      expect(below(tester).viewInsets.bottom, keyboard);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(below(tester).viewInsets.bottom, 0);
    });

    testWidgets('does not come back with the resume that carries it — the '
        'reported bug', (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final nodes = await pumpGuard(tester);
      await raiseKeyboard(tester, nodes.field);

      // The app is sent to the background with the keyboard up, and
      // `main.dart` drops focus as it is paused.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      nodes.field.unfocus();
      await tester.pump();

      // It comes back with the keyboard gone and the inset still reported.
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(above(tester).viewInsets.bottom, keyboard);
      expect(below(tester).viewInsets.bottom, 0);
      expect(below(tester).padding.bottom, navBar);

      await tester.pump(window * 2);
      await tester.pump();
      expect(below(tester).viewInsets.bottom, 0);
    });

    testWidgets('is corrected without remounting the navigator', (
      tester,
    ) async {
      await pumpGuard(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      setInset(tester, keyboard);
      await tester.pump();
      expect(below(tester).viewInsets.bottom, 0);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
        reason: 'a remount here would drop every route the user has open',
      );

      setInset(tester, 0);
      await tester.pump();
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)),
        same(navigator),
      );
    });
  });

  group('onSettled', () {
    testWidgets('fires once for each inset that comes to rest, focused or '
        'not, and never while the inset is moving or zero', (tester) async {
      var settled = 0;
      final nodes = await pumpGuard(tester, onSettled: () => settled++);

      await tester.pump(window * 2);
      expect(settled, 0, reason: 'no inset, nothing to resync');

      await focus(tester, nodes.field);
      for (final inset in [60.0, 160.0, 260.0, keyboard]) {
        setInset(tester, inset);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(settled, 0, reason: 'the keyboard is still arriving');

      await tester.pump(window);
      expect(settled, 1);
      await tester.pump(window * 3);
      expect(settled, 1, reason: 'one resync per rest, not a poll');

      // The keyboard grows a suggestion strip: a new inset, a new rest.
      setInset(tester, keyboard + 40);
      await tester.pump();
      await tester.pump(window);
      expect(settled, 2);

      // Focus is dropped and the keyboard never animates away.
      await unfocus(tester, nodes.field);
      await tester.pump(window);
      expect(settled, 3);
      expect(below(tester).viewInsets.bottom, 0);

      // The resync lands: the platform value is right again.
      setInset(tester, 0);
      await tester.pump();
      await tester.pump(window * 2);
      expect(settled, 3);
    });

    testWidgets('is repeated a window apart for an inset that stays held '
        'back, and gives up at the limit', (tester) async {
      var settled = 0;
      await pumpGuard(tester, onSettled: () => settled++);

      // Nothing focused, and the platform keeps reporting a keyboard: the
      // first answer was lost, or there is nobody to give one.
      setInset(tester, keyboard);
      await tester.pump();
      for (
        var asked = 1;
        asked <= KeyboardInsetGuard.repeatLimit + 1;
        asked++
      ) {
        await tester.pump(window);
        expect(settled, asked);
        expect(below(tester).viewInsets.bottom, 0);
      }

      await tester.pump(window * 4);
      expect(
        settled,
        KeyboardInsetGuard.repeatLimit + 1,
        reason: 'a platform that cannot answer is not polled forever',
      );
    });

    testWidgets('starts a fresh round when the held-back inset moves', (
      tester,
    ) async {
      var settled = 0;
      await pumpGuard(tester, onSettled: () => settled++);
      setInset(tester, keyboard);
      await tester.pump();
      await tester.pump(window * (KeyboardInsetGuard.repeatLimit + 3));
      expect(settled, KeyboardInsetGuard.repeatLimit + 1);

      setInset(tester, keyboard - 20);
      await tester.pump();
      await tester.pump(window);
      expect(settled, KeyboardInsetGuard.repeatLimit + 2);
    });
  });
}
