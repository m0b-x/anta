import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/color_palette_sheet.dart';

import '../database/support/db_test_support.dart';

/// The management sheet's two destructive paths are what earn a widget test:
/// both are confirmed, both persist immediately (there is no Save), and both
/// must leave the built-in half alone.
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

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ColorPaletteSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty palette explains itself instead of showing nothing', (
    tester,
  ) async {
    await openSheet(tester);

    expect(
      find.text(
        'No colors of your own yet. Add one and it appears in '
        'every picker.',
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Reset colors'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reset colors'),
    );
    expect(
      reset.onPressed,
      isNull,
      reason: 'nothing to reset while the palette is untouched',
    );
  });

  testWidgets('deleting asks first, then drops only that colour', (
    tester,
  ) async {
    await service.add(customA);
    await service.add(customB);
    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete color'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(service.customColors, [customB]);
    expect(find.text('#123456'), findsNothing);
    expect(find.text('#654321'), findsOneWidget);
  });

  testWidgets('dismissing the confirmation keeps the colour', (tester) async {
    await service.add(customA);
    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(service.customColors, [customA]);
  });

  testWidgets('dragging a row reorders the palette itself', (tester) async {
    await service.add(customA);
    await service.add(customB);
    await openSheet(tester);

    // The handle is the drag target, not the row: tapping the row edits it.
    final handles = find.byIcon(Icons.drag_handle);
    final rowHeight =
        tester.getCenter(handles.last).dy - tester.getCenter(handles.first).dy;
    final gesture = await tester.startGesture(tester.getCenter(handles.last));
    await tester.pump(kPressTimeout);
    // Incremental moves, not one jump: the reorder target is recomputed per
    // pointer event, so a single teleport past the row above proves nothing.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(Offset(0, -rowHeight / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

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
    await openSheet(tester);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Reset colors'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(service.customColors, isEmpty);
    expect(CalendarPalette.all, CalendarPalette.defaults);
  });
}
