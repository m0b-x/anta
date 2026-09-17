import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/ics_serializer.dart';

/// `VALARM` is the one part of the export that reads a facade the serializer
/// is never handed: alerts come from [EventAlerts], exactly as skips come from
/// `EventSkips`, so the export path can stay "here is a list of events".
///
/// Both shapes are **relative** triggers, which is what follows every
/// occurrence of the `RRULE`: minutes before the start for a timed event, and
/// a signed duration from 00:00 of the day for an all-day one.
void main() {
  CalendarEvent event({EventTime? time, String id = 'e1'}) => CalendarEvent(
    id: id,
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 8, 3),
    rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
    time: time,
  );

  void publish(List<EventAlert> alerts, {String id = 'e1'}) {
    EventAlerts.updateCache(byEvent: {id: List.unmodifiable(alerts)});
  }

  EventAlert alert({
    String id = 'a1',
    String eventId = 'e1',
    AlertMode mode = AlertMode.notify,
    int offsetMinutes = 10,
    int daysBefore = 0,
    int? dayMinute,
    bool enabled = true,
  }) => EventAlert(
    id: id,
    eventId: eventId,
    mode: mode,
    offsetMinutes: offsetMinutes,
    daysBefore: daysBefore,
    dayMinute: dayMinute,
    enabled: enabled,
  );

  String export(CalendarEvent e) =>
      IcsSerializer.serialize(events: [e], now: DateTime.utc(2026, 8, 1));

  setUp(EventAlerts.resetCache);
  tearDown(EventAlerts.resetCache);

  test('no alerts means no VALARM at all', () {
    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    expect(ics, isNot(contains('VALARM')));
  });

  test('a reminder is a DISPLAY alarm with a relative trigger', () {
    publish([alert(offsetMinutes: 10)]);

    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    expect(ics, contains('BEGIN:VALARM'));
    expect(ics, contains('ACTION:DISPLAY'));
    // DISPLAY requires a DESCRIPTION; the title is what a phone shows.
    expect(ics, contains('DESCRIPTION:Leg day'));
    expect(ics, contains('TRIGGER:-PT10M'));
    expect(ics, contains('END:VALARM'));
  });

  test('an alarm is an AUDIO alarm', () {
    publish([alert(mode: AlertMode.ring, offsetMinutes: 0)]);

    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    expect(ics, contains('ACTION:AUDIO'));
    // Nothing in the format can say "ring until stopped", and at start is
    // still a trigger of zero rather than no trigger at all.
    expect(ics, contains('TRIGGER:-PT0M'));
  });

  test('every enabled alert gets its own VALARM', () {
    publish([
      alert(id: 'a1', offsetMinutes: 10),
      alert(id: 'a2', mode: AlertMode.ring, offsetMinutes: 30),
    ]);

    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    expect('BEGIN:VALARM'.allMatches(ics), hasLength(2));
    expect(ics, contains('TRIGGER:-PT10M'));
    expect(ics, contains('TRIGGER:-PT30M'));
  });

  test('a disabled alert exports nothing', () {
    publish([alert(enabled: false), alert(id: 'a2', offsetMinutes: 30)]);

    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    expect('BEGIN:VALARM'.allMatches(ics), hasLength(1));
    expect(ics, isNot(contains('TRIGGER:-PT10M')));
    expect(ics, contains('TRIGGER:-PT30M'));
  });

  group('all-day events', () {
    // An all-day `DTSTART` is a `DATE`, and RFC 5545 measures a relative
    // trigger on one from 00:00 of that day. Relative is the whole point: it
    // follows every occurrence of the `RRULE` and stays in floating local
    // time, where an absolute trigger has to be UTC and names one instant.
    test('trigger relative to the start of the day', () {
      publish([alert(daysBefore: 0, dayMinute: 9 * 60)]);

      final ics = export(event());

      expect(ics, contains('TRIGGER:PT9H'));
      expect(ics, isNot(contains('VALUE=DATE-TIME')));
    });

    test('daysBefore makes the trigger negative', () {
      publish([alert(daysBefore: 1, dayMinute: 20 * 60)]);

      expect(export(event()), contains('TRIGGER:-PT4H'));
    });

    test('a week before spells days, hours and minutes', () {
      publish([alert(daysBefore: 7, dayMinute: 8 * 60 + 30)]);

      // 7 days back, then 08:30 forward: 6 days 15 h 30 min before midnight.
      expect(export(event()), contains('TRIGGER:-P6DT15H30M'));
    });

    test('midnight on the day is a zero duration, not an empty one', () {
      publish([alert(daysBefore: 0, dayMinute: 0)]);

      expect(export(event()), contains('TRIGGER:PT0M'));
    });

    test('a whole number of days back has no time part', () {
      publish([alert(daysBefore: 2, dayMinute: 0)]);

      expect(export(event()), contains('TRIGGER:-P2D'));
    });

    test('a null day minute follows the settings default', () {
      // The number the planner is handed, so an alert with no time of its own
      // exports the instant it actually rings at.
      EventAlerts.configureDefaultDayMinute(8 * 60);
      addTearDown(() => EventAlerts.configureDefaultDayMinute(null));
      publish([alert(dayMinute: null)]);

      expect(export(event()), contains('TRIGGER:PT8H'));
    });

    test('with no setting published it is the shipped 09:00', () {
      publish([alert(dayMinute: null)]);
      final withDefault = export(event());

      publish([alert(dayMinute: kDefaultAlertDayMinute)]);
      final explicit = export(event());

      expect(withDefault, explicit);
    });
  });

  test('the alarm block sits inside the VEVENT it belongs to', () {
    publish([alert(offsetMinutes: 5)]);

    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    final beginAlarm = ics.indexOf('BEGIN:VALARM');
    final endAlarm = ics.indexOf('END:VALARM');
    final endEvent = ics.indexOf('END:VEVENT');
    expect(beginAlarm, greaterThan(ics.indexOf('BEGIN:VEVENT')));
    expect(endAlarm, lessThan(endEvent));
  });

  test('another event\'s alerts are not borrowed', () {
    publish([alert(offsetMinutes: 10)], id: 'other');

    final ics = export(event(time: const EventTime(startMinute: 18 * 60)));

    expect(ics, isNot(contains('VALARM')));
  });
}
