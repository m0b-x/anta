import 'package:drift/drift.dart';

import '../daos/sync_dao.dart';
import '../database.dart';

/// The identity a local write stamps on its row: the HLC that orders it and
/// the device that made it.
typedef CrdtStamp = ({String hlc, String deviceId});

/// What the outbox tells a push to do with a row. A tombstone is its own op
/// so a push never has to read the row to learn the row was deleted.
enum OutboxOp {
  upsert,
  tombstone;

  /// The op for a write that leaves the row in the given state — for the
  /// writes that keep a tombstone a tombstone rather than refusing it.
  static OutboxOp forRow({required bool isDeleted}) =>
      isDeleted ? tombstone : upsert;
}

/// Where a merged row came from, which decides whether it is queued.
///
/// A [remote] row arrived through transport: queueing it would push it
/// straight back out — an echo. A [local] row is this device's own work
/// arriving through a merge path, and travels like any other local write.
enum MergeOrigin { local, remote }

/// The row key of a `counter_values` row: its composite key joined with `|`.
/// The global value keeps `noteId == ''`, giving `'<counterId>|'`.
String counterValueRowKey(String counterId, String noteId) =>
    '$counterId|$noteId';

/// The row key of an `{eventId, day}` row — `calendar_event_absences`,
/// `calendar_event_occurrences` and `calendar_event_skips`: the event id and
/// the day as epoch milliseconds, the integer each table's `exportData`
/// writes as `dayMs`.
///
/// The instant, never a date read back from it: drift returns the column as a
/// local `DateTime`, whose `.day` shifts in zones west of UTC, while its epoch
/// value is the same in every zone — so two devices key one row alike.
///
/// Truncated to the whole second the column stores (drift writes unix
/// seconds, `~/ 1000`), so a caller's milliseconds cannot key a row apart from
/// the one the table, a `RETURNING` cascade and the export all read back.
String dayRowKey(String eventId, DateTime day) =>
    '$eventId|${day.millisecondsSinceEpoch ~/ 1000 * 1000}';

/// The one path a write on a synced table takes to obtain its stamp, and the
/// only path that feeds `sync_outbox`.
///
/// Stamping and queueing are one act so that no write can commit without the
/// push learning of it: every method here is called inside the DAO's own
/// `transaction`, so the row and its outbox entry commit together or not at
/// all. The outbox is keyed `{table, rowKey}` and a newer write replaces the
/// entry, so a row saved two hundred times before a push is pushed once, at
/// its latest HLC. Remote merges never come here.
///
/// **Stamps are taken inside the transaction**, after drift has acquired the
/// connection: a stamp taken before it could wait behind another write and
/// then land an older HLC over a newer row.
extension CrdtWrite on AppDatabase {
  /// Stamps one local write on [table]'s row [rowKey] and queues the row.
  ///
  /// Call it after the write's own checks have decided the write happens —
  /// a refused write must not leave an entry behind.
  Future<CrdtStamp> stampLocal(
    TableInfo table,
    String rowKey, {
    OutboxOp op = OutboxOp.upsert,
  }) async {
    final stamp = newStamp();
    await enqueue(table, rowKey, stamp.hlc, op: op);
    return stamp;
  }

  /// A stamp with nothing queued yet: for an action that writes several rows
  /// under one HLC and queues what it actually wrote through [enqueue] or
  /// [enqueueMany] — and for `content_chunks`, which are the local storage of
  /// a note body and never queue on their own (D14).
  ///
  /// The only place a local write's HLC is minted:
  /// `test/database/crdt_write_guard_test.dart` fails on any other `hlc.now()`
  /// in a DAO or a service, since a stamp minted beside this helper is a write
  /// the push never hears of.
  CrdtStamp newStamp() => (hlc: hlc.now().toString(), deviceId: deviceId);

  /// Whether writing [entry] over the live [existing] row would store exactly
  /// what the row already holds, so an unchanged save stamps nothing — a
  /// fresh HLC on a row nobody edited would beat a real edit made elsewhere.
  ///
  /// Compared as the values SQLite stores, not as Dart values: a caller's
  /// UTC `DateTime` equals the local one drift reads back, and milliseconds a
  /// unix-seconds column never kept do not read as an edit. [ignoring] names
  /// the audit columns every save moves.
  bool changesNothing<D>(
    Insertable<D> existing,
    Insertable<D> entry, {
    Set<String> ignoring = const {'created_at', 'updated_at'},
  }) {
    final stored = existing.toColumns(false);
    for (final MapEntry(:key, :value) in entry.toColumns(false).entries) {
      if (ignoring.contains(key)) continue;
      final current = stored[key];
      if (value is! Variable || current is! Variable) return false;
      if (typeMapping.mapToSqlVariable(value.value) !=
          typeMapping.mapToSqlVariable(current.value)) {
        return false;
      }
    }
    return true;
  }

