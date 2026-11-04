import '../../../constants/category_kinds.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';
import 'category_profile_wire.dart';

/// `calendar_category_profiles` on the wire: [CategoryProfileWire]'s map,
/// every column under its [CategoryProfileKeys] name, the dates as epoch
/// milliseconds — the map the backup's `categoryProfiles` entries carry too,
/// since the backup format is the wire format.
///
/// The overrides cross as they are stored, `null` included: an absent
/// override and a chosen one must stay distinct on the other device, and
/// `markVerb` `''` (marking off) is a value, never read as absent.
final class CalendarCategoryProfilesBinding
    extends SyncTableBinding<CategoryProfileRow> {
  const CalendarCategoryProfilesBinding();

  @override
  String get table => CategoryProfileWire.table;

  @override
  SyncInvalidation get invalidation => SyncInvalidation.calendar;

  @override
  Future<List<CategoryProfileRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.categoryProfileDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(CategoryProfileRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    CategoryProfileRow row, {
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
      data: () => CategoryProfileWire.encode(row),
    );
  }

  /// A tombstone takes the column defaults, the row a fresh insert would be.
  /// The owner is the envelope's, never the data's.
  @override
  CategoryProfileRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)
      ..expectSame(CategoryProfileKeys.id, envelope.rowKey);
    final c = CategoryProfileWire.decode(f);
    return CategoryProfileRow(
      id: envelope.rowKey,
      categoryId: c.categoryId.value,
      kind: c.kind.value,
      area: c.area.value,
      measure: c.measure.value,
      nominalMinutes: c.nominalMinutes.value,
      markVerb: c.markVerb.value,
      marksNew: c.marksNew.value,
      assumeAbsentNew: c.assumeAbsentNew.value,
      countsHours: c.countsHours.value,
      targetKind: c.targetKind.value,
      targetValue: c.targetValue.value,
      targetPeriod: c.targetPeriod.value,
      createdAt: c.createdAt.value,
      updatedAt: c.updatedAt.value,
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
    return db.categoryProfileDao.mergeRemoteCategoryProfile(
      decode(envelope),
      floor: floor,
    );
  }
}
