import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// The platform side of `SharedPreferences`, scripted: a test holds or fails
/// a read and fails a write while the code under test runs unchanged over
/// the real `SharedPreferences` (final review X-3, X-7, X-11).
class ScriptedPrefsStore extends InMemorySharedPreferencesStore {
  ScriptedPrefsStore([Map<String, Object> values = const {}])
    : super.withData({
        for (final MapEntry(:key, :value) in values.entries)
          '$_prefix$key': value,
      });

  static const _prefix = 'flutter.';

  /// Installs a store holding [values] as the platform's, after dropping the
  /// `SharedPreferences` memo so the next `getInstance` reads from it.
  static ScriptedPrefsStore install([Map<String, Object> values = const {}]) {
    SharedPreferences.resetStatic();
    final store = ScriptedPrefsStore(values);
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  /// How many reads have arrived, the first counted as 1.
  int reads = 0;

  /// Awaited by every read with its number before it answers: a test holds
  /// the read on a future, or fails it by throwing.
  FutureOr<void> Function(int read)? onRead;

  /// Called with the key, without its prefix, of every write and remove; the
  /// write throws when it answers true.
  bool Function(String key)? failWrite;

  /// Called with the key, without its prefix, of every remove; the remove
  /// keeps the value and answers `false` when it answers true — how the
  /// Android store reports a failed remove instead of throwing.
  bool Function(String key)? refuseRemove;

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    await onRead?.call(reads);
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _checkWrite(key);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    _checkWrite(key);
    if (refuseRemove?.call(_unprefixed(key)) ?? false) return false;
    return super.remove(key);
  }

  void _checkWrite(String key) {
    final unprefixed = _unprefixed(key);
    if (failWrite?.call(unprefixed) ?? false) {
      throw StateError('the store refused to write "$unprefixed"');
    }
  }

  static String _unprefixed(String key) =>
      key.startsWith(_prefix) ? key.substring(_prefix.length) : key;
}
