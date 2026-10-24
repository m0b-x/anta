import '../../../database/crdt/crdt_write.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_event_skips` on the wire: the map of
/// `EventSkipService.exportData`, keyed `eventId|dayMs` by [dayRowKey].
final class CalendarEventSkipsBinding extends SyncTableBinding<EventSkipRow> {
  const CalendarEventSkipsBinding();

  @override
  String get table => 'calendar_event_skips';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<EventSkipRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.eventSkipDao.getByDayKeysIncludingDeleted([
    for (final key in rowKeys) dayKeyOf(key),
  ]);

  @override
  String rowKeyOf(EventSkipRow row) => dayRowKey(row.eventId, row.day);

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    EventSkipRow row, {
    required String boundUid,
  }) async {
    return envelopeOf(
      table: table,
      rowKey: rowKeyOf(row),
      hlc: row.hlcTimestamp,
      deviceId: row.deviceId,
      version: row.version,
      isDeleted: row.isDeleted,
      ownerId: row.ownerId ?? boundUid,
      data: () => {
        'eventId': row.eventId,
        'dayMs': row.day.millisecondsSinceEpoch,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  /// The identity comes from the key, which a data-less tombstone still
  /// carries; a live row's `eventId` / `dayMs` must name the same day.
  @override
  EventSkipRow decode(SyncEnvelope envelope) {
    final key = dayKeyOf(envelope.rowKey);
    final f = WireFields(envelope)
      ..field<String>('eventId', '')
      ..field<int>('dayMs', 0)
      ..expectSame('eventId', key.eventId)
      ..expectSame('dayMs', key.day.millisecondsSinceEpoch);
    return EventSkipRow(
      eventId: key.eventId,
      day: key.day,
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
    return db.eventSkipDao.mergeRemoteSkip(decode(envelope), floor: floor);
  }
}
