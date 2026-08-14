import 'package:drift/drift.dart';

/// Per-occurrence description overrides for calendar events (**v24**).
///
/// Holds **only user deltas**, exactly like `public_holidays` since v22: a row
/// exists for a `(eventId, day)` pair only once the user has actually written
/// or ticked something on that day. Every other day falls back to the event's
/// own `description`, which acts as a template. A daily event therefore costs
/// zero rows until it is touched.
///
/// A present row always wins, **including when its [description] is empty** —
/// that is how a deliberately blanked day stays blank instead of falling back
/// to the template. Resetting a day to the template deletes the row; it never
/// writes `''`.
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

  @override
  Set<Column> get primaryKey => {eventId, day};
}
