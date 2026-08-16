import 'package:drift/drift.dart';

/// Per-occurrence absence marks for calendar events (**v26**).
///
/// Attendance is implicit and costs nothing: a **live** row for an
/// `(eventId, day)` pair means "this occurrence was scheduled and missed";
/// no live row means present. A daily event therefore stays at zero rows
/// until a day is actually skipped, exactly like `calendar_event_occurrences`
/// since v24.
///
/// Un-marking **tombstones** the row (`is_deleted = 1`, fresh HLC,
/// `version + 1`) rather than deleting it, and re-marking resurrects the same
/// row with its original [createdAt]. Mark/unmark is precisely the toggle that
/// needs an ordered tombstone once two devices merge, and with the composite
/// primary key `{eventId, day}` the table is a last-writer-wins element set.
///
/// The five CRDT columns are the shipped Notes/Folders block byte-for-byte
/// (`notes_table.dart`), **not** `ContentChunks`' four-column variant, which
/// skips [deletedAt] and forgets the version bump on soft delete. Stamping
/// lives entirely in `EventAbsenceDao`.
///
/// [day] is date-only UTC, matching `CalendarEvent.occursOn`. Drift hands the
/// column back as a *local* `DateTime`, so every read must round-trip through
/// the same epoch-milliseconds recovery the event service uses, or dates shift
/// by one day in non-UTC zones.
@DataClassName('EventAbsenceRow')
class EventAbsences extends Table {
  @override
  String get tableName => 'calendar_event_absences';

  TextColumn get eventId => text()();

  /// UTC date-only (year, month, day).
  DateTimeColumn get day => dateTime()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {eventId, day};
}
