import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  Future<void> deleteInvite(String code);

  /// The id of a pair made from the invite [inviteCode]: the code, then
  /// [nonce] — random, minted by the device that creates the pair. The
  /// rules hold a new pair to the first half (`namedAfterInvite`).
  ///
  /// What an account shares names the pair by this id
  /// (`docs/cloud-sharing-foundations.md` §4), so an id must never come
  /// round again for the same two people: the code is minted at random by
  /// the one who invites, the nonce by the one who redeems, and neither can
  /// steer both back to the id of a pair that ended while the other's
  /// documents still carry it.
  static String pairIdFor(String inviteCode, String nonce) =>
      '${inviteCode}_$nonce';

  /// Redeems [inviteCode] for [self]: creates the pair of [self] and
  /// [partner] and stamps it onto the invite, as one write — both land or
  /// neither does.
  ///
  /// [inviteCode] is the pair's proof of consent, not bookkeeping: security
  /// rules read the invite to confirm the other member really handed one out
  /// — and the pair's id starts with it ([pairIdFor]). They also hold the
  /// pair and the claim to each other, so a code is spent by the very write
  /// that creates its pair and the id can never be created a second time:
  /// not by ending and deleting the pair and making it again while the
  /// invite still lives, with the other member's documents still naming it.
  ///
  /// Throws [PairingError.codeInvalid] when the invite is gone or someone
  /// else claimed it first.
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  });

  /// Every active pair containing [uid] — the server-truth query
  /// reconciliation is built on. More than one means a race to resolve.
  /// Bounded: an unbounded query here is a free-tier read-quota hazard.
  ///
  /// Throws rather than leave out a pair it cannot read: "no pair" ends
  /// everything a pair carries on this device — what the partner shares is
  /// removed, what this account shares is made private — and must never be
  /// the answer for "one I could not make sense of".
  Future<List<PairRecord>> findActivePairs(String uid);

  Future<PairRecord?> readPair(String pairId);

  Stream<PairRecord?> watchPair(String pairId);

  Future<void> endPair({required String pairId, required String endedBy});

  Future<void> writeProfile({
    required String pairId,
    required PairProfile profile,
  });

  /// A page of the pairs [uid] is a member of, ended ones included — what
  /// an account's deletion walks, deleting as it goes and asking again
  /// until a page reads empty (cloud-multi-user-roadmap §6.1 g).
  Future<List<PairRecord>> findPairs(String uid);

  /// Removes an ended pair's document for good; the rules refuse an active
  /// one, which is ended first so the partner's device hears a tombstone.
  /// Completes normally when the document is already gone — the rules let
  /// a delete of a missing pair through, as they do for an invite, so two
  /// walks removing the same documents never fail each other.
  Future<void> deletePair(String pairId);

  /// A page of the codes of the invites [uid] created or redeemed, spent
  /// and expired ones included — walked like [findPairs], each deleted with
  /// [deleteInvite]. The rules answer for one's own only, so no code can be
  /// enumerated this way.
  Future<List<String>> findOwnInvites(String uid);
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

  @override
  Future<List<PairRecord>> findPairs(String uid) async => _unavailable();

  @override
  Future<void> deletePair(String pairId) async => _unavailable();

  @override
  Future<List<String>> findOwnInvites(String uid) async => _unavailable();
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

  /// How many documents one page of an account deletion's walk reads
  /// ([findPairs], [findOwnInvites]): the walk asks again until a page reads
  /// empty, so the size bounds a call, not the walk.
  static const int _sweepPage = 20;

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
  Future<void> deleteInvite(String code) =>
      _guard(() => _invites.doc(code).delete());

  @override
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  }) {
    return _guard(() async {
      final ref = _pairs.doc(
        PairingGateway.pairIdFor(inviteCode, _pairs.doc().id),
      );
      final invite = _invites.doc(inviteCode);
      // A transaction for its read, not for a retry: the invite is looked at
      // first so a code someone else just claimed answers "not valid", where
      // the rules' refusal of the write would read as "not allowed". Its two
      // writes commit together, which is what the rules ask for — each one's
      // rule reads the other document as it stands after the commit.
      await _db.runTransaction((tx) async {
        final claimed = _inviteFrom(inviteCode, (await tx.get(invite)).data());
        if (claimed == null || claimed.isRedeemed) {
          throw const PairingException(PairingError.codeInvalid);
        }
        tx.set(ref, {
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
        tx.update(invite, {'pairId': ref.id, 'redeemedBy': self.uid});
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
    return activePairsFrom({for (final doc in result.docs) doc.id: doc.data()});
  });

  /// The pairs of an active-pairs answer, by document id. One that does not
  /// read as a pair fails the whole answer ([findActivePairs]): the server
  /// said the account is in it, and dropping it would report "not paired".
  @visibleForTesting
  static List<PairRecord> activePairsFrom(
    Map<String, Map<String, dynamic>> documents,
  ) => [
    for (final MapEntry(key: id, value: data) in documents.entries)
      _pairFrom(id, data) ??
          (throw const PairingException(PairingError.unknown)),
  ];

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

  @override
  Future<List<PairRecord>> findPairs(String uid) => _guard(() async {
    final result = await _pairs
        .where('members', arrayContains: uid)
        .limit(_sweepPage)
        .get(const GetOptions(source: Source.server));
    // Every document the query answers, a malformed one included: the walk
    // has to remove it too, or it would report an account's pairs gone with
    // the uid still in one.
    return result.docs
        .map((doc) => _pairFrom(doc.id, doc.data(), lenient: true))
        .whereType<PairRecord>()
        .toList();
  });

  @override
  Future<void> deletePair(String pairId) =>
      _guard(() => _pairs.doc(pairId).delete());

  @override
  Future<List<String>> findOwnInvites(String uid) => _guard(() async {
    const server = GetOptions(source: Source.server);
    // Two queries: the rules answer a listing only when it is provably the
    // caller's own, and no single filter says "created or redeemed by".
    final created = await _invites
        .where('creatorUid', isEqualTo: uid)
        .limit(_sweepPage)
        .get(server);
    final redeemed = await _invites
        .where('redeemedBy', isEqualTo: uid)
        .limit(_sweepPage)
        .get(server);
    return {
      for (final doc in created.docs) doc.id,
      for (final doc in redeemed.docs) doc.id,
    }.toList();
  });

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

  /// [lenient] reads a document without a `createdAt` too, at the epoch —
  /// only for [findPairs], whose caller removes what it is given and never
  /// compares the dates.
  static PairRecord? _pairFrom(
    String pairId,
    Map<String, dynamic>? data, {
    bool lenient = false,
  }) {
    if (data == null) return null;
    final members = data['members'];
    final createdAt =
        _dateFrom(data['createdAt']) ??
        (lenient ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true) : null);
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

  static Map<String, PairProfile> _profilesFrom(Object? raw) {
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

  static DateTime? _dateFrom(Object? raw) {
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
