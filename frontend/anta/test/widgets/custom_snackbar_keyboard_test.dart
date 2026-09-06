import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/utils/custom_snackbar.dart';

/// A floating [SnackBar] is positioned by the [Scaffold], and the Scaffold only
/// subtracts the keyboard inset when it was asked to resize for it
/// (`material/scaffold.dart:3220-3222`). The note editor sets
/// `resizeToAvoidBottomInset: false` — it pads its own body so the markdown
/// toolbar rides the keyboard — so every bar it shows used to land at the
/// bottom of the screen, underneath the IME: a `[[wiki link]]` that resolved to
/// nothing gave no visible feedback at all while typing.
///
/// These tests pin the lift and, just as importantly, pin that it is *not*
/// applied twice. A Scaffold that does resize has already moved the bar above
/// the keyboard, and adding the inset a second time would float it a keyboard's
/// height into the middle of the screen.
void main() {
  const keyboard = 300.0;
  const navBar = 48.0;
  const surface = Size(400, 800);
  const message = 'No note titled "Nope"';

  final screenHeight = surface.height;

  /// A phone with a three-button navigation bar, keyboard optionally up.
  ///
  /// When the IME is up it covers the navigation bar, so `padding` collapses to
  /// zero while `viewPadding` keeps the 48px — the same split the real platform
  /// reports, and the split the Scaffold's two inset terms read differently.
  void sizeSurface(WidgetTester tester, {double keyboardInset = 0}) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = keyboardInset > 0
        ? FakeViewPadding.zero
        : const FakeViewPadding(bottom: navBar);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required bool resizeToAvoidBottomInset,
    required void Function(BuildContext context) onShow,
    bool fromPageContext = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Host(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          onShow: onShow,
          fromPageContext: fromPageContext,
        ),
      ),
    );
  }

  /// Taps the button and lets the 250ms entrance settle.
  Future<void> showBar(WidgetTester tester) async {
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Tears the app down so the messenger's dismissal timer is cancelled with
  /// its state rather than left pending past the test.
  Future<void> disposeHost(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// The rect of the bar the user actually sees.
  ///
  /// [SnackBar]'s own box spans the margin too — the margin is a [Padding]
  /// *inside* it (`material/snack_bar.dart:823`) — so its bottom edge is the
  /// anchor the Scaffold chose, not the pill. The first [Material] below it is
  /// the pill itself.
  Rect barRect(WidgetTester tester) => tester.getRect(
    find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first,
  );

  void show(BuildContext context) => CustomSnackbar.show(context, message);

  testWidgets(
    'lifts the bar above the keyboard when the Scaffold does not resize',
    (tester) async {
      sizeSurface(tester, keyboardInset: keyboard);
      await pumpHost(tester, resizeToAvoidBottomInset: false, onShow: show);
      await showBar(tester);

      expect(find.text(message), findsOneWidget);
      expect(
        barRect(tester).bottom,
        lessThanOrEqualTo(screenHeight - keyboard),
        reason: 'the whole bar must clear the IME',
      );

      await disposeHost(tester);
    },
  );

  testWidgets('lifts a bar shown from the page State context', (tester) async {
    sizeSurface(tester, keyboardInset: keyboard);
    await pumpHost(
      tester,
      resizeToAvoidBottomInset: false,
      onShow: show,
      fromPageContext: true,
    );
    await showBar(tester);

    expect(
      barRect(tester).bottom,
      lessThanOrEqualTo(screenHeight - keyboard),
      reason:
          'pages call in from a context above their own Scaffold, which is the '
          'shape the editor uses and the only one the bug appears in',
    );

    await disposeHost(tester);
  });

  testWidgets('does not lift twice when the Scaffold resizes', (tester) async {
    sizeSurface(tester, keyboardInset: keyboard);
    await pumpHost(tester, resizeToAvoidBottomInset: true, onShow: show);
    await showBar(tester);

    final bottom = barRect(tester).bottom;
    expect(bottom, lessThanOrEqualTo(screenHeight - keyboard));
    expect(
      bottom,
      greaterThan(screenHeight - keyboard - AppSpacing.lg - 1),
      reason:
          'the Scaffold already anchored the bar to the top of the IME, so the '
          'only gap left is the margin — a second lift would put it a '
          'keyboard-height higher',
    );

    await disposeHost(tester);
  });

  testWidgets('leaves the no-keyboard layout untouched', (tester) async {
    sizeSurface(tester);
    await pumpHost(tester, resizeToAvoidBottomInset: true, onShow: show);
    await showBar(tester);
    final resizing = barRect(tester);
    await disposeHost(tester);

    sizeSurface(tester);
    await pumpHost(tester, resizeToAvoidBottomInset: false, onShow: show);
    await showBar(tester);
    final notResizing = barRect(tester);

    expect(
      notResizing,
      resizing,
      reason:
          'with no IME both Scaffolds anchor at size.height - viewPadding.bottom '
          '(scaffold.dart:1238-1241) and the lift is zero, so the branch the fix '
          'adds must be invisible',
    );
    expect(
      notResizing.bottom,
      closeTo(screenHeight - navBar - AppSpacing.lg, 0.01),
      reason: 'the Scaffold clears the navigation bar; the margin is the rest',
    );

    await disposeHost(tester);
  });

  testWidgets('lifts an action bar the same way', (tester) async {
    sizeSurface(tester, keyboardInset: keyboard);
    await pumpHost(
      tester,
      resizeToAvoidBottomInset: false,
      onShow: (context) => CustomSnackbar.showWithAction(
        context,
        message: message,
        actionLabel: 'Open',
        onAction: () {},
      ),
    );
    await showBar(tester);

    expect(find.text('OPEN'), findsOneWidget);
    expect(barRect(tester).bottom, lessThanOrEqualTo(screenHeight - keyboard));

    await disposeHost(tester);
  });
}

/// A page-shaped host: the [Scaffold] is built by a [State], so
/// [_HostState.context] sits *above* it while the body's `Builder` context sits
/// below. [fromPageContext] picks which one the snackbar is shown from.
class _Host extends StatefulWidget {
  const _Host({
    required this.resizeToAvoidBottomInset,
    required this.onShow,
    this.fromPageContext = false,
  });

  final bool resizeToAvoidBottomInset;
  final void Function(BuildContext context) onShow;
  final bool fromPageContext;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      body: Builder(
        builder: (inner) => Center(
          child: ElevatedButton(
            onPressed: () =>
                widget.onShow(widget.fromPageContext ? context : inner),
            child: const Text('show'),
          ),
        ),
      ),
    );
  }
}
