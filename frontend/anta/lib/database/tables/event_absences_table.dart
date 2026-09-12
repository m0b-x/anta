import 'package:drift/drift.dart';

/// Per-occurrence presence marks for calendar events (**v26**, statuses since
/// **v37**).
///
/// A **live** row for an `(eventId, day)` pair is an explicit [status] the user
/// chose for that occurrence — `missed` or `present` — and it always wins. No
/// live row means "no answer yet", which resolves through the event's own
/// default (`CalendarEvent.assumesAbsentOn`): present for the classic implicit
/// attendance v26 shipped, missed once assume-absent covers the day. The table
/// still holds only user deltas, so a daily event stays at zero rows until
/// something is actually recorded, exactly like `calendar_event_occurrences`
/// since v24.
///
/// Clearing a mark **tombstones** the row (`is_deleted = 1`, fresh HLC,
/// `version + 1`) rather than deleting it, and re-marking resurrects the same
/// row with its original [createdAt]. That path belongs to `clearMark` alone —
/// the day panel's and detail sheet's toggle writes the opposite status
/// instead, because "present" is now a statement, not the absence of one.
/// Clearing is precisely the toggle that needs an ordered tombstone once two
/// devices merge, and with the composite primary key `{eventId, day}` the
/// table is a last-writer-wins element set.
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

  /// `PresenceStatus.name` — `missed` (the pre-v37 meaning of every row, and
  /// the default) or `present`. Unknown values decode to `missed`; no `CHECK`
  /// clause, matching the other additive columns in this schema.
  TextColumn get status => text().withDefault(const Constant('missed'))();

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
