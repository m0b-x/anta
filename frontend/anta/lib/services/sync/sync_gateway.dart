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

  /// The server refuses a document — too large, malformed: retrying the same
  /// batch fails the same way, so the row has to be parked, not retried.
  invalidData,
  unknown,
}

/// Where a pull resumes. Opaque to the engine: each gateway defines its own
/// encoding, so the engine stores and hands it back but never reads it.
class SyncCursor extends Equatable {
  final String value;

  const SyncCursor(this.value);

  @override
  List<Object?> get props => [value];
}

/// One page of a pull.
class SyncPullPage extends Equatable {
  final List<SyncEnvelope> envelopes;

  /// The cursor to resume after the last envelope returned; when the page is
  /// empty, the cursor passed in — null only when nothing was ever pushed and
  /// the pull started from the beginning.
  final SyncCursor? next;

  /// True when a further page may exist, so the engine pulls again before it
  /// stores [next] as caught up.
  final bool hasMore;

  const SyncPullPage({
    required this.envelopes,
    required this.next,
    required this.hasMore,
  });

  @override
  List<Object?> get props => [envelopes, next, hasMore];
}

/// A space as binding sees it — what the picker lists and what a device
/// checks before it pushes (its schema against [schema]).
class SyncSpaceInfo extends Equatable {
  final SyncSpaceRef ref;
  final String name;

  /// Null while the server timestamp of a fresh create is still pending.
  final DateTime? createdAt;

  /// The device id that created the space.
  final String createdBy;

  /// The highest schema version that ever pushed here: raised, never
  /// lowered, so an older build can tell it is behind.
  final int schema;
  final DateTime? lastWriteAt;
  final String? lastWriter;

  const SyncSpaceInfo({
    required this.ref,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    required this.schema,
    this.lastWriteAt,
    this.lastWriter,
  });

  @override
  List<Object?> get props => [
    ref,
    name,
    createdAt,
    createdBy,
    schema,
    lastWriteAt,
    lastWriter,
  ];
}

/// The space document seen as a change signal: one listener tells a device
/// which tables moved, so it pulls those and nothing else.
class SyncSpaceSignal extends Equatable {
  /// When each table was last written, keyed by SQL table name.
  final Map<String, DateTime> touched;
  final String? lastWriter;
  final int schema;

  const SyncSpaceSignal({
    required this.touched,
    required this.lastWriter,
    required this.schema,
  });

  @override
  List<Object?> get props => [touched, lastWriter, schema];
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
  /// The largest batch a push takes and a pull returns by default. An
  /// instance getter because it differs per gateway: Firestore answers 499,
  /// the space document taking the 500th write of its batch.
  int get maxBatch;

  /// Writes [batch] — at most [maxBatch] envelopes — all or nothing: a
  /// failure leaves none of them written, so the outbox entries stay queued
  /// and the whole batch is retried (D19).
  ///
  /// The same write marks the space document, which is the change signal:
  /// `touched[table]` for every table in the batch, `lastWriter` =
  /// [pushedBy], `lastWriteAt`, and `schema` raised to the larger of the
  /// stored one and [schema] — never lowered, so an older build pushing
  /// cannot hide that a newer one wrote here.
  ///
  /// Pushing an envelope again is harmless: the stored row is replaced by
  /// the newer push, and the engine never pushes a row older than the one
  /// it holds.
  Future<void> pushBatch(
    SyncSpaceRef space,
    List<SyncEnvelope> batch, {
    required String pushedBy,
    required int schema,
  });

  /// The envelopes of [table] in arrival order strictly after [after] — all
  /// of them from the start when it is null — at most `limit ?? maxBatch`.
  ///
  /// Arrival order, not HLC order: an HLC is write order. A phone that edits
  /// offline at 09:30 and pushes at 10:05 delivers a row stamped below a
  /// cursor a tablet stored at 09:55 from rows pushed elsewhere; an HLC
  /// cursor would skip that row for good. A row pushed again moves to the
  /// end of the order and its old position disappears, so a puller sees each
  /// row once, at its newest state.
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
  });

  /// Creates a space for [ownerUid]; the gateway mints its id.
  Future<SyncSpaceInfo> createSpace({
    required String ownerUid,
    required String name,
    required String deviceId,
    required int schema,
  });

  /// Every space [ownerUid] owns, for the bind picker.
  Future<List<SyncSpaceInfo>> listSpaces(String ownerUid);

  /// The space, or null when it does not exist (deleted from the console, or
  /// a binding from another account).
  Future<SyncSpaceInfo?> readSpace(SyncSpaceRef space);

  /// The space's signal: the current one on subscription, then again after
  /// every push to the space.
  Stream<SyncSpaceSignal> watchSpace(SyncSpaceRef space);
}
