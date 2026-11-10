import 'dart:async';
import 'dart:typed_data';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/content_chunks_binding.dart';

/// An in-memory [SyncGateway] for the engine's tests: one map per space and
/// table, keyed by row key, holding the newest envelope pushed for each row
/// with its arrival sequence number — the fake's cursor.
class FakeSyncGateway implements SyncGateway {
  /// The longest space name `validSpace()` accepts (`firestore.rules`), in
  /// code points; an empty one is refused too. The cap lives only in the
  /// rules, so a picker tested against a fake that stored any string would
  /// pass here and meet `permission-denied` in production.
  static const int maxSpaceNameLength = 100;

  final Map<SyncSpaceRef, Map<String, Map<String, _Arrival>>> _store = {};
  final Map<SyncSpaceRef, Map<String, int>> _sequences = {};

  /// The created spaces, in creation order — the order [listSpaces] answers.
  final Map<SyncSpaceRef, _Space> _spaces = {};
  final Map<SyncSpaceRef, StreamController<SyncSpaceSignal>> _signals = {};
  var _clock = 0;
  var _elapsed = Duration.zero;

  /// Every batch accepted, in order.
  final List<List<SyncEnvelope>> pushes = [];

  /// Every pull and push attempted past a scripted failure, in order, as
  /// `pull:<table>` and `push:<pushedBy>` — so a test can read the order a
  /// run made its calls in, and which tables a pull touched. A deletion's
  /// steps join them as `mark`, `deleteRows:<table>` and `deleteSpace`.
  final List<String> calls = [];

  /// How many [readSpace] calls were made, scripted failures included — kept
  /// out of [calls] so the suites' exact call lists stay as they are.
  int readSpaceCalls = 0;

  /// The `limit` of every [deleteRows] call past a scripted failure, in
  /// order, null when none was passed.
  final List<int?> deleteLimits = [];

  /// How many arrival numbers before the cursor a resumed pull starts, so the
  /// engine's tests see the repeats Firestore's resume overlap delivers.
  int replayOnResume = 0;

  /// Every page asked for with `resumed` true from a cursor, by table, in
  /// order — the overlap re-reads the engine did not prove unnecessary.
  final List<String> resumedPulls = [];

  /// When true, a cursor carries its row's arrival time as Firestore's does
  /// (`<seq>|<micros>`), so [cursorTime] answers and the engine may prove a
  /// table settled; false, a cursor is the bare sequence number and every
  /// resumed page re-reads.
  bool timedCursors = false;

  /// When true, a new listener of [watchSpace] hears nothing — no first
  /// snapshot, no later one — as a resume whose snapshot has not come yet.
  bool holdSignals = false;

  @override
  Duration resumeOverlap = const Duration(seconds: 10);

  /// Moves the fake's server clock on by [by], so a write after it lands
  /// that much later than the one before.
  void elapse(Duration by) => _elapsed += by;

  /// When true, `hasMore` is `page.length == limit`, as the Firestore gateway
  /// answers without looking further — so the engine's tests meet "hasMore,
  /// then an empty page".
  bool looseHasMore = false;

  /// Documents, by table and row key, this build cannot turn into an
  /// envelope: dropped from the page the pull answers with while the cursor
  /// still advances over them, as `firestore_sync_gateway` does.
  final Set<(String, String)> unreadable = {};

  /// Run inside [pushBatch] once the batch is accepted and before it
  /// returns, so a test can land an edit or a restore in the window the
  /// acknowledgement has to survive.
  Future<void> Function(List<SyncEnvelope> batch)? onPushBatch;

  /// Run inside [pullPage] once the page is read and before it returns, so a
  /// test can land a rebind between the page's read and its transaction.
  Future<void> Function(String table)? onPullPage;

  /// Every page asked for, as `<table>:<limit>` with the limit the gateway
  /// applied — so a test reads the page sizes a run asked for.
  final List<String> pullTakes = [];

  /// The link modelled as bytes per call: a page whose envelopes' JSON
  /// passes it fails as [SyncGatewayException.timedOut] and changes nothing,
  /// as a page too large for a slow link outlasts the call's deadline.
  int? pullBytesPerCall;

