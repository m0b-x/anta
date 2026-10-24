import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/sync/sync_engine.dart';
import '../../services/sync/sync_status.dart';
import '../../utils/auth_error.dart';
import 'sync_event.dart';
import 'sync_state.dart';

export 'sync_event.dart';
export 'sync_state.dart';

class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final AuthService _authService;
  final FutureOr<SyncStatusReader> Function()? _statusReader;
  final Future<SyncEngine?> Function()? _engine;

  StreamSubscription<AppUser?>? _authSubscription;
  StreamSubscription<SyncStatus>? _engineSubscription;
  SyncEngine? _followedEngine;

  /// Bumped per [_followEngine], so a slow resolution that a later one
  /// overtook does not subscribe over it.
  int _engineGeneration = 0;

  /// How long an account state waits for its status before showing none: a
  /// database still opening must not leave the account behind a spinner.
  static const Duration statusTimeout = Duration(seconds: 3);

  /// Without a [statusReader] every state carries [SyncStatus.empty]. It is
  /// called only when a status is read, so a platform that never shows one
  /// never opens the database for it, and a failure lands in a handler.
  ///
  /// [engine] is null where no engine runs (no gateway bound); otherwise it
  /// is resolved on the first load or sign-in, its status stream followed
  /// and "Sync now" sent to it — a thunk for the same reason as
  /// [statusReader].
  SyncBloc({
    required AuthService authService,
    FutureOr<SyncStatusReader> Function()? statusReader,
    Future<SyncEngine?> Function()? engine,
  }) : _authService = authService,
       _statusReader = statusReader,
       _engine = engine,
       super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoad);
    on<SignInRequested>(_onSignIn);
    on<SignOutRequested>(_onSignOut);
    on<AuthStateChanged>(_onAuthStateChanged);
    on<RefreshSyncStatus>(_onRefresh);
    on<SyncNowRequested>(_onSyncNow);
    on<SyncEngineStatusChanged>(_onEngineStatus);
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
    _followEngine();
    await _emitStatus(shown, user, emit);
  }

  Future<void> _onSignIn(SignInRequested event, Emitter<SyncState> emit) async {
    if (!_authService.isAvailable) {
      emit(const SyncUnavailable());
      return;
    }

    emit(const SyncSigningIn());
    _followEngine();
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
    final status = _withEngine(await _readStatus(user));
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

  /// [read] with the fields only the engine knows laid over it from the
  /// followed engine's last status: the reader sees the database, not the
  /// run, and a refresh that replaced them would drop a showing `noAccess`
  /// until the engine's next emit (S3c review F7). The sync times come from
  /// the engine only once it has them; the pause only when it is one the
  /// engine decides.
  SyncStatus _withEngine(SyncStatus read) {
    final engine = _followedEngine?.current;
    if (engine == null || engine == SyncStatus.empty) return read;
    final pause = switch (engine.pause) {
      SyncPause.noAccess ||
      SyncPause.appOutdated ||
      SyncPause.quotaExhausted => engine.pause,
      _ => null,
    };
    return read.copyWith(
      activity: engine.activity,
      lastFailure: engine.lastFailure,
      clearLastFailure: engine.lastFailure == null,
      parkedCount: engine.parkedCount,
      downloadedRows: engine.downloadedRows,
      lastPullAt: engine.lastPullAt,
      lastPushAt: engine.lastPushAt,
      pause: pause,
    );
  }

  Future<void> _onSyncNow(
    SyncNowRequested event,
    Emitter<SyncState> emit,
  ) async {
    final thunk = _engine;
    if (thunk == null) return;
    try {
      // The run's progress and outcome arrive through the status stream.
      await (await thunk())?.syncNow();
    } catch (e, st) {
      debugPrint('[SyncBloc] sync now failed: $e\n$st');
    }
  }

  /// The engine's status, into the account state on screen — unless that
  /// state has moved on: a sign-in in flight or a failure owns the screen,
  /// and an account the identity no longer reports is about to be replaced,
  /// while the engine reads its status for the current one.
  void _onEngineStatus(
    SyncEngineStatusChanged event,
    Emitter<SyncState> emit,
  ) {
    final current = _authService.currentUser;
    switch (state) {
      case SyncSignedIn(:final user) when user.uid == current?.uid:
        emit(SyncSignedIn(user, status: event.status));
      case SyncSignedOut() when current == null:
        emit(SyncSignedOut(status: event.status));
      default:
        break;
    }
  }

  /// Resolves the engine and follows its status stream, starting from its
  /// [SyncEngine.current] — the stream does not replay. Asked again on every
  /// load and sign-in: after a database switch the thunk answers with a new
  /// engine, and the old one's stream simply goes quiet (its reset does not
  /// close it). Never awaited by a handler, so an engine that is dead or
  /// never emits leaves the account state as it is.
  void _followEngine() {
    final thunk = _engine;
    if (thunk == null) return;
    final generation = ++_engineGeneration;
    unawaited(() async {
      try {
        final engine = await thunk();
        if (engine == null || isClosed || generation != _engineGeneration) {
          return;
        }
        if (identical(engine, _followedEngine) && _engineSubscription != null) {
          return;
        }
        await _engineSubscription?.cancel();
        _engineSubscription = null;
        if (isClosed || generation != _engineGeneration) return;
        _followedEngine = engine;
        _engineSubscription = engine.status.listen(
          (status) => add(SyncEngineStatusChanged(status)),
          onDone: () {
            if (identical(_followedEngine, engine)) _engineSubscription = null;
          },
        );
        // An engine that has not emitted yet has nothing to add to the
        // reader's status, and its empty one would wipe it.
        final current = engine.current;
        if (current != SyncStatus.empty) add(SyncEngineStatusChanged(current));
      } catch (e, st) {
        debugPrint('[SyncBloc] the sync engine is unavailable: $e\n$st');
      }
    }());
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
    _engineSubscription?.cancel();
    return super.close();
  }
}
