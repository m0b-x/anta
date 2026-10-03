import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/widgets/filter_preset_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';

/// The saved-filter sheet is the one surface where a preset is *chosen*, so
/// what it must get right is: finding one by what it does as well as by what
/// it was called, saying which one is currently in use, and handing back the
/// filters rather than the preset (the page applies filters, not rows). Since
/// the 2026-09-27 migration into the grouped-row language the chrome is
/// pinned too: "No filter" as the first row, the search row past the
/// threshold, the save row dimmed rather than hidden, the ⋮ menu's items with
/// their ids, and no empty-state paragraph. Since 2026-09-29 the list is
/// reorderable, and the group at the end pins that: a drag on the handle or
/// a long press on the row moves a preset and persists the order, a drop
/// past the save row lands last, Move to top does the same in one tap, and
/// a live search locks all of it in place.
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

  /// Hosts the sheet as a route so `Navigator.pop` has somewhere to go, on a
  /// phone tall enough that thirteen rows never push the save row below the
  /// fold.
  Future<void> pumpSheet(
    WidgetTester tester, {
    CalendarGridFilters current = CalendarGridFilters.none,
    double height = 1600,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(800, height);
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
    // bound, so one settle is enough for the rows to fill in.
    await tester.pumpAndSettle();
    expect(find.byType(FilterPresetSheet), findsOneWidget);
  }

  Finder id(String value) => find.bySemanticsIdentifier(value);

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The check row carrying [label], read for its state.
  FormCheckRow rowNamed(WidgetTester tester, String label) =>
      tester.widget<FormCheckRow>(find.widgetWithText(FormCheckRow, label));

  FormActionRow saveRow(WidgetTester tester) => tester.widget<FormActionRow>(
    find.ancestor(
      of: id(SemanticsIds.filterPresetSave),
      matching: find.byType(FormActionRow),
    ),
  );

  /// One over the search threshold, with [named] listed first, so the search
  /// row is on screen before anything is typed.
  Future<void> seedPastThreshold({
    Map<String, CalendarGridFilters> named = const {},
  }) async {
    for (final entry in named.entries) {
      await service.create(name: entry.key, filters: entry.value);
    }
    for (var i = named.length; i <= AppConstants.listSearchThreshold; i++) {
      await service.create(
        name: 'Filler $i',
        filters: CalendarGridFilters(priorities: {i % 5 + 1}),
      );
    }
  }

  /// The ⋮ menu item wearing [itemId], read for whether it is enabled.
  PopupMenuItem<dynamic> menuItem(WidgetTester tester, String itemId) =>
      tester.widget(
            find.ancestor(
              of: id(itemId),
              matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
            ),
          )
          as PopupMenuItem<dynamic>;

  testWidgets('an empty database shows No filter checked, a dimmed save row '
      'and no paragraph', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('No saved filters yet'), findsNothing);
    expect(rowNamed(tester, 'No filter').checked, isTrue);
    expect(saveRow(tester).onTap, isNull);
    expect(find.text('Save the current filter'), findsOneWidget);
  });

  testWidgets('saved filters are listed with what they filter', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);

    expect(find.text('Training'), findsOneWidget);
    // The subtitle is the shared description, not the raw blob.
    expect(find.text('Tracked'), findsOneWidget);
    expect(id(SemanticsIds.filterPresetRow(service.presets.single.id)),
        findsOneWidget);
  });

  testWidgets('the search row appears only past the threshold', (
    tester,
  ) async {
    for (var i = 0; i < AppConstants.listSearchThreshold; i++) {
      await service.create(name: 'Filler $i', filters: tracked);
    }

    await pumpSheet(tester);

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the search field matches the name', (tester) async {
    await seedPastThreshold(named: {'Training': tracked, 'Skipped days': missed});

    await pumpSheet(tester);
    expect(id(SemanticsIds.filterPresetSearch), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'train');
    await tester.pumpAndSettle();

    expect(find.text('Training'), findsOneWidget);
    expect(find.text('Skipped days'), findsNothing);
    expect(find.textContaining('Filler'), findsNothing);
  });

  /// Findable by what it does, not only by what it was called — the reason
  /// the description is part of the match.
  testWidgets('the search field also matches the description', (tester) async {
    await seedPastThreshold(named: {'Zebra': tracked, 'Aardvark': missed});

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'tracked');
    await tester.pumpAndSettle();

    expect(find.text('Zebra'), findsOneWidget);
    expect(find.text('Aardvark'), findsNothing);
  });

  testWidgets('a search with no hits says so under the group', (tester) async {
    await seedPastThreshold(named: {'Training': tracked});

    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.textContaining('No saved filter matches'), findsOneWidget);
    // The field stays to clear the query, and the fixed rows stay put.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('No filter'), findsOneWidget);
    expect(find.text('Save the current filter'), findsOneWidget);
  });

  /// The sheet hands back **filters**, not the preset row: the page applies a
  /// filter set, and giving it a row would make it unwrap one.
  testWidgets('tapping a preset pops its filters', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);
    await tap(tester, find.text('Training'));

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

  testWidgets('the close button pops nothing to apply', (tester) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);
    await tap(tester, id(SemanticsIds.filterPresetClose));

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
    expect(rowNamed(tester, 'Training').checked, isTrue);
    expect(rowNamed(tester, 'Skipped days').checked, isFalse);
    expect(rowNamed(tester, 'No filter').checked, isFalse);
  });

  testWidgets('with nothing applied, No filter is the one row checked', (
    tester,
  ) async {
    await service.create(name: 'Training', filters: tracked);

    await pumpSheet(tester);

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(rowNamed(tester, 'No filter').checked, isTrue);
    expect(rowNamed(tester, 'Training').checked, isFalse);
  });

  group('saving the live filter from here', () {
    /// The row is live for the one state it means something in: a filter is
    /// applied, and it is not already in the list.
    testWidgets('is offered for an applied filter nobody saved', (
      tester,
    ) async {
      await pumpSheet(tester, current: tracked);

      expect(find.text('Save the current filter'), findsOneWidget);
      expect(saveRow(tester).onTap, isNotNull);
    });

    testWidgets('is dimmed when nothing is filtered', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);

      expect(find.text('Save the current filter'), findsOneWidget);
      expect(saveRow(tester).onTap, isNull);
    });

    testWidgets('is dimmed once that filter is saved', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester, current: tracked);

      expect(saveRow(tester).onTap, isNull);
    });

    /// A query is a find, not a create — an action row among the results is
    /// noise — but a row that vanishes moves the results under the finger,
    /// so it dims instead.
    testWidgets('is dimmed while searching, and back once the query clears', (
      tester,
    ) async {
      await seedPastThreshold(named: {'Training': missed});

      await pumpSheet(tester, current: tracked);
      expect(saveRow(tester).onTap, isNotNull);

      await tester.enterText(find.byType(TextField), 'train');
      await tester.pumpAndSettle();

      expect(find.text('Save the current filter'), findsOneWidget);
      expect(saveRow(tester).onTap, isNull);

      await tap(tester, find.byTooltip('Clear search'));

      expect(saveRow(tester).onTap, isNotNull);
    });

    testWidgets('at the limit it says so above the sheet, where a finger can '
        'reach the message, and saves nothing', (tester) async {
      for (var i = 0; i < FilterPresetService.maxPresets; i++) {
        await service.create(
          name: 'Filler $i',
          filters: CalendarGridFilters(priorities: {i % 5 + 1}),
        );
      }
      // Tall enough for the save row, the last of fifty-one, to be on screen.
      await pumpSheet(tester, current: tracked, height: 4400);
      expect(saveRow(tester).onTap, isNotNull);

      await tap(tester, find.text('Save the current filter'));

      // A bar on the page's `Scaffold` would be drawn under this route.
      expect(
        find.text('You can save up to 50 filters').hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      // No name was asked for: the only dialog the sheet opens has none up.
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.presets, hasLength(FilterPresetService.maxPresets));
    });

    testWidgets('saves without closing the sheet', (tester) async {
      await pumpSheet(tester, current: tracked);

      await tap(tester, find.text('Save the current filter'));
      await tester.enterText(find.byType(TextField).last, 'From here');
      await tap(tester, find.text('Save'));

      expect(service.presets.single.name, 'From here');
      expect(service.presets.single.filters, tracked);
      // Still open, and the new row now reads as the one in use.
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(find.text('From here'), findsOneWidget);
      expect(rowNamed(tester, 'From here').checked, isTrue);
      // And the offer is dimmed, because the filter is saved now.
      expect(saveRow(tester).onTap, isNull);
    });
  });

  group('No filter', () {
    /// The one answer the sheet could not give before: "no lens". Clearing
    /// otherwise meant closing, opening the filter sheet, Reset, Apply.
    testWidgets('pops a cleared filter set', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester, current: tracked);
      await tap(tester, id(SemanticsIds.filterPresetNone));

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
      await tap(tester, find.text('No filter'));

      expect(popped.single?.isEmpty, isTrue);
      expect(popped.single?.panelShowsAll, isTrue);
    });

    testWidgets('is checked when nothing is filtered, above the list', (
      tester,
    ) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);

      final none = rowNamed(tester, 'No filter');
      expect(none.checked, isTrue);
      expect(none.exclusive, isTrue);
      expect(
        tester.getTopLeft(find.text('No filter')).dy,
        lessThan(tester.getTopLeft(find.text('Training')).dy),
      );
    });
  });

  group('the ⋮ menu', () {
    testWidgets('carries its ids and disables Update while in use', (
      tester,
    ) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester, current: tracked);
      await tap(
        tester,
        id(SemanticsIds.filterPresetOptions(service.presets.single.id)),
      );

      expect(id(SemanticsIds.filterPresetRename), findsOneWidget);
      expect(id(SemanticsIds.filterPresetUpdate), findsOneWidget);
      expect(id(SemanticsIds.filterPresetDelete), findsOneWidget);
      expect(menuItem(tester, SemanticsIds.filterPresetRename).enabled, isTrue);
      expect(menuItem(tester, SemanticsIds.filterPresetUpdate).enabled, isFalse);
      expect(menuItem(tester, SemanticsIds.filterPresetDelete).enabled, isTrue);
    });

    testWidgets('disables Update while nothing is filtered', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);
      await tap(
        tester,
        id(SemanticsIds.filterPresetOptions(service.presets.single.id)),
      );

      expect(menuItem(tester, SemanticsIds.filterPresetUpdate).enabled, isFalse);
    });

    testWidgets('Update re-points the preset at the live filter in place', (
      tester,
    ) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester, current: missed);
      await tap(
        tester,
        id(SemanticsIds.filterPresetOptions(service.presets.single.id)),
      );
      expect(menuItem(tester, SemanticsIds.filterPresetUpdate).enabled, isTrue);
      await tap(tester, id(SemanticsIds.filterPresetUpdate));

      expect(service.presets.single.filters, missed);
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(rowNamed(tester, 'Training').checked, isTrue);
      expect(find.text('Missed'), findsOneWidget);
    });

    testWidgets('Rename renames in place and keeps the sheet open', (
      tester,
    ) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);
      await tap(
        tester,
        id(SemanticsIds.filterPresetOptions(service.presets.single.id)),
      );
      await tap(tester, id(SemanticsIds.filterPresetRename));
      await tester.enterText(find.byType(TextField).last, 'Gym days');
      await tap(tester, find.text('Save'));

      expect(service.presets.single.name, 'Gym days');
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(find.text('Gym days'), findsOneWidget);
      expect(find.text('Training'), findsNothing);
    });

    testWidgets('Delete asks first and removes in place', (tester) async {
      await service.create(name: 'Training', filters: tracked);

      await pumpSheet(tester);
      await tap(
        tester,
        id(SemanticsIds.filterPresetOptions(service.presets.single.id)),
      );
      await tap(tester, id(SemanticsIds.filterPresetDelete));

      expect(find.text('Delete saved filter'), findsOneWidget);
      expect(service.presets, hasLength(1));

      await tap(tester, find.widgetWithText(FilledButton, 'Delete'));

      expect(service.presets, isEmpty);
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(find.text('Training'), findsNothing);
    });
  });

  group('reorder', () {
    Future<List<String>> seedNamed(List<String> names) async {
      for (final name in names) {
        await service.create(
          name: name,
          filters: CalendarGridFilters(
            priorities: {names.indexOf(name) % 5 + 1},
          ),
        );
      }
      return [for (final p in service.presets) p.id];
    }

    List<String> storedNames() => [for (final p in service.presets) p.name];

    /// The names in the order the sheet draws them, top to bottom.
    List<String> shownNames(WidgetTester tester, List<String> names) {
      final byTop = [
        for (final name in names)
          (name, tester.getTopLeft(find.text(name)).dy),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final entry in byTop) entry.$1];
    }

    Finder handleOf(String presetId) =>
        id(SemanticsIds.filterPresetHandle(presetId));

    /// A drop's animation settles in a frame or two; a stuck one would
    /// otherwise hold the suite for pumpAndSettle's ten-minute default.
    Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    /// Well past every row: the list reports an index beyond the save row
    /// (or before the first row) and the sheet clamps it into the preset
    /// run, so a drag that overshoots lands last (or first), never outside
    /// the group.
    const past = 600.0;

    testWidgets('every preset row carries a handle with its id and name', (
      tester,
    ) async {
      final ids = await seedNamed(['A', 'B']);

      await pumpSheet(tester);

      for (final presetId in ids) {
        expect(handleOf(presetId), findsOneWidget);
        expect(
          tester.getSemantics(handleOf(presetId)).getSemanticsData().label,
          'Drag to reorder',
        );
      }
      expect(find.byType(ReorderableListView), findsOneWidget);
      // The handle leads the row, the ⋮ ends it.
      expect(
        tester.getTopLeft(handleOf(ids.first)).dx,
        lessThan(tester.getTopLeft(find.text('A')).dx),
      );
      expect(
        tester.getTopLeft(find.text('A')).dx,
        lessThan(
          tester.getTopLeft(id(SemanticsIds.filterPresetOptions(ids.first))).dx,
        ),
      );
    });

    testWidgets('a drag on the handle reorders the list and persists it', (
      tester,
    ) async {
      final ids = await seedNamed(['A', 'B', 'C']);

      await pumpSheet(tester);
      await tester.drag(handleOf(ids.first), const Offset(0, past));
      await settle(tester);

      expect(shownNames(tester, ['A', 'B', 'C']), ['B', 'C', 'A']);
      expect(storedNames(), ['B', 'C', 'A']);
      expect(service.presets.map((p) => p.sortOrder), [0, 1, 2]);
      // The save row is an item of the same list so the run draws as one
      // group; the drop landed above it, never below.
      expect(
        tester.getTopLeft(find.text('A')).dy,
        lessThan(tester.getTopLeft(find.text('Save the current filter')).dy),
      );
      // In place: the sheet is still open and nothing was applied.
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(popped, isEmpty);
    });

    /// Past the threshold the search row leads the list, so the list's
    /// indices are one ahead of the presets': the one place a reorder can
    /// silently move the row below the one lifted.
    testWidgets('with the search row on screen, a drag past the top lands '
        'first, under the field', (tester) async {
      await seedPastThreshold(named: {'Zebra': tracked});
      final last = service.presets.last;

      await pumpSheet(tester);
      expect(find.byType(TextField), findsOneWidget);
      // Thirteen rows put the last handle far down the sheet, so the
      // distance is measured: well above the "No filter" row, past the field.
      final aboveTheList = tester.getTopLeft(find.text('No filter')).dy - 40;
      await tester.drag(
        handleOf(last.id),
        Offset(0, aboveTheList - tester.getCenter(handleOf(last.id)).dy),
      );
      await settle(tester);

      expect(storedNames().first, last.name);
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        lessThan(tester.getTopLeft(find.text(last.name)).dy),
      );
    });

    testWidgets('with the search row on screen, a drag past the bottom lands '
        'last, above the save row', (tester) async {
      await seedPastThreshold(named: {'Zebra': tracked});
      final first = service.presets.first;

      await pumpSheet(tester);
      final belowTheList =
          tester.getBottomLeft(find.text('Save the current filter')).dy + 40;
      await tester.drag(
        handleOf(first.id),
        Offset(0, belowTheList - tester.getCenter(handleOf(first.id)).dy),
      );
      await settle(tester);

      expect(storedNames().last, 'Zebra');
      expect(
        tester.getTopLeft(find.text('Zebra')).dy,
        lessThan(tester.getTopLeft(find.text('Save the current filter')).dy),
      );
    });

    /// Flutter's reorderable list wraps every item in a semantics container
    /// carrying move up / down / to start / to end, so a screen reader can
    /// reorder without a drag; the row, its handle and its ⋮ stay their own
    /// nodes inside it.
    testWidgets('every preset row carries the reorder actions for a screen '
        'reader', (tester) async {
      final ids = await seedNamed(['A', 'B']);

      await pumpSheet(tester);

      for (final presetId in ids) {
        final data = tester
            .getSemantics(find.byKey(ValueKey(presetId)))
            .getSemanticsData();
        expect(data.customSemanticsActionIds, isNotEmpty);
      }
      expect(id(SemanticsIds.filterPresetRow(ids.first)), findsOneWidget);
      expect(handleOf(ids.first), findsOneWidget);
      expect(id(SemanticsIds.filterPresetOptions(ids.first)), findsOneWidget);
    });

    testWidgets('a drag past the top lands first, under No filter', (
      tester,
    ) async {
      final ids = await seedNamed(['A', 'B', 'C']);

      await pumpSheet(tester);
      await tester.drag(handleOf(ids.last), const Offset(0, -past));
      await settle(tester);

      expect(shownNames(tester, ['A', 'B', 'C']), ['C', 'A', 'B']);
      expect(storedNames(), ['C', 'A', 'B']);
      expect(
        tester.getTopLeft(find.text('No filter')).dy,
        lessThan(tester.getTopLeft(find.text('C')).dy),
      );
    });

    testWidgets('a long press anywhere on the row lifts it too', (
      tester,
    ) async {
      await seedNamed(['A', 'B', 'C']);

      await pumpSheet(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('A')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, past));
      await tester.pump();
      await gesture.up();
      await settle(tester);

      expect(storedNames(), ['B', 'C', 'A']);
      // A long press is a lift, never a pick.
      expect(popped, isEmpty);
    });

    testWidgets('a drag past the fold scrolls the list', (tester) async {
      final ids = await seedNamed([for (var i = 0; i < 12; i++) 'Preset $i']);

      // A phone short enough that twelve rows overflow the sheet's clamp.
      await pumpSheet(tester, height: 700);
      final scrollable = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);

      // Lift the first row and hold it at the sheet's bottom edge: the
      // edge auto-scroller has to move the list under it.
      final gesture = await tester.startGesture(
        tester.getCenter(handleOf(ids.first)),
      );
      await tester.pump();
      final sheetBottom = tester.getBottomLeft(find.byType(ReorderableListView)).dy;
      await gesture.moveTo(Offset(400, sheetBottom - 10));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(position.pixels, greaterThan(0));
      await gesture.up();
      await settle(tester);

      expect(storedNames().first, isNot('Preset 0'));
    });

    testWidgets('a live search locks the handles and Move to top in place', (
      tester,
    ) async {
      await seedPastThreshold(named: {'Zebra': tracked});
      final zebra = service.presets.first.id;

      await pumpSheet(tester);
      expect(find.byType(ReorderableDragStartListener), findsWidgets);

      await tester.enterText(find.byType(TextField), 'zeb');
      await tester.pumpAndSettle();

      // Still there, still a node with its name; greyed, and wired to no drag.
      expect(handleOf(zebra), findsOneWidget);
      expect(
        tester.widget<FormDragHandle>(find.byType(FormDragHandle)).enabled,
        isFalse,
      );
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(
        tester
            .widget<ReorderableDelayedDragStartListener>(
              find.byType(ReorderableDelayedDragStartListener),
            )
            .enabled,
        isFalse,
      );
      await tap(tester, id(SemanticsIds.filterPresetOptions(zebra)));
      expect(
        menuItem(tester, SemanticsIds.filterPresetMoveToTop).enabled,
        isFalse,
      );
    });

    testWidgets('Move to top moves the preset first, in place, and persists', (
      tester,
    ) async {
      final ids = await seedNamed(['A', 'B', 'C']);

      await pumpSheet(tester);
      await tap(tester, id(SemanticsIds.filterPresetOptions(ids.last)));
      expect(
        menuItem(tester, SemanticsIds.filterPresetMoveToTop).enabled,
        isTrue,
      );
      await tap(tester, id(SemanticsIds.filterPresetMoveToTop));

      expect(shownNames(tester, ['A', 'B', 'C']), ['C', 'A', 'B']);
      expect(storedNames(), ['C', 'A', 'B']);
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(popped, isEmpty);
    });

    testWidgets('Move to top is disabled for the preset already first', (
      tester,
    ) async {
      final ids = await seedNamed(['A', 'B']);

      await pumpSheet(tester);
      await tap(tester, id(SemanticsIds.filterPresetOptions(ids.first)));

      expect(id(SemanticsIds.filterPresetMoveToTop), findsOneWidget);
      expect(
        menuItem(tester, SemanticsIds.filterPresetMoveToTop).enabled,
        isFalse,
      );
    });

    /// The caption names the sets like the Filters sheet's rows do, so the
    /// same filter never reads "Priority (2)" here and "Highest, High" there.
    testWidgets('the caption names several priorities', (tester) async {
      await service.create(
        name: 'Top',
        filters: const CalendarGridFilters(priorities: {1, 2}),
      );

      await pumpSheet(tester);

      expect(find.text('Highest, High'), findsOneWidget);
      expect(find.textContaining('Priority (2)'), findsNothing);
    });
  });

  /// Soft, never blocking — the category editor's rule. Presets are keyed by
  /// id, so a duplicate name is confusing rather than corrupting.
  testWidgets('a duplicate name warns but still saves', (tester) async {
    await service.create(name: 'Training', filters: missed);

    await pumpSheet(tester, current: tracked);
    await tap(tester, find.text('Save the current filter'));
    await tester.enterText(find.byType(TextField).last, 'Training');
    await tester.pumpAndSettle();

    expect(find.text('"Training" already exists'), findsOneWidget);

    await tap(tester, find.text('Save'));

    expect(service.presets.map((p) => p.name), ['Training', 'Training']);
  });
}
