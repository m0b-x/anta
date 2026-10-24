import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show InvalidDataException;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../database/crdt/crdt_write.dart';
import '../../database/daos/sync_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../models/app_user.dart';
import '../../models/sync_binding.dart';
import 'sync_apply_hooks.dart';
import 'sync_binding_service.dart';
import 'sync_gateway.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';
import 'sync_status_service.dart';
import 'sync_suspension.dart';
import 'sync_table_binding.dart';
import 'sync_tables.dart';

/// Why a run ended without reaching the space.
enum SyncRunSkip {
  unbound,
  signedOut,
  accountMismatch,

  /// A restore or import holds [SyncSuspension] — at the start of the run or
  /// before one of its pages or batches — or the engine was stopped.
  suspended,

  /// The quota ran out and its retry has not fired yet; a resume or "Sync
  /// now" lifts the hold.
  paused,
  appOutdated,
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

  /// Whether the quota pause still blocks runs: its retry, a resume and
  /// "Sync now" lift it, while [_pause] stays until a call succeeds.
  bool _quotaHeld = false;
  SyncFailureInfo? _lastFailure;
  int _downloadedRows = 0;
  int _backoffStep = 0;

  bool _started = false;
  bool _stopped = false;
  bool _foreground = true;

  StreamSubscription<SyncSpaceSignal>? _signalSubscription;
  SyncSpaceRef? _signalSpace;
  SyncSpaceSignal? _signal;
  StreamSubscription<void>? _outboxSubscription;
  StreamSubscription<AppUser?>? _authSubscription;
  Timer? _debounce;
  Timer? _retry;

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
  /// order.
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
       _tables = tables ?? syncTableBindings;

