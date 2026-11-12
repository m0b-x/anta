import 'dart:async';

import 'package:anta/models/app_user.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/utils/pairing_error.dart';

const userA = AppUser(uid: 'uid-a', displayName: 'Alex', email: 'a@b.c');
const userB = AppUser(uid: 'uid-b', displayName: 'Ana', email: 'p@b.c');

class FakeAuthService implements AuthService {
  FakeAuthService({this.available = true, AppUser? user}) : _user = user;

  final bool available;
  AppUser? _user;
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  @override
  bool get isAvailable => available;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _user;

  void emitAuth(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Future<AppUser?> signInWithGoogle() async => _user;

  /// Thrown by [signOut] when set, which then leaves the user signed in.
  Object? signOutError;

  @override
  Future<void> signOut() async {
    if (signOutError case final error?) throw error;
    _user = null;
  }

  /// What [reauthenticate] answers; false is a dismissed prompt.
  bool reauthenticates = true;

  /// Thrown by [reauthenticate] when set.
  Object? reauthenticateError;

  int reauthenticateCalls = 0;

  @override
  Future<bool> reauthenticate() async {
    reauthenticateCalls++;
    if (reauthenticateError case final error?) throw error;
    return reauthenticates;
  }

  /// Thrown by [deleteAccount] when set, which then deletes nothing.
  Object? deleteAccountError;

  /// The accounts [deleteAccount] removed, in order.
  final List<String> deletedAccounts = [];

  /// Ends the session as the real one does: the stream hears null.
  @override
  Future<void> deleteAccount() async {
    if (deleteAccountError case final error?) throw error;
    final user = _user;
    if (user == null) throw StateError('nobody is signed in');
    deletedAccounts.add(user.uid);
    emitAuth(null);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// An in-memory stand-in for Firestore that keeps the rules the real gateway
/// relies on: an invite is create-only and claimable once, a pair is deleted
/// only once ended, and `createdAt` is assigned here rather than by the
/// caller.
class FakePairingGateway implements PairingGateway {
  FakePairingGateway({this.available = true});

  final bool available;

  final Map<String, InviteRecord> invites = {};
  final Map<String, PairRecord> pairs = {};

  final Map<String, StreamController<InviteRecord?>> _inviteControllers = {};
  final Map<String, StreamController<PairRecord?>> _pairControllers = {};

  /// Thrown by the next call to any method, then cleared — the "reconnect and
  /// it works" path matters as much as the failure.
  PairingError? failNext;

  /// Every call fails with this until it is cleared.
  PairingError? failAlways;

  /// Server-assigned timestamps, handed out in call order so a test can make
  /// one pair provably older than another.
  DateTime clock = DateTime.utc(2026, 1, 1);
  int _pairSeq = 0;

  int createPairCalls = 0;
  int readPairCalls = 0;
  final List<String> endedPairs = [];

  /// Runs at the start of [createPair], so a test can let someone else claim
  /// the code in the window between the redeemer's read and its own write.
  void Function()? beforeCreatePair;

  /// Forces the next N calls to [createInvite] to report a collision, so a
  /// test can exercise the retry loop without predicting a random code.
  int rejectNextInvites = 0;

  @override
  bool get isAvailable => available;

  void _maybeFail() {
    final always = failAlways;
    if (always != null) throw PairingException(always);
    final next = failNext;
    if (next != null) {
      failNext = null;
      throw PairingException(next);
    }
  }

  DateTime _tick() => clock.add(Duration(seconds: _pairSeq++));

  @override
  Future<InviteRecord?> createInvite({
    required String code,
    required String creatorUid,
    required Duration lifetime,
  }) async {
    _maybeFail();
    if (rejectNextInvites > 0) {
      rejectNextInvites--;
      return null;
    }
    if (invites.containsKey(code)) return null;
    final invite = InviteRecord(
      code: code,
      creatorUid: creatorUid,
      expiresAt: DateTime.now().toUtc().add(lifetime),
    );
    invites[code] = invite;
    _emitInvite(code);
    return invite;
  }

  @override
  Future<InviteRecord?> readInvite(String code) async {
    _maybeFail();
    return invites[code];
  }

  @override
  Stream<InviteRecord?> watchInvite(String code) => _inviteControllers
      .putIfAbsent(code, () => StreamController<InviteRecord?>.broadcast())
      .stream;

  /// Stamps a claim onto the invite [code] outright — for a test that needs
  /// a spent invite without the redemption that spends one. The app's only
  /// claim is [createPair]'s.
  void seedClaim(
    String code, {
    required String pairId,
    required String redeemerUid,
  }) {
    final invite = invites[code]!;
    invites[code] = InviteRecord(
      code: invite.code,
      creatorUid: invite.creatorUid,
      expiresAt: invite.expiresAt,
      pairId: pairId,
      redeemedBy: redeemerUid,
    );
    _emitInvite(code);
  }

  @override
  Future<void> deleteInvite(String code) async {
    _maybeFail();
    invites.remove(code);
    _emitInvite(code);
  }

  @override
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  }) async {
    _maybeFail();
    beforeCreatePair?.call();
    // The gateway's own look at the invite, inside its transaction: a code
    // that is gone or was claimed first is not valid, rather than forbidden.
    final invite = invites[inviteCode];
    if (invite == null || invite.isRedeemed) {
      throw const PairingException(PairingError.codeInvalid);
    }
    // Mirrors the security rule: a pair is only legitimate when the other
    // member handed out a live invite. Without this the fake would happily
    // accept the forced-pair attack the rule exists to stop.
    if (invite.isExpiredAt(DateTime.now().toUtc()) ||
        invite.creatorUid == self.uid ||
        invite.creatorUid != partner.uid) {
      throw const PairingException(PairingError.permissionDenied);
    }
    createPairCalls++;
    final pair = seedPair(
      [self.uid, partner.uid],
      {self.uid: self, partner.uid: partner},
    );
    // One write with the pair, as the rules hold the two to each other.
    seedClaim(inviteCode, pairId: pair.pairId, redeemerUid: self.uid);
    final lost = loseCreatePairAnswer;
    if (lost != null) {
      loseCreatePairAnswer = null;
      throw PairingException(lost);
    }
    return pair;
  }

  /// Makes the next [createPair] fail with this after its write landed — the
  /// reply lost, or the read-back failing: the pair exists and the invite is
  /// spent, and the caller is told neither.
  PairingError? loseCreatePairAnswer;

  /// Plants a pair directly, bypassing the invite check — for tests that need
  /// a pre-existing pair rather than a full round-trip.
  PairRecord seedPair(
    List<String> members, [
    Map<String, PairProfile> profiles = const {},
  ]) {
    final pairId = 'pair-${pairs.length + 1}';
    final pair = PairRecord(
      pairId: pairId,
      members: members,
      isActive: true,
      createdAt: _tick(),
      profiles: profiles,
    );
    pairs[pairId] = pair;
    _emitPair(pairId);
    return pair;
  }

  @override
  Future<List<PairRecord>> findActivePairs(String uid) async {
    _maybeFail();
    return pairs.values
        .where((pair) => pair.isActive && pair.contains(uid))
        .toList();
  }

  @override
  Future<PairRecord?> readPair(String pairId) async {
    _maybeFail();
    readPairCalls++;
    return pairs[pairId];
  }

  @override
  Stream<PairRecord?> watchPair(String pairId) => _pairControllers
      .putIfAbsent(pairId, () => StreamController<PairRecord?>.broadcast())
      .stream;

  @override
  Future<void> endPair({
    required String pairId,
    required String endedBy,
  }) async {
    _maybeFail();
    final pair = pairs[pairId];
    if (pair == null) return;
    endedPairs.add(pairId);
    pairs[pairId] = PairRecord(
      pairId: pair.pairId,
      members: pair.members,
      isActive: false,
      createdAt: pair.createdAt,
      endedBy: endedBy,
      endedAt: _tick(),
      profiles: pair.profiles,
    );
    _emitPair(pairId);
  }

  @override
  Future<void> writeProfile({
    required String pairId,
    required PairProfile profile,
  }) async {
    _maybeFail();
    final pair = pairs[pairId];
    if (pair == null) return;
    pairs[pairId] = PairRecord(
      pairId: pair.pairId,
      members: pair.members,
      isActive: pair.isActive,
      createdAt: pair.createdAt,
      endedBy: pair.endedBy,
      endedAt: pair.endedAt,
      profiles: {...pair.profiles, profile.uid: profile},
    );
    _emitPair(pairId);
  }

  @override
  Future<List<PairRecord>> findPairs(String uid) async {
    _maybeFail();
    return pairs.values.where((pair) => pair.contains(uid)).toList();
  }

  /// The pairs [deletePair] removed, in order.
  final List<String> deletedPairs = [];

  /// Refuses an active pair, as the rules do.
  @override
  Future<void> deletePair(String pairId) async {
    _maybeFail();
    final pair = pairs[pairId];
    if (pair == null) return;
    if (pair.isActive) {
      throw const PairingException(PairingError.permissionDenied);
    }
    pairs.remove(pairId);
    deletedPairs.add(pairId);
    _emitPair(pairId);
  }

  @override
  Future<List<String>> findOwnInvites(String uid) async {
    _maybeFail();
    return [
      for (final invite in invites.values)
        if (invite.creatorUid == uid || invite.redeemedBy == uid) invite.code,
    ];
  }

  bool hasPairListener(String pairId) =>
      _pairControllers[pairId]?.hasListener ?? false;

  bool hasInviteListener(String code) =>
      _inviteControllers[code]?.hasListener ?? false;

  void _emitInvite(String code) {
    final controller = _inviteControllers[code];
    if (controller != null && controller.hasListener) {
      controller.add(invites[code]);
    }
  }

  void _emitPair(String pairId) {
    final controller = _pairControllers[pairId];
    if (controller != null && controller.hasListener) {
      controller.add(pairs[pairId]);
    }
  }

  Future<void> dispose() async {
    for (final controller in _inviteControllers.values) {
      await controller.close();
    }
    for (final controller in _pairControllers.values) {
      await controller.close();
    }
  }
}
