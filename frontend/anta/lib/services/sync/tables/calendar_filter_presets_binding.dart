import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_filter_presets` on the wire: the map of
/// `FilterPresetService.exportData`, the filter blob verbatim so a field a
/// newer build wrote survives.
final class CalendarFilterPresetsBinding
    extends SyncTableBinding<CalendarFilterPresetRow> {
  const CalendarFilterPresetsBinding();

  @override
  String get table => 'calendar_filter_presets';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<CalendarFilterPresetRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.filterPresetDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(CalendarFilterPresetRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    CalendarFilterPresetRow row, {
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
        'filters': row.filters,
        'sortOrder': row.sortOrder,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  @override
  CalendarFilterPresetRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return CalendarFilterPresetRow(
      id: envelope.rowKey,
      name: f.field<String>('name', ''),
      filters: f.field<String>('filters', ''),
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
    return db.filterPresetDao.mergeRemotePreset(decode(envelope), floor: floor);
  }
}
