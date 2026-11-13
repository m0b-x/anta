import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/push_constants.dart';
import '../../constants/settings_keys.dart';
import 'push_address_source.dart';
import 'push_messaging.dart';

/// What a relay message does with the app in front
/// (`docs/cloud-shared-freshness.md` §7, "The message"): one that names the
/// open database's pair asks for the shared read now, a burst of them as one
/// read a moment later; any other message is ignored. The open calendar and
/// a partner's open note then follow by the paths a read already takes.
///
/// Listens, and hands the background handler over, only once this install
/// holds an address ([start], [addressInUse]): an account that never paired
/// asks the platform nothing for it. Global like the registry; the open
/// database is asked at each message.
class PushReceiver {
  final PushMessaging _messaging;
  final PushAddressSource _addresses;
  final Future<String?> Function() _openPair;
  final Future<void> Function() _readShared;
  final Future<int?> Function() _sdkLevel;
  final Future<SharedPreferences> _prefs;
  final Duration _coalesce;

  StreamSubscription<Map<String, dynamic>>? _listening;
  final Set<String> _heard = {};
  Timer? _gathering;

  /// [openPair] answers the open database's pair; [readShared] asks the
  /// engine for the shared read now — the engine's own floor, never the
  /// Sharing page's, since a message means something changed. [sdkLevel]
  /// answers the phone's Android API level, kept in [prefs] for the
  /// background handler ([SettingsKeys.pushExpeditedWork]).
  PushReceiver({
    required PushMessaging messaging,
    required PushAddressSource addresses,
    required Future<String?> Function() openPair,
    required Future<void> Function() readShared,
    required Future<int?> Function() sdkLevel,
    required Future<SharedPreferences> prefs,
    Duration coalesce = kPushMessageCoalesce,
  }) : _messaging = messaging,
       _addresses = addresses,
       _openPair = openPair,
       _readShared = readShared,
       _sdkLevel = sdkLevel,
       _prefs = prefs,
       _coalesce = coalesce;

  /// At launch: listens when this install holds an address — one preference
  /// read, nothing asked of the platform otherwise. Never throws.
  Future<void> start() async {
    try {
      if (await _addresses.holds()) await addressInUse();
    } catch (e) {
      debugPrint('[PushReceiver] not started: $e');
    }
  }

  /// The registry took an address into use or confirmed one: listen if not
  /// yet, and hand the background handler over again — the platform keeps
  /// its handle, and an update may have changed it. Never throws.
  ///
  /// Before each hand-over, whether this phone runs an expedited work
  /// without a notification is written for the handler, which cannot ask
  /// the activity: a handler never runs on an answer older than its own
  /// hand-over, and a write that fails does not stop it.
  Future<void> addressInUse() async {
    await _storeExpedited();
    try {
      _listening ??= _messaging.foreground.listen(
        _onMessage,
        onError: (Object e) => debugPrint('[PushReceiver] stream: $e'),
      );
      await _messaging.registerBackgroundHandler();
    } catch (e) {
      debugPrint('[PushReceiver] not listening: $e');
    }
  }

  /// [SettingsKeys.pushExpeditedWork] as the phone's API level says: set at
  /// [kExpeditedWorkMinSdk] and above, removed for anything else — a lower
  /// level, no answer, a failed one.
  Future<void> _storeExpedited() async {
    var expedited = false;
    try {
      final level = await _sdkLevel();
      expedited = level != null && level >= kExpeditedWorkMinSdk;
    } catch (e) {
      debugPrint('[PushReceiver] API level not read: $e');
    }
    try {
      final prefs = await _prefs;
      if (expedited) {
        await prefs.setString(SettingsKeys.pushExpeditedWork, '1');
      } else {
        await prefs.remove(SettingsKeys.pushExpeditedWork);
      }
    } catch (e) {
      debugPrint('[PushReceiver] expedited not stored: $e');
    }
  }

  void _onMessage(Map<String, dynamic> data) {
    final pair = sharedPokePair(data);
    if (pair == null) return;
    _heard.add(pair);
    _gathering ??= Timer(_coalesce, () => unawaited(_read()));
  }

  Future<void> _read() async {
    _gathering = null;
    final heard = {..._heard};
    _heard.clear();
    try {
      final open = await _openPair();
      // Another database's pair: it is read when that database is open
      // (case B13).
      if (open == null || !heard.contains(open)) return;
      await _readShared();
    } catch (e) {
      debugPrint('[PushReceiver] read not asked for: $e');
    }
  }

  Future<void> dispose() async {
    _gathering?.cancel();
    _gathering = null;
    await _listening?.cancel();
    _listening = null;
  }
}
