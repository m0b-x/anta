import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../core/qa/qa_mode.dart';

/// The install's preferences as the platform's store holds them now, read
/// past this isolate's copy and without touching it — for the keys another
/// isolate writes: what the shared check's run and the app tell each other
/// (`docs/cloud-shared-freshness.md` §5, §6).
///
/// `SharedPreferences` is a copy per isolate, loaded once. Its own
/// `reload()` is no way to see the other isolate's write from the app:
/// it awaits the platform's map and then replaces the whole copy, so a key
/// the app wrote while it waited is in the store and gone from the copy —
/// the marker of a restore begun in that moment was never taken off, and
/// the app read back the database name it had just left. So nothing in
/// `lib/` reloads. The alarm fork does, in every isolate that starts it,
/// at each change between foreground and background
/// (`packages/alarm/lib/service/alarm_storage.dart`) — one more reason a
/// key another isolate writes is never read off the copy: every
/// cross-isolate read, in either isolate, comes through here, and writes
/// go through `SharedPreferences` as ever.
///
/// Asked the way the plugin asks: under its own prefix with the call it
/// makes there, and under the QA build's namespace
/// (`QaBootstrap.namespacePreferences`) with the call it makes for a
/// prefix of the app's choosing.
class FreshPreferences {
  final Map<String, Object> _values;

  const FreshPreferences._(this._values);

  static const String _pluginPrefix = 'flutter.';

  /// One platform round trip. Throws what the store throws: the caller
  /// decides what not knowing means.
  static Future<FreshPreferences> read() async {
    final store = SharedPreferencesStorePlatform.instance;
    const prefix = QaMode.enabled ? QaMode.preferencesPrefix : _pluginPrefix;
    final all = QaMode.enabled
        ? await store.getAllWithParameters(
            GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
          )
        : await store.getAll();
    return FreshPreferences._({
      for (final MapEntry(:key, :value) in all.entries)
        if (key.startsWith(prefix)) key.substring(prefix.length): value,
    });
  }

  bool containsKey(String key) => _values.containsKey(key);

  /// Every key the store holds, for what is kept under a prefix.
  Iterable<String> get keys => _values.keys;

  String? getString(String key) => switch (_values[key]) {
    final String value => value,
    _ => null,
  };

  int? getInt(String key) => switch (_values[key]) {
    final int value => value,
    _ => null,
  };

  /// A list comes off the platform untyped.
  List<String>? getStringList(String key) => switch (_values[key]) {
    final List<Object?> value => [...value.whereType<String>()],
    _ => null,
  };
}
