import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_tables.dart';

import 'support/sync_pair.dart';

/// What a run costs (scalability record S9): the equal-stamp ack that keeps
/// a rebind from uploading everything again, the resume that pulls only
/// what the snapshot names, the overlap re-read skipped for a settled table,
/// the quota retry's time and the run's counters.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  List<String> pulls() => [
    for (final call in pair.gateway.calls)
      if (call.startsWith('pull:')) call.substring(5),
  ];

  /// Every table a run pulls: the chunks travel on the push only.
  final pulledTables = [
    for (final b in syncTableBindings)
      if (b.pulls) b,
  ];

  /// A started A that pulled everything once and then left the foreground.
  Future<void> startThenLeave() async {
    await a().engine.start();
    await a().settle();
    await a().engine.onAppBackgrounded();
    await a().settle();
    pair.gateway.calls.clear();
    pair.gateway.resumedPulls.clear();
  }

  group('the equal-stamp ack', () {
    test('a rebind of identical data pushes nothing', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      await a().db.folderDao.createFolder(name: 'Food');
      await a().sync();
      final pushes = pair.gateway.pushes.length;

      await a().binding.unbind();
      await pair.bind(a());
      expect(await a().db.syncOutboxDao.count(), greaterThan(0));
      final report = await a().sync();

      expect(report.pushedRows, 0);
      expect(pair.gateway.pushes, hasLength(pushes));
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('a Merge of a database the space already holds pushes '
        'nothing', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      await a().sync();
      await b().sync();
      expect(await b().db.select(b().db.folders).get(), hasLength(1));
      final pushes = pair.gateway.pushes.length;

      await b().binding.unbind();
      await pair.bind(b());
      final report = await b().sync();

      expect(report.pushedRows, 0);
      expect(pair.gateway.pushes, hasLength(pushes));
      expect(await b().db.syncOutboxDao.count(), 0);
    });
  });

  group('the resume', () {
    test('an idle resume pulls nothing; after a push it pulls only what '
        'moved', () async {
      await startThenLeave();

      a().engine.onAppResumed();
      await a().settle();
      expect(pulls(), isEmpty, reason: 'the snapshot names nothing new');

      await a().engine.onAppBackgrounded();
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      pair.gateway.calls.clear();
      a().engine.onAppResumed();
      await a().settle();

      expect(pulls(), ['folders']);
      expect(await a().db.select(a().db.folders).get(), hasLength(1));
      expect(
        a().scheduler.pending,
        isNot(contains(SyncEngine.resumeSnapshotWait)),
        reason: 'the snapshot cancelled the fallback',
      );
    });

    test('a resume whose snapshot does not come pulls every table after '
        '5 s, and says so in its log line', () async {
      await startThenLeave();
      pair.gateway.holdSignals = true;

      a().engine.onAppResumed();
      await a().settle();
      expect(pulls(), isEmpty);
      expect(a().scheduler.pending, contains(SyncEngine.resumeSnapshotWait));

      final lines = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      addTearDown(() => debugPrint = print);
      expect(a().scheduler.fire(SyncEngine.resumeSnapshotWait), 1);
      await a().settle();
      debugPrint = print;

      expect(pulls(), hasLength(pulledTables.length));
      final runs = lines.where((l) => l.startsWith('[SyncEngine] run '));
      expect(runs.single, contains('run full'));
      expect(runs.single, contains('fallbacks 1'));
    });

    test('a resume a day after the last full pull pulls every table at '
        'once', () async {
      await startThenLeave();
      final dayAgo = DateTime.now().subtract(SyncEngine.fullPullInterval);
      await a().db.syncDao.setValue(
        SyncDao.keyFullPullAt,
        '${dayAgo.millisecondsSinceEpoch}',
      );

      a().engine.onAppResumed();
      await a().settle();

      expect(pulls(), hasLength(pulledTables.length));
      expect(
        a().scheduler.pending,
        isNot(contains(SyncEngine.resumeSnapshotWait)),
      );
      final fullAt = int.parse(
        (await a().db.syncDao.getValue(SyncDao.keyFullPullAt))!,
      );
      expect(fullAt, greaterThan(dayAgo.millisecondsSinceEpoch));
    });

    test('a debounced drain before any snapshot pulls every table and counts '
        'as the full pull', () async {
      pair.gateway.holdSignals = true;
      await a().engine.start();
      await a().settle();
      await a().db.syncDao.deleteValue(SyncDao.keyFullPullAt);
      pair.gateway.calls.clear();

      await a().db.folderDao.createFolder(name: 'Typed');
      await a().settle();
      expect(
        a().scheduler.fire(const SyncEngineTiming().pushDebounce),
        1,
        reason: 'the outbox trigger armed the debounce',
      );
      await a().settle();

      expect(pulls(), hasLength(pulledTables.length));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyFullPullAt),
        isNotNull,
        reason: 'a stale run with no snapshot pulled every table',
      );
    });

    test('a resume whose first snapshot says the space is gone drops the '
        'fallback with the listener', () async {
      await startThenLeave();
      pair.gateway.deleteSpace(pair.space);

      a().engine.onAppResumed();
      await a().settle();

      expect(a().engine.current.pause, SyncPause.noAccess);
      expect(
        a().scheduler.pending,
        isNot(contains(SyncEngine.resumeSnapshotWait)),
      );
      expect(pulls(), isEmpty);
    });

    test('a resume with a failure waiting runs every table at once, as the '
        'retry it replaces would have', () async {
      await a().engine.start();
      await a().settle();
      pair.gateway.failNextWith(SyncGatewayFailure.offline);
      await a().sync();
      expect(a().engine.current.lastFailure, isNotNull);
      await a().engine.onAppBackgrounded();
      await a().settle();
      pair.gateway.calls.clear();

      a().engine.onAppResumed();
      await a().settle();

      expect(pulls(), hasLength(pulledTables.length));
      expect(
        a().scheduler.pending,
        isNot(contains(SyncEngine.resumeSnapshotWait)),
      );
    });
  });

  group('the settled overlap', () {
    setUp(() => pair.gateway.timedCursors = true);

    /// B pushes a folder; A, started, pulls it; then, [later] on the server
    /// clock, B pushes a category, which A's snapshot reports — by default
    /// past the folder cursor by more than the settle margin (six overlaps).
    Future<void> folderThenLaterWrite({
      Duration later = const Duration(seconds: 90),
    }) async {
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      await a().engine.start();
      await a().settle();
      pair.gateway.elapse(later);
      await b().db.calendarCategoryDao.insertCategory(
        birthdayCategory(name: 'B cat'),
      );
      await b().sync();
      await a().settle();
      expect(
        await a().db.syncDao.getValue(SyncDao.keyServerSeen),
        isNotNull,
        reason: 'the snapshot stored the server time',
      );
      pair.gateway.resumedPulls.clear();
    }

    test('a table pulled before the server clock passed its cursor by the '
        'overlap keeps its re-read', () async {
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      await a().sync();
      pair.gateway.resumedPulls.clear();

      await a().sync();

      expect(pair.gateway.resumedPulls, contains('folders'));
    });

    test('a server clock past the cursor by the overlap but short of the '
        'settle margin keeps the re-read', () async {
      await folderThenLaterWrite(later: const Duration(seconds: 30));

      await a().sync();
      await a().sync();

      expect(pair.gateway.resumedPulls.where((t) => t == 'folders'), [
        'folders',
        'folders',
      ]);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        isNull,
      );
    });

    test('a cold start settles from the stored server time alone, once it '
        'stands six overlaps past the cursor', () async {
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      // Never started: no listener, no snapshot.
      await a().sync();
      final cursor = await a().db.syncDao.getValue(
        SyncDao.keyPullCursor('folders'),
      );
      final at = pair.gateway.cursorTime(SyncCursor(cursor!))!;
      Future<void> serverSeen(Duration past) => a().db.syncDao.setValue(
        SyncDao.keyServerSeen,
        '${at.add(past).microsecondsSinceEpoch}',
      );

      await serverSeen(const Duration(seconds: 59));
      await a().sync();
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        isNull,
      );

      await serverSeen(const Duration(seconds: 60));
      await a().sync();
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        cursor,
      );

      pair.gateway.resumedPulls.clear();
      await a().sync();
      expect(pair.gateway.resumedPulls, isNot(contains('folders')));
    });

    test('a walk cut mid-table leaves no mark', () async {
      pair.gateway.maxBatch = 1;
      await b().db.folderDao.createFolder(name: 'One');
      await b().db.folderDao.createFolder(name: 'Two');
      await b().sync();
      await a().db.syncDao.setValue(
        SyncDao.keyServerSeen,
        '${DateTime.utc(2027).microsecondsSinceEpoch}',
      );
      var cut = false;
      pair.gateway.onPullPage = (table) async {
        if (table != 'folders' || cut) return;
        cut = true;
        // Not started, so this only notes the leave; the walk stops before
        // its next page.
        await a().engine.onAppBackgrounded();
      };

      await a().sync();

      expect(await a().db.select(a().db.folders).get(), hasLength(1));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        isNull,
      );

      a().engine.onAppResumed();
      await a().sync();
      expect(await a().db.select(a().db.folders).get(), hasLength(2));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        reason: 'the same walk, uncut, settles',
      );
    });

    test('pull_seen is kept as a max', () async {
      await folderThenLaterWrite();
      final high = '${DateTime.utc(2027).microsecondsSinceEpoch}';
      await a().db.syncDao.setValue(SyncDao.keyPullSeen('folders'), high);

      await a().sync();

      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSeen('folders')),
        high,
      );
    });

    test('a table settles in a resume run, and a resume with no snapshot '
        'then reads it from its cursor exactly', () async {
      await folderThenLaterWrite();
      await a().engine.onAppBackgrounded();
      pair.gateway.holdSignals = true;

      a().engine.onAppResumed();
      await a().settle();
      a().scheduler.fire(SyncEngine.resumeSnapshotWait);
      await a().settle();
      expect(
        pair.gateway.resumedPulls,
        contains('folders'),
        reason: 'the pull that proves the table settled re-reads once',
      );
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
      );

      await a().engine.onAppBackgrounded();
      pair.gateway.resumedPulls.clear();
      pair.gateway.calls.clear();
      a().engine.onAppResumed();
      await a().settle();
      a().scheduler.fire(SyncEngine.resumeSnapshotWait);
      await a().settle();

      expect(pulls(), contains('folders'));
      expect(pair.gateway.resumedPulls, isNot(contains('folders')));
    });

    test('a write past the cursor of a settled table brings the re-read '
        'back', () async {
      await folderThenLaterWrite();
      await a().sync();
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        isNotNull,
      );

      // A's own: B's pulls would re-read on the same gateway.
      await a().db.folderDao.createFolder(name: 'Later from A');
      pair.gateway.resumedPulls.clear();
      await a().sync();
      await a().settle();

      // Read exactly before the push, re-read once the push moved
      // `touched` past the cursor.
      expect(pair.gateway.resumedPulls.where((t) => t == 'folders'), [
        'folders',
      ]);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        isNull,
        reason: 'the echo was read before the clock passed it',
      );
    });

    test('an unbind forgets the server time and the settled marks', () async {
      await folderThenLaterWrite();
      await a().sync();

      await a().binding.unbind();

      expect(await a().db.syncDao.getValue(SyncDao.keyServerSeen), isNull);
      expect(await a().db.syncDao.getValue(SyncDao.keyFullPullAt), isNull);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSettled('folders')),
        isNull,
      );
    });
  });

  group('the quota', () {
    test('the reset is the next midnight in Los Angeles, standard time and '
        'summer time', () {
      expect(
        SyncQuota.nextReset(DateTime.utc(2026, 11, 8, 7, 30)).toUtc(),
        DateTime.utc(2026, 11, 8, 8),
      );
      expect(
        SyncQuota.nextReset(DateTime.utc(2026, 11, 8, 8)).toUtc(),
        DateTime.utc(2026, 11, 9, 8),
      );
      expect(
        SyncQuota.nextReset(DateTime.utc(2026, 7, 1, 6, 30)).toUtc(),
        DateTime.utc(2026, 7, 1, 7),
      );
    });

    test('the retry waits for the reset plus five minutes when it comes '
        'within the hour, else an hour', () {
      const hourly = Duration(hours: 1);
      expect(
        SyncEngine.quotaRetryDelay(DateTime.utc(2026, 11, 8, 7, 30), hourly),
        const Duration(minutes: 35),
      );
      expect(
        SyncEngine.quotaRetryDelay(DateTime.utc(2026, 11, 8, 12), hourly),
        hourly,
      );
    });
  });

  test('a run reports its rows, bytes, pages and calls', () async {
    await a().db.folderDao.createFolder(name: 'Training');
    await a().db.folderDao.createFolder(name: 'Food');

    final pushed = await a().sync();
    final pulled = await b().sync();

    expect(pushed.pushedRows, 2);
    expect(pushed.pushAttempts, 1);
    expect(pushed.pushedBytes, greaterThan(0));
    expect(pushed.pages, pulledTables.length);
    expect(pulled.pulledRows, 2);
    expect(pulled.pages, pulledTables.length);
    expect(pulled.pushAttempts, 0);
    expect(pulled.resumeFallbacks, 0);
    expect(pulled.duration, greaterThanOrEqualTo(Duration.zero));
  });

  test('a database first run under a newer wire re-queues its live notes and '
      'their chunks once, and no run or start after that does', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );
    await a().sync();
    expect(
      await a().db.syncDao.getValue(SyncDao.keyWireVersion),
      '$syncSchema',
    );

    // What the run had queued when its pull began, after the cutover: the
    // pull's equal-stamp ack (S9) may retire an entry the space already
    // holds at that stamp, so the push alone would not tell.
    List<String>? queuedAtPull;
    pair.gateway.onPullPage = (_) async {
      queuedAtPull ??= [
        for (final entry in await a().db.syncOutboxDao.pending())
          '${entry.syncedTable}/${entry.rowKey}',
      ];
    };

    // A database last run by a build on the whole-body wire.
    await a().db.syncDao.setValue(SyncDao.keyWireVersion, '${syncSchema - 1}');
    final cut = await a().sync();

    expect(cut.failure, isNull);
    expect(
      queuedAtPull,
      unorderedEquals([
        'notes/${note.id}',
        'content_chunks/${ChunkHasher.hash('base')}',
      ]),
      reason: 'the live note and its chunk, not the folder',
    );
    expect(
      await a().db.syncDao.getValue(SyncDao.keyWireVersion),
      '$syncSchema',
    );
    expect(await a().db.syncOutboxDao.count(), 0);

    queuedAtPull = null;
    pair.gateway.pushes.clear();
    await a().sync();
    expect(queuedAtPull, isEmpty);
    queuedAtPull = null;
    await a().engine.start();
    await a().settle();

    expect(queuedAtPull, isEmpty);
    expect(pair.gateway.pushes, isEmpty);
  });
}
