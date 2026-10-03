import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

import 'support/category_editor_robot.dart';

/// The picker serves two arities off one sheet, and the properties worth
/// pinning are the ones a reader would otherwise copy wrong from its date
/// twin: `pickMulti` returns an **empty set** rather than collapsing it to
/// `null`, and a hidden category stays listed while it is selected. Since
/// the 2026-09-27 migration into the grouped-row language the chrome is
/// pinned too: Done and ✕ in multi mode, a pick-on-tap list with no Done in
/// single mode, the search row past the threshold, the two bulk rows
/// disabled where they would be no-ops, and the Create category row.
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

  /// The picker's own Done — by id, since the host sheet under it may carry
  /// the same word.
  Finder pickerApply() => find.bySemanticsIdentifier(SemanticsIds.categoryPickDone);

  /// The check row carrying [label], read for its state.
  FormCheckRow rowNamed(WidgetTester tester, String label) =>
      tester.widget<FormCheckRow>(find.widgetWithText(FormCheckRow, label));

  /// An action row by id, read for whether it is enabled.
  FormActionRow actionRow(WidgetTester tester, String id) =>
      tester.widget<FormActionRow>(
        find.ancestor(
          of: find.bySemanticsIdentifier(id),
          matching: find.byType(FormActionRow),
        ),
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

    expect(rowNamed(tester, 'Cat12').checked, isTrue);
    await tester.tap(find.text('Cat12'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cat12'),
      findsOneWidget,
      reason: 'the row it was just un-ticked from must still be there',
    );
    expect(rowNamed(tester, 'Cat12').checked, isFalse);

    // And re-tickable, which is the whole point of it staying.
    await tester.tap(find.text('Cat12'));
    await tester.pumpAndSettle();
    expect(rowNamed(tester, 'Cat12').checked, isTrue);

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
    expect(find.widgetWithText(FormCheckRow, 'Cat11'), findsOneWidget);
    expect(find.widgetWithText(FormCheckRow, 'Cat0'), findsNothing);
  });

  testWidgets('a short set carries no search chrome', (tester) async {
    seed(4);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c0'),
    );

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('twelve rows carry no search row', (tester) async {
    seed(12);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c0'),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickSearch),
      findsNothing,
    );
  });

  testWidgets('the search row appears at thirteen rows, never focused', (
    tester,
  ) async {
    seed(13);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c0'),
    );

    expect(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickSearch),
      findsOneWidget,
    );
    // Never autofocused: the list is what the sheet opens to show.
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
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
    expect(find.byType(FormCheckRow), findsNothing);
    // The query stays live, so the field stays to clear it.
    expect(find.byType(TextField), findsOneWidget);

    // The row opens the editor with the typed name filled in.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate));
    await tester.pumpAndSettle();

    final editor = CategoryEditorRobot(tester);
    expect(editor.isOpen, isTrue);
    expect(editor.nameText, 'Dentist');
  });

  testWidgets('the Create category row is last and opens the editor', (
    tester,
  ) async {
    seed(4);
    await openSheet<Set<String>>(
      tester,
      (context) => CategoryPickerSheet.pickMulti(context, selected: const {}),
    );

    expect(find.text('Create category'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Create category')).dy,
      greaterThan(tester.getTopLeft(find.text('Cat3')).dy),
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate));
    await tester.pumpAndSettle();

    expect(CategoryEditorRobot(tester).isOpen, isTrue);
  });

  testWidgets('multi mode returns null from the close button', (tester) async {
    seed(4);
    Set<String>? applied = const {'sentinel'};
    await openSheet<Set<String>>(tester, (context) async {
      applied = await CategoryPickerSheet.pickMulti(
        context,
        selected: const {'c1'},
      );
      return applied;
    });

    await tester.tap(find.text('Cat0'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.categoryPickClose));
    await tester.pumpAndSettle();

    expect(applied, isNull);
    expect(find.byType(CategoryPickerSheet), findsNothing);
  });

  testWidgets('single mode pops on tap with no Done and no checkboxes', (
    tester,
  ) async {
    seed(4);
    await openSheet<String>(
      tester,
      (context) => CategoryPickerSheet.pickSingle(context, selectedId: 'c2'),
    );

    expect(pickerApply(), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Type'), findsOneWidget);
    // The current one wears the check glyph; the bulk rows are multi-only.
    expect(rowNamed(tester, 'Cat2').checked, isTrue);
    expect(rowNamed(tester, 'Cat2').exclusive, isTrue);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('the bulk rows are disabled where they would be no-ops', (
    tester,
  ) async {
    seed(4);
    await openSheet<Set<String>>(
      tester,
      (context) => CategoryPickerSheet.pickMulti(context, selected: const {}),
    );

    // Nothing ticked yet, so Select none has nothing to do.
    expect(
      actionRow(tester, SemanticsIds.categoryPickSelectAll).onTap,
      isNotNull,
    );
    expect(actionRow(tester, SemanticsIds.categoryPickSelectNone).onTap, isNull);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.categoryPickSelectAll));
    await tester.pumpAndSettle();

    expect(actionRow(tester, SemanticsIds.categoryPickSelectAll).onTap, isNull);
    expect(
      actionRow(tester, SemanticsIds.categoryPickSelectNone).onTap,
      isNotNull,
    );
    expect(
      tester.widgetList<FormCheckRow>(find.byType(FormCheckRow)).every(
        (row) => row.checked,
      ),
      isTrue,
    );
  });

  testWidgets('every row carries its category id', (tester) async {
    seed(3);
    await openSheet<Set<String>>(
      tester,
      (context) => CategoryPickerSheet.pickMulti(context, selected: const {}),
    );

    for (final id in const ['c0', 'c1', 'c2']) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.categoryPickRow(id)),
        findsOneWidget,
      );
    }
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
              offered: CalendarCategories.visible,
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
