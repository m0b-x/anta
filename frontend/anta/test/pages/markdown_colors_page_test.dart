import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/markdown_colors_page.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../widgets/support/color_picker_robot.dart';

/// The markdown colours page is the one caller of the colour picker outside
/// the calendar: its add FAB prompts for a name, then opens the picker, and
/// a recolour opens it on the row's own colour. Both paths read one number
/// back from `ColorPickerSheet.show` and persist it to the markdown
/// palette, so the Tier 3 chrome swap of the picker has to leave them
/// whole. Driven through [ColorPickerRobot], which works on whatever picker
/// is open.
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

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const MarkdownColorsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types [name] into the open name dialog and confirms it.
  Future<void> nameColor(WidgetTester tester, String name) async {
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      name,
    );
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
    // The picker resolves its remembered geometry before it presents, so it
    // arrives a microtask after the dialog closes: two settles.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  }

  Future<Map<String, Color>> stored() async {
    final settings = await SettingsService.getInstance();
    return (await settings.getColorPalette()).toCustomColorMap();
  }

  testWidgets('adding a colour names it, picks it in the picker, shows it on '
      'the page and persists it', (tester) async {
    await pumpPage(tester);
    final picker = ColorPickerRobot(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await nameColor(tester, 'warm');

    expect(picker.isOpen, isTrue);
    await picker.typeHex('#3A7BDE');
    await picker.select();

    expect(picker.isOpen, isFalse);
    expect(find.text('warm'), findsOneWidget);
    expect(await stored(), {'warm': const Color(0xFF3A7BDE)});
  });

  testWidgets('a cancelled picker adds nothing', (tester) async {
    await pumpPage(tester);
    final picker = ColorPickerRobot(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await nameColor(tester, 'warm');
    expect(picker.isOpen, isTrue);
    await picker.cancel();

    expect(find.text('warm'), findsNothing);
    expect(await stored(), isEmpty);
  });

  testWidgets("a tap on a row recolours it: the picker opens on the row's "
      'colour and persists the pick', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.setCustomColors({'warm': const Color(0xFF3A7BDE)});
    await pumpPage(tester);
    final picker = ColorPickerRobot(tester);

    await tester.tap(find.text('warm'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(picker.isOpen, isTrue);
    expect(picker.hexText, '#3A7BDE');
    expect(picker.currentDotShown, isTrue);
    await picker.typeHex('#00FF00');
    await picker.select();

    expect(await stored(), {'warm': const Color(0xFF00FF00)});
  });
}
