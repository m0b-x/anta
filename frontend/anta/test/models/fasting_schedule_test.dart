import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/fasting_schedule.dart';

DateTime _utc(int year, int month, int day) => DateTime.utc(year, month, day);

void main() {
  group('defaults', () {
    test('is Wednesday + Friday, every month, weekly scope, no exceptions', () {
      const schedule = FastingSchedule();
      expect(schedule.weekdays, {DateTime.wednesday, DateTime.friday});
      expect(schedule.months, FastingSchedule.allMonths);
      expect(schedule.weekdayScope, FastingWeekdayScope.weeklyOnly);
      expect(schedule.skipDates, isEmpty);
      expect(schedule.forceDates, isEmpty);
      expect(schedule.keepsEveryMonth, isTrue);
      expect(schedule.exceptionCount, 0);
    });
  });

  group('encode / decode', () {
    test('round-trips every field', () {
      final schedule = const FastingSchedule().copyWith(
        weekdays: {DateTime.monday, DateTime.saturday},
        weekdayScope: FastingWeekdayScope.allFasts,
        months: {1, 6, 12},
        skipDates: {_utc(2026, 3, 15), _utc(2026, 4, 2)},
        forceDates: {_utc(2026, 5, 1)},
      );

      expect(FastingSchedule.decode(schedule.encode()), schedule);
    });

    test('round-trips an empty weekday set', () {
      final schedule = const FastingSchedule().copyWith(weekdays: const {});
      final decoded = FastingSchedule.decode(schedule.encode());
      expect(decoded.weekdays, isEmpty);
      expect(decoded.months, FastingSchedule.allMonths);
    });

    test('omits empty date lists but keeps the structural fields', () {
      final encoded = const FastingSchedule().encode();
      expect(encoded, contains('"weekdays"'));
      expect(encoded, contains('"weekdayScope"'));
      expect(encoded, contains('"months"'));
      // Retired, but pinned for the builds before 2026-10-26 that still read
      // it: `allFasts` is the value under which they draw this engine's grid.
      expect(encoded, contains('"monthScope":"allFasts"'));
      expect(encoded, isNot(contains('"skip"')));
      expect(encoded, isNot(contains('"force"')));
    });
  });

  group('legacy weekday CSV', () {
    test('no raw and no legacy row yields the defaults', () {
      expect(FastingSchedule.decode(null), const FastingSchedule());
    });

    test('seeds the weekdays and nothing else', () {
      final schedule = FastingSchedule.decode(null, legacyWeekdayCsv: '3,5');
      expect(schedule.weekdays, {DateTime.wednesday, DateTime.friday});
      expect(schedule.months, FastingSchedule.allMonths);
    });

    test(
      'an empty CSV is a deliberate "no weekly fast", not a missing row',
      () {
        final cleared = FastingSchedule.decode(null, legacyWeekdayCsv: '');
        expect(cleared.weekdays, isEmpty);

        final absent = FastingSchedule.decode(null);
        expect(absent.weekdays, FastingSchedule.defaultWeekdays);
      },
    );

    test('drops unparseable and out-of-range parts', () {
      final schedule = FastingSchedule.decode(
        null,
        legacyWeekdayCsv: '1,banana,9,0,7',
      );
      expect(schedule.weekdays, {DateTime.monday, DateTime.sunday});
    });
  });

  group('corrupt input degrades instead of throwing', () {
    test('non-JSON falls back to the defaults', () {
      expect(FastingSchedule.decode('not json'), const FastingSchedule());
      expect(FastingSchedule.decode('{oops'), const FastingSchedule());
    });

    test('non-JSON still honours the legacy seed', () {
      final schedule = FastingSchedule.decode(
        'not json',
        legacyWeekdayCsv: '1',
      );
      expect(schedule.weekdays, {DateTime.monday});
    });

    test(
      'a blob carrying the retired monthScope key decodes and ignores it',
      () {
        final allFasts = FastingSchedule.decode(
          '{"months":[1,2],"monthScope":"allFasts"}',
        );
        final weeklyOnly = FastingSchedule.decode(
          '{"months":[1,2],"monthScope":"weeklyOnly"}',
        );
        expect(allFasts, weeklyOnly);
        expect(allFasts.months, {1, 2});
        expect(allFasts.weekdays, FastingSchedule.defaultWeekdays);
      },
    );

    test('an unknown weekday scope falls back to weeklyOnly', () {
      final schedule = FastingSchedule.decode(
        '{"weekdayScope":"someFutureScope"}',
      );
      expect(schedule.weekdayScope, FastingWeekdayScope.weeklyOnly);
      expect(schedule.weekdays, FastingSchedule.defaultWeekdays);
    });

    test(
      'a blob written before the weekday scope existed reads as weeklyOnly',
      () {
        // Forward compatibility in the other direction: the field must default
        // to today's behaviour, never silently narrow an existing practice.
        final schedule = FastingSchedule.decode(
          '{"weekdays":[3,5],"months":[1,2,3,4,5,6,7,8,9,10,11,12],'
          '"monthScope":"allFasts"}',
        );
        expect(schedule.weekdayScope, FastingWeekdayScope.weeklyOnly);
      },
    );

    test('absent is not the same as empty', () {
      final absent = FastingSchedule.decode('{"monthScope":"weeklyOnly"}');
      expect(absent.months, FastingSchedule.allMonths);
      expect(absent.weekdays, FastingSchedule.defaultWeekdays);

      final empty = FastingSchedule.decode('{"months":[],"weekdays":[]}');
      expect(empty.months, isEmpty);
      expect(empty.weekdays, isEmpty);
    });

    test('bad dates are dropped, good ones become UTC midnight', () {
      final schedule = FastingSchedule.decode(
        '{"skip":["2026-03-15","not-a-date",7,"2026-3-5"]}',
      );
      expect(schedule.skipDates, {_utc(2026, 3, 15)});
      expect(schedule.skipDates.single.isUtc, isTrue);
    });

    test('out-of-range dates are dropped, never rolled over', () {
      final schedule = FastingSchedule.decode(
        '{"skip":["2026-13-99","2026-02-30"]}',
      );
      expect(schedule.skipDates, isEmpty);
    });
  });

  group('normalization', () {
    test('a date in both sets ends up only in force', () {
      final schedule = FastingSchedule.decode(
        '{"skip":["2026-05-01"],"force":["2026-05-01"]}',
      );
      expect(schedule.forceDates, {_utc(2026, 5, 1)});
      expect(schedule.skipDates, isEmpty);
    });

    test('copyWith date-onlys local times and clamps out-of-range ints', () {
      final schedule = const FastingSchedule().copyWith(
        weekdays: {0, 1, 8},
        months: {0, 5, 13},
        skipDates: {DateTime(2026, 5, 1, 22, 30)},
      );
      expect(schedule.weekdays, {DateTime.monday});
      expect(schedule.months, {5});
      expect(schedule.skipDates, {_utc(2026, 5, 1)});
    });

    test('each exception set is capped, oldest kept', () {
      final many = {
        for (var i = 0; i < FastingSchedule.maxExceptionDates + 25; i++)
          _utc(2026, 1, 1).add(Duration(days: i)),
      };
      final schedule = const FastingSchedule().copyWith(skipDates: many);
      expect(schedule.skipDates.length, FastingSchedule.maxExceptionDates);
      expect(schedule.skipDates, contains(_utc(2026, 1, 1)));
      expect(
        schedule.skipDates,
        isNot(contains(_utc(2026, 1, 1).add(const Duration(days: 225)))),
      );
    });
  });

  group('keeps', () {
    final wednesday = _utc(2026, 2, 11);
    final monday = _utc(2026, 2, 9);

    setUpAll(() {
      expect(wednesday.weekday, DateTime.wednesday);
      expect(monday.weekday, DateTime.monday);
    });

    test('a month turned off refuses a weekly and a seasonal entry alike', () {
      for (final scope in FastingWeekdayScope.values) {
        final schedule = const FastingSchedule().copyWith(
          weekdayScope: scope,
          months: FastingSchedule.allMonths.difference({2}),
        );
        expect(schedule.keeps(wednesday, weeklyRule: true), isFalse);
        expect(schedule.keeps(wednesday, weeklyRule: false), isFalse);
      }
    });

    test('a kept weekday is kept under both scopes and both kinds', () {
      for (final scope in FastingWeekdayScope.values) {
        final schedule = FastingSchedule(weekdayScope: scope);
        expect(schedule.keeps(wednesday, weeklyRule: true), isTrue);
        expect(schedule.keeps(wednesday, weeklyRule: false), isTrue);
      }
    });

    test('an off weekday refuses a weekly entry under both scopes', () {
      for (final scope in FastingWeekdayScope.values) {
        final schedule = FastingSchedule(weekdayScope: scope);
        expect(schedule.keeps(monday, weeklyRule: true), isFalse);
      }
    });

    test('an off weekday keeps a seasonal entry under weeklyOnly only', () {
      const weeklyOnly = FastingSchedule();
      const allFasts = FastingSchedule(
        weekdayScope: FastingWeekdayScope.allFasts,
      );
      expect(weeklyOnly.keeps(monday, weeklyRule: false), isTrue);
      expect(allFasts.keeps(monday, weeklyRule: false), isFalse);
    });

    test('a skipped date is refused on a kept weekday in a kept month', () {
      final schedule = const FastingSchedule().copyWith(skipDates: {wednesday});
      expect(schedule.keeps(wednesday, weeklyRule: true), isFalse);
      expect(schedule.keeps(wednesday, weeklyRule: false), isFalse);
    });

    test('no weekdays under weeklyOnly refuses the weekly rule only', () {
      const schedule = FastingSchedule(weekdays: {});
      expect(schedule.keeps(wednesday, weeklyRule: true), isFalse);
      expect(schedule.keeps(wednesday, weeklyRule: false), isTrue);
    });

    test('no weekdays under allFasts refuses everything', () {
      const schedule = FastingSchedule(
        weekdays: {},
        weekdayScope: FastingWeekdayScope.allFasts,
      );
      expect(schedule.keeps(wednesday, weeklyRule: true), isFalse);
      expect(schedule.keeps(wednesday, weeklyRule: false), isFalse);
    });

    test('no months refuses everything', () {
      const schedule = FastingSchedule(months: {});
      for (final day in [wednesday, monday]) {
        expect(schedule.keeps(day, weeklyRule: true), isFalse);
        expect(schedule.keeps(day, weeklyRule: false), isFalse);
      }
    });
  });

  test('equality ignores set order — configure\'s no-op path rests on it', () {
    expect(
      const FastingSchedule(weekdays: {5, 3}),
      const FastingSchedule(weekdays: {3, 5}),
    );
    expect(
      const FastingSchedule(weekdays: {5, 3}).hashCode,
      const FastingSchedule(weekdays: {3, 5}).hashCode,
    );
    // …but the weekday scope is compute-affecting, so it must separate two
    // otherwise-equal schedules or `configure` would skip the invalidation.
    expect(
      const FastingSchedule(weekdayScope: FastingWeekdayScope.allFasts),
      isNot(const FastingSchedule()),
    );
  });
}
