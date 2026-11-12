import 'package:drift/drift.dart';

/// Persisted calendar event categories.
///
/// Built-in categories are seeded by `CategoryService` with stable ids equal
/// to the historical `CalendarEventCategory` enum names (`'gym'`, `'cardio'`,
/// …) using insert-if-missing semantics, so user edits to a built-in's color
/// or icon survive subsequent launches and existing events (whose
/// `calendar_events.category` already holds those strings) link to them with
/// no data migration. User-created categories carry a UUID [id] and
/// `is_built_in = false`.
@DataClassName('CalendarCategoryRow')
class CalendarCategories extends Table {
  @override
  String get tableName => 'calendar_categories';

  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 32-bit ARGB color value.
  IntColumn get colorValue => integer()();

  /// Key into the `CalendarIcons` palette.
  TextColumn get iconKey => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();

  /// Archived: dropped from the pickers and the filter surfaces, but still
  /// resolvable, so events already carrying it keep their own colour instead
  /// of falling through to `other`. Distinct from the calendar page's
  /// transient `hiddenCategoryIds` render filter, which is not persisted.
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// The `calendar_events` block (**v43**): added to a populated table, so the
  /// identity pair carries the `''` default SQLite's `ADD COLUMN NOT NULL`
  /// demands, and the migration backfills it in the same run. All stamping
  /// lives in `CalendarCategoryDao`.
  TextColumn get hlcTimestamp => text().withDefault(const Constant(''))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The owning account once sync binds one (**v43**); NULL until then.
  TextColumn get ownerId => text().nullable()();

  /// The pair this category is shared into (**v56**,
  /// `docs/cloud-share-surfaces-roadmap.md` §7); NULL for a private one. Its
  /// events carry no mark for it: an event without a mark of its own is
  /// shared as its live category is, now and whenever it is added later.
  TextColumn get sharedPair => text().nullable()();

  /// The stamp of the write that last set or cleared [sharedPair] (**v56**),
  /// the register `calendar_events.shared_stamp` is: a merge keeps the mark
  /// with the newer stamp whichever side's row wins.
  TextColumn get sharedStamp => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
