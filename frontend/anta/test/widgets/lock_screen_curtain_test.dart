import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/lock_screen_state.dart';
import 'package:anta/widgets/lock_screen_curtain.dart';

/// The cover `MaterialApp.builder` puts over the navigator.
///
/// What it guards against was seen on a device (2026-10-04): after Stop on a
/// PIN-locked phone the calendar under the alarm page stayed on screen and
/// took touches — a tap on a day listed its events — until a key press let
/// the keyguard back in.
void main() {
  late LockScreenState state;
  late int taps;
  late int builds;

  setUp(() {
    state = LockScreenState();
    taps = 0;
    builds = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            LockScreenCurtain(state: state, child: child!),
        home: Scaffold(
          body: _Counted(
            onInit: () => builds++,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('a private note'),
            ),
          ),
        ),
      ),
    );
  }

  /// What a screen reader would be read, in order — the tree itself rather
  /// than a widget's own configuration, which an excluding ancestor does not
  /// change.
  Iterable<String> spoken(WidgetTester tester) => tester.semantics
      .simulatedAccessibilityTraversal()
      .map((node) => node.label);

  testWidgets('an unlocked phone shows the app and takes its touches', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    await tester.tap(find.text('a private note'));
    expect(taps, 1);
    expect(spoken(tester), contains('a private note'));
    semantics.dispose();
  });

  testWidgets('a locked phone with no alarm page shows nothing of the app', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    state.setLocked(true);
    await tester.pump();

    // Still mounted — the navigator keeps its stack under the cover — but not
    // hittable, and not in the accessibility tree either.
    expect(find.text('a private note'), findsOneWidget);
    await tester.tap(find.text('a private note'), warnIfMissed: false);
    expect(taps, 0);
    expect(spoken(tester), isNot(contains('a private note')));

    // The cover paints over the whole view.
    final cover = find.descendant(
      of: find.byType(LockScreenCurtain),
      matching: find.byType(ColoredBox),
    );
    expect(
      tester.getSize(cover.last),
      tester.getSize(find.byType(LockScreenCurtain)),
    );
    semantics.dispose();
  });

  testWidgets('an alarm page on top lifts the cover while the phone stays '
      'locked', (tester) async {
    await pump(tester);
    state.setLocked(true);
    final page = Object();
    state.alarmSurfaceShown(page);
    await tester.pump();

    await tester.tap(find.text('a private note'));
    expect(taps, 1);

    // The page is gone and the phone is still locked: covered again, at once.
    state.alarmSurfaceHidden(page);
    await tester.pump();
    await tester.tap(find.text('a private note'), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('covering and uncovering never remounts what is underneath', (
    tester,
  ) async {
    // A remount would throw away the navigator and every page's state with
    // it; the user must come back from the lock screen to where they were.
    await pump(tester);
    expect(builds, 1);

    state.setLocked(true);
    await tester.pump();
    state.setLocked(false);
    await tester.pump();

    expect(builds, 1);
    await tester.tap(find.text('a private note'));
    expect(taps, 1);
  });

  testWidgets('a touch on the cover asks the platform again', (tester) async {
    // An unlock nobody reported must not leave the app blank: the first touch
    // re-reads the lock screen, and an unlocked answer lifts the cover.
    var locked = true;
    var asked = 0;
    state.query = () async {
      asked++;
      return locked;
    };
    await pump(tester);
    state.setLocked(true);
    await tester.pump();

    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(asked, 1);
    expect(state.mustCover, isTrue);

    locked = false;
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(asked, 2);
    expect(state.mustCover, isFalse);

    await tester.tap(find.text('a private note'));
    expect(taps, 1);
  });
}

/// Counts how many times its state was created — once per mount.
class _Counted extends StatefulWidget {
  const _Counted({required this.onInit, required this.child});

  final VoidCallback onInit;
  final Widget child;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
