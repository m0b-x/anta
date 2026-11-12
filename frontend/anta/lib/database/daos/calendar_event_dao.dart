import 'package:drift/drift.dart';

import '../../constants/event_presence.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/calendar_events_table.dart';
import 'sync_dao.dart';

part 'calendar_event_dao.g.dart';

/// All CRDT stamping for `calendar_events` lives here, never in the service:
/// a `CrdtWrite` stamp, the row queued in the same transaction (**v43**), and
/// read-then-write `version + 1`, the [NoteDao] idiom already followed by
/// [EventAbsenceDao]. Nothing above this class — model, service, blocs,
/// backup — sees a CRDT field, a tombstone or the outbox.
@DriftAccessor(tables: [CalendarEvents])
class CalendarEventDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarEventDaoMixin {
  CalendarEventDao(super.db);

  /// Live events, in start-date order. The single read path for the whole
  /// feature, which is why the month grid, day panel, agenda, timeline, `.ics`
  /// export and the backup snapshot all inherit the tombstone filter for free.
  ///
  /// `is_deleted = 0` restates `idx_calendar_events_start_date`'s partial
  /// expression exactly. Rewriting the predicate costs the index, and with it
  /// the ordering — SQLite falls back to a scan plus a temp B-tree with no
  /// visible symptom until a user has thousands of events.
  ///
  /// It is a **literal**, not `isDeleted.equals(false)`: the latter emits a
  /// bound parameter, and whether SQLite proves `is_deleted = ?` implies the
  /// index's own `WHERE is_deleted = 0` varies by SQLite version — newer hosts
  /// do, the version shipping to Android does not.
  Future<List<CalendarEventRow>> getAll() {
    return (select(calendarEvents)
          ..where((e) => const CustomExpression<bool>('is_deleted = 0'))
          ..orderBy([(e) => OrderingTerm.asc(e.startDate)]))
        .get();
  }

