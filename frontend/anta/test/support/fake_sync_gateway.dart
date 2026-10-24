import 'dart:async';

import 'package:anta/services/sync/sync_gateway.dart';

/// An in-memory [SyncGateway] for the engine's tests: one map per space and
/// table, keyed by row key, holding the newest envelope pushed for each row
/// with its arrival sequence number — the fake's cursor.
class FakeSyncGateway implements SyncGateway {
  final Map<SyncSpaceRef, Map<String, Map<String, _Arrival>>> _store = {};
  final Map<SyncSpaceRef, Map<String, int>> _sequences = {};

  /// The created spaces, in creation order — the order [listSpaces] answers.
  final Map<SyncSpaceRef, _Space> _spaces = {};
  final Map<SyncSpaceRef, StreamController<SyncSpaceSignal>> _signals = {};
  var _clock = 0;

  /// Every batch accepted, in order.
  final List<List<SyncEnvelope>> pushes = [];

  /// Every pull and push attempted past a scripted failure, in order, as
  /// `pull:<table>` and `push:<pushedBy>` — so a test can read the order a
  /// run made its calls in, and which tables a pull touched.
  final List<String> calls = [];

  /// How many arrival numbers before the cursor a resumed pull starts, so the
  /// engine's tests see the repeats Firestore's resume overlap delivers.
  int replayOnResume = 0;

  /// When true, `hasMore` is `page.length == limit`, as the Firestore gateway
  /// answers without looking further — so the engine's tests meet "hasMore,
  /// then an empty page".
  bool looseHasMore = false;

  SyncGatewayFailure? _nextFailure;
  final Map<(String, String), SyncGatewayFailure> _refused = {};

  /// Makes the next call — any of them — throw [failure] and change nothing.
  void failNextWith(SyncGatewayFailure failure) => _nextFailure = failure;

  /// Makes every batch that carries [rowKey] of [table] fail with [failure]
  /// and write nothing, for as long as the test runs — the way the server
  /// keeps refusing one oversized or malformed document, so the engine's
  /// bisect-and-park can be seen isolating it while the rest lands.
  void refuse(String table, String rowKey, SyncGatewayFailure failure) =>
      _refused[(table, rowKey)] = failure;

  /// Removes a space, as a console delete would: pushes are denied, reads
  /// answer null, listeners hear `exists: false`.
  void deleteSpace(SyncSpaceRef space) {
    _spaces.remove(space);
    _store.remove(space);
    _sequences.remove(space);
    _signals[space]?.add(_signalNow(space));
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
    _nextFailure = null;
    throw SyncGatewayException(failure, 'scripted');
  }

  /// A clock that moves on every call, so no two writes share an instant.
  DateTime _tick() => DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_clock));

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

  @override
  int get maxBatch => 500;

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
      );
      record.touched[envelope.table] = now;
    }
    record
      ..lastWriter = pushedBy
      ..lastWriteAt = now
      ..schema = schema;
    pushes.add(List.unmodifiable(batch));
    _signalOf(space).add(record.signal);
  }

  @override
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
    bool resumed = false,
  }) async {
    _throwIfScripted();
    calls.add('pull:$table');
    var from = after == null ? 0 : int.parse(after.value);
    if (resumed && after != null) {
      from = from > replayOnResume ? from - replayOnResume : 0;
    }
    final pending = [
      for (final arrival in (_store[space]?[table] ?? const {}).values)
        if (arrival.seq > from) arrival,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    final take = limit ?? maxBatch;
    final page = pending.take(take).toList();
    return SyncPullPage(
      envelopes: [for (final arrival in page) arrival.envelope],
      next: page.isEmpty ? after : SyncCursor('${page.last.seq}'),
      hasMore: looseHasMore
          ? page.length == take
          : pending.length > page.length,
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
    final ref = SyncSpaceRef(
      ownerUid: ownerUid,
      spaceId: 'space-${_spaces.length + 1}',
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
}

class _Arrival {
  final SyncEnvelope envelope;
  final int seq;

  const _Arrival(this.envelope, this.seq);
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

  _Space(this.ref);

  SyncSpaceSignal get signal => SyncSpaceSignal(
    exists: true,
    touched: Map.unmodifiable(touched),
    lastWriter: lastWriter,
    schema: schema,
  );

  SyncSpaceInfo get info => SyncSpaceInfo(
    ref: ref,
    name: name,
    createdAt: createdAt,
    createdBy: createdBy,
    schema: schema,
    lastWriteAt: lastWriteAt,
    lastWriter: lastWriter,
  );
}
