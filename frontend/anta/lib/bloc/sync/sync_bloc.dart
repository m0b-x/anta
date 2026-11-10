import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants/sync_limits.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/sync/sync_cadence.dart';
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
  final Duration _engineStopTimeout;

  StreamSubscription<AppUser?>? _authSubscription;
  StreamSubscription<SyncStatus>? _engineSubscription;
  SyncEngine? _followedEngine;

  /// Bumped per [_followEngine], so a slow resolution that a later one
  /// overtook does not subscribe over it.
  int _engineGeneration = 0;

  /// Set for the whole of a bind or stop step, apart from the flow: an
  /// account change mid-step shows the new account's idle flow, and a tap
  /// then must not start a second step over the first (review BA-M5). Every
  /// state goes out stamped with it, so the page holds and draws busy on it
  /// too (final review U-1, U-5).
  bool _stepInFlight = false;

  /// Completed as the step in flight settles, for a sign-in or a sign-out
  /// that waits it out; null between steps.
  Completer<void>? _stepSettled;

  /// The status the last account state carried: the database's binding,
  /// queue and times outlive an account change, a sign-in in flight and a
  /// failed one, so none of them shows a bound database unbound until the
  /// next read lands (final review U-2).
  SyncStatus _known = SyncStatus.empty;

  /// Sign-ins and sign-outs asked for and not yet through: no step starts
  /// before one, or it would start between a step's settle and the deferred
  /// account change's own emit (review RC1-5).
  int _accountChangesPending = 0;

  /// A sign-out given up on that is still running, completing — never
  /// throwing — when it lands; null otherwise. A sign-in waits for it.
  Future<void>? _signOutLanding;

  bool _engineStatusSeen = false;

  /// Set once a read or the engine has put a status on screen, and stamped
  /// on every [SyncSignedIn] as [SyncSignedIn.statusRead]: the account
  /// changes the status carries across are the database's, already read.
  bool _statusRead = false;

  /// Whether a state has carried the engine's own status yet. Before it a
  /// status is the reader's alone, and a pause the engine stored is still to
  /// come: the page does not announce that pause as one that began (review
  /// RC2-4). A getter, not a state field, so no state's equality changes.
  bool get engineStatusSeen => _engineStatusSeen;

  /// The account whose deletion status is followed — the one signed in —
  /// and the last status heard for it: [_put] stamps it on that account's
  /// states only, so another account never shows the last one's deletion.
  StreamSubscription<SyncDeletionStatus>? _deletionSubscription;
  String? _deletionAccount;
  SyncDeletionStatus? _deletion;

  /// For a state a deletion status put up, the state it first re-stamped:
  /// the same account, status and flow with another deletion, so a status
  /// read awaited on that state — or on any re-stamp of it — still lands
  /// (reviews G1, K2).
  final Expando<SyncState> _restampOf = Expando('restamp of');

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
  ///
  /// [engineStopTimeout] bounds each wait on the engine and the sign-out
  /// ([SyncLimits.engineStop]); a parameter so a suite can shorten it.
  SyncBloc({
    required AuthService authService,
    FutureOr<SyncStatusReader> Function()? statusReader,
    Future<SyncEngine?> Function()? engine,
    SyncSpaceService? spaces,
    Duration engineStopTimeout = SyncLimits.engineStop,
  }) : _authService = authService,
       _statusReader = statusReader,
       _engine = engine,
       _spaces = spaces,
       _engineStopTimeout = engineStopTimeout,
       super(const SyncInitial()) {
    on<LoadSyncStatus>(_onLoad);
    on<SignInRequested>(_onSignIn);
    on<SignOutRequested>(_onSignOut);
    on<AuthStateChanged>(_onAuthStateChanged);
    on<RefreshSyncStatus>(_onRefresh);
    on<SyncNowRequested>(_onSyncNow);
    on<SyncCadenceChanged>(_onCadenceChanged);
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
    on<DeleteCloudCopyRequested>(_onDeleteCloudCopy);
    on<FinishDeletingRequested>(_onFinishDeleting);
    on<SyncDeletionStatusChanged>(_onDeletionStatus);
  }

  Future<void> _onLoad(LoadSyncStatus event, Emitter<SyncState> emit) async {
    // The bound service, not the platform gate: DI degrades to the no-op
    // binding when Firebase init failed, and that must read as unavailable
    // rather than a sign-in button that can only ever fail.
    if (!_authService.isAvailable) {
      _put(emit, const SyncUnavailable());
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
      _put(emit, const SyncUnavailable());
      return;
    }

    // Pending until the sign-out it may wait on has landed: the spinner
    // itself refuses a step, the count keeps refusing one past it.
    _accountChangesPending++;
    try {
      await _afterStep();
      if (emit.isDone) return;
      // One sign-in at a time: the spinner hides Retry, and a request that
      // arrives behind it — taps queued while a sign-out was waited out —
      // must not start a Google flow of its own (review RC2b-1).
      if (state is SyncSigningIn) return;
      // Up before the wait, so Retry is hidden while it lasts and a failure
      // after it is a new state with its own snackbar.
      _put(emit, const SyncSigningIn());
      final signedOut = await _afterSignOut();
      if (emit.isDone) return;
      if (!signedOut) {
        _put(emit, const SyncFailure(AuthError.unknown));
        return;
      }
    } finally {
      _accountChangesPending--;
    }
    unawaited(_followEngine());
    try {
      // A null user means the flow was dismissed, which the stream never
      // reports — fall back to the account we already had.
      final user =
          await _authService.signInWithGoogle() ?? _authService.currentUser;
      await _emitStatus(_emitAccount(user, emit), user, emit);
    } on AuthException catch (e) {
      _put(emit, SyncFailure(e.error));
    } catch (_) {
      _put(emit, const SyncFailure(AuthError.unknown));
    }
  }

  Future<void> _onSignOut(
    SignOutRequested event,
    Emitter<SyncState> emit,
  ) async {
    // Pending until the signed-out state (or the failure) is up.
    _accountChangesPending++;
    var pending = true;
    void through() {
      if (!pending) return;
      pending = false;
      _accountChangesPending--;
    }

    try {
      await _afterStep();
      if (emit.isDone) return;
      // A sign-out asked again from its own failure puts the account back up
      // first: a second identical failure would equal the state on screen,
      // and the bloc would drop it — no snackbar, a row that looks dead
      // (review RC3-1).
      if (state case SyncFailure(action: SyncAccountAction.signOut)) {
        _emitAccount(_authService.currentUser, emit);
      }
      try {
        // Bounded: a hung sign-out would hold the pending count, and with it
        // every step, for the page's life (review RC1b-4). Past the limit it
        // fails as a thrown one does, so the user is told and offered a retry
        // rather than left looking at an account still signed in (RC1c-2);
        // the sign-out is kept, for a sign-in to wait out (RC2-2). Both say
        // they are the sign-out's: the user is still signed in.
        final signingOut = _authService.signOut();
        try {
          await signingOut.timeout(_engineStopTimeout);
        } on TimeoutException catch (e, st) {
          debugPrint('[SyncBloc] signing out is taking too long: $e\n$st');
          final stillRunning = signingOut.then<void>(
            (_) {},
            onError: (Object e, StackTrace st) =>
                debugPrint('[SyncBloc] a late sign-out failed: $e\n$st'),
          );
          // A second one given up on while the first still runs: a sign-in
          // waits for both (review RC2b-2).
          final previous = _signOutLanding;
          final landing = previous == null
              ? stillRunning
              : Future.wait([previous, stillRunning]).then<void>((_) {});
          _signOutLanding = landing;
          unawaited(
            landing.whenComplete(() {
              if (identical(_signOutLanding, landing)) _signOutLanding = null;
            }),
          );
          _put(emit, _signOutFailure(AuthError.unknown));
          return;
        }
        final user = _authService.currentUser;
        final shown = _emitAccount(user, emit);
        through();
        await _emitStatus(shown, user, emit);
      } on AuthException catch (e) {
        _put(emit, _signOutFailure(e.error));
      } catch (_) {
        _put(emit, _signOutFailure(AuthError.unknown));
      }
    } finally {
      through();
    }
  }

  SyncFailure _signOutFailure(AuthError error) => SyncFailure(
    error,
    action: SyncAccountAction.signOut,
    user: _authService.currentUser,
  );

  /// Waits out a bind or stop step: a sign-in or a sign-out asked for
  /// meanwhile runs once it has settled — never dropped, never mid-step,
  /// where the step's settle would find another account on screen and the
  /// download's restart prompt would never come (final review U-1).
  Future<void> _afterStep() async {
    while (_stepInFlight) {
      final settled = _stepSettled;
      if (settled == null) return;
      await settled.future;
    }
  }

  /// Waits out a sign-out given up on that is still running, at most
  /// [_engineStopTimeout]: a sign-in that landed first would be signed out
  /// again when it lands (review RC2-2). False while it still runs — the
  /// sign-in fails as the sign-out did rather than run out of order.
  Future<bool> _afterSignOut() async {
    final landing = _signOutLanding;
    if (landing == null) return true;
    try {
      await landing.timeout(_engineStopTimeout);
      return true;
    } on TimeoutException {
      return false;
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

  Future<void> _onRefresh(RefreshSyncStatus event, Emitter<SyncState> emit) =>
      _refresh(emit);

  /// The status read again for the account on screen, shown with [flow] —
  /// the flow on screen when null. A read that failed or timed out keeps the
  /// status on screen; the engine's next emit refreshes it. [onRead] runs
  /// between the read and the emit, so a step's settle can clear its flag
  /// in the same emit that shows its outcome.
  Future<void> _refresh(
    Emitter<SyncState> emit, {
    SyncBindFlow? flow,
    void Function()? onRead,
  }) async {
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
    final read = await _readStatus(user);
    onRead?.call();
    // A failed read keeps the status on screen — unless the flow says the
    // database was switched, which leaves that status the old one's.
    SyncStatus kept(SyncStatus shown) {
      if (read != null) return _withEngine(read);
      if (flow case SyncBindIdle(switchedToDatabase: _?)) {
        return SyncStatus.empty;
      }
      return shown;
    }

    // Re-read after the await: an account change while reading owns the
    // state now, and its own read already carries a status.
    switch (state) {
      case SyncSignedIn(user: final current, flow: final shown, :final status)
          when current == user:
        if (read != null) _statusRead = true;
        _put(
          emit,
          SyncSignedIn(current, status: kept(status), flow: flow ?? shown),
        );
      case SyncSignedOut(flow: final shown, :final status) when user == null:
        if (read != null) _statusRead = true;
        _put(emit, SyncSignedOut(status: kept(status), flow: flow ?? shown));
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
      cadence: engine.cadence,
      activity: engine.activity,
      lastFailure: engine.lastFailure,
      clearLastFailure: engine.lastFailure == null,
      parkedCount: engine.parkedCount,
      heldBack: engine.heldBack,
      downloadedRows: engine.downloadedRows,
      updating: engine.updating,
      updatingSending: engine.updatingSending,
      updatingTotal: engine.updatingTotal,
      clearUpdatingTotal: engine.updatingTotal == null,
      updatingSent: engine.updatingSent,
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
    // The engine's status reaches only an account state: after a failed
    // sign-out the account goes back up first, or the run it starts would
    // never show (review RC3b-1).
    if (state case SyncFailure(action: SyncAccountAction.signOut)) {
      _emitAccount(_authService.currentUser, emit);
    }
    try {
      // The run's progress and outcome arrive through the status stream.
      await (await thunk())?.syncNow();
    } catch (e, st) {
      debugPrint('[SyncBloc] sync now failed: $e\n$st');
    }
  }

  /// The switch flips at once on the status shown — the engine's own emit
  /// then confirms it — and the engine stores and applies the cadence
  /// (record §13). Without an engine the row is never shown: the section
  /// offers it bound only, and a bound database on a build without sync
  /// draws the unavailable row.
  Future<void> _onCadenceChanged(
    SyncCadenceChanged event,
    Emitter<SyncState> emit,
  ) async {
    final previous = _showCadence(emit, event.cadence);
    final engine = await _resolveEngine();
    try {
      if (engine == null) throw StateError('no sync engine to store it');
      await engine.setCadence(event.cadence);
    } catch (e, st) {
      debugPrint('[SyncBloc] the sync cadence was not stored: $e\n$st');
      // Back to what is stored: a flip the engine never took would stand
      // until the next read, promising a cadence the engine does not run.
      if (previous != null && !emit.isDone) _showCadence(emit, previous);
    }
  }

  /// Shows [cadence] on the status of the account state on screen, and
  /// answers the one it replaced — null when the state carries no status
  /// (a sign-in in flight, a failure), where the page holds the switch.
  SyncCadence? _showCadence(Emitter<SyncState> emit, SyncCadence cadence) {
    switch (state) {
      case SyncSignedIn(:final user, :final status, :final flow):
        _put(
          emit,
          SyncSignedIn(
            user,
            status: status.copyWith(cadence: cadence),
            flow: flow,
          ),
        );
        return status.cadence;
      case SyncSignedOut(:final status, :final flow):
        _put(
          emit,
          SyncSignedOut(
            status: status.copyWith(cadence: cadence),
            flow: flow,
          ),
        );
        return status.cadence;
      default:
        return null;
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
        _engineStatusSeen = true;
        _statusRead = true;
        _put(emit, SyncSignedIn(user, status: event.status, flow: flow));
      case SyncSignedOut(:final flow) when current == null:
        _engineStatusSeen = true;
        _statusRead = true;
        _put(emit, SyncSignedOut(status: event.status, flow: flow));
      default:
        break;
    }
  }

  Future<void> _onSyncThisDatabase(
    SyncThisDatabaseRequested event,
    Emitter<SyncState> emit,
  ) async {
    final spaces = _spaces;
    if (spaces == null || _stepRefused) return;
    // A failed sign-out left the user signed in, and the page offers the
    // bind there: the account takes the screen again and the step runs in
    // it, as a stop does from a failure (review RC3-4).
    if (state case SyncFailure(action: SyncAccountAction.signOut)) {
      _emitAccount(_authService.currentUser, emit);
    }
    final shown = state;
    if (shown is! SyncSignedIn || shown.flow.isBusy) return;
    final uid = shown.user.uid;
    // A step like the picker's choices: D1's paths create or bind a space in
    // this same call. The account's older deletions it only requests; they
    // run in the service's background.
    await _step(
      emit,
      uid,
      const SyncBindChecking(),
      () async => switch (await spaces.start(accountUid: uid)) {
        SyncBindStartBound() => const SyncBindIdle(),
        SyncBindStartPick(:final spaces, :final holdsData, :final heldBy) =>
          SyncBindPicking(spaces: spaces, holdsData: holdsData, heldBy: heldBy),
      },
    );
  }

  /// One of the picker's choices, taken only while the picker is up — a
  /// choice from idle or from a failure would bind with no picker on screen
  /// (review BB-L8): [run] answers the database a download switched to, else
  /// null.
  Future<void> _bindChoice(
    Emitter<SyncState> emit,
    Future<String?> Function(SyncSpaceService spaces, String accountUid) run,
  ) async {
    final spaces = _spaces;
    final shown = state;
    if (spaces == null ||
        _stepRefused ||
        shown is! SyncSignedIn ||
        shown.flow is! SyncBindPicking) {
      return;
    }
    final uid = shown.user.uid;
    await _step(
      emit,
      uid,
      const SyncBindBinding(),
      () async => SyncBindIdle(switchedToDatabase: await run(spaces, uid)),
    );
  }

  /// A step is refused while one runs, and while an account change waits to
  /// run after one.
  bool get _stepRefused => _stepInFlight || _accountChangesPending > 0;

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
      case SyncSignedOut(
        flow: SyncBindFailed() || SyncBindIdle(switchedToDatabase: _?),
      ):
        account = null;
      default:
        return;
    }
    _emitFlow(emit, account, const SyncBindIdle());
  }

  /// Whatever the account (D5 A): another account's pause and a sign-out
  /// both keep the binding, and this is the way out of either — after a
  /// failed sign-in too, since an unbind is local and needs no account.
  Future<void> _onStopSyncing(
    StopSyncingRequested event,
    Emitter<SyncState> emit,
  ) async {
    final spaces = _spaces;
    if (spaces == null || _stepRefused) return;
    final String? account;
    switch (state) {
      case SyncSignedIn(:final user, :final flow) when !flow.isBusy:
        account = user.uid;
      case SyncSignedOut(:final flow) when !flow.isBusy:
        account = null;
      // The failure carries no flow to show the stop in: the account the
      // identity reports takes the screen on the last status known, and the
      // step runs in it (final review U-4).
      case SyncFailure():
        final user = _authService.currentUser;
        _put(emit, _stateFor(user, _carried(_known, user)));
        account = user?.uid;
      default:
        return;
    }
    await _step(emit, account, const SyncBindStopping(), () async {
      await spaces.stopSyncing();
      return const SyncBindIdle();
    });
  }

  /// "Delete cloud copy" as a step of the signed-in account — the owner,
  /// the only one the rules let delete. A short one: it ends once the
  /// service has marked the space and unbound, and the emptying goes on in
  /// the service's background run, which [SyncSignedIn.deletion] follows.
  ///
  /// A request [SyncCloudCopyDeletion.canDeleteCloudCopy] refuses runs no
  /// step — no engine stop and start, which would drop its pause and
  /// back-off, for a deletion that can do nothing (review S6). From a failed
  /// sign-out the rule is judged on the account as it would be put back, and
  /// only an allowed request puts it back.
  Future<void> _onDeleteCloudCopy(
    DeleteCloudCopyRequested event,
    Emitter<SyncState> emit,
  ) async {
    final spaces = _spaces;
    if (spaces == null || _stepRefused) return;
    final account = _requestingAccount();
    if (account == null ||
        account.flow.isBusy ||
        !account.status.canDeleteCloudCopy) {
      return;
    }
    if (state is SyncFailure) _emitAccount(account.user, emit);
    await _step(emit, account.user.uid, const SyncBindDeleting(), () async {
      await spaces.deleteCloudCopy();
      return const SyncBindIdle();
    });
  }

  /// "Finish deleting": the account's background run asked for, and no
  /// step — the binding and the engine stay as they are. Asked only with
  /// something pending and no run in flight, judged on the status as last
  /// heard; the run's progress and outcome arrive through the deletion
  /// status, on a failed sign-out as on the account (review K3).
  Future<void> _onFinishDeleting(
    FinishDeletingRequested event,
    Emitter<SyncState> emit,
  ) async {
    final spaces = _spaces;
    if (spaces == null || _stepRefused) return;
    final account = _requestingAccount();
    if (account == null) return;
    final uid = account.user.uid;
    final deletion = _deletionOf(uid);
    if (deletion == null || deletion.pending.isEmpty || deletion.running) {
      return;
    }
    try {
      await spaces.finishPendingDeletions(accountUid: uid);
    } catch (e, st) {
      debugPrint('[SyncBloc] finishing the deletions failed: $e\n$st');
    }
  }

  /// The account a deletion request acts for, with the status and flow it
  /// is judged on: the one on screen, or the one a failed sign-out left
  /// signed in, as [_emitAccount] would put it back. Null otherwise.
  ({AppUser user, SyncStatus status, SyncBindFlow flow})? _requestingAccount() {
    switch (state) {
      case SyncSignedIn(:final user, :final status, :final flow):
        return (user: user, status: status, flow: flow);
      case SyncFailure(action: SyncAccountAction.signOut):
        final user = _authService.currentUser;
        if (user == null) return null;
        return (
          user: user,
          status: _carried(_known, user),
          flow: const SyncBindIdle(),
        );
      default:
        return null;
    }
  }

  /// The service's status for the account followed, into the state on
  /// screen when it carries that account — a failed sign-out's included,
  /// whose row must not freeze until an account state returns (review K3).
  void _onDeletionStatus(
    SyncDeletionStatusChanged event,
    Emitter<SyncState> emit,
  ) {
    final status = event.status;
    // A status of an account no longer followed, still queued.
    if (status.accountUid != _deletionAccount) return;
    _deletion = status;
    final shown = state;
    if (_accountOf(shown) == status.accountUid) {
      _put(emit, shown);
      if (!identical(state, shown)) {
        _restampOf[state] = _restampOf[shown] ?? shown;
      }
    }
  }

  /// Follows [uid]'s deletion status — the account signed in, null for none
  /// — and drops the last one's. It only listens: resuming a deletion is the
  /// service's own, from the app's start.
  void _followDeletions(String? uid) {
    if (uid == _deletionAccount) return;
    unawaited(_deletionSubscription?.cancel());
    _deletionSubscription = null;
    _deletion = null;
    _deletionAccount = uid;
    final spaces = _spaces;
    if (uid == null || spaces == null || isClosed) return;
    _deletionSubscription = spaces.deletionStatusOf(uid).listen(
      (status) {
        if (!isClosed) add(SyncDeletionStatusChanged(status));
      },
      onError: (Object e, StackTrace st) =>
          debugPrint('[SyncBloc] reading the deletion status failed: $e\n$st'),
    );
  }

  /// [uid]'s deletion status as last heard; none for another account.
  SyncDeletionStatus? _deletionOf(String uid) =>
      uid == _deletionAccount ? _deletion : null;

  /// The signed-in account [state] carries — a failed sign-out's too, which
  /// left it signed in — or null.
  static String? _accountOf(SyncState state) => switch (state) {
    SyncSignedIn(:final user) => user.uid,
    SyncFailure(:final user?) => user.uid,
    _ => null,
  };

  /// A step that may change this database's binding, shown as [busy] until
  /// it has settled, then the flow [change] answers — or its failure — in one
  /// emit with the status read after the engine started again, so the page
  /// never shows idle over the binding it left (review BB-M2), nor a failure
  /// over a stale status (BB-L9).
  ///
  /// The engine is stopped before [change]: a page in flight for the old
  /// space would otherwise commit its cursor into the new binding, and the
  /// rows under it would never be pulled (BA-M4). It is started again after
  /// — the pair the engine names for a rebind, rather than "Sync now": a
  /// start drops the previous space's pause, back-off and parked rows, where
  /// a run would keep an `appOutdated` from the space just left. Resolved
  /// again for the start, because a download switches the database and the
  /// engine the switch rebuilt is the one that syncs it. A failed step starts
  /// it only when it was running.
  ///
  /// The page holds until the step settles, with no overall limit (reviews
  /// RC1, RC1b): a service call cannot be cancelled, and a page released
  /// mid-step would let the fresh bloc of a page opened again start a
  /// second step over this one, and a database switch on the Databases page
  /// run under a bind still to land — which would then bind the database
  /// switched to. What bounds the hold is each wait on the engine — resolve,
  /// stop, start — at [_engineStopTimeout], past which the step goes on (the
  /// puller's per-page binding check guards a run still finishing), and the
  /// gateway's own limit per call (final review U-3).
  ///
  /// Run to its end with the bloc closed too, so the engine is never left
  /// stopped; only the emits and the read for them are skipped.
  Future<void> _step(
    Emitter<SyncState> emit,
    String? account,
    SyncBindFlow busy,
    Future<SyncBindFlow> Function() change,
  ) async {
    _stepInFlight = true;
    _stepSettled = Completer<void>();
    try {
      _emitFlow(emit, account, busy);
      final before = await _resolveEngine();
      final wasRunning = before?.isStarted ?? false;
      await _stopEngine(before);
      SyncBindFlow outcome;
      var changed = true;
      try {
        outcome = await change();
      } catch (e, st) {
        outcome = _failed(e, st, deleting: busy is SyncBindDeleting);
        changed = false;
      }
      // The old database's status must not dress the one switched to.
      if (outcome case SyncBindIdle(switchedToDatabase: _?)) {
        _known = SyncStatus.empty;
      }
      if (changed || wasRunning) {
        final after = await _resolveEngine();
        // A rebuilt engine started itself over the switched database before
        // its bind: stopped too, so the start below is a fresh one.
        if (!identical(after, before)) await _stopEngine(after);
        await _startEngine(after);
      }
      if (!isClosed) await _settle(emit, account, outcome);
    } finally {
      // Settled with no emit of its own — another account on screen — the
      // state shown still says a step runs.
      _endStep();
      if (!emit.isDone && state.stepInFlight) _put(emit, state);
    }
  }

  /// Clears the step flag and lets a sign-in or sign-out that waited go.
  void _endStep() {
    _stepInFlight = false;
    final settled = _stepSettled;
    _stepSettled = null;
    settled?.complete();
  }

  /// Stops [engine], logged and never thrown, and given up on after
  /// [_engineStopTimeout]: a run's apply hooks must not hold the step.
  Future<void> _stopEngine(SyncEngine? engine) async {
    if (engine == null) return;
    try {
      await engine.stop().timeout(_engineStopTimeout);
    } catch (e, st) {
      debugPrint('[SyncBloc] stopping the sync engine failed: $e\n$st');
    }
  }

  /// Starts [engine] under the same bound as its stop (review RC1-4).
  Future<void> _startEngine(SyncEngine? engine) async {
    if (engine == null) return;
    try {
      await engine.start().timeout(_engineStopTimeout);
    } catch (e, st) {
      debugPrint('[SyncBloc] restarting the sync engine failed: $e\n$st');
    }
  }

  /// The engine a step stops and starts, or null — logged, never thrown, and
  /// given up on after [_engineStopTimeout] (review RC1-4): the step must
  /// still settle without one.
  Future<SyncEngine?> _resolveEngine() async {
    final thunk = _engine;
    if (thunk == null) return null;
    try {
      return await thunk().timeout(_engineStopTimeout);
    } catch (e, st) {
      debugPrint('[SyncBloc] the sync engine is unavailable: $e\n$st');
      return null;
    }
  }

  /// [flow] shown with the status read again, while the account on screen is
  /// still [account]'s: an account that changed mid-step owns the screen, and
  /// its own read already carries a status. A download's switch is shown
  /// whatever the account: the app now runs on another database, and only
  /// the restart prompt this flow raises says so (final review U-1).
  Future<void> _settle(
    Emitter<SyncState> emit,
    String? account,
    SyncBindFlow flow,
  ) async {
    final ours = switch (state) {
      SyncSignedIn(:final user) => user.uid == account,
      SyncSignedOut() => account == null,
      _ => false,
    };
    final switched = flow is SyncBindIdle && flow.switchedToDatabase != null;
    if (ours || switched) await _refresh(emit, flow: flow, onRead: _endStep);
  }

  /// [flow] into the account state on screen, while it is still [account]'s
  /// — null for signed out. An account that changed meanwhile owns the
  /// screen, and the flow it starts from is idle.
  void _emitFlow(Emitter<SyncState> emit, String? account, SyncBindFlow flow) {
    if (emit.isDone) return;
    switch (state) {
      case SyncSignedIn(:final user, :final status) when user.uid == account:
        _put(emit, SyncSignedIn(user, status: status, flow: flow));
      case SyncSignedOut(:final status) when account == null:
        _put(emit, SyncSignedOut(status: status, flow: flow));
      default:
        break;
    }
  }

  /// Every state goes out through here: stamped with the step flag and,
  /// wherever it carries the signed-in account, with its deletion status; an
  /// account state's status kept as the last one known. The deletion status
  /// followed is the account's the state carries — a sign-in in flight or a
  /// failed sign-in keeps the one followed until an account state settles
  /// it.
  void _put(Emitter<SyncState> emit, SyncState next) {
    _followDeletions(switch (next) {
      SyncSignedIn() || SyncFailure(user: _?) => _accountOf(next),
      SyncSignedOut() || SyncUnavailable() => null,
      _ => _deletionAccount,
    });
    var stamped = next.withStepInFlight(_stepInFlight);
    switch (stamped) {
      case final SyncSignedIn signedIn:
        stamped = signedIn
            .withStatusRead(_statusRead)
            .withDeletion(_deletionOf(signedIn.user.uid));
      case final SyncFailure failure when failure.user != null:
        stamped = failure.withDeletion(_deletionOf(failure.user!.uid));
      default:
        break;
    }
    if (stamped
        case SyncSignedIn(:final status) || SyncSignedOut(:final status)) {
      _known = status;
    }
    emit(stamped);
  }

  SyncBindFailed _failed(
    Object error,
    StackTrace stack, {
    bool deleting = false,
  }) {
    if (error is SyncSpaceException) {
      return SyncBindFailed(
        error.failure,
        holderDatabase: error.holderDatabase,
        deleting: deleting,
      );
    }
    debugPrint('[SyncBloc] binding failed: $error\n$stack');
    return SyncBindFailed(SyncBindFailure.unknown, deleting: deleting);
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
  /// whole while the user is the same one. Another account — or the first
  /// after a sign-in in flight or a failed one — gets the database's half of
  /// the last status known, its pause recomputed for that account, until its
  /// own read lands: a bound database never draws unbound in between, and
  /// the previous account's mismatch is never shown for the next (final
  /// review U-2). The bind flow is carried only for the same account.
  SyncState _emitAccount(AppUser? user, Emitter<SyncState> emit) {
    final (known, flow) = switch (state) {
      SyncSignedIn(user: final shown, :final status, :final flow)
          when shown.uid == user?.uid =>
        (status, flow),
      SyncSignedOut(:final status, :final flow) when user == null => (
        status,
        flow,
      ),
      _ => (_carried(_known, user), const SyncBindIdle()),
    };
    _put(emit, _stateFor(user, known, flow));
    return state;
  }

  /// [status] as [user] would read it: the binding, the queue, the times and
  /// the last failure belong to the database and stay; the pause is the
  /// account's, recomputed by the engine's one precedence rule from the
  /// binding — a pause the engine stored stays only under no account pause.
  static SyncStatus _carried(SyncStatus status, AppUser? user) =>
      status.copyWith(
        pause: SyncEngine.pauseOver(
          read: SyncPause.forAccount(status.binding, user?.uid),
          engine: status.pause,
        ),
      );

  /// Adds the status to [shown] once it is read, unless the state moved on
  /// meanwhile: a sign-in handled during the read owns the state, and the
  /// read's stale account must not overwrite it. A deletion status is no
  /// such move — it only re-stamps [shown] — so the read lands on the state
  /// as it left it, however many statuses came, and whether [shown] was
  /// itself a re-stamp (review K2): the two states' origins are compared.
  /// A read that failed leaves the status [shown] carries.
  Future<void> _emitStatus(
    SyncState shown,
    AppUser? user,
    Emitter<SyncState> emit,
  ) async {
    final read = await _readStatus(user);
    final current = state;
    final stillShown = identical(
      _restampOf[current] ?? current,
      _restampOf[shown] ?? shown,
    );
    if (read == null || emit.isDone || !stillShown) return;
    _statusRead = true;
    _put(emit, _stateFor(user, _withEngine(read), _flowOf(shown)));
  }

  /// A reader that fails or stalls never breaks the state: null, and the
  /// account keeps the status last known. Without a reader nothing is ever
  /// known, so [SyncStatus.empty].
  Future<SyncStatus?> _readStatus(AppUser? user) async {
    final reader = _statusReader;
    if (reader == null) return SyncStatus.empty;
    try {
      return await Future.sync(
        () async => (await reader()).read(user: user),
      ).timeout(statusTimeout);
    } catch (e, st) {
      debugPrint('[SyncBloc] reading the sync status failed: $e\n$st');
      return null;
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
    _deletionSubscription?.cancel();
    _deletionSubscription = null;
    return super.close();
  }
}
