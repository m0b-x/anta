import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/upcoming_agenda_view.dart';

/// The search half of [UpcomingAgendaView], pinned as a user experiences it:
/// **anything the agenda puts on screen can be typed back into the search
/// field to find it**, and a search reaches the whole calendar rather than the
/// window that happened to be open.
///
/// Everything here is anchored on a fixed UTC day in 2026 and asserts on entry
/// counts, row titles and the panel's own range label — never on a day-group
/// header, because `AgendaListView.dayHeaderLabel` relabels the two days
/// around `DateTime.now()` and a fixture pinned to one of those is a time bomb.
void main() {
  final l10n = AppLocalizationsEn();

  /// Every window in this file starts here. Far enough from Great Lent 2027
  /// (15 March – 1 May) that the default 30-day look-ahead cannot reach it,
  /// and close enough that the 366-day search window can.
  final anchor = DateTime.utc(2026, 8, 10);

  /// Titles that share no word with anything searched for below, so a match is
  /// always the seam under test rather than the title falling into it.
  ///
  /// Between them they render one of each subtitle segment: a repeat pattern
  /// ("Weekly · Mon"), the all-day badge, and a priority word.
  final physio = CalendarEvent(
    id: 'e-physio',
    title: 'Physio',
    categoryId: 'mobility',
    startDate: DateTime.utc(2026, 8, 3),
    rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
    time: const EventTime(startMinute: 7 * 60, durationMinutes: 60),
  );
  final retreat = CalendarEvent(
    id: 'e-retreat',
    title: 'Retreat',
    categoryId: 'rest',
    startDate: DateTime.utc(2026, 8, 20),
  );
  final dentist = CalendarEvent(
    id: 'e-dentist',
    title: 'Dentist',
    categoryId: 'measurement',
    startDate: DateTime.utc(2026, 8, 25),
    time: const EventTime(startMinute: 9 * 60, durationMinutes: 60),
    priority: 1,
  );

  /// One stable instance: the view's `identical(events)` guard treats a fresh
  /// list as a real change and rescans, which would hide a debounce bug.
  final events = [physio, retreat, dentist];

  Future<void> pumpView(
    WidgetTester tester, {
    required UpcomingAgendaFilters filters,
    DateTime? anchorDay,
    ValueChanged<UpcomingAgendaFilters>? onFiltersChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: UpcomingAgendaView(
            events: events,
            anchorDay: anchorDay ?? anchor,
            hiddenCategoryIds: const {},
            filters: filters,
            onFiltersChanged: onFiltersChanged ?? (_) {},
            onDaySelected: (_) {},
            onEditEvent: (_, _) {},
            onOpenNote: (_) {},
            appearance: const CalendarAppearance(),
          ),
        ),
      ),
    );
  }

  /// Re-pumps with new filters and lets the query debounce elapse. A query-only
  /// change is deliberately debounced, so a bare `pump()` would read the
  /// previous scan.
  Future<void> repump(
    WidgetTester tester, {
    required UpcomingAgendaFilters filters,
  }) async {
    await pumpView(tester, filters: filters);
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// The panel header — `N entries · <range>` — the only Text carrying a
  /// middle dot above the list.
  String header(WidgetTester tester) {
    final texts = tester.widgetList<Text>(find.byType(Text));
    return texts.firstWhere((t) => (t.data ?? '').contains('·')).data!;
  }

  /// [label] as a *row* of the agenda.
  ///
  /// Scoped to the list on purpose. The search field renders the query, so a
  /// bare `find.text` reports a hit for every term typed into it — and so does
  /// a "did you mean" chip, which is above the list precisely because the list
  /// found nothing.
  Finder rowText(String label) => find.descendant(
    of: find.byType(AgendaListView),
    matching: find.text(label),
  );

  setUp(() {
    // The category label only resolves once `CategoryService`'s facade is
    // filled; without it every event would answer to "Other".
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
    FastingCalendar.configure(traditions: const {FastingTradition.orthodox});
  });

  tearDown(() {
    CalendarCategories.updateCache(const []);
    FastingCalendar.resetConfiguration();
  });

  group('fasting rows', () {
    const shown = UpcomingAgendaFilters(rangeDays: 30, showFasting: true);

    testWidgets('the tradition a card is named after finds that card', (
      tester,
    ) async {
      // A window holding several named fasts titles its card with the
      // tradition — "Orthodox" is on screen, so it has to be typeable.
      await pumpView(
        tester,
        filters: shown.copyWith(
          fastingDisplay: AgendaFastingDisplay.summary,
          query: l10n.fastingTraditionOrthodox,
        ),
      );

      expect(rowText(l10n.fastingTraditionOrthodox), findsOneWidget);

      // The same panel under a term nothing carries: proof the query really is
      // filtering, so the hit above is a match rather than an unfiltered card.
      await repump(
        tester,
        filters: shown.copyWith(
          fastingDisplay: AgendaFastingDisplay.summary,
          query: 'sourdough',
        ),
      );

      expect(rowText(l10n.fastingTraditionOrthodox), findsNothing);
    });

    testWidgets('a query reaches fasts the look-ahead window cannot', (
      tester,
    ) async {
      // Great Lent 2027 opens seven months after the anchor: no amount of
      // matching can surface it while the window is the 30 days the user
      // picked, which is why a query widens it to the searchable year.
      await pumpView(tester, filters: shown.copyWith(query: 'lent'));

      expect(rowText(l10n.fastingGreatLent), findsOneWidget);
      expect(header(tester), contains(l10n.daySummaryEntryCount(1)));

      // Same filters, no query: the window is 30 days again and the fast is
      // out of reach — the widening is the query's doing, not the layer's.
      await repump(tester, filters: shown);

      expect(rowText(l10n.fastingGreatLent), findsNothing);
    });

    testWidgets('a pinned range keeps the search inside it', (tester) async {
      // A picked range is an instruction about what to show. Searching inside
      // it narrows; it must never silently widen back out.
      await pumpView(
        tester,
        filters: UpcomingAgendaFilters(
          rangeDays: 30,
          showFasting: true,
          query: 'lent',
          customStart: DateTime.utc(2026, 8, 10),
          customEnd: DateTime.utc(2026, 9, 8),
        ),
      );

      expect(header(tester), contains('Aug 10 – Sep 8'));
      expect(header(tester), contains(l10n.daySummaryEntryCount(0)));
      expect(rowText(l10n.fastingGreatLent), findsNothing);
    });

    testWidgets('a fast answers to its name in another language', (
      tester,
    ) async {
      // The app is in English and the fast is called "Great Lent" here, but a
      // Romanian or German speaker types what they know it by.
      for (final query in ['postul mare', 'fastenzeit']) {
        await pumpView(tester, filters: shown.copyWith(query: query));
        await tester.pump(const Duration(milliseconds: 250));

        expect(rowText(l10n.fastingGreatLent), findsOneWidget, reason: query);
      }
    });
  });

  group('row subtitle text', () {
    // One row per matching event, so the entry count is the match count.
    const window = UpcomingAgendaFilters(
      rangeDays: 30,
      eventDisplay: AgendaEventDisplay.perEvent,
    );

    testWidgets('the repeat pattern finds the event that repeats', (
      tester,
    ) async {
      // "Weekly" is nowhere in "Physio" — only in the subtitle the row draws.
      await pumpView(
        tester,
        filters: window.copyWith(query: l10n.recurrenceEveryWeeks(1)),
      );

      expect(header(tester), contains(l10n.daySummaryEntryCount(1)));
      expect(rowText('Physio'), findsOneWidget);
      expect(rowText('Retreat'), findsNothing);
      expect(rowText('Dentist'), findsNothing);
    });

    testWidgets('the all-day badge finds the event that shows it', (
      tester,
    ) async {
      await pumpView(tester, filters: window.copyWith(query: l10n.eventAllDay));

      expect(header(tester), contains(l10n.daySummaryEntryCount(1)));
      expect(rowText('Retreat'), findsOneWidget);
      // Physio and Dentist both carry a time instead of the badge.
      expect(rowText('Physio'), findsNothing);
      expect(rowText('Dentist'), findsNothing);
    });

    testWidgets('the priority word finds the event that carries it', (
      tester,
    ) async {
      await pumpView(
        tester,
        filters: window.copyWith(query: l10n.eventPriorityHighest),
      );

      expect(header(tester), contains(l10n.daySummaryEntryCount(1)));
      expect(rowText('Dentist'), findsOneWidget);
      // The other two sit at the neutral middle, which renders no badge — so
      // folding the word there would have found rows showing no priority.
      expect(rowText('Physio'), findsNothing);
      expect(rowText('Retreat'), findsNothing);
    });
  });

  group('holiday rows', () {
    testWidgets('the "Public holiday" subtitle finds the holidays', (
      tester,
    ) async {
      // No holiday is *named* "Public holiday" — that is the subtitle every
      // holiday row draws under its name, so this can only match through it.
      await pumpView(
        tester,
        filters: UpcomingAgendaFilters(
          rangeDays: 30,
          showHolidays: true,
          query: l10n.dayBarPublicHoliday,
        ),
      );

      expect(rowText(l10n.publicHolidayAssumption), findsOneWidget);
      expect(rowText(l10n.publicHolidayAllSaints), findsOneWidget);
      // Events carry no such subtitle, so the search folded the agenda down to
      // its holiday half.
      expect(rowText('Physio'), findsNothing);
      expect(rowText('Retreat'), findsNothing);
    });
  });

  group('did you mean', () {
    const shown = UpcomingAgendaFilters(rangeDays: 30, showFasting: true);

    testWidgets('a misspelling offers the spelling that works', (tester) async {
      UpcomingAgendaFilters? captured;
      await pumpView(
        tester,
        filters: shown.copyWith(query: 'orthodx'),
        onFiltersChanged: (f) => captured = f,
      );

      expect(header(tester), contains(l10n.daySummaryEntryCount(0)));
      expect(find.text(l10n.upcomingDidYouMean), findsOneWidget);

      final chip = find.widgetWithText(
        ActionChip,
        l10n.fastingTraditionOrthodox,
      );
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pump();

      // Tapping a correction *is* searching for it: the suggestion is a
      // display name, so the query it becomes is one the search can find.
      expect(captured?.query, l10n.fastingTraditionOrthodox);
    });

    testWidgets('a search that worked offers no corrections', (tester) async {
      await pumpView(tester, filters: shown.copyWith(query: 'physio'));

      expect(rowText('Physio'), findsWidgets);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text(l10n.upcomingDidYouMean), findsNothing);
    });
  });

  /// Hiding a category archives it: its events keep rendering in their own
  /// colour, but the agenda stops offering the name as something to search by.
  /// The exception is the view's own allowlist — a hidden id the user has
  /// selected is a live selection, which is what `visiblePlus` exists for.
  group('archived categories', () {
    const shown = UpcomingAgendaFilters(rangeDays: 30);

    void seedWithHidden(Set<String> hidden) {
      CalendarCategories.updateCache([
        for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
          CalendarCategory(
            id: seed.id,
            name: seed.kind.name,
            colorValue: seed.colorValue,
            iconKey: seed.iconKey,
            sortOrder: index,
            isBuiltIn: true,
            isHidden: hidden.contains(seed.id),
          ),
      ]);
    }

    Finder correction(String label) => find.widgetWithText(ActionChip, label);

    testWidgets('a visible category is offered as a correction', (
      tester,
    ) async {
      await pumpView(tester, filters: shown.copyWith(query: 'mobilty'));

      expect(correction(l10n.eventCategoryMobility), findsOneWidget);
    });

    testWidgets('a hidden one is not', (tester) async {
      seedWithHidden({'mobility'});
      await pumpView(tester, filters: shown.copyWith(query: 'mobilty'));

      expect(correction(l10n.eventCategoryMobility), findsNothing);
    });

    testWidgets('unless it sits in this view own allowlist', (tester) async {
      seedWithHidden({'mobility'});
      await pumpView(
        tester,
        filters: shown.copyWith(
          query: 'mobilty',
          categoryIds: const {'mobility'},
        ),
      );

      expect(correction(l10n.eventCategoryMobility), findsOneWidget);
    });
  });
}
