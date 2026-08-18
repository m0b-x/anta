import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';
import '../utils/auth_error.dart';
import 'auth_service.dart';

/// Google Sign-In on top of Firebase Auth.
///
/// Firebase persists its own session, so a returning user is already signed in
/// by the time [authStateChanges] emits on cold launch — no silent re-auth
/// against Google is needed to restore [currentUser].
class FirebaseAuthService implements AuthService {
  /// Resolved lazily: `FirebaseAuth.instance` throws when no Firebase app was
  /// initialized, and this service is constructed during DI registration —
  /// eagerly touching it would turn a swallowed init failure into a crash at
  /// launch.
  final FirebaseAuth? _injectedAuth;

  /// Memoized so concurrent callers share one `initialize()` and a failed
  /// attempt can retry instead of poisoning every later call.
  Future<void>? _initFuture;

  FirebaseAuthService({FirebaseAuth? auth}) : _injectedAuth = auth;

  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  @override
  bool get isAvailable => true;

  /// `initialize` must complete once before any other `GoogleSignIn` call.
  /// The identifiers come from `google-services.json` on Android and
  /// `Info.plist` on iOS, so nothing is passed here.
  Future<void> _ensureInitialized() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      await GoogleSignIn.instance.initialize();
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  @override
  Stream<AppUser?> get authStateChanges =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<AppUser?> signInWithGoogle() => _guard(() async {
    await _ensureInitialized();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AuthException(AuthError.notSupported);
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google Sign-In returned no ID token.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await _auth.signInWithCredential(credential);
    return _toAppUser(result.user);
  });

  @override
  Future<void> signOut() async {
    // Best-effort on the Google side: whatever happens there, the Firebase
    // session must still end, or the user is stranded signed in.
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('[FirebaseAuthService] Google sign-out failed: $e');
    }
    await _auth.signOut();
  }

  @override
  Future<void> dispose() async {}

  /// Maps every remote failure onto an [AuthError], the same way
  /// `FirestorePairingGateway._guard` shields the layers above from
  /// `FirebaseException` codes.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        _networkCode(e.code) ? AuthError.offline : AuthError.unknown,
      );
    } on GoogleSignInException catch (e) {
      throw AuthException(
        _networkCode(e.code.name) ? AuthError.offline : AuthError.unknown,
      );
    } on UnsupportedError {
      throw const AuthException(AuthError.notSupported);
    } catch (_) {
      throw const AuthException(AuthError.unknown);
    }
  }

  bool _networkCode(String code) => code.toLowerCase().contains('network');

  AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoURL,
    );
  }
}
