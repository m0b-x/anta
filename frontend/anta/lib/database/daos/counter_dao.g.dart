// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'counter_dao.dart';

// ignore_for_file: type=lint
mixin _$CounterDaoMixin on DatabaseAccessor<AppDatabase> {
  $CountersTable get counters => attachedDatabase.counters;
  $CounterValuesTable get counterValues => attachedDatabase.counterValues;
  CounterDaoManager get managers => CounterDaoManager(this);
}

class CounterDaoManager {
  final _$CounterDaoMixin _db;
  CounterDaoManager(this._db);
  $$CountersTableTableManager get counters =>
      $$CountersTableTableManager(_db.attachedDatabase, _db.counters);
  $$CounterValuesTableTableManager get counterValues =>
      $$CounterValuesTableTableManager(_db.attachedDatabase, _db.counterValues);
}
