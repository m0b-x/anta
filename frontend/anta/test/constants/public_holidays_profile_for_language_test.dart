import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/public_holidays.dart';

/// A fresh install starts on the holiday set of the language it opened in
/// (the onboarding's "Start fresh", 2026-10-30). Only the two app languages
/// that name a country map to one; an upgraded install never asks.
void main() {
  test('Romanian and German get their national sets', () {
    expect(PublicHolidays.profileForLanguage('ro'), HolidayProfile.romania);
    expect(PublicHolidays.profileForLanguage('de'), HolidayProfile.germany);
  });

  test('English and anything else keep the generic set', () {
    expect(PublicHolidays.profileForLanguage('en'), HolidayProfile.generic);
    expect(PublicHolidays.profileForLanguage('fr'), HolidayProfile.generic);
    expect(PublicHolidays.profileForLanguage(''), HolidayProfile.generic);
  });
}
