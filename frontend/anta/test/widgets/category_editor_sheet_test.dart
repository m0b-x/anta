import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/category_name.dart';
import 'package:anta/constants/category_profiles.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_profile_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/form_rows.dart' show FormSwitchRow;
import 'package:anta/widgets/form_sheet_frame.dart'
    show FormSheetSemanticsRefresh;

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';
import 'support/alert_sheet_robot.dart';
import 'support/category_editor_robot.dart';
import 'support/category_goal_robot.dart';
import 'support/category_kind_robot.dart';
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
    writes.release();
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

  testWidgets('an initialName over the limit is clamped to it and Save '
      'stores the clamped name', (tester) async {
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show(initialName: 'x' * 60);

    expect(robot.nameText, 'x' * kCategoryNameMaxLength);
    expect(
      robot.counterText,
      '$kCategoryNameMaxLength/$kCategoryNameMaxLength',
    );

    await robot.save();

    expect(outcome.result!.name, 'x' * kCategoryNameMaxLength);
    expect(
      CalendarCategories.byId(outcome.result!.id)!.name,
      'x' * kCategoryNameMaxLength,
    );
  });

  testWidgets('the clamp counts graphemes, as the field does: an emoji name '
      'keeps whole glyphs', (tester) async {
    // Four code units per grapheme: a code-unit cut would hand the field ten
    // glyphs and could end on half a surrogate pair.
    const glyph = '👍🏽';
    final robot = CategoryEditorRobot(tester);
    final outcome = await robot.show(initialName: glyph * 60);

    expect(robot.nameText, glyph * kCategoryNameMaxLength);
    expect(robot.nameText.characters.length, kCategoryNameMaxLength);
    expect(
      robot.counterText,
      '$kCategoryNameMaxLength/$kCategoryNameMaxLength',
    );

    await robot.save();

    expect(outcome.result!.name, glyph * kCategoryNameMaxLength);
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
      reason:
          'the caller would refresh against a category that does not '
          'exist, and the picker would tick a dead id into its selection',
    );
  });

  group('leaving', () {
    List<String> names() => [for (final c in service.categories) c.name];

    testWidgets('✕ on a clean create leaves at once with null', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      final before = names();

      await robot.close();

      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(robot.isOpen, isFalse);
      expect(names(), before);
    });

    testWidgets('✕ on a typed name asks, and Discard returns null and writes '
        'nothing', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');

      await robot.close();

      expect(robot.discardAsked, isTrue);
      expect(robot.isOpen, isTrue);
      expect(outcome.returned, isFalse);

      await robot.discard();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(robot.isOpen, isFalse);
      expect(names(), isNot(contains('Yoga')));
    });

    testWidgets('✕ on an edit whose colour changed asks', (tester) async {
      final existing = await custom('Old');
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: existing);
      await robot.pickSwatch(green);

      await robot.close();

      expect(robot.discardAsked, isTrue);
      await robot.discard();
      expect(outcome.result, isNull);
      expect(CalendarCategories.byId(existing.id), existing);
    });

    testWidgets('the system back on a dirty sheet asks, and Discard returns '
        'null and writes nothing', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');

      await robot.systemBack();

      expect(robot.discardAsked, isTrue);
      expect(outcome.returned, isFalse);
      await robot.discard();
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(names(), isNot(contains('Yoga')));
    });

    testWidgets('a scrim tap on a clean sheet leaves at once with null and '
        'writes nothing', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      final before = names();

      await robot.tapBarrier();

      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(names(), before);
    });

    testWidgets('a scrim tap on a dirty sheet asks: Keep editing keeps the '
        'sheet and its text, Discard returns null and writes nothing', (
      tester,
    ) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');

      await robot.tapBarrier();
      expect(robot.discardAsked, isTrue);

      await robot.keepEditing();
      expect(robot.discardAsked, isFalse);
      expect(robot.isOpen, isTrue);
      expect(robot.nameText, 'Yoga');
      expect(outcome.returned, isFalse);

      await robot.tapBarrier();
      await robot.discard();
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(names(), isNot(contains('Yoga')));
    });

    testWidgets('a create opened with the picker\'s typed text is clean until '
        'something changes', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initialName: 'Pil');

      await robot.close();

      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    });

    testWidgets('Save pops with the category and asks nothing', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');

      await robot.save();

      expect(robot.discardAsked, isFalse);
      expect(robot.isOpen, isFalse);
      expect(outcome.result?.name, 'Yoga');
    });

    testWidgets('a dismissing fling on a dirty sheet snaps back and asks: '
        'Keep editing leaves the sheet where it was', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');
      final top = robot.handleTop;

      await robot.flingDown();

      expect(robot.discardAsked, isTrue);
      expect(robot.handleTop, top, reason: 'asked over a sheet at rest');
      expect(outcome.returned, isFalse);

      await robot.keepEditing();

      expect(robot.isOpen, isTrue);
      expect(robot.handleTop, top);
      expect(robot.nameText, 'Yoga');
      expect(outcome.returned, isFalse);
    });

    testWidgets('a dismissing fling on a clean sheet leaves at once with '
        'null', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      final before = names();

      await robot.flingDown();

      expect(robot.discardAsked, isFalse);
      expect(robot.isOpen, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(names(), before);
    });

    testWidgets('a picker\'s text over the limit is clean on open: the clamp '
        'runs before the opened draft is taken', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initialName: 'x' * 60);
      expect(robot.nameText, 'x' * kCategoryNameMaxLength);

      await robot.close();

      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    });

    testWidgets('✕ while a dismissing drag snaps back asks once: the drag\'s '
        'own ask finds the question up', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');

      await robot.closeDuringSnapBack();

      expect(robot.discardQuestions, 1);
      await robot.discard();
      expect(robot.isOpen, isFalse);
      expect(outcome.result, isNull);
    });

    testWidgets('while Save writes, ✕ is disabled and neither back nor the '
        'barrier asks; the save then pops with what it wrote', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');
      writes.holdNext('calendar_categories');

      await robot.save();

      expect(writes.held, isTrue, reason: 'create reads MAX(sort_order)');
      expect(robot.closeEnabled, isFalse);
      await robot.close();
      // Read after each one: a question back opened would be dismissed by
      // the barrier tap that follows it.
      await robot.systemBack();
      expect(robot.discardAsked, isFalse, reason: 'back');
      await robot.tapBarrier();
      expect(robot.discardAsked, isFalse, reason: 'the barrier');
      expect(robot.isOpen, isTrue);
      expect(outcome.returned, isFalse);

      writes.release();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(robot.isOpen, isFalse);
      expect(robot.saveFailureShown, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result?.name, 'Yoga');
      expect(names(), contains('Yoga'));
    });
  });

  testWidgets('the content-tall sheet refreshes its semantics, since a '
      "sub-sheet's answer resizes it while that route leaves", (tester) async {
    final robot = CategoryEditorRobot(tester);
    await robot.show();
    expect(find.byType(FormSheetSemanticsRefresh), findsOneWidget);
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
      expect(robot.discardAsked, isTrue);
      await robot.discard();

      expect(EventAlerts.categoryAlertsFor(kBirthdayCategoryId), isEmpty);
    });

    testWidgets('an alert switched off and on again leaves the sheet clean', (
      tester,
    ) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [seeded('a1')]);
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: birthdays());

      await robot.toggleAlert(0);
      await robot.toggleAlert(0);
      await robot.close();

      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
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

    testWidgets('after a failed alert write ✕ asks for the alert the save '
        'did not store, and Discard hands back the category it did write', (
      tester,
    ) async {
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

      expect(robot.discardAsked, isTrue);
      expect(outcome.returned, isFalse);

      await robot.discard();

      expect(robot.isOpen, isFalse);
      final stored = service.categories.singleWhere(
        (c) => c.name == 'Training',
      );
      expect(outcome.result, stored);
      expect(EventAlerts.categoryAlertsFor(stored.id), isEmpty);
    });

    testWidgets('after a failed alert write that left the stored alerts as '
        'drafted, ✕ hands back the written category at once', (tester) async {
      await alerts.replaceForCategory(kBirthdayCategoryId, [seeded('a1')]);
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: birthdays());
      await robot.pickSwatch(green);
      // Touched but equal by value: the write is attempted, and its own read
      // is what fails, since an unchanged row is never written.
      await robot.toggleAlert(0);
      await robot.toggleAlert(0);
      writes.failNext('calendar_category_alerts');
      await robot.save();
      expect(robot.isOpen, isTrue);
      expect(robot.saveFailureShown, isTrue);

      await robot.close();

      expect(robot.discardAsked, isFalse);
      expect(robot.isOpen, isFalse);
      expect(outcome.result?.colorValue, green);
      expect(outcome.result, CalendarCategories.byId(kBirthdayCategoryId));
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

      // The calendar guide's demos: Save validates and hands back what it
      // would have written, and nothing reaches the service, the alert
      // table or the calendar — the guard against a write path added later.
      testWidgets('sandbox: Save returns the would-be category and writes '
          'nothing', (tester) async {
        final before = [...service.categories];
        final settings = await SettingsService.getInstance();
        await settings.recordRecentIconKey('directions_run');
        final robot = CategoryEditorRobot(tester);
        final sheet = AlertSheetRobot(tester);
        final outcome = await robot.show(bloc: bloc, sandbox: true);

        expect(robot.swatches.hasAdd, isFalse);
        expect(robot.swatches.hasManage, isFalse);
        expect(robot.canSave, isFalse);
        await robot.typeName('  Practice  ');
        await robot.pickSwatch(green);
        await robot.chooseIcon('cake');
        // The picker swallows a failed recent-icon write, so the icon pick is
        // proven by the recent list below and the interceptor arms after it.
        expect(await settings.getRecentIconKeys(), ['directions_run']);
        writes.fail = true;
        await robot.addAlert();
        await sheet.save();
        await robot.toggleAlert(0);
        expect(robot.alertSwitches, [false]);
        await robot.save();

        expect(outcome.returned, isTrue);
        expect(robot.isOpen, isFalse);
        final draft = outcome.result!;
        expect(draft.name, 'Practice');
        expect(draft.colorValue, green);
        expect(draft.iconKey, 'cake');
        expect(draft.isBuiltIn, isFalse);
        expect(draft.id, isNot(isEmpty));
        expect(service.categories, before);
        expect(CalendarCategories.byId(draft.id), isNull);
        expect(EventAlerts.categoryAlertsFor(draft.id), isEmpty);
        expect(observer.events, isEmpty);
      });

      testWidgets('sandbox: an edit returns the changed category and leaves '
          'the stored one alone', (tester) async {
        final stored = birthdays();
        final robot = CategoryEditorRobot(tester);
        final outcome = await robot.show(
          initial: stored,
          bloc: bloc,
          sandbox: true,
        );

        await robot.pickSwatch(green);
        await robot.save();

        expect(outcome.result?.id, kBirthdayCategoryId);
        expect(outcome.result?.colorValue, green);
        expect(outcome.result?.name, stored.name);
        expect(CalendarCategories.byId(kBirthdayCategoryId), stored);
        expect(observer.events, isEmpty);
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

  // The analytics profile (S3): two sections under the alerts, drafted here
  // and in the kind picker and the goal sheet, written through the real
  // profile service on Save.
  group('profile', () {
    late CategoryProfileService profiles;

    const kind = SemanticsIds.categoryEditorKind;
    const mark = SemanticsIds.categoryEditorMark;
    const area = SemanticsIds.categoryEditorArea;
    const measure = SemanticsIds.categoryEditorMeasure;
    const countsAs = SemanticsIds.categoryEditorCountsAs;
    const goal = SemanticsIds.categoryEditorGoal;

    setUp(() async {
      CategoryProfileService.reset();
      profiles = await CategoryProfileService.forTesting(db);
    });

    tearDown(CategoryProfileService.reset);

    /// A custom category holding [profile], or none.
    Future<CalendarCategory> profiled(
      String name, {
      CategoryKind? as,
      LifeArea? area,
      ReportMeasure? measure,
      int? nominalMinutes,
      String? markVerb,
      ReportTarget? target,
    }) async {
      final category = await custom(name);
      if (as != null) {
        await profiles.save(
          CategoryProfile(
            id: '',
            categoryId: category.id,
            kind: as,
            area: area,
            measure: measure,
            nominalMinutes: nominalMinutes,
            markVerb: markVerb,
            target: target,
          ),
        );
      }
      return category;
    }

    const weekly3 = ReportTarget(
      kind: TargetKind.atLeast,
      value: 3,
      period: TargetPeriod.week,
    );

    testWidgets('an unprofiled category reads today\'s editor and then the '
        'six rows in their default state', (tester) async {
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: await profiled('Stretching'));

      expect(robot.sectionLabels, ['Alerts', 'Report', 'Measure & goal']);
      expect(robot.valueOf(kind), 'Custom');
      expect(robot.captionOf(kind), 'Anything else');
      expect(robot.valueOf(mark), 'Off');
      expect(robot.captionOf(mark), isNull);
      expect(robot.valueOf(area), 'Other');
      expect(robot.captionOf(area), isNull);
      expect(robot.valueOf(measure), 'Auto');
      expect(robot.captionOf(measure), 'Auto picks per period');
      expect(robot.valueOf(countsAs), 'Off');
      expect(robot.captionOf(countsAs), 'For untimed events');
      expect(robot.valueOf(goal), isNull);
      expect(robot.captionOf(goal), 'Pick a measure first');
      // Disabled in place, never hidden: Custom on Auto has no unit.
      expect(robot.enabledOf(goal), isFalse);
      for (final id in CategoryEditorRobot.profileRowIds.take(5)) {
        expect(robot.enabledOf(id), isTrue, reason: id);
      }
      // The new sections come after everything the editor had.
      expect(
        robot.targetOf(kind).top,
        greaterThan(robot.targetOf(SemanticsIds.categoryAlertAdd).bottom),
      );
      // Opening and closing an unprofiled sheet writes no profile.
      await robot.close();
      expect(CategoryProfiles.all, isEmpty);
    });

    testWidgets('a kind pick fills the rows from the kind and Save stores the '
        'kind alone through the service', (tester) async {
      final category = await profiled('Gym days');
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: category);

      await robot.pickKind(CategoryKind.workout);

      expect(robot.valueOf(kind), 'Workout');
      expect(robot.captionOf(kind), 'Gym, run, swim, class');
      expect(robot.valueOf(mark), 'Attended');
      expect(robot.valueOf(area), 'Health');
      expect(robot.valueOf(measure), 'Auto');
      expect(robot.captionOf(measure), 'Auto is Attendance');
      expect(robot.valueOf(countsAs), 'Off');
      expect(robot.captionOf(countsAs), 'Suggested: 1 h');
      expect(robot.enabledOf(goal), isTrue);
      expect(robot.captionOf(goal), 'No goal');
      // Nothing stored until Save.
      expect(CategoryProfiles.profileFor(category.id), isNull);

      await robot.save();

      expect(outcome.result?.id, category.id);
      final stored = CategoryProfiles.profileFor(category.id)!;
      expect(stored.kind, CategoryKind.workout);
      expect(stored.hasOverrides, isFalse);
    });

    testWidgets('the menus write the draft and Save persists every override', (
      tester,
    ) async {
      final category = await profiled('Gym days', as: CategoryKind.workout);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);

      await robot.pick(area, SemanticsIds.categoryArea('people'));
      expect(robot.valueOf(area), 'People');

      await robot.tapRow(measure);
      // Auto names what it stands for and is not offered twice.
      expect(robot.menuItems.keys, [
        SemanticsIds.categoryMeasureAuto,
        for (final name in [
          'count',
          'events',
          'hours',
          'tasks',
          'money',
          'lastSeen',
          'daysUntil',
        ])
          SemanticsIds.categoryMeasure(name),
      ]);
      expect(
        robot.menuItems[SemanticsIds.categoryMeasureAuto],
        'Auto · Attendance',
      );
      expect(robot.checkedMenuItem, SemanticsIds.categoryMeasureAuto);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.categoryMeasure('hours')),
      );
      await tester.pumpAndSettle();
      expect(robot.valueOf(measure), 'Hours');
      expect(robot.captionOf(measure), 'Auto is Attendance');

      await robot.tapRow(countsAs);
      expect(
        robot.menuItems[SemanticsIds.categoryCountsAs(60)],
        '1 h · suggested',
      );
      expect(robot.menuItems[SemanticsIds.categoryCountsAs(30)], '30 min');
      expect(robot.checkedMenuItem, SemanticsIds.categoryCountsAsOff);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.categoryCountsAs(30)),
      );
      await tester.pumpAndSettle();
      expect(robot.valueOf(countsAs), '30 min');

      await robot.save();

      final stored = CategoryProfiles.profileFor(category.id)!;
      expect(stored.kind, CategoryKind.workout);
      expect(stored.area, LifeArea.people);
      expect(stored.measure, ReportMeasure.hours);
      expect(stored.nominalMinutes, 30);
    });

    testWidgets('a kind pick resets the area, measure and mark, keeps the '
        'counts-as and a goal that still fits, and drops one that does not', (
      tester,
    ) async {
      final category = await profiled(
        'Gym days',
        as: CategoryKind.workout,
        area: LifeArea.work,
        measure: ReportMeasure.events,
        markVerb: 'Lifted',
        nominalMinutes: 60,
        target: weekly3,
      );
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);
      expect(robot.valueOf(area), 'Work');
      expect(robot.valueOf(mark), 'Lifted');
      expect(robot.captionOf(goal), 'At least 3 a week');

      // Routine leads with Attendance, a count like Events: the goal stays.
      await robot.pickKind(CategoryKind.routine);
      expect(robot.valueOf(area), 'Health');
      expect(robot.valueOf(measure), 'Auto');
      expect(robot.valueOf(mark), 'Done');
      expect(robot.valueOf(countsAs), '1 h');
      expect(robot.captionOf(goal), 'At least 3 a week');

      // Work leads with Hours: three occurrences are not three hours.
      await robot.pickKind(CategoryKind.work);
      expect(robot.valueOf(mark), 'Off');
      expect(robot.valueOf(countsAs), '1 h');
      expect(robot.captionOf(goal), 'No goal');

      await robot.save();
      final stored = CategoryProfiles.profileFor(category.id)!;
      expect(stored.kind, CategoryKind.work);
      expect(stored.area, isNull);
      expect(stored.measure, isNull);
      expect(stored.markVerb, isNull);
      expect(stored.nominalMinutes, 60);
      expect(stored.target, isNull);
    });

    testWidgets('a measure pick that changes the goal\'s unit clears it', (
      tester,
    ) async {
      final category = await profiled(
        'Gym days',
        as: CategoryKind.workout,
        target: weekly3,
      );
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);

      await robot.pick(measure, SemanticsIds.categoryMeasure('events'));
      expect(robot.captionOf(goal), 'At least 3 a week');

      await robot.pick(measure, SemanticsIds.categoryMeasure('money'));
      expect(robot.captionOf(goal), 'No goal');
    });

    testWidgets('Counts as is disabled with its reason under Sleep, its value '
        'still shown', (tester) async {
      final category = await profiled(
        'Nights',
        as: CategoryKind.sleep,
        nominalMinutes: 480,
      );
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);

      expect(robot.enabledOf(countsAs), isFalse);
      expect(robot.valueOf(countsAs), '8 h');
      expect(robot.captionOf(countsAs), 'Sleep keeps its own hours');
      expect(
        robot.nodeOf(countsAs).flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      // The menu does not open.
      await robot.tapRow(countsAs);
      expect(robot.menuItems, isEmpty);
    });

    testWidgets('Counts as is disabled with its reason when every event of '
        'the category is a plain repeat', (tester) async {
      final category = await profiled('Standup', as: CategoryKind.meeting);
      final bloc = CalendarBloc(
        service: Completer<CalendarEventService>().future,
        alertReconciler: (_, _) async {},
        alertWriter: (_, _, {knownIds}) async {},
      );
      addTearDown(bloc.close);
      CalendarEvent event(String id, RecurrenceRule rule) => CalendarEvent(
        id: id,
        title: id,
        categoryId: category.id,
        startDate: DateTime.utc(2026, 9, 1),
        rule: rule,
      );
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        CalendarPageLoaded(
          allEvents: [
            event('a', const DailyRecurrence()),
            event('b', const DailyRecurrence(interval: 2)),
          ],
          focusedDay: DateTime(2026, 9, 1),
          selectedDay: DateTime(2026, 9, 1),
        ),
      );
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category, bloc: bloc);

      expect(robot.enabledOf(countsAs), isFalse);
      expect(robot.captionOf(countsAs), 'Repeats earn no counted hours');
      await robot.close();

      // One dated event among them, and the hours can count.
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        CalendarPageLoaded(
          allEvents: [
            event('a', const DailyRecurrence()),
            event('c', const OneTimeRecurrence()),
          ],
          focusedDay: DateTime(2026, 9, 2),
          selectedDay: DateTime(2026, 9, 2),
        ),
      );
      await robot.show(initial: category, bloc: bloc);
      expect(robot.enabledOf(countsAs), isTrue);
      expect(robot.captionOf(countsAs), 'Suggested: 30 min');
      await robot.close();

      // A partner's dated event in the category shapes none of my profile
      // (share surfaces D15): mine are still all repeats.
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        CalendarPageLoaded(
          allEvents: [
            event('a', const DailyRecurrence()),
            CalendarEvent(
              id: 'theirs',
              title: 'theirs',
              categoryId: category.id,
              startDate: DateTime.utc(2026, 9, 1),
              fromPartner: true,
            ),
          ],
          focusedDay: DateTime(2026, 9, 3),
          selectedDay: DateTime(2026, 9, 3),
        ),
      );
      await robot.show(initial: category, bloc: bloc);
      expect(robot.enabledOf(countsAs), isFalse);
      expect(robot.captionOf(countsAs), 'Repeats earn no counted hours');
    });

    testWidgets('the Goal row is disabled with its reason when the primary '
        'takes no goal, and stays reachable when a goal is stored', (
      tester,
    ) async {
      final robot = CategoryEditorRobot(tester);
      await robot.show(
        initial: await profiled('Passport', as: CategoryKind.expiry),
      );
      expect(robot.enabledOf(goal), isFalse);
      expect(robot.captionOf(goal), 'No goal for Days until');
      expect(robot.nodeOf(goal).flagsCollection.isEnabled, Tristate.isFalse);
      await robot.close();

      await robot.show(
        initial: await profiled(
          'Renewals',
          as: CategoryKind.expiry,
          target: const ReportTarget(kind: TargetKind.maxGap, value: 30),
        ),
      );
      expect(robot.enabledOf(goal), isTrue);
      expect(robot.captionOf(goal), 'At most 30 days between');
    });

    testWidgets('the goal sheet\'s Done lands in the Goal caption and Save '
        'stores it; Remove goal clears it', (tester) async {
      final category = await profiled('Gym days', as: CategoryKind.workout);
      final robot = CategoryEditorRobot(tester);
      final goalSheet = CategoryGoalRobot(tester);
      await robot.show(initial: category);

      await robot.tapRow(goal);
      expect(goalSheet.isOpen, isTrue);
      expect(goalSheet.removeShown, isFalse);
      await goalSheet.done();
      expect(robot.captionOf(goal), 'At least 3 a week');

      await robot.save();
      expect(CategoryProfiles.profileFor(category.id)!.target, weekly3);

      await robot.show(initial: CalendarCategories.byId(category.id)!);
      await robot.tapRow(goal);
      expect(goalSheet.removeShown, isTrue);
      await goalSheet.remove();
      expect(robot.captionOf(goal), 'No goal');
      await robot.save();
      expect(CategoryProfiles.profileFor(category.id)!.target, isNull);
    });

    testWidgets('the Mark menu: the kind\'s verb, the owner\'s word through '
        'the dialog, and Off', (tester) async {
      final category = await profiled('Walks', as: CategoryKind.routine);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);

      await robot.tapRow(mark);
      expect(robot.menuItems, {
        SemanticsIds.categoryMarkKind: 'Done',
        SemanticsIds.categoryMarkOwn: 'Own word…',
        SemanticsIds.categoryMarkOff: 'Off',
      });
      expect(robot.checkedMenuItem, SemanticsIds.categoryMarkKind);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await robot.setMarkWord('  Walked  ');
      expect(robot.valueOf(mark), 'Walked');
      await robot.tapRow(mark);
      expect(robot.menuItems[SemanticsIds.categoryMarkOwn], 'Walked');
      expect(robot.checkedMenuItem, SemanticsIds.categoryMarkOwn);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await robot.save();
      expect(CategoryProfiles.profileFor(category.id)!.markVerb, 'Walked');

      // The kind's own word typed back is no override; Off on a marking
      // kind stores the empty word.
      await robot.show(initial: CalendarCategories.byId(category.id)!);
      await robot.setMarkWord('Done');
      expect(robot.valueOf(mark), 'Done');
      await robot.save();
      expect(CategoryProfiles.profileFor(category.id)!.markVerb, isNull);

      await robot.show(initial: CalendarCategories.byId(category.id)!);
      await robot.pick(mark, SemanticsIds.categoryMarkOff);
      expect(robot.valueOf(mark), 'Off');
      await robot.save();
      expect(CategoryProfiles.profileFor(category.id)!.markVerb, '');
    });

    testWidgets('Save writes the category, then the profile, then the '
        'alerts', (tester) async {
      EventAlertService.reset();
      await EventAlertService.forTesting(db);
      addTearDown(EventAlertService.reset);
      final robot = CategoryEditorRobot(tester);
      final alertSheet = AlertSheetRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Training');
      await robot.pickKind(CategoryKind.workout);
      await robot.addAlert();
      await alertSheet.save();
      writes.statements.clear();

      await robot.save();

      int first(String table) =>
          writes.statements.indexWhere((s) => s.contains('"$table"'));
      final category = first('calendar_categories');
      final profile = first('calendar_category_profiles');
      final alerts = first('calendar_category_alerts');
      expect(category, isNonNegative);
      expect(profile, greaterThan(category));
      expect(alerts, greaterThan(profile));
      // A new category's profile is keyed to the id its create minted.
      expect(
        CategoryProfiles.profileFor(outcome.result!.id)!.kind,
        CategoryKind.workout,
      );
    });

    testWidgets('a failed profile write keeps the sheet open, says so, and '
        '✕ hands back the category the save did write', (tester) async {
      final category = await profiled('Gym days');
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: category);
      await robot.pickKind(CategoryKind.workout);

      writes
        ..fail = true
        ..failOnly = 'calendar_category_profiles';
      await robot.save();

      expect(robot.isOpen, isTrue);
      expect(robot.saveFailureShown, isTrue);
      expect(CategoryProfiles.profileFor(category.id), isNull);

      // The draft still holds what was not stored: ✕ asks first.
      writes.fail = false;
      await robot.close();
      expect(robot.discardAsked, isTrue);
      await robot.discard();
      expect(outcome.result?.id, category.id);
    });

    testWidgets('a failed profile write skips the alerts\' write, and the '
        'retry writes both', (tester) async {
      EventAlertService.reset();
      await EventAlertService.forTesting(db);
      addTearDown(EventAlertService.reset);
      final category = await profiled('Gym days');
      final robot = CategoryEditorRobot(tester);
      final alertSheet = AlertSheetRobot(tester);
      final outcome = await robot.show(initial: category);
      await robot.pickKind(CategoryKind.workout);
      await robot.addAlert();
      await alertSheet.save();
      writes
        ..fail = true
        ..failOnly = 'calendar_category_profiles';
      writes.statements.clear();

      await robot.save();

      expect(robot.isOpen, isTrue);
      expect(robot.saveFailureShown, isTrue);
      expect(
        writes.statements.where((s) => s.contains('calendar_category_alerts')),
        isEmpty,
      );
      expect(EventAlerts.categoryAlertsFor(category.id), isEmpty);

      writes.fail = false;
      await robot.save();

      expect(robot.isOpen, isFalse);
      expect(outcome.result?.id, category.id);
      expect(
        CategoryProfiles.profileFor(category.id)!.kind,
        CategoryKind.workout,
      );
      expect(EventAlerts.categoryAlertsFor(category.id), hasLength(1));
    });

    testWidgets('a kind turned back after a save whose alerts failed is '
        'written: the store holds the kind the draft says', (tester) async {
      EventAlertService.reset();
      await EventAlertService.forTesting(db);
      addTearDown(EventAlertService.reset);
      final category = await profiled('Bills', as: CategoryKind.bill);
      final robot = CategoryEditorRobot(tester);
      final alertSheet = AlertSheetRobot(tester);
      await robot.show(initial: category);
      await robot.addAlert();
      await alertSheet.save();
      await robot.pickKind(CategoryKind.workout);
      writes
        ..fail = true
        ..failOnly = 'calendar_category_alerts';

      await robot.save();

      // The category and the profile wrote; the alerts did not.
      expect(robot.isOpen, isTrue);
      expect(robot.saveFailureShown, isTrue);
      expect(
        CategoryProfiles.profileFor(category.id)!.kind,
        CategoryKind.workout,
      );

      await robot.pickKind(CategoryKind.bill);
      writes.fail = false;
      await robot.save();

      expect(robot.isOpen, isFalse);
      expect(CategoryProfiles.profileFor(category.id)!.kind, CategoryKind.bill);
      expect(EventAlerts.categoryAlertsFor(category.id), hasLength(1));
    });

    testWidgets('nothing opens while Save writes: the Kind row and a menu row '
        'take no tap, and the save pops with what it wrote', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show();
      await robot.typeName('Yoga');
      writes.holdNext('calendar_categories');

      await robot.save();
      expect(writes.held, isTrue);

      await robot.tapBlockedRow(kind);
      expect(CategoryKindRobot(tester).isOpen, isFalse);
      await robot.tapBlockedRow(area);
      expect(robot.menuItems, isEmpty);

      writes.release();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(robot.isOpen, isFalse);
      expect(outcome.result?.name, 'Yoga');
    });

    testWidgets('a kind pick clears the flags no row shows too, so Custom '
        'with nothing on screen overridden clears the stored row', (
      tester,
    ) async {
      final category = await custom('Gym days');
      await profiles.save(
        CategoryProfile(
          id: '',
          categoryId: category.id,
          kind: CategoryKind.workout,
          countsHours: false,
        ),
      );
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);

      await robot.pickKind(CategoryKind.custom);
      await robot.save();

      expect(CategoryProfiles.profileFor(category.id), isNull);
    });

    testWidgets('a stored measure the editor never offers reads as its own '
        'name and is listed, checked, in the menu', (tester) async {
      final robot = CategoryEditorRobot(tester);
      await robot.show(
        initial: await profiled(
          'Gym days',
          as: CategoryKind.workout,
          measure: ReportMeasure.cancelled,
        ),
      );

      expect(robot.valueOf(measure), 'Cancelled');
      await robot.tapRow(measure);
      expect(
        robot.menuItems[SemanticsIds.categoryMeasure('cancelled')],
        'Cancelled',
      );
      expect(robot.checkedMenuItem, SemanticsIds.categoryMeasure('cancelled'));
      expect(
        robot.menuItems.keys,
        isNot(contains(SemanticsIds.categoryMeasure('leadTime'))),
      );
    });

    testWidgets('a picked kind makes the sheet dirty; Custom picked on an '
        'unprofiled category does not, and writes nothing', (tester) async {
      final category = await profiled('Gym days');
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: category);

      await robot.pickKind(CategoryKind.custom);
      await robot.close();
      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);

      await robot.show(initial: category);
      await robot.pickKind(CategoryKind.bill);
      await robot.close();
      expect(robot.discardAsked, isTrue);
      await robot.keepEditing();
      // Back to Custom: the draft says what it opened with.
      await robot.pickKind(CategoryKind.custom);
      await robot.close();
      expect(robot.discardAsked, isFalse);
      expect(CategoryProfiles.all, isEmpty);
    });

    testWidgets('back to Custom with nothing overridden clears a stored '
        'profile', (tester) async {
      final category = await profiled('Bills', as: CategoryKind.bill);
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: category);

      await robot.pickKind(CategoryKind.custom);
      await robot.save();

      expect(CategoryProfiles.profileFor(category.id), isNull);
    });

    testWidgets('sandbox: the rows work and Save writes no profile', (
      tester,
    ) async {
      final category = await profiled('Gym days');
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(initial: category, sandbox: true);

      await robot.pickKind(CategoryKind.workout);
      expect(robot.valueOf(kind), 'Workout');
      await robot.save();

      expect(outcome.result?.id, category.id);
      expect(CategoryProfiles.all, isEmpty);
    });

    // The read-back captions the record names, in the three languages at
    // the three scales; the caption wraps freely, so each is whole.
    for (final (locale, texts) in [
      (
        'en',
        [
          'At least 3 a week',
          'At most 40 h a week',
          'At most 180 days between',
          'Budget 1,200 a month',
          'No goal',
        ],
      ),
      (
        'de',
        [
          'Mindestens 3 pro Woche',
          'Höchstens 40 h pro Woche',
          'Höchstens 180 Tage dazwischen',
          'Budget 1.200 pro Monat',
          'Kein Ziel',
        ],
      ),
      (
        'ro',
        [
          'Cel puțin 3 pe săptămână',
          'Cel mult 40 h pe săptămână',
          'Cel mult 180 de zile între ele',
          'Buget 1.200 pe lună',
          'Fără obiectiv',
        ],
      ),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('the Goal caption reads the goal back in $locale at '
            '$scale, whole', (tester) async {
          final cases = [
            await profiled('A', as: CategoryKind.workout, target: weekly3),
            await profiled(
              'B',
              as: CategoryKind.work,
              target: const ReportTarget(
                kind: TargetKind.atMost,
                value: 40 * 60,
                period: TargetPeriod.week,
              ),
            ),
            await profiled(
              'C',
              as: CategoryKind.maintenance,
              target: const ReportTarget(kind: TargetKind.maxGap, value: 180),
            ),
            await profiled(
              'D',
              as: CategoryKind.bill,
              target: const ReportTarget(
                kind: TargetKind.budget,
                value: 1200 * 100,
                period: TargetPeriod.month,
              ),
            ),
            await profiled('E', as: CategoryKind.workout),
          ];
          final robot = CategoryEditorRobot(tester);
          for (final (index, category) in cases.indexed) {
            final errors = await layoutErrorsDuring(() async {
              await robot.show(
                initial: category,
                locale: Locale(locale),
                textScale: scale,
                surface: const Size(360, 780),
              );
              await tester.ensureVisible(
                find.bySemanticsIdentifier(goal).first,
              );
              await tester.pumpAndSettle();
              expect(robot.captionOf(goal), texts[index]);
              expect(robot.textWhole(texts[index]), isTrue);
            });
            expect(errors, isEmpty);
            await robot.close();
          }
        });
      }
    }

    testWidgets('German at 2.0 on 360 × 780: every profile row whole and '
        'inside the sheet, at 48 dp or more', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          initial: await profiled(
            'Gym days',
            as: CategoryKind.workout,
            target: weekly3,
          ),
          locale: const Locale('de'),
          textScale: 2.0,
          surface: const Size(360, 780),
        );
        for (final id in CategoryEditorRobot.profileRowIds) {
          await tester.ensureVisible(find.bySemanticsIdentifier(id).first);
          await tester.pumpAndSettle();
          final rect = robot.targetOf(id);
          expect(rect.left, greaterThanOrEqualTo(robot.sheetRect.left));
          expect(rect.right, lessThanOrEqualTo(robot.sheetRect.right));
          expect(rect.height, greaterThanOrEqualTo(FormMetrics.rowMinHeight));
        }
        for (final id in CategoryEditorRobot.profileRowIds) {
          final caption = robot.captionOf(id);
          if (caption != null) {
            expect(robot.textWhole(caption), isTrue, reason: caption);
          }
        }
        expect(robot.captionOf(kind), 'Studio, Laufen, Kurs');
        expect(robot.captionOf(measure), 'Auto ist Anwesenheit');
        expect(robot.captionOf(goal), 'Mindestens 3 pro Woche');
      });
      expect(errors, isEmpty);
    });

    for (final (locale, scale, dark) in [
      ('en', 1.0, false),
      ('de', 2.0, true),
    ]) {
      testWidgets('$locale at $scale${dark ? ' dark' : ''}: the profile rows '
          'meet the tap-target, label and contrast guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        final robot = CategoryEditorRobot(tester);
        await robot.show(
          initial: await profiled('Gym days', as: CategoryKind.workout),
          locale: Locale(locale),
          textScale: scale,
          surface: const Size(360, 780),
          theme: dark ? AppTheme.dark() : null,
        );
        await tester.ensureVisible(find.bySemanticsIdentifier(goal).first);
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    for (final (locale, scale) in [('en', 1.0), ('de', 2.0)]) {
      testWidgets('$locale at $scale: the Report label stands a group gap '
          'under the alerts caption', (tester) async {
        final robot = CategoryEditorRobot(tester);
        await robot.show(
          initial: await profiled('Gym days', as: CategoryKind.workout),
          locale: Locale(locale),
          textScale: scale,
          surface: const Size(360, 780),
        );
        final label = robot.sectionLabels[1];
        expect(
          robot.sectionLabelRect(label).top - robot.alertsHintRect.bottom,
          moreOrLessEquals(RowMetrics.groupGap, epsilon: 0.01),
        );
      });
    }

    testWidgets('while Save writes no row dims: every profile row is drawn as '
        'it was before the tap', (tester) async {
      final robot = CategoryEditorRobot(tester);
      await robot.show(
        initial: await profiled('Sleep', as: CategoryKind.sleep),
        surface: const Size(360, 780),
      );
      await robot.typeName('Sleep well');
      final before = {
        for (final id in CategoryEditorRobot.profileRowIds)
          id: robot.opacitiesOf(id),
      };
      // Counts as is disabled under Sleep, so a dimmed row is in the set.
      expect(before[countsAs], contains(FormMetrics.disabledOpacity));
      writes.holdNext('calendar_categories');

      await robot.save();
      expect(writes.held, isTrue);
      for (final id in CategoryEditorRobot.profileRowIds) {
        expect(robot.opacitiesOf(id), before[id], reason: id);
      }

      writes.release();
      await tester.pumpAndSettle();
      expect(robot.isOpen, isFalse);
    });
  });

  group('sharing', () {
    const maria = ShareAudience(
      id: 'pair-1',
      displayName: 'Maria',
      members: [],
    );
    const ready = ShareReady(maria);
    const notSyncing = ShareNotSyncing(maria);

    // Roboto, so the row is measured as a phone draws it. The group runs
    // last, so no case above measures in anything but the test font.
    setUpAll(loadGoldenFonts);

    /// A custom category the service holds, shared when [shared] says so.
    Future<CalendarCategory> category(
      String name, {
      bool shared = false,
    }) async {
      final created = await custom(name);
      if (shared) await service.setShared(created.id, maria.id);
      return CalendarCategories.byId(created.id)!;
    }

    testWidgets('not paired: no SHARING section — the sheet as the one opened '
        'without sharing', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final work = await category('Work');
      await robot.show(initial: work, surface: const Size(360, 780));
      final labels = robot.sectionLabels;
      final height = robot.sheetRect.height;
      await robot.close();

      await robot.show(
        initial: work,
        surface: const Size(360, 780),
        share: const ShareNotPaired(),
      );
      expect(robot.shareShown, isFalse);
      expect(robot.sectionLabels, labels);
      expect(robot.sheetRect.height, height);
    });

    testWidgets('paired: SHARING sits between the look and ALERTS', (
      tester,
    ) async {
      final robot = CategoryEditorRobot(tester);
      await robot.show(initial: await category('Work'), share: ready);
      final labels = robot.sectionLabels;
      expect(labels.take(2), ['Sharing', 'Alerts']);
      expect(
        robot.sectionLabelRect('Sharing').top,
        greaterThan(robot.nameRowRect.bottom),
      );
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('at $scale: off, on and waiting for sync are one row height '
          'for a category with events and for an empty one', (tester) async {
        final robot = CategoryEditorRobot(tester);
        final work = await category('Work');
        final shared = await category('Travel', shared: true);
        // The count is the category's at the open; what may change while the
        // sheet is up is the state, so the height is pinned per count.
        for (final (count, on) in [
          (42, 'All 42 events, and new ones'),
          (0, 'New events are shared'),
        ]) {
          final heights = <double>[];
          for (final (initial, share, subtitle, enabled) in [
            (work, ready, 'Only you see these events', true),
            (shared, ready, on, true),
            (shared, notSyncing, 'Turn on sync to share', false),
          ]) {
            await robot.show(
              initial: initial,
              share: share,
              shareEventCount: count,
              textScale: scale,
              surface: const Size(360, 780),
            );
            expect(robot.shareLabel, 'Share with Maria');
            expect(robot.shareSubtitle, subtitle);
            expect(robot.shareEnabled, enabled);
            heights.add(robot.shareRowHeight);
            await robot.close();
          }
          expect(heights.toSet(), hasLength(1), reason: '$count: $heights');
          if (scale == 1.0) {
            expect(heights.first, FormMetrics.twoLineRowMinHeight);
          }
        }
      });
    }

    testWidgets('waiting for sync: off and dimmed with the reason whole, and '
        'a tap opens Sync & sharing over the sheet', (tester) async {
      final robot = CategoryEditorRobot(tester);
      var opened = 0;
      await robot.show(
        initial: await category('Travel', shared: true),
        share: notSyncing,
        openSyncSettings: (_) async => opened++,
      );
      expect(robot.shareOn, isFalse);
      // The glyph and the label; the switch keeps its own disabled colours.
      expect(
        robot
            .opacitiesOf(SemanticsIds.categoryEditorShare)
            .where((opacity) => opacity == FormMetrics.disabledOpacity),
        hasLength(2),
      );
      // The slot's last child is the line it shows; the rest are templates.
      final reason = find.ancestor(
        of: find.text('Turn on sync to share').last,
        matching: find.byType(Opacity),
      );
      for (final element in reason.evaluate()) {
        expect((element.widget as Opacity).opacity, 1.0);
      }
      // Dimmed, yet it acts: it says where its tap goes.
      expect(
        tester
            .widget<FormSwitchRow>(
              find.ancestor(
                of: find.text('Turn on sync to share').last,
                matching: find.byType(FormSwitchRow),
              ),
            )
            .onDisabledTapHint,
        'Opens Sync & sharing',
      );

      await robot.tapShare();
      expect(opened, 1);
      expect(robot.isOpen, isTrue);
      expect(robot.discardAsked, isFalse);
    });

    testWidgets('sync turned on over the sheet: the opener is asked again '
        'on the return, and the switch follows, clean', (tester) async {
      final robot = CategoryEditorRobot(tester);
      var asked = 0;
      final outcome = await robot.show(
        initial: await category('Travel', shared: true),
        share: notSyncing,
        openSyncSettings: (_) async {},
        rereadShare: () async {
          asked++;
          return ready;
        },
      );
      expect(robot.shareEnabled, isFalse);

      await robot.tapShare();

      expect(asked, 1);
      expect(robot.shareEnabled, isTrue);
      expect(robot.shareOn, isTrue, reason: 'the category is shared');
      expect(robot.shareSubtitle, 'New events are shared');
      await robot.close();
      expect(robot.discardAsked, isFalse);
      expect(outcome.share, isNull);
    });

    testWidgets('the switch is part of the draft: a flip is dirty, the leave '
        'guard asks, and Save hands it back unwritten', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final work = await category('Work');
      final outcome = await robot.show(initial: work, share: ready);

      await robot.tapShare();
      expect(robot.shareOn, isTrue);
      expect(robot.shareSubtitle, 'New events are shared');
      await robot.close();
      expect(robot.discardAsked, isTrue);
      await robot.keepEditing();

      await robot.save();
      expect(outcome.returned, isTrue);
      expect(outcome.result?.id, work.id);
      expect(outcome.share, isTrue);
      // The opener writes it: the sheet never calls the share service.
      expect(CalendarCategories.byId(work.id)!.sharedByMe, isFalse);
    });

    testWidgets('a flip turned back is clean, and Save then asks for no '
        'change', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final travel = await category('Travel', shared: true);
      final outcome = await robot.show(initial: travel, share: ready);
      expect(robot.shareOn, isTrue);
      await robot.tapShare();
      await robot.tapShare();
      await robot.close();
      expect(robot.discardAsked, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.share, isNull);

      final again = await robot.show(initial: travel, share: ready);
      await robot.save();
      expect(again.share, isNull);
      final off = await robot.show(initial: travel, share: ready);
      await robot.tapShare();
      await robot.save();
      expect(off.share, isFalse);
    });

    testWidgets('a new category can be created already shared', (tester) async {
      final robot = CategoryEditorRobot(tester);
      final outcome = await robot.show(share: ready);
      expect(robot.shareSubtitle, 'Only you see these events');
      await robot.typeName('Trips');
      await robot.tapShare();
      expect(robot.shareSubtitle, 'New events are shared');

      await robot.save();
      expect(outcome.result?.name, 'Trips');
      expect(CalendarCategories.byId(outcome.result!.id), isNotNull);
      expect(outcome.share, isTrue);
    });

    group('German at 2.0 with a long name', () {
      testWidgets('"Mit Maximilian-Alexander teilen" wraps whole inside the '
          'sheet, one height in every state', (tester) async {
        const long = ShareAudience(
          id: 'pair-1',
          displayName: 'Maximilian-Alexander',
          members: [],
        );
        final robot = CategoryEditorRobot(tester);
        final work = await category('Work');
        final shared = await category('Travel', shared: true);
        final heights = <double>[];
        final errors = await layoutErrorsDuring(() async {
          for (final (initial, share) in [
            (work, const ShareReady(long)),
            (shared, const ShareReady(long)),
            (shared, const ShareNotSyncing(long)),
          ]) {
            await robot.show(
              initial: initial,
              share: share,
              shareEventCount: 42,
              locale: const Locale('de'),
              textScale: 2.0,
              surface: const Size(360, 780),
            );
            await tester.ensureVisible(
              find.bySemanticsIdentifier(SemanticsIds.categoryEditorShare),
            );
            await tester.pumpAndSettle();
            expect(robot.shareLabel, 'Mit Maximilian-Alexander teilen');
            expect(robot.shareRowWhole, isTrue);
            heights.add(robot.shareRowHeight);
            await robot.close();
          }
        });
        expect(errors, isEmpty);
        expect(heights.toSet(), hasLength(1), reason: '$heights');
      });
    });

    for (final (locale, scale) in [('en', 1.0), ('de', 2.0)]) {
      testWidgets('$locale at $scale: the switch meets the tap-target and '
          'label guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        final robot = CategoryEditorRobot(tester);
        await robot.show(
          initial: await category('Work'),
          share: ready,
          locale: Locale(locale),
          textScale: scale,
          surface: const Size(360, 780),
        );
        await tester.ensureVisible(
          find.bySemanticsIdentifier(SemanticsIds.categoryEditorShare),
        );
        await tester.pumpAndSettle();
        expect(robot.shareNode.label, contains('Maria'));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }
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

/// Holds or fails the next read of one table — copied from the delete
/// sheet's suite: `create`'s `MAX(sort_order)` read, held so a case can act
/// on the sheet mid-save, or the alert write's own read, failed where the
/// write itself would be skipped as unchanged.
class _ReadGate extends QueryInterceptor {
  Completer<void>? _hold;
  String? _table;
  bool _fail = false;
  bool held = false;

  void holdNext(String table) {
    _table = table;
    _fail = false;
    _hold = Completer<void>();
  }

  void failNext(String table) {
    _table = table;
    _fail = true;
  }

  void release() {
    final hold = _hold;
    _hold = null;
    _table = null;
    _fail = false;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final table = _table;
    if (_fail && table != null && statement.contains(table)) {
      _table = null;
      _fail = false;
      throw StateError('read of $table failed');
    }
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    if (hold != null && table != null && statement.contains(table)) {
      _table = null;
      held = true;
      await hold.future;
    }
    return rows;
  }
}

/// Fails every write on demand — or only the ones whose statement names
/// [failOnly] — so a save can be made to fail without closing the database
/// under the sheet; the reads go through [_ReadGate], the database's one
/// interceptor.
class _WriteFailure extends _ReadGate {
  bool fail = false;
  String? failOnly;

  /// Every insert and update that went through, in order — the save order
  /// read off the database itself.
  final List<String> statements = [];

  bool _fails(String statement) =>
      fail && (failOnly == null || statement.contains(failOnly!));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_fails(statement)) return Future.error(StateError('the write failed'));
    statements.add(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_fails(statement)) return Future.error(StateError('the write failed'));
    statements.add(statement);
    return super.runUpdate(executor, statement, args);
  }
}
