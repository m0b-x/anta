import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../services/permission_support.dart';
import 'support/alert_sheet_robot.dart';
import 'support/category_editor_robot.dart';
import 'support/layout_errors.dart';

/// The category editor writes inside the sheet and hands the written row
/// back, so what is worth pinning is that contract from both ends: the row
/// the service holds afterwards and the one the caller receives are the same
/// thing, a built-in's name survives an edit, the duplicate warning warns
/// without blocking, and a save that fails leaves the sheet usable.
///
/// Runs the real service and the real DAO against `NativeDatabase.memory()`,
/// the way the categories page suite does, with a write interceptor that can
/// be told to fail. Every case drives the sheet through [CategoryEditorRobot]
/// (`support/`), so a rebuild of the chrome rewrites the robot and leaves
/// these bodies alone.
void main() {
  late AppDatabase db;
  late CategoryService service;
  late _WriteFailure writes;

  const green = 0xFF43A047;
  const defaultOrange = 0xFFFB8C00;

  setUp(() async {
    CategoryService.reset();
    CalendarPaletteService.reset();
    SettingsService.reset();
    writes = _WriteFailure();
    db = await openTestDatabase(interceptor: writes);
    SettingsService.forTesting(db);
    service = await CategoryService.forTesting(db);
  });

  tearDown(() async {
    CategoryService.reset();
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  /// A custom category the service already holds.
  Future<CalendarCategory> custom(String name, {bool hidden = false}) async {
    final created = await service.create(
      name: name,
      colorValue: 0xFF112233,
      iconKey: 'event',
    );
    if (hidden) await service.setHidden(created.id, true);
    return CalendarCategories.byId(created.id)!;
  }

  testWidgets('a new category opens on the orange event default with Save '
      'disabled', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();

    expect(robot.title, 'Create category');
    expect(robot.nameText, '');
    expect(robot.canSave, isFalse);
    expect(robot.previewIcon, CalendarIcons.forKey('event'));
    expect(robot.previewColor, const Color(defaultOrange));
    expect(robot.selectedSwatch, defaultOrange);
    expect(robot.isBuiltInName, isFalse);
  });

  testWidgets('create returns the created category and writes it through '
      'the service', (tester) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show();

    await robot.typeName('Stretching');
    await robot.pickSwatch(green);
    await robot.chooseIcon('cake');
    expect(robot.previewIcon, CalendarIcons.forKey('cake'));
    expect(robot.previewColor, const Color(green));

    await robot.save();

    expect(outcome.returned, isTrue);
    expect(robot.isOpen, isFalse);
    final created = outcome.result!;
    expect(created.name, 'Stretching');
    expect(created.colorValue, green);
    expect(created.iconKey, 'cake');
    expect(created.isBuiltIn, isFalse);
    expect(created.isHidden, isFalse);
    // Appended after every built-in.
    expect(created.sortOrder, CalendarCategories.builtInSeeds.length);
    // The row was written before the sheet popped: the caller can refresh
    // from the service and find it.
    expect(CalendarCategories.byId(created.id), created);
    expect(service.categories.map((c) => c.id), contains(created.id));
  });

  testWidgets('the name is trimmed on save', (tester) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show();

    await robot.typeName('  Stretching  ');
    await robot.save();

    expect(outcome.result!.name, 'Stretching');
    expect(CalendarCategories.byId(outcome.result!.id)!.name, 'Stretching');
  });

  testWidgets('edit writes the name, colour and icon and keeps sortOrder, '
      'isBuiltIn and isHidden', (tester) async {
    final before = await custom('Old', hidden: true);
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show(initial: before);
    expect(robot.title, 'Edit category');
    expect(robot.nameText, 'Old');

    await robot.typeName('New');
    await robot.pickSwatch(green);
    await robot.chooseIcon('cake');
    await robot.save();

    final saved = outcome.result!;
    expect(saved.id, before.id);
    expect(saved.name, 'New');
    expect(saved.colorValue, green);
    expect(saved.iconKey, 'cake');
    expect(saved.sortOrder, before.sortOrder);
    expect(saved.isBuiltIn, isFalse);
    expect(saved.isHidden, isTrue, reason: 'an edit never un-archives');
    expect(CalendarCategories.byId(before.id), saved);
  });

  testWidgets('a built-in keeps its stored name and shows the localized '
      'label read-only', (tester) async {
    final gym = CalendarCategories.byId('gym')!;
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show(initial: gym);

    expect(robot.isBuiltInName, isTrue);
    expect(robot.builtInNameText, 'Gym');
    expect(robot.builtInCaptionShown, isTrue);
    expect(robot.canSave, isTrue);

    await robot.pickSwatch(green);
    await robot.save();

    final saved = outcome.result!;
    expect(saved.name, gym.name);
    expect(saved.colorValue, green);
    expect(saved.iconKey, gym.iconKey);
    expect(saved.isBuiltIn, isTrue);
    expect(CalendarCategories.byId('gym')!.name, gym.name);
    expect(CalendarCategories.byId('gym')!.colorValue, green);
  });

  testWidgets('initialName prefills the name and is ignored beside initial', (
    tester,
  ) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show(initialName: 'Dentist');
    expect(robot.nameText, 'Dentist');
    expect(robot.canSave, isTrue);
    await robot.close();

    final existing = await custom('Old');
    await robot.show(initial: existing, initialName: 'Dentist');
    expect(robot.nameText, 'Old');
  });

  testWidgets('Save is disabled on a blank name and enabled once something '
      'is typed', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    expect(robot.canSave, isFalse);

    await robot.typeName('   ');
    expect(robot.canSave, isFalse);

    await robot.typeName('Yoga');
    expect(robot.canSave, isTrue);

    await robot.typeName('');
    expect(robot.canSave, isFalse);
  });

  testWidgets('the duplicate warning names a visible category and never '
      'blocks Save', (tester) async {
    await custom('Strength');
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    expect(robot.warningText, isNull);

    await robot.typeName('strength');
    expect(robot.warningText, '"Strength" already exists');
    expect(robot.canSave, isTrue);

    // A built-in's localized label counts too.
    await robot.typeName('Gym');
    expect(robot.warningText, '"Gym" already exists');
    expect(robot.canSave, isTrue);

    await robot.typeName('Yoga');
    expect(robot.warningText, isNull);
  });

  testWidgets('the duplicate warning says when the match is hidden', (
    tester,
  ) async {
    await custom('Archive', hidden: true);
    final robot = CategoryEditorRobot(tester);
    await robot.show();

    await robot.typeName('Archive');

    expect(robot.warningText, '"Archive" already exists but is hidden');
    expect(robot.canSave, isTrue);
  });

  testWidgets('editing keeps its own name out of the duplicate check', (
    tester,
  ) async {
    final own = await custom('Mobility work');
    final robot = CategoryEditorRobot(tester);
    await robot.show(initial: own);

    expect(robot.warningText, isNull);
  });

  testWidgets('the counter appears from 30 characters, reads n/40 and takes '
      'the error colour at the 40-character cap', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    expect(robot.counterText, isNull);

    await robot.typeName('Yoga');
    expect(robot.counterText, isNull);

    await robot.typeName('x' * 29);
    expect(robot.counterText, isNull);

    await robot.typeName('x' * 30);
    expect(robot.counterText, '30/40');
    expect(robot.counterColor, robot.colorScheme.onSurfaceVariant);

    await robot.typeName('x' * 50);
    expect(robot.nameText.length, 40);
    expect(robot.counterText, '40/40');
    expect(robot.counterColor, robot.colorScheme.error);
  });

  testWidgets('a failed save re-enables Save and says why', (tester) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show();
    await robot.typeName('Yoga');

    writes.fail = true;
    await robot.save();

    expect(robot.isOpen, isTrue);
    expect(robot.canSave, isTrue);
    expect(robot.saveFailureShown, isTrue);
    expect(service.categories.map((c) => c.name), isNot(contains('Yoga')));

    // The next attempt goes through as if nothing had happened.
    writes.fail = false;
    await robot.save();

    expect(robot.isOpen, isFalse);
    expect(outcome.result?.name, 'Yoga');
  });

  testWidgets('the failure message is drawn over the sheet, where a finger '
      'can reach it', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    await robot.typeName('Yoga');

    writes.fail = true;
    await robot.save();

    expect(robot.saveFailureShown, isTrue);
    // Not the page's snackbar: that one is drawn under the modal barrier.
    expect(find.byType(SnackBar), findsNothing);
    expect(
      robot.saveFailureReachable,
      isTrue,
      reason: 'the bar is in the overlay, above the sheet',
    );
  });

  testWidgets('a save onto a category a pull deleted says so and hands back '
      'nothing', (tester) async {
    final existing = await custom('Yoga');
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show(initial: existing);
    await robot.typeName('Yoga flow');

    // The DAO leaves a tombstoned row alone rather than resurrecting it, so
    // the edit is lost with nothing thrown — the one failure the sheet used
    // to report as a save.
    await db.calendarCategoryDao.softDeleteById(existing.id);
    await robot.save();

    expect(robot.saveFailureShown, isTrue);
    expect(robot.isOpen, isFalse);
    expect(outcome.returned, isTrue);
    expect(
      outcome.result,
      isNull,
      reason: 'the caller would refresh against a category that does not '
          'exist, and the picker would tick a dead id into its selection',
    );
  });

  testWidgets('the close button returns null and writes nothing', (
    tester,
  ) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show();
    await robot.typeName('Yoga');

    await robot.close();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(robot.isOpen, isFalse);
    expect(service.categories.map((c) => c.name), isNot(contains('Yoga')));
  });

  testWidgets('the system back returns null and writes nothing', (
    tester,
  ) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show();
    await robot.typeName('Yoga');

    await robot.systemBack();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(service.categories.map((c) => c.name), isNot(contains('Yoga')));
  });

  testWidgets('a scrim tap returns null and writes nothing', (tester) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show();
    await robot.typeName('Yoga');

    await robot.tapBarrier();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(service.categories.map((c) => c.name), isNot(contains('Yoga')));
  });

  testWidgets('the name is focused on create and not on edit', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    expect(robot.nameFocused, isTrue);
    await robot.close();

    final existing = await custom('Old');
    await robot.show(initial: existing);
    expect(robot.nameFocused, isFalse);
  });

  testWidgets('the icon picker opens from the row and a cancelled pick '
      'changes nothing', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();

    await robot.tapIcon();
    expect(robot.iconPickerOpen, isTrue);

    await robot.cancelIconPicker();
    expect(robot.iconPickerOpen, isFalse);
    expect(robot.isOpen, isTrue);
    expect(robot.previewIcon, CalendarIcons.forKey('event'));
  });

  testWidgets('the focus is dropped before the icon picker opens and does not '
      'come back when it closes', (tester) async {
    // The route under the picker remembers a focused field as its focused
    // child and hands the focus — and the keyboard — straight back when the
    // picker closes; dropping it first is what keeps the keyboard down over
    // a sheet the user had left the field in.
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    expect(robot.nameFocused, isTrue);

    await robot.tapIcon();
    expect(robot.nameFocused, isFalse);

    await robot.cancelIconPicker();
    expect(robot.iconPickerOpen, isFalse);
    expect(robot.nameFocused, isFalse);
  });

  testWidgets('German at text scale 2.0 on 360 × 780 lays out with no layout '
      'error: the title, the text action and every row whole', (tester) async {
    // The old header broke "Kategorie erstellen" over three lines between
    // the ✕ and a filled Save; the sheet header's one line and its text
    // action keep the row at its height whatever the scale.
    const phone = Size(360, 780);
    final gym = CalendarCategories.byId('gym')!;
    final robot = CategoryEditorRobot(tester);
    final errors = await layoutErrorsDuring(() async {
      await robot.show(
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );
      expect(robot.headerTitle, 'Kategorie erstellen');
      expect(robot.saveLabel, 'Speichern');
      expect(robot.canSave, isFalse);
      // The hint and the Icon row's label wrap as far as they need and are
      // never cut.
      expect(robot.textWhole('z. B. Dehnen'), isTrue);
      expect(robot.textWhole('Symbol'), isTrue);
      // Every control inside the sheet's width, at its own height or more.
      final sheet = robot.sheetRect;
      final rects = {
        'close': robot.targetOf(SemanticsIds.categoryEditorClose),
        'save': robot.targetOf(SemanticsIds.categoryEditorSave),
        'name': robot.nameRowRect,
        'icon': robot.targetOf(SemanticsIds.categoryEditorIcon),
        'colour': robot.targetOf(SemanticsIds.swatchRow),
      };
      for (final MapEntry(key: name, value: rect) in rects.entries) {
        expect(rect.left, greaterThanOrEqualTo(sheet.left), reason: name);
        expect(rect.right, lessThanOrEqualTo(sheet.right), reason: name);
        expect(
          rect.height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
          reason: name,
        );
      }
      expect(
        robot.nameRowRect.height,
        greaterThanOrEqualTo(FormMetrics.titleRowMinHeight),
      );
      await robot.close();

      // A built-in's read row at the same scale: its label whole, the row
      // at the two-line height or more, the sheet still clear of errors.
      await robot.show(
        initial: gym,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );
      expect(robot.headerTitle, 'Kategorie bearbeiten');
      expect(robot.isBuiltInName, isTrue);
      expect(robot.textWhole(robot.builtInNameText!), isTrue);
      expect(
        robot.builtInRowRect.height,
        greaterThanOrEqualTo(FormMetrics.twoLineRowMinHeight),
      );
      expect(robot.builtInRowRect.right, lessThanOrEqualTo(sheet.right));
    });
    expect(errors, isEmpty);
  });

  testWidgets('a built-in\'s name is a read row: the avatar, the localized '
      'label, the caption, no chevron, one node and no tap', (tester) async {
    final gym = CalendarCategories.byId('gym')!;
    final robot = CategoryEditorRobot(tester);
    await robot.show(initial: gym);

    expect(robot.isBuiltInName, isTrue);
    expect(robot.builtInNameText, 'Gym');
    expect(robot.builtInCaptionShown, isTrue);
    expect(robot.previewIcon, CalendarIcons.forKey(gym.iconKey));
    expect(robot.previewColor, Color(gym.colorValue));
    // One announcement for a screen reader — the label and the caption,
    // nothing to activate — and the avatar is decoration.
    expect(robot.builtInRowIsOneNode, isTrue);
    final node = robot.builtInRowSemantics;
    expect(node.label, contains('Gym'));
    expect(node.label, contains('Built-in category'));
    expect(node.hasAction(SemanticsAction.tap), isFalse);
  });

  testWidgets('the duplicate warning is a line of the title row in the error '
      'colour, goes with the name, and Save stays enabled', (tester) async {
    await custom('Strength');
    final robot = CategoryEditorRobot(tester);
    await robot.show();

    await robot.typeName('Strength');
    expect(robot.warningText, '"Strength" already exists');
    expect(robot.warningColor, robot.colorScheme.error);
    expect(robot.canSave, isTrue);

    await robot.typeName('Strength training');
    expect(robot.warningText, isNull);
    expect(robot.canSave, isTrue);
  });

  testWidgets('the strip inside the editor never collapses, carries its ids '
      'and draws no default dot', (tester) async {
    // Enough colours of the user's own that a collapsible strip would fold
    // on a phone's width.
    final palette = await CalendarPaletteService.getInstance();
    for (var i = 0; i < 10; i++) {
      await palette.add(0xFF100000 + i * 0x010101);
    }
    final robot = CategoryEditorRobot(tester);
    await robot.show(surface: const Size(360, 780));

    expect(robot.swatches.collapsible, isFalse);
    expect(robot.swatches.isCollapsed, isFalse);
    expect(robot.swatches.hasSwatch(0xFF100000 + 9 * 0x010101), isTrue);
    expect(robot.swatches.hasDefault, isFalse);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.swatchDefault),
      findsNothing,
    );
    expect(robot.swatchRowIsContainer, isTrue);
    expect(
      robot.swatches
          .nodeOf(SemanticsIds.swatchAdd)
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(
      robot.swatches
          .nodeOf(SemanticsIds.swatchManage)
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('the avatar follows a picked swatch and a picked icon, on a '
      'built-in too', (tester) async {
    final gym = CalendarCategories.byId('gym')!;
    final robot = CategoryEditorRobot(tester);
    await robot.show(initial: gym);
    expect(robot.previewColor, Color(gym.colorValue));
    expect(robot.previewIcon, CalendarIcons.forKey(gym.iconKey));

    await robot.pickSwatch(green);
    expect(robot.previewColor, const Color(green));
    expect(robot.selectedSwatch, green);

    await robot.chooseIcon('cake');
    expect(robot.previewIcon, CalendarIcons.forKey('cake'));
    expect(robot.previewColor, const Color(green));
    expect(robot.builtInNameText, 'Gym');
  });

  testWidgets('every control is a 48 dp target at 360 × 780', (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show(surface: const Size(360, 780));

    final close = robot.targetOf(SemanticsIds.categoryEditorClose);
    expect(close.width, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
    expect(close.height, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
    final save = robot.targetOf(SemanticsIds.categoryEditorSave);
    expect(save.width, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
    expect(save.height, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
    // The whole title row is the field's target.
    expect(
      robot.nameRowRect.height,
      greaterThanOrEqualTo(FormMetrics.titleRowMinHeight),
    );
    expect(
      robot.targetOf(SemanticsIds.categoryEditorIcon).height,
      greaterThanOrEqualTo(FormMetrics.rowMinHeight),
    );
    final dots = robot.dotTargets;
    expect(dots, isNotEmpty);
    for (final dot in dots) {
      expect(dot.width, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
      expect(dot.height, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
    }
  });

  testWidgets('the ✕, Save, the name field and the Icon row carry ids', (
    tester,
  ) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();

    final close = robot.nodeOf(SemanticsIds.categoryEditorClose);
    expect(close.tooltip, 'Cancel');
    expect(close.hasAction(SemanticsAction.tap), isTrue);
    // Save is disabled, never absent, on a blank name.
    expect(
      robot.nodeOf(SemanticsIds.categoryEditorSave).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
    await robot.typeName('Yoga');
    final save = robot.nodeOf(SemanticsIds.categoryEditorSave);
    expect(save.label, 'Save');
    expect(save.hasAction(SemanticsAction.tap), isTrue);
    // The name's id is on the field itself, the node a script types into.
    expect(
      robot.nodeOf(SemanticsIds.categoryEditorName).flagsCollection.isTextField,
      isTrue,
    );
    // The Icon row is one node: glyph, label, value and the tap.
    final icon = robot.nodeOf(SemanticsIds.categoryEditorIcon);
    expect(icon.label, contains('Icon'));
    expect(icon.label, contains('Choose icon'));
    expect(icon.hasAction(SemanticsAction.tap), isTrue);
  });

  // The category's alerts (v42): drafted here, edited in the alert sheet's
  // category mode, written through the real alert service on Save.
  group('alerts', () {
    late EventAlertService alerts;

    setUp(() async {
      EventAlertService.reset();
      alerts = await EventAlertService.forTesting(db);
    });

    tearDown(EventAlertService.reset);

    CategoryAlert seeded(String id, {AlertMode mode = AlertMode.notify}) =>
        CategoryAlert(
          id: id,
          categoryId: kBirthdayCategoryId,
          mode: mode,
          offsetMinutes: 10,
          daysBefore: 1,
          dayMinute: 9 * 60,
        );

    CalendarCategory birthdays() =>
        CalendarCategories.byId(kBirthdayCategoryId)!;

    testWidgets('a seeded alert reads its all-day wording over its timed '
        'one and its tier, on a built-in too', (tester) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        seeded('a1'),
        seeded('a2', mode: AlertMode.ring),
      ]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: birthdays());

      expect(robot.alertLabels, hasLength(2));
      expect(robot.alertLabels.first, startsWith('The day before, '));
      expect(robot.alertCaptions, [
        'Timed events: 10 min before · Reminder',
        'Timed events: 10 min before · Alarm',
      ]);
      expect(robot.canAddAlert, isTrue);
      expect(robot.alertsHintShown, isTrue);
    });

    testWidgets('a new category starts with no alerts and Add alert', (
      tester,
    ) async {
      final robot = CategoryEditorRobot(tester);
      await robot.show();

      expect(robot.alertLabels, isEmpty);
      expect(robot.canAddAlert, isTrue);
    });

    testWidgets('Add alert opens the category mode of the alert sheet and '
        'Save writes the new alert under a fresh id', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final sheet = AlertSheetRobot(tester);
      final outcome = await robot.show(initial: birthdays());

      await robot.addAlert();
      expect(sheet.whenRowLabels, ['Timed events', 'All-day events']);
      expect(sheet.removeAlertVisible, isFalse);
      await sheet.chooseAllDayPreset('The day before');
      await sheet.save();
      expect(robot.alertLabels, hasLength(1));

      await robot.save();

      expect(outcome.result?.id, kBirthdayCategoryId);
      final stored = EventAlerts.categoryAlertsFor(kBirthdayCategoryId);
      expect(stored, hasLength(1));
      expect(stored.single.daysBefore, 1);
      expect(stored.single.categoryId, kBirthdayCategoryId);
      expect(stored.single.id, isNot(isEmpty));
    });

    testWidgets('a created category takes its alerts under its new id', (
      tester,
    ) async {
      final robot = CategoryEditorRobot(tester);
      final sheet = AlertSheetRobot(tester);
      final outcome = await robot.show();

      await robot.typeName('Training');
      await robot.addAlert();
      await sheet.save();
      await robot.save();

      final created = outcome.result!;
      expect(EventAlerts.categoryAlertsFor(created.id), hasLength(1));
      expect(
        EventAlerts.categoryAlertsFor(created.id).single.categoryId,
        created.id,
      );
    });

    testWidgets('editing a row writes what the sheet hands back', (
      tester,
    ) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [seeded('a1')]);
      final robot = CategoryEditorRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await robot.show(initial: birthdays());

      await robot.editAlert(0);
      await sheet.choosePreset('30 min before');
      await sheet.save();
      expect(robot.alertCaptions.single, startsWith('Timed events: 30 min'));
      await robot.save();

      final stored = EventAlerts.categoryAlertsFor(kBirthdayCategoryId).single;
      expect(stored.id, 'a1');
      expect(stored.offsetMinutes, 30);
    });

    testWidgets('the alert sheet\'s Remove removes a row, and Save tombstones '
        'it', (tester) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        seeded('a1'),
        seeded('a2'),
      ]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: birthdays());
      expect(robot.alertRowsHaveRemove, isFalse);

      await robot.removeAlert(0);
      expect(robot.alertLabels, hasLength(1));
      await robot.save();

      expect(
        EventAlerts.categoryAlertsFor(
          kBirthdayCategoryId,
        ).map((alert) => alert.id),
        ['a2'],
      );
    });

    testWidgets('an alert that arrived under the open sheet survives Save', (
      tester,
    ) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [seeded('a1')]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: birthdays());
      expect(robot.alertLabels, hasLength(1));

      // Another device's alert for this category, applied by a pull while the
      // sheet is up — so it was never on screen here.
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        seeded('a1'),
        seeded('a2'),
      ]);
      await alerts.reload();

      await robot.removeAlert(0);
      await robot.save();
      // Read back from the table, not from the cache the save republished:
      // the row itself must still be live.
      await alerts.reload();

      expect(
        EventAlerts.categoryAlertsFor(
          kBirthdayCategoryId,
        ).map((alert) => alert.id),
        ['a2'],
      );
    });

    testWidgets('Add alert leaves at the cap', (tester) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        for (var i = 0; i < kMaxAlertsPerCategory; i++) seeded('a$i'),
      ]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: birthdays());

      expect(robot.alertLabels, hasLength(kMaxAlertsPerCategory));
      expect(robot.canAddAlert, isFalse);

      await robot.removeAlert(0);
      expect(robot.canAddAlert, isTrue);
    });

    testWidgets('a closed sheet writes no alert', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await robot.show(initial: birthdays());

      await robot.addAlert();
      await sheet.save();
      await robot.close();

      expect(EventAlerts.categoryAlertsFor(kBirthdayCategoryId), isEmpty);
    });

    testWidgets('a failed alert write keeps the sheet open, says so, and the '
        'retry writes one category', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final sheet = AlertSheetRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Training');
      await robot.addAlert();
      await sheet.save();

      writes
        ..fail = true
        ..failOnly = 'calendar_category_alerts';
      await robot.save();

      expect(robot.isOpen, isTrue);
      expect(robot.canSave, isTrue);
      expect(robot.saveFailureShown, isTrue);

      writes.fail = false;
      await robot.save();

      expect(robot.isOpen, isFalse);
      final created = outcome.result!;
      expect(
        service.categories.where((c) => c.name == 'Training'),
        hasLength(1),
      );
      expect(EventAlerts.categoryAlertsFor(created.id), hasLength(1));
    });

    testWidgets('after a failed alert write ✕ hands back the category the '
        'save did write', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final sheet = AlertSheetRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Training');
      await robot.addAlert();
      await sheet.save();
      writes
        ..fail = true
        ..failOnly = 'calendar_category_alerts';
      await robot.save();
      expect(robot.isOpen, isTrue);

      await robot.close();

      expect(robot.isOpen, isFalse);
      final stored = service.categories.singleWhere(
        (c) => c.name == 'Training',
      );
      expect(outcome.result, stored);
    });

    testWidgets('a row\'s switch is the category\'s own on / off for the '
        'alert, and Save writes it', (tester) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        seeded('a1'),
        seeded('a2'),
      ]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: birthdays());
      expect(robot.alertSwitches, [true, true]);

      await robot.toggleAlert(1);
      expect(robot.alertSwitches, [true, false]);
      expect(robot.alertLabels, hasLength(2));
      await robot.save();

      final stored = EventAlerts.categoryAlertsFor(kBirthdayCategoryId);
      expect(stored.map((alert) => (alert.id, alert.enabled)), [
        ('a1', true),
        ('a2', false),
      ]);
    });

    testWidgets('a paused alert opens off and is switched back on', (
      tester,
    ) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        seeded('a1').copyWith(enabled: false),
      ]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: birthdays());
      expect(robot.alertSwitches, [false]);

      await robot.toggleAlert(0);
      await robot.save();

      expect(
        EventAlerts.categoryAlertsFor(kBirthdayCategoryId).single.enabled,
        isTrue,
      );
    });

    group('what the calendar is told', () {
      late CalendarBloc bloc;
      late _RecordingObserver observer;
      late BlocObserver previousObserver;

      setUp(() {
        previousObserver = Bloc.observer;
        observer = _RecordingObserver();
        Bloc.observer = observer;
        bloc = CalendarBloc(
          service: Completer<CalendarEventService>().future,
          alertReconciler: (_, _) async {},
          alertWriter: (_, _, {knownIds}) async {},
        );
      });

      tearDown(() async {
        await bloc.close();
        Bloc.observer = previousObserver;
      });

      testWidgets('a save that wrote the alerts announces it once', (
        tester,
      ) async {
        final robot = CategoryEditorRobot(tester);
        final sheet = AlertSheetRobot(tester);
        await robot.show(initial: birthdays(), bloc: bloc);

        await robot.addAlert();
        await sheet.save();
        await robot.save();

        expect(
          observer.events.whereType<CategoryAlertsChanged>(),
          hasLength(1),
        );
      });

      testWidgets('a save that left the alerts alone says nothing', (
        tester,
      ) async {
        final robot = CategoryEditorRobot(tester);
        await robot.show(initial: birthdays(), bloc: bloc);

        await robot.pickSwatch(green);
        await robot.save();

        expect(robot.isOpen, isFalse);
        expect(observer.events.whereType<CategoryAlertsChanged>(), isEmpty);
      });

      testWidgets('a failed alert write says nothing', (tester) async {
        final robot = CategoryEditorRobot(tester);
        final sheet = AlertSheetRobot(tester);
        await robot.show(initial: birthdays(), bloc: bloc);
        await robot.addAlert();
        await sheet.save();
        writes
          ..fail = true
          ..failOnly = 'calendar_category_alerts';

        await robot.save();

        expect(robot.isOpen, isTrue);
        expect(observer.events.whereType<CategoryAlertsChanged>(), isEmpty);
      });
    });

    group('the permission check', () {
      late FakePermissionGateway gateway;

      setUp(() async {
        // Asked once already: the check then only says whether the alert
        // can ring, with no prompt in the way.
        await (await SettingsService.getInstance()).setAlertNotificationsAsked(
          true,
        );
        gateway = FakePermissionGateway(
          statuses: {
            AppPermission.notifications: PermissionStatus.granted,
            AppPermission.exactAlarms: PermissionStatus.denied,
            AppPermission.fullScreenIntent: PermissionStatus.granted,
            AppPermission.batteryOptimization: PermissionStatus.granted,
          },
        );
        final permissions = permissionServiceOver(gateway);
        GetIt.I.registerSingleton<PermissionService>(permissions);
        addTearDown(() async {
          await GetIt.I.unregister<PermissionService>();
          await permissions.dispose();
        });
      });

      Finder blocked() =>
          find.text("This can't ring until a permission is turned on");

      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      testWidgets('an enabled alert saved where it cannot ring says so', (
        tester,
      ) async {
        final robot = CategoryEditorRobot(tester);
        final sheet = AlertSheetRobot(tester);
        await robot.show(initial: birthdays());

        await robot.addAlert();
        await sheet.save();
        await robot.save();
        await settle(tester);

        expect(robot.isOpen, isFalse);
        expect(blocked(), findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
      });

      testWidgets('only paused alerts, or untouched ones, ask nothing', (
        tester,
      ) async {
        await alerts.replaceForCategory(kBirthdayCategoryId, [seeded('a1')]);
        final robot = CategoryEditorRobot(tester);
        await robot.show(initial: birthdays());

        await robot.toggleAlert(0);
        await robot.save();
        await settle(tester);
        expect(blocked(), findsNothing);

        await robot.show(initial: birthdays());
        await robot.pickSwatch(green);
        await robot.save();
        await settle(tester);
        expect(blocked(), findsNothing);
      });
    });

    testWidgets('German at text scale 2.0 on 360 × 780 lays two alert rows '
        'out whole, each at a height its switch never moves', (tester) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [
        seeded('a1'),
        seeded('a2', mode: AlertMode.ring),
      ]);
      final robot = CategoryEditorRobot(tester);
      await robot.show(
        initial: birthdays(),
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(360, 780),
      );

      expect(tester.takeException(), isNull);
      expect(robot.alertLabels, hasLength(2));
      final heights = robot.alertRowHeights;
      for (final height in heights) {
        expect(height, greaterThanOrEqualTo(FormMetrics.rowMinHeight));
      }

      await robot.toggleAlert(0);
      await robot.toggleAlert(1);

      expect(tester.takeException(), isNull);
      expect(robot.alertSwitches, [false, false]);
      expect(robot.alertRowHeights, heights);
    });
  });
}

class _RecordingObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}

/// Fails every write on demand — or only the ones whose statement names
/// [failOnly] — so a save can be made to fail without closing the database
/// under the sheet.
class _WriteFailure extends QueryInterceptor {
  bool fail = false;
  String? failOnly;

  bool _fails(String statement) =>
      fail && (failOnly == null || statement.contains(failOnly!));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_fails(statement)) return Future.error(StateError('the write failed'));
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_fails(statement)) return Future.error(StateError('the write failed'));
    return super.runUpdate(executor, statement, args);
  }
}
