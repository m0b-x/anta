import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../../../models/counter.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `counters` on the wire: `Counter.toJson()` plus `ownerId`, as
/// `CounterService.exportData` writes each counter, and `position` — the
/// backup restores order from the list, but one document per counter has no
/// list to read it from.
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
  ) {
    final keys = rowKeys.toList(growable: false);
    if (keys.isEmpty) return Future.value(const []);
    return (db.select(db.counters)..where((c) => c.id.isIn(keys))).get();
  }

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
          createdAt: row.createdAt.toUtc(),
        ).toJson(),
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
        'position': row.position,
      },
    );
  }

  @override
  CounterRow decode(SyncEnvelope envelope) {
    final data = envelope.data;
    final counter = data == null
        ? null
        : Counter.fromJson({...data, JsonKeys.id: envelope.rowKey});
    return CounterRow(
      id: envelope.rowKey,
      name: counter?.name ?? '',
      startValue: counter?.startValue ?? 1,
      step: counter?.step ?? 1,
      scope: (counter?.scope ?? CounterScope.global).name,
      position: data?['position'] as int? ?? 0,
      isPinned: counter?.isPinned ?? false,
      createdAt: (counter?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toLocal(),
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
