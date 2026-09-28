import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/widgets/agenda_filters_sheet.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/filter_check_list_sheet.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';

/// The sheet edits a **draft** and returns it on Apply, so what every case
/// pins is that a pick survives the round trip: the popped
/// [UpcomingAgendaFilters] is compared against the model, never a row's
/// text. Since the 2026-09-27 Tier 1 pass every control is a row or a menu
/// item addressed by its `SemanticsIds` value, and a control that cannot act
/// — fasting without a tradition, the event rows under "No events", Reset on
/// the default draft — is present and inert rather than absent.
void main() {
  Finder id(String value) => find.bySemanticsIdentifier(value);

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

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

  /// Opens the sheet — by default on a phone tall enough that no row sits
  /// below the fold, so every id can be tapped without scrolling — and hands
  /// back a holder the result lands in.
  Future<_Applied> openSheet(
    WidgetTester tester,
    UpcomingAgendaFilters initial, {
    Locale locale = const Locale('en'),
    Size size = const Size(800, 1400),
    double textScale = 1.0,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    final applied = _Applied();
    await tester.pumpWidget(
      MaterialApp(
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
                applied.value = await AgendaFiltersSheet.show(
                  context,
                  filters: initial,
                );
                applied.returned = true;
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

  Future<void> apply(WidgetTester tester) =>
      tap(tester, id(SemanticsIds.agendaFilterApply));

  /// Opens the menu behind a row and picks one of its items.
  Future<void> pick(WidgetTester tester, String rowId, String itemId) async {
    await tap(tester, id(rowId));
    await tap(tester, id(itemId));
  }

  /// The row an id sits on, with the value it reads back — a menu row draws
  /// a picker row, so this serves both.
  FormPickerRow pickerRow(WidgetTester tester, String rowId) =>
      tester.widget<FormPickerRow>(
        find.ancestor(of: id(rowId), matching: find.byType(FormPickerRow)),
      );

  FormMenuRow<T> menuRow<T>(WidgetTester tester, String rowId) =>
      tester.widget<FormMenuRow<T>>(
        find.ancestor(of: id(rowId), matching: find.byType(FormMenuRow<T>)),
      );

  FormSwitchRow switchRow(WidgetTester tester, String rowId) =>
      tester.widget<FormSwitchRow>(
        find.ancestor(of: id(rowId), matching: find.byType(FormSwitchRow)),
      );

  FormActionRow resetRow(WidgetTester tester) => tester.widget<FormActionRow>(
    find.ancestor(
      of: id(SemanticsIds.agendaFilterReset),
      matching: find.byType(FormActionRow),
    ),
  );

  /// The opacity a row is drawn at: the disabled 38 % wraps the row inside
  /// its own node, so it is a descendant of the id. Null when the row draws
  /// no `Opacity` at all (an enabled picker row).
  double? opacityOf(WidgetTester tester, String rowId) {
    final opacities = tester.widgetList<Opacity>(
      find.descendant(of: id(rowId), matching: find.byType(Opacity)),
    );
    return opacities.isEmpty ? null : opacities.first.opacity;
  }

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

  bool isChecked(WidgetTester tester, String itemId) =>
      dataOf(tester, itemId).flagsCollection.isChecked == CheckedState.isTrue;

  group('fasting while inert', () {
    setUp(FastingCalendar.resetConfiguration);

    testWidgets('the fasting controls are present and inert', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      final fasting = switchRow(tester, SemanticsIds.agendaFilterFasting);
      expect(fasting.onChanged, isNull);
      expect(fasting.value, isFalse);
      expect(
        opacityOf(tester, SemanticsIds.agendaFilterFasting),
        FormMetrics.disabledOpacity,
      );
      final rows = menuRow<AgendaFastingDisplay>(
        tester,
        SemanticsIds.agendaFilterFastingRows,
      );
      expect(rows.onSelected, isNull);
      expect(rows.value, 'Periods');
      expect(
        opacityOf(tester, SemanticsIds.agendaFilterFastingRows),
        FormMetrics.disabledOpacity,
      );
      // Their neighbours act: the rows are dimmed, not the group.
      expect(
        switchRow(tester, SemanticsIds.agendaFilterHolidays).onChanged,
        isNotNull,
      );
      expect(
        menuRow<AgendaHolidayDisplay>(
          tester,
          SemanticsIds.agendaFilterHolidayRows,
        ).onSelected,
        isNotNull,
      );

      // Tapping either changes nothing: no menu opens, the switch stays off.
      await tap(tester, id(SemanticsIds.agendaFilterFastingRows));
      expect(find.byType(FormMenuChoiceItem<AgendaFastingDisplay>), findsNothing);
      await tap(tester, id(SemanticsIds.agendaFilterFasting));
      expect(switchRow(tester, SemanticsIds.agendaFilterFasting).value, isFalse);

      await apply(tester);

      expect(applied.value, const UpcomingAgendaFilters());
    });

    testWidgets('picking one holiday card survives Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await pick(
        tester,
        SemanticsIds.agendaFilterHolidayRows,
        SemanticsIds.agendaFilterHolidayRowsSummary,
      );
      expect(
        pickerRow(tester, SemanticsIds.agendaFilterHolidayRows).value,
        'One card',
      );
      await apply(tester);

      expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.summary);
    });

    testWidgets('Reset returns the holiday presentation to every day', (
      tester,
    ) async {
      final applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(
          holidayDisplay: AgendaHolidayDisplay.summary,
        ),
      );

      await tap(tester, id(SemanticsIds.agendaFilterReset));
      await apply(tester);

      expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.everyDay);
    });

    testWidgets('the event rows menu offers all three presentations', (
      tester,
    ) async {
      await openSheet(tester, const UpcomingAgendaFilters());

      await tap(tester, id(SemanticsIds.agendaFilterEventRows));

      for (final item in const [
        SemanticsIds.agendaFilterEventRowsEvery,
        SemanticsIds.agendaFilterEventRowsPerEvent,
        SemanticsIds.agendaFilterEventRowsSummary,
      ]) {
        expect(id(item), findsOneWidget);
        expect(dataOf(tester, item).role, SemanticsRole.menuItemRadio);
      }
      expect(isChecked(tester, SemanticsIds.agendaFilterEventRowsEvery), isTrue);
      expect(
        isChecked(tester, SemanticsIds.agendaFilterEventRowsPerEvent),
        isFalse,
      );
      expect(
        isChecked(tester, SemanticsIds.agendaFilterEventRowsSummary),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking one event card survives Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await pick(
        tester,
        SemanticsIds.agendaFilterEventRows,
        SemanticsIds.agendaFilterEventRowsSummary,
      );
      await apply(tester);

      expect(applied.value!.eventDisplay, AgendaEventDisplay.summary);
      // The three axes are independent: picking one must not drag the others.
      expect(applied.value!.holidayDisplay, AgendaHolidayDisplay.everyDay);
      expect(applied.value!.fastingDisplay, AgendaFastingDisplay.periods);
    });

    testWidgets('Reset returns the event presentation to every occurrence', (
      tester,
    ) async {
      final applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(eventDisplay: AgendaEventDisplay.summary),
      );

      await tap(tester, id(SemanticsIds.agendaFilterReset));
      await apply(tester);

      expect(applied.value!.eventDisplay, AgendaEventDisplay.everyOccurrence);
    });
  });

  group('with a tradition configured', () {
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    testWidgets('both display menus stand side by side, enabled', (
      tester,
    ) async {
      await openSheet(tester, const UpcomingAgendaFilters());

      expect(
        switchRow(tester, SemanticsIds.agendaFilterFasting).onChanged,
        isNotNull,
      );
      expect(opacityOf(tester, SemanticsIds.agendaFilterFasting), 1);
      expect(
        menuRow<AgendaFastingDisplay>(
          tester,
          SemanticsIds.agendaFilterFastingRows,
        ).onSelected,
        isNotNull,
      );
      expect(opacityOf(tester, SemanticsIds.agendaFilterFastingRows), isNull);
      expect(id(SemanticsIds.agendaFilterHolidayRows), findsOneWidget);

      await tap(tester, id(SemanticsIds.agendaFilterFastingRows));

      for (final item in const [
        SemanticsIds.agendaFilterFastingRowsEveryDay,
        SemanticsIds.agendaFilterFastingRowsPeriods,
        SemanticsIds.agendaFilterFastingRowsSummary,
      ]) {
        expect(id(item), findsOneWidget);
        expect(dataOf(tester, item).role, SemanticsRole.menuItemRadio);
      }
      expect(
        isChecked(tester, SemanticsIds.agendaFilterFastingRowsPeriods),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the two axes move independently', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await pick(
        tester,
        SemanticsIds.agendaFilterFastingRows,
        SemanticsIds.agendaFilterFastingRowsSummary,
      );
      await apply(tester);

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

      await tap(tester, id(SemanticsIds.agendaFilterReset));
      await apply(tester);

      expect(applied.value!.fastingDisplay, AgendaFastingDisplay.periods);
    });

    testWidgets('the Fasting switch survives Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await tap(tester, id(SemanticsIds.agendaFilterFasting));
      await apply(tester);

      expect(applied.value!.showFasting, isTrue);
    });
  });

  /// The Period row is one mutually exclusive axis across six choices: three
  /// rolling presets, two calendar-year windows and the custom range. Picking
  /// any of them has to leave the others off, which is the only way the row
  /// can honestly read what the agenda is doing.
  group('the Period menu', () {
    const sixItems = [
      SemanticsIds.agendaFilterPeriod7,
      SemanticsIds.agendaFilterPeriod30,
      SemanticsIds.agendaFilterPeriod90,
      SemanticsIds.agendaFilterPeriodRestOfYear,
      SemanticsIds.agendaFilterPeriodThisYear,
      SemanticsIds.agendaFilterPeriodCustom,
    ];

    testWidgets('its six items carry their ids and the current one is checked', (
      tester,
    ) async {
      await openSheet(tester, const UpcomingAgendaFilters());
      expect(pickerRow(tester, SemanticsIds.agendaFilterPeriod).value, '30 days');

      await tap(tester, id(SemanticsIds.agendaFilterPeriod));

      for (final item in sixItems) {
        expect(id(item), findsOneWidget);
        expect(dataOf(tester, item).role, SemanticsRole.menuItemRadio);
        expect(
          isChecked(tester, item),
          item == SemanticsIds.agendaFilterPeriod30,
          reason: item,
        );
      }
      expect(find.text('Custom range…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pinned range checks Custom range… and reads the range back', (
      tester,
    ) async {
      final start = DateTime.utc(2026, 5, 1);
      final end = DateTime.utc(2026, 5, 15);
      await openSheet(
        tester,
        UpcomingAgendaFilters(customStart: start, customEnd: end),
      );

      expect(
        pickerRow(tester, SemanticsIds.agendaFilterPeriod).value,
        AgendaListView.rangeLabel('en', start, end),
      );

      await tap(tester, id(SemanticsIds.agendaFilterPeriod));

      for (final item in sixItems) {
        expect(
          isChecked(tester, item),
          item == SemanticsIds.agendaFilterPeriodCustom,
          reason: item,
        );
      }
    });

    /// A window another build stored is read back as its own count rather
    /// than snapped to the nearest preset, so the row never claims a choice
    /// the user did not make.
    testWidgets('a stored window outside the presets reads its count and '
        'checks nothing', (tester) async {
      await openSheet(tester, const UpcomingAgendaFilters(rangeDays: 14));
      expect(pickerRow(tester, SemanticsIds.agendaFilterPeriod).value, '14 days');

      await tap(tester, id(SemanticsIds.agendaFilterPeriod));

      for (final item in sixItems) {
        expect(isChecked(tester, item), isFalse, reason: item);
      }
    });

    testWidgets('picking this year survives Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await pick(
        tester,
        SemanticsIds.agendaFilterPeriod,
        SemanticsIds.agendaFilterPeriodThisYear,
      );
      expect(
        pickerRow(tester, SemanticsIds.agendaFilterPeriod).value,
        'This year',
      );
      await apply(tester);

      expect(applied.value!.periodMode, AgendaPeriodMode.wholeYear);
    });

    testWidgets('picking the rest of the year survives Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await pick(
        tester,
        SemanticsIds.agendaFilterPeriod,
        SemanticsIds.agendaFilterPeriodRestOfYear,
      );
      await apply(tester);

      expect(applied.value!.periodMode, AgendaPeriodMode.restOfYear);
    });

    testWidgets('a year window drops a pinned custom range', (tester) async {
      final applied = await openSheet(
        tester,
        UpcomingAgendaFilters(
          customStart: DateTime.utc(2026, 5, 1),
          customEnd: DateTime.utc(2026, 5, 15),
        ),
      );

      await pick(
        tester,
        SemanticsIds.agendaFilterPeriod,
        SemanticsIds.agendaFilterPeriodThisYear,
      );
      await apply(tester);

      // Both would otherwise be live at once, with the pinned range silently
      // winning over the item the user just picked.
      expect(applied.value!.periodMode, AgendaPeriodMode.wholeYear);
      expect(applied.value!.hasCustomRange, isFalse);
    });

    testWidgets('a day preset takes the window back off the year', (
      tester,
    ) async {
      final applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(periodMode: AgendaPeriodMode.wholeYear),
      );

      await pick(
        tester,
        SemanticsIds.agendaFilterPeriod,
        SemanticsIds.agendaFilterPeriod7,
      );
      await apply(tester);

      expect(applied.value!.periodMode, AgendaPeriodMode.rollingDays);
      expect(applied.value!.rangeDays, 7);
    });

    testWidgets('Reset returns the window to the rolling default', (
      tester,
    ) async {
      final applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(periodMode: AgendaPeriodMode.restOfYear),
      );

      await tap(tester, id(SemanticsIds.agendaFilterReset));
      await apply(tester);

      expect(applied.value!.periodMode, AgendaPeriodMode.rollingDays);
      expect(applied.value!.rangeDays, UpcomingAgendaFilters.defaultRangeDays);
    });

    testWidgets('Custom range… leaves the draft alone when the range dialog '
        'is dismissed', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await pick(
        tester,
        SemanticsIds.agendaFilterPeriod,
        SemanticsIds.agendaFilterPeriodCustom,
      );
      expect(find.byType(DateRangePickerDialog), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(DateRangePickerDialog), findsNothing);
      expect(find.byType(AgendaFiltersSheet), findsOneWidget);
      expect(pickerRow(tester, SemanticsIds.agendaFilterPeriod).value, '30 days');

      await apply(tester);

      expect(applied.value, const UpcomingAgendaFilters());
    });

    /// Opened over a pinned range so the dialog lands on a known month; a
    /// tap on a day starts a new range, the next tap ends it.
    testWidgets('Custom range… writes both dates when the range is confirmed', (
      tester,
    ) async {
      final applied = await openSheet(
        tester,
        UpcomingAgendaFilters(
          customStart: DateTime.utc(2026, 5, 1),
          customEnd: DateTime.utc(2026, 5, 15),
        ),
      );

      await pick(
        tester,
        SemanticsIds.agendaFilterPeriod,
        SemanticsIds.agendaFilterPeriodCustom,
      );
      await tap(tester, find.bySemanticsLabel(RegExp(r'May 10, 2026')));
      await tap(tester, find.bySemanticsLabel(RegExp(r'May 20, 2026')));
      await tap(tester, find.text('Save'));

      expect(find.byType(DateRangePickerDialog), findsNothing);
      final start = DateTime.utc(2026, 5, 10);
      final end = DateTime.utc(2026, 5, 20);
      expect(
        pickerRow(tester, SemanticsIds.agendaFilterPeriod).value,
        AgendaListView.rangeLabel('en', start, end),
      );

      await apply(tester);

      expect(applied.value!.customStart, start);
      expect(applied.value!.customEnd, end);
      expect(applied.value!.periodMode, AgendaPeriodMode.rollingDays);
    });
  });

  group('the Events menu', () {
    testWidgets('offers the whole axis, and No events dims Categories and '
        'Priority until events are listed again', (tester) async {
      seed(3);
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await tap(tester, id(SemanticsIds.agendaFilterEvents));
      for (final item in const [
        SemanticsIds.agendaFilterEventsAll,
        SemanticsIds.agendaFilterEventsRecurring,
        SemanticsIds.agendaFilterEventsOneTime,
        SemanticsIds.agendaFilterEventsNone,
      ]) {
        expect(id(item), findsOneWidget);
        expect(dataOf(tester, item).role, SemanticsRole.menuItemRadio);
      }
      expect(isChecked(tester, SemanticsIds.agendaFilterEventsAll), isTrue);

      await tap(tester, id(SemanticsIds.agendaFilterEventsNone));

      expect(
        pickerRow(tester, SemanticsIds.agendaFilterEvents).value,
        'No events',
      );
      for (final row in const [
        SemanticsIds.agendaFilterCategories,
        SemanticsIds.agendaFilterPriority,
      ]) {
        expect(pickerRow(tester, row).enabled, isFalse, reason: row);
        expect(pickerRow(tester, row).onTap, isNull, reason: row);
        expect(opacityOf(tester, row), FormMetrics.disabledOpacity, reason: row);
        final data = dataOf(tester, row);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse, reason: row);
        expect(data.hasAction(SemanticsAction.tap), isFalse, reason: row);
      }
      // Present with their values, inert: a tap opens nothing.
      expect(pickerRow(tester, SemanticsIds.agendaFilterCategories).value, 'All');
      expect(pickerRow(tester, SemanticsIds.agendaFilterPriority).value, 'Any');
      await tap(tester, id(SemanticsIds.agendaFilterCategories));
      expect(find.byType(CategoryPickerSheet), findsNothing);
      await tap(tester, id(SemanticsIds.agendaFilterPriority));
      expect(find.byType(FilterCheckListSheet), findsNothing);

      await pick(
        tester,
        SemanticsIds.agendaFilterEvents,
        SemanticsIds.agendaFilterEventsAll,
      );

      for (final row in const [
        SemanticsIds.agendaFilterCategories,
        SemanticsIds.agendaFilterPriority,
      ]) {
        expect(pickerRow(tester, row).enabled, isTrue, reason: row);
        expect(opacityOf(tester, row), isNull, reason: row);
        expect(
          dataOf(tester, row).flagsCollection.isEnabled,
          isNot(Tristate.isFalse),
          reason: row,
        );
      }
      await tap(tester, id(SemanticsIds.agendaFilterCategories));
      expect(find.byType(CategoryPickerSheet), findsOneWidget);
      await tap(tester, id(SemanticsIds.categoryPickClose));
      await tap(tester, id(SemanticsIds.agendaFilterPriority));
      expect(find.byType(FilterCheckListSheet), findsOneWidget);
      await tap(tester, id(SemanticsIds.filterListClose));

      await apply(tester);

      expect(applied.value, const UpcomingAgendaFilters());
    });

    testWidgets('picking Recurring or One-time survives Apply', (tester) async {
      var applied = await openSheet(tester, const UpcomingAgendaFilters());
      await pick(
        tester,
        SemanticsIds.agendaFilterEvents,
        SemanticsIds.agendaFilterEventsRecurring,
      );
      expect(
        pickerRow(tester, SemanticsIds.agendaFilterEvents).value,
        'Recurring',
      );
      await apply(tester);
      expect(applied.value!.eventType, AgendaEventType.recurring);

      applied = await openSheet(tester, const UpcomingAgendaFilters());
      await pick(
        tester,
        SemanticsIds.agendaFilterEvents,
        SemanticsIds.agendaFilterEventsOneTime,
      );
      await apply(tester);
      expect(applied.value!.eventType, AgendaEventType.oneTime);
    });

    testWidgets('No events survives Apply, with the rows it dims untouched', (
      tester,
    ) async {
      final applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(priorities: {1}, categoryIds: {'c1'}),
      );

      await pick(
        tester,
        SemanticsIds.agendaFilterEvents,
        SemanticsIds.agendaFilterEventsNone,
      );
      await apply(tester);

      expect(applied.value!.eventType, AgendaEventType.none);
      expect(applied.value!.priorities, {1});
      expect(applied.value!.categoryIds, {'c1'});
    });
  });

  group('Categories and Priority', () {
    testWidgets('the Categories row reads All, the names, +N more, or No '
        'categories', (tester) async {
      seed(5);
      final cases = <UpcomingAgendaFilters, String>{
        const UpcomingAgendaFilters(): 'All',
        const UpcomingAgendaFilters(categoryIds: {'c1', 'c4'}): 'Cat1, Cat4',
        const UpcomingAgendaFilters(categoryIds: {'c0', 'c1', 'c2'}):
            'Cat0, Cat1 +1 more',
        // A stale id left by a deleted category names nothing.
        const UpcomingAgendaFilters(categoryIds: {'gone'}): 'No categories',
      };
      for (final MapEntry(key: filters, value: expected) in cases.entries) {
        await openSheet(tester, filters);
        expect(
          pickerRow(tester, SemanticsIds.agendaFilterCategories).value,
          expected,
        );
        // Popped before the next open: a re-pumped app keeps its Navigator,
        // and with it the sheet still up.
        await apply(tester);
      }
    });

    testWidgets('the Priority row reads Any, then the labels ascending', (
      tester,
    ) async {
      final cases = <UpcomingAgendaFilters, String>{
        const UpcomingAgendaFilters(): 'Any',
        const UpcomingAgendaFilters(priorities: {2, 1}): 'Highest, High',
        const UpcomingAgendaFilters(priorities: {3, 1, 2}):
            'Highest, High +1 more',
      };
      for (final MapEntry(key: filters, value: expected) in cases.entries) {
        await openSheet(tester, filters);
        expect(
          pickerRow(tester, SemanticsIds.agendaFilterPriority).value,
          expected,
        );
        await apply(tester);
      }
    });

    testWidgets('the picker answer is the allowlist', (tester) async {
      seed(3);
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await tap(tester, id(SemanticsIds.agendaFilterCategories));
      expect(find.byType(CategoryPickerSheet), findsOneWidget);
      // An empty allowlist opens every row checked, so un-ticking narrows.
      await tap(
        tester,
        find.descendant(
          of: find.byType(CategoryPickerSheet),
          matching: find.text('Cat0'),
        ),
      );
      await tap(tester, id(SemanticsIds.categoryPickDone));

      expect(
        pickerRow(tester, SemanticsIds.agendaFilterCategories).value,
        'Cat1, Cat2',
      );

      await apply(tester);

      expect(applied.value!.categoryIds, {'c1', 'c2'});
    });

    testWidgets('Priority Done writes the set and a dismissed sub-sheet '
        'changes nothing', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await tap(tester, id(SemanticsIds.agendaFilterPriority));
      expect(find.byType(FilterCheckListSheet), findsOneWidget);
      await tap(tester, id(SemanticsIds.filterListRow('priority-2')));
      await tap(tester, id(SemanticsIds.filterListRow('priority-1')));
      await tap(tester, id(SemanticsIds.filterListDone));

      expect(find.byType(FilterCheckListSheet), findsNothing);
      expect(
        pickerRow(tester, SemanticsIds.agendaFilterPriority).value,
        'Highest, High',
      );

      await tap(tester, id(SemanticsIds.agendaFilterPriority));
      await tap(tester, id(SemanticsIds.filterListRow('priority-5')));
      await tap(tester, id(SemanticsIds.filterListClose));

      expect(
        pickerRow(tester, SemanticsIds.agendaFilterPriority).value,
        'Highest, High',
      );

      await apply(tester);

      expect(applied.value!.priorities, {1, 2});
    });
  });

  group('Reset, Apply and leaving', () {
    testWidgets('Reset is inert on the default draft, enabled after a change, '
        'and keeps the sheet open', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());
      expect(resetRow(tester).onTap, isNull);
      expect(
        opacityOf(tester, SemanticsIds.agendaFilterReset),
        FormMetrics.disabledOpacity,
      );

      await tap(tester, id(SemanticsIds.agendaFilterHolidays));
      expect(switchRow(tester, SemanticsIds.agendaFilterHolidays).value, isTrue);
      expect(resetRow(tester).onTap, isNotNull);
      expect(opacityOf(tester, SemanticsIds.agendaFilterReset), 1);

      await tap(tester, id(SemanticsIds.agendaFilterReset));

      expect(find.byType(AgendaFiltersSheet), findsOneWidget);
      expect(applied.returned, isFalse);
      expect(switchRow(tester, SemanticsIds.agendaFilterHolidays).value, isFalse);
      expect(resetRow(tester).onTap, isNull);

      await apply(tester);

      expect(applied.value, const UpcomingAgendaFilters());
    });

    testWidgets('Reset keeps the query and never counts it as a change', (
      tester,
    ) async {
      var applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(query: 'gym'),
      );
      expect(resetRow(tester).onTap, isNull);
      await apply(tester);
      expect(applied.value!.query, 'gym');

      applied = await openSheet(
        tester,
        const UpcomingAgendaFilters(query: 'gym', showHolidays: true),
      );
      expect(resetRow(tester).onTap, isNotNull);
      await tap(tester, id(SemanticsIds.agendaFilterReset));
      await apply(tester);

      expect(applied.value, const UpcomingAgendaFilters(query: 'gym'));
    });

    testWidgets('an untouched Apply pops the draft it was given', (
      tester,
    ) async {
      seed(3);
      final initial = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.restOfYear,
        rangeDays: 90,
        priorities: const {1, 3},
        query: 'run',
        showHolidays: true,
        showFasting: true,
        eventDisplay: AgendaEventDisplay.perEvent,
        fastingDisplay: AgendaFastingDisplay.summary,
        holidayDisplay: AgendaHolidayDisplay.summary,
        followSelectedDay: true,
        eventType: AgendaEventType.recurring,
        categoryIds: const {'c2'},
      );
      final applied = await openSheet(tester, initial);

      await apply(tester);

      expect(applied.returned, isTrue);
      expect(applied.value, initial);
    });

    testWidgets('the switches survive Apply', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());

      await tap(tester, id(SemanticsIds.agendaFilterFollow));
      await tap(tester, id(SemanticsIds.agendaFilterHolidays));
      await apply(tester);

      expect(applied.value!.followSelectedDay, isTrue);
      expect(applied.value!.showHolidays, isTrue);
    });

    testWidgets('the close button pops null and keeps nothing', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());
      await tap(tester, id(SemanticsIds.agendaFilterHolidays));

      await tap(tester, id(SemanticsIds.agendaFilterClose));

      expect(applied.returned, isTrue);
      expect(applied.value, isNull);
      expect(find.byType(AgendaFiltersSheet), findsNothing);
    });

    testWidgets('the barrier pops null', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());
      await tap(tester, id(SemanticsIds.agendaFilterHolidays));

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(applied.returned, isTrue);
      expect(applied.value, isNull);
      expect(find.byType(AgendaFiltersSheet), findsNothing);
    });

    testWidgets('the system back pops null', (tester) async {
      final applied = await openSheet(tester, const UpcomingAgendaFilters());
      await tap(tester, id(SemanticsIds.agendaFilterHolidays));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(applied.returned, isTrue);
      expect(applied.value, isNull);
      expect(find.byType(AgendaFiltersSheet), findsNothing);
    });
  });

  group('layout stress', () {
    testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
        'overflows, the Period value drops under its label and every label '
        'is whole', (tester) async {
      seed(3);
      final start = DateTime.utc(2026, 5, 1);
      final end = DateTime.utc(2026, 5, 15);
      await openSheet(
        tester,
        UpcomingAgendaFilters(
          customStart: start,
          customEnd: end,
          priorities: const {1, 2},
          showHolidays: true,
        ),
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      // The header keeps its title beside Übernehmen.
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Übernehmen'), findsOneWidget);
      // The Period value drops under its label rather than clipping.
      final rangeLabel = AgendaListView.rangeLabel('de', start, end);
      final label = tester.getRect(find.text('Zeitraum'));
      final value = tester.getRect(find.text(rangeLabel));
      expect(value.top, greaterThanOrEqualTo(label.bottom - 1));
      expect(value.left, label.left);
      // The switch labels stay whole beside their switches.
      expect(find.text('Ab ausgewähltem Tag'), findsOneWidget);
      expect(find.text('Feiertage'), findsOneWidget);

      // The Period menu widens for its German items instead of cutting them.
      await tap(tester, id(SemanticsIds.agendaFilterPeriod));
      expect(find.text('Eigener Zeitraum…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Filter zurücksetzen'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Feiertags-Zeilen'), findsOneWidget);
      expect(find.text('Fasten-Zeilen'), findsOneWidget);
    });

    testWidgets('on a 360 × 780 phone everything through Priority is above '
        'the fold', (tester) async {
      await openSheet(
        tester,
        const UpcomingAgendaFilters(),
        size: const Size(360, 780),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(id(SemanticsIds.agendaFilterPriority)).bottom,
        lessThan(780),
      );
      expect(
        tester.getRect(id(SemanticsIds.agendaFilterApply)).bottom,
        lessThan(780 * 0.08 + 48 + 22 + 8),
      );
    });

    testWidgets('on a 412 × 915 phone the sheet fits whole', (tester) async {
      await openSheet(
        tester,
        const UpcomingAgendaFilters(),
        size: const Size(412, 915),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(id(SemanticsIds.agendaFilterReset)).bottom,
        lessThanOrEqualTo(915),
      );
    });
  });
}

/// Mutable holder for the sheet's result — the sheet is awaited inside a
/// button callback, so the value arrives after the tap that dismissed it, and
/// [returned] tells a `null` result from a sheet still open.
class _Applied {
  UpcomingAgendaFilters? value;
  bool returned = false;
}
