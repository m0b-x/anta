import 'package:equatable/equatable.dart';

/// The space this database is bound to and the account that bound it, read
/// and written as one value so a half-written binding — a space without the
/// account it belongs to — is not representable.
class SyncBinding extends Equatable {
  final String spaceId;

  /// The uid that owns the space; with [spaceId] it addresses the space,
  /// never a pairId (D1).
  final String ownerUid;

  /// The account signed in when the database was bound; another account
  /// signing in pauses sync (D3 ii).
  final String accountUid;
  final DateTime? boundAt;

  const SyncBinding({
    required this.spaceId,
    required this.ownerUid,
    required this.accountUid,
    this.boundAt,
  });

  @override
  List<Object?> get props => [spaceId, ownerUid, accountUid, boundAt];
}
