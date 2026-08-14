// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings_dao.dart';

// ignore_for_file: type=lint
mixin _$UserSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UserSettingsTable get userSettings => attachedDatabase.userSettings;
  UserSettingsDaoManager get managers => UserSettingsDaoManager(this);
}

class UserSettingsDaoManager {
  final _$UserSettingsDaoMixin _db;
  UserSettingsDaoManager(this._db);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db.attachedDatabase, _db.userSettings);
}
