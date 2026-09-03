import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/utils/agenda_day_list_index.dart';

AgendaDayListEntry _entry(
  DateTime day, {
  String title = 'Entry',
  bool missed = false,
}) {
  return AgendaDayListEntry(
    day: day,
    icon: Icons.celebration_rounded,
    color: const Color(0xFFFFB300),
    title: title,
    missed: missed,
  );
}

void main() {
  group('AgendaDayListIndex.build months', () {
    test('enumerates every calendar month across a year boundary', () {
      final index = AgendaDayListIndex.build(
        const [],
        windowStart: DateTime.utc(2026, 9, 2),
        windowEnd: DateTime.utc(2027, 9, 1),
      );

      expect(index.months, hasLength(13));
      expect(index.months.first, DateTime.utc(2026, 9, 1));
      expect(index.months.last, DateTime.utc(2027, 9, 1));
      expect(index.months, [
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 12, 1),
        DateTime.utc(2027, 1, 1),
        DateTime.utc(2027, 2, 1),
        DateTime.utc(2027, 3, 1),
        DateTime.utc(2027, 4, 1),
        DateTime.utc(2027, 5, 1),
        DateTime.utc(2027, 6, 1),
        DateTime.utc(2027, 7, 1),
        DateTime.utc(2027, 8, 1),
        DateTime.utc(2027, 9, 1),
      ]);
    });

    test('a single-month window enumerates exactly that month', () {
      final index = AgendaDayListIndex.build(
        const [],
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      expect(index.months, [DateTime.utc(2026, 9, 1)]);
    });
  });

  group('AgendaDayListIndex.build counts', () {
    test('counts per month and per day match the entries handed in', () {
      final entries = [
        _entry(DateTime.utc(2026, 9, 5), title: 'a'),
        _entry(DateTime.utc(2026, 9, 5), title: 'b'),
        _entry(DateTime.utc(2026, 9, 20), title: 'c'),
        _entry(DateTime.utc(2026, 10, 1), title: 'd'),
      ];
      final index = AgendaDayListIndex.build(
        entries,
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 10, 31),
      );

      expect(index.totalCount, 4);
      expect(index.countForMonth(DateTime.utc(2026, 9, 1)), 3);
      expect(index.countForMonth(DateTime.utc(2026, 10, 1)), 1);
      expect(index.countForMonth(DateTime.utc(2026, 11, 1)), 0);
      expect(index.countForDay(DateTime.utc(2026, 9, 5)), 2);
      expect(index.countForDay(DateTime.utc(2026, 9, 20)), 1);
      expect(index.countForDay(DateTime.utc(2026, 9, 6)), 0);
    });

    test('kept counts leave the missed entries out', () {
      final entries = [
        _entry(DateTime.utc(2026, 9, 5), title: 'a'),
        _entry(DateTime.utc(2026, 9, 5), title: 'b', missed: true),
        _entry(DateTime.utc(2026, 9, 20), title: 'c', missed: true),
        _entry(DateTime.utc(2026, 10, 1), title: 'd'),
      ];
      final index = AgendaDayListIndex.build(
        entries,
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 10, 31),
      );

      // The totals still describe everything handed in; only the attendance
      // counts subtract.
      expect(index.totalCount, 4);
      expect(index.countForMonth(DateTime.utc(2026, 9, 1)), 3);
      expect(index.keptCountForMonth(DateTime.utc(2026, 9, 1)), 1);
      expect(index.keptCountForMonth(DateTime.utc(2026, 10, 1)), 1);
      expect(index.keptCountForMonth(DateTime.utc(2026, 11, 1)), 0);
      expect(index.keptCountForDay(DateTime.utc(2026, 9, 5)), 1);
      expect(index.keptCountForDay(DateTime.utc(2026, 9, 20)), 0);
      expect(index.keptCountForDay(DateTime.utc(2026, 9, 6)), 0);
    });
  });

  group('AgendaDayListIndex.build masks', () {
    test('markedMaskForMonth sets one bit per marked day', () {
      final entries = [
        _entry(DateTime.utc(2026, 9, 1)),
        _entry(DateTime.utc(2026, 9, 15)),
        _entry(DateTime.utc(2026, 9, 30)),
      ];
      final index = AgendaDayListIndex.build(
        entries,
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      final mask = index.markedMaskForMonth(DateTime.utc(2026, 9, 1));
      expect(mask & (1 << 0), isNot(0));
      expect(mask & (1 << 14), isNot(0));
      expect(mask & (1 << 29), isNot(0));
      expect(mask & (1 << 1), 0);
      expect(mask & (1 << 13), 0);
    });

    test('missedMaskForMonth marks only days where nothing was kept', () {
      final entries = [
        _entry(DateTime.utc(2026, 9, 1), missed: true),
        _entry(DateTime.utc(2026, 9, 15), missed: true),
        _entry(DateTime.utc(2026, 9, 15), title: 'kept'),
        _entry(DateTime.utc(2026, 9, 30)),
      ];
      final index = AgendaDayListIndex.build(
        entries,
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      final missed = index.missedMaskForMonth(DateTime.utc(2026, 9, 1));
      // Day 1 is missed outright; day 15 has one attended entry beside the
      // missed one and wins its square back; day 30 was attended.
      expect(missed, 1 << 0);
      // Every one of them still marks the day.
      expect(
        index.markedMaskForMonth(DateTime.utc(2026, 9, 1)),
        (1 << 0) | (1 << 14) | (1 << 29),
      );
    });

    test('a month with nothing missed carries no missed bits', () {
      final index = AgendaDayListIndex.build(
        [_entry(DateTime.utc(2026, 9, 4))],
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      expect(index.missedMaskForMonth(DateTime.utc(2026, 9, 1)), 0);
      expect(index.missedMaskForMonth(DateTime.utc(2026, 10, 1)), 0);
    });

    test('windowMaskForMonth covers a partial first and last month', () {
      final index = AgendaDayListIndex.build(
        const [],
        windowStart: DateTime.utc(2026, 9, 15),
        windowEnd: DateTime.utc(2026, 11, 10),
      );

      final september = index.windowMaskForMonth(DateTime.utc(2026, 9, 1));
      // Days 1-14 fall before the window; days 15-30 fall inside it.
      for (var day = 1; day <= 14; day++) {
        expect(september & (1 << (day - 1)), 0, reason: 'day $day');
      }
      for (var day = 15; day <= 30; day++) {
        expect(september & (1 << (day - 1)), isNot(0), reason: 'day $day');
      }

      final october = index.windowMaskForMonth(DateTime.utc(2026, 10, 1));
      // October sits entirely inside the window: every one of its 31 days.
      expect(october, (1 << 31) - 1);

      final november = index.windowMaskForMonth(DateTime.utc(2026, 11, 1));
      for (var day = 1; day <= 10; day++) {
        expect(november & (1 << (day - 1)), isNot(0), reason: 'day $day');
      }
      for (var day = 11; day <= 30; day++) {
        expect(november & (1 << (day - 1)), 0, reason: 'day $day');
      }
    });

    test('a month entirely outside the window carries no window bits', () {
      final index = AgendaDayListIndex.build(
        const [],
        windowStart: DateTime.utc(2026, 9, 15),
        windowEnd: DateTime.utc(2026, 11, 10),
      );

      // December is not even in `months`, so the mask lookup falls back to 0.
      expect(index.windowMaskForMonth(DateTime.utc(2026, 12, 1)), 0);
    });
  });

  group('AgendaDayListIndex.build window extension', () {
    test('an entry outside the window extends the window and month list', () {
      final entries = [
        _entry(DateTime.utc(2026, 9, 15)),
        _entry(DateTime.utc(2027, 1, 3)),
      ];
      final index = AgendaDayListIndex.build(
        entries,
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      expect(index.windowStart, DateTime.utc(2026, 9, 1));
      expect(index.windowEnd, DateTime.utc(2027, 1, 3));
      expect(index.months.first, DateTime.utc(2026, 9, 1));
      expect(index.months.last, DateTime.utc(2027, 1, 1));
      expect(index.countForDay(DateTime.utc(2027, 1, 3)), 1);
      // The extending entry's own day is inside the (now-extended) window.
      final januaryMask = index.windowMaskForMonth(DateTime.utc(2027, 1, 1));
      expect(januaryMask & (1 << 2), isNot(0));
    });

    test('an entry before the window pulls windowStart earlier', () {
      final entries = [_entry(DateTime.utc(2026, 8, 20))];
      final index = AgendaDayListIndex.build(
        entries,
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      expect(index.windowStart, DateTime.utc(2026, 8, 20));
      expect(index.months.first, DateTime.utc(2026, 8, 1));
    });
  });

  group('AgendaDayListIndex entriesOn / entriesInMonth ordering', () {
    test('entriesOn preserves input order for a shared day', () {
      final first = _entry(DateTime.utc(2026, 9, 5), title: 'first');
      final second = _entry(DateTime.utc(2026, 9, 5), title: 'second');
      final third = _entry(DateTime.utc(2026, 9, 5), title: 'third');
      final index = AgendaDayListIndex.build(
        [first, second, third],
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      final onDay = index.entriesOn(DateTime.utc(2026, 9, 5));
      expect(onDay, [first, second, third]);
    });

    test('entriesInMonth preserves input order across days', () {
      final a = _entry(DateTime.utc(2026, 9, 20), title: 'a');
      final b = _entry(DateTime.utc(2026, 9, 5), title: 'b');
      final c = _entry(DateTime.utc(2026, 9, 5), title: 'c');
      final index = AgendaDayListIndex.build(
        [a, b, c],
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      // Input order, not day order: `a` (day 20) was handed in first.
      expect(index.entriesInMonth(DateTime.utc(2026, 9, 1)), [a, b, c]);
    });

    test(
      'entriesOn and entriesInMonth return const empty lists when unset',
      () {
        final index = AgendaDayListIndex.build(
          const [],
          windowStart: DateTime.utc(2026, 9, 1),
          windowEnd: DateTime.utc(2026, 9, 30),
        );

        expect(index.entriesOn(DateTime.utc(2026, 9, 5)), isEmpty);
        expect(index.entriesInMonth(DateTime.utc(2026, 9, 1)), isEmpty);
      },
    );
  });

  group('AgendaDayListIndex.build empty input', () {
    test('an empty entry list still indexes the bare window', () {
      final index = AgendaDayListIndex.build(
        const [],
        windowStart: DateTime.utc(2026, 9, 1),
        windowEnd: DateTime.utc(2026, 9, 30),
      );

      expect(index.totalCount, 0);
      expect(index.days, isEmpty);
      expect(index.months, [DateTime.utc(2026, 9, 1)]);
      expect(index.countForMonth(DateTime.utc(2026, 9, 1)), 0);
      expect(index.countForDay(DateTime.utc(2026, 9, 5)), 0);
      expect(index.markedMaskForMonth(DateTime.utc(2026, 9, 1)), 0);
      expect(index.windowMaskForMonth(DateTime.utc(2026, 9, 1)), (1 << 30) - 1);
    });
  });

  group('AgendaDayListIndex.build debug assertions', () {
    test('rejects a non-UTC windowStart', () {
      expect(
        () => AgendaDayListIndex.build(
          const [],
          windowStart: DateTime(2026, 9, 1),
          windowEnd: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a windowStart with a time component', () {
      expect(
        () => AgendaDayListIndex.build(
          const [],
          windowStart: DateTime.utc(2026, 9, 1, 12),
          windowEnd: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a non-date-only UTC entry day', () {
      expect(
        () => AgendaDayListIndex.build(
          [_entry(DateTime.utc(2026, 9, 5, 8, 30))],
          windowStart: DateTime.utc(2026, 9, 1),
          windowEnd: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a non-UTC entry day', () {
      expect(
        () => AgendaDayListIndex.build(
          [_entry(DateTime(2026, 9, 5))],
          windowStart: DateTime.utc(2026, 9, 1),
          windowEnd: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AgendaDayListMonth', () {
    test('counts every entry handed in, duplicates on a day included', () {
      final month = AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
        _entry(DateTime.utc(2026, 2, 14), title: 'a'),
        _entry(DateTime.utc(2026, 2, 14), title: 'b'),
        _entry(DateTime.utc(2026, 2, 28), title: 'c'),
      ]);

      expect(month.count, 3);
      expect(month.countForDay(DateTime.utc(2026, 2, 14)), 2);
      expect(month.countForDay(DateTime.utc(2026, 2, 28)), 1);
      expect(month.countForDay(DateTime.utc(2026, 2, 1)), 0);
    });

    test('markedMask sets one bit per day carrying an entry', () {
      final month = AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
        _entry(DateTime.utc(2026, 2, 1)),
        _entry(DateTime.utc(2026, 2, 14)),
        _entry(DateTime.utc(2026, 2, 14)),
        _entry(DateTime.utc(2026, 2, 28)),
      ]);

      expect(month.markedMask & (1 << 0), isNot(0));
      expect(month.markedMask & (1 << 13), isNot(0));
      expect(month.markedMask & (1 << 27), isNot(0));
      expect(month.markedMask & (1 << 1), 0);
      expect(month.markedMask & (1 << 12), 0);
    });

    test('keptCount and missedMask account for the missed entries', () {
      final month = AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
        _entry(DateTime.utc(2026, 2, 1), missed: true),
        _entry(DateTime.utc(2026, 2, 14), missed: true),
        _entry(DateTime.utc(2026, 2, 14), title: 'kept'),
        _entry(DateTime.utc(2026, 2, 28)),
      ]);

      expect(month.count, 4);
      expect(month.keptCount, 2);
      expect(month.keptCountForDay(DateTime.utc(2026, 2, 1)), 0);
      expect(month.keptCountForDay(DateTime.utc(2026, 2, 14)), 1);
      expect(month.keptCountForDay(DateTime.utc(2026, 2, 28)), 1);
      // Off the month, as `entriesOn` does.
      expect(month.keptCountForDay(DateTime.utc(2026, 3, 28)), 0);
      // Only the 1st has nothing kept on it.
      expect(month.missedMask, 1 << 0);
    });

    test('days are ascending and hold only days with entries', () {
      final month = AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
        _entry(DateTime.utc(2026, 2, 28), title: 'late'),
        _entry(DateTime.utc(2026, 2, 3), title: 'early'),
        _entry(DateTime.utc(2026, 2, 14), title: 'middle'),
        _entry(DateTime.utc(2026, 2, 3), title: 'early again'),
      ]);

      expect(month.days, [
        DateTime.utc(2026, 2, 3),
        DateTime.utc(2026, 2, 14),
        DateTime.utc(2026, 2, 28),
      ]);
    });

    test('entriesOn keeps input order and answers empty off the month', () {
      final first = _entry(DateTime.utc(2026, 2, 14), title: 'first');
      final second = _entry(DateTime.utc(2026, 2, 14), title: 'second');
      final month = AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
        first,
        second,
      ]);

      expect(month.entriesOn(DateTime.utc(2026, 2, 14)), [first, second]);
      expect(month.entriesOn(DateTime.utc(2026, 2, 15)), isEmpty);
      // A day of a neighbouring month is not this bucket's business, even
      // when the grid asks about it.
      expect(month.entriesOn(DateTime.utc(2026, 3, 14)), isEmpty);
    });

    test('an empty month still describes itself', () {
      final month = AgendaDayListMonth.build(
        DateTime.utc(2026, 2, 1),
        const [],
      );

      expect(month.count, 0);
      expect(month.keptCount, 0);
      expect(month.markedMask, 0);
      expect(month.missedMask, 0);
      expect(month.days, isEmpty);
      // 2026 is not a leap year; the tile's dot matrix reads this.
      expect(month.daysInMonth, 28);
    });

    test('daysInMonth follows the calendar, leap years included', () {
      expect(
        AgendaDayListMonth.build(
          DateTime.utc(2028, 2, 1),
          const [],
        ).daysInMonth,
        29,
      );
      expect(
        AgendaDayListMonth.build(
          DateTime.utc(2026, 4, 1),
          const [],
        ).daysInMonth,
        30,
      );
    });

    test('rejects an entry falling outside the month', () {
      expect(
        () => AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
          _entry(DateTime.utc(2026, 3, 1)),
        ]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a month that is not the first of a month', () {
      expect(
        () => AgendaDayListMonth.build(DateTime.utc(2026, 2, 2), const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a non-date-only UTC entry day', () {
      expect(
        () => AgendaDayListMonth.build(DateTime.utc(2026, 2, 1), [
          _entry(DateTime.utc(2026, 2, 14, 8)),
        ]),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
