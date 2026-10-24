import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_event_templates` on the wire: the map of
/// `EventTemplateService.exportData`, `sortOrder` included.
final class CalendarEventTemplatesBinding
    extends SyncTableBinding<EventTemplateRow> {
  const CalendarEventTemplatesBinding();

  @override
  String get table => 'calendar_event_templates';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<EventTemplateRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.eventTemplateDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(EventTemplateRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    EventTemplateRow row, {
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
        'category': row.category,
        'sortOrder': row.sortOrder,
        'ruleKind': row.ruleKind,
        'rulePayload': row.rulePayload,
        'startMinute': row.startMinute,
        'durationMinutes': row.durationMinutes,
        'description': row.description,
        'iconKey': row.iconKey,
        'colorValue': row.colorValue,
        'tintIcon': row.tintIcon,
        'priority': row.priority,
        'retroactive': row.retroactive,
        'countOccurrences': row.countOccurrences,
        'countStyle': row.countStyle,
        'tracksPresence': row.tracksPresence,
        'assumeAbsent': row.assumeAbsent,
        'perOccurrenceDescriptions': row.perOccurrenceDescriptions,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  /// A tombstone takes the column defaults, the row a fresh insert would be.
  @override
  EventTemplateRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return EventTemplateRow(
      id: envelope.rowKey,
      name: f.field<String>('name', ''),
      category: f.field<String>('category', ''),
      sortOrder: f.field<int>('sortOrder', 0),
      ruleKind: f.field<String>('ruleKind', 'oneTime'),
      rulePayload: f.nullable<String>('rulePayload'),
      startMinute: f.nullable<int>('startMinute'),
      durationMinutes: f.nullable<int>('durationMinutes'),
      description: f.nullable<String>('description'),
      iconKey: f.nullable<String>('iconKey'),
      colorValue: f.nullable<int>('colorValue'),
      tintIcon: f.field<bool>('tintIcon', true),
      priority: f.field<int>('priority', 3),
      retroactive: f.field<bool>('retroactive', false),
      countOccurrences: f.field<bool>('countOccurrences', false),
      countStyle: f.field<String>('countStyle', 'numbered'),
      tracksPresence: f.field<bool>('tracksPresence', false),
      assumeAbsent: f.field<bool>('assumeAbsent', false),
      perOccurrenceDescriptions: f.field<bool>(
        'perOccurrenceDescriptions',
        false,
      ),
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
    return db.eventTemplateDao.mergeRemoteTemplate(
      decode(envelope),
      floor: floor,
    );
  }
}
