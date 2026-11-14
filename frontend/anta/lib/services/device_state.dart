import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/settings_keys.dart';

/// The preferences that describe this device, and the stamp that says
/// which device that is.
///
/// Android's backup and its device-to-device transfer restore the whole
/// preferences file onto a new phone, and none of what these keys speak
/// of: the platform's scheduled works, the push installation, the device
/// id (`backup_rules.xml` leaves `device_id` out on purpose). There each
/// of them is a statement about another phone — a check that "stands"
/// with no work behind it, an address "held" that was never registered,
/// an owed delete that would end the new phone's own fresh installation
/// at its first launch.
///
/// So they are kept to the device they were written on: stamped with the
/// install's device id, and cleared at the first launch that finds the
/// stamp naming another ([keepTo]).
///
/// What is **not** here, and why it stays: the active database's name,
/// the download marker (`sync_download_in_flight`), the sync registry's
/// claims and pending deletions, and the kept notices' list of database
/// names all describe the databases and the account's cloud copies, which
/// are restored with them; the relay's cached URL and its read time
/// describe the project, the same from any phone.
abstract final class DeviceState {
  /// Every key that is device state. Adding a preference that speaks of
  /// this phone's platform — a work, an address, a count of this install's
  /// attempts — adds it here.
  static const List<String> keys = [
    // The checks the platform holds for this install, by slot.
    SettingsKeys.sharedRefreshStandsFirst,
    SettingsKeys.sharedRefreshStandsSecond,
    // That a check was ever planned here: the gate for what only an
    // install with works pays.
    SettingsKeys.sharedRefreshPlanned,
    // How often this install's works asked to be run again, in a row.
    SettingsKeys.sharedRefreshMessageRetries,
    SettingsKeys.sharedRefreshCheckGaveWay,
    // A replacement in flight in a process of this phone.
    SettingsKeys.databaseReplacing,
    // This install's push address: held, owed its end, written to the
    // pair's document, and how its messages' work is handed over.
    SettingsKeys.pushAddressHeld,
    SettingsKeys.pushDeleteOwed,
    SettingsKeys.pushWritten,
    SettingsKeys.pushExpeditedWork,
  ];

  /// Device state kept one key per pair: every key that starts with one of
  /// these. A message's work that waits at this phone's platform
  /// (`SharedRefreshMessageGate`).
  static const List<String> prefixes = [
    SettingsKeys.sharedRefreshMessageWaitingPrefix,
  ];

  static bool _listed(String key) =>
      keys.contains(key) || prefixes.any(key.startsWith);

  /// Called by the launch once the database is open — so with the device
  /// id the open itself read or made, and no file read of its own — and
  /// before anything reads one of [keys]: the push objects and the first
  /// alert pass come after.
  ///
  /// A stamp naming another device clears every key and is rewritten; no
  /// stamp — the first launch of a build that stamps — is written and
  /// clears nothing; the stamp of this device costs one look at the
  /// preferences already in memory. Never throws: a launch must not fail
  /// on it, and a state left uncleared is what stood before there was a
  /// stamp.
  ///
  /// The stamp follows the clearing, and only a whole one: a key the store
  /// would not give up leaves the old stamp standing for the next launch
  /// to try again.
  static Future<void> keepTo(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stamped = prefs.get(SettingsKeys.deviceStateOf);
      if (stamped == deviceId) return;
      if (stamped != null) {
        var cleared = true;
        for (final key in prefs.getKeys().where(_listed).toList()) {
          if (!await prefs.remove(key)) cleared = false;
        }
        if (!cleared) {
          debugPrint('[DeviceState] another device\'s state not all cleared');
          return;
        }
      }
      await prefs.setString(SettingsKeys.deviceStateOf, deviceId);
    } catch (e) {
      debugPrint('[DeviceState] not kept to this device: $e');
    }
  }

  /// Called before the app deletes its own device id with its data
  /// (`AppDatabase.deleteAllData`): the phone is the same one, its works
  /// and its address stand, and the id the next launch makes must not read
  /// as another device's. With no stamp that launch writes its own and
  /// clears nothing.
  static Future<void> idDeleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(SettingsKeys.deviceStateOf)) return;
      await prefs.remove(SettingsKeys.deviceStateOf);
    } catch (e) {
      debugPrint('[DeviceState] stamp not taken off: $e');
    }
  }
}
