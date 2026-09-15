import 'package:drift/drift.dart';

/// The mirror of what the operating system currently holds for us (**v40**) —
/// one row per alarm or notification actually handed to the platform.
///
/// **Device-local.** No CRDT block, hard deletes allowed, never exported in a
/// backup and never synced: the sanctioned device-local category the pairing
/// keys already live in. A registration describes *this* phone's scheduler,
/// and carrying it anywhere else would describe a scheduler that does not
/// exist.
///
/// **The OS is the truth for `pending`.** A `.db` file imported from another
/// device brings that device's rows along, so reconcile checks every pending
/// row against the platform's own pending list and drops the ones it does not
/// recognise before diffing. The table is a cache that can always be rebuilt
/// by planning again; nothing reads it as authoritative.
///
/// [day] and [fireAt] are stored as plain epoch **milliseconds**, not as
/// Drift `DateTime` columns: [day] is a date-only **UTC** occurrence day and
/// [fireAt] is a **local** wall-clock instant, and the two must not be run
/// through one implicit conversion that would quietly shift either by a day or
/// an hour. [createdAt] / [updatedAt] are ordinary audit columns and stay
/// `DateTime`, like every other table's.
@DataClassName('AlertRegistrationRow')
class AlertRegistrations extends Table {
  @override
  String get tableName => 'alert_registrations';

  /// The 31-bit id handed to the platform, derived deterministically from the
  /// database name, the alert id, the occurrence day and the kind — so
  /// reconcile is idempotent across process deaths, and two databases can
  /// never cancel each other's alarms.
  IntColumn get osId => integer()();

  TextColumn get alertId => text()();

  TextColumn get eventId => text()();

  /// Occurrence day, date-only UTC, epoch milliseconds.
  IntColumn get day => integer()();

  /// The local instant the platform was asked to fire at, epoch milliseconds.
  IntColumn get fireAt => integer()();

  /// `scheduled` | `snooze`. A snooze is its own registration, so an unrelated
  /// reconcile of the same event leaves it alone.
  TextColumn get kind => text().withDefault(const Constant('scheduled'))();

  /// `pending` | `fired` | `stopped` | `cancelled`.
  TextColumn get state => text().withDefault(const Constant('pending'))();

  /// Which gateway backend holds it — `alarm` | `notification`.
  TextColumn get backend => text()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {osId};
}
