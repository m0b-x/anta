import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/alert_countdown.dart';
import 'package:anta/utils/alert_planner.dart';

/// The line the calendar raises after a save changed an event's alerts —
/// "Alarm in 2 h 50 min".
///
/// Three things can make it a lie, and each has a group: which fire is the
/// next one, whether a save is worth a word at all, and how the wait is
/// rounded and declined in each language.
///
/// `now` is pinned in every case, as in the planner's suite, and instants are
/// asserted as wall clock. The wording cases build their fire from `now` plus
/// an exact duration, so no timezone's DST can move them.
void main() {
  const defaults = (
    timedDefault: null,
    allDayDefault: (mode: AlertMode.notify, daysBefore: 0, dayMinute: 540),
    sound: '',
    snoozeMinutes: 10,
    silenceAfterMinutes: 10,
    noticeLeadMinutes: 120,
  );

  // A Monday, noon.
  final now = DateTime(2026, 9, 14, 12);
  final today = DateTime.utc(2026, 9, 14);
  final tomorrow = DateTime.utc(2026, 9, 15);

  EventAlert alertOf(
    String id, {
    AlertMode mode = AlertMode.notify,
    int offsetMinutes = 0,
    int daysBefore = 0,
    int? dayMinute,
    bool enabled = true,
  }) => EventAlert(
    id: id,
    eventId: 'e1',
    mode: mode,
    offsetMinutes: offsetMinutes,
    daysBefore: daysBefore,
    dayMinute: dayMinute,
    enabled: enabled,
  );

  CalendarEvent eventOf({
    String title = 'Leg day',
    required DateTime startDate,
    RecurrenceRule rule = const OneTimeRecurrence(),
    EventTime? time = const EventTime(startMinute: 7 * 60),
  }) => CalendarEvent(
    id: 'e1',
    title: title,
    categoryId: 'gym',
    startDate: startDate,
    rule: rule,
    time: time,
  );

  setUp(() {
    EventSkips.resetCache();
    PublicHolidays.resetCache();
  });

  tearDown(() {
    EventSkips.resetCache();
    PublicHolidays.resetCache();
  });

  group('the next fire', () {
    PlannedFire? nextOf(
      CalendarEvent event,
      List<EventAlert> alerts, {
      Set<DateTime>? skippedDays,
    }) => AlertCountdown.nextFire(
      event: event,
      alerts: alerts,
      defaults: defaults,
      now: now,
      skippedDays: skippedDays,
    );

    test('is the soonest of the alerts, whatever order they are in', () {
      final next = nextOf(eventOf(startDate: tomorrow), [
        alertOf('at-start', mode: AlertMode.ring),
        alertOf('hour-before', offsetMinutes: 60),
      ]);

      expect(next!.alert.id, 'hour-before');
      expect(next.fireAt.day, 15);
      expect(next.fireAt.hour, 6);
      expect(next.fireAt.minute, 0);
    });

    test('passes over a disabled alert', () {
      final next = nextOf(eventOf(startDate: tomorrow), [
        alertOf('hour-before', offsetMinutes: 60, enabled: false),
        alertOf('at-start', mode: AlertMode.ring),
      ]);

      expect(next!.alert.id, 'at-start');
      expect(next.fireAt.hour, 7);
    });

    test('is nothing once every alert is behind', () {
      // 07:00 today, asked at noon.
      expect(nextOf(eventOf(startDate: today), [alertOf('a1')]), isNull);
      expect(nextOf(eventOf(startDate: tomorrow), const []), isNull);
    });

    test('of a repeating event is its next occurrence still ahead', () {
      final next = nextOf(
        eventOf(
          startDate: DateTime.utc(2026, 9, 1),
          rule: const DailyRecurrence(),
        ),
        [alertOf('a1')],
      );

      expect(next!.day, tomorrow);
    });

    test("reaches past the scheduler's thirty days", () {
      // Not armed yet, and still the event's next alert.
      final next = nextOf(eventOf(startDate: DateTime.utc(2026, 12, 13)), [
        alertOf('a1', offsetMinutes: 24 * 60),
      ]);

      expect(next!.fireAt.month, 12);
      expect(next.fireAt.day, 12);
    });

    test('of an all-day event without a time of its own is the settings '
        'default', () {
      final next = nextOf(eventOf(startDate: tomorrow, time: null), [
        alertOf('a1'),
      ]);

      expect(next!.fireAt.day, 15);
      expect(next.fireAt.hour, 9);
    });

    test('passes over a day the same edit cancelled, before the facade has '
        'it', () {
      final daily = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const DailyRecurrence(),
      );

      final next = nextOf(
        daily,
        [alertOf('a1')],
        skippedDays: {tomorrow, DateTime.utc(2026, 9, 16)},
      );

      expect(next!.day, DateTime.utc(2026, 9, 17));
    });

    test('never passes over the one day of a one-time event', () {
      // A one-time rule carries no skips; a stale set must not hide it.
      final next = nextOf(eventOf(startDate: tomorrow), [
        alertOf('a1'),
      ], skippedDays: {tomorrow});

      expect(next!.day, tomorrow);
    });
  });

  group('after a save', () {
    PlannedFire? saidAfter({
      required CalendarEvent event,
      required List<EventAlert> alerts,
      CalendarEvent? previousEvent,
      List<EventAlert> previousAlerts = const [],
      Set<DateTime>? skippedDays,
    }) => AlertCountdown.afterSave(
      event: event,
      alerts: alerts,
      defaults: defaults,
      now: now,
      previousEvent: previousEvent,
      previousAlerts: previousAlerts,
      skippedDays: skippedDays,
    );

    final event = eventOf(startDate: tomorrow);
    final reminder = alertOf('hour-before', offsetMinutes: 60);

    test('a new event with an alert ahead is announced', () {
      final said = saidAfter(event: event, alerts: [reminder]);

      expect(said!.alert.id, 'hour-before');
    });

    test('a new event whose alert is already behind says nothing', () {
      expect(
        saidAfter(event: eventOf(startDate: today), alerts: [reminder]),
        isNull,
      );
    });

    test('a save that left the alerts and the next fire alone says '
        'nothing', () {
      expect(
        saidAfter(
          event: eventOf(title: 'Leg day, heavy', startDate: tomorrow),
          alerts: [reminder],
          previousEvent: event,
          previousAlerts: [reminder],
        ),
        isNull,
      );
    });

    test('an alert added is announced with whichever is next', () {
      final alarm = alertOf('at-start', mode: AlertMode.ring);

      final said = saidAfter(
        event: event,
        alerts: [reminder, alarm],
        previousEvent: event,
        previousAlerts: [reminder],
      );

      // The reminder is still the first to speak.
      expect(said!.alert.id, 'hour-before');
    });

    test('an alert changed in place is announced', () {
      final said = saidAfter(
        event: event,
        alerts: [reminder.copyWith(mode: AlertMode.ring)],
        previousEvent: event,
        previousAlerts: [reminder],
      );

      expect(said!.alert.isAlarm, isTrue);
    });

    test('a time moved under untouched alerts is announced', () {
      final said = saidAfter(
        event: eventOf(
          startDate: tomorrow,
          time: const EventTime(startMinute: 9 * 60),
        ),
        alerts: [reminder],
        previousEvent: event,
        previousAlerts: [reminder],
      );

      expect(said!.fireAt.hour, 8);
    });

    test('the last alert removed says nothing', () {
      expect(
        saidAfter(
          event: event,
          alerts: const [],
          previousEvent: event,
          previousAlerts: [reminder],
        ),
        isNull,
      );
    });

    test('the next occurrence cancelled in the same edit is announced as the '
        'one after it', () {
      final daily = eventOf(
        startDate: DateTime.utc(2026, 9, 1),
        rule: const DailyRecurrence(),
      );

      final said = saidAfter(
        event: daily,
        alerts: [reminder],
        previousEvent: daily,
        previousAlerts: [reminder],
        skippedDays: {tomorrow},
      );

      expect(said!.day, DateTime.utc(2026, 9, 16));
    });
  });

  group('the wording', () {
    final en = AppLocalizationsEn();
    final de = AppLocalizationsDe();
    final ro = AppLocalizationsRo();

    PlannedFire fireIn(Duration wait, {AlertMode mode = AlertMode.ring}) =>
        PlannedFire(
          event: eventOf(startDate: today),
          alert: alertOf('a1', mode: mode),
          day: today,
          fireAt: now.add(wait),
        );

    test('names the tier of the alert that is next', () {
      expect(
        AlertCountdown.message(
          fireIn(const Duration(minutes: 45), mode: AlertMode.notify),
          now,
          en,
        ),
        'Reminder in 45 min',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(hours: 2, minutes: 50)),
          now,
          en,
        ),
        'Alarm in 2 h 50 min',
      );
    });

    test('rounds a wait under a day up to the minute', () {
      expect(
        AlertCountdown.message(
          fireIn(const Duration(hours: 1, minutes: 59, seconds: 40)),
          now,
          en,
        ),
        'Alarm in 2 h',
      );
      expect(
        AlertCountdown.message(fireIn(const Duration(seconds: 10)), now, en),
        'Alarm in 1 min',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(milliseconds: 200)),
          now,
          en,
        ),
        'Alarm in 1 min',
      );
    });

    test('from a day on counts days and hours, to the nearest hour', () {
      expect(
        AlertCountdown.message(
          fireIn(const Duration(hours: 23, minutes: 59, seconds: 30)),
          now,
          en,
        ),
        'Alarm in 1 day',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(days: 1, minutes: 20)),
          now,
          en,
        ),
        'Alarm in 1 day',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(days: 1, hours: 3, minutes: 40)),
          now,
          en,
        ),
        'Alarm in 1 day 4 h',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(days: 3, hours: 4), mode: AlertMode.notify),
          now,
          en,
        ),
        'Reminder in 3 days 4 h',
      );
      expect(
        AlertCountdown.message(fireIn(const Duration(days: 89)), now, en),
        'Alarm in 89 days',
      );
    });

    test('German takes the dative after "in"', () {
      expect(
        AlertCountdown.message(
          fireIn(const Duration(hours: 2, minutes: 50)),
          now,
          de,
        ),
        'Alarm in 2 Std. 50 Min.',
      );
      expect(
        AlertCountdown.message(fireIn(const Duration(days: 1)), now, de),
        'Alarm in 1 Tag',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(days: 3, hours: 4), mode: AlertMode.notify),
          now,
          de,
        ),
        'Mitteilung in 3 Tagen 4 Std.',
      );
    });

    test('Romanian contracts one day and takes "de" from twenty', () {
      expect(
        AlertCountdown.message(
          fireIn(const Duration(hours: 2, minutes: 50)),
          now,
          ro,
        ),
        'Alarmă în 2 h 50 min',
      );
      expect(
        AlertCountdown.message(fireIn(const Duration(days: 1)), now, ro),
        'Alarmă într-o zi',
      );
      expect(
        AlertCountdown.message(
          fireIn(const Duration(days: 3, hours: 4), mode: AlertMode.notify),
          now,
          ro,
        ),
        'Notificare în 3 zile și 4 h',
      );
      expect(
        AlertCountdown.message(fireIn(const Duration(days: 20)), now, ro),
        'Alarmă în 20 de zile',
      );
    });
  });
}
