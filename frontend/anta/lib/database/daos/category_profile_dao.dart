import 'package:drift/drift.dart';

import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../database.dart';
import '../tables/calendar_category_profiles_table.dart';

part 'category_profile_dao.g.dart';

/// All CRDT stamping for `calendar_category_profiles` lives here, never in the
/// service — [CategoryAlertDao]'s shape with one live row per category in
/// place of a set, so the two category-keyed tables behave alike under a merge
/// and in the outbox. Nothing above this class sees a CRDT field, a tombstone
/// or the outbox.
@DriftAccessor(tables: [CalendarCategoryProfiles])
class CategoryProfileDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryProfileDaoMixin {
  CategoryProfileDao(super.db);

  /// Every live profile, in one statement — the single read path, with the
  /// same `is_deleted = 0` literal as [CategoryAlertDao.getAllActive].
  ///
  /// Two live rows of one category can stand here after a merge (each device
  /// made its own before they met) until the next local write converges them;
  /// the order puts the newest stamp last so a reader keyed by category keeps
  /// it.
  Future<List<CategoryProfileRow>> getAllActive() {
    return (select(calendarCategoryProfiles)
          ..where((p) => const CustomExpression<bool>('is_deleted = 0'))
          ..orderBy([
            (p) => OrderingTerm.asc(p.categoryId),
            (p) => OrderingTerm.asc(p.hlcTimestamp),
          ]))
        .get();
  }

  /// The live profile of [categoryId], or null when it has none — the newest
  /// one if a merge left two, by [getAllActive]'s order.
  Future<CategoryProfileRow?> getActiveForCategory(String categoryId) async {
    final rows = await _liveFor(categoryId);
    return rows.isEmpty ? null : rows.last;
  }

  Future<List<CategoryProfileRow>> _liveFor(String categoryId) {
    return (select(calendarCategoryProfiles)
          ..where(
            (p) =>
                p.categoryId.equals(categoryId) &
                const CustomExpression<bool>('is_deleted = 0'),
          )
          ..orderBy([(p) => OrderingTerm.asc(p.hlcTimestamp)]))
        .get();
  }

