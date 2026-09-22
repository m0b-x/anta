import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/alert_sound.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/android_alert_gateway.dart';
import 'package:anta/utils/alert_os_id.dart';
import 'package:anta/utils/alert_planner.dart';

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

  group('arming', () {
    PlannedFire fireWith({
      AlertMode mode = AlertMode.ring,
      AlertSound sound = const AlertSoundSystemDefault(),
    }) {
      return PlannedFire(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 9, 20),
          rule: const OneTimeRecurrence(),
          time: const EventTime(startMinute: 7 * 60),
        ),
        alert: EventAlert(id: 'a1', eventId: 'e1', mode: mode),
        day: DateTime.utc(2026, 9, 20),
        fireAt: DateTime(2026, 9, 20, 7),
        sound: sound,
      );
    }

    test('the phone default arms with no path at all', () {
      // Null is how the `alarm` package says "the device's default alarm
      // sound", which is what keeps this value following the Clock app instead
      // of freezing the sound it named on the day it was chosen.
      expect(
        alarmAssetPathFor(const AlertSoundSystemDefault()),
        isNull,
      );
    });

    test('a picked sound arms verbatim', () {
      // The fork's `AudioService` (Patch 2 of `packages/alarm/`) opens a
      // `content://` URI through `MediaPlayer.setDataSource(Context, Uri)`,
      // so the URI goes to the platform as it is — nothing is copied into
      // the app's files first, and no caller resolves a path any more.
      expect(
        alarmAssetPathFor(const AlertSoundUri('content://media/7')),
        'content://media/7',
      );
      expect(
        alarmAssetPathFor(
          const AlertSoundUri('content://settings/system/alarm_alert'),
        ),
        'content://settings/system/alarm_alert',
      );
    });

    test("inherit never reaches the platform; it arms the phone's default", () {
      // The planner resolves an alert's `null` sound against the setting
      // before a fire exists, so this cannot arrive here — but if it ever did,
      // the phone's default is the only honest answer. The cross-device
      // degrade rule for a URI this phone cannot open lives in the fork's
      // `AudioService` now, at ring time, and lands on the same default.
      expect(alarmAssetPathFor(const AlertSoundInherit()), isNull);
    });

    test('the volume bucket follows the phone except near zero', () {
      // A ring follows the user's own alarm slider; the floor exists only so a
      // slider left at the bottom is not an alarm that silently fails.
      expect(alertRingVolumeFor(null), AlertRingVolume.follow);
      expect(alertRingVolumeFor(0), AlertRingVolume.floor);
      expect(
        alertRingVolumeFor(kAlertRingFloorVolume - 0.01),
        AlertRingVolume.floor,
      );
      expect(alertRingVolumeFor(kAlertRingFloorVolume), AlertRingVolume.follow);
      expect(alertRingVolumeFor(0.5), AlertRingVolume.follow);
      expect(alertRingVolumeFor(1), AlertRingVolume.follow);
    });

    test('the arm signature ends in the fork token for the alarm tier only', () {
      // OS-1: the token is what re-arms, once, every alarm-tier row a
      // pre-fork build left standing — armed the old way and, for a picked
      // sound, pointed at a copied file this build deletes. A reminder's
      // token must not move: nothing about how one is armed changed.
      expect(kAlertArmClockToken, '~clock');
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith()),
        endsWith(kAlertArmClockToken),
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(mode: AlertMode.notify)),
        'alarm',
      );
    });

    test('the arm signature names the sound of every alarm-tier fire', () {
      // The phone's default is named too, and that is the point (2026-09-22):
      // the builds that shipped a sound of their own recorded the bare backend
      // name for it, so this token differing from theirs is what re-armed
      // every standing alarm once the asset was gone — none may stay pointed
      // at a file the new build no longer carries.
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith()),
        'alarm#system:default~clock',
      );
      // A reminder plays through a channel whose sound Android froze at
      // creation, so a sound can never change what one does.
      expect(
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(
            mode: AlertMode.notify,
            sound: const AlertSoundUri('content://media/7'),
          ),
        ),
        'alarm',
      );
      // These two are what make a sound moved in Calendar settings, and a
      // volume slider dragged past the floor, reach alarms already standing.
      expect(
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(sound: const AlertSoundUri('content://media/7')),
        ),
        'alarm#content://media/7~clock',
      );
      expect(
        alertArmSignature(
          context: 'alarm@floor',
          fire: fireWith(),
        ),
        isNot(alertArmSignature(context: 'alarm', fire: fireWith())),
      );
      // Stable: equal inputs, equal token, or the diff cancels and re-arms the
      // same set on every pass.
      expect(
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(sound: const AlertSoundUri('content://media/7')),
        ),
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(sound: const AlertSoundUri('content://media/7')),
        ),
      );
    });
  });

  test('the channel ids are frozen', () {
    // Android freezes a channel's importance, sound and DND behaviour at
    // creation: a changed id is the only way to change any of them, and it
    // orphans the user's own per-channel settings. These are a contract.
    expect(kAlertReminderChannelId, 'alerts_reminder');
    // The fallback tier's channel is on its second id (OS-1): the first was
    // created with no sound, so a flipped A5 switch would have rung the
    // phone's default *notification* sound. The old id is what initialize
    // deletes; the two must never be the same string.
    expect(kAlertAlarmChannelId, 'alerts_alarm_v2');
    expect(kAlertLegacyAlarmChannelId, 'alerts_alarm');
    expect(kAlertAlarmChannelId, isNot(kAlertLegacyAlarmChannelId));
    expect(kAlertAlarmChannelSoundUri, 'content://settings/system/alarm_alert');
  });
}
