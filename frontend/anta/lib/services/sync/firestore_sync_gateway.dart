import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../core/qa/qa_mode.dart';
import '../../database/crdt/crdt_write.dart';
import 'sync_gateway.dart';

/// The [SyncGateway] over Firestore (record §3.1, §3.3): one space document
/// per database at `users/{ownerUid}/spaces/{spaceId}`, one subcollection per
/// synced table beside it, each row a document keyed as the outbox keys it.
///
/// With `pairing_gateway.dart`, the only file that imports `cloud_firestore`
/// (a source scan pins it); every Firestore failure leaves it as a
/// [SyncGatewayException].
class FirestoreSyncGateway implements SyncGateway {
  /// The emulator suite's Firestore port, as `firebase.emulators.json`
  /// declares it unless a QA run names another ([QaMode.firebaseFirestorePort]).
  static const int emulatorFirestorePort = QaMode.firebaseFirestorePort;

  /// Every call is bounded: the engine runs one request at a time, so a call
  /// that never answers would hold every later run. A page or a part that
  /// outlasts it on a slow link comes back as
  /// [SyncGatewayException.timedOut], and the engine asks for a smaller one
  /// next (scalability record S10); a commit that lands after it is pushed
  /// again, which writes the same documents. Offline, a transaction fails on
  /// its own long before it.
  static const Duration _timeout = Duration(seconds: 60);

  /// What [_readBack] gets: short, because the failed write it follows has
  /// already spent [_timeout], and the caller is waiting on an answer it can
  /// act on.
  static const Duration _createdReadTimeout = Duration(seconds: 10);

  /// Attempts the SDK gives a push's write-only transaction. Its default: the
  /// whole initial upload of a large database merges the one space document,
  /// batch after batch, over Firestore's sustained single-document rate, and
  /// one contention `ABORTED` the SDK does not retry fails all 499 rows and
  /// sends the run to the engine's back-off (A8 review R97).
  static const int _writeAttempts = 5;

  final FirebaseFirestore? _injected;

  FirestoreSyncGateway({FirebaseFirestore? firestore}) : _injected = firestore;

  // Resolved lazily, like the pairing gateway: this is constructed during DI
  // registration, where `FirebaseFirestore.instance` must not be touched yet.
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  /// Once, in DI, before any Firestore use: points the SDK at the emulator
  /// suite when [emulatorHost] is set (a QA build only), then turns the SDK's
  /// own offline queue off. The outbox is the one durable queue: with the
  /// SDK's on, a commit made offline never completes, and a batch it replays
  /// after a restart could overwrite a newer document (record §3.8).
  static void configure({String emulatorHost = ''}) {
    final db = FirebaseFirestore.instance;
    if (emulatorHost.isNotEmpty) {
      db.useFirestoreEmulator(emulatorHost, emulatorFirestorePort);
    }
    db.settings = const Settings(persistenceEnabled: false);
  }

  CollectionReference<Map<String, dynamic>> _spaces(String ownerUid) =>
      _db.collection('users').doc(ownerUid).collection('spaces');

  DocumentReference<Map<String, dynamic>> _space(SyncSpaceRef space) =>
      _spaces(space.ownerUid).doc(space.spaceId);

  @override
  int get maxBatch => 499;

