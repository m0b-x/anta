import 'package:drift/drift.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/sync_outbox_table.dart';

part 'sync_outbox_dao.g.dart';

/// One entry's place in the queue's `(hlc, table, rowKey)` order — where
/// [SyncOutboxDao.pending] resumes from.
typedef SyncOutboxKey = ({String hlc, String table, String rowKey});

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
  ///
  /// [after] resumes from an entry already read, so a drain that holds many
  /// of them back pages forward instead of re-reading the queue's head for
  /// every batch. The resume is one row-value comparison over the columns of
  /// `idx_sync_outbox_order` (v47), so every page is a range seek on that
  /// index, where the expanded `>` / `=` disjunction it replaced gives SQLite
  /// no range to seek to.
  Future<List<SyncOutboxRow>> pending({int? limit, SyncOutboxKey? after}) {
    return customSelect(
      'SELECT * FROM sync_outbox'
      '${after == null ? '' : ' WHERE (hlc, table_name, row_key) > (?, ?, ?)'}'
      ' ORDER BY hlc, table_name, row_key'
      '${limit == null ? '' : ' LIMIT ?'}',
      variables: [
        if (after != null) ...[
          Variable<String>(after.hlc),
          Variable<String>(after.table),
          Variable<String>(after.rowKey),
        ],
        if (limit != null) Variable<int>(limit),
      ],
      readsFrom: {syncOutbox},
    ).map((row) => syncOutbox.map(row.data)).get();
  }

  /// The queued rows of one table, in the same order — the pull's read when
  /// a page parks under the bind floor, where the whole queue would be every
  /// row of every synced table during the initial merge.
  Future<List<SyncOutboxRow>> pendingForTable(String table) {
    return (select(syncOutbox)
          ..where((o) => o.syncedTable.equals(table))
          ..orderBy([
            (o) => OrderingTerm.asc(o.hlc),
            (o) => OrderingTerm.asc(o.rowKey),
          ]))
        .get();
  }

  /// The queued entries of [table] among [rowKeys], by key — the chunk
  /// entries a manifest's push has to send first, wherever they sit in the
  /// queue.
  Future<Map<String, SyncOutboxRow>> pendingKeys(
    String table,
    List<String> rowKeys,
  ) async {
    final rows = await CrdtMerge.loadInChunks(
      rowKeys,
      (chunk) =>
          (select(syncOutbox)..where(
                (o) => o.syncedTable.equals(table) & o.rowKey.isIn(chunk),
              ))
              .get(),
    );
    return {for (final row in rows) row.rowKey: row};
  }

  /// The keys among [rowKeys] whose row of the synced [table] is a
  /// tombstone here — what the Sync page marks deleted among the rows it
  /// lists as held back. Read by the table's row key expression, so a
  /// day-keyed row is found by the key its entry carries.
  Future<Set<String>> tombstonedKeys(String table, List<String> rowKeys) async {
    final synced = syncedTables.where((t) => t.name == table).firstOrNull;
    if (synced == null) return const {};
    final keys = await CrdtMerge.loadInChunks(rowKeys, (chunk) async {
      final rows = await customSelect(
        'SELECT ${synced.rowKeySql} AS row_key FROM ${synced.name} '
        'WHERE is_deleted = 1 AND ${synced.rowKeySql} IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final key in chunk) Variable<String>(key)],
      ).get();
      return [for (final row in rows) row.read<String>('row_key')];
    });
    return keys.toSet();
  }

  /// Fires after every commit that queued or raised an entry: the push
  /// trigger the engine debounces. Inserts only, so the engine's own acks —
  /// deletes — never re-arm the trigger they just satisfied.
  Stream<void> watchQueued() => db
      .tableUpdates(
        TableUpdateQuery.onTable(
          syncOutbox,
          limitUpdateKind: UpdateKind.insert,
        ),
      )
      .map((_) {});

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
  /// whose stamp is empty is queued too and sorts oldest. A content-addressed
  /// table queues its live hashed rows only, one entry per hash at the
  /// highest stamp among them.
  Future<int> requeueAll({required String boundUid}) {
    return transaction(() async {
      var queued = 0;
      for (final table in syncedTables) {
        queued += await _requeue(table, boundUid);
      }
      return queued;
    });
  }

  /// Queues every live note and every chunk hash a live row holds, at the
  /// stamps they carry — the cutover to the chunked wire, once per wire
  /// version (scalability record S6, D2): the space still holds whole-body
  /// documents an older build wrote, and nothing else would replace them.
  /// The other devices' entries for the same notes retire when they pull a
  /// manifest equal to their own body (S9's equal-stamp ack), and a chunk
  /// pushed twice is one document written twice.
  ///
  /// Announced as an update, not an insert: the run that cuts over drains
  /// right after, so arming [watchQueued]'s debounced drain as well would
  /// only schedule a second, empty one.
  Future<int> requeueBodies({required String boundUid}) {
    final notes = syncedTables.singleWhere((t) => t.name == 'notes');
    final chunks = syncedTables.singleWhere((t) => t.contentAddressed);
    return transaction(() async {
      return await _requeue(
            notes,
            boundUid,
            rows: 'is_deleted = 0',
            kind: UpdateKind.update,
          ) +
          await _requeue(chunks, boundUid, kind: UpdateKind.update);
    });
  }

  /// [requeueAll]'s statement for one table, narrowed to [rows], announced
  /// to the outbox's watchers as [kind].
  Future<int> _requeue(
    SyncedTable table,
    String boundUid, {
    String rows = '1 = 1',
    UpdateKind kind = UpdateKind.insert,
  }) {
    return customUpdate(
      'INSERT INTO sync_outbox (table_name, row_key, hlc, op, enqueued_at) '
      "SELECT '${table.name}', ${table.rowKeySql}, hlc_timestamp, "
      "CASE is_deleted WHEN 1 THEN 'tombstone' ELSE 'upsert' END, ? "
      'FROM ${table.name} WHERE ${table.queuedRowsSql} AND $rows '
      'ON CONFLICT (table_name, row_key) DO UPDATE SET '
      'hlc = excluded.hlc, op = excluded.op '
      'WHERE excluded.hlc > sync_outbox.hlc',
      variables: [
        Variable<DateTime>(DateTime.now()),
        Variable<String>(boundUid),
      ],
      updates: {syncOutbox},
      updateKind: kind,
    );
  }

  /// Queues one row of [table] at the stamp it already carries — the
  /// one-row form of [requeueAll], for a merge whose local row beat the
  /// remote: the space holds an older version, so this device must push its
  /// own again. Returns whether an entry was written or raised.
  ///
  /// Mints nothing and never lowers an entry pending at a newer stamp. No
  /// owner predicate: a merge only ever names a row of the bound space. Never
  /// a content-addressed row: its document cannot be out of date.
  Future<bool> requeueRow(String table, String rowKey) async {
    final synced = syncedTables.where((t) => t.name == table).firstOrNull;
    if (synced == null || synced.contentAddressed) {
      throw ArgumentError.value(table, 'table', 'not re-queued by a merge');
    }
    final written = await customUpdate(
      'INSERT INTO sync_outbox (table_name, row_key, hlc, op, enqueued_at) '
      "SELECT '${synced.name}', ${synced.rowKeySql}, hlc_timestamp, "
      "CASE is_deleted WHEN 1 THEN 'tombstone' ELSE 'upsert' END, ? "
      'FROM ${synced.name} WHERE ${synced.rowKeySql} = ? '
      'ON CONFLICT (table_name, row_key) DO UPDATE SET '
      'hlc = excluded.hlc, op = excluded.op '
      'WHERE excluded.hlc > sync_outbox.hlc',
      variables: [Variable<DateTime>(DateTime.now()), Variable<String>(rowKey)],
      updates: {syncOutbox},
      updateKind: UpdateKind.insert,
    );
    return written > 0;
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
