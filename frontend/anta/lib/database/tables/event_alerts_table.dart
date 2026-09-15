import 'package:drift/drift.dart';

/// Alerts hung off a calendar event (**v40**) — *when* the phone should speak
/// up about an occurrence, and *how*.
///
/// One row per alert, up to five per event, so `calendar_events` stays narrow
/// and adding an alert costs a row rather than a column. Two tiers live in the
/// one [mode] column: `notify` is a notification that respects silent mode,
/// `ring` is an alarm that keeps playing until it is stopped.
///
/// **Both offset sets are always stored.** [offsetMinutes] answers a timed
/// event, [daysBefore] + [dayMinute] answer an all-day one, and the planner
/// picks between them by `event.time == null` — the derived `allDay`, never
/// the persisted mirror column. An event switched from timed to all-day and
/// back therefore keeps alerts that still mean something, which is why
/// neither set is ever cleared on a flip.
///
/// [dayMinute] is nullable because `null` is a meaning of its own: *use the
/// Calendar-settings default* (09:00 out of the box), so changing that setting
/// moves every alert that never chose a time.
///
/// No `fire_at` column, and no timezone column. The instant is derived by the
/// planner from the occurrence day and the event's own time (floating local
/// time, exactly as the rest of the calendar is), so a stored instant could
/// only go stale against a rule edit, a skip or a DST shift.
///
/// The five CRDT columns are the shipped Notes/Folders block byte-for-byte,
/// and [hlcTimestamp] / [deviceId] are **default-less** — this is a new table,
/// so every insert must stamp them or fail, the `calendar_event_skips` rule
/// rather than the `DEFAULT ''` artifact v27 had to leave on `calendar_events`.
/// All stamping lives in `EventAlertDao`.
@DataClassName('EventAlertRow')
class EventAlerts extends Table {
  @override
  String get tableName => 'calendar_event_alerts';

  TextColumn get id => text()();

  TextColumn get eventId => text()();

  /// `notify` | `ring` — see `AlertMode`. Unknown values decode to `notify`,
  /// the quieter of the two, so a row written by a newer build can never
  /// surprise an older one with noise.
  TextColumn get mode => text().withDefault(const Constant('notify'))();

  /// Minutes before the occurrence's start, for a **timed** event. `0` is
  /// "at start"; negative offsets (after start) are deliberately not modelled.
  IntColumn get offsetMinutes => integer().withDefault(const Constant(0))();

  /// Whole days before the occurrence, for an **all-day** event. `0` is
  /// "on the day".
  IntColumn get daysBefore => integer().withDefault(const Constant(0))();

  /// Minute of day the all-day alert fires at. `NULL` means the Calendar
  /// settings default.
  IntColumn get dayMinute => integer().nullable()();

  /// Alarm sound id; `NULL` is the default sound. Meaningless for `notify`,
  /// which plays whatever its notification channel plays.
  TextColumn get sound => text().nullable()();

  /// The hub switch. A disabled alert is **kept** and never registered, so
  /// turning it back on restores exactly what it said.
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

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
