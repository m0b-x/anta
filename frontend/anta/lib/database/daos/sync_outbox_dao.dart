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
  ///
  /// [unpushedOnly] leaves out the entries that only re-send a version the
  /// space holds ([SyncOutbox.republish]), in the same order: what a push
  /// sends first, so a write that changes what other rows' documents say —
  /// a share mark on a folder — reaches the space before those rows are
  /// sent again under it (`docs/cloud-sharing-foundations.md` §3).
  Future<List<SyncOutboxRow>> pending({
    int? limit,
    SyncOutboxKey? after,
    bool unpushedOnly = false,
  }) {
    final conditions = [
      if (after != null) '(hlc, table_name, row_key) > (?, ?, ?)',
      if (unpushedOnly) 'republish = 0',
    ];
    return customSelect(
      'SELECT * FROM sync_outbox'
      '${conditions.isEmpty ? '' : ' WHERE ${conditions.join(' AND ')}'}'
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
  ///
  /// [unpushedOnly] leaves out the entries that re-send a version the space
  /// holds ([SyncOutbox.republish]): what the conflict check asks for, where
  /// only a write this device never pushed can be lost.
  Future<Map<String, SyncOutboxRow>> pendingKeys(
    String table,
    List<String> rowKeys, {
    bool unpushedOnly = false,
  }) async {
    final rows = await CrdtMerge.loadInChunks(
      rowKeys,
      (chunk) =>
          (select(syncOutbox)..where((o) {
                final keyed =
                    o.syncedTable.equals(table) & o.rowKey.isIn(chunk);
                return unpushedOnly ? keyed & o.republish.equals(false) : keyed;
              }))
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

  /// The queued entries, of [table] alone when given — the notes a
  /// cutover's drain says it is sending, apart from their chunks.
  Future<int> count({String? table}) async {
    final countExpr = syncOutbox.rowKey.count();
    final query = selectOnly(syncOutbox)..addColumns([countExpr]);
    if (table != null) query.where(syncOutbox.syncedTable.equals(table));
    final row = await query.getSingle();
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

  /// [ackThrough] for a merge whose newer remote overwrites the row: retires
  /// the entry the same way and returns whether it stood for a write this
  /// device had not pushed — false for none, and for an entry that only
  /// re-sent a version the space holds ([SyncOutbox.republish]), whose
  /// overwrite loses no text. One statement, so the answer is the entry the
  /// delete took.
  Future<bool> ackUnpushedThrough(
    String table,
    String rowKey,
    String hlc,
  ) async {
    final retired = await customWriteReturning(
      'DELETE FROM sync_outbox '
      'WHERE table_name = ? AND row_key = ? AND hlc <= ? RETURNING republish',
      variables: [
        Variable<String>(table),
        Variable<String>(rowKey),
        Variable<String>(hlc),
      ],
      updates: {syncOutbox},
      updateKind: UpdateKind.delete,
    );
    return retired.any((row) => row.read<int>('republish') == 0);
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
  ///
  /// Each entry written is a republish ([SyncOutbox.republish]): the version
  /// it sends is the space's already, so a newer remote that overwrites it
  /// in the re-read that follows files no copy — `note_seen` alone cannot
  /// say so for a device upgrading from a build that never recorded it, nor
  /// for a note this device wrote. An entry already queued at the row's
  /// stamp is an edit not pushed yet and is left as it is.
  Future<int> requeueBodies({required String boundUid}) {
    final notes = syncedTables.singleWhere((t) => t.name == 'notes');
    final chunks = syncedTables.singleWhere((t) => t.contentAddressed);
    return transaction(() async {
      return await _requeue(
            notes,
            boundUid,
            rows: 'is_deleted = 0',
            kind: UpdateKind.update,
            republish: true,
          ) +
          await _requeue(
            chunks,
            boundUid,
            kind: UpdateKind.update,
            republish: true,
          );
    });
  }

  /// [requeueAll]'s statement for one table, narrowed to [rows], announced
  /// to the outbox's watchers as [kind], its entries marked [republish].
  ///
  /// An entry raised keeps a real edit's mark: a re-queue never turns an
  /// entry that stood for an unpushed write into a republish, where the
  /// wrong answer would drop a text rather than file a copy too many. For
  /// the same reason a plain re-queue clears a republish at an equal stamp.
  Future<int> _requeue(
    SyncedTable table,
    String boundUid, {
    String rows = '1 = 1',
    UpdateKind kind = UpdateKind.insert,
    bool republish = false,
  }) {
    return customUpdate(
      'INSERT INTO sync_outbox '
      '(table_name, row_key, hlc, op, enqueued_at, republish) '
      "SELECT '${table.name}', ${table.rowKeySql}, hlc_timestamp, "
      "CASE is_deleted WHEN 1 THEN 'tombstone' ELSE 'upsert' END, ?, "
      '${republish ? 1 : 0} '
      'FROM ${table.name} WHERE ${table.queuedRowsSql} AND $rows '
      'ON CONFLICT (table_name, row_key) DO UPDATE SET '
      'hlc = excluded.hlc, op = excluded.op, '
      'republish = MIN(sync_outbox.republish, excluded.republish) '
      'WHERE excluded.hlc > sync_outbox.hlc OR (excluded.hlc = '
      'sync_outbox.hlc AND excluded.republish < sync_outbox.republish)',
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
  ///
  /// [republish]: the space holds this very version, only in a shape it is
  /// sent again to replace ([SyncOutbox.republish]); raised over an existing
  /// entry it keeps a real edit's mark, as [requeueBodies] does. A plain
  /// re-queue clears the mark even at the entry's own stamp: the local row
  /// beat the remote, so the space no longer holds this version.
  Future<bool> requeueRow(
    String table,
    String rowKey, {
    bool republish = false,
  }) async {
    final synced = syncedTables.where((t) => t.name == table).firstOrNull;
    if (synced == null || synced.contentAddressed) {
      throw ArgumentError.value(table, 'table', 'not re-queued by a merge');
    }
    final written = await customUpdate(
      'INSERT INTO sync_outbox '
      '(table_name, row_key, hlc, op, enqueued_at, republish) '
      "SELECT '${synced.name}', ${synced.rowKeySql}, hlc_timestamp, "
      "CASE is_deleted WHEN 1 THEN 'tombstone' ELSE 'upsert' END, ?, "
      '${republish ? 1 : 0} '
      'FROM ${synced.name} WHERE ${synced.rowKeySql} = ? '
      'ON CONFLICT (table_name, row_key) DO UPDATE SET '
      'hlc = excluded.hlc, op = excluded.op, '
      'republish = MIN(sync_outbox.republish, excluded.republish) '
      'WHERE excluded.hlc > sync_outbox.hlc OR (excluded.hlc = '
      'sync_outbox.hlc AND excluded.republish < sync_outbox.republish)',
      variables: [Variable<DateTime>(DateTime.now()), Variable<String>(rowKey)],
      updates: {syncOutbox},
      updateKind: UpdateKind.insert,
    );
    return written > 0;
  }

  /// Queues again, at the stamps they carry, the rows of [table] that the SQL
  /// condition [rows] selects — [requeueRow] for a set, tombstones included
  /// — and returns how many entries were written or raised. Its numbered
  /// parameters start at `?2`, bound from [variables] in order: `?1` is the
  /// statement's own.
  ///
  /// For the rows whose documents say something their own columns do not —
  /// who may read them, which a day row takes from its event and a folder
  /// or a note from the folder above it
  /// (`docs/cloud-sharing-foundations.md` §3): a change of that root is no
  /// write of theirs, so nothing else would push them again. Mints nothing
  /// and never lowers an entry pending at a newer stamp. Never a
  /// content-addressed table; [rows] has to leave out what another account
  /// shares with this one (`SyncDao.mineSql`).
  ///
  /// Each entry written is a republish ([SyncOutbox.republish]): the space
  /// holds this very version of the row, and only what its document says
  /// beside the row is sent again — so a newer remote that overwrites the
  /// row before the push loses no text, and files no copy of it. An entry
  /// already standing for an unpushed write keeps saying so.
  ///
  /// [unpushed] writes them as entries of a write the space never saw
  /// instead: for rows that were never uploaded at all, where a newer
  /// remote under the same key is a conflict like any other.
  Future<int> requeueRows(
    String table, {
    required String rows,
    List<Variable<Object>> variables = const [],
    bool unpushed = false,
  }) {
    final synced = syncedTables.where((t) => t.name == table).firstOrNull;
    if (synced == null || synced.contentAddressed) {
      throw ArgumentError.value(table, 'table', 'not re-queued as a set');
    }
    return customUpdate(
      'INSERT INTO sync_outbox '
      '(table_name, row_key, hlc, op, enqueued_at, republish) '
      "SELECT '${synced.name}', ${synced.rowKeySql}, hlc_timestamp, "
      "CASE is_deleted WHEN 1 THEN 'tombstone' ELSE 'upsert' END, ?1, "
      '${unpushed ? 0 : 1} '
      'FROM ${synced.name} WHERE $rows '
      'ON CONFLICT (table_name, row_key) DO UPDATE SET '
      'hlc = excluded.hlc, op = excluded.op, '
      'republish = MIN(sync_outbox.republish, excluded.republish) '
      'WHERE excluded.hlc > sync_outbox.hlc OR (excluded.hlc = '
      'sync_outbox.hlc AND excluded.republish < sync_outbox.republish)',
      variables: [Variable<DateTime>(DateTime.now()), ...variables],
      updates: {syncOutbox},
      updateKind: UpdateKind.insert,
    );
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
