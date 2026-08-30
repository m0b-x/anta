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

  /// Seeds the built-in catalog: insert-if-not-exists for every entry, so a
  /// user's edits to a built-in's colour, icon, order or archive flag are
  /// never clobbered on a later launch.
  ///
  /// One `batch` — which drift runs as a single transaction and a single
  /// commit — rather than one awaited insert per seed. This runs on the first
  /// `CategoryService.getInstance()` of a session and again after every backup
  /// import, and `injection.dart` already records the nine-statement version
  /// as part of why the calendar services left the pre-`runApp` path.
  Future<void> seedMissing(List<CalendarCategoriesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(calendarCategories, entry, mode: InsertMode.insertOrIgnore);
      }
    });
  }

  /// Restores a backup's rows in one `batch` — the shape
  /// `EventTemplateDao.importAll` established: parsed first, written once, so
  /// a restore costs one commit rather than one per archived category, and a
  /// row that fails to parse cannot leave the table half-written.
  ///
  /// `insertOrReplace` because `CategoryService.importData` wipes the table
  /// first: an archive carrying the same id twice must cost the duplicate,
  /// never the whole restore.
  Future<void> importAll(List<CalendarCategoriesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(calendarCategories, entry, mode: InsertMode.insertOrReplace);
      }
    });
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