  /// The same for a push: a batch whose rows' JSON passes it times out and
  /// writes nothing.
  int? pushBytesPerCall;

  SyncGatewayException? _nextFailure;
  int _failuresLeft = 0;
  final Map<(String, String), SyncGatewayFailure> _refused = {};

  /// The spaces [createSpace] has minted, never counted down: as Firestore's
  /// random ids never come back, a removed space's id is never reused.
  int _spacesCreated = 0;

  /// Makes the next call — any of them — throw [failure] and change nothing;
  /// the next [times] calls, for a link that stays down past a manual run's
  /// read of the space.
  void failNextWith(SyncGatewayFailure failure, {int times = 1}) {
    _nextFailure = SyncGatewayException(failure, 'scripted');
    _failuresLeft = times;
  }

  /// Makes the next call throw [error] and change nothing — for a kind
  /// [failNextWith] cannot name, such as [SyncGatewayException.timedOut].
  void failNextWithException(SyncGatewayException error) {
    _nextFailure = error;
    _failuresLeft = 1;
  }

  /// Makes every batch that carries [rowKey] of [table] fail with [failure]
  /// and write nothing, for as long as the test runs — the way the server
  /// keeps refusing one oversized or malformed document, so the engine's
  /// bisect-and-park can be seen isolating it while the rest lands.
  void refuse(String table, String rowKey, SyncGatewayFailure failure) =>
      _refused[(table, rowKey)] = failure;

  /// Lifts a [refuse], for an upload that is only late, not refused for good.
  void accept(String table, String rowKey) => _refused.remove((table, rowKey));

  /// Removes a space and every row under it at once, as a console delete
  /// would — no mark, no emptying: pushes are denied, reads answer null,
  /// listeners hear `exists: false`. The app's own delete is [deleteSpace].
  void consoleDeleteSpace(SyncSpaceRef space) {
    _spaces.remove(space);
    _store.remove(space);
    _sequences.remove(space);
    _signals[space]?.add(_signalNow(space));
  }

  /// Puts a space back under [space]'s own id, as a console restore would:
  /// [createSpace] never reuses an id, so this is how a test brings a
  /// removed space back.
  void consoleRestoreSpace(
    SyncSpaceRef space, {
    required String name,
    required String deviceId,
    required int schema,
  }) {
    final record = _Space(space)
      ..name = name
      ..createdAt = _tick()
      ..createdBy = deviceId
      ..schema = schema;
    _spaces[space] = record;
    _signals[space]?.add(record.signal);
  }

  /// Delivers [failure] as an error to every listener of [space]'s signal,
  /// as a dropped Firestore listener reports one; the listeners stay
  /// subscribed. Test-only, for the engine's re-attach back-off.
  void failWatches(SyncSpaceRef space, SyncGatewayFailure failure) =>
      _signals[space]?.addError(SyncGatewayException(failure, 'scripted'));

  /// Ends every listener of [space]'s signal, as a stream that completes;
  /// a later [watchSpace] listens afresh. Test-only, for the engine's
  /// `onDone`.
  void endWatches(SyncSpaceRef space) => _signals.remove(space)?.close();

  /// Writes [envelope] into the space as if another client pushed it, past
  /// every check — a malformed document the rules would never have let in,
  /// so the engine's per-envelope parking can meet one.
  void plant(SyncSpaceRef space, SyncEnvelope envelope) {
    final sequences = _sequences.putIfAbsent(space, () => {});
    final seq = sequences[envelope.table] =
        (sequences[envelope.table] ?? 0) + 1;
    _store
        .putIfAbsent(space, () => {})
        .putIfAbsent(envelope.table, () => {})[envelope.rowKey] = _Arrival(
      envelope,
      seq,
      _now(),
    );
  }

  /// What the space holds for [table], keyed by row key.
  Map<String, SyncEnvelope> rowsOf(SyncSpaceRef space, String table) =>
      Map.unmodifiable({
        for (final entry in (_store[space]?[table] ?? const {}).entries)
          entry.key: entry.value.envelope,
      });

  void _throwIfScripted() {
    final failure = _nextFailure;
    if (failure == null) return;
    if (--_failuresLeft <= 0) _nextFailure = null;
    throw failure;
  }

