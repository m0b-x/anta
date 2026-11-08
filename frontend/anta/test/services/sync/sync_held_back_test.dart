import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import 'support/sync_pair.dart';

/// Visibility and cadence (scalability record S7): push parks that outlive
/// the session and come round at every start, "Sync now" retrying the
/// oldest stored parks as a start does, a known row refused again never
/// read as a rules change, the held-back rows the status lists, and the push
/// at most [SyncEngineTiming.pushMaxWait] after the first write while writes
/// keep coming.
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
  /// device C.
  String justAfter(String hlc) {
    final stamp = HlcTimestamp.parse(hlc);
    final wall = stamp.wallTime.toRadixString(16).padLeft(12, '0');
    final counter = (stamp.logicalCounter + 1)
        .toRadixString(16)
        .padLeft(4, '0');
    return '$wall:$counter:C';
  }

  Map<String, Object> spaceFolders() =>
      pair.gateway.rowsOf(pair.space, 'folders');

  /// The stored push parks, `table.rowKey` → value, oldest first.
  Future<List<(String, String)>> storedPushParks() async {
    final rows = await a().db.syncDao.valuesByPrefix(SyncDao.pushParkedPrefix);
    return [
      for (final (key, value) in rows)
        (key.substring(SyncDao.pushParkedPrefix.length), value),
    ]..sort((x, y) => x.$2.compareTo(y.$2));
  }

  /// [count] folders the rules refuse, each parked by one "Sync now"; the
  /// ids in the order their parks were stored.
  Future<List<String>> refusedFolders(int count) async {
    for (var i = 0; i < count; i++) {
      final folder = await a().db.folderDao.createFolder(name: 'Folder $i');
      pair.gateway.refuse('folders', folder.id, SyncGatewayFailure.invalidData);
    }
    final report = await a().sync();
    expect(report.parked, count);
    return [
      for (final (key, _) in await storedPushParks())
        key.substring('folders.'.length),
    ];
  }

  void acceptAll(List<String> ids) {
    for (final id in ids) {
      pair.gateway.accept('folders', id);
    }
  }

  /// [count] new folders the rules deny, queued and not yet pushed.
  Future<void> denied(int count, String prefix) async {
    for (var i = 0; i < count; i++) {
      final folder = await a().db.folderDao.createFolder(name: '$prefix$i');
      pair.gateway.refuse(
        'folders',
        folder.id,
        SyncGatewayFailure.permissionDenied,
      );
    }
  }

  /// 25 permission-refused push parks, stored by two drains of 15 and 10 on
  /// a started engine — one drain of 25 fresh refusals would read as a
  /// rules change.
  Future<void> storeDeniedParks() async {
    await a().engine.start();
    await a().settle();
    for (final (count, prefix) in const [(15, 'A'), (10, 'B')]) {
      await denied(count, prefix);
      await a().engine.onAppBackgrounded();
      a().engine.onAppResumed();
      await a().settle();
    }
    expect(await storedPushParks(), hasLength(25));
    expect(a().engine.current.pause, SyncPause.none);
  }

  group('push parks', () {
    test('a push park is stored with its stamp and reason, survives a stop '
        'and a start past the retries, and holds its entry back', () async {
      final ids = await refusedFolders(SyncEngine.maxParkRetries + 1);
      final newest = ids.last;
      final stamp = (await a().db.folderDao.getFolderById(
        newest,
      ))!.hlcTimestamp;
      expect((await storedPushParks()).last.$2, endsWith('|$stamp|refused'));
      acceptAll(ids);

      await restart();

      expect(
        spaceFolders().keys.toSet(),
        ids.take(SyncEngine.maxParkRetries).toSet(),
        reason: 'the ${SyncEngine.maxParkRetries} oldest were tried again',
      );
      expect(spaceFolders(), isNot(contains(newest)));
      expect(await storedPushParks(), hasLength(1));
      expect(a().engine.current.parkedCount, 1);
      expect(a().engine.current.heldBack.single.rowKey, newest);
      expect(a().engine.current.heldBack.single.reason, SyncHeldReason.refused);

      await a().engine.onAppBackgrounded();
      expect(spaceFolders(), isNot(contains(newest)), reason: 'still held');
    });

    test('an edit past the park\'s stamp lets go of it', () async {
      final ids = await refusedFolders(SyncEngine.maxParkRetries + 1);
      final newest = ids.last;
      acceptAll(ids);
      await restart();
      expect(spaceFolders(), isNot(contains(newest)));

      await a().db.folderDao.updateFolder(id: newest, name: 'Renamed');
      await a().engine.onAppBackgrounded();

      expect(spaceFolders(), contains(newest));
      expect(await storedPushParks(), isEmpty);
      await a().settle();
      expect(a().engine.current.parkedCount, 0);
    });

    test('a start under a new build tries every stored park again', () async {
      final ids = await refusedFolders(SyncEngine.maxParkRetries + 1);
      acceptAll(ids);
      a().build = 'next';

      await restart();

      expect(spaceFolders().keys.toSet(), ids.toSet());
      expect(await storedPushParks(), isEmpty);
      expect(await a().db.syncDao.getValue(SyncDao.keyPushParkedBuild), 'next');
    });

    test('a park refused again at a start is stored again behind the others, '
        'so the next start reaches the rest', () async {
      final ids = await refusedFolders(SyncEngine.maxParkRetries + 1);

      await restart();

      final after = [
        for (final (key, _) in await storedPushParks())
          key.substring('folders.'.length),
      ];
      expect(after.first, ids.last, reason: 'the one not retried is oldest');
      expect(after.skip(1), ids.take(SyncEngine.maxParkRetries));
    });

    test('a bind and an unbind drop the stored push parks', () async {
      await refusedFolders(1);
      expect(await storedPushParks(), hasLength(1));

      await a().binding.unbind();

      expect(await storedPushParks(), isEmpty);
      expect(await a().db.syncDao.getValue(SyncDao.keyPushParkedBuild), isNull);
    });
  });

  group('"Sync now"', () {
    test('tries a stored push park again at once', () async {
      final ids = await refusedFolders(1);
      acceptAll(ids);

      final report = await a().sync();

      expect(report.pushedRows, 1);
      expect(spaceFolders(), contains(ids.single));
      expect(await storedPushParks(), isEmpty);
      expect(a().engine.current.heldBack, isEmpty);
    });

    test('tries the ${SyncEngine.maxParkRetries} oldest stored push parks '
        'again, as a start does', () async {
      final ids = await refusedFolders(SyncEngine.maxParkRetries + 1);
      acceptAll(ids);

      await a().sync();

      expect(
        spaceFolders().keys.toSet(),
        ids.take(SyncEngine.maxParkRetries).toSet(),
      );
      expect(await storedPushParks(), hasLength(1));
    });

    test('reads a stored pull park\'s document again at once', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Training');
      await a().sync();
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          folder.id,
          justAfter(folder.hlcTimestamp),
          name: 'From C',
        ),
      );
      pair.gateway.unreadable.add(('folders', folder.id));
      await a().sync();
      expect(
        await a().db.syncDao.getValue(
          SyncDao.keyPullParked('folders', folder.id),
        ),
        isNotNull,
      );
      expect(
        a().engine.current.heldBack.single.reason,
        SyncHeldReason.unreadable,
      );

      pair.gateway.unreadable.clear();
      await a().sync();

      expect((await a().db.folderDao.getFolderById(folder.id))!.name, 'From C');
      expect(
        await a().db.syncDao.getValue(
          SyncDao.keyPullParked('folders', folder.id),
        ),
        isNull,
      );
      expect(a().engine.current.heldBack, isEmpty);
    });
  });

  group('"Sync now" over the pull parks', () {
    /// [count] folder documents the space holds and this device cannot read,
    /// planted from device C under ids starting with [prefix].
    void plantUnreadable(int count, String prefix) {
      for (var i = 0; i < count; i++) {
        final id = '$prefix$i';
        pair.gateway.plant(
          pair.space,
          folderEnvelope(id, '000000000001:0000:C'),
        );
        pair.gateway.unreadable.add(('folders', id));
      }
    }

    /// [count] unreadable documents parked, and one press past them so the
    /// build their retry is due under is stored.
    Future<void> parkUnreadable(int count) async {
      plantUnreadable(count, 'u');
      await a().sync();
      await a().sync();
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullParkedBuild),
        SyncEngine.build,
      );
    }

    List<String> keysRead() => [
      for (final keys in pair.gateway.rowReadKeys) ...keys,
    ];

    test('reads the ${SyncEngine.maxParkRetries} oldest of '
        '${SyncEngine.maxParkRetries + 1} stored ones', () async {
      await parkUnreadable(SyncEngine.maxParkRetries + 1);
      await restart();
      pair.gateway.rowReadKeys.clear();

      await a().sync();

      expect(keysRead(), hasLength(SyncEngine.maxParkRetries));
    });

    test('reads this session\'s parks before the stored ones', () async {
      await parkUnreadable(SyncEngine.maxParkRetries);
      await restart();
      plantUnreadable(1, 'late');
      await a().sync();
      pair.gateway.rowReadKeys.clear();

      await a().sync();

      expect(keysRead(), hasLength(SyncEngine.maxParkRetries));
      expect(keysRead().first, 'late0');
    });
  });

  group('known refusals', () {
    test('"Sync now" over 25 stored permission-refused parks pauses nothing '
        'and parks them again', () async {
      await storeDeniedParks();
      final before = await storedPushParks();

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(a().engine.current.pause, SyncPause.none);
      expect(report.parked, 25, reason: 'every one was tried again');
      final after = await storedPushParks();
      expect(
        {for (final (key, _) in after) key},
        {for (final (key, _) in before) key},
      );
      expect(after.first.$2, isNot(before.first.$2), reason: 'a new order');
      expect(a().engine.current.parkedCount, 25);
    });

    test('a start over 25 of them ends with no pause', () async {
      await storeDeniedParks();

      await restart();

      expect(a().engine.current.pause, SyncPause.none);
      expect(await storedPushParks(), hasLength(25));
    });

    test('a retry the link cuts keeps them stored and listed, and the next '
        'press reads their refusals as known still', () async {
      await storeDeniedParks();
      final ids = [
        for (final (key, _) in await storedPushParks())
          key.substring('folders.'.length),
      ];
      for (final id in ids) {
        pair.gateway.refuse('folders', id, SyncGatewayFailure.offline);
      }

      final offline = await a().sync();

      expect(offline.failure, SyncGatewayFailure.offline);
      expect(await storedPushParks(), hasLength(25));
      expect(a().engine.current.parkedCount, 25);
      expect(
        {for (final item in a().engine.current.heldBack) item.reason},
        {SyncHeldReason.refused},
        reason: 'listed under their stored reason while they wait',
      );

      for (final id in ids) {
        pair.gateway.refuse('folders', id, SyncGatewayFailure.permissionDenied);
      }
      final online = await a().sync();

      expect(online.failure, isNull);
      expect(a().engine.current.pause, SyncPause.none);
      expect(await storedPushParks(), hasLength(25));
    });

    test('a stop in the middle of the retry keeps the stored parks', () async {
      final ids = await refusedFolders(3);
      final before = await storedPushParks();
      acceptAll(ids);
      Future<void>? stopping;
      pair.gateway.onPushBatch = (_) async {
        // Not awaited: the stop waits for this very run.
        stopping ??= a().engine.stop();
      };

      final halted = await a().sync();
      await stopping;

      expect(halted.skipped, SyncRunSkip.stopped);
      expect(await storedPushParks(), before);
    });

    test('a 21st fresh refusal in the same drain still reads as the rules '
        'changing', () async {
      await storeDeniedParks();
      // One past the pusher's 20 fresh refusals per drain.
      await denied(21, 'C');

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(a().engine.current.pause, SyncPause.noAccess);
    });
  });

  test('a kept chunk park holds its chunk back when a restart meets its note '
      'raised', () async {
    // The oldest parks, so the chunk's park is kept at the next start.
    for (var i = 0; i < SyncEngine.maxParkRetries; i++) {
      final folder = await a().db.folderDao.createFolder(name: 'F$i');
      pair.gateway.refuse('folders', folder.id, SyncGatewayFailure.invalidData);
    }
    await a().sync();
    await a().engine.start();
    await a().settle();
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await a().db.noteDao.createNote(
      folderId: folder.id,
      title: 'Leg day',
      content: 'Squat 5x5',
    );
    final hash = (await a().db.contentChunkDao.hashesOf(note.id)).single!;
    pair.gateway.refuse('content_chunks', hash, SyncGatewayFailure.invalidData);
    await a().engine.onAppBackgrounded();
    final chunkKey = SyncDao.keyPushParked('content_chunks', hash);
    final before = await a().db.syncDao.getValue(chunkKey);
    expect(before, isNotNull);

    await a().db.noteDao.updateNotePosition(id: note.id, newPosition: 5);
    await restart();

    expect(
      await a().db.syncDao.getValue(chunkKey),
      before,
      reason: 'not pushed again, so not parked again under a new order',
    );
    expect(pair.gateway.rowsOf(pair.space, 'notes'), isNot(contains(note.id)));
  });

  test('a start that is signed out still lists the stored parks', () async {
    final ids = await refusedFolders(1);
    await a().engine.stop();
    a().user = null;

    await a().engine.start();
    await a().settle();

    expect(a().engine.current.pause, SyncPause.signedOut);
    expect(a().engine.current.parkedCount, 1);
    expect(a().engine.current.heldBack.single.rowKey, ids.single);
  });

  test('a refused chunk and the manifest it holds back are one held-back '
      'row, the note, refused', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await a().db.noteDao.createNote(
      folderId: folder.id,
      title: 'Leg day',
      content: 'Squat 5x5',
    );
    final hash = (await a().db.contentChunkDao.hashesOf(note.id)).single!;
    pair.gateway.refuse('content_chunks', hash, SyncGatewayFailure.invalidData);

    final report = await a().sync();

    expect(report.parked, 2, reason: 'the chunk and the manifest');
    expect(a().engine.current.parkedCount, 1);
    expect(a().engine.current.heldBack, [
      SyncHeldItem(
        table: 'notes',
        rowKey: note.id,
        kind: SyncHeldKind.note,
        name: 'Leg day',
        reason: SyncHeldReason.refused,
      ),
    ]);
  });

  group('push cadence', () {
    const step = Duration(seconds: 10);

    /// Writes a folder every [step] for [span] on a started engine, moving
    /// the scheduler's clock with it, and returns when each push went out.
    Future<List<Duration>> typeFor(Duration span, {Duration? every}) async {
      await a().engine.start();
      await a().settle();
      final scheduler = a().scheduler;
      final pushes = <Duration>[];
      var written = Duration.zero;
      final gap = every ?? step;
      while (scheduler.elapsed < span) {
        if (scheduler.elapsed >= written) {
          await a().db.folderDao.createFolder(name: 'At ${scheduler.elapsed}');
          written += gap;
          await pumpEventQueue();
        }
        pair.gateway.calls.clear();
        scheduler.elapse(step);
        await a().settle();
        if (pair.gateway.calls.contains('push:A')) {
          pushes.add(scheduler.elapsed);
        }
      }
      return pushes;
    }

    test(
      'writes every 10 s for 5 min push once, 3 min after the first',
      () async {
        final pushes = await typeFor(const Duration(minutes: 5));

        expect(pushes, [const SyncEngineTiming().pushMaxWait]);
      },
    );

    test('one write then quiet pushes after 30 s, and the drain cancels the '
        'longest wait', () async {
      final pushes = await typeFor(
        const Duration(minutes: 1),
        every: const Duration(hours: 1),
      );

      expect(pushes, [const SyncEngineTiming().pushDebounce]);
      expect(
        a().scheduler.pending,
        isNot(contains(const Duration(minutes: 3))),
      );
    });

    test('a stop cancels both waits', () async {
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      expect(
        a().scheduler.pending,
        containsAll(const [Duration(seconds: 30), Duration(minutes: 3)]),
      );

      await a().engine.stop();

      expect(a().scheduler.pending, isEmpty);
    });

    test('the longest wait under a quota hold calls nothing', () async {
      // 04:00 in Los Angeles: the quota's retry is an hour away.
      a().now = () => DateTime.utc(2026, 11, 8, 12);
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'First');
      pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted);
      await a().sync();
      expect(a().engine.current.pause, SyncPause.quotaExhausted);
      await a().db.folderDao.createFolder(name: 'Second');
      await pumpEventQueue();
      pair.gateway.calls.clear();
      final reads = pair.gateway.readSpaceCalls;

      a().scheduler.elapse(const SyncEngineTiming().pushMaxWait);
      await a().settle();

      expect(pair.gateway.calls, isEmpty);
      expect(pair.gateway.readSpaceCalls, reads);
      expect(spaceFolders(), isEmpty);
    });

    test('a leave cancels the longest wait', () async {
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      expect(a().scheduler.pending, contains(const Duration(minutes: 3)));

      final drained = a().engine.onAppBackgrounded();

      expect(
        a().scheduler.pending,
        isNot(contains(const Duration(minutes: 3))),
      );
      await drained;
    });

    test('the longest wait firing while the debounce\'s run pulls is served '
        'by that run\'s drain, with no run behind it', () async {
      // No snapshot: the debounce's stale run pulls every table.
      pair.gateway.holdSignals = true;
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      const timing = SyncEngineTiming();
      var fired = 0;
      pair.gateway.onPullPage = (_) async {
        if (fired > 0) return;
        fired = a().scheduler.elapse(timing.pushMaxWait - timing.pushDebounce);
      };
      pair.gateway.calls.clear();

      a().scheduler.elapse(timing.pushDebounce);
      await a().settle();

      expect(fired, greaterThan(0), reason: 'the longest wait fired mid-pull');
      expect(spaceFolders(), hasLength(1));
      expect(
        pair.gateway.calls.where((c) => c == 'pull:folders'),
        hasLength(1),
      );
      expect(pair.gateway.calls.where((c) => c.startsWith('push:')), [
        'push:A',
      ]);
    });

    test('the longest wait left to a run that ends with no drain arms the '
        'debounce again', () async {
      pair.gateway.holdSignals = true;
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      const timing = SyncEngineTiming();
      final restore = Completer<void>();
      var fired = 0;
      pair.gateway.onPullPage = (_) async {
        if (fired > 0) return;
        fired = a().scheduler.elapse(timing.pushMaxWait - timing.pushDebounce);
        unawaited(SyncSuspension.run(() => restore.future));
      };

      a().scheduler.elapse(timing.pushDebounce);
      await a().settle();

      expect(fired, greaterThan(0), reason: 'the longest wait fired mid-pull');
      expect(
        spaceFolders(),
        isEmpty,
        reason: 'the suspended run never drained',
      );
      expect(a().scheduler.pending, contains(timing.pushDebounce));

      restore.complete();
      await pumpEventQueue();
      pair.gateway.onPullPage = null;
      a().scheduler.elapse(timing.pushDebounce);
      await a().settle();

      expect(spaceFolders(), hasLength(1));
    });
  });
}
