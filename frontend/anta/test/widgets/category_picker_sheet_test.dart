import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
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
  Finder pickerApply() =>
      find.bySemanticsIdentifier(SemanticsIds.categoryPickDone);

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

  testWidgets('single mode leaves out the excluded ids, the selection still '
      'listed', (tester) async {
    seed(4);
    String? picked;
    await openSheet<String>(tester, (context) async {
      picked = await CategoryPickerSheet.pickSingle(
        context,
        selectedId: 'c0',
        exclude: {'c1'},
      );
      return picked;
    });

    expect(find.text('Cat1'), findsNothing);
    for (final label in ['Cat0', 'Cat2', 'Cat3']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Cat3'));
    await tester.pumpAndSettle();

    expect(picked, 'c3');
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
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate),
    );
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

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate),
    );
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
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickClose),
    );
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
    expect(find.text('Category'), findsOneWidget);
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
    expect(
      actionRow(tester, SemanticsIds.categoryPickSelectNone).onTap,
      isNull,
    );

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickSelectAll),
    );
    await tester.pumpAndSettle();

    expect(actionRow(tester, SemanticsIds.categoryPickSelectAll).onTap, isNull);
    expect(
      actionRow(tester, SemanticsIds.categoryPickSelectNone).onTap,
      isNotNull,
    );
    expect(
      tester
          .widgetList<FormCheckRow>(find.byType(FormCheckRow))
          .every((row) => row.checked),
      isTrue,
    );
  });

  // The calendar guide's demos: the Create row is the picker's one path into
  // a category write, so a sandbox has none — not as the plain row, not as
  // the no-match offer — while search and picking answer as ever.
  testWidgets('sandbox: no Create row, search and picking unchanged', (
    tester,
  ) async {
    seed(15);
    final catalog = CalendarCategories.all;
    String? picked;
    await openSheet<String>(tester, (context) async {
      picked = await CategoryPickerSheet.pickSingle(
        context,
        selectedId: 'c0',
        sandbox: true,
      );
      return picked;
    });

    expect(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate),
      findsNothing,
    );
    expect(find.text('Create category'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Dentist');
    await tester.pumpAndSettle();
    expect(find.text('No categories match'), findsOneWidget);
    expect(find.text('Create "Dentist"'), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate),
      findsNothing,
    );
    expect(CategoryEditorRobot(tester).isOpen, isFalse);

    await tester.enterText(find.byType(TextField), 'Cat14');
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickRow('c14')),
    );
    await tester.pumpAndSettle();

    expect(picked, 'c14');
    expect(identical(CalendarCategories.all, catalog), isTrue);
  });

  testWidgets('sandbox: multi mode still edits and returns its set', (
    tester,
  ) async {
    seed(4);
    Set<String>? applied;
    await openSheet<Set<String>>(tester, (context) async {
      applied = await CategoryPickerSheet.pickMulti(
        context,
        selected: const {'c1'},
        sandbox: true,
      );
      return applied;
    });

    expect(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickCreate),
      findsNothing,
    );
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryPickSelectAll),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cat2'));
    await tester.pumpAndSettle();
    await tester.tap(pickerApply());
    await tester.pumpAndSettle();

    expect(applied, {'c0', 'c1', 'c3'});
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

  group('the Sharing page\'s tick sheet (share surfaces §6.3)', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    testWidgets('it takes a title, a caption under the header and each row\'s '
        'event count, " · Hidden" after an archived one; an empty pick stays '
        'an empty pick', (tester) async {
      seed(3, hidden: {'c2'});
      Set<String>? applied;
      await openSheet<Set<String>>(tester, (context) async {
        applied = await CategoryPickerSheet.pickMulti(
          context,
          selected: const {'c2'},
          title: l10n.shareCategoriesTitle,
          caption: l10n.shareCategoriesCaption('Maria'),
          counts: const {'c0': 42, 'c2': 3},
          identifier: SemanticsIds.shareCategoriesSheet,
        );
        return applied;
      });

      expect(
        find.bySemanticsIdentifier(SemanticsIds.shareCategoriesSheet),
        findsOneWidget,
      );
      expect(find.text(l10n.shareCategoriesTitle), findsOneWidget);
      expect(find.text(l10n.calendarCategories), findsNothing);
      expect(
        tester
            .widget<FormSheetHeader>(find.byType(FormSheetHeader))
            .stackTitleAtLargeText,
        isTrue,
      );
      final caption = find.widgetWithText(
        FormCaption,
        l10n.shareCategoriesCaption('Maria'),
      );
      expect(caption, findsOneWidget);
      expect(
        find.ancestor(of: caption, matching: find.byType(Scrollable)),
        findsNothing,
        reason: 'the caption stays under the header, outside the scroll',
      );
      expect(rowNamed(tester, 'Cat0').caption, l10n.categoryEventCount(42));
      expect(rowNamed(tester, 'Cat1').caption, l10n.categoryEventCount(0));
      expect(
        rowNamed(tester, 'Cat2').caption,
        '${l10n.categoryEventCount(3)} · ${l10n.categoryHidden}',
      );

      await tester.tap(find.text('Cat2'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();

      expect(applied, isNotNull);
      expect(applied, isEmpty);
    });

    testWidgets('without them the picker is the one every other caller '
        'opens', (tester) async {
      seed(2, hidden: {'c1'});
      await openSheet<Set<String>>(
        tester,
        (context) =>
            CategoryPickerSheet.pickMulti(context, selected: const {'c1'}),
      );

      expect(find.text(l10n.calendarCategories), findsOneWidget);
      // The one caption is the archived row's own "Hidden".
      expect(
        find.byType(FormCaption).evaluate().length,
        find
            .descendant(
              of: find.byType(FormCheckRow),
              matching: find.byType(FormCaption),
            )
            .evaluate()
            .length,
      );
      expect(
        tester
            .widget<FormSheetHeader>(find.byType(FormSheetHeader))
            .stackTitleAtLargeText,
        isFalse,
      );
      expect(rowNamed(tester, 'Cat0').caption, isNull);
      expect(rowNamed(tester, 'Cat1').caption, l10n.categoryHidden);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.shareCategoriesSheet),
        findsNothing,
      );
    });
  });

  // Create category writes through the real service, so these run it
  // against `NativeDatabase.memory()` as the editor's own suite does.
  group('a category created inline', () {
    late AppDatabase db;

    setUp(() async {
      CategoryService.reset();
      CalendarPaletteService.reset();
      SettingsService.reset();
      db = await openTestDatabase();
      SettingsService.forTesting(db);
      await CategoryService.forTesting(db);
    });

    tearDown(() async {
      CategoryService.reset();
      CalendarPaletteService.reset();
      SettingsService.reset();
      await db.close();
    });

    for (final tickCreated in const [true, false]) {
      testWidgets(
        tickCreated
            ? 'arrives ticked for every caller that keeps the default'
            : 'arrives un-ticked in the share tick sheet, so Done hands over '
                  'only what was ticked (case C9)',
        (tester) async {
          Set<String>? applied;
          await openSheet<Set<String>>(tester, (context) async {
            applied = tickCreated
                ? await CategoryPickerSheet.pickMulti(
                    context,
                    selected: const {},
                  )
                : await CategoryPickerSheet.pickMulti(
                    context,
                    selected: const {},
                    identifier: SemanticsIds.shareCategoriesSheet,
                    tickCreated: false,
                  );
            return applied;
          });

          // Below the built-ins the service seeds.
          final create = find.bySemanticsIdentifier(
            SemanticsIds.categoryPickCreate,
          );
          await tester.ensureVisible(create);
          await tester.pumpAndSettle();
          await tester.tap(create);
          await tester.pumpAndSettle();
          final editor = CategoryEditorRobot(tester);
          await editor.typeName('Dentist');
          await editor.save();
          expect(editor.isOpen, isFalse);

          final created = CalendarCategories.all.singleWhere(
            (category) => category.name == 'Dentist',
          );
          expect(rowNamed(tester, 'Dentist').checked, tickCreated);

          await tester.tap(pickerApply());
          await tester.pumpAndSettle();
          expect(applied, tickCreated ? {created.id} : isEmpty);
        },
      );
    }
  });
  // The partner's own categories, as `CalendarCategories.partnerShown` hands
  // them to the two filter sheets (share surfaces §6.10, slice D spec §5).
  const night = CalendarCategory(
    id: 'p-night',
    name: 'Night shift',
    colorValue: 0xFF3949AB,
    iconKey: 'work',
    sortOrder: 0,
    isBuiltIn: false,
    fromPartner: true,
  );
  const pilates = CalendarCategory(
    id: 'p-pilates',
    name: 'Pilates',
    colorValue: 0xFFAFB42B,
    iconKey: 'self_improvement',
    sortOrder: 0,
    isBuiltIn: false,
    fromPartner: true,
  );
  const choir = CalendarCategory(
    id: 'p-choir',
    name: 'Choir',
    colorValue: 0xFF8E24AA,
    iconKey: 'music_note',
    sortOrder: 0,
    isBuiltIn: false,
    fromPartner: true,
  );
  const theirs = [night, pilates, choir];
  const maria = PartnerLook(name: 'Maria');

  /// The picker the filter sheets open, its answer kept once it pops.
  Future<_Picked> openWithPartner(
    WidgetTester tester, {
    required Set<String> selected,
    List<CalendarCategory> partner = theirs,
    PartnerLook look = maria,
    Size surface = const Size(360, 1200),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final picked = _Picked();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked.value = await CategoryPickerSheet.pickMulti(
                  context,
                  selected: selected,
                  partner: partner,
                  partnerLook: look,
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
    return picked;
  }

  Finder pickRow(String id) =>
      find.bySemanticsIdentifier(SemanticsIds.categoryPickRow(id));

  /// The avatar on the row an id sits on.
  EventAvatar avatarOf(WidgetTester tester, String id) =>
      tester.widget<EventAvatar>(
        find.descendant(
          of: find.ancestor(
            of: pickRow(id),
            matching: find.byType(FormCheckRow),
          ),
          matching: find.byType(EventAvatar),
        ),
      );

  group('a partner\'s categories (share surfaces §6.10)', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    testWidgets('their group stands after mine under "From Maria", in the '
        'order given, and the answer holds both kinds of ids', (tester) async {
      seed(3);
      final picked = await openWithPartner(
        tester,
        selected: const {'c0', 'c1', 'c2', 'p-night', 'p-choir'},
      );

      final label = find.text('FROM MARIA');
      expect(label, findsOneWidget);
      final createTop = tester.getRect(find.text(l10n.createCategory)).bottom;
      final tops = [
        tester.getRect(label).top,
        for (final name in ['Night shift', 'Pilates', 'Choir'])
          tester.getRect(find.text(name)).top,
      ];
      expect(tops.first, greaterThan(createTop));
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: 'row $i');
      }
      for (final category in theirs) {
        expect(pickRow(category.id), findsOneWidget, reason: category.id);
      }
      // Two groups: mine, with the gap the label needs above it, then theirs.
      final groups = tester
          .widgetList<FormRowGroup>(find.byType(FormRowGroup))
          .toList();
      expect(groups, hasLength(2));
      expect(groups.first.trailingGap, isTrue);
      expect(groups.last.trailingGap, isFalse);
      expect(rowNamed(tester, 'Pilates').checked, isFalse);
      expect(rowNamed(tester, 'Night shift').caption, isNull);

      await tester.tap(find.text('Pilates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat1'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();

      expect(picked.value, {'c0', 'c2', 'p-night', 'p-pilates', 'p-choir'});
    });

    testWidgets('no name reads the stand-in', (tester) async {
      seed(1);
      await openWithPartner(
        tester,
        selected: const {},
        look: const PartnerLook(),
      );

      expect(
        find.text(
          FormSectionLabel.capitals(
            l10n.shareFromPartner(l10n.sharePartnerFallback),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('each look draws their avatars as the event rows do, with no '
        'per-row "From" label; mine stay plain', (tester) async {
      seed(1);
      const face = AppUser(uid: 'maria', displayName: 'Maria');
      for (final look in ShareEventLook.values) {
        await openWithPartner(
          tester,
          selected: const {},
          look: PartnerLook(look: look, partner: face, name: 'Maria'),
        );

        for (final category in theirs) {
          final avatar = avatarOf(tester, category.id);
          expect(
            avatar.outlined,
            look == ShareEventLook.outlined,
            reason: '$look ${category.id}',
          );
          expect(
            avatar.badge,
            look == ShareEventLook.avatar
                ? const EventAvatarBadge.partner(face)
                : null,
            reason: '$look ${category.id}',
          );
          expect(avatar.semanticsLabel, isNull, reason: '$look');
          expect(avatar.color, category.color);
        }
        final mine = avatarOf(tester, 'c0');
        expect(mine.outlined, isFalse);
        expect(mine.badge, isNull);

        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.categoryPickClose),
        );
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Select all and Select none act on both groups and are '
        'disabled by the no-op rule over both', (tester) async {
      seed(2);
      final picked = await openWithPartner(
        tester,
        selected: const {'c0', 'c1'},
        partner: const [night, pilates],
      );

      // Every one of mine ticked, theirs not: Select all still has work.
      expect(
        actionRow(tester, SemanticsIds.categoryPickSelectAll).onTap,
        isNotNull,
      );
      await tester.tap(find.text(l10n.categoriesSelectAll));
      await tester.pumpAndSettle();
      for (final name in ['Cat0', 'Cat1', 'Night shift', 'Pilates']) {
        expect(rowNamed(tester, name).checked, isTrue, reason: name);
      }
      expect(
        actionRow(tester, SemanticsIds.categoryPickSelectAll).onTap,
        isNull,
      );

      await tester.tap(find.text(l10n.categoriesSelectNone));
      await tester.pumpAndSettle();
      for (final name in ['Cat0', 'Cat1', 'Night shift', 'Pilates']) {
        expect(rowNamed(tester, name).checked, isFalse, reason: name);
      }
      expect(
        actionRow(tester, SemanticsIds.categoryPickSelectNone).onTap,
        isNull,
      );

      // One of theirs ticked: Select none has work again.
      await tester.tap(find.text('Pilates'));
      await tester.pumpAndSettle();
      expect(
        actionRow(tester, SemanticsIds.categoryPickSelectNone).onTap,
        isNotNull,
      );

      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      expect(picked.value, {'p-pilates'});
    });

    testWidgets('search counts both lists, filters both by one ranking, and '
        'their group leaves when the query matches none of theirs', (
      tester,
    ) async {
      // Twelve across both groups: no search row.
      seed(9);
      await openWithPartner(tester, selected: const {});
      expect(find.byType(TextField), findsNothing);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.categoryPickClose),
      );
      await tester.pumpAndSettle();

      // Thirteen across both, ten of them mine: the field is there.
      seed(10);
      await openWithPartner(tester, selected: const {});
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'pil');
      await tester.pumpAndSettle();
      expect(find.text('FROM MARIA'), findsOneWidget);
      expect(find.byType(FormCheckRow), findsOneWidget);
      expect(find.text('Pilates'), findsOneWidget);
      // A partner's row answered, so the typed name is no new category.
      expect(find.text(l10n.createCategory), findsOneWidget);
      // The bulk rows act on what is listed: Pilates alone.
      await tester.tap(find.text(l10n.categoriesSelectAll));
      await tester.pumpAndSettle();
      expect(rowNamed(tester, 'Pilates').checked, isTrue);

      await tester.enterText(find.byType(TextField), 'cat1');
      await tester.pumpAndSettle();
      expect(find.text('FROM MARIA'), findsNothing);
      expect(find.byType(FormSectionLabel), findsNothing);
      expect(find.text('Cat1'), findsOneWidget);
      expect(rowNamed(tester, 'Cat1').checked, isFalse);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byType(FormCheckRow), findsNothing);
      expect(find.text(l10n.noCategoriesMatch), findsOneWidget);
      expect(find.text(l10n.createCategoryNamed('zzz')), findsOneWidget);
    });

    testWidgets('an empty partner list is the picker every other caller '
        'opens: one group, no label, today\'s rows', (tester) async {
      seed(3);
      await openWithPartner(tester, selected: const {'c1'}, partner: const []);

      // The scroll body holds the one group and nothing after it.
      final body =
          tester
                  .widget<SingleChildScrollView>(
                    find.byType(SingleChildScrollView),
                  )
                  .child!
              as Column;
      expect(body.children, hasLength(1));
      final group = body.children.single as FormRowGroup;
      expect(group.trailingGap, isFalse);
      expect(
        [for (final row in group.children) row.runtimeType],
        [
          FormActionRow,
          FormActionRow,
          FormCheckRow,
          FormCheckRow,
          FormCheckRow,
          FormActionRow,
        ],
      );
      expect(
        (group.children.last as FormActionRow).identifier,
        SemanticsIds.categoryPickCreate,
      );
      expect(find.byType(FormSectionLabel), findsNothing);
    });
  });

  // Last in the file: the real faces stay loaded for every test after them.
  group('a partner\'s categories with the real fonts', () {
    setUpAll(loadGoldenFonts);

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('de'), 2.0),
    ]) {
      testWidgets('their rows are 56 dp at $locale $scale on 360 × 780', (
        tester,
      ) async {
        seed(2);
        await openWithPartner(
          tester,
          selected: const {'c0', 'p-night'},
          surface: const Size(360, 780),
          locale: locale,
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        for (final category in theirs) {
          final row = find.ancestor(
            of: pickRow(category.id),
            matching: find.byType(FormCheckRow),
          );
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(row).height,
            moreOrLessEquals(56, epsilon: 0.5),
            reason: category.id,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final dark in const [false, true]) {
      testWidgets('the picker with their group meets the tap-target, label '
          'and contrast guidelines, ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        seed(2);
        // A mixed selection, so neither bulk row is drawn disabled.
        await openWithPartner(
          tester,
          selected: const {'c0', 'p-night'},
          surface: const Size(360, 780),
          dark: dark,
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        // The sampler reads "Pilates" and "Choir" at 4.01:1 in light, ticked
        // or not: at 15 px their anti-aliasing step (#7E7A80) outnumbers the
        // full-strength `onSurface` pixels in the sampled rect — the
        // text-contrast sampler trap, the same reading "Katholisch" gave. The
        // contrast pass runs over a name that samples cleanly; every
        // partner label's colour is pinned by token in the next case.
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.categoryPickClose),
        );
        await tester.pumpAndSettle();
        await openWithPartner(
          tester,
          selected: const {'c0', 'p-night'},
          partner: const [night],
          surface: const Size(360, 780),
          dark: dark,
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('every partner row\'s label is drawn in onSurface, light and '
        'dark', (tester) async {
      seed(1);
      for (final dark in const [false, true]) {
        await openWithPartner(
          tester,
          selected: const {},
          surface: const Size(360, 780),
          dark: dark,
        );
        final onSurface = Theme.of(
          tester.element(find.byType(CategoryPickerSheet)),
        ).colorScheme.onSurface;
        for (final category in theirs) {
          final label = find.text(category.name);
          final text = tester.widget<Text>(label);
          final color = DefaultTextStyle.of(
            tester.element(label),
          ).style.merge(text.style).color;
          expect(color, onSurface, reason: '${category.id} dark: $dark');
        }
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.categoryPickClose),
        );
        await tester.pumpAndSettle();
      }
    });
  });
}

/// The picker's answer, which arrives after the tap that closed it.
class _Picked {
  Set<String>? value;
}
