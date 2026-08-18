import 'package:equatable/equatable.dart';

import '../../models/pair_record.dart';
import '../../utils/pairing_error.dart';

/// Pairing is orthogonal to auth — signed-in crossed with unpaired / inviting
/// / paired / ended — so it gets its own hierarchy rather than more `SyncState`
/// variants.
///
/// Recoverable failures ride as [PairingFailure] on the state they failed from
/// rather than in a separate failure state: a cancel that fails must not drop
/// the code the user is in the middle of reading aloud. The failure carries
/// the action that produced it so each surface can tell whether the message is
/// about the control it owns.
sealed class PairingState extends Equatable {
  const PairingState();

  @override
  List<Object?> get props => [];
}

final class PairingInitial extends PairingState {
  const PairingInitial();
}

/// The bound service cannot pair — unsupported platform, or Firebase init
/// failed and DI degraded the binding.
final class PairingUnavailable extends PairingState {
  const PairingUnavailable();
}

final class PairingSignedOut extends PairingState {
  const PairingSignedOut();
}

final class PairingLoading extends PairingState {
  const PairingLoading();
}

final class PairingUnpaired extends PairingState {
  /// Generating a code or redeeming one.
  final bool busy;
  final PairingFailure? failure;

  const PairingUnpaired({this.busy = false, this.failure});

  @override
  List<Object?> get props => [busy, failure];
}

/// This device minted a code and is waiting for the other side to use it.
final class PairingInviting extends PairingState {
  final String code;
  final DateTime expiresAt;
  final bool busy;
  final PairingFailure? failure;

  const PairingInviting({
    required this.code,
    required this.expiresAt,
    this.busy = false,
    this.failure,
  });

  @override
  List<Object?> get props => [code, expiresAt, busy, failure];
}

final class PairingPaired extends PairingState {
  /// Null until the partner publishes a profile — only they can write their
  /// own entry, so a freshly redeemed pair briefly knows the uid and no name.
  final PairProfile? partner;
  final bool busy;
  final PairingFailure? failure;

  const PairingPaired({this.partner, this.busy = false, this.failure});

  @override
  List<Object?> get props => [partner, busy, failure];
}

/// The partner ended the link and the user has not acknowledged it yet.
/// [partnerName] is null when they never published a profile.
final class PairingEnded extends PairingState {
  final String? partnerName;

  const PairingEnded({this.partnerName});

  @override
  List<Object?> get props => [partnerName];
}
