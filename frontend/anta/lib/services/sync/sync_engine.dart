import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart'
    show CouldNotRollBackException, InvalidDataException;
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:get_it/get_it.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../../database/crdt/crdt_write.dart';
import '../../database/daos/sync_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../database/migrations/database_schema.dart';
import '../../models/app_user.dart';
import '../../models/sync_binding.dart';
import '../auth_service.dart';
import '../permission_service.dart';
import 'app_sync_apply_hooks.dart';
import 'sync_apply_hooks.dart';
import 'sync_binding_service.dart';
import 'sync_gateway.dart';
import 'sync_lifecycle_bridge.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';
import 'sync_status_service.dart';
import 'sync_suspension.dart';
import 'sync_table_binding.dart';
import 'sync_tables.dart';

part 'sync_puller.dart';
part 'sync_pusher.dart';

/// Why a run ended without reaching the space, or stopped short of it.
enum SyncRunSkip {
  /// The database has no binding — at the start of the run, or it was
  /// unbound (or rebound) before one of its pages or batches, which then
  /// write nothing into it.
  unbound,

  /// No account is signed in; the binding waits for the bound one (D5).
  signedOut,

  /// Another account than the bound one is signed in; its session must not
  /// read or write the bound account's space.
  accountMismatch,

  /// A restore or import holds [SyncSuspension] — at the start of the run or
  /// before one of its pages or batches.
  suspended,

  /// The engine was stopped — a database switch, or the dependencies torn
  /// down — before the run or one of its pages or batches.
  stopped,

  /// The quota ran out and its retry has not fired yet; a resume or "Sync
  /// now" lifts the hold.
  paused,

  /// The space was written by a newer schema than this build's; nothing
  /// runs until the app is updated.
  appOutdated,

  /// The space is gone or no longer readable by this account; nothing runs
  /// until the next sign-in or launch.
  noAccess,
}

/// What one run did, for "Sync now" to report and for the tests to read.
class SyncRunReport extends Equatable {
  /// Envelopes the pull merged, repeats included.
  final int pulledRows;

  /// Rows the space acknowledged.
  final int pushedRows;

  /// Envelopes and rows set aside during this run.
  final int parked;

  /// The failure that ended the run, null when it ran through.
  final SyncGatewayFailure? failure;

  /// Why the run did not reach the space, null when it did.
  final SyncRunSkip? skipped;

  const SyncRunReport({
    this.pulledRows = 0,
    this.pushedRows = 0,
    this.parked = 0,
    this.failure,
    this.skipped,
  });

  @override
  List<Object?> get props => [pulledRows, pushedRows, parked, failure, skipped];
}

/// The engine's delays, in one value so a test can shorten one without
/// restating the rest.
class SyncEngineTiming {
  /// How long the outbox stays quiet before a push: typing a note writes
  /// every few seconds, and one push per burst is one write per row (D19).
  final Duration pushDebounce;

  /// The waits after successive `offline` / `unknown` failures; the last one
  /// repeats. Reset by a success and skipped by a resume.
  final List<Duration> backoff;

  /// How long a `quotaExhausted` pause holds before the engine tries again.
  final Duration quotaRetry;

  const SyncEngineTiming({
    this.pushDebounce = const Duration(seconds: 30),
    this.backoff = const [
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
      Duration(minutes: 10),
    ],
    this.quotaRetry = const Duration(hours: 1),
  });

  Duration _backoffAt(int step) =>
      backoff[step < backoff.length ? step : backoff.length - 1];
}

/// Syncs this database with its space: drains the outbox in batches, pulls
/// the space's rows in arrival order and merges them table by table, follows
/// the space document's signal, and reports a [SyncStatus] (record §3.5).
///
/// It runs only while the database is bound, the bound account is signed
/// in, no restore holds [SyncSuspension] and no pause of its own holds; it
/// checks before every run, page and batch. Its app-facing effects go
/// through [SyncApplyHooks], so it never reaches a service above it.
class SyncEngine {
  static SyncEngine? _instance;

  /// The lifecycle feed of the app's engine, ended with it by [reset].
  static SyncLifecycleBridge? _bridge;

  final AppDatabase _db;
  final SyncGateway _gateway;
  final SyncBindingService _binding;
  final SyncStatusService _statusService;
  final SyncApplyHooks _hooks;
  final String _deviceId;
  final int _schema;
  final AppUser? Function() _currentUser;
  final Stream<AppUser?>? _authChanges;
  final SyncScheduler _scheduler;
  final SyncEngineTiming _timing;
  final List<SyncTableBinding<Object>> _tables;
  final AppLifecycleState? Function()? _lifecycleState;
  late final _Puller _puller = _Puller(this);
  late final _Pusher _pusher = _Pusher(this);

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _current = SyncStatus.empty;
  Future<void> _emits = Future.value();

