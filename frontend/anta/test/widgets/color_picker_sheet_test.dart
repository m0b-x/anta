import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/color_picker_mode.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import 'support/color_picker_robot.dart';
import 'support/layout_errors.dart';

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
///
/// Every case drives the picker through [ColorPickerRobot] (`support/`), so
/// a rebuild of the chrome rewrites the robot and leaves these bodies alone.
/// The last group pins the sub-sheet chrome the picker took in Tier 3
/// (slice 5, D22): the header's two actions, the mode chips, the dots' 48 dp
/// targets, the hex field's id, "Copied" over the sheet, German at 200 % on
/// a phone.
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

  testWidgets('opens on the colour it was given, shown as hex', (tester) async {
    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF3A7BDE);

    expect(robot.hexText, '#3A7BDE');
  });

  testWidgets('a typed hex code is what Select returns', (tester) async {
    final robot = ColorPickerRobot(tester);
    final outcome = await robot.show();

    await robot.typeHex('#3A7BDE');
    await robot.select();

    expect(outcome.result, 0xFF3A7BDE);
  });

  testWidgets('a hex code without the hash is accepted too', (tester) async {
    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF000000);

    await robot.typeHex('00ff00');

    expect(robot.hexError, isNull);
  });

  testWidgets('an eight-digit code is refused — this picker has no alpha', (
    tester,
  ) async {
    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF3A7BDE);

    await robot.typeHex('803A7BDE');

    expect(robot.hexError, 'Enter a color like #3A7BDE');
  });

  testWidgets('an unparseable code shows the error and changes nothing', (
    tester,
  ) async {
    final robot = ColorPickerRobot(tester);
    final outcome = await robot.show(initialColor: 0xFF3A7BDE);

    await robot.typeHex('ZZZZZZ');
    expect(robot.hexError, 'Enter a color like #3A7BDE');

    await robot.select();

    expect(
      outcome.result,
      0xFF3A7BDE,
      reason: 'a rejected code must not have moved the colour',
    );
  });

  testWidgets('cancelling returns null', (tester) async {
    final robot = ColorPickerRobot(tester);
    final outcome = await robot.show();

    await robot.cancel();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
  });

  testWidgets('the before/after pair only exists when replacing a colour', (
    tester,
  ) async {
    final robot = ColorPickerRobot(tester);
    await robot.show();
    expect(robot.currentDotShown, isFalse);
    expect(robot.newDotShown, isTrue);

    await robot.select();
    await robot.show(initialColor: 0xFF3A7BDE);
    expect(robot.currentDotShown, isTrue);
  });

  testWidgets('tapping the current swatch reverts an edit in progress', (
    tester,
  ) async {
    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF3A7BDE);
    await robot.typeHex('#00FF00');
    expect(robot.hexText, '#00FF00');

    await robot.tapCurrentDot();

    expect(robot.hexText, '#3A7BDE');
  });

  testWidgets('the hue slider moves the colour and the hex follows', (
    tester,
  ) async {
    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF3A7BDE);
    final before = robot.hexText;

    await robot.dragSlider(-120);

    expect(robot.hexText, isNot(before));
  });

  testWidgets('lays out on a small phone without overflowing', (tester) async {
    // A sheet that overflows throws in tests, so the assertion is that this
    // pumps at all — the square is the one part that could push the actions
    // off the bottom, and it is the part sized from constraints.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF3A7BDE);

    expect(robot.selectShown, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('geometry modes', () {
    testWidgets('the square is what a fresh install opens on', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);

      expect(robot.currentMode, ColorPickerMode.square);
    });

    testWidgets('switching geometry never moves the colour', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);
      final before = robot.hexText;

      await robot.pickMode(ColorPickerMode.wheel);
      expect(robot.currentMode, ColorPickerMode.wheel);
      expect(robot.hexText, before);

      await robot.pickMode(ColorPickerMode.square);
      expect(robot.currentMode, ColorPickerMode.square);
      expect(robot.hexText, before);
    });

    testWidgets('each mode carries exactly one slider', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);
      expect(robot.sliderCount, 1);

      await robot.pickMode(ColorPickerMode.wheel);
      expect(robot.sliderCount, 1);
    });

    testWidgets('the wheel slider is brightness, not hue', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);
      await robot.pickMode(ColorPickerMode.wheel);

      // Brightness runs 0..1, so dragging the track to its left end is black
      // whatever the hue — which a hue slider could never produce.
      await robot.dragSlider(-400);

      expect(robot.hexText, '#000000');
    });

    testWidgets('dragging past the rim pegs saturation instead of stalling', (
      tester,
    ) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF808080);
      await robot.pickMode(ColorPickerMode.wheel);

      // Well outside the disc, straight to the right: hue 0, saturation 1.
      await robot.dragGeometry(const Offset(400, 0));

      expect(robot.hexText, '#800000');
    });

    testWidgets('the chosen geometry is remembered for the next open', (
      tester,
    ) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);
      await robot.pickMode(ColorPickerMode.wheel);
      await robot.cancel();

      expect(
        await SettingsService.getInstance().then((s) => s.getColorPickerMode()),
        ColorPickerMode.wheel,
      );

      await robot.show(initialColor: 0xFF3A7BDE);
      expect(robot.currentMode, ColorPickerMode.wheel);
    });

    testWidgets('wheel mode lays out on a small phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);
      await robot.pickMode(ColorPickerMode.wheel);

      expect(robot.selectShown, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching geometry moves nothing below the picker', (
      tester,
    ) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);
      final geometryBefore = robot.geometryRect;
      final hexBefore = robot.hexFieldRect;

      await robot.pickMode(ColorPickerMode.wheel);

      expect(
        robot.geometryRect,
        geometryBefore,
        reason: 'the geometry box is one fixed height for both shapes',
      );
      expect(robot.hexFieldRect, hexBefore);
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

    final robot = ColorPickerRobot(tester);
    await robot.show(initialColor: 0xFF3A7BDE);
    await robot.copyHex();

    expect(copied, '#3A7BDE');
    expect(robot.copiedMessageShown, isTrue);
  });

  group('the sub-sheet of the language', () {
    const phone = Size(360, 780);

    testWidgets("the header's ✕ and Select carry ids: Select reads Select "
        'and returns the colour, ✕ returns null', (tester) async {
      final robot = ColorPickerRobot(tester);
      var outcome = await robot.show(initialColor: 0xFF3A7BDE);

      final select = robot.nodeOf(SemanticsIds.colorPickerSelect);
      expect(select.label, 'Select');
      expect(select.flagsCollection.isButton, isTrue);
      expect(robot.selectLabel, 'Select');
      final close = robot.nodeOf(SemanticsIds.colorPickerClose);
      expect(close.tooltip, 'Cancel');
      expect(close.flagsCollection.isButton, isTrue);

      await robot.select();
      expect(outcome.result, 0xFF3A7BDE);

      outcome = await robot.show(initialColor: 0xFF3A7BDE);
      await robot.cancel();
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    });

    testWidgets('the mode chips carry ids and announce the one on; a pick '
        'moves the check and is remembered', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);

      expect(
        robot.nodeOf(SemanticsIds.colorModeSquare).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        robot.nodeOf(SemanticsIds.colorModeWheel).flagsCollection.isSelected,
        isNot(Tristate.isTrue),
      );
      expect(robot.currentMode, ColorPickerMode.square);

      await robot.pickMode(ColorPickerMode.wheel);

      expect(robot.currentMode, ColorPickerMode.wheel);
      expect(
        robot.nodeOf(SemanticsIds.colorModeWheel).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        robot.nodeOf(SemanticsIds.colorModeSquare).flagsCollection.isSelected,
        isNot(Tristate.isTrue),
      );
      expect(
        await SettingsService.getInstance().then((s) => s.getColorPickerMode()),
        ColorPickerMode.wheel,
      );
    });

    testWidgets('both preview dots are 48 dp targets', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);

      final dots = robot.dotTargets;
      expect(dots, hasLength(2));
      for (final dot in dots) {
        expect(dot.width, FormMetrics.trailingButtonSize);
        expect(dot.height, FormMetrics.trailingButtonSize);
      }
    });

    testWidgets("the hex field's node carries its id, the copy button its "
        'own, and the chips theirs', (tester) async {
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);

      final hex = robot.nodeOf(SemanticsIds.colorHex);
      expect(hex.flagsCollection.isTextField, isTrue);
      expect(hex.value, '#3A7BDE');
      final copy = robot.nodeOf(SemanticsIds.colorCopyHex);
      expect(copy.tooltip, 'Copy hex code');
      expect(copy.flagsCollection.isButton, isTrue);
      expect(copy.hasAction(SemanticsAction.tap), isTrue);
      for (final id in [
        SemanticsIds.colorModeSquare,
        SemanticsIds.colorModeWheel,
      ]) {
        final chip = robot.nodeOf(id);
        expect(chip.flagsCollection.isButton, isTrue, reason: id);
        expect(chip.flagsCollection.isEnabled, isNot(Tristate.isFalse));
      }
    });

    testWidgets('"Copied" is drawn over the sheet, where a finger can reach '
        'it', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final robot = ColorPickerRobot(tester);
      await robot.show(initialColor: 0xFF3A7BDE);

      await robot.copyHex();

      expect(robot.isOpen, isTrue);
      expect(robot.copiedMessageReachable, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('German at text scale 2.0 on 360 × 780 lays out with no '
        'layout error, the hex row whole inside the sheet', (tester) async {
      final robot = ColorPickerRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          initialColor: 0xFF3A7BDE,
          locale: const Locale('de'),
          textScale: 2.0,
          surface: phone,
        );
        expect(robot.selectShown, isTrue);
        expect(robot.selectLabel, 'Auswählen');
        final sheet = robot.sheetRect;
        for (final rect in [
          robot.hexFieldRect,
          robot.copyButtonRect,
          robot.geometryRect,
          robot.targetOf(SemanticsIds.colorPickerClose),
          robot.targetOf(SemanticsIds.colorPickerSelect),
          robot.targetOf(SemanticsIds.colorModeSquare),
          robot.targetOf(SemanticsIds.colorModeWheel),
        ]) {
          expect(rect.left, greaterThanOrEqualTo(sheet.left));
          expect(rect.right, lessThanOrEqualTo(sheet.right));
        }
        for (final dot in robot.dotTargets) {
          expect(dot.width, FormMetrics.trailingButtonSize);
        }
        expect(robot.hexText, '#3A7BDE');
      });
      expect(errors, isEmpty);
    });
  });
}
