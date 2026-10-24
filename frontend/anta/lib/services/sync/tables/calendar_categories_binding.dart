import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_categories` on the wire: the map of `CategoryService.exportData`.
/// Built-ins travel like any row under their fixed ids, `isBuiltIn` and
/// `isHidden` included.
final class CalendarCategoriesBinding
    extends SyncTableBinding<CalendarCategoryRow> {
  const CalendarCategoriesBinding();

  @override
  String get table => 'calendar_categories';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<CalendarCategoryRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.calendarCategoryDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(CalendarCategoryRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    CalendarCategoryRow row, {
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
        'colorValue': row.colorValue,
        'iconKey': row.iconKey,
        'sortOrder': row.sortOrder,
        'isBuiltIn': row.isBuiltIn,
        'isHidden': row.isHidden,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        if (row.ownerId != null) 'ownerId': row.ownerId,
      },
    );
  }

  @override
  CalendarCategoryRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame('id', envelope.rowKey);
    return CalendarCategoryRow(
      id: envelope.rowKey,
      name: f.field<String>('name', ''),
      colorValue: f.field<int>('colorValue', 0),
      iconKey: f.field<String>('iconKey', ''),
      sortOrder: f.field<int>('sortOrder', 0),
      isBuiltIn: f.field<bool>('isBuiltIn', false),
      isHidden: f.field<bool>('isHidden', false),
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
    return db.calendarCategoryDao.mergeRemoteCategory(
      decode(envelope),
      floor: floor,
    );
  }
}
