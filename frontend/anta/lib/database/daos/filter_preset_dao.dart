import 'package:drift/drift.dart';

import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../database.dart';
import '../tables/calendar_filter_presets_table.dart';

part 'filter_preset_dao.g.dart';

/// All CRDT stamping for `calendar_filter_presets` lives here, never in the
/// service: a `CrdtWrite` stamp, the row queued in the same transaction
/// (**v43**), and read-then-write `version + 1`, the [EventTemplateDao]
/// idiom.
@DriftAccessor(tables: [CalendarFilterPresets])
class FilterPresetDao extends DatabaseAccessor<AppDatabase>
    with _$FilterPresetDaoMixin {
  FilterPresetDao(super.db);

  /// Live presets in display order. Tombstones stay below the service's
  /// waterline — they exist for a future merge, not for anything the app
  /// renders. Ordered by `id` after `sort_order` so two presets saved in the
  /// same millisecond still list deterministically.
  Future<List<CalendarFilterPresetRow>> getAll() {
    return (select(calendarFilterPresets)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// Inserts a new preset or updates an existing one in place.
  ///
  /// An update bumps `version` from the stored row and leaves `created_at`
  /// alone, so renaming a preset or re-saving it over the current filters
  /// keeps the date it was made. A tombstoned row is resurrected rather than
  /// duplicated — ids are caller-supplied, and a re-imported id must not
  /// collide. A save of a live preset that changes nothing writes nothing.
  Future<void> upsertPreset(CalendarFilterPresetsCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);
      final now = DateTime.now();

      if (existing == null) {
        final stamp = await db.stampLocal(calendarFilterPresets, id);
        await into(calendarFilterPresets).insert(
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
      final stamp = await db.stampLocal(calendarFilterPresets, id);
      await (update(
        calendarFilterPresets,
      )..where((t) => t.id.equals(id))).write(
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

  /// Soft-deletes a preset, the [EventTemplateDao.softDeleteById] shape: the
  /// row survives as a tombstone so the delete carries an order once devices
  /// merge. A missing or already-tombstoned row is a no-op.
  Future<void> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        calendarFilterPresets,
        id,
        op: OutboxOp.tombstone,
      );
      await (update(
        calendarFilterPresets,
      )..where((t) => t.id.equals(id))).write(
        CalendarFilterPresetsCompanion(
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

  /// Next free display position. Tombstones count: reusing a dead preset's
  /// slot would reorder the list if that preset is ever resurrected.
  Future<int> nextSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order '
      'FROM calendar_filter_presets',
      readsFrom: {calendarFilterPresets},
    ).getSingle();
    return row.read<int>('max_order') + 1;
  }

  /// Rewrites `sort_order` to a dense `0..N-1` matching [idsInOrder] — the
  /// display order the sheet hands over after a drag or a Move to top.
  ///
  /// One transaction of `UPDATE`s and **no reads**: `version = version + 1`
  /// is done in SQL, the [NoteDao.setNotePositions] shape, rather than
  /// reading each row to compute it — `query_count_test` guards that a
  /// reorder never issues a `SELECT`. A row already at its position is left
  /// alone (`sort_order != ?`), so a drag that moves one row stamps one row
  /// and the others keep their `version` and HLC; a tombstone or an unknown
  /// id updates nothing (`is_deleted = 0`), the outcome an existence check
  /// would have produced. **Dense values matter**: [getAll] tie-breaks on
  /// `id`, so gaps or duplicates would let rows shuffle on the next load,
  /// which reads as the drag not having stuck. Only the rows it moved are
  /// queued, under the drag's one HLC.
  Future<void> reorder(List<String> idsInOrder) async {
    if (idsInOrder.isEmpty) return;
    final now = DateTime.now();

    await transaction(() async {
      final stamp = db.newStamp();
      final moved = <String>[];
      for (var i = 0; i < idsInOrder.length; i++) {
        final changed = await customUpdate(
          'UPDATE calendar_filter_presets SET sort_order = ?, updated_at = ?, '
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
          updates: {calendarFilterPresets},
        );
        if (changed > 0) moved.add(idsInOrder[i]);
      }
      await db.enqueueMany(calendarFilterPresets, moved, stamp.hlc);
    });
  }

  /// Inserts presets while preserving externally-provided audit fields, the
  /// [EventTemplateDao.importAll] convention: `createdAt`/`updatedAt` come
  /// from the caller, identity is stamped **fresh**. A backup is not a sync
  /// channel, so a restored preset is this device's own live row, never a
  /// replayed one. One batched transaction and one commit for the whole
  /// archive, each row queued in it as any new local row is.
  Future<void> importAll(List<CalendarFilterPresetsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            calendarFilterPresets,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, calendarFilterPresets, entry.id.value, stamp.hlc);
        }
      });
    });
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CalendarFilterPresetRow>> getByIdsIncludingDeleted(
    List<String> ids,
  ) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(calendarFilterPresets)..where((t) => t.id.isIn(ids))).get();
  }

  /// Merges one remote preset on the contract of [CrdtMerge.mergeRemoteRow].
  /// The filter blob is stored verbatim, so a field a newer build wrote
  /// survives. A tombstone writes the stamps, the deletion and the owner and
  /// keeps the rest; the 50-preset cap is the service's, not a merge's.
  Future<MergeOutcome> mergeRemotePreset(
    CalendarFilterPresetRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await _byId(remote.id);
      return CrdtMerge.mergeRemoteRow(
        db,
        table: calendarFilterPresets,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(calendarFilterPresets).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              calendarFilterPresets,
            )..where((t) => t.id.equals(remote.id))).write(
              CalendarFilterPresetsCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            await update(calendarFilterPresets).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// The **hard** wipe, tombstones included. Used by the import path, where no
  /// parent survives to merge against and a tombstone would strand a row no
  /// surface can reach.
  Future<void> deleteAll() {
    return delete(calendarFilterPresets).go();
  }

  Future<CalendarFilterPresetRow?> _byId(String id) {
    return (select(
      calendarFilterPresets,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
