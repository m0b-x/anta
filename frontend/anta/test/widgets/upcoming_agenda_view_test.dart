import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_day_list_sheet.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
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
  final sharedEvents = [daily];

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
    List<CalendarEvent>? events,
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: UpcomingAgendaView(
            events: events ?? sharedEvents,
            anchorDay: anchorDay,
            onResetAnchor: onResetAnchor,
            hiddenCategoryIds: const {},
            filters: filters,
            onFiltersChanged: onFiltersChanged ?? (_) {},
            onDaySelected: onDaySelected ?? (_) {},
            onEditEvent: onEditEvent ?? (_, _) {},
            onOpenNote: (_) {},
            appearance: const CalendarAppearance(),
            missedDisplay: missedDisplay,
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

  /// Scrolls the drill-down sheet's month body so the rows under the mini
  /// calendar are laid out.
  ///
  /// Scoped to the sheet on purpose: the agenda underneath is a
  /// `CustomScrollView` too, and it is the one an unscoped finder reaches
  /// first.
  Future<void> scrollSheetBody(WidgetTester tester) async {
    final state = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(AgendaDayListSheet),
              matching: find.byType(CustomScrollView),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  /// Switches the drill-down's year overview to the calendar year. Addressed
  /// through the typed selector, so it can never hit the mode selector above
  /// it, and by position rather than label.
  Future<void> tapThisYear(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is SegmentedButton<AgendaDayListYearScope>,
            ),
            matching: find.byType(Text),
          )
          .at(1),
    );
    await tester.pumpAndSettle();
  }

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

  /// The two calendar-year windows. Unlike the rolling presets these are
  /// anchored to 1 January / 31 December rather than counted forward, which is
  /// what lets the agenda answer "every birthday this year" — including the
  /// ones already past.
  group('calendar-year windows', () {
    const wholeYear = UpcomingAgendaFilters(
      periodMode: AgendaPeriodMode.wholeYear,
    );
    const restOfYear = UpcomingAgendaFilters(
      periodMode: AgendaPeriodMode.restOfYear,
    );
    // A non-leap year, so the day counts below are 365 rather than 366.
    final midYear = DateTime.utc(2026, 8, 29);

    testWidgets('the whole year reaches back to January', (tester) async {
      await pumpView(tester, anchorDay: midYear, filters: wholeYear);

      expect(
        header(tester),
        contains(
          AgendaListView.rangeLabel(
            'en',
            DateTime.utc(2026, 1, 1),
            DateTime.utc(2026, 12, 31),
          ),
        ),
      );
    });

    testWidgets('the rest of the year starts at the anchor', (tester) async {
      await pumpView(tester, anchorDay: midYear, filters: restOfYear);

      expect(
        header(tester),
        contains(
          AgendaListView.rangeLabel('en', midYear, DateTime.utc(2026, 12, 31)),
        ),
      );
    });

    testWidgets('walking the grid inside the year costs no rescan', (
      tester,
    ) async {
      await pumpView(tester, anchorDay: midYear, filters: wholeYear);
      final before = header(tester);

      CalendarEvent.debugOccursOnCalls = 0;
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2026, 11, 3),
        filters: wholeYear,
      );

      // The window is the year, not the anchor: nothing moved, so nothing may
      // be re-expanded — a 365-day rescan per grid tap is exactly the cost
      // this mode must not introduce.
      expect(CalendarEvent.debugOccursOnCalls, 0);
      expect(header(tester), before);
    });

    testWidgets('crossing into another year rescans once', (tester) async {
      await pumpView(tester, anchorDay: midYear, filters: wholeYear);

      CalendarEvent.debugOccursOnCalls = 0;
      await pumpView(
        tester,
        anchorDay: DateTime.utc(2027, 2, 4),
        filters: wholeYear,
      );

      // One daily event across 2027: one occursOn per day of the new window,
      // and no more.
      expect(CalendarEvent.debugOccursOnCalls, 365);
      expect(
        header(tester),
        contains(
          AgendaListView.rangeLabel(
            'en',
            DateTime.utc(2027, 1, 1),
            DateTime.utc(2027, 12, 31),
          ),
        ),
      );
    });

    testWidgets('a query narrows a year window instead of widening it', (
      tester,
    ) async {
      await pumpView(tester, anchorDay: midYear, filters: wholeYear);
      final before = header(tester);

      await pumpView(
        tester,
        anchorDay: midYear,
        filters: wholeYear.copyWith(query: 'leg'),
      );
      await tester.pump(const Duration(milliseconds: 250));

      // The rolling window widens to a full year on a query so a search can
      // reach February from August. A year window already *is* that reach, and
      // widening it would push it forward off the year the user asked for —
      // so the window, and with it every matching row, stands still.
      expect(header(tester), before);
    });

    testWidgets('the chip undoes the year without forgetting the preset', (
      tester,
    ) async {
      UpcomingAgendaFilters? captured;
      await pumpView(
        tester,
        anchorDay: midYear,
        filters: wholeYear.copyWith(rangeDays: 90),
        onFiltersChanged: (f) => captured = f,
      );

      // Addressed by the summary chip's own delete tooltip, not by "the only
      // InputChip on screen": `midYear` is a fixed past date, so the header's
      // *anchor* chip (tooltip `upcomingResetAnchor`) is showing too from the
      // day after this test was written onwards.
      expect(removeFilter, findsOneWidget);
      expect(find.text('This year'), findsOneWidget);

      await tester.tap(removeFilter);
      await tester.pump();

      expect(captured?.periodMode, AgendaPeriodMode.rollingDays);
      // The rolling window the user had chosen before, not the default.
      expect(captured?.rangeDays, 90);
    });
  });

  group('drill-down resolver', () {
    // The sheet dates itself off the real clock (`today` is resolved when the
    // sheet opens), so its This-year tiles are always the current calendar
    // year. Every fixture here is anchored to that year rather than to a
    // literal one, and the window is pinned to December so January is safely
    // outside it.
    final thisYear = EventAgenda.dateOnly(DateTime.now()).year;
    final january = DateTime.utc(thisYear, 1, 1);
    final anchor = DateTime.utc(thisYear, 12, 1);
    String januaryTile() => DateFormat.yMMM('en').format(january);
    const summary = UpcomingAgendaFilters(
      rangeDays: 30,
      eventDisplay: AgendaEventDisplay.summary,
    );

    final dailyThisYear = CalendarEvent(
      id: 'r1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: january,
      rule: const DailyRecurrence(),
    );

    /// In the card's category but far outside its window, and ranked away from
    /// the neutral default so a priority filter can exclude it.
    final winter = CalendarEvent(
      id: 'r2',
      title: 'Winter session',
      categoryId: 'gym',
      startDate: DateTime.utc(thisYear, 1, 14),
      rule: const OneTimeRecurrence(),
      priority: 1,
    );

    /// Same past month, a different category — the drill-down is scoped to the
    /// card that opened it, so this must never reach it.
    final dentist = CalendarEvent(
      id: 'r3',
      title: 'Dentist',
      categoryId: 'other',
      startDate: DateTime.utc(thisYear, 1, 20),
      rule: const OneTimeRecurrence(),
    );

    final pastEvents = [dailyThisYear, winter, dentist];

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

    /// Opens the one summary card's drill-down and switches its year overview
    /// to the calendar year, where every month of the year is a tile.
    Future<void> openThisYear(
      WidgetTester tester,
      UpcomingAgendaFilters filters,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: filters,
        events: pastEvents,
      );
      // A query debounces the rescan; let it land before the card is read.
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.byTooltip('Show every day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();
      await tapThisYear(tester);
    }

    testWidgets('This year reaches a past month with the card\'s own rows', (
      tester,
    ) async {
      await openThisYear(tester, summary);

      final handle = tester.ensureSemantics();
      // 31 daily occurrences plus the one-time January session. The dentist is
      // in the same month and is not this card's category, so it is not here.
      expect(
        find.bySemanticsLabel('${januaryTile()}, 32 entries'),
        findsOneWidget,
      );
      handle.dispose();

      await tester.tap(find.text(januaryTile()));
      await tester.pumpAndSettle();
      // Narrow to the one day that carries both, so the assertion does not
      // depend on where a lazy list stopped building.
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await scrollSheetBody(tester);

      expect(find.text('Winter session'), findsOneWidget);
      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Dentist'), findsNothing);
    });

    testWidgets('the priority filter excludes a past occurrence too', (
      tester,
    ) async {
      await openThisYear(
        tester,
        summary.copyWith(priorities: const {kDefaultEventPriority}),
      );

      final handle = tester.ensureSemantics();
      // The daily event alone: the P1 session no longer passes the filter the
      // card was built under, so the month it was in must not count it.
      expect(
        find.bySemanticsLabel('${januaryTile()}, 31 entries'),
        findsOneWidget,
      );
      handle.dispose();

      await tester.tap(find.text(januaryTile()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await scrollSheetBody(tester);

      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Winter session'), findsNothing);
    });

    testWidgets('the text query excludes a past occurrence too', (
      tester,
    ) async {
      await openThisYear(tester, summary.copyWith(query: 'leg'));

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('${januaryTile()}, 31 entries'),
        findsOneWidget,
      );
      handle.dispose();

      await tester.tap(find.text(januaryTile()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await scrollSheetBody(tester);

      expect(find.text('Leg day'), findsOneWidget);
      expect(find.text('Winter session'), findsNothing);
    });
  });

  group('holiday drill-down resolver', () {
    final thisYear = EventAgenda.dateOnly(DateTime.now()).year;
    final anchor = DateTime.utc(thisYear, 8, 10);
    String januaryTile() =>
        DateFormat.yMMM('en').format(DateTime.utc(thisYear, 1));

    testWidgets('This year reaches a holiday the window never covered', (
      tester,
    ) async {
      // New Year's Day resolves through the uninitialized fixed-date fallback,
      // and an August window can never contain it.
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: const UpcomingAgendaFilters(
          rangeDays: 90,
          showHolidays: true,
          holidayDisplay: AgendaHolidayDisplay.summary,
        ),
      );

      await tester.tap(find.byTooltip('Show every day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();
      await tapThisYear(tester);

      final handle = tester.ensureSemantics();
      // New Year's Day and Epiphany.
      expect(
        find.bySemanticsLabel('${januaryTile()}, 2 entries'),
        findsOneWidget,
      );
      handle.dispose();

      await tester.tap(find.text(januaryTile()));
      await tester.pumpAndSettle();
      await scrollSheetBody(tester);

      expect(find.text("New Year's Day"), findsOneWidget);
    });
  });

  group('fasting drill-down resolver', () {
    setUp(
      () => FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
      ),
    );
    tearDown(FastingCalendar.resetConfiguration);

    final thisYear = EventAgenda.dateOnly(DateTime.now()).year;
    final anchor = DateTime.utc(thisYear, 8, 10);
    String januaryTile() =>
        DateFormat.yMMM('en').format(DateTime.utc(thisYear, 1));

    testWidgets('This year reaches fasting days outside the window', (
      tester,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: const UpcomingAgendaFilters(
          rangeDays: 30,
          showFasting: true,
          fastingDisplay: AgendaFastingDisplay.summary,
        ),
      );

      await tester.tap(find.byTooltip('Show every day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();
      await tapThisYear(tester);

      // The year-round Wednesday/Friday rule alone marks eight or nine days a
      // month, and January carries no span fast in most years — the exact
      // number is the calendar's business, but a January tile counted from the
      // window would read zero.
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('^${januaryTile()}, \\d+ entries\$')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('drill-down presence', () {
    // Same anchoring rule as the resolver group above: the sheet dates itself
    // off the real clock, so This year is always the current calendar year.
    final thisYear = EventAgenda.dateOnly(DateTime.now()).year;
    final january = DateTime.utc(thisYear, 1, 1);
    final anchor = DateTime.utc(thisYear, 12, 1);
    final missedDay = DateTime.utc(thisYear, 1, 14);
    String januaryTile() => DateFormat.yMMM('en').format(january);
    const summary = UpcomingAgendaFilters(
      rangeDays: 30,
      eventDisplay: AgendaEventDisplay.summary,
    );

    /// Tracked and recurring, so one of its January occurrences can be marked
    /// missed — the daily gym event the drill-down used to report as attended
    /// every day of the month.
    final tracked = CalendarEvent(
      id: 'p1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: january,
      rule: const DailyRecurrence(),
      tracksPresence: true,
    );

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
      EventPresence.updateCache(
        byEvent: {
          'p1': {missedDay},
        },
      );
    });
    tearDown(() {
      CalendarCategories.updateCache(const []);
      EventPresence.resetCache();
    });

    Future<void> openJanuary(
      WidgetTester tester,
      CalendarMissedDisplay display,
    ) async {
      await pumpView(
        tester,
        anchorDay: anchor,
        filters: summary,
        events: [tracked],
        missedDisplay: display,
      );
      await tester.tap(find.byTooltip('Show every day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();
      await tapThisYear(tester);
    }

    CalendarDayCell cellFor(WidgetTester tester, String day) =>
        tester.widget<CalendarDayCell>(
          find.ancestor(
            of: find.text(day),
            matching: find.byType(CalendarDayCell),
          ),
        );

    testWidgets(
      'faded keeps a missed occurrence out of the count and dims it',
      (tester) async {
        await openJanuary(tester, CalendarMissedDisplay.faded);

        // 31 January occurrences, one of them missed.
        final handle = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel('${januaryTile()}, 30 entries · 1 missed'),
          findsOneWidget,
        );
        handle.dispose();

        await tester.tap(find.text(januaryTile()));
        await tester.pumpAndSettle();
        expect(cellFor(tester, '14').isOutside, isFalse);

        await tester.tap(find.text('14'));
        await tester.pumpAndSettle();
        await scrollSheetBody(tester);

        final faded = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.text('Leg day'),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(faded.opacity, CalendarColors.missedEventAlpha);
      },
    );

    testWidgets('hidden drops it from the rows, the count and the grid', (
      tester,
    ) async {
      await openJanuary(tester, CalendarMissedDisplay.hidden);

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('${januaryTile()}, 30 entries'),
        findsOneWidget,
      );
      handle.dispose();

      await tester.tap(find.text(januaryTile()));
      await tester.pumpAndSettle();
      // Nothing is left on the 14th, so the grid treats it as an empty day.
      expect(cellFor(tester, '14').isOutside, isTrue);
      expect(cellFor(tester, '15').isOutside, isFalse);
    });
  });
}
