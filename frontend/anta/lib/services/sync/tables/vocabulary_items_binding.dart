import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `vocabulary_items` on the wire: the per-item map of
/// `VocabularyService.exportData`, plus the `vocabularyId` the backup
/// expresses by nesting.
final class VocabularyItemsBinding extends SyncTableBinding<VocabularyItemRow> {
  const VocabularyItemsBinding();

  @override
  String get table => 'vocabulary_items';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.vocabularies;

  @override
  Future<List<VocabularyItemRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.vocabularyDao.getItemsByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(VocabularyItemRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    VocabularyItemRow row, {
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
        'term': row.term,
        'sortOrder': row.sortOrder,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
        'vocabularyId': row.vocabularyId,
      },
    );
  }

  @override
  VocabularyItemRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return VocabularyItemRow(
      id: envelope.rowKey,
      vocabularyId: f.field<String>('vocabularyId', ''),
      term: f.field<String>('term', ''),
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
    return db.vocabularyDao.mergeRemoteVocabularyItem(
      decode(envelope),
      floor: floor,
    );
  }
}
