import 'package:drift/drift.dart';

/// Persisted public holidays.
///
/// Each row is a single dated holiday. The composite primary key
/// `(date, name_key)` allows multiple holidays to coexist on the same
/// day — e.g. a built-in [PublicHoliday.easterMonday] and a user-added
/// custom note for that date — which the previous date-only PK could
/// not represent.
///
/// Columns:
/// - [date]: UTC date-only (year, month, day).
/// - [nameKey]: localizable enum name (e.g. `newYear`, `easterMonday`)
///   for built-in holidays. User-added rows use the sentinel `custom`
///   and store their display string in [customLabel].
/// - [profile]: which `HolidayProfile` owns this row. Built-in rows are
///   tagged with the profile that seeded them (e.g. `generic`,
///   `romania`); custom rows use the sentinel `custom`. This lets the
///   service swap profiles cleanly: rows tagged with the *previous*
///   profile are deleted, rows tagged `custom` survive every switch.
///
/// Since schema v22 this table holds **only user deltas** — custom
/// holidays and suppressions. Built-in holidays (including Easter and its
/// dependents) are no longer seeded as rows: they are computed per year
/// from `HolidaySeeds.forYear(profile, year)` and memoized, so every year
/// in `CalendarBounds` resolves without any stored rows at all.
@DataClassName('PublicHolidayRow')
class PublicHolidaysTable extends Table {
  @override
  String get tableName => 'public_holidays';

  /// UTC date-only (year, month, day).
  DateTimeColumn get date => dateTime()();
  TextColumn get nameKey => text()();

  /// Owning `HolidayProfile.name` for built-in rows, or the sentinel
  /// `custom` for user-added rows. Defaulted in SQL so legacy rows from
  /// schema versions ≤ 12 (which had no profile concept) cleanly back-fill
  /// to the historical Catholic-leaning seed set.
  TextColumn get profile => text().withDefault(const Constant('generic'))();
  TextColumn get customLabel => text().nullable()();

  /// User-suppressed for this specific dated row. Built-in rows are kept
  /// (not deleted) when suppressed, precisely so the seeder's
  /// insert-if-missing pass never resurrects them on the next app start
  /// or after a backup restore; `PublicHolidayService._load()` skips
  /// suppressed rows when building the lookup cache. Custom rows are
  /// still hard-deleted on removal since there is no re-seed to defend
  /// against. Defaults to `false` so existing rows are unaffected.
  BoolColumn get suppressed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {date, nameKey};
}
