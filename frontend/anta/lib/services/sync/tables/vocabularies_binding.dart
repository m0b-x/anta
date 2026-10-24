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
  ) {
    final keys = rowKeys.toList(growable: false);
    if (keys.isEmpty) return Future.value(const []);
    return (db.select(db.vocabularies)..where((t) => t.id.isIn(keys))).get();
  }

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
    final data = dataOf(envelope);
    return VocabularyRow(
      id: envelope.rowKey,
      name: data['name'] as String? ?? '',
      isEnabled: data['isEnabled'] as bool? ?? true,
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
    return db.vocabularyDao.mergeRemoteVocabulary(
      decode(envelope),
      floor: floor,
    );
  }
}
