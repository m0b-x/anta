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
