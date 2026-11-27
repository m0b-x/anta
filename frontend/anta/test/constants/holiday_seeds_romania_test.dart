import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/public_holidays.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/recurrence_rule.dart';

/// The Romania profile's January against the law
/// (`docs/religious-calendar-roadmap.md` §2.2, D6): the Labour Code's "1 și 2
/// ianuarie", and Theophany and Saint John from 2024, when Legea 52/2023
/// first applied. The Patriarchate's official calendar flags all three as
/// days off in 2025 and 2026; the profile carried none of them.
///
/// A public holiday is a day off for the app too: the workdays recurrence
/// skips it, and with it the alarm of a workdays event. So the cases below
/// pin both sides — the days that entered, and a feast that is no day off.
void main() {
  PublicHoliday? on(int year, int month, int day) => HolidaySeeds.forYear(
    HolidayProfile.romania,
    year,
  )[DateTime.utc(year, month, day)]?.holiday;

  test('2 January is a day off in every year', () {
    for (final year in [1995, 2016, 2023, 2026, 2040]) {
      expect(on(year, 1, 2), PublicHoliday.dayAfterNewYear, reason: '$year');
      expect(on(year, 1, 1), PublicHoliday.newYear, reason: '$year');
    }
  });

  test('Theophany and Saint John are days off from 2024 on', () {
    for (final year in [2024, 2025, 2026, 2040]) {
      expect(on(year, 1, 6), PublicHoliday.epiphany, reason: '$year');
      expect(on(year, 1, 7), PublicHoliday.stJohnTheBaptist, reason: '$year');
    }
  });

  test('and were ordinary days before the law applied', () {
    for (final year in [2016, 2022, 2023]) {
      expect(on(year, 1, 6), isNull, reason: '$year');
      expect(on(year, 1, 7), isNull, reason: '$year');
    }
  });

  test('no other profile gained a day', () {
    for (final profile in HolidayProfile.values) {
      if (profile == HolidayProfile.romania) continue;
      final holidays = HolidaySeeds.forYear(profile, 2026).values;
      expect(
        holidays.map((occurrence) => occurrence.holiday),
        isNot(
          anyOf(
            contains(PublicHoliday.dayAfterNewYear),
            contains(PublicHoliday.stJohnTheBaptist),
          ),
        ),
        reason: profile.name,
      );
    }
  });

  test('the two new days are named in the three languages', () {
    final en = AppLocalizationsEn();
    final de = AppLocalizationsDe();
    final ro = AppLocalizationsRo();

    expect(
      PublicHolidays.nameOf(PublicHoliday.dayAfterNewYear, ro),
      'A doua zi de Anul Nou',
    );
    expect(
      PublicHolidays.nameOf(PublicHoliday.stJohnTheBaptist, ro),
      'Sfântul Ioan Botezătorul',
    );
    for (final l10n in [en, de]) {
      for (final holiday in [
        PublicHoliday.dayAfterNewYear,
        PublicHoliday.stJohnTheBaptist,
      ]) {
        expect(PublicHolidays.nameOf(holiday, l10n), isNotEmpty);
      }
    }
  });

  group('a workdays event under the Romania profile', () {
    const rule = WorkdaysRecurrence();
    final start = DateTime.utc(2020, 1, 1);

    setUp(
      () => PublicHolidays.configure(
        profile: HolidayProfile.romania,
        overrides: const {},
        suppressed: const {},
      ),
    );

    tearDown(PublicHolidays.resetCache);

    bool occurs(int year, int month, int day) =>
        rule.occursOn(DateTime.utc(year, month, day), start);

    test('skips Friday 2, Tuesday 6 and Wednesday 7 January 2026', () {
      expect(occurs(2026, 1, 2), isFalse);
      expect(occurs(2026, 1, 5), isTrue);
      expect(occurs(2026, 1, 6), isFalse);
      expect(occurs(2026, 1, 7), isFalse);
      expect(occurs(2026, 1, 8), isTrue);
    });

    test('still occurs on Thursday 6 and Friday 7 January 2022, before '
        'the law', () {
      expect(occurs(2022, 1, 6), isTrue);
      expect(occurs(2022, 1, 7), isTrue);
    });

    test('occurs on Saint Nicholas, a feast that is no day off: Monday 6 '
        'December 2027', () {
      expect(occurs(2027, 12, 6), isTrue);
    });
  });
}
