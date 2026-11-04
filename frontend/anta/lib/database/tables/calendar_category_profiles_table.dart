import 'package:drift/drift.dart';

/// What a calendar category *is* and how it is counted (**v44**) — its kind
/// from the catalogue and the owner's overrides of that kind's defaults.
///
/// Shaped like `calendar_category_alerts` (the analytics record's decision G)
/// so it syncs, soft-deletes and backs up with no new pattern: keyed by its
/// own id, naming its category by the stable id, the CRDT block and
/// `owner_id` byte-for-byte. One live row per category is the rule
/// `CategoryProfileDao.upsertForCategory` converges to; a category without a
/// row is a `custom` category with nothing overridden.
///
/// Every override column is nullable and `NULL` means "the kind's default", so
/// a kind whose defaults change later moves every category that never chose
/// otherwise. [markVerb] `''` is a value, not an absence: marking turned off.
@DataClassName('CategoryProfileRow')
class CalendarCategoryProfiles extends Table {
  @override
  String get tableName => 'calendar_category_profiles';

  TextColumn get id => text()();

  TextColumn get categoryId => text()();

  /// The catalogue key; `custom` when the owner never picked one.
  TextColumn get kind => text().withDefault(const Constant('custom'))();

  TextColumn get area => text().nullable()();

  /// Override of the kind's primary measure.
  TextColumn get measure => text().nullable()();

  /// The confirmed "counts as" length an untimed occurrence earns; `NULL` is
  /// none.
  IntColumn get nominalMinutes => integer().nullable()();

  /// Override of the kind's mark verb; `''` turns marking off.
  TextColumn get markVerb => text().nullable()();

  /// Whether new events in the category track presence.
  BoolColumn get marksNew => boolean().nullable()();

  /// Whether new events in the category assume absent.
  BoolColumn get assumeAbsentNew => boolean().nullable()();

  BoolColumn get countsHours => boolean().nullable()();

  /// `atLeast` | `atMost` | `maxGap` | `budget`; `NULL` is no goal.
  TextColumn get targetKind => text().nullable()();

  IntColumn get targetValue => integer().nullable()();

  /// `day` | `week` | `month` | `year`.
  TextColumn get targetPeriod => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The owning account once sync binds one; NULL until then.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
