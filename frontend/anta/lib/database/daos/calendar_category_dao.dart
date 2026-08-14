import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/calendar_categories_table.dart';

part 'calendar_category_dao.g.dart';

@DriftAccessor(tables: [CalendarCategories])
class CalendarCategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarCategoryDaoMixin {
  CalendarCategoryDao(super.db);

  Future<List<CalendarCategoryRow>> getAll() {
    return (select(calendarCategories)..orderBy([
          (c) => OrderingTerm.asc(c.sortOrder),
          (c) => OrderingTerm.asc(c.id),
        ]))
        .get();
  }

  /// Insert-if-not-exists. Used to seed built-ins idempotently so user edits
  /// to a built-in's color/icon are never clobbered on a later launch.
  /// Returns true when the row was actually inserted.
  Future<bool> insertIfMissing(CalendarCategoriesCompanion entry) async {
    final inserted = await into(
      calendarCategories,
    ).insert(entry, mode: InsertMode.insertOrIgnore);
    return inserted > 0;
  }

  Future<void> insertCategory(CalendarCategoriesCompanion entry) {
    return into(calendarCategories).insert(entry);
  }

  /// Update that preserves `created_at` by masking it out, mirroring
  /// `CalendarEventDao.upsert`.
  Future<void> updateCategory(CalendarCategoriesCompanion entry) {
    return (update(calendarCategories)
          ..where((c) => c.id.equals(entry.id.value)))
        .write(entry.copyWith(createdAt: const Value.absent()));
  }

  Future<void> deleteById(String id) {
    return (delete(calendarCategories)..where((c) => c.id.equals(id))).go();
  }

  Future<void> deleteAll() {
    return delete(calendarCategories).go();
  }

  /// Next free sort order (max + 1, or 0 when the table is empty). Used to
  /// append newly created categories after every existing one.
  Future<int> nextSortOrder() async {
    final maxExpr = calendarCategories.sortOrder.max();
    final row = await (selectOnly(
      calendarCategories,
    )..addColumns([maxExpr])).getSingleOrNull();
    final current = row?.read(maxExpr);
    return (current ?? -1) + 1;
  }
}