  /// Queues one row already written under [hlc].
  Future<void> enqueue(
    TableInfo table,
    String rowKey,
    String hlc, {
    OutboxOp op = OutboxOp.upsert,
  }) async {
    await _persistClockNow();
    await into(syncOutbox).insert(
      _entry(table, rowKey, hlc, op, DateTime.now()),
      onConflict: _newerWins,
    );
  }

  /// [enqueue] added to a DAO's [batch], so it commits with the batch's rows.
  ///
  /// The clock row joins the batch and is claimed as the batch is built:
  /// this method cannot observe the caller's batch, so a batch that throws
  /// leaves the claim ahead of the store until the next, higher stamp.
  ///
  /// That is safe only because a caller never continues after its batch
  /// fails: stamps it minted before the batch (S1..Sn of an `importAll`)
  /// would find the clock covered by a claim that never stored, and commit
  /// above the stored clock. A failed batch ends the action; a retry mints
  /// anew.
  void enqueueIn(
    Batch batch,
    TableInfo table,
    String rowKey,
    String hlc, {
    OutboxOp op = OutboxOp.upsert,
  }) {
    _persistClockIn(batch);
    batch.insert(
      syncOutbox,
      _entry(table, rowKey, hlc, op, DateTime.now()),
      onConflict: _newerWins,
    );
  }

  /// Queues every row in [rowKeys], all written under one shared [hlc], as
  /// one prepared statement however many keys there are.
  ///
  /// A set-based write whose `WHERE` decides which rows change learns its
  /// keys from `UPDATE … RETURNING` and passes them here, so nothing is read
  /// before the write. `RETURNING` needs SQLite 3.35; the app bundles SQLite
  /// through `sqlite3_flutter_libs` on every target, so that is guaranteed
  /// rather than left to the platform's copy.
  Future<void> enqueueMany(
    TableInfo table,
    Iterable<String> rowKeys,
    String hlc, {
    OutboxOp op = OutboxOp.upsert,
  }) async {
    if (rowKeys.isEmpty) return;
    final now = DateTime.now();
    final clock = this.hlc.last.toString();
    final persist = !_covered(clock);
    await batch((b) {
      if (persist) b.insert(syncMetadata, _clockRow(clock), onConflict: _ahead);
      b.insertAll(syncOutbox, [
        for (final key in rowKeys) _entry(table, key, hlc, op, now),
      ], onConflict: _newerWins);
    });
    // This method owns its batch, so it claims only once the batch has run.
    if (persist) this.hlc.claimPersisted(clock);
  }

  /// Queues, inside a [batch], the rows among [rowKeys] that the batch wrote
  /// under [hlc] — for batched writes whose per-row `WHERE` decides which
  /// rows change, where no row count comes back to say which did.
  ///
  /// Restricted to [rowKeys] as well as matched on the HLC: a row written
  /// before the clock was persisted can carry an HLC this clock mints again
  /// after a clock set back, and the key set keeps such a collision inside
  /// the rows this action targeted.
  ///
  /// The clock is stored only when the batch queued a row under [hlc], so a
  /// launch whose seeding wrote nothing writes no clock either; nothing is
  /// claimed, since whether it stored is decided inside SQLite.
  void enqueueWrittenIn(
    Batch batch,
    TableInfo table,
    Iterable<String> rowKeys,
    String hlc, {
    OutboxOp op = OutboxOp.upsert,
  }) {
    final keys = rowKeys.toSet().toList(growable: false);
    if (keys.isEmpty) return;
    final name = table.actualTableName;
    batch.customStatement(
      'INSERT INTO sync_outbox (table_name, row_key, hlc, op, enqueued_at) '
      'SELECT ?, id, hlc_timestamp, ?, ? FROM $name '
      'WHERE hlc_timestamp = ? AND id IN '
      '(${List.filled(keys.length, '?').join(', ')}) '
      'ON CONFLICT (table_name, row_key) DO UPDATE SET hlc = excluded.hlc, '
      'op = excluded.op, enqueued_at = excluded.enqueued_at '
      'WHERE excluded.hlc > sync_outbox.hlc',
      [
        name,
        op.name,
        typeMapping.mapToSqlVariable(DateTime.now()),
        hlc,
        ...keys,
      ],
      [TableUpdate.onTable(syncOutbox, kind: UpdateKind.insert)],
    );
    final clock = this.hlc.last.toString();
    if (_covered(clock)) return;
    batch.customStatement(
      'INSERT INTO sync_metadata (key, value, updated_at) '
      'SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM sync_outbox '
      'WHERE table_name = ? AND hlc = ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value, '
      'updated_at = excluded.updated_at '
      'WHERE excluded.value > sync_metadata.value',
      [
        SyncDao.keyLastHlc,
        clock,
        typeMapping.mapToSqlVariable(DateTime.now()),
        name,
        hlc,
      ],
      [TableUpdate.onTable(syncMetadata, kind: UpdateKind.insert)],
    );
  }

