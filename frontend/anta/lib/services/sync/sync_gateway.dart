import 'dart:convert';
import 'dart:typed_data';

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
  /// carries nothing but its identity and stamp. A [Uint8List] value is a
  /// bytes field, which a gateway stores as its own binary type.
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

  /// The bytes [data] puts on the wire, as the push's byte budget counts
  /// them: its JSON in UTF-8, a top-level bytes field counted as its length
  /// rather than as the list of numbers JSON would make of it.
  int get wireBytes {
    final fields = data;
    if (fields == null) return 0;
    var blobs = 0;
    final plain = <String, Object?>{};
    for (final MapEntry(:key, :value) in fields.entries) {
      if (value is Uint8List) {
        blobs += value.length;
        plain[key] = null;
      } else {
        plain[key] = value;
      }
    }
    return utf8.encode(jsonEncode(plain)).length + blobs;
  }
}

/// Why a gateway call failed, in the terms the engine acts on.
enum SyncGatewayFailure {
  /// No connection: retry later, nothing is wrong with the data.
  offline,

  /// The day's quota ran out: pause until it resets (D19).
  quotaExhausted,

  /// The rules refused the call: the space is gone, marked for deletion or
  /// another account's, the app is older than the space's schema, or a row's
  /// shape is malformed.
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

  /// Where a resumed page's re-read of the overlap stopped when it ended
  /// still before the cursor it resumed from — a window holding more
  /// documents than the page takes. The next page continues the re-read
  /// from here ([SyncGateway.pullPage]'s `scan`); null once a page reached
  /// past that cursor, and on every page that re-read nothing.
  final SyncCursor? scan;

  /// The row keys of the page's documents this build could not turn into an
  /// envelope, which the cursor passed over: the engine parks them, so the
  /// drain does not push those rows over versions it never read and a later
  /// build retries them (scalability record S8).
  final List<String> skipped;

  const SyncPullPage({
    required this.envelopes,
    required this.next,
    required this.hasMore,
    this.scan,
    this.skipped = const [],
  });

  @override
  List<Object?> get props => [envelopes, next, hasMore, scan, skipped];
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

  /// The space was marked by [SyncGateway.markSpaceDeleted]: it takes no
  /// more pushes and is on its way out, so it is never offered for binding —
  /// only finished ([SyncGateway.deleteRows], then [SyncGateway.deleteSpace]).
  final bool markedForDeletion;

  const SyncSpaceInfo({
    required this.ref,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    required this.schema,
    this.lastWriteAt,
    this.lastWriter,
    this.markedForDeletion = false,
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
    markedForDeletion,
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

  /// The space was marked by [SyncGateway.markSpaceDeleted] — `exists` stays
  /// true until the space document itself is deleted — so a listener can
  /// stop before a push is denied. Always false while `exists` is false.
  final bool markedForDeletion;

  const SyncSpaceSignal({
    required this.exists,
    required this.touched,
    required this.lastWriter,
    required this.schema,
    this.markedForDeletion = false,
  });

  @override
  List<Object?> get props => [
    exists,
    touched,
    lastWriter,
    schema,
    markedForDeletion,
  ];
}

class SyncGatewayException implements Exception {
  final SyncGatewayFailure failure;
  final String? message;

  /// The call ran out of the gateway's deadline rather than failing: the
  /// engine treats it as [SyncGatewayFailure.offline] and also shrinks what
  /// it asks of the link next (scalability record S10).
  final bool timedOut;

  const SyncGatewayException(this.failure, [this.message]) : timedOut = false;

  /// A call that exceeded the gateway's deadline — on a slow link most often
  /// one page or one part too large for it.
  const SyncGatewayException.timedOut([this.message = 'timed out'])
    : failure = SyncGatewayFailure.offline,
      timedOut = true;

  @override
  String toString() =>
      'SyncGatewayException(${timedOut ? 'timedOut' : failure.name}'
      '${message == null ? '' : ': $message'})';
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
  /// [SyncSpaceRef.ownerUid], as the rules require. An envelope whose
  /// `ownerId` is not that uid is a programming error, never a remote
  /// condition: the gateway throws [ArgumentError] before writing anything.
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
  /// makes a repeat a no-op. Pages inside one pull resume exactly — and so
  /// does a first page the engine proved settled, which it asks for with
  /// [resumed] false (scalability record S9).
  ///
  /// A re-read that a page's [limit] stopped short of [after] continues with
  /// [resumed] true and [scan] the page's [SyncPullPage.scan]: the page
  /// reads on strictly after [scan] and still answers [SyncPullPage.next] no
  /// lower than [after], so the walk through a crowded window neither skips
  /// its tail nor moves the cursor back (scalability record S10).
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
    bool resumed = false,
    SyncCursor? scan,
  });

