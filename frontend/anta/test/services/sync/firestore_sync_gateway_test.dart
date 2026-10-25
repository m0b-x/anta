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
        FirestoreSyncWire.encodeCursor(10, 'b'),
      ];
      final decoded = cursors.map(FirestoreSyncWire.decodeCursor).toList()
        ..sort((x, y) {
          final byTime = x.$1.compareTo(y.$1);
          return byTime != 0 ? byTime : x.$2.compareTo(y.$2);
        });
      expect(decoded, [(10, 'b'), (10, 'z'), (20, 'a')]);
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

  test('no file outside the two gateways imports cloud_firestore', () {
    const allowed = {
      'lib/services/pairing_gateway.dart',
      'lib/services/sync/firestore_sync_gateway.dart',
    };
    final importers = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('package:cloud_firestore/'))
          file.path.replaceAll(r'\', '/'),
    ]..sort();

    expect(importers, allowed.toList()..sort());
  });
}
