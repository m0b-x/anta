import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/services/event_time_formatter.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/utils/digest_labels.dart';
import 'package:anta/utils/digest_notification_content.dart';
import 'package:anta/utils/digest_planner.dart';

/// The two formatters every digest surface reads: how a digest fires, and
/// what it is called — the latter the notification's own rule, so a row
/// and the notification it stops can never name one digest two ways.
/// Written for `en_US`, the one locale `intl` answers with no date symbols
/// loaded.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));
  final ro = lookupAppLocalizations(const Locale('ro'));

  String describe(
    EventDigest digest, {
    AppLocalizations? l10n,
    bool use24Hour = true,
  }) => digestDescribe(
    digest,
    l10n ?? en,
    formatMinute: (minute) => EventTimeFormatter.formatMinuteFor(
      minute,
      localeName: 'en_US',
      use24Hour: use24Hour,
    ),
    weekdayName: (weekday) => digestWeekdayName(weekday, 'en_US'),
  );

  group('digestDescribe', () {
    const daily = EventDigest(
      id: 'd',
      cadence: DigestCadence.daily,
      anchor: 0,
      minute: 7 * 60 + 30,
    );
    const weekly = EventDigest(
      id: 'w',
      cadence: DigestCadence.weekly,
      anchor: DateTime.sunday,
      minute: 20 * 60,
    );
    const monthly = EventDigest(id: 'm', anchor: 1, minute: 9 * 60);

    test('on the 24-hour clock', () {
      expect(describe(daily), 'Daily at 07:30');
      expect(describe(weekly), 'Weekly on Sunday, 20:00');
      expect(describe(monthly), 'Monthly on the 1st, 09:00');
    });

    test('a report says so, on the schedule it fires on', () {
      const weeklyReport = EventDigest(
        id: 'wr',
        cadence: DigestCadence.weeklyReport,
        anchor: DateTime.monday,
        minute: 8 * 60,
      );
      const monthlyReport = EventDigest(
        id: 'mr',
        cadence: DigestCadence.monthlyReport,
        anchor: 1,
        minute: 9 * 60,
      );

      expect(describe(weeklyReport), 'Weekly report on Monday, 08:00');
      expect(describe(monthlyReport), 'Monthly report on the 1st, 09:00');
      expect(describe(monthlyReport, l10n: de), 'Monatsbericht am 1., 09:00');
    });

    test('on the 12-hour clock', () {
      expect(describe(daily, use24Hour: false), 'Daily at 7:30 AM');
      expect(describe(weekly, use24Hour: false), 'Weekly on Sunday, 8:00 PM');
      expect(
        describe(monthly, use24Hour: false),
        'Monthly on the 1st, 9:00 AM',
      );
    });

    test('each language writes its own ordinal around the digits', () {
      String day(int n, AppLocalizations l10n) => digestDayOfMonth(n, l10n);

      expect(
        [
          for (final n in const [1, 2, 3, 4, 11, 21, 22, 23, 28]) day(n, en),
        ],
        ['1st', '2nd', '3rd', '4th', '11th', '21st', '22nd', '23rd', '28th'],
      );
      expect(day(1, de), '1.');
      expect(day(1, ro), '1');
      expect(describe(monthly, l10n: de), 'Monatlich am 1., 09:00');
      expect(describe(monthly, l10n: ro), 'Lunar, pe 1, la 09:00');
    });
  });

  group('digestTitleOf', () {
    String labelOf(String id) => switch (id) {
      'birthday' => 'Birthdays',
      _ => id,
    };

    String title(EventDigest digest) =>
        digestTitleOf(digest, en, categoryLabel: labelOf);

    test('the name, else what the allowlist lists', () {
      expect(
        title(const EventDigest(id: 'a', name: ' Week ahead ')),
        'Week ahead',
      );
      expect(title(const EventDigest(id: 'a')), 'Events');
      expect(
        title(const EventDigest(id: 'a', categoryIds: {'birthday'})),
        'Birthdays',
      );
      expect(
        title(const EventDigest(id: 'a', categoryIds: {'birthday', 'gym'})),
        '2 categories',
      );
    });

    test('is the title the notification carries', () {
      for (final digest in const [
        EventDigest(id: 'a', name: 'Week ahead'),
        EventDigest(id: 'a'),
        EventDigest(id: 'a', categoryIds: {'birthday'}),
        EventDigest(id: 'a', categoryIds: {'birthday', 'gym', 'work'}),
      ]) {
        final fire = PlannedDigest(
          digest: digest,
          fireAt: DateTime(2026, 10, 1, 9),
          spanStart: DateTime.utc(2026, 10, 1),
          spanEnd: DateTime.utc(2026, 10, 31),
          entries: const [],
        );
        final content = digestNotificationContent(
          fire,
          en,
          AlertLabels.fixed,
          categoryLabel: labelOf,
          weekStart: CalendarWeekStart.monday,
        );
        expect(content.title, title(digest));
      }
    });
  });
}
