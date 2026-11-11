import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/pairing_error.dart';

import '../database/support/db_test_support.dart';
import 'pairing_support.dart';

/// One device: its own database, its own settings, its own service instance.
/// The singletons are global, so a device is "booted" by resetting them first.
class _Device {
  _Device(this.db, this.auth, this.gateway, this.service);

  final AppDatabase db;
  final FakeAuthService auth;
  final FakePairingGateway gateway;
  final PairingService service;
}

Future<_Device> _boot({
  required FakePairingGateway gateway,
  required FakeAuthService auth,
  AppDatabase? database,
}) async {
  DatabaseLifecycle.notifyDatabaseSwitching();
  SettingsService.reset();
  PairingService.reset();
  final db = database ?? await openTestDatabase();
  final settings = SettingsService.forTesting(db);
  final service = await PairingService.forTesting(
    auth: auth,
    gateway: gateway,
    settings: settings,
  );
  return _Device(db, auth, gateway, service);
}

/// [inner]'s pairs and invites, with every read of one pair failing as a
/// refusal — a pair this account may not read, or a link that dropped.
class _FailingReads extends FakePairingGateway {
  _FailingReads(FakePairingGateway inner) {
    pairs.addAll(inner.pairs);
    invites.addAll(inner.invites);
  }

  @override
  Future<PairRecord?> readPair(String pairId) async =>
      throw const PairingException(PairingError.permissionDenied);
}

/// A gateway whose pair listener hears only what the test sends it — the
/// snapshots a device really gets, one that reads as no document included —
/// and that counts the queries a reconcile makes.
class _ScriptedSnapshots extends FakePairingGateway {
  final StreamController<PairRecord?> snapshots =
      StreamController<PairRecord?>.broadcast();

  int activeQueries = 0;

  @override
  Stream<PairRecord?> watchPair(String pairId) => snapshots.stream;

  @override
  Future<List<PairRecord>> findActivePairs(String uid) {
    activeQueries++;
    return super.findActivePairs(uid);
  }

  @override
  Future<void> dispose() async {
    await snapshots.close();
    await super.dispose();
  }
}

const _lifetime = Duration(minutes: 10);

