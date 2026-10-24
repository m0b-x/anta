import 'package:drift/drift.dart';

import '../../../constants/json_keys.dart';
import '../../../database/crdt/crdt_write.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `counter_values` on the wire. The backup folds values into per-note maps
/// and an extras map, so the per-row map is defined here in the backup's key
/// vocabulary: `counterId`, `noteId` (`''` for the global value), `value`,
/// `isPinned`, `position` and `ownerId`. The table keeps no timestamps.
final class CounterValuesBinding extends SyncTableBinding<CounterValueRow> {
  const CounterValuesBinding();

  static const String _noteId = 'noteId';
  static const String _value = 'value';

  @override
  String get table => 'counter_values';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.counters;

  /// Matched on the key expression itself, the registry's `rowKeySql`, so a
  /// key is never split apart and rebuilt.
  @override
  Future<List<CounterValueRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) {
    final keys = rowKeys.toList(growable: false);
    if (keys.isEmpty) return Future.value(const []);
    return (db.select(db.counterValues)..where(
          (v) => (v.counterId + const Constant('|') + v.noteId).isIn(keys),
        ))
        .get();
  }

  @override
  String rowKeyOf(CounterValueRow row) =>
      counterValueRowKey(row.counterId, row.noteId);

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    CounterValueRow row, {
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
        JsonKeys.counterId: row.counterId,
        _noteId: row.noteId,
        _value: row.value,
        JsonKeys.counterIsPinned: row.isPinned,
        'position': row.position,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
      },
    );
  }

  /// The identity comes from the key, which a data-less tombstone still
  /// carries: a counter id never holds `|`, so the first one splits it.
  @override
  CounterValueRow decode(SyncEnvelope envelope) {
    final data = dataOf(envelope);
    final split = envelope.rowKey.indexOf('|');
    return CounterValueRow(
      counterId: envelope.rowKey.substring(0, split),
      noteId: envelope.rowKey.substring(split + 1),
      value: data[_value] as int? ?? 0,
      position: data['position'] as int? ?? 0,
      isPinned: data[JsonKeys.counterIsPinned] as bool? ?? false,
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
    return db.counterDao.mergeRemoteCounterValue(
      decode(envelope),
      floor: floor,
    );
  }
}
