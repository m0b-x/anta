import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import 'support/color_picker_robot.dart';
import 'support/layout_errors.dart';
import 'support/palette_robot.dart';

/// The management sheet's two destructive paths are what earn a widget test:
/// both are confirmed, both persist immediately (there is no Save), and both
/// must leave the built-in half alone.
///
/// Every case drives the sheet through [PaletteRobot] (`support/`), so a
/// rebuild of the chrome rewrites the robot and leaves these bodies alone.
/// The last group pins the sub-sheet of the UI language the sheet became in
/// Tier 3 (slice 5, D20): the rows with their three targets, the one Add
/// color row disabled at the cap under the count, the read-only strip, the
/// reset's message over the sheet, a long press lifting a row, German at
/// 200 % on a phone, the targets.
void main() {
  late AppDatabase db;
  late CalendarPaletteService service;

  const customA = 0xFF123456;
  const customB = 0xFF654321;

  setUp(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    service = await CalendarPaletteService.getInstance();
  });

  tearDown(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  testWidgets('an empty palette explains itself instead of showing nothing', (
    tester,
  ) async {
    final robot = PaletteRobot(tester);
    await robot.show();

    expect(robot.emptyCaptionShown, isTrue);
    expect(
      await robot.resetEnabled,
      isFalse,
      reason: 'nothing to reset while the palette is untouched',
    );
  });

  testWidgets('deleting asks first, then drops only that colour', (
    tester,
  ) async {
    await service.add(customA);
    await service.add(customB);
    final robot = PaletteRobot(tester);
    await robot.show();

    await robot.delete('#123456');
    expect(robot.dialogTitled('Delete color'), isTrue);

    await robot.confirm();

    expect(service.customColors, [customB]);
    expect(robot.customRows, isNot(contains('#123456')));
    expect(robot.customRows, contains('#654321'));
  });

  testWidgets('dismissing the confirmation keeps the colour', (tester) async {
    await service.add(customA);
    final robot = PaletteRobot(tester);
    await robot.show();

    await robot.delete('#123456');
    await robot.cancelDialog();

    expect(service.customColors, [customA]);
  });

  testWidgets('dragging a row reorders the palette itself', (tester) async {
    await service.add(customA);
    await service.add(customB);
    final robot = PaletteRobot(tester);
    await robot.show();

    await robot.dragRow(1, 0);

    expect(
      service.customColors,
      [customB, customA],
      reason: 'row order is picker order, so the drag has to persist',
    );
  });

  testWidgets('reset drops every custom colour and no built-in', (
    tester,
  ) async {
    await service.add(customA);
    await service.add(customB);
    final robot = PaletteRobot(tester);
    await robot.show();

    await robot.reset();
    await robot.confirm();

    expect(service.customColors, isEmpty);
    expect(CalendarPalette.all, CalendarPalette.defaults);
  });

  group('the sub-sheet of the language', () {
    const phone = Size(360, 780);

    /// Fills the custom half to its cap with colours that are no built-in.
    Future<void> fillToCap() async {
      for (var i = 1; i <= SettingsKeys.maxCustomCalendarColors; i++) {
        await service.add(0xFF000000 | (i * 0x0A0B0C));
      }
      expect(
        service.customColors,
        hasLength(SettingsKeys.maxCustomCalendarColors),
      );
    }

    testWidgets("a custom colour's row carries three nodes with their ids: "
        'the row reading its hex and taking a tap, the handle with its name, '
        'the delete with its tooltip', (tester) async {
      await service.add(customA);
      final robot = PaletteRobot(tester);
      await robot.show();

      expect(robot.customRows, ['#123456']);
      final row = robot.nodeOf(SemanticsIds.paletteRow('#123456'));
      expect(row.label, contains('#123456'));
      expect(row.hasAction(SemanticsAction.tap), isTrue);
      final handle = robot.nodeOf(SemanticsIds.paletteHandle('#123456'));
      expect(handle.label, 'Drag to reorder');
      final delete = robot.nodeOf(SemanticsIds.paletteDelete('#123456'));
      expect(delete.tooltip, 'Delete color');
      expect(delete.flagsCollection.isButton, isTrue);
      final close = robot.nodeOf(SemanticsIds.paletteClose);
      expect(close.tooltip, 'Close');
      expect(close.flagsCollection.isButton, isTrue);
    });

    testWidgets('a tap on a row recolours it through the picker, and Add '
        'color adds through it', (tester) async {
      await service.add(customA);
      final robot = PaletteRobot(tester);
      final picker = ColorPickerRobot(tester);
      await robot.show();

      await robot.edit('#123456');
      expect(robot.pickerOpen, isTrue);
      expect(picker.hexText, '#123456');
      await picker.typeHex('#654321');
      await picker.select();

      expect(service.customColors, [customB]);
      expect(robot.customRows, ['#654321']);

      expect(await robot.addEnabled, isTrue);
      await robot.add();
      expect(robot.pickerOpen, isTrue);
      await picker.typeHex('#ABCDEF');
      await picker.select();

      expect(service.customColors, [customB, 0xFFABCDEF]);
      expect(robot.customRows, ['#654321', '#ABCDEF']);
      expect(robot.capText, '2 of 24');
    });

    testWidgets('at the cap the Add color row is disabled in place and the '
        'count reads "24 of 24"', (tester) async {
      await fillToCap();
      final robot = PaletteRobot(tester);
      await robot.show();

      expect(robot.capText, '24 of 24');
      // The run is a lazy list: on this surface only its first rows are
      // built, so the count above is what says how many there are.
      expect(robot.customRows.first, '#0A0B0C');
      expect(await robot.addEnabled, isFalse);
      expect(
        robot.nodeOf(SemanticsIds.paletteAdd).hasAction(SemanticsAction.tap),
        isFalse,
      );
      await robot.add();
      expect(robot.pickerOpen, isFalse, reason: 'a dimmed row opens nothing');
      expect(robot.emptyCaptionShown, isFalse);
    });

    testWidgets("the built-in strip's dots are named by their hex and are "
        'not buttons', (tester) async {
      final robot = PaletteRobot(tester);
      await robot.show();

      expect(robot.builtInCount, CalendarPalette.defaults.length);
      expect(robot.builtInLabels, [
        for (final color in CalendarPalette.defaults)
          CalendarPalette.hexOf(color),
      ]);
      for (final node in robot.builtInNodes) {
        expect(node.label, matches(RegExp(r'^#[0-9A-F]{6}$')));
        expect(node.flagsCollection.isButton, isFalse);
        expect(node.hasAction(SemanticsAction.tap), isFalse);
      }
      for (final target in robot.builtInTargets) {
        expect(target.width, FormMetrics.trailingButtonSize);
        expect(target.height, FormMetrics.trailingButtonSize);
      }
    });

    testWidgets("the reset's done message is drawn over the sheet", (
      tester,
    ) async {
      await service.add(customA);
      final robot = PaletteRobot(tester);
      await robot.show();

      await robot.reset();
      await robot.confirm();

      expect(robot.isOpen, isTrue);
      expect(robot.message, 'Palette reset');
      expect(robot.messageReachable, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a long press anywhere on a row lifts it too', (tester) async {
      await service.add(customA);
      await service.add(customB);
      final robot = PaletteRobot(tester);
      await robot.show();

      await robot.dragRowByLongPress(1, 0);

      expect(service.customColors, [customB, customA]);
      expect(robot.customRows, ['#654321', '#123456']);
      expect(robot.pickerOpen, isFalse, reason: 'a lift is never an edit');
    });

    testWidgets('German at text scale 2.0 on 360 × 780 lays out with no '
        'layout error, every control inside the sheet', (tester) async {
      await service.add(customA);
      await service.add(customB);
      final robot = PaletteRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          locale: const Locale('de'),
          textScale: 2.0,
          surface: phone,
        );
        expect(robot.customRows, ['#123456', '#654321']);
        expect(robot.capText, '2 von 24');
        final sheet = robot.sheetRect;
        for (final id in [
          SemanticsIds.paletteClose,
          SemanticsIds.paletteRow('#123456'),
          SemanticsIds.paletteHandle('#123456'),
          SemanticsIds.paletteDelete('#123456'),
          SemanticsIds.paletteAdd,
          SemanticsIds.paletteReset,
        ]) {
          await robot.reveal(id);
          final rect = robot.targetOf(id);
          expect(rect.left, greaterThanOrEqualTo(sheet.left), reason: id);
          expect(rect.right, lessThanOrEqualTo(sheet.right), reason: id);
        }
      });
      expect(errors, isEmpty);
    });

    testWidgets('every control is a 48 dp target at 360 × 780', (tester) async {
      await service.add(customA);
      final robot = PaletteRobot(tester);
      await robot.show(surface: phone);

      for (final id in [
        SemanticsIds.paletteClose,
        SemanticsIds.paletteHandle('#123456'),
        SemanticsIds.paletteDelete('#123456'),
      ]) {
        final rect = robot.targetOf(id);
        expect(
          rect.width,
          greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
          reason: id,
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
          reason: id,
        );
      }
      expect(
        robot.rowRect('#123456').height,
        greaterThanOrEqualTo(FormMetrics.titleRowMinHeight),
      );
      for (final id in [SemanticsIds.paletteAdd, SemanticsIds.paletteReset]) {
        await robot.reveal(id);
        expect(
          robot.targetOf(id).height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
          reason: id,
        );
      }
    });
  });
}
