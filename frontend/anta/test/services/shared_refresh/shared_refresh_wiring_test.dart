import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/database_replacing.dart';
import 'package:anta/services/kept_share_notices.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';

import '../../support/fake_port_registry.dart';

/// Steps of a run that must never be taken: every one fails the test that
/// reaches it.
class _NoRun implements SharedRefreshRunSteps {
  Never _taken(String step) => fail('the run took a step: $step');

  @override
  Future<void> prepare() => _taken('prepare');
  @override
  Future<bool?> replacing() => _taken('replacing');
  @override
  Future<int?> storedSchema() => _taken('storedSchema');
  @override
  int get schema => _taken('schema');
  @override
  Future<SharedRefreshOpened> open() => _taken('open');
  @override
  Future<SharedRefreshSharing> shares() => _taken('shares');
  @override
  Future<SharedRefreshWorth?> planSuccessor() => _taken('planSuccessor');
  @override
  Future<bool> read() => _taken('read');
  @override
  Future<void> stopRead() => _taken('stopRead');
  @override
  Future<void> close() => _taken('close');
  @override
  Future<bool> retryCounted() => _taken('retryCounted');

  /// No step of a run: every end that is no give-way ends the row of them.
  @override
  Future<void> retriesOver() async {}

  /// A work the app served is written off by the app.
  @override
  Future<void> workConsumed() => _taken('workConsumed');
}

/// A run that reads until it is stopped, writing what it does into [did].
class _ReadsUntilStopped implements SharedRefreshRunSteps {
  _ReadsUntilStopped(this.did);

  final List<String> did;
  final Completer<void> _stopped = Completer<void>();

  @override
  Future<void> prepare() async {}
  @override
  Future<bool?> replacing() async => false;
  @override
  Future<int?> storedSchema() async => schema;
  @override
  int get schema => 7;
  @override
  Future<SharedRefreshOpened> open() async => SharedRefreshOpened.opened;
  @override
  Future<SharedRefreshSharing> shares() async => SharedRefreshSharing.yes;
  @override
  Future<SharedRefreshWorth?> planSuccessor() async =>
      (check: true, poke: true);
  @override
  Future<bool> read() async {
    did.add('run: read');
    await _stopped.future;
    return true;
  }

  @override
  Future<void> stopRead() async {
    did.add('run: stopRead');
    if (!_stopped.isCompleted) _stopped.complete();
  }

  @override
  Future<void> close() async => did.add('run: close');
  @override
  Future<bool> retryCounted() async => true;
  @override
  Future<void> retriesOver() async {}
  @override
  Future<void> workConsumed() async {}
}

