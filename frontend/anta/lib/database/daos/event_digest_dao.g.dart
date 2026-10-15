// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_digest_dao.dart';

// ignore_for_file: type=lint
mixin _$EventDigestDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventDigestsTable get eventDigests => attachedDatabase.eventDigests;
  EventDigestDaoManager get managers => EventDigestDaoManager(this);
}

class EventDigestDaoManager {
  final _$EventDigestDaoMixin _db;
  EventDigestDaoManager(this._db);
  $$EventDigestsTableTableManager get eventDigests =>
      $$EventDigestsTableTableManager(_db.attachedDatabase, _db.eventDigests);
}
