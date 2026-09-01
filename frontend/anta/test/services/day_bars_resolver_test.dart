import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/l10n/app_localizations_en.dart';
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

  List<String> barIds(Iterable<DayBar> bars) => [
    for (final bar in bars) bar.key.replaceFirst('event:', ''),
  ];

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  group('EventDayBarProvider ordering', () {
    // barsFor no longer sorts its own input (3.3) — `CalendarBloc.eventsForDay`
    // sorts once by `EventAgenda.compareWithinDay` when a day's memo entry is
    // built, so every one of these feeds events already in that order and
    // asserts barsFor preserves it rather than re-deriving it.
    test('equal priorities preserve the all-day-before-timed order', () {
      final events = [
        event('allDay'),
        event('timed', time: const EventTime(startMinute: 9 * 60)),
      ];

      final bars = const EventDayBarProvider()
          .barsFor(day, events)
          .toList(growable: false);

      expect(barIds(bars), ['allDay', 'timed']);
    });

    test('equal priorities preserve start-minute order', () {
      final events = [
        event('morning', time: const EventTime(startMinute: 7 * 60)),
        event('evening', time: const EventTime(startMinute: 18 * 60)),
      ];

      final bars = const EventDayBarProvider()
          .barsFor(day, events)
          .toList(growable: false);

      expect(barIds(bars), ['morning', 'evening']);
    });

    test('preserves priority order over time', () {
      final events = [
        event('highLate', priority: 1, time: const EventTime(startMinute: 600)),
        event('lowLate', priority: 5, time: const EventTime(startMinute: 60)),
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
      // order: a key tie-break would sort 'aaa' first. Already in
      // `compareWithinDay` order (zzz's start minute is earlier) — the
      // caller's contract since 3.3 — so this is a real precondition here,
      // not an accident of the ids chosen.
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
      // barsFor no longer sorts (3.3), so this feeds events pre-sorted by
      // the shared comparator and asserts the resolver's own priority
      // tie-break (by insertion index) preserves that order end to end,
      // rather than re-deriving it the way the two layers used to together.
      final events = [
        event('a', priority: 4),
        event('b', priority: 2, time: const EventTime(startMinute: 480)),
        event('c', priority: 2, time: const EventTime(startMinute: 600)),
      ]..sort(EventAgenda.compareWithinDay);

      final resolver = const DayBarsResolver(
        providers: [EventDayBarProvider()],
      );

      expect(barIds(resolver.resolve(day, events)), [
        for (final e in events) e.id,
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

  group('rail exclusion', () {
    // D8: while the rail renders, each channel means one thing — the rail
    // carries recurring commitments and their presence, the bars carry
    // everything else — and the freed `maxDayBars` slots go to the events
    // nothing else shows. With the rail off the bars must be byte-for-byte
    // what they always were, so turning the rail off can never silently drop
    // an event from the grid.
    test('a rail event vanishes from the bars while the rail is active', () {
      final events = [event('tracked', tracksPresence: true), event('plain')];

      final bars = const EventDayBarProvider(
        railActive: true,
      ).barsFor(day, events);

      expect(barIds(bars), ['plain']);
    });

    test('an event forced out of the rail keeps its bar', () {
      final events = [
        event('forcedOut', tracksPresence: true, showInDayRail: false),
      ];

      final bars = const EventDayBarProvider(
        railActive: true,
      ).barsFor(day, events);

      expect(barIds(bars), ['forcedOut']);
    });

    test('an event forced into the rail loses its bar', () {
      final events = [event('forcedIn', showInDayRail: true)];

      final bars = const EventDayBarProvider(
        railActive: true,
      ).barsFor(day, events);

      expect(bars, isEmpty);
    });

    test('a tracked one-time event keeps its bar — it is never railed', () {
      final events = [
        event(
          'once',
          tracksPresence: true,
          showInDayRail: true,
          rule: const OneTimeRecurrence(),
        ),
      ];

      final bars = const EventDayBarProvider(
        railActive: true,
      ).barsFor(day, events);

      expect(barIds(bars), ['once']);
    });

    test('the default is inert — every event keeps its bar', () {
      final events = [
        event('tracked', tracksPresence: true),
        event('forcedIn', showInDayRail: true),
        event('plain'),
      ];

      final bars = const EventDayBarProvider().barsFor(day, events);

      expect(barIds(bars), ['tracked', 'forcedIn', 'plain']);
    });

    test('DayBarsResolver.defaults threads railActive through', () {
      final l10n = AppLocalizationsEn();
      final events = [event('tracked', tracksPresence: true), event('plain')];

      final withRail = DayBarsResolver.defaults(l10n, railActive: true);
      final withoutRail = DayBarsResolver.defaults(l10n);

      expect(barIds(withRail.resolve(day, events)), ['plain']);
      expect(barIds(withoutRail.resolve(day, events)), ['tracked', 'plain']);
    });

    /// The grid filter's annotation layers are **provider composition**, not a
    /// gate downstream: a layer that is off is a provider that was never
    /// built. Asserted structurally because the holiday/fasting/money
    /// providers emit nothing with their facades unconfigured, so an output
    /// comparison could not tell "absent" from "silent".
    test('the layer flags compose providers out', () {
      final l10n = AppLocalizationsEn();

      final all = DayBarsResolver.defaults(l10n);
      final none = DayBarsResolver.defaults(
        l10n,
        showHolidays: false,
        showFasting: false,
        showMoney: false,
      );

      expect(all.providers.whereType<PublicHolidayDayBarProvider>(), isNotEmpty);
      expect(all.providers.whereType<FastingDayBarProvider>(), isNotEmpty);
      expect(all.providers.whereType<MoneyDayBarProvider>(), isNotEmpty);

      expect(none.providers.whereType<PublicHolidayDayBarProvider>(), isEmpty);
      expect(none.providers.whereType<FastingDayBarProvider>(), isEmpty);
      expect(none.providers.whereType<MoneyDayBarProvider>(), isEmpty);
      // Events and weekends are not layers — nothing the filter offers can
      // compose them out.
      expect(none.providers.whereType<EventDayBarProvider>(), hasLength(1));
      expect(none.providers.whereType<WeekendDayBarProvider>(), hasLength(1));
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

  group('CalendarEvent.barKey (5.3 precompute)', () {
    test('is `event:<id>`', () {
      expect(event('abc-123').barKey, 'event:abc-123');
    });

    test('is stable across reads — the `late final` memo, not recomputed', () {
      final e = event('stable');
      // Two reads of a `late final` field return the exact same String
      // instance; a plain getter re-running `'event:${event.id}'` would
      // also pass `==` here but would allocate a fresh String each time.
      expect(identical(e.barKey, e.barKey), isTrue);
    });

    test('barsFor emits the precomputed key unchanged', () {
      final bars = const EventDayBarProvider()
          .barsFor(day, [event('precomputed')])
          .toList(growable: false);

      expect(bars.single.key, 'event:precomputed');
    });

    // The collision constraint from the roadmap: the resolver's other
    // well-known keys are 'weekend', 'holiday', 'fasting:<tradition>' and
    // 'money'. None of them carry the 'event:' prefix, so no event id can
    // ever produce a bar key equal to one of them. Pinned here by feeding
    // an event whose *id* is chosen to look exactly like a sibling key and
    // confirming both bars survive `DayBarsResolver.resolve`'s
    // `putIfAbsent`-keyed dedup — a real collision would silently drop one.
    test('cannot collide with the weekend key', () {
      final saturday = DateTime.utc(2026, 8, 8);
      expect(saturday.weekday, DateTime.saturday);
      final l10n = AppLocalizationsEn();
      final resolver = DayBarsResolver(
        providers: [const EventDayBarProvider(), WeekendDayBarProvider(l10n)],
      );

      final bars = resolver.resolve(saturday, [
        event('weekend', title: 'Impersonator'),
      ]);

      expect(bars.map((b) => b.key).toSet(), {'event:weekend', 'weekend'});
    });

    test('cannot collide with the money key', () {
      final l10n = AppLocalizationsEn();
      final resolver = DayBarsResolver(
        providers: [const EventDayBarProvider(), MoneyDayBarProvider(l10n)],
      );

      // MoneyDayBarProvider needs no linked note to still leave the event
      // bar alone — it only ever contributes a bar of its own when the
      // ledger service is initialized, which it is not in this test. The
      // point here is purely that an id of 'money' resolves to a distinct
      // key, not that both bars are present.
      final bars = resolver.resolve(day, [
        event('money', title: 'Impersonator'),
      ]);

      expect(bars.map((b) => b.key), ['event:money']);
    });

    test('cannot collide with a fasting tradition key', () {
      // No FastingCalendar configuration is loaded in this test, so
      // FastingDayBarProvider contributes nothing either way — asserting
      // only that the event keeps its own distinct, prefixed key.
      final bars = const EventDayBarProvider()
          .barsFor(day, [event('fasting:greatLent', title: 'Impersonator')])
          .toList(growable: false);

      expect(bars.single.key, 'event:fasting:greatLent');
    });
  });
}
