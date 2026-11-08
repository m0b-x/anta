import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/alert_registrations_table.dart';
import 'sync_dao.dart';

part 'alert_registration_dao.g.dart';

/// All SQL for `alert_registrations`, the device-local mirror of what the
/// operating system currently holds.
///
/// The one DAO in the calendar family with **no CRDT stamping and hard
/// deletes**, and deliberately so: nothing here is ever exported, synced or
/// merged, and every row can be rebuilt by planning again. A tombstone would
/// describe a cancelled alarm on a phone that may not exist.
@DriftAccessor(tables: [AlertRegistrations])
class AlertRegistrationDao extends DatabaseAccessor<AppDatabase>
    with _$AlertRegistrationDaoMixin {
  AlertRegistrationDao(super.db);

  /// Records one registration, replacing any row that already holds the same
  /// `os_id`.
  ///
  /// Replace rather than fail: `os_id` is a deterministic hash of the
  /// database, alert, day and kind, so the same registration re-planned after
  /// a process death is *the same row*, and a hash collision resolved to this
  /// slot by the scheduler's probe has already released the previous holder.
  Future<void> put(AlertRegistrationsCompanion entry) {
    return into(
      alertRegistrations,
    ).insert(entry, mode: InsertMode.insertOrReplace);
  }

  /// Everything still believed to be armed, soonest first.
  ///
  /// The reconcile read, and the reason `idx_alert_registrations_pending`
  /// exists: partial on `state = 'pending'` so the handful of live rows are
  /// found without walking every swept-but-not-yet-deleted one, and keyed by
  /// `fire_at` so the ordering costs no temp B-tree. Both terms are spelled as
  /// literals — a bound `state = ?` is not reliably proven to imply the
  /// index's own `WHERE` on the SQLite version shipping to Android.
  Future<List<AlertRegistrationRow>> pending() {
    return (select(alertRegistrations)
          ..where((r) => const CustomExpression<bool>("state = 'pending'"))
          ..orderBy([(r) => OrderingTerm.asc(r.fireAt)]))
        .get();
  }

  /// Whether the platform may still hold an entry of this database: the
  /// registry holds a row, whatever its state, or a hard delete left its
  /// [SyncDao.keyAlertStraysPending] marker and no pass has completed since.
  /// The reconcile's "nothing can arm" check asks it first, in one statement.
  Future<bool> mayHoldEntries() async {
    final row = await customSelect(
      'SELECT EXISTS(SELECT 1 FROM alert_registrations) '
      'OR EXISTS(SELECT 1 FROM sync_metadata WHERE key = ?) AS hit',
      variables: [Variable<String>(SyncDao.keyAlertStraysPending)],
      readsFrom: {alertRegistrations, attachedDatabase.syncMetadata},
    ).getSingle();
    return row.read<int>('hit') != 0;
  }

  /// The strays marker as it stands, or null — read by a pass before it reads
  /// the registry, so [clearStraysMarker] clears only what that pass saw.
  Future<String?> straysMarker() =>
      attachedDatabase.syncDao.getValue(SyncDao.keyAlertStraysPending);

  /// Clears the strays marker a completed pass read as [seen]. A delete that
  /// landed mid-pass wrote a new value, which survives for the pass it
  /// requested: this one read the registry before those rows went.
  Future<void> clearStraysMarker(String seen) {
    return customUpdate(
      'DELETE FROM sync_metadata WHERE key = ? AND value = ?',
      variables: [
        Variable<String>(SyncDao.keyAlertStraysPending),
        Variable<String>(seen),
      ],
      updates: {attachedDatabase.syncMetadata},
      updateKind: UpdateKind.delete,
    );
  }

  /// Marks that rows just went while the platform may still hold their
  /// entries. Called inside the delete's transaction, so a process death can
  /// never leave the rows gone and the marker unwritten; the value is unique
  /// per delete for [clearStraysMarker] — a v4 id, which no shared instant or
  /// clock set back can repeat.
  Future<void> _markStrays() => attachedDatabase.syncDao.setValue(
    SyncDao.keyAlertStraysPending,
    _uuid.v4(),
  );

  static const _uuid = Uuid();

  /// The os ids of every `fired` registration: rings the binding announced
  /// that nothing has settled since.
  ///
  /// The reconcile's stray sweep asks once a pass, and only once a platform
  /// entry has got past every other check — a `fired` row's entry is never
  /// the plan's to cancel. A scan, which `idx_alert_registrations_pending`
  /// cannot serve: settled rows live a week at most.
  Future<Set<int>> firedOsIds() async {
    final rows = await (select(
      alertRegistrations,
    )..where((r) => const CustomExpression<bool>("state = 'fired'"))).get();
    return {for (final row in rows) row.osId};
  }

  /// One registration by the id the platform holds it under, or `null`.
  ///
  /// The read behind Stop and Snooze: both arrive from the OS carrying nothing
  /// but an `os_id`, and this is what turns that back into an event, an alert
  /// and an occurrence day. Hits the primary key, so no index is needed.
  Future<AlertRegistrationRow?> byOsId(int osId) {
    return (select(
      alertRegistrations,
    )..where((r) => r.osId.equals(osId))).getSingleOrNull();
  }

  /// Every registration of one event, whatever its state — the reason
  /// `idx_alert_registrations_event` exists.
  Future<List<AlertRegistrationRow>> forEvent(String eventId) {
    return (select(
      alertRegistrations,
    )..where((r) => r.eventId.equals(eventId))).get();
  }

  /// Moves one registration to a new lifecycle state — `fired`, `stopped`,
  /// `missed` or `cancelled`. A row the platform no longer knows about is
  /// simply absent, so a miss is a no-op rather than an error.
  Future<void> markState(int osId, String state) {
    return (update(
      alertRegistrations,
    )..where((r) => r.osId.equals(osId))).write(
      AlertRegistrationsCompanion(
        state: Value(state),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// The settled rows of the last window, newest first — the Alerts hub's
  /// *Recent* section (OS-4), in one statement: `pending` is what the phone
  /// will do, `cancelled` is the plan changing rather than history, and both
  /// are left out.
  Future<List<AlertRegistrationRow>> recent({required DateTime since}) {
    return (select(alertRegistrations)
          ..where(
            (r) =>
                const CustomExpression<bool>(
                  "state NOT IN ('pending', 'cancelled')",
                ) &
                r.updatedAt.isBiggerOrEqualValue(since),
          )
          ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]))
        .get();
  }

  /// Drops settled registrations older than [retention], in one statement.
  ///
  /// `pending` rows are never swept regardless of age — a registration whose
  /// instant has passed but which the OS never delivered is exactly what the
  /// late-fire path has to find. Everything else is history, and history that
  /// cannot be exported or merged has no reason to outlive a week.
  Future<int> sweep({
    DateTime? now,
    Duration retention = const Duration(days: 7),
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(retention);
    return (delete(alertRegistrations)..where(
          (r) =>
              const CustomExpression<bool>("state <> 'pending'") &
              r.updatedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  /// Cascade for a deleted event. A hard delete, unlike the alert rows this
  /// accompanies: the OS entries are cancelled by the scheduler in the same
  /// breath, and a tombstone here would describe nothing. Rows gone leave the
  /// strays marker for the pass that has not run yet.
  Future<int> deleteForEvent(String eventId) {
    return transaction(() async {
      final gone = await (delete(
        alertRegistrations,
      )..where((r) => r.eventId.equals(eventId))).go();
      if (gone > 0) await _markStrays();
      return gone;
    });
  }

  /// [deleteForEvent] for a wipe's tombstoned events: one statement per
  /// [_idsPerStatement] ids, so a calendar of any size stays under SQLite's
  /// bound-variable limit (999 on older builds).
  Future<void> deleteForEvents(Iterable<String> eventIds) {
    final ids = eventIds.toList();
    return transaction(() async {
      var gone = 0;
      for (var start = 0; start < ids.length; start += _idsPerStatement) {
        final end = start + _idsPerStatement < ids.length
            ? start + _idsPerStatement
            : ids.length;
        final chunk = ids.sublist(start, end);
        gone += await (delete(
          alertRegistrations,
        )..where((r) => r.eventId.isIn(chunk))).go();
      }
      if (gone > 0) await _markStrays();
    });
  }

  static const int _idsPerStatement = 500;

  /// Every registration, hard deleted. No app path calls it today; it marks
  /// like every other hard delete so a caller added later cannot strand the
  /// entries the rows described.
  Future<void> deleteAll() {
    return transaction(() async {
      if (await delete(alertRegistrations).go() > 0) await _markStrays();
    });
  }
}
