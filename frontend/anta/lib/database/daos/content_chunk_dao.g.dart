// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_chunk_dao.dart';

// ignore_for_file: type=lint
mixin _$ContentChunkDaoMixin on DatabaseAccessor<AppDatabase> {
  $ContentChunksTable get contentChunks => attachedDatabase.contentChunks;
  ContentChunkDaoManager get managers => ContentChunkDaoManager(this);
}

class ContentChunkDaoManager {
  final _$ContentChunkDaoMixin _db;
  ContentChunkDaoManager(this._db);
  $$ContentChunksTableTableManager get contentChunks =>
      $$ContentChunksTableTableManager(_db.attachedDatabase, _db.contentChunks);
}
