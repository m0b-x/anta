import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/agenda_day_list_sheet.dart';
import 'package:anta/widgets/color_palette_sheet.dart';
import 'package:anta/widgets/color_picker_sheet.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/event_detail_sheet.dart';

import '../database/support/db_test_support.dart';

/// `showModalBottomSheet(useSafeArea: true)` guards the **status bar** only —
/// its route wraps the sheet in `SafeArea(bottom: false)`. A sheet sitting on
/// the bottom edge of the screen therefore runs underneath the system
/// navigation bar (gesture pill or three-button bar) unless it pads itself,
/// and the last row of a scrollable is what disappears under it.
///
/// Every calendar sheet answers this the same way: the larger of the keyboard
/// inset and the system's bottom inset, added to the scrollable's bottom
/// padding (or to the whole sheet where a fixed footer sits below the scroll
/// view). These tests pin that the padding actually responds to the inset,
/// which a `const EdgeInsets` cannot do.
///
/// **Add every new sheet here.** This is the app's most-repeated defect — four
/// separate rounds of it have shipped — and it is invisible in review because
/// a sheet padded by `viewInsets` alone looks correct with the keyboard up.
void main() {
  const navBar = 48.0;

  // The colour sheets resolve settings before presenting (the picker reads
  // its remembered geometry, the palette warms its service), so they need a
  // backend bound or they never open inside a widget test.
  late AppDatabase db;

  setUp(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  /// A device with a three-button navigation bar and no keyboard.
  void sizeSurfaceWithNavBar(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
  }

  /// Bottom padding of the sheet's scrollable, resolved to pixels.
  double listBottomPadding(WidgetTester tester) {
    final list = tester.widget<ListView>(find.byType(ListView));
    return list.padding!.resolve(TextDirection.ltr).bottom;
  }

  Future<void> openFrom(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the event detail sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    final day = DateTime.utc(2026, 8, 25);
    await openFrom(
      tester,
      (context) => EventDetailSheet.show(
        context,
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: day,
          rule: const DailyRecurrence(),
        ),
        day: day,
      ),
    );

    expect(
      listBottomPadding(tester),
      greaterThanOrEqualTo(navBar),
      reason:
          'the description and the occurrence chips are the last things in '
          'the list, and they rendered under the nav bar',
    );
  });

  /// Opens the drill-down on a one-entry August list, the fixture all three
  /// mode variants below share.
  Future<void> openDayListSheet(WidgetTester tester) {
    return openFrom(
      tester,
      (context) => AgendaDayListSheet.show(
        context,
        AgendaDayList(
          title: 'Holidays',
          subtitle: '2 holidays',
          source: const AgendaDayListHolidaySource(),
          color: const Color(0xFFFFB300),
          entries: [
            AgendaDayListEntry(
              day: DateTime.utc(2026, 8, 15),
              icon: Icons.celebration_rounded,
              color: const Color(0xFFFFB300),
              title: 'Assumption of Mary',
              subtitle: 'Saturday, August 15',
            ),
          ],
        ),
        resolve: (_, _) => const [],
        appearance: const CalendarAppearance(),
        today: DateTime.utc(2026, 8, 1),
        windowStart: DateTime.utc(2026, 8, 1),
        windowEnd: DateTime.utc(2026, 8, 31),
      ),
    );
  }

  testWidgets('the agenda day list sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openDayListSheet(tester);

    expect(listBottomPadding(tester), greaterThanOrEqualTo(navBar));
  });

  testWidgets('the day list sheet clears the navigation bar in month mode', (
    tester,
  ) async {
    // Month mode is a `CustomScrollView`, so its clearance is a trailing
    // sliver rather than a list padding — a different code path, and the one
    // the rows under the mini calendar end on.
    sizeSurfaceWithNavBar(tester);
    await openDayListSheet(tester);
    await tester.tap(find.byIcon(Icons.calendar_view_month_rounded));
    await tester.pumpAndSettle();

    final spacer =
        tester
                .widgetList<SliverToBoxAdapter>(find.byType(SliverToBoxAdapter))
                .last
                .child
            as SizedBox;
    expect(spacer.height, greaterThanOrEqualTo(navBar));
  });

  testWidgets('the day list sheet clears the navigation bar in year mode', (
    tester,
  ) async {
    // Year mode is a `GridView` with its own padding; the last row of tiles is
    // what runs under the bar without it.
    sizeSurfaceWithNavBar(tester);
    await openDayListSheet(tester);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    final padding = tester
        .widget<GridView>(find.byType(GridView))
        .padding!
        .resolve(TextDirection.ltr)
        .bottom;
    expect(padding, greaterThanOrEqualTo(navBar));
  });

  testWidgets('a sheet on a device without a navigation bar is unpadded', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
    final day = DateTime.utc(2026, 8, 25);
    await openFrom(
      tester,
      (context) => EventDetailSheet.show(
        context,
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: day,
          rule: const OneTimeRecurrence(),
        ),
        day: day,
      ),
    );

    expect(
      listBottomPadding(tester),
      24,
      reason:
          'the clearance is additive — with nothing to clear the sheet keeps '
          'exactly its designed padding',
    );
  });

  testWidgets('the colour picker sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(tester, (context) => ColorPickerSheet.show(context));
    await tester.pumpAndSettle();

    // This sheet ends in a fixed action row rather than a scrollable, so the
    // clearance is on the whole sheet: the assertion is that Select sits
    // clear of the bar, not that some padding value exists.
    final selectBottom = tester
        .getRect(find.widgetWithText(FilledButton, 'Select'))
        .bottom;
    expect(
      selectBottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - navBar),
      reason: 'Cancel and Select ran under the gesture bar',
    );
  });

  testWidgets('the colour palette sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(tester, (context) => ColorPaletteSheet.show(context));

    final padding = tester
        .widgetList<SliverPadding>(find.byType(SliverPadding))
        .last
        .padding
        .resolve(TextDirection.ltr)
        .bottom;
    expect(padding, greaterThanOrEqualTo(navBar));
  });
}
