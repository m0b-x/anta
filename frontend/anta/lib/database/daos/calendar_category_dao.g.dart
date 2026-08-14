// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_category_dao.dart';

// ignore_for_file: type=lint
mixin _$CalendarCategoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarCategoriesTable get calendarCategories =>
      attachedDatabase.calendarCategories;
  CalendarCategoryDaoManager get managers => CalendarCategoryDaoManager(this);
}

class CalendarCategoryDaoManager {
  final _$CalendarCategoryDaoMixin _db;
  CalendarCategoryDaoManager(this._db);
  $$CalendarCategoriesTableTableManager get calendarCategories =>
      $$CalendarCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.calendarCategories,
      );
}