  /// The current documents of [table] under [rowKeys], one read each — the
  /// retry of a parked document the cursor has passed (scalability record
  /// S8). The page carries the readable ones as envelopes and the unreadable
  /// ones' keys as [SyncPullPage.skipped]; a key with no document is in
  /// neither. No cursor: [SyncPullPage.next] is null, `hasMore` false.
  Future<SyncPullPage> readRows(
    SyncSpaceRef space,
    String table,
    List<String> rowKeys,
  );

  /// How many documents one [readRows] call reads at once, each batch under
  /// its own deadline: a start may retry a hundred parks, and every one of
  /// them inside a single call's deadline would time out on a slow link. A
  /// pull's chunk reads ask for no more in one call, so a gateway that did
  /// not split a longer list never reads one under a single deadline
  /// (scalability record S6b).
  static const int rowReadBatch = 30;

  /// How long after a write's server time it may still become visible to a
  /// query — what a [pullPage] with `resumed` re-reads before its cursor.
  Duration get resumeOverlap;

  /// The server time [cursor] stands at, which [SyncSpaceSignal.touched] is
  /// measured on; null when the cursor carries none or is unreadable, and
  /// then the engine never skips the [resumeOverlap] re-read.
  DateTime? cursorTime(SyncCursor cursor);

  /// Creates a space for [ownerUid]; the gateway mints its id. Listeners
  /// already watching that ref hear it at once (`exists` true), as a
  /// Firestore snapshot listener on the document would.
  ///
  /// [name] is 1..100 code points — the rules' own cap, and the one thing
  /// about a space a caller can get wrong: a name outside it comes back as
  /// [SyncGatewayFailure.permissionDenied], not as a validation error of
  /// ours (record §3.3).
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

  /// The first step of deleting a space (record cloud-multi-user-roadmap
  /// §5.3): stamps it as marked with the server's time, after which
  /// [readSpace], [listSpaces] and [watchSpace] report
  /// `markedForDeletion`. It cannot be undone: a marked space refuses every
  /// change of its document, so every [pushBatch] to it is
  /// [SyncGatewayFailure.permissionDenied] whole, while [pullPage] and
  /// [readRows] still answer. Only a marked space lets [deleteRows] and
  /// [deleteSpace] through — the rules keep a live space's rows leaving by
  /// tombstone alone.
  ///
  /// Completes normally when the space is already marked or no longer
  /// exists, so a caller that lost a reply simply calls again. Never retried
  /// inside the call — a repeat of a mark that landed would be refused as a
  /// change of a marked space — so after a refusal or a failure that may
  /// have landed (a timeout, a dropped link) it reads the space once and
  /// answers by what the server shows: marked or gone completes, anything
  /// else rethrows the original failure. Offline it fails as
  /// [SyncGatewayFailure.offline] and nothing is marked.
  Future<void> markSpaceDeleted(SyncSpaceRef space);

  /// The most documents one [deleteRows] call deletes, and its default. The
  /// rules `get()` the space document for every row delete, and Firestore
  /// documents a limit of twenty document-access calls per multi-document
  /// request; only the emulator was ever seen accepting more, and whether
  /// the live service caches that `get()` across one request cannot be
  /// verified from here, so the documented limit is the contract (record
  /// cloud-multi-user-roadmap §5, review F9).
  static const int rowDeleteBatch = 20;

  /// Deletes up to [limit] documents of [table] — `limit ?? rowDeleteBatch`;
  /// above [rowDeleteBatch] or below 1 is an [ArgumentError] — and answers
  /// how many it deleted: one page read from the server, then one
  /// all-or-nothing write of its deletes. 0 means the table reads empty,
  /// which is when the caller moves on to the next table; anything else, it
  /// calls again. A table's documents can be large (`content_chunks`, up to
  /// 64 KB each), so a caller whose page timed out asks for a smaller
  /// [limit] next.
  ///
  /// [SyncGatewayFailure.permissionDenied] when the table holds documents
  /// and the space is not marked ([markSpaceDeleted]) or no longer exists;
  /// an empty table answers 0 whatever the space's state, because nothing
  /// was asked of the rules. The client cannot list a space's tables, so the
  /// caller walks the registry, `content_chunks` included.
  Future<int> deleteRows(SyncSpaceRef space, String table, {int? limit});

  /// The last step of deleting a space: removes the space document, after
  /// which [readSpace] answers null and [watchSpace] `exists: false`. It
  /// deletes none of the rows — Firestore has no recursive delete — so the
  /// caller empties every table with [deleteRows] first; a row left behind
  /// can never be deleted by this app again, its space no longer marked.
  ///
  /// [SyncGatewayFailure.permissionDenied] when the space is not marked.
  /// Completes normally when the document is already gone, and, like
  /// [markSpaceDeleted], reads the space once after a refusal or a failure
  /// that may have landed and completes when it is gone.
  Future<void> deleteSpace(SyncSpaceRef space);
}
