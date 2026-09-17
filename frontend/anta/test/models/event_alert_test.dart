import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';

/// [EventAlert] carries **both** offset sets at once and lets the event decide
/// which one is being read, so the two things worth pinning are that the codec
/// round-trips every field and that an all-day flip changes the *reading*
/// without touching the data.
///
/// `describe` is a table because it is the single formatter four surfaces
/// share — the editor card, the detail row, the hub row and the notification
/// body. A second switch anywhere would be a second answer.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    initializeDateFormatting('en');
    l10n = lookupAppLocalizations(const Locale('en'));
  });

  CalendarEvent eventOf({EventTime? time}) => CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 14),
    rule: const OneTimeRecurrence(),
    time: time,
  );

  const timed = EventTime(startMinute: 18 * 60);

  EventAlert alert({
    AlertMode mode = AlertMode.notify,
    int offsetMinutes = 0,
    int daysBefore = 0,
    int? dayMinute,
    String? sound,
    bool enabled = true,
  }) => EventAlert(
    id: 'a1',
    eventId: 'e1',
    mode: mode,
    offsetMinutes: offsetMinutes,
    daysBefore: daysBefore,
    dayMinute: dayMinute,
    sound: sound,
    enabled: enabled,
  );

  group('codec', () {
    test('round-trips every field', () {
      final original = alert(
        mode: AlertMode.ring,
        offsetMinutes: 30,
        daysBefore: 2,
        dayMinute: 1200,
        sound: 'chime',
        enabled: false,
      );

      expect(EventAlert.fromJson(original.toJson()), original);
    });

    test('a null sound and a null day minute survive the trip', () {
      final original = alert(offsetMinutes: 10);
      final decoded = EventAlert.fromJson(original.toJson());

      expect(decoded, original);
      expect(decoded!.sound, isNull);
      expect(decoded.dayMinute, isNull);
    });

    test('an unknown mode decodes to the quieter tier', () {
      final decoded = EventAlert.fromJson({
        EventAlertKeys.id: 'a1',
        EventAlertKeys.eventId: 'e1',
        EventAlertKeys.mode: 'siren',
      });

      // A row written by a newer build must never surprise an older one with
      // noise, so the fallback is `notify` rather than `ring`.
      expect(decoded!.mode, AlertMode.notify);
    });

    test('missing identity is rejected, missing detail is not', () {
      expect(EventAlert.fromJson({EventAlertKeys.eventId: 'e1'}), isNull);
      expect(EventAlert.fromJson({EventAlertKeys.id: 'a1'}), isNull);
      expect(
        EventAlert.fromJson({
          EventAlertKeys.id: 'a1',
          EventAlertKeys.eventId: 'e1',
        }),
        alert(),
      );
    });

    test('a negative offset decodes to zero rather than backwards', () {
      final decoded = EventAlert.fromJson({
        EventAlertKeys.id: 'a1',
        EventAlertKeys.eventId: 'e1',
        EventAlertKeys.offsetMinutes: -30,
        EventAlertKeys.daysBefore: -1,
      });

      expect(decoded!.offsetMinutes, 0);
      expect(decoded.daysBefore, 0);
    });

    test('an out-of-range day minute is clamped into the day', () {
      final decoded = EventAlert.fromJson({
        EventAlertKeys.id: 'a1',
        EventAlertKeys.eventId: 'e1',
        EventAlertKeys.dayMinute: 5000,
      });

      expect(decoded!.dayMinute, EventAlert.minutesPerDay - 1);
    });
  });

  group('copyWith', () {
    test('clearSound and clearDayMinute beat a passed value', () {
      final full = alert(dayMinute: 1200, sound: 'chime');

      expect(full.copyWith(clearSound: true).sound, isNull);
      expect(full.copyWith(clearDayMinute: true).dayMinute, isNull);
      expect(
        full.copyWith(sound: 'bell', clearSound: true).sound,
        isNull,
        reason: 'the clear flag is the explicit act; the value is the default',
      );
    });

    test('an untouched field is carried over', () {
      final full = alert(mode: AlertMode.ring, offsetMinutes: 15, sound: 'x');
      final toggled = full.copyWith(enabled: false);

      expect(toggled.mode, AlertMode.ring);
      expect(toggled.offsetMinutes, 15);
      expect(toggled.sound, 'x');
      expect(toggled.enabled, isFalse);
    });
  });

  group('describe', () {
    final cases = <({String name, EventAlert alert, bool allDay, String text})>[
      (
        name: 'at start',
        alert: alert(offsetMinutes: 0),
        allDay: false,
        text: 'At start',
      ),
      (
        name: 'minutes',
        alert: alert(offsetMinutes: 10),
        allDay: false,
        text: '10 min before',
      ),
      (
        name: 'a single minute keeps the singular arm',
        alert: alert(offsetMinutes: 1),
        allDay: false,
        text: '1 min before',
      ),
      (
        name: 'whole hours become hours',
        alert: alert(offsetMinutes: 120),
        allDay: false,
        text: '2 h before',
      ),
      (
        name: 'a ragged offset stays in minutes',
        alert: alert(offsetMinutes: 90),
        allDay: false,
        text: '90 min before',
      ),
      (
        name: 'whole days become days',
        alert: alert(offsetMinutes: 1440),
        allDay: false,
        text: '1 day before',
      ),
      (
        name: 'all-day, on the day, default time',
        alert: alert(),
        allDay: true,
        text: 'On the day, 09:00',
      ),
      (
        name: 'all-day, on the day, chosen time',
        alert: alert(dayMinute: 20 * 60),
        allDay: true,
        text: 'On the day, 20:00',
      ),
      (
        name: 'all-day, the evening before',
        alert: alert(daysBefore: 1, dayMinute: 20 * 60),
        allDay: true,
        text: 'The day before, 20:00',
      ),
      (
        name: 'all-day, a week before',
        alert: alert(daysBefore: 7),
        allDay: true,
        text: '7 days before, 09:00',
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final event = eventOf(time: c.allDay ? null : timed);
        expect(c.alert.describe(l10n, event), c.text);
      });
    }

    test('the tier does not change the wording', () {
      // The mode decides the glyph and the subtitle beside the row, never this
      // string — so a reminder and an alarm ten minutes out read identically.
      final event = eventOf(time: timed);
      expect(
        alert(mode: AlertMode.ring, offsetMinutes: 10).describe(l10n, event),
        alert(mode: AlertMode.notify, offsetMinutes: 10).describe(l10n, event),
      );
    });

    test('a null day minute follows the shipped default', () {
      expect(
        alert(dayMinute: null).describe(l10n, eventOf()),
        alert(dayMinute: kDefaultAlertDayMinute).describe(l10n, eventOf()),
      );
    });
  });

  group('an alert with no time of its own', () {
    tearDown(() => EventAlerts.configureDefaultDayMinute(null));

    test('describes the settings default, which is what it rings at', () {
      // The planner is handed this same number. Falling back to 09:00 here
      // instead meant an alert read "09:00" and rang at the time the setting
      // had been moved to.
      EventAlerts.configureDefaultDayMinute(7 * 60 + 30);

      expect(
        alert(dayMinute: null).describe(l10n, eventOf()),
        alert(dayMinute: 7 * 60 + 30).describe(l10n, eventOf()),
      );
    });

    test('its own time still wins', () {
      EventAlerts.configureDefaultDayMinute(7 * 60 + 30);

      expect(
        alert(dayMinute: 20 * 60).describe(l10n, eventOf()),
        contains('20:00'),
      );
    });

    test('"no all-day default" leaves the shipped anchor', () {
      EventAlerts.configureDefaultDayMinute(6 * 60);
      EventAlerts.configureDefaultDayMinute(null);

      expect(EventAlerts.defaultDayMinute, kDefaultAlertDayMinute);
    });
  });

  group('an all-day flip', () {
    test('changes the reading and keeps both offset sets', () {
      final both = alert(offsetMinutes: 10, daysBefore: 1, dayMinute: 20 * 60);

      final asTimed = both.describe(l10n, eventOf(time: timed));
      final asAllDay = both.describe(l10n, eventOf());

      expect(asTimed, '10 min before');
      expect(asAllDay, 'The day before, 20:00');
      // Nothing on the alert changed: the event is what decided which set was
      // being read, which is why flipping back is lossless.
      expect(both.offsetMinutes, 10);
      expect(both.daysBefore, 1);
      expect(both.dayMinute, 20 * 60);
    });

    test('surviving a round trip through the codec as well', () {
      final both = alert(offsetMinutes: 45, daysBefore: 2, dayMinute: 480);
      final decoded = EventAlert.fromJson(both.toJson())!;

      expect(decoded.describe(l10n, eventOf(time: timed)), '45 min before');
      expect(decoded.describe(l10n, eventOf()), '2 days before, 08:00');
    });
  });
}
