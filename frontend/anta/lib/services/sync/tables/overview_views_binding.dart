import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `overview_views` on the wire: the map of `OverviewViewService.exportData`,
/// the payload verbatim so a field a newer build wrote survives.
final class OverviewViewsBinding extends SyncTableBinding<OverviewViewRow> {
  const OverviewViewsBinding();

  @override
  String get table => 'overview_views';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<OverviewViewRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.overviewViewDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(OverviewViewRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    OverviewViewRow row, {
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
        'payload': row.payload,
        'sortOrder': row.sortOrder,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  @override
  OverviewViewRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return OverviewViewRow(
      id: envelope.rowKey,
      name: f.field<String>('name', ''),
      payload: f.field<String>('payload', ''),
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
    return db.overviewViewDao.mergeRemoteView(decode(envelope), floor: floor);
  }
}
