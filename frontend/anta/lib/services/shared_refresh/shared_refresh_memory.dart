import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/settings_keys.dart';
import '../../core/qa/qa_bootstrap.dart';
import '../fresh_preferences.dart';
import 'shared_refresh.dart';
import 'shared_refresh_scheduler.dart';

/// [SharedRefreshMemory] in the preferences, which every isolate of the
/// install reads: the app's, a run's, and the trigger that never opened a
/// database. A key per slot, each written whole, so two isolates that write
/// close together lose nothing of each other's.
class PreferencesSharedRefreshMemory implements SharedRefreshMemory {
  const PreferencesSharedRefreshMemory();

  static String _keyOf(SharedRefreshSlot slot) => switch (slot) {
    SharedRefreshSlot.first => SettingsKeys.sharedRefreshStandsFirst,
    SharedRefreshSlot.second => SettingsKeys.sharedRefreshStandsSecond,
  };

  /// The store as this build reads it: a trigger the app answered never
  /// took the run's first step, which is what namespaces a QA build's.
  Future<SharedPreferences> _store() {
    QaBootstrap.namespacePreferences();
    return SharedPreferences.getInstance();
  }

  /// Off the platform's store, never by re-reading this isolate's copy of
  /// the preferences ([FreshPreferences]): every alert pass of the app
  /// asks, and a copy replaced under it lost what the app wrote meanwhile.
  @override
  Future<Map<SharedRefreshSlot, DateTime>> standing() async {
    final fresh = await FreshPreferences.read();
    return {
      for (final slot in SharedRefreshSlot.values)
        if (fresh.getInt(_keyOf(slot)) case final due?)
          slot: DateTime.fromMillisecondsSinceEpoch(due),
    };
  }

  /// A removal is asked of the store whatever this isolate's copy holds:
  /// the check may have been written by another.
  @override
  Future<void> stands(SharedRefreshSlot slot, DateTime? due) async {
    final prefs = await _store();
    if (due == null) {
      await prefs.remove(_keyOf(slot));
    } else {
      await prefs.setInt(_keyOf(slot), due.millisecondsSinceEpoch);
    }
  }
}
