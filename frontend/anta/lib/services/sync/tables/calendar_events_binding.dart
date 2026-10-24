import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_events` on the wire: the map of
/// `CalendarEventService.exportData`. The table has no position — the
/// calendar orders events by their dates — so nothing is added to it.
final class CalendarEventsBinding extends SyncTableBinding<CalendarEventRow> {
  const CalendarEventsBinding();

  @override
  String get table => 'calendar_events';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<CalendarEventRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.calendarEventDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(CalendarEventRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    CalendarEventRow row, {
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
        'title': row.title,
        'category': row.category,
        'startDateMs': row.startDate.millisecondsSinceEpoch,
        'allDay': row.allDay,
        'iconKey': row.iconKey,
        'ruleKind': row.ruleKind,
        'rulePayload': row.rulePayload,
        'endDateMs': row.endDate?.millisecondsSinceEpoch,
        'startMinute': row.startMinute,
        'durationMinutes': row.durationMinutes,
        'description': row.description,
        'noteId': row.noteId,
        'colorValue': row.colorValue,
        'tintIcon': row.tintIcon,
        'priority': row.priority,
        'retroactive': row.retroactive,
        'countOccurrences': row.countOccurrences,
        'countStyle': row.countStyle,
        'tracksPresence': row.tracksPresence,
        'assumeAbsent': row.assumeAbsent,
        'assumeAbsentFromMs': row.assumeAbsentFrom?.millisecondsSinceEpoch,
        'perOccurrenceDescriptions': row.perOccurrenceDescriptions,
        'showInDayRail': row.showInDayRail,
        'removeAfterAlert': row.removeAfterAlert,
        'categoryAlerts': row.categoryAlerts,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  /// A tombstone takes the column defaults, the row a fresh insert would be;
  /// `showInDayRail` stays null, "follow the setting".
  @override
  CalendarEventRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return CalendarEventRow(
      id: envelope.rowKey,
      title: f.field<String>('title', ''),
      category: f.field<String>('category', ''),
      startDate: f.fieldMs('startDateMs'),
      allDay: f.field<bool>('allDay', true),
      iconKey: f.nullable<String>('iconKey'),
      ruleKind: f.field<String>('ruleKind', 'oneTime'),
      rulePayload: f.nullable<String>('rulePayload'),
      endDate: f.nullableMs('endDateMs'),
      startMinute: f.nullable<int>('startMinute'),
      durationMinutes: f.nullable<int>('durationMinutes'),
      description: f.nullable<String>('description'),
      noteId: f.nullable<String>('noteId'),
      colorValue: f.nullable<int>('colorValue'),
      tintIcon: f.field<bool>('tintIcon', true),
      priority: f.field<int>('priority', 3),
      retroactive: f.field<bool>('retroactive', false),
      countOccurrences: f.field<bool>('countOccurrences', false),
      countStyle: f.field<String>('countStyle', 'numbered'),
      tracksPresence: f.field<bool>('tracksPresence', false),
      perOccurrenceDescriptions: f.field<bool>(
        'perOccurrenceDescriptions',
        false,
      ),
      showInDayRail: f.nullable<bool>('showInDayRail'),
      assumeAbsent: f.field<bool>('assumeAbsent', false),
      assumeAbsentFrom: f.nullableMs('assumeAbsentFromMs'),
      removeAfterAlert: f.field<bool>('removeAfterAlert', false),
      categoryAlerts: f.field<bool>('categoryAlerts', true),
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
    return db.calendarEventDao.mergeRemoteEvent(decode(envelope), floor: floor);
  }
}
