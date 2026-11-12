import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/account_closer.dart';
import 'package:anta/utils/auth_error.dart';
import 'package:anta/utils/pairing_error.dart';

import '../../database/support/db_test_support.dart';
import '../pairing_support.dart';

const _userC = AppUser(uid: 'uid-c', displayName: 'Cat');

Matcher _fails(AccountCloseFailure failure) =>
    isA<AccountCloseException>().having((e) => e.failure, 'failure', failure);

/// The identity, telling a test what the cloud still held as the account
/// itself was deleted.
class _WatchedAuth extends FakeAuthService {
  _WatchedAuth({super.user});

  void Function()? onDeleteAccount;

  @override
  Future<void> deleteAccount() {
    onDeleteAccount?.call();
    return super.deleteAccount();
  }
}

/// A gateway whose pair deletes never land.
class _StuckPairs extends FakePairingGateway {
  int deleteCalls = 0;

  @override
  Future<void> deletePair(String pairId) async => deleteCalls++;
}

/// A gateway whose invite deletes never land.
class _StuckInvites extends FakePairingGateway {
  int deleteCalls = 0;

  @override
  Future<void> deleteInvite(String code) async => deleteCalls++;
}

/// A gateway with a hook as the walk reaches the invites — after the pairs,
/// before the account — and one that refuses to end a pair as the rules do
/// for a pair that is no longer active.
class _ScriptedGateway extends FakePairingGateway {
  void Function()? onInvitesListed;
  void Function(String pairId)? beforeEnd;
  bool refuseEnd = false;

  @override
  Future<List<String>> findOwnInvites(String uid) async {
    onInvitesListed?.call();
    return super.findOwnInvites(uid);
  }

  @override
  Future<void> endPair({
    required String pairId,
    required String endedBy,
  }) async {
    beforeEnd?.call(pairId);
    if (refuseEnd || !(pairs[pairId]?.isActive ?? false)) {
      throw const PairingException(PairingError.permissionDenied);
    }
    return super.endPair(pairId: pairId, endedBy: endedBy);
  }
}

