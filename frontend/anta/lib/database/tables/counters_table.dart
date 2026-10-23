import 'package:drift/drift.dart';

@DataClassName('CounterRow')
class Counters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get startValue => integer().withDefault(const Constant(1))();
  IntColumn get step => integer().withDefault(const Constant(1))();
  TextColumn get scope => text().withDefault(const Constant('global'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  /// The `calendar_events` block (**v43**): added to a populated table, so the
  /// identity pair carries the `''` default SQLite's `ADD COLUMN NOT NULL`
  /// demands, and the migration backfills it in the same run. All stamping
  /// lives in `CounterDao`.
  TextColumn get hlcTimestamp => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The owning account once sync binds one (**v43**); NULL until then.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