  @override
  Future<void> pushBatch(
    SyncSpaceRef space,
    List<SyncEnvelope> batch, {
    required String pushedBy,
    required int schema,
    String? sharedPair,
  }) async {
    if (batch.isEmpty) {
      throw ArgumentError.value(batch.length, 'batch', 'no rows');
    }
    if (batch.length > maxBatch) {
      throw ArgumentError.value(batch.length, 'batch', 'over $maxBatch rows');
    }
    for (final envelope in batch) {
      if (envelope.ownerId != space.ownerUid) {
        throw ArgumentError.value(
          envelope.ownerId,
          'ownerId',
          '${envelope.table}/${envelope.rowKey} is not owned by the space owner',
        );
      }
    }
    await _guard(
      () => _writeOnly((transaction) {
        final now = FieldValue.serverTimestamp();
        final spaceDoc = _space(space);
        for (final envelope in batch) {
          transaction.set(
            spaceDoc.collection(envelope.table).doc(envelope.rowKey),
            FirestoreSyncWire.documentOf(
              envelope,
              pushedBy: pushedBy,
              serverTime: now,
              wire: schema,
            ),
          );
        }
        transaction.set(
          spaceDoc,
          FirestoreSyncWire.spaceMergeOf(
            {for (final envelope in batch) envelope.table},
            pushedBy: pushedBy,
            schema: schema,
            serverTime: now,
            sharedPair: sharedPair,
            removed: FieldValue.delete(),
          ),
          SetOptions(merge: true),
        );
      }),
    );
  }

  /// Commits [write]'s sets as one write-only transaction, never a
  /// `WriteBatch`: the SDK queues a batch in memory while offline even with
  /// persistence off, so it would time out as `offline`, land on reconnect
  /// anyway and gain a copy on every retry; a transaction is never queued and
  /// fails at once offline (S5 review M4). [attempts] of them, [_writeAttempts]
  /// by default: with nothing read there is nothing to re-read, so every
  /// attempt commits the same sets, and the SDK absorbs a contention `ABORTED`
  /// the engine's back-off would answer a second too late; a repeated attempt
  /// writes the same documents, so one landing twice is a no-op. That last
  /// clause is only true where a second `set` is still a *create*: a caller
  /// whose document the first attempt already wrote passes 1, because the
  /// rules judge the retry as an update against what landed ([createSpace],
  /// A8 review R149). Offline the commit is still never queued, it only fails
  /// after the SDK's attempts rather than on the first, and [_timeout] bounds
  /// all of them together.
  Future<void> _writeOnly(
    void Function(Transaction transaction) write, {
    int attempts = _writeAttempts,
  }) => _db.runTransaction<void>((transaction) async {
    write(transaction);
  }, maxAttempts: attempts);

  @override
  Duration get resumeOverlap => FirestoreSyncWire.pullOverlap;

  @override
  DateTime? cursorTime(SyncCursor cursor) {
    final decoded = FirestoreSyncWire.tryDecodeCursor(cursor);
    return decoded == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(decoded.$1, isUtc: true);
  }

