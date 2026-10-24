import '../../../constants/event_alerts.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_event_alerts` on the wire: the map of
/// `EventAlertService.exportData` under [EventAlertKeys]. The export goes
/// through the `EventAlert` model; the wire writes the columns themselves
/// under the same keys, so a mode or sound this build does not know crosses
/// unchanged for the build that wrote it.
final class CalendarEventAlertsBinding extends SyncTableBinding<EventAlertRow> {
  const CalendarEventAlertsBinding();

  @override
  String get table => 'calendar_event_alerts';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.alerts;

  @override
  Future<List<EventAlertRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.eventAlertDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(EventAlertRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    EventAlertRow row, {
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
        EventAlertKeys.id: row.id,
        EventAlertKeys.eventId: row.eventId,
        EventAlertKeys.mode: row.mode,
        EventAlertKeys.offsetMinutes: row.offsetMinutes,
        EventAlertKeys.daysBefore: row.daysBefore,
        EventAlertKeys.dayMinute: row.dayMinute,
        EventAlertKeys.sound: row.sound,
        EventAlertKeys.enabled: row.enabled,
        EventAlertKeys.createdAtMs: row.createdAt.millisecondsSinceEpoch,
        EventAlertKeys.updatedAtMs: row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) EventAlertKeys.ownerId: row.ownerId,
      },
    );
  }

  /// A tombstone takes the column defaults, the row a fresh insert would be.
  @override
  EventAlertRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)
      ..expectSame(EventAlertKeys.id, envelope.rowKey);
    return EventAlertRow(
      id: envelope.rowKey,
      eventId: f.field<String>(EventAlertKeys.eventId, ''),
      mode: f.field<String>(EventAlertKeys.mode, 'notify'),
      offsetMinutes: f.field<int>(EventAlertKeys.offsetMinutes, 0),
      daysBefore: f.field<int>(EventAlertKeys.daysBefore, 0),
      dayMinute: f.nullable<int>(EventAlertKeys.dayMinute),
      sound: f.nullable<String>(EventAlertKeys.sound),
      enabled: f.field<bool>(EventAlertKeys.enabled, true),
      createdAt: f.fieldMs(EventAlertKeys.createdAtMs),
      updatedAt: f.fieldMs(EventAlertKeys.updatedAtMs),
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
    return db.eventAlertDao.mergeRemoteAlert(decode(envelope), floor: floor);
  }
}
