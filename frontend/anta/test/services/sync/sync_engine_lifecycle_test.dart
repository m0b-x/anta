import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_suspension.dart';
import 'package:anta/services/sync/sync_table_binding.dart';

import 'support/sync_pair.dart';

/// When the engine runs and what it tells the app: the signal, the
/// single-flight queue, suspension and the database switch, the hooks, the
/// status stream and the account gate.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  /// The calls made after B's last push — what A did on its own.
  List<String> callsAfterPushOfB() {
    final calls = pair.gateway.calls;
    return calls.sublist(calls.lastIndexOf('push:B') + 1);
  }

  group('the signal', () {
    test('after B pushes, a started A pulls only the tables B touched', () async {
      await a().engine.start();
      await a().settle();
      await b().db.folderDao.createFolder(name: 'From B');
      pair.gateway.calls.clear();

      await b().sync();
      await a().settle();

      expect(callsAfterPushOfB(), ['pull:folders']);
      expect(await a().db.select(a().db.folders).get(), hasLength(1));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSeen('folders')),
        isNotNull,
      );
    });

    test('a space written at a newer schema pauses a started A', () async {
      await a().engine.start();
      await a().settle();

      await pair.gateway.pushBatch(
        pair.space,
        const [],
        pushedBy: 'C',
        schema: syncSchema + 1,
      );
      await a().settle();

      expect(a().engine.current.pause, SyncPause.appOutdated);
      pair.gateway.calls.clear();
      await b().db.folderDao.createFolder(name: 'Ignored');
      expect((await a().sync()).skipped, SyncRunSkip.appOutdated);
      expect(pair.gateway.calls, isEmpty);
    });

    test('a space deleted under a started A means no access', () async {
      await a().engine.start();
      await a().settle();

      pair.gateway.deleteSpace(pair.space);
      await a().settle();

      expect(a().engine.current.pause, SyncPause.noAccess);
    });
  });

  test('requests during a run are served by exactly one more run', () async {
    await b().db.folderDao.createFolder(name: 'From B');
    await b().sync();
    final hold = Completer<void>();
    var held = false;
    a().hooks.onBeforePage = (table) async {
      if (held) return;
      held = true;
      await hold.future;
    };
    pair.gateway.calls.clear();

    final first = a().engine.syncNow();
    while (!held) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = a().engine.syncNow();
    final third = a().engine.syncNow();
    var idle = false;
    final whenIdle = a().engine.whenIdle.then((_) => idle = true);
    await Future<void>.delayed(Duration.zero);
    expect(idle, isFalse);
    hold.complete();

    final reports = await Future.wait([first, second, third]);
    await whenIdle;

    expect(reports[0].pulledRows, 1);
    expect(identical(reports[1], reports[2]), isTrue);
    expect(
      pair.gateway.calls.where((c) => c == 'pull:calendar_categories'),
      hasLength(2),
    );
    expect(idle, isTrue);
  });

  group('stopping', () {
    test('a suspension that begins mid-page ends the run before the next '
        'page', () async {
      await b().db.folderDao.createFolder(name: 'Folder');
      await b().db.counterDao.upsertValue('c1', '', 3);
      await b().sync();
      final restore = Completer<void>();
      a().hooks.onBeforePage = (table) async {
        if (table == 'folders') unawaited(SyncSuspension.run(() => restore.future));
      };

      final report = await a().sync();
      restore.complete();
      await Future<void>.delayed(Duration.zero);

      expect(report.skipped, SyncRunSkip.suspended);
      expect(a().hooks.calls, contains('after:folders'));
      expect(a().hooks.calls, isNot(contains('before:counter_values')));
      expect(SyncSuspension.isSuspended, isFalse);
      expect((await a().sync()).skipped, isNull);
    });

    test('a database switch cancels the signal, the trigger and the timers', () async {
      SyncEngine.registerForTesting(a().engine);
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      expect(a().scheduler.pending, [const Duration(seconds: 30)]);

      SyncEngine.reset();
      await a().engine.whenIdle;
      pair.gateway.calls.clear();
      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      await Future<void>.delayed(Duration.zero);

      expect(a().scheduler.pending, isEmpty);
      expect(callsAfterPushOfB(), isEmpty);
      expect((await a().engine.syncNow()).skipped, SyncRunSkip.stopped);
    });

    test('the outbox trigger drains after the debounce', () async {
      await a().engine.start();
      await a().settle();
      final folder = await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();

      a().scheduler.fire(const Duration(seconds: 30));
      await a().settle();

      expect(pair.gateway.rowsOf(pair.space, 'folders').keys, [folder.id]);
    });

    test('going to the background drains at once', () async {
      await a().engine.start();
      await a().settle();
      final folder = await a().db.folderDao.createFolder(name: 'Queued');

      await a().engine.onAppBackgrounded();

      expect(pair.gateway.rowsOf(pair.space, 'folders').keys, [folder.id]);
    });
  });

  group('hooks', () {
    test('an event moving alone touches calendar and alerts, page by page', () async {
      await b().db.calendarEventDao.upsert(eventRow('e1'));
      await b().sync();

      await a().sync();

      expect(a().hooks.calls, [
        'before:calendar_events',
        'after:calendar_events',
        'run',
      ]);
      expect(a().hooks.pages.single.$2.single.result, MergeResult.inserted);
      expect(a().hooks.runs.single, {
        SyncInvalidation.calendar,
        SyncInvalidation.alerts,
      });
    });

    test('a page of notes and folders names both classes', () async {
      final folder = await b().db.folderDao.createFolder(name: 'Training');
      await writeNote(b(), folderId: folder.id, title: 'Log', body: 'body');
      await b().sync();

      await a().sync();

      expect(a().hooks.runs.single, {
        SyncInvalidation.folders,
        SyncInvalidation.notes,
      });
    });
  });

  group('status', () {
    test('the stream goes pulling, pushing, idle and ends with the counts', () async {
      await a().db.folderDao.createFolder(name: 'Training');

      await a().sync();

      final activities = <SyncActivity>[];
      for (final status in a().statuses) {
        if (activities.isEmpty || activities.last != status.activity) {
          activities.add(status.activity);
        }
      }
      expect(activities, [
        SyncActivity.pulling,
        SyncActivity.pushing,
        SyncActivity.idle,
      ]);
      final last = a().engine.current;
      expect(last.pendingCount, 0);
      expect(last.lastPushAt, isNotNull);
      expect(last.lastPullAt, isNotNull);
      expect(last.binding?.spaceId, pair.space.spaceId);
    });

    test('signed out and another account skip with their reasons', () async {
      a().user = null;
      expect((await a().sync()).skipped, SyncRunSkip.signedOut);
      expect(a().engine.current.pause, SyncPause.signedOut);

      a().user = const AppUser(uid: 'someone-else');
      expect((await a().sync()).skipped, SyncRunSkip.accountMismatch);
      expect(a().engine.current.pause, SyncPause.accountMismatch);
    });

    test('signing back in as the bound account resumes a started engine', () async {
      a().user = null;
      await a().engine.start();
      await a().settle();
      final folder = await a().db.folderDao.createFolder(name: 'Queued');

      a().user = const AppUser(uid: syncUid);
      a().auth.add(a().user);
      await a().settle();

      expect(pair.gateway.rowsOf(pair.space, 'folders').keys, [folder.id]);
      expect(a().engine.current.pause, SyncPause.none);
    });

    test('an unbound database skips as unbound', () async {
      await a().binding.unbind();

      expect((await a().sync()).skipped, SyncRunSkip.unbound);
    });

    test('a failed call is cleared from the status by the next success', () async {
      pair.gateway.failNextWith(SyncGatewayFailure.offline);
      await a().sync();
      expect(a().engine.current.lastFailure, isNotNull);

      await a().sync();

      expect(a().engine.current.lastFailure, isNull);
    });
  });
}
