import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/quick_alarm.dart';

/// The quick alarm's arithmetic and the event it becomes, with no widget in
/// sight: the sheet only shows what these say.
void main() {
  group('the opening moment', () {
    test('is the next quarter hour strictly after now', () {
      expect(
        quickAlarmDefaultFor(DateTime(2026, 9, 23, 10, 0)),
        (day: DateTime.utc(2026, 9, 23), minute: 10 * 60 + 15),
      );
      expect(
        quickAlarmDefaultFor(DateTime(2026, 9, 23, 10, 14, 59)),
        (day: DateTime.utc(2026, 9, 23), minute: 10 * 60 + 15),
      );
      expect(
        quickAlarmDefaultFor(DateTime(2026, 9, 23, 10, 15)),
        (day: DateTime.utc(2026, 9, 23), minute: 10 * 60 + 30),
      );
    });

    test('rolls into tomorrow after 23:45', () {
      expect(
        quickAlarmDefaultFor(DateTime(2026, 9, 23, 23, 50)),
        (day: DateTime.utc(2026, 9, 24), minute: 0),
      );
    });
  });

  group('the presets', () {
    test('"in N" rounds up to the whole minute, and crosses midnight', () {
      expect(
        quickAlarmAfter(DateTime(2026, 9, 23, 10, 3), const Duration(minutes: 20)),
        (day: DateTime.utc(2026, 9, 23), minute: 10 * 60 + 23),
      );
      expect(
        quickAlarmAfter(
          DateTime(2026, 9, 23, 10, 3, 40),
          const Duration(minutes: 20),
        ),
        (day: DateTime.utc(2026, 9, 23), minute: 10 * 60 + 24),
      );
      expect(
        quickAlarmAfter(DateTime(2026, 9, 23, 23, 30), const Duration(hours: 1)),
        (day: DateTime.utc(2026, 9, 24), minute: 30),
      );
    });

    test('tonight is 21:00 today, and nothing once that has passed', () {
      expect(
        quickAlarmTonightFor(DateTime(2026, 9, 23, 20, 59)),
        (day: DateTime.utc(2026, 9, 23), minute: kQuickAlarmTonightMinute),
      );
      expect(quickAlarmTonightFor(DateTime(2026, 9, 23, 21, 0)), isNull);
    });
  });

  group('the day an alarm lands on', () {
    final now = DateTime(2026, 9, 23, 10, 0);

    test('is the opened day while its time is still ahead', () {
      expect(
        quickAlarmDayFor(day: DateTime.utc(2026, 9, 23), minute: 10 * 60 + 1, now: now),
        DateTime.utc(2026, 9, 23),
      );
      expect(
        quickAlarmDayFor(day: DateTime.utc(2026, 9, 30), minute: 6 * 60, now: now),
        DateTime.utc(2026, 9, 30),
      );
    });

    test('rolls a time already gone to today or tomorrow', () {
      expect(
        quickAlarmDayFor(day: DateTime.utc(2026, 9, 23), minute: 10 * 60, now: now),
        DateTime.utc(2026, 9, 24),
      );
      expect(
        quickAlarmDayFor(day: DateTime.utc(2026, 9, 1), minute: 15 * 60, now: now),
        DateTime.utc(2026, 9, 23),
      );
      expect(
        quickAlarmDayFor(day: DateTime.utc(2026, 9, 1), minute: 9 * 60, now: now),
        DateTime.utc(2026, 9, 24),
      );
    });
  });

  group('the event and its alert', () {
    final draft = QuickAlarmDraft(
      day: DateTime.utc(2026, 9, 23),
      startMinute: 7 * 60,
      name: 'Alarm',
    );

    test('is a one-time event in the fallback category with the alarm icon', () {
      final event = buildQuickAlarmEvent(draft, id: 'e1');

      expect(event.id, 'e1');
      expect(event.title, 'Alarm');
      expect(event.categoryId, kFallbackCategoryId);
      expect(event.startDate, DateTime.utc(2026, 9, 23));
      expect(event.rule, const OneTimeRecurrence());
      expect(event.iconKey, kQuickAlarmIconKey);
      expect(event.time, const EventTime(startMinute: 7 * 60));
      expect(event.removeAfterAlert, isTrue);
    });

    test('carries one alert at start in the chosen tier', () {
      final alert = buildQuickAlarmAlert(draft, eventId: 'e1', id: 'a1');

      expect(alert.id, 'a1');
      expect(alert.eventId, 'e1');
      expect(alert.mode, AlertMode.ring);
      expect(alert.offsetMinutes, 0);
      expect(alert.enabled, isTrue);
      expect(alert.sound, isNull);
    });

    test('a reminder never removes the event, whatever the switch said', () {
      final reminder = QuickAlarmDraft(
        day: DateTime.utc(2026, 9, 23),
        startMinute: 7 * 60,
        name: 'Water the plants',
        mode: AlertMode.notify,
        removeAfterAlert: true,
      );

      expect(buildQuickAlarmEvent(reminder, id: 'e2').removeAfterAlert, isFalse);
      expect(
        buildQuickAlarmAlert(reminder, eventId: 'e2', id: 'a2').mode,
        AlertMode.notify,
      );
    });

    test('the switch off keeps the event', () {
      final kept = QuickAlarmDraft(
        day: DateTime.utc(2026, 9, 23),
        startMinute: 7 * 60,
        name: 'Alarm',
        removeAfterAlert: false,
      );

      expect(buildQuickAlarmEvent(kept, id: 'e3').removeAfterAlert, isFalse);
    });
  });
}
