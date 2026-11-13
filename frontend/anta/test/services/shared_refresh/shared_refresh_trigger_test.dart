import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';

import '../../support/fake_port_registry.dart';

/// A run without the app as a list of what it did, each answer scripted.
class _FakeSteps implements SharedRefreshRunSteps {
  final List<String> calls = [];

  int? stored = 7;
  @override
  int schema = 7;
  @override
  bool suspended = false;
  bool sharing = true;

  /// What the pass found: worth the phone's own check, worth a read when a
  /// message comes.
  bool checkWorthy = true;
  bool pokeWorthy = true;

  /// Run inside the step of that name, before it answers.
  final Map<String, Future<void> Function()> during = {};

  /// Completed by [stopRead]; a read that waits on it ends when stopped.
  final Completer<void> stopped = Completer<void>();

  Future<void> _step(String name) async {
    calls.add(name);
    await during[name]?.call();
  }

  @override
  Future<void> prepare() => _step('prepare');

  @override
  Future<int?> storedSchema() async {
    await _step('storedSchema');
    return stored;
  }

  @override
  Future<void> open() => _step('open');

  @override
  Future<bool> shares() async {
    await _step('shares');
    return sharing;
  }

  @override
  Future<SharedRefreshWorth> planSuccessor() async {
    await _step('planSuccessor');
    return (check: checkWorthy, poke: pokeWorthy);
  }

  @override
  Future<void> read() => _step('read');

  @override
  Future<void> stopRead() async {
    calls.add('stopRead');
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  Future<void> close() => _step('close');
}

/// `SharedRefreshTrigger` — one trigger of the check, and the run without
/// the app in the order of `docs/cloud-shared-freshness.md` §6.
void main() {
  const whole = [
    'prepare',
    'storedSchema',
    'open',
    'shares',
    'planSuccessor',
    'read',
    'close',
  ];

  late FakePortRegistry registry;
  late _FakeSteps steps;

  setUp(() {
    registry = FakePortRegistry();
    steps = _FakeSteps();
  });

  SharedRefreshTrigger trigger({
    Duration limit = kSharedRefreshRunLimit,
    SharedRefreshCause cause = SharedRefreshCause.check,
    SharedRefreshSlot slot = SharedRefreshSlot.first,
  }) => SharedRefreshTrigger(
    steps: steps,
    cause: cause,
    slot: slot,
    port: SharedRefreshRunPort(
      registry: registry,
      pingTimeout: const Duration(milliseconds: 60),
    ),
    limit: limit,
  );

  bool holdsName() => registry.names.containsKey(kSharedRefreshRunPort);

  group('the run without the app', () {
    test('wanted: every step in the record\'s order, the successor planned '
        'before the read, the database closed, the name given up', () async {
      var heldWhileOpen = false;
      steps.during['open'] = () async => heldWhileOpen = holdsName();

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.read);
      expect(end.retry, isFalse);
      expect(steps.calls, whole);
      expect(heldWhileOpen, isTrue);
      expect(holdsName(), isFalse);
    });

    test('the name is held before anything is prepared or looked at', () async {
      var heldAtPrepare = false;
      steps.during['prepare'] = () async => heldAtPrepare = holdsName();

      await trigger().fire();

      expect(heldAtPrepare, isTrue);
    });

    test(
      'no database file: nothing is opened, so nothing is created',
      () async {
        steps.stored = null;

        expect(await trigger().fire(), SharedRefreshEnd.noDatabase);
        expect(steps.calls, ['prepare', 'storedSchema']);
        expect(holdsName(), isFalse);
      },
    );

    test('a file of another schema — the app was updated and not opened — '
        'is left alone, older or newer', () async {
      for (final stored in [6, 8, -1]) {
        steps
          ..stored = stored
          ..calls.clear();

        expect(await trigger().fire(), SharedRefreshEnd.schemaMismatch);
        expect(steps.calls, ['prepare', 'storedSchema'], reason: '$stored');
      }
    });

    test(
      'a restore holds sync: closed again, nothing planned or read',
      () async {
        steps.suspended = true;

        expect(await trigger().fire(), SharedRefreshEnd.suspended);
        expect(steps.calls, ['prepare', 'storedSchema', 'open', 'close']);
      },
    );

    test('not bound, not signed in as the bound account, or not paired: '
        'nothing planned or read, no successor', () async {
      steps.sharing = false;

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.notSharing);
      expect(end.retry, isFalse);
      expect(steps.calls, [
        'prepare',
        'storedSchema',
        'open',
        'shares',
        'close',
      ]);
    });

    test('no alert depends on the partner\'s rows: the pass scheduled no '
        'successor and nothing is read', () async {
      steps
        ..checkWorthy = false
        ..pokeWorthy = false;

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.notWanted);
      expect(end.retry, isFalse);
      expect(steps.calls, isNot(contains('read')));
      expect(steps.calls.last, 'close');
    });

