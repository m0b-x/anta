// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_absence_dao.dart';

// ignore_for_file: type=lint
mixin _$EventAbsenceDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventAbsencesTable get eventAbsences => attachedDatabase.eventAbsences;
  EventAbsenceDaoManager get managers => EventAbsenceDaoManager(this);
}

class EventAbsenceDaoManager {
  final _$EventAbsenceDaoMixin _db;
  EventAbsenceDaoManager(this._db);
  $$EventAbsencesTableTableManager get eventAbsences =>
      $$EventAbsencesTableTableManager(_db.attachedDatabase, _db.eventAbsences);
}
