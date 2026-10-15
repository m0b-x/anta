import 'package:drift/drift.dart';

/// Saved overview lists (**v41**).
///
/// A view is a named `OverviewView` — "Q1 2026 · Gym · one per event" — that
/// the overview re-applies in one tap: the period, the list options and the
/// categories allowlist the user would otherwise rebuild by hand.
///
/// The `calendar_filter_presets` (v35) shape on purpose, column for column:
/// a named, ordered, individually editable record backed up and restored like
/// every other user-created row, with the whole view in **one JSON blob**
/// ([payload], `OverviewView.toJson`). The codec is forward- and
/// backward-compatible by construction, so a view saved by an older build
/// still applies after a field is added, and one saved by a newer build
/// degrades instead of throwing.
///
/// The five CRDT columns are the v29 block byte-for-byte, present from birth,
/// with no `withDefault('')` on the identity pair. Stamping lives entirely in
/// `OverviewViewDao`.
///
/// A view's only foreign reference is the category ids inside its blob, and
/// a stale one lists nothing (the allowlist simply names a category no event
/// carries), so this table needs no strand rule on import.
@DataClassName('OverviewViewRow')
class OverviewViews extends Table {
  @override
  String get tableName => 'overview_views';

  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `jsonEncode(OverviewView.toJson())` — see the class doc.
  TextColumn get payload => text()();

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
