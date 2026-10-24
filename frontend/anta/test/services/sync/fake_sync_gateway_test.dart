import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../support/fake_sync_gateway.dart';

/// Proves the fake keeps the [SyncGateway] contract, so engine tests written
/// against it hold against the real gateway too.
void main() {
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
    ownerId: 'owner',
    data: op == OutboxOp.upsert ? {'id': key, 'name': 'Folder $key'} : null,
  );

  Matcher failsWith(SyncGatewayFailure failure) => throwsA(
    isA<SyncGatewayException>().having((e) => e.failure, 'failure', failure),
  );

  late FakeSyncGateway gateway;
  late SyncSpaceInfo created;
  late SyncSpaceRef space;

  setUp(() async {
    gateway = FakeSyncGateway();
    created = await gateway.createSpace(
      ownerUid: 'owner',
      name: 'Main',
      deviceId: 'dev',
      schema: 43,
    );
    space = created.ref;
  });

  Future<void> push(
    List<SyncEnvelope> batch, {
    SyncSpaceRef? to,
    String by = 'dev',
    int schema = 43,
  }) => gateway.pushBatch(to ?? space, batch, pushedBy: by, schema: schema);

  test('what is pushed comes back on a pull, in its own space only', () async {
    final elsewhere = await gateway.createSpace(
      ownerUid: 'owner',
      name: 'Work',
      deviceId: 'dev',
      schema: 43,
    );
    await push([envelope('a', 1), envelope('b', 2)]);

    final page = await gateway.pullPage(space, 'folders');
    expect(page.envelopes, [envelope('a', 1), envelope('b', 2)]);
    expect(page.hasMore, isFalse);
    expect(
      (await gateway.pullPage(elsewhere.ref, 'folders')).envelopes,
      isEmpty,
    );
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

  test('a page that ends exactly on the last row has no more', () async {
    await push([for (var i = 1; i <= 7; i++) envelope('r$i', i)]);

    final page = await gateway.pullPage(space, 'folders', limit: 7);

    expect(page.envelopes, hasLength(7));
    expect(page.hasMore, isFalse);
  });

  test(
    'looseHasMore answers a full page as more, then an empty page',
    () async {
      gateway.looseHasMore = true;
      await push([for (var i = 1; i <= 3; i++) envelope('r$i', i)]);

      final full = await gateway.pullPage(space, 'folders', limit: 3);
      final empty = await gateway.pullPage(
        space,
        'folders',
        after: full.next,
        limit: 3,
      );

      expect(full.envelopes, hasLength(3));
      expect(full.hasMore, isTrue);
      expect(empty.envelopes, isEmpty);
      expect(empty.next, full.next);
      expect(empty.hasMore, isFalse);
    },
  );

  test('replayOnResume repeats rows on a resumed page only', () async {
    gateway.replayOnResume = 2;
    await push([for (var i = 1; i <= 5; i++) envelope('r$i', i)]);
    final stored = (await gateway.pullPage(space, 'folders', limit: 3)).next;

    final resumed = await gateway.pullPage(
      space,
      'folders',
      after: stored,
      limit: 2,
      resumed: true,
    );
    final following = await gateway.pullPage(
      space,
      'folders',
      after: resumed.next,
    );
    final unresumed = await gateway.pullPage(space, 'folders', after: stored);

    expect(resumed.envelopes.map((e) => e.rowKey), ['r2', 'r3']);
    expect(following.envelopes.map((e) => e.rowKey), ['r4', 'r5']);
    expect(unresumed.envelopes.map((e) => e.rowKey), ['r4', 'r5']);
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

  test(
    'a push to a space never created is denied and stores nothing',
    () async {
      await expectLater(
        push([envelope('a', 1)], to: other),
        failsWith(SyncGatewayFailure.permissionDenied),
      );

      expect(gateway.rowsOf(other, 'folders'), isEmpty);
      expect(gateway.pushes, isEmpty);
      expect(await gateway.readSpace(other), isNull);
      expect((await gateway.watchSpace(other).first).exists, isFalse);
    },
  );

  test(
    'a push below the space schema is denied; equal and higher land',
    () async {
      await expectLater(
        push([envelope('a', 1)], schema: 42),
        failsWith(SyncGatewayFailure.permissionDenied),
      );
      expect(gateway.rowsOf(space, 'folders'), isEmpty);
      expect(gateway.pushes, isEmpty);
      expect((await gateway.readSpace(space))!.schema, 43);

      await push([envelope('a', 1)], schema: 43);
      expect(gateway.rowsOf(space, 'folders').keys, ['a']);
      expect((await gateway.readSpace(space))!.schema, 43);

      await push([envelope('b', 2)], schema: 44);
      expect(gateway.rowsOf(space, 'folders').keys, ['a', 'b']);
      expect((await gateway.readSpace(space))!.schema, 44);

      await expectLater(
        push([envelope('c', 3)], schema: 43),
        failsWith(SyncGatewayFailure.permissionDenied),
      );
      expect(gateway.rowsOf(space, 'folders').keys, ['a', 'b']);
    },
  );

  test('a scripted failure throws once and writes nothing', () async {
    gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

    await expectLater(
      push([envelope('a', 1)]),
      failsWith(SyncGatewayFailure.quotaExhausted),
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
      failsWith(SyncGatewayFailure.invalidData),
    );
    expect(gateway.rowsOf(space, 'folders').keys, ['a']);
    expect((await gateway.pullPage(space, 'folders')).envelopes, [
      envelope('a', 1),
    ]);
  });

  test('a scripted failure on createSpace creates nothing', () async {
    gateway.failNextWith(SyncGatewayFailure.offline);

    await expectLater(
      gateway.createSpace(
        ownerUid: 'owner',
        name: 'Work',
        deviceId: 'dev',
        schema: 43,
      ),
      failsWith(SyncGatewayFailure.offline),
    );
    expect(await gateway.listSpaces('owner'), [created]);

    final work = await gateway.createSpace(
      ownerUid: 'owner',
      name: 'Work',
      deviceId: 'dev',
      schema: 43,
    );
    expect(await gateway.listSpaces('owner'), [created, work]);
  });

  test('a scripted failure on listSpaces and readSpace throws once', () async {
    gateway.failNextWith(SyncGatewayFailure.unknown);
    await expectLater(
      gateway.listSpaces('owner'),
      failsWith(SyncGatewayFailure.unknown),
    );
    expect(await gateway.listSpaces('owner'), [created]);

    gateway.failNextWith(SyncGatewayFailure.permissionDenied);
    await expectLater(
      gateway.readSpace(space),
      failsWith(SyncGatewayFailure.permissionDenied),
    );
    expect(await gateway.readSpace(space), created);
  });

  test(
    'a scripted failure on watchSpace is a broadcast stream error',
    () async {
      gateway.failNextWith(SyncGatewayFailure.offline);
      final failing = gateway.watchSpace(space);
      final error = emitsError(
        isA<SyncGatewayException>().having(
          (e) => e.failure,
          'failure',
          SyncGatewayFailure.offline,
        ),
      );

      expect(failing.isBroadcast, isTrue);
      await expectLater(failing, emitsInOrder([error, emitsDone]));
      // A second listener on the same stream hears the error too, no throw.
      await expectLater(failing, emitsInOrder([error, emitsDone]));

      final next = await gateway.watchSpace(space).first;
      expect(next.exists, isTrue);
      expect(next.schema, 43);
    },
  );

  test('watchSpace emits the current signal, then one per push', () async {
    final signals = <SyncSpaceSignal>[];
    final subscription = gateway.watchSpace(space).listen(signals.add);
    await pumpEventQueue();

    expect(signals.single.exists, isTrue);
    expect(signals.single.touched, isEmpty);
    expect(signals.single.lastWriter, isNull);

    await push([envelope('a', 1)], by: 'phone', schema: 44);
    await pumpEventQueue();
    await push(
      [
        envelope('n', 2, table: 'notes'),
        envelope('e', 3, table: 'calendar_events'),
      ],
      by: 'tablet',
      schema: 44,
    );
    await pumpEventQueue();
    await subscription.cancel();

    expect(signals, hasLength(3));
    expect(signals[1].touched.keys, ['folders']);
    expect(signals[1].lastWriter, 'phone');
    expect(signals[1].schema, 44);

    // The tables a push moved are exactly the ones whose stamp advanced; the
    // space document keeps the older tables' stamps, as Firestore merges it —
    // a fake that replaced `touched` would lose `folders` here.
    final moved = {
      for (final entry in signals[2].touched.entries)
        if (entry.value != signals[1].touched[entry.key]) entry.key,
    };
    expect(moved, {'notes', 'calendar_events'});
    expect(signals[2].touched.keys.toSet(), {
      'folders',
      'notes',
      'calendar_events',
    });
    expect(signals[2].touched['folders'], signals[1].touched['folders']);
    expect(signals[2].lastWriter, 'tablet');
    expect(signals[2].schema, 44);
  });

  test('two listeners on one watchSpace stream both hear a push', () async {
    final stream = gateway.watchSpace(space);
    final first = <SyncSpaceSignal>[];
    final second = <SyncSpaceSignal>[];
    final a = stream.listen(first.add);
    final b = stream.listen(second.add);
    await pumpEventQueue();

    await push([envelope('a', 1)], by: 'phone');
    await pumpEventQueue();
    await a.cancel();
    await b.cancel();

    for (final heard in [first, second]) {
      expect(heard, hasLength(2));
      expect(heard.last.touched.keys, ['folders']);
      expect(heard.last.lastWriter, 'phone');
    }
  });

  test('createSpace reaches a listener already watching its ref', () async {
    const next = SyncSpaceRef(ownerUid: 'owner', spaceId: 'space-2');
    final signals = <SyncSpaceSignal>[];
    final subscription = gateway.watchSpace(next).listen(signals.add);
    await pumpEventQueue();

    final work = await gateway.createSpace(
      ownerUid: 'owner',
      name: 'Work',
      deviceId: 'tablet',
      schema: 44,
    );
    await pumpEventQueue();
    await subscription.cancel();

    expect(work.ref, next);
    expect(signals, hasLength(2));
    expect(signals[0].exists, isFalse);
    expect(signals[0].touched, isEmpty);
    expect(signals[0].schema, 0);
    expect(signals[1].exists, isTrue);
    expect(signals[1].schema, 44);
  });

  test('a late listener first hears the space as it stands', () async {
    await push([envelope('a', 1)], by: 'phone', schema: 44);

    final first = await gateway.watchSpace(space).first;

    expect(first.exists, isTrue);
    expect(first.touched.keys, ['folders']);
    expect(first.lastWriter, 'phone');
    expect(first.schema, 44);
  });

  test('createSpace, listSpaces and readSpace round trip', () async {
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

    expect(space, const SyncSpaceRef(ownerUid: 'owner', spaceId: 'space-1'));
    expect(work.ref.spaceId, 'space-2');
    expect(created.createdBy, 'dev');
    expect(created.createdAt, isNotNull);
    expect(await gateway.listSpaces('owner'), [created, work]);
    expect(await gateway.readSpace(space), created);
    expect(await gateway.readSpace(other), isNull);

    await push([envelope('a', 1)], by: 'tablet', schema: 44);
    final read = (await gateway.readSpace(space))!;
    expect(read.schema, 44);
    expect(read.lastWriter, 'tablet');
    expect(read.lastWriteAt, isNotNull);
    expect(read.name, 'Main');
  });
}