  SyncActivity _activity = SyncActivity.idle;

  /// The pauses the engine decides: `noAccess`, `appOutdated` and
  /// `quotaExhausted`; the status service decides the account ones.
  SyncPause _pause = SyncPause.none;

  /// Whether one read of the space may lift a `noAccess` pause: a space gone
  /// or unreadable may come back, while rules that refused too many rows are
  /// not disproved by a readable space.
  bool _accessRecheckable = false;

  /// Set by a resume and by "Sync now": the next gate reads the space once
  /// before it believes a `noAccess` pause (record §3.3).
  bool _recheckAccess = false;

  /// Whether the quota pause still blocks runs: its retry, a resume and
  /// "Sync now" lift it, while [_pause] stays until a call succeeds.
  bool _quotaHeld = false;
  SyncFailureInfo? _lastFailure;
  int _downloadedRows = 0;
  int _backoffStep = 0;

  /// The signal's own back-off, apart from the runs': a listener that keeps
  /// failing re-subscribes on it without pulling anything.
  int _signalBackoffStep = 0;

  bool _started = false;
  bool _stopped = false;

  /// Tracked whether or not the engine is started, so a [start] after a
  /// return made while stopped neither cuts every pull nor goes without a
  /// signal (S3d review M4).
  bool _foreground = true;

  /// Whether [_lastFailure] is the signal's: a healthy snapshot clears it,
  /// while a run's failure waits for a run that succeeds.
  bool _failureFromSignal = false;

  /// Moved by every [start] and [stop], so a [start] that a [stop] overtook
  /// during its first await attaches nothing.
  int _startGeneration = 0;

  StreamSubscription<SyncSpaceSignal>? _signalSubscription;
  SyncSpaceRef? _signalSpace;
  SyncSpaceSignal? _signal;
  StreamSubscription<void>? _outboxSubscription;
  StreamSubscription<AppUser?>? _authSubscription;
  Timer? _debounce;
  Timer? _retry;
  Timer? _signalRetry;

  _RunRequest? _queued;
  bool _pumping = false;
  Completer<void>? _idle;

  /// Re-evaluations and debounced drains started by a timer, a resume or an
  /// account change, which may yet request a run: [whenIdle] waits for them.
  final Set<Future<void>> _pending = {};

  /// An engine outside the singleton and the [DatabaseLifecycle] registry —
  /// the two devices of a convergence test each hold one. [schema] is this
  /// build's `DatabaseSchema.currentVersion`, what the space's schema is
  /// compared against; [tables] defaults to every synced table in pull
  /// order. [lifecycleState] reads the app's lifecycle as [start] finds it;
  /// without one, or before the first lifecycle message, the foreground is
  /// what the lifecycle calls tracked.
  SyncEngine.detached({
    required AppDatabase db,
    required SyncGateway gateway,
    required SyncBindingService binding,
    required SyncStatusService status,
    required SyncApplyHooks hooks,
    required String deviceId,
    required int schema,
    required AppUser? Function() currentUser,
    Stream<AppUser?>? authChanges,
    SyncScheduler? scheduler,
    SyncEngineTiming timing = const SyncEngineTiming(),
    List<SyncTableBinding<Object>>? tables,
    AppLifecycleState? Function()? lifecycleState,
  }) : _db = db,
       _gateway = gateway,
       _binding = binding,
       _statusService = status,
       _hooks = hooks,
       _deviceId = deviceId,
       _schema = schema,
       _currentUser = currentUser,
       _authChanges = authChanges,
       _scheduler = scheduler ?? const TimerSyncScheduler(),
       _timing = timing,
       _tables = tables ?? syncTableBindings,
       _lifecycleState = lifecycleState;

  /// Set by DI once it decided the app syncs: every engine [getInstance]
  /// builds then starts itself, the one built after a database switch
  /// included — DI runs once, the [DatabaseLifecycle] reset many times, and
  /// an engine built unstarted would leave the switched database unsynced
  /// until the next launch (S3c review F6).
  static bool autoStart = false;

  /// The app's engine over the active database, built once per database: the
  /// gateway and the identity come from GetIt (global, like the
  /// `AlertScheduler`'s gateway), the database and the sync services from
  /// their own singletons, and the app's lifecycle is bridged in; started,
  /// unawaited, when [autoStart] is set. Throws [StateError] — touching
  /// nothing — when no [SyncGateway] is registered, which DI checks before
  /// calling.
  ///
  /// A database switch landing between its awaits makes it start over once
  /// (S4b-1 review L10): the database it awaited first may be the one being
  /// closed, and an engine registered over it would keep
  /// [_rebuildAfterSwitch] from building the new database's. A second switch
  /// inside the retry throws rather than register anything.
  static Future<SyncEngine> getInstance() => _build(mayRetry: true);

