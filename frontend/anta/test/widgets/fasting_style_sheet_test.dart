import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import 'support/fasting_style_robot.dart';
import 'support/layout_errors.dart';

/// The style sheet applies live: every control writes a whole
/// `FastingTraditionStyle` through `onChanged`, and the settings page
/// persists each one. What is worth pinning is therefore the payload each
/// control produces, when it is produced (the title's dialog and the
/// description's sheet write on confirm and nothing on cancel; everything
/// else writes at once), and that the preview follows the sheet's own draft
/// rather than the engine. The last group pins the sub-sheet of the UI
/// language the sheet became in Tier 3 (slice 4): the menu rows and their
/// items, the title row and its clear, the description row's line, the
/// ids, German at 200 % on a phone, the targets.
///
/// A real in-memory settings backend is bound for the colour strip, which
/// loads the palette, and the app-wide markdown bar bloc for the description
/// sheet. Every case drives the sheet through [FastingStyleRobot]
/// (`support/`), so a rebuild of the chrome rewrites the robot and leaves
/// these bodies alone.
void main() {
  late AppDatabase db;

  // The description sheet the Description row opens reads the app-wide
  // markdown bar bloc from its `initState`, and the bar's service lives in
  // the app database.
  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  const green = 0xFF43A047;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_fasting_style');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
  });

  tearDown(() async {
    await barBloc.close();
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  /// Opens the sheet on [initial] and collects every style it writes.
  Future<(FastingStyleRobot, List<FastingTraditionStyle>)> open(
    WidgetTester tester, {
    FastingTradition tradition = FastingTradition.orthodox,
    FastingTraditionStyle initial = const FastingTraditionStyle(),
    Size surface = FastingStyleRobot.defaultSurface,
  }) async {
    final writes = <FastingTraditionStyle>[];
    final robot = FastingStyleRobot(tester);
    await robot.show(
      tradition: tradition,
      initialStyle: initial,
      onChanged: writes.add,
      surface: surface,
      barBloc: barBloc,
    );
    return (robot, writes);
  }

  testWidgets('the sheet opens on the tradition and its defaults', (
    tester,
  ) async {
    final (robot, writes) = await open(tester);

    expect(robot.title, 'Orthodox');
    expect(robot.style, FastingDisplayStyle.tint);
    expect(robot.placement, FastingRowPlacement.afterHolidays);
    expect(robot.swatches.defaultSelected, isTrue);
    expect(robot.iconLabel, 'Default icon');
    expect(robot.hasIconReset, isFalse);
    expect(robot.titleText, '');
    expect(robot.descriptionText, '');
    expect(writes, isEmpty);
  });

  testWidgets('a style chip writes the style at once', (tester) async {
    final (robot, writes) = await open(tester);

    await robot.pickStyle(FastingDisplayStyle.bar);

    expect(writes, [
      const FastingTraditionStyle(style: FastingDisplayStyle.bar),
    ]);
    expect(robot.style, FastingDisplayStyle.bar);
  });

  testWidgets('a placement chip writes the placement at once', (tester) async {
    final (robot, writes) = await open(tester);

    await robot.pickPlacement(FastingRowPlacement.first);

    expect(writes, [
      const FastingTraditionStyle(placement: FastingRowPlacement.first),
    ]);
    expect(robot.placement, FastingRowPlacement.first);
  });

  testWidgets('a swatch writes the colour at once', (tester) async {
    final (robot, writes) = await open(tester);

    await robot.pickSwatch(green);

    expect(writes, [const FastingTraditionStyle(colorValue: green)]);
    expect(robot.swatches.selectedColor, green);
    expect(robot.swatches.defaultSelected, isFalse);
  });

  testWidgets('the default colour dot clears the colour', (tester) async {
    final (robot, writes) = await open(
      tester,
      initial: const FastingTraditionStyle(colorValue: green),
    );
    expect(robot.swatches.selectedColor, green);

    await robot.useDefaultColor();

    expect(writes, [const FastingTraditionStyle()]);
    expect(writes.single.colorValue, isNull);
    expect(robot.swatches.defaultSelected, isTrue);
  });

  testWidgets('the icon picker\'s pick writes the icon at once', (
    tester,
  ) async {
    final (robot, writes) = await open(tester);

    await robot.chooseIcon('cake');

    expect(writes, [const FastingTraditionStyle(iconKey: 'cake')]);
    expect(robot.iconLabel, 'Custom icon');
    expect(robot.hasIconReset, isTrue);
  });

  testWidgets('a cancelled icon picker writes nothing', (tester) async {
    final (robot, writes) = await open(tester);

    await robot.tapIcon();
    expect(robot.iconPickerOpen, isTrue);
    await robot.cancelIconPicker();

    expect(writes, isEmpty);
    expect(robot.iconLabel, 'Default icon');
  });

  testWidgets('the icon reset clears the icon at once', (tester) async {
    final (robot, writes) = await open(
      tester,
      initial: const FastingTraditionStyle(iconKey: 'cake'),
    );
    expect(robot.iconLabel, 'Custom icon');

    await robot.resetIcon();

    expect(writes, [const FastingTraditionStyle()]);
    expect(writes.single.iconKey, isNull);
    expect(robot.iconLabel, 'Default icon');
    expect(robot.hasIconReset, isFalse);
  });

  testWidgets('a confirmed title dialog writes at once and a cancelled one '
      'writes nothing', (tester) async {
    final (robot, writes) = await open(tester);

    await robot.openTitle();
    expect(robot.titleDialogOpen, isTrue);
    await robot.cancelTitle();
    expect(robot.titleDialogOpen, isFalse);
    expect(writes, isEmpty);
    expect(robot.previewTitle, 'Great Lent');

    await robot.typeTitle('Fasting');

    // No debounce to wait out: the dialog's confirm is the write.
    expect(writes, [const FastingTraditionStyle(titleOverride: 'Fasting')]);
    expect(robot.previewTitle, 'Fasting');
    expect(robot.titleText, 'Fasting');
  });

  testWidgets('a description confirmed with Done writes at once; a dismissed '
      'description sheet writes nothing', (tester) async {
    final (robot, writes) = await open(tester);

    await robot.openDescription();
    expect(robot.descriptionSheetOpen, isTrue);
    await robot.replaceDescription('Keep it light');
    await robot.cancelDescription();
    expect(robot.descriptionSheetOpen, isFalse);
    expect(writes, isEmpty);
    expect(robot.descriptionText, '');

    await robot.typeDescription('Keep it light');
    expect(writes, [const FastingTraditionStyle(description: 'Keep it light')]);
    expect(robot.descriptionText, 'Keep it light');

    // A Done that changed nothing writes nothing — the template form's rule.
    await robot.typeDescription('Keep it light');
    expect(writes, hasLength(1));

    await robot.close();
    expect(robot.isOpen, isFalse);
    expect(writes, hasLength(1));
  });

  testWidgets('blank text is written as null', (tester) async {
    final (robot, writes) = await open(
      tester,
      initial: const FastingTraditionStyle(
        titleOverride: 'Fasting',
        description: 'Keep it light',
      ),
    );
    expect(robot.titleText, 'Fasting');
    expect(robot.descriptionText, 'Keep it light');

    await robot.clearTitle();
    await robot.elapse(const Duration(milliseconds: 400));
    expect(writes.last.titleOverride, isNull);
    expect(writes.last.description, 'Keep it light');

    await robot.typeDescription('   ');
    await robot.elapse(const Duration(milliseconds: 400));
    expect(writes.last.description, isNull);
    expect(writes.last, const FastingTraditionStyle());
  });

  testWidgets('a typed description reaches the preview as plain text', (
    tester,
  ) async {
    final (robot, _) = await open(tester);
    expect(robot.previewDescription, isNull);

    await robot.typeDescription('**Keep** it light');

    expect(robot.previewDescription, '**Keep** it light');
  });

  testWidgets('the preview resolves the icon from the draft', (tester) async {
    final (robot, _) = await open(tester);
    expect(robot.previewIcon, Icons.church);

    await robot.chooseIcon('cake');
    expect(robot.previewIcon, CalendarIcons.forKey('cake'));

    await robot.resetIcon();
    expect(robot.previewIcon, Icons.church);
  });

  testWidgets('the title override replaces the sample period in the preview', (
    tester,
  ) async {
    final (robot, _) = await open(
      tester,
      initial: const FastingTraditionStyle(titleOverride: 'Fasting'),
    );

    expect(robot.previewTitle, 'Fasting');
    expect(await robot.titleHint(), 'Great Lent');
  });

  for (final (tradition, period, regime) in const [
    (FastingTradition.orthodox, 'Great Lent', 'Fish allowed'),
    (FastingTradition.catholic, 'Lent', 'Day of penance'),
    (FastingTradition.muslim, 'Ramadan', 'Fast from dawn to sunset'),
    (FastingTradition.jewish, 'Yom Kippur', 'Total fast'),
  ]) {
    testWidgets('the sample period and regime follow the tradition '
        '(${tradition.name})', (tester) async {
      final (robot, _) = await open(tester, tradition: tradition);

      expect(robot.previewTitle, period);
      expect(robot.previewSubtitle, regime);
      expect(await robot.titleHint(), period);
    });
  }

  testWidgets('German at text scale 2.0 on 360 × 780 lays out with no layout '
      'error: the preview\'s sample day cell included, every row\'s label '
      'whole', (tester) async {
    // The 44 × 52 sample cell is the one box in the sheet that cannot grow
    // with the text, and in the test's box font "15" at 200 % is wider than
    // it; the number is fitted into the cell (D19), so the cell holds.
    const phone = Size(360, 780);
    final robot = FastingStyleRobot(tester);
    final errors = await layoutErrorsDuring(() async {
      await robot.show(
        onChanged: (_) {},
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
        initialStyle: const FastingTraditionStyle(
          iconKey: 'cake',
          titleOverride: 'Fasten',
        ),
        barBloc: barBloc,
      );
      expect(robot.title, 'Orthodox');
      expect(robot.sectionLabelWhole('Vorschau'), isTrue);
      for (final id in [
        SemanticsIds.fastingStyleGrid,
        SemanticsIds.fastingStylePlacement,
        SemanticsIds.fastingStyleIcon,
        SemanticsIds.fastingStyleTitle,
        SemanticsIds.fastingStyleDescription,
      ]) {
        expect(robot.controlLabelWhole(id), isTrue, reason: id);
      }
      expect(robot.textWhole('Anzeige im Raster'), isTrue);
      expect(robot.textWhole('Reihenfolge im Tagespanel'), isTrue);
      expect(robot.textWhole('Symbol'), isTrue);
      expect(robot.textWhole('Eigener Titel'), isTrue);
      expect(robot.textWhole('Beschreibung'), isTrue);
      // Every control inside the sheet's width, the two second targets too.
      final sheet = robot.sheetRect;
      for (final id in [
        SemanticsIds.fastingStyleClose,
        SemanticsIds.fastingStyleGrid,
        SemanticsIds.fastingStylePlacement,
        SemanticsIds.fastingStyleIcon,
        SemanticsIds.fastingStyleIconReset,
        SemanticsIds.swatchRow,
        SemanticsIds.fastingStyleTitle,
        SemanticsIds.fastingStyleTitleClear,
        SemanticsIds.fastingStyleDescription,
      ]) {
        final rect = robot.targetOf(id);
        expect(rect.left, greaterThanOrEqualTo(sheet.left), reason: id);
        expect(rect.right, lessThanOrEqualTo(sheet.right), reason: id);
      }
    });
    expect(errors, isEmpty);
  });

  group('the sub-sheet of the language', () {
    const phone = Size(360, 780);

    testWidgets('the grid and placement rows are menus whose items carry ids; '
        'a pick writes at once and the row reads it back', (tester) async {
      final (robot, writes) = await open(tester);

      await robot.openGridMenu();
      expect(robot.menuOpen, isTrue);
      for (final id in [
        SemanticsIds.fastingStyleGridTint,
        SemanticsIds.fastingStyleGridBar,
        SemanticsIds.fastingStyleGridStrong,
        SemanticsIds.fastingStyleGridNone,
      ]) {
        expect(robot.menuItemShown(id), isTrue, reason: id);
      }
      expect(robot.menuItemChecked(SemanticsIds.fastingStyleGridTint), isTrue);
      expect(
        robot.menuItemChecked(SemanticsIds.fastingStyleGridStrong),
        isFalse,
      );
      await robot.dismissMenu();
      expect(robot.menuOpen, isFalse);
      expect(writes, isEmpty);

      await robot.pickStyle(FastingDisplayStyle.strong);
      expect(writes.last.style, FastingDisplayStyle.strong);
      expect(robot.styleLabel, 'Bold day number');

      await robot.openPlacementMenu();
      for (final id in [
        SemanticsIds.fastingStylePlacementFirst,
        SemanticsIds.fastingStylePlacementBeforeHolidays,
        SemanticsIds.fastingStylePlacementAfterHolidays,
        SemanticsIds.fastingStylePlacementLast,
      ]) {
        expect(robot.menuItemShown(id), isTrue, reason: id);
      }
      expect(
        robot.menuItemChecked(SemanticsIds.fastingStylePlacementAfterHolidays),
        isTrue,
      );
      await robot.dismissMenu();

      await robot.pickPlacement(FastingRowPlacement.last);
      expect(writes.last.placement, FastingRowPlacement.last);
      expect(writes.last.style, FastingDisplayStyle.strong);
      expect(robot.placementLabel, 'Last');
      expect(writes, hasLength(2));
    });

    testWidgets('the Custom title row reads Default, its clear button exists '
        'only with an override and resets it', (tester) async {
      final (robot, writes) = await open(tester);
      expect(robot.titleLabel, 'Default');
      expect(robot.hasTitleClear, isFalse);

      await robot.typeTitle('Fasting');
      expect(robot.titleLabel, 'Fasting');
      expect(robot.hasTitleClear, isTrue);
      final clear = robot.nodeOf(SemanticsIds.fastingStyleTitleClear);
      expect(clear.tooltip, 'Reset to default');
      expect(clear.flagsCollection.isButton, isTrue);

      await robot.clearTitle();
      expect(writes.last.titleOverride, isNull);
      expect(robot.titleLabel, 'Default');
      expect(robot.hasTitleClear, isFalse);
      expect(robot.previewTitle, 'Great Lent');

      // A confirmed blank is the clear too.
      await robot.typeTitle('Fasting');
      await robot.typeTitle('   ');
      expect(writes.last.titleOverride, isNull);
      expect(robot.hasTitleClear, isFalse);
    });

    testWidgets('the Description row reads the hint while empty and the text '
        'with its markdown dropped once set', (tester) async {
      final (robot, _) = await open(tester);
      expect(
        robot.descriptionCaption,
        'Shown under the rule — markdown works here',
      );

      await robot.typeDescription('**Keep** it _light_\n\n- and simple');
      expect(robot.descriptionCaption, 'Keep it light and simple');
      // The preview keeps the text as typed: plain, never rendered.
      expect(robot.previewDescription, '**Keep** it _light_\n\n- and simple');
    });

    testWidgets("a long description's line shows two lines with an ellipsis, "
        'never a paragraph', (tester) async {
      const long =
          'Keep it light and simple, fish on the weekends, no meat on '
          'Wednesdays and Fridays, oil and wine only on the feast days of the '
          'period, and nothing at all on the strict days before the great '
          'feast at the end, when the whole household keeps the fast together';
      final (robot, _) = await open(
        tester,
        initial: const FastingTraditionStyle(description: long),
        surface: phone,
      );

      // The line is the text with its markdown dropped and the strip's own
      // 200-character cap applied; what the row then draws is two lines.
      expect(robot.descriptionCaption, startsWith('Keep it light and simple'));
      expect(robot.descriptionCaptionLines, FormMetrics.valueMaxLines);
      expect(robot.descriptionCaptionClamped, isTrue);
      // The row still reads its whole line to a screen reader: the clamp is
      // drawn, not announced.
      expect(
        robot.nodeOf(SemanticsIds.fastingStyleDescription).label,
        contains(robot.descriptionCaption),
      );
    });

    testWidgets('the ✕ and every row carry ids, the strip is a container and '
        'the preview sits on its group with no card', (tester) async {
      final (robot, writes) = await open(
        tester,
        initial: const FastingTraditionStyle(
          iconKey: 'cake',
          titleOverride: 'Fasting',
        ),
      );
      expect(robot.previewOnCard, isFalse);
      expect(robot.swatchRowIsContainer, isTrue);
      final close = robot.nodeOf(SemanticsIds.fastingStyleClose);
      expect(close.tooltip, 'Close');
      expect(close.flagsCollection.isButton, isTrue);
      for (final id in [
        SemanticsIds.fastingStyleGrid,
        SemanticsIds.fastingStylePlacement,
        SemanticsIds.fastingStyleIcon,
        SemanticsIds.fastingStyleTitle,
        SemanticsIds.fastingStyleDescription,
      ]) {
        final node = robot.nodeOf(id);
        expect(node.flagsCollection.isEnabled, isNot(Tristate.isFalse));
        expect(node.label, isNotEmpty, reason: id);
      }
      expect(
        robot.nodeOf(SemanticsIds.fastingStyleIconReset).tooltip,
        'Reset to default',
      );
      expect(
        robot.nodeOf(SemanticsIds.fastingStyleTitleClear).tooltip,
        'Reset to default',
      );

      await robot.close();
      expect(robot.isOpen, isFalse);
      expect(writes, isEmpty);
    });

    testWidgets('every control is a 48 dp target at 360 × 780', (tester) async {
      final (robot, _) = await open(
        tester,
        initial: const FastingTraditionStyle(
          iconKey: 'cake',
          titleOverride: 'Fasting',
        ),
        surface: phone,
      );

      for (final id in [
        SemanticsIds.fastingStyleClose,
        SemanticsIds.fastingStyleIconReset,
        SemanticsIds.fastingStyleTitleClear,
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
      for (final id in [
        SemanticsIds.fastingStyleGrid,
        SemanticsIds.fastingStylePlacement,
        SemanticsIds.fastingStyleIcon,
        SemanticsIds.fastingStyleTitle,
        SemanticsIds.fastingStyleDescription,
      ]) {
        expect(
          robot.targetOf(id).height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
          reason: id,
        );
      }
      final dots = robot.dotTargets;
      expect(dots, isNotEmpty);
      for (final dot in dots) {
        expect(dot.width, greaterThanOrEqualTo(FormMetrics.trailingButtonSize));
        expect(
          dot.height,
          greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
        );
      }
    });
  });
}
