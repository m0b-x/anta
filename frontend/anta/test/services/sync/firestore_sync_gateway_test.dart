import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/services/sync/firestore_sync_gateway.dart';
import 'package:anta/services/sync/sync_gateway.dart';

/// The Firestore gateway's pure half — the cursor, the documents, the space
/// merge, the error codes, the resume overlap — and the boundary that keeps
/// `cloud_firestore` inside the two gateways. The calls themselves meet
/// Firestore only on the emulator suite (the rules probe, the S6 device pass).
void main() {
  const serverTime = #serverTime;

  SyncEnvelope envelope({
    OutboxOp op = OutboxOp.upsert,
    Map<String, Object?>? data = const {'id': 'f1', 'name': 'Training'},
  }) => SyncEnvelope(
    table: 'folders',
    rowKey: 'f1',
    hlc: '000000000001:0000:A',
    deviceId: 'A',
    version: 3,
    op: op,
    ownerId: 'u1',
    data: op == OutboxOp.tombstone ? null : data,
  );

  group('the cursor', () {
    test('round-trips a row key that holds bars of its own', () {
      final cursor = FirestoreSyncWire.encodeCursor(1700000000123456, 'c1|');
      expect(cursor.value, '1700000000123456|c1|');
      expect(FirestoreSyncWire.decodeCursor(cursor), (1700000000123456, 'c1|'));

      final composite = FirestoreSyncWire.encodeCursor(5, 'e1|1767225600000');
      expect(FirestoreSyncWire.decodeCursor(composite), (
        5,
        'e1|1767225600000',
      ));
    });

    test('orders by pushedAt first, then by row key', () {
      final cursors = [
        FirestoreSyncWire.encodeCursor(20, 'a'),
        FirestoreSyncWire.encodeCursor(10, 'z'),
        FirestoreSyncWire.encodeCursor(9, 'zz|1'),
        FirestoreSyncWire.encodeCursor(10, 'b'),
      ]..sort(FirestoreSyncWire.compareCursors);

      expect(cursors.map(FirestoreSyncWire.decodeCursor), [
        (9, 'zz|1'),
        (10, 'b'),
        (10, 'z'),
        (20, 'a'),
      ]);
      expect(
        FirestoreSyncWire.compareCursors(
          FirestoreSyncWire.encodeCursor(10, 'b'),
          FirestoreSyncWire.encodeCursor(10, 'b'),
        ),
        0,
      );
    });

    test('refuses a value it did not write', () {
      for (final value in ['', '42', 'abc|row', '|row']) {
        expect(
          () => FirestoreSyncWire.decodeCursor(SyncCursor(value)),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('a resumed pull starts ten seconds before the cursor', () {
      expect(FirestoreSyncWire.pullOverlap, const Duration(seconds: 10));
      expect(FirestoreSyncWire.overlapStart(60000000), 50000000);
    });
  });

  group('a row document', () {
    test('an upsert carries every field the rules allow, pushedAt the server '
        'time', () {
      final document = FirestoreSyncWire.documentOf(
        envelope(),
        pushedBy: 'A',
        serverTime: serverTime,
      );

      expect(document, {
        'hlc': '000000000001:0000:A',
        'deviceId': 'A',
        'version': 3,
        'op': 'upsert',
        'ownerId': 'u1',
        'data': {'id': 'f1', 'name': 'Training'},
        'pushedAt': serverTime,
        'pushedBy': 'A',
      });
    });

    test('a tombstone carries the data key as null and the owner', () {
      final document = FirestoreSyncWire.documentOf(
        envelope(op: OutboxOp.tombstone),
        pushedBy: 'B',
        serverTime: serverTime,
      );

      expect(document.containsKey('data'), isTrue);
      expect(document['data'], isNull);
      expect(document['op'], 'tombstone');
      expect(document['ownerId'], 'u1');
    });

    test('reads back as the envelope it was written from, both ops', () {
      for (final op in OutboxOp.values) {
        final written = envelope(op: op);
        final document = {
          ...FirestoreSyncWire.documentOf(
            written,
            pushedBy: 'A',
            serverTime: serverTime,
          ),
        };

        expect(
          FirestoreSyncWire.envelopeOf('folders', 'f1', document),
          written,
          reason: op.name,
        );
      }
    });

    test('a document without the data key, with an unknown op or a mistyped '
        'field reads as nothing', () {
      final good = FirestoreSyncWire.documentOf(
        envelope(),
        pushedBy: 'A',
        serverTime: serverTime,
      );
      final broken = [
        {...good}..remove('data'),
        {...good, 'op': 'delete'},
        {...good, 'hlc': 7},
        {...good, 'ownerId': null},
        {...good, 'data': 'text'},
      ];
      for (final document in broken) {
        expect(
          FirestoreSyncWire.envelopeOf('folders', 'f1', document),
          isNull,
          reason: '$document',
        );
      }
    });
  });

  test('the space merge names each pushed table under touched, the writer '
      'and this build\'s schema', () {
    expect(
      FirestoreSyncWire.spaceMergeOf(
        {'folders', 'notes'},
        pushedBy: 'A',
        schema: 43,
        serverTime: serverTime,
      ),
      {
        'touched': {'folders': serverTime, 'notes': serverTime},
        'lastWriter': 'A',
        'lastWriteAt': serverTime,
        'schema': 43,
      },
    );
  });

  test('a new space carries its name, creator and schema, createdAt the '
      'server time', () {
    expect(
      FirestoreSyncWire.spaceCreateOf(
        name: 'Main',
        deviceId: 'A',
        schema: 43,
        serverTime: serverTime,
      ),
      {'name': 'Main', 'createdAt': serverTime, 'createdBy': 'A', 'schema': 43},
    );
  });

  test('only a server snapshot without pending writes reaches the engine', () {
    expect(
      {
        for (final fromCache in [false, true])
          for (final pending in [false, true])
            (fromCache, pending): FirestoreSyncWire.shouldForwardSnapshot(
              isFromCache: fromCache,
              hasPendingWrites: pending,
            ),
      },
      {
        (false, false): true,
        (false, true): false,
        (true, false): false,
        (true, true): false,
      },
    );
  });

  test('an empty batch is refused before Firestore is touched', () {
    expect(
      () => FirestoreSyncGateway().pushBatch(
        const SyncSpaceRef(ownerUid: 'u1', spaceId: 's1'),
        const [],
        pushedBy: 'A',
        schema: 43,
      ),
      throwsArgumentError,
    );
  });

  test('error codes map onto the engine\'s failures', () {
    expect(
      {
        for (final code in [
          'unavailable',
          'deadline-exceeded',
          'resource-exhausted',
          'permission-denied',
          'unauthenticated',
          'invalid-argument',
          'failed-precondition',
          'aborted',
          'internal',
        ])
          code: FirestoreSyncWire.failureOf(code),
      },
      {
        'unavailable': SyncGatewayFailure.offline,
        'deadline-exceeded': SyncGatewayFailure.offline,
        'resource-exhausted': SyncGatewayFailure.quotaExhausted,
        'permission-denied': SyncGatewayFailure.permissionDenied,
        'unauthenticated': SyncGatewayFailure.permissionDenied,
        'invalid-argument': SyncGatewayFailure.invalidData,
        'failed-precondition': SyncGatewayFailure.unknown,
        'aborted': SyncGatewayFailure.unknown,
        'internal': SyncGatewayFailure.unknown,
      },
    );
  });

  test('the gateway batches one row fewer than Firestore allows', () {
    expect(FirestoreSyncGateway().maxBatch, 499);
  });

  test('no file outside the two gateways imports cloud_firestore or its '
      'platform interface', () {
    const allowed = {
      'lib/services/pairing_gateway.dart',
      'lib/services/sync/firestore_sync_gateway.dart',
    };
    final importers = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            RegExp(
              r'package:cloud_firestore(_platform_interface)?/',
            ).hasMatch(file.readAsStringSync()))
          file.path.replaceAll(r'\', '/'),
    ]..sort();

    expect(importers, allowed.toList()..sort());
  });
}
