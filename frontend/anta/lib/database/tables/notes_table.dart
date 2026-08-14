import 'package:drift/drift.dart';

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get folderId => text()();
  TextColumn get title => text().withLength(min: 0, max: 500)();
  TextColumn get preview => text().withDefault(const Constant(''))();
  IntColumn get contentLength => integer().withDefault(const Constant(0))();
  IntColumn get chunkCount => integer().withDefault(const Constant(0))();
  BoolColumn get isCompressed => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
