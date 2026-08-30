import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/widgets/category_picker_sheet.dart';

/// The picker serves two arities off one sheet, and the properties worth
/// pinning are the ones a reader would otherwise copy wrong from its date
/// twin: `pickMulti` returns an **empty set** rather than collapsing it to
/// `null`, and a hidden category stays listed while it is selected.
void main() {
  /// Fills the facade `CategoryService` normally owns. Custom categories, so
  /// every label is its stored name and the assertions read literally.
  void seed(int count, {Set<String> hidden = const {}}) {
    CalendarCategories.updateCache([
      for (var i = 0; i < count; i++)
        CalendarCategory(
          id: 'c$i',
          name: 'Cat$i',
          colorValue: 0xFF1E88E5,
          iconKey: 'event',
          sortOrder: i,
          isBuiltIn: false,
          isHidden: hidden.contains('c$i'),
        ),
    ]);
  }

  tearDown(() => CalendarCategories.updateCache(const []));

  Future<T?> openSheet<T>(
    WidgetTester tester,
    Future<T?> Function(BuildContext context) open,
  ) async {
    T? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  /// The picker's own Apply, not the host page's — both exist once a filter
  /// sheet has opened this one.
  Finder pickerApply() => find.descendant(
    of: find.byType(CategoryPickerSheet),
    matching: find.text('Apply'),
  );

  testWidgets('un-ticking an archived row leaves it on screen', (tester) async {
    // 12 visible plus one archived-but-selected id: `visiblePlus` offers 13,
    // one over the threshold, so the search field is showing too.
    //
    // The offered set is keyed to the selection the sheet **opened with**, not
    // the live one. Keyed to the live set, un-ticking the archived row deletes
    // it from the list in the very next build — the user cannot change their
    // mind, and the offered count drops back under the threshold mid-query.
    seed(13, hidden: {'c12'});
    await openSheet<Set<String>>(
      tester,
      (context) => CategoryPickerSheet.pickMulti(context, selected: {'c12'}),
    );

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'cat1');
    await tester.pumpAndSettle();

    Checkbox archivedBox() => tester.widget<Checkbox>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Cat12'),
        matching: find.byType(Checkbox),
      ),
    );

    expect(archivedBox().value, isTrue);
    await tester.tap(find.text('Cat12'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cat12'),
      findsOneWidget,
      reason: 'the row it was just un-ticked from must still be there',
    );
    expect(archivedBox().value, isFalse);

    // And re-tickable, which is the whole point of it staying.
    await tester.tap(find.text('Cat12'));
    await tester.pumpAndSettle();
    expect(archivedBox().value, isTrue);

    expect(
      find.byType(TextField),
      findsOneWidget,
      reason:
          'the query is still live; retracting the field would strand the '
          'list filtered with no way to clear it',
    );
  });

  testWidgets('single mode returns the tapped id', (tester) async {
    seed(4);
    String? picked;
    await openSheet<String>(tester, (context) async {
      picked = await CategoryPickerSheet.pickSingle(context, selectedId: 'c0');
      return picked;
    });

    await tester.tap(find.text('Cat2'));
    await tester.pumpAndSettle();

    expect(picked, 'c2');
  });

  testWidgets('multi mode returns an empty set, never null, when cleared', (
    tester,
  ) async {
    seed(4);
    Set<String>? applied;
    var completed = false;
    await openSheet<Set<String>>(tester, (context) async {
      applied = await CategoryPickerSheet.pickMulti(
        context,
        selected: const {'c1'},
      );
      completed = true;
      return applied;
    });

    // Clearing the last selection is a real state on both call sites — an
    // empty allowlist means "all", an empty denylist means "hide everything".
    await tester.tap(find.text('Cat1'));
    await tester.pumpAndSettle();
    await tester.tap(pickerApply());
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(applied, isNotNull);
    expect(applied, isEmpty);
  });

  testWidgets('multi mode returns null when dismissed', (tester) async {
    seed(4);
    Set<String>? applied = const {'sentinel'};
    await openSheet<Set<String>>(tester, (context) async {
      applied = await CategoryPickerSheet.pickMulti(
        context,
        selected: const {'c1'},
      );
      return applied;
    });

    // Above the sheet is the modal barrier.
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();

    expect(applied, isNull);
  });

  testWidgets('multi mode toggles rows into the returned set', (tester) async {
    seed(4);
    Set<String>? applied;
    await openSheet<Set<String>>(tester, (context) async {
      applied = await CategoryPickerSheet.pickMulti(
        context,
        selected: const {},
      );
      return applied;
    });

    await tester.tap(find.text('Cat0'));
    await tester.tap(find.text('Cat3'));
    await tester.pumpAndSettle();
    await tester.tap(pickerApply());
    await tester.pumpAndSettle();

    expect(applied, {'c0', 'c3'});
  });

  testWidgets('a hidden category is listed only while it is selected', (
    tester,
  ) async {
    seed(4, hidden: {'c1', 'c2'});
    await openSheet<Set<String>>(
      tester,
      (context) => CategoryPickerSheet.pickMulti(context, selected: {'c1'}),
    );

    // Selected and hidden: still listed, and flagged so it does not read as an
    // ordinary row. Hidden and unselected: gone.
    expect(find.text('Cat1'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.text('Cat2'), findsNothing);
    expect(find.text('Cat0'), findsOneWidget);
  });

  testWidgets('search appears above the threshold and narrows the rows', (
    tester,
  ) async {
    seed(15);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c0'),
    );

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Cat11');
    await tester.pumpAndSettle();

    // The field itself renders the term, so the row is addressed as a row.
    expect(find.widgetWithText(ListTile, 'Cat11'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Cat0'), findsNothing);
  });

  testWidgets('a short set carries no search chrome', (tester) async {
    seed(4);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c0'),
    );

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('no match offers to create what was typed', (tester) async {
    seed(15);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c0'),
    );

    await tester.enterText(find.byType(TextField), 'Dentist');
    await tester.pumpAndSettle();

    expect(find.text('No categories match'), findsOneWidget);
    expect(find.text('Create "Dentist"'), findsOneWidget);
  });

  group('CategoryFilterTile', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      required List<CalendarCategory> selected,
      required bool selectsAll,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: CategoryFilterTile(
              selected: selected,
              selectsAll: selectsAll,
              onTap: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('names the whole set in one line', (tester) async {
      seed(6);
      await pumpTile(
        tester,
        selected: CalendarCategories.visible,
        selectsAll: true,
      );

      expect(find.text('All categories'), findsOneWidget);
    });

    testWidgets('folds everything past the first names into +N more', (
      tester,
    ) async {
      seed(6);
      await pumpTile(
        tester,
        selected: CalendarCategories.visible,
        selectsAll: false,
      );

      expect(find.text('Cat0, Cat1 +4 more'), findsOneWidget);
    });

    testWidgets('says so when nothing is selected', (tester) async {
      seed(6);
      await pumpTile(tester, selected: const [], selectsAll: false);

      expect(find.text('No categories'), findsOneWidget);
    });
  });
}
