import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/alert_sound.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/android_alert_gateway.dart';
import 'package:anta/utils/alert_labels.dart';
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

    test('the excerpt rides the wire and an older payload reads as none', () {
      // OS-4: the reminder's expandable body and the Missed notice's are
      // drawn from the payload alone, so the excerpt has to survive a
      // reboot with the rest — and a payload from before it must not fail.
      final rich = AlertPayload(
        database: payload.database,
        eventId: payload.eventId,
        alertId: payload.alertId,
        dayUtcMs: payload.dayUtcMs,
        osId: payload.osId,
        mode: payload.mode,
        title: payload.title,
        timeLabel: payload.timeLabel,
        categoryId: payload.categoryId,
        excerpt: 'Squat and bench',
      );
      expect(AlertPayload.decode(rich.encode())!.excerpt, 'Squat and bench');
      expect(AlertPayload.decode(payload.encode())!.excerpt, '');
      expect(rich.copyWith(osId: 9).excerpt, 'Squat and bench');
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

    test('an upcoming notice id never lands on a live entry or a Missed one', () {
      for (final osId in [0, 1, 4242, 0x4d495353, kAlertOsIdMask]) {
        final notice = noticeNotificationId(osId);
        expect(notice, isNot(osId));
        expect(notice, isNot(missedNotificationId(osId)));
        expect(notice, inInclusiveRange(0, kAlertOsIdMask));
        expect(noticeNotificationId(osId), notice);
      }
    });

    test('an upcoming notice dies at the instant of the alarm it announces', () {
      // A ring stopped or snoozed natively with no Dart running cancels
      // nothing on this side, so the notice's own timeout is what keeps its
      // Skip from cancelling an occurrence that already happened.
      expect(
        noticeTimeoutMillis(
          noticeAt: DateTime(2026, 9, 20, 16),
          fireAt: DateTime(2026, 9, 20, 18),
        ),
        const Duration(hours: 2).inMilliseconds,
      );
    });

    test('a tap on an upcoming notice is told apart, and carries its flag', () {
      final notice = payload.copyWith(notice: true);
      expect(isNoticeNotification(noticeNotificationId(payload.osId), notice), isTrue);
      expect(isNoticeNotification(payload.osId, notice), isFalse);
      expect(isNoticeNotification(null, notice), isTrue);
      expect(isNoticeNotification(null, payload), isFalse);
      // Round-tripped: the platform hands the notice's payload back through
      // a reboot, and the flag is what a response with no id falls back on.
      expect(AlertPayload.decode(notice.encode())!.notice, isTrue);
      expect(AlertPayload.decode(payload.encode())!.notice, isFalse);
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
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
        contains(kAlertArmClockToken),
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(mode: AlertMode.notify), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
        'alarm',
      );
    });

    test('the snooze length stays under the in-flight grace', () {
      // OS-2 review: a native snooze taken with no Dart running moves the
      // plugin's entry while the registry row keeps the original instant,
      // and the snoozed ring is what launches the app — so at that launch
      // the row is exactly the snooze length late. Under `kLateFireGrace` it
      // is in flight and the ring handler settles it; at the grace it would
      // be reported missed and cancelled as a stray while it rings.
      expect(
        SettingsKeys.maxAlertSnoozeMinutes,
        lessThan(kLateFireGrace.inMinutes),
      );
    });

    test('the arm signature carries the notice lead for the alarm tier', () {
      // OS-3: the notice is armed beside the alarm at `fireAt − lead`, so a
      // changed lead — off included — has to re-arm the alarm for its notice
      // to move or go; a reminder never has one.
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 0, silenceAfterMinutes: 10),
        'alarm#system:default~clock~10~n0~s10',
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 60, silenceAfterMinutes: 10),
        isNot(alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10)),
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(mode: AlertMode.notify), snoozeMinutes: 10, noticeLeadMinutes: 0, silenceAfterMinutes: 10),
        alertArmSignature(context: 'alarm', fire: fireWith(mode: AlertMode.notify), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
      );
    });

    test('the arm signature carries the snooze length for the alarm tier', () {
      // OS-2: the plugin's own notification offers a Snooze of exactly this
      // length, armed into the entry, so a changed setting has to reach every
      // standing alarm the way a changed sound does — and a reminder, which
      // snoozes from the payload alone, must not be re-armed for it.
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
        'alarm#system:default~clock~10~n120~s10',
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 5, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
        isNot(
          alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
        ),
      );
      expect(
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(mode: AlertMode.notify),
          snoozeMinutes: 5,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(mode: AlertMode.notify),
          snoozeMinutes: 10,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
      );
    });

    test('the arm signature carries Silence after for the alarm tier', () {
      // C114: the binding freezes the length into the platform entry as
      // `timeoutAfterMillis`, so a changed slider has to re-arm every standing
      // alarm the way a changed snooze length does. A reminder's ring has no
      // length to silence.
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 2),
        'alarm#system:default~clock~10~n120~s2',
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 2),
        isNot(alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10)),
      );
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(mode: AlertMode.notify), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 2),
        alertArmSignature(context: 'alarm', fire: fireWith(mode: AlertMode.notify), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
      );
    });

    test('the arm signature names the sound of every alarm-tier fire', () {
      // The phone's default is named too, and that is the point (2026-09-22):
      // the builds that shipped a sound of their own recorded the bare backend
      // name for it, so this token differing from theirs is what re-armed
      // every standing alarm once the asset was gone — none may stay pointed
      // at a file the new build no longer carries.
      expect(
        alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10),
        'alarm#system:default~clock~10~n120~s10',
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
          snoozeMinutes: 10,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
        'alarm',
      );
      // These two are what make a sound moved in Calendar settings, and a
      // volume slider dragged past the floor, reach alarms already standing.
      expect(
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(sound: const AlertSoundUri('content://media/7')),
          snoozeMinutes: 10,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
        'alarm#content://media/7~clock~10~n120~s10',
      );
      expect(
        alertArmSignature(
          context: 'alarm@floor',
          fire: fireWith(),
          snoozeMinutes: 10,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
        isNot(alertArmSignature(context: 'alarm', fire: fireWith(), snoozeMinutes: 10, noticeLeadMinutes: 120, silenceAfterMinutes: 10)),
      );
      // Stable: equal inputs, equal token, or the diff cancels and re-arms the
      // same set on every pass.
      expect(
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(sound: const AlertSoundUri('content://media/7')),
          snoozeMinutes: 10,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
        alertArmSignature(
          context: 'alarm',
          fire: fireWith(sound: const AlertSoundUri('content://media/7')),
          snoozeMinutes: 10,
          noticeLeadMinutes: 120,
          silenceAfterMinutes: 10,
        ),
      );
    });
  });

  group('a ring report', () {
    // The plugin re-arms a snoozed alarm with the settings it was first given,
    // payload included, so what it hands back at the second ring still reads
    // the first. `ringReportPayload` is where the two are reconciled, and the
    // whole of what the binding decides about a ring before announcing it.
    final dueAt = DateTime(2026, 9, 20, 7);
    final labels = AlertLabels.fixed;

    /// An entry armed by a build that stamps its payloads, at the event's
    /// start — so it left the event's own time out as a repeat of its own.
    final stamped = AlertPayload(
      database: 'gym_notes',
      eventId: 'e1',
      alertId: 'a1',
      dayUtcMs: 1789862400000,
      osId: 0,
      mode: AlertMode.ring,
      title: 'Leg day',
      timeLabel: '07:00',
      categoryId: 'gym',
      excerpt: 'Squats first.',
      fireAtMs: dueAt.millisecondsSinceEpoch,
      tintValue: 0xFF1E88E5,
      glyphKey: 'fitness_center',
      languageCode: 'en',
    );

    AlertPayload report(
      AlertPayload stored, {
      required DateTime rangAt,
      bool nativelySnoozed = false,
    }) => ringReportPayload(
      stored: stored,
      alarmDateTime: rangAt,
      osId: 77,
      labels: labels,
      nativelySnoozed: nativelySnoozed,
    );

    test('an unstamped payload changes only its id, whatever the plugin says',
        () {
      // `payload` carries no due instant: armed before the field existed.
      // There is nothing to compare the plugin's time with, and its page
      // goes on drawing what it always drew — even for a ring this process
      // knows was snoozed.
      final reported = report(
        payload,
        rangAt: DateTime(2026, 9, 20, 7, 10),
        nativelySnoozed: true,
      );

      expect(reported, payload.copyWith(osId: 77));
      expect(reported.timeLabel, '07:00');
      expect(reported.fireAtMs, isNull);
      expect(reported.reRing, isFalse);
    });

    test('a stamped payload that rang when it was due changes only its id', () {
      expect(report(stamped, rangAt: dueAt), stamped.copyWith(osId: 77));
    });

    test('a moved instant is restamped, with the clock label for it', () {
      final rangAt = DateTime(2026, 9, 20, 7, 10);
      final reported = report(stamped, rangAt: rangAt);

      expect(reported.osId, 77);
      expect(reported.fireAtMs, rangAt.millisecondsSinceEpoch);
      expect(reported.timeLabel, '07:10');
    });

    test("the event's own time is rescued when the due time was all that "
        'said it', () {
      final rangAt = DateTime(2026, 9, 20, 7, 10);

      // Left empty at arm time as a repeat of "07:00"; with the due time
      // moved to 07:10 nothing else says when the event is.
      expect(report(stamped, rangAt: rangAt).whenLabel, '07:00');
      // An entry that did say it keeps what it said.
      expect(
        report(
          stamped.copyWith(whenLabel: '07:15 – 08:00'),
          rangAt: rangAt,
        ).whenLabel,
        '07:15 – 08:00',
      );
    });

    test('everything else a moved ring carries is as it was armed', () {
      final rangAt = DateTime(2026, 9, 20, 7, 10);

      expect(
        report(stamped, rangAt: rangAt, nativelySnoozed: true),
        stamped.copyWith(
          osId: 77,
          fireAtMs: rangAt.millisecondsSinceEpoch,
          timeLabel: '07:10',
          whenLabel: '07:00',
          reRing: true,
        ),
      );
    });

    test('a re-ring is said only from the snooze record, never from a moved '
        'time alone', () {
      final rangAt = DateTime(2026, 9, 20, 7, 10);

      // The platform defers rings for reasons of its own — a refused start
      // is re-armed half a minute on — and that is not a snooze.
      expect(report(stamped, rangAt: rangAt).reRing, isFalse);
      expect(
        report(stamped, rangAt: rangAt, nativelySnoozed: true).reRing,
        isTrue,
      );
      // Nor from the record alone: an entry that rang when it was due was
      // not moved by anything, whatever this id went through before.
      expect(
        report(stamped, rangAt: dueAt, nativelySnoozed: true).reRing,
        isFalse,
      );
    });

    test('a deferral inside the minute moves the instant and nothing drawn',
        () {
      final rangAt = DateTime(2026, 9, 20, 7, 0, 30);
      final reported = report(stamped, rangAt: rangAt);

      expect(reported.fireAtMs, rangAt.millisecondsSinceEpoch);
      expect(reported.timeLabel, '07:00');
      // Rescued here, the caption would repeat the clock above it.
      expect(reported.whenLabel, '');
    });

    test('a test ring that was snoozed gains no event time', () {
      final test = AlertPayload(
        database: 'gym_notes',
        eventId: AlertPayload.testEventId,
        alertId: '${AlertPayload.testEventId}:1',
        dayUtcMs: 1789862400000,
        osId: 0,
        mode: AlertMode.ring,
        title: '',
        timeLabel: '07:00',
        categoryId: 'other',
        snooze: true,
        fireAtMs: dueAt.millisecondsSinceEpoch,
        tintValue: 0xFF6750A4,
        glyphKey: 'alarm',
        languageCode: 'en',
      );

      final reported = report(
        test,
        rangAt: DateTime(2026, 9, 20, 7, 10),
        nativelySnoozed: true,
      );

      expect(reported.timeLabel, '07:10');
      expect(reported.whenLabel, '');
      expect(reported.reRing, isTrue);
    });
  });

  group('the silence window', () {
    // Silence-after is for the time a ring is heard. The host sounds one
    // alarm at a time and holds one that comes due during another, silent,
    // while the plugin's fallback timer tells the app of it at its own
    // instant: counted from there, the window of a held alarm ran out while
    // it waited, and it was silenced moments after it was promoted. When
    // the binding asks is pinned as text in
    // test/android/alert_silence_window_test.dart.

    test('counts while the host sounds this ring', () {
      expect(alertSilenceWindowRuns(sounding: true, anySounding: true), isTrue);
    });

    test('waits while the host sounds another ring and holds this one', () {
      expect(
        alertSilenceWindowRuns(sounding: false, anySounding: true),
        isFalse,
      );
    });

    test('counts when the host sounds nothing: an announced alarm nothing '
        'will promote, or a host that cannot answer', () {
      // The plugin answers `false` to a query that failed, so a waiting
      // window needs the host to say, positively, that another ring
      // sounds — the one bound on a wait that would otherwise keep a
      // silent page up for good.
      expect(
        alertSilenceWindowRuns(sounding: false, anySounding: false),
        isTrue,
      );
    });
  });

  group("the plugin's log", () {
    LogRecord record(Level level) => LogRecord(
      level,
      'Alarm with id 7 started ringing but the settings object could not be '
          'found.',
      'AlarmTriggerApiImpl',
    );

    test('a warning and anything above it is printed, with who said it', () {
      // The line that explains a ring with no page: the plugin drops it with
      // one `severe` and tells nobody else.
      expect(
        alarmPluginLogLine(record(Level.SEVERE)),
        '[alarm] SEVERE AlarmTriggerApiImpl: Alarm with id 7 started ringing '
        'but the settings object could not be found.',
      );
      expect(
        alarmPluginLogLine(record(Level.WARNING)),
        startsWith('[alarm] WARNING AlarmTriggerApiImpl: '),
      );
      expect(alarmPluginLogLine(record(Level.SHOUT)), isNotNull);
    });

    test('its narration stays unprinted', () {
      // One `info` per arm, stop and ring: on a reconcile of the horizon that
      // is dozens of lines saying nothing went wrong.
      expect(alarmPluginLogLine(record(Level.INFO)), isNull);
      expect(alarmPluginLogLine(record(Level.FINE)), isNull);
      expect(alarmPluginLogLine(record(Level.CONFIG)), isNull);
    });
  });

  test('the channel ids are frozen', () {
    // Android freezes a channel's importance, sound and DND behaviour at
    // creation: a changed id is the only way to change any of them, and it
    // orphans the user's own per-channel settings. These are a contract.
    expect(kAlertReminderChannelId, 'alerts_reminder');
    // The quiet kinds' own channel (2026-10), of low importance: the notice,
    // Missed and the session chip left the reminder channel for it, which is
    // one more reason neither id may ever move onto the other.
    expect(kAlertQuietChannelId, 'alerts_quiet');
    expect(kAlertQuietChannelId, isNot(kAlertReminderChannelId));
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
