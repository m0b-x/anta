import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../support/fake_sync_gateway.dart';

/// Proves the fake keeps the [SyncGateway] contract, so engine tests written
/// against it hold against the real gateway too.
void main() {
  const space = SyncSpaceRef(ownerUid: 'owner', spaceId: 'space');
  const other = SyncSpaceRef(ownerUid: 'owner', spaceId: 'elsewhere');

  String stamp(int n) => '${n.toRadixString(16).padLeft(12, '0')}:0000:dev';

  SyncEnvelope envelope(String key, int at, {OutboxOp op = OutboxOp.upsert}) =>
      SyncEnvelope(
        table: 'folders',
        rowKey: key,
        hlc: stamp(at),
        deviceId: 'dev',
        version: 1,
        op: op,
        data: op == OutboxOp.upsert ? {'id': key, 'name': 'Folder $key'} : null,
      );

  late FakeSyncGateway gateway;
  setUp(() => gateway = FakeSyncGateway());

  test('what is pushed comes back on a pull, in its own space only', () async {
    await gateway.pushBatch(space, [envelope('a', 1), envelope('b', 2)]);

    expect(await gateway.pullSince(space, 'folders'), [
      envelope('a', 1),
      envelope('b', 2),
    ]);
    expect(await gateway.pullSince(other, 'folders'), isEmpty);
    expect(await gateway.pullSince(space, 'notes'), isEmpty);
  });

  test('a pull returns what is newer than its cursor, oldest first', () async {
    await gateway.pushBatch(space, [
      envelope('c', 30),
      envelope('a', 10),
      envelope('b', 20),
    ]);

    final pulled = await gateway.pullSince(
      space,
      'folders',
      sinceHlc: stamp(10),
    );

    expect(pulled.map((e) => e.rowKey), ['b', 'c']);
  });

  test('a pull stops at its limit and resumes from the last stamp', () async {
    await gateway.pushBatch(space, [
      for (var i = 1; i <= SyncGateway.maxBatch; i++) envelope('r$i', i),
    ]);
    await gateway.pushBatch(space, [envelope('last', 1000)]);

    final first = await gateway.pullSince(space, 'folders');
    final rest = await gateway.pullSince(
      space,
      'folders',
      sinceHlc: first.last.hlc,
      sinceRowKey: first.last.rowKey,
    );

    expect(first, hasLength(SyncGateway.maxBatch));
    expect(rest.map((e) => e.rowKey), ['last']);
    expect(await gateway.pullSince(space, 'folders', limit: 3), hasLength(3));
  });

  test('rows sharing one stamp are all delivered across a page', () async {
    await gateway.pushBatch(space, [
      envelope('c', 5),
      envelope('a', 5),
      envelope('b', 5),
    ]);

    final first = await gateway.pullSince(space, 'folders', limit: 2);
    final rest = await gateway.pullSince(
      space,
      'folders',
      sinceHlc: first.last.hlc,
      sinceRowKey: first.last.rowKey,
      limit: 2,
    );

    expect(first.map((e) => e.rowKey), ['a', 'b']);
    expect(rest.map((e) => e.rowKey), ['c']);
  });

  test('a batch over the limit is refused whole', () async {
    final tooMany = [
      for (var i = 0; i <= SyncGateway.maxBatch; i++) envelope('r$i', i + 1),
    ];

    await expectLater(gateway.pushBatch(space, tooMany), throwsArgumentError);
    expect(gateway.rowsOf(space, 'folders'), isEmpty);
  });

  test('a scripted failure throws once and writes nothing', () async {
    gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

    await expectLater(
      gateway.pushBatch(space, [envelope('a', 1)]),
      throwsA(
        isA<SyncGatewayException>().having(
          (e) => e.failure,
          'failure',
          SyncGatewayFailure.quotaExhausted,
        ),
      ),
    );
    expect(gateway.rowsOf(space, 'folders'), isEmpty);
    expect(gateway.pushes, isEmpty);

    await gateway.pushBatch(space, [envelope('a', 1)]);
    expect(gateway.rowsOf(space, 'folders').keys, ['a']);
  });

  test('a repeated push keeps the newest stamp of each row', () async {
    await gateway.pushBatch(space, [envelope('a', 5)]);
    await gateway.pushBatch(space, [envelope('a', 5)]);
    await gateway.pushBatch(space, [envelope('a', 3)]);

    expect(gateway.rowsOf(space, 'folders')['a'], envelope('a', 5));

    await gateway.pushBatch(space, [envelope('a', 9, op: OutboxOp.tombstone)]);
    final row = gateway.rowsOf(space, 'folders')['a']!;
    expect(row.op, OutboxOp.tombstone);
    expect(row.data, isNull);
  });

  test('acknowledgements are recorded in order', () async {
    await gateway.ack(space, 'folders', stamp(4), 'a');
    await gateway.ack(space, 'notes', stamp(7), 'b');

    expect(gateway.acks.map((a) => (a.table, a.throughHlc, a.throughRowKey)), [
      ('folders', stamp(4), 'a'),
      ('notes', stamp(7), 'b'),
    ]);
  });
}
