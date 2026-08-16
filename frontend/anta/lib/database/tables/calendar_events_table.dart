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
/// [colorValue] / [tintIcon] / [priority] (added in schema v16) drive
/// per-event presentation. [colorValue] is an optional 32-bit ARGB override
/// (NULL = use the category color); [tintIcon] decides whether that color
/// also tints the icon; [priority] (1–5, default 3) orders bars / summary
/// entries and decides which bars win a day cell's limited slots.
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
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
