// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_event_dao.dart';

// ignore_for_file: type=lint
mixin _$CalendarEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarEventsTable get calendarEvents => attachedDatabase.calendarEvents;
  CalendarEventDaoManager get managers => CalendarEventDaoManager(this);
}

class CalendarEventDaoManager {
  final _$CalendarEventDaoMixin _db;
  CalendarEventDaoManager(this._db);
  $$CalendarEventsTableTableManager get calendarEvents =>
      $$CalendarEventsTableTableManager(
        _db.attachedDatabase,
        _db.calendarEvents,
      );
}
