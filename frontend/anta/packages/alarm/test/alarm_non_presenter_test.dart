import 'package:alarm/alarm.dart';
import 'package:alarm/service/alarm_storage.dart';
import 'package:alarm/src/alarm_trigger_api_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_host.dart';

/// ANTA fork, Patch 10: an engine that is not a presenter
/// (`Alarm.initWithoutPresenting`).
///
/// A background engine — a WorkManager run, with no activity and a life of
/// seconds — sets and stops alarms like any other. With no app in the process
/// it used to be the only engine the host could report to, so a ring during
/// its life was shown to it, and whatever the application timed from that
/// ring ended with the isolate. Its `Alarm.init()` also re-set every stored
/// future alarm each time such an engine started.
///
/// The host's half — which engine a ring is reported to — is pinned in Kotlin
/// (`AlarmPluginTest`). Here: what this isolate says to the host, and what it
/// no longer does by itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final android = TargetPlatformVariant.only(TargetPlatform.android);
  const presenter = MethodChannel('com.gdelataillade.alarm/presenter');

  /// The fallback timer's period, and comfortably past the 700 ms it then
  /// gives the platform.
  const tick = Duration(milliseconds: 200);
  const pastTheWait = Duration(milliseconds: 800);

  late FakeHost host;
  late List<String> said;
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

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Alarm.resetForTesting();
    AlarmStorage.resetForTesting();
    AlarmTriggerApiImpl.resetForTesting();
    host = FakeHost()..install();
    said = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(presenter, (call) async {
      said.add(call.method);
      return null;
    });
    timerLog = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen((record) {
      if (record.loggerName == 'PlatformTimers') timerLog.add(record);
    });
    addTearDown(subscription.cancel);
  });

  tearDown(() {
    host.remove();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(presenter, null);
    Alarm.resetForTesting();
    AlarmStorage.resetForTesting();
    AlarmTriggerApiImpl.resetForTesting();
  });

  testWidgets(
    'tells the host it presents nothing, and reconciles nothing: no stored '
    'alarm is set again or stopped, and the host is not drained',
    (tester) async {
      final now = DateTime.now();
      await AlarmStorage.saveAlarm(
        buildAlarm(1, now.add(const Duration(hours: 1))),
      );
      await AlarmStorage.saveAlarm(
        buildAlarm(2, now.subtract(const Duration(minutes: 2))),
      );

      await Alarm.initWithoutPresenting();

      expect(said, ['resign']);
      expect(Alarm.presents, isFalse);
      expect(host.calls, isEmpty);
      expect(
        (await Alarm.getAlarms()).map((alarm) => alarm.id),
        unorderedEquals(<int>[1, 2]),
      );
    },
    variant: android,
  );

  testWidgets(
    'the presenting start is what it was: the future alarm is set again, the '
    'dead one stopped, the host drained, and nothing is said of resigning',
    (tester) async {
      final now = DateTime.now();
      await AlarmStorage.saveAlarm(
        buildAlarm(1, now.add(const Duration(hours: 1))),
      );
      await AlarmStorage.saveAlarm(
        buildAlarm(2, now.subtract(const Duration(minutes: 2))),
      );

      await Alarm.init();

      expect(said, isEmpty);
      expect(Alarm.presents, isTrue);
      expect(
        host.calls,
        containsAll(<String>['getPendingAlarmEvents', 'setAlarm', 'stopAlarm']),
      );

      // The alarm set again has its fallback timer, which fake time would
      // otherwise find still pending as the test ends.
      Alarm.resetForTesting();
    },
    variant: android,
  );

  testWidgets(
    'sets and stops through the host like any engine, and arms no fallback '
    'timer: an alarm that comes due is announced to nobody here',
    (tester) async {
      await Alarm.initWithoutPresenting();

      final set = await Alarm.set(
        alarmSettings: buildAlarm(42, DateTime.now()),
      );
      await tester.pump(tick);
      await tester.pump(pastTheWait);

      expect(set, isTrue);
      expect(host.calls, ['setAlarm']);
      expect(Alarm.ringing.value.alarms, isEmpty);
      expect(timerLog, isEmpty);

      await Alarm.stop(42);
      expect(host.calls, ['setAlarm', 'stopAlarm']);
      expect(await Alarm.getAlarms(), isEmpty);
    },
    variant: android,
  );

  testWidgets(
    'where a presenting isolate announces the same alarm by its timer',
    (tester) async {
      await Alarm.init();

      await Alarm.set(alarmSettings: buildAlarm(42, DateTime.now()));
      await tester.pump(tick);
      await tester.pump(pastTheWait);

      expect(Alarm.ringing.value.containsId(42), isTrue);
    },
    variant: android,
  );

  testWidgets(
    'a host that cannot be told is no start at all: the isolate must not go '
    'on as a presenter by accident',
    (tester) async {
      // Answered in the test's own zone: a channel left with no handler is
      // answered by the real engine, which fake time never hears from.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        presenter,
        (call) async => throw MissingPluginException(call.method),
      );

      await expectLater(
        Alarm.initWithoutPresenting(),
        throwsA(isA<MissingPluginException>()),
      );
      expect(Alarm.presents, isFalse);
      expect(host.calls, isEmpty);
    },
    variant: android,
  );
}
