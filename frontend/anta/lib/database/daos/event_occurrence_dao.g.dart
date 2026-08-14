// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_occurrence_dao.dart';

// ignore_for_file: type=lint
mixin _$EventOccurrenceDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventOccurrenceDescriptionsTable get eventOccurrenceDescriptions =>
      attachedDatabase.eventOccurrenceDescriptions;
  EventOccurrenceDaoManager get managers => EventOccurrenceDaoManager(this);
}

class EventOccurrenceDaoManager {
  final _$EventOccurrenceDaoMixin _db;
  EventOccurrenceDaoManager(this._db);
  $$EventOccurrenceDescriptionsTableTableManager
  get eventOccurrenceDescriptions =>
      $$EventOccurrenceDescriptionsTableTableManager(
        _db.attachedDatabase,
        _db.eventOccurrenceDescriptions,
      );
}
