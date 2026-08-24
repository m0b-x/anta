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
    return (select(
      eventAbsences,
    )..where((a) => a.isDeleted.equals(false))).get();
  }

  /// The same live rows as [getActive], narrowed to the key pair — everything
  /// [EventPresenceService] keeps in memory, and nothing else.
  ///
  /// Kept separate rather than narrowing [getActive] because `exportData`
  /// still needs `created_at` / `updated_at`; a backup is not the hot path.
  ///
  /// This projection is exactly `idx_calendar_event_absences_active`, so the
  /// read is answered from the index and never visits the table — which is
  /// what stops years of uncollected tombstones from being scanned at every
  /// startup and after every event delete.
  ///
  /// The predicate is a raw literal, not `isDeleted.equals(false)`: Drift
  /// binds that as `is_deleted = ?`, and whether SQLite can prove a bound
  /// parameter implies the partial index's `WHERE` clause differs by version
  /// (3.53 can, 3.50 falls back to a scan). `is_deleted = 0` matches the index
  /// definition syntactically on every version, including the one shipped to
  /// Android.
  Future<List<({String eventId, DateTime day})>> getActiveKeys() async {
    final query = selectOnly(eventAbsences)
      ..addColumns([eventAbsences.eventId, eventAbsences.day])
      ..where(const CustomExpression<bool>('is_deleted = 0'));
    final rows = await query.get();
    return [
      for (final row in rows)
        (
          eventId: row.read(eventAbsences.eventId)!,
          day: row.read(eventAbsences.day)!,
        ),
    ];
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

      await (update(
        eventAbsences,
      )..where((a) => a.eventId.equals(eventId) & a.day.equals(day))).write(
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
      await (update(
        eventAbsences,
      )..where((a) => a.eventId.equals(eventId) & a.day.equals(day))).write(
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
  /// Takes the whole archive at once (**5.1**): one batched transaction and one
  /// commit, where this was a separate awaited insert — and so a separate WAL
  /// commit — per restored mark. See [CalendarEventDao.importAll] for why
  /// `insertOrReplace` is the safe mode here.
  Future<void> importAll(List<EventAbsencesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(
          eventAbsences,
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

  /// Cascade for a deleted event, matching the parent: since v27 deleting one
  /// event **tombstones** it, so its marks tombstone too and the pair merges as
  /// one act.
  ///
  /// One statement for an unbounded row count — `version + 1` in SQL, one
  /// shared HLC for the batch, the [FolderDao.softDeleteFolderWithDescendants]
  /// idiom. Already-tombstoned rows are skipped, so a repeat cannot churn
  /// versions. `updated_at` / `deleted_at` bind as `Variable<DateTime>`
  /// because Drift stores unix seconds.
  Future<void> tombstoneForEvent(String eventId) async {
    final now = DateTime.now();
    await customUpdate(
      'UPDATE calendar_event_absences SET is_deleted = 1, deleted_at = ?, '
      'updated_at = ?, hlc_timestamp = ?, device_id = ?, '
      'version = version + 1 '
      'WHERE event_id = ? AND is_deleted = 0',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(db.generateHlc()),
        Variable<String>(db.deviceId),
        Variable<String>(eventId),
      ],
      updates: {eventAbsences},
    );
  }

  /// The **hard** cascade, tombstones included — kept for the wipe paths, where
  /// no parent survives to merge against and a tombstoned child would strand an
  /// orphan in every export. Deleting a single event goes through
  /// [tombstoneForEvent] instead, so this is currently caller-less, exactly as
  /// [CalendarEventDao.deleteById] is.
  Future<void> deleteForEvent(String eventId) {
    return (delete(
      eventAbsences,
    )..where((a) => a.eventId.equals(eventId))).go();
  }

  Future<void> deleteAll() {
    return delete(eventAbsences).go();
  }

  Future<EventAbsenceRow?> _byKey(String eventId, DateTime day) {
    return (select(eventAbsences)
          ..where((a) => a.eventId.equals(eventId) & a.day.equals(day)))
        .getSingleOrNull();
  }
}
