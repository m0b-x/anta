import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/settings_keys.dart';
import '../shared_refresh/shared_refresh_scheduler.dart';
import '../shared_refresh/workmanager_shared_refresh_scheduler.dart';

/// The pair a relay message names (`docs/cloud-shared-freshness.md` §7,
/// decision i): `{t: "shared", p: <pair id>}` and nothing else is read.
/// Null for any other kind, or a message that does not say it whole.
String? sharedPokePair(Map<String, dynamic> data) {
  final pair = data['p'];
  if (data['t'] != 'shared' || pair is! String || pair.isEmpty) return null;
  return pair;
}

/// The messaging plugin's two doors for a message, behind one seam so the
/// receiver's suite decides what arrives and nothing reaches the platform
/// unless this install holds an address.
abstract interface class PushMessaging {
  /// The data of each message that arrives with the app in front.
  Stream<Map<String, dynamic>> get foreground;

  /// Hands the platform [pushBackgroundHandler], for a message that arrives
  /// with the app not in front.
  Future<void> registerBackgroundHandler();
}

/// Bound wherever push cannot work — not Android, a QA build, the run with
/// the app closed: nothing arrives, nothing is handed over.
class NoOpPushMessaging implements PushMessaging {
  const NoOpPushMessaging();

  @override
  Stream<Map<String, dynamic>> get foreground =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> registerBackgroundHandler() async {}
}

/// [PushMessaging] over `firebase_messaging` 17.
///
/// The handler's handles are kept by the plugin in the app's own
/// preferences and read back when a message arrives with no app running;
/// the Dart side sends them once per process, and an update may change
/// them — so they are handed over in every process that takes an address
/// into use, never once for good.
class FirebasePushMessaging implements PushMessaging {
  const FirebasePushMessaging();

  @override
  Stream<Map<String, dynamic>> get foreground {
    // The plugin answers its native side only once its instance is built.
    FirebaseMessaging.instance.isAutoInitEnabled;
    return FirebaseMessaging.onMessage.map((message) => message.data);
  }

  @override
  Future<void> registerBackgroundHandler() async =>
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
}

/// Where the platform runs Dart for a message that arrives with the app not
/// in front: an isolate of the plugin's own, beside whatever else runs.
///
/// It opens no database and builds no service — the app's one isolate holds
/// the database (decision d) — but hands the read to the check's own work,
/// started now, and returns. It stays a top-level function under this name:
/// the platform finds it by a handle stored when the app last handed it
/// over.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) =>
    handleBackgroundPush(
      message.data,
      scheduler: WorkmanagerSharedRefreshScheduler(),
      expedited: storedExpedited,
    );

/// What the app wrote when it last handed the handler over
/// ([SettingsKeys.pushExpeditedWork]): one read of the preferences, no
/// database. Absent is false.
@visibleForTesting
Future<bool> storedExpedited() async =>
    (await SharedPreferences.getInstance()).getString(
      SettingsKeys.pushExpeditedWork,
    ) !=
    null;

/// [pushBackgroundHandler]'s work, over [scheduler]: a message that names a
/// pair starts the check for it, [expedited] when that answers true — asked
/// only then, and any failure of it is false, the direction that costs no
/// notification; anything else does nothing. Never throws.
@visibleForTesting
Future<void> handleBackgroundPush(
  Map<String, dynamic> data, {
  required SharedRefreshScheduler scheduler,
  required Future<bool> Function() expedited,
}) async {
  final pair = sharedPokePair(data);
  if (pair == null) return;
  var expedite = false;
  try {
    expedite = await expedited();
  } catch (e) {
    debugPrint('[Push] expedited not read: $e');
  }
  try {
    await scheduler.scheduleMessage(pair, expedited: expedite);
  } catch (e) {
    debugPrint('[Push] message work not scheduled: $e');
  }
}
