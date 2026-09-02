import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/color_picker_mode.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/color_picker_sheet.dart';

import '../database/support/db_test_support.dart';

/// What the picker owes its callers is one number, so the tests pin the paths
/// that produce it: the hex field as the precise (and non-visual) way in, the
/// alpha guarantee every calendar surface relies on, the before/after pair
/// that makes editing a swatch an edit rather than a fresh pick, and — since
/// the wheel landed — that the two geometries are one picker wearing two
/// shapes rather than two pickers.
///
/// A real in-memory settings backend is bound because `show()` resolves the
/// remembered geometry before presenting: without one, that read fails into
/// the square-mode fallback and the persistence path would go untested.
void main() {
  late AppDatabase db;

  setUp(() async {
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  Future<int?> openPicker(
    WidgetTester tester, {
    int? initialColor,
    bool cancelled = false,
  }) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ColorPickerSheet.show(
                  context,
                  initialColor: initialColor,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The sheet resolves the remembered geometry before presenting, so it
    // arrives a microtask after the tap.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    return result;
  }

  Future<int?> selectAndClose(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();
    return null;
  }

  Future<void> typeHex(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  String hexFieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('opens on the colour it was given, shown as hex', (tester) async {
    await openPicker(tester, initialColor: 0xFF3A7BDE);

    expect(hexFieldText(tester), '#3A7BDE');
  });

  testWidgets('a typed hex code is what Select returns', (tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ColorPickerSheet.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The sheet resolves the remembered geometry before presenting, so it
    // arrives a microtask after the tap.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await typeHex(tester, '#3A7BDE');
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();

    expect(picked, 0xFF3A7BDE);
  });

  testWidgets('a hex code without the hash is accepted too', (tester) async {
    await openPicker(tester, initialColor: 0xFF000000);

    await typeHex(tester, '00ff00');

    expect(find.text('Enter a color like #3A7BDE'), findsNothing);
  });

  testWidgets('an eight-digit code is refused — this picker has no alpha', (
    tester,
  ) async {
    await openPicker(tester, initialColor: 0xFF3A7BDE);

    await typeHex(tester, '803A7BDE');

    expect(find.text('Enter a color like #3A7BDE'), findsOneWidget);
  });

  testWidgets('an unparseable code shows the error and changes nothing', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ColorPickerSheet.show(
                  context,
                  initialColor: 0xFF3A7BDE,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The sheet resolves the remembered geometry before presenting, so it
    // arrives a microtask after the tap.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await typeHex(tester, 'ZZZZZZ');
    expect(find.text('Enter a color like #3A7BDE'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();

    expect(
      picked,
      0xFF3A7BDE,
      reason: 'a rejected code must not have moved the colour',
    );
  });

  testWidgets('cancelling returns null', (tester) async {
    int? picked = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ColorPickerSheet.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The sheet resolves the remembered geometry before presenting, so it
    // arrives a microtask after the tap.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });

  testWidgets('the before/after pair only exists when replacing a colour', (
    tester,
  ) async {
    await openPicker(tester);
    expect(find.byTooltip('Current color, tap to restore'), findsNothing);
    expect(find.byTooltip('New color'), findsOneWidget);

    await selectAndClose(tester);
    await openPicker(tester, initialColor: 0xFF3A7BDE);
    expect(find.byTooltip('Current color, tap to restore'), findsOneWidget);
  });

  testWidgets('tapping the current swatch reverts an edit in progress', (
    tester,
  ) async {
    await openPicker(tester, initialColor: 0xFF3A7BDE);
    await typeHex(tester, '#00FF00');
    expect(hexFieldText(tester), '#00FF00');

    await tester.tap(find.byTooltip('Current color, tap to restore'));
    await tester.pumpAndSettle();

    expect(hexFieldText(tester), '#3A7BDE');
  });

  testWidgets('the hue slider moves the colour and the hex follows', (
    tester,
  ) async {
    await openPicker(tester, initialColor: 0xFF3A7BDE);
    final before = hexFieldText(tester);

    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(hexFieldText(tester), isNot(before));
  });

  testWidgets('lays out on a small phone without overflowing', (tester) async {
    // A sheet that overflows throws in tests, so the assertion is that this
    // pumps at all — the square is the one part that could push the actions
    // off the bottom, and it is the part sized from constraints.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openPicker(tester, initialColor: 0xFF3A7BDE);

    expect(find.widgetWithText(FilledButton, 'Select'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('geometry modes', () {
    Finder square() => find.byKey(const ValueKey('color_picker_square'));
    Finder wheel() => find.byKey(const ValueKey('color_picker_wheel'));

    Future<void> switchTo(WidgetTester tester, ColorPickerMode mode) async {
      await tester.tap(
        find.byIcon(
          mode == ColorPickerMode.wheel
              ? Icons.donut_large_rounded
              : Icons.gradient_rounded,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the square is what a fresh install opens on', (tester) async {
      await openPicker(tester, initialColor: 0xFF3A7BDE);

      expect(square(), findsOneWidget);
      expect(wheel(), findsNothing);
    });

    testWidgets('switching geometry never moves the colour', (tester) async {
      await openPicker(tester, initialColor: 0xFF3A7BDE);
      final before = hexFieldText(tester);

      await switchTo(tester, ColorPickerMode.wheel);
      expect(wheel(), findsOneWidget);
      expect(hexFieldText(tester), before);

      await switchTo(tester, ColorPickerMode.square);
      expect(square(), findsOneWidget);
      expect(hexFieldText(tester), before);
    });

    testWidgets('each mode carries exactly one slider', (tester) async {
      await openPicker(tester, initialColor: 0xFF3A7BDE);
      expect(find.byType(Slider), findsOneWidget);

      await switchTo(tester, ColorPickerMode.wheel);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('the wheel slider is brightness, not hue', (tester) async {
      await openPicker(tester, initialColor: 0xFF3A7BDE);
      await switchTo(tester, ColorPickerMode.wheel);

      // Brightness runs 0..1, so dragging the track to its left end is black
      // whatever the hue — which a hue slider could never produce.
      await tester.drag(find.byType(Slider), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(hexFieldText(tester), '#000000');
    });

    testWidgets('dragging past the rim pegs saturation instead of stalling', (
      tester,
    ) async {
      await openPicker(tester, initialColor: 0xFF808080);
      await switchTo(tester, ColorPickerMode.wheel);

      final centre = tester.getCenter(wheel());
      // Well outside the disc, straight to the right: hue 0, saturation 1.
      await tester.dragFrom(centre, const Offset(400, 0));
      await tester.pumpAndSettle();

      expect(hexFieldText(tester), '#800000');
    });

    testWidgets('the chosen geometry is remembered for the next open', (
      tester,
    ) async {
      await openPicker(tester, initialColor: 0xFF3A7BDE);
      await switchTo(tester, ColorPickerMode.wheel);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        await SettingsService.getInstance().then((s) => s.getColorPickerMode()),
        ColorPickerMode.wheel,
      );

      await openPicker(tester, initialColor: 0xFF3A7BDE);
      expect(wheel(), findsOneWidget);
      expect(square(), findsNothing);
    });

    testWidgets('wheel mode lays out on a small phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await openPicker(tester, initialColor: 0xFF3A7BDE);
      await switchTo(tester, ColorPickerMode.wheel);

      expect(find.widgetWithText(FilledButton, 'Select'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching geometry moves nothing below the picker', (
      tester,
    ) async {
      await openPicker(tester, initialColor: 0xFF3A7BDE);
      final hexBefore = tester.getRect(find.byType(TextField));
      final selectBefore = tester.getRect(
        find.widgetWithText(FilledButton, 'Select'),
      );

      await switchTo(tester, ColorPickerMode.wheel);

      expect(tester.getRect(find.byType(TextField)), hexBefore);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Select')),
        selectBefore,
        reason: 'the geometry box is one fixed height for both shapes',
      );
    });
  });

  testWidgets('copy puts the hex code on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await openPicker(tester, initialColor: 0xFF3A7BDE);
    await tester.tap(find.byTooltip('Copy hex code'));
    await tester.pumpAndSettle();

    expect(copied, '#3A7BDE');
    expect(find.text('Copied'), findsOneWidget);
  });
}
