import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/fasting_schedule.dart';

DateTime _utc(int year, int month, int day) => DateTime.utc(year, month, day);

void main() {
  group('defaults', () {
    test('is Wednesday + Friday, every month, weekly scope, no exceptions', () {
      const schedule = FastingSchedule();
      expect(schedule.weekdays, {DateTime.wednesday, DateTime.friday});
      expect(schedule.months, FastingSchedule.allMonths);
      expect(schedule.monthScope, FastingMonthScope.weeklyOnly);
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
        months: {1, 6, 12},
        monthScope: FastingMonthScope.allFasts,
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
      expect(encoded, contains('"months"'));
      expect(encoded, contains('"monthScope"'));
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
      expect(schedule.monthScope, FastingMonthScope.weeklyOnly);
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

    test('an unknown month scope falls back to weeklyOnly', () {
      final schedule = FastingSchedule.decode(
        '{"monthScope":"someFutureScope"}',
      );
      expect(schedule.monthScope, FastingMonthScope.weeklyOnly);
      expect(schedule.weekdays, FastingSchedule.defaultWeekdays);
      expect(schedule.months, FastingSchedule.allMonths);
    });

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

  test('equality ignores set order — configure\'s no-op path rests on it', () {
    expect(
      const FastingSchedule(weekdays: {5, 3}),
      const FastingSchedule(weekdays: {3, 5}),
    );
    expect(
      const FastingSchedule(weekdays: {5, 3}).hashCode,
      const FastingSchedule(weekdays: {3, 5}).hashCode,
    );
  });
}
