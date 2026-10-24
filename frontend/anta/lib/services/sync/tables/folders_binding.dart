import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../../../models/item_label.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `folders` on the wire: the folder map of `BackupService.exportAllData`.
final class FoldersBinding extends SyncTableBinding<Folder> {
  const FoldersBinding();

  @override
  String get table => 'folders';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.folders;

  @override
  Future<List<Folder>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) {
    final keys = rowKeys.toList(growable: false);
    if (keys.isEmpty) return Future.value(const []);
    return (db.select(db.folders)..where((f) => f.id.isIn(keys))).get();
  }

  @override
  String rowKeyOf(Folder row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    Folder row, {
    required String boundUid,
  }) async {
    return envelopeOf(
      table: table,
      rowKey: row.id,
      hlc: row.hlcTimestamp,
      deviceId: row.deviceId,
      version: row.version,
      isDeleted: row.isDeleted,
      ownerId: row.ownerId ?? boundUid,
      data: () => {
        JsonKeys.id: row.id,
        JsonKeys.name: row.name,
        JsonKeys.parentId: row.parentId,
        'position': row.position,
        JsonKeys.createdAt: isoOf(row.createdAt),
        JsonKeys.updatedAt: isoOf(row.updatedAt),
        JsonKeys.noteSortOrder: row.noteSortOrder,
        JsonKeys.subfolderSortOrder: row.subfolderSortOrder,
        JsonKeys.label: ItemLabel.fromStorage(row.label).storageName,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
      },
    );
  }

  @override
  Folder decode(SyncEnvelope envelope) {
    final data = dataOf(envelope);
    return Folder(
      id: envelope.rowKey,
      // The column refuses an empty name, and a data-less tombstone has none:
      // its id stands in, on a row nothing ever shows.
      name: data[JsonKeys.name] as String? ?? envelope.rowKey,
      parentId: data[JsonKeys.parentId] as String?,
      position: data['position'] as int? ?? 0,
      label: ItemLabel.fromName(data[JsonKeys.label] as String?).storageValue,
      createdAt: fromIso(data[JsonKeys.createdAt]),
      updatedAt: fromIso(data[JsonKeys.updatedAt]),
      noteSortOrder: data[JsonKeys.noteSortOrder] as String?,
      subfolderSortOrder: data[JsonKeys.subfolderSortOrder] as String?,
      hlcTimestamp: envelope.hlc,
      deviceId: envelope.deviceId,
      version: envelope.version,
      isDeleted: isTombstone(envelope),
      deletedAt: deletedAtOf(envelope),
      ownerId: envelope.ownerId,
    );
  }

  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) {
    return db.folderDao.mergeFolder(decode(envelope), floor: floor);
  }
}
