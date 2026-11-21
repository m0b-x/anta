import 'dart:async';
import 'dart:isolate';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';

import '../../support/fake_port_registry.dart';
import '../../support/scripted_prefs_store.dart';

/// A registry whose call [throwsAt] (`lookup:<name>`, `register:<name>`)
/// throws, from the [after]th such call on.
class _ThrowingRegistry extends FakePortRegistry {
  _ThrowingRegistry(this.throwsAt, {this.after = 0});

  final String throwsAt;
  final int after;
  int _seen = 0;

  void _maybeThrow(String call) {
    if (call == throwsAt && _seen++ >= after) throw StateError(call);
  }

  @override
  SendPort? lookup(String name) {
    _maybeThrow('lookup:$name');
    return super.lookup(name);
  }

  @override
  bool register(SendPort port, String name) {
    _maybeThrow('register:$name');
    return super.register(port, name);
  }
}

/// A registry that takes no name while [refuses].
class _RefusingRegistry extends FakePortRegistry {
  bool refuses = true;

  @override
  bool register(SendPort port, String name) =>
      !refuses && super.register(port, name);
}

/// The handshake that keeps the database in one isolate
/// (`docs/cloud-shared-freshness.md` §5), both sides driven in one isolate
/// over real ports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const short = Duration(milliseconds: 60);
  const limit = Duration(seconds: 5);

  late FakePortRegistry registry;
  late List<String> reads;
  late Future<void> Function() onRead;
  final open = <void Function()>[];

  setUp(() {
    registry = FakePortRegistry();
    reads = [];
    onRead = () async {};
    // An install where no trigger can exist, unless a group says otherwise:
    // a launch here starts no timer, and reads its gate from a store that
    // answers.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    for (final close in open) {
      close();
    }
    open.clear();
  });

  SharedRefreshAppPort app({Duration yieldTimeout = limit}) {
    final port = SharedRefreshAppPort(
      read: (_) {
        reads.add('read');
        return onRead();
      },
      registry: registry,
      yieldTimeout: yieldTimeout,
    );
    open.add(port.close);
    return port;
  }

  SharedRefreshRunPort run({Duration pingTimeout = limit}) {
    final port = SharedRefreshRunPort(
      registry: registry,
      pingTimeout: pingTimeout,
    );
    open.add(port.close);
    return port;
  }

  test('the two names and the waits are the record\'s', () {
    expect(kSharedRefreshAppPort, 'anta.app');
    expect(kSharedRefreshRunPort, 'anta.refresh');
    expect(kSharedRefreshPingTimeout, const Duration(seconds: 2));
    expect(kSharedRefreshYieldTimeout, const Duration(seconds: 5));
    expect(kSharedRefreshRunLimit, const Duration(seconds: 60));
    expect(kSharedRefreshDeadRunAfter, const Duration(seconds: 1));
    expect(kSharedRefreshAbandonGrace, const Duration(seconds: 5));
  });

  test('the app stops counting an asker as waiting before the asker\'s own '
      'limit runs out (review H10e): equal, a read could begin in the turn '
      'its asker was answered failure', () {
    expect(
      kSharedRefreshRunLimit - kSharedRefreshForwardPatience,
      greaterThanOrEqualTo(const Duration(seconds: 3)),
    );
    expect(kSharedRefreshForwardPatience, greaterThan(Duration.zero));
  });

  group('a trigger asks the app', () {
    test(
      'no app in this process: nothing is asked and nothing removed',
      () async {
        final trigger = run()..open();

        expect(await trigger.forward(limit: limit), SharedRefreshForward.noApp);
        expect(registry.names.keys, [kSharedRefreshRunPort]);
      },
    );

    test('the app answers the ping and does the read on its own isolate; '
        'the trigger gives its name up before it asks for the read', () async {
      app().open();
      final trigger = run()..open();
      var heldDuringRead = true;
      onRead = () async {
        heldDuringRead = registry.names.containsKey(kSharedRefreshRunPort);
      };

      final forwarded = await trigger.forward(limit: limit);

      expect(forwarded, SharedRefreshForward.done);
      expect(reads, ['read']);
      expect(heldDuringRead, isFalse);
      expect(registry.names.keys, [kSharedRefreshAppPort]);
    });

    test('a read that throws is answered as failed', () async {
      app().open();
      onRead = () async => throw StateError('no engine');

      expect(
        await (run()..open()).forward(limit: limit),
        SharedRefreshForward.failed,
      );
    });

    test('a read that does not end within the limit is failed, not waited '
        'for', () async {
      app().open();
      final never = Completer<void>();
      onRead = () => never.future;

      expect(
        await (run()..open()).forward(limit: short),
        SharedRefreshForward.failed,
      );
    });

    test('a name nobody answers under is a dead isolate\'s: removed, and '
        'the run goes on without the app', () async {
      final dead = ReceivePort();
      addTearDown(dead.close);
      registry.names[kSharedRefreshAppPort] = dead.sendPort;
      final trigger = run(pingTimeout: short)..open();

      expect(await trigger.forward(limit: limit), SharedRefreshForward.noApp);
      expect(registry.names.containsKey(kSharedRefreshAppPort), isFalse);
      expect(
        registry.names.containsKey(kSharedRefreshRunPort),
        isTrue,
        reason: 'the run still holds its own name',
      );
    });

    test('three pings over six seconds, the record\'s, before a name is '
        'called stale', () {
      expect(kSharedRefreshPings, 3);
      expect(
        kSharedRefreshPingTimeout * kSharedRefreshPings,
        const Duration(seconds: 6),
      );
    });

    test('an app that misses two pings — a stalled main isolate — and '
        'answers the third is alive: its name stands, it does the read, and '
        'no run goes on beside it', () async {
      var pings = 0;
      final stalled = ReceivePort();
      addTearDown(stalled.close);
      stalled.listen((message) {
        final [verb as String, reply as SendPort, ...] = message as List;
        if (verb == SharedRefreshWire.ping) {
          if (++pings == 3) reply.send(SharedRefreshWire.pong);
        } else if (verb == SharedRefreshWire.read) {
          reads.add('read');
          reply.send(SharedRefreshWire.done);
        }
      });
      registry.names[kSharedRefreshAppPort] = stalled.sendPort;
      final trigger = run(pingTimeout: short)..open();

      expect(await trigger.forward(limit: limit), SharedRefreshForward.done);
      expect(pings, 3);
      expect(reads, ['read']);
      expect(registry.names[kSharedRefreshAppPort], stalled.sendPort);
    });

    test('a name a launch took while the ping went unanswered is left '
        'standing', () async {
      final dead = ReceivePort();
      addTearDown(dead.close);
      registry.names[kSharedRefreshAppPort] = dead.sendPort;
      final trigger = run(pingTimeout: short)..open();

      final forwarding = trigger.forward(limit: limit);
      final launched = app()..open();
      await forwarding;

      expect(registry.names.containsKey(kSharedRefreshAppPort), isTrue);
      launched.close();
    });
  });

  group('a launch asks a run in flight', () {
    test('no run: nothing to await, and only the name was looked for', () {
      final launch = app()..open();
      registry.calls.clear();

      expect(launch.yieldRunInFlight(), isNull);
      expect(registry.calls, ['lookup:$kSharedRefreshRunPort']);
    });

    test('a run holds the database: it hears the yield, and the launch '
        'waits until the run has closed', () async {
      final running = run()..open();
      final launch = app()..open();
      var waited = false;

      final wait = launch.yieldRunInFlight()!.then((_) => waited = true);
      await running.yieldRequested;
      expect(running.yieldAsked, isTrue);
      await Future<void>.delayed(short);
      expect(waited, isFalse, reason: 'the run has not closed yet');

      running.close();
      await wait;

      expect(waited, isTrue);
      expect(registry.names.containsKey(kSharedRefreshRunPort), isFalse);
    });

    test('a run that never answers holds the launch for the wait and no '
        'longer', () async {
      run().open();
      final launch = app(yieldTimeout: short)..open();
      final clock = Stopwatch()..start();

      await launch.yieldRunInFlight();

      expect(clock.elapsed, greaterThanOrEqualTo(short));
      expect(clock.elapsed, lessThan(limit));
    });

    test('a run that closed a moment before the yield reached it never '
        'answers: the launch sees its name gone and goes on within half a '
        'second, not after the five', () async {
      final gone = ReceivePort();
      registry.names[kSharedRefreshRunPort] = gone.sendPort;
      final launch = app()..open();
      final clock = Stopwatch()..start();

      final wait = launch.yieldRunInFlight()!;
      // What the run's close does, with the question still on its way.
      registry.names.remove(kSharedRefreshRunPort);
      gone.close();
      await wait;

      expect(clock.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(kSharedRefreshYieldPoll, const Duration(milliseconds: 250));
    });

    test('a run that still holds its name is waited for past the first '
        'looks', () async {
      final running = run()..open();
      final launch = app()..open();
      var waited = false;

      final wait = launch.yieldRunInFlight()!.then((_) => waited = true);
      await Future<void>.delayed(kSharedRefreshYieldPoll * 2.4);
      expect(waited, isFalse);

      running.close();
      await wait;
    });

    test('a run killed with its engine left its name (review H4): the '
        'launch waits the short bound and not the whole wait, removes the '
        'name — and the next launch awaits nothing', () async {
      final dead = ReceivePort();
      registry.names[kSharedRefreshRunPort] = dead.sendPort;
      dead.close();
      SharedRefreshAppPort launching() {
        final port = SharedRefreshAppPort(
          read: (_) async {},
          registry: registry,
          yieldTimeout: limit,
          deadRunAfter: short,
        )..open();
        open.add(port.close);
        return port;
      }

      final clock = Stopwatch()..start();
      await launching().yieldRunInFlight();

      expect(clock.elapsed, greaterThanOrEqualTo(short));
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
      expect(registry.names.containsKey(kSharedRefreshRunPort), isFalse);
      expect(launching().yieldRunInFlight(), isNull);
    });

    test(
      'a run that answers the ping is alive however long it takes to '
      'close: it keeps its name past the short bound and is waited for',
      () async {
        final running = run()..open();
        final launch = SharedRefreshAppPort(
          read: (_) async {},
          registry: registry,
          yieldTimeout: limit,
          deadRunAfter: short,
        )..open();
        open.add(launch.close);
        var waited = false;

        final wait = launch.yieldRunInFlight()!.then((_) => waited = true);
        await Future<void>.delayed(short * 3);
        expect(waited, isFalse);
        expect(registry.names.containsKey(kSharedRefreshRunPort), isTrue);

        running.close();
        await wait;
      },
    );

    test('the launch is told which it was (closing review, K4): a holder '
        'that was only silent — its name removed on no proof — or one that '
        'answered and gave way', () async {
      final silent = ReceivePort();
      addTearDown(silent.close);
      registry.names[kSharedRefreshRunPort] = silent.sendPort;
      SharedRefreshAppPort launching() {
        final port = SharedRefreshAppPort(
          read: (_) async {},
          registry: registry,
          yieldTimeout: limit,
          deadRunAfter: short,
        )..open();
        open.add(port.close);
        return port;
      }

      expect(await launching().yieldRunInFlight(), isTrue);

      final running = run()..open();
      final wait = launching().yieldRunInFlight()!;
      await running.yieldRequested;
      running.close();
      expect(await wait, isFalse);
    });

    test('a run gives the name up only while it is its own (closing review, '
        'K4): one taken for dead whose name a later run has since taken '
        'leaves that name where it is', () async {
      final first = run()..open();
      // The launch took it for dead; a later run took the name.
      registry.names.remove(kSharedRefreshRunPort);
      final later = run();
      expect(await later.open(), isTrue);
      final laters = registry.names[kSharedRefreshRunPort];

      first.close();

      expect(registry.names[kSharedRefreshRunPort], laters);
    });

    test('a run killed with its engine left its name: the next run takes it '
        'over, once its pings went unanswered', () async {
      final dead = ReceivePort();
      addTearDown(dead.close);
      registry.names[kSharedRefreshRunPort] = dead.sendPort;

      expect(await run(pingTimeout: short).open(), isTrue);

      expect(registry.names[kSharedRefreshRunPort], isNot(dead.sendPort));
    });

    test('a holder that was only silent is still asked to give way before '
        'its name is taken (review A8): a run busy past the pings must not '
        'go on beside the next one unaware', () async {
      final busy = ReceivePort();
      addTearDown(busy.close);
      final heard = <Object?>[];
      busy.listen((message) => heard.add((message as List).first));
      registry.names[kSharedRefreshRunPort] = busy.sendPort;

      final taking = run(pingTimeout: short);
      expect(await taking.open(), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(heard, contains(SharedRefreshWire.giveWayToRun));
      expect(registry.names[kSharedRefreshRunPort], isNot(busy.sendPort));
    });
  });

  group('a run that finds the name held (review item 6)', () {
    test('with nobody under it the name is taken in the caller\'s own '
        'turn — what "name first, look second" rests on', () {
      final taking = run().open();

      expect(registry.names.containsKey(kSharedRefreshRunPort), isTrue);
      expect(taking, completion(isTrue));
    });

    test('a live run is asked to end and waited for; the name is taken '
        'only once that one gave it up, never over it', () async {
      final first = run()..open();
      final firstPort = registry.names[kSharedRefreshRunPort];
      final second = run();
      var taken = false;

      final taking = second.open().then((ok) => taken = ok);
      await first.yieldRequested;
      await Future<void>.delayed(short);
      expect(taken, isFalse);
      expect(registry.names[kSharedRefreshRunPort], firstPort);
      // Told who asks: a run, which may read nothing in its place.
      expect(first.yieldAskedByApp, isFalse);

      first.close();
      await taking;

      expect(taken, isTrue);
      expect(registry.names[kSharedRefreshRunPort], isNot(firstPort));
    });

    test('a live run that does not end in time keeps its name, and the '
        'later one is told it may not go on', () async {
      final first = run()..open();
      final firstPort = registry.names[kSharedRefreshRunPort];
      final second = SharedRefreshRunPort(
        registry: registry,
        yieldTimeout: short,
      );

      expect(await second.open(), isFalse);
      expect(registry.names[kSharedRefreshRunPort], firstPort);
      expect(first.yieldAsked, isTrue);
    });

    test('a launch that comes while the later run waits asks the one that '
        'holds the database, and is let go when that one closes', () async {
      final first = run()..open();
      final second = run();
      final taking = second.open();
      await first.yieldRequested;

      final launch = app()..open();
      var launchGoes = false;
      final wait = launch.yieldRunInFlight()!.then((_) => launchGoes = true);
      await Future<void>.delayed(short);
      expect(launchGoes, isFalse);
      // The app asked too, after the run did: the app reads.
      expect(first.yieldAskedByApp, isTrue);

      first.close();
      expect(first.yieldAskedByApp, isTrue, reason: 'kept past the close');
      await wait;
      expect(await taking, isTrue);
      expect(await second.forward(limit: limit), SharedRefreshForward.done);
    });
  });

  group('a launch and a run that start together', () {
    // That each takes its own name before it looks for the other's is the
    // callers' order, pinned on the calls they really make in
    // `shared_refresh_wiring_test.dart`; here the two names are simply
    // both taken, as that order leaves them.
    test('with both names taken, the run forwards and the launch is let go '
        'at once', () async {
      final running = run()..open();
      final launch = app()..open();

      final wait = launch.yieldRunInFlight();
      final forwarded = await running.forward(limit: limit);
      await wait;

      expect(wait, isNotNull);
      expect(forwarded, SharedRefreshForward.done);
      expect(reads, ['read']);
      expect(registry.names.keys, [kSharedRefreshAppPort]);
    });
  });

  group('the app\'s name', () {
    test('taken once; opening again asks only whether it still stands', () {
      final launch = app();
      expect(launch.open(), isTrue);
      final port = registry.names[kSharedRefreshAppPort];
      registry.calls.clear();

      expect(launch.open(), isFalse);

      expect(registry.names[kSharedRefreshAppPort], port);
      expect(registry.calls, ['lookup:$kSharedRefreshAppPort']);
    });

    test('a name the registry refused was not taken (review H10c): the '
        'answer is the registry\'s, and what follows a name taken does not '
        'follow', () {
      final refusing = _RefusingRegistry();
      final launch = SharedRefreshAppPort(
        read: (_) async {},
        registry: refusing,
      );
      open.add(launch.close);

      expect(launch.open(), isFalse);
      expect(refusing.names.containsKey(kSharedRefreshAppPort), isFalse);

      refusing.refuses = false;
      expect(launch.open(), isTrue);
    });

    test('taken again after a trigger removed it for stale', () async {
      final launch = app()..open();
      registry.names.remove(kSharedRefreshAppPort);

      launch.open();

      expect(
        await (run()..open()).forward(limit: limit),
        SharedRefreshForward.done,
      );
    });
  });

  group('the launch\'s step (SharedRefreshApp.beginLaunch)', () {
    setUp(() => SharedRefreshAvailability.debugSupported = true);
    tearDown(() {
      SharedRefreshApp.resetForTesting();
      SharedRefreshAvailability.debugSupported = null;
    });

    test('an ordinary launch is four registry calls in the caller\'s own '
        'turn — its name looked at, cleared of a dead isolate\'s and taken, '
        'then one look for a run — and there is nothing to await', () {
      final wait = SharedRefreshApp.beginLaunch(registry: registry);

      expect(wait, isNull);
      expect(registry.names.keys, [kSharedRefreshAppPort]);
      expect(registry.calls, [
        'lookup:$kSharedRefreshAppPort',
        'remove:$kSharedRefreshAppPort',
        'register:$kSharedRefreshAppPort',
        'lookup:$kSharedRefreshRunPort',
      ]);
    });

    test('a registry that throws costs the launch nothing: it is logged, '
        'no name is held, and nothing is awaited — this runs before the '
        'launch has its error hooks (review item 10)', () {
      for (final broken in [
        _ThrowingRegistry('register:$kSharedRefreshAppPort'),
        _ThrowingRegistry('lookup:$kSharedRefreshRunPort'),
      ]) {
        expect(SharedRefreshApp.beginLaunch(registry: broken), isNull);
        expect(broken.names, isEmpty, reason: broken.throwsAt);

        // The rest of the launch finds no port and does nothing.
        SharedRefreshApp.launched();
        SharedRefreshApp.inFront(true, every: short);
        expect(broken.names, isEmpty, reason: broken.throwsAt);
        SharedRefreshApp.resetForTesting();
      }
    });

    test('a wait for a run that fails is no failed launch either', () async {
      final running = run()..open();
      final broken = _ThrowingRegistry(
        'lookup:$kSharedRefreshRunPort',
        after: 1,
      )..names.addAll(registry.names);

      final wait = SharedRefreshApp.beginLaunch(registry: broken);
      expect(wait, isNotNull);

      // The wait's own look for the run's name throws: the wait ends there,
      // well before its five seconds, and throws at nobody.
      await wait!.timeout(const Duration(seconds: 2));
      running.close();
    });

    test('the engine detaches: the name is given up at once, so the next '
        'trigger finds no app without pinging a dead isolate; an engine '
        'that comes back takes it again (review item 10)', () async {
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.launched();
      final mine = registry.names[kSharedRefreshAppPort];

      SharedRefreshApp.detached();

      expect(registry.names.containsKey(kSharedRefreshAppPort), isFalse);
      registry.calls.clear();
      expect(
        await (run()..open()).forward(limit: limit),
        SharedRefreshForward.noApp,
      );
      // Its own name, one look for the app's, and no ping to wait out.
      expect(registry.calls, [
        'lookup:$kSharedRefreshRunPort',
        'register:$kSharedRefreshRunPort',
        'lookup:$kSharedRefreshAppPort',
      ]);

      SharedRefreshApp.inFront(true, every: limit);
      expect(registry.names[kSharedRefreshAppPort], mine);
    });

    test('a name a later launch took is not the detaching engine\'s to '
        'remove', () {
      SharedRefreshApp.beginLaunch(registry: registry);
      final later = ReceivePort();
      addTearDown(later.close);
      registry.names[kSharedRefreshAppPort] = later.sendPort;

      SharedRefreshApp.detached();

      expect(registry.names[kSharedRefreshAppPort], later.sendPort);
    });

    test('where no check exists nothing is registered or looked up', () {
      SharedRefreshAvailability.debugSupported = false;

      expect(SharedRefreshApp.beginLaunch(registry: registry), isNull);
      expect(registry.calls, isEmpty);
    });

    test('a run in flight is asked to yield and waited for', () async {
      final running = run()..open();

      final wait = SharedRefreshApp.beginLaunch(registry: registry);
      expect(wait, isNotNull);
      await running.yieldRequested;
      running.close();

      await wait;
    });

    test(
      'a forwarded read is held until the launch has brought the app up',
      () async {
        var read = false;
        SharedRefreshApp.beginLaunch(
          registry: registry,
          read: (_) async => read = true,
        );
        final forwarding = (run()..open()).forward(limit: limit);
        await Future<void>.delayed(short);
        expect(read, isFalse);

        SharedRefreshApp.launched();

        expect(await forwarding, SharedRefreshForward.done);
        expect(read, isTrue);
      },
    );

    test('reads forwarded while the launch hangs, whose askers gave up, are '
        'dropped: none runs once the app is up, each with an alert pass '
        'nobody waits for (review item 9)', () async {
      var reads = 0;
      SharedRefreshApp.beginLaunch(
        registry: registry,
        read: (_) async => reads++,
        // The asker's own limit, as the app knows it.
        readLimit: short,
      );

      // Each asker waits well past it, so which gave up first is no race.
      final ends = [
        for (var i = 0; i < 3; i++)
          await (run()..open()).forward(limit: short * 3),
      ];
      expect(ends, everyElement(SharedRefreshForward.failed));

      SharedRefreshApp.launched();
      await Future<void>.delayed(short);

      expect(reads, 0);
    });

    test(
      'a read whose asker still waits when the app comes up is made',
      () async {
        var reads = 0;
        SharedRefreshApp.beginLaunch(
          registry: registry,
          read: (_) async => reads++,
          readLimit: limit,
        );
        final late_ = (run()..open()).forward(limit: short);
        expect(await late_, SharedRefreshForward.failed);

        // Its asker's own patience was shorter than the limit the app counts
        // by: the app cannot know, and reads — the one gap left, a trigger
        // the platform tore down early.
        SharedRefreshApp.launched();
        await Future<void>.delayed(short);

        expect(reads, 1);
      },
    );
  });

  group('the app keeps its name while it is in front (review item 4)', () {
    setUp(() {
      SharedRefreshAvailability.debugSupported = true;
      // An install where a trigger can exist: a check was planned once.
      // The timer is started through that gate, open — not through the
      // answer a store that cannot be read gets.
      SharedPreferences.setMockInitialValues({
        SettingsKeys.sharedRefreshPlanned: '1',
      });
    });
    tearDown(() {
      SharedRefreshApp.resetForTesting();
      SharedRefreshAvailability.debugSupported = null;
    });

    test('where the preferences cannot be read the name is kept all the '
        'same: not knowing whether a trigger can exist is no reason to '
        'leave the app without its name', () async {
      ScriptedPrefsStore.install().onRead = (_) => throw StateError('store');
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.inFront(true, every: short);
      final mine = registry.names[kSharedRefreshAppPort];

      registry.names.remove(kSharedRefreshAppPort);
      await Future<void>.delayed(short * 3);

      expect(registry.names[kSharedRefreshAppPort], mine);
    });

    /// What a trigger does to an app that answered none of its pings.
    void takenForDead() => registry.names.remove(kSharedRefreshAppPort);

    test('a name lost mid-session is taken again on the timer, with no '
        'resume in between', () async {
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.inFront(true, every: short);
      final mine = registry.names[kSharedRefreshAppPort];
      expect(mine, isNotNull);

      takenForDead();
      await Future<void>.delayed(short * 3);

      expect(registry.names[kSharedRefreshAppPort], mine);
    });

    test('a name that stands costs a lookup and nothing else', () async {
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.inFront(true, every: short);
      registry.calls.clear();

      await Future<void>.delayed(short * 3);

      expect(registry.calls, isNotEmpty);
      expect(registry.calls.toSet(), {'lookup:$kSharedRefreshAppPort'});
    });

    test('the run that went on beside the app is asked to end as the name '
        'is taken back', () async {
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.inFront(true, every: short);
      takenForDead();
      final beside = run()..open();

      await beside.yieldRequested.timeout(limit);

      expect(registry.names.containsKey(kSharedRefreshAppPort), isTrue);
      beside.close();
    });

    test('not in front nothing is taken again; the resume takes it at '
        'once', () async {
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.inFront(true, every: short);
      SharedRefreshApp.inFront(false);

      takenForDead();
      await Future<void>.delayed(short * 3);
      expect(registry.names.containsKey(kSharedRefreshAppPort), isFalse);

      SharedRefreshApp.inFront(true, every: short);
      expect(registry.names.containsKey(kSharedRefreshAppPort), isTrue);
    });

    test('the launch starts the timer — the app comes up in front and no '
        'lifecycle change says so — at the record\'s interval', () {
      fakeAsync((async) {
        SharedRefreshApp.beginLaunch(registry: registry);
        SharedRefreshApp.launched();
        takenForDead();

        async.elapse(
          kSharedRefreshReassertEvery - const Duration(milliseconds: 1),
        );
        expect(registry.names.containsKey(kSharedRefreshAppPort), isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(registry.names.containsKey(kSharedRefreshAppPort), isTrue);

        SharedRefreshApp.resetForTesting();
      });
    });
  });
}
