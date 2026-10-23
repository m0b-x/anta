import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/sync/sync_status.dart';
import '../../utils/auth_error.dart';
import 'sync_event.dart';
import 'sync_state.dart';

export 'sync_event.dart';
export 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final AuthService _authService;
  final FutureOr<SyncStatusReader> Function()? _statusReader;

  StreamSubscription<AppUser?>? _authSubscription;

  /// How long an account state waits for its status before showing none: a
  /// database still opening must not leave the account behind a spinner.
  static const Duration statusTimeout = Duration(seconds: 3);

  /// Without a [statusReader] every state carries [SyncStatus.empty]. It is
  /// called only when a status is read, so a platform that never shows one
  /// never opens the database for it, and a failure lands in a handler.
  SyncBloc({
    required AuthService authService,
    FutureOr<SyncStatusReader> Function()? statusReader,
  }) : _authService = authService,
       _statusReader = statusReader,
       super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoad);
    on<SignInRequested>(_onSignIn);
    on<SignOutRequested>(_onSignOut);
    on<AuthStateChanged>(_onAuthStateChanged);
    on<RefreshSyncStatus>(_onRefresh);
  }

  Future<void> _onLoad(LoadSyncStatus event, Emitter<SyncState> emit) async {
    // The bound service, not the platform gate: DI degrades to the no-op
    // binding when Firebase init failed, and that must read as unavailable
    // rather than a sign-in button that can only ever fail.
    if (!_authService.isAvailable) {
      emit(const SyncUnavailable());
      return;
    }

    final user = _authService.currentUser;
    final shown = _emitAccount(user, emit);

    _authSubscription ??= _authService.authStateChanges.listen(
      (user) => add(AuthStateChanged(user)),
    );
    await _emitStatus(shown, user, emit);
  }

  Future<void> _onSignIn(SignInRequested event, Emitter<SyncState> emit) async {
    if (!_authService.isAvailable) {
      emit(const SyncUnavailable());
      return;
    }

    emit(const SyncSigningIn());
    try {
      // A null user means the flow was dismissed, which the stream never
      // reports — fall back to the account we already had.
      final user =
          await _authService.signInWithGoogle() ?? _authService.currentUser;
      await _emitStatus(_emitAccount(user, emit), user, emit);
    } on AuthException catch (e) {
      emit(SyncFailure(e.error));
    } catch (_) {
      emit(const SyncFailure(AuthError.unknown));
    }
  }

  Future<void> _onSignOut(
    SignOutRequested event,
    Emitter<SyncState> emit,
  ) async {
    try {
      await _authService.signOut();
      await _emitStatus(_emitAccount(null, emit), null, emit);
    } on AuthException catch (e) {
      emit(SyncFailure(e.error));
    } catch (_) {
      emit(const SyncFailure(AuthError.unknown));
    }
  }

  Future<void> _onAuthStateChanged(
    AuthStateChanged event,
    Emitter<SyncState> emit,
  ) async {
    // An in-flight interactive sign-in owns the state until it resolves, so
    // the stream's intermediate "still signed out" must not clear the spinner.
    if (state is SyncSigningIn && event.user == null) return;
    await _emitStatus(_emitAccount(event.user, emit), event.user, emit);
  }

  Future<void> _onRefresh(
    RefreshSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    final AppUser? user;
    switch (state) {
      case SyncSignedIn(user: final current):
        user = current;
      case SyncSignedOut():
        user = null;
      default:
        return;
    }
    final status = await _readStatus(user);
    // Re-read after the await: an account change while reading owns the
    // state now, and its own read already carries a status.
    switch (state) {
      case SyncSignedIn(user: final current) when current == user:
        emit(SyncSignedIn(current, status: status));
      case SyncSignedOut() when user == null:
        emit(SyncSignedOut(status: status));
      default:
        break;
    }
  }

  /// Shows [user]'s account at once and returns the state emitted, for
  /// [_emitStatus] to recognise. The status already on screen is carried
  /// only while the user is the same one: the queue belongs to the database,
  /// but the pause is per account, so another account starts from
  /// [SyncStatus.empty] until its own read lands rather than showing the
  /// previous account's mismatch.
  SyncState _emitAccount(AppUser? user, Emitter<SyncState> emit) {
    final known = switch (state) {
      SyncSignedIn(user: final shown, :final status)
          when shown.uid == user?.uid =>
        status,
      SyncSignedOut(:final status) when user == null => status,
      _ => SyncStatus.empty,
    };
    emit(_stateFor(user, known));
    return state;
  }

  /// Adds the status to [shown] once it is read, unless the state moved on
  /// meanwhile: a sign-in handled during the read owns the state, and the
  /// read's stale account must not overwrite it.
  Future<void> _emitStatus(
    SyncState shown,
    AppUser? user,
    Emitter<SyncState> emit,
  ) async {
    final status = await _readStatus(user);
    if (emit.isDone || !identical(state, shown)) return;
    emit(_stateFor(user, status));
  }

  /// A reader that fails or stalls never breaks the state: the account still
  /// shows, with nothing known about its sync.
  Future<SyncStatus> _readStatus(AppUser? user) async {
    final reader = _statusReader;
    if (reader == null) return SyncStatus.empty;
    try {
      return await Future.sync(
        () async => (await reader()).read(user: user),
      ).timeout(statusTimeout);
    } catch (e, st) {
      debugPrint('[SyncBloc] reading the sync status failed: $e\n$st');
      return SyncStatus.empty;
    }
  }

  SyncState _stateFor(AppUser? user, SyncStatus status) => user == null
      ? SyncSignedOut(status: status)
      : SyncSignedIn(user, status: status);

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
