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
}
