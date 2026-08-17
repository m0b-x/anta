import 'package:drift/drift.dart';

/// Per-occurrence description overrides for calendar events (**v24**,
/// CRDT-shaped since **v28**).
///
/// Holds **only user deltas**, exactly like `public_holidays` since v22: a row
/// exists for a `(eventId, day)` pair only once the user has actually written
/// or ticked something on that day. Every other day falls back to the event's
/// own `description`, which acts as a template. A daily event therefore costs
/// zero rows until it is touched, and the event's own
/// `per_occurrence_descriptions` flag (v28) decides whether the deltas render
/// at all — turning it off leaves them dormant, never deleted.
///
/// A **live** row always wins, **including when its [description] is empty** —
/// that is how a deliberately blanked day stays blank instead of falling back
/// to the template. Resetting a day to the template **tombstones** the row
/// (`is_deleted = 1`, fresh HLC, `version + 1`); it never writes `''` and never
/// deletes, so the reset survives a merge instead of being pushed back by the
/// partner. Re-describing that day resurrects the same row with its original
/// [createdAt].
///
/// The five CRDT columns are the `calendar_events` variant of the
/// Notes/Folders block, not `calendar_event_absences`': [hlcTimestamp] /
/// [deviceId] carry `withDefault(const Constant(''))` because v28 added them to
/// a *populated* table and SQLite's `ALTER TABLE … ADD COLUMN NOT NULL` demands
/// a default. The declaration has to match the migrated shape, so the default
/// lives here too — but `''` is transitional, never valid: the migration
/// backfills real identity immediately and `EventOccurrenceDao` stamps every
/// write. Observing `''` at runtime means something wrote around the DAO.
///
/// [day] is date-only UTC, matching `CalendarEvent.occursOn`. Drift hands the
/// column back as a *local* `DateTime`, so every read must round-trip through
/// the same epoch-milliseconds recovery the event service uses, or dates shift
/// by one day in non-UTC zones.
@DataClassName('EventOccurrenceRow')
class EventOccurrenceDescriptions extends Table {
  @override
  String get tableName => 'calendar_event_occurrences';

  TextColumn get eventId => text()();

  /// UTC date-only (year, month, day).
  DateTimeColumn get day => dateTime()();

  /// Materialized markdown source for this one occurrence. Non-nullable: the
  /// row's existence is the override, and an empty string is a meaningful
  /// value (see the class doc).
  TextColumn get description => text()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {eventId, day};
}
