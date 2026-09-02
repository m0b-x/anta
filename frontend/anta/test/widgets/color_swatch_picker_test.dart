import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/color_swatch_picker.dart';

import '../database/support/db_test_support.dart';

/// The picker is one widget standing in five places, so what is worth pinning
/// is the part each of those places used to hand-roll: the default dot is the
/// selection when the value is null, a colour that is no longer in the palette
/// still shows up selected rather than vanishing (an event coloured before its
/// swatch was deleted), a built-in offers no long-press menu while the user's
/// own does, and a colour added anywhere repaints a picker already on screen.
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

  /// The dots the picker rendered, in order.
  List<ColorSwatchDot> dots(WidgetTester tester) =>
      tester.widgetList<ColorSwatchDot>(find.byType(ColorSwatchDot)).toList();

  ColorSwatchDot dotOf(WidgetTester tester, int argb) =>
      dots(tester).firstWhere((d) => d.color?.toARGB32() == argb);

  testWidgets('renders the built-ins plus the wheel and manage dots', (
    tester,
  ) async {
    await pumpPicker(tester);

    expect(
      dots(tester).length,
      CalendarColors.swatchPalette.length + 2,
      reason: 'no default option, no custom colours: palette + wheel + manage',
    );
  });

  testWidgets('the default dot carries the selection while the value is null', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(color: Colors.teal),
    );

    expect(dots(tester).first.selected, isTrue);
    expect(dots(tester).where((d) => d.selected), hasLength(1));
  });

  testWidgets('tapping a swatch reports it and moves the check', (
    tester,
  ) async {
    await pumpPicker(
      tester,
      defaultOption: const ColorSwatchDefault(color: Colors.teal),
    );

    await tester.tap(find.byWidget(dotOf(tester, builtIn)));
    await tester.pumpAndSettle();

    expect(dotOf(tester, builtIn).selected, isTrue);
    expect(dots(tester).first.selected, isFalse);
  });

  testWidgets('a value outside the palette still renders, selected', (
    tester,
  ) async {
    await pumpPicker(tester, value: orphan);

    final dot = dotOf(tester, orphan);
    expect(dot.selected, isTrue);
    expect(CalendarPalette.contains(orphan), isFalse);
  });

  testWidgets('only the user\'s own swatches offer the long-press menu', (
    tester,
  ) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    await pumpPicker(tester);

    expect(dotOf(tester, custom).onLongPress, isNotNull);
    expect(dotOf(tester, builtIn).onLongPress, isNull);
  });

  testWidgets('a colour added elsewhere repaints a picker already on screen', (
    tester,
  ) async {
    await pumpPicker(tester);
    expect(dots(tester).any((d) => d.color?.toARGB32() == custom), isFalse);

    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    await tester.pumpAndSettle();

    expect(dotOf(tester, custom).color?.toARGB32(), custom);
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
    await pumpPicker(tester);

    final collapsed = dots(tester).length;
    expect(
      collapsed,
      lessThan(CalendarPalette.all.length),
      reason: 'a full palette is nine rows of circles inside a form',
    );

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();

    expect(dots(tester).length, greaterThan(collapsed));
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
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
    await pumpPicker(tester, value: last);

    expect(dotOf(tester, last).selected, isTrue);
  });

  testWidgets('a deleted colour leaves every picker', (tester) async {
    final service = await CalendarPaletteService.getInstance();
    await service.add(custom);
    await pumpPicker(tester);

    await service.remove(custom);
    await tester.pumpAndSettle();

    expect(dots(tester).any((d) => d.color?.toARGB32() == custom), isFalse);
  });
}
