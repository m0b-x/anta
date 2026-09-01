import 'package:drift/drift.dart';

/// Saved calendar filter presets (**v35**).
///
/// A preset is a named `CalendarGridFilters` — "Tracked only", "P1 this
/// month", "Money" — that the user can re-apply in one tap instead of
/// rebuilding the same combination in the filter sheet each time.
///
/// [filters] holds the whole filter set as **one JSON blob**, the string
/// `CalendarGridFilters.encode()` already produces for
/// `SettingsKeys.calendarGridFilters`. Fifteen columns would have to grow with
/// every new axis and would duplicate a codec that already exists, tested, in
/// the model; a blob costs one decode per preset on a table that holds a
/// handful of rows. The decoder is forward- and backward-compatible by
/// construction (absent field ⇒ that field's default), so a preset saved by an
/// older build still applies after an axis is added, and one saved by a newer
/// build degrades instead of throwing.
///
/// Deliberately **not** a settings key holding a list. A preset is a named,
/// ordered, individually editable record with its own audit trail — the
/// `calendar_event_templates` (v29) shape, not the
/// `calendar_fasting_schedule` one. That is also what makes it back up and
/// restore like every other user-created row.
///
/// The five CRDT columns are the v29 block byte-for-byte, present from birth:
/// a table that starts empty gets the identity shape for free, with no
/// `withDefault('')` deviation needed because no existing row has to be
/// satisfied. Stamping lives entirely in `FilterPresetDao`.
///
/// A preset's only foreign reference is the category ids inside its blob, and
/// a stale one is already harmless everywhere else the filter is read (an id
/// no category answers to simply hides nothing), so this table needs no
/// strand rule on import.
@DataClassName('CalendarFilterPresetRow')
class CalendarFilterPresets extends Table {
  @override
  String get tableName => 'calendar_filter_presets';

  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `CalendarGridFilters.encode()` output — see the class doc.
  TextColumn get filters => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

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
