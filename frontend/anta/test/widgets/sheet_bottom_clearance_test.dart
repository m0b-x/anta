import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/agenda_day_list_sheet.dart';
import 'package:anta/widgets/event_detail_sheet.dart';

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
void main() {
  const navBar = 48.0;

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

  testWidgets('the agenda day list sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(
      tester,
      (context) => AgendaDayListSheet.show(
        context,
        AgendaDayList(
          title: 'Holidays',
          subtitle: '2 holidays',
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
        editTooltip: 'Edit event',
      ),
    );

    expect(listBottomPadding(tester), greaterThanOrEqualTo(navBar));
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
}
