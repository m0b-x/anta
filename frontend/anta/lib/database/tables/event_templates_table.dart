import 'package:drift/drift.dart';

/// Reusable event presets (**v29**).
///
/// A template is everything an event needs *except* a date: category,
/// schedule shape, time-of-day, colour, icon, priority, description and the
/// per-event opt-in flags. Applying one to a day stamps out a `CalendarEvent`
/// with that day as its start.
///
/// Deliberately **not** columns on `calendar_categories`. A category is a
/// taxonomy — one row per kind of thing — while a user wants several presets
/// inside one category ("Push day" and "Leg day" both under Gym). Folding
/// defaults into the category would cap that at one preset per category
/// forever.
///
/// [name] doubles as the title stamped onto the created event; categories set
/// the one-label precedent, and a separate `title` column is additive later if
/// a template ever needs a label that differs from what it produces.
///
/// Nullable columns mean "leave it to the default at apply time", and only
/// where `null` already means that on the event itself: [iconKey] and
/// [colorValue] fall back to the category, [startMinute] `null` means all-day
/// (which is why there is no `all_day` column — the event's own is a
/// write-only mirror of `time == null`), [description] means none, and
/// [rulePayload] carries data only for the kinds that have any.
///
/// There is deliberately **no `note_id`**: a linked note is per-instance data,
/// and stamping one note onto many events would break the money ledger's
/// per-(day, note) attribution.
///
/// The five CRDT columns are the Notes/Folders block byte-for-byte, present
/// from birth. The v27 retrofit of `calendar_events` priced the alternative:
/// five `ALTER TABLE`s plus an identity backfill plus an index swap. A table
/// that starts empty gets the same shape for free, with no `withDefault('')`
/// deviation needed on [hlcTimestamp] / [deviceId] because no existing row has
/// to be satisfied. Stamping lives entirely in `EventTemplateDao`.
@DataClassName('EventTemplateRow')
class EventTemplates extends Table {
  @override
  String get tableName => 'calendar_event_templates';

  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Category id, matching `calendar_events.category`.
  TextColumn get category => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get ruleKind => text().withDefault(const Constant('oneTime'))();
  TextColumn get rulePayload => text().nullable()();

  IntColumn get startMinute => integer().nullable()();
  IntColumn get durationMinutes => integer().nullable()();

  TextColumn get description => text().nullable()();
  TextColumn get iconKey => text().nullable()();
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