  static Future<SyncEngine> _build({required bool mayRetry}) async {
    final existing = _instance;
    if (existing != null) return existing;
    if (!GetIt.I.isRegistered<SyncGateway>()) {
      throw StateError('SyncGateway is not registered');
    }
    final generation = DatabaseLifecycle.generation;
    final gateway = GetIt.I<SyncGateway>();
    final auth = GetIt.I<AuthService>();
    final db = await AppDatabase.getInstance();
    final binding = await SyncBindingService.getInstance();
    final status = await SyncStatusService.getInstance();
    final raced = _instance;
    if (raced != null) return raced;
    if (DatabaseLifecycle.generation != generation) {
      if (mayRetry) return _build(mayRetry: false);
      throw StateError('the database switched while the engine was built');
    }
    final engine = SyncEngine.detached(
      db: db,
      gateway: gateway,
      binding: binding,
      status: status,
      hooks: AppSyncApplyHooks(),
      deviceId: db.deviceId,
      schema: DatabaseSchema.currentVersion,
      currentUser: () => auth.currentUser,
      authChanges: auth.authStateChanges,
      lifecycleState: () => WidgetsBinding.instance.lifecycleState,
    );
    _bridge = SyncLifecycleBridge(
      engine,
      PermissionService.appLifecycle(),
      initial: WidgetsBinding.instance.lifecycleState,
    );
    _register(engine);
    // Not awaited: the first run reaches the network, and neither the launch
    // nor a database switch waits on it.
    if (autoStart) unawaited(_startLogged(engine));
    return engine;
  }

  static Future<void> _startLogged(SyncEngine engine) async {
    try {
      await engine.start();
    } catch (error, stack) {
      _warn('start failed: $error\n$stack');
    }
  }

  static SyncEngine _register(SyncEngine engine) {
    _instance = engine;
    DatabaseLifecycle.registerResetHandler(reset);
    DatabaseLifecycle.registerSwitchedHandler(_rebuildAfterSwitch);
    return engine;
  }

