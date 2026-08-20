import 'package:drift/drift.dart';

import '../../constants/public_holidays.dart';
import '../database.dart';
import '../tables/public_holidays_table.dart';

part 'public_holiday_dao.g.dart';

@DriftAccessor(tables: [PublicHolidaysTable])
class PublicHolidayDao extends DatabaseAccessor<AppDatabase>
    with _$PublicHolidayDaoMixin {
  PublicHolidayDao(super.db);

  Future<List<PublicHolidayRow>> getAll() {
    return (select(
      publicHolidaysTable,
    )..orderBy([(h) => OrderingTerm.asc(h.date)])).get();
  }

  /// Insert-if-not-exists. Returns true when the row was actually inserted.
  /// [profile] tags ownership so [deleteProfile] can later remove only the
  /// rows that belong to a given preset. [suppressed] round-trips the flag
  /// on backup import; regular seeding never passes it (new rows are never
  /// born suppressed).
  Future<bool> insertIfMissing({
    required DateTime date,
    required String nameKey,
    required String profile,
    String? customLabel,
    bool suppressed = false,
  }) async {
    final inserted = await into(publicHolidaysTable).insert(
      PublicHolidaysTableCompanion(
        date: Value(date),
        nameKey: Value(nameKey),
        profile: Value(profile),
        customLabel: Value(customLabel),
        suppressed: Value(suppressed),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    return inserted > 0;
  }

  /// Removes the holiday(s) on [date]: built-in rows are kept but flagged
  /// `suppressed` (so the seeder's insert-if-missing pass never resurrects
  /// them on the next app start or backup restore), while custom rows are
  /// hard-deleted (no re-seed to defend against).
  Future<void> suppressOn(DateTime date) async {
    await (update(publicHolidaysTable)..where(
          (h) =>
              h.date.equals(date) &
              h.nameKey.equals(kCustomPublicHolidayKey).not(),
        ))
        .write(const PublicHolidaysTableCompanion(suppressed: Value(true)));
    await (delete(publicHolidaysTable)..where(
          (h) =>
              h.date.equals(date) & h.nameKey.equals(kCustomPublicHolidayKey),
        ))
        .go();
  }

  /// Every row the user has suppressed, across every profile still present
  /// in the table. Feeds the "restore a removed holiday" settings list.
  Future<List<PublicHolidayRow>> getSuppressed() {
    return (select(publicHolidaysTable)
          ..where((h) => h.suppressed.equals(true))
          ..orderBy([(h) => OrderingTerm.asc(h.date)]))
        .get();
  }

  /// Deletes one specific dated row. Used to lift a suppression: built-in
  /// holidays are computed, so dropping the "not here" marker is what makes
  /// the holiday resolve again — clearing the flag would instead leave a
  /// stored copy of derived data behind.
  Future<void> deleteOn(DateTime date, String nameKey) {
    return (delete(
      publicHolidaysTable,
    )..where((h) => h.date.equals(date) & h.nameKey.equals(nameKey))).go();
  }

  /// Deletes every built-in row owned by [profile]. Custom rows
  /// (`profile = kCustomHolidayProfileKey`) are intentionally untouched
  /// so user data survives every profile switch.
  Future<int> deleteProfile(String profile) {
    return (delete(
      publicHolidaysTable,
    )..where((h) => h.profile.equals(profile))).go();
  }

  Future<void> deleteAll() {
    return delete(publicHolidaysTable).go();
  }
}