  @override
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
    bool resumed = false,
    SyncCursor? scan,
  }) {
    final take = limit ?? maxBatch;
    // A stored cursor no gateway of this kind wrote (a hand-edited or
    // corrupted database, a gateway swapped out) would fail every run of
    // this table identically and forever; the table is read from the start
    // instead, which the merge makes a no-op (A8 review R92).
    var from = after;
    final start = FirestoreSyncWire.tryDecodeCursor(from);
    if (from != null && start == null) {
      debugPrint(
        '[FirestoreSyncGateway] unreadable $table cursor "${from.value}", '
        'reading the table from the start',
      );
      from = null;
    }
    final begin = FirestoreSyncWire.queryStart(
      from,
      resumed: resumed,
      scan: scan,
    );
    return _guard(() async {
      Query<Map<String, dynamic>> query = _space(
        space,
      ).collection(table).orderBy('pushedAt').orderBy(FieldPath.documentId);
      if (begin != null) {
        final at = Timestamp.fromMicrosecondsSinceEpoch(begin.micros);
        query = begin.overlap
            ? query.where('pushedAt', isGreaterThanOrEqualTo: at)
            : query.startAfter([at, begin.rowKey]);
      }
      final snapshot = await query
          .limit(take)
          .get(const GetOptions(source: Source.server));
      final envelopes = <SyncEnvelope>[];
      final skipped = <String>[];
      final pushed = <String, SyncPush>{};
      var next = from;
      // The page's latest position in the cursor's own order — the query's
      // order, so the cursor cannot step back inside a page. Seeded with
      // the cursor the page resumed from: a `resumed` page re-reads the
      // ten-second overlap, so every document in it can sit under that
      // cursor, and the page's own maximum would move it backwards (A7
      // review R137).
      SyncCursor? latest = from;
      // The last position read in the query's order, the page's own maximum
      // even where [latest] kept the cursor: where a re-read goes on.
      SyncCursor? read;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final pushedAt = data['pushedAt'];
        // A pending server timestamp — never from a server read, but a
        // cursor cannot be made from it.
        if (pushedAt is! Timestamp) continue;
        final position = FirestoreSyncWire.encodeCursor(
          pushedAt.microsecondsSinceEpoch,
          doc.id,
        );
        read = position;
        if (latest == null ||
            FirestoreSyncWire.compareCursors(position, latest) > 0) {
          latest = next = position;
        }
        final envelope = FirestoreSyncWire.envelopeOf(table, doc.id, data);
        if (envelope == null) {
          // The rules admit no such document; skipped like a parked
          // envelope, so one cannot pin the pull at this cursor.
          debugPrint(
            '[FirestoreSyncGateway] skipped malformed $table/${doc.id}',
          );
          skipped.add(doc.id);
          continue;
        }
        envelopes.add(envelope);
        pushed[doc.id] = FirestoreSyncWire.pushOf(data, pushedAt.toDate());
      }
      final hasMore = snapshot.docs.length == take;
      return SyncPullPage(
        envelopes: envelopes,
        next: next,
        hasMore: hasMore,
        scan: FirestoreSyncWire.scanAfter(
          from: from,
          resumed: resumed,
          full: hasMore,
          read: read,
        ),
        skipped: skipped,
        pushed: pushed,
      );
    });
  }

  @override
  Future<SyncPullPage> readRows(
    SyncSpaceRef space,
    String table,
    List<String> rowKeys,
  ) async {
    final collection = _space(space).collection(table);
    final envelopes = <SyncEnvelope>[];
    final skipped = <String>[];
    final pushed = <String, SyncPush>{};
    const step = SyncGateway.rowReadBatch;
    for (var start = 0; start < rowKeys.length; start += step) {
      final batch = rowKeys.skip(start).take(step);
      final docs = await _guard(
        () => Future.wait([
          for (final key in batch)
            collection.doc(key).get(const GetOptions(source: Source.server)),
        ]),
      );
      for (final doc in docs) {
        final data = doc.data();
        if (data == null) continue;
        final envelope = FirestoreSyncWire.envelopeOf(table, doc.id, data);
        if (envelope == null) {
          skipped.add(doc.id);
        } else {
          envelopes.add(envelope);
          final at = data['pushedAt'];
          pushed[doc.id] = FirestoreSyncWire.pushOf(
            data,
            at is Timestamp ? at.toDate() : null,
          );
        }
      }
    }
    return SyncPullPage(
      envelopes: envelopes,
      next: null,
      hasMore: false,
      skipped: skipped,
      pushed: pushed,
    );
  }

  @override
  Future<SyncSpaceInfo> createSpace({
    required String ownerUid,
    required String name,
    required String deviceId,
    required int schema,
  }) async {
    // The id is drawn once, before the write: a repeated call is a new
    // space, never a second write of this one. So a call that fails after
    // its commit landed — the reply lost, or the read-back past the budget —
    // reads the drawn id back once before it gives up: the id dies with the
    // call, and a retry that drew a fresh one would leave the first space
    // orphaned in `listSpaces`, indistinguishable by name (A8 review R87).
    // Drawing it goes through [_guard] as well: it touches `_db`, which
    // throws where Firebase never initialised (`main.dart` degrades to
    // local-only on purpose), and every failure of this file must reach the
    // caller as a [SyncGatewayException] (A8 review R151).
    final doc = await _guard(() async => _spaces(ownerUid).doc());
    final ref = SyncSpaceRef(ownerUid: ownerUid, spaceId: doc.id);
    SyncSpaceInfo unread() => SyncSpaceInfo(
      ref: ref,
      name: name,
      createdAt: null,
      createdBy: deviceId,
      schema: schema,
    );
    try {
      return await _guard(() async {
        await _writeOnly(
          (transaction) => transaction.set(
            doc,
            FirestoreSyncWire.spaceCreateOf(
              name: name,
              deviceId: deviceId,
              schema: schema,
              serverTime: FieldValue.serverTimestamp(),
            ),
          ),
          // One attempt, where a push takes [_writeAttempts]: a retry re-runs
          // this handler, so `createdAt` resolves to the later attempt's
          // `request.time` and the set lands on the document the first
          // attempt wrote — an update the rules deny
          // (`createdAt == resource.data.createdAt`), which would turn a lost
          // reply into `permissionDenied`. It also keeps the rescue read
          // below honest: nothing of this call is still in flight when it
          // asks whether the space is there (A8 review R149, R150).
          attempts: 1,
        );
        // Read back rather than guess: `createdAt` is the server's.
        final created = await doc.get(const GetOptions(source: Source.server));
        return _infoOf(ref, created.data()) ?? unread();
      });
    } on SyncGatewayException {
      // The server not holding the space, or not answering in time, is the
      // expected answer here — the commit did not land.
      final created = (await _readBack(doc, after: 'create'))?.data();
      if (created == null) rethrow;
      return _infoOf(ref, created) ?? unread();
    }
  }

  @override
  Future<List<SyncSpaceInfo>> listSpaces(String ownerUid) => _guard(() async {
    final snapshot = await _spaces(
      ownerUid,
    ).orderBy('createdAt').get(const GetOptions(source: Source.server));
    return [
      for (final doc in snapshot.docs)
        ?_infoOf(SyncSpaceRef(ownerUid: ownerUid, spaceId: doc.id), doc.data()),
    ];
  });

  @override
  Future<SyncSpaceInfo?> readSpace(SyncSpaceRef space) => _guard(() async {
    final snapshot = await _space(
      space,
    ).get(const GetOptions(source: Source.server));
    return _infoOf(space, snapshot.data());
  });

  @override
  Stream<SyncSpaceSignal> watchSpace(SyncSpaceRef space) {
    // Broadcast on every path, each listener its own Firestore listener; a
    // failure arrives as a gateway error before the stream ends, never as a
    // bare completion. Metadata changes are asked for so the server's first
    // answer arrives even when it matches what the cache said; only server
    // snapshots reach the engine.
    return Stream.multi((listener) {
      final subscription = _space(space)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) {
              final metadata = snapshot.metadata;
              if (FirestoreSyncWire.shouldForwardSnapshot(
                isFromCache: metadata.isFromCache,
                hasPendingWrites: metadata.hasPendingWrites,
              )) {
                listener.add(_signalOf(snapshot.data()));
              }
            },
            onError: (Object error) =>
                listener.addError(FirestoreSyncWire.errorOf(error)),
            onDone: listener.close,
          );
      listener.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  @override
  Future<void> markSpaceDeleted(SyncSpaceRef space) async {
    // Resolved inside the guard, as every call here is, so a handle that
    // cannot be had fails as a gateway failure too (review F10).
    DocumentReference<Map<String, dynamic>>? doc;
    try {
      await _guard(() {
        final ref = doc = _space(space);
        return _writeOnly(
          (transaction) => transaction.update(
            ref,
            FirestoreSyncWire.spaceMarkOf(FieldValue.serverTimestamp()),
          ),
          // One attempt: a retry of a mark that landed is an update of a
          // marked space, which the rules refuse.
          attempts: 1,
        );
      });
    } on SyncGatewayException {
      final ref = doc;
      if (ref == null) rethrow;
      // `update` never creates, so a missing space fails here too; so does a
      // mark that already landed, and a reply lost on the way back.
      final read = await _readBack(ref, after: 'mark');
      if (read == null) rethrow;
      final data = read.data();
      if (data != null && !FirestoreSyncWire.isMarked(data)) rethrow;
    }
  }

  @override
  Future<int> deleteRows(SyncSpaceRef space, String table, {int? limit}) async {
    const most = SyncGateway.rowDeleteBatch;
    final take = limit ?? most;
    if (take < 1 || take > most) {
      throw ArgumentError.value(take, 'limit', 'not within 1..$most');
    }
    final page = await _guard(
      () => _space(space)
          .collection(table)
          .limit(take)
          .get(const GetOptions(source: Source.server)),
    );
    if (page.docs.isEmpty) return 0;
    // Deleting a document already gone is allowed under a marked space, so
    // the SDK's own retries of this write are safe.
    await _guard(
      () => _writeOnly((transaction) {
        for (final doc in page.docs) {
          transaction.delete(doc.reference);
        }
      }),
    );
    return page.docs.length;
  }

  @override
  Future<void> deleteSpace(SyncSpaceRef space) async {
    DocumentReference<Map<String, dynamic>>? doc;
    try {
      await _guard(() {
        final ref = doc = _space(space);
        // One attempt: a retry of a delete that landed meets no document,
        // and the rules refuse a delete with no mark to read.
        return _writeOnly(
          (transaction) => transaction.delete(ref),
          attempts: 1,
        );
      });
    } on SyncGatewayException {
      final ref = doc;
      if (ref == null) rethrow;
      final read = await _readBack(ref, after: 'delete');
      if (read == null || read.exists) rethrow;
    }
  }

  /// The space document read once from the server after a create, a mark or
  /// a delete failed ([after] names which, for the log), or null when it
  /// cannot be read in time. Its own short budget: the call has already
  /// spent the gateway's, and the failure that brought us here is the one
  /// the caller sees unless the read proves the write is done.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _readBack(
    DocumentReference<Map<String, dynamic>> doc, {
    required String after,
  }) async {
    try {
      return await doc
          .get(const GetOptions(source: Source.server))
          .timeout(_createdReadTimeout);
    } catch (error) {
      debugPrint('[FirestoreSyncGateway] $after not read back: $error');
      return null;
    }
  }

  SyncSpaceSignal _signalOf(Map<String, dynamic>? data) {
    if (data == null) {
      return const SyncSpaceSignal(
        exists: false,
        touched: {},
        lastWriter: null,
        schema: 0,
      );
    }
    final touched = <String, DateTime>{};
    final raw = data['touched'];
    if (raw is Map) {
      raw.forEach((table, at) {
        final date = _dateOf(at);
        if (table is String && date != null) touched[table] = date;
      });
    }
    final lastWriter = data['lastWriter'];
    final schema = data['schema'];
    return SyncSpaceSignal(
      exists: true,
      touched: Map.unmodifiable(touched),
      lastWriter: lastWriter is String ? lastWriter : null,
      schema: schema is num ? schema.toInt() : 0,
      markedForDeletion: FirestoreSyncWire.isMarked(data),
    );
  }

  SyncSpaceInfo? _infoOf(SyncSpaceRef ref, Map<String, dynamic>? data) {
    if (data == null) return null;
    final name = data['name'];
    final createdBy = data['createdBy'];
    final schema = data['schema'];
    final lastWriter = data['lastWriter'];
    return SyncSpaceInfo(
      ref: ref,
      name: name is String ? name : '',
      createdAt: _dateOf(data['createdAt']),
      createdBy: createdBy is String ? createdBy : '',
      schema: schema is num ? schema.toInt() : 0,
      lastWriteAt: _dateOf(data['lastWriteAt']),
      lastWriter: lastWriter is String ? lastWriter : null,
      markedForDeletion: FirestoreSyncWire.isMarked(data),
    );
  }

  DateTime? _dateOf(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    return null;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(_timeout);
    } on SyncGatewayException {
      rethrow;
    } on ArgumentError {
      rethrow;
    } catch (error) {
      throw FirestoreSyncWire.errorOf(error);
    }
  }
}

