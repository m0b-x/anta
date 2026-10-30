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

  // D62: the guide's fasting card builds its own years and styles through
  // these; they must answer exactly what the configured facade answers.
  group('the pure seams', () {
    tearDown(FastingCalendar.resetConfiguration);

    List<(FastingTradition, FastingPeriod, FastingRegime)> entries(
      List<FastingInfo> infos,
    ) => [for (final info in infos) (info.tradition, info.period, info.regime)];

    final practice = const FastingSchedule().copyWith(
      weekdays: const {DateTime.wednesday},
      months: const {1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12},
      skipDates: {_d(2027, 3, 17)},
      forceDates: {_d(2027, 7, 6), _d(2027, 3, 18)},
    );

    for (final (name, traditions, greatFasts, schedule) in [
      (
        'every tradition, the multi-day fasts, the default practice',
        FastingTradition.values.toSet(),
        true,
        const FastingSchedule(),
      ),
      (
        'Orthodox and Catholic without the multi-day fasts, a practice of '
            'one weekday, a month off, a skipped and two forced days',
        const {FastingTradition.orthodox, FastingTradition.catholic},
        false,
        practice,
      ),
      (
        'Muslim and Jewish under the same practice',
        const {FastingTradition.muslim, FastingTradition.jewish},
        true,
        practice,
      ),
    ]) {
      test('computeYear equals the configured on() on every day: $name', () {
        FastingCalendar.configure(
          traditions: traditions,
          orthodoxGreatFasts: greatFasts,
          schedule: schedule,
        );
        for (final year in const [2027, 2028]) {
          final computed = FastingCalendar.computeYear(
            year,
            traditions: traditions,
            orthodoxGreatFasts: greatFasts,
            schedule: schedule,
          );
          var marked = 0;
          for (final day in _daysOf(year)) {
            final expected = entries(FastingCalendar.on(day));
            if (expected.isNotEmpty) marked++;
            expect(
              entries(computed[day] ?? const []),
              expected,
              reason: '$day',
            );
          }
          expect(computed.length, marked, reason: '$year holds no other day');
          expect(marked, greaterThan(0));
        }
      });
    }

    // What the pure build itself decides, without the facade.
    group('computeYear under a practice', () {
      const orthodoxOnly = {FastingTradition.orthodox};
      // A strict Wednesday of the Orthodox Great Lent of 2027.
      final lentWednesday = _d(2027, 3, 17);
      final noWednesday = const FastingSchedule().copyWith(
        weekdays: const {DateTime.friday},
      );

      test('Wednesday off under the all-fasts scope unmarks a Great Lent '
          'Wednesday; under the weekly scope it stays marked', () {
        final all = FastingCalendar.computeYear(
          2027,
          traditions: orthodoxOnly,
          schedule: noWednesday.copyWith(
            weekdayScope: FastingWeekdayScope.allFasts,
          ),
        );
        expect(all[lentWednesday], isNull);

        final weekly = FastingCalendar.computeYear(
          2027,
          traditions: orthodoxOnly,
          schedule: noWednesday.copyWith(
            weekdayScope: FastingWeekdayScope.weeklyOnly,
          ),
        );
        expect(entries(weekly[lentWednesday]!), [
          (
            FastingTradition.orthodox,
            FastingPeriod.greatLent,
            FastingRegime.strict,
          ),
        ]);
      });

      test('a month turned off holds no weekly fast day', () {
        final year = FastingCalendar.computeYear(
          2027,
          traditions: orthodoxOnly,
          schedule: const FastingSchedule().copyWith(
            months: {
              for (var month = 1; month <= 12; month++)
                if (month != DateTime.october) month,
            },
          ),
        );
        expect(
          year.keys.where((day) => day.month == DateTime.october),
          isEmpty,
        );
        // September keeps its Wednesdays.
        expect(
          entries(year[_d(2027, 9, 22)]!).single.$2,
          FastingPeriod.weekdayFast,
        );
      });

      test('a forced date outside every fast is a personal fast', () {
        // A Monday outside the long fasts: no Orthodox mark of its own.
        final monday = _d(2027, 10, 11);
        expect(
          FastingCalendar.computeYear(2027, traditions: orthodoxOnly)[monday],
          isNull,
        );
        final forced = FastingCalendar.computeYear(
          2027,
          traditions: orthodoxOnly,
          schedule: const FastingSchedule().copyWith(forceDates: {monday}),
        );
        expect(entries(forced[monday]!), [
          (
            FastingTradition.orthodox,
            FastingPeriod.personalFast,
            FastingRegime.oil,
          ),
        ]);
      });
    });

    test('computeYear neither reads nor moves the configuration', () {
      _configureOrthodox(greatFasts: true);
      final revision = FastingCalendar.revision;
      final configured = FastingCalendar.on(_d(2027, 3, 10));

      final muslim = FastingCalendar.computeYear(
        2027,
        traditions: const {FastingTradition.muslim},
      );

      expect(muslim.values.expand((infos) => infos).map((i) => i.tradition), {
        FastingTradition.muslim,
      });
      expect(FastingCalendar.revision, revision);
      expect(FastingCalendar.traditions, {FastingTradition.orthodox});
      expect(entries(FastingCalendar.on(_d(2027, 3, 10))), entries(configured));
    });

    test('resolveCellStyle equals cellStyleForUtcDay for a marked day', () {
      const red = 0xFFE53935;
      const blue = 0xFF1E88E5;
      final appearance = const FastingAppearance()
          .withStyle(
            FastingTradition.orthodox,
            const FastingTraditionStyle(
              style: FastingDisplayStyle.strong,
              colorValue: red,
            ),
          )
          .withStyle(
            FastingTradition.catholic,
            const FastingTraditionStyle(colorValue: blue),
          );
      FastingCalendar.configure(
        traditions: const {
          FastingTradition.orthodox,
          FastingTradition.catholic,
        },
        appearance: appearance,
      );
      // A Friday of 2027's Catholic Lent, an Orthodox weekly fast day: one
      // entry for each tradition, each asking for its own slot.
      final day = _d(2027, 3, 12);
      expect(FastingCalendar.on(day), hasLength(2));

      final resolved = FastingCalendar.resolveCellStyle(
        FastingCalendar.on(day),
        appearance,
      );
      final configured = FastingCalendar.cellStyleForUtcDay(day);
      expect(resolved.tint, const Color(blue));
      expect(resolved.numberColor, const Color(red));
      expect(resolved.tint, configured.tint);
      expect(resolved.numberColor, configured.numberColor);
      expect(
        FastingCalendar.resolveCellStyle(const [], appearance).isEmpty,
        isTrue,
      );
    });

    test('the facade lookup reads the configured look', () {
      const green = 0xFF43A047;
      final appearance = const FastingAppearance().withStyle(
        FastingTradition.muslim,
        const FastingTraditionStyle(colorValue: green, iconKey: 'star'),
      );
      FastingCalendar.configure(
        traditions: const {FastingTradition.muslim},
        appearance: appearance,
      );
      const lookup = FastingLookup.facade;
      expect(lookup.appearance, appearance);
      expect(lookup.colorOf(FastingTradition.muslim), const Color(green));
      expect(
        lookup.colorOf(FastingTradition.muslim),
        FastingCalendar.colorOf(FastingTradition.muslim),
      );
      expect(
        lookup.iconFor(FastingTradition.muslim),
        FastingCalendar.iconFor(FastingTradition.muslim),
      );
      expect(
        lookup.iconFor(FastingTradition.jewish),
        FastingCalendar.defaultIconOf(FastingTradition.jewish),
      );
    });
  });
}
