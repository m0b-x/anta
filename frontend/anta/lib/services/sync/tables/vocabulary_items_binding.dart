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
  ) {
    final keys = rowKeys.toList(growable: false);
    if (keys.isEmpty) return Future.value(const []);
    return (db.select(db.vocabularyItems)..where((t) => t.id.isIn(keys))).get();
  }

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
    final data = dataOf(envelope);
    return VocabularyItemRow(
      id: envelope.rowKey,
      vocabularyId: data['vocabularyId'] as String? ?? '',
      term: data['term'] as String? ?? '',
      sortOrder: data['sortOrder'] as int? ?? 0,
      createdAt: fromMs(data['createdAtMs']),
      updatedAt: fromMs(data['updatedAtMs']),
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
