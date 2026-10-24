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

  @override
  Future<List<CounterValueRow>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.counterDao.getValuesByKeysIncludingDeleted([
    for (final key in rowKeys) _keyOf(key),
  ]);

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
  /// carries; a live row's own ids must agree with it.
  @override
  CounterValueRow decode(SyncEnvelope envelope) {
    final key = _keyOf(envelope.rowKey);
    final f = WireFields(envelope)
      ..expectSame(JsonKeys.counterId, key.counterId)
      ..expectSame(_noteId, key.noteId);
    return CounterValueRow(
      counterId: key.counterId,
      noteId: key.noteId,
      value: f.field<int>(_value, 0),
      position: f.field<int>('position', 0),
      isPinned: f.field<bool>(JsonKeys.counterIsPinned, false),
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

  /// [counterValueRowKey] read back: a counter id never holds `|`, so the
  /// first one splits it, and a global value's note id is `''`. A key without
  /// a `|` or a counter id names no row and is a [FormatException], so the
  /// engine parks its envelope.
  static ({String counterId, String noteId}) _keyOf(String rowKey) {
    final split = rowKey.indexOf('|');
    if (split < 1) {
      throw FormatException('not a counterId|noteId row key', rowKey);
    }
    return (
      counterId: rowKey.substring(0, split),
      noteId: rowKey.substring(split + 1),
    );
  }
}
