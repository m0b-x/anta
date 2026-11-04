// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_profile_dao.dart';

// ignore_for_file: type=lint
mixin _$CategoryProfileDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarCategoryProfilesTable get calendarCategoryProfiles =>
      attachedDatabase.calendarCategoryProfiles;
  CategoryProfileDaoManager get managers => CategoryProfileDaoManager(this);
}

class CategoryProfileDaoManager {
  final _$CategoryProfileDaoMixin _db;
  CategoryProfileDaoManager(this._db);
  $$CalendarCategoryProfilesTableTableManager get calendarCategoryProfiles =>
      $$CalendarCategoryProfilesTableTableManager(
        _db.attachedDatabase,
        _db.calendarCategoryProfiles,
      );
}
