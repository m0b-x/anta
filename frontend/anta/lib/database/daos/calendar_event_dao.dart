import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/calendar_events_table.dart';

part 'calendar_event_dao.g.dart';

/// All CRDT stamping for `calendar_events` lives here, never in the service:
/// `db.generateHlc()`, `db.deviceId` and read-then-write `version + 1`, the
/// [NoteDao] idiom already followed by [EventAbsenceDao]. Nothing above this
/// class — model, service, blocs, backup — sees a CRDT field or a tombstone.
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
  Future<void> upsert(CalendarEventsCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);
      final hlc = db.generateHlc();

      if (existing == null) {
        await into(calendarEvents).insert(
          entry.copyWith(
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: const Value(1),
          ),
        );
        return;
      }

      await (update(calendarEvents)..where((e) => e.id.equals(id))).write(
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

  /// Tombstones one event, the [NoteDao.softDeleteNote] shape: the row survives
  /// with `is_deleted = 1` and a bumped version so the delete carries an order
  /// once devices merge, and [getAll]'s filter is what makes it vanish from
  /// every surface. A missing or already-tombstoned row is a no-op, so a
  /// repeated delete cannot churn the version.
  Future<void> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      await (update(calendarEvents)..where((e) => e.id.equals(id))).write(
        CalendarEventsCompanion(
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
  Future<int> reassignCategory(String fromId, String toId) {
    return customUpdate(
      'UPDATE calendar_events SET category = ?, updated_at = ?, '
      'hlc_timestamp = ?, device_id = ?, version = version + 1 '
      'WHERE category = ? AND is_deleted = 0',
      variables: [
        Variable<String>(toId),
        Variable<DateTime>(DateTime.now()),
        Variable<String>(db.generateHlc()),
        Variable<String>(db.deviceId),
        Variable<String>(fromId),
      ],
      updates: {calendarEvents},
    );
  }

  /// Hard wipe, tombstones included. Backs "Delete all events" — whose copy
  /// promises the removal is permanent — and the backup import's
  /// replace-everything step. That second use is why it must **stay** hard:
  /// re-inserting the backed-up ids over tombstones would depend on
  /// resurrection to be visible at all.
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
  /// restore is — never a merge.
  Future<void> importAll(List<CalendarEventsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(
          calendarEvents,
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

  /// Deliberately unfiltered: [upsert] has to see a tombstone to resurrect it,
  /// and [softDeleteById] has to see one to stay a no-op.
  Future<CalendarEventRow?> _byId(String id) {
    return (select(
      calendarEvents,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
  }
}
