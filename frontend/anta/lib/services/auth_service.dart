import '../models/app_user.dart';
import '../utils/auth_error.dart';

/// Cloud identity, kept behind an interface so `injection.dart` can bind a
/// no-op implementation on platforms where [SyncAvailability] is false and
/// Firebase types never reach the bloc or UI layers.
abstract class AuthService {
  /// Whether this binding can actually run a sign-in flow. False on the
  /// no-op service, so the UI reports "unavailable" both on unsupported
  /// platforms and when Firebase init failed and DI degraded the binding —
  /// the bound service, not the platform gate, is the single source of truth.
  bool get isAvailable;

  /// Emits the current account, then every change. Emits `null` when signed
  /// out. Replays the latest value to new listeners.
  Stream<AppUser?> get authStateChanges;

  /// The account as of the last stream emission, or `null` when signed out.
  AppUser? get currentUser;

  /// Runs the interactive sign-in flow. Returns `null` when the user
  /// dismissed it — cancellation is not an error.
  Future<AppUser?> signInWithGoogle();

  Future<void> signOut();

  /// Asks the signed-in account to sign in once more, interactively — the
  /// proof of presence [deleteAccount] needs. False when the user dismissed
  /// it, and then nothing changed.
  ///
  /// Throws [OtherAccountException] when another account was chosen — the
  /// session stays the first one's — and [AuthException] for anything else,
  /// [AuthError.unknown] when nobody is signed in.
  Future<bool> reauthenticate();

  /// Deletes the signed-in account itself and ends the session, so
  /// [authStateChanges] emits null. Its data is not this call's: whatever
  /// the account holds in the cloud is deleted first, by the caller, because
  /// the same person signing in again is a new account that could never
  /// reach it (cloud-multi-user-roadmap §6.1 b).
  ///
  /// Throws [RecentSignInRequiredException] when the sign-in is older than
  /// the few minutes the server allows — nothing was deleted, and
  /// [reauthenticate] is the way on — and [AuthException] otherwise;
  /// [AuthError.offline] too when the call outlasted its bound, in which
  /// case the delete may still land and the session then ends by itself.
  Future<void> deleteAccount();

  Future<void> dispose();
}

/// Bound on platforms without cloud sync. Reports "signed out" forever and
/// refuses to start a flow that cannot complete.
class NoOpAuthService implements AuthService {
  @override
  bool get isAvailable => false;

  @override
  Stream<AppUser?> get authStateChanges => Stream<AppUser?>.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  Future<AppUser?> signInWithGoogle() async {
    throw const AuthException(AuthError.unavailable);
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> reauthenticate() async {
    throw const AuthException(AuthError.unavailable);
  }

  @override
  Future<void> deleteAccount() async {
    throw const AuthException(AuthError.unavailable);
  }

  @override
  Future<void> dispose() async {}
}
