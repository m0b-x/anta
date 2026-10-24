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

  /// The account the rules require on every document of the space, a
  /// tombstone's included — a missing owner would have every delete denied.
  final String ownerId;

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
    required this.ownerId,
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

  /// The rules refused the call: the space is gone or another account's, the
  /// app is older than the space's schema, or a row's shape is malformed.
  /// The engine tells these apart by reading the space (record §3.5).
  permissionDenied,

  /// Strictly what the server reports as `invalid-argument` — a document
  /// over 1 MiB: retrying the same batch fails the same way, so the row has
  /// to be parked, not retried. A malformed row is a rule refusal and
  /// arrives as [permissionDenied] instead.
  invalidData,
  unknown,
}

/// Where a pull resumes. Opaque to the engine: each gateway defines its own
/// encoding, so the engine stores and hands it back but never reads it.
class SyncCursor extends Equatable {
  /// A string so the engine can persist it in `sync_metadata` as it is,
  /// whatever the gateway packs into it.
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
  /// stores [next] as caught up. A gateway may answer `page.length == limit`
  /// without looking further, so "hasMore, then an empty page" is normal.
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
  /// lowered — a push from a lower one is denied — so an older build can
  /// tell it is behind.
  final int schema;

  /// For the bind picker, so two spaces with the same name can be told apart
  /// by how recently they were used; null until something was pushed.
  final DateTime? lastWriteAt;

  /// The device id of the last push, the other half of telling spaces apart
  /// in the picker; null until something was pushed.
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
  /// False while the space document is missing — never created, or deleted
  /// from the console — so a listener can tell "nothing pushed yet" from
  /// "gone", where a push would be denied.
  final bool exists;

  /// When each table was last written, keyed by SQL table name.
  final Map<String, DateTime> touched;

  /// The device id of the last push, for diagnosis only: the engine does not
  /// skip a pull by it — a table touched by its own push may hold another
  /// device's rows too, so its own are read back once and merge as no-ops
  /// (record §3.5).
  final String? lastWriter;
  final int schema;

  const SyncSpaceSignal({
    required this.exists,
    required this.touched,
    required this.lastWriter,
    required this.schema,
  });

  @override
  List<Object?> get props => [exists, touched, lastWriter, schema];
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
  /// [pushedBy], `lastWriteAt`, and `schema` = [schema].
  ///
  /// The stored row is replaced unconditionally — no HLC check: a stale
  /// overwrite is repaired by the device holding the newer row, which keeps
  /// it on the next pull and re-queues it (record §3.4). Every document
  /// carries the `data` key (null for a tombstone) and `ownerId` =
  /// [SyncSpaceRef.ownerUid], as the rules require.
  ///
  /// Denied with [SyncGatewayFailure.permissionDenied] before anything is
  /// written when the space does not exist (Firestore's merge-write on a
  /// missing space document is a create the rules refuse), or when [schema]
  /// is lower than the space's — Firestore has no max transform, so the rule
  /// `schema >= stored` keeps an outdated app from writing rows that lack
  /// columns. An equal or higher [schema] is stored.
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
  /// row at its newest state.
  ///
  /// Delivery is at least once. The engine passes [resumed] true on the
  /// first page of each table in a run — [after] came from storage — and
  /// false for the pages that follow. A gateway may re-deliver rows near a
  /// resumed cursor (Firestore starts a little before it, because a write
  /// received earlier can commit after a query that already ran); the merge
  /// makes a repeat a no-op. Pages inside one pull resume exactly.
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
    bool resumed = false,
  });

  /// Creates a space for [ownerUid]; the gateway mints its id. Listeners
  /// already watching that ref hear it at once (`exists` true), as a
  /// Firestore snapshot listener on the document would.
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
  /// every push to the space and on its creation. A missing space emits
  /// `exists: false` with nothing touched and schema 0, so a binding whose
  /// space was deleted is noticed without a failed push.
  ///
  /// Broadcast on every path, a failure's included, so a second listener on
  /// the same stream never throws — on the error path least of all, where a
  /// retry may re-subscribe to the stream it already holds.
  Stream<SyncSpaceSignal> watchSpace(SyncSpaceRef space);
}
