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

  SyncEnvelope envelope(
    String key,
    int at, {
    OutboxOp op = OutboxOp.upsert,
    String table = 'folders',
  }) => SyncEnvelope(
    table: table,
    rowKey: key,
    hlc: stamp(at),
    deviceId: 'dev',
    version: 1,
    op: op,
    data: op == OutboxOp.upsert ? {'id': key, 'name': 'Folder $key'} : null,
  );

  late FakeSyncGateway gateway;
  setUp(() => gateway = FakeSyncGateway());

  Future<void> push(
    List<SyncEnvelope> batch, {
    SyncSpaceRef to = space,
    String by = 'dev',
    int schema = 43,
  }) => gateway.pushBatch(to, batch, pushedBy: by, schema: schema);

  test('what is pushed comes back on a pull, in its own space only', () async {
    await push([envelope('a', 1), envelope('b', 2)]);

    final page = await gateway.pullPage(space, 'folders');
    expect(page.envelopes, [envelope('a', 1), envelope('b', 2)]);
    expect(page.hasMore, isFalse);
    expect((await gateway.pullPage(other, 'folders')).envelopes, isEmpty);
    expect((await gateway.pullPage(space, 'notes')).envelopes, isEmpty);
  });

  test('a pull follows arrival order, not stamp order', () async {
    await push([envelope('c', 30), envelope('a', 10), envelope('b', 20)]);

    final page = await gateway.pullPage(space, 'folders');

    expect(page.envelopes.map((e) => e.rowKey), ['c', 'a', 'b']);
  });

  test('a row pushed late with a lower stamp is still pulled', () async {
    await push([envelope('a', 2)]);
    final cursor = (await gateway.pullPage(space, 'folders')).next;

    await push([envelope('b', 1)], by: 'phone');
    final page = await gateway.pullPage(space, 'folders', after: cursor);

    expect(page.envelopes, [envelope('b', 1)]);
  });

  test('a page boundary inside one batch loses and repeats nothing', () async {
    await push([for (var i = 1; i <= 7; i++) envelope('r$i', i)]);

    final seen = <String>[];
    final hasMore = <bool>[];
    SyncCursor? cursor;
    for (var i = 0; i < 3; i++) {
      final page = await gateway.pullPage(
        space,
        'folders',
        after: cursor,
        limit: 3,
      );
      seen.addAll(page.envelopes.map((e) => e.rowKey));
      hasMore.add(page.hasMore);
      cursor = page.next;
    }

    expect(seen, [for (var i = 1; i <= 7; i++) 'r$i']);
    expect(hasMore, [true, true, false]);
  });

  test('a pull stops at maxBatch by default and resumes after it', () async {
    await push([
      for (var i = 1; i <= gateway.maxBatch; i++) envelope('r$i', i),
    ]);
    await push([envelope('last', 1000)]);

    final first = await gateway.pullPage(space, 'folders');
    final rest = await gateway.pullPage(space, 'folders', after: first.next);

    expect(first.envelopes, hasLength(gateway.maxBatch));
    expect(first.hasMore, isTrue);
    expect(rest.envelopes.map((e) => e.rowKey), ['last']);
    expect(rest.hasMore, isFalse);
  });

  test('an empty pull keeps the cursor it was given', () async {
    expect((await gateway.pullPage(space, 'folders')).next, isNull);

    await push([envelope('a', 1)]);
    final cursor = (await gateway.pullPage(space, 'folders')).next;
    final empty = await gateway.pullPage(space, 'folders', after: cursor);

    expect(empty.envelopes, isEmpty);
    expect(empty.next, cursor);
    expect(empty.hasMore, isFalse);
  });

  test('a re-pushed row appears once, at its newest state', () async {
    await push([envelope('a', 1), envelope('b', 2)]);
    final cursor = (await gateway.pullPage(space, 'folders')).next;

    await push([envelope('a', 9, op: OutboxOp.tombstone)]);
    final page = await gateway.pullPage(space, 'folders', after: cursor);

    expect(page.envelopes, [envelope('a', 9, op: OutboxOp.tombstone)]);
    final all = await gateway.pullPage(space, 'folders');
    expect(all.envelopes.map((e) => e.rowKey), ['b', 'a']);
    expect(gateway.rowsOf(space, 'folders')['a']!.data, isNull);
  });

  test('a batch over the limit is refused whole', () async {
    final tooMany = [
      for (var i = 0; i <= gateway.maxBatch; i++) envelope('r$i', i + 1),
    ];

    await expectLater(push(tooMany), throwsArgumentError);
    expect(gateway.rowsOf(space, 'folders'), isEmpty);
    expect(gateway.maxBatch, 500);
  });

  test('a scripted failure throws once and writes nothing', () async {
    gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

    await expectLater(
      push([envelope('a', 1)]),
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

    await push([envelope('a', 1)]);
    expect(gateway.rowsOf(space, 'folders').keys, ['a']);
  });

  test('a scripted failure on a pull throws and changes nothing', () async {
    await push([envelope('a', 1)]);
    gateway.failNextWith(SyncGatewayFailure.invalidData);

    await expectLater(
      gateway.pullPage(space, 'folders'),
      throwsA(
        isA<SyncGatewayException>().having(
          (e) => e.failure,
          'failure',
          SyncGatewayFailure.invalidData,
        ),
      ),
    );
    expect(gateway.rowsOf(space, 'folders').keys, ['a']);
    expect((await gateway.pullPage(space, 'folders')).envelopes, [
      envelope('a', 1),
    ]);
  });

  test('watchSpace emits the current signal, then one per push', () async {
    final signals = <SyncSpaceSignal>[];
    final subscription = gateway.watchSpace(space).listen(signals.add);
    await pumpEventQueue();

    expect(signals.single.touched, isEmpty);
    expect(signals.single.lastWriter, isNull);

    await push([envelope('a', 1)], by: 'phone', schema: 44);
    await pumpEventQueue();
    await push(
      [envelope('n', 2, table: 'notes'), envelope('e', 3, table: 'events')],
      by: 'tablet',
      schema: 43,
    );
    await pumpEventQueue();
    await subscription.cancel();

    expect(signals, hasLength(3));
    expect(signals[1].touched.keys, ['folders']);
    expect(signals[1].lastWriter, 'phone');
    expect(signals[1].schema, 44);

    // The tables a push moved are exactly the ones whose stamp advanced; the
    // space document keeps the older tables' stamps, as Firestore merges it.
    final moved = {
      for (final entry in signals[2].touched.entries)
        if (entry.value != signals[1].touched[entry.key]) entry.key,
    };
    expect(moved, {'notes', 'events'});
    expect(signals[2].lastWriter, 'tablet');
    expect(signals[2].schema, 44);
  });

  test('a late listener first hears the space as it stands', () async {
    await push([envelope('a', 1)], by: 'phone', schema: 44);

    final first = await gateway.watchSpace(space).first;

    expect(first.touched.keys, ['folders']);
    expect(first.lastWriter, 'phone');
    expect(first.schema, 44);
  });

  test('createSpace, listSpaces and readSpace round trip', () async {
    final main = await gateway.createSpace(
      ownerUid: 'owner',
      name: 'Main',
      deviceId: 'phone',
      schema: 43,
    );
    final work = await gateway.createSpace(
      ownerUid: 'owner',
      name: 'Work',
      deviceId: 'tablet',
      schema: 43,
    );
    await gateway.createSpace(
      ownerUid: 'stranger',
      name: 'Theirs',
      deviceId: 'x',
      schema: 43,
    );

    expect(main.ref, const SyncSpaceRef(ownerUid: 'owner', spaceId: 'space-1'));
    expect(work.ref.spaceId, 'space-2');
    expect(main.createdBy, 'phone');
    expect(main.createdAt, isNotNull);
    expect(await gateway.listSpaces('owner'), [main, work]);
    expect(await gateway.readSpace(main.ref), main);
    expect(await gateway.readSpace(other), isNull);

    await push([envelope('a', 1)], to: main.ref, by: 'tablet', schema: 44);
    final read = (await gateway.readSpace(main.ref))!;
    expect(read.schema, 44);
    expect(read.lastWriter, 'tablet');
    expect(read.lastWriteAt, isNotNull);
    expect(read.name, 'Main');
  });
}
