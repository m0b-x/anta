import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/utils/liturgical_computus.dart';

DateTime _d(int year, int month, int day) => DateTime.utc(year, month, day);

List<FastingPeriod> _periodsOn(DateTime day) =>
    FastingCalendar.on(day).map((info) => info.period).toList();

/// Every day of [year], so a test can assert about a whole year rather than
/// about dates it had to look up by hand.
Iterable<DateTime> _daysOf(int year) sync* {
  for (
    var day = _d(year, 1, 1);
    day.year == year;
    day = day.add(const Duration(days: 1))
  ) {
    yield day;
  }
}

void _configureOrthodox({
  FastingSchedule schedule = const FastingSchedule(),
  bool greatFasts = false,
}) {
  FastingCalendar.configure(
    traditions: const {FastingTradition.orthodox},
    orthodoxGreatFasts: greatFasts,
    schedule: schedule,
  );
}

void _configureCatholic({FastingSchedule schedule = const FastingSchedule()}) {
  FastingCalendar.configure(
    traditions: const {FastingTradition.catholic},
    schedule: schedule,
  );
}

void main() {
  // A static facade: without this, one test's configuration leaks into the
  // next. Doubles as coverage of the DatabaseLifecycle reset hook.
  setUp(FastingCalendar.resetConfiguration);

  final pascha2026 = LiturgicalComputus.easterSundayOrthodox(2026);
  final easter2026 = LiturgicalComputus.easterSundayGregorian(2026);

  group('weekly rule', () {
    test('marks the configured days and nothing else', () {
      _configureOrthodox();
      expect(_d(2026, 1, 14).weekday, DateTime.wednesday);
      expect(_periodsOn(_d(2026, 1, 14)), [FastingPeriod.weekdayFast]);
      expect(_periodsOn(_d(2026, 1, 16)), [FastingPeriod.weekdayFast]);
      expect(_periodsOn(_d(2026, 1, 15)), isEmpty);
    });

    test('an empty weekday set leaves the whole year unmarked', () {
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(weekdays: const {}),
      );
      for (final day in _daysOf(2026)) {
        expect(FastingCalendar.on(day), isEmpty, reason: '$day');
      }
    });

    test('follows a non-traditional day set', () {
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(
          weekdays: const {DateTime.monday},
        ),
      );
      expect(_d(2026, 1, 12).weekday, DateTime.monday);
      expect(_periodsOn(_d(2026, 1, 12)), [FastingPeriod.weekdayFast]);
      expect(_periodsOn(_d(2026, 1, 14)), isEmpty);
    });

    test('fast-free weeks still suspend it', () {
      _configureOrthodox();
      final brightWednesday = pascha2026.add(const Duration(days: 3));
      expect(brightWednesday.weekday, DateTime.wednesday);
      expect(FastingCalendar.on(brightWednesday), isEmpty);
    });

    test('never overwrites a great fast', () {
      _configureOrthodox(greatFasts: true);
      final lentWednesday = pascha2026.subtract(const Duration(days: 46));
      expect(lentWednesday.weekday, DateTime.wednesday);
      expect(_periodsOn(lentWednesday), [FastingPeriod.greatLent]);
    });
  });

  group('months', () {
    test('a month turned off is never marked, whatever the fast', () {
      // The owner's case (2026-10-26): Monday and Saturday in every month but
      // December, with the great fasts on. The Nativity fast used to fill
      // December under the retired month scope's default.
      _configureOrthodox(
        greatFasts: true,
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.monday, DateTime.saturday},
          months: FastingSchedule.allMonths.difference({12}),
        ),
      );
      for (final day in _daysOf(2026).where((day) => day.month == 12)) {
        expect(FastingCalendar.on(day), isEmpty, reason: '$day');
      }
      expect(_periodsOn(_d(2026, 11, 20)), [FastingPeriod.nativityFast]);
      expect(_d(2026, 11, 2).weekday, DateTime.monday);
      expect(_periodsOn(_d(2026, 11, 2)), [FastingPeriod.weekdayFast]);
    });

    test('a disabled month drops the weekly fast there only', () {
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(
          months: FastingSchedule.allMonths.where((m) => m != 1).toSet(),
        ),
      );
      for (final day in _daysOf(2026).where((day) => day.month == 1)) {
        expect(FastingCalendar.on(day), isEmpty, reason: '$day');
      }
      // A February Wednesday clear of the Publican & Pharisee fast-free week
      // (Pascha−69, which covers Feb 2–8 in 2026).
      expect(_d(2026, 2, 11).weekday, DateTime.wednesday);
      expect(_periodsOn(_d(2026, 2, 11)), [FastingPeriod.weekdayFast]);
    });

    test('no months at all blanks the year — a legitimate state', () {
      _configureOrthodox(
        greatFasts: true,
        schedule: const FastingSchedule().copyWith(months: const {}),
      );
      for (final day in _daysOf(2026)) {
        expect(FastingCalendar.on(day), isEmpty, reason: '$day');
      }
    });

    test('a forced date still wins in a month turned off', () {
      _configureOrthodox(
        greatFasts: true,
        schedule: const FastingSchedule().copyWith(
          months: FastingSchedule.allMonths.difference({12}),
          forceDates: {_d(2026, 12, 10)},
        ),
      );
      expect(_periodsOn(_d(2026, 12, 10)), [FastingPeriod.personalFast]);
      for (final day in _daysOf(2026).where((day) => day.month == 12)) {
        if (day == _d(2026, 12, 10)) continue;
        expect(FastingCalendar.on(day), isEmpty, reason: '$day');
      }
    });

    test('a month turned off silences the Catholic Friday abstinence', () {
      _configureCatholic(
        schedule: const FastingSchedule().copyWith(
          months: FastingSchedule.allMonths.difference({7}),
        ),
      );
      expect(_d(2026, 7, 3).weekday, DateTime.friday);
      expect(FastingCalendar.on(_d(2026, 7, 3)), isEmpty);
      expect(_d(2026, 8, 7).weekday, DateTime.friday);
      expect(_periodsOn(_d(2026, 8, 7)), [FastingPeriod.fridayAbstinence]);
    });

    test('a month turned off gates the traditions without a weekly rule', () {
      // Ramadan and the Jewish fasts have no weekly rule, so the month set is
      // the only part of the practice that reaches them. The marked days come
      // from an all-months run rather than from a date looked up by hand.
      FastingCalendar.configure(
        traditions: const {FastingTradition.muslim, FastingTradition.jewish},
      );
      final marked = _daysOf(2026).where(FastingCalendar.isFastingDay).toList();
      expect(marked, isNotEmpty);
      final offMonth = marked.first.month;
      FastingCalendar.configure(
        traditions: const {FastingTradition.muslim, FastingTradition.jewish},
        schedule: const FastingSchedule().copyWith(
          months: FastingSchedule.allMonths.difference({offMonth}),
        ),
      );
      for (final day in marked) {
        expect(
          FastingCalendar.on(day),
          day.month == offMonth ? isEmpty : isNotEmpty,
          reason: '$day',
        );
      }
    });
  });

  group('weekday scope', () {
    // Clean Monday opens Great Lent, so these two are Lenten days of known
    // weekday without hard-coding a date the computus owns.
    final lentenWednesday = pascha2026.subtract(const Duration(days: 46));
    final lentenThursday = pascha2026.subtract(const Duration(days: 45));

    FastingSchedule wedFri({
      FastingWeekdayScope scope = FastingWeekdayScope.weeklyOnly,
    }) => const FastingSchedule().copyWith(
      weekdays: {DateTime.wednesday, DateTime.friday},
      weekdayScope: scope,
    );

    test('weeklyOnly leaves a great fast on every one of its days', () {
      // Pins today's behaviour explicitly: the default scope gates only the
      // year-round weekly rule, so Lent keeps its Thursdays.
      _configureOrthodox(greatFasts: true, schedule: wedFri());
      expect(lentenThursday.weekday, DateTime.thursday);
      expect(_periodsOn(lentenThursday), [FastingPeriod.greatLent]);
    });

    test('allFasts drops a great fast day on an off weekday', () {
      _configureOrthodox(
        greatFasts: true,
        schedule: wedFri(scope: FastingWeekdayScope.allFasts),
      );
      expect(FastingCalendar.on(lentenThursday), isEmpty);
    });

    test('allFasts keeps the great fast itself on a kept weekday', () {
      // Subtract-only: a kept Wednesday still belongs to Lent, and must not
      // degrade into the generic weekly fast.
      _configureOrthodox(
        greatFasts: true,
        schedule: wedFri(scope: FastingWeekdayScope.allFasts),
      );
      expect(lentenWednesday.weekday, DateTime.wednesday);
      expect(_periodsOn(lentenWednesday), [FastingPeriod.greatLent]);
    });

    test('allFasts composes with a kept month without inventing days', () {
      _configureOrthodox(
        greatFasts: true,
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.wednesday, DateTime.friday},
          weekdayScope: FastingWeekdayScope.allFasts,
        ),
      );
      // December is kept, so the Nativity Fast survives on its Wednesdays…
      expect(_d(2026, 12, 2).weekday, DateTime.wednesday);
      expect(_periodsOn(_d(2026, 12, 2)), [FastingPeriod.nativityFast]);
      // …and nowhere else. Every marked day of the year is a Wed or a Fri.
      for (final day in _daysOf(2026)) {
        if (FastingCalendar.on(day).isEmpty) continue;
        expect(
          {DateTime.wednesday, DateTime.friday},
          contains(day.weekday),
          reason: '$day',
        );
      }
    });

    test('a forced date still wins on an off weekday', () {
      _configureOrthodox(
        greatFasts: true,
        schedule: const FastingSchedule().copyWith(
          weekdays: {DateTime.wednesday, DateTime.friday},
          weekdayScope: FastingWeekdayScope.allFasts,
          forceDates: {lentenThursday},
        ),
      );
      expect(_periodsOn(lentenThursday), [FastingPeriod.personalFast]);
    });
  });

  group('catholic weekly rule is subtract-only', () {
    test('keeps Friday abstinence outside Lent and Advent by default', () {
      _configureCatholic();
      expect(_d(2026, 7, 3).weekday, DateTime.friday);
      expect(_periodsOn(_d(2026, 7, 3)), [FastingPeriod.fridayAbstinence]);
    });

    test('dropping Friday silences it without inventing another day', () {
      _configureCatholic(
        schedule: const FastingSchedule().copyWith(
          weekdays: const {DateTime.wednesday},
        ),
      );
      for (final day in _daysOf(2026)) {
        expect(
          _periodsOn(day),
          isNot(contains(FastingPeriod.fridayAbstinence)),
          reason: '$day',
        );
      }
      expect(_d(2026, 7, 1).weekday, DateTime.wednesday);
      expect(FastingCalendar.on(_d(2026, 7, 1)), isEmpty);
    });

    test('seasonal fasts are not the weekly rule and always survive', () {
      _configureCatholic(
        schedule: const FastingSchedule().copyWith(weekdays: const {}),
      );
      final goodFriday = easter2026.subtract(const Duration(days: 2));
      final ashWednesday = easter2026.subtract(const Duration(days: 46));
      expect(_periodsOn(goodFriday), [FastingPeriod.goodFriday]);
      expect(_periodsOn(ashWednesday), [FastingPeriod.ashWednesday]);
      expect(_periodsOn(ashWednesday.add(const Duration(days: 1))), [
        FastingPeriod.lent,
      ]);
    });

    test('allFasts with Friday off drops the seasonal Fridays too', () {
      // The Friday loop runs unconditionally since 2026-10-26; what drops a
      // Friday is `keeps`, and under allFasts it drops Lent's as well.
      _configureCatholic(
        schedule: const FastingSchedule().copyWith(
          weekdays: const {DateTime.wednesday},
          weekdayScope: FastingWeekdayScope.allFasts,
        ),
      );
      final lentFriday = easter2026.subtract(const Duration(days: 9));
      final lentWednesday = easter2026.subtract(const Duration(days: 11));
      expect(lentFriday.weekday, DateTime.friday);
      expect(lentWednesday.weekday, DateTime.wednesday);
      expect(FastingCalendar.on(lentFriday), isEmpty);
      expect(
        FastingCalendar.on(easter2026.subtract(const Duration(days: 2))),
        isEmpty,
      );
      expect(_periodsOn(lentWednesday), [FastingPeriod.lent]);
    });
  });

  group('exception dates', () {
    test('a skip removes a computed day outright', () {
      final lentWednesday = pascha2026.subtract(const Duration(days: 46));
      _configureOrthodox(
        greatFasts: true,
        schedule: const FastingSchedule().copyWith(skipDates: {lentWednesday}),
      );
      expect(FastingCalendar.on(lentWednesday), isEmpty);
      expect(_periodsOn(lentWednesday.add(const Duration(days: 1))), [
        FastingPeriod.greatLent,
      ]);
    });

    test('a skip on an unmarked day is a no-op', () {
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(
          skipDates: {_d(2026, 1, 15)},
        ),
      );
      expect(FastingCalendar.on(_d(2026, 1, 15)), isEmpty);
      expect(_periodsOn(_d(2026, 1, 14)), [FastingPeriod.weekdayFast]);
      expect(_periodsOn(_d(2026, 1, 16)), [FastingPeriod.weekdayFast]);
    });

    test('a force marks an unmarked day for the first enabled tradition', () {
      final tuesday = _d(2026, 7, 7);
      expect(tuesday.weekday, DateTime.tuesday);
      FastingCalendar.configure(
        traditions: const {
          FastingTradition.orthodox,
          FastingTradition.catholic,
        },
        orthodoxGreatFasts: false,
        schedule: const FastingSchedule().copyWith(forceDates: {tuesday}),
      );
      final infos = FastingCalendar.on(tuesday);
      expect(infos, hasLength(1));
      expect(infos.single.period, FastingPeriod.personalFast);
      expect(infos.single.regime, FastingRegime.oil);
      expect(infos.single.tradition, FastingTradition.orthodox);
    });

    test('the owner follows which traditions are enabled', () {
      final tuesday = _d(2026, 7, 7);
      _configureCatholic(
        schedule: const FastingSchedule().copyWith(forceDates: {tuesday}),
      );
      expect(
        FastingCalendar.on(tuesday).single.tradition,
        FastingTradition.catholic,
      );
    });

    test('a force on an already-marked day does not duplicate it', () {
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(
          forceDates: {_d(2026, 1, 14)},
        ),
      );
      final infos = FastingCalendar.on(_d(2026, 1, 14));
      expect(infos, hasLength(1));
      expect(infos.single.period, FastingPeriod.weekdayFast);
    });

    test('nothing is forced while no tradition is enabled', () {
      FastingCalendar.configure(
        traditions: const {},
        schedule: const FastingSchedule().copyWith(
          forceDates: {_d(2026, 7, 7)},
        ),
      );
      expect(FastingCalendar.on(_d(2026, 7, 7)), isEmpty);
    });
  });

  group('configure invalidation', () {
    test('an equal schedule keeps the warm year map', () {
      _configureOrthodox();
      final first = FastingCalendar.on(_d(2026, 1, 14));
      _configureOrthodox(
        schedule: const FastingSchedule(
          weekdays: {DateTime.friday, DateTime.wednesday},
        ),
      );
      expect(identical(FastingCalendar.on(_d(2026, 1, 14)), first), isTrue);
    });

    test('a changed month set invalidates it', () {
      _configureOrthodox();
      expect(_periodsOn(_d(2026, 1, 14)), [FastingPeriod.weekdayFast]);
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(
          months: FastingSchedule.allMonths.where((m) => m != 1).toSet(),
        ),
      );
      expect(FastingCalendar.on(_d(2026, 1, 14)), isEmpty);
    });

    test('an appearance-only change keeps it warm but restyles the cell', () {
      _configureOrthodox();
      final first = FastingCalendar.on(_d(2026, 1, 14));
      const red = 0xFFFF0000;
      FastingCalendar.configure(
        traditions: const {FastingTradition.orthodox},
        appearance: const FastingAppearance(
          byTradition: {
            FastingTradition.orthodox: FastingTraditionStyle(colorValue: red),
          },
        ),
        orthodoxGreatFasts: false,
      );
      expect(identical(FastingCalendar.on(_d(2026, 1, 14)), first), isTrue);
      expect(
        FastingCalendar.cellStyleFor(_d(2026, 1, 14)).tint,
        const Color(red),
      );
    });
  });

  group('cellStyleFor eviction', () {
    test(
      'filling past the cap does not lose an earlier still-relevant day',
      () {
        _configureOrthodox(greatFasts: true);

        // Padding inserted first, so the target below is not itself among the
        // oldest entries once the cap is crossed — a FIFO always sacrifices
        // its oldest entries, so a target inserted with no padding ahead of it
        // would be evicted by *any* bounded scheme, which is correct, not a
        // bug this test should catch.
        for (var i = 0; i < 500; i++) {
          FastingCalendar.cellStyleFor(_d(1950, 1, 1).add(Duration(days: i)));
        }

        final lentenWednesday = pascha2026.subtract(const Duration(days: 46));
        final first = FastingCalendar.cellStyleFor(lentenWednesday);
        // A real, freshly-allocated style (not the `FastingCellStyle.empty`
        // const singleton every empty day shares) — otherwise `same(first)`
        // below would pass even after a wholesale clear-and-recompute, since
        // every empty result is `identical` to every other.
        expect(first.isEmpty, isFalse);

        // Cross `_cellCacheCap` (512) by a margin far smaller than the padding
        // above. A wholesale clear-on-overflow (the old bug) wipes every entry
        // the moment the cap is crossed at all, regardless of margin; a
        // bounded FIFO evicts only that many of the *oldest* entries — the
        // padding, never the target that was inserted after all of it.
        for (var i = 500; i < 520; i++) {
          FastingCalendar.cellStyleFor(_d(1950, 1, 1).add(Duration(days: i)));
        }

        expect(
          FastingCalendar.cellStyleFor(lentenWednesday),
          same(first),
          reason:
              'cellStyleFor must evict one entry at a time, never clear the '
              'whole cache from inside the lookup',
        );
      },
    );
  });

  group('resetConfiguration', () {
    test('drops the configuration and both caches', () {
      _configureOrthodox();
      expect(FastingCalendar.isEnabled, isTrue);
      expect(FastingCalendar.on(_d(2026, 1, 14)), isNotEmpty);

      FastingCalendar.resetConfiguration();

      expect(FastingCalendar.isEnabled, isFalse);
      expect(FastingCalendar.schedule, const FastingSchedule());
      expect(FastingCalendar.on(_d(2026, 1, 14)), isEmpty);
      expect(FastingCalendar.cellStyleFor(_d(2026, 1, 14)).isEmpty, isTrue);
    });

    test('a later configure answers from the new configuration', () {
      _configureOrthodox();
      FastingCalendar.resetConfiguration();
      _configureOrthodox(
        schedule: const FastingSchedule().copyWith(
          weekdays: const {DateTime.monday},
        ),
      );
      expect(FastingCalendar.on(_d(2026, 1, 14)), isEmpty);
      expect(_periodsOn(_d(2026, 1, 12)), [FastingPeriod.weekdayFast]);
    });
  });

  group('cellStyleForUtcDay (5.4)', () {
    test('agrees with the normalizing entry point', () {
      _configureOrthodox();
      // A local-time instant with a wall clock, the shape the grid hands in.
      final wall = DateTime(2026, 1, 14, 13, 45);
      final key = _d(2026, 1, 14);

      expect(
        FastingCalendar.cellStyleForUtcDay(key),
        FastingCalendar.cellStyleFor(wall),
      );
    });

    test('rejects a day that is not date-only UTC', () {
      // The grid's fast path trusts its caller, so the assert is the contract.
      _configureOrthodox();
      expect(
        () => FastingCalendar.cellStyleForUtcDay(DateTime(2026, 1, 14, 13)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('an unconfigured calendar is empty either way', () {
      FastingCalendar.resetConfiguration();
      expect(
        FastingCalendar.cellStyleForUtcDay(_d(2026, 1, 14)).isEmpty,
        isTrue,
      );
      expect(FastingCalendar.cellStyleFor(_d(2026, 1, 14)).isEmpty, isTrue);
    });
  });
}
