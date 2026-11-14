import 'dart:async';

import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/push_constants.dart';
import '../../constants/settings_keys.dart';
import '../../models/pair_record.dart';
import '../fresh_preferences.dart';
import 'push_address_source.dart';

/// The two plugin objects an address is made and ended with, behind one
/// seam so the source's suite decides what the platform answers.
abstract interface class PushPlatform {
  /// `FirebaseMessaging.onRegistered`: the installation id, each time a
  /// registration completes. It does not replay.
  Stream<String> get registered;

  Future<void> register();
  Future<void> unregister();

  /// `FirebaseInstallations.delete()`: the only call after which the next
  /// registration names a new id.
  Future<void> deleteInstallation();
}

/// [PushPlatform] over `firebase_messaging` 17's installation-id API and
/// `firebase_app_installations`.
class FirebasePushPlatform implements PushPlatform {
  const FirebasePushPlatform();

  @override
  Stream<String> get registered => FirebaseMessaging.instance.onRegistered;

  @override
  Future<void> register() => FirebaseMessaging.instance.register();

  @override
  Future<void> unregister() => FirebaseMessaging.instance.unregister();

  @override
  Future<void> deleteInstallation() => FirebaseInstallations.instance.delete();
}

/// [PushAddressSource] over FCM's installation-id API (`firebase_messaging`
/// 17): the address is the Firebase Installation ID a registration names
/// through `onRegistered`, never the deprecated token.
///
/// FCM's `unregister()` ends the registration but keeps the installation,
/// so the next `register()` would name the same id again; [giveUp] deletes
/// the installation too, which is what makes the next one new (decision n).
/// A delete that failed is owed — kept for the install — and paid before
/// the next registration, so an ended address never comes back. Auto-init
/// stays off in the manifest: nothing registers until [current] is asked.
class FirebasePushAddressSource implements PushAddressSource {
  final PushPlatform _platform;
  final Future<SharedPreferences> _prefs;
  final Duration _deadline;
  final Duration _endDeadline;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _listening;
  String? _last;

  /// Which address life this is: a [giveUp] starts the next, and a name the
  /// platform gives for a registration of an earlier one is not this
  /// install's address any more.
  int _epoch = 0;

  /// The life the registration in flight, or the last one made, belongs
  /// to; null when none has been asked for since the last [giveUp].
  int? _registeredIn;

  /// The registration in flight, shared by every caller that asks meanwhile.
  Future<String?>? _registering;

  FirebasePushAddressSource({
    PushPlatform platform = const FirebasePushPlatform(),
    Future<SharedPreferences>? prefs,
    Duration deadline = kPushRegisterDeadline,
    Duration endDeadline = kPushEndDeadline,
  }) : _platform = platform,
       _prefs = prefs ?? SharedPreferences.getInstance(),
       _deadline = deadline,
       _endDeadline = endDeadline;

  @override
  String get kind => PairPushDevice.kindFid;

  @override
  Stream<String> get addresses {
    late final StreamController<String> replay;
    StreamSubscription<String>? live;
    replay = StreamController<String>(
      onListen: () {
        final last = _last;
        if (last != null) replay.add(last);
        live = _controller.stream.listen(replay.add);
      },
      onCancel: () => live?.cancel(),
    );
    return replay.stream;
  }

  @override
  Future<String?> current() {
    final last = _last;
    if (last != null) return Future.value(last);
    return _registering ??= _registerOnce().whenComplete(
      () => _registering = null,
    );
  }

  Future<String?> _registerOnce() async {
    if (!await _paidOwed()) return null;
    // Subscribed before `register()`, as the API asks: the stream does not
    // replay, and a phone already registered names its id at once.
    _listening ??= _platform.registered.listen(
      _heard,
      onError: (Object e) => debugPrint('[PushAddress] stream failed: $e'),
    );
    final epoch = _epoch;
    _registeredIn = epoch;
    final named = _controller.stream.first;
    // Held from the ask on: a registration whose name never reached this
    // process may still have registered the installation.
    await _mark(SettingsKeys.pushAddressHeld, true);
    try {
      await _platform.register();
      return await named.timeout(_deadline);
    } catch (e) {
      // A name that comes later is still taken, and held ([_heard]).
      debugPrint('[PushAddress] not registered yet: $e');
      return epoch == _epoch ? _last : null;
    }
  }

