import 'package:drift/drift.dart';

/// Cancelled occurrences of a recurring event (**v30**).
///
/// A **live** row for an `(eventId, day)` pair means that occurrence **does
/// not exist**: `CalendarEvent.occursOn` returns false for it, so it leaves
/// the grid, the day panel, the agenda, the timeline and the `.ics` export at
/// once. The table holds only user deltas, so an event costs zero rows until a
/// day is actually cancelled — the same shape as
/// `calendar_event_occurrences` (v24) and `calendar_event_absences` (v26).
///
/// Deliberately **not** a `status` column on `calendar_event_absences`, and
/// not the same thing as a missed occurrence. The two diverge on every axis
/// that governs them:
///
/// | | missed (v26) | skipped (v30) |
/// | --- | --- | --- |
/// | gate | `tracksPresence` opt-in | any recurring event |
/// | layer | rendering | membership |
/// | day cache | must **not** invalidate | must invalidate |
/// | `.ics` | exports as an occurrence | exports as an `EXDATE` |
///
/// A discriminator column would make "a live row means missed" — the invariant
/// three surfaces and the backup strand rule are built on — conditional on
/// every reader remembering to filter it.
///
/// Un-skipping **tombstones** the row (`is_deleted = 1`, fresh HLC,
/// `version + 1`) rather than deleting it, and re-skipping resurrects the same
/// row with its original [createdAt]: skip/un-skip is exactly the toggle that
/// needs an ordered tombstone once two devices merge, and with the composite
/// primary key `{eventId, day}` the table is a last-writer-wins element set.
///
/// The five CRDT columns are the shipped Notes/Folders block byte-for-byte.
/// Stamping lives entirely in `EventSkipDao`.
///
/// [day] is date-only UTC, matching `CalendarEvent.occursOn`. Drift hands the
/// column back as a *local* `DateTime`, so every read must round-trip through
/// the same epoch-milliseconds recovery the event service uses, or dates shift
/// by one day in non-UTC zones.
@DataClassName('EventSkipRow')
class EventSkips extends Table {
  @override
  String get tableName => 'calendar_event_skips';

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
