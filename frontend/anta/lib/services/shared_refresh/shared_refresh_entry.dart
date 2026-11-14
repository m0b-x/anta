import 'dart:io' show Platform;

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../constants/push_constants.dart';
import '../../constants/shared_refresh_constants.dart';
import '../../core/qa/qa_bootstrap.dart';
import 'shared_refresh_app.dart';
import 'shared_refresh_scheduler.dart';
import 'shared_refresh_trigger.dart';

/// Where the platform starts Dart for the check, in an engine of its own
/// with no app behind it (`docs/cloud-shared-freshness.md` §6).
///
/// The platform finds it by a handle stored when the app last scheduled
/// the work, so it stays a top-level function in this library under this
/// name: moved or renamed, a work scheduled by the build before would find
/// nothing to run.
///
/// False asks the platform to run the work again on its back-off; a stop
/// from the platform — its time is up, the network left — ends the run
/// where it is before the isolate is torn down.
///
/// Off Android it returns at once and sets nothing up. Only there does the
/// work get an engine of its own: on iOS the plugin runs a task on the
/// app's engine, where a run "without the app" would register its own
/// dependencies over the app's and close the app's database as it ended.
@pragma('vm:entry-point')
void sharedRefreshEntry() {
  if (!SharedRefreshAvailability.isSupported) return;
  Workmanager().executeTask(
    sharedRefreshTask,
    onTaskStopped: (task, reason) => stopSharedRefresh(),
  );
}

/// The work's engine tells the alarm plugin's host that no ring is to be
/// presented to it — before Firebase and the database come up: until it is
/// told, a ring that starts with no app in the process is reported to this
/// isolate, which shows nothing and ends in seconds. The run's own alert
/// binding says the same as it starts, much later; said twice it is said
/// once.
///
/// A failure is that binding's to act on (`AndroidAlertGateway`): a run
/// whose engine could not resign arms nothing.
Future<void> _resignWithHost() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await Alarm.initWithoutPresenting();
}

/// [resign], for at most [within] ([kPushResignBound]): a host that does
/// not answer holds the work back no longer — unbounded, the trigger was
/// never fired, and a message's waiting note never taken off. An answer
/// that comes later still counts with the host.
Future<void> _resignAsPresenter(
  Future<void> Function() resign,
  Duration within,
) async {
  try {
    await resign().timeout(within);
  } catch (error) {
    debugPrint('[SharedRefresh] engine not resigned at its entry: $error');
  }
}

/// One work of the check as the platform hands it over: its [task] name and
/// the [inputData] it was scheduled with. True unless the platform should
/// run it again.
///
/// Guarded like the entry, for a handler that is reached some other way —
/// one a build before this guard left registered: nothing is fired where
/// no check exists, and nothing is asked for again.
///
/// The preferences are namespaced first, before the resign: the resign
/// opens the alarm fork's storage, which is this isolate's first look at
/// the preferences, and a QA build's prefix has to stand before it — after
/// it the plugin refuses the prefix, and every step that asks for it
/// throws.
///
/// [resign], [resignBound] and [fire] are a suite's stand-ins.
Future<bool> sharedRefreshTask(
  String task,
  Map<String, dynamic>? inputData, {
  Future<void> Function() resign = _resignWithHost,
  Duration resignBound = kPushResignBound,
  Future<bool> Function({
        SharedRefreshCause cause,
        SharedRefreshSlot slot,
        String? pair,
      })
      fire =
      fireSharedRefresh,
}) async {
  if (!SharedRefreshAvailability.isSupported) return true;
  QaBootstrap.namespacePreferences();
  await _resignAsPresenter(resign, resignBound);
  return fire(
    cause: SharedRefreshCause.fromInput(inputData),
    // The check's task is named for the slot it was scheduled in.
    slot: SharedRefreshSlot.ofTask(task),
    pair: switch (inputData?[kSharedRefreshPairKey]) {
      final String pair => pair,
      _ => null,
    },
  );
}
