import 'package:drift/drift.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/sync_outbox_table.dart';

part 'sync_outbox_dao.g.dart';

/// The push side's view of `sync_outbox`. Entries are written only by
/// `CrdtWrite`, inside the transaction of the write they describe; this class
/// reads and retires them. It holds no cache, so a database switch leaves
/// nothing stale behind.
@DriftAccessor(tables: [SyncOutbox])
class SyncOutboxDao extends DatabaseAccessor<AppDatabase>
    with _$SyncOutboxDaoMixin {
  SyncOutboxDao(super.db);

  /// The queued rows, oldest change first, so a push that stops part-way has
  /// sent a prefix of history rather than a random sample. The HLC encoding
  /// sorts lexicographically in time order.
  Future<List<SyncOutboxRow>> pending({int? limit}) {
    final query = select(syncOutbox)
      ..orderBy([
        (o) => OrderingTerm.asc(o.hlc),
        (o) => OrderingTerm.asc(o.syncedTable),
        (o) => OrderingTerm.asc(o.rowKey),
      ]);
    if (limit != null) query.limit(limit);
    return query.get();
  }

  Future<int> count() async {
    final countExpr = syncOutbox.rowKey.count();
    final row = await (selectOnly(
      syncOutbox,
    )..addColumns([countExpr])).getSingle();
    return row.read(countExpr) ?? 0;
  }

  /// Retires one entry once the push of the row at [hlc] is acknowledged.
  ///
  /// Compare-and-delete: an entry whose stored HLC is newer than [hlc] was
  /// re-queued by a write that landed while the push was in flight, and
  /// must survive to be pushed again. Returns whether the entry was retired.
  Future<bool> ackThrough(String table, String rowKey, String hlc) async {
    final deleted =
        await (delete(syncOutbox)..where(
              (o) =>
                  o.syncedTable.equals(table) &
                  o.rowKey.equals(rowKey) &
                  o.hlc.isSmallerOrEqualValue(hlc),
            ))
            .go();
    return deleted > 0;
  }

  Future<void> clear() => delete(syncOutbox).go();

  /// Queues every live row and tombstone of every synced table, at the stamp
  /// it already carries, and returns how many entries were written — the
  /// re-seed of the initial merge at bind (D15), after which every local row
  /// is either uploaded or settled against the space.
  ///
  /// Copies stored stamps and mints none. A row owned by another account
  /// ([boundUid] is the account this database is bound to) is never queued
  /// (D16); an entry already pending at a newer stamp is never lowered; a row
  /// whose stamp is empty is queued too and sorts oldest. A table whose rows
  /// travel inside their parent is never queued.
  Future<int> requeueAll({required String boundUid}) {
    final now = Variable<DateTime>(DateTime.now());
    return transaction(() async {
      var queued = 0;
      for (final table in syncedTables) {
        if (table.travelsWithParent) continue;
        queued += await customUpdate(
          'INSERT INTO sync_outbox (table_name, row_key, hlc, op, enqueued_at) '
          "SELECT '${table.name}', ${table.rowKeySql}, hlc_timestamp, "
          "CASE is_deleted WHEN 1 THEN 'tombstone' ELSE 'upsert' END, ? "
          'FROM ${table.name} WHERE owner_id IS NULL OR owner_id = ? '
          'ON CONFLICT (table_name, row_key) DO UPDATE SET '
          'hlc = excluded.hlc, op = excluded.op '
          'WHERE excluded.hlc > sync_outbox.hlc',
          variables: [now, Variable<String>(boundUid)],
          updates: {syncOutbox},
          updateKind: UpdateKind.insert,
        );
      }
      return queued;
    });
  }

  /// The highest stamp any synced row carries, `content_chunks` included,
  /// or null when no row carries one.
  Future<String?> maxHlc() async {
    final union = [
      for (final table in syncedTables)
        'SELECT MAX(hlc_timestamp) AS hlc FROM ${table.name} '
            "WHERE hlc_timestamp IS NOT NULL AND hlc_timestamp != ''",
    ].join(' UNION ALL ');
    final row = await customSelect(
      'SELECT MAX(hlc) AS hlc FROM ($union)',
    ).getSingle();
    return row.readNullable<String>('hlc');
  }
}
