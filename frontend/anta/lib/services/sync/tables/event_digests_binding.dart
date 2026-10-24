import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `event_digests` on the wire: the map of `EventDigestService.exportData`,
/// the payload verbatim so a field a newer build wrote survives.
final class EventDigestsBinding extends SyncTableBinding<EventDigestRow> {
  const EventDigestsBinding();

  @override
  String get table => 'event_digests';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.alerts;

  @override
  Future<List<EventDigestRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.eventDigestDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(EventDigestRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    EventDigestRow row, {
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
        'enabled': row.enabled,
        'sortOrder': row.sortOrder,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  @override
  EventDigestRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return EventDigestRow(
      id: envelope.rowKey,
      name: f.field<String>('name', ''),
      payload: f.field<String>('payload', ''),
      enabled: f.field<bool>('enabled', true),
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
    return db.eventDigestDao.mergeRemoteDigest(decode(envelope), floor: floor);
  }
}
