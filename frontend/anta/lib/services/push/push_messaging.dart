import 'dart:async';
import 'dart:io' show Platform;

import 'package:alarm/alarm.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;

import '../../constants/push_constants.dart';
import '../../constants/settings_keys.dart';
import '../../core/qa/qa_bootstrap.dart';
import '../fresh_preferences.dart';
import '../shared_refresh/shared_refresh_message_gate.dart';
import '../shared_refresh/shared_refresh_scheduler.dart';
import '../shared_refresh/workmanager_shared_refresh_scheduler.dart';
import 'push_registry.dart';

/// The pair a relay message names (`docs/cloud-shared-freshness.md` §7,
/// decision i): `{t: "shared", p: <pair id>}` and nothing else is read.
/// Null for any other kind, or a message that does not say it whole — a pair
/// the relay itself would refuse ([kPushPairPattern]) included.
String? sharedPokePair(Map<String, dynamic> data) {
  final pair = data['p'];
  if (data['t'] != 'shared' || pair is! String) return null;
  return _pairShape.hasMatch(pair) ? pair : null;
}

final RegExp _pairShape = RegExp(kPushPairPattern);

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
///
/// The preferences are namespaced first, as at the check's own entry
/// (`sharedRefreshTask`): the resign that follows opens the alarm fork's
/// storage, this isolate's first look at the preferences, and a QA build's
/// prefix has to stand before it. A QA build registers no handler today;
/// the order is the same in both entries so a later one cannot meet it.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  QaBootstrap.namespacePreferences();
  await handleBackgroundPush(
    message.data,
    scheduler: WorkmanagerSharedRefreshScheduler(),
    resign: resignPushEngine,
  );
}

Future<void> _noResign() async {}

/// Whether this isolate has told the alarm plugin's host that no ring is to
/// be presented to it ([resignPushEngine]).
bool _engineResigned = false;

/// The one ask of the host this isolate has in flight. Kept until it is
/// answered: every message waits on it, each for the bound at most — asked
/// anew by each, a host that did not answer was left one more call pending
/// per message. One that failed is forgotten, and the next message asks
/// again.
Future<void>? _resigning;

Future<void> _resignedOnce(Future<void> Function() resign) {
  late final Future<void> asking;
  asking = Future.sync(resign).then(
    (_) {
      _engineResigned = true;
    },
    onError: (Object error, StackTrace stack) {
      if (identical(_resigning, asking)) _resigning = null;
      Error.throwWithStackTrace(error, stack);
    },
  );
  return asking;
}

@visibleForTesting
void debugForgetPushEngineResigned() {
  _engineResigned = false;
  _resigning = null;
}

/// The messaging plugin keeps one engine for the life of the process, with
/// every plugin attached, and with no app alive the alarm fork's host would
/// pick it as the place a ring is shown — an isolate with no activity,
/// which answers the ring's report with an error (the push review's F13).
/// So it resigns, as the check's own engine does at its entry (the fork's
/// Patch 10). Throws what the host throws; the handler logs it and asks
/// again at the next message.
@visibleForTesting
Future<void> resignPushEngine() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await Alarm.initWithoutPresenting();
}

/// [pushBackgroundHandler]'s work, over [scheduler]: a message that names a
/// pair — the one this install's address was written for, when one was —
/// starts the check for it unless a work for the pair waits already,
/// expedited when the app stored that it may be. Anything else does
/// nothing. Never throws.
///
/// What the app stored is read once per message, off the store
/// ([FreshPreferences]): the app's isolate writes it, and this isolate may
/// have loaded its own copy of the preferences long before — the messaging
/// plugin keeps its engine for the life of the process. A store that cannot
/// be read drops nothing and expedites nothing, the direction that costs no
/// notification.
///
/// [writtenPair] and [expedited] answer in place of the store's
/// [SettingsKeys.pushWritten] and [SettingsKeys.pushExpeditedWork] — a
/// suite's stand-ins, each asked only when the message got that far.
@visibleForTesting
Future<void> handleBackgroundPush(
  Map<String, dynamic> data, {
  required SharedRefreshScheduler scheduler,
  Future<bool> Function()? expedited,
  Future<String?> Function()? writtenPair,
  Future<void> Function() resign = _noResign,
  Duration resignBound = kPushResignBound,
  DateTime Function() clock = DateTime.now,
}) async {
  // First, and for a message that is dropped too: the engine exists
  // whatever the message says. Bounded: a host that does not answer holds
  // no hand-over past the bound, and an answer that comes later still
  // counts.
  if (!_engineResigned) {
    try {
      await (_resigning ??= _resignedOnce(resign)).timeout(resignBound);
    } catch (e) {
      debugPrint('[Push] engine not resigned as a presenter: $e');
    }
  }
  final pair = sharedPokePair(data);
  if (pair == null) return;
  FreshPreferences? stored;
  try {
    stored = await FreshPreferences.read();
  } catch (e) {
    debugPrint('[Push] what the app stored not read: $e');
  }
  // A pair this install's address was not written for costs nothing — no
  // work, no engine, no database. With none written, or none readable, the
  // run's own pair check stands.
  try {
    final written = writtenPair != null
        ? await writtenPair()
        : PushRegistry.writtenPairOf(
            stored?.getString(SettingsKeys.pushWritten),
          );
    if (written != null && written != pair) return;
  } catch (e) {
    debugPrint('[Push] written pair not read: $e');
  }
  // One work waits for the pair already: it reads after it starts, so
  // after the change this message is about.
  final now = clock();
  if (stored != null &&
      SharedRefreshMessageGate.waitsIn(stored, pair, now: now)) {
    return;
  }
  await SharedRefreshMessageGate.mark(pair, now: now);
  var expedite = false;
  try {
    expedite = expedited != null
        ? await expedited()
        : stored?.getString(SettingsKeys.pushExpeditedWork) != null;
  } catch (e) {
    debugPrint('[Push] expedited not read: $e');
  }
  try {
    await scheduler.scheduleMessage(pair, expedited: expedite);
    return;
  } catch (e) {
    if (!expedite) {
      debugPrint('[Push] message work not scheduled: $e');
      await SharedRefreshMessageGate.unmark(pair);
      return;
    }
    debugPrint('[Push] expedited work refused, asked plain: $e');
  }
  // The plugin refuses an expedited work before it enqueues anything — a
  // permission gone from the merged manifest, a quota — and a plain one
  // still runs the check, later.
  try {
    await scheduler.scheduleMessage(pair, expedited: false);
  } catch (e) {
    debugPrint('[Push] message work not scheduled: $e');
    await SharedRefreshMessageGate.unmark(pair);
  }
}
