import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/push/push_pairing_gateway.dart';
import 'package:anta/services/push/push_registry.dart';
import 'package:anta/utils/pairing_error.dart';

import '../../support/fake_push.dart';
import '../pairing_support.dart';

/// An install whose process dies right after it gave its address up.
class _DiesAfterGivingUp extends FakePushAddressSource {
  @override
  Future<void> giveUp() async {
    await super.giveUp();
    throw StateError('the process died here');
  }
}

/// An address source that says so the moment it is asked to give up.
class _ToldWhenGivingUp extends FakePushAddressSource {
  _ToldWhenGivingUp(this._told);

  final void Function() _told;

  @override
  Future<void> giveUp() {
    _told();
    return super.giveUp();
  }
}

/// This device's entry in the pair's document
/// (`docs/cloud-shared-freshness.md` §7): written only while the open
/// database is paired and syncing and a relay is known, refreshed weekly by
/// this install's own clock, my stale devices dropped against the newest of
/// mine, and gone with its address when the pair ends, at sign-out and when
/// sync stops — a leave bounded whatever is in flight.
void main() {
  const uid = 'uid-a';
  const partner = 'uid-b';
  const device = 'dev-a';
  final server = DateTime.utc(2026, 11, 13, 12);

  late FakePairingGateway pairs;
  late FakePushAddressSource addresses;
  late FakePushRelay relay;
  late PushRegistry registry;
  late PairingGateway gateway;
  late bool syncing;
  late int sharesAsked;
  late int deviceAsked;
  late DateTime phone;
  late String? signedIn;
  late Completer<void>? sharesGate;
  String? storedPair;

  PushRegistry build({Duration leaveDeadline = const Duration(seconds: 5)}) =>
      PushRegistry(
        gateway: pairs,
        addresses: addresses,
        relay: relay,
        shares: (_) async {
          sharesAsked++;
          if (sharesGate case final gate?) await gate.future;
          return syncing;
        },
        storedPair: () async => storedPair,
        deviceId: () async {
          deviceAsked++;
          return device;
        },
        signedIn: () => signedIn,
        prefs: SharedPreferences.getInstance(),
        clock: () => phone,
        leaveDeadline: leaveDeadline,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pairs = FakePairingGateway()..pushClock = server;
    addresses = FakePushAddressSource();
    relay = FakePushRelay()..configured = Uri.parse('https://relay.test');
    syncing = true;
    sharesAsked = 0;
    deviceAsked = 0;
    phone = server;
    signedIn = uid;
    sharesGate = null;
    storedPair = null;
    registry = build();
    gateway = PushPairingGateway(pairs, registry: () => registry);
  });

  tearDown(() => registry.dispose());

  PairRecord pair() => pairs.seedPair([uid, partner]);

  Future<void> hear() async =>
      registry.heardPairs(uid, await pairs.findActivePairs(uid));

  PairPushDevice? entryOf(String pairId, [String id = device]) =>
      pairs.pairs[pairId]!.devicesOf(uid)[id];

  /// The stored write (`pair|address|ms`), the install's memory of where
  /// its entry stands.
  Future<String?> written() async => (await SharedPreferences.getInstance())
      .getString(SettingsKeys.pushWritten);

  PairPushDevice fid(String id, DateTime at) =>
      PairPushDevice(id: id, kind: PairPushDevice.kindFid, at: at);

  test('an install that holds no address and was never paired asks nothing '
      'of anything, the address source included', () async {
    expect(await gateway.findActivePairs(uid), isEmpty);
    await pumpEventQueue();
    await registry.leave(uid);
    await gateway.endPair(pairId: 'gone', endedBy: uid);
    await pumpEventQueue();

    expect(relay.refreshes, 0);
    expect(addresses.registrations, 0);
    expect(addresses.giveUpCalls, 0);
    expect(sharesAsked, 0);
    expect(deviceAsked, 0);
    expect(pairs.pushWrites, isEmpty);
    expect(pairs.readPushRelayCalls, 0);
  });

  test('paired, syncing and a relay known: the answer the app already asked '
      'for writes this device\'s entry', () async {
    final p = pair();
    await gateway.findActivePairs(uid);
    await pumpEventQueue();

    expect(entryOf(p.pairId)?.id, 'fid-1');
    expect(pairs.pushWrites, ['write ${p.pairId} $uid $device fid-1']);
  });

  test('paired but not syncing: nothing is read of the relay and no address '
      'is asked for', () async {
    pair();
    syncing = false;
    await hear();

    expect(relay.refreshes, 0);
    expect(addresses.registrations, 0);
    expect(pairs.pushWrites, isEmpty);
  });

  test('no relay: nothing registers', () async {
    pair();
    relay.configured = null;
    await hear();

    expect(addresses.registrations, 0);
    expect(pairs.pushWrites, isEmpty);
  });

  test('written again seven days after this install last wrote it, by its '
      'own clock', () async {
    final p = pair();
    await hear();
    phone = phone.add(const Duration(days: 6));
    await hear();
    expect(pairs.pushWrites, hasLength(1));

    phone = phone.add(const Duration(days: 2));
    await hear();
    expect(pairs.pushWrites, hasLength(2));
    expect(entryOf(p.pairId)?.id, 'fid-1');
  });

  test('a phone clock a year off writes once, not at every answer, and '
      'drops none of my devices', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {
      'tablet': fid('fid-t', server.subtract(const Duration(days: 30))),
    });
    phone = server.subtract(const Duration(days: 365));
    await hear();
    await hear();
    await hear();
    expect(pairs.pushWrites, ['write ${p.pairId} $uid $device fid-1']);

    phone = server.add(const Duration(days: 365));
    final fresh = build();
    await fresh.heardPairs(uid, await pairs.findActivePairs(uid));
    expect(pairs.pairs[p.pairId]!.devicesOf(uid).keys, contains('tablet'));
    await fresh.dispose();
  });

  test('another address than the stored one is written at once', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {
      device: fid('fid-old', server.subtract(const Duration(hours: 1))),
    });
    await hear();
    expect(entryOf(p.pairId)?.id, 'fid-1');
  });

  test('a device of mine sixty days older than my newest goes with my next '
      'write; one that refreshed stays', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {
      'old-phone': fid('fid-x', server.subtract(const Duration(days: 61))),
      'tablet': fid('fid-y', server.subtract(const Duration(days: 30))),
      'laptop': fid('fid-z', server),
    });
    await hear();

    expect(pairs.pairs[p.pairId]!.devicesOf(uid).keys, {
      'tablet',
      'laptop',
      device,
    });
  });

  test('my map full of five other devices: the write drops my oldest, so '
      'a sixth install still registers', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {
      for (var i = 0; i < 5; i++)
        'old-$i': fid('fid-$i', server.subtract(Duration(days: 10 - i))),
    });
    await hear();

    final mine = pairs.pairs[p.pairId]!.devicesOf(uid);
    expect(mine, hasLength(PushRegistry.maxDevices));
    expect(mine.keys, isNot(contains('old-0')));
    expect(mine[device]?.id, 'fid-1');
  });

  test('a renewal the platform names is written without being asked', () async {
    final p = pair();
    await hear();
    addresses.renew('fid-renewed');
    await pumpEventQueue();

    expect(entryOf(p.pairId)?.id, 'fid-renewed');
  });

  test('a pair this device ends: the partner is poked urgent, the entry '
      'leaves and the address is given up', () async {
    final p = pair();
    await hear();
    await gateway.endPair(pairId: p.pairId, endedBy: uid);
    await pumpEventQueue();

    expect(relay.pokes, [(pair: p.pairId, urgent: true)]);
    expect(entryOf(p.pairId), isNull);
    expect(addresses.giveUps, 1);

    final next = pair();
    await hear();
    expect(entryOf(next.pairId)?.id, 'fid-2');
  });

  test('an end before anything was heard in this process: the address an '
      'earlier process wrote goes with the pair', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {device: fid('fid-1', server)});
    addresses.held = true;
    relay.address = Uri.parse('https://relay.test');
    await registry.endedByMe(p.pairId, uid);

    expect(relay.pokes, [(pair: p.pairId, urgent: true)]);
    expect(entryOf(p.pairId), isNull);
    expect(addresses.giveUps, 1);
  });

  test('a race\'s losing pair: its entry leaves, the address stays for the '
      'pair kept', () async {
    final kept = pair();
    await hear();
    final loser = pair();
    pairs.seedPush(loser.pairId, uid, {device: fid('fid-1', server)});
    await registry.endedByMe(loser.pairId, uid);

    expect(entryOf(loser.pairId), isNull);
    expect(entryOf(kept.pairId)?.id, 'fid-1');
    expect(addresses.giveUps, 0);
  });

  test('with no relay known any more, an end and a leave still remove the '
      'entry and give up the address', () async {
    final p = pair();
    await hear();
    relay.address = null;
    await registry.endedByMe(p.pairId, uid);
    expect(entryOf(p.pairId), isNull);
    expect(addresses.giveUps, 1);

    final next = pair();
    relay.address = Uri.parse('https://relay.test');
    await pairs.endPair(pairId: p.pairId, endedBy: uid);
    await hear();
    relay.address = null;
    relay.configured = null;
    storedPair = next.pairId;
    await registry.leave(uid);
    expect(entryOf(next.pairId), isNull);
    expect(addresses.giveUps, 2);
  });

  test('a new process whose first answer names a later pair: the entry in '
      'the earlier one goes, the address is given up, and the later pair '
      'gets a new one (decision n)', () async {
    final earlier = pair();
    await hear();
    expect(entryOf(earlier.pairId)?.id, 'fid-1');
    await registry.dispose();

    await pairs.endPair(pairId: earlier.pairId, endedBy: partner);
    final later = pairs.seedPair([uid, 'uid-c']);
    // The same installation, in a process that remembers nothing of it.
    addresses = FakePushAddressSource()..held = true;
    registry = build();
    await hear();

    expect(entryOf(earlier.pairId), isNull);
    expect(addresses.giveUps, 1);
    expect(entryOf(later.pairId)?.id, 'fid-2');
    expect(pairs.pushWrites.last, 'write ${later.pairId} $uid $device fid-2');
  });

  test('a removal the earlier pair refuses still gives the address up, '
      'once: the later pair never carries the earlier address', () async {
    final earlier = pair();
    await hear();
    await registry.dispose();
    await pairs.endPair(pairId: earlier.pairId, endedBy: partner);
    final later = pairs.seedPair([uid, 'uid-c']);
    addresses = FakePushAddressSource()..held = true;
    registry = build();
    final answer = await pairs.findActivePairs(uid);
    pairs.failNext = PairingError.offline;
    await registry.heardPairs(uid, answer);
    await hear();

    expect(addresses.giveUps, 1);
    expect(entryOf(later.pairId)?.id, 'fid-2');
  });

  test('a removal the earlier pair refuses keeps the memory of where the '
      'entry was written (PA2\'s default): the next answer asks the removal '
      'again, and the write into the later pair then names that one', () async {
    final earlier = pair();
    await hear();
    await registry.dispose();
    await pairs.endPair(pairId: earlier.pairId, endedBy: partner);
    final later = pairs.seedPair([uid, 'uid-c']);
    addresses = FakePushAddressSource()..held = true;
    registry = build();
    final answer = await pairs.findActivePairs(uid);
    syncing = false;
    pairs.failNext = PairingError.offline;
    await registry.heardPairs(uid, answer);

    expect(entryOf(earlier.pairId)?.id, 'fid-1', reason: 'refused');
    expect(
      PushRegistry.writtenPairOf(await written()),
      earlier.pairId,
      reason: 'kept: only this says where the entry still stands',
    );

    syncing = true;
    await hear();

    expect(entryOf(earlier.pairId), isNull);
    expect(PushRegistry.writtenPairOf(await written()), later.pairId);
    expect(addresses.giveUps, 1);
  });

  test('the earlier address\'s end is made owed before its entry is '
      'removed: a process that dies between the two still knows the pair it '
      'wrote into, and the next one finishes (second look, D3)', () async {
    final earlier = pair();
    await hear();
    await registry.dispose();
    await pairs.endPair(pairId: earlier.pairId, endedBy: partner);
    final later = pairs.seedPair([uid, 'uid-c']);
    final dying = _DiesAfterGivingUp()..held = true;
    addresses = dying;
    registry = build();
    await hear();

    expect(dying.giveUps, 1);
    expect(entryOf(earlier.pairId)?.id, 'fid-1', reason: 'not reached');
    expect(PushRegistry.writtenPairOf(await written()), earlier.pairId);
    await registry.dispose();

    // The next process: nothing held any more, the stored write its memory.
    addresses = FakePushAddressSource()..next = 'fid-2';
    registry = build();
    await hear();

    expect(entryOf(earlier.pairId), isNull);
    expect(entryOf(later.pairId)?.id, 'fid-2');
    expect(PushRegistry.writtenPairOf(await written()), later.pairId);
  });

  group('after a run with the app closed gave the address up (second look, '
      'N3, D4)', () {
    late PairRecord ended;

    /// The app wrote its entry, the partner ended the pair, and a run gave
    /// the address up: nothing is held, and the stored write still names
    /// the pair.
    setUp(() async {
      ended = pair();
      await hear();
      await registry.dispose();
      await pairs.endPair(pairId: ended.pairId, endedBy: partner);
      addresses = FakePushAddressSource()..held = false;
      registry = build();
      pairs.pushWrites.clear();
    });

    test('the next open finishes the end: the entry leaves the pair\'s '
        'document and the stored write is cleared, though nothing is '
        'held', () async {
      await hear();

      expect(entryOf(ended.pairId), isNull);
      expect(await written(), isNull);
      expect(addresses.registrations, 0);

      // And from then on an answer with no pair asks nothing of anything.
      pairs.pushWrites.clear();
      await hear();
      expect(pairs.pushWrites, isEmpty);
    });

    test('a removal that could not be asked is asked again at the next '
        'answer', () async {
      final answer = await pairs.findActivePairs(uid);
      pairs.failNext = PairingError.offline;
      await registry.heardPairs(uid, answer);
      expect(PushRegistry.writtenPairOf(await written()), ended.pairId);

      await hear();
      expect(entryOf(ended.pairId), isNull);
      expect(await written(), isNull);
    });

    test('one the pair refuses for good is not asked at every answer: the '
        'address it names is dead, and the stored write goes', () async {
      final answer = await pairs.findActivePairs(uid);
      pairs.failNext = PairingError.permissionDenied;
      await registry.heardPairs(uid, answer);

      expect(await written(), isNull);
      pairs.pushWrites.clear();
      await hear();
      expect(pairs.pushWrites, isEmpty);
    });
  });

  test('with no live pair too, the address\'s end comes before its entry '
      'is removed: at the give-up the pair\'s document is still untouched '
      '(default (cw))', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {device: fid('fid-1', server)});
    await pairs.endPair(pairId: p.pairId, endedBy: partner);
    storedPair = p.pairId;
    List<String>? writesAtTheGiveUp;
    addresses = _ToldWhenGivingUp(
      () => writesAtTheGiveUp = [...pairs.pushWrites],
    )..held = true;
    registry = build();
    pairs.pushWrites.clear();

    await hear();

    expect(writesAtTheGiveUp, isEmpty);
    expect(pairs.pushWrites, ['remove ${p.pairId} $uid $device']);
  });

  test('the partner ends it: the next answer names no pair, and the entry '
      'and the address go — from the stored pair when this process heard '
      'nothing before', () async {
    final p = pair();
    pairs.seedPush(p.pairId, uid, {device: fid('fid-1', server)});
    addresses.held = true;
    await pairs.endPair(pairId: p.pairId, endedBy: partner);
    storedPair = p.pairId;
    await hear();

    expect(entryOf(p.pairId), isNull);
    expect(addresses.giveUps, 1);
    expect(relay.pokes, isEmpty, reason: 'the partner pokes for their own end');
  });

  test('a leave sends what waits for its minute while the account still '
      'can, the urgent poke of an end queued before it included', () async {
    final p = pair();
    await hear();
    unawaited(registry.endedByMe(p.pairId, uid));
    await registry.leave(uid);

    expect(relay.flushedAt, isNotEmpty);
    expect(relay.flushedAt.last, 1, reason: 'after the end poked');
  });

  test('an install that holds no address still sends what waits at a '
      'leave', () async {
    await registry.leave(uid);
    expect(relay.flushedAt, isNotEmpty);
  });

  test(
    'sign-out leaves from the stored pair when nothing was heard yet',
    () async {
      final p = pair();
      await hear();
      final fresh = build();
      storedPair = p.pairId;
      await fresh.leave(uid);
      expect(entryOf(p.pairId), isNull);
      expect(addresses.giveUps, 1);
      await fresh.dispose();
    },
  );

  test('a leave is bounded, the wait for a registration in flight '
      'included', () async {
    pair();
    addresses.stall = Completer<void>();
    registry = build(leaveDeadline: const Duration(milliseconds: 50));
    unawaited(hear());
    await pumpEventQueue();

    final left = Stopwatch()..start();
    await registry.leave(uid);
    expect(left.elapsed, lessThan(const Duration(seconds: 2)));
    addresses.stall!.complete();
    await pumpEventQueue();
  });

  test('an answer that lands after a leave and a sign-out writes '
      'nothing', () async {
    pair();
    sharesGate = Completer<void>();
    final late = hear();
    await pumpEventQueue();
    final leaving = registry.leave(uid);
    signedIn = null;
    sharesGate!.complete();
    await late;
    await leaving;

    expect(pairs.pushWrites, isEmpty);
  });

  test('each address taken into use or confirmed is told, so the handler '
      'is handed over in this process', () async {
    pair();
    var told = 0;
    final telling = PushRegistry(
      gateway: pairs,
      addresses: addresses,
      relay: relay,
      shares: (_) async => true,
      storedPair: () async => null,
      deviceId: () async => device,
      signedIn: () => signedIn,
      prefs: SharedPreferences.getInstance(),
      clock: () => phone,
      inUse: () => told++,
    );
    addTearDown(telling.dispose);
    await telling.heardPairs(uid, await pairs.findActivePairs(uid));
    await telling.heardPairs(uid, await pairs.findActivePairs(uid));
    expect(told, 2);

    await telling.heardPairs(uid, []);
    expect(told, 2, reason: 'no pair: nothing to hear for');
  });

  test(
    'a database switch forgets the pair the last database stood in',
    () async {
      final p = pair();
      await hear();
      DatabaseLifecycle.notifyDatabaseSwitching();

      await registry.leave(uid);

      expect(entryOf(p.pairId)?.id, 'fid-1');
      expect(addresses.giveUps, 1);
    },
  );

  test('a write that fails is logged, never thrown, and the next answer '
      'writes', () async {
    final p = pair();
    pairs.failAlwaysOnPush = PairingError.offline;
    await hear();
    expect(entryOf(p.pairId), isNull);

    pairs.failAlwaysOnPush = null;
    await hear();
    expect(entryOf(p.pairId)?.id, 'fid-1');
  });

  group('the pair\'s push map reads leniently', () {
    test('an older document, or a malformed entry, reads as no device', () {
      final at = DateTime.utc(2026, 11, 1);
      expect(FirestorePairingGateway.pushFrom(null), isEmpty);
      expect(FirestorePairingGateway.pushFrom('push'), isEmpty);
      expect(
        FirestorePairingGateway.pushFrom({
          uid: {
            'ok': {'id': 'fid-1', 'kind': 'fid', 'at': at},
            'no-id': {'kind': 'fid', 'at': at},
            'empty-id': {'id': '', 'kind': 'fid', 'at': at},
            'no-at': {'id': 'fid-2', 'kind': 'fid'},
            'not-a-map': 7,
          },
          partner: 'nothing',
        }),
        {
          uid: {'ok': PairPushDevice(id: 'fid-1', kind: 'fid', at: at)},
        },
      );
    });
  });
}
