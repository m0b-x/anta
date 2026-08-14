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
