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

  @override
  Set<Column> get primaryKey => {counterId, noteId};
}