  /// The bytes [envelopes] carry on the wire, as the pusher counts them.
  static int bytesOf(Iterable<SyncEnvelope> envelopes) {
    var bytes = 0;
    for (final envelope in envelopes) {
      bytes += envelope.wireBytes;
    }
    return bytes;
  }

  /// Whether `firestore.rules`' `validChunk()` admits [envelope]: a
  /// `content_chunks` document is an upsert whose `gz` is bytes of at most
  /// 65,536 — the one shape rule of the rules the fake repeats, since it is
  /// the one this build's own pushes could break.
  static bool _chunkAdmitted(SyncEnvelope envelope) {
    if (envelope.table != 'content_chunks') return true;
    final gz = envelope.data?[ContentChunksBinding.gzKey];
    return envelope.op == OutboxOp.upsert &&
        gz is Uint8List &&
        gz.length <= ContentChunksBinding.maxGzBytes;
  }

  /// A clock that moves on every call, so no two writes share an instant.
  DateTime _tick() {
    ++_clock;
    return _now();
  }

  DateTime _now() =>
      DateTime.utc(2026, 1, 1).add(_elapsed + Duration(seconds: _clock));

  SyncSpaceSignal _signalNow(SyncSpaceRef space) =>
      _spaces[space]?.signal ??
      const SyncSpaceSignal(
        exists: false,
        touched: {},
        lastWriter: null,
        schema: 0,
      );

  StreamController<SyncSpaceSignal> _signalOf(SyncSpaceRef space) =>
      _signals.putIfAbsent(space, StreamController<SyncSpaceSignal>.broadcast);

  /// Settable, so a test can cut one stamp's rows over several batches the
  /// way a cascade of more than 500 rows is cut, without writing 500 rows.
  @override
  int maxBatch = 500;

