import 'package:drift/drift.dart';

/// Scheduled digests (**v42**) — one bundled notification on a cadence,
/// "3 birthdays this month".
///
/// The `overview_views` (v41) shape column for column plus [enabled]: a named,
/// ordered, individually editable record with everything about *what* it
/// lists and *when* it fires in **one JSON blob** ([payload],
/// `EventDigest.encodePayload`), whose codec is forward-compatible so a digest
/// saved by a newer build degrades instead of throwing. [name] `''` means the
/// title is derived from the categories it covers.
///
/// The five CRDT columns are the v29 block byte-for-byte, with no default on
/// the identity pair. Stamping lives entirely in `EventDigestDao`.
///
/// Its only foreign references are the category ids inside the blob, and a
/// stale one lists nothing, so this table needs no strand rule on import.
@DataClassName('EventDigestRow')
class EventDigests extends Table {
  @override
  String get tableName => 'event_digests';

  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();

  /// `EventDigest.encodePayload()` — see the class doc.
  TextColumn get payload => text()();

  /// The hub switch. A disabled digest is kept and arms nothing.
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The owning account once sync binds one (**v43**); NULL until then.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
