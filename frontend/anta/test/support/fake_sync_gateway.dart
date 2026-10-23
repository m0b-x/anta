import 'package:anta/services/sync/sync_gateway.dart';

/// An in-memory [SyncGateway] for the engine's tests: one map per space and
/// table, keyed by row key, holding the newest envelope pushed for each row.
class FakeSyncGateway implements SyncGateway {
  final Map<SyncSpaceRef, Map<String, Map<String, SyncEnvelope>>> _store = {};

  /// Every batch accepted, in order.
  final List<List<SyncEnvelope>> pushes = [];

  /// Every acknowledgement, in order.
  final List<
    ({
      SyncSpaceRef space,
      String table,
      String throughHlc,
      String throughRowKey,
    })
  >
  acks = [];

  SyncGatewayFailure? _nextFailure;

  /// Makes the next call — push, pull or ack — throw [failure] and change
  /// nothing.
  void failNextWith(SyncGatewayFailure failure) => _nextFailure = failure;

  /// What the space holds for [table], keyed by row key.
  Map<String, SyncEnvelope> rowsOf(SyncSpaceRef space, String table) =>
      Map.unmodifiable(_store[space]?[table] ?? const {});

  void _throwIfScripted() {
    final failure = _nextFailure;
    if (failure == null) return;
    _nextFailure = null;
    throw SyncGatewayException(failure, 'scripted');
  }

  @override
  Future<void> pushBatch(SyncSpaceRef space, List<SyncEnvelope> batch) async {
    _throwIfScripted();
    if (batch.length > SyncGateway.maxBatch) {
      throw ArgumentError.value(batch.length, 'batch', 'over the batch limit');
    }
    final tables = _store.putIfAbsent(space, () => {});
    for (final envelope in batch) {
      final rows = tables.putIfAbsent(envelope.table, () => {});
      final current = rows[envelope.rowKey];
      if (current == null || envelope.hlc.compareTo(current.hlc) > 0) {
        rows[envelope.rowKey] = envelope;
      }
    }
    pushes.add(List.unmodifiable(batch));
  }

  @override
  Future<List<SyncEnvelope>> pullSince(
    SyncSpaceRef space,
    String table, {
    String? sinceHlc,
    String? sinceRowKey,
    int limit = SyncGateway.maxBatch,
  }) async {
    _throwIfScripted();
    bool afterCursor(SyncEnvelope envelope) {
      if (sinceHlc == null) return true;
      final byHlc = envelope.hlc.compareTo(sinceHlc);
      if (byHlc != 0) return byHlc > 0;
      return sinceRowKey != null && envelope.rowKey.compareTo(sinceRowKey) > 0;
    }

    final rows =
        [
          for (final envelope in (_store[space]?[table] ?? const {}).values)
            if (afterCursor(envelope)) envelope,
        ]..sort((a, b) {
          final byHlc = a.hlc.compareTo(b.hlc);
          return byHlc != 0 ? byHlc : a.rowKey.compareTo(b.rowKey);
        });
    return rows.take(limit).toList();
  }

  @override
  Future<void> ack(
    SyncSpaceRef space,
    String table,
    String throughHlc,
    String throughRowKey,
  ) async {
    _throwIfScripted();
    acks.add((
      space: space,
      table: table,
      throughHlc: throughHlc,
      throughRowKey: throughRowKey,
    ));
  }
}
