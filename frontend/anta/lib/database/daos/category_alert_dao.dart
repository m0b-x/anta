import 'package:drift/drift.dart';

import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../database.dart';
import '../tables/calendar_category_alerts_table.dart';

part 'category_alert_dao.g.dart';

/// All CRDT stamping for `calendar_category_alerts` lives here, never in the
/// service — [EventAlertDao] verbatim with the category as the owner, so the
/// two alert tables behave alike under a future merge, the outbox included
/// (**v43**). Nothing above this class sees a CRDT field, a tombstone or the
/// outbox.
@DriftAccessor(tables: [CalendarCategoryAlerts])
class CategoryAlertDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryAlertDaoMixin {
  CategoryAlertDao(super.db);

  /// Every live category alert, in one statement — the single read path, as
  /// [EventAlertDao.getAllActive] is for the event table. The predicate is the
  /// same `is_deleted = 0` literal for the same reason: one spelling for every
  /// statement that filters live rows.
  Future<List<CategoryAlertRow>> getAllActive() {
    return (select(calendarCategoryAlerts)
          ..where((a) => const CustomExpression<bool>('is_deleted = 0'))
          ..orderBy([
            (a) => OrderingTerm.asc(a.categoryId),
            (a) => OrderingTerm.asc(a.createdAt),
          ]))
        .get();
  }

  /// Makes [entries] the complete set of alerts for [categoryId], in one
  /// transaction: missing rows are **tombstoned**, kept rows re-stamped only
  /// if something in them changed, new rows inserted.
  ///
  /// [EventAlertDao.replaceForEvent]'s contract and its reasons: an unchanged
  /// row is not written (a fresh HLC on an alert nobody touched would beat a
  /// real edit made elsewhere), a kept row keeps its identity, a re-added id
  /// resurrects its row, and the category's rows are read once rather than
  /// one `SELECT` per alert — and its queueing: one HLC for the save,
  /// removals as tombstones, inserts and edits as upserts.
  Future<void> replaceForCategory(
    String categoryId,
    List<CalendarCategoryAlertsCompanion> entries,
  ) {
    return transaction(() async {
      final existing = await (select(
        calendarCategoryAlerts,
      )..where((a) => a.categoryId.equals(categoryId))).get();
      final byId = {for (final row in existing) row.id: row};
      final keep = {for (final entry in entries) entry.id.value};
      final now = DateTime.now();
      final stamp = db.newStamp();
      final removed = <String>[];
      final written = <String>[];

      for (final row in existing) {
        if (row.isDeleted || keep.contains(row.id)) continue;
        await (update(
          calendarCategoryAlerts,
        )..where((a) => a.id.equals(row.id))).write(
          CalendarCategoryAlertsCompanion(
            isDeleted: const Value(true),
            deletedAt: Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(row.version + 1),
          ),
        );
        removed.add(row.id);
      }

      for (final entry in entries) {
        final row = byId[entry.id.value];
        if (row != null && _sameContent(row, entry, categoryId)) continue;
        written.add(entry.id.value);
        if (row == null) {
          await into(calendarCategoryAlerts).insert(
            entry.copyWith(
              categoryId: Value(categoryId),
              createdAt: entry.createdAt.present ? entry.createdAt : Value(now),
              updatedAt: Value(now),
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
          );
          continue;
        }
        await (update(
          calendarCategoryAlerts,
        )..where((a) => a.id.equals(row.id))).write(
          entry.copyWith(
            categoryId: Value(categoryId),
            createdAt: const Value.absent(),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(row.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
      }

      await db.enqueueMany(
        calendarCategoryAlerts,
        removed,
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
      await db.enqueueMany(calendarCategoryAlerts, written, stamp.hlc);
    });
  }

  /// Whether [entry] would leave a live [row] saying exactly what it says now.
  /// An absent companion field is one the write would not touch.
  static bool _sameContent(
    CategoryAlertRow row,
    CalendarCategoryAlertsCompanion entry,
    String categoryId,
  ) {
    bool same<T>(Value<T> next, T current) =>
        !next.present || next.value == current;
    return !row.isDeleted &&
        row.categoryId == categoryId &&
        same(entry.mode, row.mode) &&
        same(entry.offsetMinutes, row.offsetMinutes) &&
        same(entry.daysBefore, row.daysBefore) &&
        same(entry.dayMinute, row.dayMinute) &&
        same(entry.sound, row.sound) &&
        same(entry.enabled, row.enabled);
  }

  /// Cascade for a deleted category, [EventAlertDao.tombstoneForEvent]'s
  /// shape: one statement, `version + 1` in SQL, one shared HLC, live rows
  /// only so a repeat cannot churn versions. `updated_at` / `deleted_at` bind
  /// as `Variable<DateTime>` because Drift stores unix seconds. `RETURNING id`
  /// queues exactly the rows it tombstoned; [stamp] is the category delete's
  /// own, from [CalendarCategoryDao.tombstoneCascade].
  Future<void> tombstoneForCategory(String categoryId, {CrdtStamp? stamp}) {
    return transaction(() async {
      final shared = stamp ?? db.newStamp();
      final now = DateTime.now();
      final tombstoned = await customWriteReturning(
        'UPDATE calendar_category_alerts SET is_deleted = 1, deleted_at = ?, '
        'updated_at = ?, hlc_timestamp = ?, device_id = ?, '
        'version = version + 1 '
        'WHERE category_id = ? AND is_deleted = 0 RETURNING id',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(shared.hlc),
          Variable<String>(shared.deviceId),
          Variable<String>(categoryId),
        ],
        updates: {calendarCategoryAlerts},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(
        calendarCategoryAlerts,
        [for (final row in tombstoned) row.read<String>('id')],
        shared.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CategoryAlertRow>> getByIdsIncludingDeleted(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(calendarCategoryAlerts)..where((a) => a.id.isIn(ids))).get();
  }

  /// Merges one remote category alert on the contract of
  /// [CrdtMerge.mergeRemoteRow], its columns as received. Unlike
  /// [replaceForCategory] it never refuses an id another category owns: the
  /// newest stamp decides, as for every row. A tombstone writes the stamps,
  /// the deletion and the owner and keeps the rest.
  Future<MergeOutcome> mergeRemoteCategoryAlert(
    CategoryAlertRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await (select(
        calendarCategoryAlerts,
      )..where((a) => a.id.equals(remote.id))).getSingleOrNull();
      return CrdtMerge.mergeRemoteRow(
        db,
        table: calendarCategoryAlerts,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(calendarCategoryAlerts).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              calendarCategoryAlerts,
            )..where((a) => a.id.equals(remote.id))).write(
              CalendarCategoryAlertsCompanion(
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
            await update(calendarCategoryAlerts).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// The **hard** wipe, tombstones included, for the import path.
  Future<void> deleteAll() {
    return delete(calendarCategoryAlerts).go();
  }

  /// Inserts alerts while preserving the caller's audit fields; identity is
  /// stamped **fresh** — a backup is not a sync channel. One batch for the
  /// whole archive, [EventAlertDao.importAll]'s shape, each row queued in it.
  Future<void> importAll(List<CalendarCategoryAlertsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            calendarCategoryAlerts,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, calendarCategoryAlerts, entry.id.value, stamp.hlc);
        }
      });
    });
  }
}
