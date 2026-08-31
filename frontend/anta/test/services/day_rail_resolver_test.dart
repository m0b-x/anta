import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_rail_mark.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/day_rail_resolver.dart';
import 'package:anta/utils/event_agenda.dart';

/// Guards the rail's membership rule and the two properties it shares with the
/// bar strip.
///
/// Membership is the whole point of the tri-state column: `null` must mean
/// exactly what presence tracking already meant (so no pre-v34 row changed
/// behaviour), and the recurrence guard must survive an explicit `true` — a
/// one-time event has no attendance streak to scan across a month.
///
/// Ordering and presence mirror `day_bars_resolver_test.dart`: equal-priority
/// marks keep the arrival order `EventAgenda.compareWithinDay` gave them, and a
/// hidden missed mark is dropped *before* it is added, or it silently consumes
/// one of the cell's `maxDayRailMarks` slots.
void main() {
  final day = DateTime.utc(2026, 8, 10);
  final l10n = AppLocalizationsEn();

  CalendarEvent event(
    String id, {
    String title = 'Event',
    int priority = kDefaultEventPriority,
    EventTime? time,
    bool tracksPresence = false,
    bool? showInDayRail,
    RecurrenceRule rule = const DailyRecurrence(),
    int? colorValue,
  }) {
    return CalendarEvent(
      id: id,
      title: title,
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: rule,
      priority: priority,
      time: time,
      tracksPresence: tracksPresence,
      showInDayRail: showInDayRail,
      colorValue: colorValue,
    );
  }

  List<String> markIds(Iterable<DayRailMark> marks) => [
    for (final mark in marks) mark.key.replaceFirst('event:', ''),
  ];

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  group('eventInDayRail — auto (NULL)', () {
    test('a presence-tracked recurring event is in', () {
      expect(eventInDayRail(event('e', tracksPresence: true)), isTrue);
    });

    test('a presence-tracked one-time event is out', () {
      expect(
        eventInDayRail(
          event('e', tracksPresence: true, rule: const OneTimeRecurrence()),
        ),
        isFalse,
      );
    });

    test('an untracked recurring event is out', () {
      expect(eventInDayRail(event('e')), isFalse);
    });

    test('matches EventPresence.appliesTo exactly', () {
      // The equivalence the "no backfill" decision rests on: with the column
      // NULL, membership is literally the presence gate.
      for (final e in [
        event('tracked', tracksPresence: true),
        event('untracked'),
        event(
          'trackedOnce',
          tracksPresence: true,
          rule: const OneTimeRecurrence(),
        ),
        event(
          'trackedDates',
          tracksPresence: true,
          rule: SpecificDatesRecurrence(dates: {DateTime.utc(2026, 8, 10)}),
        ),
      ]) {
        expect(
          eventInDayRail(e),
          EventPresence.appliesTo(e),
          reason: 'membership drifted from the presence gate for ${e.id}',
        );
      }
    });
  });

  group('eventInDayRail — explicit override', () {
    test('true forces an untracked recurring event in', () {
      expect(eventInDayRail(event('e', showInDayRail: true)), isTrue);
    });

    test('false forces a tracked recurring event out', () {
      expect(
        eventInDayRail(event('e', tracksPresence: true, showInDayRail: false)),
        isFalse,
      );
    });

    test('true on a one-time event still stays out', () {
      // The recurrence guard lives in the predicate, not on the column, so no
      // stored value can put a single-day event on the rail.
      expect(
        eventInDayRail(
          event(
            'e',
            tracksPresence: true,
            showInDayRail: true,
            rule: const OneTimeRecurrence(),
          ),
        ),
        isFalse,
      );
    });

    test('true admits a specific-dates event, which is not one-time', () {
      expect(
        eventInDayRail(
          event(
            'e',
            showInDayRail: true,
            rule: SpecificDatesRecurrence(dates: {DateTime.utc(2026, 8, 10)}),
          ),
        ),
        isTrue,
      );
    });
  });

  group('EventDayRailProvider', () {
    test('emits only rail-eligible events, in arrival order', () {
      final events = [
        event('tracked', tracksPresence: true),
        event('plain'),
        event('forcedIn', showInDayRail: true),
        event('forcedOut', tracksPresence: true, showInDayRail: false),
      ];

      final marks = EventDayRailProvider(l10n).marksFor(day, events);

      expect(markIds(marks), ['tracked', 'forcedIn']);
    });

    test('a day with nothing eligible emits nothing', () {
      expect(EventDayRailProvider(l10n).marksFor(day, const []), isEmpty);
      expect(
        EventDayRailProvider(l10n).marksFor(day, [event('plain')]),
        isEmpty,
      );
    });

    test('an explicit colour override wins over the category colour', () {
      const override = 0xFF123456;

      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [
            event('e', tracksPresence: true, colorValue: override),
          ])
          .toList(growable: false);

      expect(marks.single.color, const Color(override));
    });

    test('emits the precomputed `event:<id>` key', () {
      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [event('abc-123', tracksPresence: true)])
          .toList(growable: false);

      expect(marks.single.key, 'event:abc-123');
    });

    test('does not mutate the caller list', () {
      final events = [
        event('b', tracksPresence: true),
        event('a', tracksPresence: true),
      ];

      EventDayRailProvider(l10n).marksFor(day, events).toList(growable: false);

      expect([for (final e in events) e.id], ['b', 'a']);
    });
  });

  group('presence', () {
    setUp(() {
      EventPresence.updateCache(
        byEvent: {
          'missed': {day},
          'untracked': {day},
        },
      );
    });

    test('a missed occurrence sets the flag and keeps its colour unfaded', () {
      // The alpha is applied at paint time so `dot` style can render the same
      // mark hollow; folding it in here would fade it twice.
      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [event('missed', tracksPresence: true)])
          .toList(growable: false);

      expect(marks.single.missed, isTrue);
      expect(marks.single.color.a, closeTo(1.0, 0.01));
    });

    test('a kept occurrence of a tracked event is not missed', () {
      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [event('kept', tracksPresence: true)])
          .toList(growable: false);

      expect(marks.single.missed, isFalse);
    });

    test('a stale mark on an untracked forced-in event is ignored', () {
      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [event('untracked', showInDayRail: true)])
          .toList(growable: false);

      expect(marks.single.missed, isFalse);
    });

    test('a hidden missed mark is dropped, never just flagged', () {
      final events = [
        event('missed', tracksPresence: true),
        event('kept', tracksPresence: true),
      ];

      final marks = EventDayRailProvider(
        l10n,
        missedDisplay: CalendarMissedDisplay.hidden,
      ).marksFor(day, events);

      expect(markIds(marks), ['kept']);
    });

    test('the missed label composes the title, so colour is not alone', () {
      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [
            event('missed', title: 'Physio', tracksPresence: true),
          ])
          .toList(growable: false);

      expect(marks.single.semanticLabel, 'Physio, missed');
    });

    test('a kept occurrence labels with the bare title', () {
      final marks = EventDayRailProvider(l10n)
          .marksFor(day, [event('kept', title: 'Physio', tracksPresence: true)])
          .toList(growable: false);

      expect(marks.single.semanticLabel, 'Physio');
    });
  });

  group('DayRailResolver.resolve', () {
    test('dedups by key across providers, first provider winning', () {
      final events = [event('dup', title: 'First', tracksPresence: true)];
      final resolver = DayRailResolver(
        providers: [EventDayRailProvider(l10n), EventDayRailProvider(l10n)],
      );

      final marks = resolver.resolve(day, events);

      expect(marks, hasLength(1));
      expect(marks.single.semanticLabel, 'First');
    });

    test('preserves provider order for equal-priority marks', () {
      // Ids chosen so lexical order is the reverse of the intended order: a
      // key tie-break would sort 'aaa' first. Already in `compareWithinDay`
      // order, which is the caller's contract.
      final events = [
        event(
          'zzz',
          tracksPresence: true,
          time: const EventTime(startMinute: 7 * 60),
        ),
        event(
          'aaa',
          tracksPresence: true,
          time: const EventTime(startMinute: 18 * 60),
        ),
      ];

      final resolver = DayRailResolver(providers: [EventDayRailProvider(l10n)]);

      expect(markIds(resolver.resolve(day, events)), ['zzz', 'aaa']);
    });

    test('sorts by priority and agrees with the shared comparator', () {
      final events = [
        event('a', priority: 4, tracksPresence: true),
        event(
          'b',
          priority: 2,
          tracksPresence: true,
          time: const EventTime(startMinute: 480),
        ),
        event(
          'c',
          priority: 2,
          tracksPresence: true,
          time: const EventTime(startMinute: 600),
        ),
      ]..sort(EventAgenda.compareWithinDay);

      final resolver = DayRailResolver(providers: [EventDayRailProvider(l10n)]);

      expect(markIds(resolver.resolve(day, events)), [
        for (final e in events) e.id,
      ]);
    });

    test('does not cap — the widget caps', () {
      final events = [
        for (var i = 0; i < 8; i++) event('e$i', tracksPresence: true),
      ];

      expect(DayRailResolver.defaults(l10n).resolve(day, events), hasLength(8));
    });

    test('defaults threads missedDisplay into the provider', () {
      EventPresence.updateCache(
        byEvent: {
          'missed': {day},
        },
      );

      final resolver = DayRailResolver.defaults(
        l10n,
        missedDisplay: CalendarMissedDisplay.hidden,
      );

      expect(
        resolver.resolve(day, [event('missed', tracksPresence: true)]),
        isEmpty,
      );
    });
  });
}
