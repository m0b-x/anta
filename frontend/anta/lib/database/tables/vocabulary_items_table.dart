import 'package:drift/drift.dart';

/// The terms inside a [Vocabularies] row (**v32**).
///
/// One row per suggestion rather than a delimited blob on the parent: terms are
/// user-entered free text, so any delimiter is a term someone eventually types
/// ("Squat, paused" is a real exercise name). Per-row identity also survives a
/// rename — reordering or re-saving a list keeps each term's `id`, which is
/// what a future per-term usage count or insertion template would hang off.
///
/// The column is [term], not `text`: `text()` is the Drift column builder on
/// `Table` and a getter of that name would shadow it.
///
/// [sortOrder] is rewritten wholesale on every save, since the management UI
/// edits the list as one block of lines.
///
/// Same five CRDT columns as the parent, same reasoning. A term removed from
/// the list is tombstoned, not deleted, so re-adding it later resurrects the
/// original row instead of forking its identity.
@DataClassName('VocabularyItemRow')
class VocabularyItems extends Table {
  @override
  String get tableName => 'vocabulary_items';

  TextColumn get id => text()();
  TextColumn get vocabularyId => text()();
  TextColumn get term => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

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
