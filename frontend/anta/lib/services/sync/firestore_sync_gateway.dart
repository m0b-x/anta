import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

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
  /// The emulator suite's ports, as `firebase.emulators.json` declares them.
  static const int emulatorFirestorePort = 8080;

  /// Every call is bounded: the engine runs one request at a time, so a call
  /// that never answers would hold every later run. Long enough for a full
  /// batch of large notes over a slow link; a commit that lands after it is
  /// pushed again, which writes the same documents.
  static const Duration _timeout = Duration(seconds: 60);

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
  }) async {
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
    await _guard(() {
      final now = FieldValue.serverTimestamp();
      final write = _db.batch();
      final spaceDoc = _space(space);
      for (final envelope in batch) {
        write.set(
          spaceDoc.collection(envelope.table).doc(envelope.rowKey),
          FirestoreSyncWire.documentOf(
            envelope,
            pushedBy: pushedBy,
            serverTime: now,
          ),
        );
      }
      write.set(
        spaceDoc,
        FirestoreSyncWire.spaceMergeOf(
          {for (final envelope in batch) envelope.table},
          pushedBy: pushedBy,
          schema: schema,
          serverTime: now,
        ),
        SetOptions(merge: true),
      );
      return write.commit();
    });
  }

  @override
  Future<SyncPullPage> pullPage(
    SyncSpaceRef space,
    String table, {
    SyncCursor? after,
    int? limit,
    bool resumed = false,
  }) {
    final take = limit ?? maxBatch;
    return _guard(() async {
      Query<Map<String, dynamic>> query = _space(
        space,
      ).collection(table).orderBy('pushedAt').orderBy(FieldPath.documentId);
      if (after != null) {
        final (micros, rowKey) = FirestoreSyncWire.decodeCursor(after);
        query = resumed
            ? query.where(
                'pushedAt',
                isGreaterThanOrEqualTo: Timestamp.fromMicrosecondsSinceEpoch(
                  FirestoreSyncWire.overlapStart(micros),
                ),
              )
            : query.startAfter([
                Timestamp.fromMicrosecondsSinceEpoch(micros),
                rowKey,
              ]);
      }
      final snapshot = await query
          .limit(take)
          .get(const GetOptions(source: Source.server));
      final envelopes = <SyncEnvelope>[];
      var next = after;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final pushedAt = data['pushedAt'];
        // A pending server timestamp — never from a server read, but a
        // cursor cannot be made from it.
        if (pushedAt is! Timestamp) continue;
        next = FirestoreSyncWire.encodeCursor(
          pushedAt.microsecondsSinceEpoch,
          doc.id,
        );
        final envelope = FirestoreSyncWire.envelopeOf(table, doc.id, data);
        if (envelope == null) {
          // The rules admit no such document; skipped like a parked
          // envelope, so one cannot pin the pull at this cursor.
          debugPrint(
            '[FirestoreSyncGateway] skipped malformed $table/${doc.id}',
          );
          continue;
        }
        envelopes.add(envelope);
      }
      return SyncPullPage(
        envelopes: envelopes,
        next: next,
        hasMore: snapshot.docs.length == take,
      );
    });
  }

  @override
  Future<SyncSpaceInfo> createSpace({
    required String ownerUid,
    required String name,
    required String deviceId,
    required int schema,
  }) {
    return _guard(() async {
      final doc = _spaces(ownerUid).doc();
      await doc.set({
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': deviceId,
        'schema': schema,
      });
      // Read back rather than guess: `createdAt` is the server's.
      final created = await doc.get(const GetOptions(source: Source.server));
      final ref = SyncSpaceRef(ownerUid: ownerUid, spaceId: doc.id);
      return _infoOf(ref, created.data()) ??
          SyncSpaceInfo(
            ref: ref,
            name: name,
            createdAt: null,
            createdBy: deviceId,
            schema: schema,
          );
    });
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
    // bare completion.
    return Stream.multi((listener) {
      final subscription = _space(space).snapshots().listen(
        (snapshot) => listener.add(_signalOf(snapshot.data())),
        onError: (Object error) => listener.addError(_mapError(error)),
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    }, isBroadcast: true);
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
      throw _mapError(error);
    }
  }

  SyncGatewayException _mapError(Object error) => switch (error) {
    SyncGatewayException() => error,
    FirebaseException(:final code, :final message) => SyncGatewayException(
      FirestoreSyncWire.failureOf(code),
      message ?? code,
    ),
    TimeoutException() => const SyncGatewayException(
      SyncGatewayFailure.offline,
      'timed out',
    ),
    _ => SyncGatewayException(SyncGatewayFailure.unknown, '$error'),
  };
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

  /// Where a pull resumed from a cursor at [pushedAtMicros] starts.
  static int overlapStart(int pushedAtMicros) =>
      pushedAtMicros - pullOverlap.inMicroseconds;

  /// A row's document. `data` is always present — null for a tombstone — and
  /// [serverTime] (Firestore's server-timestamp sentinel) stamps `pushedAt`,
  /// which the rules require to be the request's time.
  static Map<String, Object?> documentOf(
    SyncEnvelope envelope, {
    required String pushedBy,
    required Object serverTime,
  }) => {
    'hlc': envelope.hlc,
    'deviceId': envelope.deviceId,
    'version': envelope.version,
    'op': envelope.op.name,
    'ownerId': envelope.ownerId,
    'data': envelope.data,
    'pushedAt': serverTime,
    'pushedBy': pushedBy,
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
    if (hlc is! String ||
        deviceId is! String ||
        version is! num ||
        op == null ||
        ownerId is! String ||
        !document.containsKey('data') ||
        (data != null && data is! Map)) {
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
      data: data == null ? null : Map<String, Object?>.from(data as Map),
    );
  }

  /// What a push merges into the space document: `touched` for each of
  /// [tables] as a nested map — a merge-set deep-merges maps, while a dotted
  /// key would be a field name with dots in it — the writer and this build's
  /// [schema], which the rules refuse when lower than the stored one.
  static Map<String, Object?> spaceMergeOf(
    Set<String> tables, {
    required String pushedBy,
    required int schema,
    required Object serverTime,
  }) => {
    'touched': {for (final table in tables) table: serverTime},
    'lastWriter': pushedBy,
    'lastWriteAt': serverTime,
    'schema': schema,
  };

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
