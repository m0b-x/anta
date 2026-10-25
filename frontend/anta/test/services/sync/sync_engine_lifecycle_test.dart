import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_suspension.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';

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

    test('a signal stream that ends is attached afresh by the next run', () async {
      await a().engine.start();
      await a().settle();

      pair.gateway.endWatches(pair.space);
      await a().settle();
      await a().sync();
      await b().db.folderDao.createFolder(name: 'From B');
      pair.gateway.calls.clear();
      await b().sync();
      await a().settle();

      expect(callsAfterPushOfB(), ['pull:folders']);
    });

    test('a failing signal re-attaches on its own growing back-off and '
        'pulls nothing', () async {
      await a().engine.start();
      await a().settle();
      pair.gateway.calls.clear();

      pair.gateway.failWatches(pair.space, SyncGatewayFailure.unknown);
      await pumpEventQueue();
      for (var i = 0; i < 2; i++) {
        pair.gateway.failNextWith(SyncGatewayFailure.unknown);
        expect(a().scheduler.fire(), 1);
        await a().settle();
        await pumpEventQueue();
      }

      expect([for (final timer in a().scheduler.timers) timer.delay], const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
      ]);
      expect(pair.gateway.calls, isEmpty);
    });

    test('a signal stream that ends is attached afresh on the signal\'s '
        'back-off, without waiting for a run', () async {
      await a().engine.start();
      await a().settle();

      pair.gateway.endWatches(pair.space);
      await a().settle();
      expect(a().scheduler.pending, [const Duration(seconds: 30)]);
      a().scheduler.fire();
      await a().settle();
      await b().db.folderDao.createFolder(name: 'From B');
      pair.gateway.calls.clear();
      await b().sync();
      await a().settle();

      expect(callsAfterPushOfB(), ['pull:folders']);
    });

    test('a healthy snapshot after a signal error clears the error', () async {
      await a().engine.start();
      await a().settle();

      pair.gateway.failWatches(pair.space, SyncGatewayFailure.unknown);
      await a().settle();
      expect(
        a().engine.current.lastFailure?.failure,
        SyncGatewayFailure.unknown,
      );
      a().scheduler.fire();
      await a().settle();

      expect(a().engine.current.lastFailure, isNull);
    });

    test('a dropped listener\'s last snapshot does not pick the tables of a '
        'later run', () async {
      await pair.close();
      pair = await SyncPair.open(
        timing: const SyncEngineTiming(pushDebounce: Duration(minutes: 7)),
      );
      await a().engine.start();
      await a().settle();
      await b().db.folderDao.createFolder(name: 'First from B');
      await b().sync();
      await a().settle();
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSeen('folders')),
        isNotNull,
      );

      pair.gateway.failWatches(pair.space, SyncGatewayFailure.unknown);
      await a().settle();
      final second = await b().db.folderDao.createFolder(name: 'Second from B');
      await b().sync();
      await a().db.folderDao.createFolder(name: 'Mine');
      await pumpEventQueue();
      // The run's own attach fails too, so no fresh snapshot can arrive.
      pair.gateway.failNextWith(SyncGatewayFailure.unknown);
      expect(a().scheduler.fire(const Duration(minutes: 7)), 1);
      await a().settle();

      expect(await a().db.folderDao.getFolderById(second.id), isNotNull);
    });

    test('a debounced drain without a snapshot pulls every table first', () async {
      await pair.close();
      pair = await SyncPair.open(
        timing: const SyncEngineTiming(pushDebounce: Duration(minutes: 7)),
      );
      await a().engine.start();
      await a().settle();
      pair.gateway.failWatches(pair.space, SyncGatewayFailure.unknown);
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      pair.gateway.calls.clear();

      // The run's own attach fails too, so no snapshot arrives before it.
      pair.gateway.failNextWith(SyncGatewayFailure.unknown);
      expect(a().scheduler.fire(const Duration(minutes: 7)), 1);
      await a().settle();

      expect(pair.gateway.calls, [
        for (final binding in syncTableBindings) 'pull:${binding.table}',
        'push:A',
      ]);
    });

    test('the signal keeps its own back-off apart from the runs\'', () async {
      await pair.close();
      pair = await SyncPair.open(
        timing: const SyncEngineTiming(pushDebounce: Duration(minutes: 7)),
      );
      await a().engine.start();
      await a().settle();
      final folder = await a().db.folderDao.createFolder(name: 'Stuck');
      pair.gateway.refuse('folders', folder.id, SyncGatewayFailure.offline);

      await a().sync();
      await a().sync();
      pair.gateway.failWatches(pair.space, SyncGatewayFailure.unknown);
      await a().settle();
      await a().sync();

      final waits = [
        for (final timer in a().scheduler.timers)
          if (timer.delay != const Duration(minutes: 7)) timer.delay,
      ];
      expect(waits.take(4), const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(seconds: 30),
        Duration(minutes: 2),
      ]);
    });

    test('a table halted after a signal stores no pull_seen', () async {
      await a().engine.start();
      await a().settle();
      final restore = Completer<void>();
      a().hooks.onBeforePage = (table) async {
        if (table == 'folders') unawaited(SyncSuspension.run(() => restore.future));
      };

      await b().db.folderDao.createFolder(name: 'From B');
      await b().sync();
      await a().settle();
      restore.complete();
      await pumpEventQueue();

      expect(a().hooks.calls, contains('before:folders'));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullSeen('folders')),
        isNull,
      );
      expect(await a().db.select(a().db.folders).get(), isEmpty);
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
    test('a suspension that begins as a page is about to merge ends the run '
        'before that page merges', () async {
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
      expect(a().hooks.calls, contains('before:folders'));
      expect(a().hooks.calls, isNot(contains('after:folders')));
      expect(await a().db.select(a().db.folders).get(), isEmpty);
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

    test('going to the background mid-pull stops the pull before its next '
        'page, drains, and completes', () async {
      await a().sync();
      await b().db.folderDao.createFolder(name: 'From B');
      await b().db.counterDao.upsertValue('c1', '', 3);
      await b().sync();
      final hold = Completer<void>();
      var held = false;
      a().hooks.onBeforePage = (table) async {
        if (table != 'folders' || held) return;
        held = true;
        await hold.future;
      };
      await a().engine.start();
      while (!held) {
        await Future<void>.delayed(Duration.zero);
      }
      final mine = await a().db.folderDao.createFolder(name: 'Mine');
      pair.gateway.calls.clear();

      final background = a().engine.onAppBackgrounded();
      hold.complete();
      await background.timeout(const Duration(seconds: 5));

      expect(pair.gateway.rowsOf(pair.space, 'folders'), contains(mine.id));
      expect(pair.gateway.calls.where((c) => c.startsWith('pull')), isEmpty);
      expect(await a().db.select(a().db.counterValues).get(), isEmpty);
    });

    test('a leave cutting a pull drains before the caches hear of the pull', () async {
      await a().sync();
      await b().db.folderDao.createFolder(name: 'From B');
      await b().db.counterDao.upsertValue('c1', '', 3);
      await b().sync();
      final hold = Completer<void>();
      var held = false;
      a().hooks.onBeforePage = (table) async {
        if (table != 'folders' || held) return;
        held = true;
        await hold.future;
      };
      int? pushesAtAfterRun;
      a().hooks.onAfterRun = () async => pushesAtAfterRun ??= pair.gateway.calls
          .where((c) => c == 'push:A')
          .length;
      await a().engine.start();
      while (!held) {
        await Future<void>.delayed(Duration.zero);
      }
      await a().db.folderDao.createFolder(name: 'Mine');
      pair.gateway.calls.clear();

      final background = a().engine.onAppBackgrounded();
      hold.complete();
      await background.timeout(const Duration(seconds: 5));
      await a().settle();

      expect(a().hooks.runs.single, contains(SyncInvalidation.folders));
      expect(pushesAtAfterRun, 1);
    });

    test('a stop and a start across a leave and a return follow the space '
        'again', () async {
      await a().engine.start();
      await a().settle();
      await a().engine.onAppBackgrounded();
      await a().engine.stop();
      a().engine.onAppResumed();
      await a().engine.start();
      await a().settle();

      await b().db.folderDao.createFolder(name: 'From B');
      pair.gateway.calls.clear();
      await b().sync();
      await a().settle();
      expect(callsAfterPushOfB(), ['pull:folders'], reason: 'the signal');

      pair.gateway.calls.clear();
      await a().sync();
      expect(pair.gateway.calls, contains('pull:folders'));
    });

    test('a debounced drain over a closed database ends quietly', () async {
      await a().engine.start();
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      await a().db.close();

      expect(a().scheduler.fire(const Duration(seconds: 30)), 1);
      await a().engine.whenIdle;
    });

    test('a sign-out or another account during a run ends it before the '
        'next page', () async {
      await b().db.folderDao.createFolder(name: 'Folder');
      await b().sync();
      for (final (user, skip) in [
        (null, SyncRunSkip.signedOut),
        (const AppUser(uid: 'someone-else'), SyncRunSkip.accountMismatch),
      ]) {
        a().hooks.onBeforePage = (table) async {
          if (table == 'folders') a().user = user;
        };

        final report = await a().sync();

        expect(report.skipped, skip);
        expect(await a().db.select(a().db.folders).get(), isEmpty);
        a().user = const AppUser(uid: syncUid);
      }
    });

    test('resume and background do nothing before start and after stop', () async {
      await a().db.folderDao.createFolder(name: 'Queued');

      a().engine.onAppResumed();
      await a().engine.onAppBackgrounded();
      await a().settle();
      expect(pair.gateway.calls, isEmpty);

      await a().engine.start();
      await a().settle();
      await a().engine.stop();
      pair.gateway.calls.clear();
      await a().db.folderDao.createFolder(name: 'Later');
      a().engine.onAppResumed();
      await a().engine.onAppBackgrounded();
      await a().settle();
      expect(pair.gateway.calls, isEmpty);
    });

    test('a stop during start attaches nothing, and a later start attaches '
        'once', () async {
      final starting = a().engine.start();
      await a().engine.stop();
      await starting;

      expect(a().auth.hasListener, isFalse);
      await a().db.folderDao.createFolder(name: 'Queued');
      await pumpEventQueue();
      expect(a().scheduler.timers, isEmpty);

      unawaited(a().engine.start());
      final stopping = a().engine.stop();
      await a().engine.start();
      await stopping;
      await a().settle();
      await a().db.folderDao.createFolder(name: 'Again');
      await pumpEventQueue();

      expect(a().auth.hasListener, isTrue);
      expect(
        a().scheduler.timers.where(
          (timer) => timer.delay == const Duration(seconds: 30),
        ),
        hasLength(1),
      );
    });

    test('an unbind during a run ends it before the next page: no merge, no '
        'cursor, no last pull', () async {
      await b().db.folderDao.createFolder(name: 'Folder');
      await b().db.counterDao.upsertValue('c1', '', 3);
      await b().sync();
      a().hooks.onBeforePage = (table) async {
        if (table == 'folders') await a().binding.unbind();
      };

      final report = await a().sync();

      expect(report.skipped, SyncRunSkip.unbound);
      expect(await a().db.select(a().db.folders).get(), isEmpty);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        isNull,
      );
      expect(await a().db.syncDao.getValue(SyncDao.keyLastPullAt), isNull);
      expect(a().hooks.calls, isNot(contains('before:counter_values')));
    });

    test('a throwing afterRun neither masks a halt nor fails a run', () async {
      await b().db.folderDao.createFolder(name: 'Folder');
      await b().db.counterDao.upsertValue('c1', '', 3);
      await b().sync();
      a().hooks.onAfterRun = () async => throw StateError('hook');
      final restore = Completer<void>();
      a().hooks.onBeforePage = (table) async {
        if (table == 'counter_values') {
          unawaited(SyncSuspension.run(() => restore.future));
        }
      };

      final halted = await a().sync();
      restore.complete();
      await pumpEventQueue();
      a().hooks.onBeforePage = null;
      final next = await a().sync();

      expect(halted.skipped, SyncRunSkip.suspended);
      expect(halted.failure, isNull);
      expect(next.failure, isNull);
      expect(next.pulledRows, 1);
      expect(a().hooks.runs, hasLength(2));
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