/// The handshake's two real ends against each other — the launch's own step
/// and a whole trigger — and the lines of `main.dart` that call into it,
/// which no suite can run (`docs/cloud-shared-freshness.md` §5; review item
/// 14: the cases that passed with the behaviour removed).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePortRegistry registry;
  late List<String> reads;

  setUp(() {
    registry = FakePortRegistry();
    reads = [];
    SharedRefreshAvailability.debugSupported = true;
  });

  tearDown(() {
    SharedRefreshApp.resetForTesting();
    SharedRefreshAvailability.debugSupported = null;
  });

  Future<void>? launch() => SharedRefreshApp.beginLaunch(
    registry: registry,
    read: (ask) async => reads.add('read:${ask.slot?.name ?? 'none'}'),
  );

  SharedRefreshTrigger trigger() => SharedRefreshTrigger(
    steps: _NoRun(),
    port: SharedRefreshRunPort(
      registry: registry,
      pingTimeout: const Duration(milliseconds: 200),
    ),
  );

  int at(String call) => registry.calls.indexOf(call);

  group('a launch and a run that start together', () {
    test('each takes its own name before it looks for the other\'s — in the '
        'calls the two really make, not in an order a test chose', () async {
      final fired = trigger().fire();
      final wait = launch();
      SharedRefreshApp.launched();

      // The run: its name is registered before the app's is looked for.
      expect(at('register:$kSharedRefreshRunPort'), isNonNegative);
      expect(
        at('register:$kSharedRefreshRunPort'),
        lessThan(at('lookup:$kSharedRefreshAppPort')),
      );
      // The launch: its name is registered before the run's is looked for.
      expect(
        at('register:$kSharedRefreshAppPort'),
        lessThan(registry.calls.lastIndexOf('lookup:$kSharedRefreshRunPort')),
      );

      await wait;
      expect(await fired, SharedRefreshEnd.forwarded);
    });

    for (final first in ['the run', 'the launch']) {
      test('$first first: the run forwards and takes no step of its own, '
          'the app does the one read, and the launch is let go', () async {
        late Future<SharedRefreshEnd> fired;
        late Future<void>? wait;
        if (first == 'the run') {
          fired = trigger().fire();
          wait = launch();
        } else {
          wait = launch();
          fired = trigger().fire();
        }
        SharedRefreshApp.launched();

        // `_NoRun` fails the test if the run opened anything.
        expect(await fired, SharedRefreshEnd.forwarded);
        await wait;
        expect(reads, ['read:first']);
        expect(registry.names.keys, [kSharedRefreshAppPort]);
      });
    }
  });

  group('the app takes its name back after a trigger took it for dead '
      '(review H2)', () {
    const tick = Duration(milliseconds: 60);
    late List<String> did;

    setUp(() {
      did = [];
      // A check was planned on this install: the name is kept on a timer.
      SharedPreferences.setMockInitialValues({
        SettingsKeys.sharedRefreshPlanned: '1',
      });
    });

    void launchedWith() {
      SharedRefreshApp.beginLaunch(
        registry: registry,
        read: (_) async => did.add('forwarded read'),
        catchUp: () async => did.add('catch up'),
      );
      SharedRefreshApp.launched();
    }

    test('a run that went on beside the app is ended by the timer\'s '
        're-take — yielded, nothing retried, since the app reads — and only '
        'once it has closed does the app catch up, once', () async {
      launchedWith();
      registry.names.remove(kSharedRefreshAppPort);
      final run = _ReadsUntilStopped(did);
      final fired = SharedRefreshTrigger(
        steps: run,
        cause: SharedRefreshCause.message,
        port: SharedRefreshRunPort(registry: registry),
      ).fire();
      await pumpEventQueue();
      expect(did.last, 'run: read');

      SharedRefreshApp.inFront(true, every: tick);
      final end = await fired;
      await Future<void>.delayed(tick * 4);

      expect(end, SharedRefreshEnd.yielded);
      expect(end.retry, isFalse);
      expect(did, ['run: read', 'run: stopRead', 'run: close', 'catch up']);
    });

    test('a tick that finds the name standing is one lookup and nothing '
        'else: no catch-up, no read', () async {
      launchedWith();
      SharedRefreshApp.inFront(true, every: tick);
      registry.calls.clear();

      await Future<void>.delayed(tick * 4);

      expect(did, isEmpty);
      expect(registry.calls, isNotEmpty);
      expect(registry.calls.toSet(), {'lookup:$kSharedRefreshAppPort'});
    });

    test('catching up is the reload, then the read, then the alert pass — '
        'and one that fails costs the others nothing', () async {
      final order = <String>[];

      await SharedRefreshApp.caughtUp(
        reload: () async => order.add('reload'),
        read: () async {
          order.add('read');
          throw StateError('offline');
        },
        alertPass: () async => order.add('pass'),
      );

      expect(order, ['reload', 'read', 'pass']);
    });

    test('a launch that took a silent holder for dead owes one catch-up, '
        'once the old patience has passed (closing review, K4): the holder '
        'may have been a live run that was busy, writing behind the launch '
        'that went on beside it', () async {
      final silent = ReceivePort();
      addTearDown(silent.close);
      registry.names[kSharedRefreshRunPort] = silent.sendPort;

      await SharedRefreshApp.beginLaunch(
        registry: registry,
        catchUp: () async => did.add('catch up'),
        yieldTimeout: tick * 4,
        deadRunAfter: tick,
      );
      SharedRefreshApp.launched();
      expect(registry.names.containsKey(kSharedRefreshRunPort), isFalse);
      await Future<void>.delayed(tick * 2);
      expect(did, isEmpty, reason: 'not before the patience is over');

      await Future<void>.delayed(tick * 3);
      expect(did, ['catch up']);
    });

    test('a holder that answered and gave way, and no holder at all, owe '
        'none', () async {
      expect(
        SharedRefreshApp.beginLaunch(
          registry: registry,
          catchUp: () async => did.add('catch up'),
        ),
        isNull,
      );
      SharedRefreshApp.resetForTesting();

      final running = SharedRefreshRunPort(registry: registry);
      await running.open();
      unawaited(running.yieldRequested.then((_) => running.close()));
      await SharedRefreshApp.beginLaunch(
        registry: registry,
        catchUp: () async => did.add('catch up'),
        yieldTimeout: tick * 4,
        deadRunAfter: tick,
      );
      SharedRefreshApp.launched();
      await Future<void>.delayed(tick * 6);

      expect(did, isEmpty);
    });

    test('nothing is caught up while a database is being replaced (closing '
        'review, K7): a restore is what stalls the app past the pings, and '
        'a reload and a pass in the middle of it read a database half '
        'replaced', () async {
      final order = <String>[];
      final prompted = KeptShareNotices.prompts.listen(
        (_) => order.add('prompt'),
      );
      addTearDown(prompted.cancel);

      await SharedRefreshApp.caughtUp(
        reload: () async => order.add('reload'),
        read: () async => order.add('read'),
        alertPass: () async => order.add('pass'),
        replacing: () => true,
      );
      await pumpEventQueue();
      expect(order, isEmpty);

      // The default asks the app's own marker: a scope open in this isolate.
      await DatabaseReplacing.run(
        () => SharedRefreshApp.caughtUp(
          reload: () async => order.add('reload'),
          read: () async => order.add('read'),
          alertPass: () async => order.add('pass'),
        ),
      );
      await pumpEventQueue();
      expect(order, isEmpty);
    });

    test('one catch-up at a time (closing review, K7): a second re-take '
        'while one runs is folded into it', () async {
      final catching = Completer<void>();
      var catchUps = 0;
      SharedRefreshApp.beginLaunch(
        registry: registry,
        catchUp: () {
          catchUps++;
          return catching.future;
        },
      );
      SharedRefreshApp.launched();

      for (var retake = 0; retake < 2; retake++) {
        registry.names.remove(kSharedRefreshAppPort);
        SharedRefreshApp.reassert();
        await pumpEventQueue();
      }
      expect(catchUps, 1);

      catching.complete();
      await pumpEventQueue();
      registry.names.remove(kSharedRefreshAppPort);
      SharedRefreshApp.reassert();
      await pumpEventQueue();
      expect(catchUps, 2, reason: 'a re-take after it is its own');
    });

    test('an engine that leaves is not in front (closing review, K7): '
        'nothing still on its way starts the timer again and takes the '
        'name it has just given up', () async {
      SharedPreferences.setMockInitialValues({});
      launchedWith();
      SharedRefreshApp.inFront(true, every: tick);

      SharedRefreshApp.detached();
      expect(registry.names.containsKey(kSharedRefreshAppPort), isFalse);
      // The first check ever planned lands now: it would start the timer.
      SharedRefreshApp.checkPlanned();
      await Future<void>.delayed(tick * 4);

      expect(registry.names.containsKey(kSharedRefreshAppPort), isFalse);
    });

    test('and then whoever says the notices is prompted to read what the '
        'run kept (the notices review, N2): unprompted, they waited for a '
        'return that may be hours away', () async {
      final order = <String>[];
      final prompted = KeptShareNotices.prompts.listen(
        (_) => order.add('prompt'),
      );
      addTearDown(prompted.cancel);

      await SharedRefreshApp.caughtUp(
        reload: () async => order.add('reload'),
        read: () async => order.add('read'),
        alertPass: () async => order.add('pass'),
      );
      await pumpEventQueue();

      expect(order, ['reload', 'read', 'pass', 'prompt']);
    });
  });

  group('the timer runs only where a trigger can exist (review H7)', () {
    const tick = Duration(milliseconds: 60);

    Future<bool> nameComesBack() async {
      registry.names.remove(kSharedRefreshAppPort);
      await Future<void>.delayed(tick * 4);
      return registry.names.containsKey(kSharedRefreshAppPort);
    }

    void launchedInFront() {
      SharedRefreshApp.beginLaunch(registry: registry, catchUp: () async {});
      SharedRefreshApp.launched();
      SharedRefreshApp.inFront(true, every: tick);
    }

    test('never planned a check and holds no push address: no timer — and '
        'the session that plans its first check starts it then', () async {
      SharedPreferences.setMockInitialValues({});
      launchedInFront();
      registry.calls.clear();

      expect(await nameComesBack(), isFalse);
      expect(registry.calls, isEmpty, reason: 'not one tick');

      SharedRefreshApp.checkPlanned();
      expect(await nameComesBack(), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          SettingsKeys.sharedRefreshPlanned,
        ),
        '1',
      );
    });

    test('a push address held is enough: a message can start a run', () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushAddressHeld: '1',
      });
      launchedInFront();

      expect(await nameComesBack(), isTrue);
    });

    test('the same gate keeps the arm facts (review R6), and whoever opens '
        'it stores them before a run can come: the first check ever '
        'planned, at once — and a push address that came since the last '
        'pass, as the app leaves the front', () async {
      var kept = 0;
      SharedRefreshApp.keepArmFacts = () async => kept++;
      SharedPreferences.setMockInitialValues({});
      launchedInFront();

      // Never paired: leaving the front asks for nothing.
      SharedRefreshApp.inFront(false);
      await pumpEventQueue();
      expect(kept, 0);

      SharedRefreshApp.checkPlanned();
      await pumpEventQueue();
      expect(kept, 1, reason: 'the first check ever planned');

      SharedRefreshApp.inFront(false);
      await pumpEventQueue();
      expect(kept, 2, reason: 'the gate is open as the app leaves');
    });

    test('a check planned on an install that has planned one before stores '
        'nothing by itself: every pass there keeps the facts', () async {
      var kept = 0;
      SharedRefreshApp.keepArmFacts = () async => kept++;
      SharedPreferences.setMockInitialValues({
        SettingsKeys.sharedRefreshPlanned: '1',
      });
      launchedInFront();

      SharedRefreshApp.checkPlanned();
      await pumpEventQueue();

      expect(kept, 0);
    });
  });

  group('what main.dart calls, read where no suite can run it', () {
    final source = File('lib/main.dart').readAsStringSync();
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    int where(String line) {
      final index = code.indexOf(line);
      expect(index, isNonNegative, reason: line);
      expect(code.indexOf(line, index + 1), -1, reason: 'once: $line');
      return index;
    }

    test('the launch takes its name and waits for a run before anything can '
        'open a database, and clears a marker a dead process left once the '
        'preferences are this build\'s', () {
      final begins = where(
        'final refreshInFlight = SharedRefreshApp.beginLaunch();',
      );
      final waits = where(
        'if (refreshInFlight != null) await refreshInFlight;',
      );
      final namespaced = where('await QaBootstrap.beforeDependencies();');
      final cleared = where('await DatabaseReplacing.clearLeftBehind();');
      // The launch's real first open, three statements before the
      // dependencies.
      final opens = where(
        'await openDatabaseForLaunch(open: AppDatabase.getInstance);',
      );

      expect(
        code.indexOf('WidgetsFlutterBinding.ensureInitialized();'),
        lessThan(begins),
      );
      // The wait follows the step with nothing between the two.
      expect(
        code.substring(begins, waits).trim(),
        'final refreshInFlight = SharedRefreshApp.beginLaunch();',
      );
      expect(waits, lessThan(namespaced));
      expect(namespaced, lessThan(cleared));
      expect(cleared, lessThan(opens));
      expect(opens, lessThan(where('await configureDependencies();')));
      // And that open is the first thing in `main` to name the database.
      final main = code.indexOf('void main() async {');
      expect(main, isNonNegative);
      expect(code.indexOf('AppDatabase', main), greaterThan(opens));
      // Nothing of the database between the binding and the launch's step.
      expect(
        code.substring(
          code.indexOf('WidgetsFlutterBinding.ensureInitialized();'),
          begins,
        ),
        isNot(anyOf(contains('Database'), contains('SharedPreferences'))),
      );
    });

    test('the device\'s state is kept to this device with the id the open '
        'just read or made, before Firebase and the dependencies — the push '
        'objects, the planner and the first alert pass read it after', () {
      final opens = where(
        'await openDatabaseForLaunch(open: AppDatabase.getInstance);',
      );
      final kept = where(
        'await DeviceState.keepTo((await AppDatabase.getInstance()).deviceId);',
      );

      // The statement after the open, with nothing between the two.
      expect(
        code.substring(opens, kept).trim(),
        'await openDatabaseForLaunch(open: AppDatabase.getInstance);',
      );
      expect(kept, lessThan(where('await initializeFirebaseForSync();')));
      expect(kept, lessThan(where('await configureDependencies();')));
    });

    test('a forwarded read is let through only once the app is up: the '
        'last thing before the first frame', () {
      final up = where('SharedRefreshApp.launched();');

      expect(where('await configureDependencies();'), lessThan(up));
      expect(
        code.substring(up),
        matches(
          RegExp(
            r'^SharedRefreshApp\.launched\(\);\s*runApp\(const MyApp\(\)\);',
          ),
        ),
      );
    });

    test('the name follows the app\'s life: taken again on every resume, '
        'left alone once paused, given up as the engine detaches', () {
      String branch(String state) {
        final match = RegExp(
          'if \\(state == AppLifecycleState\\.$state\\) '
          r'(\{[\s\S]*?^    \}|[^\n]*;)',
          multiLine: true,
        ).firstMatch(code);
        expect(match, isNotNull, reason: state);
        return match!.group(0)!;
      }

      expect(branch('resumed'), contains('SharedRefreshApp.inFront(true);'));
      expect(branch('paused'), contains('SharedRefreshApp.inFront(false);'));
      expect(branch('detached'), contains('SharedRefreshApp.detached();'));
      where('SharedRefreshApp.inFront(true);');
      where('SharedRefreshApp.inFront(false);');
      where('SharedRefreshApp.detached();');
      // A marker whose removal the store refused is asked off again here
      // (review H6a).
      expect(
        branch('resumed'),
        contains('unawaited(DatabaseReplacing.clearLeftBehind());'),
      );
    });
  });
}