  /// The switched-to database has opened: with [autoStart] set, build its
  /// engine — which starts itself — rather than waiting for the Sharing
  /// page's bloc to ask for one, which left a switched database unsynced
  /// until that page loaded (S4a review M5).
  static void _rebuildAfterSwitch(AppDatabase _) {
    if (!autoStart || _instance != null) return;
    unawaited(
      getInstance().then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            _warn('rebuild after a database switch failed: $error\n$stack'),
      ),
    );
  }

  /// The singleton, or null while none is built — read without building one.
  @visibleForTesting
  static SyncEngine? get instanceForTesting => _instance;

  /// Makes [engine] the singleton [reset] stops, so a test can prove the
  /// lifecycle contract before DI builds one. Never for app code.
  @visibleForTesting
  static SyncEngine registerForTesting(SyncEngine engine) => _register(engine);

  /// Stops and drops the singleton, so a switched database is never synced
  /// with the previous one's space: the signal, the triggers and the timers
  /// end at once, a run in flight ends before its next page or batch.
  /// Invoked by [DatabaseLifecycle].
  static void reset() {
    final engine = _instance;
    final bridge = _bridge;
    _instance = null;
    _bridge = null;
    if (bridge != null) unawaited(bridge.dispose());
    if (engine != null) unawaited(engine.stop());
  }

  /// Every change of [current], as it happens: the sync settings and
  /// `SyncBloc` render from it.
  Stream<SyncStatus> get status => _statusController.stream;

  /// The last status emitted.
  SyncStatus get current => _current;

  /// Between [start] and [stop]. The lifecycle calls run nothing outside it;
  /// they only track the foreground.
  bool get isStarted => _started;

  /// Completes once no run is active, queued or about to be requested, and
  /// the status of the last one has been emitted.
  Future<void> get whenIdle async {
    while (_pumping || _pending.isNotEmpty) {
      if (_pending.isNotEmpty) await Future.wait(_pending.toList());
      if (_pumping) await _idle!.future;
    }
    await _emits;
  }

  void _track(Future<void> work) {
    _pending.add(work);
    unawaited(work.whenComplete(() => _pending.remove(work)));
  }

  /// Starts following the space: the outbox trigger, the account changes,
  /// the space's signal while runnable — and a full run at once, which is
  /// also the launch's retry of a quota pause kept from the last session.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _stopped = false;
    // An engine built while the app is away has heard no leave (S5 review
    // M7).
    final state = _lifecycleState?.call();
    if (state != null) _foreground = !SyncLifecycleBridge.isLeave(state);
    final generation = ++_startGeneration;
    final quotaPaused =
        await _db.syncDao.getValue(SyncDao.keyQuotaPausedAt) != null;
    if (generation != _startGeneration) return;
    if (quotaPaused) _pause = SyncPause.quotaExhausted;
    unawaited(_outboxSubscription?.cancel());
    unawaited(_authSubscription?.cancel());
    _outboxSubscription = _db.syncOutboxDao.watchQueued().listen(
      (_) => _armDebounce(),
    );
    _authSubscription = _authChanges?.listen(_onAuthChanged);
    await _reevaluate(run: true);
  }

  /// Ends every subscription and timer at once and waits for a run in
  /// flight, which stops before its next page or batch.
  Future<void> stop() async {
    _stopped = true;
    _started = false;
    _startGeneration++;
    _debounce?.cancel();
    _retry?.cancel();
    _signalRetry?.cancel();
    _debounce = null;
    _retry = null;
    _signalRetry = null;
    final cancels = [
      _signalSubscription?.cancel(),
      _outboxSubscription?.cancel(),
      _authSubscription?.cancel(),
    ];
    _signalSubscription = null;
    _outboxSubscription = null;
    _authSubscription = null;
    _signalSpace = null;
    _signal = null;
    for (final cancel in cancels) {
      await cancel;
    }
    await whenIdle;
  }

  /// [stop], then closes [status].
  Future<void> dispose() async {
    await stop();
    await _statusController.close();
  }

  /// Pulls every table, then drains — "Sync now". Lifts a quota hold: the
  /// user asked, so the space is tried once more; a `noAccess` pause is
  /// re-checked with one read of the space. A request during a run is served
  /// by the one run that follows it.
  Future<SyncRunReport> syncNow() {
    _quotaHeld = false;
    _recheckAccess = true;
    return _request(_RunMode.full);
  }

  /// The app came back: the signal is followed again and a full run starts
  /// now, skipping whatever back-off or quota wait was pending, after one
  /// read of the space when a `noAccess` pause holds. Unless started, only
  /// the foreground is noted.
  void onAppResumed() {
    _foreground = true;
    if (!_started) return;
    _backoffStep = 0;
    _signalBackoffStep = 0;
    _quotaHeld = false;
    _recheckAccess = true;
    _retry?.cancel();
    _retry = null;
    _signalRetry?.cancel();
    _signalRetry = null;
    _track(_reevaluate(run: true));
  }

  /// The app went to the background: the signal is dropped and the outbox
  /// drained now, without the debounce — the process may not live long
  /// enough for it (readiness D19). Bounded: the drain pulls nothing, and a
  /// run in flight stops pulling before its next page. Completes when that
  /// drain has run or was skipped — skipped while the initial merge is
  /// pending, which only a full pull may end (record §3.5). Unless started,
  /// only the leave is noted.
  Future<void> onAppBackgrounded() async {
    _foreground = false;
    if (!_started) return;
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
    _signalRetry?.cancel();
    _signalRetry = null;
    _detachSignal();
    await _request(_RunMode.drain);
  }

  // ---------------------------------------------------------------------------
  // Runs

  Future<SyncRunReport> _request(_RunMode mode) {
    final request = _queued ??= _RunRequest();
    if (mode.index > request.mode.index) request.mode = mode;
    _pump();
    return request.done.future;
  }

  /// Single flight: one run at a time, and every request made during it is
  /// served by exactly one run after it.
  void _pump() {
    if (_pumping) return;
    _pumping = true;
    _idle ??= Completer<void>();
    unawaited(_loop());
  }

  Future<void> _loop() async {
    try {
      while (true) {
        final request = _queued;
        if (request == null) break;
        _queued = null;
        request.done.complete(await _run(request.mode));
      }
    } finally {
      _pumping = false;
      final idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }

  /// One run: the pull — every table for [_RunMode.full], the tables the
  /// signal says moved for [_RunMode.stale], none for [_RunMode.drain] — then
  /// the drain, so a push never carries a row this device would have lost to
  /// a newer remote a moment later. A table whose pull failed pushes nothing
  /// in this run, for the same reason.
  ///
  /// While the initial merge is pending every run that pulls pulls
  /// everything, and one whose pull was cut short by a leave — or a
  /// drain-only run — pushes nothing: a push before the floor pull would put
  /// the pre-bind rows over the space, where the floor could never undo it.
  /// A pull that reached every table drains the tables that did not fault,
  /// each pulled in full under the floor, so one table that keeps faulting
  /// does not hold every push (record §3.5, S3d review M3).
  Future<SyncRunReport> _run(_RunMode mode) async {
    final tally = _RunTally();
    final parkedBefore = _parks;
    SyncRunReport report({SyncGatewayFailure? failure, SyncRunSkip? skipped}) =>
        SyncRunReport(
          pulledRows: tally.pulled,
          pushedRows: tally.pushed,
          parked: _parks - parkedBefore,
          failure: failure,
          skipped: skipped,
        );
    try {
      final (binding, skip) = await _gate();
      if (binding == null) {
        if (skip != SyncRunSkip.suspended) _detachSignal();
        return SyncRunReport(skipped: skip);
      }
      if (_started && _foreground) _attachSignal(_spaceOf(binding));
      final initial =
          await _db.syncDao.getValue(SyncDao.keyBindMergePending) != null;
      if (initial && mode == _RunMode.drain) return report();
      final full = initial || mode == _RunMode.full;
      final pulled = await _puller.pull(
        binding,
        full
            ? _tables
            : mode == _RunMode.stale
            ? await _staleTables(_spaceOf(binding))
            : const [],
        initial: initial,
        everyTable: full,
        tally: tally,
      );
      try {
        if (!initial || pulled.reached) {
          await _pusher.drain(binding, tally, skipTables: pulled.failedTables);
        }
      } finally {
        // A leave cut the pull: the drain the leave exists for went first,
        // the caches hear of the pages after it (S3d review L7).
        if (pulled.cut) await _puller.notifyRun(pulled.touched);
      }
      final tableFault = pulled.fault;
      if (tableFault != null) {
        await _failed(tableFault);
        return report(failure: tableFault.failure);
      }
      if (tally.calls > 0) _succeeded();
      return report();
    } on _Halted catch (halted) {
      if (halted.skip != SyncRunSkip.suspended) _detachSignal();
      return report(skipped: halted.skip);
    } on _AccessLost catch (lost) {
      _recordFailure(lost.cause);
      _loseAccess(lost.pause, recheckable: lost.recheckable);
      return report(failure: lost.cause.failure);
    } on SyncGatewayException catch (error) {
      await _failed(error);
      return report(failure: error.failure);
    } catch (error, stack) {
      // A run must never wedge the queue: a local fault is reported as an
      // unknown failure and retried on the back-off like one.
      debugPrint('[SyncEngine] run failed: $error\n$stack');
      final failure = SyncGatewayException(
        SyncGatewayFailure.unknown,
        '$error',
      );
      await _failed(failure);
      return report(failure: failure.failure);
    } finally {
      _activity = SyncActivity.idle;
      _emit();
    }
  }

  /// The binding to sync when the engine may run now, else why not.
  Future<(SyncBinding?, SyncRunSkip?)> _gate() async {
    if (_stopped) return (null, SyncRunSkip.stopped);
    final binding = await _binding.read();
    if (binding == null) return (null, SyncRunSkip.unbound);
    final user = _currentUser();
    if (user == null) return (null, SyncRunSkip.signedOut);
    if (user.uid != binding.accountUid) {
      return (null, SyncRunSkip.accountMismatch);
    }
    if (SyncSuspension.isSuspended) return (null, SyncRunSkip.suspended);
    if (_pause == SyncPause.noAccess && !await _regainsAccess(binding)) {
      return (null, SyncRunSkip.noAccess);
    }
    if (_pause == SyncPause.appOutdated) {
      return (null, SyncRunSkip.appOutdated);
    }
    if (_quotaHeld) return (null, SyncRunSkip.paused);
    return (binding, null);
  }

  /// Whether a `noAccess` pause lifts now: only when a resume or "Sync now"
  /// asked and the pause is one a readable space disproves — then one
  /// [SyncGateway.readSpace]; a space that answers lifts it, a missing one or
  /// any failure keeps it. A transient refusal must not hold sync until the
  /// next sign-in or launch (record §3.3).
  Future<bool> _regainsAccess(SyncBinding binding) async {
    if (!_recheckAccess || !_accessRecheckable) return false;
    _recheckAccess = false;
    try {
      if (await _gateway.readSpace(_spaceOf(binding)) == null) return false;
    } on SyncGatewayException {
      return false;
    }
    _pause = SyncPause.none;
    return true;
  }

  SyncSpaceRef _spaceOf(SyncBinding binding) =>
      SyncSpaceRef(ownerUid: binding.ownerUid, spaceId: binding.spaceId);

  /// Throws [_Halted] between pages and batches once the run must end: the
  /// engine was stopped, a restore took [SyncSuspension], the database is no
  /// longer bound as [bound] (an unbind or a rebind — nothing may land in it
  /// after that), or the bound account is no longer the one signed in.
  /// Cheap enough for every page: one settings read.
  Future<void> _checkHalt(SyncBinding bound) async {
    if (_stopped) throw const _Halted(SyncRunSkip.stopped);
    if (SyncSuspension.isSuspended) throw const _Halted(SyncRunSkip.suspended);
    if (await _binding.read() != bound) {
      throw const _Halted(SyncRunSkip.unbound);
    }
    final user = _currentUser();
    if (user == null) throw const _Halted(SyncRunSkip.signedOut);
    if (user.uid != bound.accountUid) {
      throw const _Halted(SyncRunSkip.accountMismatch);
    }
    // The await above may have spanned a stop or a suspension.
    if (_stopped) throw const _Halted(SyncRunSkip.stopped);
    if (SyncSuspension.isSuspended) throw const _Halted(SyncRunSkip.suspended);
  }

  /// The tables whose `touched` moved past their stored `pull_seen` — or
  /// that were never seen — in the latest signal; every table before one
  /// arrived, since nothing then says which tables are current.
  Future<List<SyncTableBinding<Object>>> _staleTables(
    SyncSpaceRef space,
  ) async {
    final signal = _signalOf(space);
    if (signal == null) return _tables;
    final stale = <SyncTableBinding<Object>>[];
    for (final table in _tables) {
      final touched = signal.touched[table.table];
      if (touched == null) continue;
      final seen = int.tryParse(
        await _db.syncDao.getValue(SyncDao.keyPullSeen(table.table)) ?? '',
      );
      if (seen == null || touched.microsecondsSinceEpoch > seen) {
        stale.add(table);
      }
    }
    return stale;
  }

  SyncTableBinding<Object>? _bindingFor(String table) {
    for (final binding in _tables) {
      if (binding.table == table) return binding;
    }
    return null;
  }

  int get _parkedCount => _puller.parked.length + _pusher.parked.length;

  /// Keys parked this session, counted as they are set aside and never
  /// lowered when one lets go — what a run reports as parked, apart from
  /// [_parkedCount], which shrinks as rows land.
  int _parks = 0;

  // ---------------------------------------------------------------------------
  // Outcomes

  /// Counts a call that reached the space. The first of a run ends a quota
  /// pause and deletes its stored mark whatever pause shows now: the space
  /// answered, so the quota is back (record §3.5, D19).
  Future<void> _reached(_RunTally tally) async {
    if (tally.calls++ > 0) return;
    if (_pause == SyncPause.quotaExhausted) _pause = SyncPause.none;
    await _db.syncDao.deleteValue(SyncDao.keyQuotaPausedAt);
  }

  /// A run's calls all reached the space: the failure and the back-off are
  /// over.
  void _succeeded() {
    _lastFailure = null;
    _failureFromSignal = false;
    _backoffStep = 0;
    _retry?.cancel();
    _retry = null;
  }

  Future<void> _failed(SyncGatewayException error) async {
    _recordFailure(error);
    switch (error.failure) {
      case SyncGatewayFailure.quotaExhausted:
        _pause = SyncPause.quotaExhausted;
        _quotaHeld = true;
        _detachSignal();
        try {
          await _db.syncDao.setValue(
            SyncDao.keyQuotaPausedAt,
            '${DateTime.now().millisecondsSinceEpoch}',
          );
        } catch (error) {
          // The pause holds for this session either way; only the next
          // launch's retry at once is lost.
          _warn('quota pause not stored: $error');
        }
        _scheduleRetry(_timing.quotaRetry, liftsQuota: true);
      case SyncGatewayFailure.permissionDenied:
        // A pull's denial; a push's is diagnosed before it gets here.
        _loseAccess(SyncPause.noAccess);
      case SyncGatewayFailure.offline:
      case SyncGatewayFailure.invalidData:
      case SyncGatewayFailure.unknown:
        _scheduleBackoff();
    }
  }

  void _recordFailure(SyncGatewayException error, {bool signal = false}) {
    _failureFromSignal = signal;
    _lastFailure = SyncFailureInfo(
      error.failure,
      at: DateTime.now().toUtc(),
      message: error.message,
    );
  }

  /// Holds sync for [pause] until the next sign-in or launch — or, when
  /// [recheckable], until a resume or "Sync now" finds the space readable:
  /// nothing is pulled, pushed or listened to.
  void _loseAccess(SyncPause pause, {bool recheckable = true}) {
    _pause = pause;
    _accessRecheckable = recheckable;
    // Only a resume or "Sync now" after this pause asks again.
    _recheckAccess = false;
    _retry?.cancel();
    _retry = null;
    _detachSignal();
    _emit();
  }

  /// The next back-off step, only while in the foreground: in the background
  /// the resume retries at once instead.
  void _scheduleBackoff() {
    if (_stopped || !_foreground) return;
    _scheduleRetry(_timing._backoffAt(_backoffStep++));
  }

  void _scheduleRetry(Duration delay, {bool liftsQuota = false}) {
    _retry?.cancel();
    _retry = _scheduler.schedule(delay, () {
      _retry = null;
      if (liftsQuota) _quotaHeld = false;
      _track(_reevaluate(run: true));
    });
  }

  // ---------------------------------------------------------------------------
  // Triggers

  /// Follows the signal when runnable and drops it otherwise, then reports;
  /// [run] also starts a full run when runnable.
  Future<void> _reevaluate({required bool run}) async {
    if (_stopped) return;
    final SyncBinding? binding;
    final SyncRunSkip? skip;
    try {
      (binding, skip) = await _gate();
    } catch (error) {
      // A closed database: nothing to follow, and a run would fail the same
      // way — it reports the failure when one is asked for.
      debugPrint('[SyncEngine] re-evaluation failed: $error');
      return;
    }
    if (_stopped) return;
    if (binding != null) {
      if (_started && _foreground) _attachSignal(_spaceOf(binding));
      if (run) unawaited(_request(_RunMode.full));
    } else if (skip != SyncRunSkip.suspended) {
      // A suspension keeps the signal: nothing announces its end, and the
      // restore it covers unbinds the database anyway.
      _detachSignal();
    }
    _emit();
  }

  void _onAuthChanged(AppUser? user) {
    // "Until the next sign-in": a fresh account session tries the space
    // again.
    if (user != null && _pause == SyncPause.noAccess) _pause = SyncPause.none;
    _track(_reevaluate(run: true));
  }

  void _armDebounce() {
    if (_stopped) return;
    _debounce?.cancel();
    _debounce = _scheduler.schedule(_timing.pushDebounce, () {
      _debounce = null;
      _track(_drainIfQueued());
    });
  }

  /// The debounced push, skipped when the run that followed the trigger has
  /// already emptied the outbox — a merge's re-queue arms the trigger too.
  /// A closed database ends it quietly: it runs from a timer, where a throw
  /// would surface as an uncaught error through [whenIdle] (S3d review L5).
  Future<void> _drainIfQueued() async {
    try {
      if (_stopped || await _db.syncOutboxDao.count() == 0) return;
    } catch (error) {
      debugPrint('[SyncEngine] debounced drain skipped: $error');
      return;
    }
    await _request(_RunMode.stale);
  }

  void _attachSignal(SyncSpaceRef space) {
    if (_signalSubscription != null && _signalSpace == space) return;
    _detachSignal();
    _signalSpace = space;
    late final StreamSubscription<SyncSpaceSignal> subscription;
    subscription = _gateway
        .watchSpace(space)
        .listen(
          (signal) {
            if (identical(_signalSubscription, subscription)) _onSignal(signal);
          },
          onError: _onSignalError,
          // A stream that ended is not a listener: it is dropped and attached
          // afresh on the signal's back-off, so an idle session does not go
          // deaf until its next edit or resume (S3d review L9).
          onDone: () {
            if (!identical(_signalSubscription, subscription)) return;
            _detachSignal();
            _scheduleSignalRetry();
          },
        );
    _signalSubscription = subscription;
  }

  /// Drops the listener and the snapshot it delivered: a snapshot outlives
  /// neither its listener nor its space, so a stale one never picks the
  /// tables to pull nor writes the `pull_seen` of another space (S3d review
  /// L6).
  void _detachSignal() {
    final subscription = _signalSubscription;
    _signalSubscription = null;
    _signalSpace = null;
    _signal = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// The latest snapshot of [space], null when the listener follows another
  /// space or none.
  SyncSpaceSignal? _signalOf(SyncSpaceRef space) =>
      _signalSpace == space ? _signal : null;

  void _onSignal(SyncSpaceSignal signal) {
    if (_stopped) return;
    if (!signal.exists) return _loseAccess(SyncPause.noAccess);
    if (signal.schema > _schema) return _loseAccess(SyncPause.appOutdated);
    _signal = signal;
    _signalBackoffStep = 0;
    // The listener is healthy again; a run's failure waits for a run.
    if (_failureFromSignal) {
      _lastFailure = null;
      _failureFromSignal = false;
      _emit();
    }
    unawaited(_request(_RunMode.stale));
  }

  void _onSignalError(Object error) {
    if (_stopped) return;
    final failure = error is SyncGatewayException
        ? error
        : SyncGatewayException(SyncGatewayFailure.unknown, '$error');
    _recordFailure(failure, signal: true);
    if (failure.failure == SyncGatewayFailure.permissionDenied) {
      return _loseAccess(SyncPause.noAccess);
    }
    _detachSignal();
    _scheduleSignalRetry();
    _emit();
  }

  /// Re-subscribes after the signal's next back-off step, without a run: a
  /// listener that keeps failing must not cost a full pull per error, and a
  /// snapshot that arrives pulls what moved anyway. Foreground only, like
  /// the runs' back-off.
  void _scheduleSignalRetry() {
    if (_stopped || !_foreground) return;
    _signalRetry?.cancel();
    _signalRetry = _scheduler.schedule(
      _timing._backoffAt(_signalBackoffStep++),
      () {
        _signalRetry = null;
        _track(_reevaluate(run: false));
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Status

  void _setActivity(SyncActivity activity) {
    if (_activity == activity) return;
    _activity = activity;
    _emit();
  }

  /// The one rule for which pause a status shows, used here and by
  /// `SyncBloc` over a refreshed read (S4a review L10): the reader's
  /// [SyncPause.signedOut] / [SyncPause.accountMismatch] win — no user, or
  /// the wrong one, makes any pause the engine stored for the run stale —
  /// otherwise the engine's own [SyncPause.noAccess] /
  /// [SyncPause.appOutdated] / [SyncPause.quotaExhausted]; otherwise none.
  static SyncPause pauseOver({
    required SyncPause read,
    required SyncPause engine,
  }) {
    if (read == SyncPause.signedOut || read == SyncPause.accountMismatch) {
      return read;
    }
    return switch (engine) {
      SyncPause.noAccess ||
      SyncPause.appOutdated ||
      SyncPause.quotaExhausted => engine,
      _ => SyncPause.none,
    };
  }

  /// Emits the stored status overlaid with the engine's own fields, as they
  /// stand now. Serialized, so a slow read never lands after a newer one.
  void _emit() {
    final activity = _activity;
    final pause = _pause;
    final failure = _lastFailure;
    final parked = _parkedCount;
    final downloaded = _downloadedRows;
    _emits = _emits.then((_) async {
      if (_statusController.isClosed) return;
      final SyncStatus stored;
      try {
        stored = await _statusService.read(user: _currentUser());
      } catch (error) {
        debugPrint('[SyncEngine] status not read: $error');
        return;
      }
      final next = stored.copyWith(
        activity: activity,
        pause: pauseOver(read: stored.pause, engine: pause),
        lastFailure: failure,
        clearLastFailure: failure == null,
        parkedCount: parked,
        downloadedRows: downloaded,
      );
      if (next == _current || _statusController.isClosed) return;
      _current = next;
      _statusController.add(next);
    });
  }
}

/// What a run pulls before it drains, weakest first: requests made during a
/// run merge into the strongest of them.
enum _RunMode {
  /// Nothing — the background drain.
  drain,

  /// The tables the latest signal says moved — the signal and the debounce.
  stale,

  /// Every table — a start, a resume, a retry, "Sync now".
  full,
}

class _RunRequest {
  _RunMode mode = _RunMode.drain;
  final Completer<SyncRunReport> done = Completer<SyncRunReport>();
}

/// The engine's warnings: faults a parked row or a failed table hides from
/// the status, which a developer reading the log must still see.
void _warn(String message) => debugPrint('[SyncEngine] warning: $message');

class _RunTally {
  int pulled = 0;
  int pushed = 0;

  /// Gateway calls that succeeded: a run that made none proved nothing about
  /// the space, so it clears no failure and no quota pause.
  int calls = 0;
}

class _DrainState {
  int refused = 0;

  /// Whether this drain already read the space to judge a denial: once is
  /// enough to tell the space's denial from a row's.
  bool diagnosed = false;
}

class _Queued {
  final SyncOutboxRow entry;
  final SyncEnvelope envelope;

  /// The row data's size as JSON, which the batch's byte cap adds up.
  final int bytes;

  const _Queued(this.entry, this.envelope, this.bytes);
}

class _Halted implements Exception {
  /// What the run reports.
  final SyncRunSkip skip;

  const _Halted(this.skip);
}

class _AccessLost implements Exception {
  final SyncPause pause;
  final SyncGatewayException cause;

  /// Whether a readable space disproves the pause; see
  /// [SyncEngine._accessRecheckable].
  final bool recheckable;

  const _AccessLost(this.pause, this.cause, {this.recheckable = true});
}
