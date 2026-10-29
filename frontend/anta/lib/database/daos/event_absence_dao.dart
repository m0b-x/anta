import 'package:drift/drift.dart';

import '../../constants/event_presence.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/event_absences_table.dart';

part 'event_absence_dao.g.dart';

/// All CRDT stamping for `calendar_event_absences` lives here, never in the
/// service: a `CrdtWrite` stamp, the row queued under [dayRowKey] in the same
/// transaction (**v43**), and read-then-write `version + 1`, the [NoteDao]
/// idiom.
@DriftAccessor(tables: [EventAbsences])
class EventAbsenceDao extends DatabaseAccessor<AppDatabase>
    with _$EventAbsenceDaoMixin {
  EventAbsenceDao(super.db);

  /// Live marks only, whatever their status. Tombstones stay below the
  /// service's waterline — they exist for a future merge, not for anything the
  /// app renders. The table
  /// holds only user deltas, so this stays small enough to keep entirely in
  /// memory for O(1) synchronous lookups.
  Future<List<EventAbsenceRow>> getActive() {
    return (select(
      eventAbsences,
    )..where((a) => a.isDeleted.equals(false))).get();
  }

  /// The same live rows as [getActive], narrowed to key + status — everything
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
  Future<List<({String eventId, DateTime day, PresenceStatus status})>>
  getActiveKeys() async {
    final query = selectOnly(eventAbsences)
      ..addColumns([
        eventAbsences.eventId,
        eventAbsences.day,
        eventAbsences.status,
      ])
      ..where(const CustomExpression<bool>('is_deleted = 0'));
    final rows = await query.get();
    return [
      for (final row in rows)
        (
          eventId: row.read(eventAbsences.eventId)!,
          day: row.read(eventAbsences.day)!,
          status: PresenceStatus.fromName(row.read(eventAbsences.status)),
        ),
    ];
  }

  /// Records an explicit [status] for one occurrence (**v37**).
  ///
  /// Three cases in one transaction: no row inserts a fresh `version 1` mark;
  /// a tombstoned row — or a live one carrying the *other* status — is written
  /// in place with `created_at` untouched, so a day keeps the date it was
  /// first marked; a live row already carrying [status] is a complete no-op,
  /// with no version churn for a repeated tap.
  ///
  /// Replaces v26's `markMissed`: since a `present` row is now a statement of
  /// its own, flipping a day writes the opposite status rather than
  /// tombstoning. [clearMark] is the only path that tombstones.
  Future<void> setStatus(String eventId, DateTime day, PresenceStatus status) {
    return transaction(() async {
      final existing = await _byKey(eventId, day);
      if (existing != null &&
          !existing.isDeleted &&
          PresenceStatus.fromName(existing.status) == status) {
        return;
      }

      final now = DateTime.now();
      final stamp = await db.stampLocal(eventAbsences, dayRowKey(eventId, day));
      if (existing == null) {
        await into(eventAbsences).insert(
          EventAbsencesCompanion(
            eventId: Value(eventId),
            day: Value(day),
            status: Value(status.name),
            createdAt: Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
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
          status: Value(status.name),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Drops the explicit answer for one occurrence, the
  /// [NoteDao.softDeleteNote] shape: the row survives as a tombstone so the
  /// toggle carries an order once devices merge. The day falls back to the
  /// event's own default. A missing or already-tombstoned row is a no-op.
  Future<void> clearMark(String eventId, DateTime day) {
    return transaction(() async {
      final existing = await _byKey(eventId, day);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        eventAbsences,
        dayRowKey(eventId, day),
        op: OutboxOp.tombstone,
      );
      await (update(
        eventAbsences,
      )..where((a) => a.eventId.equals(eventId) & a.day.equals(day))).write(
        EventAbsencesCompanion(
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

  /// Inserts a mark while preserving externally-provided audit fields, the
  /// [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored mark is this device's own live row, never a replayed one.
  /// Takes the whole archive at once (**5.1**): one batched transaction and one
  /// commit, where this was a separate awaited insert — and so a separate WAL
  /// commit — per restored mark. See [CalendarEventDao.importAll] for why
  /// `insertOrReplace` is the safe mode here. Each mark is queued in the same
  /// batch, as any new local row is.
  Future<void> importAll(List<EventAbsencesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            eventAbsences,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(
            b,
            eventAbsences,
            dayRowKey(entry.eventId.value, entry.day.value),
            stamp.hlc,
          );
        }
      });
    });
  }

  /// Cascade for a deleted event, matching the parent: since v27 deleting one
  /// event **tombstones** it, so its marks tombstone too and the pair merges as
  /// one act.
  ///
  /// One statement for an unbounded row count — `version + 1` in SQL, one
  /// shared HLC for the batch, the [FolderDao.softDeleteFolderWithDescendants]
  /// idiom — and `RETURNING day` to queue exactly the rows it tombstoned.
  /// Already-tombstoned rows are skipped, so a repeat cannot churn versions.
  /// `updated_at` / `deleted_at` bind as `Variable<DateTime>` because Drift
  /// stores unix seconds. [stamp] is the event delete's own, from
  /// [CalendarEventDao.tombstoneEventCascade].
  Future<void> tombstoneForEvent(String eventId, {CrdtStamp? stamp}) {
    return transaction(() async {
      final shared = stamp ?? db.newStamp();
      final now = DateTime.now();
      final tombstoned = await customWriteReturning(
        'UPDATE calendar_event_absences SET is_deleted = 1, deleted_at = ?, '
        'updated_at = ?, hlc_timestamp = ?, device_id = ?, '
        'version = version + 1 '
        'WHERE event_id = ? AND is_deleted = 0 RETURNING day',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(shared.hlc),
          Variable<String>(shared.deviceId),
          Variable<String>(eventId),
        ],
        updates: {eventAbsences},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(
        eventAbsences,
        [
          for (final row in tombstoned)
            dayRowKey(eventId, row.read<DateTime>('day')),
        ],
        shared.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }

  /// Puts [marks] back under the restore's shared [stamp], the
  /// [tombstoneForEvent] inverse for [CalendarEventDao.restoreEventCascade]:
  /// a tombstoned row is written in place with its `created_at` intact — the
  /// day keeps the date it was first marked — and a row the cascade's own
  /// delete has since removed from the table is re-inserted at `version 1`,
  /// the [setStatus] cases without the no-op branch, since a restore is
  /// exactly the write that must move the stamp.
  Future<void> restoreForEvent(
    String eventId,
    Map<DateTime, PresenceStatus> marks, {
    required CrdtStamp stamp,
  }) {
    if (marks.isEmpty) return Future.value();
    return transaction(() async {
      // Keyed on the whole second the column stores, never on the read-back
      // `DateTime`: drift hands that back in local time, so a UTC date-only
      // key would never match it in Dart ([EventSkipDao.applySkipDiff]).
      final existing = {
        for (final row in await (select(eventAbsences)..where(
              (a) => a.eventId.equals(eventId) & a.day.isIn(marks.keys),
            ))
            .get())
          dayMs(row.day): row,
      };
      final now = DateTime.now();
      await batch((b) {
        for (final mark in marks.entries) {
          final row = existing[dayMs(mark.key)];
          if (row == null) {
            b.insert(
              eventAbsences,
              EventAbsencesCompanion(
                eventId: Value(eventId),
                day: Value(mark.key),
                status: Value(mark.value.name),
                createdAt: Value(now),
                updatedAt: Value(now),
                hlcTimestamp: Value(stamp.hlc),
                deviceId: Value(stamp.deviceId),
                version: const Value(1),
                isDeleted: const Value(false),
              ),
            );
            continue;
          }
          b.update(
            eventAbsences,
            EventAbsencesCompanion(
              status: Value(mark.value.name),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
              updatedAt: Value(now),
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: Value(row.version + 1),
            ),
            where: (a) => a.eventId.equals(eventId) & a.day.equals(mark.key),
          );
        }
      });
      await db.enqueueMany(
        eventAbsences,
        [for (final day in marks.keys) dayRowKey(eventId, day)],
        stamp.hlc,
      );
    });
  }

  /// The [tombstoneForEvent] statement over every event, for
  /// [CalendarEventDao.tombstoneAll]: only the rows [ownedRowsWhere] allows,
  /// under the wipe's [stamp].
  Future<void> tombstoneAll({
    required CrdtStamp stamp,
    required String? ownerUid,
  }) async {
    final owned = ownedRowsWhere(ownerUid);
    final now = DateTime.now();
    final tombstoned = await customWriteReturning(
      'UPDATE calendar_event_absences SET is_deleted = 1, deleted_at = ?, '
      'updated_at = ?, hlc_timestamp = ?, device_id = ?, '
      'version = version + 1 '
      'WHERE is_deleted = 0 AND ${owned.sql} RETURNING event_id, day',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        ...owned.variables,
      ],
      updates: {eventAbsences},
      updateKind: UpdateKind.update,
    );
    await db.enqueueMany(
      eventAbsences,
      [
        for (final row in tombstoned)
          dayRowKey(row.read<String>('event_id'), row.read<DateTime>('day')),
      ],
      stamp.hlc,
      op: OutboxOp.tombstone,
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

  /// The rows under [keys], tombstones included: the sync push sends the
  /// tombstone a delete queued. Narrowed by event id and day on the primary
  /// key — a recurring event's years of marks stay out of the read — then
  /// matched through [dayRowKey], the outbox's own key, so only the asked
  /// pairs come back and a caller's milliseconds cannot miss the stored
  /// second.
  Future<List<EventAbsenceRow>> getByDayKeysIncludingDeleted(
    List<({String eventId, DateTime day})> keys,
  ) async {
    if (keys.isEmpty) return const [];
    final wanted = {for (final k in keys) dayRowKey(k.eventId, k.day)};
    final rows =
        await (select(eventAbsences)..where(
              (a) =>
                  a.eventId.isIn({for (final k in keys) k.eventId}) &
                  a.day.isIn({for (final k in keys) k.day}),
            ))
            .get();
    return [
      for (final row in rows)
        if (wanted.contains(dayRowKey(row.eventId, row.day))) row,
    ];
  }

  /// Merges one remote presence mark, keyed [dayRowKey], on the contract of
  /// [CrdtMerge.mergeRemoteRow], its `status` as received. Stored even under
  /// an event tombstoned here, the parent's tombstone being its own row. A
  /// tombstone writes the stamps, the deletion and the owner and keeps the
  /// rest.
  Future<MergeOutcome> mergeRemoteAbsence(
    EventAbsenceRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await _byKey(remote.eventId, remote.day);
      return CrdtMerge.mergeRemoteRow(
        db,
        table: eventAbsences,
        rowKey: dayRowKey(remote.eventId, remote.day),
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(eventAbsences).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(eventAbsences)..where(
                  (a) =>
                      a.eventId.equals(remote.eventId) &
                      a.day.equals(remote.day),
                ))
                .write(
                  EventAbsencesCompanion(
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
            await update(eventAbsences).replace(remote);
          }
          return applied;
        },
      );
    });
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
