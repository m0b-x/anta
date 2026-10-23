import 'package:drift/drift.dart';

import '../crdt/crdt_write.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/calendar_events_table.dart';

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
  Future<void> upsert(CalendarEventsCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);

      if (existing == null) {
        final stamp = await db.stampLocal(calendarEvents, id);
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
      final stamp = await db.stampLocal(calendarEvents, id);
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
  /// bump happens in SQL (the [NoteDao.setNotePositions] idiom) and the whole
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
