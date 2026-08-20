import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/day_bars_resolver.dart';
import 'package:anta/utils/event_agenda.dart';

/// Guards the two properties the day-bar stripes share with the day panel.
///
/// Ordering: both surfaces must rank same-day events through the single
/// comparator `EventAgenda.compareWithinDay`. The resolver's own tie-break is
/// the bar *key* (`event:<uuid>`), so an unsorted provider plus an unstable
/// sort used to scramble equal-priority stripes into id order while the panel
/// listed them by time — the same day, two different answers.
///
/// Presence: a hidden missed bar must be dropped *before* it is added, or it
/// silently consumes one of the cell's `maxDayBars` slots.
void main() {
  final day = DateTime.utc(2026, 8, 10);

  CalendarEvent event(
    String id, {
    String title = 'Event',
    int priority = kDefaultEventPriority,
    EventTime? time,
    bool tracksPresence = false,
    int? colorValue,
  }) {
    return CalendarEvent(
      id: id,
      title: title,
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: const DailyRecurrence(),
      priority: priority,
      time: time,
      tracksPresence: tracksPresence,
      colorValue: colorValue,
    );
  }

  List<String> barIds(List<DayBar> bars) => [
    for (final bar in bars) bar.key.replaceFirst('event:', ''),
  ];

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  group('EventDayBarProvider ordering', () {
    test('equal priorities put the all-day event before the timed one', () {
      // Reversed on input so a provider that just echoes its argument fails.
      final events = [
        event('timed', time: const EventTime(startMinute: 9 * 60)),
        event('allDay'),
      ];

      final bars = const EventDayBarProvider()
          .barsFor(day, events)
          .toList(growable: false);

      expect(barIds(bars), ['allDay', 'timed']);
    });

    test('equal priorities order timed events by start minute', () {
      final events = [
        event('evening', time: const EventTime(startMinute: 18 * 60)),
        event('morning', time: const EventTime(startMinute: 7 * 60)),
      ];

      final bars = const EventDayBarProvider()
          .barsFor(day, events)
          .toList(growable: false);

      expect(barIds(bars), ['morning', 'evening']);
    });

    test('priority still outranks time', () {
      final events = [
        event('lowLate', priority: 5, time: const EventTime(startMinute: 60)),
        event('highLate', priority: 1, time: const EventTime(startMinute: 600)),
      ];

      final bars = const EventDayBarProvider()
          .barsFor(day, events)
          .toList(growable: false);

      expect(barIds(bars), ['highLate', 'lowLate']);
    });

    test('does not mutate the caller list', () {
      final events = [
        event('timed', time: const EventTime(startMinute: 9 * 60)),
        event('allDay'),
      ];

      const EventDayBarProvider().barsFor(day, events).toList(growable: false);

      expect([for (final e in events) e.id], ['timed', 'allDay']);
    });
  });

  group('DayBarsResolver.resolve stability', () {
    test('preserves provider order for equal-priority bars', () {
      // Ids chosen so lexical order is the exact reverse of the intended
      // order: a key tie-break would sort 'aaa' first.
      final events = [
        event('zzz', time: const EventTime(startMinute: 7 * 60)),
        event('aaa', time: const EventTime(startMinute: 18 * 60)),
      ];

      final resolver = const DayBarsResolver(
        providers: [EventDayBarProvider()],
      );

      expect(barIds(resolver.resolve(day, events)), ['zzz', 'aaa']);
    });

    test('agrees with the shared same-day comparator', () {
      final events = [
        event('c', priority: 2, time: const EventTime(startMinute: 600)),
        event('a', priority: 4),
        event('b', priority: 2, time: const EventTime(startMinute: 480)),
      ];
      final expected = [...events]..sort(EventAgenda.compareWithinDay);

      final resolver = const DayBarsResolver(
        providers: [EventDayBarProvider()],
      );

      expect(barIds(resolver.resolve(day, events)), [
        for (final e in expected) e.id,
      ]);
    });
  });

  group('presence', () {
    setUp(() {
      EventPresence.updateCache(
        byEvent: {
          'missed': {day},
        },
      );
    });

    test('a hidden missed bar is dropped, not just faded', () {
      final events = [event('missed', tracksPresence: true), event('kept')];

      final bars = const EventDayBarProvider(
        missedDisplay: CalendarMissedDisplay.hidden,
      ).barsFor(day, events).toList(growable: false);

      expect(barIds(bars), ['kept']);
    });

    test('a faded missed bar keeps its slot at the missed alpha', () {
      final events = [event('missed', tracksPresence: true, colorValue: null)];

      final bars = const EventDayBarProvider()
          .barsFor(day, events)
          .toList(growable: false);

      expect(bars, hasLength(1));
      expect(
        bars.single.color.a,
        closeTo(CalendarColors.missedEventAlpha, 0.01),
      );
    });

    test('an untracked event on a marked day is never faded', () {
      final bars = const EventDayBarProvider()
          .barsFor(day, [event('missed')])
          .toList(growable: false);

      expect(bars.single.color.a, closeTo(1.0, 0.01));
    });
  });

  group('colour', () {
    test('an explicit override wins over the category colour', () {
      const override = 0xFF123456;

      final bars = const EventDayBarProvider()
          .barsFor(day, [event('e', colorValue: override)])
          .toList(growable: false);

      expect(bars.single.color, const Color(override));
    });
  });
}
