import 'package:drift/drift.dart' show Value;

import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../../../models/item_label.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `folders` on the wire: the JSON backup's folder map, as
/// `BackupService.importFromJson` reads it, except its dates, which cross as
/// epoch milliseconds under `createdAtMs` / `updatedAtMs` as every calendar
/// table writes them — the backup's local ISO strings carry no offset, so two
/// zones would read different instants.
final class FoldersBinding extends SyncTableBinding<Folder> {
  const FoldersBinding();

  @override
  String get table => 'folders';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.folders;

  @override
  Future<List<Folder>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) =>
      db.folderDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(Folder row) => row.id;

  /// A folder is shared by its own mark or the nearest one above it.
  @override
  Future<Map<String, String>> sharedPairs(AppDatabase db, List<Folder> rows) =>
      db.folderDao.sharedPairsOf([for (final row in rows) row.id]);

  @override
  Future<Map<String, String>> shareStamps(AppDatabase db, List<Folder> rows) =>
      db.folderDao.shareStampsOf([for (final row in rows) row.id]);

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
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        JsonKeys.noteSortOrder: row.noteSortOrder,
        JsonKeys.subfolderSortOrder: row.subfolderSortOrder,
        JsonKeys.label: ItemLabel.fromStorage(row.label).storageName,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
        if (row.sharedPair != null) sharedPairKey: row.sharedPair,
        if (row.sharedStamp != null) sharedStampKey: row.sharedStamp,
      },
    );
  }

  @override
  Folder decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame(JsonKeys.id, envelope.rowKey);
    return Folder(
      id: envelope.rowKey,
      // The column refuses an empty name, and a data-less tombstone has none:
      // its id stands in, on a row nothing ever shows.
      name: f.field<String>(JsonKeys.name, envelope.rowKey),
      parentId: f.nullable<String>(JsonKeys.parentId),
      position: f.field<int>('position', 0),
      label: ItemLabel.fromName(
        f.field<String>(JsonKeys.label, ItemLabel.none.storageName),
      ).storageValue,
      createdAt: f.fieldMs('createdAtMs'),
      updatedAt: f.fieldMs('updatedAtMs'),
      noteSortOrder: f.nullable<String>(JsonKeys.noteSortOrder),
      subfolderSortOrder: f.nullable<String>(JsonKeys.subfolderSortOrder),
      hlcTimestamp: envelope.hlc,
      deviceId: envelope.deviceId,
      version: envelope.version,
      isDeleted: isTombstone(envelope),
      deletedAt: deletedAtOf(envelope),
      ownerId: envelope.ownerId,
      sharedPair: f.nullable<String>(sharedPairKey),
      sharedStamp: f.nullable<String>(sharedStampKey),
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

  /// The parent is stored as the wire names it; a parent that was not
  /// shared, or that this device holds as its own, is settled after the
  /// page by `SharedRowDao.placeFolders`.
  @override
  Future<MergeOutcome> mergeShared(AppDatabase db, SyncEnvelope envelope) {
    final remote = decode(envelope).copyWith(
      sharedPair: const Value(null),
      sharedStamp: const Value(null),
    );
    return db.transaction(() async {
      await SharedRowRefused.unlessFree(db, table, remote.id, remote.ownerId!);
      return db.folderDao.mergeFolder(remote, shared: true);
    });
  }
}