  /// Stores the clock's current value as the seed for the next open — for a
  /// pull that advanced it through the merges, once per applied batch, and
  /// after a migration's backfill. Local writes need not call it: queueing a
  /// row persists the clock.
  Future<void> persistClock() async {
    final current = hlc.last.toString();
    await into(syncMetadata).insert(_clockRow(current), onConflict: _ahead);
    hlc.claimPersisted(current);
  }

  /// Stores the clock as `last_hlc` in the caller's transaction, unless this
  /// instance already stored it: so a restart, or a wall clock set back,
  /// never mints below a row already written.
  ///
  /// The clock, not the stamp being queued: it is the highest stamp minted so
  /// far, so an action that pre-mints one stamp per row — every `importAll` —
  /// pays one statement at its first queued row and the rest find it covered.
  ///
  /// Claimed after the insert lands, so a concurrent action that minted the
  /// same clock does not skip its own write on a claim that never stored. A
  /// rolled-back transaction still leaves its claim behind; that is safe
  /// because no committed row carries a stamp above the stored value, the
  /// next stamp is higher and stores itself again, and every stamp is minted
  /// inside its own transaction — a retry mints anew, never reuses one.
  Future<void> _persistClockNow() async {
    final clock = hlc.last.toString();
    if (_covered(clock)) return;
    await into(syncMetadata).insert(_clockRow(clock), onConflict: _ahead);
    hlc.claimPersisted(clock);
  }

  /// [_persistClockNow] added to a [batch], so it commits with the batch's
  /// rows; claimed as it is added, since the batch belongs to the caller.
  void _persistClockIn(Batch batch) {
    final clock = hlc.last.toString();
    if (_covered(clock)) return;
    batch.insert(syncMetadata, _clockRow(clock), onConflict: _ahead);
    hlc.claimPersisted(clock);
  }

  /// Whether [clock] is at or below what this instance already claimed. The
  /// encoding is zero-padded hex, so string order is stamp order.
  bool _covered(String clock) {
    final persisted = hlc.persistedUpTo;
    return persisted != null && clock.compareTo(persisted) <= 0;
  }

  SyncMetadataCompanion _clockRow(String stamp) {
    return SyncMetadataCompanion.insert(
      key: SyncDao.keyLastHlc,
      value: stamp,
      updatedAt: DateTime.now(),
    );
  }

  /// The stored clock only moves forward: a write committing after a newer
  /// one, or a merge's older clock, must not lower the seed.
  DoUpdate<$SyncMetadataTable, SyncMetadataData> get _ahead {
    return DoUpdate.withExcluded(
      (old, excluded) => SyncMetadataCompanion.custom(
        value: excluded.value,
        updatedAt: excluded.updatedAt,
      ),
      where: (old, excluded) => excluded.value.isBiggerThan(old.value),
    );
  }

  /// An entry only ever moves forward: a write that commits after a newer
  /// one (or a stale re-queue) must not lower the HLC a push acknowledges
  /// through, or the newer change would be retired unsent.
  DoUpdate<$SyncOutboxTable, SyncOutboxRow> get _newerWins {
    return DoUpdate.withExcluded(
      (old, excluded) => SyncOutboxCompanion.custom(
        hlc: excluded.hlc,
        op: excluded.op,
        enqueuedAt: excluded.enqueuedAt,
      ),
      where: (old, excluded) => excluded.hlc.isBiggerThan(old.hlc),
    );
  }

  SyncOutboxCompanion _entry(
    TableInfo table,
    String rowKey,
    String hlc,
    OutboxOp op,
    DateTime now,
  ) {
    return SyncOutboxCompanion.insert(
      syncedTable: table.actualTableName,
      rowKey: rowKey,
      hlc: hlc,
      op: op.name,
      enqueuedAt: now,
    );
  }
}
