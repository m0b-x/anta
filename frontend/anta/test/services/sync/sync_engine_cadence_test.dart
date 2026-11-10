import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_tables.dart';

import 'support/sync_pair.dart';

/// The manual cadence (record §13): nothing reaches the space unasked — no
/// run at a start or a return, no signal, no push timer, no drain on a
/// leave, no retry — while "Sync now" runs in full, the bind's first merge
/// runs whatever the cadence, and a switch mid-session takes effect at once
/// and is read back by the next start.
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

  /// The calls made after B's last push — what A did on its own.
  List<String> callsAfterPushOfB() {
    final calls = pair.gateway.calls;
    return calls.sublist(calls.lastIndexOf('push:B') + 1);
  }

  /// Every table a run pulls: the chunks travel on the push only.
  final pulledTables = [
    for (final b in syncTableBindings)
      if (b.pulls) b,
  ];

  /// A with the bind's first merge done and its cadence stored as manual,
  /// started afresh with the call log empty. Its "Sync now" reads the space
  /// before anything else, so a failure scripted for the run's first pull
  /// is scripted `times: 2` — the read meets it too, as on a real link.
  Future<void> startManual() async {
    await a().sync();
    await a().engine.stop();
    await a().binding.setCadence(SyncCadence.manual);
    pair.gateway.calls.clear();
    await a().engine.start();
    await a().settle();
  }

  test('a start reads the stored cadence and runs nothing: no pull, no '
      'signal, and the status says so', () async {
    await startManual();

    expect(a().engine.cadence, SyncCadence.manual);
    expect(a().engine.current.cadence, SyncCadence.manual);
    expect(pair.gateway.calls, isEmpty);

    await b().db.folderDao.createFolder(name: 'From B');
    await b().sync();
    await a().settle();

    expect(callsAfterPushOfB(), isEmpty, reason: 'no signal is followed');
    expect(await a().db.select(a().db.folders).get(), isEmpty);
  });

  test('the bind\'s first merge runs at a manual start all the same, and '
      'ends the pending flag', () async {
    await a().binding.setCadence(SyncCadence.manual);
    await b().db.folderDao.createFolder(name: 'From B');
    await b().sync();
    pair.gateway.calls.clear();

    await a().engine.start();
    await a().settle();

    expect(pulls(), hasLength(pulledTables.length));
    expect(await a().db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
    expect(await a().db.select(a().db.folders).get(), hasLength(1));

    pair.gateway.calls.clear();
    await b().db.folderDao.createFolder(name: 'Later');
    await b().sync();
    await a().settle();
    expect(
      callsAfterPushOfB(),
      isEmpty,
      reason: 'the merge attached no signal',
    );
  });

  test('an edit arms no push timer; "Sync now" runs in full and sends it, '
      'and still follows no signal after', () async {
    await startManual();
    await a().db.folderDao.createFolder(name: 'Typed');
    await a().settle();
    expect(a().scheduler.pending, isEmpty);
    expect(await a().db.syncOutboxDao.count(), 1);

    final report = await a().sync();

    expect(report.pushedRows, 1);
    expect(await a().db.syncOutboxDao.count(), 0);
    expect(pulls(), hasLength(pulledTables.length));

    pair.gateway.calls.clear();
    await b().db.folderDao.createFolder(name: 'From B');
    await b().sync();
    await a().settle();
    expect(callsAfterPushOfB(), isEmpty);
  });

  test('a local write shows in the status as a change waiting, with no run '
      'and no timer', () async {
    await startManual();
    pair.gateway.readSpaceCalls = 0;
    expect(a().engine.current.pendingCount, 0);

    await a().db.folderDao.createFolder(name: 'Typed');
    await pumpEventQueue();
    await a().settle();

    expect(a().engine.current.pendingCount, 1);
    expect(a().scheduler.pending, isEmpty);
    expect(pair.gateway.calls, isEmpty);
    expect(pair.gateway.readSpaceCalls, 0);
  });

  test('a burst of writes waits behind one status read at most and ends on '
      'the final count (review K5)', () async {
    await startManual();
    a().statements.reset();

    // The outbox count is the status read's own statement.
    int statusReads() => [
      for (final statement in a().statements.captured)
        if (statement.sql.contains('COUNT(') &&
            statement.sql.contains('sync_outbox'))
          statement,
    ].length;

    const writes = 30;
    await Future.wait([
      for (var i = 0; i < writes; i++)
        a().db.folderDao.createFolder(name: 'Typed $i'),
    ]);
    await pumpEventQueue();
    await a().settle();

    expect(statusReads(), lessThanOrEqualTo(3));
    expect(a().engine.current.pendingCount, writes);
    expect(a().statuses.last.pendingCount, writes);
    expect(pair.gateway.calls, isEmpty);
  });

  test('a leave drains nothing, and says so', () async {
    await startManual();
    await a().db.folderDao.createFolder(name: 'Typed');
    await a().settle();

    final report = await a().engine.onAppBackgrounded();
    await a().settle();

    expect(report.skipped, SyncRunSkip.manual);
    expect(pair.gateway.calls, isEmpty);
    expect(await a().db.syncOutboxDao.count(), 1);
  });

  test('a quota pause schedules no retry and a return lifts nothing; "Sync '
      'now" lifts it', () async {
    await startManual();
    pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted, times: 2);
    await a().sync();
    expect(a().engine.current.pause, SyncPause.quotaExhausted);
    expect(a().scheduler.pending, isEmpty, reason: 'no hourly retry');
    await a().engine.onAppBackgrounded();
    await a().settle();
    pair.gateway.calls.clear();

    a().engine.onAppResumed();
    await a().settle();

    expect(pair.gateway.calls, isEmpty);
    expect(a().engine.current.pause, SyncPause.quotaExhausted);

    final report = await a().sync();

    expect(report.failure, isNull);
    expect(a().engine.current.pause, SyncPause.none);
  });

  test('a failure schedules no back-off; the status keeps it until a press '
      'succeeds', () async {
    await startManual();
    pair.gateway.failNextWith(SyncGatewayFailure.offline, times: 2);

    await a().sync();

    expect(a().engine.current.lastFailure?.failure, SyncGatewayFailure.offline);
    expect(a().scheduler.pending, isEmpty);

    await a().sync();

    expect(a().engine.current.lastFailure, isNull);
  });

  test('a "Sync now" a leave cut short finishes on the return', () async {
    await startManual();
    final folder = await b().db.folderDao.createFolder(name: 'From B');
    await writeNote(
      b(),
      folderId: folder.id,
      title: 'Leg day',
      body: 'Squat 5x5',
    );
    await b().sync();
    pair.gateway.calls.clear();
    pair.gateway.onPullPage = (table) async {
      if (table != 'folders') return;
      pair.gateway.onPullPage = null;
      unawaited(a().engine.onAppBackgrounded());
    };

    await a().sync();

    expect(pulls(), isNot(contains('notes')), reason: 'cut before notes');
    expect(await a().db.select(a().db.notes).get(), isEmpty);
    pair.gateway.calls.clear();

    a().engine.onAppResumed();
    await a().settle();

    expect(pulls(), contains('notes'));
    expect(await a().db.select(a().db.notes).get(), hasLength(1));

    pair.gateway.calls.clear();
    await a().engine.onAppBackgrounded();
    a().engine.onAppResumed();
    await a().settle();
    expect(pair.gateway.calls, isEmpty, reason: 'owed once, not for good');
  });

  test('switching to manual drops the signal and the armed push, and stores '
      'the choice; switching back runs at once and follows again', () async {
    await a().engine.start();
    await a().settle();
    await a().db.folderDao.createFolder(name: 'Typed');
    await a().settle();
    expect(
      a().scheduler.pending,
      contains(const SyncEngineTiming().pushDebounce),
    );

    await a().engine.setCadence(SyncCadence.manual);
    await a().settle();

    expect(a().scheduler.pending, isEmpty);
    expect(a().engine.current.cadence, SyncCadence.manual);
    expect(await a().settings.getSyncCadence(), SyncCadence.manual);
    pair.gateway.calls.clear();
    await b().db.folderDao.createFolder(name: 'From B');
    await b().sync();
    await a().settle();
    expect(callsAfterPushOfB(), isEmpty, reason: 'the signal was dropped');
    expect(await a().db.syncOutboxDao.count(), 1);

    pair.gateway.calls.clear();
    await a().engine.setCadence(SyncCadence.automatic);
    await a().settle();

    expect(await a().db.syncOutboxDao.count(), 0, reason: 'the switch ran');
    expect(await a().db.select(a().db.folders).get(), hasLength(2));
    expect(a().engine.current.cadence, SyncCadence.automatic);
    pair.gateway.calls.clear();
    await b().db.folderDao.createFolder(name: 'Again');
    await b().sync();
    await a().settle();
    expect(callsAfterPushOfB(), ['pull:folders'], reason: 'followed again');
  });

  test(
    'switching back to automatic lifts a quota hold, as a return does',
    () async {
      await startManual();
      pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted, times: 2);
      await a().sync();
      expect(a().engine.current.pause, SyncPause.quotaExhausted);
      pair.gateway.calls.clear();

      await a().engine.setCadence(SyncCadence.automatic);
      await a().settle();

      expect(a().engine.current.pause, SyncPause.none);
      expect(pair.gateway.calls, isNotEmpty);
    },
  );

  test(
    'the cadence stored mid-session is read back by the next start',
    () async {
      await a().engine.start();
      await a().settle();
      await a().engine.setCadence(SyncCadence.manual);
      await a().engine.stop();

      await a().engine.start();
      await a().settle();

      expect(a().engine.cadence, SyncCadence.manual);
    },
  );

  test('a quota pause stored from the last session holds a manual start, and '
      'the switch to automatic is its full retry', () async {
    await startManual();
    pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted, times: 2);
    await a().sync();
    await a().engine.stop();
    pair.gateway.calls.clear();

    await a().engine.start();
    await a().settle();

    expect(a().engine.current.pause, SyncPause.quotaExhausted);
    expect(pair.gateway.calls, isEmpty);
    expect(a().scheduler.pending, isEmpty);

    await a().engine.setCadence(SyncCadence.automatic);
    await a().settle();

    expect(pulls(), hasLength(pulledTables.length), reason: 'the retry');
    expect(a().engine.current.pause, SyncPause.none);
    expect(
      await a().db.syncDao.getValue(SyncDao.keyQuotaPausedAt),
      isNull,
      reason: 'the first call that reached the space cleared the mark',
    );
  });

  test('a run a snapshot queued behind "Sync now" is dropped once the cadence '
      'turned manual meanwhile', () async {
    await a().engine.start();
    await a().settle();
    pair.gateway.calls.clear();
    pair.gateway.onPullPage = (table) async {
      if (table != 'calendar_categories') return;
      pair.gateway.onPullPage = null;
      // B's push moves the signal, which queues a stale run behind the one
      // in flight; then the user turns the switch off. The log is shared by
      // both devices, so it is cleared here: what follows is A's alone —
      // the rest of the run in flight, and whatever the queued run reads.
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      await a().engine.setCadence(SyncCadence.manual);
      pair.gateway.calls.clear();
    };

    await a().sync();
    await a().settle();

    expect(
      pulls(),
      [for (final table in pulledTables.skip(1)) table.table],
      reason: 'the run in flight finished; the queued run reached nothing',
    );
    expect(await a().db.select(a().db.folders).get(), hasLength(1));
  });

  test('a stopped engine stores the cadence without applying it', () async {
    await a().sync();
    await a().engine.stop();

    await a().engine.setCadence(SyncCadence.manual);

    expect(await a().settings.getSyncCadence(), SyncCadence.manual);
    expect(a().engine.cadence, SyncCadence.manual);
    expect(pair.gateway.calls, isNotEmpty, reason: 'the merge ran before');
  });

  test('an account change under the manual cadence runs nothing', () async {
    await startManual();
    pair.gateway.calls.clear();

    a().auth.add(a().user);
    await a().settle();

    expect(pair.gateway.calls, isEmpty);
    expect(a().engine.current.cadence, SyncCadence.manual);
  });

  group('"Sync now" reads the space first, with no signal to say it '
      '(record D1, review F1)', () {
    test('a space another device marked: read once, paused as deleted, '
        'nothing pulled or pushed', () async {
      await startManual();
      await a().db.folderDao.createFolder(name: 'Queued');
      await a().settle();
      await pair.gateway.markSpaceDeleted(pair.space);
      pair.gateway.calls.clear();
      final reads = pair.gateway.readSpaceCalls;

      final report = await a().sync();

      expect(report.skipped, SyncRunSkip.spaceDeleted);
      expect(pair.gateway.readSpaceCalls, reads + 1);
      expect(pair.gateway.calls, isEmpty);
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
      expect(await a().db.syncOutboxDao.count(), 1);
    });

    test('a space deleted from the console: read once, paused as deleted, '
        'nothing pulled', () async {
      await startManual();
      pair.gateway.consoleDeleteSpace(pair.space);
      final reads = pair.gateway.readSpaceCalls;

      final report = await a().sync();

      expect(report.skipped, SyncRunSkip.spaceDeleted);
      expect(pair.gateway.readSpaceCalls, reads + 1);
      expect(pair.gateway.calls, isEmpty);
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
    });

    test(
      'a space a newer build wrote to: read once, paused as outdated',
      () async {
        await startManual();
        await pair.gateway.pushBatch(
          pair.space,
          const [],
          pushedBy: 'C',
          schema: syncSchema + 1,
        );
        pair.gateway.calls.clear();
        final reads = pair.gateway.readSpaceCalls;

        final report = await a().sync();

        expect(report.skipped, SyncRunSkip.appOutdated);
        expect(pair.gateway.readSpaceCalls, reads + 1);
        expect(pair.gateway.calls, isEmpty);
        expect(a().engine.current.pause, SyncPause.appOutdated);
      },
    );

    test('a live space: exactly one read, then the usual run', () async {
      await startManual();
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      pair.gateway.calls.clear();
      final reads = pair.gateway.readSpaceCalls;

      final report = await a().sync();

      expect(report.skipped, isNull);
      expect(report.failure, isNull);
      expect(pair.gateway.readSpaceCalls, reads + 1);
      expect(pulls(), hasLength(pulledTables.length));
      expect(await a().db.select(a().db.folders).get(), hasLength(1));
      expect(a().engine.current.pause, SyncPause.none);
    });

    test('a read that fails is no verdict: the run goes on', () async {
      await startManual();
      pair.gateway.failNextWith(SyncGatewayFailure.offline);
      pair.gateway.calls.clear();
      final reads = pair.gateway.readSpaceCalls;

      final report = await a().sync();

      expect(pair.gateway.readSpaceCalls, reads + 1);
      expect(report.skipped, isNull);
      expect(pulls(), hasLength(pulledTables.length));
      expect(a().engine.current.pause, SyncPause.none);
    });

    test(
      'a pause the gate lifts on its own read costs no second one',
      () async {
        await startManual();
        pair.gateway.consoleDeleteSpace(pair.space);
        await a().sync();
        expect(a().engine.current.pause, SyncPause.spaceDeleted);
        pair.gateway.consoleRestoreSpace(
          pair.space,
          name: 'Main',
          deviceId: 'C',
          schema: syncSchema,
        );
        final reads = pair.gateway.readSpaceCalls;

        final report = await a().sync();

        expect(report.skipped, isNull);
        expect(pair.gateway.readSpaceCalls, reads + 1);
        expect(a().engine.current.pause, SyncPause.none);
      },
    );
  });

  test(
    'SyncCadence.parse reads the stored names and defaults to automatic',
    () {
      expect(SyncCadence.parse('manual'), SyncCadence.manual);
      expect(SyncCadence.parse('automatic'), SyncCadence.automatic);
      expect(SyncCadence.parse(null), SyncCadence.automatic);
      expect(SyncCadence.parse('live'), SyncCadence.automatic);
    },
  );
}
