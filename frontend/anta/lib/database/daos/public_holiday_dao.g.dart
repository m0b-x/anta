// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_holiday_dao.dart';

// ignore_for_file: type=lint
mixin _$PublicHolidayDaoMixin on DatabaseAccessor<AppDatabase> {
  $PublicHolidaysTableTable get publicHolidaysTable =>
      attachedDatabase.publicHolidaysTable;
  PublicHolidayDaoManager get managers => PublicHolidayDaoManager(this);
}

class PublicHolidayDaoManager {
  final _$PublicHolidayDaoMixin _db;
  PublicHolidayDaoManager(this._db);
  $$PublicHolidaysTableTableTableManager get publicHolidaysTable =>
      $$PublicHolidaysTableTableTableManager(
        _db.attachedDatabase,
        _db.publicHolidaysTable,
      );
}
