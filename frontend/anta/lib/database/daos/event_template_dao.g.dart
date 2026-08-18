// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_template_dao.dart';

// ignore_for_file: type=lint
mixin _$EventTemplateDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventTemplatesTable get eventTemplates => attachedDatabase.eventTemplates;
  EventTemplateDaoManager get managers => EventTemplateDaoManager(this);
}

class EventTemplateDaoManager {
  final _$EventTemplateDaoMixin _db;
  EventTemplateDaoManager(this._db);
  $$EventTemplatesTableTableManager get eventTemplates =>
      $$EventTemplatesTableTableManager(
        _db.attachedDatabase,
        _db.eventTemplates,
      );
}
