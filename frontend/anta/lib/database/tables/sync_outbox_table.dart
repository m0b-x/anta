import 'package:drift/drift.dart';

/// The change feed (**v43**): one row per synced row that changed locally and
/// has not been pushed yet, keyed by `{table_name, row_key}` so a row edited
/// ten times before a push is queued once, at its latest [hlc].
///
/// Device-local and never backed up: it describes this device's unsent work,
/// which no other device or restore can use. The [rowKey] is the remote
/// document id — a text id as it is, a composite key joined with `|` and its
/// day as epoch-ms.
@DataClassName('SyncOutboxRow')
class SyncOutbox extends Table {
  @override
  String get tableName => 'sync_outbox';

  /// The SQL name of the changed row's table. Not `tableName` in Dart, which
  /// [Table] already owns.
  TextColumn get syncedTable => text().named('table_name')();
  TextColumn get rowKey => text()();

  /// The HLC the row was written at, so a push can tell whether the row moved
  /// again after it was read.
  TextColumn get hlc => text()();

  /// `upsert` or `delete` — a tombstone travels as a delete.
  TextColumn get op => text()();
  DateTimeColumn get enqueuedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {syncedTable, rowKey};
}
