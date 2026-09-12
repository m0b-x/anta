import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/presence_stats.dart';

/// Adherence is derived arithmetic with no storage of its own, so every risk
/// here is a boundary: which days count toward the ratio, which count toward
/// the streaks, and whether a day that has not happened yet can drag either
/// down.
void main() {
  final today = DateTime.utc(2026, 8, 18);

  CalendarEvent event({
    RecurrenceRule rule = const DailyRecurrence(),
    DateTime? startDate,
    bool tracksPresence = true,
    bool retroactive = false,
    bool assumeAbsent = false,
    DateTime? assumeAbsentFrom,
  }) {
    return CalendarEvent(
      id: 'e1',
      title: 'Leg day',
      categoryId: 'gym',
      // Well before the lookback window, so a full-lookback expectation is
      // about the walk and not about where the series happens to start.
      startDate: startDate ?? DateTime.utc(2024, 1, 1),
      rule: rule,
      tracksPresence: tracksPresence,
      retroactive: retroactive,
      assumeAbsent: assumeAbsent,
      assumeAbsentFrom: assumeAbsentFrom,
    );
  }

  void markMissed(Iterable<DateTime> days) {
    EventPresence.updateCache(
      byEvent: {
        'e1': {for (final day in days) day: PresenceStatus.missed},
      },
    );
  }

  void markPresent(Iterable<DateTime> days) {
    EventPresence.updateCache(
      byEvent: {
        'e1': {for (final day in days) day: PresenceStatus.present},
      },
    );
  }

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  group('gating', () {
    test('an event that does not track presence has no stats', () {
      expect(
        PresenceAdherence.compute(event(tracksPresence: false), today: today),
        isNull,
      );
    });

    test('a one-time event has no stats even when it opted in', () {
      expect(
        PresenceAdherence.compute(
          event(rule: const OneTimeRecurrence()),
          today: today,
        ),
        isNull,
      );
    });

    test('an event with no occurrence in the lookback has no stats', () {
      expect(
        PresenceAdherence.compute(
          event(startDate: DateTime.utc(2030, 1, 1)),
          today: today,
        ),
        isNull,
      );
    });
  });

  group('attended / total', () {
    test('a clean daily run fills the window exactly', () {
      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.total, PresenceAdherence.windowDays);
      expect(stats.attended, PresenceAdherence.windowDays);
    });

    test('each miss inside the window costs one attendance', () {
      markMissed([
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 5)),
      ]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.total, PresenceAdherence.windowDays);
      expect(stats.attended, PresenceAdherence.windowDays - 2);
    });

    test('a miss just outside the window does not touch the ratio', () {
      markMissed([
        today.subtract(const Duration(days: PresenceAdherence.windowDays)),
      ]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.attended, PresenceAdherence.windowDays);
    });

    test('the window is inclusive of today and of its far edge', () {
      markMissed([
        today,
        today.subtract(const Duration(days: PresenceAdherence.windowDays - 1)),
      ]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.attended, PresenceAdherence.windowDays - 2);
    });

    test('a weekly rule only counts the days it fires on', () {
      // Anchored on a Monday, so exactly the Mondays in the window count.
      final stats = PresenceAdherence.compute(
        event(
          rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
          startDate: DateTime.utc(2026, 1, 5),
        ),
        today: today,
      )!;

      expect(stats.total, lessThan(PresenceAdherence.windowDays));
      expect(stats.total, greaterThan(0));
      expect(stats.attended, stats.total);
    });

    test('days before the series start never count', () {
      final start = today.subtract(const Duration(days: 4));

      final stats = PresenceAdherence.compute(
        event(startDate: start),
        today: today,
      )!;

      expect(stats.total, 5);
    });
  });

  group('streaks', () {
    test('an unbroken run streaks the whole lookback', () {
      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.currentStreak, PresenceAdherence.lookbackDays);
      expect(stats.longestStreak, PresenceAdherence.lookbackDays);
    });

    test('a miss today zeroes the current streak', () {
      markMissed([today]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.currentStreak, 0);
      expect(stats.longestStreak, PresenceAdherence.lookbackDays - 1);
    });

    test('the current streak counts back to the most recent miss', () {
      markMissed([today.subtract(const Duration(days: 3))]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.currentStreak, 3);
    });

    test('the longest streak can beat the current one', () {
      markMissed([
        today.subtract(const Duration(days: 2)),
        today.subtract(const Duration(days: 12)),
      ]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.currentStreak, 2);
      // The nine clean days between the two misses.
      expect(stats.longestStreak, greaterThan(stats.currentStreak));
    });

    test('a gap day the event never fires on does not break a streak', () {
      // Every-other-day: the untouched off-days must not read as misses.
      final stats = PresenceAdherence.compute(
        event(
          rule: const DailyRecurrence(interval: 2),
          startDate: DateTime.utc(2026, 1, 1),
        ),
        today: today,
      )!;

      expect(stats.currentStreak, stats.longestStreak);
      expect(stats.currentStreak, greaterThan(1));
    });
  });

  group('future occurrences', () {
    test('a pre-marked future miss is ignored until it happens', () {
      markMissed([today.add(const Duration(days: 1))]);

      final stats = PresenceAdherence.compute(event(), today: today)!;

      expect(stats.attended, PresenceAdherence.windowDays);
      expect(stats.currentStreak, PresenceAdherence.lookbackDays);
    });
  });

  group('optimistic override', () {
    test('a not-yet-written miss counts immediately', () {
      final stats = PresenceAdherence.compute(
        event(),
        today: today,
        overrideDay: today,
        overrideMissed: true,
      )!;

      expect(stats.attended, PresenceAdherence.windowDays - 1);
      expect(stats.currentStreak, 0);
    });

    test('a not-yet-written un-mark clears a stored miss', () {
      markMissed([today]);

      final stats = PresenceAdherence.compute(
        event(),
        today: today,
        overrideDay: today,
        overrideMissed: false,
      )!;

      expect(stats.attended, PresenceAdherence.windowDays);
      expect(stats.currentStreak, PresenceAdherence.lookbackDays);
    });

    test('it applies to exactly one day, not the whole event', () {
      markMissed([today.subtract(const Duration(days: 2))]);

      final stats = PresenceAdherence.compute(
        event(),
        today: today,
        overrideDay: today,
        overrideMissed: false,
      )!;

      expect(stats.attended, PresenceAdherence.windowDays - 1);
    });

    test('a naive local override day still matches the walk', () {
      // The walk keys on date-only UTC; a caller handing over a wall-clock
      // DateTime must not silently miss.
      final stats = PresenceAdherence.compute(
        event(),
        today: today,
        overrideDay: DateTime(today.year, today.month, today.day, 13, 45),
        overrideMissed: true,
      )!;

      expect(stats.currentStreak, 0);
    });
  });

  group('assume-absent events (v37)', () {
    test('an unconfirmed event scores zero, not full marks', () {
      final stats = PresenceAdherence.compute(
        event(assumeAbsent: true),
        today: today,
      )!;

      // The reading this whole feature exists for: before v37 a tracked event
      // nobody had ever marked read as attended on every day of its life, so
      // the drill-down called a month the user never confirmed "fully
      // present".
      expect(stats.total, PresenceAdherence.windowDays);
      expect(stats.attended, 0);
      expect(stats.currentStreak, 0);
      expect(stats.longestStreak, 0);
    });

    test('one confirmed day is one attendance and one streak', () {
      markPresent([today]);

      final stats = PresenceAdherence.compute(
        event(assumeAbsent: true),
        today: today,
      )!;

      expect(stats.attended, 1);
      expect(stats.currentStreak, 1);
      expect(stats.longestStreak, 1);
    });

    test('a confirmed day still breaks against the days around it', () {
      markPresent([today.subtract(const Duration(days: 3))]);

      final stats = PresenceAdherence.compute(
        event(assumeAbsent: true),
        today: today,
      )!;

      // Today is unconfirmed, so the current streak is closed before the walk
      // ever reaches the confirmation.
      expect(stats.attended, 1);
      expect(stats.currentStreak, 0);
      expect(stats.longestStreak, 1);
    });

    test('a boundary splits the window in two readings', () {
      final from = today.subtract(const Duration(days: 9));

      final stats = PresenceAdherence.compute(
        event(assumeAbsent: true, assumeAbsentFrom: from),
        today: today,
      )!;

      // Ten days on the inverted side (the boundary day included), the other
      // twenty still reading as the implicit attendance they were recorded
      // under — which is the entire reason the from-date exists.
      expect(stats.total, PresenceAdherence.windowDays);
      expect(stats.attended, PresenceAdherence.windowDays - 10);
      expect(stats.currentStreak, 0);
      expect(stats.longestStreak, PresenceAdherence.lookbackDays - 10);
    });

    test('the boundary never reads the wall clock', () {
      // A future day of an assume-absent event is missed like any other, but
      // the walk still refuses to count it — the two rules are independent and
      // both have to hold, or a pre-marked tomorrow drags today's ratio down.
      final stats = PresenceAdherence.compute(
        event(assumeAbsent: true, assumeAbsentFrom: today),
        today: today,
      )!;

      expect(stats.total, PresenceAdherence.windowDays);
      expect(stats.attended, PresenceAdherence.windowDays - 1);
    });
  });

  group('retroactive events', () {
    test('occurrences before the anchor still count', () {
      // Anchored in the future, so every counted day is a back-projection.
      final stats = PresenceAdherence.compute(
        event(startDate: DateTime.utc(2026, 12, 1), retroactive: true),
        today: today,
      )!;

      expect(stats.total, PresenceAdherence.windowDays);
    });
  });
}
