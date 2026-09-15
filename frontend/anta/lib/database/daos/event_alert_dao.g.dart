// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_alert_dao.dart';

// ignore_for_file: type=lint
mixin _$EventAlertDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventAlertsTable get eventAlerts => attachedDatabase.eventAlerts;
  EventAlertDaoManager get managers => EventAlertDaoManager(this);
}

class EventAlertDaoManager {
  final _$EventAlertDaoMixin _db;
  EventAlertDaoManager(this._db);
  $$EventAlertsTableTableManager get eventAlerts =>
      $$EventAlertsTableTableManager(_db.attachedDatabase, _db.eventAlerts);
}