/// The pure half of [FirestoreSyncGateway]: how a cursor, a row and the space
/// document's merge look on the wire, and what a Firestore error code means —
/// no Firestore type, so it is unit-tested without a backend.
@visibleForTesting
abstract final class FirestoreSyncWire {
  /// How far before a stored cursor a resumed pull starts: `pushedAt` is the
  /// time a write was received, and a write received earlier can commit
  /// after a query that already ran (record §3.3).
  static const Duration pullOverlap = Duration(seconds: 10);

  /// What a failed call raises. A call past the gateway's 60 s deadline, or
  /// past the server's (`deadline-exceeded`), is
  /// [SyncGatewayException.timedOut]: still offline to the engine, which
  /// also asks for a smaller page or part next (scalability record S10).
  static SyncGatewayException errorOf(Object error) => switch (error) {
    SyncGatewayException() => error,
    FirebaseException(:final code, :final message) => _firebaseFailure(
      code,
      message,
    ),
    TimeoutException() => const SyncGatewayException.timedOut(),
    _ => SyncGatewayException(SyncGatewayFailure.unknown, '$error'),
  };

  static SyncGatewayException _firebaseFailure(String code, String? message) {
    // Retried like any unknown failure, so without its own line a query
    // missing its index would fail quietly forever.
    if (code == 'failed-precondition') {
      debugPrint(
        '[FirestoreSyncGateway] failed-precondition, possibly a missing '
        'index: $message',
      );
    }
    // The server's own deadline on a long query or commit: the same page or
    // part retried unchanged would meet it again.
    if (code == 'deadline-exceeded') {
      return SyncGatewayException.timedOut(message ?? code);
    }
    return SyncGatewayException(failureOf(code), message ?? code);
  }

