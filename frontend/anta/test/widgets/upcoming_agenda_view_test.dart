import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/widgets/upcoming_agenda_view.dart';

/// The first widget tests for [UpcomingAgendaView]. They pin the three
/// behaviours the anchored-window change introduces, driven against fakes
/// with no database — the agenda scan is pure and the row facades
/// (presence/description) resolve through their uninitialized fallbacks.
///
/// The panel header (`N entries · <range>`) is the one deterministic readout:
/// the day-group headers depend on the wall clock (Today/Tomorrow), but the
/// range label is derived purely from the anchor and `rangeDays`. It is also
/// the only Text carrying a middle dot, so it is unambiguous to locate.
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

  Future<void> pumpView(
    WidgetTester tester, {
    required DateTime anchorDay,
    required UpcomingAgendaFilters filters,
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
            anchorDay: anchorDay,
            hiddenCategoryIds: const {},
            filters: filters,
            onFiltersChanged: onFiltersChanged ?? (_) {},
            onDaySelected: (_) {},
            onEditEvent: (_, _) {},
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

  testWidgets('anchor change with no custom range moves the window', (
    tester,
  ) async {
    const filters = UpcomingAgendaFilters(rangeDays: 30);

    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: filters,
    );
    expect(header(tester), contains('Aug 10'));
    // The first day-group header is scan output (a row), not the pure range
    // label — asserting it proves the scan actually re-ran, not just that the
    // header getter recomputed. Full month name, so it cannot collide with the
    // abbreviated "Aug 10" in the panel header.
    expect(find.textContaining('August 10'), findsOneWidget);

    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 9, 10),
      filters: filters,
    );
    await tester.pump();
    expect(header(tester), contains('Sep 10'));
    expect(header(tester), isNot(contains('Aug 10')));
    expect(find.textContaining('September 10'), findsOneWidget);
    expect(find.textContaining('August 10'), findsNothing);
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

  testWidgets('deleting the Custom chip clears the range', (tester) async {
    UpcomingAgendaFilters? captured;
    final filters = UpcomingAgendaFilters(
      rangeDays: 30,
      filtersExpanded: true,
      customStart: DateTime.utc(2026, 5, 1),
      customEnd: DateTime.utc(2026, 5, 15),
    );

    await pumpView(
      tester,
      anchorDay: DateTime.utc(2026, 8, 10),
      filters: filters,
      onFiltersChanged: (f) => captured = f,
    );

    await tester.tap(find.byTooltip('Clear custom range'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.hasCustomRange, isFalse);
    expect(captured!.customStart, isNull);
    expect(captured!.customEnd, isNull);
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
    // The bloc normalizes selectedDay, so tapping the already-selected day
    // hands back an equal anchor — the guard must recognise it and skip the
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
}
