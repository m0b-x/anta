import 'package:drift/drift.dart';
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

  /// The prefix every [keyPullCursor] shares, for [deleteByPrefix].
  static const String pullCursorPrefix = 'pull_cursor.';

  /// The prefix every [keyPullSeen] shares, for [deleteByPrefix].
  static const String pullSeenPrefix = 'pull_seen.';

  /// Where [table]'s pull resumes: the gateway's cursor after the last
  /// applied page. A bind and an unbind delete every one, so a rebind pulls
  /// from the beginning.
  static String keyPullCursor(String table) => '$pullCursorPrefix$table';

  /// The space document's `touched[table]` last pulled up to: a snapshot
  /// whose value moved past it pulls the table. Deleted with the cursors.
  static String keyPullSeen(String table) => '$pullSeenPrefix$table';

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

  Future<void> deleteValue(String key) async {
    await (delete(syncMetadata)..where((s) => s.key.equals(key))).go();
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
    return (delete(syncMetadata)..where(
          (s) => s.key.substr(1, prefix.length).equals(prefix),
        ))
        .go();
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
