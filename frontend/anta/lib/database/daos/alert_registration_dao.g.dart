// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_registration_dao.dart';

// ignore_for_file: type=lint
mixin _$AlertRegistrationDaoMixin on DatabaseAccessor<AppDatabase> {
  $AlertRegistrationsTable get alertRegistrations =>
      attachedDatabase.alertRegistrations;
  AlertRegistrationDaoManager get managers => AlertRegistrationDaoManager(this);
}

class AlertRegistrationDaoManager {
  final _$AlertRegistrationDaoMixin _db;
  AlertRegistrationDaoManager(this._db);
  $$AlertRegistrationsTableTableManager get alertRegistrations =>
      $$AlertRegistrationsTableTableManager(
        _db.attachedDatabase,
        _db.alertRegistrations,
      );
}
