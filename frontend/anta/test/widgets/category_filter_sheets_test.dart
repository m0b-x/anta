import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/widgets/agenda_filters_sheet.dart';
import 'package:anta/widgets/calendar_filter_sheet.dart';
import 'package:anta/widgets/category_picker_sheet.dart';

/// `CategoryPickerSheet.pickMulti` is semantics-free — a set in, a set out —
/// so the two filter sheets are what decide what the set *means*. The agenda
/// holds an **allowlist** (empty = all) and the calendar filter a **denylist**
/// (empty = show all), and the caller is what inverts. These pin both
/// directions, plus the threshold that keeps a short set on chips.
void main() {
  void seed(int count) {
    CalendarCategories.updateCache([
      for (var i = 0; i < count; i++)
        CalendarCategory(
          id: 'c$i',
          name: 'Cat$i',
          colorValue: 0xFF1E88E5,
          iconKey: 'event',
          sortOrder: i,
          isBuiltIn: false,
        ),
    ]);
  }

  tearDown(() => CalendarCategories.updateCache(const []));

  Future<void> pumpHost(
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

  /// The sub-sheet's Apply, not the host sheet's — both are on screen once the
  /// picker has opened over a filter sheet.
  Finder pickerApply() => find.descendant(
    of: find.byType(CategoryPickerSheet),
    matching: find.text('Apply'),
  );

  /// One row inside the sub-sheet. The tile behind it names the selection too,
  /// so a bare text finder is ambiguous while the picker is open.
  Finder pickerRow(String label) => find.descendant(
    of: find.byType(CategoryPickerSheet),
    matching: find.text(label),
  );

  group('calendar filter sheet', () {
    testWidgets('a short set keeps its chips', (tester) async {
      seed(6);
      await pumpHost(
        tester,
        (context) => CalendarFilterSheet.show(
          context,
          format: CalendarFormat.month,
          hiddenCategoryIds: const {},
        ),
      );

      expect(find.byType(FilterChip), findsNWidgets(6));
      expect(find.byType(CategoryFilterTile), findsNothing);
    });

    testWidgets('past the threshold the chips collapse to one tile', (
      tester,
    ) async {
      seed(15);
      await pumpHost(
        tester,
        (context) => CalendarFilterSheet.show(
          context,
          format: CalendarFormat.month,
          hiddenCategoryIds: const {},
        ),
      );

      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(CategoryFilterTile), findsOneWidget);
      expect(find.text('All categories'), findsOneWidget);
    });

    testWidgets('the denylist is the inverse of what the picker returns', (
      tester,
    ) async {
      seed(15);
      CalendarFilterResult? applied;
      await pumpHost(tester, (context) async {
        applied = await CalendarFilterSheet.show(
          context,
          format: CalendarFormat.month,
          hiddenCategoryIds: const {},
        );
      });

      await tester.tap(find.byType(CategoryFilterTile));
      await tester.pumpAndSettle();
      // Everything starts shown, so un-ticking one row is what hides it.
      await tester.tap(pickerRow('Cat2'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();

      expect(find.text('Cat0, Cat1 +12 more'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.hiddenCategoryIds, {'c2'});
    });

    /// The header is one toggle, so its two halves are only ever reachable in
    /// alternation — which is exactly why **Select all must empty the denylist
    /// outright**, archived denials included. Subtracting only the visible ids
    /// instead strands an archived denial: `_hidden` never empties, the toggle
    /// never flips, and the button becomes a permanent no-op. (Clear all's
    /// union is the one-directional guard that hiding everything must not
    /// un-hide anything; it has no mirror here, and it is unreachable while
    /// anything is already hidden.)
    testWidgets('Select all empties the denylist, archived denials included', (
      tester,
    ) async {
      // 15 visible plus one archived category the user has *also* denied.
      seed(15);
      CalendarCategories.updateCache([
        ...CalendarCategories.all,
        const CalendarCategory(
          id: 'arch',
          name: 'Archived',
          colorValue: 0xFF1E88E5,
          iconKey: 'event',
          sortOrder: 99,
          isBuiltIn: false,
          isHidden: true,
        ),
      ]);
      CalendarFilterResult? applied;
      await pumpHost(tester, (context) async {
        applied = await CalendarFilterSheet.show(
          context,
          format: CalendarFormat.month,
          hiddenCategoryIds: const {'arch', 'c2'},
        );
      });

      // Something is hidden, so the header offers Select all.
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      // Everything is shown now, so the header has flipped to its other half —
      // which is the check that the button is not a permanent no-op.
      expect(find.text('Select all'), findsNothing);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Clear all denied every visible id; `arch` was already un-denied by
      // Select all and is not re-added, because Clear all unions the *visible*
      // set and `arch` is not in it.
      expect(applied?.hiddenCategoryIds, hasLength(15));
      expect(applied?.hiddenCategoryIds, isNot(contains('arch')));
    });

    testWidgets('clearing every row in the picker hides every category', (
      tester,
    ) async {
      seed(15);
      CalendarFilterResult? applied;
      await pumpHost(tester, (context) async {
        applied = await CalendarFilterSheet.show(
          context,
          format: CalendarFormat.month,
          // Starts with everything already hidden, so the picker opens with an
          // empty selection and Apply returns that empty set unchanged — the
          // case its date twin would have collapsed to a dismissal.
          hiddenCategoryIds: {for (final c in CalendarCategories.visible) c.id},
        );
      });

      expect(find.text('No categories'), findsOneWidget);

      await tester.tap(find.byType(CategoryFilterTile));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.hiddenCategoryIds.length, 15);
    });
  });

  group('agenda filters sheet', () {
    /// The Categories section sits below the fold of the sheet's scroll view.
    Future<void> scrollToCategories(WidgetTester tester) {
      return tester.dragUntilVisible(
        find.byType(CategoryFilterTile),
        find.byType(SingleChildScrollView).first,
        const Offset(0, -80),
      );
    }

    testWidgets('a short set keeps its chips', (tester) async {
      seed(6);
      await pumpHost(
        tester,
        (context) => AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(),
        ),
      );

      expect(find.byType(CategoryFilterTile), findsNothing);
    });

    testWidgets('an empty allowlist opens the picker with every row checked', (
      tester,
    ) async {
      seed(15);
      UpcomingAgendaFilters? applied;
      await pumpHost(tester, (context) async {
        applied = await AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(),
        );
      });

      await scrollToCategories(tester);
      // An empty allowlist means "all", which is what the tile must say.
      expect(find.text('All categories'), findsOneWidget);

      await tester.tap(find.byType(CategoryFilterTile));
      await tester.pumpAndSettle();

      // "All categories" over an unchecked sub-sheet would be one state shown
      // two contradictory ways — and the calendar filter's picker, inverting a
      // denylist, opens checked for the equivalent state. The caller seeds.
      final checkboxes = tester.widgetList<Checkbox>(
        find.descendant(
          of: find.byType(CategoryPickerSheet),
          matching: find.byType(Checkbox),
        ),
      );
      expect(checkboxes, isNotEmpty);
      expect(checkboxes.every((box) => box.value == true), isTrue);

      // Applying it unchanged collapses back to the empty set rather than
      // freezing today's catalog into a list that would silently exclude
      // every category created later.
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      expect(find.text('All categories'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.categoryIds, isEmpty);
    });

    testWidgets('unchecking rows narrows to the explicit remainder', (
      tester,
    ) async {
      seed(15);
      UpcomingAgendaFilters? applied;
      await pumpHost(tester, (context) async {
        applied = await AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(),
        );
      });

      await scrollToCategories(tester);
      await tester.tap(find.byType(CategoryFilterTile));
      await tester.pumpAndSettle();
      await tester.tap(pickerRow('Cat0'));
      await tester.tap(pickerRow('Cat1'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.categoryIds, hasLength(13));
      expect(applied?.categoryIds, isNot(contains('c0')));
      expect(applied?.categoryIds, isNot(contains('c1')));
    });

    testWidgets('an explicit allowlist is exactly what the picker returns', (
      tester,
    ) async {
      seed(15);
      UpcomingAgendaFilters? applied;
      await pumpHost(tester, (context) async {
        applied = await AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(categoryIds: {'c1'}),
        );
      });

      await scrollToCategories(tester);
      // A non-empty allowlist seeds itself, so this adds rather than removes.
      await tester.tap(find.byType(CategoryFilterTile));
      await tester.pumpAndSettle();
      await tester.tap(pickerRow('Cat4'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();

      expect(find.text('Cat1, Cat4'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.categoryIds, {'c1', 'c4'});
    });

    testWidgets('clearing the picker restores the empty "all" allowlist', (
      tester,
    ) async {
      seed(15);
      UpcomingAgendaFilters? applied;
      await pumpHost(tester, (context) async {
        applied = await AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(categoryIds: {'c1'}),
        );
      });

      await scrollToCategories(tester);
      await tester.tap(find.byType(CategoryFilterTile));
      await tester.pumpAndSettle();
      await tester.tap(pickerRow('Cat1'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.categoryIds, isEmpty);
    });
  });
}
