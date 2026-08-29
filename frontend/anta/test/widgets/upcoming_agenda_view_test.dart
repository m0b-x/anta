import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/upcoming_agenda_view.dart';

/// Widget tests for [UpcomingAgendaView], driven against fakes with no
/// database — the agenda scan is pure and the row facades
/// (presence/description) resolve through their uninitialized fallbacks.
///
/// Two readouts are deterministic. The panel header (`N entries · <range>`) is
/// derived purely from the anchor and `rangeDays`, and is the only Text
/// carrying a middle dot. The summary chips are derived purely from the
/// filters, and are the only chips left inline now that everything else moved
/// into the filters sheet.
void main() {
  /// Occurs every day, so any window is non-empty and its first day is the
  /// window start.
  final daily = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
  );

  /// One stable list instance across pumps — the calendar bloc preserves
  /// `allEvents` identity on a day tap, so the view's `identical(events)` guard
  /// stays quiet and only the anchor drives (or does not drive) a rescan.
  final events = [daily];

  /// A day far enough from the real clock that the agenda never relabels it.
  ///
  /// `AgendaListView.dayHeaderLabel` substitutes "Today"/"Tomorrow" for the two
  /// days around `DateTime.now()`, deliberately, so a panel left open across
  /// midnight relabels itself. That makes a fixture pinned to a literal date a
  /// time bomb: this file used to assert "August 26" and went red on every
  /// 25 August. Anchoring off the clock is what keeps these assertions honest.
  DateTime farDay(int offsetDays) =>
      EventAgenda.dateOnly(DateTime.now()).add(Duration(days: 60 + offsetDays));

  /// The exact strings the agenda renders for [day]: the day-group header
  /// inside the list, and the abbreviated form used in the panel header.
  String dayHeader(DateTime day) => DateFormat.MMMMEEEEd('en').format(day);
  String rangeStamp(DateTime day) => DateFormat.MMMd('en').format(day);

  Future<void> pumpView(
    WidgetTester tester, {
    required DateTime anchorDay,
    required UpcomingAgendaFilters filters,
    ValueChanged<UpcomingAgendaFilters>? onFiltersChanged,
    VoidCallback? onResetAnchor,
    ValueChanged<DateTime>? onDaySelected,
    void Function(CalendarEvent event, DateTime day)? onEditEvent,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: UpcomingAgendaView(
            events: events,
            anchorDay: anchorDay,
            onResetAnchor: onResetAnchor,
            hiddenCategoryIds: const {},
            filters: filters,
            onFiltersChanged: onFiltersChanged ?? (_) {},
            onDaySelected: onDaySelected ?? (_) {},
            onEditEvent: onEditEvent ?? (_, _) {},
            onOpenNote: (_) {},
          ),
        ),
      ),
    );
  }

  /// The panel header string — the single Text carrying a middle dot.
  String header(WidgetTester tester) {
    final texts = tester.widgetList<Text>(find.byType(Text));
    return texts.firstWhere((t) => (t.data ?? '').contains('·')).data!;
  }

  /// Every summary chip's delete button carries the same tooltip, so a test
  /// that pumps exactly one chip can address it without reaching for whichever
  /// icon the current Material version draws there.
  final removeFilter = find.byTooltip('Remove filter');

  testWidgets('anchor change with no custom range moves the window', (
    tester,
  ) async {
    const filters = UpcomingAgendaFilters(rangeDays: 30);
    final first = farDay(0);
    final second = farDay(31);

    await pumpView(tester, anchorDay: first, filters: filters);
    expect(header(tester), contains(rangeStamp(first)));
    // The first day-group header is scan output (a row), not the pure range
    // label — asserting it proves the scan actually re-ran, not just that the
    // header getter recomputed. Full month name, so it cannot collide with the
    // abbreviated stamp in the panel header.
    expect(find.textContaining(dayHeader(first)), findsOneWidget);

    await pumpView(tester, anchorDay: second, filters: filters);
    await tester.pump();
    expect(header(tester), contains(rangeStamp(second)));
    expect(header(tester), isNot(contains(rangeStamp(first))));
    expect(find.textContaining(dayHeader(second)), findsOneWidget);
    expect(find.textContaining(dayHeader(first)), findsNothing);
  });

  testWidgets('anchor change under a custom range leaves the window put', (
    tester,
  ) async {
    final filters = UpcomingAgendaFilters(
      rangeDays: 30,
      customStart: DateTime.utc(2026, 5, 1),
      customEnd: DateTime.utc(2026, 5, 15),
    );

    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: filters,
    );
    final before = header(tester);
    expect(before, contains('May 1'));

    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 9, 10),
      filters: filters,
    );
    expect(header(tester), before);
  });

  testWidgets('a pinned custom range suppresses the anchor rescan', (
    tester,
  ) async {
    // The regression this guard exists to prevent: with a custom range pinned,
    // moving the anchor must not re-run the scan. Counted with the same debug
    // seam the bloc budget test uses — the header alone could not catch a
    // stale-but-unchanged scan.
    final pinned = UpcomingAgendaFilters(
      rangeDays: 30,
      customStart: DateTime.utc(2026, 5, 1),
      customEnd: DateTime.utc(2026, 5, 30),
    );
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: pinned,
    );

    CalendarEvent.debugOccursOnCalls = 0;
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 9, 10),
      filters: pinned,
    );
    expect(CalendarEvent.debugOccursOnCalls, 0);
  });

  testWidgets('an anchor move with no custom range runs one window scan', (
    tester,
  ) async {
    const filters = UpcomingAgendaFilters(rangeDays: 30);
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: filters,
    );

    CalendarEvent.debugOccursOnCalls = 0;
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 9, 10),
      filters: filters,
    );
    // One daily (recurring) event across a 30-day window: one occursOn per day
    // and no more — the rescan ran once, not once per rebuild.
    expect(CalendarEvent.debugOccursOnCalls, 30);
  });

  testWidgets('re-selecting the same anchor day does not rescan', (
    tester,
  ) async {
    const filters = UpcomingAgendaFilters(rangeDays: 30);
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: filters,
    );

    CalendarEvent.debugOccursOnCalls = 0;
    // The bloc normalizes selectedDay, so re-anchoring on the already-anchored
    // day hands back an equal anchor — the guard must recognise it and skip the
    // scan (the "second select of the same day costs zero" contract).
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: filters,
    );
    expect(CalendarEvent.debugOccursOnCalls, 0);
  });

  testWidgets('Events: None hides all event rows', (tester) async {
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: const UpcomingAgendaFilters(rangeDays: 30),
    );
    expect(find.text('Leg day'), findsWidgets);

    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: const UpcomingAgendaFilters(
        rangeDays: 30,
        eventType: AgendaEventType.none,
      ),
    );
    expect(find.text('Leg day'), findsNothing);
  });

  group('summary chips', () {
    testWidgets('defaults leave the inline surface chip-free', (tester) async {
      await pumpView(
        tester,
        anchorDay: EventAgenda.dateOnly(DateTime.now()),
        filters: const UpcomingAgendaFilters(),
      );

      // No restrictive filter, anchored on today: nothing to summarise, and
      // nothing to return the window from.
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('a layer toggle is not a restriction', (tester) async {
      await pumpView(
        tester,
        anchorDay: EventAgenda.dateOnly(DateTime.now()),
        filters: const UpcomingAgendaFilters(
          showHolidays: true,
          eventDisplay: AgendaEventDisplay.perEvent,
        ),
      );

      // Showing holidays adds rows and collapsing condenses them; neither can
      // explain a missing entry, so neither earns a chip.
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('each restriction gets its own chip', (tester) async {
      await pumpView(
        tester,
        anchorDay: EventAgenda.dateOnly(DateTime.now()),
        filters: const UpcomingAgendaFilters(
          rangeDays: 90,
          eventType: AgendaEventType.recurring,
          priorities: {1},
          categoryIds: {'gym'},
        ),
      );

      expect(find.byType(InputChip), findsNWidgets(4));
      expect(find.text('90 days'), findsOneWidget);
      expect(find.text('Recurring'), findsOneWidget);
    });

    testWidgets('deleting the range chip clears the custom range', (
      tester,
    ) async {
      UpcomingAgendaFilters? captured;
      final filters = UpcomingAgendaFilters(
        rangeDays: 30,
        customStart: DateTime.utc(2026, 5, 1),
        customEnd: DateTime.utc(2026, 5, 15),
      );

      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: filters,
        onFiltersChanged: (f) => captured = f,
      );

      // A pinned range makes the anchor irrelevant, so the anchor chip is
      // absent and this is the only chip in the tree.
      expect(find.byType(InputChip), findsOneWidget);
      await tester.tap(removeFilter);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.hasCustomRange, isFalse);
      expect(captured!.customStart, isNull);
      expect(captured!.customEnd, isNull);
    });

    testWidgets('deleting the priority chip clears the priority filter', (
      tester,
    ) async {
      UpcomingAgendaFilters? captured;

      await pumpView(
        tester,
        anchorDay: EventAgenda.dateOnly(DateTime.now()),
        filters: const UpcomingAgendaFilters(priorities: {1, 2}),
        onFiltersChanged: (f) => captured = f,
      );

      await tester.tap(removeFilter);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.priorities, isEmpty);
    });
  });

  group('anchor chip', () {
    testWidgets('is absent while the window starts today', (tester) async {
      await pumpView(
        tester,
        anchorDay: EventAgenda.dateOnly(DateTime.now()),
        filters: const UpcomingAgendaFilters(),
        onResetAnchor: () {},
      );

      expect(find.byTooltip('Back to today'), findsNothing);
    });

    testWidgets('appears once the anchor moves, and resets it', (tester) async {
      var reset = 0;
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: const UpcomingAgendaFilters(),
        onResetAnchor: () => reset++,
      );

      expect(find.textContaining('from Aug 10'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to today'));
      await tester.pump();
      expect(reset, 1);
    });

    testWidgets('stays away while a custom range pins the window', (
      tester,
    ) async {
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: UpcomingAgendaFilters(
          customStart: DateTime.utc(2026, 5, 1),
          customEnd: DateTime.utc(2026, 5, 15),
        ),
        onResetAnchor: () {},
      );

      // The anchor is ignored under a pinned range, so offering to "return" to
      // today would move nothing.
      expect(find.byTooltip('Back to today'), findsNothing);
    });
  });

  testWidgets('the list reserves room for the page\'s add button', (
    tester,
  ) async {
    // The reported bug: the FAB floats over this list, so without reserved
    // clearance the last row's edit and open-note buttons sit underneath it
    // and cannot be tapped. Padding rather than hiding the button is what
    // makes them reachable at every scroll position.
    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: const UpcomingAgendaFilters(rangeDays: 30),
    );

    final list = tester.widget<AgendaListView>(find.byType(AgendaListView));
    expect(list.padding.bottom, greaterThanOrEqualTo(AppSpacing.fabClearance));
  });

  group('holiday display', () {
    // Assumption (Aug 15) and All Saints (Nov 1) both resolve through the
    // uninitialized fixed-date fallback, so a 90-day window from Aug 10 holds
    // exactly two holidays with no profile configured.
    const shown = UpcomingAgendaFilters(rangeDays: 90, showHolidays: true);
    final anchor = DateTime.utc(2026, 8, 10);

    testWidgets('every-day mode lists the holiday on its own day', (
      tester,
    ) async {
      // A short window anchored on the holiday itself: the list is lazily
      // built, so a 90-day window would leave the row below the fold and the
      // absence would prove nothing.
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 14),
        filters: const UpcomingAgendaFilters(rangeDays: 3, showHolidays: true),
      );

      expect(find.text('Assumption of Mary'), findsOneWidget);
      expect(find.text('Holidays'), findsNothing);
    });

    testWidgets('summary mode condenses them into one card', (tester) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: shown.copyWith(holidayDisplay: AgendaHolidayDisplay.summary),
      );

      expect(find.text('Holidays'), findsOneWidget);
      expect(find.text('2 holidays'), findsOneWidget);
      expect(find.text('Aug 15 – Nov 1'), findsOneWidget);
      // The individual rows are gone from the list — they live in the
      // drill-down now.
      expect(find.text('Assumption of Mary'), findsNothing);
    });

    testWidgets('changing the presentation costs no event rescan', (
      tester,
    ) async {
      // Holidays never enter the event scan and the days are already resolved,
      // so this is a pure re-render: the memo key is the whole mechanism.
      await pumpView(tester, anchorDay: anchor, filters: shown);

      CalendarEvent.debugOccursOnCalls = 0;
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: shown.copyWith(holidayDisplay: AgendaHolidayDisplay.summary),
      );
      await tester.pump();
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });

    testWidgets('the card drills down to the holidays it stands for', (
      tester,
    ) async {
      DateTime? selected;
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: shown.copyWith(holidayDisplay: AgendaHolidayDisplay.summary),
        onDaySelected: (day) => selected = day,
      );

      await tester.tap(find.byTooltip('Show every day'));
      await tester.pumpAndSettle();

      // Same two holidays the card counted, now named and dated.
      expect(find.text('Assumption of Mary'), findsOneWidget);
      expect(find.text("All Saints' Day"), findsOneWidget);
      expect(find.text('Saturday, August 15'), findsOneWidget);

      await tester.tap(find.text("All Saints' Day"));
      await tester.pumpAndSettle();

      expect(selected, DateTime.utc(2026, 11, 1));
    });

    testWidgets('the card is not counted among the entries', (tester) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: shown.copyWith(holidayDisplay: AgendaHolidayDisplay.summary),
      );
      final withCard = header(tester);

      await pumpView(
        tester,
        anchorDay: anchor,
        filters: shown.copyWith(holidayDisplay: AgendaHolidayDisplay.everyDay),
      );
      await tester.pump();
      final withRows = header(tester);

      // Ninety daily occurrences either way; the two holiday rows are entries
      // and the card that replaces them is not, so the count drops by exactly
      // two rather than by one.
      expect(withRows, contains('92 entries'));
      expect(withCard, contains('90 entries'));
    });
  });

  group('fasting display', () {
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    const shown = UpcomingAgendaFilters(rangeDays: 30, showFasting: true);

    testWidgets('changing the presentation costs no event rescan', (
      tester,
    ) async {
      // Fasting days never enter the event scan, so moving between the three
      // presentations must re-derive only the annotation layer — the same
      // counting seam the anchor tests use.
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: shown,
      );

      CalendarEvent.debugOccursOnCalls = 0;
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: shown.copyWith(fastingDisplay: AgendaFastingDisplay.summary),
      );
      await tester.pump();
      expect(CalendarEvent.debugOccursOnCalls, 0);

      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: shown.copyWith(fastingDisplay: AgendaFastingDisplay.everyDay),
      );
      await tester.pump();
      expect(CalendarEvent.debugOccursOnCalls, 0);
    });

    testWidgets('the summary condenses the fasting rows to one card', (
      tester,
    ) async {
      // Every fasting day listed: an August window carries the Dormition Fast
      // plus the year-round Wednesday/Friday rule, so there is plenty to
      // condense.
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: shown.copyWith(fastingDisplay: AgendaFastingDisplay.everyDay),
      );
      final perDay = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data == 'Dormition Fast')
          .length;
      expect(perDay, greaterThan(1));

      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 8, 10),
        filters: shown.copyWith(fastingDisplay: AgendaFastingDisplay.summary),
      );
      await tester.pump();
      expect(find.text('Dormition Fast'), findsOneWidget);
    });
  });

  group('event display', () {
    const window = UpcomingAgendaFilters(rangeDays: 30);
    final anchor = DateTime.utc(2026, 8, 10);

    // `CalendarCategories` is a facade `CategoryService` normally fills; a bare
    // widget test resolves every id to the `other` fallback without this, so
    // the card would be titled "Other" whatever category it holds.
    setUp(() {
      CalendarCategories.updateCache([
        for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
          CalendarCategory(
            id: seed.id,
            name: seed.kind.name,
            colorValue: seed.colorValue,
            iconKey: seed.iconKey,
            sortOrder: index,
            isBuiltIn: true,
          ),
      ]);
    });
    tearDown(() => CalendarCategories.updateCache(const []));

    testWidgets('the default lists every occurrence', (tester) async {
      await pumpView(tester, anchorDay: anchor, filters: window);

      expect(find.text('Leg day'), findsWidgets);
      // No card: condensing the events layer is opt-in.
      expect(find.text('Gym'), findsNothing);
    });

    testWidgets('summary mode condenses them to one card per category', (
      tester,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(eventDisplay: AgendaEventDisplay.summary),
      );

      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Leg day'), findsNothing);
      // One daily event across thirty days: one event, thirty occurrences.
      expect(find.textContaining('1 event'), findsOneWidget);
      expect(find.textContaining('30'), findsWidgets);
    });

    testWidgets('the card is not counted among the entries', (tester) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(eventDisplay: AgendaEventDisplay.summary),
      );

      // Thirty entry rows became one card, and a card is not an entry.
      expect(header(tester), contains('0 entries'));
    });

    testWidgets('the drill-down lists the occurrences and can edit them', (
      tester,
    ) async {
      CalendarEvent? edited;
      DateTime? editedDay;
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(eventDisplay: AgendaEventDisplay.summary),
        onEditEvent: (event, day) {
          edited = event;
          editedDay = day;
        },
      );

      await tester.tap(find.byTooltip('Show every day'));
      await tester.pumpAndSettle();
      expect(find.text('Leg day'), findsWidgets);

      // Collapsing must never put editing further away than a row tap.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      expect(edited?.id, 'e1');
      expect(editedDay, anchor);
      // The sheet closed first, so the editor never stacks on top of it.
      expect(find.text('Show every day'), findsNothing);
    });

    testWidgets('per-event mode still collapses repeats to one row', (
      tester,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(eventDisplay: AgendaEventDisplay.perEvent),
      );

      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Gym'), findsNothing);
    });
  });

  group('search', () {
    const window = UpcomingAgendaFilters(rangeDays: 30);
    final anchor = DateTime.utc(2026, 8, 10);

    // The category label only exists once the facade is filled — matching a
    // term against it is the whole point of this group.
    setUp(() {
      CalendarCategories.updateCache([
        for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
          CalendarCategory(
            id: seed.id,
            name: seed.kind.name,
            colorValue: seed.colorValue,
            iconKey: seed.iconKey,
            sortOrder: index,
            isBuiltIn: true,
          ),
      ]);
    });
    tearDown(() => CalendarCategories.updateCache(const []));

    testWidgets('a term matching only the category label keeps the event', (
      tester,
    ) async {
      // "Leg day" says nothing about a gym; its *category* does.
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(query: 'gym'),
      );

      // A non-empty query widens the window to the 366-day maximum: search
      // is a lookup over the calendar, not a filter over the visible month.
      expect(header(tester), contains('366 entries'));
      expect(find.text('Leg day'), findsWidgets);
    });

    testWidgets('a term matching nothing empties the list', (tester) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(query: 'pilates'),
      );

      expect(header(tester), contains('0 entries'));
      expect(find.text('Leg day'), findsNothing);
    });

    testWidgets('every term must match, across title and category', (
      tester,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(query: 'gym leg'),
      );
      expect(header(tester), contains('366 entries'));

      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(query: 'gym pilates'),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(header(tester), contains('0 entries'));
    });

    testWidgets('a date term narrows the list to that day', (tester) async {
      // Sixteen days into a window that itself starts sixty days out, so the
      // target is unique inside the searched year and can never be the day the
      // agenda relabels as Today/Tomorrow.
      final start = farDay(0);
      final target = start.add(const Duration(days: 16));
      final query = '${DateFormat.MMM('en').format(target)} ${target.day}';

      await pumpView(
        tester,
        anchorDay: start,
        filters: window.copyWith(query: query),
      );

      expect(header(tester), contains('1 entry'));
      expect(find.textContaining(dayHeader(target)), findsOneWidget);
      expect(
        find.textContaining(
          dayHeader(target.subtract(const Duration(days: 1))),
        ),
        findsNothing,
      );
    });

    testWidgets('a query change rescans once, after the debounce', (
      tester,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(query: 'gym'),
      );

      CalendarEvent.debugOccursOnCalls = 0;
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: window.copyWith(query: 'gym leg'),
      );
      await tester.pump();
      // The keystroke is debounced: nothing is expanded yet.
      expect(CalendarEvent.debugOccursOnCalls, 0);

      await tester.pump(const Duration(milliseconds: 250));
      // One window scan, not one per rebuild the keystroke caused.
      // 366, not 30: the query widened the window. Still ONE scan, which is
      // what this test exists to pin — the debounce, not the window size.
      expect(CalendarEvent.debugOccursOnCalls, 366);
    });
  });
}
