import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pair_record.dart';
import '../utils/pairing_error.dart';

/// The remote half of pairing, kept behind an interface so `cloud_firestore`
/// types never reach the service, bloc or UI layers — the same boundary
/// `AuthService` draws around `firebase_auth`. Phase 02's `SyncGateway`
/// follows this shape.
abstract class PairingGateway {
  /// False on the no-op binding, so an unsupported platform or a failed
  /// Firebase init reads as "unavailable" rather than a button that can only
  /// fail.
  bool get isAvailable;

  /// Writes `invites/{code}`. Returns null when the code is already taken so
  /// the caller can retry with a fresh one.
  Future<InviteRecord?> createInvite({
    required String code,
    required String creatorUid,
    required Duration lifetime,
  });

  Future<InviteRecord?> readInvite(String code);

  /// Emits the invite as the redeemer stamps it, which is how the creating
  /// device learns its `pairId`.
  Stream<InviteRecord?> watchInvite(String code);

  /// Stamps `pairId`/`redeemedBy` onto a live, unclaimed invite. Throws
  /// [PairingError.codeInvalid] when someone else claimed it first.
  Future<void> claimInvite({
    required String code,
    required String pairId,
    required String redeemerUid,
  });

  Future<void> deleteInvite(String code);

  /// [inviteCode] is the pair's proof of consent, not bookkeeping: security
  /// rules read the invite to confirm the other member really handed one out.
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  });

  /// Every active pair containing [uid] — the server-truth query
  /// reconciliation is built on. More than one means a race to resolve.
  /// Bounded: an unbounded query here is a free-tier read-quota hazard.
  Future<List<PairRecord>> findActivePairs(String uid);

  Future<PairRecord?> readPair(String pairId);

  Stream<PairRecord?> watchPair(String pairId);

  Future<void> endPair({required String pairId, required String endedBy});

  Future<void> writeProfile({
    required String pairId,
    required PairProfile profile,
  });
}

/// Bound wherever cloud sync is unavailable. Refuses every call rather than
/// silently doing nothing, so a stray call surfaces instead of half-working.
class NoOpPairingGateway implements PairingGateway {
  const NoOpPairingGateway();

  Never _unavailable() =>
      throw const PairingException(PairingError.unavailable);

  @override
  bool get isAvailable => false;

  @override
  Future<InviteRecord?> createInvite({
    required String code,
    required String creatorUid,
    required Duration lifetime,
  }) async => _unavailable();

  @override
  Future<InviteRecord?> readInvite(String code) async => _unavailable();

  @override
  Stream<InviteRecord?> watchInvite(String code) =>
      const Stream<InviteRecord?>.empty();

  @override
  Future<void> claimInvite({
    required String code,
    required String pairId,
    required String redeemerUid,
  }) async => _unavailable();

  @override
  Future<void> deleteInvite(String code) async => _unavailable();

  @override
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  }) async => _unavailable();

  // Refuses like every sibling rather than reporting an empty result: "cannot
  // tell" and "no pairs" must not look the same to reconciliation.
  @override
  Future<List<PairRecord>> findActivePairs(String uid) async => _unavailable();

  @override
  Future<PairRecord?> readPair(String pairId) async => _unavailable();

  @override
  Stream<PairRecord?> watchPair(String pairId) =>
      const Stream<PairRecord?>.empty();

  @override
  Future<void> endPair({
    required String pairId,
    required String endedBy,
  }) async => _unavailable();

  @override
  Future<void> writeProfile({
    required String pairId,
    required PairProfile profile,
  }) async => _unavailable();
}

class FirestorePairingGateway implements PairingGateway {
  /// Pairing is online-only on purpose. Firestore's offline queue would
  /// accept every write and resolve nothing, leaving a spinner that never
  /// ends and two devices that never meet — so reads go to the server and
  /// every call is bounded.
  static const Duration _timeout = Duration(seconds: 15);

  /// A correct account is in exactly one active pair; anything beyond a small
  /// handful is a race or an attack, and reading it all would burn the free
  /// tier's daily quota in a single page open.
  static const int _maxActivePairs = 10;

  final FirebaseFirestore? _injected;

  FirestorePairingGateway({FirebaseFirestore? firestore})
    : _injected = firestore;

  // Resolved lazily for the same reason `FirebaseAuthService` defers
  // `FirebaseAuth.instance`: this is constructed during DI registration.
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _pairs =>
      _db.collection('pairs');

  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('invites');

  @override
  bool get isAvailable => true;

  @override
  Future<InviteRecord?> createInvite({
    required String code,
    required String creatorUid,
    required Duration lifetime,
  }) {
    final expiresAt = DateTime.now().toUtc().add(lifetime);
    return _guard(() async {
      final ref = _invites.doc(code);
      final created = await _db.runTransaction((tx) async {
        final snapshot = await tx.get(ref);
        if (snapshot.exists) return false;
        tx.set(ref, {
          'creatorUid': creatorUid,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
        });
        return true;
      });
      if (!created) return null;
      return InviteRecord(
        code: code,
        creatorUid: creatorUid,
        expiresAt: expiresAt,
      );
    });
  }

  @override
  Future<InviteRecord?> readInvite(String code) => _guard(() async {
    final snapshot = await _invites
        .doc(code)
        .get(const GetOptions(source: Source.server));
    return _inviteFrom(code, snapshot.data());
  });

  @override
  Stream<InviteRecord?> watchInvite(String code) => _invites
      .doc(code)
      .snapshots()
      .map((snapshot) => _inviteFrom(code, snapshot.data()));

