import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/utils/agenda_month_store.dart';

AgendaDayListEntry _entry(DateTime day, {bool missed = false}) {
  return AgendaDayListEntry(
    day: day,
    icon: Icons.fitness_center,
    color: const Color(0xFF1E88E5),
    title: 'Entry ${day.day}',
    missed: missed,
  );
}

/// The store resolves on navigation and caches for good: one resolver call
/// per contiguous run of months, an empty bucket for a month with nothing in
/// it, and cache-only answers for everything a frame asks.
void main() {
  final pool = [
    _entry(DateTime.utc(2026, 1, 5)),
    _entry(DateTime.utc(2026, 1, 5), missed: true),
    _entry(DateTime.utc(2026, 3, 9)),
    _entry(DateTime.utc(2025, 12, 24)),
  ];

  late List<(DateTime, DateTime)> calls;

  List<AgendaDayListEntry> resolve(DateTime start, DateTime end) {
    calls.add((start, end));
    return [
      for (final entry in pool)
        if (!entry.day.isBefore(start) && !entry.day.isAfter(end)) entry,
    ];
  }

  AgendaMonthStore store() => AgendaMonthStore(resolve: resolve, maxBars: 1);

  setUp(() => calls = []);

  test('a contiguous run resolves in one call, a gap in two', () {
    final s = store();
    s.ensure([
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 2, 1),
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 6, 1),
    ]);

    expect(calls, [
      (DateTime.utc(2026, 1, 1), DateTime.utc(2026, 3, 31)),
      (DateTime.utc(2026, 6, 1), DateTime.utc(2026, 6, 30)),
    ]);
  });

  test('an empty month is cached too, so nothing resolves twice', () {
    final s = store();
    s.ensure([DateTime.utc(2026, 2, 1)]);
    s.ensure([DateTime.utc(2026, 2, 1)]);
    s.monthFor(DateTime.utc(2026, 2, 1));

    expect(calls, hasLength(1));
    expect(s.isResolved(DateTime.utc(2026, 2, 1)), isTrue);
    expect(s.cached(DateTime.utc(2026, 2, 1))!.count, 0);
  });

  test('a whole year is one call from January 1 to December 31', () {
    final s = store();
    s.ensure(AgendaMonthStore.monthsOfYear(2026));

    expect(calls, [(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31))]);
    expect(s.cached(DateTime.utc(2026, 1, 1))!.count, 2);
    expect(s.cached(DateTime.utc(2026, 3, 1))!.count, 1);
    expect(s.cached(DateTime.utc(2026, 12, 1))!.count, 0);
  });

  test('monthFor resolves on demand and hands back the bucket', () {
    final s = store();
    final bucket = s.monthFor(DateTime.utc(2025, 12, 1));

    expect(calls, [(DateTime.utc(2025, 12, 1), DateTime.utc(2025, 12, 31))]);
    expect(bucket.days, [DateTime.utc(2025, 12, 24)]);
  });

  test('hasEntry and barsFor answer from the cache alone', () {
    final s = store();
    expect(s.hasEntry(DateTime.utc(2026, 1, 5)), isFalse);
    expect(s.barsFor(DateTime.utc(2026, 1, 5)), isNull);
    expect(calls, isEmpty);

    s.ensure([DateTime.utc(2026, 1, 1)]);

    expect(s.hasEntry(DateTime.utc(2026, 1, 5)), isTrue);
    expect(s.hasEntry(DateTime.utc(2026, 1, 6)), isFalse);
    final bars = s.barsFor(DateTime.utc(2026, 1, 5))![5]!;
    expect(bars, hasLength(1), reason: 'capped at maxBars');
    expect(bars.single.color, const Color(0xFF1E88E5));
  });

  test('a missed entry\'s bar carries the missed fade', () {
    final s = AgendaMonthStore(resolve: resolve, maxBars: 3);
    s.ensure([DateTime.utc(2026, 1, 1)]);

    final bars = s.barsFor(DateTime.utc(2026, 1, 5))![5]!;
    expect(bars, hasLength(2));
    expect(bars[1].color.a, closeTo(CalendarColors.missedEventAlpha, 0.01));
  });

  group('tallies', () {
    late List<(DateTime, DateTime)> markCalls;

    List<AgendaDayMark> resolveMarks(DateTime start, DateTime end) {
      markCalls.add((start, end));
      return [
        for (final entry in pool)
          if (!entry.day.isBefore(start) && !entry.day.isAfter(end))
            AgendaDayMark(
              day: entry.day,
              color: entry.color,
              missed: entry.missed,
            ),
      ];
    }

    setUp(() => markCalls = []);

    AgendaMonthStore withMarks() => AgendaMonthStore(
      resolve: resolve,
      resolveMarks: resolveMarks,
      maxBars: 1,
    );

    test('a year of tallies is one marks call and no row at all', () {
      final s = withMarks();
      s.ensureTallies(AgendaMonthStore.monthsOfYear(2026));

      expect(markCalls, [
        (DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31)),
      ]);
      expect(calls, isEmpty, reason: 'tiles never need entries');
      final january = s.cachedTally(DateTime.utc(2026, 1, 1))!;
      expect(january.count, 2);
      expect(january.keptCount, 1);
      expect(january.markedMask, 1 << 4);
      expect(january.missedMask, 0, reason: 'one kept entry wins the day');
      expect(january.dayColors[4], const Color(0xFF1E88E5));
      expect(january.dayColors[5], isNull);
      expect(s.cachedTally(DateTime.utc(2026, 6, 1))!.count, 0);
      expect(s.isResolved(DateTime.utc(2026, 1, 1)), isFalse);
    });

    test('a month whose rows are cached derives its tally for free', () {
      final s = withMarks();
      s.ensure([DateTime.utc(2026, 3, 1)]);
      s.ensureTallies([DateTime.utc(2026, 3, 1)]);

      expect(markCalls, isEmpty);
      expect(s.cachedTally(DateTime.utc(2026, 3, 1))!.count, 1);
    });

    test('tallyFor resolves on demand and caches', () {
      final s = withMarks();
      final tally = s.tallyFor(DateTime.utc(2025, 12, 1));
      s.tallyFor(DateTime.utc(2025, 12, 1));

      expect(markCalls, hasLength(1));
      expect(tally.markedMask, 1 << 23);
    });

    test('without a marks resolver the rows stand in', () {
      final s = store();
      s.ensureTallies(AgendaMonthStore.monthsOfYear(2026));

      expect(calls, [(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 12, 31))]);
      expect(s.cachedTally(DateTime.utc(2026, 1, 1))!.count, 2);
      expect(s.isResolved(DateTime.utc(2026, 1, 1)), isTrue);
    });
  });

  test('the month keys round-trip across a year boundary', () {
    final december = DateTime.utc(2025, 12, 1);
    final january = DateTime.utc(2026, 1, 1);
    expect(AgendaMonthStore.keyOf(january), AgendaMonthStore.keyOf(december) + 1);
    expect(AgendaMonthStore.monthOfKey(AgendaMonthStore.keyOf(january)), january);
    expect(AgendaMonthStore.monthOf(DateTime.utc(2026, 1, 31)), january);
  });
}