  /// Where a page's query starts, from the cursor [after] — null for the
  /// table's start. A resumed page re-reads from [pullOverlap] before it
  /// (`overlap`: `pushedAt >=` the time) unless [scan] says how far that
  /// re-read already got; otherwise the page starts strictly after the
  /// position.
  static ({int micros, String rowKey, bool overlap})? queryStart(
    SyncCursor? after, {
    required bool resumed,
    SyncCursor? scan,
  }) {
    final start = tryDecodeCursor(after);
    if (start == null) return null;
    if (!resumed) return (micros: start.$1, rowKey: start.$2, overlap: false);
    final goesOn = tryDecodeCursor(scan);
    if (goesOn != null) {
      return (micros: goesOn.$1, rowKey: goesOn.$2, overlap: false);
    }
    return (micros: overlapStart(start.$1), rowKey: '', overlap: true);
  }

  /// A resumed page's [SyncPullPage.scan]: the position it [read] last when
  /// it was [full] and still before [from], the cursor it resumed from —
  /// the window holds more, and the re-read goes on from there.
  static SyncCursor? scanAfter({
    required SyncCursor? from,
    required bool resumed,
    required bool full,
    required SyncCursor? read,
  }) {
    if (!resumed || !full || from == null || read == null) return null;
    return compareCursors(read, from) < 0 ? read : null;
  }

