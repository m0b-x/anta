// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_skip_dao.dart';

// ignore_for_file: type=lint
mixin _$EventSkipDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventSkipsTable get eventSkips => attachedDatabase.eventSkips;
  EventSkipDaoManager get managers => EventSkipDaoManager(this);
}

class EventSkipDaoManager {
  final _$EventSkipDaoMixin _db;
  EventSkipDaoManager(this._db);
  $$EventSkipsTableTableManager get eventSkips =>
      $$EventSkipsTableTableManager(_db.attachedDatabase, _db.eventSkips);
}
