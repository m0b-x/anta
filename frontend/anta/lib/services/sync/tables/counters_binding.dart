import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../../../models/counter.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `counters` on the wire: `Counter.toJson()` plus `ownerId`, as
/// `CounterService.exportData` writes each counter, and `position` — the
/// backup restores order from the list, but one document per counter has no
/// list to read it from. `createdAt` crosses as `createdAtMs`, the wire's one
/// date shape, where the backup writes an ISO string.
final class CountersBinding extends SyncTableBinding<CounterRow> {
  const CountersBinding();

  @override
  String get table => 'counters';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.counters;

  @override
  Future<List<CounterRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.counterDao.getCountersByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(CounterRow row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    CounterRow row, {
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
        ...Counter(
          id: row.id,
          name: row.name,
          startValue: row.startValue,
          step: row.step,
          scope: _scopeOf(row.scope),
          isPinned: row.isPinned,
          createdAt: row.createdAt,
        ).toJson()..remove(JsonKeys.createdAt),
        // The stored string, not the enum read back from it: a scope the
        // column holds but this build does not recognise goes out as it
        // stands rather than as `global` (R66). That is all it buys — a
        // scope that never reached the column cannot survive, since
        // [decode] normalises an unknown one before the merge stores it
        // (A7 review R135).
        JsonKeys.counterScope: row.scope,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
        'position': row.position,
      },
    );
  }

  /// A scope this build does not know reads as global, as
  /// `Counter.fromJson` reads it from a backup.
  @override
  CounterRow decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame(JsonKeys.id, envelope.rowKey);
    return CounterRow(
      id: envelope.rowKey,
      name: f.field<String>(JsonKeys.name, ''),
      startValue: f.field<int>(JsonKeys.counterStartValue, 1),
      step: f.field<int>(JsonKeys.counterStep, 1),
      scope: _scopeOf(
        f.field<String>(JsonKeys.counterScope, CounterScope.global.name),
      ).name,
      position: f.field<int>('position', 0),
      isPinned: f.field<bool>(JsonKeys.counterIsPinned, false),
      createdAt: f.fieldMs('createdAtMs'),
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
    return db.counterDao.mergeRemoteCounter(decode(envelope), floor: floor);
  }

  static CounterScope _scopeOf(String name) => CounterScope.values.firstWhere(
    (s) => s.name == name,
    orElse: () => CounterScope.global,
  );
}
