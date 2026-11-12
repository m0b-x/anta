import 'package:drift/drift.dart';
import '../crdt/crdt_merge.dart';
import '../database.dart';
import '../tables/sync_metadata_table.dart';

part 'sync_dao.g.dart';

@DriftAccessor(tables: [SyncMetadata])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  static const String keyLastSyncTimestamp = 'last_sync_timestamp';
  static const String keyDeviceId = 'device_id';
  static const String keyLastFolderHlc = 'last_folder_hlc';
  static const String keyLastNoteHlc = 'last_note_hlc';
  static const String keyLastChunkHlc = 'last_chunk_hlc';

  /// The highest HLC this database has issued, which seeds the clock at the
  /// next open. Written only by `CrdtWrite`, never through [setValue]: it may
  /// only move forward.
  static const String keyLastHlc = 'last_hlc';

  /// The clock of this database when it was last unbound, or when a
  /// never-bound database binds: at the initial merge a row present on both
  /// sides takes the space's copy when its local HLC is at or below it (D15).
  static const String keyBindFloor = 'bind_floor';

  /// When the last push was acknowledged, as epoch milliseconds.
  static const String keyLastPushAt = 'last_push_at';

  /// `'1'` from a bind until the engine's first complete pull of every
  /// table: while set, a row at or below [keyBindFloor] yields to the space
  /// (D15). Deleted, never set to another value.
  static const String keyBindMergePending = 'bind_merge_pending';

  /// When the last pull page was applied, as epoch milliseconds.
  static const String keyLastPullAt = 'last_pull_at';

  /// When the space's daily quota ran out, as epoch milliseconds; the engine
  /// keeps `SyncPause.quotaExhausted` across a restart until a call succeeds
  /// (D19).
  static const String keyQuotaPausedAt = 'quota_paused_at';

  /// When the last pull of every table completed, as epoch milliseconds: a
  /// resume pulls only what the signal says moved until it is a day old
  /// (scalability record S9). Deleted with the cursors.
  static const String keyFullPullAt = 'full_pull_at';

  /// The latest server time a snapshot of the space showed — the highest
  /// `touched` value — as epoch microseconds; it only rises. It outlives the
  /// listener, which a leave drops, so a resume or a cold start still knows
  /// how far the server clock has gone before its first snapshot. Deleted
  /// with the cursors.
  static const String keyServerSeen = 'server_seen';

  /// The wire version (`DatabaseSchema.syncSchemaVersion`) this database
  /// last synced under: a run under a higher one re-queues the note bodies
  /// once for the new wire, then stores it (scalability record S6, D2).
  static const String keyWireVersion = 'wire_version';

  /// The name of the database this one was found to be a copy of when the
  /// claim heal unbound it, so the Sync section can say why it stopped
  /// syncing rather than read "not syncing" with no reason (review X-2).
  /// Written only by that heal, deleted by the next bind.
  static const String keyHealUnboundFrom = 'heal_unbound_from';

  /// Set by a hard delete of `alert_registrations` rows, in the delete's own
  /// transaction, and cleared by the next alert pass that completes: while it
  /// stands the platform may hold entries no registry row describes, so a
  /// launch never takes the scheduler's "nothing can arm" path. Not a sync
  /// key — this table is where a device-local fact rides in the database's
  /// transactions; `AlertRegistrationDao` is its only writer.
  static const String keyAlertStraysPending = 'alert_strays_pending';

  /// The id this database's counter taps are filed under in a value's
  /// PN-counter shards (D8 A). Two databases tapping under one id would each
  /// keep only the larger count, and a database file is copied whole — by
  /// Android backup onto a new phone, by an import — while the install
  /// `device_id` beside it is not (S9). So the id is minted afresh at every
  /// bind and unbind ([mintReplicaId]), on the first tap of a database that
  /// has none, and whenever [keyReplicaIdDevice] names another install than
  /// this one ([replicaId]).
  static const String keyReplicaId = 'replica_id';

  /// The install `device_id` [keyReplicaId] was minted under: a database
  /// restored or transferred onto another phone reads a different one there
  /// and mints its own.
  static const String keyReplicaIdDevice = 'replica_id_device';

  /// The prefix every [keyPullCursor] shares, for [deleteByPrefix].
  static const String pullCursorPrefix = 'pull_cursor.';

  /// The prefix every [keyPullSeen] shares, for [deleteByPrefix].
  static const String pullSeenPrefix = 'pull_seen.';

  /// The prefix every [keyPullSettled] shares, for [deleteByPrefix].
  static const String pullSettledPrefix = 'pull_settled.';

  /// Where [table]'s pull resumes: the gateway's cursor after the last
  /// applied page. A bind and an unbind delete every one, so a rebind pulls
  /// from the beginning.
  static String keyPullCursor(String table) => '$pullCursorPrefix$table';

  /// The space document's `touched[table]` last pulled up to: a snapshot
  /// whose value moved past it pulls the table. Deleted with the cursors.
  static String keyPullSeen(String table) => '$pullSeenPrefix$table';

  /// The [keyPullCursor] value of [table] that a pull proved settled — no
  /// write at or before it can still become visible — so the next pull
  /// resumes exactly there, without the overlap re-read. Any other cursor
  /// value is not settled. Deleted with the cursors.
  static String keyPullSettled(String table) => '$pullSettledPrefix$table';

  /// The prefix every [keyPullParked] shares, for [valuesByPrefix] and
  /// [deleteByPrefix].
  static const String pullParkedPrefix = 'pull_parked.';

  /// A pulled document this device could not merge, by [table] and
  /// [rowKey]; the value is `<order>|<stamp>|<reason>` — the order a
  /// zero-padded counter of when it was parked, so a start retries the
  /// oldest first and the retries rotate, the stamp the document's, empty
  /// when it carried no readable one, the reason a `SyncHeldReason` name the
  /// Sync page shows (none before scalability record S7, read as
  /// unreadable). It outlives the session, so after a restart the local
  /// entries at or below that stamp are still held back from the drain; one
  /// with no stamp holds nothing back after a restart and is only counted
  /// (scalability record S8). Deleted with the cursors: it describes the
  /// bound space.
  static String keyPullParked(String table, String rowKey) =>
      '$pullParkedPrefix$table.$rowKey';

  /// The build that last retried every stored park to the end: a later
  /// build may read a document this one could not, so a start under another
  /// build retries every park. Written only once such a pass completed.
  /// Deleted with the cursors.
  static const String keyPullParkedBuild = 'pull_parked_build';

  /// The prefix every [keyPushParked] shares, for [valuesByPrefix] and
  /// [deleteByPrefix].
  static const String pushParkedPrefix = 'push_parked.';

  /// A local row the push set aside, by [table] and [rowKey]; the value is
  /// `<order>|<stamp>|<reason>` as [keyPullParked]'s, the stamp the outbox
  /// entry's. Its entry stays out of the drain at or below that stamp across
  /// a restart — an edit since is a new write and goes — until a start or a
  /// "Sync now" drops it to be tried again: the oldest
  /// `SyncEngine.maxParkRetries` at each, every one under a new build
  /// ([keyPushParkedBuild]) (scalability record S7). Deleted with the
  /// cursors.
  static String keyPushParked(String table, String rowKey) =>
      '$pushParkedPrefix$table.$rowKey';

  /// The build that last dropped the stored push parks: a start under
  /// another build drops every one. Deleted with the cursors.
  static const String keyPushParkedBuild = 'push_parked_build';

  /// The prefix every [keyNoteSeen] shares.
  static const String noteSeenPrefix = 'note_seen.';

  /// The highest stamp of another device's version of note [noteId] that
  /// this device accepted or kept out, so a re-delivery of it is not filed
  /// as a lost edit (scalability record S8). Only rises ([raiseValue]).
  /// Deleted when the database binds to another space ([keyNoteSeenSpace]):
  /// its peers' stamps compare against none of these.
  static String keyNoteSeen(String noteId) => '$noteSeenPrefix$noteId';

  /// The space (`<ownerUid>/<spaceId>`) the [keyNoteSeen] values were
  /// recorded under, written at a bind.
  static const String keyNoteSeenSpace = 'note_seen_space';

  /// The account whose shared rows this database holds — the partner the
  /// reader of shared rows last read from
  /// (`docs/cloud-sharing-foundations.md` §5, §7). A row is another
  /// account's exactly when its `owner_id` is this value; absent, the
  /// database holds none. Written with the first shared read, deleted with
  /// the rows (`SharedRowDao`).
  static const String keySharedOwner = 'shared_owner';

  /// The SQL condition, over a synced table's `owner_id`, for a row this
  /// device may push: one of its own, however the column spells that — NULL
  /// for a row written here after the bind, the bound account's uid for one
  /// that was here at the bind or arrived from its space — which is every
  /// row but those another account shares with this one
  /// ([keySharedOwner]). Never "the same owner as some other row": two rows
  /// of one person differ in that spelling on every bound device.
  static const String mineSql =
      'NOT EXISTS (SELECT 1 FROM sync_metadata '
      "WHERE key = '$keySharedOwner' AND value = owner_id)";

  /// The SQL condition "the event [eventId] names is one another account
  /// shares with this one" — [eventId] a column reference — for a set
  /// statement over rows of the person's own that hang on events (presence
  /// marks, alerts): "delete all my events" is not a word about what was
  /// added to someone else's.
  static String onSharedEventSql(String eventId) =>
      'EXISTS (SELECT 1 FROM calendar_events shared_event '
      'WHERE shared_event.id = $eventId AND shared_event.owner_id = '
      "(SELECT value FROM sync_metadata WHERE key = '$keySharedOwner'))";

  /// [mineSql] for the rows of the table aliased [alias].
  static String mineSqlOf(String alias) =>
      'NOT EXISTS (SELECT 1 FROM sync_metadata '
      "WHERE key = '$keySharedOwner' AND value = $alias.owner_id)";

  /// Present only inside a transaction of the reader of shared rows, which
  /// sets and clears it there (`SharedRowDao.writing`): what lets that one
  /// writer past the fences that keep another account's rows as their owner
  /// wrote them (`SharedRowFences`). A rollback takes it with it; no other
  /// transaction ever sees it.
  static const String keySharedWriting = 'shared_writing';

  /// The pair those rows were read under: another pair, with the same
  /// partner or not, starts with nothing shared.
  static const String keySharedPair = 'shared_pair';

  /// The prefix every [keySharedCursor] shares, for [deleteByPrefix].
  static const String sharedCursorPrefix = 'shared_cursor.';

  /// Where the shared read of [table] resumes — the cursor of the query
  /// across the partner's spaces, never one of a space's own pull.
  static String keySharedCursor(String table) => '$sharedCursorPrefix$table';

  /// When the last shared read finished, in epoch milliseconds: the next
  /// one waits out `SyncEngine.sharedReadInterval` unless it was asked for.
  static const String keySharedReadAt = 'shared_read_at';

  /// When every shared table was last read from its start, in epoch
  /// milliseconds — the daily read that needs no count to trigger it.
  static const String keySharedFullAt = 'shared_full_at';

  /// The highest wire version of a shared document this build skipped as
  /// newer than its own: the person is told to update, and a build at or
  /// above it reads every shared table again from the start.
  static const String keySharedNewerWire = 'shared_newer_wire';

  /// The prefix every [keySharedRefused] shares.
  static const String sharedRefusedPrefix = 'shared_refused.';

  /// Present while the partner's document [rowKey] of [table] is not stored
  /// here because it would take the place of, or hang under, a row of the
  /// person's own (`SharedRowRefused`): `1` while the document is live — what
  /// "{n} items could not be shown" counts — and `0` once it is a tombstone,
  /// which the server's count of the share still holds. Kept true as stored
  /// rows are — gone when the document is stored after all, when a read from
  /// the start no longer meets it and when the shared rows go.
  static String keySharedRefused(String table, String rowKey) =>
      '$sharedRefusedPrefix$table|$rowKey';

  /// The prefix every [keySharedBuiltIn] shares.
  static const String sharedBuiltInPrefix = 'shared_builtin.';

  /// Present while the partner shares the built-in category [id], which is
  /// never stored here — the person's own row under that id draws its events
  /// (D14) — and so is recorded apart, for the list of what is received;
  /// valued and kept true as [keySharedRefused] is, and never counted with
  /// it.
  static String keySharedBuiltIn(String id) => '$sharedBuiltInPrefix$id';

  /// The prefix every [keySharedWaiting] shares, for [valuesByPrefix] and
  /// [deleteByPrefix].
  static const String sharedWaitingPrefix = 'shared_waiting.';

  /// Present while the shared note [noteId] waits for text the reader could
  /// not fetch yet — its space did not name the pair at that moment. The
  /// value is `<tries>|<owner uid>/<space id>`: how often the note was asked
  /// for again on its own, and the space its document lies in, which is
  /// where the next shared read asks — the cursor alone would never come
  /// back to it.
  static String keySharedWaiting(String noteId) =>
      '$sharedWaitingPrefix$noteId';

  /// The prefix every [keySharedRoot] shares.
  static const String sharedRootPrefix = 'shared_root.';

  /// The parent a shared folder names on the wire while it stands at the
  /// top level here, because that parent was not shared: kept so the folder
  /// goes back under it once the parent arrives (`SharedRowDao.placeFolders`).
  static String keySharedRoot(String folderId) => '$sharedRootPrefix$folderId';

  Future<String?> getValue(String key) async {
    final result = await (select(
      syncMetadata,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return result?.value;
  }

  Future<void> setValue(String key, String value) async {
    await into(syncMetadata).insertOnConflictUpdate(
      SyncMetadataCompanion(
        key: Value(key),
        value: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Stores [value] under [key] unless the stored value already sorts at or
  /// above it, in one statement — for a stamp that only rises, written on a
  /// path that should not pay a read first.
  Future<void> raiseValue(String key, String value) async {
    await into(syncMetadata).insert(
      SyncMetadataCompanion.insert(
        key: key,
        value: value,
        updatedAt: DateTime.now(),
      ),
      onConflict: DoUpdate.withExcluded(
        (old, excluded) => SyncMetadataCompanion.custom(
          value: excluded.value,
          updatedAt: excluded.updatedAt,
        ),
        where: (old, excluded) => excluded.value.isBiggerThan(old.value),
      ),
    );
  }

  Future<void> deleteValue(String key) async {
    await (delete(syncMetadata)..where((s) => s.key.equals(key))).go();
  }

  /// Every key starting with [prefix] with its value, in key order; matched
  /// as [deleteByPrefix] matches.
  Future<List<(String, String)>> valuesByPrefix(String prefix) async {
    final rows = await (select(
      syncMetadata,
    )..where((s) => _startsWith(s, prefix))).get();
    return [for (final row in rows) (row.key, row.value)];
  }

  /// [valuesByPrefix] for every one of [prefixes] in one statement.
  Future<List<(String, String)>> valuesByPrefixes(List<String> prefixes) async {
    final rows = await (select(syncMetadata)..where(
          (s) => prefixes
              .map((prefix) => _startsWith(s, prefix))
              .reduce((a, b) => a | b),
        ))
        .get();
    return [for (final row in rows) (row.key, row.value)];
  }

  /// The stored values among [keys], by key; a key with none is absent. One
  /// statement per [CrdtMerge.keysPerStatement] keys, where [getValue] would
  /// pay one per key.
  Future<Map<String, String>> valuesOf(List<String> keys) async {
    final rows = await CrdtMerge.loadInChunks(
      keys,
      (chunk) => (select(syncMetadata)..where((s) => s.key.isIn(chunk))).get(),
    );
    return {for (final row in rows) row.key: row.value};
  }

  /// [keyReplicaId], minted when absent — an unbound database taps too — or
  /// when it was minted under another install's `device_id`.
  Future<String> replicaId() async {
    final stored = await getValue(keyReplicaId);
    if (stored != null &&
        stored.isNotEmpty &&
        await getValue(keyReplicaIdDevice) == db.deviceId) {
      return stored;
    }
    return mintReplicaId();
  }

  /// Files every later tap under a new [keyReplicaId], noting this install's
  /// `device_id` beside it; the shards already counted under the old one keep
  /// their counts.
  Future<String> mintReplicaId() async {
    final minted = db.generateId();
    await setValue(keyReplicaId, minted);
    await setValue(keyReplicaIdDevice, db.deviceId);
    return minted;
  }

  /// Deletes every key starting with [prefix] and returns how many went.
  /// Matched as a literal prefix, never as a `LIKE` pattern: a `_` or `%` in
  /// it — `pull_cursor.` holds one — must not match any character. An empty
  /// prefix would empty the table, the clock and the floor with it, and is
  /// refused.
  Future<int> deleteByPrefix(String prefix) {
    if (prefix.isEmpty) {
      throw ArgumentError.value(prefix, 'prefix', 'must not be empty');
    }
    return (delete(syncMetadata)..where((s) => _startsWith(s, prefix))).go();
  }

  /// The keys starting with [prefix] as a range — at or above it and below
  /// the prefix with its last code unit raised — which the key's index
  /// answers, where a `substr()` comparison reads every row of the table.
  static Expression<bool> _startsWith($SyncMetadataTable s, String prefix) {
    final last = prefix.codeUnitAt(prefix.length - 1);
    final above =
        prefix.substring(0, prefix.length - 1) + String.fromCharCode(last + 1);
    return s.key.isBiggerOrEqualValue(prefix) & s.key.isSmallerThanValue(above);
  }

  /// Whether any event, folder or category of this database carries a
  /// share mark, a deleted one's included
  /// (`docs/cloud-sharing-foundations.md` §3): one statement over three
  /// partial indexes that lets a pulled page skip everything about sharing
  /// when nothing here is shared — which is nearly always.
  Future<bool> anyShareMark() async {
    final row = await customSelect(
      'SELECT EXISTS(SELECT 1 FROM folders WHERE shared_pair IS NOT NULL) '
      'OR EXISTS(SELECT 1 FROM calendar_events '
      'WHERE shared_pair IS NOT NULL) '
      'OR EXISTS(SELECT 1 FROM calendar_categories '
      'WHERE shared_pair IS NOT NULL) AS marked',
    ).getSingle();
    return row.read<bool>('marked');
  }

  Future<String?> getLastSyncTimestamp() => getValue(keyLastSyncTimestamp);

  Future<void> setLastSyncTimestamp(String timestamp) =>
      setValue(keyLastSyncTimestamp, timestamp);

  Future<String?> getLastFolderHlc() => getValue(keyLastFolderHlc);

  Future<void> setLastFolderHlc(String hlc) => setValue(keyLastFolderHlc, hlc);

  Future<String?> getLastNoteHlc() => getValue(keyLastNoteHlc);

  Future<void> setLastNoteHlc(String hlc) => setValue(keyLastNoteHlc, hlc);

  Future<String?> getLastChunkHlc() => getValue(keyLastChunkHlc);

  Future<void> setLastChunkHlc(String hlc) => setValue(keyLastChunkHlc, hlc);
}
