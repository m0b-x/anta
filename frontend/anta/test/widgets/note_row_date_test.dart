import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/widgets/note_row.dart';

/// What a row says about when a note was last touched.
///
/// [formatRowDate] takes `now` rather than reading a clock, which is the only
/// reason the boundaries below can be pinned: every case here is a fixed pair
/// of instants, so none of them turns into a different answer overnight.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final now = DateTime(2026, 9, 7, 14, 30);

  String format(DateTime date, String locale, AppLocalizations l10n) =>
      formatRowDate(date: date, now: now, locale: locale, l10n: l10n);

  final locales = <String, AppLocalizations>{
    'en': AppLocalizationsEn(),
    'de': AppLocalizationsDe(),
    'ro': AppLocalizationsRo(),
  };

  group('the near past is named, not dated', () {
    for (final entry in locales.entries) {
      test('${entry.key}: today and yesterday', () {
        final l10n = entry.value;
        expect(format(DateTime(2026, 9, 7, 0, 1), entry.key, l10n), l10n.today);
        expect(format(now, entry.key, l10n), l10n.today);
        expect(
          format(DateTime(2026, 9, 6, 23, 59), entry.key, l10n),
          l10n.yesterday,
        );
      });
    }

    test('en says Today and Yesterday', () {
      final l10n = AppLocalizationsEn();
      expect(format(now, 'en', l10n), 'Today');
      expect(format(DateTime(2026, 9, 6), 'en', l10n), 'Yesterday');
    });

    test('de says Heute and Gestern', () {
      final l10n = AppLocalizationsDe();
      expect(format(now, 'de', l10n), 'Heute');
      expect(format(DateTime(2026, 9, 6), 'de', l10n), 'Gestern');
    });

    test('ro says Azi and Ieri', () {
      final l10n = AppLocalizationsRo();
      expect(format(now, 'ro', l10n), 'Azi');
      expect(format(DateTime(2026, 9, 6), 'ro', l10n), 'Ieri');
    });
  });

  group('two to six days back is a weekday name', () {
    test('en', () {
      final l10n = AppLocalizationsEn();
      // 2026-09-05 is a Saturday, 2026-09-01 a Tuesday.
      expect(format(DateTime(2026, 9, 5), 'en', l10n), 'Sat');
      expect(format(DateTime(2026, 9, 1), 'en', l10n), 'Tue');
    });

    test('de and ro name the same days in their own words', () {
      expect(format(DateTime(2026, 9, 5), 'de', AppLocalizationsDe()), 'Sa');
      expect(
        format(DateTime(2026, 9, 1), 'ro', AppLocalizationsRo()),
        'mar.',
      );
    });

    test('the sixth day back is still a weekday, the seventh a date', () {
      final l10n = AppLocalizationsEn();
      expect(format(DateTime(2026, 9, 1), 'en', l10n), 'Tue');
      expect(format(DateTime(2026, 8, 31), 'en', l10n), isNot('Mon'));
    });
  });

  group('older than a week is a date', () {
    test('this year drops the year', () {
      final l10n = AppLocalizationsEn();
      expect(format(DateTime(2026, 8, 31), 'en', l10n), 'Aug 31');
      expect(format(DateTime(2026, 1, 4), 'en', l10n), 'Jan 4');
    });

    test('another year keeps it', () {
      final l10n = AppLocalizationsEn();
      expect(format(DateTime(2025, 12, 31), 'en', l10n), 'Dec 31, 2025');
    });

    test('a future date never says Today', () {
      final l10n = AppLocalizationsEn();
      expect(format(DateTime(2026, 9, 8), 'en', l10n), 'Sep 8');
      expect(format(DateTime(2027, 1, 1), 'en', l10n), 'Jan 1, 2027');
    });
  });
}
