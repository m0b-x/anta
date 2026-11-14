import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
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
  Future<void> Function()? reconcileAlerts,
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
    reconcileAlerts: reconcileAlerts ?? () async {},
  );
  return _Device(db, auth, gateway, service);
}

/// A server that, while [empty], names no pair and cannot be read: a link
/// that dropped mid-answer.
class _TransientlyEmpty extends FakePairingGateway {
  bool empty = false;

  @override
  Future<List<PairRecord>> findActivePairs(String uid) async =>
      empty ? const [] : await super.findActivePairs(uid);

  @override
  Future<PairRecord?> readPair(String pairId) async => empty
      ? throw const PairingException(PairingError.offline)
      : await super.readPair(pairId);
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

/// A gateway that counts the listeners opened on it — a pair's and an
/// invite's alike.
class _WatchCounting extends FakePairingGateway {
  int watches = 0;

  @override
  Stream<PairRecord?> watchPair(String pairId) {
    watches++;
    return super.watchPair(pairId);
  }

  @override
  Stream<InviteRecord?> watchInvite(String code) {
    watches++;
    return super.watchInvite(code);
  }
}

/// Once [armed], every write to the database fails — a full disk.
class _FailingWrites extends QueryInterceptor {
  bool armed = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => armed
      ? Future.error(StateError('disk full'))
      : super.runInsert(executor, statement, args);

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => armed
      ? Future.error(StateError('disk full'))
      : super.runDelete(executor, statement, args);
}

/// Once [armed], every write of the setting [key] fails; every other
/// statement runs.
class _FailingKey extends QueryInterceptor {
  _FailingKey(this.key);

  final String key;
  bool armed = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => armed && args.contains(key)
      ? Future.error(StateError('disk full'))
      : super.runInsert(executor, statement, args);
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

  test('the pairing is read in one statement, for an account that never '
      'paired too — seven before the leave notice kept its pair', () async {
    final counter = StatementCounter();
    final db = await openTestDatabase(interceptor: counter);
    addTearDown(db.close);
    final settings = SettingsService.forTesting(db);
    counter.reset();

    expect(await settings.getPairingSettings(), PairingSettings.empty);
    expect(counter.captured, hasLength(1));
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

    test('a pair is named after its invite: the code, then what the device '
        'that makes it adds — the shape the rules hold a new pair to, and '
        'short enough for a shared document to carry', () {
      final id = PairingGateway.pairIdFor('K7M2P4XQ', 'a' * 20);

      expect(id, 'K7M2P4XQ_${'a' * 20}');
      expect(id.split('_').first, 'K7M2P4XQ');
      expect(id.length, lessThanOrEqualTo(64));
      // No code holds the separator, so the first half is always the code.
      expect(PairingService.codeAlphabet.contains('_'), isFalse);
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

    test(
      'a code someone else claims first makes no pair: the pair and the '
      'claim are one write, so losing the race leaves nothing to end',
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
        // Someone else claims it in the window between the read and the write.
        gateway.beforeCreatePair = () {
          gateway.beforeCreatePair = null;
          gateway.seedClaim(code, pairId: 'pair-other', redeemerUid: 'uid-c');
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
        expect(gateway.pairs, isEmpty);
        expect(gateway.endedPairs, isEmpty);
        expect(gateway.invites[code]!.pairId, 'pair-other');
        expect(redeemer.service.status.isPaired, isFalse);
      },
    );

    test('a redemption whose write landed and whose answer was lost is '
        'paired all the same: the server is asked once before the failure '
        'is believed, where a second try would have been told the code is '
        'not valid', () async {
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
      gateway.loseCreatePairAnswer = PairingError.offline;

      final status = await redeemer.service.redeem(code);

      expect(status.isPaired, isTrue);
      expect(status.partner?.uid, userA.uid);
      expect(gateway.pairs, hasLength(1));
    });

    test('and when the server cannot be asked either, the next try of the '
        'same code finds it claimed by this very account and is paired — '
        'not told that its own redeemed code is not valid', () async {
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
      gateway.loseCreatePairAnswer = PairingError.offline;
      // The link is down for the check that follows the lost answer too.
      gateway.beforeCreatePair = () {
        gateway.beforeCreatePair = null;
        gateway.failNext = PairingError.offline;
      };

      await expectLater(
        redeemer.service.redeem(code),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.offline,
          ),
        ),
      );
      expect(gateway.pairs, hasLength(1));

      final status = await redeemer.service.redeem(code);

      expect(status.isPaired, isTrue);
      expect(status.partner?.uid, userA.uid);
      expect(gateway.pairs, hasLength(1));
    });

    test('a redemption that failed does not answer "paired" for a pair it '
        'did not make: one another account made from this account\'s own '
        'code is adopted, and the failure still told', () async {
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
      gateway.beforeCreatePair = () {
        gateway.beforeCreatePair = null;
        gateway.seedPair([userB.uid, 'uid-c']);
        throw const PairingException(PairingError.unknown);
      };

      await expectLater(
        redeemer.service.redeem(code),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.unknown,
          ),
        ),
      );
      expect(gateway.invites[code]!.isRedeemed, isFalse);
      expect(redeemer.service.status.partner?.uid, 'uid-c');
    });

