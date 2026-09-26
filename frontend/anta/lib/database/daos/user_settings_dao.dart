import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/user_settings_table.dart';

part 'user_settings_dao.g.dart';

@DriftAccessor(tables: [UserSettings])
class UserSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$UserSettingsDaoMixin {
  UserSettingsDao(super.db);

  Future<String?> getValue(String key) async {
    final setting = await (select(
      userSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return setting?.value;
  }

  Future<void> setValue(String key, String value) async {
    await into(userSettings).insertOnConflictUpdate(
      UserSettingsCompanion(
        key: Value(key),
        value: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Writes several keys as one transaction, so a bundle saved while another
  /// save of the same bundle is in flight lands whole or not at all.
  Future<void> setValues(Map<String, String> values) async {
    if (values.isEmpty) return;
    final now = DateTime.now();
    await batch((b) {
      b.insertAllOnConflictUpdate(userSettings, [
        for (final entry in values.entries)
          UserSettingsCompanion(
            key: Value(entry.key),
            value: Value(entry.value),
            updatedAt: Value(now),
          ),
      ]);
    });
  }

  Future<void> deleteValue(String key) async {
    await (delete(userSettings)..where((s) => s.key.equals(key))).go();
  }

  Future<Map<String, String>> getAllSettings() async {
    final settings = await select(userSettings).get();
    return {for (final s in settings) s.key: s.value};
  }

  /// Reads a known set of keys in one statement.
  ///
  /// Prefer this over [getAllSettings] for a fixed bundle: this table is not
  /// only app settings — `NotePositionService` writes a `note_position_<id>`
  /// row per note — so a full read scales with the note count, not with the
  /// number of settings. Missing keys are simply absent from the result, which
  /// keeps `map[key] == null` meaning exactly what [getValue] returning null
  /// means.
  Future<Map<String, String>> getValuesFor(Iterable<String> keys) async {
    final wanted = keys.toList(growable: false);
    if (wanted.isEmpty) return const {};
    final rows = await (select(
      userSettings,
    )..where((s) => s.key.isIn(wanted))).get();
    return {for (final s in rows) s.key: s.value};
  }
}
