import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/widgets/agenda_filters_sheet.dart';
import 'package:anta/widgets/calendar_filter_sheet.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/filter_check_list_sheet.dart';
import 'package:anta/widgets/filter_preset_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';

/// `CategoryPickerSheet.pickMulti` is semantics-free — a set in, a set out —
/// so the two filter sheets are what decide what the set *means*. The agenda
/// holds an **allowlist** (empty = all) and the calendar filter a **denylist**
/// (empty = show all), and the caller is what inverts. These pin both
/// directions — and, for the calendar's sheet, the two-level summary: every
/// row reads its value back, every sub-sheet's Done lands in the draft, and
/// only Apply pops it.
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

  /// The picker's own Done — by id, since the host sheet under it may carry
  /// the same word.
  Finder pickerApply() => find.bySemanticsIdentifier(SemanticsIds.categoryPickDone);

  /// One row inside the sub-sheet. The row behind it names the selection too,
  /// so a bare text finder is ambiguous while the picker is open.
  Finder pickerRow(String label) => find.descendant(
    of: find.byType(CategoryPickerSheet),
    matching: find.text(label),
  );

  group('calendar filter sheet', () {
    const tracked = CalendarGridFilters(trackedOnly: true);
    const missedOnly = CalendarGridFilters(missedOnly: true);
    const everyTrait = CalendarGridFilters(
      trackedOnly: true,
      missedOnly: true,
      linkedNotesOnly: true,
      moneyOnly: true,
      withDescriptionOnly: true,
      countedOnly: true,
      hideEnded: true,
    );

    // The sheet resolves the preset service for its Saved filter row; bound
    // to an in-memory database so the row can read a name back.
    late AppDatabase db;
    late FilterPresetService service;

    setUp(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      FilterPresetService.reset();
      db = await openTestDatabase();
      service = await FilterPresetService.forTesting(db);
    });

    tearDown(() async {
      FilterPresetService.reset();
      FastingCalendar.resetConfiguration();
      await db.close();
    });

    Finder id(String value) => find.bySemanticsIdentifier(value);

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// The row an id sits on, with the value it reads back.
    FormPickerRow row(WidgetTester tester, String rowId) =>
        tester.widget<FormPickerRow>(
          find.ancestor(of: id(rowId), matching: find.byType(FormPickerRow)),
        );

    FormSwitchRow switchRow(WidgetTester tester, String rowId) =>
        tester.widget<FormSwitchRow>(
          find.ancestor(of: id(rowId), matching: find.byType(FormSwitchRow)),
        );

    FormActionRow resetRow(WidgetTester tester) => tester.widget<FormActionRow>(
      find.ancestor(
        of: id(SemanticsIds.filterReset),
        matching: find.byType(FormActionRow),
      ),
    );

    /// The Saved filter row's bookmark — the sheet's one trailing button.
    FormTrailingButton bookmark(WidgetTester tester) =>
        tester.widget<FormTrailingButton>(find.byType(FormTrailingButton));

    /// Opens the sheet on a phone tall enough that no row sits below the
    /// fold, so every id can be tapped without scrolling.
    Future<_Applied> open(
      WidgetTester tester,
      CalendarGridFilters filters,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      final applied = _Applied();
      await pumpHost(tester, (context) async {
        applied.value = await CalendarFilterSheet.show(
          context,
          filters: filters,
        );
        applied.returned = true;
      });
      return applied;
    }

    testWidgets('the Categories row reads All, opens the picker, and the '
        'denylist is the inverse of its answer', (tester) async {
      seed(15);
      final applied = await open(tester, CalendarGridFilters.none);

      expect(row(tester, SemanticsIds.filterCategories).value, 'All');

      await tap(tester, id(SemanticsIds.filterCategories));
      expect(find.byType(CategoryPickerSheet), findsOneWidget);
      // Everything starts shown, so un-ticking one row is what hides it.
      await tap(tester, pickerRow('Cat2'));
      await tap(tester, pickerApply());

      expect(
        row(tester, SemanticsIds.filterCategories).value,
        'Cat0, Cat1 +12 more',
      );

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.hiddenCategoryIds, {'c2'});
    });

    /// The picker never lists a denied archived category (a hidden one
    /// reaches it only inside a selection), so an answer that ticks every
    /// listed row is read as "show everything" and empties the denylist
    /// outright. Subtracting the answer from the offered set instead would
    /// strand the archived denial: the row would keep reading a count with
    /// nothing left in the picker to un-tick.
    testWidgets('Select all in the picker empties the denylist, archived '
        'denials included', (tester) async {
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
      final applied = await open(
        tester,
        const CalendarGridFilters(hiddenCategoryIds: {'arch', 'c2'}),
      );

      // Sixteen offered (the archived one rides in on its denial), two hidden.
      expect(
        row(tester, SemanticsIds.filterCategories).value,
        'Cat0, Cat1 +12 more',
      );

      await tap(tester, id(SemanticsIds.filterCategories));
      expect(pickerRow('Archived'), findsNothing);
      await tap(tester, find.text('Select all'));
      await tap(tester, pickerApply());

      expect(row(tester, SemanticsIds.filterCategories).value, 'All');

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.hiddenCategoryIds, isEmpty);
    });

    /// The denylist is rebuilt from the catalog **after** the picker returns:
    /// a category created inside it is visible by then, and an answer that
    /// omits it must deny it — the list captured when the sheet was built
    /// would never have listed it.
    testWidgets('a picker answer that omits a freshly visible category '
        'denies it', (tester) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterCategories));
      // A category appears while the picker is open (what Create category
      // does through the facade); a toggle back and forth rebuilds the list.
      CalendarCategories.updateCache([
        ...CalendarCategories.all,
        const CalendarCategory(
          id: 'c3',
          name: 'Cat3',
          colorValue: 0xFF1E88E5,
          iconKey: 'event',
          sortOrder: 3,
          isBuiltIn: false,
        ),
      ]);
      await tap(tester, pickerRow('Cat0'));
      await tap(tester, pickerRow('Cat0'));
      expect(pickerRow('Cat3'), findsOneWidget);
      await tap(tester, pickerApply());

      expect(
        row(tester, SemanticsIds.filterCategories).value,
        'Cat0, Cat1 +1 more',
      );

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.hiddenCategoryIds, {'c3'});
    });

    /// With every category archived the picker lists nothing, so its Done is
    /// not "every listed row ticked" and the archived denial stays.
    testWidgets('an empty picker keeps an archived denial', (tester) async {
      CalendarCategories.updateCache([
        const CalendarCategory(
          id: 'arch',
          name: 'Archived',
          colorValue: 0xFF1E88E5,
          iconKey: 'event',
          sortOrder: 0,
          isBuiltIn: false,
          isHidden: true,
        ),
      ]);
      final applied = await open(
        tester,
        const CalendarGridFilters(hiddenCategoryIds: {'arch'}),
      );

      expect(
        row(tester, SemanticsIds.filterCategories).value,
        'No categories',
      );

      await tap(tester, id(SemanticsIds.filterCategories));
      expect(find.byType(FormCheckRow), findsNothing);
      await tap(tester, pickerApply());

      expect(
        row(tester, SemanticsIds.filterCategories).value,
        'No categories',
      );

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.hiddenCategoryIds, {'arch'});
    });

    testWidgets('un-ticking one row keeps an archived denial denied', (
      tester,
    ) async {
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
      final applied = await open(
        tester,
        const CalendarGridFilters(hiddenCategoryIds: {'arch'}),
      );

      await tap(tester, id(SemanticsIds.filterCategories));
      await tap(tester, pickerRow('Cat2'));
      await tap(tester, pickerApply());
      await tap(tester, id(SemanticsIds.filterApply));

      // Not every listed row was ticked, so the answer is a real narrowing
      // and the archived denial rides along untouched.
      expect(applied.value?.hiddenCategoryIds, {'arch', 'c2'});
    });

    testWidgets('Select none in the picker hides everything and the row reads '
        'No categories', (tester) async {
      seed(15);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterCategories));
      await tap(tester, find.text('Select none'));
      // Empty is a real answer here — "hide every category" — never a
      // dismissal.
      await tap(tester, pickerApply());

      expect(
        row(tester, SemanticsIds.filterCategories).value,
        'No categories',
      );

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.hiddenCategoryIds, hasLength(15));
    });

    testWidgets('Priority Done returns the set and the row reads Highest, '
        'High', (tester) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      expect(row(tester, SemanticsIds.filterPriority).value, 'Any');

      await tap(tester, id(SemanticsIds.filterPriority));
      expect(find.byType(FilterCheckListSheet), findsOneWidget);
      await tap(tester, id(SemanticsIds.filterListRow('priority-2')));
      await tap(tester, id(SemanticsIds.filterListRow('priority-1')));
      await tap(tester, id(SemanticsIds.filterListDone));

      expect(find.byType(FilterCheckListSheet), findsNothing);
      expect(row(tester, SemanticsIds.filterPriority).value, 'Highest, High');

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.priorities, {1, 2});
    });

    testWidgets('a dismissed Priority sub-sheet changes nothing', (
      tester,
    ) async {
      seed(3);
      final applied = await open(
        tester,
        const CalendarGridFilters(priorities: {1}),
      );

      await tap(tester, id(SemanticsIds.filterPriority));
      await tap(tester, id(SemanticsIds.filterListRow('priority-5')));
      await tap(tester, id(SemanticsIds.filterListClose));

      expect(row(tester, SemanticsIds.filterPriority).value, 'Highest');

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.priorities, {1});
    });

    testWidgets('Only show Done writes the seven flags and the row reads the '
        'names then +N more', (tester) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      expect(row(tester, SemanticsIds.filterOnlyShow).value, 'Everything');

      await tap(tester, id(SemanticsIds.filterOnlyShow));
      for (final trait in const [
        'tracked',
        'missed',
        'linked-note',
        'money',
        'description',
        'counted',
        'not-ended',
      ]) {
        await tap(tester, id(SemanticsIds.filterListRow(trait)));
      }
      await tap(tester, id(SemanticsIds.filterListDone));

      expect(
        row(tester, SemanticsIds.filterOnlyShow).value,
        'Tracked, Missed +5 more',
      );

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value, everyTrait);
    });

    testWidgets('the menus change the recurrence and the time of day', (
      tester,
    ) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      expect(row(tester, SemanticsIds.filterRepeat).value, 'All');
      await tap(tester, id(SemanticsIds.filterRepeat));
      await tap(tester, id(SemanticsIds.filterRepeatRecurring));
      expect(row(tester, SemanticsIds.filterRepeat).value, 'Recurring');

      expect(row(tester, SemanticsIds.filterTime).value, 'All');
      await tap(tester, id(SemanticsIds.filterTime));
      await tap(tester, id(SemanticsIds.filterTimeAllDay));
      expect(row(tester, SemanticsIds.filterTime).value, 'All day');

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.eventType, AgendaEventType.recurring);
      expect(applied.value?.timing, CalendarEventTiming.allDay);
    });

    /// Disabled with its stored value rather than omitted: a row that appears
    /// between two openings moves everything under it.
    testWidgets('Fasting is present and inert while no tradition is '
        'configured', (tester) async {
      seed(3);
      await open(tester, const CalendarGridFilters(showFasting: false));

      final fasting = switchRow(tester, SemanticsIds.filterFasting);
      expect(fasting.onChanged, isNull);
      expect(fasting.value, isFalse);
    });

    testWidgets('Fasting toggles once a tradition is configured', (
      tester,
    ) async {
      FastingCalendar.configure(traditions: const {FastingTradition.orthodox});
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      expect(switchRow(tester, SemanticsIds.filterFasting).onChanged, isNotNull);
      await tap(tester, id(SemanticsIds.filterFasting));
      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value?.showFasting, isFalse);
    });

    testWidgets('the switches write the layers and the panel flag', (
      tester,
    ) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterHolidays));
      await tap(tester, id(SemanticsIds.filterMoney));
      await tap(tester, id(SemanticsIds.filterPanelAll));
      await tap(tester, id(SemanticsIds.filterApply));

      expect(
        applied.value,
        const CalendarGridFilters(
          showHolidays: false,
          showMoney: false,
          panelShowsAll: true,
        ),
      );
    });

    testWidgets('Reset is inert on an empty draft', (tester) async {
      seed(3);
      await open(tester, CalendarGridFilters.none);

      expect(resetRow(tester).onTap, isNull);
    });

    testWidgets('Reset clears everything but the panel flag and keeps the '
        'sheet open', (tester) async {
      seed(3);
      final applied = await open(
        tester,
        const CalendarGridFilters(
          trackedOnly: true,
          priorities: {1},
          showMoney: false,
          panelShowsAll: true,
        ),
      );

      expect(row(tester, SemanticsIds.filterOnlyShow).value, 'Tracked');
      expect(resetRow(tester).onTap, isNotNull);

      await tap(tester, id(SemanticsIds.filterReset));

      expect(find.byType(CalendarFilterSheet), findsOneWidget);
      expect(row(tester, SemanticsIds.filterOnlyShow).value, 'Everything');
      expect(row(tester, SemanticsIds.filterPriority).value, 'Any');
      expect(switchRow(tester, SemanticsIds.filterMoney).value, isTrue);
      expect(switchRow(tester, SemanticsIds.filterPanelAll).value, isTrue);
      expect(resetRow(tester).onTap, isNull);

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value, const CalendarGridFilters(panelShowsAll: true));
    });

    testWidgets('the close button pops null', (tester) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterHolidays));
      await tap(tester, id(SemanticsIds.filterClose));

      expect(find.byType(CalendarFilterSheet), findsNothing);
      expect(applied.returned, isTrue);
      expect(applied.value, isNull);
    });

    testWidgets('the barrier pops null', (tester) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterHolidays));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarFilterSheet), findsNothing);
      expect(applied.returned, isTrue);
      expect(applied.value, isNull);
    });

    testWidgets('the system back pops null', (tester) async {
      seed(3);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterHolidays));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(CalendarFilterSheet), findsNothing);
      expect(applied.returned, isTrue);
      expect(applied.value, isNull);
    });

    testWidgets('the saved-filter row reads the matching preset and its '
        'bookmark is inert once saved', (tester) async {
      seed(3);
      await service.create(name: 'Training', filters: tracked);
      await open(tester, tracked);

      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'Training');
      expect(bookmark(tester).icon, Icons.bookmark_added_rounded);
      expect(bookmark(tester).onPressed, isNull);

      // Off the preset: re-resolved on every edit, and the bookmark re-arms.
      await tap(tester, id(SemanticsIds.filterHolidays));
      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'None');
      expect(bookmark(tester).icon, Icons.bookmark_add_outlined);
      expect(bookmark(tester).onPressed, isNotNull);

      // Back onto it: saved again.
      await tap(tester, id(SemanticsIds.filterHolidays));
      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'Training');
    });

    testWidgets('the bookmark is inert on an empty draft', (tester) async {
      seed(3);
      await open(tester, CalendarGridFilters.none);

      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'None');
      expect(bookmark(tester).icon, Icons.bookmark_add_outlined);
      expect(bookmark(tester).onPressed, isNull);
    });

    testWidgets('the bookmark saves the draft under a name and the row reads '
        'it back', (tester) async {
      seed(3);
      await open(tester, const CalendarGridFilters(missedOnly: true));

      await tap(tester, id(SemanticsIds.filterSave));
      await tester.enterText(find.byType(TextField), 'Skipped');
      await tap(tester, find.text('Save'));

      expect(service.presets.single.name, 'Skipped');
      expect(find.byType(CalendarFilterSheet), findsOneWidget);
      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'Skipped');
      expect(bookmark(tester).onPressed, isNull);
    });

    testWidgets('the saved-filter row opens the presets and a pick replaces '
        'the draft', (tester) async {
      seed(3);
      await service.create(name: 'Training', filters: tracked);
      final applied = await open(tester, CalendarGridFilters.none);

      await tap(tester, id(SemanticsIds.filterSavedFilter));
      expect(find.byType(FilterPresetSheet), findsOneWidget);
      await tap(tester, find.text('Training'));

      expect(find.byType(FilterPresetSheet), findsNothing);
      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'Training');
      expect(row(tester, SemanticsIds.filterOnlyShow).value, 'Tracked');

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value, tracked);
    });

    testWidgets('No filter in the presets resets the draft and keeps the '
        'panel flag', (tester) async {
      seed(3);
      // The panel flag is part of a preset's identity, so the saved filter
      // carries it too or the row would read None.
      const trackedWithPanel = CalendarGridFilters(
        trackedOnly: true,
        panelShowsAll: true,
      );
      await service.create(name: 'Training', filters: trackedWithPanel);
      final applied = await open(tester, trackedWithPanel);

      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'Training');

      await tap(tester, id(SemanticsIds.filterSavedFilter));
      await tap(tester, id(SemanticsIds.filterPresetNone));

      expect(find.byType(FilterPresetSheet), findsNothing);
      expect(find.byType(CalendarFilterSheet), findsOneWidget);
      expect(row(tester, SemanticsIds.filterSavedFilter).value, 'None');
      expect(row(tester, SemanticsIds.filterOnlyShow).value, 'Everything');
      expect(switchRow(tester, SemanticsIds.filterPanelAll).value, isTrue);
      expect(resetRow(tester).onTap, isNull);

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value, const CalendarGridFilters(panelShowsAll: true));
    });

    testWidgets('a dismissed presets sheet leaves the draft alone', (
      tester,
    ) async {
      seed(3);
      await service.create(name: 'Training', filters: tracked);
      final applied = await open(tester, missedOnly);

      await tap(tester, id(SemanticsIds.filterSavedFilter));
      await tap(tester, id(SemanticsIds.filterPresetClose));

      expect(row(tester, SemanticsIds.filterOnlyShow).value, 'Missed');

      await tap(tester, id(SemanticsIds.filterApply));

      expect(applied.value, missedOnly);
    });

    testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
        'overflows, the value drops under its label and every label is '
        'whole', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      seed(3);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    CalendarFilterSheet.show(context, filters: everyTrait),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The header keeps its title beside Übernehmen.
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Übernehmen'), findsOneWidget);
      // The Only show value drops under its label rather than clipping.
      final label = tester.getRect(find.text('Nur anzeigen'));
      final value = tester.getRect(
        find.text('Mit Anwesenheit, Verpasst +5 weitere'),
      );
      expect(value.top, greaterThanOrEqualTo(label.bottom - 1));
      expect(value.left, label.left);

      await tester.scrollUntilVisible(
        find.text('Filter zurücksetzen'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Alle Ereignisse im Tagesbereich'), findsOneWidget);
    });
  });

  group('agenda filters sheet', () {
    Finder categoriesRow() =>
        find.bySemanticsIdentifier(SemanticsIds.agendaFilterCategories);

    /// What the Categories row reads back.
    String categoriesValue(WidgetTester tester) => tester
        .widget<FormPickerRow>(
          find.ancestor(
            of: categoriesRow(),
            matching: find.byType(FormPickerRow),
          ),
        )
        .value!;

    /// The Categories row sits in the sheet's second group, which a short
    /// surface can put under the fold of the scroll view.
    Future<void> scrollToCategories(WidgetTester tester) {
      return tester.dragUntilVisible(
        categoriesRow(),
        find.byType(SingleChildScrollView).first,
        const Offset(0, -80),
      );
    }

    /// Opens the picker from the row.
    Future<void> openPicker(WidgetTester tester) async {
      await scrollToCategories(tester);
      await tester.tap(categoriesRow());
      await tester.pumpAndSettle();
    }

    /// One picker row whatever the catalog size (Tier 1, D5): the wall of
    /// chips below twelve and the tile above it are gone, and an empty
    /// allowlist reads "All".
    testWidgets('the Categories row reads All whatever the catalog size', (
      tester,
    ) async {
      for (final count in const [6, 15]) {
        seed(count);
        await pumpHost(
          tester,
          (context) => AgendaFiltersSheet.show(
            context,
            filters: const UpcomingAgendaFilters(),
          ),
        );

        await scrollToCategories(tester);
        expect(categoriesValue(tester), 'All', reason: '$count categories');
        expect(find.byType(CategoryFilterTile), findsNothing);
        expect(find.byType(FilterChip), findsNothing);
        // Popped before the next open: a re-pumped host keeps its Navigator,
        // and with it the sheet still up.
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
      }
    });

    /// An explicit allowlist reads its names; the picker's Select all is the
    /// way back to "All" — covering the offered set collapses to the empty
    /// allowlist rather than freezing today's catalog into a list.
    testWidgets('the row reads the names and Select all empties the '
        'allowlist', (tester) async {
      seed(15);
      UpcomingAgendaFilters? applied;
      await pumpHost(tester, (context) async {
        applied = await AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(categoryIds: {'c1', 'c4'}),
        );
      });

      await scrollToCategories(tester);
      expect(categoriesValue(tester), 'Cat1, Cat4');

      await openPicker(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();

      expect(categoriesValue(tester), 'All');

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.categoryIds, isEmpty);
    });

    /// Fifty rows open already checked, because an empty allowlist means
    /// "all" — so narrowing to two costs forty-eight taps without these.
    testWidgets('Select none clears every listed row in one tap', (
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

      await openPicker(tester);

      await tester.tap(find.text('Select none'));
      await tester.pumpAndSettle();
      await tester.tap(pickerRow('Cat3'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(applied?.categoryIds, {'c3'});
    });

    /// Enabled tint on a no-op promises a change that costs a tap to discover
    /// is not there — and an empty allowlist opens every row checked, so the
    /// picker's very first state is the one where Select all does nothing.
    testWidgets('each bulk button is disabled where it would do nothing', (
      tester,
    ) async {
      seed(15);
      await pumpHost(
        tester,
        (context) => AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(),
        ),
      );

      await openPicker(tester);

      FormActionRow rowWith(String label) => tester.widget<FormActionRow>(
        find.widgetWithText(FormActionRow, label),
      );

      expect(rowWith('Select all').onTap, isNull);
      expect(rowWith('Select none').onTap, isNotNull);

      await tester.tap(find.text('Select none'));
      await tester.pumpAndSettle();

      expect(rowWith('Select all').onTap, isNotNull);
      expect(rowWith('Select none').onTap, isNull);
      expect(
        tester
            .widgetList<Checkbox>(
              find.descendant(
                of: find.byType(CategoryPickerSheet),
                matching: find.byType(Checkbox),
              ),
            )
            .every((box) => box.value == false),
        isTrue,
      );
    });

    testWidgets('Select all re-checks every listed row', (tester) async {
      seed(15);
      UpcomingAgendaFilters? applied;
      await pumpHost(tester, (context) async {
        applied = await AgendaFiltersSheet.show(
          context,
          filters: const UpcomingAgendaFilters(categoryIds: {'c1'}),
        );
      });

      await openPicker(tester);

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Covering everything on offer collapses back to the empty set rather
      // than freezing today's catalog into a list.
      expect(applied?.categoryIds, isEmpty);
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
      // An empty allowlist means "all", which is what the row must say.
      expect(categoriesValue(tester), 'All');

      await openPicker(tester);

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
      expect(categoriesValue(tester), 'All');

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

      await openPicker(tester);
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

      // A non-empty allowlist seeds itself, so this adds rather than removes.
      await openPicker(tester);
      // The Select all / none row costs the list a row of height, so the
      // fifth entry can sit under the pinned footer on a small surface.
      await tester.ensureVisible(pickerRow('Cat4'));
      await tester.pumpAndSettle();
      await tester.tap(pickerRow('Cat4'));
      await tester.pumpAndSettle();
      await tester.tap(pickerApply());
      await tester.pumpAndSettle();

      expect(categoriesValue(tester), 'Cat1, Cat4');

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

      await openPicker(tester);
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

/// Mutable holder for the filter sheet's result — the sheet is awaited inside
/// a button callback, so the value arrives after the tap that dismissed it.
class _Applied {
  bool returned = false;
  CalendarGridFilters? value;
}
