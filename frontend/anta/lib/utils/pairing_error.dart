import 'package:equatable/equatable.dart';

import '../l10n/app_localizations.dart';

/// Why a pairing attempt failed. Unlike sign-in — one button, one outcome —
/// every redemption failure implies a different next action ("ask for a new
/// code", "that one is yours", "you are already paired"), so these do not
/// collapse into a single message.
enum PairingError {
  /// Firestore could not reach a server. Pairing is deliberately online-only:
  /// a write that lands in the offline queue would report success and pair
  /// nobody.
  offline,

  notSignedIn,

  /// The bound service cannot pair at all — unsupported platform, or Firebase
  /// init failed and DI degraded the binding.
  unavailable,

  /// Not found, expired, or already redeemed. Security rules make expired
  /// invites unreadable, so the client genuinely cannot tell these apart.
  codeInvalid,

  ownCode,
  alreadyPaired,
  permissionDenied,
  unknown,
}

/// The one place the ARB keys map onto [PairingError], following the
/// `MoneyErrorMessages` pattern — a sealed `switch`, no key lookup.
class PairingErrorMessages {
  final String offline;
  final String notSignedIn;
  final String unavailable;
  final String codeInvalid;
  final String ownCode;
  final String alreadyPaired;
  final String permissionDenied;
  final String unknown;

  const PairingErrorMessages({
    required this.offline,
    required this.notSignedIn,
    required this.unavailable,
    required this.codeInvalid,
    required this.ownCode,
    required this.alreadyPaired,
    required this.permissionDenied,
    required this.unknown,
  });

  factory PairingErrorMessages.of(AppLocalizations l10n) =>
      PairingErrorMessages(
        offline: l10n.pairingErrorOffline,
        notSignedIn: l10n.pairingErrorNotSignedIn,
        unavailable: l10n.pairingErrorUnavailable,
        codeInvalid: l10n.pairingErrorCodeInvalid,
        ownCode: l10n.pairingErrorOwnCode,
        alreadyPaired: l10n.pairingErrorAlreadyPaired,
        permissionDenied: l10n.pairingErrorPermissionDenied,
        unknown: l10n.pairingErrorUnknown,
      );

  String resolve(PairingError e) {
    switch (e) {
      case PairingError.offline:
        return offline;
      case PairingError.notSignedIn:
        return notSignedIn;
      case PairingError.unavailable:
        return unavailable;
      case PairingError.codeInvalid:
        return codeInvalid;
      case PairingError.ownCode:
        return ownCode;
      case PairingError.alreadyPaired:
        return alreadyPaired;
      case PairingError.permissionDenied:
        return permissionDenied;
      case PairingError.unknown:
        return unknown;
    }
  }
}

/// Which attempt produced a failure. Without it, "no connection" from
/// generating a code renders as an error on the code-entry field the user
/// never touched — the message is right but it accuses the wrong control.
enum PairingAction {
  load,
  generate,
  cancel,
  redeem,
  unpair,

  /// No user action: a dropped snapshot listener, or the background half of a
  /// redemption failing.
  background,
}

/// A failure bound to the thing that failed, so each surface can decide
/// whether it owns the message.
class PairingFailure extends Equatable {
  final PairingError error;
  final PairingAction action;

  const PairingFailure(this.error, this.action);

  /// The code field owns redemption failures; everything else belongs to the
  /// invite half of the sheet or to the settings row.
  bool get belongsToCodeField => action == PairingAction.redeem;

  @override
  List<Object?> get props => [error, action];
}

/// Thrown across the gateway/service boundary so callers never see a
/// `FirebaseException`, the same way `AppUser` keeps `firebase_auth` out of
/// the layers above.
class PairingException implements Exception {
  final PairingError error;

  const PairingException(this.error);

  @override
  String toString() => 'PairingException(${error.name})';
}
