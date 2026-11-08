import 'package:drift/drift.dart';

class ContentChunks extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  IntColumn get chunkIndex => integer()();
  TextColumn get content => text()();
  BoolColumn get isCompressed => boolean().withDefault(const Constant(false))();

  // CRDT fields
  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// The owning account once sync binds one (**v43**); NULL until then. Here
  /// for parity with `notes` only: a chunk is local storage of a note's body.
  TextColumn get ownerId => text().nullable()();

  /// The SHA-256 of the chunk's text as `ChunkHasher` defines it (**v46**):
  /// what a save diffs by, so no stored chunk is decompressed to compare.
  /// NULL on a legacy fixed slice, which its note's next body save re-cuts.
  TextColumn get contentHash => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
