import 'package:drift/drift.dart';

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
  CrdtStamp newStamp() => (hlc: generateHlc(), deviceId: deviceId);

  /// Queues one row already written under [hlc].
  Future<void> enqueue(
    TableInfo table,
    String rowKey,
    String hlc, {
    OutboxOp op = OutboxOp.upsert,
  }) {
    return into(syncOutbox).insert(
      _entry(table, rowKey, hlc, op, DateTime.now()),
      onConflict: _newerWins,
    );
  }

  /// [enqueue] added to a DAO's [batch], so it commits with the batch's rows.
  void enqueueIn(
    Batch batch,
    TableInfo table,
    String rowKey,
    String hlc, {
    OutboxOp op = OutboxOp.upsert,
  }) {
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
    await batch((b) {
      b.insertAll(syncOutbox, [
        for (final key in rowKeys) _entry(table, key, hlc, op, now),
      ], onConflict: _newerWins);
    });
  }

  /// Queues, inside a [batch], the rows among [rowKeys] that the batch wrote
  /// under [hlc] — for batched writes whose per-row `WHERE` decides which
  /// rows change, where no row count comes back to say which did.
  ///
  /// Restricted to [rowKeys] as well as matched on the HLC: until the clock
  /// is persisted (R5), a clock set back can mint an HLC an older row already
  /// carries, and the key set keeps such a collision inside the rows this
  /// action targeted.
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
