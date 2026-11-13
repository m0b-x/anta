import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';

import '../../support/fake_port_registry.dart';

/// The handshake that keeps the database in one isolate
/// (`docs/cloud-shared-freshness.md` §5), both sides driven in one isolate
/// over real ports.
void main() {
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

    test('a run killed with its engine left its name: the next run takes it '
        'over', () {
      final dead = ReceivePort();
      addTearDown(dead.close);
      registry.names[kSharedRefreshRunPort] = dead.sendPort;

      run().open();

      expect(registry.names[kSharedRefreshRunPort], isNot(dead.sendPort));
    });
  });

  group('a launch and a run that start together', () {
    test('each takes its own name before it looks for the other\'s, so the '
        'run forwards and the launch is let go at once', () async {
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
      final launch = app()..open();
      final port = registry.names[kSharedRefreshAppPort];
      registry.calls.clear();

      launch.open();

      expect(registry.names[kSharedRefreshAppPort], port);
      expect(registry.calls, ['lookup:$kSharedRefreshAppPort']);
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

    test('an ordinary launch: the name is taken, one lookup is made, and '
        'there is nothing to await', () {
      final wait = SharedRefreshApp.beginLaunch(registry: registry);

      expect(wait, isNull);
      expect(registry.names.keys, [kSharedRefreshAppPort]);
      expect(
        registry.calls.where((call) => call.contains(kSharedRefreshRunPort)),
        ['lookup:$kSharedRefreshRunPort'],
      );
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
  });
}