  @override
  Future<void> pushBatch(
    SyncSpaceRef space,
    List<SyncEnvelope> batch, {
    required String pushedBy,
    required int schema,
  }) async {
    _throwIfScripted();
    calls.add('push:$pushedBy');
    if (batch.length > maxBatch) {
      throw ArgumentError.value(batch.length, 'batch', 'over the batch limit');
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
    final record = _spaces[space];
    if (record == null) {
      throw const SyncGatewayException(
        SyncGatewayFailure.permissionDenied,
        'no such space',
      );
    }
    if (record.deletedAt != null) {
      throw const SyncGatewayException(
        SyncGatewayFailure.permissionDenied,
        'space marked for deletion',
      );
    }
    if (schema < record.schema) {
      throw const SyncGatewayException(
        SyncGatewayFailure.permissionDenied,
        'schema below the space',
      );
    }
    for (final envelope in batch) {
      final refused = _refused[(envelope.table, envelope.rowKey)];
      if (refused != null) {
        throw SyncGatewayException(refused, 'refused ${envelope.rowKey}');
      }
      if (!_chunkAdmitted(envelope)) {
        throw SyncGatewayException(
          SyncGatewayFailure.permissionDenied,
          'not a chunk document: ${envelope.rowKey}',
        );
      }
    }
    final link = pushBytesPerCall;
    if (link != null && bytesOf(batch) > link) {
      throw const SyncGatewayException.timedOut();
    }
    final now = _tick();
    final tables = _store.putIfAbsent(space, () => {});
    final sequences = _sequences.putIfAbsent(space, () => {});
    for (final envelope in batch) {
      final seq = sequences[envelope.table] =
          (sequences[envelope.table] ?? 0) + 1;
      tables.putIfAbsent(envelope.table, () => {})[envelope.rowKey] = _Arrival(
        envelope,
        seq,
        now,
      );
      record.touched[envelope.table] = now;
    }
    record
      ..lastWriter = pushedBy
      ..lastWriteAt = now
      ..schema = schema;
    pushes.add(List.unmodifiable(batch));
    _signalOf(space).add(record.signal);
    await onPushBatch?.call(batch);
  }

  @override
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
    bool resumed = false,
    SyncCursor? scan,
  }) async {
    _throwIfScripted();
    calls.add('pull:$table');
    final rereads = resumed && after != null;
    if (rereads) resumedPulls.add(table);
    final cursor = after == null ? 0 : _seqOf(after);
    var from = cursor;
    if (rereads) {
      from = scan != null
          ? _seqOf(scan)
          : (from > replayOnResume ? from - replayOnResume : 0);
    }
    final pending = [
      for (final arrival in (_store[space]?[table] ?? const {}).values)
        if (arrival.seq > from) arrival,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    final take = limit ?? maxBatch;
    pullTakes.add('$table:$take');
    final page = pending.take(take).toList();
    final link = pullBytesPerCall;
    if (link != null && bytesOf([for (final a in page) a.envelope]) > link) {
      throw const SyncGatewayException.timedOut();
    }
    await onPullPage?.call(table);
    final hasMore = looseHasMore
        ? page.length == take
        : pending.length > page.length;
    // As Firestore's: a re-read never moves the cursor back, and one a full
    // page stopped short of it says where it goes on.
    final behind = rereads && page.isNotEmpty && page.last.seq <= cursor;
    return SyncPullPage(
      envelopes: [
        for (final arrival in page)
          if (!unreadable.contains((table, arrival.envelope.rowKey)))
            arrival.envelope,
      ],
      next: page.isEmpty || behind ? after : _cursorOf(page.last),
      hasMore: hasMore,
      scan: behind && hasMore && page.last.seq < cursor
          ? _cursorOf(page.last)
          : null,
      skipped: [
        for (final arrival in page)
          if (unreadable.contains((table, arrival.envelope.rowKey)))
            arrival.envelope.rowKey,
      ],
    );
  }

  /// Every [readRows] call's keys, as `<table>:<count>`.
  final List<String> rowReads = [];

  /// Every [readRows] call's keys themselves, in the order asked.
  final List<List<String>> rowReadKeys = [];

  /// Tables whose [readRows] fails offline and reads nothing, for a retry
  /// cut part-way.
  final Set<String> failRowReads = {};

  @override
  Future<SyncPullPage> readRows(
    SyncSpaceRef space,
    String table,
    List<String> rowKeys,
  ) async {
    _throwIfScripted();
    calls.add('read:$table');
    if (failRowReads.contains(table)) {
      throw const SyncGatewayException(SyncGatewayFailure.offline, 'scripted');
    }
    rowReads.add('$table:${rowKeys.length}');
    rowReadKeys.add(List.of(rowKeys));
    final stored = _store[space]?[table] ?? const <String, _Arrival>{};
    return SyncPullPage(
      envelopes: [
        for (final key in rowKeys)
          if (stored[key] case final arrival?)
            if (!unreadable.contains((table, key))) arrival.envelope,
      ],
      next: null,
      hasMore: false,
      skipped: [
        for (final key in rowKeys)
          if (stored.containsKey(key) && unreadable.contains((table, key))) key,
      ],
    );
  }

  static int _seqOf(SyncCursor cursor) =>
      int.parse(cursor.value.split('|').first);

  SyncCursor _cursorOf(_Arrival arrival) => SyncCursor(
    timedCursors
        ? '${arrival.seq}|${arrival.at.microsecondsSinceEpoch}'
        : '${arrival.seq}',
  );

  @override
  DateTime? cursorTime(SyncCursor cursor) {
    final bar = cursor.value.indexOf('|');
    if (bar < 0) return null;
    return DateTime.fromMicrosecondsSinceEpoch(
      int.parse(cursor.value.substring(bar + 1)),
      isUtc: true,
    );
  }

  @override
  Future<SyncSpaceInfo> createSpace({
    required String ownerUid,
    required String name,
    required String deviceId,
    required int schema,
  }) async {
    _throwIfScripted();
    // Runes, not `length`: CEL's `size()` counts code points, so a name of
    // 60 emoji is 60 to the rules and 120 to `String.length` (A8 review R154).
    final size = name.runes.length;
    if (size == 0 || size > maxSpaceNameLength) {
      throw SyncGatewayException(
        SyncGatewayFailure.permissionDenied,
        'space name of $size code points',
      );
    }
    final ref = SyncSpaceRef(
      ownerUid: ownerUid,
      spaceId: 'space-${++_spacesCreated}',
    );
    final record = _Space(ref)
      ..name = name
      ..createdAt = _tick()
      ..createdBy = deviceId
      ..schema = schema;
    _spaces[ref] = record;
    _signals[ref]?.add(record.signal);
    return record.info;
  }

  @override
  Future<List<SyncSpaceInfo>> listSpaces(String ownerUid) async {
    _throwIfScripted();
    return [
      for (final record in _spaces.values)
        if (record.ref.ownerUid == ownerUid) record.info,
    ];
  }

  @override
  Future<SyncSpaceInfo?> readSpace(SyncSpaceRef space) async {
    readSpaceCalls++;
    _throwIfScripted();
    return _spaces[space]?.info;
  }

  @override
  Stream<SyncSpaceSignal> watchSpace(SyncSpaceRef space) {
    try {
      _throwIfScripted();
    } on SyncGatewayException catch (error) {
      return Stream.multi((listener) {
        listener.addError(error);
        listener.close();
      }, isBroadcast: true);
    }
    if (holdSignals) {
      return Stream.multi((listener) {}, isBroadcast: true);
    }
    return Stream.multi((listener) {
      listener.add(_signalNow(space));
      final subscription = _signalOf(space).stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  @override
  Future<void> markSpaceDeleted(SyncSpaceRef space) async {
    _throwIfScripted();
    calls.add('mark');
    final record = _spaces[space];
    if (record == null || record.deletedAt != null) return;
    record.deletedAt = _tick();
    _signalOf(space).add(record.signal);
  }

  @override
  Future<int> deleteRows(SyncSpaceRef space, String table, {int? limit}) async {
    _throwIfScripted();
    calls.add('deleteRows:$table');
    deleteLimits.add(limit);
    const most = SyncGateway.rowDeleteBatch;
    final take = limit ?? most;
    if (take < 1 || take > most) {
      throw ArgumentError.value(take, 'limit', 'not within 1..$most');
    }
    final rows = _store[space]?[table];
    if (rows == null || rows.isEmpty) return 0;
    if (_spaces[space]?.deletedAt == null) {
      throw const SyncGatewayException(
        SyncGatewayFailure.permissionDenied,
        'rows of a space not marked for deletion',
      );
    }
    // Firestore's default order, by document id.
    final page = (rows.keys.toList()..sort()).take(take).toList();
    page.forEach(rows.remove);
    return page.length;
  }

  @override
  Future<void> deleteSpace(SyncSpaceRef space) async {
    _throwIfScripted();
    calls.add('deleteSpace');
    final record = _spaces[space];
    if (record == null) return;
    if (record.deletedAt == null) {
      throw const SyncGatewayException(
        SyncGatewayFailure.permissionDenied,
        'space not marked for deletion',
      );
    }
    // The rows stay, as Firestore leaves a deleted document's subcollections.
    _spaces.remove(space);
    _signals[space]?.add(_signalNow(space));
  }
}

class _Arrival {
  final SyncEnvelope envelope;
  final int seq;

  /// The server time it landed at — its `pushedAt`.
  final DateTime at;

  const _Arrival(this.envelope, this.seq, this.at);
}

/// The space document of a created space.
class _Space {
  final SyncSpaceRef ref;
  String name = '';
  DateTime? createdAt;
  String createdBy = '';
  int schema = 0;
  final Map<String, DateTime> touched = {};
  String? lastWriter;
  DateTime? lastWriteAt;

  /// Set by [FakeSyncGateway.markSpaceDeleted], never cleared.
  DateTime? deletedAt;

  _Space(this.ref);

  SyncSpaceSignal get signal => SyncSpaceSignal(
    exists: true,
    touched: Map.unmodifiable(touched),
    lastWriter: lastWriter,
    schema: schema,
    markedForDeletion: deletedAt != null,
  );

  SyncSpaceInfo get info => SyncSpaceInfo(
    ref: ref,
    name: name,
    createdAt: createdAt,
    createdBy: createdBy,
    schema: schema,
    lastWriteAt: lastWriteAt,
    lastWriter: lastWriter,
    markedForDeletion: deletedAt != null,
  );
}
