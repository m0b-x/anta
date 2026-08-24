import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/recurrence_rule.dart';

/// Differential guard for `RecurrenceRule.candidateDaysIn` (3.2b).
///
/// The generator is a **superset** filter, never a membership decision: the
/// scan still validates every candidate through `CalendarEvent.occursOnUtcDay`,
/// so an extra day costs one check while a missing day silently removes a real
/// event from the user's calendar. This file only ever asserts that direction —
/// containment — which is what turns "byte-identical to the old full scan" from
/// an argument into a checkable property.
///
/// Every rule kind is walked against windows that sit after, straddle and sit
/// entirely before the anchor, in both retroactive modes, so the Feb-29 skip,
/// the day-31 clamp, the Monday-grid week phase (including `_weekIndex`'s
/// negative floor) and the empty-weekday case are all covered by the same table.
void main() {
  DateTime day(int year, int month, int dayOfMonth) =>
      DateTime.utc(year, month, dayOfMonth);

  /// Asserts the superset contract over `[from, to]`: `occursOn` true implies
  /// membership in the generated set. A `null` result opts the rule out of
  /// pruning entirely, which is always sound.
  void expectSuperset(
    RecurrenceRule rule,
    DateTime start, {
    required DateTime from,
    required DateTime to,
    required bool retroactive,
    required String label,
  }) {
    final candidates = rule.candidateDaysIn(
      from,
      to,
      start,
      retroactive: retroactive,
    );
    if (candidates == null) return;
    final generated = candidates.toSet();
    final missing = <DateTime>[];
    for (
      var probe = from;
      !probe.isAfter(to);
      probe = probe.add(const Duration(days: 1))
    ) {
      if (rule.occursOn(probe, start, retroactive: retroactive) &&
          !generated.contains(probe)) {
        missing.add(probe);
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          '$label (retroactive: $retroactive) dropped real occurrences '
          '${missing.take(5).toList()} from [$from, $to]',
    );
  }

  /// The three window positions relative to [start] the contract has to hold
  /// for: entirely after, straddling, entirely before (the negative-phase path).
  void expectSupersetEverywhere(
    String label,
    RecurrenceRule rule,
    DateTime start, {
    int span = 400,
    int offset = 40,
  }) {
    final windows = <String, (DateTime, DateTime)>{
      'after': (
        start.add(Duration(days: offset)),
        start.add(Duration(days: offset + span)),
      ),
      'straddling': (
        start.subtract(Duration(days: span ~/ 2)),
        start.add(Duration(days: span ~/ 2)),
      ),
      'before': (
        start.subtract(Duration(days: offset + span)),
        start.subtract(Duration(days: offset)),
      ),
    };
    for (final entry in windows.entries) {
      for (final retroactive in const [false, true]) {
        expectSuperset(
          rule,
          start,
          from: entry.value.$1,
          to: entry.value.$2,
          retroactive: retroactive,
          label: '$label / ${entry.key}',
        );
      }
    }
  }

  group('candidateDaysIn is a superset of occursOn', () {
    final anchor = day(2026, 3, 12);

    final cases = <String, (RecurrenceRule, DateTime)>{
      'oneTime': (const OneTimeRecurrence(), anchor),
      'specificDates': (
        SpecificDatesRecurrence(
          dates: <DateTime>{
            // Deliberately unsorted, and straddling the anchor: this rule has
            // no pre-start guard, so a date before `start` still fires.
            day(2026, 6, 1),
            day(2025, 11, 30),
            anchor,
            day(2026, 3, 31),
            day(2024, 2, 29),
          },
        ),
        anchor,
      ),
      'daily interval 1': (const DailyRecurrence(), anchor),
      'daily interval 3': (const DailyRecurrence(interval: 3), anchor),
      'daily interval 7': (const DailyRecurrence(interval: 7), anchor),
      'weekly single day': (
        const WeeklyRecurrence(weekdays: {DateTime.monday}),
        anchor,
      ),
      'weekly three days': (
        const WeeklyRecurrence(
          weekdays: {DateTime.tuesday, DateTime.thursday, DateTime.sunday},
        ),
        anchor,
      ),
      'weekly all seven': (
        const WeeklyRecurrence(weekdays: {1, 2, 3, 4, 5, 6, 7}),
        anchor,
      ),
      'weekly all seven every 2 weeks': (
        const WeeklyRecurrence(weekdays: {1, 2, 3, 4, 5, 6, 7}, interval: 2),
        anchor,
      ),
      'weekly empty set': (const WeeklyRecurrence(weekdays: <int>{}), anchor),
      'weekly interval 2': (
        const WeeklyRecurrence(weekdays: {DateTime.wednesday}, interval: 2),
        anchor,
      ),
      'weekly interval 3 pre-epoch anchor': (
        const WeeklyRecurrence(
          weekdays: {DateTime.friday, DateTime.saturday},
          interval: 3,
        ),
        day(1997, 5, 14),
      ),
      'monthly interval 1': (const MonthlyRecurrence(), anchor),
      'monthly interval 2': (const MonthlyRecurrence(interval: 2), anchor),
      'monthly interval 5': (const MonthlyRecurrence(interval: 5), anchor),
      'monthly day 31 anchor': (const MonthlyRecurrence(), day(2026, 1, 31)),
      'monthly day 30 anchor': (const MonthlyRecurrence(), day(2025, 4, 30)),
      'monthly day 29 anchor': (const MonthlyRecurrence(), day(2024, 1, 29)),
      'monthly day 31 anchor every 3 months': (
        const MonthlyRecurrence(interval: 3),
        day(2026, 1, 31),
      ),
      'yearly interval 1': (const YearlyRecurrence(), anchor),
      'yearly interval 2': (const YearlyRecurrence(interval: 2), anchor),
      'yearly interval 4': (const YearlyRecurrence(interval: 4), anchor),
      'yearly leap-day anchor': (const YearlyRecurrence(), day(2024, 2, 29)),
      'yearly leap-day anchor every 2 years': (
        const YearlyRecurrence(interval: 2),
        day(2024, 2, 29),
      ),
      'workdays': (const WorkdaysRecurrence(), anchor),
      'weekends': (const WeekendsRecurrence(), anchor),
      'holidaysOnly': (const PublicHolidaysOnlyRecurrence(), anchor),
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        expectSupersetEverywhere(entry.key, entry.value.$1, entry.value.$2);
      });
    }
  });

  group('leap-year and short-month anchors across many years', () {
    // Wide enough to cross 2024/2028/2032 (leap) and every non-leap year
    // between them, so the Feb-29 skip and the day-31 clamp are exercised
    // repeatedly rather than once.
    final from = day(2020, 1, 1);
    final to = day(2033, 12, 31);

    test('yearly Feb-29 anchor never drops a leap year', () {
      for (final retroactive in const [false, true]) {
        expectSuperset(
          const YearlyRecurrence(),
          day(2024, 2, 29),
          from: from,
          to: to,
          retroactive: retroactive,
          label: 'yearly Feb-29 wide',
        );
      }
      final generated = const YearlyRecurrence()
          .candidateDaysIn(from, to, day(2024, 2, 29), retroactive: true)!
          .toSet();
      expect(generated, contains(day(2024, 2, 29)));
      expect(generated, contains(day(2028, 2, 29)));
      expect(generated, contains(day(2020, 2, 29)));
      // The rolled-over date `DateTime.utc(2027, 2, 29)` is March 1, which
      // `occursOn` rejects; emitting it would be pure waste.
      expect(generated, isNot(contains(day(2027, 3, 1))));
      expect(generated.every((d) => d.month == 2 && d.day == 29), isTrue);
    });

    test('monthly day-31 anchor never drops a 31-day month', () {
      for (final retroactive in const [false, true]) {
        expectSuperset(
          const MonthlyRecurrence(),
          day(2026, 1, 31),
          from: from,
          to: to,
          retroactive: retroactive,
          label: 'monthly day-31 wide',
        );
      }
      final generated = const MonthlyRecurrence()
          .candidateDaysIn(from, to, day(2026, 1, 31), retroactive: true)!
          .toSet();
      expect(generated, contains(day(2026, 1, 31)));
      expect(generated, contains(day(2026, 3, 31)));
      expect(generated, contains(day(2020, 12, 31)));
      // February and the 30-day months have no 31st; a rolled-over
      // `DateTime.utc(2026, 2, 31)` would be March 3.
      expect(generated, isNot(contains(day(2026, 3, 3))));
      expect(generated, isNot(contains(day(2026, 5, 1))));
      expect(generated.every((d) => d.day == 31), isTrue);
    });

    test('monthly day-30 anchor never drops a 30-day month', () {
      for (final retroactive in const [false, true]) {
        expectSuperset(
          const MonthlyRecurrence(),
          day(2026, 4, 30),
          from: from,
          to: to,
          retroactive: retroactive,
          label: 'monthly day-30 wide',
        );
      }
      final generated = const MonthlyRecurrence()
          .candidateDaysIn(from, to, day(2026, 4, 30), retroactive: true)!
          .toSet();
      expect(generated, contains(day(2026, 4, 30)));
      expect(generated, contains(day(2026, 1, 30)));
      // February never has a 30th; `DateTime.utc(2026, 2, 30)` is March 2.
      expect(generated, isNot(contains(day(2026, 3, 2))));
      expect(generated.every((d) => d.day == 30), isTrue);
    });

    test('monthly day-29 anchor keeps February only in leap years', () {
      final generated = const MonthlyRecurrence()
          .candidateDaysIn(from, to, day(2024, 1, 29), retroactive: true)!
          .toSet();
      expect(generated, contains(day(2024, 2, 29)));
      expect(generated, isNot(contains(day(2025, 2, 29))));
      expect(generated, isNot(contains(day(2025, 3, 1))));
      expect(generated.every((d) => d.day == 29), isTrue);
      for (final retroactive in const [false, true]) {
        expectSuperset(
          const MonthlyRecurrence(),
          day(2024, 1, 29),
          from: from,
          to: to,
          retroactive: retroactive,
          label: 'monthly day-29 wide',
        );
      }
    });
  });

  group('week phase comes off the Monday grid, not the anchor', () {
    // 2026-03-12 is a Thursday; an every-2-weeks rule on Wednesdays therefore
    // fires in weeks whose `_weekIndex` matches the anchor's, which is *not*
    // the same set as "every 14 days from the anchor".
    final start = DateTime.utc(2026, 3, 12);
    const rule = WeeklyRecurrence(weekdays: {DateTime.wednesday}, interval: 2);

    test('forward window keeps the anchor week parity', () {
      final from = DateTime.utc(2026, 3, 1);
      final to = DateTime.utc(2026, 12, 31);
      final generated = rule.candidateDaysIn(from, to, start)!.toSet();
      for (
        var probe = from;
        !probe.isAfter(to);
        probe = probe.add(const Duration(days: 1))
      ) {
        if (rule.occursOn(probe, start)) {
          expect(generated, contains(probe));
        }
      }
      // The anchor's own week is a firing week, and its Wednesday precedes the
      // Thursday anchor — so the forward, non-retroactive window must not
      // contain it, while the retroactive one must.
      expect(generated, isNot(contains(DateTime.utc(2026, 3, 11))));
      final retro = rule
          .candidateDaysIn(from, to, start, retroactive: true)!
          .toSet();
      expect(retro, contains(DateTime.utc(2026, 3, 11)));
    });

    test('retroactive window entirely before the anchor and the epoch', () {
      // Before `_weekEpoch` (2000-01-03), where `_weekIndex` floors toward
      // negative infinity — the case a 7-day step from `start` gets wrong.
      final from = DateTime.utc(1996, 1, 1);
      final to = DateTime.utc(1999, 12, 31);
      const preEpoch = WeeklyRecurrence(
        weekdays: {DateTime.monday, DateTime.friday},
        interval: 3,
      );
      final anchor = DateTime.utc(2026, 3, 12);
      final generated = preEpoch
          .candidateDaysIn(from, to, anchor, retroactive: true)!
          .toSet();
      var fired = 0;
      for (
        var probe = from;
        !probe.isAfter(to);
        probe = probe.add(const Duration(days: 1))
      ) {
        if (preEpoch.occursOn(probe, anchor, retroactive: true)) {
          fired++;
          expect(generated, contains(probe));
        }
      }
      expect(fired, greaterThan(100), reason: 'window must actually fire');
    });
  });

  group('null and empty are different answers', () {
    final start = DateTime.utc(2026, 3, 12);
    final from = DateTime.utc(2026, 1, 1);
    final to = DateTime.utc(2026, 12, 31);

    test('rules that cannot prune return null, not every day', () {
      expect(const DailyRecurrence().candidateDaysIn(from, to, start), isNull);
      expect(
        const WeeklyRecurrence(
          weekdays: {1, 2, 3, 4, 5, 6, 7},
        ).candidateDaysIn(from, to, start),
        isNull,
      );
      expect(
        const WorkdaysRecurrence().candidateDaysIn(from, to, start),
        isNull,
      );
      expect(
        const WeekendsRecurrence().candidateDaysIn(from, to, start),
        isNull,
      );
      // Mandatory: membership is the mutable `PublicHolidays` facade, which no
      // cached index may capture.
      expect(
        const PublicHolidaysOnlyRecurrence().candidateDaysIn(from, to, start),
        isNull,
      );
    });

    test('an empty weekday set generates nothing, not everything', () {
      const rule = WeeklyRecurrence(weekdays: <int>{});
      for (final retroactive in const [false, true]) {
        expect(
          rule.candidateDaysIn(from, to, start, retroactive: retroactive),
          isEmpty,
        );
      }
      for (
        var probe = from;
        !probe.isAfter(to);
        probe = probe.add(const Duration(days: 1))
      ) {
        expect(rule.occursOn(probe, start, retroactive: true), isFalse);
      }
    });

    test('a rule whose window ends before its anchor generates nothing', () {
      final before = DateTime.utc(2025, 1, 1);
      final beforeEnd = DateTime.utc(2025, 6, 30);
      expect(
        const DailyRecurrence(
          interval: 3,
        ).candidateDaysIn(before, beforeEnd, start),
        isEmpty,
      );
      expect(
        const WeeklyRecurrence(
          weekdays: {DateTime.monday},
        ).candidateDaysIn(before, beforeEnd, start),
        isEmpty,
      );
      expect(
        const MonthlyRecurrence().candidateDaysIn(before, beforeEnd, start),
        isEmpty,
      );
      expect(
        const YearlyRecurrence().candidateDaysIn(before, beforeEnd, start),
        isEmpty,
      );
    });
  });

  group('the exact-membership rules ignore the anchor', () {
    test('oneTime yields its start only when the window holds it', () {
      final start = DateTime.utc(2026, 3, 12);
      expect(
        const OneTimeRecurrence().candidateDaysIn(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 12, 31),
          start,
        ),
        [start],
      );
      expect(
        const OneTimeRecurrence().candidateDaysIn(
          DateTime.utc(2027, 1, 1),
          DateTime.utc(2027, 12, 31),
          start,
        ),
        isEmpty,
      );
    });

    test('specificDates keeps dates before the anchor', () {
      final start = DateTime.utc(2026, 3, 12);
      final early = DateTime.utc(2024, 5, 4);
      final late = DateTime.utc(2027, 9, 9);
      final rule = SpecificDatesRecurrence(
        dates: <DateTime>{late, early, start},
      );
      final generated = rule
          .candidateDaysIn(
            DateTime.utc(2020, 1, 1),
            DateTime.utc(2030, 1, 1),
            start,
          )!
          .toSet();
      expect(generated, {early, start, late});
      // `supportsRetroactive` is false, so the flag must not change anything.
      expect(
        rule
            .candidateDaysIn(
              DateTime.utc(2020, 1, 1),
              DateTime.utc(2030, 1, 1),
              start,
              retroactive: true,
            )!
            .toSet(),
        generated,
      );
      expect(
        rule
            .candidateDaysIn(
              DateTime.utc(2026, 1, 1),
              DateTime.utc(2026, 12, 31),
              start,
            )!
            .toSet(),
        {start},
      );
    });
  });
}
