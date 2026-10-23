import 'package:drift/drift.dart';

import '../crdt/crdt_write.dart';
import '../database.dart';
import '../tables/event_alerts_table.dart';

part 'event_alert_dao.g.dart';

/// All CRDT stamping for `calendar_event_alerts` lives here, never in the
/// service: a `CrdtWrite` stamp, the row queued in the same transaction
/// (**v43**), and read-then-write `version + 1`, the [NoteDao] idiom already
/// followed by [EventSkipDao]. Nothing above this class — model, service,
/// blocs, backup — sees a CRDT field, a tombstone or the outbox.
@DriftAccessor(tables: [EventAlerts])
class EventAlertDao extends DatabaseAccessor<AppDatabase>
    with _$EventAlertDaoMixin {
  EventAlertDao(super.db);

  /// Every live alert, in one statement.
  ///
  /// The single read path for the feature: `EventAlertService` loads the whole
  /// table into the `EventAlerts` facade at startup and republishes from it,
  /// so the badges, the editor, the hub and the planner all inherit the
  /// tombstone filter for free — and a per-event read in a loop, which is
  /// exactly what `query_count_test` exists to catch, never becomes tempting.
  ///
  /// The predicate is a raw literal rather than `isDeleted.equals(false)`:
  /// Drift binds that as `is_deleted = ?`, and whether SQLite can prove a
  /// bound parameter implies the partial index's `WHERE is_deleted = 0`
  /// differs by version (3.53 can, the version shipping to Android cannot).
  /// The literal matches syntactically everywhere.
  Future<List<EventAlertRow>> getAllActive() {
    return (select(eventAlerts)
          ..where((a) => const CustomExpression<bool>('is_deleted = 0'))
          ..orderBy([
            (a) => OrderingTerm.asc(a.eventId),
            (a) => OrderingTerm.asc(a.createdAt),
          ]))
        .get();
  }

  /// Makes [entries] the complete set of alerts for [eventId], in one
  /// transaction: rows that are no longer in the list are **tombstoned**, rows
  /// that are stay — re-stamped only if something in them changed — and rows
  /// that are new are inserted.
  ///
  /// A kept row whose content is **unchanged is not written at all**. The
  /// editor and the hub's switch both hand over the whole set on every save,
  /// so re-stamping regardless would bump the version and the HLC of every
  /// alert whenever an event's title changed — and once two devices merge, a
  /// fresh HLC on an alert nobody touched beats a real edit made elsewhere.
  ///
  /// One transaction rather than a delete-then-insert pair, because an alert's
  /// identity is what survives an edit: keeping the row means the registration
  /// the scheduler already placed for it can be diffed rather than cancelled
  /// and re-created, and a merge sees one ordered change instead of a
  /// disappearance and an unrelated arrival.
  ///
  /// Removals tombstone rather than delete for the same reason every other
  /// CRDT table does — the delete has to carry an order once two devices
  /// merge. Re-adding an alert with the same id resurrects its row, the
  /// `CalendarEventDao.upsert` rule.
  ///
  /// One read for the whole event, then one write per changed row: the
  /// alternative, a `SELECT` per alert to find its version, is the
  /// query-in-a-loop shape at five rows.
  ///
  /// The whole save is one act under one HLC: removals queue as tombstones,
  /// inserts and edits as upserts, each set in one statement, and an
  /// unchanged row queues nothing.
  Future<void> replaceForEvent(
    String eventId,
    List<EventAlertsCompanion> entries,
  ) {
    return transaction(() async {
      final existing = await (select(
        eventAlerts,
      )..where((a) => a.eventId.equals(eventId))).get();
      final byId = {for (final row in existing) row.id: row};
      final keep = {for (final entry in entries) entry.id.value};
      final now = DateTime.now();
      final stamp = db.newStamp();
      final removed = <String>[];
      final written = <String>[];

      for (final row in existing) {
        if (row.isDeleted || keep.contains(row.id)) continue;
        await (update(eventAlerts)..where((a) => a.id.equals(row.id))).write(
          EventAlertsCompanion(
            isDeleted: const Value(true),
            deletedAt: Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(row.version + 1),
          ),
        );
        removed.add(row.id);
      }

      for (final entry in entries) {
        final row = byId[entry.id.value];
        if (row != null && _sameContent(row, entry, eventId)) continue;
        written.add(entry.id.value);
        if (row == null) {
          await into(eventAlerts).insert(
            entry.copyWith(
              eventId: Value(eventId),
              createdAt: entry.createdAt.present
                  ? entry.createdAt
                  : Value(now),
              updatedAt: Value(now),
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
          );
          continue;
        }
        await (update(eventAlerts)..where((a) => a.id.equals(row.id))).write(
          entry.copyWith(
            eventId: Value(eventId),
            // Never overwritten: an alert keeps the moment it was first set,
            // the `CalendarEventDao.upsert` rule.
            createdAt: const Value.absent(),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(row.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
      }

      await db.enqueueMany(
        eventAlerts,
        removed,
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
      await db.enqueueMany(eventAlerts, written, stamp.hlc);
    });
  }

  /// Whether [entry] would leave a live [row] saying exactly what it says now.
  /// An absent companion field is one the write would not touch.
  static bool _sameContent(
    EventAlertRow row,
    EventAlertsCompanion entry,
    String eventId,
  ) {
    bool same<T>(Value<T> next, T current) =>
        !next.present || next.value == current;
    return !row.isDeleted &&
        row.eventId == eventId &&
        same(entry.mode, row.mode) &&
        same(entry.offsetMinutes, row.offsetMinutes) &&
        same(entry.daysBefore, row.daysBefore) &&
        same(entry.dayMinute, row.dayMinute) &&
        same(entry.sound, row.sound) &&
        same(entry.enabled, row.enabled);
  }

  /// Cascade for a deleted event: since v27 deleting an event tombstones it,
  /// so its alerts tombstone too and the pair merges as one act.
  ///
  /// One statement for an unbounded row count — `version + 1` in SQL, one
  /// shared HLC for the batch, the [EventSkipDao.tombstoneForEvent] idiom.
  /// Already-tombstoned rows are skipped, so a repeat cannot churn versions.
  /// `updated_at` / `deleted_at` bind as `Variable<DateTime>` because Drift
  /// stores unix seconds.
  ///
  /// The `is_deleted = 0` literal is what lets this find its rows through
  /// `idx_calendar_event_alerts_active` instead of scanning years of
  /// tombstones. `RETURNING id` queues exactly the rows it tombstoned; [stamp]
  /// is the event delete's own, from [CalendarEventDao.tombstoneEventCascade].
  Future<void> tombstoneForEvent(String eventId, {CrdtStamp? stamp}) {
    return transaction(() async {
      final shared = stamp ?? db.newStamp();
      final now = DateTime.now();
      final tombstoned = await customWriteReturning(
        'UPDATE calendar_event_alerts SET is_deleted = 1, deleted_at = ?, '
        'updated_at = ?, hlc_timestamp = ?, device_id = ?, '
        'version = version + 1 '
        'WHERE event_id = ? AND is_deleted = 0 RETURNING id',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(shared.hlc),
          Variable<String>(shared.deviceId),
          Variable<String>(eventId),
        ],
        updates: {eventAlerts},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(
        eventAlerts,
        [for (final row in tombstoned) row.read<String>('id')],
        shared.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }

  /// The **hard** cascade, tombstones included — for the wipe paths, where no
  /// parent survives to merge against and a tombstoned child would strand an
  /// orphan in every export.
  Future<void> deleteForEvent(String eventId) {
    return (delete(eventAlerts)..where((a) => a.eventId.equals(eventId))).go();
  }

  Future<void> deleteAll() {
    return delete(eventAlerts).go();
  }

  /// Inserts alerts while preserving externally-provided audit fields, the
  /// [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored alert is this device's own live row, never a replayed one.
  ///
  /// One batched transaction and one commit for the whole archive rather than
  /// an awaited insert — and a WAL commit — per restored alert. Each alert is
  /// queued in the same batch, as any new local row is.
  Future<void> importAll(List<EventAlertsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            eventAlerts,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, eventAlerts, entry.id.value, stamp.hlc);
        }
      });
    });
  }
}
