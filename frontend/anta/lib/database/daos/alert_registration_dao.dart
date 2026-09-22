import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/alert_registrations_table.dart';

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
    return (update(alertRegistrations)..where((r) => r.osId.equals(osId)))
        .write(
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
  /// breath, and a tombstone here would describe nothing.
  Future<int> deleteForEvent(String eventId) {
    return (delete(
      alertRegistrations,
    )..where((r) => r.eventId.equals(eventId))).go();
  }

  Future<void> deleteAll() {
    return delete(alertRegistrations).go();
  }
}
