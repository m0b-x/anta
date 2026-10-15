import 'dart:ui' show Locale;

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/utils/alert_labels.dart';

/// The labels are the only place an alert's times and days become text: a
/// notification is frozen when it is armed and the reminder's Snooze runs
/// where nothing can format, so a line that is wrong here is wrong on every
/// surface until the entry is armed again.
///
/// Every instant is built in the constructor form, `DateTime(y, m, d, 0,
/// minutes)`: it is wall-clock time, and adding a `Duration` to local
/// midnight lands an hour off on the day the clocks change.
///
/// **The date tables are the running app's.** `main()` loads `intl`'s, and
/// the app's first `MaterialApp` writes Flutter's over them for every
/// language Flutter ships — while the lock resolves another `intl` on each
/// of the owner's machines. Loaded the same way here, a literal below is
/// what a phone writes rather than what one machine's `intl` would.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    for (final locale in AppLocalizations.supportedLocales) {
      await GlobalMaterialLocalizations.delegate.load(locale);
    }
  });

  AlertLabels labelsOf(String language, {required bool use24Hour}) =>
      AlertLabels(
        strings: lookupAppLocalizations(Locale(language)),
        use24Hour: use24Hour,
      );

  // A phone on the 24-hour clock, in each language the app ships…
  final english = labelsOf('en', use24Hour: true);
  final german = labelsOf('de', use24Hour: true);
  final romanian = labelsOf('ro', use24Hour: true);
  // …and one that is not.
  final twelveHour = labelsOf('en', use24Hour: false);

  final sunday = DateTime.utc(2026, 9, 20);
  final monday = DateTime.utc(2026, 9, 21);

  DateTime at(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day, 0, minute);

  const sixPm = 18 * 60;
  const point = EventTime(startMinute: sixPm);
  const session = EventTime(startMinute: sixPm, durationMinutes: 90);

  group("the event's own time", () {
    test('a range is written whole, even on an alert at its start', () {
      // The end is news the due time does not carry.
      final due = at(sunday, sixPm);

      expect(
        english.whenLabel(time: session, day: sunday, fireAt: due),
        '18:00 – 19:30',
      );
    });

    test('a single time is written when the alert comes ahead of it', () {
      final due = at(sunday, sixPm - 10);

      expect(english.whenLabel(time: point, day: sunday, fireAt: due), '18:00');
    });

    test('an all-day event says so, in the language of the labels', () {
      final due = at(sunday, 9 * 60);

      expect(
        english.whenLabel(time: null, day: sunday, fireAt: due),
        'All day',
      );
      expect(
        german.whenLabel(time: null, day: sunday, fireAt: due),
        'Ganztägig',
      );
      expect(
        romanian.whenLabel(time: null, day: sunday, fireAt: due),
        'Toată ziua',
      );
    });

    test('a range past midnight keeps the mark the detail sheet gives it', () {
      const late = EventTime(startMinute: 23 * 60 + 30, durationMinutes: 90);
      final due = at(sunday, 23 * 60 + 30);

      expect(
        english.whenLabel(time: late, day: sunday, fireAt: due),
        '23:30 – 01:00 (+1)',
      );
    });

    group('is left empty when it would only repeat the due time', () {
      test('a point in time, on the due day, at the due minute', () {
        final due = at(sunday, sixPm);

        expect(english.whenLabel(time: point, day: sunday, fireAt: due), '');
      });

      test('compared as minutes, so the seconds of a snooze do not count', () {
        final due = DateTime(2026, 9, 20, 18, 0, 42, 310);

        expect(english.whenLabel(time: point, day: sunday, fireAt: due), '');
      });

      test('and never as text, so the clock style cannot change it', () {
        // "6:00 PM" against a due label still written "18:00" would never
        // match as strings.
        final due = at(sunday, sixPm);

        expect(twelveHour.whenLabel(time: point, day: sunday, fireAt: due), '');
      });

      test('one minute apart is two times', () {
        final due = at(sunday, sixPm + 1);

        expect(
          english.whenLabel(time: point, day: sunday, fireAt: due),
          '18:00',
        );
      });

      test('on the day the clocks change it is still the wall clock', () {
        // Europe's 2026 changes; on a host with no daylight saving the two
        // days are ordinary ones and the case holds all the same.
        final changes = [DateTime.utc(2026, 3, 29), DateTime.utc(2026, 10, 25)];
        for (final day in changes) {
          expect(
            english.whenLabel(time: point, day: day, fireAt: at(day, sixPm)),
            '',
            reason: '$day',
          );
        }
      });
    });

    group('names its day when the occurrence is not on the due day', () {
      // "1 day before": due on Sunday for Monday's occurrence.
      test('for an all-day event', () {
        final due = at(sunday, 9 * 60);

        expect(
          english.whenLabel(time: null, day: monday, fireAt: due),
          'Mon, Sep 21 · All day',
        );
      });

      test('for a range', () {
        final due = at(sunday, sixPm);

        expect(
          english.whenLabel(time: session, day: monday, fireAt: due),
          'Mon, Sep 21 · 18:00 – 19:30',
        );
      });

      test('for a point in time, even at the same minute of the day', () {
        // The same clock time a day early is not a repeat of the due time:
        // without the day the caption would read as today's.
        final due = at(sunday, sixPm);

        expect(
          english.whenLabel(time: point, day: monday, fireAt: due),
          'Mon, Sep 21 · 18:00',
        );
      });

      test('for an alert that comes just before midnight', () {
        const justAfter = EventTime(startMinute: 5);
        final due = at(sunday, 23 * 60 + 55);

        expect(
          english.whenLabel(time: justAfter, day: monday, fireAt: due),
          'Mon, Sep 21 · 00:05',
        );
      });

      test('first, so the end a one-line notification cuts is never the '
          'day', () {
        // A notification's text is one line beside its avatar: about 33
        // characters on a 427 dp phone, about 24 at 360 dp. Written after
        // the time, "Reminder · 6:00 PM – 7:30 PM, Mon, Sep 21" lost its day
        // to the cut, and what was left read as today's.
        final due = at(sunday, sixPm);

        expect(
          twelveHour.whenLabel(time: session, day: monday, fireAt: due),
          'Mon, Sep 21 · 6:00 PM – 7:30 PM',
        );
      });

      test('with German and Romanian day names', () {
        final due = at(sunday, 9 * 60);

        expect(
          german.whenLabel(time: null, day: monday, fireAt: due),
          'Mo., 21. Sept. · Ganztägig',
        );
        expect(
          romanian.whenLabel(time: null, day: monday, fireAt: due),
          'lun., 21 sept. · Toată ziua',
        );
      });
    });

    group('follows the clock the phone is on', () {
      final due = at(sunday, 9 * 60);

      test('24-hour when the phone says so, whatever the language', () {
        for (final labels in [english, german, romanian]) {
          expect(
            labels.whenLabel(time: session, day: sunday, fireAt: due),
            '18:00 – 19:30',
            reason: labels.languageCode,
          );
        }
      });

      test('12-hour in English when it does not', () {
        const morning = EventTime(startMinute: 7 * 60 + 5);
        const justAfterMidnight = EventTime(startMinute: 5);

        expect(
          twelveHour.whenLabel(time: session, day: sunday, fireAt: due),
          '6:00 PM – 7:30 PM',
        );
        expect(
          twelveHour.whenLabel(time: morning, day: sunday, fireAt: due),
          '7:05 AM',
        );
        expect(
          twelveHour.whenLabel(
            time: justAfterMidnight,
            day: sunday,
            fireAt: due,
          ),
          '12:05 AM',
        );
      });

      test('and still 24-hour in German and Romanian, which have no other', () {
        for (final language in ['de', 'ro']) {
          final labels = labelsOf(language, use24Hour: false);

          expect(
            labels.whenLabel(time: session, day: sunday, fireAt: due),
            '18:00 – 19:30',
            reason: language,
          );
        }
      });
    });
  });

  group('the due time', () {
    test('is written on the clock the phone is on, like every other label', () {
      // It stayed on a neutral 24-hour skeleton while nothing re-armed a
      // standing entry on a clock change; the arm context names the clock
      // now, so an entry armed today no longer reads beside older ones.
      final due = at(sunday, sixPm);

      expect(english.timeLabel(due), '18:00');
      expect(twelveHour.timeLabel(due), '6:00 PM');
      expect(english.timeLabel(at(sunday, 7 * 60 + 5)), '07:05');
      expect(twelveHour.timeLabel(at(sunday, 7 * 60 + 5)), '7:05 AM');
      expect(twelveHour.timeLabel(at(sunday, 5)), '12:05 AM');
    });

    test('is 24-hour in German and Romanian whatever the phone says', () {
      // Material's rule, the one the alarm page and every in-app time follow.
      final due = at(sunday, sixPm);

      for (final language in ['de', 'ro']) {
        expect(
          labelsOf(language, use24Hour: false).timeLabel(due),
          '18:00',
          reason: language,
        );
        expect(
          labelsOf(language, use24Hour: true).timeLabel(due),
          '18:00',
          reason: language,
        );
      }
    });

    test('reads as the event\'s own time does when the two are the same', () {
      // The notification puts one where the other is missing, so the two
      // must be one string for one minute, in either clock style.
      const morning = EventTime(startMinute: 7 * 60 + 5);
      final ahead = at(sunday, 6 * 60);

      for (final labels in [english, twelveHour, german, romanian]) {
        expect(
          labels.timeLabel(at(sunday, 7 * 60 + 5)),
          labels.whenLabel(time: morning, day: sunday, fireAt: ahead),
          reason: '${labels.languageCode}, 24-hour: ${labels.use24Hour}',
        );
      }
    });
  });

  group("the notice's day", () {
    test('is nothing while the alarm is due on the day the notice comes', () {
      expect(
        english.dayLabel(
          fireAt: at(sunday, sixPm),
          noticeAt: at(sunday, sixPm - 120),
        ),
        isNull,
      );
    });

    test("is the alarm's day once the notice comes the day before", () {
      final alarm = at(monday, 30);
      final notice = at(sunday, 22 * 60 + 30);

      expect(english.dayLabel(fireAt: alarm, noticeAt: notice), 'Mon, Sep 21');
      expect(
        german.dayLabel(fireAt: alarm, noticeAt: notice),
        'Mo., 21. Sept.',
      );
      expect(
        romanian.dayLabel(fireAt: alarm, noticeAt: notice),
        'lun., 21 sept.',
      );
    });
  });

  group("a digest's days", () {
    test('a line names its day as the notice does', () {
      expect(english.entryDayLabel(sunday), 'Sun, Sep 20');
      expect(german.entryDayLabel(sunday), 'So., 20. Sept.');
      expect(AlertLabels.fixed.entryDayLabel(sunday), 'Sun, Sep 20');
    });

    test('the collapsed line names its date without the weekday', () {
      expect(english.entryDateLabel(sunday), 'Sep 20');
      expect(german.entryDateLabel(sunday), '20. Sept.');
      expect(AlertLabels.fixed.entryDateLabel(sunday), 'Sep 20');
    });

    test('a span is both ends, even inside one month', () {
      final start = DateTime.utc(2026, 11, 4);
      final end = DateTime.utc(2026, 11, 10);

      expect(english.spanLabel(start, end), 'Nov 4 – Nov 10');
      expect(german.spanLabel(start, end), '4. Nov. – 10. Nov.');
      expect(
        AlertLabels.fixed.spanLabel(start, DateTime.utc(2026, 12, 3)),
        'Nov 4 – Dec 3',
      );
    });

    test('a span of one day is that day', () {
      final day = DateTime.utc(2026, 11, 4);

      expect(english.spanLabel(day, day), 'Nov 4');
    });
  });

  group("the chip's end", () {
    test("is the clock time the session ends at, on the phone's clock", () {
      final end = at(sunday, 19 * 60 + 30);

      expect(english.untilLabel(end), '19:30');
      expect(twelveHour.untilLabel(end), '7:30 PM');
      expect(labelsOf('de', use24Hour: false).untilLabel(end), '19:30');
      expect(labelsOf('ro', use24Hour: false).untilLabel(end), '19:30');
    });
  });

  group('the language', () {
    test('is the one the labels were built in', () {
      expect(english.languageCode, 'en');
      expect(german.languageCode, 'de');
      expect(romanian.languageCode, 'ro');
    });

    test('the fixed labels are 24-hour English', () {
      expect(AlertLabels.fixed.languageCode, 'en');
      expect(AlertLabels.fixed.use24Hour, isTrue);
      expect(
        AlertLabels.fixed.whenLabel(
          time: session,
          day: monday,
          fireAt: at(sunday, sixPm),
        ),
        'Mon, Sep 21 · 18:00 – 19:30',
      );
    });
  });

  group('an entry moved to a new instant', () {
    /// An entry of Sunday's occurrence, due on Sunday at [dueMinute].
    AlertPayload payloadOf({
      String eventId = 'e1',
      String whenLabel = '',
      String? languageCode = 'en',
      int dueMinute = sixPm,
    }) => AlertPayload(
      database: 'gym_notes',
      eventId: eventId,
      alertId: 'a1',
      dayUtcMs: sunday.millisecondsSinceEpoch,
      osId: 1234,
      mode: AlertMode.ring,
      title: 'Leg day',
      timeLabel: english.timeLabel(at(sunday, dueMinute)),
      categoryId: 'gym',
      excerpt: 'Squats first.',
      fireAtMs: at(sunday, dueMinute).millisecondsSinceEpoch,
      whenLabel: whenLabel,
      tintValue: 0xFF00897B,
      glyphKey: 'fitness_center',
      languageCode: languageCode,
    );

    final later = at(sunday, sixPm + 10);

    test('is due then, and says so', () {
      final moved = english.moved(payloadOf(whenLabel: '18:00 – 19:30'), later);

      expect(moved.fireAtMs, later.millisecondsSinceEpoch);
      expect(moved.timeLabel, '18:10');
    });

    test('keeps everything a new instant does not change', () {
      final before = payloadOf(whenLabel: '18:00 – 19:30');

      expect(
        english.moved(before, later),
        before.copyWith(
          fireAtMs: later.millisecondsSinceEpoch,
          timeLabel: '18:10',
        ),
      );
    });

    test("takes the old due time as the event's own, when that was all that "
        'said it', () {
      // Armed at the event's start, the entry left the event's time out as a
      // repeat of the due time. Once the due time moves on, nothing else
      // says when the event is.
      expect(english.moved(payloadOf(), later).whenLabel, '18:00');
    });

    test('but not on an entry armed before the labels existed', () {
      // No language means no labels wrote it: its empty line is "not known",
      // and the old due time of a "10 minutes before" alert is not the
      // event's time. Carrying a due instant does not change that — a snooze
      // taken from such a payload stamps one.
      final older = payloadOf(languageCode: null);

      expect(english.moved(older, later).whenLabel, '');
    });

    test('nor on a test ring, which has no event to have a time', () {
      final testRing = payloadOf(eventId: AlertPayload.testEventId);

      expect(english.moved(testRing, later).whenLabel, '');
    });

    test('nor inside the same minute, where the due time reads as it did', () {
      // What a ring the platform deferred by seconds looks like.
      final nudged = DateTime(2026, 9, 20, 18, 0, 30);
      final moved = english.moved(payloadOf(), nudged);

      expect(moved.fireAtMs, nudged.millisecondsSinceEpoch);
      expect(moved.timeLabel, '18:00');
      expect(moved.whenLabel, '');
    });

    test('the same minute is told from the two instants, not from how the '
        'two labels are spelled', () {
      // Armed on the 24-hour clock, moved by labels on the 12-hour one: the
      // old line reads "18:00" and the new one "6:00 PM" for one and the same
      // minute. Compared as text that was a move, and the due time was taken
      // for the event's own.
      final nudged = DateTime(2026, 9, 20, 18, 0, 30);
      final moved = twelveHour.moved(payloadOf(), nudged);

      expect(moved.fireAtMs, nudged.millisecondsSinceEpoch);
      expect(moved.timeLabel, '6:00 PM');
      expect(moved.whenLabel, '');

      // The last millisecond of the minute is still inside it; the first of
      // the next one is not.
      expect(
        twelveHour
            .moved(payloadOf(), DateTime(2026, 9, 20, 18, 0, 59, 999))
            .whenLabel,
        '',
      );
      expect(
        twelveHour.moved(payloadOf(), DateTime(2026, 9, 20, 18, 1)).whenLabel,
        '18:00',
      );
    });

    test('a move that leaves the label reading as it did is still a move', () {
      // Put off by exactly a day, "18:00" stays "18:00". Compared as text
      // nothing had moved, and Sunday's time was lost under Monday's date.
      final nextDay = at(monday, sixPm);
      final moved = english.moved(payloadOf(), nextDay);

      expect(moved.timeLabel, '18:00');
      expect(moved.fireAtMs, nextDay.millisecondsSinceEpoch);
      expect(moved.whenLabel, 'Sun, Sep 20 · 18:00');
    });

    test('put off past midnight, the line says which day it is about, and '
        'says it once', () {
      // Sunday's 23:55, snoozed ten minutes: due on Monday now, where a bare
      // "23:55" would read as Monday's.
      const lateMinute = 23 * 60 + 55;
      final pastMidnight = at(monday, 5);
      final rescued = english.moved(
        payloadOf(dueMinute: lateMinute),
        pastMidnight,
      );

      expect(rescued.timeLabel, '00:05');
      expect(rescued.whenLabel, 'Sun, Sep 20 · 23:55');

      // A line the entry already carried answers to the same rule…
      final carried = english.moved(
        payloadOf(whenLabel: '23:30 – 01:00 (+1)', dueMinute: lateMinute),
        pastMidnight,
      );
      expect(carried.whenLabel, 'Sun, Sep 20 · 23:30 – 01:00 (+1)');

      // …in the language of the labels that move it.
      expect(
        german.moved(payloadOf(dueMinute: lateMinute), pastMidnight).whenLabel,
        'So., 20. Sept. · 23:55',
      );

      // And a second snooze finds a line written for a day that already was
      // not the occurrence's: the day is there, and is not added again.
      final again = english.moved(rescued, at(monday, 15));
      expect(again.timeLabel, '00:15');
      expect(again.whenLabel, 'Sun, Sep 20 · 23:55');
    });

    test('keeps the shape it was armed in', () {
      // A new instant is not a new arming: whether the entry's notification
      // was armed in the app's group is the platform binding's to say, and
      // a move carries what it said.
      final inGroup = payloadOf().copyWith(grouped: true);

      expect(english.moved(inGroup, later).grouped, isTrue);
      expect(english.moved(inGroup, at(monday, 5)).grouped, isTrue);
      expect(english.moved(payloadOf(), later).grouped, isFalse);
    });
  });
}