  void _heard(String address) {
    if (address.isEmpty || _registeredIn != _epoch) return;
    if (address == _last) return;
    _last = address;
    // Held the moment it is in use, however late it came.
    unawaited(_mark(SettingsKeys.pushAddressHeld, true));
    _controller.add(address);
  }

  /// An owed delete alone is not held: it is paid at launch and before the
  /// next registration, and nothing is listened to for it.
  @override
  Future<bool> holds() async =>
      (await _prefs).getString(SettingsKeys.pushAddressHeld) != null;

  /// Whether an address is held, and whether the end of one is still owed,
  /// as the store says now. A give-up may be asked by an isolate that did
  /// not take the address — the check's run, whose read found the pair
  /// ended — and its copy of the preferences may be older than the address
  /// ([FreshPreferences]). A store that cannot be read leaves the copy's
  /// answer.
  Future<({bool held, bool owed})> _endNow() async {
    try {
      final stored = await FreshPreferences.read();
      return (
        held: stored.getString(SettingsKeys.pushAddressHeld) != null,
        owed: stored.getString(SettingsKeys.pushDeleteOwed) != null,
      );
    } catch (e) {
      debugPrint('[PushAddress] held not read off the store: $e');
      final prefs = await _prefs;
      return (
        held: prefs.getString(SettingsKeys.pushAddressHeld) != null,
        owed: prefs.getString(SettingsKeys.pushDeleteOwed) != null,
      );
    }
  }

  @override
  Future<void> giveUp() async {
    final end = await _endNow();
    if (!end.held) {
      // An end an earlier give-up could not finish is this one's to finish:
      // the run that learns the pair ended asks again at each run, with
      // the app — whose launch would pay it — still closed.
      if (end.owed) await _paidOwed(owed: true);
      return;
    }
    // No longer this install's address from here, whatever follows.
    _epoch++;
    _registeredIn = null;
    _last = null;
    await _mark(SettingsKeys.pushDeleteOwed, true);
    await _mark(SettingsKeys.pushAddressHeld, false);
    await _paidOwed(owed: true);
  }

  @override
  Future<void> payOwed() async {
    await _paidOwed();
  }

  /// Ends the installation an earlier [giveUp] left standing; true when
  /// none is owed any more.
  ///
  /// Whether one is owed is read off the store ([_endNow]) unless the
  /// caller just did and says so in [owed]: the give-up that left it may
  /// have been another isolate's — the check's run — after this one loaded
  /// its copy of the preferences. Gone by the copy, a registration went
  /// ahead with the delete still owed, and the next launch paid it by
  /// deleting the installation then in use.
  Future<bool> _paidOwed({bool? owed}) async {
    if (!(owed ?? (await _endNow()).owed)) return true;
    try {
      // Unregistered first while the installation still stands; a failure
      // there, or no answer, is no reason to keep it — its deletion ends the
      // id either way. Each call is bounded: the registry's steps wait on
      // this one.
      await _platform
          .unregister()
          .timeout(_endDeadline)
          .catchError(
            (Object e) => debugPrint('[PushAddress] not unregistered: $e'),
          );
      await _platform.deleteInstallation().timeout(_endDeadline);
      await _mark(SettingsKeys.pushDeleteOwed, false);
      return true;
    } catch (e) {
      debugPrint('[PushAddress] installation not deleted, still owed: $e');
      return false;
    }
  }

  /// Told each time this install comes to hold an address it did not hold:
  /// from then on the partner's change can arrive as a message and start a
  /// run with no app. Set by DI, which stores what such a run arms under
  /// (`AlertScheduler.keepArmFactsQuietly`) before one can come.
  static Future<void> Function()? onAddressFirstHeld;

  Future<void> _mark(String key, bool on) async {
    final prefs = await _prefs;
    if (on) {
      final first =
          key == SettingsKeys.pushAddressHeld && !prefs.containsKey(key);
      await prefs.setString(key, '1');
      if (first) {
        unawaited(
          Future.sync(() => onAddressFirstHeld?.call()).catchError((Object e) {
            debugPrint('[PushAddress] first address not announced: $e');
          }),
        );
      }
    } else {
      await prefs.remove(key);
    }
  }
}
