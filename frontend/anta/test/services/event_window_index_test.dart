import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/constants/alert_constants.dart';
import 'package:anta/services/event_window_index.dart';
import 'package:anta/utils/digest_planner.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/event_search_query.dart';

import 'support/event_window_fixture.dart';

/// The window index narrows every range scan to the recurring events plus
/// the one-time events of the months a window touches (scalability record
/// §5.6, S13). It must change no result: each call site's scan is compared
/// with the full scan it replaced ([EventWindowIndex.debugFullScan]) over a
/// seeded store, and the work it saves is pinned in calls, not milliseconds.
void main() {
  final store = seededWindowStore();

  tearDown(() => EventWindowIndex.debugFullScan = false);

  /// [scan] once through the index and once over the whole store.
  (T, T) both<T>(T Function() scan) {
    EventWindowIndex.debugFullScan = false;
    final indexed = scan();
    EventWindowIndex.debugFullScan = true;
    final full = scan();
    EventWindowIndex.debugFullScan = false;
    return (indexed, full);
  }

  List<String> keysOf(List<EventOccurrence> occurrences) => [
    for (final o in occurrences)
      '${o.event.id}@${o.day.toIso8601String()}x${o.occurrenceCountInWindow}',
  ];

  group('eventsPossiblyIn', () {
    final a = CalendarEvent(
      id: 'a',
      title: 'a',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 1, 31),
    );
    final weekly = CalendarEvent(
      id: 'w',
      title: 'w',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 1, 1),
      rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
    );
    final b = CalendarEvent(
      id: 'b',
      title: 'b',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 2, 1),
    );
    final dates = CalendarEvent(
      id: 'd',
      title: 'd',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 5, 1),
      rule: SpecificDatesRecurrence(dates: {DateTime.utc(2025, 1, 1)}),
    );
    final c = CalendarEvent(
      id: 'c',
      title: 'c',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 3, 1),
    );
    final events = List<CalendarEvent>.unmodifiable([a, weekly, b, dates, c]);
    List<String> ids(DateTime from, DateTime to) => [
      for (final e in EventWindowIndex.of(events).eventsPossiblyIn(from, to))
        e.id,
    ];

    test('the recurring events and the touched months\' one-time events, in '
        'the list\'s order', () {
      expect(ids(DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 1)), [
        'w',
        'b',
        'd',
      ]);
      expect(ids(DateTime.utc(2026, 1, 31), DateTime.utc(2026, 2, 1)), [
        'a',
        'w',
        'b',
        'd',
      ]);
      expect(
        ids(DateTime.utc(2025, 1, 1), DateTime.utc(2026, 12, 31)),
        ['a', 'w', 'b', 'd', 'c'],
        reason: 'a window wider than the months held walks the buckets',
      );
      expect(
        ids(DateTime.utc(2026, 4, 1), DateTime.utc(2026, 4, 30)),
        ['w', 'd'],
        reason: 'specific dates may lie anywhere, so they are always in',
      );
      expect(
        ids(DateTime.utc(2026, 3, 1), DateTime.utc(2026, 2, 1)),
        ['w', 'd'],
        reason: 'an inverted window touches no month',
      );
    });

    test('one index per list instance, rebuilt for another list', () {
      expect(
        identical(EventWindowIndex.of(events), EventWindowIndex.of(events)),
        isTrue,
      );
      final copy = List<CalendarEvent>.unmodifiable(events);
      expect(
        identical(EventWindowIndex.of(copy), EventWindowIndex.of(events)),
        isFalse,
      );
      final grown = [a];
      EventWindowIndex.of(grown);
      grown.add(b);
      expect(
        EventWindowIndex.of(
          grown,
        ).eventsPossiblyIn(DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 1)),
        [b],
        reason: 'a list grown in place is indexed again',
      );
    });

    test('an empty store has nothing to narrow', () {
      expect(
        EventWindowIndex.of(
          const <CalendarEvent>[],
        ).eventsPossiblyIn(DateTime.utc(2026), DateTime.utc(2026, 12, 31)),
        isEmpty,
      );
    });
  });

  group('the scans are unchanged', () {
    test('a plain scan, as the digest planner asks it', () {
      for (final (from, to) in seededWindows) {
        final (indexed, full) = both(
          () => EventAgenda.occurrencesInRange(
            events: store,
            from: from,
            to: to,
            categoryIds: const {},
          ),
        );
        expect(keysOf(indexed), keysOf(full), reason: '$from .. $to');
      }
      // The fixture must reach every class the index narrows.
      final year = EventAgenda.occurrencesInRange(
        events: store,
        from: DateTime.utc(2026),
        to: DateTime.utc(2026, 12, 31),
      );
      expect(year.where((o) => o.event.rule is OneTimeRecurrence), isNotEmpty);
      expect(year.where((o) => o.event.rule is! OneTimeRecurrence), isNotEmpty);
    });

    test("the overview's year and month runs, with an allowlist", () {
      for (final (from, to) in seededWindows) {
        final (indexed, full) = both(
          () => EventAgenda.occurrencesInRange(
            events: store,
            from: from,
            to: to,
            categoryIds: const {'gym', 'birthday'},
          ),
        );
        expect(keysOf(indexed), keysOf(full), reason: '$from .. $to');
      }
    });

    test("the upcoming agenda's scan: a denylist, priorities, a query over "
        'the labels, collapsed and with the missed hidden', () {
      final query = EventSearchQuery.parse('event', localeName: 'en');
      for (final collapse in [false, true]) {
        for (final (from, to) in seededWindows) {
          final (indexed, full) = both(
            () => EventAgenda.occurrencesInRange(
              events: store,
              from: from,
              to: to,
              hiddenCategoryIds: const {'other'},
              priorities: const {1, 2, 4},
              query: query,
              labelTextOf: (event) => event.priority.isEven ? 'even' : 'odd',
              collapseRecurring: collapse,
              hideMissed: true,
            ),
          );
          expect(
            keysOf(indexed),
            keysOf(full),
            reason: '$from .. $to, collapse: $collapse',
          );
        }
      }
    });

    test('DigestPlanner.plan: every digest shape, the same plan', () {
      final now = DateTime(2026, 1, 20, 12);
      final digests = [
        for (final (i, cadence) in DigestCadence.values.indexed)
          EventDigest(
            id: 'd$i',
            cadence: cadence,
            anchor: cadence == DigestCadence.daily ? 0 : 1,
            minute: 9 * 60,
            leadDays: i % 3,
            categoryIds: i.isEven ? const {} : const {'gym', 'work'},
            includeEmpty: i.isOdd,
            enabled: true,
            sortOrder: i,
          ),
      ];
      List<String> describe(List<PlannedDigest> plan) => [
        for (final p in plan)
          '${p.digest.id} ${p.fireAt} ${p.spanStart} ${p.spanEnd} '
              '${keysOf(p.entries).join(',')}',
      ];
      final (indexed, full) = both(
        () => DigestPlanner.plan(
          digests: digests,
          events: store,
          horizon: const DigestHorizon(perDigest: 4, maxDigests: 10),
          now: now,
        ),
      );
      expect(describe(indexed), describe(full));
      expect(indexed.expand((p) => p.entries), isNotEmpty);
    });
  });

  group('the work it saves', () {
    // Yearly routines are sparse: one candidate day each per year. The
    // one-time events lie one per month from 2020 to 2030.
    final yearly = [
      for (var i = 0; i < 5; i++)
        CalendarEvent(
          id: 'y$i',
          title: 'Yearly $i',
          categoryId: 'birthday',
          startDate: DateTime.utc(2010, i + 1, 10),
          rule: const YearlyRecurrence(),
        ),
    ];
    final oneTime = [
      for (var month = 0; month < 132; month++)
        CalendarEvent(
          id: 'o$month',
          title: 'Once $month',
          categoryId: 'work',
          startDate: DateTime.utc(2020, month + 1, 5),
        ),
    ];
    final events = List<CalendarEvent>.unmodifiable([...yearly, ...oneTime]);

    test('a year run validates the routines and that year\'s one-time '
        'events, and asks for no other event\'s labels', () {
      var labelled = 0;
      EventAgenda.debugClearFoldCaches();
      CalendarEvent.debugOccursOnCalls = 0;
      final occurrences = EventAgenda.occurrencesInRange(
        events: events,
        from: DateTime.utc(2026),
        to: DateTime.utc(2026, 12, 31),
        query: EventSearchQuery.parse('nothing-matches', localeName: 'en'),
        labelTextOf: (event) {
          labelled++;
          return 'nothing-matches';
        },
      );
      expect(occurrences, hasLength(5 + 12));
      expect(
        CalendarEvent.debugOccursOnCalls,
        5 + 12,
        reason: 'one candidate day per routine, one per one-time event of 2026',
      );
      expect(labelled, 5 + 12, reason: 'the other 120 are never candidates');
    });

    test('a year with no one-time event touches the routines alone', () {
      var labelled = 0;
      CalendarEvent.debugOccursOnCalls = 0;
      EventAgenda.occurrencesInRange(
        events: events,
        from: DateTime.utc(2035),
        to: DateTime.utc(2035, 12, 31),
        query: EventSearchQuery.parse('nothing-matches', localeName: 'en'),
        labelTextOf: (event) {
          labelled++;
          return 'nothing-matches';
        },
      );
      expect(CalendarEvent.debugOccursOnCalls, 5);
      expect(labelled, 5);
    });
  });
}
