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

  @override
  Set<Column> get primaryKey => {id};
}
