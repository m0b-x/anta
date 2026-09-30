import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/calendar_filter_presets_table.dart';

part 'filter_preset_dao.g.dart';

/// All CRDT stamping for `calendar_filter_presets` lives here, never in the
/// service: `db.generateHlc()`, `db.deviceId` and read-then-write
/// `version + 1`, the [EventTemplateDao] idiom.
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
  /// collide.
  Future<void> upsertPreset(CalendarFilterPresetsCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);
      final now = DateTime.now();
      final hlc = db.generateHlc();

      if (existing == null) {
        await into(calendarFilterPresets).insert(
          entry.copyWith(
            createdAt: entry.createdAt.present ? entry.createdAt : Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
        return;
      }

      await (update(
        calendarFilterPresets,
      )..where((t) => t.id.equals(id))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          updatedAt: Value(now),
          hlcTimestamp: Value(hlc),
          deviceId: Value(db.deviceId),
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
      await (update(
        calendarFilterPresets,
      )..where((t) => t.id.equals(id))).write(
        CalendarFilterPresetsCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(db.generateHlc()),
          deviceId: Value(db.deviceId),
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
  /// which reads as the drag not having stuck.
  Future<void> reorder(List<String> idsInOrder) async {
    if (idsInOrder.isEmpty) return;
    final now = DateTime.now();
    final hlc = db.generateHlc();

    await transaction(() async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await customUpdate(
          'UPDATE calendar_filter_presets SET sort_order = ?, updated_at = ?, '
          'hlc_timestamp = ?, device_id = ?, version = version + 1 '
          'WHERE id = ? AND is_deleted = 0 AND sort_order != ?',
          variables: [
            Variable<int>(i),
            Variable<DateTime>(now),
            Variable<String>(hlc),
            Variable<String>(db.deviceId),
            Variable<String>(idsInOrder[i]),
            Variable<int>(i),
          ],
          updates: {calendarFilterPresets},
        );
      }
    });
  }

  /// Inserts presets while preserving externally-provided audit fields, the
  /// [EventTemplateDao.importAll] convention: `createdAt`/`updatedAt` come
  /// from the caller, identity is stamped **fresh**. A backup is not a sync
  /// channel, so a restored preset is this device's own live row, never a
  /// replayed one. One batched transaction and one commit for the whole
  /// archive.
  Future<void> importAll(List<CalendarFilterPresetsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(
          calendarFilterPresets,
          entry.copyWith(
            hlcTimestamp: Value(db.generateHlc()),
            deviceId: Value(db.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
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
