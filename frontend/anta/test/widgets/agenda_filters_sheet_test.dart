import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/widgets/agenda_filters_sheet.dart';

/// The sheet edits a **draft** and returns it on Apply, so the property worth
/// pinning for the fasting control is that a segment tap survives the round
/// trip — and that the control is absent entirely while fasting is inert,
/// which is what keeps an unconfigured install from being offered a choice
/// that cannot change anything.
void main() {
  /// Opens the sheet and hands back a holder the Apply result lands in.
  Future<_Applied> openSheet(
    WidgetTester tester,
    UpcomingAgendaFilters initial,
  ) async {
    final applied = _Applied();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                applied.value = await AgendaFiltersSheet.show(
                  context,
                  filters: initial,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return applied;
  }

  /// The sheet's body scrolls, and the Display section sits at the bottom of
  /// it — so every fasting assertion has to reach it first.
  Future<void> scrollTo(WidgetTester tester, Finder target) {
    return tester.dragUntilVisible(
      target,
      find.byType(SingleChildScrollView).first,
      const Offset(0, -80),
    );
  }

  // "Every one"/"Every day" and "One card" label segments on **three** display
  // controls now, so every assertion addresses them by position rather than by
  // text alone. They are built in order: events, fasting (only when a tradition
  // is configured), then holidays.
  Finder segmentAt(String label, int index) => find.text(label).at(index);

  testWidgets('the fasting control is absent while fasting is inert', (
    tester,
  ) async {
    await openSheet(tester, const UpcomingAgendaFilters());
    await scrollTo(tester, find.text('Holiday rows'));

    expect(find.text('Fasting rows'), findsNothing);
    expect(find.text('Periods'), findsNothing);
    // Events and holidays are never inert, so their two controls remain — and
    // between them they carry "One card" twice.
    expect(find.text('Event rows'), findsOneWidget);
    expect(find.text('One card'), findsNWidgets(2));
  });

  testWidgets('picking one holiday card survives Apply', (tester) async {
    final applied = await openSheet(tester, const UpcomingAgendaFilters());

    await scrollTo(tester, find.text('Holiday rows'));
    await tester.tap(find.text('One card').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applied.value, isNotNull);
    expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.summary);
  });

  testWidgets('Reset returns the holiday presentation to every day', (
    tester,
  ) async {
    final applied = await openSheet(
      tester,
      const UpcomingAgendaFilters(holidayDisplay: AgendaHolidayDisplay.summary),
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.everyDay);
  });

  testWidgets('the event control offers all three presentations', (
    tester,
  ) async {
    await openSheet(tester, const UpcomingAgendaFilters());
    await scrollTo(tester, find.text('Event rows'));

    expect(find.text('Every one'), findsOneWidget);
    expect(find.text('Per event'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking one event card survives Apply', (tester) async {
    final applied = await openSheet(tester, const UpcomingAgendaFilters());

    await scrollTo(tester, find.text('Event rows'));
    await tester.tap(find.text('One card').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applied.value!.eventDisplay, AgendaEventDisplay.summary);
    // The three axes are independent: picking one must not drag the others.
    expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.everyDay);
  });

  testWidgets('Reset returns the event presentation to every occurrence', (
    tester,
  ) async {
    final applied = await openSheet(
      tester,
      const UpcomingAgendaFilters(eventDisplay: AgendaEventDisplay.summary),
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(applied.value!.eventDisplay, AgendaEventDisplay.everyOccurrence);
  });

  group('with a tradition configured', () {
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    testWidgets('both display controls stand side by side', (tester) async {
      await openSheet(tester, const UpcomingAgendaFilters());
      await scrollTo(tester, find.text('Holiday rows'));

      expect(find.text('Fasting rows'), findsOneWidget);
      expect(find.text('Holiday rows'), findsOneWidget);
      // Three fasting segments plus two holiday ones, so the shared labels
      // appear twice and "Periods" only once.
      expect(find.text('Periods'), findsOneWidget);
      // Fasting and holidays both say "Every day"; all three say "One card".
      expect(find.text('Every day'), findsNWidgets(2));
      expect(find.text('One card'), findsNWidgets(3));
      // Three labels in one segmented row is the layout most at risk here;
      // they ellipsize rather than overflow, exactly like the event-type
      // control above them.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the two axes move independently', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await scrollTo(tester, find.text('Holiday rows'));
      await tester.tap(segmentAt('One card', 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied.value!.fastingDisplay, AgendaFastingDisplay.summary);
      // Untouched: picking a fasting presentation must not drag holidays along.
      expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.everyDay);
    });

    testWidgets('Reset returns the presentation to periods', (tester) async {
      final applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(
          fastingDisplay: AgendaFastingDisplay.summary,
        ),
      );

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied.value!.fastingDisplay, AgendaFastingDisplay.periods);
    });
  });
}

/// Mutable holder for the sheet's Apply result — the sheet is awaited inside a
/// button callback, so the value arrives after the tap that dismissed it.
class _Applied {
  UpcomingAgendaFilters? value;
}
