// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'filter_preset_dao.dart';

// ignore_for_file: type=lint
mixin _$FilterPresetDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarFilterPresetsTable get calendarFilterPresets =>
      attachedDatabase.calendarFilterPresets;
  FilterPresetDaoManager get managers => FilterPresetDaoManager(this);
}

class FilterPresetDaoManager {
  final _$FilterPresetDaoMixin _db;
  FilterPresetDaoManager(this._db);
  $$CalendarFilterPresetsTableTableManager get calendarFilterPresets =>
      $$CalendarFilterPresetsTableTableManager(
        _db.attachedDatabase,
        _db.calendarFilterPresets,
      );
}
