import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/event_absences_table.dart';

part 'event_absence_dao.g.dart';

/// All CRDT stamping for `calendar_event_absences` lives here, never in the
/// service: `db.generateHlc()`, `db.deviceId` and read-then-write
/// `version + 1`, the [NoteDao] idiom.
@DriftAccessor(tables: [EventAbsences])
class EventAbsenceDao extends DatabaseAccessor<AppDatabase>
    with _$EventAbsenceDaoMixin {
  EventAbsenceDao(super.db);

  /// Live marks only. Tombstones stay below the service's waterline — they
  /// exist for a future merge, not for anything the app renders. The table
  /// holds only user deltas, so this stays small enough to keep entirely in
  /// memory for O(1) synchronous lookups.
  Future<List<EventAbsenceRow>> getActive() {
    return (select(eventAbsences)..where((a) => a.isDeleted.equals(false)))
        .get();
  }

  /// Marks one occurrence missed.
  ///
  /// Three cases in one transaction: no row inserts a fresh `version 1` mark;
  /// a tombstoned row is **resurrected** with `created_at` untouched, so a day
  /// keeps the date it was first marked; an already-live row is a complete
  /// no-op, with no version churn for a repeated tap.
  Future<void> markMissed(String eventId, DateTime day) {
    return transaction(() async {
      final existing = await _byKey(eventId, day);
      if (existing != null && !existing.isDeleted) return;

      final now = DateTime.now();
      final hlc = db.generateHlc();
      if (existing == null) {
        await into(eventAbsences).insert(
          EventAbsencesCompanion(
            eventId: Value(eventId),
            day: Value(day),
            createdAt: Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
          ),
        );
        return;
      }

      await (update(eventAbsences)..where(
            (a) => a.eventId.equals(eventId) & a.day.equals(day),
          ))
          .write(
            EventAbsencesCompanion(
              isDeleted: const Value(false),
              deletedAt: const Value(null),
              updatedAt: Value(now),
              hlcTimestamp: Value(hlc),
              deviceId: Value(db.deviceId),
              version: Value(existing.version + 1),
            ),
          );
    });
  }

  /// Un-marks one occurrence, the [NoteDao.softDeleteNote] shape: the row
  /// survives as a tombstone so the toggle carries an order once devices
  /// merge. A missing or already-tombstoned row is a no-op.
  Future<void> unmark(String eventId, DateTime day) {
    return transaction(() async {
      final existing = await _byKey(eventId, day);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      await (update(eventAbsences)..where(
            (a) => a.eventId.equals(eventId) & a.day.equals(day),
          ))
          .write(
            EventAbsencesCompanion(
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

  /// Inserts a mark while preserving externally-provided audit fields, the
  /// [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored mark is this device's own live row, never a replayed one.
  Future<void> importAbsence(EventAbsencesCompanion entry) {
    return into(eventAbsences).insert(
      entry.copyWith(
        hlcTimestamp: Value(db.generateHlc()),
        deviceId: Value(db.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
        deletedAt: const Value(null),
      ),
    );
  }

  /// Cascade for a deleted event — a **hard** delete, tombstones included.
  /// The parent event's own delete is hard today, and tombstoned children of a
  /// hard-deleted parent would strand orphans in every export.
  Future<void> deleteForEvent(String eventId) {
    return (delete(
      eventAbsences,
    )..where((a) => a.eventId.equals(eventId))).go();
  }

  Future<void> deleteAll() {
    return delete(eventAbsences).go();
  }

  Future<EventAbsenceRow?> _byKey(String eventId, DateTime day) {
    return (select(eventAbsences)..where(
          (a) => a.eventId.equals(eventId) & a.day.equals(day),
        ))
        .getSingleOrNull();
  }
}
