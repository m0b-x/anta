import 'package:drift/drift.dart';

import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/event_occurrences_table.dart';

part 'event_occurrence_dao.g.dart';

/// All CRDT stamping for `calendar_event_occurrences` lives here, never in the
/// service: a `CrdtWrite` stamp, the row queued under [dayRowKey] in the same
/// transaction (**v43**), and read-then-write `version + 1`, the [NoteDao]
/// idiom shared with [EventAbsenceDao].
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
  /// `created_at` intact instead of quietly updating an invisible one. A live
  /// day re-saved with the same text writes nothing.
  Future<void> upsert(EventOccurrenceDescriptionsCompanion entry) {
    return transaction(() async {
      final eventId = entry.eventId.value;
      final day = entry.day.value;
      final existing = await _byKey(eventId, day);

      if (existing == null) {
        final stamp = await db.stampLocal(
          eventOccurrenceDescriptions,
          dayRowKey(eventId, day),
        );
        await into(eventOccurrenceDescriptions).insert(
          entry.copyWith(
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: const Value(1),
          ),
        );
        return;
      }

      if (!existing.isDeleted && db.changesNothing(existing, entry)) return;
      final stamp = await db.stampLocal(
        eventOccurrenceDescriptions,
        dayRowKey(eventId, day),
      );
      await (update(
        eventOccurrenceDescriptions,
      )..where((o) => o.eventId.equals(eventId) & o.day.equals(day))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
        ),
      );
    });
  }

  /// "Reset this day" — returns one day to the event's template, the
  /// [EventAbsenceDao.clearMark] shape: the row survives as a tombstone so the
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
      final stamp = await db.stampLocal(
        eventOccurrenceDescriptions,
        dayRowKey(eventId, day),
        op: OutboxOp.tombstone,
      );
      await (update(
        eventOccurrenceDescriptions,
      )..where((o) => o.eventId.equals(eventId) & o.day.equals(day))).write(
        EventOccurrenceDescriptionsCompanion(
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

  /// Cascade for a deleted event, matching the parent: since v28 deleting one
  /// event **tombstones** it, so its per-day descriptions tombstone too and the
  /// whole act keeps one merge order.
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
        'UPDATE calendar_event_occurrences SET is_deleted = 1, '
        'deleted_at = ?, updated_at = ?, hlc_timestamp = ?, device_id = ?, '
        'version = version + 1 '
        'WHERE event_id = ? AND is_deleted = 0 RETURNING day',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(shared.hlc),
          Variable<String>(shared.deviceId),
          Variable<String>(eventId),
        ],
        updates: {eventOccurrenceDescriptions},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(
        eventOccurrenceDescriptions,
        [
          for (final row in tombstoned)
            dayRowKey(eventId, row.read<DateTime>('day')),
        ],
        shared.hlc,
        op: OutboxOp.tombstone,
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
      'UPDATE calendar_event_occurrences SET is_deleted = 1, '
      'deleted_at = ?, updated_at = ?, hlc_timestamp = ?, device_id = ?, '
      'version = version + 1 '
      'WHERE is_deleted = 0 AND ${owned.sql} RETURNING event_id, day',
      variables: [
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        ...owned.variables,
      ],
      updates: {eventOccurrenceDescriptions},
      updateKind: UpdateKind.update,
    );
    await db.enqueueMany(
      eventOccurrenceDescriptions,
      [
        for (final row in tombstoned)
          dayRowKey(row.read<String>('event_id'), row.read<DateTime>('day')),
      ],
      stamp.hlc,
      op: OutboxOp.tombstone,
    );
  }

  /// Inserts an override while preserving externally-provided audit fields, the
  /// [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored day is this device's own live row, never a replayed one.
  /// Takes the whole archive at once (**5.1**): one batched transaction and one
  /// commit, where this was a separate awaited insert — and so a separate WAL
  /// commit — per restored day. See [CalendarEventDao.importAll] for why
  /// `insertOrReplace` is the safe mode here. Each day is queued in the same
  /// batch, as any new local row is.
  Future<void> importAll(List<EventOccurrenceDescriptionsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            eventOccurrenceDescriptions,
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
            eventOccurrenceDescriptions,
            dayRowKey(entry.eventId.value, entry.day.value),
            stamp.hlc,
          );
        }
      });
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

  /// The rows under [keys], tombstones included: the sync push sends the
  /// tombstone a delete queued. Narrowed by event id on the primary key's
  /// prefix, then matched through [dayRowKey] — the outbox's own key — so a
  /// caller's milliseconds cannot miss the stored second.
  Future<List<EventOccurrenceRow>> getByDayKeysIncludingDeleted(
    List<({String eventId, DateTime day})> keys,
  ) async {
    if (keys.isEmpty) return const [];
    final wanted = {for (final k in keys) dayRowKey(k.eventId, k.day)};
    final rows = await (select(
      eventOccurrenceDescriptions,
    )..where((o) => o.eventId.isIn({for (final k in keys) k.eventId}))).get();
    return [
      for (final row in rows)
        if (wanted.contains(dayRowKey(row.eventId, row.day))) row,
    ];
  }

  /// Merges one remote description, keyed [dayRowKey], on the contract of
  /// [CrdtMerge.mergeRemoteRow]. Stored as received even under an event
  /// tombstoned here, the parent's tombstone being its own row. A tombstone
  /// writes the stamps, the deletion and the owner and keeps the rest.
  Future<MergeOutcome> mergeRemoteOccurrence(
    EventOccurrenceRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await _byKey(remote.eventId, remote.day);
      return CrdtMerge.mergeRemoteRow(
        db,
        table: eventOccurrenceDescriptions,
        rowKey: dayRowKey(remote.eventId, remote.day),
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(eventOccurrenceDescriptions).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(eventOccurrenceDescriptions)..where(
                  (o) =>
                      o.eventId.equals(remote.eventId) &
                      o.day.equals(remote.day),
                ))
                .write(
                  EventOccurrenceDescriptionsCompanion(
                    hlcTimestamp: Value(remote.hlcTimestamp),
                    deviceId: Value(remote.deviceId),
                    version: Value(remote.version),
                    isDeleted: const Value(true),
                    deletedAt: Value(remote.deletedAt),
                    ownerId: Value(remote.ownerId),
                  ),
                );
          } else {
            await update(eventOccurrenceDescriptions).replace(remote);
          }
          return applied;
        },
      );
    });
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
