import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:alarm/src/android_alarm.dart';
import 'package:alarm/src/ios_alarm.dart';
import 'package:flutter_fgbg/flutter_fgbg.dart';
import 'package:logging/logging.dart';

/// Fallback logic for platform alarm triggering (iOS and Android).
class PlatformTimers {
  static final _log = Logger('PlatformTimers');

  /// Map of alarm timers.
  static final Map<int, Timer?> _timers = {};

  /// Map of foreground/background subscriptions.
  static final Map<int, StreamSubscription<FGBGType>?> _fgbgSubscriptions = {};

  /// Listens for alarm trigger.
  static void setAlarm(AlarmSettings settings) {
    final id = settings.id;

    final timer = _timers[id];
    if (timer != null && timer.isActive) {
      _disposeAlarm(id);
    }

    _timers[id] = _periodicTimer(
      () => unawaited(_alarmRang(settings)),
      settings.dateTime,
      id,
    );

    _listenAppStateChange(
      id: id,
      onBackground: () => _disposeTimer(id),
      onForeground: () async {
        if (_fgbgSubscriptions[id] == null) return;

        bool alarmIsRinging;
        if (Platform.isIOS) {
          alarmIsRinging = await IOSAlarm().isRinging(id);
        } else if (Platform.isAndroid) {
          alarmIsRinging = await AndroidAlarm().isRinging(id);
        } else {
          // Fallback for other platforms (though unlikely in this package)
          alarmIsRinging = false;
        }

        if (alarmIsRinging) {
          _disposeAlarm(id);
          unawaited(_alarmRang(settings));
        } else {
          final timer = _timers[id];
          if (timer != null && timer.isActive) {
            timer.cancel();
          }
          _timers[id] = _periodicTimer(
            () => unawaited(_alarmRang(settings)),
            settings.dateTime,
            id,
          );
        }
      },
    );
  }

  /// Stops listening for alarm trigger.
  static void stopAlarm(int id) {
    _disposeAlarm(id);
  }

  /// Stops listening for all alarm triggers.
  static void stopAll() {
    _timers.forEach((_, timer) => timer?.cancel());
    _fgbgSubscriptions.forEach((_, sub) => sub?.cancel());
    _timers.clear();
    _fgbgSubscriptions.clear();
  }

  /// Listens when app goes foreground so we can check if alarm is ringing.
  /// When app goes background, periodical timer will be disposed.
  static void _listenAppStateChange({
    required int id,
    required void Function() onForeground,
    required void Function() onBackground,
  }) {
    // Cancel any previous subscription for this id so replacing an alarm
    // never leaks a listener.
    _fgbgSubscriptions[id]?.cancel();
    _fgbgSubscriptions[id] = FGBGEvents.instance.stream.listen((event) {
      if (event == FGBGType.foreground) onForeground();
      if (event == FGBGType.background) onBackground();
    });
  }

  /// Checks periodically if alarm is ringing, as long as app is in foreground.
  static Timer _periodicTimer(void Function()? onRing, DateTime dt, int id) {
    return Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (DateTime.now().isBefore(dt)) return;
      _disposeAlarm(id);
      onRing?.call();
    });
  }

  /// Disposes alarm timer.
  static void _disposeTimer(int id) {
    _timers[id]?.cancel();
    _timers.removeWhere((key, value) => key == id);
  }

  /// Disposes alarm timer and FGBG subscription.
  static void _disposeAlarm(int id) {
    _disposeTimer(id);
    _fgbgSubscriptions[id]?.cancel();
    _fgbgSubscriptions.removeWhere((key, value) => key == id);
  }

  static Future<void> _alarmRang(AlarmSettings settings) async {
    if (Alarm.ringing.value.contains(settings)) {
      _log.info('Alarm timer triggered but alarm is already marked as ringing. '
          'Info: ${settings.toJson()}');
      return;
    }

    // Give the native platform sometime to notify Flutter.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (Alarm.ringing.value.contains(settings)) {
      _log.info('Alarm timer triggered but native marked the alarm as ringing '
          'shortly after. Info: ${settings.toJson()}');
      return;
    }

    // (ANTA fork, Patch 7) Not ringing now is not the same as never reported.
    // An alarm the platform did report, and that was stopped, snoozed or set
    // again inside the wait above, is not in the ringing set either — and
    // announcing it here would tell the application of a ring that is over.
    // What tells the two apart is the scheduled set: `Alarm.alarmRang` takes
    // an alarm out of it as it puts it into the ringing one, and every stop
    // takes it out of both. So only an alarm the platform never told of — the
    // case this fallback exists for, and the alarm the host holds back while
    // another one sounds — is still scheduled when the wait ends.
    if (!_isScheduledAs(settings)) {
      _log.info('Alarm timer triggered but the alarm was reported, and then '
          'stopped or set again, while waiting. Info: ${settings.toJson()}');
      return;
    }

    _log.warning('Alarm had to be triggered manually via timer. '
        'Info: ${settings.toJson()}');
    Alarm.alarmRang(settings);
  }

  /// Whether [Alarm.scheduled] still holds exactly [settings].
  ///
  /// Compared whole, where the set itself goes by id alone: an alarm snoozed
  /// from the application is armed again under the id it rang under, and the
  /// id being scheduled once more — for another time — says nothing of the
  /// ring this timer was started for.
  static bool _isScheduledAs(AlarmSettings settings) =>
      Alarm.scheduled.value.alarms.any((alarm) => alarm == settings);
}
