import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/android_alert_gateway.dart';
import 'package:anta/utils/alert_os_id.dart';

/// The Android binding's **pure half**: the ids it hands the platform and the
/// payload it round-trips through it.
///
/// Nothing here constructs an [AndroidAlertGateway] or touches a plugin
/// channel, and nothing can: the binding is registered behind
/// `AlertAvailability.isSupported`, so a test host — a desktop — always gets
/// the no-op. What *is* worth pinning is everything that crosses a process
/// boundary, because the platform stores an os id and a JSON string through a
/// reboot and hands them back to a build that may be two versions newer.
void main() {
  const payload = AlertPayload(
    database: 'gym_notes',
    eventId: 'e1',
    alertId: 'a1',
    dayUtcMs: 1789862400000,
    osId: 1234567,
    mode: AlertMode.ring,
    title: 'Leg day',
    timeLabel: '07:00',
    colorValue: 0xFF1E88E5,
    iconKey: 'fitness_center',
    categoryId: 'gym',
    removeAfterAlert: true,
    snooze: true,
    snoozeMinutes: 15,
  );

  group('payload round trip', () {
    test('every field survives the wire', () {
      final decoded = AlertPayload.decode(payload.encode());

      expect(decoded, payload);
      // Spelled out as well as compared, because `Equatable` would happily
      // agree about two payloads that both lost the same field.
      expect(decoded!.database, 'gym_notes');
      expect(decoded.mode, AlertMode.ring);
      expect(decoded.removeAfterAlert, isTrue);
      expect(decoded.snooze, isTrue);
      // The background isolate has no settings service, so the snooze length
      // has to arrive in the payload or Snooze cannot re-schedule at all.
      expect(decoded.snoozeMinutes, 15);
    });

    test('a payload written by an older build still decodes', () {
      // No `snoozeMin` key — what every entry armed before this session
      // carries. It has to read as the shipped default rather than as a
      // snooze of zero minutes.
      const legacy =
          '{"db":"gym_notes","eventId":"e1","alertId":"a1",'
          '"dayUtcMs":1789862400000,"osId":7,"mode":"ring"}';
      final decoded = AlertPayload.decode(legacy);

      expect(decoded, isNotNull);
      expect(decoded!.snoozeMinutes, greaterThan(0));
      expect(decoded.osId, 7);
    });

    test('a truncated or foreign payload reads as "not ours", never throws', () {
      // Every one of these arrives inside a platform callback, where an
      // exception would take the ring down with it.
      expect(AlertPayload.decode(null), isNull);
      expect(AlertPayload.decode(''), isNull);
      expect(AlertPayload.decode('{"db":"gym_notes"'), isNull);
      expect(AlertPayload.decode('"a string"'), isNull);
      expect(AlertPayload.decode('{"db":"gym_notes","eventId":"e1"}'), isNull);
    });

    test('the test-alarm sentinel is recognised on both sides', () {
      const test = AlertPayload(
        database: 'gym_notes',
        eventId: AlertPayload.testEventId,
        alertId: AlertPayload.testEventId,
        dayUtcMs: 1789862400000,
        osId: 9,
        mode: AlertMode.ring,
        title: '',
        timeLabel: '07:00',
        categoryId: 'other',
      );

      expect(test.isTest, isTrue);
      expect(AlertPayload.decode(test.encode())!.isTest, isTrue);
      expect(payload.isTest, isFalse);
    });
  });

  group('os ids', () {
    test('the seed is deterministic and fits the platform id space', () {
      final day = DateTime.utc(2026, 9, 20);
      int seed(String database, AlertKind kind) => alertOsIdSeed(
        database: database,
        alertId: 'a1',
        dayUtc: day,
        kind: kind,
      );

      // Same inputs, same id — the whole reason reconcile is idempotent
      // across a process death, an app update and a reboot.
      expect(
        seed('gym_notes', AlertKind.scheduled),
        seed('gym_notes', AlertKind.scheduled),
      );
      // Namespaced by database (A9) and by kind (A8), so two databases cannot
      // cancel each other's alarms and a snooze never lands on the scheduled
      // entry it came from.
      expect(
        seed('gym_notes', AlertKind.scheduled),
        isNot(seed('work', AlertKind.scheduled)),
      );
      expect(
        seed('gym_notes', AlertKind.scheduled),
        isNot(seed('gym_notes', AlertKind.snooze)),
      );
      // Android notification ids and the `alarm` package's ids are both
      // signed 32-bit.
      expect(seed('gym_notes', AlertKind.scheduled), inInclusiveRange(0, kAlertOsIdMask));
    });

    test('a "Missed" notice never lands on a live registration id', () {
      for (final osId in [0, 1, 4242, kAlertOsIdMask]) {
        final missed = missedNotificationId(osId);
        expect(missed, isNot(osId));
        expect(missed, inInclusiveRange(0, kAlertOsIdMask));
        // Derived, so reporting the same miss twice replaces the notice
        // rather than stacking two of them.
        expect(missedNotificationId(osId), missed);
      }
    });

    test('a tap on a "Missed" notice is told apart from the alarm itself', () {
      // The notice carries the alarm's own payload, so only the notification
      // id can say which of the two was tapped — and the answer decides
      // between opening the event and pushing a ring page for a session that
      // ended hours ago.
      expect(
        isMissedNotification(missedNotificationId(payload.osId), payload),
        isTrue,
      );
      expect(isMissedNotification(payload.osId, payload), isFalse);
      expect(isMissedNotification(null, payload), isFalse);
    });
  });

  test('the binding names a backend the registry can record', () {
    // The registry stores this per row, which is what lets a reconcile after
    // the A5 switch is flipped re-schedule every entry under the new backend
    // instead of leaving them stranded on the old one.
    expect(
      kAlarmTierUsesNotifications ? 'notification' : 'alarm',
      isNot(const NoOpAlertGateway().backendName),
    );
  });

  test('the channel ids are frozen', () {
    // Android freezes a channel's importance, sound and DND behaviour at
    // creation: a changed id is the only way to change any of them, and it
    // orphans the user's own per-channel settings. These two are a contract.
    expect(kAlertReminderChannelId, 'alerts_reminder');
    expect(kAlertAlarmChannelId, 'alerts_alarm');
  });
}
