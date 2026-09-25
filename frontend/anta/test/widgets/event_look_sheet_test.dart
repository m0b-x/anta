import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_look_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/icon_picker_sheet.dart';

import '../database/support/db_test_support.dart';

class _Outcome {
  EventLookDraft? result;
  bool returned = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const surface = Size(800, 1400);
  const tintLabel = 'Tint icon with color';
  const resetTooltip = 'Reset to Default';
  const categoryDefaultTooltip = 'Category color';

  late Directory tempDir;
  late AppDatabase db;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_look_sheet');
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
    CalendarCategories.updateCache([
      for (final (i, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: seed.id,
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: i,
          isBuiltIn: true,
        ),
    ]);
  });

  tearDown(() async {
    CalendarCategories.updateCache(const []);
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  CalendarCategory gym() => CalendarCategories.resolve('gym');

  int otherSwatch() =>
      CalendarPalette.all.firstWhere((argb) => argb != gym().colorValue);

  Future<_Outcome> openSheet(
    WidgetTester tester, {
    EventLookDraft draft = const EventLookDraft(),
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                outcome.result = await EventLookSheet.show(
                  context,
                  draft: draft,
                  category: gym(),
                );
                outcome.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(EventLookSheet), findsOneWidget);
    return outcome;
  }

  Finder swatchDot(int argb) => find.byWidgetPredicate(
    (widget) => widget is ColorSwatchDot && widget.color?.toARGB32() == argb,
  );

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) => tapAndSettle(tester, find.text('Done'));

  Switch tintSwitch(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch));

  EventAvatar avatar(WidgetTester tester) =>
      tester.widget<EventAvatar>(find.byType(EventAvatar));

  Size sheetSize(WidgetTester tester) =>
      tester.getSize(find.byType(EventLookSheet));

  testWidgets('Done returns the draft with the picked colour', (tester) async {
    final swatch = otherSwatch();
    final outcome = await openSheet(tester);

    await tapAndSettle(tester, swatchDot(swatch));
    await done(tester);

    expect(outcome.returned, isTrue);
    expect(outcome.result, EventLookDraft(colorValue: swatch));
    expect(outcome.result!.colorValue, swatch);
    expect(outcome.result!.isCustom, isTrue);
    expect(find.byType(EventLookSheet), findsNothing);
  });

  testWidgets('Done with nothing touched returns the draft it was given', (
    tester,
  ) async {
    const draft = EventLookDraft(
      iconKey: 'cake',
      colorValue: 0xFF43A047,
      tintIcon: false,
    );
    final outcome = await openSheet(tester, draft: draft);

    await done(tester);

    expect(outcome.returned, isTrue);
    expect(outcome.result, draft);
  });

  testWidgets('the close button returns null and keeps nothing', (
    tester,
  ) async {
    final swatch = otherSwatch();
    final outcome = await openSheet(tester);
    await tapAndSettle(tester, swatchDot(swatch));

    await tapAndSettle(tester, find.byIcon(Icons.close_rounded));

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(EventLookSheet), findsNothing);
  });

  testWidgets('the system back returns null', (tester) async {
    final swatch = otherSwatch();
    final outcome = await openSheet(tester);
    await tapAndSettle(tester, swatchDot(swatch));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(outcome.returned, isTrue);
    expect(outcome.result, isNull);
    expect(find.byType(EventLookSheet), findsNothing);
  });

  testWidgets('the tint row is always present, disabled without a colour', (
    tester,
  ) async {
    final swatch = otherSwatch();
    final outcome = await openSheet(tester);

    expect(find.text(tintLabel), findsOneWidget);
    expect(tintSwitch(tester).onChanged, isNull);
    expect(tintSwitch(tester).value, isTrue);
    expect(avatar(tester).color, gym().color);

    await tapAndSettle(tester, swatchDot(swatch));

    expect(find.text(tintLabel), findsOneWidget);
    expect(tintSwitch(tester).onChanged, isNotNull);
    expect(avatar(tester).color, Color(swatch));

    await tapAndSettle(tester, find.byType(Switch));

    expect(tintSwitch(tester).value, isFalse);
    expect(avatar(tester).color, gym().color);

    await tapAndSettle(tester, find.byTooltip(categoryDefaultTooltip));

    expect(find.text(tintLabel), findsOneWidget);
    expect(tintSwitch(tester).onChanged, isNull);
    expect(tintSwitch(tester).value, isFalse);

    await done(tester);

    expect(outcome.result, const EventLookDraft(tintIcon: false));
  });

  testWidgets('the Icon row reads Default with a chevron and no reset', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.text('Icon'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
    expect(find.byType(FormChevron), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byTooltip(resetTooltip), findsNothing);
    expect(avatar(tester).icon, CalendarIcons.forKey('fitness_center'));
  });

  testWidgets('the Icon row reads Custom with a reset button that clears it', (
    tester,
  ) async {
    final outcome = await openSheet(
      tester,
      draft: const EventLookDraft(iconKey: 'cake'),
    );
    final before = sheetSize(tester);

    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    expect(find.byType(FormChevron), findsNothing);
    expect(find.byTooltip(resetTooltip), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(avatar(tester).icon, CalendarIcons.forKey('cake'));

    await tapAndSettle(tester, find.byIcon(Icons.refresh_rounded));

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
    expect(find.byType(FormChevron), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(avatar(tester).icon, CalendarIcons.forKey('fitness_center'));
    expect(sheetSize(tester), before);

    await done(tester);

    expect(outcome.result, const EventLookDraft());
    expect(outcome.result!.iconKey, isNull);
  });

  testWidgets('tapping the Icon row opens the icon picker and keeps the pick', (
    tester,
  ) async {
    final outcome = await openSheet(tester);

    await tapAndSettle(tester, find.text('Icon'));

    expect(find.byType(IconPickerSheet), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'cake');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byIcon(CalendarIcons.forKey('cake')!));

    expect(find.byType(IconPickerSheet), findsNothing);
    expect(find.byType(EventLookSheet), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.byTooltip(resetTooltip), findsOneWidget);
    expect(avatar(tester).icon, CalendarIcons.forKey('cake'));

    await done(tester);

    expect(outcome.result, const EventLookDraft(iconKey: 'cake'));
  });

  testWidgets('the whole palette is shown, never a show-more dot', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    expect(
      find.byType(ColorSwatchDot),
      findsNWidgets(CalendarPalette.all.length + 3),
    );
    for (final argb in CalendarPalette.all) {
      expect(swatchDot(argb), findsAtLeastNWidgets(1));
    }
    expect(find.byTooltip(categoryDefaultTooltip), findsOneWidget);
    expect(find.byTooltip('Add color'), findsOneWidget);
    expect(find.byTooltip('Manage colors'), findsOneWidget);
    expect(
      tester
          .widget<ColorSwatchPicker>(find.byType(ColorSwatchPicker))
          .collapsible,
      isFalse,
    );
  });

  testWidgets('the sheet is content-sized and keeps its height', (
    tester,
  ) async {
    final swatch = otherSwatch();
    await openSheet(tester);
    final before = sheetSize(tester);

    const runs = 2;
    const paletteRow =
        8 + runs * ColorSwatchDot.tapTarget + (runs - 1) * 2 + 12;
    const expectedHeight =
        FormMetrics.handleStripHeight +
        FormMetrics.headerHeight +
        FormMetrics.bodyTop +
        FormMetrics.titleRowMinHeight +
        1 +
        paletteRow +
        1 +
        FormMetrics.rowMinHeight +
        FormMetrics.bodyBottom;
    expect(before.height, expectedHeight);
    expect(before.height, lessThan(surface.height * 0.92));

    await tapAndSettle(tester, swatchDot(swatch));
    expect(sheetSize(tester), before);

    await tapAndSettle(tester, find.byType(Switch));
    expect(sheetSize(tester), before);

    await tapAndSettle(tester, find.byTooltip(categoryDefaultTooltip));
    expect(sheetSize(tester), before);
  });

  testWidgets('the header stays above the scroll view under a tall keyboard', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 1180);
    await openSheet(tester);

    final box = sheetSize(tester);
    expect(box.height, greaterThan(0));
    expect(box.height, lessThanOrEqualTo(surface.height * 0.92));
    final view = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .first;
    expect(view.padding!.resolve(TextDirection.ltr).bottom, 24 + 1180);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tapAndSettle(tester, find.byIcon(Icons.close_rounded));
    expect(find.byType(EventLookSheet), findsNothing);
  });
}