  /// Upsert that preserves `createdAt` on existing rows and stamps merge
  /// identity on both branches.
  ///
  /// Read-then-write rather than `insertOnConflictUpdate` (which would
  /// overwrite `createdAt` with whatever the caller's companion holds) and
  /// rather than a blind UPDATE-then-INSERT (which cannot compute
  /// `version + 1`): a miss inserts a fresh `version 1` row, a hit bumps the
  /// version and re-stamps HLC/device. One extra SELECT per save, on a table
  /// that writes at human speed.
  ///
  /// The update branch clears the tombstone flags **explicitly**, so saving an
  /// event over its own tombstone resurrects it instead of quietly updating an
  /// invisible row. That is what keeps a backup import — which re-inserts the
  /// backed-up ids through here — from restoring events nothing can render.
  ///
  /// A save of a live event that changes nothing writes nothing.
  ///
  /// [shared] is supplied only by [restoreEventCascade], which writes five
  /// tables under one HLC; the row is queued either way, so it leaves on the
  /// next push whoever minted the stamp.
  Future<void> upsert(CalendarEventsCompanion entry, {CrdtStamp? shared}) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);

      if (existing == null) {
        final stamp = await _stampFor(id, shared);
        await into(calendarEvents).insert(
          entry.copyWith(
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: const Value(1),
          ),
        );
        return;
      }

      if (!existing.isDeleted && db.changesNothing(existing, entry)) return;
      final stamp = await _stampFor(id, shared);
      await (update(calendarEvents)..where((e) => e.id.equals(id))).write(
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

  /// Tombstones one event, the [NoteDao.softDeleteNote] shape: the row survives
  /// with `is_deleted = 1` and a bumped version so the delete carries an order
  /// once devices merge, and [getAll]'s filter is what makes it vanish from
  /// every surface. A missing or already-tombstoned row is a no-op, so a
  /// repeated delete cannot churn the version.
  ///
  /// Deleting an event from the app goes through [tombstoneEventCascade]; this
  /// is the event row alone.
  Future<void> softDeleteById(String id) {
    return transaction(() => _tombstone(id, db.newStamp()));
  }

  /// Deletes an event as the one act it is to the user: the event and every
  /// live absence mark, day description, skip and alert it owns tombstone
  /// under **one** HLC, each row queued, so the whole delete merges as one
  /// ordered change instead of five that another device could interleave.
  ///
  /// The children are tombstoned whether or not the event row was still live,
  /// as the service's cascade always did, so a child that outlived its parent
  /// is still cleaned up.
  Future<void> tombstoneEventCascade(String id) {
    return transaction(() async {
      final stamp = db.newStamp();
      await _tombstone(id, stamp);
      await db.eventAbsenceDao.tombstoneForEvent(id, stamp: stamp);
      await db.eventOccurrenceDao.tombstoneForEvent(id, stamp: stamp);
      await db.eventSkipDao.tombstoneForEvent(id, stamp: stamp);
      await db.eventAlertDao.tombstoneForEvent(id, stamp: stamp);
    });
  }

  /// Puts a cascaded delete back as the one act it is to the user — the Undo
  /// of A3's "Removed" snackbar — mirroring [tombstoneEventCascade]: the event
  /// row and the absence marks, day descriptions, skips and alerts it names
  /// are written under **one** fresh HLC, so the restore merges as one ordered
  /// change on every paired device instead of five another device could
  /// interleave. Without it only the event and its alerts came back and the
  /// other three row sets stayed tombstoned for good, here and everywhere.
  ///
  /// The children are keyed to what the caller captured, never to "every
  /// tombstone this event owns": a day the user had cleared, reset or
  /// un-skipped long before the delete must stay that way.
  Future<void> restoreEventCascade(
    CalendarEventsCompanion entry, {
    required Map<DateTime, PresenceStatus> marks,
    required Map<DateTime, String> descriptions,
    required Set<DateTime> skips,
    required List<EventAlertsCompanion> alerts,
  }) {
    final id = entry.id.value;
    return transaction(() async {
      final stamp = db.newStamp();
      // Queued here rather than inside [upsert]: the four children queue what
      // they wrote under this same HLC, and the event row is the fifth.
      await db.enqueue(calendarEvents, id, stamp.hlc);
      await upsert(entry, shared: stamp);
      await db.eventAbsenceDao.restoreForEvent(id, marks, stamp: stamp);
      await db.eventOccurrenceDao.restoreForEvent(
        id,
        descriptions,
        stamp: stamp,
      );
      await db.eventSkipDao.applySkipDiff(
        id,
        add: skips,
        remove: const {},
        stamp: stamp,
      );
      await db.eventAlertDao.replaceForEvent(id, alerts, stamp: stamp);
    });
  }

  /// "Delete all events" as a sync can carry it (D13): every live event,
  /// absence mark, day description, skip and alert this device may delete —
  /// see [ownedRowsWhere]; [ownerUid] is the bound account, null when unbound
  /// — tombstones under **one** HLC, each row queued. A hard wipe would leave
  /// nothing to propagate, and the other device would keep every event.
  ///
  /// Already-tombstoned rows are left alone, so a repeat writes nothing.
  /// A repeat still mints a stamp and runs the five statements, notifying
  /// every table's streams: a pre-check would cost a statement on every real
  /// wipe, and the repeat is a user retapping a button that is disabled once
  /// nothing is left.
  ///
  /// Returns the ids of the events it tombstoned, so the service hard deletes
  /// the `alert_registrations` of those alone — device-local, rebuilt by the
  /// next reconcile — and an event another account owns keeps its armed
  /// entries.
  Future<List<String>> tombstoneAll({required String? ownerUid}) {
    return transaction(() async {
      final stamp = db.newStamp();
      final owned = ownedRowsWhere(ownerUid);
      final now = DateTime.now();
      final tombstoned = await customWriteReturning(
        'UPDATE calendar_events SET is_deleted = 1, deleted_at = ?, '
        'updated_at = ?, hlc_timestamp = ?, device_id = ?, '
        'version = version + 1 '
        'WHERE is_deleted = 0 AND ${owned.sql} RETURNING id',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          ...owned.variables,
        ],
        updates: {calendarEvents},
        updateKind: UpdateKind.update,
      );
      final ids = [for (final row in tombstoned) row.read<String>('id')];
      await db.enqueueMany(
        calendarEvents,
        ids,
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
      await db.eventAbsenceDao.tombstoneAll(stamp: stamp, ownerUid: ownerUid);
      await db.eventOccurrenceDao.tombstoneAll(
        stamp: stamp,
        ownerUid: ownerUid,
      );
      await db.eventSkipDao.tombstoneAll(stamp: stamp, ownerUid: ownerUid);
      await db.eventAlertDao.tombstoneAll(stamp: stamp, ownerUid: ownerUid);
      return ids;
    });
  }

  /// The stamp [upsert] writes under: its own, queued by [CrdtWrite], or the
  /// cascade's, which [restoreEventCascade] has already queued.
  Future<CrdtStamp> _stampFor(String id, CrdtStamp? shared) =>
      shared == null ? db.stampLocal(calendarEvents, id) : Future.value(shared);

  Future<void> _tombstone(String id, CrdtStamp stamp) async {
    final existing = await _byId(id);
    if (existing == null || existing.isDeleted) return;

    final now = DateTime.now();
    await db.enqueue(calendarEvents, id, stamp.hlc, op: OutboxOp.tombstone);
    await (update(calendarEvents)..where((e) => e.id.equals(id))).write(
      CalendarEventsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      ),
    );
  }

  /// Live event count per category id, as one `GROUP BY`.
  ///
  /// **One statement for the whole page, never a count-per-row loop** — the
  /// categories page renders this figure on every row, which is exactly the
  /// shape `query_count_test` exists to catch: forty individually-fast
  /// `SELECT COUNT(*)` statements look fine in a query plan and only the count
  /// gives them away.
  ///
  /// A category with no live events is simply absent from the map rather than
  /// present at zero — callers read it with `?? 0`, which is also what makes
  /// an id the map has never heard of (a stale allowlist entry) free.
  ///
  /// `is_deleted = 0` is the same literal predicate [getAll] uses, for the
  /// same reason: a bound parameter is not reliably proven to imply the
  /// partial index's own `WHERE is_deleted = 0` on the SQLite version shipping
  /// to Android.
  Future<Map<String, int>> countByCategory() async {
    final total = calendarEvents.id.count();
    final rows =
        await (selectOnly(calendarEvents)
              ..addColumns([calendarEvents.category, total])
              ..where(const CustomExpression<bool>('is_deleted = 0'))
              ..groupBy([calendarEvents.category]))
            .get();
    return {
      for (final row in rows)
        row.read(calendarEvents.category)!: row.read(total) ?? 0,
    };
  }

  /// The hard counterpart to [softDeleteById], the [NoteDao.hardDeleteNote]
  /// precedent: retained and currently caller-less, because the delete the app
  /// performs is the tombstoning one.
  Future<void> deleteById(String id) {
    return (delete(calendarEvents)..where((e) => e.id.equals(id))).go();
  }

  /// Reassigns every live event currently in category [fromId] to [toId]. Used
  /// when a custom category is deleted so its events fall back to a surviving
  /// category instead of dangling. Returns the number of rows updated.
  ///
  /// The row count is unbounded, so this cannot read-then-write: the version
  /// bump happens in SQL (the [NoteDao.applyOrder] idiom) and the whole
  /// batch shares one HLC, because it is one user action. `updated_at` binds as
  /// a `Variable<DateTime>` — Drift stores unix seconds, so raw
  /// `millisecondsSinceEpoch` would write timestamps a thousand times too
  /// large. Tombstoned rows are skipped: a deleted event's category is not
  /// something to repair.
  ///
  /// `RETURNING id` names the moved events, so exactly those are queued with
  /// no read first. [stamp] is the category delete's own, when this is part of
  /// [CalendarCategoryDao.tombstoneCascade].
  Future<int> reassignCategory(String fromId, String toId, {CrdtStamp? stamp}) {
    return transaction(() async {
      final shared = stamp ?? db.newStamp();
      final moved = await customWriteReturning(
        'UPDATE calendar_events SET category = ?, updated_at = ?, '
        'hlc_timestamp = ?, device_id = ?, version = version + 1 '
        'WHERE category = ? AND is_deleted = 0 RETURNING id',
        variables: [
          Variable<String>(toId),
          Variable<DateTime>(DateTime.now()),
          Variable<String>(shared.hlc),
          Variable<String>(shared.deviceId),
          Variable<String>(fromId),
        ],
        updates: {calendarEvents},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(calendarEvents, [
        for (final row in moved) row.read<String>('id'),
      ], shared.hlc);
      return moved.length;
    });
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CalendarEventRow>> getByIdsIncludingDeleted(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(calendarEvents)..where((e) => e.id.isIn(ids))).get();
  }

  /// Merges one remote event on the contract of [CrdtMerge.mergeRemoteRow].
  ///
  /// A tombstone touches this row alone — its stamps, the deletion and the
  /// owner — and never runs [tombstoneEventCascade]: the delete elsewhere
  /// queued every day row and alert it tombstoned, so they arrive as their
  /// own envelopes, and the device-local `alert_registrations` follow from
  /// the engine's reconcile.
  ///
  /// The share mark is settled apart from the row ([CrdtMerge.mergeMark]):
  /// the mark stamped later stands whichever side's row won, so an edit
  /// made where a share's end had not arrived cannot bring the share back.
  /// A tombstone carries no mark, and the one here stands.
  ///
  /// A merge that changes the event's mark queues this device's copies of
  /// its day rows again ([_requeueDayRows]): a device that pushed one before
  /// it had merged the mark wrote a document that says the old one, and
  /// only the device holding the row can say it again.
  Future<MergeOutcome> mergeRemoteEvent(
    CalendarEventRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await _byId(remote.id);
      final outcome = await CrdtMerge.mergeRemoteRow(
        db,
        table: calendarEvents,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(calendarEvents).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              calendarEvents,
            )..where((e) => e.id.equals(remote.id))).write(
              CalendarEventsCompanion(
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
            await update(calendarEvents).replace(remote);
          }
          return applied;
        },
      );
      if (remote.isDeleted) return outcome;
      final kept = await CrdtMerge.mergeMark(
        db,
        table: calendarEvents,
        rowKey: remote.id,
        local: local == null
            ? null
            : (pair: local.sharedPair, stamp: local.sharedStamp),
        remote: (pair: remote.sharedPair, stamp: remote.sharedStamp),
        result: outcome.result,
        write: (mark) =>
            (update(calendarEvents)..where((e) => e.id.equals(remote.id)))
                .write(
                  CalendarEventsCompanion(
                    sharedPair: Value(mark.pair),
                    sharedStamp: Value(mark.stamp),
                  ),
                ),
      );
      if (local?.sharedPair != kept.pair) await _requeueDayRows([remote.id]);
      return outcome;
    });
  }

  /// The pair each event among [ids] is shared into, by id: an event with no
  /// mark has no entry, and a tombstone keeps its mark — the partner has to
  /// hear of the delete (`docs/cloud-sharing-foundations.md` §3).
  Future<Map<String, String>> sharedPairsOf(Iterable<String> ids) async {
    final rows = await CrdtMerge.loadInChunks(
      ids.toSet().toList(growable: false),
      (chunk) => customSelect(
        'SELECT id, shared_pair FROM calendar_events '
        'WHERE shared_pair IS NOT NULL AND id IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final id in chunk) Variable<String>(id)],
        readsFrom: {calendarEvents},
      ).get(),
    );
    return {
      for (final row in rows)
        row.read<String>('id'): row.read<String>('shared_pair'),
    };
  }

  /// The stamp each event among [ids] carries, by id, tombstones included —
  /// the newest write that decides what its day rows are shared into, since
  /// a change of the event's mark is a write of the event
  /// (`SyncTableBinding.shareStamps`).
  Future<Map<String, String>> stampsOf(Iterable<String> ids) async {
    final rows = await CrdtMerge.loadInChunks(
      ids.toSet().toList(growable: false),
      (chunk) => customSelect(
        'SELECT id, hlc_timestamp FROM calendar_events WHERE id IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final id in chunk) Variable<String>(id)],
        readsFrom: {calendarEvents},
      ).get(),
    );
    return {
      for (final row in rows)
        row.read<String>('id'): row.read<String>('hlc_timestamp'),
    };
  }

  /// Shares the live event [id] into [pairId], or makes it private again
  /// when null — the one writer of `shared_pair` on this table
  /// (`docs/cloud-sharing-foundations.md` §3). A stamped write of the one
  /// column, so the owner's other devices merge the mark like any edit;
  /// `updated_at` is left alone, as a label's write leaves it.
  ///
  /// A database shares into one pair: setting a mark clears every mark of
  /// another pair, here and on `folders`, in the same transaction.
  ///
  /// A missing or tombstoned event writes nothing, and neither does a mark
  /// the event already carries — though the marks of other pairs are
  /// cleared even then. Returns whether the event's mark was written.
  Future<bool> setSharedPair(String id, String? pairId) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null || existing.isDeleted) return false;
      // One stamp for the whole act: the mark and whatever it clears.
      final stamp = db.newStamp();
      if (pairId != null) {
        await clearOtherPairs(pairId, stamp);
        await db.folderDao.clearOtherPairs(pairId, stamp);
      }
      if (existing.sharedPair == pairId) return false;
      await db.enqueue(calendarEvents, id, stamp.hlc);
      await (update(calendarEvents)..where((e) => e.id.equals(id))).write(
        CalendarEventsCompanion(
          sharedPair: Value(pairId),
          sharedStamp: Value(stamp.hlc),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      await _requeueDayRows([id]);
      return true;
    });
  }

  /// Clears, under [stamp], the mark of every event shared into another pair
  /// than [pairId] — every mark there is when null — each row queued: its
  /// half of "a database shares into one pair", called inside the
  /// transaction of the write that sets a mark ([setSharedPair],
  /// [FolderDao.setSharedPair]) and when the account's pair is found
  /// changed or ended. Tombstones too: their documents would go on naming a
  /// pair this database no longer shares into. Returns how many it cleared.
  Future<int> clearOtherPairs(String? pairId, CrdtStamp stamp) async {
    final cleared = await customWriteReturning(
      'UPDATE calendar_events SET shared_pair = NULL, shared_stamp = ?1, '
      'hlc_timestamp = ?1, device_id = ?2, version = version + 1 '
      'WHERE shared_pair IS NOT NULL AND shared_pair IS NOT ?3 '
      'RETURNING id, is_deleted',
      variables: [
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        Variable<String>(pairId),
      ],
      updates: {calendarEvents},
      updateKind: UpdateKind.update,
    );
    if (cleared.isEmpty) return 0;
    for (final deleted in const [false, true]) {
      await db.enqueueMany(
        calendarEvents,
        [
          for (final row in cleared)
            if (row.read<bool>('is_deleted') == deleted) row.read<String>('id'),
        ],
        stamp.hlc,
        op: OutboxOp.forRow(isDeleted: deleted),
      );
    }
    await _requeueDayRows([for (final row in cleared) row.read<String>('id')]);
    return cleared.length;
  }

  /// Queues again, at the stamps they carry, the skipped days and per-day
  /// texts of the events [ids]: their documents say who may read them from
  /// their event's mark, and only a push writes that
  /// ([CrdtWrite.requeueRows]). Every one this device may push — its own,
  /// whatever `owner_id` spells that as ([SyncDao.mineSql]) — and never a
  /// row another account shares with it.
  Future<void> _requeueDayRows(List<String> ids) async {
    const step = CrdtMerge.keysPerStatement;
    for (var start = 0; start < ids.length; start += step) {
      final chunk = ids.skip(start).take(step).toList(growable: false);
      final places = [
        for (var i = 0; i < chunk.length; i++) '?${i + 2}',
      ].join(', ');
      // The day tables shared as their event is: the per-day texts and the
      // skipped days. Presence marks are a person's own and never shared.
      for (final table in <TableInfo>[
        db.eventOccurrenceDescriptions,
        db.eventSkips,
      ]) {
        await db.requeueRows(
          table,
          rows: 'event_id IN ($places) AND ${SyncDao.mineSql}',
          variables: [for (final id in chunk) Variable<String>(id)],
        );
      }
    }
  }

  /// Hard wipe, tombstones included — the backup import's replace-everything
  /// step alone ("Delete all events" tombstones through [tombstoneAll]). It
  /// must **stay** hard: re-inserting the backed-up ids over tombstones would
  /// depend on resurrection to be visible at all.
  Future<void> deleteAll() {
    return delete(calendarEvents).go();
  }

  /// Bulk restore path for a backup import — **5.1**, the [EventOccurrenceDao]
  /// `importOccurrence` convention widened to the whole list.
  ///
  /// [importData] used to drive [upsert] once per row, which cost a nested
  /// transaction (so a WAL commit) **and** a `SELECT` per event. Both were
  /// pure waste here and nowhere else: [deleteAll] runs immediately before
  /// this and is a documented *hard* wipe, tombstones included, so the table
  /// is empty and every one of those reads was a guaranteed miss whose insert
  /// branch always won. One `batch` is one transaction and one commit for the
  /// whole restore.
  ///
  /// `insertOrReplace` rather than a plain insert **only** to keep the old
  /// last-one-wins behaviour if an archive carries the same id twice; against
  /// an empty table with no foreign keys in the schema it can never cascade.
  /// Rows arrive as `version 1` originals of this device, which is what a
  /// restore is — never a merge — and each is queued in the same batch, as any
  /// new local row is.
  Future<void> importAll(List<CalendarEventsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            calendarEvents,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, calendarEvents, entry.id.value, stamp.hlc);
        }
      });
    });
  }

  /// Deliberately unfiltered: [upsert] has to see a tombstone to resurrect it,
  /// and [softDeleteById] has to see one to stay a no-op.
  Future<CalendarEventRow?> _byId(String id) {
    return (select(
      calendarEvents,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
  }
}
