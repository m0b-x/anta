import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/push/push_pairing_gateway.dart';
import 'package:anta/services/push/push_registry.dart';
import 'package:anta/utils/pairing_error.dart';

import '../../support/fake_push.dart';
import '../pairing_support.dart';

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

  test('sign-out leaves from the stored pair when nothing was heard yet', () async {
    final p = pair();
    await hear();
    final fresh = build();
    storedPair = p.pairId;
    await fresh.leave(uid);
    expect(entryOf(p.pairId), isNull);
    expect(addresses.giveUps, 1);
    await fresh.dispose();
  });

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

  test('a database switch forgets the pair the last database stood in', () async {
    final p = pair();
    await hear();
    DatabaseLifecycle.notifyDatabaseSwitching();

    await registry.leave(uid);

    expect(entryOf(p.pairId)?.id, 'fid-1');
    expect(addresses.giveUps, 1);
  });

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