  /// `<pushedAt micros>|<rowKey>`. A row key may itself hold `|`
  /// (`counterId|noteId`), so the micros come first and the first `|` ends
  /// them.
  static SyncCursor encodeCursor(int pushedAtMicros, String rowKey) =>
      SyncCursor('$pushedAtMicros|$rowKey');

  /// The cursor's `pushedAt` in microseconds and its row key; a
  /// [FormatException] for a value no gateway of this kind wrote.
  static (int, String) decodeCursor(SyncCursor cursor) {
    final value = cursor.value;
    final bar = value.indexOf('|');
    final micros = bar < 0 ? null : int.tryParse(value.substring(0, bar));
    if (micros == null) {
      throw FormatException('not a Firestore sync cursor', value);
    }
    return (micros, value.substring(bar + 1));
  }

  /// [cursor] decoded, or null when there is none or it holds a value no
  /// gateway of this kind wrote: a pull reads the table from the start
  /// rather than failing on a cursor forever (A8 review R92).
  static (int, String)? tryDecodeCursor(SyncCursor? cursor) {
    if (cursor == null) return null;
    try {
      return decodeCursor(cursor);
    } on FormatException {
      return null;
    }
  }

  /// The order a pull reads rows in, as the query states it: `pushedAt`
  /// first, then the row key.
  static int compareCursors(SyncCursor a, SyncCursor b) {
    final (aMicros, aKey) = decodeCursor(a);
    final (bMicros, bKey) = decodeCursor(b);
    final byTime = aMicros.compareTo(bMicros);
    return byTime != 0 ? byTime : aKey.compareTo(bKey);
  }

