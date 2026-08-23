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

  testWidgets('the fasting control is absent while fasting is inert', (
    tester,
  ) async {
    await openSheet(tester, const UpcomingAgendaFilters());

    expect(find.text('Fasting rows'), findsNothing);
    expect(find.text('One card'), findsNothing);
  });

  group('with a tradition configured', () {
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    testWidgets('offers all three presentations', (tester) async {
      await openSheet(tester, const UpcomingAgendaFilters());
      await scrollTo(tester, find.text('Fasting rows'));

      expect(find.text('Every day'), findsOneWidget);
      expect(find.text('Periods'), findsOneWidget);
      expect(find.text('One card'), findsOneWidget);
      // Three labels in one segmented row is the layout most at risk here;
      // they ellipsize rather than overflow, exactly like the event-type
      // control above them.
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking one card survives Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await scrollTo(tester, find.text('One card'));
      await tester.tap(find.text('One card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied.value, isNotNull);
      expect(applied.value!.fastingDisplay, AgendaFastingDisplay.summary);
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
