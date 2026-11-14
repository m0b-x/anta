import 'dart:async';
import 'dart:isolate';

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
  bool sharing = true;

  /// Whether the database shares could be told at all.
  bool sharingKnown = true;

  /// A restore, an import or a download marked in flight; null for a store
  /// that could not be read.
  bool? replacingNow = false;

  /// The ask of the marker — first, second, third — from which
  /// [replacingNow] is the answer; before it the answer is "no".
  int replacingFrom = 1;
  int _replacingAsks = 0;

  /// What the open finds where the file was.
  SharedRefreshOpened opened = SharedRefreshOpened.opened;

  /// Whether the app has stored what a pass arms under.
  bool canArm = true;

  /// Whether the read reaches its end.
  bool readCompletes = true;

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
  Future<bool?> replacing() async {
    await _step('replacing');
    return ++_replacingAsks < replacingFrom ? false : replacingNow;
  }

  @override
  Future<int?> storedSchema() async {
    await _step('storedSchema');
    return stored;
  }

  @override
  Future<SharedRefreshOpened> open() async {
    await _step('open');
    return opened;
  }

  @override
  Future<SharedRefreshSharing> shares() async {
    await _step('shares');
    if (!sharingKnown) return SharedRefreshSharing.unknown;
    return sharing ? SharedRefreshSharing.yes : SharedRefreshSharing.no;
  }

  @override
  Future<SharedRefreshWorth?> planSuccessor() async {
    await _step('planSuccessor');
    return canArm ? (check: checkWorthy, poke: pokeWorthy) : null;
  }

  @override
  Future<bool> read() async {
    await _step('read');
    return readCompletes;
  }

  @override
  Future<void> stopRead() async {
    calls.add('stopRead');
    if (!stopped.isCompleted) stopped.complete();
  }

  @override
  Future<void> close() => _step('close');

  /// The give-way count as the trigger asked for it, in order: `again` a
  /// give-way counted, `over` the row ended. Apart from [calls], which is
  /// the run's own order.
  final List<String> counted = [];

  /// Whether a counted give-way still leaves the platform an attempt.
  bool attemptsLeft = true;

  @override
  Future<bool> retryCounted() async {
    counted.add('again');
    return attemptsLeft;
  }

  @override
  Future<void> retriesOver() async => counted.add('over');

  /// How often the work was written off the plan's memory.
  int consumed = 0;

  @override
  Future<void> workConsumed() async => consumed++;
}

/// Steps whose give-way count cannot be kept, as a store that fails would.
class _ThrowingCount extends _FakeSteps {
  @override
  Future<bool> retryCounted() => throw StateError('preferences');
}

