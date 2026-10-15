// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_alert_dao.dart';

// ignore_for_file: type=lint
mixin _$CategoryAlertDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarCategoryAlertsTable get calendarCategoryAlerts =>
      attachedDatabase.calendarCategoryAlerts;
  CategoryAlertDaoManager get managers => CategoryAlertDaoManager(this);
}

class CategoryAlertDaoManager {
  final _$CategoryAlertDaoMixin _db;
  CategoryAlertDaoManager(this._db);
  $$CalendarCategoryAlertsTableTableManager get calendarCategoryAlerts =>
      $$CalendarCategoryAlertsTableTableManager(
        _db.attachedDatabase,
        _db.calendarCategoryAlerts,
      );
}