  @override
  Future<void> claimInvite({
    required String code,
    required String pairId,
    required String redeemerUid,
  }) {
    return _guard(() async {
      final ref = _invites.doc(code);
      await _db.runTransaction((tx) async {
        final snapshot = await tx.get(ref);
        final invite = _inviteFrom(code, snapshot.data());
        if (invite == null || invite.isRedeemed) {
          throw const PairingException(PairingError.codeInvalid);
        }
        tx.update(ref, {'pairId': pairId, 'redeemedBy': redeemerUid});
      });
    });
  }

  @override
  Future<void> deleteInvite(String code) =>
      _guard(() => _invites.doc(code).delete());

  @override
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  }) {
    return _guard(() async {
      final ref = _pairs.doc();
      await ref.set({
        'members': [self.uid, partner.uid],
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'inviteCode': inviteCode,
        'profiles': {
          self.uid: _profileData(self),
          partner.uid: _profileData(partner),
        },
        'permissions': {
          self.uid: {'allowPartnerEdit': false},
          partner.uid: {'allowPartnerEdit': false},
        },
      });
      // Read back rather than guess: `createdAt` is server-assigned and it is
      // the tie-break both devices sort on when a race produces two pairs.
      final created = await readPair(ref.id);
      if (created == null) {
        throw const PairingException(PairingError.unknown);
      }
      return created;
    });
  }

  @override
  Future<List<PairRecord>> findActivePairs(String uid) => _guard(() async {
    final result = await _pairs
        .where('members', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .limit(_maxActivePairs)
        .get(const GetOptions(source: Source.server));
    return result.docs
        .map((doc) => _pairFrom(doc.id, doc.data()))
        .whereType<PairRecord>()
        .toList();
  });

  @override
  Future<PairRecord?> readPair(String pairId) => _guard(() async {
    final snapshot = await _pairs
        .doc(pairId)
        .get(const GetOptions(source: Source.server));
    return _pairFrom(pairId, snapshot.data());
  });

  @override
  Stream<PairRecord?> watchPair(String pairId) => _pairs
      .doc(pairId)
      .snapshots()
      .map((snapshot) => _pairFrom(pairId, snapshot.data()));

  @override
  Future<void> endPair({required String pairId, required String endedBy}) =>
      _guard(
        () => _pairs.doc(pairId).update({
          'status': 'ended',
          'endedBy': endedBy,
          'endedAt': FieldValue.serverTimestamp(),
        }),
      );

  @override
  Future<void> writeProfile({
    required String pairId,
    required PairProfile profile,
  }) => _guard(
    () => _pairs.doc(pairId).update({
      'profiles.${profile.uid}': _profileData(profile),
    }),
  );

  Map<String, dynamic> _profileData(PairProfile profile) => {
    'displayName': profile.displayName,
    'photoUrl': profile.photoUrl,
  };

  InviteRecord? _inviteFrom(String code, Map<String, dynamic>? data) {
    if (data == null) return null;
    final creatorUid = data['creatorUid'];
    final expiresAt = _dateFrom(data['expiresAt']);
    if (creatorUid is! String || expiresAt == null) return null;
    final pairId = data['pairId'];
    final redeemedBy = data['redeemedBy'];
    return InviteRecord(
      code: code,
      creatorUid: creatorUid,
      expiresAt: expiresAt,
      pairId: pairId is String ? pairId : null,
      redeemedBy: redeemedBy is String ? redeemedBy : null,
    );
  }

  PairRecord? _pairFrom(String pairId, Map<String, dynamic>? data) {
    if (data == null) return null;
    final members = data['members'];
    final createdAt = _dateFrom(data['createdAt']);
    // A cached snapshot taken between the write and the server's reply has a
    // null `createdAt`. Skipping it is deliberate: an invented timestamp
    // would corrupt the earliest-wins tie-break.
    if (members is! List || createdAt == null) return null;
    final endedBy = data['endedBy'];
    return PairRecord(
      pairId: pairId,
      members: members.whereType<String>().toList(),
      isActive: data['status'] != 'ended',
      createdAt: createdAt,
      endedBy: endedBy is String ? endedBy : null,
      endedAt: _dateFrom(data['endedAt']),
      profiles: _profilesFrom(data['profiles']),
    );
  }

  Map<String, PairProfile> _profilesFrom(Object? raw) {
    if (raw is! Map) return const {};
    final profiles = <String, PairProfile>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final displayName = value['displayName'];
      final photoUrl = value['photoUrl'];
      profiles[key] = PairProfile(
        uid: key,
        displayName: displayName is String ? displayName : null,
        photoUrl: photoUrl is String ? photoUrl : null,
      );
    });
    return profiles;
  }

  DateTime? _dateFrom(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    return null;
  }

  /// Maps every remote failure onto a [PairingError]. Without this, an
  /// offline device shows a generic error or hangs on a queued write, and
  /// the caller would have to know Firestore's error codes.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(_timeout);
    } on PairingException {
      rethrow;
    } on FirebaseException catch (e) {
      throw PairingException(switch (e.code) {
        'unavailable' ||
        'deadline-exceeded' ||
        'aborted' => PairingError.offline,
        'permission-denied' => PairingError.permissionDenied,
        // A missing composite index. Nothing the user can do, but reporting it
        // as "unavailable" beats "something went wrong" on every page open.
        'failed-precondition' => PairingError.unavailable,
        _ => PairingError.unknown,
      });
    } on TimeoutException {
      throw const PairingException(PairingError.offline);
    } catch (_) {
      throw const PairingException(PairingError.unknown);
    }
  }
}
