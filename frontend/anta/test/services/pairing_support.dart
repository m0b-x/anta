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

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// An in-memory stand-in for Firestore that keeps the rules the real gateway
/// relies on: an invite is create-only and claimable once, a pair is never
/// deleted, and `createdAt` is assigned here rather than by the caller.
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

  /// Runs at the start of [claimInvite], so a test can let someone else claim
  /// the code in the window between the redeemer's read and its own claim.
  void Function()? beforeClaim;

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
  Stream<InviteRecord?> watchInvite(String code) =>
      _inviteControllers
          .putIfAbsent(code, () => StreamController<InviteRecord?>.broadcast())
          .stream;

  @override
  Future<void> claimInvite({
    required String code,
    required String pairId,
    required String redeemerUid,
  }) async {
    _maybeFail();
    beforeClaim?.call();
    final invite = invites[code];
    if (invite == null || invite.isRedeemed) {
      throw const PairingException(PairingError.codeInvalid);
    }
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
    // Mirrors the security rule: a pair is only legitimate when the other
    // member handed out a live, unclaimed invite. Without this the fake would
    // happily accept the forced-pair attack the rule exists to stop.
    final invite = invites[inviteCode];
    if (invite == null ||
        invite.isRedeemed ||
        invite.isExpiredAt(DateTime.now().toUtc()) ||
        invite.creatorUid == self.uid ||
        invite.creatorUid != partner.uid) {
      throw const PairingException(PairingError.permissionDenied);
    }
    createPairCalls++;
    return seedPair([self.uid, partner.uid], {self.uid: self, partner.uid: partner});
  }

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
  Stream<PairRecord?> watchPair(String pairId) =>
      _pairControllers
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
