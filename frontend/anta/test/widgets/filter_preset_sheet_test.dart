import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/widgets/filter_preset_sheet.dart';

import '../database/support/db_test_support.dart';

/// The saved-filter sheet is the one surface where a preset is *chosen*, so
/// what it must get right is: finding one by what it does as well as by what
/// it was called, saying which one is currently in use, and handing back the
/// filters rather than the preset (the page applies filters, not rows).
void main() {
  late AppDatabase db;
  late FilterPresetService service;

  const tracked = CalendarGridFilters(trackedOnly: true);
  const missed = CalendarGridFilters(missedOnly: true);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    FilterPresetService.reset();
    db = await openTestDatabase();
    service = await FilterPresetService.forTesting(db);
  });

  tearDown(() async {
    FilterPresetService.reset();
    await db.close();
  });

  /// Collects what the sheet popped. A holder rather than a return value:
  /// [pumpSheet] returns while the sheet is still open, so the result only
  /// exists after the test body has tapped something.
  late List<CalendarGridFilters?> popped;

  /// Hosts the sheet as a route so `Navigator.pop` has somewhere to go.
  Future<void> pumpSheet(
    WidgetTester tester, {
    CalendarGridFilters current = CalendarGridFilters.none,
  }) async {
    popped = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped.add(
                    await FilterPresetSheet.show(context, current: current),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The sheet resolves the service in initState; the instance is already
    // bound, so one settle is enough to get past the spinner.
    await tester.pumpAndSettle();
    expect(find.byType(FilterPresetSheet), findsOneWidget);
  }

  testWidgets('an empty database shows the empty state, not a search field', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('No saved filters yet'), findsOneWidget);
  });

  testWidgets('saved filters are listed with what they filter', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);

    expect(find.text('Training'), findsOneWidget);
    // The subtitle is the shared description, not the raw blob.
    expect(find.text('Tracked'), findsOneWidget);
  });

  testWidgets('the search field matches the name', (tester) async {
    await service.create(name: 'Training', filters: tracked);
    await service.create(name: 'Skipped days', filters: missed);

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'train');
    await tester.pumpAndSettle();

    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Skipped days'), findsNothing);
  });

  /// Findable by what it does, not only by what it was called — the reason
  /// the description is part of the match.
  testWidgets('the search field also matches the description', (tester) async {
    await service.create(name: 'Zebra', filters: tracked);
    await service.create(name: 'Aardvark', filters: missed);

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'tracked');
    await tester.pumpAndSettle();

    expect(find.text('Zebra'), findsOneWidget);
    expect(find.text('Aardvark'), findsNothing);
  });

  testWidgets('a search with no hits says so', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.textContaining('No saved filter matches'), findsOneWidget);
  });

  /// The sheet hands back **filters**, not the preset row: the page applies a
  /// filter set, and giving it a row would make it unwrap one.
  testWidgets('tapping a preset pops its filters', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);
    await tester.tap(find.text('Training'));
    await tester.pumpAndSettle();

    expect(find.byType(FilterPresetSheet), findsNothing);
    expect(popped, [tracked]);
  });

  testWidgets('dismissing pops nothing to apply', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);
    // The scrim, not a row.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(FilterPresetSheet), findsNothing);
    expect(popped, [null]);
  });

  /// Value equality on the filters, not the id: what makes a preset "the one
  /// in use" is that the calendar shows exactly what it saves.
  testWidgets('the preset holding the current filters is marked in use', (
    tester,
  ) async {
    await service.create(name: 'Training', filters: tracked);
    await service.create(name: 'Skipped days', filters: missed);

    await pumpSheet(tester, current: tracked);

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });

  testWidgets('with nothing applied, no preset is marked in use', (
    tester,
  ) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);

    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });

  group('saving the live filter from here', () {
    /// The row exists for the one state it means something in: a filter is
    /// applied, and it is not already in the list.
    testWidgets('is offered for an applied filter nobody saved', (
      tester,
    ) async {
      await pumpSheet(tester, current: tracked);

      expect(find.text('Save the current filter'), findsOneWidget);
      // It says what it would save, through the shared description.
      expect(find.text('Tracked'), findsOneWidget);
    });

    testWidgets('is not offered when nothing is filtered', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);

      expect(find.text('Save the current filter'), findsNothing);
    });

    testWidgets('is not offered once that filter is saved', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester, current: tracked);

      expect(find.text('Save the current filter'), findsNothing);
    });

    /// A query is a find, not a create — an action row among the results is
    /// noise, and it would sit there unmatched by the query that produced it.
    testWidgets('is hidden while searching', (tester) async {
      await service.create(name: 'Training', filters: missed);

      await pumpSheet(tester, current: tracked);
      expect(find.text('Save the current filter'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'train');
      await tester.pumpAndSettle();

      expect(find.text('Save the current filter'), findsNothing);
    });

    testWidgets('saves without closing the sheet', (tester) async {
      await pumpSheet(tester, current: tracked);

      await tester.tap(find.text('Save the current filter'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'From here');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(service.presets.single.name, 'From here');
      expect(service.presets.single.filters, tracked);
      // Still open, and the new row now reads as the one in use.
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(find.text('From here'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // And the offer is gone, because the filter is saved now.
      expect(find.text('Save the current filter'), findsNothing);
    });
  });

  group('showing everything again', () {
    /// The one answer the sheet could not give before: "no lens". Clearing
    /// otherwise meant closing, opening the filter sheet, Reset, Apply.
    testWidgets('pops a cleared filter set', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester, current: tracked);
      await tester.tap(find.text('Show everything'));
      await tester.pumpAndSettle();

      expect(find.byType(FilterPresetSheet), findsNothing);
      expect(popped.single?.isEmpty, isTrue);
    });

    /// `cleared()`, not `CalendarGridFilters.none`: the panel opt-out is a
    /// preference about the day panel, not something being hidden, and the
    /// filter sheet's Reset keeps it for the same reason.
    testWidgets('keeps the panel opt-out', (tester) async {
      const withPanelOptOut = CalendarGridFilters(
        trackedOnly: true,
        panelShowsAll: true,
      );

      await pumpSheet(tester, current: withPanelOptOut);
      await tester.tap(find.text('Show everything'));
      await tester.pumpAndSettle();

      expect(popped.single?.isEmpty, isTrue);
      expect(popped.single?.panelShowsAll, isTrue);
    });

    /// Disabled rather than hidden, so the header cannot change height between
    /// two openings of the same sheet.
    testWidgets('is disabled when nothing is filtered', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Show everything'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  /// Soft, never blocking — the category editor's rule. Presets are keyed by
  /// id, so a duplicate name is confusing rather than corrupting.
  testWidgets('a duplicate name warns but still saves', (tester) async {
    await service.create(name: 'Training', filters: missed);

    await pumpSheet(tester, current: tracked);
    await tester.tap(find.text('Save the current filter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Training');
    await tester.pumpAndSettle();

    expect(find.text('"Training" already exists'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(service.presets.map((p) => p.name), ['Training', 'Training']);
  });
}
