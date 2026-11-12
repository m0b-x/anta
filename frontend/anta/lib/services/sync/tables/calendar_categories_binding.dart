import 'package:drift/drift.dart' show Value;

import '../../../database/daos/calendar_category_dao.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `calendar_categories` on the wire: the map of `CategoryService.exportData`.
/// Built-ins travel like any row under their fixed ids, `isBuiltIn` and
/// `isHidden` included. Since wire 48 the share mark and its stamp travel in
/// `data` too, as an event's do, for the owner's other devices — never in
/// the export.
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

  /// A category is shared by its own mark, which the row carries; a
  /// tombstone keeps it, so the partner hears of the delete.
  @override
  Future<Map<String, String>> sharedPairs(
    AppDatabase db,
    List<CalendarCategoryRow> rows,
  ) async => {for (final row in rows) row.id: ?row.sharedPair};

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
        if (row.sharedPair != null) sharedPairKey: row.sharedPair,
        if (row.sharedStamp != null) sharedStampKey: row.sharedStamp,
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
      sharedPair: f.nullable<String>(sharedPairKey),
      sharedStamp: f.nullable<String>(sharedStampKey),
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

  /// A category another account shares, stored under its owner without the
  /// owner's mark. The owner's order and archive flag are theirs and not
  /// obeyed here: it is stored at order 0, shown, and never a built-in —
  /// where it is listed is this phone's decision. A built-in id is always
  /// refused, whether or not this device holds that row yet: the person's
  /// own row under it is the one that draws (D14).
  @override
  Future<MergeOutcome> mergeShared(AppDatabase db, SyncEnvelope envelope) {
    final remote = decode(envelope).copyWith(
      sortOrder: 0,
      isHidden: false,
      isBuiltIn: false,
      sharedPair: const Value(null),
      sharedStamp: const Value(null),
    );
    return db.transaction(() async {
      if (CalendarCategoryDao.builtInIds.contains(remote.id)) {
        throw SharedRowRefused(table, remote.id, builtIn: true);
      }
      await SharedRowRefused.unlessFree(db, table, remote.id, remote.ownerId!);
      return db.calendarCategoryDao.mergeRemoteCategory(remote, shared: true);
    });
  }
}
