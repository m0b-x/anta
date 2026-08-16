import '../models/app_user.dart';

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
    throw UnsupportedError('Cloud sync is not available on this platform.');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> dispose() async {}
}