  /// Makes [draft] the profile of its category, in one transaction under one
  /// HLC.
  ///
  /// A live row of the category is updated **in place, keeping its id** —
  /// whatever id the draft carries — so an edit is one row moving forward
  /// rather than a delete and an insert another device could interleave.
  /// Without one, the draft takes its own id: a tombstone under that id comes
  /// back live with `version + 1`, otherwise the row is inserted; a live row
  /// of another category under that id is an [ArgumentError].
  ///
  /// **Convergence**: any *other* live row of the category is tombstoned in
  /// the same write. Two devices may each have created a profile before they
  /// met; the merge keeps both (the stamp decides per id, not per category),
  /// and the first local save after it leaves one. The row kept is the newest
  /// stamp, the one [getActiveForCategory] was already showing.
  ///
  /// An unchanged save writes nothing, [CategoryAlertDao.replaceForCategory]'s
  /// rule: a fresh HLC on a profile nobody edited would beat a real edit made
  /// elsewhere. Writes are queued as the alerts' are — the kept row as an
  /// upsert, the converged ones as tombstones.
  Future<void> upsertForCategory(CalendarCategoryProfilesCompanion draft) {
    final categoryId = draft.categoryId.value;
    return transaction(() async {
      final live = await _liveFor(categoryId);
      final kept = live.isEmpty ? null : live.last;
      final others = [
        for (final row in live)
          if (row.id != kept?.id) row,
      ];
      final unchanged =
          kept != null &&
          others.isEmpty &&
          db.changesNothing(kept, _content(draft, categoryId));
      if (unchanged) return;

      // A tombstone can already hold the draft's id — the category was
      // deleted and its profile cascaded, a pull tombstoned it, or `clear`
      // ran — so the id is read past the live filter and revived in place, as
      // [CategoryAlertDao.replaceForCategory] does; an insert would fail its
      // primary key.
      final buried = kept != null
          ? null
          : await (select(
              calendarCategoryProfiles,
            )..where((p) => p.id.equals(draft.id.value))).getSingleOrNull();

      // A live row under the draft's id is another category's profile (this
      // category's live rows are `kept` and `others`): taking it would move
      // that profile, and an insert would fail the primary key. Refused
      // before a stamp is minted, so the clock does not move for nothing.
      if (buried != null && !buried.isDeleted) {
        throw ArgumentError.value(
          draft.id.value,
          'draft.id',
          'is the live profile of category "${buried.categoryId}", '
              'not of "$categoryId"',
        );
      }

      final now = DateTime.now();
      final stamp = db.newStamp();

      for (final row in others) {
        await (update(
          calendarCategoryProfiles,
        )..where((p) => p.id.equals(row.id))).write(
          CalendarCategoryProfilesCompanion(
            isDeleted: const Value(true),
            deletedAt: Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(row.version + 1),
          ),
        );
      }

      final String writtenId;
      if (buried != null) {
        writtenId = buried.id;
        await (update(
          calendarCategoryProfiles,
        )..where((p) => p.id.equals(buried.id))).write(
          _content(draft, categoryId).copyWith(
            // The insert path's rule: a present draft date wins, else the
            // tombstone keeps the one it was first created with.
            createdAt: draft.createdAt.present
                ? draft.createdAt
                : const Value.absent(),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(buried.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
      } else if (kept == null) {
        writtenId = draft.id.value;
        await into(calendarCategoryProfiles).insert(
          draft.copyWith(
            categoryId: Value(categoryId),
            createdAt: draft.createdAt.present ? draft.createdAt : Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
      } else {
        writtenId = kept.id;
        await (update(
          calendarCategoryProfiles,
        )..where((p) => p.id.equals(kept.id))).write(
          _content(draft, categoryId).copyWith(
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(kept.version + 1),
          ),
        );
      }

      await db.enqueueMany(
        calendarCategoryProfiles,
        [for (final row in others) row.id],
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
      await db.enqueue(calendarCategoryProfiles, writtenId, stamp.hlc);
    });
  }

  /// The draft's payload alone — no identity, audit or CRDT field — so an
  /// in-place update can never move a row's id or stamps by accident.
  static CalendarCategoryProfilesCompanion _content(
    CalendarCategoryProfilesCompanion draft,
    String categoryId,
  ) {
    return CalendarCategoryProfilesCompanion(
      categoryId: Value(categoryId),
      kind: draft.kind,
      area: draft.area,
      measure: draft.measure,
      nominalMinutes: draft.nominalMinutes,
      markVerb: draft.markVerb,
      marksNew: draft.marksNew,
      assumeAbsentNew: draft.assumeAbsentNew,
      countsHours: draft.countsHours,
      targetKind: draft.targetKind,
      targetValue: draft.targetValue,
      targetPeriod: draft.targetPeriod,
    );
  }

  /// Cascade for a deleted category, [CategoryAlertDao.tombstoneForCategory]'s
  /// shape: one statement, `version + 1` in SQL, one shared HLC, live rows
  /// only so a repeat cannot churn versions. `RETURNING id` queues exactly
  /// the rows it tombstoned and hands them back; [stamp] is the category
  /// delete's own, from [CalendarCategoryDao.tombstoneCascade].
  Future<List<String>> tombstoneForCategory(
    String categoryId, {
    CrdtStamp? stamp,
  }) {
    return transaction(() async {
      final shared = stamp ?? db.newStamp();
      final now = DateTime.now();
      final tombstoned = await customWriteReturning(
        'UPDATE calendar_category_profiles SET is_deleted = 1, '
        'deleted_at = ?, updated_at = ?, hlc_timestamp = ?, device_id = ?, '
        'version = version + 1 '
        'WHERE category_id = ? AND is_deleted = 0 RETURNING id',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(shared.hlc),
          Variable<String>(shared.deviceId),
          Variable<String>(categoryId),
        ],
        updates: {calendarCategoryProfiles},
        updateKind: UpdateKind.update,
      );
      final ids = [for (final row in tombstoned) row.read<String>('id')];
      await db.enqueueMany(
        calendarCategoryProfiles,
        ids,
        shared.hlc,
        op: OutboxOp.tombstone,
      );
      return ids;
    });
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CategoryProfileRow>> getByIdsIncludingDeleted(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(
      calendarCategoryProfiles,
    )..where((p) => p.id.isIn(ids))).get();
  }

  /// Merges one remote profile on the contract of [CrdtMerge.mergeRemoteRow],
  /// its columns as received — [CategoryAlertDao.mergeRemoteCategoryAlert]'s
  /// rules. The newest stamp decides per id; a second live row for the same
  /// category is kept, not refused, and converged by the next
  /// [upsertForCategory]. A tombstone writes the stamps, the deletion and the
  /// owner and keeps the rest.
  Future<MergeOutcome> mergeRemoteCategoryProfile(
    CategoryProfileRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await (select(
        calendarCategoryProfiles,
      )..where((p) => p.id.equals(remote.id))).getSingleOrNull();
      return CrdtMerge.mergeRemoteRow(
        db,
        table: calendarCategoryProfiles,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(calendarCategoryProfiles).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              calendarCategoryProfiles,
            )..where((p) => p.id.equals(remote.id))).write(
              CalendarCategoryProfilesCompanion(
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
            await update(calendarCategoryProfiles).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// The **hard** wipe, tombstones included, for the import path.
  Future<void> deleteAll() {
    return delete(calendarCategoryProfiles).go();
  }

  /// A restore's [deleteAll] and [importAll] in one transaction, so an import
  /// that fails part-way leaves this database's profiles as they were.
  Future<void> replaceAll(List<CalendarCategoryProfilesCompanion> entries) {
    return transaction(() async {
      await deleteAll();
      await importAll(entries);
    });
  }

  /// Inserts profiles while preserving the caller's audit fields; identity is
  /// stamped **fresh** — a backup is not a sync channel. One batch for the
  /// whole archive, [CategoryAlertDao.importAll]'s shape, each row queued in
  /// it.
  Future<void> importAll(List<CalendarCategoryProfilesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            calendarCategoryProfiles,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, calendarCategoryProfiles, entry.id.value, stamp.hlc);
        }
      });
    });
  }
}
