part of '../settings_service.dart';

/// Decoders take the raw stored string so a value can be resolved either
/// from a single-row read or from a bulk snapshot without a second copy of
/// the parsing rules. `UserSettings.value` is non-nullable, so a `null` raw
/// means "no row" from both sources alike — which is the distinction
/// [_decodeFastingSchedule] and [_decodeFastingAppearance] depend on.
bool _decodeBool(String? raw, bool defaultValue) =>
    raw == null ? defaultValue : raw == 'true';

int _decodeInt(String? raw, int defaultValue) =>
    raw == null ? defaultValue : (int.tryParse(raw) ?? defaultValue);

double _decodeDouble(String? raw, double defaultValue) =>
    raw == null ? defaultValue : (double.tryParse(raw) ?? defaultValue);

/// The open database and the typed reads and writes over its settings rows:
/// what every settings area is written against. [SettingsService] is this
/// class with the areas of the sibling files mixed in, in the order it lists
/// them, and each area sees only the ones before it.
abstract class _SettingsStore {
  late AppDatabase _db;

  // Helper methods for type conversion
  Future<bool> _getBool(String key, bool defaultValue) async {
    final value = await _db.userSettingsDao.getValue(key);
    return _decodeBool(value, defaultValue);
  }

  Future<void> _setBool(String key, bool value) async {
    await _db.userSettingsDao.setValue(key, value.toString());
  }

  Future<int> _getInt(String key, int defaultValue) async {
    final value = await _db.userSettingsDao.getValue(key);
    return _decodeInt(value, defaultValue);
  }

  Future<void> _setInt(String key, int value) async {
    await _db.userSettingsDao.setValue(key, value.toString());
  }

  /// Writes a value, or removes the row entirely when it is null — "absent"
  /// and "empty string" must not be the same state for pairing.
  Future<void> _write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _db.userSettingsDao.deleteValue(key);
    } else {
      await _db.userSettingsDao.setValue(key, value);
    }
  }

  String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  // The debounced write and its flush are [SettingsService]'s own, beside
  // the timer they share; declared here so that an area can ask for them.
  void _scheduleWrite(String key, String value);
  Future<void> flushPendingWrites();
}