/// The end of an account's deletion (cloud-multi-user-roadmap §6.1): pairs
/// ended and removed, invites removed, then the account — in that order, as
/// whoever is signed in, and only while it is still wanted.
void main() {
  late _WatchedAuth auth;
  late FakePairingGateway gateway;
  late PairedAccountCloser closer;

  setUp(() {
    auth = _WatchedAuth(user: userA);
    gateway = FakePairingGateway();
    closer = PairedAccountCloser(auth: auth, pairing: gateway);
  });

  tearDown(() async {
    await auth.dispose();
    await gateway.dispose();
  });

  Future<void> close(AccountCloser closer, {bool Function()? stillWanted}) =>
      closer.close(userA.uid, stillWanted: stillWanted ?? () => true);

  Future<void> seedInvite(
    FakePairingGateway into,
    String code, {
    required String creator,
    String? redeemedBy,
  }) async {
    await into.createInvite(
      code: code,
      creatorUid: creator,
      lifetime: const Duration(minutes: 10),
    );
    if (redeemedBy != null) {
      into.seedClaim(code, pairId: 'pair-of-$code', redeemerUid: redeemedBy);
    }
  }

  test('ends the active pair, removes every pair of the account and every '
      'invite it created or redeemed, and only then the account', () async {
    final active = gateway.seedPair([userA.uid, userB.uid]);
    final over = gateway.seedPair([userA.uid, _userC.uid]);
    await gateway.endPair(pairId: over.pairId, endedBy: _userC.uid);
    gateway.endedPairs.clear();
    final theirs = gateway.seedPair([userB.uid, _userC.uid]);
    await seedInvite(gateway, 'MINE2345', creator: userA.uid);
    await seedInvite(
      gateway,
      'SPENT234',
      creator: userB.uid,
      redeemedBy: userA.uid,
    );
    await seedInvite(gateway, 'THEIRS23', creator: userB.uid);

    int? pairsAtDelete;
    int? invitesAtDelete;
    auth.onDeleteAccount = () {
      pairsAtDelete = gateway.pairs.values
          .where((pair) => pair.contains(userA.uid))
          .length;
      invitesAtDelete = gateway.invites.values
          .where((i) => i.creatorUid == userA.uid || i.redeemedBy == userA.uid)
          .length;
    };

    await close(closer);

    expect(gateway.endedPairs, [active.pairId]);
    expect(gateway.deletedPairs, unorderedEquals([active.pairId, over.pairId]));
    expect(gateway.pairs.keys, [theirs.pairId]);
    expect(gateway.invites.keys, ['THEIRS23']);
    expect(pairsAtDelete, 0);
    expect(invitesAtDelete, 0);
    expect(auth.deletedAccounts, [userA.uid]);
    expect(auth.currentUser, isNull);
  });

  test("a partner's listening device hears the tombstone before the pair "
      'is gone', () async {
    final pair = gateway.seedPair([userA.uid, userB.uid]);
    final heard = <PairRecord?>[];
    final subscription = gateway.watchPair(pair.pairId).listen(heard.add);
    addTearDown(subscription.cancel);

    await close(closer);
    await pumpEventQueue();

    expect(heard, hasLength(2));
    expect(heard.first!.isActive, isFalse);
    expect(heard.first!.endedBy, userA.uid);
    expect(heard.last, isNull);
  });

  test('an account with no pair and no invite is simply deleted', () async {
    await close(closer);

    expect(auth.deletedAccounts, [userA.uid]);
    expect(gateway.deletedPairs, isEmpty);
  });

  for (final (label, signedIn) in [
    ('another account is signed in', userB),
    ('nobody is signed in', null),
  ]) {
    test('refused, with nothing touched, when $label', () async {
      auth.emitAuth(signedIn);
      final pair = gateway.seedPair([userA.uid, userB.uid]);

      await expectLater(
        close(closer),
        throwsA(_fails(AccountCloseFailure.permissionDenied)),
      );

      expect(gateway.pairs[pair.pairId]!.isActive, isTrue);
      expect(auth.deletedAccounts, isEmpty);
    });
  }

  group("asked again right before the account's own delete", () {
    test('no longer wanted: the walks are done, the account is kept', () async {
      gateway.seedPair([userA.uid, userB.uid]);
      await seedInvite(gateway, 'MINE2345', creator: userA.uid);
      var asked = 0;

      await expectLater(
        close(
          closer,
          stillWanted: () {
            asked++;
            return false;
          },
        ),
        throwsA(_fails(AccountCloseFailure.withdrawn)),
      );

      expect(asked, 1);
      expect(gateway.pairs, isEmpty);
      expect(gateway.invites, isEmpty);
      expect(auth.deletedAccounts, isEmpty);
      expect(auth.currentUser, userA);
    });

    test('it is asked after the walks, not before them', () async {
      final scripted = _ScriptedGateway()..seedPair([userA.uid, userB.uid]);
      addTearDown(scripted.dispose);
      var wanted = true;
      scripted.onInvitesListed = () => wanted = false;

      await expectLater(
        close(
          PairedAccountCloser(auth: auth, pairing: scripted),
          stillWanted: () => wanted,
        ),
        throwsA(_fails(AccountCloseFailure.withdrawn)),
      );

      expect(auth.deletedAccounts, isEmpty);
    });

    test('a session that ended during the walks deletes nothing: the '
        'account is whoever is signed in, and that is nobody now', () async {
      final scripted = _ScriptedGateway()..seedPair([userA.uid, userB.uid]);
      addTearDown(scripted.dispose);
      scripted.onInvitesListed = () => auth.emitAuth(null);

      await expectLater(
        close(PairedAccountCloser(auth: auth, pairing: scripted)),
        throwsA(_fails(AccountCloseFailure.permissionDenied)),
      );

      expect(auth.deletedAccounts, isEmpty);
    });
  });

  group('a pair the partner got to first', () {
    test('ended since the page listed it: the refusal is read back, and the '
        'pair removed all the same', () async {
      final scripted = _ScriptedGateway();
      addTearDown(scripted.dispose);
      final pair = scripted.seedPair([userA.uid, userB.uid]);
      // The partner's own unpair lands between the listing and our end.
      scripted.beforeEnd = (pairId) {
        scripted.beforeEnd = null;
        scripted.pairs[pairId] = PairRecord(
          pairId: pairId,
          members: pair.members,
          isActive: false,
          createdAt: pair.createdAt,
          endedBy: userB.uid,
        );
      };

      await close(PairedAccountCloser(auth: auth, pairing: scripted));

      expect(scripted.pairs, isEmpty);
      expect(auth.deletedAccounts, [userA.uid]);
    });

    test('removed since the page listed it: nothing to end, nothing to '
        'remove, and the account goes', () async {
      final scripted = _ScriptedGateway();
      addTearDown(scripted.dispose);
      scripted.seedPair([userA.uid, userB.uid]);
      scripted.beforeEnd = (pairId) => scripted.pairs.remove(pairId);

      await close(PairedAccountCloser(auth: auth, pairing: scripted));

      expect(auth.deletedAccounts, [userA.uid]);
    });

    test('a refusal with the pair still active is a refusal', () async {
      final scripted = _ScriptedGateway()
        ..seedPair([userA.uid, userB.uid])
        ..refuseEnd = true;
      addTearDown(scripted.dispose);

      await expectLater(
        close(PairedAccountCloser(auth: auth, pairing: scripted)),
        throwsA(_fails(AccountCloseFailure.permissionDenied)),
      );

      expect(auth.deletedAccounts, isEmpty);
    });
  });

  for (final (error, failure) in [
    (PairingError.offline, AccountCloseFailure.offline),
    (PairingError.permissionDenied, AccountCloseFailure.permissionDenied),
    (PairingError.unavailable, AccountCloseFailure.unknown),
    (PairingError.unknown, AccountCloseFailure.unknown),
  ]) {
    test('a pairing call failing as ${error.name} stops before the account '
        'and is ${failure.name}', () async {
      gateway.failNext = error;

      await expectLater(close(closer), throwsA(_fails(failure)));

      expect(auth.deletedAccounts, isEmpty);
      expect(auth.currentUser, userA);
    });
  }

  for (final (Object error, failure) in [
    (
      const RecentSignInRequiredException(),
      AccountCloseFailure.recentSignInRequired,
    ),
    (const AuthException(AuthError.offline), AccountCloseFailure.offline),
    (const AuthException(AuthError.unknown), AccountCloseFailure.unknown),
  ]) {
    test("the account's own delete failing with $error is ${failure.name}, "
        'with its pairs and invites already gone', () async {
      gateway.seedPair([userA.uid, userB.uid]);
      await seedInvite(gateway, 'MINE2345', creator: userA.uid);
      auth.deleteAccountError = error;

      await expectLater(close(closer), throwsA(_fails(failure)));

      expect(gateway.pairs, isEmpty);
      expect(gateway.invites, isEmpty);
      expect(auth.currentUser, userA);

      // Asked again after a fresh sign-in, it goes on from there.
      auth.deleteAccountError = null;
      await close(closer);
      expect(auth.deletedAccounts, [userA.uid]);
    });
  }

  test('pair deletes that never land end as a failure, not a loop', () async {
    final stuck = _StuckPairs()..seedPair([userA.uid, userB.uid]);
    addTearDown(stuck.dispose);

    await expectLater(
      close(PairedAccountCloser(auth: auth, pairing: stuck)),
      throwsA(_fails(AccountCloseFailure.unknown)),
    );

    expect(stuck.deleteCalls, PairedAccountCloser.maxPages);
    expect(auth.deletedAccounts, isEmpty);
  });

  test('invite deletes that never land end as a failure, not a loop', () async {
    final stuck = _StuckInvites();
    addTearDown(stuck.dispose);
    await seedInvite(stuck, 'MINE2345', creator: userA.uid);

    await expectLater(
      close(PairedAccountCloser(auth: auth, pairing: stuck)),
      throwsA(_fails(AccountCloseFailure.unknown)),
    );

    expect(stuck.deleteCalls, PairedAccountCloser.maxPages);
    expect(auth.deletedAccounts, isEmpty);
  });

  group("the open database's own pairing", () {
    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      PairingService.reset();
    });

    tearDown(() {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      PairingService.reset();
    });

    test('is forgotten before the pairs are touched, so the device that '
        'deletes its account never tells itself the partner ended '
        'sharing', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      // The partner's side made the invite; this device redeemed it.
      await seedInvite(gateway, 'K7M2P4XQ', creator: userB.uid);
      final pairing = await PairingService.forTesting(
        auth: auth,
        gateway: gateway,
        settings: SettingsService.forTesting(db),
      );
      final paired = await pairing.redeem('K7M2P4XQ');
      expect(paired.isPaired, isTrue);
      await pairing.load();
      final statuses = <PairingStatus>[];
      final heard = pairing.changes.listen(statuses.add);
      addTearDown(heard.cancel);

      List<String>? pairsWhenForgotten;
      final over = PairedAccountCloser(
        auth: auth,
        pairing: gateway,
        forgetLocalPairing: () async {
          pairsWhenForgotten = gateway.pairs.keys.toList();
          await pairing.forget();
        },
      );
      await close(over);
      await pumpEventQueue();

      expect(pairsWhenForgotten, [paired.pairId]);
      expect(gateway.pairs, isEmpty);
      expect(pairing.status.isPaired, isFalse);
      expect(pairing.status.endedNoticePending, isFalse);
      expect(statuses.where((status) => status.endedNoticePending), isEmpty);
      expect(gateway.hasPairListener(paired.pairId!), isFalse);
    });
  });
}