  /// Where a pull resumed from a cursor at [pushedAtMicros] starts.
  static int overlapStart(int pushedAtMicros) =>
      pushedAtMicros - pullOverlap.inMicroseconds;

  /// Whether a space snapshot reaches the engine: only the server's word.
  /// Offline, the first snapshot of a document never read says it does not
  /// exist, which would pause the engine for good as a deleted space (S5
  /// review H1); a snapshot of the device's own write carries null server
  /// timestamps (L8).
  static bool shouldForwardSnapshot({
    required bool isFromCache,
    required bool hasPendingWrites,
  }) => !isFromCache && !hasPendingWrites;

  /// A row's document. `data` is always present — null for a tombstone — and
  /// [serverTime] (Firestore's server-timestamp sentinel) stamps `pushedAt`,
  /// which the rules require to be the request's time. A bytes field of
  /// `data` (a chunk's `gz`) is written as a [Blob], Firestore's own binary
  /// type, a quarter smaller than base64 text and what the rules check.
  ///
  /// A shared row's document says so beside `data` — [sharedPairKey], what
  /// the rules let the pair read it by — and names [wire], the wire version
  /// of this build, under [wireKey]: its reader is another account's
  /// device, which cannot read this space's schema. A private row's
  /// document carries neither, and the whole document is replaced on every
  /// push, so a row made private loses both with the write.
  static Map<String, Object?> documentOf(
    SyncEnvelope envelope, {
    required String pushedBy,
    required Object serverTime,
    required int wire,
  }) => {
    'hlc': envelope.hlc,
    'deviceId': envelope.deviceId,
    'version': envelope.version,
    'op': envelope.op.name,
    'ownerId': envelope.ownerId,
    'data': _mapValues(envelope.data, (v) => v is Uint8List ? Blob(v) : v),
    'pushedAt': serverTime,
    'pushedBy': pushedBy,
    if (envelope.sharedPair != null) ...{
      sharedPairKey: envelope.sharedPair,
      wireKey: wire,
    },
  };

  /// The field a shared row's document names its writer's wire version
  /// under.
  static const String wireKey = 'wire';

  /// The push that wrote [document] ([SyncPullPage.pushed]): its `pushedBy`
  /// — null for one that names none — and [at], its `pushedAt` as the
  /// caller read it.
  static SyncPush pushOf(Map<String, Object?> document, DateTime? at) {
    final pushedBy = document['pushedBy'];
    return SyncPush(
      by: pushedBy is String && pushedBy.isNotEmpty ? pushedBy : null,
      at: at,
    );
  }

  /// [data] with each top-level value passed through [map].
  static Map<String, Object?>? _mapValues(
    Map<Object?, Object?>? data,
    Object? Function(Object? value) map,
  ) => data == null
      ? null
      : {
          for (final MapEntry(:key, :value) in data.entries)
            key as String: map(value),
        };

