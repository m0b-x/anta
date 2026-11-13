import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/qa/qa_mode.dart';
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

  /// The Auth emulator's port, as `firebase.emulators.json` declares it
  /// unless a QA run names another ([QaMode.firebaseAuthPort]).
  static const int emulatorAuthPort = QaMode.firebaseAuthPort;

  /// Points Firebase Auth at the emulator suite on [host]: once, in DI,
  /// before any sign-in, and only in a QA build ([QaMode.useFirebaseEmulator]).
  static Future<void> useEmulator(String host) =>
      FirebaseAuth.instance.useAuthEmulator(host, emulatorAuthPort);

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
    final credential = await _credential();
    if (credential == null) return null;
    final result = await _auth.signInWithCredential(credential);
    return _toAppUser(result.user);
  });

  /// What a sign-in, or a sign-in asked again, hands Firebase: the QA
  /// account's on the Auth emulator, otherwise Google's from its interactive
  /// flow — null when the user dismissed that.
  Future<AuthCredential?> _credential() async {
    if (QaMode.useFirebaseEmulator) return _qaCredential();
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
      throw const NoIdTokenException();
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// [QaIdentity.account] as a credential for the Auth emulator, without
  /// Google: the emulator takes an unsigned JSON "ID token" as a Google
  /// credential, its `sub` the account's key (Firebase docs, "Connect your
  /// app to the Authentication Emulator").
  AuthCredential _qaCredential() {
    final account = QaIdentity.account;
    final colon = account.indexOf(':');
    if (colon <= 0) {
      throw const QaAccountFormatException();
    }
    final token = jsonEncode({
      'sub': account.substring(0, colon),
      'email': account.substring(colon + 1),
      'email_verified': true,
    });
    return GoogleAuthProvider.credential(idToken: token);
  }

  /// Set by DI: what has to be written as this account before its session
  /// ends — the push registry's leave, which only the account itself may
  /// write (`docs/cloud-shared-freshness.md` §7). Bounded by its own
  /// deadline; its failure never holds the sign-out.
  static Future<void> Function(String uid)? beforeSignOut;

  /// A Firebase ID token of the signed-in account, for a call that proves it
  /// to a server of ours (the push relay); null while nobody is signed in.
  static Future<String?> idToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  @override
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    final leaving = beforeSignOut;
    if (uid != null && leaving != null) {
      try {
        await leaving(uid);
      } catch (e) {
        debugPrint('[FirebaseAuthService] before sign-out: $e');
      }
    }
    // Best-effort on the Google side: whatever happens there, the Firebase
    // session must still end, or the user is stranded signed in.
    await _leaveGoogle('sign-out', () => GoogleSignIn.instance.signOut());
    await _auth.signOut();
  }

  @override
  Future<bool> reauthenticate() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException(AuthError.unknown);
    final credential = await _credential();
    if (credential == null) return false;
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-mismatch') rethrow;
      // Google now holds the other account as the one it would offer first;
      // dropped, so the next attempt asks which account again.
      await _leaveGoogle('sign-out', () => GoogleSignIn.instance.signOut());
      throw const OtherAccountException();
    }
    return true;
  });

  /// How long [deleteAccount] waits for the server: the call is the last of
  /// a background run that every other deletion queues behind, and one that
  /// never answered would hold them all.
  static const Duration deleteAccountTimeout = Duration(seconds: 30);

  @override
  Future<void> deleteAccount() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException(AuthError.unknown);
    try {
      await user.delete().timeout(deleteAccountTimeout);
    } on TimeoutException {
      throw const AuthException(AuthError.offline);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'requires-recent-login':
          throw const RecentSignInRequiredException();
        // Deleted already, from another device: what is left is this
        // session, which only a sign-out ends.
        case 'user-not-found':
          await _auth.signOut();
        default:
          rethrow;
      }
    }
    // The app's grant in the Google account goes with the account: a later
    // sign-in is a new account's and asks for consent again. Not awaited:
    // the account is gone whatever Google answers, and a prompt that never
    // did would hold the run that called this.
    unawaited(
      _leaveGoogle('disconnect', () => GoogleSignIn.instance.disconnect()),
    );
  });

  /// [leave] on the Google side, logged and never thrown: the Firebase
  /// session is what the app reads, and it must change whatever Google
  /// answers.
  Future<void> _leaveGoogle(String what, Future<void> Function() leave) async {
    try {
      await _ensureInitialized();
      await leave();
    } on GoogleSignInException catch (e) {
      _logCause(AuthError.unknown, 'google $what ${e.code.name}');
    } catch (e) {
      _logCause(AuthError.unknown, 'google $what ${e.runtimeType}');
    }
  }

  @override
  Future<void> dispose() async {}

  /// Maps every remote failure onto an [AuthError], the same way
  /// `FirestorePairingGateway._guard` shields the layers above from
  /// `FirebaseException` codes.
  ///
  /// The cause is logged before it is mapped: an `unknown` reads only "Sign-in
  /// failed", and the first sign-in against the emulator suite failed with
  /// nothing in any log to say why. Only in a debug build, and only the
  /// mapped cause and the exception's code: `debugPrint` still prints in
  /// release, and an exception's message or `toString()` can name the
  /// account.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException {
      rethrow;
    } on OtherAccountException {
      rethrow;
    } on RecentSignInRequiredException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      final cause = _networkCode(e.code)
          ? AuthError.offline
          : AuthError.unknown;
      _logCause(cause, e.code);
      throw AuthException(cause);
    } on GoogleSignInException catch (e) {
      final cause = _networkCode(e.code.name)
          ? AuthError.offline
          : AuthError.unknown;
      _logCause(cause, 'google ${e.code.name}');
      throw AuthException(cause);
    } on UnsupportedError {
      throw const AuthException(AuthError.notSupported);
    } catch (e) {
      _logCause(AuthError.unknown, e.runtimeType.toString());
      throw const AuthException(AuthError.unknown);
    }
  }

  void _logCause(AuthError cause, String code) {
    if (kDebugMode) debugPrint('[FirebaseAuthService] ${cause.name}: $code');
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

/// Google Sign-In finished without an ID token. A type of its own because
/// `_guard` logs only an exception's type: the name is the diagnosis, so the
/// log never needs a message.
class NoIdTokenException implements Exception {
  const NoIdTokenException();
}

/// `ANTA_QA_ACCOUNT` is not `<sub>:<email>`. A type of its own so the log
/// names the fault without the define's value, which carries an address.
class QaAccountFormatException implements Exception {
  const QaAccountFormatException();
}