void main() {
  // Each "device" opens its own in-memory database on purpose — that is what
  // makes the per-database pairing cases real.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
  });

  group('codes', () {
    test('normalizes case, separators and whitespace to one code', () {
      expect(PairingService.normalizeCode('k7m2-p4xq'), 'K7M2P4XQ');
      expect(PairingService.normalizeCode(' K7M2 P4XQ '), 'K7M2P4XQ');
    });

    test('drops glyphs the alphabet excludes rather than guessing', () {
      // `0`, `O`, `1`, `I`, `L` and `U` are absent so a code can be read
      // aloud; a typo containing them shortens the code and fails cleanly.
      expect(PairingService.normalizeCode('K0O1ILU2'), 'K2');
    });

    test('formats as two groups for reading aloud', () {
      expect(PairingService.formatCode('K7M2P4XQ'), 'K7M2-P4XQ');
    });
  });

  group('redeem', () {
    test('rejects the code this device generated', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final device = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );

      final status = await device.service.generateInvite();
      expect(status.pendingCode, isNotNull);

      await expectLater(
        device.service.redeem(status.pendingCode!),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.ownCode,
          ),
        ),
      );
      expect(gateway.createPairCalls, 0);
    });

    test('an expired code fails before any pair is created', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final status = await creator.service.generateInvite();
      final code = status.pendingCode!;

      // Expire it the way the server would, then redeem on the other device.
      final invite = gateway.invites[code]!;
      gateway.invites[code] = InviteRecord(
        code: invite.code,
        creatorUid: invite.creatorUid,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );

      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      await expectLater(
        redeemer.service.redeem(code),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.codeInvalid,
          ),
        ),
      );
      expect(gateway.createPairCalls, 0);
    });

    test('a completed round-trip pairs both accounts', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final code = (await creator.service.generateInvite()).pendingCode!;

      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      final redeemed = await redeemer.service.redeem(code);

      expect(redeemed.isPaired, isTrue);
      expect(redeemed.partner?.uid, userA.uid);
      // The invite is consumed, so the code cannot be used a second time.
      expect(gateway.invites[code]?.isRedeemed, isTrue);
    });

    test('a failed claim does not leave an orphaned pair behind', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final code = (await creator.service.generateInvite()).pendingCode!;

      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      // Someone else claims it in the window between the read and the claim.
      // The pair is created before the claim by design, so losing this race
      // is exactly the case that must not leak a live pair.
      gateway.beforeClaim = () {
        gateway.beforeClaim = null;
        final invite = gateway.invites[code]!;
        gateway.invites[code] = InviteRecord(
          code: invite.code,
          creatorUid: invite.creatorUid,
          expiresAt: invite.expiresAt,
          pairId: 'pair-other',
          redeemedBy: 'uid-c',
        );
      };

      await expectLater(
        redeemer.service.redeem(code),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.codeInvalid,
          ),
        ),
      );
      expect(gateway.endedPairs, hasLength(1));
      expect(gateway.pairs[gateway.endedPairs.single]!.isActive, isFalse);
      expect(redeemer.service.status.isPaired, isFalse);
    });

    test(
      'a permission-denied read from a mistyped code surfaces as invalid, not as permission denied',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final device = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );

        // Firestore rules deny reads of an expired invite, so a mistyped code
        // reaches `readInvite` as permission-denied rather than "not found".
        gateway.failNext = PairingError.permissionDenied;
        await expectLater(
          device.service.redeem('K7M2P4XQ'),
          throwsA(
            isA<PairingException>().having(
              (e) => e.error,
              'error',
              PairingError.codeInvalid,
            ),
          ),
        );
      },
    );
  });

  group('generateInvite', () {
    test(
      'a code collision is retried rather than surfaced to the caller',
      () async {
        final gateway = FakePairingGateway()..rejectNextInvites = 4;
        addTearDown(gateway.dispose);
        final device = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );

        final status = await device.service.generateInvite();

        expect(status.pendingCode, isNotNull);
        expect(status.pendingCode!.length, PairingService.codeLength);
      },
    );
  });

  group('gateway invariants', () {
    test(
      'createPair refuses a pair with no matching live invite from the partner',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);

        // Mirrors the security rule that stops anyone who knows your uid from
        // forcing a pair on you: without a live, unclaimed invite the creator
        // handed out, the write must be denied.
        await expectLater(
          gateway.createPair(
            self: PairProfile.fromUser(userA),
            partner: PairProfile.fromUser(userB),
            inviteCode: 'no-such-code',
          ),
          throwsA(
            isA<PairingException>().having(
              (e) => e.error,
              'error',
              PairingError.permissionDenied,
            ),
          ),
        );
      },
    );
  });

  group('reconciliation', () {
    test(
      'a second database on the same account adopts the existing pair',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final creator = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await creator.service.generateInvite()).pendingCode!;
        final redeemer = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
        );
        await redeemer.service.redeem(code);
        final pairsBefore = gateway.createPairCalls;

        // A different local database for the same signed-in account: pairing
        // settings do not travel, so this starts with nothing cached.
        final second = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
        );
        final status = await second.service.load();

        expect(status.isPaired, isTrue);
        expect(status.partner?.uid, userA.uid);
        expect(
          gateway.createPairCalls,
          pairsBefore,
          reason: 'adopting must not fork a second pair',
        );
      },
    );

    test(
      'two active pairs converge on the earliest, tombstoning the rest',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final first = gateway.seedPair(['uid-a', 'uid-b']);
        final second = gateway.seedPair(['uid-b', 'uid-a']);
        expect(first.createdAt.isBefore(second.createdAt), isTrue);

        final device = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final status = await device.service.load();

        expect(status.pairId, first.pairId);
        expect(gateway.pairs[second.pairId]!.isActive, isFalse);
      },
    );

    test('a pair tombstoned while offline raises the ended notice', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final code = (await creator.service.generateInvite()).pendingCode!;
      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      final paired = await redeemer.service.redeem(code);

      // The partner unpaired while this device was away.
      await gateway.endPair(pairId: paired.pairId!, endedBy: userA.uid);

      final status = await redeemer.service.load();
      expect(status.isPaired, isFalse);
      expect(status.endedNoticePending, isTrue);
    });

    test('a pair removed while this device was away raises the ended '
        'notice too: only the partner deleting their account removes one '
        '(cloud-multi-user-roadmap §6.1 g)', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final code = (await creator.service.generateInvite()).pendingCode!;
      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      final paired = await redeemer.service.redeem(code);

      await gateway.endPair(pairId: paired.pairId!, endedBy: userA.uid);
      await gateway.deletePair(paired.pairId!);

      final status = await redeemer.service.load();
      expect(status.isPaired, isFalse);
      expect(status.endedNoticePending, isTrue);
    });

    test('a pair that could not be read says nothing: unpaired, with no '
        'notice blaming the partner', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final code = (await creator.service.generateInvite()).pendingCode!;
      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      final paired = await redeemer.service.redeem(code);
      await gateway.endPair(pairId: paired.pairId!, endedBy: userB.uid);
      // The reconcile's query answers; the read of the pair after it fails.
      final reads = _FailingReads(gateway);
      final device = await _boot(
        gateway: reads,
        auth: FakeAuthService(user: userB),
        database: redeemer.db,
      );

      final status = await device.service.load();
      expect(status.isPaired, isFalse);
      expect(status.endedNoticePending, isFalse);
    });

    test('a pair removed while this device listens — heard as a snapshot '
        'with no document, after a live one — is asked of the server and '
        'raises the ended notice', () async {
      final gateway = _ScriptedSnapshots();
      addTearDown(gateway.dispose);
      await gateway.createInvite(
        code: 'K7M2P4XQ',
        creatorUid: userA.uid,
        lifetime: _lifetime,
      );
      final device = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      final paired = await device.service.redeem('K7M2P4XQ');
      final statuses = <PairingStatus>[];
      final heard = device.service.changes.listen(statuses.add);
      addTearDown(heard.cancel);
      gateway.snapshots.add(gateway.pairs[paired.pairId!]);
      await pumpEventQueue();

      // The partner deleted their account: the pair ended and was removed
      // within a round trip, and only the removal was heard.
      gateway.pairs.remove(paired.pairId!);
      gateway.snapshots.add(null);
      await pumpEventQueue();

      expect(device.service.status.isPaired, isFalse);
      expect(device.service.status.endedNoticePending, isTrue);
      expect(statuses.last.endedNoticePending, isTrue);
    });

    test('a first snapshot that reads as no document — a pair just written, '
        'its server time still to come — decides nothing', () async {
      final gateway = _ScriptedSnapshots();
      addTearDown(gateway.dispose);
      await gateway.createInvite(
        code: 'K7M2P4XQ',
        creatorUid: userA.uid,
        lifetime: _lifetime,
      );
      final device = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      await device.service.redeem('K7M2P4XQ');
      final asked = gateway.activeQueries;

      gateway.snapshots.add(null);
      await pumpEventQueue();

      // No reconcile: a query that does not see the new pair yet would read
      // as the pair having vanished.
      expect(gateway.activeQueries, asked);
      expect(device.service.status.isPaired, isTrue);
    });

    test(
      'forget drops the pairing with no word to the server, no notice '
      'and no listener left: what the account\'s own deletion then does '
      'to the pair blames nobody (cloud-multi-user-roadmap §6.1 g)',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        await gateway.createInvite(
          code: 'K7M2P4XQ',
          creatorUid: userA.uid,
          lifetime: _lifetime,
        );
        final device = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
        );
        final paired = await device.service.redeem('K7M2P4XQ');
        final pairId = paired.pairId!;
        expect(gateway.hasPairListener(pairId), isTrue);
        final statuses = <PairingStatus>[];
        final heard = device.service.changes.listen(statuses.add);
        addTearDown(heard.cancel);

        final status = await device.service.forget();
        await pumpEventQueue();

        expect(status.isPaired, isFalse);
        expect(status.endedNoticePending, isFalse);
        expect(statuses, [status]);
        expect(gateway.endedPairs, isEmpty);
        expect(gateway.pairs[pairId]!.isActive, isTrue);
        expect(gateway.hasPairListener(pairId), isFalse);

        await gateway.endPair(pairId: pairId, endedBy: userB.uid);
        await gateway.deletePair(pairId);
        await pumpEventQueue();
        expect(device.service.status.endedNoticePending, isFalse);
        expect(statuses, [status]);
      },
    );

    test('forget with nothing paired is still quiet', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final device = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );

      final status = await device.service.forget();

      expect(status.isPaired, isFalse);
      expect(status.endedNoticePending, isFalse);
    });

    test('unpairing yourself does not raise an ended notice', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      final creator = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );
      final code = (await creator.service.generateInvite()).pendingCode!;
      final redeemer = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userB),
      );
      await redeemer.service.redeem(code);

      final status = await redeemer.service.unpair();
      expect(status.isPaired, isFalse);
      expect(status.endedNoticePending, isFalse);
    });

    test(
      'signing in as a different account clears the stored pairing',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final creator = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await creator.service.generateInvite()).pendingCode!;

        final auth = FakeAuthService(user: userB);
        final device = await _boot(gateway: gateway, auth: auth);
        await device.service.redeem(code);
        expect(device.service.status.isPaired, isTrue);

        // Same database, different Google account: the stored pairId now
        // belongs to nobody signed in here.
        final readCallsBeforeSwitch = gateway.readPairCalls;
        auth.emitAuth(const AppUser(uid: 'uid-c'));
        final status = await device.service.load();

        expect(status.isPaired, isFalse);
        expect(status.endedNoticePending, isFalse);
        expect(
          gateway.readPairCalls,
          readCallsBeforeSwitch,
          reason:
              'a different account must be rejected by the mismatch check '
              'itself, not by falling through to the vanished-pair path that '
              'reads the old pair',
        );
      },
    );

    test(
      'a pending invite survives a restart and still adopts its pair',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final creator = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
          database: db,
        );
        final code = (await creator.service.generateInvite()).pendingCode!;

        final redeemer = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
        );
        await redeemer.service.redeem(code);

        // The creator's app restarts: same database, brand new service.
        final restarted = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
          database: db,
        );
        final status = await restarted.service.load();

        expect(
          status.isPaired,
          isTrue,
          reason: 'the persisted code is what stops the creator being stranded',
        );
        expect(status.partner?.uid, userB.uid);
      },
    );

    test(
      'both sides generating and redeeming converge on the earliest pair without a false ended notice',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final deviceA = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final deviceB = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
        );

        // Minted straight through the gateway — the same primitive
        // `generateInvite` calls — so neither device has a live invite
        // listener of its own; otherwise the creator's listener races ahead
        // and auto-adopts before its explicit `redeem` below runs, and only
        // one real pair is ever created instead of two.
        const codeFromA = 'AAAA2222';
        const codeFromB = 'BBBB3333';
        await gateway.createInvite(
          code: codeFromA,
          creatorUid: userA.uid,
          lifetime: PairingService.inviteLifetime,
        );
        await gateway.createInvite(
          code: codeFromB,
          creatorUid: userB.uid,
          lifetime: PairingService.inviteLifetime,
        );

        // Each device redeems the other's code: the real race, not
        // `gateway.seedPair`'s pre-planted pairs, so it actually forks two
        // independently-created pairs.
        final earlierPairId = (await deviceB.service.redeem(codeFromA)).pairId!;
        final laterPairId = (await deviceA.service.redeem(codeFromB)).pairId!;
        expect(
          gateway.pairs,
          hasLength(2),
          reason: 'the race must fork two real pairs, not converge for free',
        );
        expect(earlierPairId, isNot(laterPairId));

        // A is left watching the pair that loses the tie-break — the
        // interesting half of the bug: it must silently reconverge, not
        // claim its partner ended the link.
        await deviceB.service.load();
        await pumpEventQueue();

        expect(deviceA.service.status.pairId, earlierPairId);
        expect(deviceB.service.status.pairId, earlierPairId);
        expect(
          deviceA.service.status.endedNoticePending,
          isFalse,
          reason:
              'the loser of a same-pair race must silently reconverge, not '
              'raise a false "partner ended sharing" notice',
        );
      },
    );
  });

  group('listeners', () {
    test(
      'the creator adopts the pair through its invite listener alone, without ever reloading',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final creator = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await creator.service.generateInvite()).pendingCode!;

        final statuses = <PairingStatus>[];
        final sub = creator.service.changes.listen(statuses.add);
        addTearDown(sub.cancel);

        // The redeemer's half of the round trip, driven straight through the
        // gateway so the creator's PairingService is never reloaded: booting
        // a second PairingService would call `reset()` on the singleton and
        // detach the very listener under test.
        final pair = await gateway.createPair(
          self: PairProfile.fromUser(userB),
          partner: PairProfile(uid: userA.uid),
          inviteCode: code,
        );
        await gateway.claimInvite(
          code: code,
          pairId: pair.pairId,
          redeemerUid: userB.uid,
        );
        await pumpEventQueue();

        expect(
          statuses.map((s) => s.isPaired),
          contains(true),
          reason:
              'the invite listener, not a reload, is what tells the creator '
              'it is now paired',
        );
        expect(creator.service.status.pairId, pair.pairId);
        expect(creator.service.status.partner?.uid, userB.uid);
      },
    );
  });

  group('offline', () {
    test(
      'a failed reconcile keeps the cached pairing instead of clearing it',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final creator = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await creator.service.generateInvite()).pendingCode!;
        final auth = FakeAuthService(user: userB);
        final db = await openTestDatabase();
        final redeemer = await _boot(
          gateway: gateway,
          auth: auth,
          database: db,
        );
        await redeemer.service.redeem(code);

        gateway.failAlways = PairingError.offline;
        final restarted = await _boot(
          gateway: gateway,
          auth: auth,
          database: db,
        );

        await expectLater(
          restarted.service.load(),
          throwsA(
            isA<PairingException>().having(
              (e) => e.error,
              'error',
              PairingError.offline,
            ),
          ),
        );
        expect(
          restarted.service.status.isPaired,
          isTrue,
          reason: 'opening Sharing on a train must not read as "not paired"',
        );
        expect(
          gateway.hasPairListener(restarted.service.status.pairId!),
          isTrue,
          reason:
              'load() must attach listeners even when reconcile throws, or the '
              'device goes permanently deaf after one offline page open',
        );
      },
    );

    test('generating a code offline surfaces the offline error', () async {
      final gateway = FakePairingGateway()..failAlways = PairingError.offline;
      addTearDown(gateway.dispose);
      final device = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );

      await expectLater(
        device.service.generateInvite(),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.offline,
          ),
        ),
      );
    });

    test(
      'pairing while signed out fails before touching the network',
      () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final device = await _boot(gateway: gateway, auth: FakeAuthService());

        await expectLater(
          device.service.generateInvite(),
          throwsA(
            isA<PairingException>().having(
              (e) => e.error,
              'error',
              PairingError.notSignedIn,
            ),
          ),
        );
        expect(gateway.invites, isEmpty);
      },
    );

    test('an unavailable binding refuses rather than half-working', () async {
      final gateway = FakePairingGateway(available: false);
      addTearDown(gateway.dispose);
      final device = await _boot(
        gateway: gateway,
        auth: FakeAuthService(user: userA),
      );

      await expectLater(
        device.service.generateInvite(),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.unavailable,
          ),
        ),
      );
    });
  });
}
