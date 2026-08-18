import 'package:equatable/equatable.dart';

import 'app_user.dart';

/// A member's public identity inside a pair. `members` carries uids only, so
/// this is what lets the UI name the partner rather than showing a raw uid.
class PairProfile extends Equatable {
  final String uid;
  final String? displayName;
  final String? photoUrl;

  const PairProfile({required this.uid, this.displayName, this.photoUrl});

  factory PairProfile.fromUser(AppUser user) => PairProfile(
    uid: user.uid,
    displayName: user.displayName ?? user.email,
    photoUrl: user.photoUrl,
  );

  /// The partner as an [AppUser] so the Sharing row can reuse `UserAvatar`.
  AppUser toUser() =>
      AppUser(uid: uid, displayName: displayName, photoUrl: photoUrl);

  @override
  List<Object?> get props => [uid, displayName, photoUrl];
}

/// A link between two accounts. Never deleted and never reused: unpairing
/// flips [isActive] to false and leaves [members] intact, so the partner keeps
/// read access and can still find out who ended it.
class PairRecord extends Equatable {
  final String pairId;
  final List<String> members;
  final bool isActive;

  /// Server-assigned. The tie-break when a uid ends up in two active pairs —
  /// earliest wins, which both devices can compute independently.
  final DateTime createdAt;

  final String? endedBy;
  final DateTime? endedAt;
  final Map<String, PairProfile> profiles;

  const PairRecord({
    required this.pairId,
    required this.members,
    required this.isActive,
    required this.createdAt,
    this.endedBy,
    this.endedAt,
    this.profiles = const {},
  });

  String? partnerUidOf(String uid) {
    for (final member in members) {
      if (member != uid) return member;
    }
    return null;
  }

  PairProfile? partnerProfileOf(String uid) {
    final partner = partnerUidOf(uid);
    return partner == null ? null : profiles[partner];
  }

  bool contains(String uid) => members.contains(uid);

  @override
  List<Object?> get props => [
    pairId,
    members,
    isActive,
    createdAt,
    endedBy,
    endedAt,
    profiles,
  ];
}

/// A pending invite. [pairId] is null until the other side redeems it — that
/// write-back is how the creator, who never sees the redeemer's device, learns
/// which pair it now belongs to.
class InviteRecord extends Equatable {
  final String code;
  final String creatorUid;
  final DateTime expiresAt;
  final String? pairId;
  final String? redeemedBy;

  const InviteRecord({
    required this.code,
    required this.creatorUid,
    required this.expiresAt,
    this.pairId,
    this.redeemedBy,
  });

  bool get isRedeemed => pairId != null && pairId!.isNotEmpty;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  @override
  List<Object?> get props => [code, creatorUid, expiresAt, pairId, redeemedBy];
}
