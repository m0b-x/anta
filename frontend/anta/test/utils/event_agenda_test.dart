import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/utils/event_agenda.dart';

/// Pure coverage for the agenda scan's event-type axis and the fasting-day
/// scan — no widget tree, no database. `SpecificDatesRecurrence` counts as
/// recurring everywhere in the codebase, so the filter must agree.
void main() {
  final windowStart = DateTime.utc(2026, 8, 10);
  final windowEnd = DateTime.utc(2026, 8, 12);

  final oneTime = CalendarEvent(
    id: 'ot',
    title: 'Dentist',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 8, 11),
    rule: const OneTimeRecurrence(),
  );
  final daily = CalendarEvent(
    id: 'd',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 1),
    rule: const DailyRecurrence(),
  );
  final specific = CalendarEvent(
    id: 'sp',
    title: 'Pinned',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 8, 10),
    rule: SpecificDatesRecurrence(dates: {DateTime.utc(2026, 8, 10)}),
  );

  final events = [oneTime, daily, specific];

  Set<String> idsFor(AgendaEventType eventType) {
    return EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      eventType: eventType,
    ).map((o) => o.event.id).toSet();
  }

  Set<String> idsForCategories(
    Set<String> categoryIds, {
    Set<String> hiddenCategoryIds = const {},
  }) {
    return EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      categoryIds: categoryIds,
      hiddenCategoryIds: hiddenCategoryIds,
    ).map((o) => o.event.id).toSet();
  }

  test('all admits every event kind', () {
    expect(idsFor(AgendaEventType.all), {'ot', 'd', 'sp'});
  });

  test('recurring drops one-time but keeps specific-dates', () {
    expect(idsFor(AgendaEventType.recurring), {'d', 'sp'});
  });

  test('oneTime keeps only single-occurrence events', () {
    expect(idsFor(AgendaEventType.oneTime), {'ot'});
  });

  test('none short-circuits to no event occurrences', () {
    expect(
      EventAgenda.occurrencesInRange(
        events: events,
        from: windowStart,
        to: windowEnd,
        eventType: AgendaEventType.none,
      ),
      isEmpty,
    );
  });

  test('fastingDaysInRange is empty when no tradition is configured', () {
    // FastingCalendar is unconfigured in a bare test, so the scan pays nothing.
    expect(
      EventAgenda.fastingDaysInRange(from: windowStart, to: windowEnd),
      isEmpty,
    );
  });

  test('category allowlist keeps only the selected categories', () {
    expect(idsForCategories({'gym'}), {'d'});
    expect(idsForCategories({'other'}), {'ot', 'sp'});
  });

  test('an empty category allowlist shows every category', () {
    expect(idsForCategories(const {}), {'ot', 'd', 'sp'});
  });

  test('the category allowlist composes with the hidden set', () {
    // Both apply: 'other' stays hidden even though it is in the allowlist.
    expect(idsForCategories({'gym', 'other'}, hiddenCategoryIds: {'other'}), {
      'd',
    });
  });

  test('collapseRecurring shows each recurring event once', () {
    final occ = EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
      collapseRecurring: true,
    );
    final counts = <String, int>{};
    for (final o in occ) {
      counts[o.event.id] = (counts[o.event.id] ?? 0) + 1;
    }
    // Daily collapses from 3 rows to 1; one-time and specific stay at 1.
    expect(counts, {'ot': 1, 'd': 1, 'sp': 1});
    // The kept row is the recurring event's first in-window occurrence.
    expect(occ.firstWhere((o) => o.event.id == 'd').day, windowStart);
  });

  test('without collapseRecurring a daily event shows on every day', () {
    final occ = EventAgenda.occurrencesInRange(
      events: events,
      from: windowStart,
      to: windowEnd,
    );
    expect(occ.where((o) => o.event.id == 'd').length, 3);
  });
}