    group('what started it decides what it reads for', () {
      for (final (cause, check, poke, reads) in const [
        (SharedRefreshCause.check, true, true, true),
        (SharedRefreshCause.check, false, true, false),
        (SharedRefreshCause.message, false, true, true),
        (SharedRefreshCause.message, false, false, false),
      ]) {
        test('${cause.name}: the check ${check ? 'wanted' : 'not wanted'}, '
            'an alert of mine ${poke ? 'on' : 'on none of'} their events → '
            '${reads ? 'reads' : 'reads nothing'}', () async {
          steps
            ..checkWorthy = check
            ..pokeWorthy = poke;

          final end = await trigger(cause: cause).fire();

          expect(
            end,
            reads ? SharedRefreshEnd.read : SharedRefreshEnd.notWanted,
          );
          expect(steps.calls.contains('read'), reads);
          expect(steps.calls, contains('planSuccessor'));
        });
      }

      test('a work\'s input names its cause; none, or one this build does '
          'not know, is the schedule\'s', () {
        SharedRefreshCause of(Object? value) =>
            SharedRefreshCause.fromInput({kSharedRefreshCauseKey: ?value});

        expect(of('message'), SharedRefreshCause.message);
        expect(of('check'), SharedRefreshCause.check);
        expect(of('later'), SharedRefreshCause.check);
        expect(of(null), SharedRefreshCause.check);
        expect(of(3), SharedRefreshCause.check);
        expect(SharedRefreshCause.fromInput(null), SharedRefreshCause.check);
      });
    });

