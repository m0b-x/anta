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

/// A write named a row another account shares with this one, where doing
/// nothing — what the fences do for every other write of such a row — would
/// have answered with a row that was never stored.
final class SharedRowException implements Exception {
  final String table;
  final String id;

  const SharedRowException(this.table, this.id);

  @override
  String toString() => 'SharedRowException: $table/$id is shared, read-only';
}

/// A shared row that was removed here, and where it stood — the folder a
/// note lay in, a folder's parent (null at the top level), null for every
/// other table: what a screen needs to drop a row it can no longer read.
typedef SharedRemoval = ({String key, String? parent});

/// What a removal of shared rows did, for the screens to follow: the rows
/// that went, by table, and the shared folders left without their parent,
/// which now stand at the top level.
class SharedRemovals {
  const SharedRemovals(this.gone, this.placed);

  static const SharedRemovals none = SharedRemovals({}, []);

  final Map<String, List<SharedRemoval>> gone;
  final List<String> placed;

  bool get isEmpty =>
      placed.isEmpty && gone.values.every((rows) => rows.isEmpty);

  /// The keys removed from [table].
  List<String> keysOf(String table) => [
    for (final row in gone[table] ?? const <SharedRemoval>[]) row.key,
  ];
}

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

  /// Runs [body] in a transaction that may store, change and remove shared
  /// rows — the reader's, and nothing else's: everything outside one is
  /// stopped by the fences (`SharedRowFences`), which stand down while
  /// [SyncDao.keySharedWriting] is present. The key is set and taken away
  /// inside the transaction, so no other one ever sees it, and a rollback
  /// takes it along. Nests: an inner call leaves the key to the outermost.
  Future<T> writing<T>(Future<T> Function() body) {
    return transaction(() async {
      final dao = db.syncDao;
      if (await dao.getValue(SyncDao.keySharedWriting) != null) return body();
      await dao.setValue(SyncDao.keySharedWriting, '1');
      final T result;
      try {
        result = await body();
      } catch (_) {
        // The rollback takes the key along; taking it out here as well is
        // for a caller that catches inside an outer transaction, and must
        // not put its own failure — the transaction may be past writing —
        // in the place of the body's.
        try {
          await dao.deleteValue(SyncDao.keySharedWriting);
        } catch (_) {}
        rethrow;
      }
      // Not swallowed: a commit with the key still present would leave the
      // fences down for good.
      await dao.deleteValue(SyncDao.keySharedWriting);
      return result;
    });
  }

  /// Whether the row of [table] under [id] — an event, a folder or a note —
  /// is one another account shares with this one: what a surface asks
  /// before it offers an edit, since a write of such a row does nothing
  /// (`SharedRowFences`).
  Future<bool> isShared(String table, String id) async {
    final synced = _shared(table);
    final row = await customSelect(
      'SELECT EXISTS(SELECT 1 FROM ${synced.name} WHERE id = ?1 '
      'AND owner_id = (SELECT value FROM sync_metadata WHERE key = ?2)) '
      'AS shared',
      variables: [
        Variable<String>(id),
        Variable<String>(SyncDao.keySharedOwner),
      ],
      readsFrom: {_tableOf(table), syncMetadata},
    ).getSingle();
    return row.read<bool>('shared');
  }

  /// Throws [SharedRowException] when [id] names a shared row of [table] —
  /// for the two writes that would otherwise answer with a row the fences
  /// never let be stored: a note or a folder created inside a shared
  /// folder.
  Future<void> ensureOwn(String table, String id) async {
    if (await isShared(table, id)) throw SharedRowException(table, id);
  }

  /// [ensureOwn] for a row its caller has already read, [ownerId] being that
  /// row's — for the writers whose answer would otherwise be a lie: a save
  /// or a move the fences turned into nothing would still stamp, queue and
  /// hand back a note as if it were stored, and an editor would believe its
  /// text was saved. No statement for a row that names no owner, which is
  /// every row written since the bind.
  Future<void> ensureOwnRow(String table, String id, String? ownerId) async {
    if (ownerId != null && ownerId == await owner()) {
      throw SharedRowException(table, id);
    }
  }

  /// Whether the category under [id] (an SQL expression) is one another
  /// account shares with this one, as a column of a writer's own read of
  /// its row: an event or a template of the person's own saved into such a
  /// category is skipped by the fences while the writer would stamp, queue
  /// and answer "saved", so the writer asks first and throws
  /// [SharedRowException] — at no statement of its own. `=` rather than
  /// `IS`: with no shared account the comparison is NULL, never a match on
  /// a category of the person's own that names no owner.
  static String partnersCategorySql(String id) =>
      'EXISTS(SELECT 1 FROM calendar_categories theirs WHERE theirs.id = $id '
      'AND theirs.owner_id = (SELECT value FROM sync_metadata '
      "WHERE key = '${SyncDao.keySharedOwner}'))";

  /// The keys among [keys] under which this database holds a shared row of
  /// [table] — asked by the account's own pull before it merges a page, so
  /// a row of its own space is never kept out by a shared row that took its
  /// id first ([evict]). No statement past the first for a database that
  /// reads no shared rows.
  Future<List<String>> sharedAmong(String table, List<String> keys) async {
    if (keys.isEmpty) return const [];
    final owner = await this.owner();
    if (owner == null) return const [];
    return _sharedOf(table, owner, keys);
  }

  Future<List<String>> _sharedOf(
    String table,
    String owner,
    List<String> keys,
  ) async {
    final synced = _shared(table);
    final taken = await CrdtMerge.loadInChunks(keys, (chunk) async {
      final rows = await customSelect(
        'SELECT ${synced.rowKeySql} AS k FROM ${synced.name} '
        'WHERE owner_id = ? AND ${synced.rowKeySql} IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [
          Variable<String>(owner),
          for (final key in chunk) Variable<String>(key),
        ],
        readsFrom: {_tableOf(table)},
      ).get();
      return [for (final row in rows) row.read<String>('k')];
    });
    return taken;
  }

  /// The keys among [keys] under which [table] holds no row at all,
  /// whoever's: asked after a page for which shared rows gave way, to see
  /// which of the person's own rows did not land in their place.
  Future<List<String>> absentAmong(String table, List<String> keys) async {
    if (keys.isEmpty) return const [];
    final synced = _shared(table);
    final present = (await CrdtMerge.loadInChunks(keys, (chunk) async {
      final rows = await customSelect(
        'SELECT ${synced.rowKeySql} AS k FROM ${synced.name} '
        'WHERE ${synced.rowKeySql} IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final key in chunk) Variable<String>(key)],
        readsFrom: {_tableOf(table)},
      ).get();
      return [for (final row in rows) row.read<String>('k')];
    })).toSet();
    return [
      for (final key in keys)
        if (!present.contains(key)) key,
    ];
  }

  /// Removes the shared rows of [table] under [keys]: a row of this
  /// account's own is about to take the same id — it arrived from the
  /// account's space, or an import carries it — and the person's own data
  /// comes first. The shared one is then simply not shown, as when the own
  /// row was here first (`SharedRowRefused`).
  ///
  /// What hung under a removed row goes with it — an event's shared day
  /// rows, the shared notes directly inside a folder: under a row that is
  /// the person's own now they are what the reader refuses to store, and a
  /// partner's skipped day would show on the person's own event. A shared
  /// folder under a removed one is still shared, and stands at the top
  /// level ([placeFolders]).
  ///
  /// The same call makes room under a parent: a note, a folder or a day row
  /// of the person's own that names a folder or an event held here as
  /// shared says that id is theirs, and nothing of theirs is stored under a
  /// shared row (`SharedRowFences`) — so the caller evicts the parent's key
  /// from the parent's table first.
  ///
  /// One statement, the read of whose rows are shared, for a database that
  /// holds none; nothing at all for no keys.
  Future<SharedRemovals> evict(String table, List<String> keys) async {
    if (keys.isEmpty) return SharedRemovals.none;
    final owner = await this.owner();
    if (owner == null) return SharedRemovals.none;
    final taken = await _sharedOf(table, owner, keys);
    if (taken.isEmpty) return SharedRemovals.none;
    return writing(() async {
      final gone = <String, List<SharedRemoval>>{
        table: await _remove(_shared(table), owner, taken),
      };
      var placed = const <String>[];
      switch (table) {
        case 'calendar_events':
          for (final days in const [
            'calendar_event_occurrences',
            'calendar_event_skips',
          ]) {
            gone[days] = await _remove(
              _shared(days),
              owner,
              await _under(days, 'event_id', owner, taken),
            );
          }
        case 'folders':
          gone['notes'] = await _remove(
            _shared('notes'),
            owner,
            await _under('notes', 'folder_id', owner, taken),
          );
          placed = await placeFolders(owner);
      }
      return SharedRemovals(gone, placed);
    });
  }

  /// The keys of the rows of [table] that [owner] owns and whose [column]
  /// names one of [parents].
  Future<List<String>> _under(
    String table,
    String column,
    String owner,
    List<String> parents,
  ) {
    final synced = _shared(table);
    return CrdtMerge.loadInChunks(parents, (chunk) async {
      final rows = await customSelect(
        'SELECT ${synced.rowKeySql} AS k FROM ${synced.name} '
        'WHERE owner_id = ? AND $column IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [
          Variable<String>(owner),
          for (final parent in chunk) Variable<String>(parent),
        ],
        readsFrom: {_tableOf(table)},
      ).get();
      return [for (final row in rows) row.read<String>('k')];
    });
  }

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
        // Queued first, while the rows can still be told from the rest, and
        // as writes the space never saw — which they are: a re-send would
        // let a newer document under the same key replace one unseen. How
        // many entries that wrote says nothing about how many rows there
        // are — one already queued at its stamp writes none — so the rows
        // are adopted whatever it answers.
        await db.requeueRows(
          table,
          rows: 'owner_id IS NOT NULL AND owner_id != ?2',
          variables: [Variable<String>(boundUid)],
          unpushed: true,
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
  ///
  /// A category id is the person's by use as well: an event or a template
  /// of theirs that names it — a category deleted long ago, or one restored
  /// from a backup the partner restored too — would draw as the partner's,
  /// leave the .ics export, and be held back at its next version from the
  /// person's own space. Tombstones count, here as for the row itself: a
  /// stored partner's tombstone would fence the id as a live one does. Still
  /// one statement, and only for a category document.
  Future<bool> holdsOther(String table, String id, String owner) async {
    final synced = _shared(table);
    final byUse = table == 'calendar_categories'
        ? ' OR EXISTS(SELECT 1 FROM calendar_events '
              'WHERE category = ?1 AND owner_id IS NOT ?2) '
              'OR EXISTS(SELECT 1 FROM calendar_event_templates '
              'WHERE category = ?1 AND owner_id IS NOT ?2)'
        : '';
    final row = await customSelect(
      'SELECT EXISTS(SELECT 1 FROM ${synced.name} '
      'WHERE id = ?1 AND owner_id IS NOT ?2)$byUse AS held',
      variables: [Variable<String>(id), Variable<String>(owner)],
      readsFrom: {
        _tableOf(table),
        if (byUse.isNotEmpty) ...[calendarEvents, db.eventTemplates],
      },
    ).getSingle();
    return row.read<bool>('held');
  }

  /// How many rows of [table] this database holds of [owner]'s, tombstones
  /// included, and how many of the partner's documents it knows it does not
  /// store ([recorded]): what the server's count of the same share is
  /// compared with. Counting the recorded ones is what lets a refused
  /// document's leave be found as a stored row's is.
  Future<int> countOf(String table, String owner) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM ${_shared(table).name} WHERE owner_id = ?',
      variables: [Variable<String>(owner)],
      readsFrom: {_tableOf(table)},
    ).getSingle();
    return row.read<int>('c') + (await recorded(table)).length;
  }

  /// The value of a record ([SyncDao.keySharedRefused],
  /// [SyncDao.keySharedBuiltIn]) of a live document.
  static const String _liveRecord = '1';

  /// The value of a record of a document that is a tombstone.
  static const String _tombstoneRecord = '0';

  /// The tables whose rows a person would name — "{n} items could not be
  /// shown" counts their refused documents alone. An event's day rows are
  /// refused with their event, and counting them would read fifty-one for
  /// one event with fifty skipped days.
  static const Set<String> _namedTables = {
    'calendar_categories',
    'calendar_events',
    'folders',
    'notes',
  };

  /// The keys of [table]'s shared documents this database knows of and does
  /// not store, tombstones included: refused for a row of the person's own
  /// ([SyncDao.keySharedRefused]), and for `calendar_categories` the
  /// built-ins the partner shares ([SyncDao.keySharedBuiltIn]). One read.
  Future<Set<String>> recorded(String table) async {
    final refused = SyncDao.keySharedRefused(table, '');
    const builtIn = SyncDao.sharedBuiltInPrefix;
    return {
      for (final (key, _) in await db.syncDao.valuesByPrefixes([
        refused,
        if (table == 'calendar_categories') builtIn,
      ]))
        key.startsWith(refused)
            ? key.substring(refused.length)
            : key.substring(builtIn.length),
    };
  }

  /// Records what became of the partner's document [rowKey] of [table] that
  /// was refused — apart, when it is a built-in category ([builtIn]). A live
  /// one is not shown, and is counted. A tombstone is nothing to show, and
  /// is still recorded: the server's count of the share holds its document,
  /// and forgetting it here would let it mask a later leave ([countOf]).
  Future<void> noteRefused(
    String table,
    String rowKey, {
    required bool live,
    bool builtIn = false,
  }) async {
    await db.syncDao.setValue(
      builtIn
          ? SyncDao.keySharedBuiltIn(rowKey)
          : SyncDao.keySharedRefused(table, rowKey),
      live ? _liveRecord : _tombstoneRecord,
    );
  }

  /// Forgets that the documents [rowKeys] of [table] were refused: they are
  /// stored now. Nothing for no keys; else one delete per
  /// [CrdtMerge.keysPerStatement] keys and no read, so the records are read
  /// once per table in a shared read — by [countOf] — however many pages
  /// it stored.
  Future<void> noteStored(String table, Iterable<String> rowKeys) async {
    final keys = [
      for (final rowKey in rowKeys) SyncDao.keySharedRefused(table, rowKey),
    ];
    for (var at = 0; at < keys.length; at += CrdtMerge.keysPerStatement) {
      final chunk = keys.skip(at).take(CrdtMerge.keysPerStatement).toList();
      await (delete(syncMetadata)..where((s) => s.key.isIn(chunk))).go();
    }
  }

  /// How many of the partner's live documents are not shown here because a
  /// row of the person's own holds their id — "{n} items could not be
  /// shown": categories, events, folders and notes ([_namedTables]). A
  /// built-in category is never one of them: it is shown, as the person's
  /// own.
  Future<int> refusedCount() async {
    const prefix = SyncDao.sharedRefusedPrefix;
    var count = 0;
    for (final (key, value) in await db.syncDao.valuesByPrefix(prefix)) {
      final table = key.substring(prefix.length, key.indexOf('|'));
      if (value == _liveRecord && _namedTables.contains(table)) count++;
    }
    return count;
  }

  /// The built-in categories the partner shares, by id: never stored here,
  /// since the person's own row under each draws the partner's events too.
  /// A built-in's tombstone is no category received.
  Future<Set<String>> sharedBuiltIns() async => {
    for (final (key, value) in await db.syncDao.valuesByPrefix(
      SyncDao.sharedBuiltInPrefix,
    ))
      if (value == _liveRecord)
        key.substring(SyncDao.sharedBuiltInPrefix.length),
  };

  /// Removes the rows of [table] this database holds of [owner]'s whose key
  /// is not among [kept] — the keys a read of the whole share just returned
  /// — and says what it removed. A removed note's text goes with it; what
  /// the person added of their own to a removed row (presence marks,
  /// alerts, counter values) is theirs and stays.
  ///
  /// So does a category alert or a category profile of the person's own on
  /// a removed partner's category: stored, still synced in their own space,
  /// and inert while no category draws under that id — exactly as their
  /// alerts on a shared event that left. Nothing lists it meanwhile (the
  /// Alerts hub lists armed entries alone), and it applies again if that
  /// category is shared again.
  Future<SharedRemovals> removeAbsent(
    String table,
    String owner,
    Set<String> kept,
  ) {
    return writing(() async {
      final synced = _shared(table);
      for (final key in await recorded(table)) {
        if (kept.contains(key)) continue;
        await db.syncDao.deleteValue(SyncDao.keySharedRefused(table, key));
        if (table == 'calendar_categories') {
          await db.syncDao.deleteValue(SyncDao.keySharedBuiltIn(key));
        }
      }
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
      if (absent.isEmpty) return SharedRemovals.none;
      final gone = await _remove(synced, owner, absent);
      return SharedRemovals({
        table: gone,
      }, table == 'folders' ? await placeFolders(owner) : const []);
    });
  }

  /// Removes every row this database holds of the account it reads shared
  /// rows from, with everything the reader stored about them, and says what
  /// it removed — nothing when it held none. The grant ended: the pair did,
  /// another partner took its place, or this database stopped syncing and
  /// nothing would keep the rows true. What the person keeps of their own
  /// on those rows stays, as [removeAbsent] says.
  Future<SharedRemovals> removeAll() {
    return writing(() async {
      final owner = await this.owner();
      final removed = <String, List<SharedRemoval>>{};
      if (owner != null) {
        for (final table in sharedTables.reversed) {
          final gone = (await removeAbsent(table, owner, const {})).gone[table];
          if (gone != null && gone.isNotEmpty) removed[table] = gone;
        }
      }
      final dao = db.syncDao;
      await dao.deleteValue(SyncDao.keySharedOwner);
      await dao.deleteValue(SyncDao.keySharedPair);
      await dao.deleteValue(SyncDao.keySharedReadAt);
      await dao.deleteValue(SyncDao.keySharedFullAt);
      await dao.deleteValue(SyncDao.keySharedNewerWire);
      await dao.deleteByPrefix(SyncDao.sharedCursorPrefix);
      await dao.deleteByPrefix(SyncDao.sharedWaitingPrefix);
      await dao.deleteByPrefix(SyncDao.sharedRootPrefix);
      await dao.deleteByPrefix(SyncDao.sharedRefusedPrefix);
      await dao.deleteByPrefix(SyncDao.sharedBuiltInPrefix);
      // Every shared folder went, so none was left to place.
      return SharedRemovals(removed, const []);
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
    return writing(() async {
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
  /// note's chunk rows with it, and says what went. The owner is part of
  /// every statement: a key alone must never reach a row of the person's
  /// own. A folder and a note are read first for where they stood, which
  /// nothing can ask once they are gone.
  Future<List<SharedRemoval>> _remove(
    SyncedTable synced,
    String owner,
    List<String> keys,
  ) async {
    if (keys.isEmpty) return const [];
    final table = _tableOf(synced.name);
    final parent = switch (synced.name) {
      'notes' => 'folder_id',
      'folders' => 'parent_id',
      _ => null,
    };
    final gone = <SharedRemoval>[];
    for (var at = 0; at < keys.length; at += CrdtMerge.keysPerStatement) {
      final chunk = keys.skip(at).take(CrdtMerge.keysPerStatement).toList();
      final places = List.filled(chunk.length, '?').join(', ');
      if (parent == null) {
        gone.addAll([for (final key in chunk) (key: key, parent: null)]);
      } else {
        final theirs = await customSelect(
          'SELECT id, $parent AS parent FROM ${synced.name} '
          'WHERE owner_id = ? AND id IN ($places)',
          variables: [
            Variable<String>(owner),
            for (final key in chunk) Variable<String>(key),
          ],
          readsFrom: {table},
        ).get();
        gone.addAll([
          for (final row in theirs)
            (key: row.read<String>('id'), parent: row.read<String?>('parent')),
        ]);
        if (synced.name == 'notes') {
          // A chunk row carries no owner of its own, so only the notes just
          // read as the owner's lose theirs: a key that names a note of the
          // person's own must not cost it its text.
          await db.contentChunkDao.deleteChunksForNotes([
            for (final row in theirs) row.read<String>('id'),
          ]);
        }
      }
      await customUpdate(
        'DELETE FROM ${synced.name} WHERE owner_id = ? AND '
        '${synced.rowKeySql} IN ($places)',
        variables: [
          Variable<String>(owner),
          for (final key in chunk) Variable<String>(key),
        ],
        updates: {table},
        updateKind: UpdateKind.delete,
      );
    }
    return gone;
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
