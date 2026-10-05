import 'package:alarm/alarm.dart';
import 'package:alarm/service/alarm_storage.dart';
import 'package:alarm/src/alarm_trigger_api_impl.dart';
import 'package:alarm/src/generated/platform_bindings.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_host.dart';

/// Delivers one of the host's two calls about a ring — `alarmRang` once the
/// alarm is audible, `alarmStopped` when it ended on the host's side — the
/// way the host would with an engine attached.
Future<void> hostCalls(String method, int alarmId) async {
  final encoded = AlarmTriggerApi.pigeonChannelCodec.encodeMessage(
    <Object?>[alarmId],
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'dev.flutter.pigeon.alarm.AlarmTriggerApi.$method',
    encoded,
    (_) {},
  );
}

/// ANTA fork, Patch 7: the fallback timer beside every alarm
/// (`PlatformTimers`).
///
/// While the app is in front, a Dart timer waits for each alarm's due time
/// and, when the platform has not reported the ring by then, gives it 700 ms
/// more and announces the ring itself. "Not ringing after the wait" used to
/// be all it asked — and an alarm the platform did report, stopped inside
/// those 700 ms, is not ringing either. A Stop pressed within half a second
/// of the alarm page coming up was followed by a second announcement of a
/// ring that was over.
///
/// The timers run on fake time (`testWidgets`); the due time is compared with
/// the wall clock, so "due now" is a time already behind it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final android = TargetPlatformVariant.only(TargetPlatform.android);

  /// The timer's period, and so the longest it takes to notice a due alarm.
  const tick = Duration(milliseconds: 200);

  /// Somewhere inside the 700 ms the timer then gives the platform.
  const intoTheWait = Duration(milliseconds: 300);

  /// Comfortably past the end of them.
  const pastTheWait = Duration(milliseconds: 800);

  late FakeHost host;
  late List<LogRecord> timerLog;

  AlarmSettings buildAlarm(int id, DateTime dateTime) => AlarmSettings(
        id: id,
        dateTime: dateTime,
        volumeSettings: const VolumeSettings.fixed(),
        notificationSettings: const NotificationSettings(
          title: 'Wake up',
          body: '',
        ),
      );

  /// What the fallback announced by itself: its one warning per ring.
  List<String> announcedByTimer() => [
        for (final record in timerLog)
          if (record.level >= Level.WARNING) record.message,
      ];

  /// Whether [alarmId] was ringing, change by change, as a listener of
  /// `Alarm.ringing` sees it — which is how an application learns of a ring.
  List<bool> ringingHistoryOf(int alarmId) {
    final history = <bool>[];
    final subscription = Alarm.ringing.listen((set) {
      final ringing = set.containsId(alarmId);
      if (history.isEmpty || history.last != ringing) history.add(ringing);
    });
    addTearDown(subscription.cancel);
    return history;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Alarm.resetForTesting();
    AlarmStorage.resetForTesting();
    AlarmTriggerApiImpl.resetForTesting();
    host = FakeHost()..install();
    timerLog = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'PlatformTimers') timerLog.add(record);
    });
    addTearDown(subscription.cancel);
  });

  tearDown(() {
    host.remove();
    Alarm.resetForTesting();
    AlarmStorage.resetForTesting();
    AlarmTriggerApiImpl.resetForTesting();
  });

  group('a ring the platform reported, then over inside the wait', () {
    testWidgets(
      'is not announced again after a stop',
      (tester) async {
        await Alarm.init();
        await Alarm.set(alarmSettings: buildAlarm(42, DateTime.now()));
        final history = ringingHistoryOf(42);

        // The tick finds the alarm due and not ringing yet, and waits.
        await tester.pump(tick);
        await hostCalls('alarmRang', 42);
        await tester.pump(intoTheWait);
        expect(Alarm.ringing.value.containsId(42), isTrue);

        // Stop on the application's own screen, half a second in.
        await Alarm.stop(42);
        await tester.pump(pastTheWait);

        expect(Alarm.ringing.value.alarms, isEmpty);
        expect(history, [false, true, false]);
        expect(announcedByTimer(), isEmpty);
      },
      variant: android,
    );

    testWidgets(
      "is not announced again after a stop on the host's own notification",
      (tester) async {
        // The ending that never passes through `Alarm.stop`, and so never
        // tells the timers anything.
        await Alarm.init();
        await Alarm.set(alarmSettings: buildAlarm(42, DateTime.now()));
        final history = ringingHistoryOf(42);

        await tester.pump(tick);
        await hostCalls('alarmRang', 42);
        await tester.pump(intoTheWait);
        await hostCalls('alarmStopped', 42);
        await tester.pump(pastTheWait);

        expect(Alarm.ringing.value.alarms, isEmpty);
        expect(history, [false, true, false]);
        expect(announcedByTimer(), isEmpty);
      },
      variant: android,
    );

    testWidgets(
      'is not announced under its old settings once it is set again',
      (tester) async {
        // A snooze taken in the application re-arms under the id the alarm
        // rang under, so the scheduled set holds that id again — for another
        // time.
        await Alarm.init();
        await Alarm.set(alarmSettings: buildAlarm(42, DateTime.now()));
        final history = ringingHistoryOf(42);

        await tester.pump(tick);
        await hostCalls('alarmRang', 42);
        await tester.pump(intoTheWait);
        final snoozedUntil = DateTime.now().add(const Duration(minutes: 10));
        await Alarm.set(alarmSettings: buildAlarm(42, snoozedUntil));
        await tester.pump(pastTheWait);

        expect(Alarm.ringing.value.alarms, isEmpty);
        expect(history, [false, true, false]);
        expect(announcedByTimer(), isEmpty);
        // And the alarm that replaced it is still owed: announcing the old
        // one takes whatever holds its id out of the scheduled set.
        expect(Alarm.scheduled.value.alarms.single.dateTime, snoozedUntil);

        // Nothing may still be ticking when a fake-time test ends.
        await Alarm.stop(42);
      },
      variant: android,
    );

    testWidgets(
      "is not announced once the host's own snooze has moved it",
      (tester) async {
        await Alarm.init();
        await Alarm.set(alarmSettings: buildAlarm(42, DateTime.now()));
        final history = ringingHistoryOf(42);

        await tester.pump(tick);
        await hostCalls('alarmRang', 42);
        await tester.pump(intoTheWait);
        final snoozedUntil = DateTime.now().add(const Duration(minutes: 9));
        await hostReportsEvent(snoozeEvent(42, snoozedUntil));
        await tester.pump(pastTheWait);

        expect(Alarm.ringing.value.alarms, isEmpty);
        expect(history, [false, true, false]);
        expect(announcedByTimer(), isEmpty);
        expect(
          Alarm.scheduled.value.alarms.single.dateTime.millisecondsSinceEpoch,
          snoozedUntil.millisecondsSinceEpoch,
        );

        await Alarm.stop(42);
      },
      variant: android,
    );
  });

  group('a ring the platform never reported', () {
    testWidgets(
      'is announced by the timer, once',
      (tester) async {
        // What the fallback is for.
        await Alarm.init();
        final alarm = buildAlarm(42, DateTime.now());
        await Alarm.set(alarmSettings: alarm);
        final history = ringingHistoryOf(42);

        await tester.pump(tick);
        expect(Alarm.ringing.value.alarms, isEmpty);
        await tester.pump(pastTheWait);

        expect(Alarm.ringing.value.alarms.single, alarm);
        expect(Alarm.scheduled.value.alarms, isEmpty);
        expect(history, [false, true]);
        expect(announcedByTimer(), hasLength(1));
      },
      variant: android,
    );

    testWidgets(
      'is announced while another alarm sounds: the one the host holds back',
      (tester) async {
        // Two alarms due together. The host sounds one and queues the other
        // without a word, so this timer is all that tells of the second.
        await Alarm.init();
        final due = DateTime.now();
        final held = buildAlarm(42, due).copyWith(
          allowSameSecondScheduling: true,
        );
        await Alarm.set(alarmSettings: buildAlarm(41, due));
        await Alarm.set(alarmSettings: held);
        final soundingHistory = ringingHistoryOf(41);
        final heldHistory = ringingHistoryOf(42);

        await tester.pump(tick);
        await hostCalls('alarmRang', 41);
        await tester.pump(pastTheWait);

        expect(
          Alarm.ringing.value.alarms.map((alarm) => alarm.id),
          unorderedEquals(<int>[41, 42]),
        );
        expect(soundingHistory, [false, true]);
        expect(heldHistory, [false, true]);
        // Only the held one needed the timer.
        expect(announcedByTimer(), hasLength(1));
        expect(announcedByTimer().single, contains('id: 42,'));
      },
      variant: android,
    );
  });
}
