import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/overlay_snackbar.dart';

import '../database/support/db_test_support.dart';
import 'support/color_picker_robot.dart';
import 'support/swatch_robot.dart';

/// The picker is one widget standing in five places, so what is worth pinning
/// is the part each of those places used to hand-roll: the default dot is the
/// selection when the value is null, a colour that is no longer in the palette
/// still shows up selected rather than vanishing (an event coloured before its
/// swatch was deleted), a built-in offers no long-press menu while the user's
/// own does, and a colour added anywhere repaints a picker already on screen.
///
/// Every case drives the strip through [SwatchRobot] (`support/`), so a
/// rebuild of its chrome rewrites the robot and leaves these bodies alone.
void main() {
  late AppDatabase db;

  final builtIn = CalendarColors.swatchPalette.first;
  const custom = 0xFF123456;
  const orphan = 0xFF999999;

  setUp(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    await CalendarPaletteService.getInstance();
  });

  tearDown(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  Future<int?> pumpPicker(
    WidgetTester tester, {
    int? value,
    ColorSwatchDefault? defaultOption,
  }) async {
    int? emitted;
    var reported = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ColorSwatchPicker(
              value: value,
              defaultOption: defaultOption,
              onChanged: (next) {
                emitted = next;
                reported = true;
                setState(() => value = next);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return reported ? emitted : null;
  }

  testWidgets('renders the built-ins plus the wheel and manage dots', (
    tester,
  ) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);

    expect(
      swatches.dots().length,
      CalendarColors.swatchPalette.length + 2,
      reason: 'no default option, no custom colours: palette + wheel + manage',
    );
  });

  testWidgets('the default dot carries the selection while the value is null', (
    tester,
  ) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(color: Colors.teal),
    );

    expect(swatches.dots().first.selected, isTrue);
    expect(swatches.selectedCount, 1);
  });

  testWidgets('tapping a swatch reports it and moves the check', (
    tester,
  ) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(color: Colors.teal),
    );

    await swatches.tap(builtIn);

    expect(swatches.isSelected(builtIn), isTrue);
    expect(swatches.dots().first.selected, isFalse);
  });

  testWidgets('a value outside the palette still renders, selected', (
    tester,
  ) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester, value: orphan);

    expect(swatches.isSelected(orphan), isTrue);
    expect(CalendarPalette.contains(orphan), isFalse);
  });

  testWidgets('only the user\'s own swatches offer the long-press menu', (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);

    expect(swatches.offersMenu(custom), isTrue);
    expect(swatches.offersMenu(builtIn), isFalse);
  });

  testWidgets('a colour added elsewhere repaints a picker already on screen', (
    tester,
  ) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);
    expect(swatches.hasSwatch(custom), isFalse);

    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    await tester.pumpAndSettle();

    expect(swatches.hasSwatch(custom), isTrue);
  });

  testWidgets('the selection follows a swatch recoloured anywhere', (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    var reported = custom;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ColorSwatchPicker(
            value: custom,
            onChanged: (next) => reported = next!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The recolour happens in the service, standing in for the management
    // sheet — which is reachable from this very row, and where the picker
    // would otherwise never hear about the edit.
    await service.update(custom, 0xFFAABBCC);
    await tester.pumpAndSettle();

    expect(
      reported,
      0xFFAABBCC,
      reason: 'an edit means "this swatch, but that shade"',
    );
  });

  testWidgets('an unrelated palette change leaves the selection alone', (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ColorSwatchPicker(value: custom, onChanged: (_) => changes++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await service.add(0xFFAABBCC);
    await service.update(0xFFAABBCC, 0xFFDDEEFF);
    await tester.pumpAndSettle();

    expect(changes, 0);
  });

  testWidgets('a long palette collapses, and expands on request', (
    tester,
  ) async {
    // Phone width: on a wide surface the whole palette fits three runs and
    // collapsing would be the wrong answer, which is why the row measures.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final service = await CalendarPaletteService.getInstance();
    for (var i = 0; i < 20; i++) {
      await service.add(0xFF000001 + i);
    }
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);

    final collapsed = swatches.dots().length;
    expect(
      collapsed,
      lessThan(CalendarPalette.all.length),
      reason: 'a full palette is nine rows of circles inside a form',
    );

    await swatches.tapShowMore();

    expect(swatches.dots().length, greaterThan(collapsed));
    expect(swatches.isCollapsed, isFalse);
  });

  testWidgets('a collapsed row still shows the colour in force', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final service = await CalendarPaletteService.getInstance();
    for (var i = 0; i < 20; i++) {
      await service.add(0xFF000001 + i);
    }
    // The last swatch added is the furthest from the front of the row, so it
    // is the one a naive "first N" would hide.
    final last = CalendarPalette.custom.last;
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester, value: last);

    expect(swatches.isSelected(last), isTrue);
  });

  testWidgets('a deleted colour leaves every picker', (tester) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);

    await service.remove(custom);
    await tester.pumpAndSettle();

    expect(swatches.hasSwatch(custom), isFalse);
  });

  // --- Tier 3, slice 1 (§3.8, §4.2 item 6) ----------------------------------

  testWidgets("the default dot always wears a glyph: the caller's, else the "
      'reset one, so it is never a twin of a swatch in its colour', (
    tester,
  ) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(color: Colors.teal),
    );
    expect(swatches.defaultGlyph, Icons.format_color_reset_rounded);

    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(
        color: Colors.teal,
        icon: Icons.event_rounded,
      ),
    );
    expect(swatches.defaultGlyph, Icons.event_rounded);
  });

  testWidgets('the default, add and manage dots carry their ids on their '
      'own nodes, tooltip and state included', (tester) async {
    final swatches = SwatchRobot(tester);
    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(
        color: Colors.teal,
        tooltip: 'Category color',
      ),
    );

    final defaultDot = swatches.nodeOf(SemanticsIds.swatchDefault);
    expect(defaultDot.tooltip, 'Category color');
    expect(defaultDot.flagsCollection.isSelected, Tristate.isTrue);
    expect(defaultDot.flagsCollection.isButton, isTrue);
    expect(defaultDot.hasAction(SemanticsAction.tap), isTrue);
    final add = swatches.nodeOf(SemanticsIds.swatchAdd);
    expect(add.tooltip, 'Add color');
    expect(add.hasAction(SemanticsAction.tap), isTrue);
    final manage = swatches.nodeOf(SemanticsIds.swatchManage);
    expect(manage.tooltip, 'Manage colors');
    expect(manage.hasAction(SemanticsAction.tap), isTrue);
    // One node each: the id did not grow a second, unlabelled node.
    expect(find.bySemanticsIdentifier(SemanticsIds.swatchAdd), findsOneWidget);
  });

  testWidgets('a long press on a custom swatch opens a popup of three items '
      'by id, hung from the dot', (tester) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);

    await swatches.longPress(custom);

    expect(swatches.menuItems, ['Edit color', 'Delete color', 'Manage colors']);
    expect(swatches.hasMenuItem(SemanticsIds.swatchMenuEdit), isTrue);
    expect(swatches.hasMenuItem(SemanticsIds.swatchMenuDelete), isTrue);
    expect(swatches.hasMenuItem(SemanticsIds.swatchMenuManage), isTrue);
    // The preset ⋮'s anchor rule: a zero-width anchor at the dot's right
    // edge, which the popup grows away from the nearer screen edge — the
    // menu's left edge there while the dot sits in the left half, its right
    // edge there past the middle (a row's ⋮ always takes the second); under
    // the dot while there is room; between the actions menu's floor (the
    // preset ⋮'s, the app's menu width, not a choice menu's) and the cap.
    final dot = swatches.dotRect(custom);
    final first = swatches.menuFirstItemRect;
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (dot.right > screen.width / 2) {
      expect(first.right, moreOrLessEquals(dot.right, epsilon: 0.5));
    } else {
      expect(first.left, moreOrLessEquals(dot.right, epsilon: 0.5));
    }
    expect(
      first.top,
      moreOrLessEquals(dot.bottom + FormMetrics.menuPadding.top, epsilon: 0.5),
    );
    expect(
      first.width,
      inInclusiveRange(AppTheme.menuWidth, FormMetrics.menuMaxWidth),
    );
    expect(first.height, FormMetrics.menuRowHeight);
  });

  testWidgets('delete from the menu asks first and removes only on confirm', (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    final swatches = SwatchRobot(tester);
    await pumpPicker(tester);

    await swatches.longPress(custom);
    await swatches.pickMenu('Delete color');
    expect(swatches.dialogShown, isTrue);
    await swatches.cancelDelete();
    expect(swatches.dialogShown, isFalse);
    expect(swatches.hasSwatch(custom), isTrue);
    expect(CalendarPalette.custom, contains(custom));

    await swatches.longPress(custom);
    await swatches.pickMenu('Delete color');
    await swatches.confirmDelete();
    expect(swatches.hasSwatch(custom), isFalse);
    expect(CalendarPalette.custom, isNot(contains(custom)));
  });

  testWidgets('the add dot drops the focus of a field beside the strip, so '
      'the picker returning raises no keyboard', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: node),
              ColorSwatchPicker(value: null, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);

    final swatches = SwatchRobot(tester);
    await swatches.tapAdd();
    expect(swatches.pickerOpen, isTrue);
    await ColorPickerRobot(tester).cancel();
    expect(swatches.pickerOpen, isFalse);

    // Nothing regained the focus when the picker's route went away: the
    // field had already let go of it before the route was pushed.
    expect(node.hasFocus, isFalse);
    expect(FocusManager.instance.primaryFocus, isNot(same(node)));
  });

  testWidgets('a refusal is drawn over the sheet the strip is in', (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    for (var i = 0; i < SettingsKeys.maxCustomCalendarColors; i++) {
      await service.add(0xFF000001 + i);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => ColorSwatchPicker(
                  value: null,
                  onChanged: (_) {},
                  collapsible: false,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final swatches = SwatchRobot(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ColorSwatchPicker)),
    )!;

    // A full palette and a colour it does not hold: the one refusal `add`
    // gives.
    await swatches.tapAdd();
    final picker = ColorPickerRobot(tester);
    await picker.typeHex('ABCDEF');
    await picker.select();
    await tester.pumpAndSettle();

    expect(swatches.pickerOpen, isFalse);
    expect(find.text(l10n.colorPaletteFull).hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    OverlaySnackbar.hide();
    await tester.pumpAndSettle();
  });

  testWidgets('a refusal comes down after the error duration the palette '
      "sheet gives the same message, not the overlay's longer default", (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    for (var i = 0; i < SettingsKeys.maxCustomCalendarColors; i++) {
      await service.add(0xFF000001 + i);
    }
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => ColorSwatchPicker(
                  value: null,
                  onChanged: (_) {},
                  collapsible: false,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final swatches = SwatchRobot(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ColorSwatchPicker)),
    )!;

    await swatches.tapAdd();
    final picker = ColorPickerRobot(tester);
    await picker.typeHex('ABCDEF');
    await picker.select();
    await tester.pumpAndSettle();
    final message = find.text(l10n.colorPaletteFull);
    expect(message, findsOneWidget);

    // The bar's timer started on the frame that drew it, at most a settle
    // ago: once the error duration has passed it is down, where the
    // overlay's default would still hold it up.
    await tester.pump(AppConstants.snackbarErrorDuration);
    expect(message, findsNothing);
  });
}
