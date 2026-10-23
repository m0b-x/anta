import 'package:drift/drift.dart';
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
}