    test('a throw in the read still closes the database and gives the name '
        'up, and the platform is asked to try again', () async {
      steps.during['read'] = () async => throw StateError('no network');

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.failed);
      expect(end.retry, isTrue);
      expect(steps.calls, whole);
      expect(holdsName(), isFalse);
    });

    test('a throw while opening closes what was opened', () async {
      steps.during['open'] = () async => throw StateError('locked');

      expect(await trigger().fire(), SharedRefreshEnd.failed);
      expect(steps.calls, ['prepare', 'storedSchema', 'open', 'close']);
      expect(holdsName(), isFalse);
    });

    test('a close that throws is logged and the name is given up all the '
        'same', () async {
      steps.during['close'] = () async => throw StateError('busy');

      expect(await trigger().fire(), SharedRefreshEnd.read);
      expect(holdsName(), isFalse);
    });
  });

  group('the limit', () {
    test('past it the read is stopped where it is, the database closed, and '
        'the platform asked to try again', () async {
      steps.during['read'] = () => steps.stopped.future;

      final end = await trigger(limit: const Duration(milliseconds: 80)).fire();

      expect(end, SharedRefreshEnd.cut);
      expect(end.retry, isTrue);
      expect(steps.calls, [
        'prepare',
        'storedSchema',
        'open',
        'shares',
        'planSuccessor',
        'read',
        'stopRead',
        'close',
      ]);
      expect(holdsName(), isFalse);
    });

    test('reached before the read, the run ends at its next step and reads '
        'nothing', () async {
      steps.during['shares'] = () =>
          Future<void>.delayed(const Duration(milliseconds: 120));

      final end = await trigger(limit: const Duration(milliseconds: 40)).fire();

      expect(end, SharedRefreshEnd.cut);
      expect(steps.calls, [
        'prepare',
        'storedSchema',
        'open',
        'shares',
        'close',
      ]);
    });
  });

  group('the platform stops the work', () {
    test('the read is stopped, and the stop completes only once the '
        'database is closed', () async {
      final running = trigger();
      steps.during['read'] = () => steps.stopped.future;
      final reading = Completer<void>();
      final inner = steps.during['read']!;
      steps.during['read'] = () {
        reading.complete();
        return inner();
      };

      final fired = running.fire();
      await reading.future;
      await running.stop();

      expect(steps.calls.last, 'close');
      final end = await fired;
      expect(end, SharedRefreshEnd.cut);
      expect(end.retry, isTrue);
    });

    test('a stop after the end changes nothing', () async {
      final running = trigger();
      final end = await running.fire();

      await running.stop();

      expect(end, SharedRefreshEnd.read);
      expect(steps.calls, whole);
    });
  });

  group('a launch asks for the database', () {
    Future<String?> askYield() async {
      final launch = SharedRefreshAppPort(
        read: (_) async {},
        registry: registry,
      );
      // The launch's look alone: its own name is not what this case is
      // about, and with it the trigger would forward instead.
      final wait = launch.yieldRunInFlight();
      if (wait == null) return null;
      await wait;
      return 'done';
    }

    test('during the read: the read is stopped, the database closed, and '
        'only then is the launch answered; nothing is retried — the app\'s '
        'own start reads the share', () async {
      String? answered;
      var closedBeforeAnswer = false;
      steps.during['read'] = () async {
        unawaited(askYield().then((answer) => answered = answer));
        await steps.stopped.future;
      };
      steps.during['close'] = () async => closedBeforeAnswer = answered == null;

      final end = await trigger().fire();
      await pumpEventQueue();

      expect(end, SharedRefreshEnd.yielded);
      expect(end.retry, isFalse);
      expect(steps.calls, containsAllInOrder(['read', 'stopRead', 'close']));
      expect(closedBeforeAnswer, isTrue);
      expect(answered, 'done');
    });

    test('before the database is opened: it never is', () async {
      String? answered;
      steps.during['prepare'] = () async {
        unawaited(askYield().then((answer) => answered = answer));
        await pumpEventQueue();
      };

      final end = await trigger().fire();
      await pumpEventQueue();

      expect(end, SharedRefreshEnd.yielded);
      expect(steps.calls, ['prepare', 'storedSchema']);
      expect(answered, 'done');
    });
  });

  group('the app runs in this process', () {
    late List<String> appReads;
    late SharedRefreshAppPort app;

    setUp(() {
      appReads = [];
      app = SharedRefreshAppPort(
        read: (slot) async => appReads.add('read:${slot?.name ?? 'none'}'),
        registry: registry,
      )..open();
    });

    tearDown(() => app.close());

    test('its own isolate does the read: no step of the run is taken, the '
        'database is never opened here', () async {
      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.forwarded);
      expect(end.retry, isFalse);
      expect(appReads, ['read:first']);
      expect(steps.calls, isEmpty);
      expect(holdsName(), isFalse);
    });

    test('the app is told which slot the forwarding work runs in: its pass '
        'writes the successor into the other, never over the work that '
        'waits for its answer', () async {
      await trigger(slot: SharedRefreshSlot.second).fire();

      expect(appReads, ['read:second']);
    });

    test('a message\'s work stands in neither slot, whatever its task is '
        'named: the app is told none, so its pass replaces no running work '
        'and forgets no standing check', () async {
      await trigger(
        cause: SharedRefreshCause.message,
        slot: SharedRefreshSlot.second,
      ).fire();

      expect(appReads, ['read:none']);
      expect(
        SharedRefreshCause.check.standsIn(SharedRefreshSlot.second),
        SharedRefreshSlot.second,
      );
    });

    test('its read fails: the platform is asked to try again, and the run '
        'still opens nothing', () async {
      app.close();
      app = SharedRefreshAppPort(
        read: (_) async => throw StateError('engine'),
        registry: registry,
      )..open();

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.forwardFailed);
      expect(end.retry, isTrue);
      expect(steps.calls, isEmpty);
    });
  });
}
