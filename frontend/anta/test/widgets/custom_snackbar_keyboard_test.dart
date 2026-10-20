import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/snackbar_metrics.dart';
import 'package:anta/utils/custom_snackbar.dart';
import 'package:anta/widgets/overlay_snackbar.dart';

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
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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

  /// The rect of the pill the user actually sees, on either road.
  ///
  /// A page that does not resize raises an [OverlaySnackbarBody], whose pill
  /// is its [PhysicalModel]. On the Scaffold road, [SnackBar]'s own box spans
  /// the margin too — the margin is a [Padding] *inside* it
  /// (`material/snack_bar.dart:823`) — so its bottom edge is the anchor the
  /// Scaffold chose, not the pill. The first [Material] below it is the pill
  /// itself.
  Rect barRect(WidgetTester tester) {
    final overlay = find.byType(OverlaySnackbarBody);
    if (overlay.evaluate().isNotEmpty) {
      return tester.getRect(
        find.descendant(of: overlay, matching: find.byType(PhysicalModel)),
      );
    }
    return tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
  }

  void show(BuildContext context) => CustomSnackbar.show(context, message);

  testWidgets(
    'lifts the bar above the keyboard when the Scaffold does not resize',
    (tester) async {
      sizeSurface(tester, keyboardInset: keyboard);
      await pumpHost(tester, resizeToAvoidBottomInset: false, onShow: show);
      await showBar(tester);

      expect(find.text(message), findsOneWidget);
      expect(
        find.byType(OverlaySnackbarBody),
        findsOneWidget,
        reason: 'a page that lays itself out around the IME raises its bars '
            'in the overlay, the road that can follow the keyboard',
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(
        barRect(tester).bottom,
        lessThanOrEqualTo(screenHeight - keyboard),
        reason: 'the whole bar must clear the IME',
      );

      await disposeHost(tester);
    },
  );

  testWidgets('follows the keyboard down when it closes', (tester) async {
    sizeSurface(tester, keyboardInset: keyboard);
    await pumpHost(tester, resizeToAvoidBottomInset: false, onShow: show);
    await showBar(tester);
    expect(barRect(tester).bottom, lessThanOrEqualTo(screenHeight - keyboard));

    // The IME goes down while the bar is still up: the bar must come down
    // with it instead of staying a keyboard-height up mid-screen — the owner's
    // report after "1 long line was formatted".
    sizeSurface(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(message), findsOneWidget);
    expect(
      barRect(tester).bottom,
      closeTo(screenHeight - navBar - AppSpacing.lg, 0.01),
      reason: 'with the IME gone only the navigation bar and the margin '
          'separate the pill from the bottom of the screen',
    );

    await disposeHost(tester);
  });

  testWidgets('follows the keyboard up when it opens', (tester) async {
    sizeSurface(tester);
    await pumpHost(tester, resizeToAvoidBottomInset: false, onShow: show);
    await showBar(tester);
    expect(
      barRect(tester).bottom,
      closeTo(screenHeight - navBar - AppSpacing.lg, 0.01),
    );

    sizeSurface(tester, keyboardInset: keyboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      barRect(tester).bottom,
      closeTo(screenHeight - keyboard - AppSpacing.lg, 0.01),
      reason: 'the bar re-anchors above the IME on the frame it appears',
    );

    await disposeHost(tester);
  });

  testWidgets('keeps the toolbar offset while riding the keyboard', (
    tester,
  ) async {
    sizeSurface(tester, keyboardInset: keyboard);
    await pumpHost(
      tester,
      resizeToAvoidBottomInset: false,
      onShow: (context) =>
          CustomSnackbar.show(context, message, withToolbarOffset: true),
    );
    await showBar(tester);
    expect(
      barRect(tester).bottom,
      closeTo(screenHeight - keyboard - AppSpacing.toolbarOffset, 0.01),
      reason: 'the editor bar sits on the IME, so the pill clears both',
    );

    sizeSurface(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      barRect(tester).bottom,
      closeTo(screenHeight - navBar - AppSpacing.toolbarOffset, 0.01),
    );

    await disposeHost(tester);
  });

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
      notResizing.bottom,
      closeTo(resizing.bottom, 0.01),
      reason:
          'with no IME the Scaffold anchors at size.height - viewPadding.bottom '
          '(scaffold.dart:1238-1241) and the overlay road clears the same '
          'navigation bar, so the two roads put the pill at one height',
    );
    expect(notResizing.left, closeTo(resizing.left, 0.01));
    expect(notResizing.right, closeTo(resizing.right, 0.01));
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

    expect(find.text('Open'), findsOneWidget);
    expect(barRect(tester).bottom, lessThanOrEqualTo(screenHeight - keyboard));

    await disposeHost(tester);
  });

  testWidgets('the action takes an overlay bar down with it', (tester) async {
    var opened = 0;
    sizeSurface(tester, keyboardInset: keyboard);
    await pumpHost(
      tester,
      resizeToAvoidBottomInset: false,
      onShow: (context) => CustomSnackbar.showWithAction(
        context,
        message: message,
        actionLabel: 'Open',
        onAction: () => opened++,
      ),
    );
    await showBar(tester);

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(opened, 1);
    expect(
      find.byType(OverlaySnackbarBody),
      findsNothing,
      reason: 'the confirming tap must not leave the bar lingering',
    );

    await disposeHost(tester);
  });

  // The bar inherits `snackBarTheme`, the popup menu's surface; it used to be
  // Material's `inverseSurface`, a near-white card in the dark theme, with the
  // action in `inversePrimary`.
  testWidgets('draws an action bar on the menu surface in the dark theme', (
    tester,
  ) async {
    final scheme = AppTheme.dark().colorScheme;
    sizeSurface(tester);
    await pumpHost(
      tester,
      resizeToAvoidBottomInset: true,
      theme: AppTheme.dark(),
      onShow: (context) => CustomSnackbar.showWithAction(
        context,
        message: message,
        actionLabel: 'Open',
        onAction: () {},
      ),
    );
    await showBar(tester);

    final pill = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(pill.color, scheme.surfaceContainerHigh);
    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Open'),
    );
    expect(
      action.style?.foregroundColor?.resolve(const <WidgetState>{}),
      scheme.primary,
    );

    await disposeHost(tester);
  });

  // U2.6 grew the action to a 48 dp target, and it sat inside the content's
  // 14 dp padding: a 76 dp bar app-wide. The target stays; the bar is 56.
  for (final resizes in [false, true]) {
    testWidgets('an action bar keeps the 48 dp target within 56 dp '
        '(${resizes ? 'Scaffold' : 'overlay'} road)', (tester) async {
      sizeSurface(tester);
      await pumpHost(
        tester,
        resizeToAvoidBottomInset: resizes,
        onShow: (context) => CustomSnackbar.showWithAction(
          context,
          // One line, as an Undo is: a wrapped message keeps its 14 dp.
          message: 'Moved',
          actionLabel: 'Open',
          onAction: () {},
        ),
      );
      await showBar(tester);

      final action = tester.getSize(find.widgetWithText(TextButton, 'Open'));
      expect(action.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(action.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(barRect(tester).height, lessThanOrEqualTo(56));

      await disposeHost(tester);
    });
  }

  group('action bar durations', () {
    for (final resize in [false, true]) {
      final road = resize ? 'the Scaffold road' : 'the overlay road';

      Future<void> showAction(
        WidgetTester tester, {
        Duration? duration,
      }) async {
        sizeSurface(tester);
        await pumpHost(
          tester,
          resizeToAvoidBottomInset: resize,
          onShow: (context) => CustomSnackbar.showWithAction(
            context,
            message: message,
            actionLabel: 'Open',
            onAction: () {},
            duration: duration,
          ),
        );
        await tester.tap(find.text('show'));
        await tester.pump();
      }

      // The Scaffold road's bar animates out after its duration, so it is
      // read off the bar the messenger was handed.
      Future<void> expectUpFor(WidgetTester tester, Duration up) async {
        if (resize) {
          expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, up);
        } else {
          await tester.pump(up - const Duration(milliseconds: 100));
          expect(find.byType(OverlaySnackbarBody), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(OverlaySnackbarBody), findsNothing);
        }
        await disposeHost(tester);
      }

      testWidgets('an Undo keeps the 3 s default on $road', (tester) async {
        await showAction(tester);
        await expectUpFor(tester, AppConstants.snackbarActionDefaultDuration);
        expect(
          AppConstants.snackbarActionDefaultDuration,
          const Duration(seconds: 3),
        );
      });

      testWidgets('the link confirm stays up 5 s on $road', (tester) async {
        await showAction(
          tester,
          duration: CustomSnackbar.confirmActionDuration,
        );
        await expectUpFor(tester, const Duration(seconds: 5));
      });

      testWidgets('a longer request is capped at the 5 s max on $road', (
        tester,
      ) async {
        await showAction(tester, duration: const Duration(seconds: 10));
        await expectUpFor(tester, AppConstants.snackbarActionMaxDuration);
        expect(
          AppConstants.snackbarActionMaxDuration,
          const Duration(seconds: 5),
        );
      });
    }

    // Only a bar with an action trades its padding for the action's own
    // 48 dp target; a plain message keeps a SnackBar's 14 dp.
    testWidgets('a plain message keeps the 14 dp padding on both roads', (
      tester,
    ) async {
      for (final resize in [false, true]) {
        sizeSurface(tester);
        await pumpHost(
          tester,
          resizeToAvoidBottomInset: resize,
          onShow: (context) => CustomSnackbar.show(context, message),
        );
        await showBar(tester);
        if (resize) {
          expect(tester.widget<SnackBar>(find.byType(SnackBar)).padding, null);
        } else {
          expect(
            tester
                .widget<OverlaySnackbarBody>(find.byType(OverlaySnackbarBody))
                .verticalPadding,
            SnackbarMetrics.barVerticalPadding,
          );
        }
        await disposeHost(tester);
      }
      expect(SnackbarMetrics.barVerticalPadding, 14);
    });
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
