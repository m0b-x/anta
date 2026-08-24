import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/event_occurrences_table.dart';

part 'event_occurrence_dao.g.dart';

/// All CRDT stamping for `calendar_event_occurrences` lives here, never in the
/// service: `db.generateHlc()`, `db.deviceId` and read-then-write
/// `version + 1`, the [NoteDao] idiom shared with [EventAbsenceDao].
@DriftAccessor(tables: [EventOccurrenceDescriptions])
class EventOccurrenceDao extends DatabaseAccessor<AppDatabase>
    with _$EventOccurrenceDaoMixin {
  EventOccurrenceDao(super.db);

  /// Live overrides only. Tombstones stay below the service's waterline — a day
  /// reset to the template exists for a future merge, not for anything the app
  /// renders. The table holds only user deltas, so this stays small enough to
  /// keep entirely in memory for O(1) synchronous lookups.
  Future<List<EventOccurrenceRow>> getActive() {
    return (select(
      eventOccurrenceDescriptions,
    )..where((o) => o.isDeleted.equals(false))).get();
  }

  /// Materializes one day's description, preserving `createdAt` on an existing
  /// row and stamping merge identity on both branches.
  ///
  /// Read-then-write rather than `insertOnConflictUpdate` (which would
  /// overwrite `createdAt` with whatever the caller's companion holds) and
  /// rather than a blind UPDATE-then-INSERT (which cannot compute
  /// `version + 1`), the [CalendarEventDao.upsert] shape: a miss inserts a
  /// fresh `version 1` row, a hit bumps the version and re-stamps HLC/device.
  ///
  /// The update branch clears the tombstone flags **explicitly**, so
  /// re-describing a day that was reset resurrects its original row with
  /// `created_at` intact instead of quietly updating an invisible one.
  Future<void> upsert(EventOccurrenceDescriptionsCompanion entry) {
    return transaction(() async {
      final eventId = entry.eventId.value;
      final day = entry.day.value;
      final existing = await _byKey(eventId, day);
      final hlc = db.generateHlc();

      if (existing == null) {
        await into(eventOccurrenceDescriptions).insert(
          entry.copyWith(
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: const Value(1),
          ),
        );
        return;
      }

      await (update(
        eventOccurrenceDescriptions,
      )..where((o) => o.eventId.equals(eventId) & o.day.equals(day))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          hlcTimestamp: Value(hlc),
          deviceId: Value(db.deviceId),
          version: Value(existing.version + 1),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
        ),
      );
    });
  }

  /// "Reset this day" — returns one day to the event's template, the
  /// [EventAbsenceDao.unmark] shape: the row survives as a tombstone so the
  /// reset carries an order once devices merge, and [getActive]'s filter is
  /// what makes the override disappear. Writing `''` would mean a deliberately
  /// blanked day instead, which is why this never does. A missing or
  /// already-tombstoned row is a no-op, so a repeated reset cannot churn the
  /// version.
  Future<void> tombstone(String eventId, DateTime day) {
    return transaction(() async {
      final existing = await _byKey(eventId, day);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      await (update(
        eventOccurrenceDescriptions,
      )..where((o) => o.eventId.equals(eventId) & o.day.equals(day))).write(
        EventOccurrenceDescriptionsCompanion(
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

  /// Cascade for a deleted event, matching the parent: since v28 deleting one
  /// event **tombstones** it, so its per-day descriptions tombstone too and the
  /// whole act keeps one merge order.
  ///
  /// One statement for an unbounded row count — `version + 1` in SQL, one
  /// shared HLC for the batch, the [FolderDao.softDeleteFolderWithDescendants]
  /// idiom. Already-tombstoned rows are skipped, so a repeat cannot churn
  /// versions. `updated_at` / `deleted_at` bind as `Variable<DateTime>` because
  /// Drift stores unix seconds.
  Future<void> tombstoneForEvent(String eventId) async {
    final now = DateTime.now();
    await customUpdate(
      'UPDATE calendar_event_occurrences SET is_deleted = 1, deleted_at = ?, '
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
      updates: {eventOccurrenceDescriptions},
    );
  }

  /// Inserts an override while preserving externally-provided audit fields, the
  /// [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored day is this device's own live row, never a replayed one.
  /// Takes the whole archive at once (**5.1**): one batched transaction and one
  /// commit, where this was a separate awaited insert — and so a separate WAL
  /// commit — per restored day. See [CalendarEventDao.importAll] for why
  /// `insertOrReplace` is the safe mode here.
  Future<void> importAll(List<EventOccurrenceDescriptionsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(
          eventOccurrenceDescriptions,
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

  /// The **hard** single-day drop. Superseded by [tombstone] for "reset this
  /// day", which is the act that has to carry an order into a merge, so this is
  /// currently caller-less — exactly as [CalendarEventDao.deleteById] is.
  Future<void> deleteFor(String eventId, DateTime day) {
    return (delete(
      eventOccurrenceDescriptions,
    )..where((o) => o.eventId.equals(eventId) & o.day.equals(day))).go();
  }

  /// The **hard** cascade, tombstones included — kept for the wipe paths, where
  /// no parent survives to merge against and a tombstoned child would strand an
  /// orphan in every export. Deleting a single event goes through
  /// [tombstoneForEvent] instead.
  Future<void> deleteForEvent(String eventId) {
    return (delete(
      eventOccurrenceDescriptions,
    )..where((o) => o.eventId.equals(eventId))).go();
  }

  Future<void> deleteAll() {
    return delete(eventOccurrenceDescriptions).go();
  }

  /// Deliberately unfiltered: [upsert] has to see a tombstone to resurrect it,
  /// and [tombstone] has to see one to stay a no-op.
  Future<EventOccurrenceRow?> _byKey(String eventId, DateTime day) {
    return (select(eventOccurrenceDescriptions)
          ..where((o) => o.eventId.equals(eventId) & o.day.equals(day)))
        .getSingleOrNull();
  }
}
