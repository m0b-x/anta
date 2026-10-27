import 'package:drift/drift.dart';

import '../../models/calendar_event.dart' show CalendarEventCategory;
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../database.dart';
import '../tables/calendar_categories_table.dart';

part 'calendar_category_dao.g.dart';

/// All CRDT stamping for `calendar_categories` lives here (**v43**), the
/// [CalendarEventDao] rule: nothing above this class — `CategoryService`, the
/// `CalendarCategories` facade, backup — sees a CRDT field or a tombstone.
@DriftAccessor(tables: [CalendarCategories])
class CalendarCategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarCategoryDaoMixin {
  CalendarCategoryDao(super.db);

  /// The live-row predicate every read restates, spelled exactly as
  /// `idx_calendar_categories_active`'s `WHERE`. A literal rather than
  /// `isDeleted.equals(false)`, whose bound parameter the SQLite shipping to
  /// Android does not prove implies the index's predicate.
  static const _live = CustomExpression<bool>('is_deleted = 0');

  /// The built-in ids: every `CalendarEventCategory` name, the seeds'
  /// `id => kind.name`, `kFallbackCategoryId` among them.
  static final _builtInIds = {
    for (final kind in CalendarEventCategory.values) kind.name,
  };

  Future<List<CalendarCategoryRow>> getAll() {
    return (select(calendarCategories)
          ..where((c) => _live)
          ..orderBy([
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
  ///
  /// Every seed carries one shared HLC, but only the rows actually written
  /// keep it: a live built-in is never re-stamped, so a launch is not a write
  /// to every built-in — and since only the rows carrying that HLC are
  /// queued, a launch queues nothing either.
  ///
  /// The one conflict that does write is a **tombstoned** built-in, which is
  /// resurrected — keeping the user's last edits, flagged built-in again —
  /// rather than ignored. Built-ins are undeletable, but a tombstone can still
  /// arrive (a merge, or a row an older archive restored as custom), and
  /// ignoring it would hide that built-in for good, `other` — the fallback
  /// every orphaned event resolves to — included.
  Future<void> seedMissing(List<CalendarCategoriesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamp = db.newStamp();
      await batch((b) => _seed(b, entries, stamp));
    });
  }

  void _seed(
    Batch b,
    List<CalendarCategoriesCompanion> entries,
    CrdtStamp stamp,
  ) {
    for (final entry in entries) {
      b.insert(
        calendarCategories,
        entry.copyWith(
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
        ),
        onConflict: DoUpdate<$CalendarCategoriesTable, CalendarCategoryRow>(
          (old) => CalendarCategoriesCompanion.custom(
            isBuiltIn: const Constant(true),
            isDeleted: const Constant(false),
            deletedAt: const Constant<DateTime>(null),
            hlcTimestamp: Variable<String>(stamp.hlc),
            deviceId: Variable<String>(stamp.deviceId),
            version: old.version + const Constant(1),
          ),
          where: (old) => old.isDeleted,
        ),
      );
    }
    // A batch reports no per-row result, so the rows it wrote are found by
    // the stamp, inside the seeded ids.
    db.enqueueWrittenIn(b, calendarCategories, [
      for (final entry in entries) entry.id.value,
    ], stamp.hlc);
  }

  /// Restores a backup's rows in one `batch` — the shape
  /// `EventTemplateDao.importAll` established: parsed first, written once, so
  /// a restore costs one commit rather than one per archived category, and a
  /// row that fails to parse cannot leave the table half-written.
  ///
  /// `insertOrReplace` because `CategoryService.importData` wipes the table
  /// first: an archive carrying the same id twice must cost the duplicate,
  /// never the whole restore.
  ///
  /// Rows arrive as live `version 1` originals of this device, the
  /// [CalendarEventDao.importAll] convention: a restore is never a merge. Each
  /// is queued in the same batch, as any new local row is.
  Future<void> importAll(List<CalendarCategoriesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            calendarCategories,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, calendarCategories, entry.id.value, stamp.hlc);
        }
      });
    });
  }

  Future<void> insertCategory(CalendarCategoriesCompanion entry) {
    return transaction(() async {
      final stamp = await db.stampLocal(calendarCategories, entry.id.value);
      await into(calendarCategories).insert(
        entry.copyWith(
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
        ),
      );
    });
  }

  /// Update that preserves `created_at` by masking it out, mirroring
  /// `CalendarEventDao.upsert`.
  ///
  /// Read-then-write so the version can be bumped. A tombstoned category is
  /// left alone rather than resurrected: an edit that lands after the delete
  /// would otherwise bring back a category whose events already moved to the
  /// fallback — the no-op the hard delete this replaced gave.
  ///
  /// An edit that changes nothing but `updated_at` writes nothing, the way
  /// `CategoryService.setHidden` already refuses a repeated tap, so a save of
  /// an unchanged category does not read as a change once devices merge.
  Future<void> updateCategory(CalendarCategoriesCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _liveById(id);
      if (existing == null) return;
      final merged = existing.copyWithCompanion(
        entry.copyWith(createdAt: const Value.absent()),
      );
      if (merged.copyWith(updatedAt: existing.updatedAt) == existing) return;
      final stamp = await db.stampLocal(calendarCategories, id);
      await (update(calendarCategories)..where((c) => c.id.equals(id))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Tombstones a category, the [CalendarEventDao.softDeleteById] shape: the
  /// row survives with `is_deleted = 1` and a bumped version, so the delete
  /// carries an order once devices merge, and [getAll]'s filter is what makes
  /// it vanish. A missing or already-tombstoned row is a no-op.
  ///
  /// **Refuses every built-in** — by id as well as by flag, since an older
  /// archive could restore a built-in as custom — and returns false, so no
  /// path can tombstone one: `other` is where every orphaned event resolves.
  /// Returns true only when a row was tombstoned.
  Future<bool> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _deletable(id);
      if (existing == null) return false;
      await _tombstone(existing, db.newStamp());
      return true;
    });
  }

  /// Deletes a custom category as the one act it is to the user: its live
  /// events move to [reassignTo], its live alerts tombstone, and the category
  /// tombstones, all under **one** HLC and each row queued — so another device
  /// merges the delete whole rather than three changes it could interleave.
  ///
  /// [softDeleteById]'s refusals are checked before anything is written: a
  /// built-in, missing or already-tombstoned category moves no event and
  /// tombstones no alert. Returns whether the category was deleted.
  Future<bool> tombstoneCascade(String id, {required String reassignTo}) {
    return transaction(() async {
      final existing = await _deletable(id);
      if (existing == null) return false;
      final stamp = db.newStamp();
      await db.calendarEventDao.reassignCategory(id, reassignTo, stamp: stamp);
      await db.categoryAlertDao.tombstoneForCategory(id, stamp: stamp);
      await _tombstone(existing, stamp);
      return true;
    });
  }

  /// The live custom row [id], or null when it is missing, already a
  /// tombstone, or built in — by flag or by id.
  Future<CalendarCategoryRow?> _deletable(String id) async {
    final existing = await _liveById(id);
    if (existing == null || existing.isBuiltIn || _builtInIds.contains(id)) {
      return null;
    }
    return existing;
  }

  Future<void> _tombstone(CalendarCategoryRow existing, CrdtStamp stamp) async {
    final now = DateTime.now();
    await db.enqueue(
      calendarCategories,
      existing.id,
      stamp.hlc,
      op: OutboxOp.tombstone,
    );
    await (update(
      calendarCategories,
    )..where((c) => c.id.equals(existing.id))).write(
      CalendarCategoriesCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      ),
    );
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CalendarCategoryRow>> getByIdsIncludingDeleted(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(calendarCategories)..where((c) => c.id.isIn(ids))).get();
  }

  /// Merges one remote category on the contract of [CrdtMerge.mergeRemoteRow].
  /// A built-in's fixed id merges like any other, `is_built_in` included as
  /// received; a tombstone writes the stamps, the deletion and the owner and
  /// keeps the rest, and reassigns no event — the events moved by the delete
  /// elsewhere arrive as their own rows.
  Future<MergeOutcome> mergeRemoteCategory(
    CalendarCategoryRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await (select(
        calendarCategories,
      )..where((c) => c.id.equals(remote.id))).getSingleOrNull();
      return CrdtMerge.mergeRemoteRow(
        db,
        table: calendarCategories,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(calendarCategories).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              calendarCategories,
            )..where((c) => c.id.equals(remote.id))).write(
              CalendarCategoriesCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                updatedAt: CrdtMerge.tombstoneUpdatedAt(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            await update(calendarCategories).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// Hard wipe, tombstones included — the backup import's replace-everything
  /// step, which must stay hard: a restore is never a merge.
  Future<void> deleteAll() {
    return delete(calendarCategories).go();
  }

  /// Rewrites `sort_order` to a dense `0..N-1` matching [idsInOrder].
  ///
  /// One `batch` — which drift runs as a single transaction and a single
  /// commit — never an update per row awaited in a loop, and never a read
  /// first: `version + 1` is SQL arithmetic, and the drag shares one HLC.
  /// `query_count_test` guards the shape. A row already at its index is not
  /// written, so a drag re-stamps only the rows it moved.
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
    await transaction(() async {
      final stamp = db.newStamp();
      await batch((b) {
        for (var i = 0; i < idsInOrder.length; i++) {
          b.update(
            calendarCategories,
            CalendarCategoriesCompanion.custom(
              sortOrder: Variable<int>(i),
              updatedAt: Variable<DateTime>(now),
              hlcTimestamp: Variable<String>(stamp.hlc),
              deviceId: Variable<String>(stamp.deviceId),
              version: calendarCategories.version + const Constant(1),
            ),
            where: (c) =>
                c.id.equals(idsInOrder[i]) &
                _live &
                c.sortOrder.equals(i).not(),
          );
        }
        db.enqueueWrittenIn(b, calendarCategories, idsInOrder, stamp.hlc);
      });
    });
  }

  /// Next free sort order (max + 1, or 0 when the table is empty). Used to
  /// append newly created categories after every existing one.
  ///
  /// Counts tombstones on purpose, the `VocabularyDao` rule: a merge can
  /// resurrect a deleted category, and it must not land on a slot a newer one
  /// took. It returns a number, never a row, so no tombstone leaks upward.
  Future<int> nextSortOrder() async {
    final maxExpr = calendarCategories.sortOrder.max();
    final row = await (selectOnly(
      calendarCategories,
    )..addColumns([maxExpr])).getSingleOrNull();
    final current = row?.read(maxExpr);
    return (current ?? -1) + 1;
  }

  Future<CalendarCategoryRow?> _liveById(String id) {
    return (select(
      calendarCategories,
    )..where((c) => c.id.equals(id) & _live)).getSingleOrNull();
  }
}
