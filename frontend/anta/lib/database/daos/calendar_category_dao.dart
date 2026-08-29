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

  /// Rewrites `sort_order` to a dense `0..N-1` matching [idsInOrder].
  ///
  /// One `batch` — which drift runs as a single transaction and a single
  /// commit — never an update per row awaited in a loop, and never a read
  /// first: this table carries no CRDT columns, so there is no `version + 1`
  /// to compute and nothing to fetch. `query_count_test` guards the shape.
  ///
  /// **Dense values matter.** `CalendarCategories._byOrder` tie-breaks on
  /// `id`, so leaving gaps or duplicates lets rows shuffle among themselves
  /// on the next load, which reads as the drag not having stuck.
  ///
  /// Ids not present in the table update nothing; a repeated id is written
  /// twice and the last wins. Neither can corrupt the ordering of the rest.
  Future<void> reorder(List<String> idsInOrder) async {
    if (idsInOrder.isEmpty) return;
    final now = DateTime.now();
    await batch((b) {
      for (var i = 0; i < idsInOrder.length; i++) {
        b.update(
          calendarCategories,
          CalendarCategoriesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
          ),
          where: (c) => c.id.equals(idsInOrder[i]),
        );
      }
    });
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
