import 'package:drift/drift.dart';

import '../crdt/crdt_write.dart';
import '../database.dart';
import '../tables/overview_views_table.dart';

part 'overview_view_dao.g.dart';

/// All CRDT stamping for `overview_views` lives here, never in the service —
/// the [FilterPresetDao] idiom, cloned so the two saved-list tables behave
/// alike under a future merge, the outbox included (**v43**).
@DriftAccessor(tables: [OverviewViews])
class OverviewViewDao extends DatabaseAccessor<AppDatabase>
    with _$OverviewViewDaoMixin {
  OverviewViewDao(super.db);

  /// Live views in display order, tie-broken on `id` so two views saved in
  /// the same millisecond still list deterministically.
  Future<List<OverviewViewRow>> getAll() {
    return (select(overviewViews)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// Inserts a new view or updates an existing one in place.
  ///
  /// An update bumps `version` from the stored row and leaves `created_at`
  /// alone, so a rename or an update to the current list keeps the date it
  /// was made. A tombstoned row is resurrected rather than duplicated; a save
  /// of a live view that changes nothing writes nothing.
  Future<void> upsertView(OverviewViewsCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);
      final now = DateTime.now();

      if (existing == null) {
        final stamp = await db.stampLocal(overviewViews, id);
        await into(overviewViews).insert(
          entry.copyWith(
            createdAt: entry.createdAt.present ? entry.createdAt : Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
        return;
      }

      if (!existing.isDeleted && db.changesNothing(existing, entry)) return;
      final stamp = await db.stampLocal(overviewViews, id);
      await (update(overviewViews)..where((t) => t.id.equals(id))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
        ),
      );
    });
  }

  /// Soft-deletes a view: the row survives as a tombstone so the delete
  /// carries an order once devices merge. A missing or already-tombstoned
  /// row is a no-op.
  Future<void> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        overviewViews,
        id,
        op: OutboxOp.tombstone,
      );
      await (update(overviewViews)..where((t) => t.id.equals(id))).write(
        OverviewViewsCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Next free display position. Tombstones count: reusing a dead view's
  /// slot would reorder the list if that view is ever resurrected.
  Future<int> nextSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM overview_views',
      readsFrom: {overviewViews},
    ).getSingle();
    return row.read<int>('max_order') + 1;
  }

  /// Rewrites `sort_order` to a dense `0..N-1` matching [idsInOrder] in one
  /// transaction of `UPDATE`s and no reads — [FilterPresetDao.reorder]'s
  /// contract: `version + 1` in SQL, a row already in place left alone, a
  /// tombstone or an unknown id untouched. Dense values matter because
  /// [getAll] tie-breaks on `id`. Only the rows it moved are queued.
  Future<void> reorder(List<String> idsInOrder) async {
    if (idsInOrder.isEmpty) return;
    final now = DateTime.now();

    await transaction(() async {
      final stamp = db.newStamp();
      final moved = <String>[];
      for (var i = 0; i < idsInOrder.length; i++) {
        final changed = await customUpdate(
          'UPDATE overview_views SET sort_order = ?, updated_at = ?, '
          'hlc_timestamp = ?, device_id = ?, version = version + 1 '
          'WHERE id = ? AND is_deleted = 0 AND sort_order != ?',
          variables: [
            Variable<int>(i),
            Variable<DateTime>(now),
            Variable<String>(stamp.hlc),
            Variable<String>(stamp.deviceId),
            Variable<String>(idsInOrder[i]),
            Variable<int>(i),
          ],
          updates: {overviewViews},
        );
        if (changed > 0) moved.add(idsInOrder[i]);
      }
      await db.enqueueMany(overviewViews, moved, stamp.hlc);
    });
  }

  /// Inserts views while preserving the caller's audit fields; identity is
  /// stamped **fresh** — a backup is not a sync channel, so a restored view
  /// is this device's own live row, queued like one. One batch for the whole
  /// archive.
  Future<void> importAll(List<OverviewViewsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            overviewViews,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, overviewViews, entry.id.value, stamp.hlc);
        }
      });
    });
  }

  /// The **hard** wipe, tombstones included, for the import path.
  Future<void> deleteAll() {
    return delete(overviewViews).go();
  }

  Future<OverviewViewRow?> _byId(String id) {
    return (select(
      overviewViews,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
