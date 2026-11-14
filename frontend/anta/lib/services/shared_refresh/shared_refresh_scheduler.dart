import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/settings_keys.dart';
import '../../constants/shared_refresh_constants.dart';

/// Single gate for whether this device reads what a partner shares while
/// the app is closed: Android alone (`docs/cloud-shared-freshness.md` §10).
///
/// What the binding and the words go by — the read sheet's caption and the
/// guide say what is true on the device they run on.
///
/// [kIsWeb] is checked first because `dart:io`'s [Platform] throws on web.
abstract final class SharedRefreshAvailability {
  static bool get isSupported =>
      debugSupported ?? (!kIsWeb && Platform.isAndroid);

  /// A suite's stand-in for the platform, so both sets of words can be
  /// drawn on the machine the tests run on. Null is the platform's answer.
  @visibleForTesting
  static bool? debugSupported;

  /// Whether anything could start a run of the check on this install: a
  /// check was planned at some time, or a push address is held, so the
  /// partner's change can arrive as a message. What an install that never
  /// paired is spared goes by this — the timer that keeps the app's name,
  /// and the arm facts kept for a run. From the preferences the launch has
  /// already loaded; unreadable, the answer is yes.
  static Future<bool> runsCanExist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(SettingsKeys.sharedRefreshPlanned) ||
          prefs.getString(SettingsKeys.pushAddressHeld) != null;
    } catch (error) {
      debugPrint('[SharedRefresh] triggers not known: $error');
      return true;
    }
  }
}

/// The two unique names the check's work lives under, one at a time.
///
/// Two, because a run is itself the work under one of them, and replacing
/// a unique work cancels it: a run that scheduled its successor under its
/// own name was stopped by the platform right after it had planned, before
/// it read anything (device pass, 2026-11-13). A run schedules into the
/// slot it is **not** running in; the app, which runs in no work, writes
/// the first and takes the second off.
enum SharedRefreshSlot {
  first(kSharedRefreshWorkName),
  second(kSharedRefreshSecondWorkName);

  /// The work's unique name, and the task name its run is handed — how a
  /// run knows which slot it is.
  final String workName;

  const SharedRefreshSlot(this.workName);

  SharedRefreshSlot get other => this == first ? second : first;

  /// The slot a run is in, from the task name the platform handed it; the
  /// first for a name this build does not know, which only a build that
  /// had one slot could have scheduled.
  static SharedRefreshSlot ofTask(String? taskName) =>
      taskName == second.workName ? second : first;
}

/// The platform's half of the check: one one-off work, run once the
/// network is there (`docs/cloud-shared-freshness.md` §4). A seam, so the
/// planning above it is proven against a fake and desktop binds nothing.
abstract interface class SharedRefreshScheduler {
  /// Runs the check once, [delay] from now, in place of whatever stood
  /// scheduled. The platform keeps it across a restart of the phone.
  ///
  /// [runningIn]: the slot of the work that is running while this is asked
  /// — the run itself, or the worker whose read the app is doing for it.
  /// The check then goes into the other slot and the running one is left
  /// alone; with none running it goes into the first and the second is
  /// taken off.
  Future<void> schedule(Duration delay, {SharedRefreshSlot? runningIn});

  /// Takes the scheduled check off; nothing when none stands. Never the
  /// work that is running ([runningIn]): it is ending by itself.
  Future<void> cancel({SharedRefreshSlot? runningIn});

  /// Whether the platform holds the check's work in [slot], waiting or
  /// running. Null when it cannot tell — a binding with no platform, a
  /// question that failed: the asker then goes by what it remembers.
  ///
  /// What the plan's memory is checked against before it is relied on to
  /// schedule nothing (`SharedRefresh`): the memory is restored with the
  /// phone's backup and the works are not, and a work can be consumed or
  /// lost with nobody writing it off.
  Future<bool?> stands(SharedRefreshSlot slot);

  /// Runs the check now for a relay message naming [pairId], under a work
  /// of its own — in neither slot, never touching the schedule's — and in
  /// place of any message's work that stands: at most one does, the newest.
  /// [expedited] lets it run on a phone asleep, where the platform can do
  /// so without a notification.
  ///
  /// [behindRunning]: asked by a message's work that is running, for the
  /// read it still owes — the fresh work goes behind it, and the work that
  /// asks is left to end by itself.
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  });
}

/// The binding of a platform with no background work: the desktop builds,
/// iOS until its slice, and a QA build that keeps sync off.
class NoOpSharedRefreshScheduler implements SharedRefreshScheduler {
  const NoOpSharedRefreshScheduler();

  @override
  Future<void> schedule(Duration delay, {SharedRefreshSlot? runningIn}) async {}

  @override
  Future<void> cancel({SharedRefreshSlot? runningIn}) async {}

  @override
  Future<bool?> stands(SharedRefreshSlot slot) async => null;

  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  }) async {}
}
