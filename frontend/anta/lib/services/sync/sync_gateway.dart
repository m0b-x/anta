import 'package:equatable/equatable.dart';

import '../../database/crdt/crdt_write.dart';

/// The space a database syncs with, addressed by its owner and its id —
/// never by a pairId, which names a partnership rather than data (D1).
class SyncSpaceRef extends Equatable {
  final String ownerUid;
  final String spaceId;

  const SyncSpaceRef({required this.ownerUid, required this.spaceId});

  @override
  List<Object?> get props => [ownerUid, spaceId];
}

/// One row on the wire, keyed as the outbox keys it.
class SyncEnvelope extends Equatable {
  /// The SQL table name.
  final String table;
  final String rowKey;
  final String hlc;
  final String deviceId;
  final int version;
  final OutboxOp op;
  final String? ownerId;

  /// The row as its table's backup serializer writes it for an upsert — the
  /// backup format is the wire format — and null for a tombstone, which
  /// carries nothing but its identity and stamp.
  final Map<String, Object?>? data;

  const SyncEnvelope({
    required this.table,
    required this.rowKey,
    required this.hlc,
    required this.deviceId,
    required this.version,
    required this.op,
    this.ownerId,
    this.data,
  });

  @override
  List<Object?> get props => [
    table,
    rowKey,
    hlc,
    deviceId,
    version,
    op,
    ownerId,
    data,
  ];
}

/// Why a gateway call failed, in the terms the engine acts on.
enum SyncGatewayFailure {
  /// No connection: retry later, nothing is wrong with the data.
  offline,

  /// The day's quota ran out: pause until it resets (D19).
  quotaExhausted,

  /// The account may not touch the space: the binding is stale.
  permissionDenied,
  unknown,
}

class SyncGatewayException implements Exception {
  final SyncGatewayFailure failure;
  final String? message;

  const SyncGatewayException(this.failure, [this.message]);

  @override
  String toString() =>
      'SyncGatewayException(${failure.name}${message == null ? '' : ': $message'})';
}

/// The remote store, seen by the sync engine. The engine is built and tested
/// against a fake; the Firestore implementation is the last piece to land,
/// and no Firestore type crosses this interface.
abstract interface class SyncGateway {
  /// Writes [batch] — at most [maxBatch] envelopes — all or nothing: a
  /// failure leaves none of them written, so the outbox entries stay queued
  /// and the whole batch is retried (D19). Pushing an envelope again is
  /// harmless: a row already at that stamp or newer is left as it is.
  Future<void> pushBatch(SyncSpaceRef space, List<SyncEnvelope> batch);

  /// The envelopes of [table] after the cursor ([sinceHlc], [sinceRowKey]),
  /// ordered by `(hlc, rowKey)`, at most [limit] — so the next call resumes
  /// from the last envelope returned. All of them when [sinceHlc] is null.
  ///
  /// The cursor is a pair, never a stamp alone: one HLC stamps many rows (a
  /// cascade, an `enqueueMany`), and a page that ends inside such a run
  /// would otherwise skip the rest of it. A null [sinceRowKey] starts after
  /// every row at [sinceHlc].
  Future<List<SyncEnvelope>> pullSince(
    SyncSpaceRef space,
    String table, {
    String? sinceHlc,
    String? sinceRowKey,
    int limit = maxBatch,
  });

  /// Tells the gateway the engine applied everything of [table] through the
  /// cursor ([throughHlc], [throughRowKey]): a hint it may keep or ignore,
  /// never a write to the data. Idempotent.
  Future<void> ack(
    SyncSpaceRef space,
    String table,
    String throughHlc,
    String throughRowKey,
  );

  /// The largest batch a push takes and a pull returns by default.
  static const int maxBatch = 500;
}
