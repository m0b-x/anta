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

  Future<void> deleteValue(String key) async {
    await (delete(userSettings)..where((s) => s.key.equals(key))).go();
  }

  Future<Map<String, String>> getAllSettings() async {
    final settings = await select(userSettings).get();
    return {for (final s in settings) s.key: s.value};
  }
}
