import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../services/pairing_service.dart';
import '../../utils/pairing_error.dart';

sealed class PairingEvent extends Equatable {
  const PairingEvent();

  @override
  List<Object?> get props => [];
}

final class LoadPairing extends PairingEvent {
  const LoadPairing();
}

final class GenerateInviteRequested extends PairingEvent {
  const GenerateInviteRequested();
}

final class CancelInviteRequested extends PairingEvent {
  const CancelInviteRequested();
}

final class RedeemCodeRequested extends PairingEvent {
  final String code;

  const RedeemCodeRequested(this.code);

  @override
  List<Object?> get props => [code];
}

final class UnpairRequested extends PairingEvent {
  const UnpairRequested();
}

final class EndedNoticeDismissed extends PairingEvent {
  const EndedNoticeDismissed();
}

/// Pushed by the service when a listener fires — an invite redeemed on the
/// other device, a partner ending the link, a profile arriving.
final class PairingStatusChanged extends PairingEvent {
  final PairingStatus status;

  const PairingStatusChanged(this.status);

  @override
  List<Object?> get props => [status];
}

/// A failure with no user action to attach it to — a dropped snapshot
/// listener, or the background half of a redemption failing.
final class PairingErrorReported extends PairingEvent {
  final PairingError error;

  const PairingErrorReported(this.error);

  @override
  List<Object?> get props => [error];
}

/// Fed by the auth stream, not the UI. Signing in is what makes reconciliation
/// possible, and signing out invalidates everything downstream of the uid.
final class PairingAuthChanged extends PairingEvent {
  final AppUser? user;

  const PairingAuthChanged(this.user);

  @override
  List<Object?> get props => [user];
}
