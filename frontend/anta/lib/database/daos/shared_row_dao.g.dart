// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shared_row_dao.dart';

// ignore_for_file: type=lint
mixin _$SharedRowDaoMixin on DatabaseAccessor<AppDatabase> {
  $CalendarEventsTable get calendarEvents => attachedDatabase.calendarEvents;
  $EventOccurrenceDescriptionsTable get eventOccurrenceDescriptions =>
      attachedDatabase.eventOccurrenceDescriptions;
  $EventSkipsTable get eventSkips => attachedDatabase.eventSkips;
  $FoldersTable get folders => attachedDatabase.folders;
  $NotesTable get notes => attachedDatabase.notes;
  $ContentChunksTable get contentChunks => attachedDatabase.contentChunks;
  $SyncMetadataTable get syncMetadata => attachedDatabase.syncMetadata;
  SharedRowDaoManager get managers => SharedRowDaoManager(this);
}

class SharedRowDaoManager {
  final _$SharedRowDaoMixin _db;
  SharedRowDaoManager(this._db);
  $$CalendarEventsTableTableManager get calendarEvents =>
      $$CalendarEventsTableTableManager(
        _db.attachedDatabase,
        _db.calendarEvents,
      );
  $$EventOccurrenceDescriptionsTableTableManager
  get eventOccurrenceDescriptions =>
      $$EventOccurrenceDescriptionsTableTableManager(
        _db.attachedDatabase,
        _db.eventOccurrenceDescriptions,
      );
  $$EventSkipsTableTableManager get eventSkips =>
      $$EventSkipsTableTableManager(_db.attachedDatabase, _db.eventSkips);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$ContentChunksTableTableManager get contentChunks =>
      $$ContentChunksTableTableManager(_db.attachedDatabase, _db.contentChunks);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db.attachedDatabase, _db.syncMetadata);
}
