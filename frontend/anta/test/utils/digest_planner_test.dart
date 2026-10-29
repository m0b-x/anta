import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/digest_planner.dart';

/// The digest planner is the alert planner's twin and pure the same way:
/// `now` is injected, every case pins it, and fire instants are asserted as
/// wall clock so the suite holds in any host timezone.
void main() {
  const horizon = DigestHorizon(perDigest: 2, maxDigests: 10);

  /// Tuesday 2026-09-15, noon.
  final now = DateTime(2026, 9, 15, 12);

  EventDigest digestOf({
    String id = 'd1',
    DigestCadence cadence = DigestCadence.monthly,
    int anchor = 1,
    int minute = 9 * 60,
    int leadDays = 0,
    Set<String> categoryIds = const {},
    bool includeEmpty = true,
    bool enabled = true,
    int sortOrder = 0,
  }) => EventDigest(
    id: id,
    cadence: cadence,
    anchor: anchor,
    minute: minute,
    leadDays: leadDays,
    categoryIds: categoryIds,
    includeEmpty: includeEmpty,
    enabled: enabled,
    sortOrder: sortOrder,
  );

  CalendarEvent eventOf(
    String id,
    DateTime startDate, {
    String categoryId = 'birthday',
    RecurrenceRule rule = const OneTimeRecurrence(),
    EventTime? time,
  }) => CalendarEvent(
    id: id,
    title: id,
    categoryId: categoryId,
    startDate: startDate,
    rule: rule,
    time: time,
  );

  List<PlannedDigest> planOf(
    List<EventDigest> digests, {
    List<CalendarEvent> events = const [],
    DateTime? at,
    DigestHorizon caps = horizon,
  }) => DigestPlanner.plan(
    digests: digests,
    events: events,
    horizon: caps,
    now: at ?? now,
  );

  group('fire instants', () {
    test('daily: today when still ahead, then tomorrow', () {
      final plan = planOf([
        digestOf(cadence: DigestCadence.daily, anchor: 0, minute: 18 * 60),
      ]);

      expect(plan.map((fire) => fire.fireAt), [
        DateTime(2026, 9, 15, 18),
        DateTime(2026, 9, 16, 18),
      ]);
    });

    test('daily: a time already behind now starts tomorrow', () {
      final plan = planOf([
        digestOf(cadence: DigestCadence.daily, anchor: 0, minute: 8 * 60),
      ]);

      expect(plan.map((fire) => fire.fireAt), [
        DateTime(2026, 9, 16, 8),
        DateTime(2026, 9, 17, 8),
      ]);
    });

    test('weekly: each anchor lands on its own weekday', () {
      for (
        var weekday = DateTime.monday;
        weekday <= DateTime.sunday;
        weekday++
      ) {
        final fires = planOf([
          digestOf(cadence: DigestCadence.weekly, anchor: weekday),
        ]).map((fire) => fire.fireAt).toList();

        expect(fires, hasLength(2), reason: 'weekday $weekday');
        for (final fire in fires) {
          expect(fire.weekday, weekday);
          expect(fire.isAfter(now), isTrue);
        }
        expect(
          fires[1],
          DateTime(fires[0].year, fires[0].month, fires[0].day + 7, 9),
        );
      }
    });

    test("weekly: today's anchor at a time behind now is next week's", () {
      final fires = planOf([
        digestOf(cadence: DigestCadence.weekly, anchor: DateTime.tuesday),
      ]).map((fire) => fire.fireAt);

      expect(fires, [DateTime(2026, 9, 22, 9), DateTime(2026, 9, 29, 9)]);
    });

    test('monthly: the next two of the anchor day', () {
      final fires = planOf([digestOf()]).map((fire) => fire.fireAt);

      expect(fires, [DateTime(2026, 10, 1, 9), DateTime(2026, 11, 1, 9)]);
    });

    test('monthly: the anchor still ahead this month comes first', () {
      final fires = planOf([digestOf(anchor: 20)]).map((fire) => fire.fireAt);

      expect(fires, [DateTime(2026, 9, 20, 9), DateTime(2026, 10, 20, 9)]);
    });

    test('monthly: anchor 28 fires in February', () {
      final fires = planOf([
        digestOf(anchor: 28),
      ], at: DateTime(2027, 1, 30)).map((fire) => fire.fireAt);

      expect(fires, [DateTime(2027, 2, 28, 9), DateTime(2027, 3, 28, 9)]);
    });

    test('nextFireInstants answers without the spans', () {
      expect(
        DigestPlanner.nextFireInstants(
          digestOf(includeEmpty: false),
          now: now,
          count: 3,
        ),
        [
          DateTime(2026, 10, 1, 9),
          DateTime(2026, 11, 1, 9),
          DateTime(2026, 12, 1, 9),
        ],
      );
    });
  });

  group('daylight saving', () {
    // The wall-clock constructor, never local midnight plus a duration — the
    // alert planner's A14 rule. In a zone with no transition on these days
    // it is the ordinary case, which must also hold.
    for (final date in [
      DateTime.utc(2026, 3, 29),
      DateTime.utc(2026, 10, 25),
      DateTime.utc(2026, 3, 8),
      DateTime.utc(2026, 11, 1),
    ]) {
      test('a 07:00 daily digest fires at 07:00 on '
          '${date.toIso8601String()}', () {
        final plan = planOf([
          digestOf(cadence: DigestCadence.daily, anchor: 0, minute: 7 * 60),
        ], at: DateTime(date.year, date.month, date.day - 1, 12));

        final fireAt = plan.first.fireAt;
        expect(fireAt.day, date.day);
        expect(fireAt.hour, 7);
        expect(fireAt.minute, 0);
        expect(fireAt, DateTime(date.year, date.month, date.day, 0, 7 * 60));
      });
    }
  });

  group('the span', () {
    test('daily is the fire day, or the next with a lead of one', () {
      final today = digestOf(cadence: DigestCadence.daily, anchor: 0);
      final tomorrow = today.copyWith(leadDays: 1);
      final day = DateTime.utc(2026, 9, 30);

      expect(DigestPlanner.spanFor(today, day), (start: day, end: day));
      expect(DigestPlanner.spanFor(tomorrow, day), (
        start: DateTime.utc(2026, 10, 1),
        end: DateTime.utc(2026, 10, 1),
      ));
    });

    test('weekly is seven days from the span start', () {
      final sunday = digestOf(
        cadence: DigestCadence.weekly,
        anchor: DateTime.sunday,
        leadDays: 1,
      );

      expect(DigestPlanner.spanFor(sunday, DateTime.utc(2026, 9, 27)), (
        start: DateTime.utc(2026, 9, 28),
        end: DateTime.utc(2026, 10, 4),
      ));
    });

    test('monthly on the 1st is the calendar month', () {
      expect(DigestPlanner.spanFor(digestOf(), DateTime.utc(2027, 2, 1)), (
        start: DateTime.utc(2027, 2, 1),
        end: DateTime.utc(2027, 2, 28),
      ));
    });

    test('monthly from the 15th runs to the 14th of the next month', () {
      expect(
        DigestPlanner.spanFor(digestOf(anchor: 15), DateTime.utc(2026, 12, 15)),
        (start: DateTime.utc(2026, 12, 15), end: DateTime.utc(2027, 1, 14)),
      );
    });

    test('a planned digest carries the span of its fire day', () {
      final fire = planOf([digestOf(leadDays: 1)]).first;

      expect(fire.spanStart, DateTime.utc(2026, 10, 2));
      expect(fire.spanEnd, DateTime.utc(2026, 11, 1));
    });
  });

  group('entries', () {
    test('every occurrence in the span is an entry, sorted by day', () {
      final events = [
        eventOf('late', DateTime.utc(2026, 10, 27)),
        eventOf('early', DateTime.utc(2026, 10, 4)),
        eventOf(
          'weekly',
          DateTime.utc(2026, 10, 5),
          rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
        ),
        eventOf('outside', DateTime.utc(2026, 11, 2)),
      ];

      final october = planOf([digestOf()], events: events).first;

      expect(october.entries.map((entry) => (entry.event.id, entry.day.day)), [
        ('early', 4),
        ('weekly', 5),
        ('weekly', 12),
        ('weekly', 19),
        ('weekly', 26),
        ('late', 27),
      ]);
    });

    test('the allowlist narrows the entries; empty lists every category', () {
      final events = [
        eventOf('ana', DateTime.utc(2026, 10, 4)),
        eventOf('run', DateTime.utc(2026, 10, 6), categoryId: 'gym'),
      ];

      final birthdays = planOf([
        digestOf(categoryIds: const {'birthday'}),
      ], events: events).first;
      final everything = planOf([digestOf()], events: events).first;

      expect(birthdays.entries.map((entry) => entry.event.id), ['ana']);
      expect(everything.entries.map((entry) => entry.event.id), ['ana', 'run']);
    });

    test('an empty span is left out unless the digest says otherwise', () {
      final events = [eventOf('ana', DateTime.utc(2026, 10, 4))];

      final quiet = planOf([digestOf(includeEmpty: false)], events: events);
      final loud = planOf([digestOf(includeEmpty: true)], events: events);

      // October lists Ana; November lists nothing.
      expect(quiet.map((fire) => fire.fireAt), [DateTime(2026, 10, 1, 9)]);
      expect(loud.map((fire) => fire.fireAt), [
        DateTime(2026, 10, 1, 9),
        DateTime(2026, 11, 1, 9),
      ]);
      expect(loud.last.entries, isEmpty);
    });
  });

  group('which digests', () {
    test('a disabled digest plans nothing', () {
      expect(planOf([digestOf(enabled: false)]), isEmpty);
    });

    test('maxDigests takes the first enabled ones in display order', () {
      final plan = planOf([
        digestOf(id: 'c', sortOrder: 2),
        digestOf(id: 'off', sortOrder: 0, enabled: false),
        digestOf(id: 'a', sortOrder: 1),
        digestOf(id: 'b', sortOrder: 3),
      ], caps: const DigestHorizon(perDigest: 1, maxDigests: 2));

      expect(plan.map((fire) => fire.digest.id), ['a', 'c']);
    });

    test('overCapIds names the enabled tail the plan leaves out', () {
      // C113: what the hub reads to say a switched-on digest is not armed.
      // Same order as the plan, and a disabled digest is never in it — it
      // takes no room under the cap and promises no fire either way.
      const horizon = DigestHorizon(perDigest: 1, maxDigests: 2);
      final digests = [
        digestOf(id: 'c', sortOrder: 2),
        digestOf(id: 'off', sortOrder: 0, enabled: false),
        digestOf(id: 'a', sortOrder: 1),
        digestOf(id: 'b', sortOrder: 3),
      ];

      expect(
        DigestPlanner.overCapIds(digests: digests, horizon: horizon),
        {'b'},
      );
      expect(
        DigestPlanner.overCapIds(
          digests: digests.take(2).toList(),
          horizon: horizon,
        ),
        isEmpty,
      );
    });

    test('the plan is soonest first, then by digest id', () {
      final plan = planOf([
        digestOf(id: 'z', cadence: DigestCadence.daily, anchor: 0),
        digestOf(id: 'monthly'),
        digestOf(id: 'a', cadence: DigestCadence.daily, anchor: 0),
      ]);

      expect(plan.map((fire) => (fire.digest.id, fire.fireAt.day)), [
        ('a', 16),
        ('z', 16),
        ('a', 17),
        ('z', 17),
        ('monthly', 1),
        ('monthly', 1),
      ]);
    });
  });

  group('out of range', () {
    test('a digest built out of range fails where it is built, in debug', () {
      expect(
        () => EventDigest(id: 'x', anchor: 31),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EventDigest(id: 'x', minute: Duration.minutesPerDay),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EventDigest(id: 'x', leadDays: EventDigest.maxLeadDays + 1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EventDigest(id: 'x', cadence: DigestCadence.weekly, anchor: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('the planner reads one clamped, as a release build would hold it', () {
      // A release build carries no asserts: the 31st is the 28th, a minute
      // past the day is its last minute, a lead past seven is seven.
      const draft = _UncheckedDigest(anchor: 31, minute: 1500, leadDays: 12);

      final plan = planOf([draft], caps: horizon);

      expect(plan.map((fire) => fire.fireAt), [
        DateTime(2026, 9, 28, 0, EventDigest.lastMinute),
        DateTime(2026, 10, 28, 0, EventDigest.lastMinute),
      ]);
      expect(plan.first.spanStart, DateTime.utc(2026, 10, 5));
      expect(plan.first.spanEnd, DateTime.utc(2026, 11, 4));
    });
  });

  group('work budget', () {
    // Counted, not timed — the alert planner's register. A yearly birthday
    // names its one day in a span, so a month of thirty birthdays costs
    // thirty probes, not thirty times thirty-one.
    setUp(() => CalendarEvent.debugOccursOnCalls = 0);

    test('yearly events cost one probe each over a month span', () {
      final events = [
        for (var i = 0; i < 30; i++)
          eventOf(
            'b$i',
            DateTime.utc(1990 + i, 10, 1 + i),
            rule: const YearlyRecurrence(),
          ),
      ];

      final plan = planOf(
        [digestOf()],
        events: events,
        caps: const DigestHorizon(perDigest: 1, maxDigests: 10),
      );

      expect(plan.single.entries, hasLength(30));
      expect(CalendarEvent.debugOccursOnCalls, 30);
    });
  });
}

/// A monthly digest whose fields no debug constructor would let through —
/// what a release build could hold. Only what the planner reads is answered.
class _UncheckedDigest implements EventDigest {
  const _UncheckedDigest({
    required this.anchor,
    required this.minute,
    required this.leadDays,
  });

  @override
  final int anchor;

  @override
  final int minute;

  @override
  final int leadDays;

  @override
  String get id => 'unchecked';

  @override
  String get name => '';

  @override
  DigestCadence get cadence => DigestCadence.monthly;

  @override
  Set<String> get categoryIds => const {};

  @override
  bool get includeEmpty => true;

  @override
  bool get enabled => true;

  @override
  int get sortOrder => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
