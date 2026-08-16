import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import 'sync_event.dart';
import 'sync_state.dart';

export 'sync_event.dart';
export 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final AuthService _authService;

  StreamSubscription<AppUser?>? _authSubscription;

  SyncBloc({required AuthService authService})
    : _authService = authService,
      super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoad);
    on<SignInRequested>(_onSignIn);
    on<SignOutRequested>(_onSignOut);
    on<AuthStateChanged>(_onAuthStateChanged);
  }

  void _onLoad(LoadSyncStatus event, Emitter<SyncState> emit) {
    // The bound service, not the platform gate: DI degrades to the no-op
    // binding when Firebase init failed, and that must read as unavailable
    // rather than a sign-in button that can only ever fail.
    if (!_authService.isAvailable) {
      emit(const SyncUnavailable());
      return;
    }

    emit(_stateFor(_authService.currentUser));

    _authSubscription ??= _authService.authStateChanges.listen(
      (user) => add(AuthStateChanged(user)),
    );
  }

  Future<void> _onSignIn(
    SignInRequested event,
    Emitter<SyncState> emit,
  ) async {
    if (!_authService.isAvailable) {
      emit(const SyncUnavailable());
      return;
    }

    emit(const SyncSigningIn());
    try {
      final user = await _authService.signInWithGoogle();
      // A null user means the flow was dismissed, which the stream never
      // reports — fall back to the account we already had.
      emit(_stateFor(user ?? _authService.currentUser));
    } catch (e) {
      emit(SyncFailure(e.toString()));
    }
  }

  Future<void> _onSignOut(
    SignOutRequested event,
    Emitter<SyncState> emit,
  ) async {
    try {
      await _authService.signOut();
      emit(const SyncSignedOut());
    } catch (e) {
      emit(SyncFailure(e.toString()));
    }
  }

  void _onAuthStateChanged(AuthStateChanged event, Emitter<SyncState> emit) {
    // An in-flight interactive sign-in owns the state until it resolves, so
    // the stream's intermediate "still signed out" must not clear the spinner.
    if (state is SyncSigningIn && event.user == null) return;
    emit(_stateFor(event.user));
  }

  SyncState _stateFor(AppUser? user) =>
      user == null ? const SyncSignedOut() : SyncSignedIn(user);

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