  /// The row document as an envelope, or null when its shape is not one
  /// [documentOf] writes.
  static SyncEnvelope? envelopeOf(
    String table,
    String rowKey,
    Map<String, Object?> document,
  ) {
    final hlc = document['hlc'];
    final deviceId = document['deviceId'];
    final version = document['version'];
    final op = OutboxOp.values.asNameMap()[document['op']];
    final ownerId = document['ownerId'];
    final data = document['data'];
    final sharedPair = document[sharedPairKey];
    final wire = document[wireKey];
    if (hlc is! String ||
        deviceId is! String ||
        version is! num ||
        op == null ||
        ownerId is! String ||
        !document.containsKey('data') ||
        (data != null && data is! Map) ||
        (sharedPair != null && sharedPair is! String) ||
        (wire != null && wire is! num)) {
      return null;
    }
    return SyncEnvelope(
      table: table,
      rowKey: rowKey,
      hlc: hlc,
      deviceId: deviceId,
      version: version.toInt(),
      op: op,
      ownerId: ownerId,
      data: _mapValues(data as Map?, (v) => v is Blob ? v.bytes : v),
      sharedPair: sharedPair as String?,
      wire: (wire as num?)?.toInt(),
    );
  }

  /// What a push merges into the space document: `touched` for each of
  /// [tables] as a nested map — a merge-set deep-merges maps, while a dotted
  /// key would be a field name with dots in it — the writer and this build's
  /// [schema], which the rules refuse when lower than the stored one.
  ///
  /// `touched` must be [serverTime], written in the transaction that writes
  /// the rows' `pushedAt`, never a client clock: the engine reads the latest
  /// `touched` as the server clock (`server_seen`) and skips a table's
  /// overlap re-read on it (scalability record S9), so a client time ahead
  /// of the server would mark a table settled while writes can still land.
  ///
  /// [sharedPair], the pair the database's notes are shared into, is kept
  /// under [sharedPairKey] and taken out again when null — [removed] is
  /// Firestore's field-delete sentinel, a no-op on a document that never
  /// had the field — so the space never names a pair its database stopped
  /// sharing into.
  static Map<String, Object?> spaceMergeOf(
    Set<String> tables, {
    required String pushedBy,
    required int schema,
    required Object serverTime,
    required String? sharedPair,
    required Object removed,
  }) => {
    'touched': {for (final table in tables) table: serverTime},
    'lastWriter': pushedBy,
    'lastWriteAt': serverTime,
    'schema': schema,
    sharedPairKey: sharedPair ?? removed,
  };

  /// A new space document; the rules require `createdAt` to be the request's
  /// time, so [serverTime] stamps it.
  static Map<String, Object?> spaceCreateOf({
    required String name,
    required String deviceId,
    required int schema,
    required Object serverTime,
  }) => {
    'name': name,
    'createdAt': serverTime,
    'createdBy': deviceId,
    'schema': schema,
  };

  /// The space document's mark (record cloud-multi-user-roadmap §5.3), the
  /// key `firestore.rules`' `marked()` tests for.
  static const String markKey = 'deletedAt';

  /// What a mark writes into the space document: [markKey] as [serverTime],
  /// the only value the rules accept.
  static Map<String, Object?> spaceMarkOf(Object serverTime) => {
    markKey: serverTime,
  };

  /// Whether a space document carries the mark. Presence, not the value, as
  /// the rules judge it.
  static bool isMarked(Map<String, Object?> data) => data.containsKey(markKey);

  /// A Firestore error code in the engine's terms.
  static SyncGatewayFailure failureOf(String code) => switch (code) {
    'unavailable' || 'deadline-exceeded' => SyncGatewayFailure.offline,
    'resource-exhausted' => SyncGatewayFailure.quotaExhausted,
    'permission-denied' ||
    'unauthenticated' => SyncGatewayFailure.permissionDenied,
    'invalid-argument' => SyncGatewayFailure.invalidData,
    _ => SyncGatewayFailure.unknown,
  };
}
