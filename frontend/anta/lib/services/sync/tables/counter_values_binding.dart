import '../../../constants/json_keys.dart';
import '../../../database/crdt/crdt_write.dart';
import '../../../database/crdt/hlc.dart';
import '../../../database/crdt/pn_counter.dart';
import '../../../database/database.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `counter_values` on the wire. The backup folds values into per-note maps
/// and an extras map, so the per-row map is defined here in the backup's key
/// vocabulary: `counterId`, `noteId` (`''` for the global value), `value`,
/// `isPinned`, `position` and `ownerId`, plus the PN-counter state (D8 A) —
/// `epochHlc`, `epochValue` and `shards` as `{replicaId: [p, n]}` — which an
/// older build ignores, reading `value` alone. The table keeps no timestamps.
///
/// `syncSchemaVersion` does not move for the three keys: a bump would pause
/// every older device as appOutdated until it updates. The cost is the
/// mixed-version window instead: an older build still writes the value as a
/// last-writer-wins number, so its envelope (one without the keys) never
/// joins — it merges by stamp order, the pre-S20 rule ([mergeRemote]), and a
/// strictly newer one still overwrites the taps the new build counted since.
final class CounterValuesBinding extends SyncTableBinding<CounterValueRow> {
  const CounterValuesBinding();

  static const String _noteId = 'noteId';
  static const String _value = 'value';
  static const String _epochHlc = 'epochHlc';
  static const String _epochValue = 'epochValue';
  static const String _shards = 'shards';

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
        _epochHlc: row.epochHlc,
        _epochValue: row.epochValue,
        _shards: PnCounterState(
          epochHlc: row.epochHlc,
          epochValue: row.epochValue,
          shards: PnCounterState.shardsOfColumn(row.shards),
        ).shardsWire,
      },
    );
  }

  /// The identity comes from the key, which a data-less tombstone still
  /// carries; a live row's own ids must agree with it.
  ///
  /// The PN-counter keys are read as nullable: an envelope without any of
  /// them comes from an older build and is a legacy absolute state — an
  /// epoch of its own stamp holding its `value`, no shards. One with some but
  /// not all of them, shards that are not replica `[p, n]` pairs, an epoch
  /// that is not a stamp, or a `value` its state does not add up to is a
  /// [FormatException], so the engine parks it rather than store a count
  /// another device reads differently.
  @override
  CounterValueRow decode(SyncEnvelope envelope) {
    final key = _keyOf(envelope.rowKey);
    final f = WireFields(envelope)
      ..expectSame(JsonKeys.counterId, key.counterId)
      ..expectSame(_noteId, key.noteId);
    final value = f.field<int>(_value, 0);
    final state = f.live ? _stateOf(f, envelope, value) : null;
    return CounterValueRow(
      counterId: key.counterId,
      noteId: key.noteId,
      value: value,
      position: f.field<int>('position', 0),
      isPinned: f.field<bool>(JsonKeys.counterIsPinned, false),
      hlcTimestamp: envelope.hlc,
      deviceId: envelope.deviceId,
      version: envelope.version,
      isDeleted: isTombstone(envelope),
      deletedAt: deletedAtOf(envelope),
      ownerId: envelope.ownerId,
      epochHlc: state?.epochHlc ?? PnCounterState.genesis,
      epochValue: state?.epochValue ?? 0,
      shards: state?.shardsColumn ?? '',
    );
  }

  static PnCounterState _stateOf(
    WireFields f,
    SyncEnvelope envelope,
    int value,
  ) {
    final epochHlc = f.nullable<String>(_epochHlc);
    final epochValue = f.nullable<int>(_epochValue);
    final shards = f.nullable<Map<Object?, Object?>>(_shards);
    if (epochHlc == null && epochValue == null && shards == null) {
      return PnCounterState(epochHlc: envelope.hlc, epochValue: value);
    }
    if (epochHlc == null || epochValue == null || shards == null) {
      throw FormatException(
        '${f.table}: "${envelope.rowKey}" carries part of a PN-counter',
      );
    }
    if (epochHlc.isNotEmpty) HlcTimestamp.parse(epochHlc);
    final state = PnCounterState(
      epochHlc: epochHlc,
      epochValue: epochValue,
      shards: PnCounterState.shardsOfWire(shards),
    );
    if (state.value != value) {
      throw FormatException(
        '${f.table}: "${envelope.rowKey}" holds $value, its shards add up to '
        '${state.value}',
      );
    }
    return state;
  }

  /// An envelope without the PN-counter keys never joins: an older build
  /// re-sends rows it holds — a requeue, a pin or position change, its bind's
  /// `requeueAll`, an echo — under stamps above the epoch this build counts
  /// in, and joined as an absolute write each would wipe the taps since. By
  /// stamp order an older or equal one loses to the local row, and only a
  /// strictly newer one — a real write of that build — wins whole.
  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) {
    return db.counterDao.mergeRemoteCounterValue(
      decode(envelope),
      floor: floor,
      joins: dataOf(envelope).containsKey(_epochHlc),
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