    test('a refusal by the rules that is not about the invite stays a '
        'refusal: only a code found spent is "not valid"', () async {
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
      gateway.beforeCreatePair = () {
        gateway.beforeCreatePair = null;
        throw const PairingException(PairingError.permissionDenied);
      };

      await expectLater(
        redeemer.service.redeem(code),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.permissionDenied,
          ),
        ),
      );
    });

    test('a redemption that failed before anything was written still '
        'fails as it did: nothing to adopt', () async {
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
      // The invite's read succeeds, the write is never made.
      gateway.beforeCreatePair = () {
        gateway.beforeCreatePair = null;
        throw const PairingException(PairingError.offline);
      };

      await expectLater(
        redeemer.service.redeem(code),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.offline,
          ),
        ),
      );
      expect(gateway.pairs, isEmpty);
      expect(redeemer.service.status.isPaired, isFalse);
    });

    test('an invite that runs out between its read and the write is the '
        'same wrong code, not a matter of permission', () async {
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
      gateway.beforeCreatePair = () {
        gateway.beforeCreatePair = null;
        final invite = gateway.invites[code]!;
        gateway.invites[code] = InviteRecord(
          code: invite.code,
          creatorUid: invite.creatorUid,
          expiresAt: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
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
      expect(gateway.pairs, isEmpty);
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
        Matcher refusedAs(PairingError error) => throwsA(
          isA<PairingException>().having((e) => e.error, 'error', error),
        );

        // Mirrors the security rule that stops anyone who knows your uid from
        // forcing a pair on you: without a live, unclaimed invite the creator
        // handed out, the write must be denied. A code that names no invite
        // is told apart: the gateway looks before it writes.
        await expectLater(
          gateway.createPair(
            self: PairProfile.fromUser(userA),
            partner: PairProfile.fromUser(userB),
            inviteCode: 'no-such-code',
          ),
          refusedAs(PairingError.codeInvalid),
        );
        await gateway.createInvite(
          code: 'K7M2P4XQ',
          creatorUid: 'uid-c',
          lifetime: const Duration(minutes: 10),
        );
        await expectLater(
          gateway.createPair(
            self: PairProfile.fromUser(userA),
            partner: PairProfile.fromUser(userB),
            inviteCode: 'K7M2P4XQ',
          ),
          refusedAs(PairingError.permissionDenied),
        );
        expect(gateway.pairs, isEmpty);
        expect(gateway.invites['K7M2P4XQ']!.isRedeemed, isFalse);
      },
    );

    test('createPair spends the invite with the pair it creates, in one '
        'write: the same code makes no second pair', () async {
      final gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await gateway.createInvite(
        code: 'K7M2P4XQ',
        creatorUid: userB.uid,
        lifetime: const Duration(minutes: 10),
      );

      final pair = await gateway.createPair(
        self: PairProfile.fromUser(userA),
        partner: PairProfile(uid: userB.uid),
        inviteCode: 'K7M2P4XQ',
      );

      final invite = gateway.invites['K7M2P4XQ']!;
      expect(invite.pairId, pair.pairId);
      expect(invite.redeemedBy, userA.uid);
      await expectLater(
        gateway.createPair(
          self: PairProfile.fromUser(userA),
          partner: PairProfile(uid: userB.uid),
          inviteCode: 'K7M2P4XQ',
        ),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.codeInvalid,
          ),
        ),
      );
      expect(gateway.pairs, hasLength(1));
    });

    test('an active pair the server names and this build cannot read fails '
        'the answer — never "no pair", which would end everything the pair '
        'carries on this device', () {
      final created = DateTime.utc(2026, 11, 1);
      Map<String, dynamic> pair({Object? createdAt}) => {
        'members': [userA.uid, userB.uid],
        'status': 'active',
        'createdAt': createdAt,
      };

      expect(
        FirestorePairingGateway.activePairsFrom({
          'p1': pair(createdAt: created),
        }).single.pairId,
        'p1',
      );
      expect(
        () => FirestorePairingGateway.activePairsFrom({
          'p1': pair(createdAt: created),
          'p2': pair(),
        }),
        throwsA(
          isA<PairingException>().having(
            (e) => e.error,
            'error',
            PairingError.unknown,
          ),
        ),
      );
      expect(FirestorePairingGateway.activePairsFrom(const {}), isEmpty);
    });
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

    group('who ended it, for the leave notice (D35)', () {
      Future<({PairingService me, String pairId})> paired(
        FakePairingGateway gateway, {
        AppDatabase? database,
      }) async {
        final creator = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await creator.service.generateInvite()).pendingCode!;
        final redeemer = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
          database: database,
        );
        final status = await redeemer.service.redeem(code);
        return (me: redeemer.service, pairId: status.pairId!);
      }

      /// Alex — named on the pair — ends it, and I have heard.
      Future<({PairingService me, String pairId})> endedByAlex(
        FakePairingGateway gateway, {
        AppDatabase? database,
      }) async {
        final pair = await paired(gateway, database: database);
        await gateway.writeProfile(
          pairId: pair.pairId,
          profile: const PairProfile(uid: 'uid-a', displayName: 'Alex'),
        );
        await pair.me.load();
        await gateway.endPair(pairId: pair.pairId, endedBy: userA.uid);
        await pair.me.load();
        return pair;
      }

      test(
        'a new pair never inherits the name kept for one that ended',
        () async {
          final gateway = FakePairingGateway();
          addTearDown(gateway.dispose);
          final pair = await endedByAlex(gateway);
          await pair.me.dismissEndedNotice();
          final me = pair.me;
          final cara = await _boot(
            gateway: gateway,
            auth: FakeAuthService(
              user: const AppUser(uid: 'uid-c', displayName: 'Cara'),
            ),
          );
          final code = (await cara.service.generateInvite()).pendingCode!;

          final next = await me.redeem(code);

          expect((await me.endingOf(next.pairId)).name, isNot('Alex'));
          expect((await me.endingOf(pair.pairId)).byPartner, isFalse);
          await gateway.endPair(pairId: next.pairId!, endedBy: 'uid-c');
          await me.load();
          expect(me.status.endedPartnerName, isNot('Alex'));
        },
      );

      test('an invite of mine forgets the kept ending and its name', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final pair = await endedByAlex(gateway);
        await pair.me.dismissEndedNotice();

        await pair.me.generateInvite();

        expect(await pair.me.endingOf(pair.pairId), (
          byPartner: false,
          name: null,
        ));
      });

      test('the answer does not wait on clearing the record: a write that '
          'fails still tells the partner\'s ending', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final failing = _FailingWrites();
        final db = await openTestDatabase(interceptor: failing);
        final pair = await endedByAlex(gateway, database: db);
        await pair.me.dismissEndedNotice();
        failing.armed = true;

        expect(await pair.me.endingOf(pair.pairId), (
          byPartner: true,
          name: 'Alex',
        ));
      });

      test('the partner ended it: recorded or not yet heard, it is theirs, '
          'with their name', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final pair = await paired(gateway);
        final name = pair.me.status.partner?.displayName;
        await gateway.endPair(pairId: pair.pairId, endedBy: userA.uid);

        expect(await pair.me.endingOf(pair.pairId), (
          byPartner: true,
          name: name,
        ));
        await pair.me.load();
        expect(await pair.me.endingOf(pair.pairId), (
          byPartner: true,
          name: name,
        ));
      });

      test('the ended notice dismissed before the read: the ending and the '
          'name are kept until the leave is told, once', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final pair = await paired(gateway);
        await gateway.writeProfile(
          pairId: pair.pairId,
          profile: const PairProfile(uid: 'uid-a', displayName: 'Alex'),
        );
        await pair.me.load();
        const name = 'Alex';
        expect(pair.me.status.partner?.displayName, name);
        await gateway.endPair(pairId: pair.pairId, endedBy: userA.uid);
        await pair.me.load();

        await pair.me.dismissEndedNotice();

        expect(pair.me.status.endedNoticePending, isFalse);
        expect(pair.me.status.endedPartnerName, isNull);
        expect(await pair.me.endingOf(pair.pairId), (
          byPartner: true,
          name: name,
        ));
        expect(await pair.me.endingOf(pair.pairId), (
          byPartner: false,
          name: null,
        ));
      });

      test('my Unpair is mine', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final pair = await paired(gateway);

        await pair.me.unpair();

        expect((await pair.me.endingOf(pair.pairId)).byPartner, isFalse);
      });

      test(
        'ended from another device of mine, not yet heard, is mine',
        () async {
          final gateway = FakePairingGateway();
          addTearDown(gateway.dispose);
          final pair = await paired(gateway);
          await gateway.endPair(pairId: pair.pairId, endedBy: userB.uid);

          expect((await pair.me.endingOf(pair.pairId)).byPartner, isFalse);
        },
      );

      group('asked with no service built — the check that runs with the app '
          'closed (shared freshness §6)', () {
        /// The same question in an isolate that has built no service: the
        /// one of the scenario is dropped, as a new isolate never had it.
        Future<PairEnding> readIn(_WatchCounting gateway, String pairId) async {
          PairingService.reset();
          gateway.watches = 0;
          return PairingService.endingRead(
            pairId,
            auth: FakeAuthService(user: userB),
            gateway: gateway,
            settings: await SettingsService.getInstance(),
          );
        }

        test('the partner ended it and nothing here has heard: one read of '
            'the pair says so, with their name — and no service is built, '
            'no pair followed', () async {
          final gateway = _WatchCounting();
          addTearDown(gateway.dispose);
          final pair = await paired(gateway);
          final name = pair.me.status.partner?.displayName;
          await gateway.endPair(pairId: pair.pairId, endedBy: userA.uid);

          final ending = await readIn(gateway, pair.pairId);

          expect(ending, (byPartner: true, name: name));
          expect(PairingService.pairedInMemory, isNull);
          expect(gateway.watches, 0);
        });

        test(
          'recorded as ended, the notice dismissed: told once with the '
          'name, and the record goes with the answer — in the stored '
          'pairing, where the app\'s own service then finds it gone',
          () async {
            final gateway = _WatchCounting();
            addTearDown(gateway.dispose);
            final pair = await endedByAlex(gateway);
            await pair.me.dismissEndedNotice();

            expect(await readIn(gateway, pair.pairId), (
              byPartner: true,
              name: 'Alex',
            ));
            expect(await readIn(gateway, pair.pairId), (
              byPartner: false,
              name: null,
            ));
            expect(PairingService.pairedInMemory, isNull);
            expect(gateway.watches, 0);

            final app = await PairingService.forTesting(
              auth: FakeAuthService(user: userB),
              gateway: gateway,
              settings: await SettingsService.getInstance(),
            );
            expect(await app.endingOf(pair.pairId), (
              byPartner: false,
              name: null,
            ));
          },
        );

        test('my Unpair is mine, and another pair\'s ending is not this '
            'one\'s', () async {
          final gateway = _WatchCounting();
          addTearDown(gateway.dispose);
          final pair = await paired(gateway);

          expect((await readIn(gateway, 'another-pair')).byPartner, isFalse);
          final me = await PairingService.forTesting(
            auth: FakeAuthService(user: userB),
            gateway: gateway,
            settings: await SettingsService.getInstance(),
          );
          await me.unpair();

          expect((await readIn(gateway, pair.pairId)).byPartner, isFalse);
        });

        test('the hooks of that check ask this way — over the registered '
            'identity and gateway and the open database\'s settings — and '
            'the engine built for the check is given those hooks', () async {
          final gateway = _WatchCounting();
          addTearDown(gateway.dispose);
          final pair = await paired(gateway);
          await gateway.endPair(pairId: pair.pairId, endedBy: userA.uid);
          PairingService.reset();
          gateway.watches = 0;
          GetIt.I
            ..registerSingleton<AuthService>(FakeAuthService(user: userB))
            ..registerSingleton<PairingGateway>(gateway);
          addTearDown(GetIt.I.reset);

          final ending = await AppSyncApplyHooks.pairEndingRead(pair.pairId);

          expect(ending.byPartner, isTrue);
          expect(PairingService.pairedInMemory, isNull);
          expect(gateway.watches, 0);

          // The two lines no suite can run — the engine of an isolate with
          // no app is built over the app's real singletons — read instead.
          final hooks = File(
            'lib/services/sync/app_sync_apply_hooks.dart',
          ).readAsStringSync();
          expect(
            hooks,
            matches(
              RegExp(
                r'AppSyncApplyHooks\.awayFromApp\(\{\s*'
                r'required void Function\(ShareNotice notice\) notify,\s*'
                r'\}\) : this\(notify: notify, pairEnding: pairEndingRead\);',
              ),
            ),
          );
          final engine = File(
            'lib/services/sync/sync_engine.dart',
          ).readAsStringSync();
          final away = RegExp(
            // To the brace alone on its line: `  }) async {` closes only
            // the parameters.
            r'static Future<SyncEngine> awayFromApp\(\{[\s\S]*?^  \}\r?$',
            multiLine: true,
          ).stringMatch(engine);
          expect(
            away,
            contains('hooks: AppSyncApplyHooks.awayFromApp(notify: notify),'),
          );
          expect(
            'AppSyncApplyHooks.awayFromApp('.allMatches(engine),
            hasLength(1),
          );
        });

        test('a pair that cannot be read answers "not the partner", as the '
            'service does', () async {
          final inner = FakePairingGateway();
          addTearDown(inner.dispose);
          final pair = await paired(inner);
          await inner.endPair(pairId: pair.pairId, endedBy: userA.uid);
          PairingService.reset();

          final ending = await PairingService.endingRead(
            pair.pairId,
            auth: FakeAuthService(user: userB),
            gateway: _FailingReads(inner),
            settings: await SettingsService.getInstance(),
          );

          expect(ending.byPartner, isFalse);
        });
      });
    });

    /// "Only alerts I add" / "Category alerts too" is chosen for a pair:
    /// carried to the next one, it armed my category alerts on a built-in
    /// that person shares without my having chosen it for them.
    group('what may ring belongs to the pair (D38)', () {
      tearDown(() => EventAlerts.configureShareAlerts(null));

      // A device's database is left open, as `_boot`'s own are: a pair
      // listener's write can still be on its way when a case ends, and into
      // a closed database it fails whichever case runs next.

      Future<String?> stored(AppDatabase db) =>
          db.userSettingsDao.getValue(SettingsKeys.shareAlerts);

      /// I — Ben — pair with Alex on [db], and choose [choice] for that pair.
      Future<({PairingService me, String pairId})> pairedChoosing(
        FakePairingGateway gateway,
        AppDatabase db,
        ShareAlerts choice, {
        Future<void> Function()? reconcileAlerts,
      }) async {
        final alex = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await alex.service.generateInvite()).pendingCode!;
        final me = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
          database: db,
          reconcileAlerts: reconcileAlerts,
        );
        final status = await me.service.redeem(code);
        await SettingsService.forTesting(db).setShareAlerts(choice);
        return (me: me.service, pairId: status.pairId!);
      }

      Future<String> inviteFromCara(FakePairingGateway gateway) async {
        final cara = await _boot(
          gateway: gateway,
          auth: FakeAuthService(
            user: const AppUser(uid: 'uid-c', displayName: 'Cara'),
          ),
        );
        return (await cara.service.generateInvite()).pendingCode!;
      }

      test('another pair starts at the shipped choice, published as a read '
          'of it would be (A16)', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);
        expect(await stored(db), 'category');

        await gateway.endPair(pairId: pair.pairId, endedBy: userA.uid);
        await pair.me.load();
        expect(await stored(db), 'category', reason: 'an ending resets none');
        await pair.me.dismissEndedNotice();
        final next = await pair.me.redeem(await inviteFromCara(gateway));

        expect(next.pairId, isNot(pair.pairId));
        expect(await stored(db), SettingsKeys.defaultShareAlerts);
        expect(EventAlerts.shareAlerts, ShareAlerts.own);
      });

      test('"Off" is reset like any other choice (N6): another pair starts '
          'from "Only alerts I add" whatever stood, and each chooses '
          'again', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.off);

        await pair.me.unpair();
        await pair.me.redeem(await inviteFromCara(gateway));

        expect(await stored(db), SettingsKeys.defaultShareAlerts);
      });

      test('the same pair adopted again — a reconcile, and a launch — keeps '
          'the choice', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);

        await pair.me.load();
        expect(await stored(db), 'category');

        final relaunched = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
          database: db,
        );
        await relaunched.service.load();

        expect(relaunched.service.status.pairId, pair.pairId);
        expect(await stored(db), 'category');
      });

      test('a first pair ever, the shipped choice standing, writes nothing '
          'for it', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final counter = StatementCounter();
        final db = await openTestDatabase(interceptor: counter);
        final alex = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userA),
        );
        final code = (await alex.service.generateInvite()).pendingCode!;
        final me = await _boot(
          gateway: gateway,
          auth: FakeAuthService(user: userB),
          database: db,
        );
        counter.reset();

        await me.service.redeem(code);

        expect(await stored(db), isNull, reason: 'never written');
        expect([
          for (final statement in counter.captured)
            if (!statement.isSelect &&
                statement.args.contains(SettingsKeys.shareAlerts))
              statement.sql,
        ], isEmpty);
      });

      test('both or neither (N7a): a reset that cannot be written fails the '
          'adoption — no pair is ever stored under the choice made for '
          'another — and the next reconcile makes both', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final failing = _FailingKey(SettingsKeys.shareAlerts);
        final db = await openTestDatabase(interceptor: failing);
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);
        await pair.me.unpair();
        final code = await inviteFromCara(gateway);
        failing.armed = true;

        await expectLater(pair.me.redeem(code), throwsA(anything));

        // Off the database itself: the settings service is whichever
        // device booted last.
        expect(
          await db.userSettingsDao.getValue(SettingsKeys.pairingPairId),
          isNull,
        );
        expect(pair.me.status.pairId, isNull);
        expect(await stored(db), 'category');

        failing.armed = false;
        final status = await pair.me.load();

        expect(status.pairId, isNotNull);
        expect(status.pairId, isNot(pair.pairId));
        expect(await stored(db), SettingsKeys.defaultShareAlerts);
      });

      test('a pass follows a reset that changed the choice (N7b), after the '
          'choice is published: what "Category alerts too" armed on rows '
          'still stored does not stay armed until something else passes — '
          'and no pass where nothing changed', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final passes = <ShareAlerts?>[];
        final pair = await pairedChoosing(
          gateway,
          db,
          ShareAlerts.category,
          reconcileAlerts: () async => passes.add(EventAlerts.shareAlerts),
        );
        expect(passes, isEmpty, reason: 'a first pair changes nothing');

        await pair.me.load();
        expect(passes, isEmpty, reason: 'the same pair adopted again');

        await pair.me.unpair();
        await pair.me.redeem(await inviteFromCara(gateway));

        expect(passes, [ShareAlerts.own]);
      });

      test('the same pair found again keeps its choice (N7c): lost locally '
          'while the server could not be reached, it is not another pair '
          'when it is adopted again under its own id', () async {
        final gateway = _TransientlyEmpty();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);

        gateway.empty = true;
        expect((await pair.me.load()).pairId, isNull);
        gateway.empty = false;
        final found = await pair.me.load();

        expect(found.pairId, pair.pairId);
        expect(await stored(db), 'category');
        expect(EventAlerts.shareAlerts, isNot(ShareAlerts.own));
      });

      test('a real re-pair with the same person is another pair: another '
          'id, the shipped choice', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);
        await pair.me.unpair();

        // Alex's half, straight through the gateway: booting her service
        // would take mine down.
        final again = gateway.seedPair([userA.uid, userB.uid]);
        final status = await pair.me.load();

        expect(status.pairId, again.pairId);
        expect(await stored(db), SettingsKeys.defaultShareAlerts);
      });

      test('the pair a reconcile swaps in — two were active, the stored one '
          'the later — is another pair', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final earlier = gateway.seedPair([userB.uid, 'uid-c']);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);
        expect(pair.pairId, isNot(earlier.pairId));

        final status = await pair.me.load();

        expect(status.pairId, earlier.pairId);
        expect(await stored(db), SettingsKeys.defaultShareAlerts);
      });

      test('the pair of another account signed in on this database is '
          'another pair', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        await pairedChoosing(gateway, db, ShareAlerts.category);
        final caras = gateway.seedPair(['uid-c', 'uid-d']);

        final cara = await _boot(
          gateway: gateway,
          auth: FakeAuthService(
            user: const AppUser(uid: 'uid-c', displayName: 'Cara'),
          ),
          database: db,
        );
        final status = await cara.service.load();

        expect(status.pairId, caras.pairId);
        expect(await stored(db), SettingsKeys.defaultShareAlerts);
      });

      test('the pair my own invite brings, adopted by its listener with no '
          'reload, is another pair', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.category);
        await pair.me.unpair();
        final code = (await pair.me.generateInvite()).pendingCode!;

        final next = await gateway.createPair(
          self: PairProfile.fromUser(
            const AppUser(uid: 'uid-c', displayName: 'Cara'),
          ),
          partner: PairProfile(uid: userB.uid),
          inviteCode: code,
        );
        await pumpEventQueue();

        expect(pair.me.status.pairId, next.pairId);
        expect(await stored(db), SettingsKeys.defaultShareAlerts);
      });

      test('the last pair this database was in is a pairing row like the '
          'others (N7c): under their prefix, which is what a restore and a '
          'handed-out copy strip by', () async {
        final gateway = FakePairingGateway();
        addTearDown(gateway.dispose);
        final db = await openTestDatabase();
        final pair = await pairedChoosing(gateway, db, ShareAlerts.own);

        expect(
          SettingsKeys.pairingLastPair,
          startsWith(SettingsKeys.pairingPrefix),
        );
        expect(
          await db.userSettingsDao.getValue(SettingsKeys.pairingLastPair),
          pair.pairId,
        );
      });
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
