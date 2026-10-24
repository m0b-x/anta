import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `vocabularies` on the wire: the vocabulary map of
/// `VocabularyService.exportData` without its nested `items`, which travel
/// as their own rows.
final class VocabulariesBinding extends SyncTableBinding<VocabularyRow> {
  const VocabulariesBinding();

  @override
  String get table => 'vocabularies';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.vocabularies;

  @override
  Future<List<VocabularyRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.vocabularyDao.getVocabulariesByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(VocabularyRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    VocabularyRow row, {
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
        'id': row.id,
        'name': row.name,
        'isEnabled': row.isEnabled,
        'sortOrder': row.sortOrder,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
      },
    );
  }

  @override
  VocabularyRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return VocabularyRow(
      id: envelope.rowKey,
      name: f.field<String>('name', ''),
      isEnabled: f.field<bool>('isEnabled', true),
      sortOrder: f.field<int>('sortOrder', 0),
      createdAt: f.fieldMs('createdAtMs'),
      updatedAt: f.fieldMs('updatedAtMs'),
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
    return db.vocabularyDao.mergeRemoteVocabulary(
      decode(envelope),
      floor: floor,
    );
  }
}
