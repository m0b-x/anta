import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/sync/sync_engine.dart';
import '../../services/sync/sync_space_service.dart';
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
  final SyncSpaceService? _spaces;

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
  ///
  /// [spaces] is null where sync is not (no gateway bound): the bind and stop
  /// events are then ignored.
  SyncBloc({
    required AuthService authService,
    FutureOr<SyncStatusReader> Function()? statusReader,
    Future<SyncEngine?> Function()? engine,
    SyncSpaceService? spaces,
  }) : _authService = authService,
       _statusReader = statusReader,
       _engine = engine,
       _spaces = spaces,
       super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoad);
    on<SignInRequested>(_onSignIn);
    on<SignOutRequested>(_onSignOut);
    on<AuthStateChanged>(_onAuthStateChanged);
    on<RefreshSyncStatus>(_onRefresh);
    on<SyncNowRequested>(_onSyncNow);
    on<SyncEngineStatusChanged>(_onEngineStatus);
    on<SyncThisDatabaseRequested>(_onSyncThisDatabase);
    on<MergeIntoSpaceRequested>(
      (event, emit) => _bindChoice(emit, (spaces, uid) async {
        await spaces.bindExisting(event.space.ref, accountUid: uid);
        return null;
      }),
    );
    on<DownloadSpaceRequested>(
      (event, emit) => _bindChoice(
        emit,
        (spaces, uid) =>
            spaces.downloadIntoNewDatabase(event.space, accountUid: uid),
      ),
    );
    on<UploadAsNewSpaceRequested>(
      (event, emit) => _bindChoice(emit, (spaces, uid) async {
        await spaces.createAndBind(accountUid: uid, name: event.name);
        return null;
      }),
    );
    on<BindFlowDismissed>(_onBindFlowDismissed);
    on<StopSyncingRequested>(_onStopSyncing);
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
    unawaited(_followEngine());
    await _emitStatus(shown, user, emit);
  }

  Future<void> _onSignIn(SignInRequested event, Emitter<SyncState> emit) async {
    if (!_authService.isAvailable) {
      emit(const SyncUnavailable());
      return;
    }

    emit(const SyncSigningIn());
    unawaited(_followEngine());
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
    // A bloc that outlived a database switch still follows the engine the
    // switch dropped, and would lay that space's status over the new
    // database's fresh read on every refresh (A1c review R40). Idempotent
    // while the engine is the same one.
    //
    // Awaited, unlike on a load or a sign-in: `_withEngine` below reads the
    // followed engine, so a follow still resolving would leave the dropped
    // space's times over this read and only the next refresh clean (A6
    // review R112). Bounded by the same timeout as the read — an engine that
    // never resolves must not keep the refresh from emitting.
    await _followEngine().timeout(statusTimeout, onTimeout: () {});
    final status = _withEngine(await _readStatus(user));
    // Re-read after the await: an account change while reading owns the
    // state now, and its own read already carries a status.
    switch (state) {
      case SyncSignedIn(user: final current, :final flow) when current == user:
        emit(SyncSignedIn(current, status: status, flow: flow));
      case SyncSignedOut(:final flow) when user == null:
        emit(SyncSignedOut(status: status, flow: flow));
      default:
        break;
    }
  }

  /// [read] with the fields only the engine knows laid over it from the
  /// followed engine's last status: the reader sees the database, not the
  /// run, and a read that replaced them would drop a showing `noAccess`
  /// until the engine's next emit (S3c review F7). The sync times come from
  /// the engine only once it has them; the pause by
  /// [SyncEngine.pauseOver], the rule the engine's own emits follow, so a
  /// sign-out is never shown under a `noAccess` the engine stored for the
  /// account before it (S4a review L10).
  SyncStatus _withEngine(SyncStatus read) {
    final engine = _followedEngine?.current;
    if (engine == null || engine == SyncStatus.empty) return read;
    final pause = SyncEngine.pauseOver(read: read.pause, engine: engine.pause);
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
  void _onEngineStatus(SyncEngineStatusChanged event, Emitter<SyncState> emit) {
    final current = _authService.currentUser;
    switch (state) {
      case SyncSignedIn(:final user, :final flow) when user.uid == current?.uid:
        emit(SyncSignedIn(user, status: event.status, flow: flow));
      case SyncSignedOut(:final flow) when current == null:
        emit(SyncSignedOut(status: event.status, flow: flow));
      default:
        break;
    }
  }

  Future<void> _onSyncThisDatabase(
    SyncThisDatabaseRequested event,
    Emitter<SyncState> emit,
  ) async {
    final spaces = _spaces;
    final shown = state;
    if (spaces == null || shown is! SyncSignedIn || shown.flow.isBusy) return;
    final uid = shown.user.uid;
    _emitFlow(emit, uid, const SyncBindChecking());
    try {
      switch (await spaces.start(accountUid: uid)) {
        case SyncBindStartBound():
          await _afterBindingChanged(emit, uid, const SyncBindIdle());
        case SyncBindStartPick(:final spaces, :final holdsData, :final heldBy):
          _emitFlow(
            emit,
            uid,
            SyncBindPicking(
              spaces: spaces,
              holdsData: holdsData,
              heldBy: heldBy,
            ),
          );
      }
    } catch (e, st) {
      _emitFlow(emit, uid, _failed(e, st));
    }
  }

  /// One of the picker's choices — or a retry after a failed one: [run]
  /// answers the database a download switched to, else null.
  Future<void> _bindChoice(
    Emitter<SyncState> emit,
    Future<String?> Function(SyncSpaceService spaces, String accountUid) run,
  ) async {
    final spaces = _spaces;
    final shown = state;
    if (spaces == null || shown is! SyncSignedIn || shown.flow.isBusy) return;
    final uid = shown.user.uid;
    _emitFlow(emit, uid, const SyncBindBinding());
    try {
      final switchedTo = await run(spaces, uid);
      await _afterBindingChanged(
        emit,
        uid,
        SyncBindIdle(switchedToDatabase: switchedTo),
      );
    } catch (e, st) {
      _emitFlow(emit, uid, _failed(e, st));
    }
  }

  void _onBindFlowDismissed(BindFlowDismissed event, Emitter<SyncState> emit) {
    final String? account;
    switch (state) {
      case SyncSignedIn(
        :final user,
        flow: SyncBindPicking() ||
            SyncBindFailed() ||
            SyncBindIdle(switchedToDatabase: _?),
      ):
        account = user.uid;
      case SyncSignedOut(flow: SyncBindFailed()):
        account = null;
      default:
        return;
    }
    _emitFlow(emit, account, const SyncBindIdle());
  }

  /// Whatever the account (D5 A): another account's pause and a sign-out
  /// both keep the binding, and this is the way out of either.
  Future<void> _onStopSyncing(
    StopSyncingRequested event,
    Emitter<SyncState> emit,
  ) async {
    final spaces = _spaces;
    if (spaces == null) return;
    final String? account;
    switch (state) {
      case SyncSignedIn(:final user, :final flow) when !flow.isBusy:
        account = user.uid;
      case SyncSignedOut(:final flow) when !flow.isBusy:
        account = null;
      default:
        return;
    }
    _emitFlow(emit, account, const SyncBindStopping());
    try {
      await spaces.stopSyncing();
      await _afterBindingChanged(emit, account, const SyncBindIdle());
    } catch (e, st) {
      _emitFlow(emit, account, _failed(e, st));
    }
  }

  /// [flow] shown, then the engine restarted and the status read again, so
  /// the row under the flow says what the binding now is.
  ///
  /// Restarted — [SyncEngine.stop] then [SyncEngine.start], the pair the
  /// engine names for a rebind — rather than sent "Sync now": a start drops
  /// the previous space's pause, back-off and parked rows, where a run would
  /// keep an `appOutdated` from the space just left, and it runs at once.
  Future<void> _afterBindingChanged(
    Emitter<SyncState> emit,
    String? account,
    SyncBindFlow flow,
  ) async {
    _emitFlow(emit, account, flow);
    final thunk = _engine;
    if (thunk != null) {
      try {
        final engine = await thunk();
        if (engine != null) {
          await engine.stop();
          await engine.start();
        }
      } catch (e, st) {
        debugPrint('[SyncBloc] restarting the sync engine failed: $e\n$st');
      }
    }
    await _onRefresh(const RefreshSyncStatus(), emit);
  }

  /// [flow] into the account state on screen, while it is still [account]'s
  /// — null for signed out. An account that changed meanwhile owns the
  /// screen, and the flow it starts from is idle.
  void _emitFlow(Emitter<SyncState> emit, String? account, SyncBindFlow flow) {
    if (emit.isDone) return;
    switch (state) {
      case SyncSignedIn(:final user, :final status) when user.uid == account:
        emit(SyncSignedIn(user, status: status, flow: flow));
      case SyncSignedOut(:final status) when account == null:
        emit(SyncSignedOut(status: status, flow: flow));
      default:
        break;
    }
  }

  SyncBindFailed _failed(Object error, StackTrace stack) {
    if (error is SyncSpaceException) {
      return SyncBindFailed(
        error.failure,
        holderDatabase: error.holderDatabase,
      );
    }
    debugPrint('[SyncBloc] binding failed: $error\n$stack');
    return const SyncBindFailed(SyncBindFailure.unknown);
  }

  /// Resolves the engine and follows its status stream, starting from its
  /// [SyncEngine.current] — the stream does not replay. Asked again on every
  /// load and sign-in: after a database switch the thunk answers with a new
  /// engine, and the old one's stream simply goes quiet (its reset does not
  /// close it). Never awaited by a handler, so an engine that is dead or
  /// never emits leaves the account state as it is — except on a refresh,
  /// which awaits it under a timeout because it reads the followed engine on
  /// the next line (A6 review R112).
  Future<void> _followEngine() async {
    final thunk = _engine;
    if (thunk == null) return;
    final generation = ++_engineGeneration;
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
  }

  /// Shows [user]'s account at once and returns the state emitted, for
  /// [_emitStatus] to recognise. The status already on screen is carried
  /// only while the user is the same one: the queue belongs to the database,
  /// but the pause is per account, so another account starts from
  /// [SyncStatus.empty] until its own read lands rather than showing the
  /// previous account's mismatch. The bind flow follows the same rule.
  SyncState _emitAccount(AppUser? user, Emitter<SyncState> emit) {
    final (known, flow) = switch (state) {
      SyncSignedIn(user: final shown, :final status, :final flow)
          when shown.uid == user?.uid =>
        (status, flow),
      SyncSignedOut(:final status, :final flow) when user == null => (
        status,
        flow,
      ),
      _ => (SyncStatus.empty, const SyncBindIdle()),
    };
    emit(_stateFor(user, known, flow));
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
    final status = _withEngine(await _readStatus(user));
    if (emit.isDone || !identical(state, shown)) return;
    emit(_stateFor(user, status, _flowOf(shown)));
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

  SyncState _stateFor(
    AppUser? user,
    SyncStatus status, [
    SyncBindFlow flow = const SyncBindIdle(),
  ]) => user == null
      ? SyncSignedOut(status: status, flow: flow)
      : SyncSignedIn(user, status: status, flow: flow);

  static SyncBindFlow _flowOf(SyncState state) => switch (state) {
    SyncSignedIn(:final flow) || SyncSignedOut(:final flow) => flow,
    _ => const SyncBindIdle(),
  };

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _engineSubscription?.cancel();
    return super.close();
  }
}