  static SyncEngine _register(SyncEngine engine) {
    _instance = engine;
    DatabaseLifecycle.registerResetHandler(reset);
    return engine;
  }

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
    _instance = null;
    if (engine != null) unawaited(engine.stop());
  }

  /// Every change of [current], as it happens: the sync settings and
  /// `SyncBloc` render from it.
  Stream<SyncStatus> get status => _statusController.stream;

  /// The last status emitted.
  SyncStatus get current => _current;

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
    if (await _db.syncDao.getValue(SyncDao.keyQuotaPausedAt) != null) {
      _pause = SyncPause.quotaExhausted;
    }
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
    _debounce?.cancel();
    _retry?.cancel();
    _debounce = null;
    _retry = null;
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
  /// user asked, so the space is tried once more. A request during a run is
  /// served by the one run that follows it.
  Future<SyncRunReport> syncNow() {
    _quotaHeld = false;
    return _request(full: true);
  }

  /// The app came back: the signal is followed again and a full run starts
  /// now, skipping whatever back-off or quota wait was pending.
  void onAppResumed() {
    _foreground = true;
    _backoffStep = 0;
    _quotaHeld = false;
    _retry?.cancel();
    _retry = null;
    _track(_reevaluate(run: true));
  }

  /// The app went to the background: the signal is dropped and the outbox
  /// drained now, without the debounce — the process may not live long
  /// enough for it (readiness D19). Completes when the drain has run.
  Future<void> onAppBackgrounded() async {
    _foreground = false;
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
    _detachSignal();
    await _request(full: false);
  }

  // ---------------------------------------------------------------------------
  // Runs

  Future<SyncRunReport> _request({required bool full}) {
    final request = _queued ??= _RunRequest();
    request.full |= full;
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
        request.done.complete(await _run(full: request.full));
      }
    } finally {
      _pumping = false;
      final idle = _idle;
      _idle = null;
      idle?.complete();
    }
  }

  /// One run: the pull — every table when [full], else the tables the
  /// signal says moved — then the drain, so a push never carries a row this
  /// device would have lost to a newer remote a moment later.
  Future<SyncRunReport> _run({required bool full}) async {
    final (binding, skip) = await _gate();
    if (binding == null) {
      if (skip != SyncRunSkip.suspended) _detachSignal();
      _emit();
      return SyncRunReport(skipped: skip);
    }
    final space = _spaceOf(binding);
    if (_started && _foreground) _attachSignal(space);
    final tally = _RunTally();
    final parkedBefore = _parkedCount;
    SyncRunReport report({SyncGatewayFailure? failure, SyncRunSkip? skipped}) =>
        SyncRunReport(
          pulledRows: tally.pulled,
          pushedRows: tally.pushed,
          parked: _parkedCount - parkedBefore,
          failure: failure,
          skipped: skipped,
        );
    try {
      await _puller.pull(
        space,
        full ? _tables : await _staleTables(),
        everyTable: full,
        tally: tally,
      );
      await _pusher.drain(space, binding.accountUid, tally);
      if (tally.calls > 0) await _succeeded();
      return report();
    } on _Halted {
      return report(skipped: SyncRunSkip.suspended);
    } on _AccessLost catch (lost) {
      _recordFailure(lost.cause);
      _loseAccess(lost.pause);
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
    if (_stopped) return (null, SyncRunSkip.suspended);
    final binding = await _binding.read();
    if (binding == null) return (null, SyncRunSkip.unbound);
    final user = _currentUser();
    if (user == null) return (null, SyncRunSkip.signedOut);
    if (user.uid != binding.accountUid) {
      return (null, SyncRunSkip.accountMismatch);
    }
    if (SyncSuspension.isSuspended) return (null, SyncRunSkip.suspended);
    if (_pause == SyncPause.noAccess) return (null, SyncRunSkip.noAccess);
    if (_pause == SyncPause.appOutdated) {
      return (null, SyncRunSkip.appOutdated);
    }
    if (_quotaHeld) return (null, SyncRunSkip.paused);
    return (binding, null);
  }

  SyncSpaceRef _spaceOf(SyncBinding binding) =>
      SyncSpaceRef(ownerUid: binding.ownerUid, spaceId: binding.spaceId);

  /// Thrown between pages and batches once the run must end: a restore took
  /// [SyncSuspension], or the engine was stopped.
  void _checkHalt() {
    if (_stopped || SyncSuspension.isSuspended) throw const _Halted();
  }

  /// The tables whose `touched` moved past their stored `pull_seen` — or
  /// that were never seen — in the latest signal; none before one arrived.
  Future<List<SyncTableBinding<Object>>> _staleTables() async {
    final signal = _signal;
    if (signal == null) return const [];
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

  // ---------------------------------------------------------------------------
  // Outcomes

  /// A call reached the space: the failure, the back-off and a quota pause
  /// are over.
  Future<void> _succeeded() async {
    _lastFailure = null;
    _backoffStep = 0;
    _retry?.cancel();
    _retry = null;
    if (_pause == SyncPause.quotaExhausted) {
      _pause = SyncPause.none;
      await _db.syncDao.deleteValue(SyncDao.keyQuotaPausedAt);
    }
  }

  Future<void> _failed(SyncGatewayException error) async {
    _recordFailure(error);
    switch (error.failure) {
      case SyncGatewayFailure.quotaExhausted:
        _pause = SyncPause.quotaExhausted;
        _quotaHeld = true;
        _detachSignal();
        await _db.syncDao.setValue(
          SyncDao.keyQuotaPausedAt,
          '${DateTime.now().millisecondsSinceEpoch}',
        );
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

  void _recordFailure(SyncGatewayException error) {
    _lastFailure = SyncFailureInfo(
      error.failure,
      at: DateTime.now().toUtc(),
      message: error.message,
    );
  }

  /// Holds sync for [pause] until the next sign-in or launch: nothing is
  /// pulled, pushed or listened to.
  void _loseAccess(SyncPause pause) {
    _pause = pause;
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
    final (binding, skip) = await _gate();
    if (_stopped) return;
    if (binding != null) {
      if (_started && _foreground) _attachSignal(_spaceOf(binding));
      if (run) unawaited(_request(full: true));
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
  Future<void> _drainIfQueued() async {
    if (_stopped || await _db.syncOutboxDao.count() == 0) return;
    await _request(full: false);
  }

  void _attachSignal(SyncSpaceRef space) {
    if (_signalSubscription != null && _signalSpace == space) return;
    _detachSignal();
    _signalSpace = space;
    _signalSubscription = _gateway
        .watchSpace(space)
        .listen(_onSignal, onError: _onSignalError);
  }

  void _detachSignal() {
    final subscription = _signalSubscription;
    _signalSubscription = null;
    _signalSpace = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _onSignal(SyncSpaceSignal signal) {
    if (_stopped) return;
    if (!signal.exists) return _loseAccess(SyncPause.noAccess);
    if (signal.schema > _schema) return _loseAccess(SyncPause.appOutdated);
    _signal = signal;
    unawaited(_request(full: false));
  }

  void _onSignalError(Object error) {
    if (_stopped) return;
    final failure = error is SyncGatewayException
        ? error
        : SyncGatewayException(SyncGatewayFailure.unknown, '$error');
    _recordFailure(failure);
    if (failure.failure == SyncGatewayFailure.permissionDenied) {
      return _loseAccess(SyncPause.noAccess);
    }
    // The retry re-subscribes through _reevaluate.
    _detachSignal();
    _scheduleBackoff();
    _emit();
  }

  // ---------------------------------------------------------------------------
  // Status

  void _setActivity(SyncActivity activity) {
    if (_activity == activity) return;
    _activity = activity;
    _emit();
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
        pause: stored.pause == SyncPause.none ? pause : stored.pause,
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

/// The pull side of a run.
class _Puller {
  final SyncEngine _e;

  /// The envelopes set aside this session, by table and key; a re-delivery
  /// of the same one is not counted twice.
  final Set<(String, String)> parked = {};

  _Puller(this._e);

  /// Pulls [tables] in order. [everyTable] says the run covers the whole
  /// space, which is what ends the initial merge after a bind (D15).
  Future<void> pull(
    SyncSpaceRef space,
    List<SyncTableBinding<Object>> tables, {
    required bool everyTable,
    required _RunTally tally,
  }) async {
    if (tables.isEmpty) return;
    final db = _e._db;
    final initial =
        await db.syncDao.getValue(SyncDao.keyBindMergePending) != null;
    final floor = initial ? await _e._binding.bindFloor() : null;
    final touched = <SyncInvalidation>{};
    _e._setActivity(SyncActivity.pulling);
    try {
      for (final table in tables) {
        await _pullTable(
          space,
          table,
          floor: floor,
          initial: initial,
          touched: touched,
          tally: tally,
        );
      }
    } finally {
      // Pages already applied stay applied, a halted run's included, so the
      // caches hear of them either way.
      if (touched.contains(SyncInvalidation.calendar)) {
        touched.add(SyncInvalidation.alerts);
      }
      if (touched.isNotEmpty) {
        await _e._hooks.afterRun(Set.unmodifiable(touched));
      }
    }
    await db.syncDao.setValue(
      SyncDao.keyLastPullAt,
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    if (initial && everyTable) {
      await db.syncDao.deleteValue(SyncDao.keyBindMergePending);
      _e._downloadedRows = 0;
    }
  }

  Future<void> _pullTable(
    SyncSpaceRef space,
    SyncTableBinding<Object> table, {
    required String? floor,
    required bool initial,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    // Read before the first page: a push landing during the pull moves
    // `touched` past this mark, so the next signal pulls again rather than
    // the table being marked seen up to a write it never read.
    final seenUpTo = _e._signal?.touched[name];
    final stored = await db.syncDao.getValue(SyncDao.keyPullCursor(name));
    var cursor = stored == null ? null : SyncCursor(stored);
    var resumed = true;
    while (true) {
      _e._checkHalt();
      final page = await _e._gateway.pullPage(
        space,
        name,
        after: cursor,
        resumed: resumed,
      );
      tally.calls++;
      resumed = false;
      if (page.envelopes.isEmpty) break;
      await _apply(table, page, floor: floor, touched: touched, tally: tally);
      if (initial) _e._downloadedRows += page.envelopes.length;
      _e._emit();
      cursor = page.next ?? cursor;
      if (!page.hasMore) break;
    }
    if (seenUpTo != null) {
      await db.syncDao.setValue(
        SyncDao.keyPullSeen(name),
        '${seenUpTo.microsecondsSinceEpoch}',
      );
    }
  }

  /// One page in one transaction: the merges, the cursor, the clock stored
  /// once (readiness R5); the hooks after it committed.
  Future<void> _apply(
    SyncTableBinding<Object> table,
    SyncPullPage page, {
    required String? floor,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    await _e._hooks.beforePage(name);
    final rows = <SyncAppliedRow>[];
    final conflicts = <SyncNoteConflict>[];
    await db.transaction(() async {
      for (final envelope in page.envelopes) {
        final MergeOutcome outcome;
        try {
          outcome = await table.mergeRemote(db, envelope, floor: floor);
        } on Object catch (error) {
          if (!_isEnvelopeFault(error)) rethrow;
          _park(envelope, error);
          continue;
        }
        rows.add(
          SyncAppliedRow(
            rowKey: envelope.rowKey,
            result: outcome.result,
            tombstone: isTombstone(envelope),
          ),
        );
        if (outcome.result == MergeResult.inserted ||
            outcome.result == MergeResult.applied) {
          touched.add(table.invalidation);
        }
        final loser = outcome.loser;
        if (loser != null) {
          conflicts.add(
            SyncNoteConflict(
              loser: loser,
              loserContent: outcome.loserContent ?? '',
            ),
          );
        }
      }
      final next = page.next;
      if (next != null) {
        await db.syncDao.setValue(SyncDao.keyPullCursor(name), next.value);
      }
      await db.persistClock();
    });
    tally.pulled += rows.length;
    await _e._hooks.afterPage(name, List.unmodifiable(rows));
    for (final conflict in conflicts) {
      await _e._hooks.fileConflictCopy(conflict);
    }
  }

  /// What one malformed document raises: a missing or mistyped key, a value
  /// a column refuses (drift checks lengths on write), a key that names no
  /// row. Anything else is the database's or the engine's own fault and ends
  /// the run instead.
  static bool _isEnvelopeFault(Object error) =>
      error is FormatException ||
      error is TypeError ||
      error is ArgumentError ||
      error is InvalidDataException;

  void _park(SyncEnvelope envelope, Object error) {
    debugPrint(
      '[SyncEngine] parked ${envelope.table}/${envelope.rowKey}: $error',
    );
    parked.add((envelope.table, envelope.rowKey));
  }
}

/// The push side of a run.
class _Pusher {
  final SyncEngine _e;

  /// The outbox entries set aside this session, retried next launch: one bad
  /// row must not stop every other row (record §3.5).
  final Set<(String, String)> parked = {};

  _Pusher(this._e);

  /// About 900 KB of JSON: under Firestore's 1 MiB document with room for
  /// the envelope's own fields, so an oversized row is parked here rather
  /// than refused for its whole batch.
  static const int maxDocumentBytes = 900000;

  /// More rows than this refused by the rules in one drain means the rules
  /// changed, not the rows (record §3.5).
  static const int maxRefusedPerDrain = 20;

  /// Pushes the outbox in batches, oldest change first, until it is empty or
  /// a call fails.
  Future<void> drain(
    SyncSpaceRef space,
    String boundUid,
    _RunTally tally,
  ) async {
    final outbox = _e._db.syncOutboxDao;
    final maxBatch = _e._gateway.maxBatch;
    // The entry stamp each row was pushed at in this drain: an entry the
    // acknowledgement could not retire at the same stamp is not pushed again
    // until an edit raises it.
    final pushed = <(String, String), String>{};
    final drain = _DrainState();
    while (true) {
      _e._checkHalt();
      final skipped = parked.length + pushed.length;
      final entries = [
        for (final entry in await outbox.pending(limit: maxBatch + skipped))
          if (!parked.contains((entry.syncedTable, entry.rowKey)) &&
              pushed[(entry.syncedTable, entry.rowKey)] != entry.hlc)
            entry,
      ].take(maxBatch).toList();
      if (entries.isEmpty) break;
      _e._setActivity(SyncActivity.pushing);
      final batch = await _prepare(entries, boundUid);
      _e._emit();
      if (batch.isEmpty) continue;
      for (final queued in batch) {
        pushed[(queued.entry.syncedTable, queued.entry.rowKey)] =
            queued.entry.hlc;
      }
      await _push(space, batch, tally, drain);
    }
  }

  /// The batch for [entries]: each row read as it stands now, a tombstone
  /// included. A row gone since it was queued (an import wipe) retires its
  /// entry; one that cannot be encoded or would exceed [maxDocumentBytes]
  /// is parked before the push.
  Future<List<_Queued>> _prepare(
    List<SyncOutboxRow> entries,
    String boundUid,
  ) async {
    final db = _e._db;
    final byTable = <String, List<SyncOutboxRow>>{};
    for (final entry in entries) {
      byTable.putIfAbsent(entry.syncedTable, () => []).add(entry);
    }
    final batch = <_Queued>[];
    for (final MapEntry(key: table, value: group) in byTable.entries) {
      final binding = _e._bindingFor(table);
      final List<Object> rows;
      try {
        if (binding == null) throw ArgumentError.value(table, 'table');
        rows = await binding.loadByKeys(db, [for (final e in group) e.rowKey]);
      } on Object catch (error) {
        if (!_Puller._isEnvelopeFault(error)) rethrow;
        for (final entry in group) {
          _park(entry, error);
        }
        continue;
      }
      final byKey = {for (final row in rows) binding.rowKeyOf(row): row};
      for (final entry in group) {
        final row = byKey[entry.rowKey];
        if (row == null) {
          await db.syncOutboxDao.ackThrough(table, entry.rowKey, entry.hlc);
          continue;
        }
        final SyncEnvelope envelope;
        try {
          envelope = await binding.encode(db, row, boundUid: boundUid);
        } on Object catch (error) {
          _park(entry, error);
          continue;
        }
        final data = envelope.data;
        if (data != null &&
            utf8.encode(jsonEncode(data)).length > maxDocumentBytes) {
          _park(entry, 'over $maxDocumentBytes bytes');
          continue;
        }
        batch.add(_Queued(entry, envelope));
      }
    }
    return batch;
  }

  /// Pushes [batch]; a refusal that would refuse it again — `invalidData`,
  /// or a rule refusal of a row's shape — is narrowed to the refused rows,
  /// which are parked while the rest lands.
  Future<void> _push(
    SyncSpaceRef space,
    List<_Queued> batch,
    _RunTally tally,
    _DrainState drain,
  ) async {
    try {
      await _send(space, batch, tally);
    } on SyncGatewayException catch (error) {
      switch (error.failure) {
        case SyncGatewayFailure.permissionDenied:
          await _diagnose(space, error);
        case SyncGatewayFailure.invalidData:
          break;
        case SyncGatewayFailure.offline:
        case SyncGatewayFailure.quotaExhausted:
        case SyncGatewayFailure.unknown:
          rethrow;
      }
      await _isolate(space, batch, error, tally, drain);
    }
  }

  /// A denied push is believed only after the space is read (record §3.5):
  /// gone or unreadable is `noAccess`, a newer schema is `appOutdated`;
  /// otherwise the rules refused a row, which the caller isolates.
  Future<void> _diagnose(
    SyncSpaceRef space,
    SyncGatewayException denied,
  ) async {
    final SyncSpaceInfo? info;
    try {
      info = await _e._gateway.readSpace(space);
    } on SyncGatewayException catch (error) {
      if (error.failure == SyncGatewayFailure.permissionDenied) {
        throw _AccessLost(SyncPause.noAccess, denied);
      }
      rethrow;
    }
    if (info == null) throw _AccessLost(SyncPause.noAccess, denied);
    if (info.schema > _e._schema) {
      throw _AccessLost(SyncPause.appOutdated, denied);
    }
  }

  /// Bisects [batch] — halves, then single rows — down to the rows refused
  /// with [refusal]'s failure, parks those and pushes the rest.
  Future<void> _isolate(
    SyncSpaceRef space,
    List<_Queued> batch,
    SyncGatewayException refusal,
    _RunTally tally,
    _DrainState drain,
  ) async {
    if (batch.length == 1) {
      _park(batch.single.entry, refusal);
      if (refusal.failure == SyncGatewayFailure.permissionDenied &&
          ++drain.refused > maxRefusedPerDrain) {
        throw _AccessLost(SyncPause.noAccess, refusal);
      }
      return;
    }
    final middle = batch.length ~/ 2;
    for (final half in [batch.sublist(0, middle), batch.sublist(middle)]) {
      try {
        await _send(space, half, tally);
      } on SyncGatewayException catch (error) {
        if (error.failure != refusal.failure) rethrow;
        await _isolate(space, half, error, tally, drain);
      }
    }
  }

  /// One push, then each entry retired at the stamp its row had when read:
  /// an entry an edit raised during the push stays queued.
  Future<void> _send(
    SyncSpaceRef space,
    List<_Queued> batch,
    _RunTally tally,
  ) async {
    _e._checkHalt();
    final db = _e._db;
    await _e._gateway.pushBatch(
      space,
      [for (final queued in batch) queued.envelope],
      pushedBy: _e._deviceId,
      schema: _e._schema,
    );
    tally.calls++;
    await db.transaction(() async {
      for (final queued in batch) {
        await db.syncOutboxDao.ackThrough(
          queued.entry.syncedTable,
          queued.entry.rowKey,
          queued.envelope.hlc,
        );
      }
    });
    tally.pushed += batch.length;
    await db.syncDao.setValue(
      SyncDao.keyLastPushAt,
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    _e._emit();
  }

  void _park(SyncOutboxRow entry, Object reason) {
    debugPrint(
      '[SyncEngine] parked ${entry.syncedTable}/${entry.rowKey}: $reason',
    );
    parked.add((entry.syncedTable, entry.rowKey));
  }
}

class _RunRequest {
  bool full = false;
  final Completer<SyncRunReport> done = Completer<SyncRunReport>();
}

class _RunTally {
  int pulled = 0;
  int pushed = 0;

  /// Gateway calls that succeeded: a run that made none proved nothing about
  /// the space, so it clears no failure and no quota pause.
  int calls = 0;
}

class _DrainState {
  int refused = 0;
}

class _Queued {
  final SyncOutboxRow entry;
  final SyncEnvelope envelope;

  const _Queued(this.entry, this.envelope);
}

class _Halted implements Exception {
  const _Halted();
}

class _AccessLost implements Exception {
  final SyncPause pause;
  final SyncGatewayException cause;

  const _AccessLost(this.pause, this.cause);
}
