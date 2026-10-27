import '../../../database/crdt/crdt_write.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_event_absences` on the wire: the map of
/// `EventPresenceService.exportData`, keyed `eventId|dayMs` by [dayRowKey].
final class CalendarEventAbsencesBinding
    extends SyncTableBinding<EventAbsenceRow> {
  const CalendarEventAbsencesBinding();

  @override
  String get table => 'calendar_event_absences';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<EventAbsenceRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.eventAbsenceDao.getByDayKeysIncludingDeleted([
    for (final key in rowKeys) localDayKeyOf(key),
  ]);

  @override
  String rowKeyOf(EventAbsenceRow row) => dayRowKey(row.eventId, row.day);

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    EventAbsenceRow row, {
    required String boundUid,
  }) async {
    return envelopeOf(
      table: table,
      rowKey: dayEnvelopeKey(row.eventId, row.day),
      hlc: row.hlcTimestamp,
      deviceId: row.deviceId,
      version: row.version,
      isDeleted: row.isDeleted,
      ownerId: row.ownerId ?? boundUid,
      data: () => {
        'eventId': row.eventId,
        'dayMs': dayEnvelopeMs(row.day),
        'status': row.status,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  /// The identity comes from the key, which a data-less tombstone still
  /// carries; a live row's `eventId` / `dayMs` must name the same day. A
  /// tombstone's `status` is the column default.
  @override
  EventAbsenceRow decode(SyncEnvelope envelope) {
    final key = dayKeyOf(envelope.rowKey);
    final f = WireFields(envelope)
      ..field<String>('eventId', '')
      ..field<int>('dayMs', 0)
      ..expectSame('eventId', key.eventId)
      ..expectSame('dayMs', key.day.millisecondsSinceEpoch);
    return EventAbsenceRow(
      eventId: key.eventId,
      day: key.day,
      status: f.field<String>('status', 'missed'),
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
    return db.eventAbsenceDao.mergeRemoteAbsence(
      decode(envelope),
      floor: floor,
    );
  }
}
