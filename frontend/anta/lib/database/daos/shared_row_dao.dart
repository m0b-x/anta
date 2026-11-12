import 'package:drift/drift.dart';

import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/synced_tables.dart';
import '../database.dart';
import '../tables/calendar_events_table.dart';
import '../tables/content_chunks_table.dart';
import '../tables/event_occurrences_table.dart';
import '../tables/event_skips_table.dart';
import '../tables/folders_table.dart';
import '../tables/notes_table.dart';
import '../tables/sync_metadata_table.dart';
import 'sync_dao.dart';

part 'shared_row_dao.g.dart';

/// The rows another account shares with the one this database syncs for
/// (`docs/cloud-sharing-foundations.md` §5–§7): a cache of a live grant,
/// held in the same tables as the person's own and told from them by
/// `owner_id` alone — the account [SyncDao.keySharedOwner] names. They
/// arrive only through the shared reader, are never pushed, and are removed
/// — hard, no tombstone — when the grant ends.
///
/// Nothing here stamps or queues a shared row: it is the owner's, and this
/// device's copy of it follows the owner's.
@DriftAccessor(
  tables: [
    CalendarEvents,
    EventOccurrenceDescriptions,
    EventSkips,
    Folders,
    Notes,
    ContentChunks,
    SyncMetadata,
  ],
)
class SharedRowDao extends DatabaseAccessor<AppDatabase>
    with _$SharedRowDaoMixin {
  SharedRowDao(super.db);

  /// The account whose shared rows this database holds, or null for none.
  Future<String?> owner() => db.syncDao.getValue(SyncDao.keySharedOwner);

  /// Makes [owner] the account this database reads shared rows from, under
  /// [pair], in one transaction — before the first of its rows is stored.
  ///
  /// From here on a row with another `owner_id` than [boundUid] is that
  /// account's, read-only and removable. So every row that carries one
  /// today is first made [boundUid]'s and queued: such a row is the
  /// person's own, left under an account that bound this database before a
  /// build released its rows at an unbind (cloud-multi-user-roadmap §6.1 f),
  /// and it was never uploaded. Were that earlier account the partner now —
  /// one person's two accounts, paired — the first read that found it
  /// missing from the share would remove it.
  Future<void> begin({
    required String owner,
    required String pair,
    required String boundUid,
  }) {
    return transaction(() async {
      for (final synced in syncedTables) {
        if (synced.contentAddressed) continue;
        final table = _tableOf(synced.name);
        // Queued first, while the rows can still be told from the rest. How
        // many entries that wrote says nothing about how many rows there
        // are — one already queued at its stamp writes none — so the rows
        // are adopted whatever it answers.
        await db.requeueRows(
          table,
          rows: 'owner_id IS NOT NULL AND owner_id != ?2',
          variables: [Variable<String>(boundUid)],
        );
        await customUpdate(
          'UPDATE ${synced.name} SET owner_id = ?1 '
          'WHERE owner_id IS NOT NULL AND owner_id != ?1',
          variables: [Variable<String>(boundUid)],
          updates: {table},
          updateKind: UpdateKind.update,
        );
      }
      await db.syncDao.setValue(SyncDao.keySharedOwner, owner);
      await db.syncDao.setValue(SyncDao.keySharedPair, pair);
    });
  }

  /// Whether this database holds a row of [table] — an event, a folder or a
  /// note — under [id] that [owner] does not own: the person's own, most
  /// often. Two accounts can hold one id — both restored one backup, or one
  /// copied a row it was once given — and a shared row must then stand
  /// back: taking the place of that row, or hanging under it, would hand
  /// the person's own data to the next "no longer shared".
  Future<bool> holdsOther(String table, String id, String owner) async {
    final synced = _shared(table);
    final row = await customSelect(
      'SELECT EXISTS(SELECT 1 FROM ${synced.name} '
      'WHERE id = ?1 AND owner_id IS NOT ?2) AS held',
      variables: [Variable<String>(id), Variable<String>(owner)],
      readsFrom: {_tableOf(table)},
    ).getSingle();
    return row.read<bool>('held');
  }

  /// How many rows of [table] this database holds of [owner]'s, tombstones
  /// included: what the server's count of the same share is compared with.
  Future<int> countOf(String table, String owner) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM ${_shared(table).name} WHERE owner_id = ?',
      variables: [Variable<String>(owner)],
      readsFrom: {_tableOf(table)},
    ).getSingle();
    return row.read<int>('c');
  }

  /// Removes the rows of [table] this database holds of [owner]'s whose key
  /// is not among [kept] — the keys a read of the whole share just returned
  /// — and returns the keys removed. A removed note's text goes with it;
  /// what the person added of their own to a removed row (presence marks,
  /// alerts, counter values) is theirs and stays.
  Future<List<String>> removeAbsent(
    String table,
    String owner,
    Set<String> kept,
  ) {
    return transaction(() async {
      final synced = _shared(table);
      final held = await customSelect(
        'SELECT ${synced.rowKeySql} AS k FROM ${synced.name} '
        'WHERE owner_id = ?',
        variables: [Variable<String>(owner)],
        readsFrom: {_tableOf(table)},
      ).get();
      final absent = [
        for (final row in held)
          if (!kept.contains(row.read<String>('k'))) row.read<String>('k'),
      ];
      await _remove(synced, owner, absent);
      if (table == 'folders' && absent.isNotEmpty) await placeFolders(owner);
      return absent;
    });
  }

  /// Removes every row this database holds of the account it reads shared
  /// rows from, with everything the reader stored about them, and returns
  /// the keys removed by table — empty when it held none. The grant ended:
  /// the pair did, another partner took its place, or this database stopped
  /// syncing and nothing would keep the rows true.
  Future<Map<String, List<String>>> removeAll() {
    return transaction(() async {
      final owner = await this.owner();
      final removed = <String, List<String>>{};
      if (owner != null) {
        for (final table in sharedTables.reversed) {
          final gone = await removeAbsent(table, owner, const {});
          if (gone.isNotEmpty) removed[table] = gone;
        }
      }
      final dao = db.syncDao;
      await dao.deleteValue(SyncDao.keySharedOwner);
      await dao.deleteValue(SyncDao.keySharedPair);
      await dao.deleteValue(SyncDao.keySharedReadAt);
      await dao.deleteValue(SyncDao.keySharedFullAt);
      await dao.deleteValue(SyncDao.keySharedNewerWire);
      await dao.deleteByPrefix(SyncDao.sharedCursorPrefix);
      await dao.deleteByPrefix(SyncDao.sharedRetryPrefix);
      await dao.deleteByPrefix(SyncDao.sharedRootPrefix);
      return removed;
    });
  }

  /// Keeps every folder of [owner]'s reachable in the browser, whose top
  /// level is `parent_id IS NULL`: a shared folder whose parent was not
  /// shared stands at the top level here, and goes back under that parent
  /// once it arrives. Returns the folders it moved.
  ///
  /// The parent the wire names is kept under [SyncDao.keySharedRoot] while
  /// the folder stands at the top: the merge restores it on the row with
  /// every change of the folder, and an unchanged folder is merged as
  /// unchanged, so nothing else would remember where it belongs once its
  /// parent is shared too. Never stamped or queued — the difference from
  /// the owner's document is this device's own.
  Future<List<String>> placeFolders(String owner) {
    return transaction(() async {
      final dao = db.syncDao;
      final moved = <String>[];
      for (final (key, parent) in await dao.valuesByPrefix(
        SyncDao.sharedRootPrefix,
      )) {
        final id = key.substring(SyncDao.sharedRootPrefix.length);
        final rows = await customSelect(
          'SELECT f.parent_id AS parent, EXISTS(SELECT 1 FROM folders p '
          'WHERE p.id = ?2 AND p.owner_id = ?3) AS arrived '
          'FROM folders f WHERE f.id = ?1 AND f.owner_id = ?3',
          variables: [
            Variable<String>(id),
            Variable<String>(parent),
            Variable<String>(owner),
          ],
          readsFrom: {folders},
        ).get();
        final row = rows.firstOrNull;
        // Gone, or merged since under a parent of its own: the note of where
        // it belonged is spent either way.
        if (row == null || row.read<String?>('parent') != null) {
          await dao.deleteValue(key);
        } else if (row.read<bool>('arrived')) {
          await _setParent(id, parent);
          await dao.deleteValue(key);
          moved.add(id);
        }
      }
      final orphans = await customSelect(
        'SELECT f.id AS id, f.parent_id AS parent FROM folders f '
        'WHERE f.owner_id = ?1 AND f.parent_id IS NOT NULL AND NOT EXISTS '
        '(SELECT 1 FROM folders p WHERE p.id = f.parent_id '
        'AND p.owner_id = ?1)',
        variables: [Variable<String>(owner)],
        readsFrom: {folders},
      ).get();
      for (final row in orphans) {
        final id = row.read<String>('id');
        await dao.setValue(
          SyncDao.keySharedRoot(id),
          row.read<String>('parent'),
        );
        await _setParent(id, null);
        moved.add(id);
      }
      return moved;
    });
  }

  Future<void> _setParent(String id, String? parent) {
    return (update(folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(parentId: Value(parent)),
    );
  }

  /// Hard-deletes the rows of [synced] under [keys] that [owner] owns, a
  /// note's chunk rows with it. The owner is part of every statement: a key
  /// alone must never reach a row of the person's own.
  Future<void> _remove(
    SyncedTable synced,
    String owner,
    List<String> keys,
  ) async {
    if (keys.isEmpty) return;
    final table = _tableOf(synced.name);
    for (var at = 0; at < keys.length; at += CrdtMerge.keysPerStatement) {
      final chunk = keys.skip(at).take(CrdtMerge.keysPerStatement).toList();
      if (synced.name == 'notes') {
        await db.contentChunkDao.deleteChunksForNotes(chunk);
      }
      await customUpdate(
        'DELETE FROM ${synced.name} WHERE owner_id = ? AND '
        '${synced.rowKeySql} IN (${List.filled(chunk.length, '?').join(', ')})',
        variables: [
          Variable<String>(owner),
          for (final key in chunk) Variable<String>(key),
        ],
        updates: {table},
        updateKind: UpdateKind.delete,
      );
    }
  }

  /// [table] as a table that can be shared; anything else is a programming
  /// error, since a row of another table is never another account's.
  static SyncedTable _shared(String table) {
    if (!sharedTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not a shareable table');
    }
    return syncedTables.singleWhere((synced) => synced.name == table);
  }

  TableInfo<Table, Object?> _tableOf(String name) =>
      db.allTables.firstWhere((table) => table.actualTableName == name);
}
