import '../l10n/app_localizations.dart';

/// Why a sign-in attempt failed. One button, one outcome, but "sign-in
/// failed" alone gives the user nothing to act on — offline and
/// not-supported-here call for different next steps than a transient
/// server error does.
enum AuthError {
  /// The device could not reach Google or Firebase. Distinct from
  /// [unavailable]: this is a transient condition, retrying once back online
  /// should succeed.
  offline,

  /// The bound service cannot sign in at all — Firebase init failed and DI
  /// degraded to the no-op binding.
  unavailable,

  /// The platform (or this device) does not support the interactive Google
  /// Sign-In flow.
  notSupported,

  unknown,
}

/// The one place the ARB keys map onto [AuthError], following the
/// `PairingErrorMessages` pattern — a sealed `switch`, no key lookup.
class AuthErrorMessages {
  final String offline;
  final String unavailable;
  final String notSupported;
  final String unknown;

  const AuthErrorMessages({
    required this.offline,
    required this.unavailable,
    required this.notSupported,
    required this.unknown,
  });

  factory AuthErrorMessages.of(AppLocalizations l10n) => AuthErrorMessages(
    offline: l10n.authErrorOffline,
    unavailable: l10n.authErrorUnavailable,
    notSupported: l10n.authErrorNotSupported,
    unknown: l10n.authErrorUnknown,
  );

  String resolve(AuthError e) {
    switch (e) {
      case AuthError.offline:
        return offline;
      case AuthError.unavailable:
        return unavailable;
      case AuthError.notSupported:
        return notSupported;
      case AuthError.unknown:
        return unknown;
    }
  }
}

/// Thrown across the service boundary so callers never see a
/// `FirebaseException` or `GoogleSignInException`, the same way `AppUser`
/// keeps `firebase_auth` out of the layers above.
class AuthException implements Exception {
  final AuthError error;

  const AuthException(this.error);

  @override
  String toString() => 'AuthException(${error.name})';
}

/// The account chosen to confirm a sign-in again is not the one signed in:
/// nothing was confirmed, and the session stays as it was. A type of its
/// own, not an [AuthError]: it is no reason a sign-in failed, and whoever
/// asked for the confirmation words it — an account's deletion, as
/// "that is another account".
class OtherAccountException implements Exception {
  const OtherAccountException();

  @override
  String toString() => 'OtherAccountException';
}

/// The sign-in is too old for what was asked: Firebase deletes an account
/// only minutes after one. The way on is to sign in again
/// (`AuthService.reauthenticate`), never to retry — which is why it is no
/// [AuthError], whose every value a retry may cure.
class RecentSignInRequiredException implements Exception {
  const RecentSignInRequiredException();

  @override
  String toString() => 'RecentSignInRequiredException';
}