/// `SharedRefreshTrigger` — one trigger of the check, and the run without
/// the app in the order of `docs/cloud-shared-freshness.md` §6.
void main() {
  const whole = [
    'prepare',
    'replacing',
    'storedSchema',
    'open',
    'shares',
    'replacing',
    'planSuccessor',
    'replacing',
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
      // "Looked at" is the app's name: a trigger that asked after the app
      // first and took its own name second would still hold it by the time
      // it prepares, and a launch starting in between would see no run.
      expect(
        registry.calls.indexOf('register:$kSharedRefreshRunPort'),
        inInclusiveRange(
          0,
          registry.calls.indexOf('lookup:$kSharedRefreshAppPort') - 1,
        ),
      );
    });

    test(
      'no database file: nothing is opened, so nothing is created',
      () async {
        steps.stored = null;

        expect(await trigger().fire(), SharedRefreshEnd.noDatabase);
        expect(steps.calls, ['prepare', 'replacing', 'storedSchema']);
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
        expect(steps.calls, [
          'prepare',
          'replacing',
          'storedSchema',
        ], reason: '$stored');
      }
    });

    test('a replacement that began after the run\'s first look (review '
        'H10a): the marker is asked again before the alert pass, and the '
        'run arms nothing into the database being replaced', () async {
      steps.replacingFrom = 2;
      steps.replacingNow = true;

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.suspended);
      expect(end.retry, isFalse);
      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'shares',
        'replacing',
        'close',
      ]);
    });

    test('and again before the read: one that began during the alert pass '
        'is read into by nothing', () async {
      steps.replacingFrom = 3;
      steps.replacingNow = true;

      expect(await trigger().fire(), SharedRefreshEnd.suspended);
      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'shares',
        'replacing',
        'planSuccessor',
        'replacing',
        'close',
      ]);
    });

    test('a marker that cannot be read (review H6b) is not a replacement in '
        'flight: nothing is opened, and the platform asks again — at the '
        'first look and at each later one', () async {
      for (final from in [1, 2, 3]) {
        steps = _FakeSteps()
          ..replacingFrom = from
          ..replacingNow = null;

        final end = await trigger().fire();

        expect(end, SharedRefreshEnd.replacingUnknown, reason: 'ask $from');
        expect(end.retry, isTrue);
        expect(steps.calls, isNot(contains('read')));
        expect(steps.calls.contains('open'), from > 1);
        expect(holdsName(), isFalse);
      }
    });

    test('the file went, or changed schema, between the look and the open '
        '(review H10b): the open says so, the run ends as the look would '
        'have ended it — no retry — and what was opened is closed', () async {
      for (final (found, end) in const [
        (SharedRefreshOpened.noDatabase, SharedRefreshEnd.noDatabase),
        (SharedRefreshOpened.schemaMismatch, SharedRefreshEnd.schemaMismatch),
      ]) {
        steps = _FakeSteps()..opened = found;

        final ended = await trigger().fire();

        expect(ended, end);
        expect(ended.retry, isFalse);
        expect(steps.calls, [
          'prepare',
          'replacing',
          'storedSchema',
          'open',
          'close',
        ]);
      }
    });

    test('not bound, not signed in as the bound account, or not paired: '
        'nothing planned or read, no successor', () async {
      steps.sharing = false;

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.notSharing);
      expect(end.retry, isFalse);
      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'shares',
        'close',
      ]);
    });

    test(
      'a database is being replaced: the marker is the first thing '
      'looked at, and nothing — not the file, not the name\'s schema — is '
      'touched after it; no retry, the app that replaces is in front',
      () async {
        steps.replacingNow = true;

        final end = await trigger().fire();

        expect(end, SharedRefreshEnd.suspended);
        expect(end.retry, isFalse);
        expect(steps.calls, ['prepare', 'replacing']);
        expect(holdsName(), isFalse);
      },
    );

    test('whether it shares cannot be told yet — Firebase not up, the '
        'account not restored in time: nothing planned or read, and the '
        'platform is asked to try again', () async {
      steps.sharingKnown = false;

      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.sharingUnknown);
      expect(end.retry, isTrue);
      expect(steps.calls, isNot(contains('planSuccessor')));
      expect(steps.calls.last, 'close');
    });

    test(
      'nothing stored to arm under: no pass ran, nothing is read, and '
      'the ending says so; no retry — only the app\'s own pass stores it',
      () async {
        steps.canArm = false;

        final end = await trigger().fire();

        expect(end, SharedRefreshEnd.noArmContext);
        expect(end.retry, isFalse);
        expect(steps.calls, isNot(contains('read')));
        expect(steps.calls.last, 'close');
      },
    );

    for (final cause in SharedRefreshCause.values) {
      test(
        'a ${cause.name}\'s read that did not complete — offline, '
        'dropped — is not answered as a read: the platform tries again',
        () async {
          steps
            ..readCompletes = false
            ..checkWorthy = cause == SharedRefreshCause.check;

          final end = await trigger(cause: cause).fire();

          expect(end, SharedRefreshEnd.readFailed);
          expect(end.retry, isTrue);
          expect(steps.calls.last, 'close');
        },
      );
    }

    test('an ending whose cause cannot pass by itself never asks for a '
        'retry — a message\'s expedited work would loop on it', () {
      for (final end in const [
        SharedRefreshEnd.schemaMismatch,
        SharedRefreshEnd.notSharing,
        SharedRefreshEnd.noDatabase,
        SharedRefreshEnd.suspended,
        SharedRefreshEnd.noArmContext,
        SharedRefreshEnd.notWanted,
        SharedRefreshEnd.yielded,
        SharedRefreshEnd.gaveWay,
        SharedRefreshEnd.retriesSpent,
      ]) {
        expect(end.retry, isFalse, reason: end.name);
      }
      for (final end in const [
        SharedRefreshEnd.sharingUnknown,
        SharedRefreshEnd.readFailed,
        SharedRefreshEnd.gaveWayOwed,
        SharedRefreshEnd.busy,
        SharedRefreshEnd.cut,
        SharedRefreshEnd.abandoned,
        SharedRefreshEnd.replacingUnknown,
        SharedRefreshEnd.failed,
        SharedRefreshEnd.forwardFailed,
      ]) {
        expect(end.retry, isTrue, reason: end.name);
      }
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
      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'close',
      ]);
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
        'replacing',
        'storedSchema',
        'open',
        'shares',
        'replacing',
        'planSuccessor',
        'replacing',
        'read',
        'stopRead',
        'close',
      ]);
      expect(holdsName(), isFalse);
    });

    test('a step that never returns (review H3): past the limit and the '
        'grace the trigger leaves it — closes what it opened, gives its name '
        'up, ends with a retry — the platform\'s stop returns, and the next '
        'run is not turned away', () async {
      steps.during['planSuccessor'] = () => Completer<void>().future;
      final stuck = SharedRefreshTrigger(
        steps: steps,
        port: SharedRefreshRunPort(registry: registry),
        limit: const Duration(milliseconds: 40),
        grace: const Duration(milliseconds: 40),
      );

      final end = await stuck.fire().timeout(const Duration(seconds: 2));

      expect(end, SharedRefreshEnd.abandoned);
      expect(end.retry, isTrue);
      expect(steps.calls.last, 'close');
      expect(steps.calls, isNot(contains('read')));
      expect(holdsName(), isFalse);
      await stuck.stop().timeout(const Duration(seconds: 2));

      final later = _FakeSteps();
      final laterEnd = await SharedRefreshTrigger(
        steps: later,
        cause: SharedRefreshCause.message,
        port: SharedRefreshRunPort(registry: registry),
      ).fire();
      expect(laterEnd, SharedRefreshEnd.read);
    });

    test('a close that never returns either is given its own bound: the '
        'name is given up all the same', () async {
      steps.during['read'] = () => Completer<void>().future;
      steps.during['close'] = () => Completer<void>().future;

      final end = await SharedRefreshTrigger(
        steps: steps,
        port: SharedRefreshRunPort(registry: registry),
        limit: const Duration(milliseconds: 40),
        grace: const Duration(milliseconds: 40),
        closeBound: const Duration(milliseconds: 40),
      ).fire().timeout(const Duration(seconds: 2));

      expect(end, SharedRefreshEnd.abandoned);
      expect(steps.calls.where((call) => call == 'close'), hasLength(1));
      expect(holdsName(), isFalse);
    });

    test('a step that ends within the grace is not left: the run ends at '
        'its next step, cut', () async {
      steps.during['shares'] = () =>
          Future<void>.delayed(const Duration(milliseconds: 80));

      final end = await SharedRefreshTrigger(
        steps: steps,
        port: SharedRefreshRunPort(registry: registry),
        limit: const Duration(milliseconds: 40),
        grace: const Duration(milliseconds: 400),
      ).fire();

      expect(end, SharedRefreshEnd.cut);
    });

    test('reached before the read, the run ends at its next step and reads '
        'nothing', () async {
      steps.during['shares'] = () =>
          Future<void>.delayed(const Duration(milliseconds: 120));

      final end = await trigger(limit: const Duration(milliseconds: 40)).fire();

      expect(end, SharedRefreshEnd.cut);
      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'shares',
        'close',
      ]);
    });
  });

  group('the platform stops the work', () {
    test('a stop that came before the trigger reached the forward ends it '
        'at once: cut, the name given up, the app never asked and no step '
        'run — not the whole grace as an abandoned forward (review of leg '
        '12, F4)', () async {
      final running = trigger();
      final stopped = running.stop();

      final end = await running.fire().timeout(const Duration(seconds: 1));
      await stopped;

      expect(end, SharedRefreshEnd.cut);
      expect(steps.calls, isEmpty);
      expect(registry.calls, isNot(contains('lookup:$kSharedRefreshAppPort')));
      expect(holdsName(), isFalse);
    });

    test('a message\'s work the platform stopped touches the count neither '
        'way: what it answers is not acted on, and a newer work\'s own end '
        'is the one that counts or clears (review of leg 12, F1)', () async {
      final running = trigger(cause: SharedRefreshCause.message);
      final preparing = Completer<void>();
      final held = Completer<void>();
      steps.during['prepare'] = () {
        preparing.complete();
        return held.future;
      };

      final fired = running.fire();
      await preparing.future;
      final stopped = running.stop();
      held.complete();

      expect(await fired, SharedRefreshEnd.cut);
      await stopped;
      expect(running.stoppedByPlatform, isTrue);
      expect(steps.counted, isEmpty);
    });

    test(
      'only its retrying end is left uncounted: a message\'s work that '
      'had read when the platform stopped it — while it closed — ends the '
      'row of retries like any such end (verification of leg 13, P4)',
      () async {
        final running = trigger(cause: SharedRefreshCause.message);
        final closing = Completer<void>();
        final held = Completer<void>();
        steps.during['close'] = () {
          closing.complete();
          return held.future;
        };

        final fired = running.fire();
        await closing.future;
        final stopped = running.stop();
        held.complete();

        expect(await fired, SharedRefreshEnd.read);
        await stopped;
        expect(running.stoppedByPlatform, isTrue);
        expect(steps.counted, ['over']);
      },
    );

    test('its own limit is no stop of the platform\'s: that end is counted '
        'as ever', () async {
      steps.during['read'] = () => steps.stopped.future;

      final ended = await trigger(
        cause: SharedRefreshCause.message,
        limit: const Duration(milliseconds: 40),
      ).fire();

      expect(ended, SharedRefreshEnd.cut);
      expect(steps.counted, ['again']);
    });

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

    test('an open that returns after the trigger left it cleans up after '
        'itself (closing review, K5; probe R8-D): the database it opened is '
        'closed, no later step is taken, and the work — which is run again '
        '— is not written off', () async {
      final opening = Completer<void>();
      steps.during['open'] = () => opening.future;
      final end = await SharedRefreshTrigger(
        steps: steps,
        port: SharedRefreshRunPort(registry: registry),
        limit: const Duration(milliseconds: 40),
        grace: const Duration(milliseconds: 40),
        closeBound: const Duration(milliseconds: 40),
      ).fire();
      expect(end, SharedRefreshEnd.abandoned);
      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'close',
      ]);

      opening.complete();
      await pumpEventQueue();

      expect(steps.calls, [
        'prepare',
        'replacing',
        'storedSchema',
        'open',
        'close',
        'close',
      ]);
      expect(steps.consumed, 0);
    });

    test('a stop while a step hangs returns once the grace is over '
        '(review H3)', () async {
      steps.during['open'] = () => Completer<void>().future;
      final running = SharedRefreshTrigger(
        steps: steps,
        port: SharedRefreshRunPort(registry: registry),
        grace: const Duration(milliseconds: 40),
      );
      final fired = running.fire();
      await pumpEventQueue();
      expect(steps.calls.last, 'open');

      await running.stop().timeout(const Duration(seconds: 2));

      expect(await fired, SharedRefreshEnd.abandoned);
      expect(steps.calls.last, 'close');
      expect(holdsName(), isFalse);
    });

    test('a stop after the end changes nothing', () async {
      final running = trigger();
      final end = await running.fire();

      await running.stop();

      expect(end, SharedRefreshEnd.read);
      expect(steps.calls, whole);
    });
  });

  group('a second run beside a live one (review item 6)', () {
    SharedRefreshTrigger triggerOf(
      _FakeSteps of, {
      SharedRefreshCause cause = SharedRefreshCause.check,
      Duration yieldTimeout = kSharedRefreshYieldTimeout,
    }) => SharedRefreshTrigger(
      steps: of,
      cause: cause,
      port: SharedRefreshRunPort(
        registry: registry,
        pingTimeout: const Duration(milliseconds: 60),
        yieldTimeout: yieldTimeout,
      ),
    );

    test('a message\'s run beside a live check\'s run: the check\'s run is '
        'asked to end and has ended — read stopped, database closed, name '
        'given up — before the later one prepares, opens, plans or '
        'schedules anything', () async {
      final first = steps;
      first.during['read'] = () => first.stopped.future;
      final firstEnd = triggerOf(first).fire();
      await pumpEventQueue();
      expect(first.calls.last, 'read');

      final second = _FakeSteps();
      List<String>? firstAtSecondStart;
      second.during['prepare'] = () async =>
          firstAtSecondStart = [...first.calls];
      final secondEnd = await triggerOf(
        second,
        cause: SharedRefreshCause.message,
      ).fire();

      // The check's run owes nothing — its successor was planned before
      // its read — so it is never run again for having given way.
      final gaveWay = await firstEnd;
      expect(gaveWay, SharedRefreshEnd.gaveWay);
      expect(gaveWay.retry, isFalse);
      expect(first.counted, ['over']);
      expect(firstAtSecondStart, containsAllInOrder(['stopRead', 'close']));
      expect(secondEnd, SharedRefreshEnd.read);
      expect(second.calls, whole);
      expect(second.counted, ['over']);
      expect(holdsName(), isFalse);
    });

    test('a check\'s run asked to give way before its alert pass returned '
        '(review H5) has planned no successor: it is run again, counted '
        'like a message\'s — and without a retry at the cap', () async {
      for (final attemptsLeft in [true, false]) {
        final check = _FakeSteps()..attemptsLeft = attemptsLeft;
        final gate = Completer<void>();
        check.during['open'] = () => gate.future;
        final checkEnd = triggerOf(check).fire();
        await pumpEventQueue();
        expect(check.calls.last, 'open');

        final message = triggerOf(
          _FakeSteps()..sharing = false,
          cause: SharedRefreshCause.message,
        ).fire();
        await pumpEventQueue();
        gate.complete();

        final end = await checkEnd;
        await message;
        expect(
          end,
          attemptsLeft
              ? SharedRefreshEnd.gaveWayOwed
              : SharedRefreshEnd.gaveWay,
        );
        expect(end.retry, attemptsLeft);
        expect(check.counted, ['again']);
        expect(check.calls, isNot(contains('planSuccessor')));
      }
    });

    /// A message's run held in its read, and a check's run that starts
    /// beside it and finds nothing wanted — the case the change is left
    /// unread in: the first's end.
    Future<SharedRefreshEnd> messageRunBesideALaterCheck(
      _FakeSteps message,
    ) async {
      message.during['read'] = () => message.stopped.future;
      final messageEnd = triggerOf(
        message,
        cause: SharedRefreshCause.message,
      ).fire();
      await pumpEventQueue();
      expect(message.calls.last, 'read');

      final check = _FakeSteps()..checkWorthy = false;
      expect(await triggerOf(check).fire(), SharedRefreshEnd.notWanted);
      expect(check.calls, isNot(contains('read')));
      return messageEnd;
    }

    test('a message\'s run that gives way to a later check\'s run is run '
        'again: that check may want nothing, and the partner\'s change '
        'would wait for the app to be opened', () async {
      final end = await messageRunBesideALaterCheck(steps);

      expect(end, SharedRefreshEnd.gaveWayOwed);
      expect(end.retry, isTrue);
      expect(steps.counted, ['again']);
      expect(steps.calls, containsAllInOrder(['read', 'stopRead', 'close']));
    });

    test('the cap: a message\'s run whose give-ways in a row have reached '
        'the limit ends without a retry — a work that keeps finding a run '
        'ends', () async {
      steps.attemptsLeft = false;

      final end = await messageRunBesideALaterCheck(steps);

      expect(end, SharedRefreshEnd.gaveWay);
      expect(end.retry, isFalse);
      expect(steps.counted, ['again']);
    });

    test('a count that cannot be kept is no retry either', () async {
      final uncounted = _ThrowingCount();

      final end = await messageRunBesideALaterCheck(uncounted);

      expect(end, SharedRefreshEnd.gaveWay);
    });

    test('a message\'s run asked by a run and then by the app gave way to '
        'the app: it reads the share itself, nothing is retried and the row '
        'of give-ways is over', () async {
      steps.during['read'] = () => steps.stopped.future;
      // The database is still open when the app asks too.
      final closing = Completer<void>();
      steps.during['close'] = () => closing.future;
      final messageEnd = triggerOf(
        steps,
        cause: SharedRefreshCause.message,
      ).fire();
      await pumpEventQueue();

      final later = triggerOf(_FakeSteps()).fire();
      await pumpEventQueue();
      expect(steps.calls.last, 'close');
      final launch = SharedRefreshAppPort(
        read: (_) async {},
        registry: registry,
      );
      final wait = launch.yieldRunInFlight();
      await pumpEventQueue();
      closing.complete();

      final end = await messageEnd;
      await wait;
      await later;
      expect(end, SharedRefreshEnd.yielded);
      expect(end.retry, isFalse);
      expect(steps.counted, ['over']);
    });

    test('a live run that does not end when asked: the later one opens '
        'nothing beside it, and the platform is asked to try again', () async {
      final first = steps;
      final hang = Completer<void>();
      first.during['read'] = () => hang.future;
      final firstEnd = triggerOf(first).fire();
      await pumpEventQueue();

      final second = _FakeSteps();
      final end = await triggerOf(
        second,
        cause: SharedRefreshCause.message,
        yieldTimeout: const Duration(milliseconds: 80),
      ).fire();

      expect(end, SharedRefreshEnd.busy);
      expect(end.retry, isTrue);
      expect(second.calls, isEmpty);
      // A message's work that asks to be run again is counted, whatever
      // it ended as (review R3).
      expect(second.counted, ['again']);
      expect(holdsName(), isTrue, reason: 'the first still holds its name');

      hang.complete();
      await firstEnd;
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

    test('a message\'s run gives way to the app as the check\'s does: no '
        'retry — the app reads — and the row of give-ways is over', () async {
      steps.during['read'] = () async {
        unawaited(askYield());
        await steps.stopped.future;
      };

      final end = await trigger(cause: SharedRefreshCause.message).fire();
      await pumpEventQueue();

      expect(end, SharedRefreshEnd.yielded);
      expect(end.retry, isFalse);
      expect(steps.counted, ['over']);
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
      expect(steps.calls, ['prepare', 'replacing', 'storedSchema']);
      expect(answered, 'done');
    });
  });

  group('the app runs in this process', () {
    late List<String> appReads;
    late SharedRefreshAppPort app;

    /// The pair each forwarded read named, null for none.
    late List<String?> appPairs;

    setUp(() {
      appReads = [];
      appPairs = [];
      app = SharedRefreshAppPort(
        read: (ask) async {
          appReads.add('read:${ask.slot?.name ?? 'none'}');
          appPairs.add(ask.pair);
        },
        registry: registry,
      )..open();
    });

    tearDown(() => app.close());

    test(
      'a message\'s forwarded read carries the pair it named, and no '
      'slot; the check\'s own carries its slot and no pair (case B13)',
      () async {
        final end = await SharedRefreshTrigger(
          steps: steps,
          cause: SharedRefreshCause.message,
          pair: 'pair-1',
          port: SharedRefreshRunPort(
            registry: registry,
            pingTimeout: const Duration(milliseconds: 60),
          ),
        ).fire();
        await trigger(slot: SharedRefreshSlot.second).fire();

        expect(end, SharedRefreshEnd.forwarded);
        expect(appReads, ['read:none', 'read:second']);
        expect(appPairs, ['pair-1', null]);
      },
    );

    test('its own isolate does the read: no step of the run is taken, the '
        'database is never opened here', () async {
      final end = await trigger().fire();

      expect(end, SharedRefreshEnd.forwarded);
      expect(end.retry, isFalse);
      expect(appReads, ['read:first']);
      expect(steps.calls, isEmpty);
      expect(holdsName(), isFalse);
    });

    test('a read the app made ends the row of give-ways (review H8): a '
        'message\'s work the app answered is not "in a row" with one that '
        'gave way before it', () async {
      final end = await trigger(cause: SharedRefreshCause.message).fire();

      expect(end, SharedRefreshEnd.forwarded);
      expect(steps.calls, isEmpty);
      expect(steps.counted, ['over']);
    });

    test('the platform stops the work while the app reads (review H10d): '
        'the wait is over at once — not at the limit — and the platform is '
        'asked to try again', () async {
      app.close();
      final reading = Completer<void>();
      final hold = Completer<void>();
      app = SharedRefreshAppPort(
        read: (_) {
          reading.complete();
          return hold.future;
        },
        registry: registry,
      )..open();
      final running = trigger();
      final fired = running.fire();
      await reading.future;

      await running.stop().timeout(const Duration(seconds: 2));

      final end = await fired.timeout(const Duration(seconds: 2));
      expect(end, SharedRefreshEnd.cut);
      expect(end.retry, isTrue);
      expect(steps.calls, isEmpty);
      expect(holdsName(), isFalse);
      hold.complete();
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

    test('a check\'s work the app served is written off by the app, never '
        'from here: the app may have scheduled into that slot since', () async {
      expect(await trigger().fire(), SharedRefreshEnd.forwarded);

      expect(steps.consumed, 0);
    });
  });

  group('a message\'s work that keeps asking for a retry ends (review R3)', () {
    /// Each a message's run that ends asking for a retry, by what makes it.
    final retrying = <SharedRefreshEnd, void Function(_FakeSteps)>{
      SharedRefreshEnd.readFailed: (steps) => steps.readCompletes = false,
      SharedRefreshEnd.failed: (steps) =>
          steps.during['read'] = () async => throw StateError('row'),
      SharedRefreshEnd.sharingUnknown: (steps) => steps.sharingKnown = false,
      SharedRefreshEnd.replacingUnknown: (steps) => steps.replacingNow = null,
    };

    test('every end that asks for one is counted, not the give-ways alone, '
        'and is run again while attempts are left', () async {
      for (final MapEntry(key: end, value: make) in retrying.entries) {
        steps = _FakeSteps();
        make(steps);

        final ended = await trigger(cause: SharedRefreshCause.message).fire();

        expect(ended, end);
        expect(ended.retry, isTrue);
        expect(steps.counted, ['again'], reason: end.name);
      }
    });

    test('at the cap it ends without a retry — the unique work kept '
        'enqueued, later messages waited behind it for good', () async {
      for (final MapEntry(key: end, value: make) in retrying.entries) {
        steps = _FakeSteps()..attemptsLeft = false;
        make(steps);

        final ended = await trigger(cause: SharedRefreshCause.message).fire();

        expect(ended, SharedRefreshEnd.retriesSpent, reason: end.name);
        expect(ended.retry, isFalse);
      }
    });

    test('a count that cannot be kept is no retry either', () async {
      steps = _ThrowingCount()..readCompletes = false;

      final ended = await trigger(cause: SharedRefreshCause.message).fire();

      expect(ended, SharedRefreshEnd.retriesSpent);
    });

    test('an end that asks for none ends the row', () async {
      final ended = await trigger(cause: SharedRefreshCause.message).fire();

      expect(ended, SharedRefreshEnd.read);
      expect(steps.counted, ['over']);
    });

    test('the check\'s own work counts its give-ways only: its retry chain '
        'and its successor replace each other, and the back-off spaces the '
        'rest', () async {
      steps
        ..readCompletes = false
        ..attemptsLeft = false;

      final ended = await trigger().fire();

      expect(ended, SharedRefreshEnd.readFailed);
      expect(ended.retry, isTrue);
      expect(steps.counted, ['over']);
    });
  });

  group('a check\'s work that ends for good stands no more (review R2)', () {
    test('written off the plan\'s memory at every end that asks for no '
        'retry — the ones before the open included, which no step of the '
        'run had said', () async {
      for (final make in <void Function(_FakeSteps)>[
        (steps) {},
        (steps) => steps.stored = null,
        (steps) => steps.replacingNow = true,
        (steps) => steps.sharing = false,
        (steps) => steps.canArm = false,
      ]) {
        steps = _FakeSteps();
        make(steps);

        final ended = await trigger().fire();

        expect(ended.retry, isFalse);
        expect(steps.consumed, 1, reason: ended.name);
      }
    });

    test('never while the platform will run it again, and never for a '
        'message\'s work, which stands in no slot', () async {
      steps.readCompletes = false;
      expect(await trigger().fire(), SharedRefreshEnd.readFailed);
      expect(steps.consumed, 0);

      steps = _FakeSteps();
      await trigger(cause: SharedRefreshCause.message).fire();
      expect(steps.consumed, 0);
    });
  });

  test('a run a launch took for dead on its silence (closing review, K4) '
      'ends at its next step boundary — the yield was already on its way — '
      'takes no further writing step, and leaves alone the name a later run '
      'has taken since', () async {
    final planning = Completer<void>();
    steps.during['planSuccessor'] = () => planning.future;
    final fired = trigger().fire();
    await pumpEventQueue();
    expect(steps.calls.last, 'planSuccessor');

    // No patience at all: the verdict falls before any pong can come.
    final launch = SharedRefreshAppPort(
      read: (_) async {},
      registry: registry,
      deadRunAfter: Duration.zero,
    );
    addTearDown(launch.close);
    expect(await launch.yieldRunInFlight(), isTrue);
    expect(holdsName(), isFalse);
    final later = ReceivePort();
    addTearDown(later.close);
    registry.names[kSharedRefreshRunPort] = later.sendPort;

    // The step in flight goes on a while yet: the yield reaches the run's
    // queue before it ends.
    await pumpEventQueue();
    planning.complete();
    final end = await fired;

    expect(end, SharedRefreshEnd.yielded);
    expect(steps.calls, isNot(contains('read')));
    expect(steps.calls.last, 'close');
    expect(registry.names[kSharedRefreshRunPort], later.sendPort);
  });

  test('a pass that left no plan the work can end on fails the run, and the '
      'platform runs it again (review R1): read as "not wanted" it ended the '
      'chain of checks', () async {
    steps.during['planSuccessor'] = () async => throw StateError('no plan');

    final ended = await trigger().fire();

    expect(ended, SharedRefreshEnd.failed);
    expect(ended.retry, isTrue);
    expect(steps.calls, isNot(contains('read')));
    expect(steps.calls.last, 'close');
  });
}
