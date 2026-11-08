import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import 'support/sync_pair.dart';

/// Pull parks that outlive the session (scalability record S8): a document
/// this device could not merge is stored with its stamp, so a restart still
/// holds back the local entries at or below it; one with no readable stamp
/// is counted but held no longer; a start retries the stored parks — all of
/// them under a new build, until such a pass completes, and the
/// [SyncEngine.maxParkRetries] oldest otherwise.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  Future<void> restart() async {
    await a().engine.stop();
    await a().engine.start();
    await a().settle();
  }

  /// The stamp one counter step past [hlc] at the same wall time, from
  /// device C: above [hlc], below the next millisecond's stamps.
  String justAfter(String hlc, {int steps = 1}) {
    final stamp = HlcTimestamp.parse(hlc);
    final wall = stamp.wallTime.toRadixString(16).padLeft(12, '0');
    final counter = (stamp.logicalCounter + steps)
        .toRadixString(16)
        .padLeft(4, '0');
    return '$wall:$counter:C';
  }

  String? spaceWriterOf(String id) =>
      pair.gateway.rowsOf(pair.space, 'folders')[id]?.deviceId;

  /// The stamp stored for the park of [table]'s [rowKey], null for none.
  Future<String?> storedStamp(String table, String rowKey) async {
    final value = await a().db.syncDao.getValue(
      SyncDao.keyPullParked(table, rowKey),
    );
    return value?.split('|')[1];
  }

  /// A folder renamed on A and left unpushed, with a document for it from C
  /// that this build cannot merge planted at [hlc] — or just above the
  /// rename when null.
  Future<String> parkedFolder({String? hlc}) async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    await a().sync();
    await a().db.folderDao.updateFolder(id: folder.id, name: 'Renamed');
    final renamed = (await a().db.folderDao.getFolderById(folder.id))!;
    pair.gateway.plant(
      pair.space,
      folderEnvelope(
        folder.id,
        hlc ?? justAfter(renamed.hlcTimestamp),
        data: {JsonKeys.id: folder.id},
      ),
    );
    return folder.id;
  }

  /// [count] folder documents this build cannot merge, `p0` the oldest.
  void plantParks(int count) {
    for (var i = 0; i < count; i++) {
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          'p$i',
          '${(i + 1).toRadixString(16).padLeft(12, '0')}:0000:C',
          data: {JsonKeys.id: 'p$i'},
        ),
      );
    }
  }

  test('a stored park survives a stop and a start and still holds back the '
      'entries at or below its stamp, and no later one', () async {
    final id = await parkedFolder();

    expect((await a().sync()).parked, 1);
    expect(spaceWriterOf(id), 'C');
    expect(
      await storedStamp('folders', id),
      pair.gateway.rowsOf(pair.space, 'folders')[id]!.hlc,
    );

    await restart();

    expect(spaceWriterOf(id), 'C', reason: 'the rename is below the park');
    expect(a().engine.current.parkedCount, 1);

    await a().db.folderDao.updateFolder(id: id, name: 'Renamed again');
    await a().sync();

    expect(spaceWriterOf(id), 'A', reason: 'an edit above the park outranks');
  });

  test('a newer unreadable version of a stored park keeps its stamp and holds '
      'the row back for the session (S8 review F4)', () async {
    final id = await parkedFolder();
    await a().sync();
    final stamp = await storedStamp('folders', id);
    await restart();

    pair.gateway.plant(
      pair.space,
      folderEnvelope(id, justAfter(stamp!, steps: 2), name: 'Newer'),
    );
    pair.gateway.unreadable.add(('folders', id));
    await a().db.folderDao.updateFolder(id: id, name: 'Renamed again');
    await a().sync();

    expect(await storedStamp('folders', id), stamp);
    expect(spaceWriterOf(id), 'C', reason: 'two unmerged versions stand');
  });

  test('a park with no readable stamp is counted after a restart but holds '
      'nothing back', () async {
    final id = await parkedFolder(hlc: 'not-a-stamp');
    // A document this device holds no row of: nothing pushes over it, so its
    // park stays and is counted.
    pair.gateway.plant(
      pair.space,
      folderEnvelope('unknown', 'not-a-stamp', data: {JsonKeys.id: 'unknown'}),
    );

    expect((await a().sync()).parked, 2);
    expect(spaceWriterOf(id), 'C', reason: 'held for the session');
    expect(await storedStamp('folders', id), '');

    await restart();

    expect(spaceWriterOf(id), 'A', reason: 'not held across the launch');
    expect(await storedStamp('folders', 'unknown'), '');
    // The first park let go once our version replaced its document.
    expect(a().engine.current.parkedCount, 1);
  });

  test('a document the gateway skipped is parked with the cursor that passed '
      'it, and a new build that reads it merges it and lets go', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    await a().sync();
    pair.gateway.plant(
      pair.space,
      folderEnvelope(folder.id, justAfter(folder.hlcTimestamp), name: 'From C'),
    );
    pair.gateway.unreadable.add(('folders', folder.id));

    await a().sync();

    expect(await storedStamp('folders', folder.id), '');
    expect(a().engine.current.parkedCount, 1);

    pair.gateway.unreadable.clear();
    a().build = 'next';
    await restart();

    expect((await a().db.folderDao.getFolderById(folder.id))!.name, 'From C');
    expect(await storedStamp('folders', folder.id), isNull);
    expect(await a().db.syncDao.getValue(SyncDao.keyPullParkedBuild), 'next');
    expect(a().engine.current.parkedCount, 0);
  });

  test('a start retries every park until one pass completes, then the '
      '${SyncEngine.maxParkRetries} oldest, rotating, and every one again '
      'under a new build', () async {
    const count = SyncEngine.maxParkRetries + 5;
    plantParks(count);
    expect((await a().sync()).parked, count);
    expect(pair.gateway.rowReads, isEmpty);

    await restart();
    expect(pair.gateway.rowReads, ['folders:$count']);

    await restart();
    await restart();
    await restart();
    final [first, second, third] = pair.gateway.rowReadKeys.sublist(1);
    expect(first, [for (var i = 0; i < 100; i++) 'p$i']);
    expect(second.take(5), ['p100', 'p101', 'p102', 'p103', 'p104']);
    expect(third.take(5), ['p95', 'p96', 'p97', 'p98', 'p99']);

    a().build = 'next';
    await restart();
    expect(pair.gateway.rowReads.last, 'folders:$count');
    expect(a().engine.current.parkedCount, count);
  });

  test('a retry a failure cuts after one table owes every park again at the '
      'next start (S8 review F5)', () async {
    plantParks(SyncEngine.maxParkRetries + 5);
    pair.gateway.plant(
      pair.space,
      SyncEnvelope(
        table: 'notes',
        rowKey: 'n1',
        hlc: '000000000001:0000:C',
        deviceId: 'C',
        version: 1,
        op: OutboxOp.upsert,
        ownerId: syncUid,
        data: const {JsonKeys.id: 'n1'},
      ),
    );
    await a().sync();
    a().build = 'next';
    pair.gateway.failRowReads.add('notes');

    await restart();

    expect(pair.gateway.rowReads, ['folders:${SyncEngine.maxParkRetries + 5}']);
    expect(await a().db.syncDao.getValue(SyncDao.keyPullParkedBuild), isNull);

    pair.gateway.failRowReads.clear();
    await restart();

    expect(pair.gateway.rowReads.sublist(1), [
      'folders:${SyncEngine.maxParkRetries + 5}',
      'notes:1',
    ]);
    expect(await a().db.syncDao.getValue(SyncDao.keyPullParkedBuild), 'next');
  });

  test('unreadable parks rotate too: one met unreadable again is stored '
      'behind the others (S8 re-review R1)', () async {
    for (var i = 0; i < SyncEngine.maxParkRetries; i++) {
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          'u$i',
          '${(i + 1).toRadixString(16).padLeft(12, '0')}'
              ':0000:C',
        ),
      );
      pair.gateway.unreadable.add(('folders', 'u$i'));
    }
    pair.gateway.plant(
      pair.space,
      const SyncEnvelope(
        table: 'notes',
        rowKey: 'n1',
        hlc: '000000000001:0000:C',
        deviceId: 'C',
        version: 1,
        op: OutboxOp.upsert,
        ownerId: syncUid,
        data: {JsonKeys.id: 'n1'},
      ),
    );
    pair.gateway.unreadable.add(('notes', 'n1'));
    expect((await a().sync()).parked, SyncEngine.maxParkRetries + 1);

    await restart();
    await restart();
    await restart();

    expect(pair.gateway.rowReads, [
      'folders:${SyncEngine.maxParkRetries}',
      'notes:1',
      'folders:${SyncEngine.maxParkRetries}',
      'folders:${SyncEngine.maxParkRetries - 1}',
      'notes:1',
    ]);
    expect(a().engine.current.parkedCount, SyncEngine.maxParkRetries + 1);
  });

  test('a rebind drops the stored parks with the cursors', () async {
    await parkedFolder();
    expect((await a().sync()).parked, 1);

    await a().binding.unbind();

    expect(
      await a().db.syncDao.valuesByPrefix(SyncDao.pullParkedPrefix),
      isEmpty,
    );
    expect(await a().db.syncDao.getValue(SyncDao.keyPullParkedBuild), isNull);
  });

  test('note_seen survives a rebind to the same space and is dropped by a '
      'bind to another (S8 review F9)', () async {
    final key = SyncDao.keyNoteSeen('n1');
    await a().db.syncDao.raiseValue(key, '000000000005:0000:B');

    await a().binding.unbind();
    await pair.bind(a());
    expect(await a().db.syncDao.getValue(key), '000000000005:0000:B');

    final other = await pair.gateway.createSpace(
      ownerUid: syncUid,
      name: 'Other',
      deviceId: 'A',
      schema: syncSchema,
    );
    await a().binding.unbind();
    await a().binding.bind(space: other.ref, accountUid: syncUid);
    expect(await a().db.syncDao.getValue(key), isNull);
  });
}
