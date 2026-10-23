import 'package:drift/drift.dart';

/// Stores the current value for each counter. For global counters [noteId] is
/// the empty string `''`. For per-note counters [noteId] is the note's UUID.
/// This avoids nullable columns in the composite primary key.
@DataClassName('CounterValueRow')
class CounterValues extends Table {
  TextColumn get counterId => text()();
  TextColumn get noteId => text().withDefault(const Constant(''))();
  IntColumn get value => integer()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

  /// The `calendar_events` block (**v43**), as on `counters`. A deleted
  /// counter tombstones its values with it, so the composite key keeps a row
  /// to merge against.
  TextColumn get hlcTimestamp => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The owning account once sync binds one (**v43**); NULL until then.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {counterId, noteId};
}
