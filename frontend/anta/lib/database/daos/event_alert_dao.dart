import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/event_alerts_table.dart';

part 'event_alert_dao.g.dart';

/// All CRDT stamping for `calendar_event_alerts` lives here, never in the
/// service: `db.generateHlc()`, `db.deviceId` and read-then-write
/// `version + 1`, the [NoteDao] idiom already followed by [EventSkipDao].
/// Nothing above this class — model, service, blocs, backup — sees a CRDT
/// field or a tombstone.
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
  /// that are stay and are re-stamped, rows that are new are inserted.
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
      final hlc = db.generateHlc();

      for (final row in existing) {
        if (row.isDeleted || keep.contains(row.id)) continue;
        await (update(eventAlerts)..where((a) => a.id.equals(row.id))).write(
          EventAlertsCompanion(
            isDeleted: const Value(true),
            deletedAt: Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: Value(row.version + 1),
          ),
        );
      }

      for (final entry in entries) {
        final row = byId[entry.id.value];
        if (row == null) {
          await into(eventAlerts).insert(
            entry.copyWith(
              eventId: Value(eventId),
              createdAt: entry.createdAt.present
                  ? entry.createdAt
                  : Value(now),
              updatedAt: Value(now),
              hlcTimestamp: Value(hlc),
              deviceId: Value(db.deviceId),
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
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: Value(row.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
      }
    });
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
  /// tombstones.
  Future<void> tombstoneForEvent(String eventId) async {
    final now = DateTime.now();
    await customUpdate(
      'UPDATE calendar_event_alerts SET is_deleted = 1, deleted_at = ?, '
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
      updates: {eventAlerts},
    );
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
  /// an awaited insert — and a WAL commit — per restored alert.
  Future<void> importAll(List<EventAlertsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(
          eventAlerts,
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
}
