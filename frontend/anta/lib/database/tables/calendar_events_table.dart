import 'package:drift/drift.dart';

/// Persisted custom calendar events. The recurrence rule is stored as
/// [ruleKind] plus an optional JSON [rulePayload] for kinds that carry data
/// (currently only `weekly` uses payload `{"weekdays":[1,3,5]}`).
///
/// [endDate] (added in schema v11) is an inclusive upper bound for any
/// recurring rule — the event stops producing occurrences strictly after
/// this UTC date. `null` means "no end".
///
/// [startMinute] / [durationMinutes] (also v11, reserved) are placeholders
/// for future time-of-day events. They are currently never written by
/// application code; they exist so we can introduce timed events without
/// another migration.
///
/// [noteId] (added in schema v14) is an optional link to a workout note
/// (`notes.id`). `null` means the event has no linked note. The folder is
/// resolved from the note at navigation time, so only the id is stored —
/// the link survives the note being moved between folders.
///
/// [retroactive] (added in schema v19) lifts the recurrence engine's
/// pre-start guard: when set, the rule also produces occurrences before
/// [startDate]. Defaults to 0, which is exactly the pre-v19 behaviour.
///
/// [countOccurrences] (added in schema v20) is display-only: each occurrence
/// of a periodic rule carries a count label derived from [startDate]. It
/// never affects occurrence math. [countStyle] (v21) picks the label shape:
/// `numbered` ("Day 1", "Week 3" — the start day is the first) or `elapsed`
/// ("30 years" — a birthday anchored on the birth date shows the age).
///
/// [tracksPresence] (added in schema v26) is the per-event opt-in for
/// presence tracking: skipped occurrences are marked in
/// `calendar_event_absences` and rendered faded or hidden. Defaults to 0, and
/// it only means anything for a rule with more than one occurrence — the gate
/// is `tracksPresence && rule is! OneTimeRecurrence`.
///
/// [perOccurrenceDescriptions] (added in schema v28) is the [tracksPresence]
/// twin for description scope: the event's own [description] becomes a
/// template and `calendar_event_occurrences` holds only the days that differ.
/// It replaces the single global switch v24 shipped, so the same gate applies
/// — `perOccurrenceDescriptions && rule is! OneTimeRecurrence`, via
/// `OccurrenceDescriptions.appliesTo`. Defaults to 0, which renders one shared
/// description exactly as a global-off install did.
///
/// [showInDayRail] (added in schema v34) is the per-event override for
/// membership in the day-cell rail — the second, multi-source presence
/// channel next to the single-event tint. It is the schema's first nullable
/// bool on purpose: NULL (the default) means *auto* — the event is in the
/// rail exactly when `EventPresence.appliesTo` holds; `true` forces it in,
/// `false` forces it out. The recurrence guard lives in the shared predicate
/// (`eventInDayRail`), so `true` on a one-time event still stays out.
///
/// [colorValue] / [tintIcon] / [priority] (added in schema v16) drive
/// per-event presentation. [colorValue] is an optional 32-bit ARGB override
/// (NULL = use the category color); [tintIcon] decides whether that color
/// also tints the icon; [priority] (1–5, default 3) orders bars / summary
/// entries and decides which bars win a day cell's limited slots.
///
/// The five CRDT columns (added in schema v27) are the Notes/Folders
/// block with one deviation: [hlcTimestamp] / [deviceId] carry
/// `withDefault(const Constant(''))` where `notes_table.dart` leaves them
/// default-less, because v27 added them to a populated table and SQLite's
/// `ALTER TABLE … ADD COLUMN NOT NULL` demands a default. The declaration has
/// to match the migrated shape, so the default lives here too — but `''` is
/// transitional, not valid: the migration backfills real identity immediately
/// and `CalendarEventDao` stamps every write. Observing `''` at runtime means
/// something wrote around the DAO.
///
/// [isDeleted] / [deletedAt] make a deleted event a **tombstone**: the single
/// read path filters them, `idx_calendar_events_start_date` is partial on the
/// same predicate, and nothing above the DAO — model, service, blocs, backup —
/// can tell a tombstone from a delete.
@DataClassName('CalendarEventRow')
class CalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get category => text()();
  DateTimeColumn get startDate => dateTime()();
  BoolColumn get allDay => boolean().withDefault(const Constant(true))();
  TextColumn get iconKey => text().nullable()();
  TextColumn get ruleKind => text()();
  TextColumn get rulePayload => text().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get startMinute => integer().nullable()();
  IntColumn get durationMinutes => integer().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get noteId => text().nullable()();
  IntColumn get colorValue => integer().nullable()();
  BoolColumn get tintIcon => boolean().withDefault(const Constant(true))();
  IntColumn get priority => integer().withDefault(const Constant(3))();
  BoolColumn get retroactive => boolean().withDefault(const Constant(false))();
  BoolColumn get countOccurrences =>
      boolean().withDefault(const Constant(false))();
  TextColumn get countStyle => text().withDefault(const Constant('numbered'))();
  BoolColumn get tracksPresence =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get perOccurrenceDescriptions =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showInDayRail => boolean().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
