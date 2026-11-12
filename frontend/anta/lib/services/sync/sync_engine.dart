import 'dart:async';

import 'package:drift/drift.dart'
    show CouldNotRollBackException, InvalidDataException, UpdateKind, Variable;
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, listEquals, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:get_it/get_it.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../../constants/app_version.dart';
import '../../constants/json_keys.dart';
import '../../database/chunking/content_chunker.dart';
import '../../database/crdt/crdt_merge.dart';
import '../../database/crdt/crdt_write.dart';
import '../../database/crdt/hlc.dart';
import '../../database/crdt/synced_tables.dart';
import '../../database/daos/shared_row_dao.dart';
import '../../database/daos/sync_dao.dart';
import '../../database/daos/sync_outbox_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../database/migrations/database_schema.dart';
import '../../models/app_user.dart';
import '../../models/sync_binding.dart';
import '../auth_service.dart';
import '../permission_service.dart';
import '../pairing_gateway.dart';
import '../settings_service.dart';
import 'app_sync_apply_hooks.dart';
import 'share_partner_source.dart';
import 'sync_apply_hooks.dart';
import 'sync_binding_service.dart';
import 'sync_cadence.dart';
import 'sync_gateway.dart';
import 'sync_lifecycle_bridge.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';
import 'sync_status_service.dart';
import 'sync_suspension.dart';
import 'sync_table_binding.dart';
import 'sync_tables.dart';
import 'tables/content_chunks_binding.dart';
import 'tables/folders_binding.dart';
import 'tables/notes_binding.dart';

part 'sync_puller.dart';
part 'sync_pusher.dart';
part 'sync_shared_reader.dart';

/// Why a run ended without reaching the space, or stopped short of it.
enum SyncRunSkip {
  /// The database has no binding — at the start of the run, or it was
  /// unbound before one of its pages or batches, which then write nothing
  /// into it.
  unbound,

  /// The database was bound again — to another space, or anew to the same
  /// one — after the run began, and the run stopped before its next page or
  /// batch: what it read belongs to a binding that is no longer this
  /// database's (review X-10).
  rebound,

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

  /// The space is no longer readable by this account; nothing runs until
  /// the next sign-in or launch.
  noAccess,

  /// The space was marked for deletion or is gone; it holds as [noAccess]
  /// does.
  spaceDeleted,

  /// The initial merge is still pending and the run pulls nothing — the
  /// background drain: a push before the floor pull would put the pre-bind
  /// rows over the space (record §3.5).
  initialMergePending,

  /// The cadence is [SyncCadence.manual] and nobody asked: a leave drains
  /// nothing, a snapshot's or a timer's run queued before the switch reaches
  /// nothing; only "Sync now" and the bind's first merge run (record §13).
  manual,
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

  /// The size of the acknowledged rows' data as UTF-8 JSON — what the run
  /// cost in upload, for the Spark budget (scalability record S9). There is
  /// no pulled counterpart: the gateway hands over decoded maps, and sizing
  /// them would encode every pulled row a second time.
  final int pushedBytes;

  /// Pull pages read, empty ones included: one document read each at least.
  final int pages;

  /// Push calls made, refused and failed ones included.
  final int pushAttempts;

  /// Resumes and starts whose snapshot did not come in time, so this run
  /// pulled every table instead of the ones a snapshot named.
  final int resumeFallbacks;

  /// How long the run took, gate to status.
  final Duration duration;

  const SyncRunReport({
    this.pulledRows = 0,
    this.pushedRows = 0,
    this.parked = 0,
    this.failure,
    this.skipped,
    this.pushedBytes = 0,
    this.pages = 0,
    this.pushAttempts = 0,
    this.resumeFallbacks = 0,
    this.duration = Duration.zero,
  });

  /// The outcome only: the counters measure a run, and two runs that did
  /// the same thing are equal however long they took.
  @override
  List<Object?> get props => [pulledRows, pushedRows, parked, failure, skipped];
}

/// The engine's delays, in one value so a test can shorten one without
/// restating the rest.
class SyncEngineTiming {
  /// How long the outbox stays quiet before a push: typing a note writes
  /// every few seconds, and one push per burst is one write per row (D19).
  final Duration pushDebounce;

  /// The longest a write waits for its push while writes keep coming, from
  /// the first write after the last drain: an hour of typing never goes
  /// quiet for [pushDebounce], and would otherwise push nothing for the hour
  /// (scalability record S7, D10).
  final Duration pushMaxWait;

  /// The waits after successive `offline` / `unknown` failures; the last one
  /// repeats. Reset by a success and skipped by a resume.
  final List<Duration> backoff;

  /// How long a `quotaExhausted` pause holds before the engine tries again.
  final Duration quotaRetry;

  const SyncEngineTiming({
    this.pushDebounce = const Duration(seconds: 30),
    this.pushMaxWait = const Duration(minutes: 3),
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

  /// How long a resume waits for the space's first snapshot before it pulls
  /// every table: the snapshot names the tables that moved, and without one
  /// nothing says which are current.
  static const Duration resumeSnapshotWait = Duration(seconds: 5);

  /// How old the last pull of every table may grow before a resume pulls
  /// every table again rather than only the ones a snapshot names — the
  /// bound on anything a missed or misread snapshot left behind.
  static const Duration fullPullInterval = Duration(hours: 24);

  /// How long the rows a partner shares are not read again unasked
  /// ([_SharedReader]). Nothing signals a partner's change — this account
  /// cannot read the other's space document — so the read is a poll, and
  /// each one costs the pair, a page and a count per shareable table: about
  /// a dozen document reads, more with the rules' own lookups. Five minutes
  /// keeps a day of opening the app well inside a free tier's reads; "Sync
  /// now" reads at once.
  static const Duration sharedReadInterval = Duration(minutes: 5);

  /// How many of the gateway's [SyncGateway.resumeOverlap]s the server clock
  /// must stand past a table's cursor, as a pull begins, for the pull to mark
  /// the table settled. The overlap is the receive-to-commit bound the record
  /// states (§3.3), and a re-read covers a commit later than it only until a
  /// later write moves the cursor; a skipped re-read would miss it for good,
  /// so the skip asks for a wide margin over the bound, not the bound itself.
  static const int settledOverlaps = 6;

  /// How long after the quota's reset the retry waits: the reset is the
  /// server's, and a retry a moment early would be refused once more.
  static const Duration quotaResetMargin = Duration(minutes: 5);

  /// The least time between the starts of two pushes when the first was cut
  /// by bytes: every push also writes the space document, whose sustained
  /// write rate is about one a second (A8 review R97), and the part budget
  /// cuts parts far smaller than the 499-row count cut (scalability record
  /// S10).
  static const Duration minPartSpacing = Duration(seconds: 1);

  /// What a table's pull page is divided by after a timeout: a page that
  /// outlasted the deadline would outlast it again (scalability record S10).
  static const int pullTimeoutDivisor = 2;

  /// The divisor for a second timeout in a row: halving alone takes too
  /// many runs, each a 60 s wait and a back-off, to reach a page the link
  /// carries.
  static const int repeatedPullTimeoutDivisor = 4;

  /// How many stored pull parks a start retries, one document read each,
  /// when the build has not changed since they were last retried: a build
  /// that could not read a document yesterday mostly cannot today, so a few
  /// a launch keeps the retry cheap while each still comes round
  /// (scalability record S8).
  static const int maxParkRetries = 100;

  /// The most chunk text, in code units, one pull page of notes may read
  /// from the space and hold before its transaction, counted as its missing
  /// chunks times the cutter's largest ([ContentChunker.maxCodeUnits]) — an
  /// upper bound, since the size of a chunk is not known before it is read.
  /// A page over it is halved and pulled again from the same cursor, down
  /// to one note, which pulls whatever its size (scalability record S6).
  static const int chunkFetchBudget = 16 * 1024 * 1024;

  /// The most body text, in code units, one transaction of a notes pull
  /// stores: a page whose bodies to store add up past it is committed in
  /// parts ([_Puller._apply]). Drift's executor is exclusive during a
  /// transaction, so every query of the browser and the calendar waits for
  /// the page in flight; with the bodies cut and encoded before it, what is
  /// left is writing their chunk rows, and a page of fifty 300 KB notes
  /// held them for seconds on a phone. 2 MiB keeps one wait to a fraction
  /// of a second there, and costs a page of ordinary notes nothing: it is
  /// one part, as before.
  static const int pullBodyBudget = 2 * 1024 * 1024;

  /// What this build stores beside its pull parks: the app's version and the
  /// wire's, since a change to either may teach the decoders a document
  /// they refused.
  static const String build =
      '$kAppVersion+${DatabaseSchema.syncSchemaVersion}';

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

  /// The tables a run pulls: [_tables] but the push-only ones.
  late final List<SyncTableBinding<Object>> _pulledTables = [
    for (final table in _tables)
      if (table.pulls) table,
  ];
  final AppLifecycleState? Function()? _lifecycleState;

  /// The wall clock the quota retry and the full-pull age are read from — a
  /// seam, so a test pins them on either side of the quota's reset.
  final DateTime Function() _now;

  /// The build the stored pull parks are compared against at a start
  /// ([build]) — a seam, so a test can change builds between two starts.
  final String Function() _runningBuild;
  late final _Puller _puller = _Puller(this);
  late final _Pusher _pusher = _Pusher(this);
  late final _SharedReader _shared = _SharedReader(this);

  /// Who the bound account is paired with; null for an engine that reads
  /// nothing another account shares.
  final SharePartnerSource? _partners;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _current = SyncStatus.empty;
  Future<void> _emits = Future.value();

  /// Whether an outbox write's emit is queued behind [_emits] and not begun:
  /// a later write joins it, so a burst of auto-saves under the manual
  /// cadence reads the status once per emit in flight, not once per write
  /// (review K5).
  bool _outboxEmitQueued = false;

  SyncActivity _activity = SyncActivity.idle;

  /// The pauses the engine decides: `noAccess`, `spaceDeleted`,
  /// `appOutdated` and `quotaExhausted`; the status service decides the
  /// account ones.
  SyncPause _pause = SyncPause.none;

  /// Whether one read of the space may lift a `noAccess` or `spaceDeleted`
  /// pause: a space gone or unreadable may come back, while rules that
  /// refused too many rows are not disproved by a readable space.
  bool _accessRecheckable = false;

  /// Set by a resume and by "Sync now": the next gate reads the space once
  /// before it believes a `noAccess` or `spaceDeleted` pause (record §3.3).
  bool _recheckAccess = false;

  /// Whether the gate of the run in flight lifted a pause on a read of the
  /// space it made ([_regainsAccess]): under the manual cadence that read
  /// is the run's look at the space, never a second one ([_confirmSpace]).
  bool _spaceReadByGate = false;

  /// The pair the space's document named, and the device that last wrote
  /// it, when the run in flight read the space itself — the gate's read or
  /// the manual cadence's — and null when it read none: what
  /// [_settleSpaceShare] goes by where no snapshot is held.
  ({String? pair, String? writer})? _spaceShareRead;

  /// Whether the quota pause still blocks runs: its retry, a resume and
  /// "Sync now" lift it, while [_pause] stays until a call succeeds.
  bool _quotaHeld = false;
  SyncFailureInfo? _lastFailure;
  int _downloadedRows = 0;

  /// Whether the run in flight cut over to this build's wire and is reading
  /// every note again ([_cutOverWire]), then sending the notes that re-read
  /// left queued; [SyncStatus.updating].
  bool _updating = false;

  /// Whether that run's drain has begun; [SyncStatus.updatingSending].
  bool _updatingSending = false;

  /// The live notes as that re-read began, then the notes queued as its
  /// drain began; [SyncStatus.updatingTotal].
  int? _updatingTotal;

  /// The notes that drain has pushed so far; [SyncStatus.updatingSent].
  int _updatingSent = 0;
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

  /// When the engine runs unasked, as stored for this database and read at
  /// every [start]; [setCadence] changes it mid-session (record §13).
  SyncCadence _cadence = SyncCadence.automatic;

  /// Whether the engine may run unasked now: every trigger but "Sync now"
  /// and the bind's own first merge asks this first.
  bool get _autoRuns => _cadence == SyncCadence.automatic;

  /// Whether a leave cut a pull the user asked for under the manual cadence:
  /// nothing continues it on its own there, so the return runs it to its
  /// end — what the user pressed for.
  bool _resumeOwed = false;

  /// The account the engine follows, as of [start] and of every account
  /// change it acted on. The auth stream replays the current account to a
  /// new listener (the `AuthService` contract), and before this the replay
  /// was taken for a change and requested a full run beside the start's own
  /// — every launch pulled every table, quiet start or not (review
  /// 2026-11-09, record §13).
  String? _followedUid;

  /// Whether a snapshot arrived since the last run began: only then may a
  /// run that found no table stale stamp the last pull — offline, the
  /// listener keeps its last server snapshot, which says nothing about now.
  bool _signalFresh = false;

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

  /// Armed by the first write after a drain, beside [_debounce]: fires the
  /// drain [SyncEngineTiming.pushMaxWait] later however the writes go on.
  /// A drain cancels both.
  Timer? _maxWait;

  /// Whether the run in flight is pulling and drains next: a push timer that
  /// fires meanwhile — the longest wait during the debounce's own run — is
  /// served by that drain, and a run queued behind it would only pull again
  /// and re-send what the drain could not retire.
  bool _drainAhead = false;

  /// Whether a push timer fired while [_drainAhead] and left its drain to
  /// the run in flight: a run that then ends with no drain — a suspension,
  /// an initial merge cut short — arms the debounce again, or the write
  /// that armed it would wait for the next write.
  bool _drainSwallowed = false;
  Timer? _retry;
  Timer? _signalRetry;

  /// Armed by a resume that waits for the space's snapshot; the snapshot
  /// cancels it, and if it fires first every table is pulled.
  Timer? _resumeFallback;

  /// Fallbacks fired since the last run began, reported by the next one.
  int _resumeFallbacks = 0;

  /// The highest server time stored as `server_seen`, in microseconds, so a
  /// snapshot that does not raise it writes nothing; read on [start].
  int? _serverSeen;

  _RunRequest? _queued;
  bool _pumping = false;
  Completer<void>? _idle;

  /// Re-evaluations and debounced drains started by a timer, a resume or an
  /// account change, which may yet request a run: [whenIdle] waits for them.
  final Set<Future<void>> _pending = {};

  /// An engine outside the singleton and the [DatabaseLifecycle] registry —
  /// the two devices of a convergence test each hold one. [schema] is this
  /// build's `DatabaseSchema.syncSchemaVersion`, what the space's schema is
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
    DateTime Function() now = DateTime.now,
    String Function()? build,
    SharePartnerSource? partners,
  }) : _now = now,
       _partners = partners,
       _runningBuild = build ?? (() => SyncEngine.build),
       _db = db,
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
      schema: DatabaseSchema.syncSchemaVersion,
      currentUser: () => auth.currentUser,
      authChanges: auth.authStateChanges,
      lifecycleState: () => WidgetsBinding.instance.lifecycleState,
      partners: GetIt.I.isRegistered<PairingGateway>()
          ? PairingSharePartnerSource(
              gateway: GetIt.I<PairingGateway>(),
              settings: SettingsService.getInstance,
            )
          : null,
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

  /// The schema this engine reports to the space; the suites build engines
  /// with their own, so only this getter shows what [getInstance] passes.
  @visibleForTesting
  int get schemaForTesting => _schema;

  /// Stops and drops the singleton, so a switched database is never synced
  /// with the previous one's space: the signal, the triggers and the timers
  /// end at once, a run in flight ends before its next page or batch.
  /// Invoked by [DatabaseLifecycle].
  ///
  /// [stop], never [dispose]: `SyncBloc` follows [status] across a database
  /// switch and has no signal to re-subscribe on, so closing the controller
  /// here would leave it following a stream that is done. The dropped
  /// engine's controller therefore outlives it — one per switch, emitting
  /// nothing more once stopped (A5 review R105).
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
  /// the space's signal while runnable — and a run at once. A quiet start
  /// — no quota pause kept from the last session — runs as a quiet resume
  /// does: it waits for the signal's first snapshot and pulls only the
  /// tables it names, every table when none comes within
  /// [resumeSnapshotWait], when the last full pull is [fullPullInterval]
  /// old, when the bind's first merge is pending or when stored parks are
  /// owed a retry (record §13); a start under a quota pause runs in full at
  /// once, the launch's retry of that pause. Under [SyncCadence.manual]
  /// only the bind's first merge runs.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _stopped = false;
    // Nothing of the last session's run survives a start: a stop and a start
    // — the pair a rebind makes — must not meet the new space holding the
    // old one's pause, quota hold, back-off, failure or parked keys, which
    // `appOutdated` had no in-session exit from at all (A2 review R45).
    _pause = SyncPause.none;
    _accessRecheckable = false;
    _quotaHeld = false;
    _lastFailure = null;
    _failureFromSignal = false;
    _backoffStep = 0;
    _signalBackoffStep = 0;
    _downloadedRows = 0;
    _puller.resetParks();
    _pusher.resetParks();
    _retryEveryPark = false;
    _puller.resetSizes();
    _pusher.resetSizes();
    // An engine built while the app is away has heard no leave (S5 review
    // M7).
    final state = _lifecycleState?.call();
    if (state != null) _foreground = !SyncLifecycleBridge.isLeave(state);
    _resumeOwed = false;
    final generation = ++_startGeneration;
    final quotaPaused =
        await _db.syncDao.getValue(SyncDao.keyQuotaPausedAt) != null;
    final serverSeen = int.tryParse(
      await _db.syncDao.getValue(SyncDao.keyServerSeen) ?? '',
    );
    final cadence = await _binding.cadence();
    if (generation != _startGeneration) return;
    _serverSeen = serverSeen;
    _cadence = cadence;
    if (quotaPaused) _pause = SyncPause.quotaExhausted;
    unawaited(_outboxSubscription?.cancel());
    unawaited(_authSubscription?.cancel());
    _outboxSubscription = _db.syncOutboxDao.watchQueued().listen(
      (_) => _armDebounce(),
    );
    _followedUid = _currentUser()?.uid;
    _authSubscription = _authChanges?.listen(_onAuthChanged);
    await _reevaluate(run: true, resume: _pause == SyncPause.none);
  }

  /// Ends every subscription and timer at once and waits for a run in
  /// flight, which stops before its next page or batch.
  Future<void> stop() async {
    _stopped = true;
    _started = false;
    _startGeneration++;
    _cancelPushTimers();
    _retry?.cancel();
    _signalRetry?.cancel();
    _resumeFallback?.cancel();
    _pusher.cancelSpacing();
    _retry = null;
    _signalRetry = null;
    _resumeFallback = null;
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
  /// user asked, so the space is tried once more; a `noAccess` or
  /// `spaceDeleted` pause is re-checked with one read of the space. A
  /// request during a run is served by the one run that follows it.
  ///
  /// The parks are tried again on the way, as a start tries them: the
  /// [maxParkRetries] oldest of the pull's and of the push's, every one
  /// under a new build, so one press re-reads at most that many documents
  /// and re-sends at most that many rows however many are held; the user
  /// asked, and the page lists them (scalability record S7).
  Future<SyncRunReport> syncNow() {
    _liftQuotaHold();
    _recheckAccess = true;
    _retryEveryPark = true;
    return _request(_RunMode.full, asked: true);
  }

  /// Set by [syncNow] and taken by the next run as it starts, never during
  /// one: a drain in flight reads the push's parks as it bisects.
  bool _retryEveryPark = false;

  /// When the engine runs unasked, as it stands now.
  SyncCadence get cadence => _cadence;

  /// Stores [next] for this database and applies it to the session (record
  /// §13). To [SyncCadence.manual]: the signal is dropped and every timer
  /// cancelled — a run in flight ends on its own. To
  /// [SyncCadence.automatic]: the user acted, so a quota hold lifts as it
  /// does on a return, the signal is followed again and a run starts the way
  /// a quiet [start] does. A stopped engine only stores it: the next [start]
  /// reads it back.
  Future<void> setCadence(SyncCadence next) async {
    await _binding.setCadence(next);
    if (_cadence == next) return;
    _cadence = next;
    if (!_started || _stopped) return;
    switch (next) {
      case SyncCadence.manual:
        _cancelPushTimers();
        _retry?.cancel();
        _retry = null;
        _signalRetry?.cancel();
        _signalRetry = null;
        _resumeFallback?.cancel();
        _resumeFallback = null;
        _detachSignal();
        _emit();
      case SyncCadence.automatic:
        // Judged before the lift, as a return judges it: a quota pause kept
        // from the last session is the retry this run owes, so it runs in
        // full and its first call clears the stored mark.
        final quiet = _pause == SyncPause.none && _lastFailure == null;
        _backoffStep = 0;
        _signalBackoffStep = 0;
        _liftQuotaHold();
        _recheckAccess = true;
        await _reevaluate(run: true, resume: quiet);
    }
  }

  /// Lifts a quota hold, the pause with it: a run that makes no gateway call
  /// at all — a stale run with no stale table and an empty outbox — reaches
  /// nothing to clear the pause with, and the status would go on showing a
  /// quota pause while sync is in fact unblocked (A2 review R57).
  void _liftQuotaHold() {
    _quotaHeld = false;
    if (_pause == SyncPause.quotaExhausted) _pause = SyncPause.none;
  }

  /// The app came back: the signal is followed again, skipping whatever
  /// back-off or quota wait was pending, after one read of the space when a
  /// `noAccess` or `spaceDeleted` pause holds. Unless started, only the
  /// foreground is noted.
  ///
  /// A quiet resume — no pause, no failure waiting for its retry — pulls
  /// only the tables the space's snapshot says moved, so an idle return
  /// costs one read instead of a page per table (scalability record S9);
  /// a full run starts when no snapshot comes within [resumeSnapshotWait]
  /// or the last full pull is older than [fullPullInterval]. Any other
  /// resume is the retry it replaces and runs in full at once.
  ///
  /// Under [SyncCadence.manual] a return lifts nothing and follows nothing:
  /// it runs the bind's first merge while that is pending, and a "Sync now"
  /// the leave cut short ([_resumeOwed]) — the pause and the failure shown
  /// stay as they are until the user presses again (record §13).
  void onAppResumed() {
    _foreground = true;
    if (!_started) return;
    if (!_autoRuns) {
      if (_resumeOwed) {
        _resumeOwed = false;
        unawaited(_request(_RunMode.full, asked: true));
      } else {
        _track(_reevaluate(run: true));
      }
      return;
    }
    final quiet = _pause == SyncPause.none && _lastFailure == null;
    _backoffStep = 0;
    _signalBackoffStep = 0;
    _liftQuotaHold();
    _recheckAccess = true;
    _retry?.cancel();
    _retry = null;
    _signalRetry?.cancel();
    _signalRetry = null;
    _track(_reevaluate(run: true, resume: quiet));
  }

  /// The app went to the background: the signal is dropped and the outbox
  /// drained now, without the debounce — the process may not live long
  /// enough for it (readiness D19). Bounded: the drain pulls nothing, and a
  /// run in flight stops pulling before its next page. Completes when that
  /// drain has run or was skipped — skipped while the initial merge is
  /// pending, which only a full pull may end (record §3.5). Unless started,
  /// only the leave is noted.
  ///
  /// Answers with the drain's report, the one reader of
  /// [SyncRunSkip.initialMergePending]: a caller — and the suite — can tell
  /// a drain that ran from one the pending merge held back (A7 review R142).
  /// Under [SyncCadence.manual] nothing is drained — [SyncRunSkip.manual] —
  /// a run in flight still stops pulling before its next page.
  Future<SyncRunReport> onAppBackgrounded() async {
    _foreground = false;
    if (!_started) {
      return const SyncRunReport(skipped: SyncRunSkip.stopped);
    }
    _cancelPushTimers();
    _retry?.cancel();
    _retry = null;
    _signalRetry?.cancel();
    _signalRetry = null;
    _resumeFallback?.cancel();
    _resumeFallback = null;
    _detachSignal();
    if (!_autoRuns) return const SyncRunReport(skipped: SyncRunSkip.manual);
    return _request(_RunMode.drain);
  }

  // ---------------------------------------------------------------------------
  // Runs

  /// [asked] marks a run the user or the bind owes — "Sync now", the first
  /// merge, a cut "Sync now" finished on the return — which the manual
  /// cadence lets through; requests merged into one run keep the mark if
  /// any of them had it.
  Future<SyncRunReport> _request(_RunMode mode, {bool asked = false}) {
    final request = _queued ??= _RunRequest();
    if (mode.index > request.mode.index) request.mode = mode;
    if (asked) request.asked = true;
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
        SyncRunReport report;
        try {
          report = await _run(request);
        } catch (error, stack) {
          // `_run` nets its own body, but not the handlers that report a
          // failure: a throw from one of those must still answer the
          // request, or "Sync now" waits for the rest of the session and the
          // throw surfaces as an uncaught async error (A2 review R49).
          _warn('run failed past its own handlers: $error\n$stack');
          report = const SyncRunReport(failure: SyncGatewayFailure.unknown);
        }
        request.done.complete(report);
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
  Future<SyncRunReport> _run(_RunRequest request) async {
    final mode = request.mode;
    final tally = _RunTally();
    final clock = Stopwatch()..start();
    // Consumed by this run whatever it does: a later run that found no table
    // stale may stamp the last pull only on a snapshot of its own.
    final fresh = _signalFresh;
    _signalFresh = false;
    final fallbacks = _resumeFallbacks;
    _resumeFallbacks = 0;
    final parkedBefore = _parks;
    var reached = false;
    SyncRunReport report({SyncGatewayFailure? failure, SyncRunSkip? skipped}) {
      final done = SyncRunReport(
        pulledRows: tally.pulled,
        pushedRows: tally.pushed,
        parked: _parks - parkedBefore,
        failure: failure,
        skipped: skipped,
        pushedBytes: tally.pushedBytes,
        pages: tally.pages,
        pushAttempts: tally.pushAttempts,
        resumeFallbacks: fallbacks,
        duration: clock.elapsed,
      );
      // One line per run that passed the gate, for reading a session's cost
      // off the log against the Spark budget; debug builds only.
      if (reached && kDebugMode) {
        debugPrint(
          '[SyncEngine] run ${mode.name}: pulled ${done.pulledRows} rows in '
          '${done.pages} pages, pushed '
          '${done.pushedRows} rows / ${done.pushedBytes} B in '
          '${done.pushAttempts} calls, fallbacks ${done.resumeFallbacks}, '
          '${done.duration.inMilliseconds} ms'
          '${failure == null ? '' : ', failed ${failure.name}'}'
          '${skipped == null ? '' : ', stopped ${skipped.name}'}',
        );
      }
      return done;
    }

    try {
      _spaceReadByGate = false;
      _spaceShareRead = null;
      final (binding, skip) = await _gate();
      if (binding == null) {
        if (skip != SyncRunSkip.suspended) _detachSignal();
        return SyncRunReport(skipped: skip, resumeFallbacks: fallbacks);
      }
      // A run nobody asked for — a snapshot's or a timer's, queued behind
      // the run in flight when the cadence turned manual — reaches nothing.
      if (!_autoRuns && !request.asked) {
        return report(skipped: SyncRunSkip.manual);
      }
      if (!_autoRuns && !_spaceReadByGate) {
        final confirmed = await _confirmSpace(binding);
        if (confirmed != null) {
          return SyncRunReport(skipped: confirmed, resumeFallbacks: fallbacks);
        }
      }
      reached = true;
      if (_started && _foreground && _autoRuns) {
        _attachSignal(_spaceOf(binding));
      }
      if (_retryEveryPark && mode == _RunMode.full) {
        _retryEveryPark = false;
        _puller.retryAll();
        _pusher.resetParks();
      }
      // Before anything may drain: a drain-only run is the first of a start
      // as often as not, and it must hold back what the stored parks hold.
      await _puller.restoreParks();
      await _pusher.restoreParks();
      final initial =
          await _db.syncDao.getValue(SyncDao.keyBindMergePending) != null;
      if (initial && mode == _RunMode.drain) {
        // Named, not a bare report: [onAppBackgrounded] promises its caller
        // can tell a drain that ran from one that was skipped (A2 review
        // R56).
        return report(skipped: SyncRunSkip.initialMergePending);
      }
      // Never in a drain-only run, which would push the re-queued notes
      // before the re-read could retire the ones the space holds newer.
      final wire = mode == _RunMode.drain
          ? _WireCutover.none
          : await _cutOverWire(binding);
      final cutOver = wire != _WireCutover.none;
      // A bind's first run cuts over too — a database never synced has no
      // wire version — but that is the download the page already words. Only
      // the bodies' cutover is worded at all: the marks' re-reads two small
      // tables and sends nothing.
      if (wire == _WireCutover.bodies && !initial) {
        _downloadedRows = 0;
        _updatingTotal = await _db.noteDao.getNoteCount(null);
        _updating = true;
      }
      // The stored parks are owed their retry at every start (scalability
      // record S7), and a run that pulls no table retries none: the first
      // run of a start that still owes them pulls every table, whatever a
      // snapshot named — parks are rare, so this costs nothing in practice.
      final full =
          initial ||
          mode == _RunMode.full ||
          cutOver ||
          (mode == _RunMode.stale && _puller.owesRetry);
      final tables = full
          ? _pulledTables
          : mode == _RunMode.stale
          ? await _staleTables(_spaceOf(binding))
          : const <SyncTableBinding<Object>>[];
      _drainAhead = true;
      final pulled = await _puller.pull(
        binding,
        tables,
        initial: initial,
        // A stale run with no snapshot pulls every table too, and counts as
        // the full pull a resume measures its age from.
        everyTable: full || tables.length == _pulledTables.length,
        // A stale run whose live snapshot named no table found every table
        // current: that is a sync as far as the user can tell, so it stamps
        // the last pull like one that read pages (record §13).
        confirmed:
            mode == _RunMode.stale &&
            fresh &&
            _signalOf(_spaceOf(binding)) != null,
        tally: tally,
      );
      // A leave cut a pull the user or the bind asked for under the manual
      // cadence: nothing continues it on its own there, so the return will
      // (`onAppResumed`).
      if (pulled.cut && !_autoRuns && request.asked) _resumeOwed = true;
      // The cutover is done once a run that cut over read every table to
      // its end, `notes` again from the start; until then the re-queued
      // notes wait, since only that re-read retires the ones the space holds
      // newer, and a drain would push them over it at their local stamps.
      var sending = 0;
      if (cutOver && pulled.complete) {
        await _db.syncDao.setValue(SyncDao.keyWireVersion, '$_schema');
        // The progress goes on through the drain, the longer half: every
        // note still in legacy slices is re-cut on its way out.
        sending = _updating
            ? await _db.syncOutboxDao.count(table: const NotesBinding().table)
            : 0;
        if (sending == 0) _endUpdating();
      } else {
        _endUpdating();
      }
      final held = {
        ...pulled.failedTables,
        if (!await _wireCurrent()) const NotesBinding().table,
      };
      try {
        if (!initial || pulled.reached) {
          // The drain takes every write queued so far; a write during it
          // arms both timers again.
          _drainAhead = false;
          _drainSwallowed = false;
          _cancelPushTimers();
          // Only now the drain's total: until here the activity still says
          // pulling, and an emit in between words the re-read against its
          // own total.
          if (sending > 0) {
            _updatingTotal = sending;
            _updatingSent = 0;
            _updatingSending = true;
          }
          await _pusher.drain(binding, tally, skipTables: held);
        }
      } finally {
        // A leave cut the pull: the drain the leave exists for went first,
        // the caches hear of the pages after it (S3d review L7).
        if (pulled.cut) await _puller.notifyRun(pulled.touched);
      }
      // After the account's own pull and drain, never in a drain-only run
      // nor after a pull a leave cut. A table of the account's own that
      // failed does not hold it back — what a partner shares is read from
      // other documents — except at a bind, whose first merge must have had
      // the space's whole say before another account's rows arrive. It
      // reports nothing into this run: its calls must not end a back-off or
      // lift a pause the account's own sync is under.
      // It comes last, with the run's own books closed: its calls each have
      // a deadline of their own, and a halt raised inside it must not leave
      // the account's own failure unrecorded or its success uncounted.
      final tableFault = pulled.fault;
      if (tableFault != null) {
        await _failed(tableFault);
      } else {
        // A push writes it with its rows; a run that read to the end and
        // had nothing to push is the one that has to look.
        if (mode != _RunMode.drain && pulled.complete && tally.pushed == 0) {
          await _settleSpaceShare(binding, tally);
        }
        if (tally.calls > 0) _succeeded();
      }
      if (mode != _RunMode.drain &&
          !pulled.cut &&
          (!initial || pulled.complete)) {
        await _shared.read(binding, asked: request.asked);
      }
      return tableFault == null
          ? report()
          : report(failure: tableFault.failure);
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
      _drainAhead = false;
      if (_drainSwallowed) {
        _drainSwallowed = false;
        // A scheduled retry runs a drain of its own.
        if (_retry == null) _armDebounce();
      }
      _endUpdating();
      _activity = SyncActivity.idle;
      _emit();
    }
  }

  /// Says again, on the space's document, which pair this database's notes
  /// are shared into when the document names another — or one where there
  /// is none (`docs/cloud-sharing-foundations.md` §4). Every push writes
  /// what its device knew then, so a device that had not yet merged the end
  /// of a share puts the pair back with its next push of anything, and the
  /// pair could again fetch the text of notes by hash until some device
  /// pushed. Called by a run that pulled to the end, whose folders are as
  /// current as this device can make them.
  ///
  /// The two directions are not weighed alike, as for a row's document
  /// ([_Puller._resayShares]): a pair the document names where this device
  /// knows of none is always taken out; a pair it lacks is put back only
  /// over this device's own write — the one it made before it had merged
  /// the share. Two devices that go on disagreeing would otherwise write
  /// the document at each other for as long as they did, each write waking
  /// the other; this way the document rests at "none", and the next push of
  /// a device that shares says the pair again.
  ///
  /// What the document says is the live snapshot's, or under the manual
  /// cadence what the run's own read of the space showed; with neither,
  /// nothing is known and nothing is written. Best effort: a failure is
  /// logged and the next run looks again, since a correction must never
  /// pause the sync it rides on.
  Future<void> _settleSpaceShare(SyncBinding binding, _RunTally tally) async {
    final space = _spaceOf(binding);
    final signal = _signalOf(space);
    final seen = signal != null
        ? (pair: signal.sharedPair, writer: signal.lastWriter)
        : _spaceShareRead;
    if (seen == null) return;
    final mine = await _db.folderDao.sharedPairOfNotes();
    if (mine == seen.pair) return;
    if (mine != null && seen.writer != _deviceId) return;
    await _checkHalt(binding);
    try {
      await _gateway.writeSpaceShare(
        space,
        sharedPair: mine,
        pushedBy: _deviceId,
        schema: _schema,
      );
      await _reached(tally);
    } on SyncGatewayException catch (error) {
      debugPrint('[SyncEngine] the space\'s share was not written: $error');
    }
  }

  /// Ends the cutover's progress with the run that carried it, or with its
  /// pull when that was cut short: such a run cuts over again next time and
  /// counts afresh.
  void _endUpdating() {
    if (!_updating) return;
    _updating = false;
    _updatingSending = false;
    _updatingTotal = null;
    _updatingSent = 0;
    _downloadedRows = 0;
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
    // The skip names the pause the re-read left, which may have turned a
    // `noAccess` into `appOutdated` (review F13).
    if (_accessLost && !await _regainsAccess(binding)) {
      return (
        null,
        switch (_pause) {
          SyncPause.spaceDeleted => SyncRunSkip.spaceDeleted,
          SyncPause.appOutdated => SyncRunSkip.appOutdated,
          _ => SyncRunSkip.noAccess,
        },
      );
    }
    if (_pause == SyncPause.appOutdated) {
      return (null, SyncRunSkip.appOutdated);
    }
    if (_quotaHeld) return (null, SyncRunSkip.paused);
    return (binding, null);
  }

  /// Whether the engine holds a `noAccess` or `spaceDeleted` pause — the two
  /// that one read of the space settles ([_regainsAccess]).
  bool get _accessLost =>
      _pause == SyncPause.noAccess || _pause == SyncPause.spaceDeleted;

  /// Whether a `noAccess` or `spaceDeleted` pause lifts now: only when a
  /// resume or "Sync now" asked and the pause is one a readable space
  /// disproves — then one [SyncGateway.readSpace], and the pause becomes
  /// what it shows: a live space lifts it, a missing or marked one is
  /// `spaceDeleted`, any failure keeps it. A transient refusal must not hold
  /// sync until the next sign-in or launch (record §3.3).
  Future<bool> _regainsAccess(SyncBinding binding) async {
    if (!_recheckAccess || !_accessRecheckable) return false;
    _recheckAccess = false;
    final SyncSpaceInfo? info;
    try {
      info = await _gateway.readSpace(_spaceOf(binding));
    } on SyncGatewayException {
      return false;
    }
    if (info == null || info.markedForDeletion) {
      _pause = SyncPause.spaceDeleted;
      return false;
    }
    // A space written by a newer build reads fine and denies every write:
    // lifting the pause here would burn a whole pull and a push on every
    // resume before the diagnosis says so (A4 review R88).
    if (info.schema > _schema) {
      _pause = SyncPause.appOutdated;
      return false;
    }
    _pause = SyncPause.none;
    _spaceReadByGate = true;
    _spaceShareRead = (pair: info.sharedPair, writer: info.lastWriter);
    return true;
  }

  /// Under [SyncCadence.manual] no signal follows the space, so a run the
  /// user asked for reads it once first, or a space marked or removed by
  /// another device would go on pulling as if live (record D1, review F1).
  /// Settles as [_regainsAccess] does: missing or marked is
  /// `spaceDeleted`, a newer schema `appOutdated` — the skip returned, the
  /// pause held; a live space is null and the run goes on. A failed read is
  /// null too: the run meets the same failure on its first call and reports
  /// it as it always has.
  Future<SyncRunSkip?> _confirmSpace(SyncBinding binding) async {
    final SyncSpaceInfo? info;
    try {
      info = await _gateway.readSpace(_spaceOf(binding));
    } on SyncGatewayException {
      return null;
    }
    if (info == null || info.markedForDeletion) {
      _loseAccess(SyncPause.spaceDeleted);
      return SyncRunSkip.spaceDeleted;
    }
    if (info.schema > _schema) {
      _loseAccess(SyncPause.appOutdated);
      return SyncRunSkip.appOutdated;
    }
    _spaceShareRead = (pair: info.sharedPair, writer: info.lastWriter);
    return null;
  }

  SyncSpaceRef _spaceOf(SyncBinding binding) =>
      SyncSpaceRef(ownerUid: binding.ownerUid, spaceId: binding.spaceId);

  /// Throws [_Halted] between pages and batches once the run must end: the
  /// engine was stopped, a restore took [SyncSuspension], the database is no
  /// longer bound as [bound] (an unbind or a rebind — nothing may land in it
  /// after that), or the bound account is no longer the one signed in.
  ///
  /// Reading the binding is three or four uncached `user_settings` SELECTs,
  /// and this runs before every page and every batch — on the app's
  /// background-isolate database, that many port round trips each time (A2
  /// review R53). Worth it: nothing may land in a database unbound or
  /// rebound mid-run.
  Future<void> _checkHalt(SyncBinding bound) async {
    if (_stopped) throw const _Halted(SyncRunSkip.stopped);
    if (SyncSuspension.isSuspended) throw const _Halted(SyncRunSkip.suspended);
    _haltUnlessStillBound(await _binding.read(), bound);
    final user = _currentUser();
    if (user == null) throw const _Halted(SyncRunSkip.signedOut);
    if (user.uid != bound.accountUid) {
      throw const _Halted(SyncRunSkip.accountMismatch);
    }
    // The await above may have spanned a stop or a suspension.
    if (_stopped) throw const _Halted(SyncRunSkip.stopped);
    if (SyncSuspension.isSuspended) throw const _Halted(SyncRunSkip.suspended);
  }

  /// Halts a run begun on [bound] once the stored binding is [current]
  /// no longer: [SyncRunSkip.unbound] when it was cleared,
  /// [SyncRunSkip.rebound] when another binding took its place.
  static void _haltUnlessStillBound(SyncBinding? current, SyncBinding bound) {
    if (current == null) throw const _Halted(SyncRunSkip.unbound);
    if (current != bound) throw const _Halted(SyncRunSkip.rebound);
  }

  /// The tables whose `touched` moved past their stored `pull_seen` — or
  /// that were never seen — in the latest signal; every table before one
  /// arrived, since nothing then says which tables are current.
  Future<List<SyncTableBinding<Object>>> _staleTables(
    SyncSpaceRef space,
  ) async {
    final signal = _signalOf(space);
    if (signal == null) return _pulledTables;
    final stale = <SyncTableBinding<Object>>[];
    for (final table in _pulledTables) {
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

  /// Re-queues every live note and chunk once this database first runs under
  /// a wire version above the one it last ran under (`wire_version`), so the
  /// space's whole-body documents are replaced by manifests and their chunks
  /// (scalability record S6, D2). Local only: a space at our version is what
  /// the `appOutdated` gate holds every older build to, and the bump itself
  /// travels with the next push's `schema`. Re-queueing mints no stamp, so
  /// the other devices' merges see the same writes again.
  ///
  /// The `notes` cursor and its settled mark go too, so this run reads every
  /// note document again: a build before this wire read the space's schema
  /// only after its pull, kept its parks for the session alone and moved its
  /// cursor past a manifest it could not read — without the re-read such a
  /// note would never arrive, and the re-queue would push this device's
  /// older version over it. Manifests are small, and the chunks they name
  /// are mostly held here already. Returns whether it cut over, for the run
  /// to pull every table.
  ///
  /// The version is stored by the run once its pull completed, so a run cut
  /// short re-queues and re-reads again next time, which undoes nothing.
  ///
  /// Only the wire that re-cut the bodies does this
  /// ([DatabaseSchema.bodyWireVersion]). A database that already ran at or
  /// above it meets a later wire with nothing to send again.
  ///
  /// One that ran below the wire that first carried a share mark
  /// ([DatabaseSchema.shareWireVersion]) reads `calendar_events` and
  /// `folders` again from the start instead ([_WireCutover.marks]): an older
  /// build may have merged an event or a folder a newer one had already
  /// marked, without the mark it could not read, and an unchanged row is
  /// never delivered again on its own — this device would go on saying
  /// "private" for everything under it. The re-read hands the mark to the
  /// merge, which takes it at the row's own stamp
  /// (`docs/cloud-sharing-foundations.md` §4). Nothing is queued.
  Future<_WireCutover> _cutOverWire(SyncBinding binding) async {
    final ran = await _wireRan();
    final dao = _db.syncDao;
    if (ran != null && ran >= _bodyWire) {
      if (ran >= _schema) return _WireCutover.none;
      if (ran >= DatabaseSchema.shareWireVersion ||
          _schema < DatabaseSchema.shareWireVersion) {
        await dao.setValue(SyncDao.keyWireVersion, '$_schema');
        return _WireCutover.none;
      }
      await _db.transaction(() async {
        for (final table in _markedTables) {
          await dao.deleteValue(SyncDao.keyPullCursor(table));
          await dao.deleteValue(SyncDao.keyPullSettled(table));
        }
      });
      return _WireCutover.marks;
    }
    await _db.transaction(() async {
      final queued = await _db.syncOutboxDao.requeueBodies(
        boundUid: binding.accountUid,
      );
      // A database that never ran merged nothing a mark could be missing
      // from, and a run of its first pull that was cut would otherwise read
      // the two tables again each time it resumed.
      for (final table in ['notes', if (ran != null) ..._markedTables]) {
        await dao.deleteValue(SyncDao.keyPullCursor(table));
        await dao.deleteValue(SyncDao.keyPullSettled(table));
      }
      debugPrint('[SyncEngine] wire → $_schema: $queued rows re-queued');
    });
    return _WireCutover.bodies;
  }

  /// The tables whose rows carry a share mark of their own.
  static const List<String> _markedTables = ['calendar_events', 'folders'];

  /// Whether this database's notes are in the shape this build pushes: it
  /// completed a run at or above the wire that re-cut their bodies.
  Future<bool> _wireCurrent() async {
    final ran = await _wireRan();
    return ran != null && ran >= _bodyWire;
  }

  /// The wire version this database last completed a run under, if any.
  Future<int?> _wireRan() async =>
      int.tryParse(await _db.syncDao.getValue(SyncDao.keyWireVersion) ?? '');

  /// [DatabaseSchema.bodyWireVersion], never above this engine's own wire:
  /// an engine built for an older one is current at its own.
  int get _bodyWire => _schema < DatabaseSchema.bodyWireVersion
      ? _schema
      : DatabaseSchema.bodyWireVersion;

  SyncTableBinding<Object>? _bindingFor(String table) {
    for (final binding in _tables) {
      if (binding.table == table) return binding;
    }
    return null;
  }

  /// Every park the engine holds, pull and push, this session's and the
  /// stored ones.
  List<SyncParkedRow> get _parkedRows => [..._puller.parks, ..._pusher.parks];

  /// Keys parked this session, counted as they are set aside and never
  /// lowered when one lets go — what a run reports as parked, apart from
  /// the status's held-back rows, which shrink as rows land.
  int _parks = 0;

  /// The parks the last emit listed and the rows it listed for them, so an
  /// emit with the same parks — most of them, one per page and batch — asks
  /// the database nothing.
  List<SyncParkedRow> _heldParks = const [];
  List<SyncHeldItem> _heldItems = const [];

  /// Whether the last read of the held-back rows failed, so a failure that
  /// lasts is logged once.
  bool _heldReadFailed = false;

  /// The parks as stored, pull and push, for an emit before a run restored
  /// them.
  Future<List<SyncParkedRow>> _storedParks() async {
    final syncDao = _db.syncDao;
    return [
      for (final park in _readParks(
        await syncDao.valuesByPrefix(SyncDao.pullParkedPrefix),
        SyncDao.pullParkedPrefix,
      ))
        SyncParkedRow(
          park.key.$1,
          park.key.$2,
          park.stamp,
          park.reason ?? SyncHeldReason.unreadable,
        ),
      for (final park in _readParks(
        await syncDao.valuesByPrefix(SyncDao.pushParkedPrefix),
        SyncDao.pushParkedPrefix,
      ))
        SyncParkedRow(
          park.key.$1,
          park.key.$2,
          park.stamp,
          park.reason ?? SyncHeldReason.unencodable,
        ),
    ];
  }

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
        final pausedAt = _now();
        try {
          await _db.syncDao.setValue(
            SyncDao.keyQuotaPausedAt,
            '${pausedAt.millisecondsSinceEpoch}',
          );
        } catch (error) {
          // The pause holds for this session either way; only the next
          // launch's retry at once is lost.
          _warn('quota pause not stored: $error');
        }
        // Under the manual cadence the hold stands until "Sync now" lifts
        // it: the pause is shown, and the user decides when to try again.
        if (_autoRuns) {
          _scheduleRetry(
            quotaRetryDelay(pausedAt, _timing.quotaRetry),
            liftsQuota: true,
          );
        }
      case SyncGatewayFailure.permissionDenied:
        // A pull's denial; a push's is diagnosed before it gets here.
        _loseAccess(SyncPause.noAccess);
      case SyncGatewayFailure.offline:
      case SyncGatewayFailure.invalidData:
      case SyncGatewayFailure.unknown:
        _scheduleBackoff();
    }
  }

  /// How long a quota pause that began at [now] holds: until
  /// [quotaResetMargin] past the quota's next reset ([SyncQuota.nextReset]),
  /// never longer than [hourly] — the hourly retry stays, only its time
  /// moves when the reset comes sooner.
  static Duration quotaRetryDelay(DateTime now, Duration hourly) {
    final reset = SyncQuota.nextReset(
      now,
    ).add(quotaResetMargin).difference(now);
    return reset < hourly ? reset : hourly;
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
    // A resume waiting for its first snapshot: the snapshot said this.
    _resumeFallback?.cancel();
    _resumeFallback = null;
    _detachSignal();
    _emit();
  }

  /// The next back-off step, only while in the foreground: in the background
  /// the resume retries at once instead. Never under [SyncCadence.manual],
  /// where the failure waits for the next press.
  void _scheduleBackoff() {
    if (_stopped || !_foreground || !_autoRuns) return;
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
  /// [run] also starts a full run when runnable. With [resume] the run waits
  /// for the signal's snapshot instead and pulls what it names, unless the
  /// last full pull is [fullPullInterval] old ([onAppResumed]).
  ///
  /// Under [SyncCadence.manual] no signal is followed and [run] runs only
  /// the bind's first merge, while `bind_merge_pending` stands: the bind the
  /// user asked for owes it, whatever the cadence (record §13).
  Future<void> _reevaluate({required bool run, bool resume = false}) async {
    if (_stopped) return;
    final SyncBinding? binding;
    final SyncRunSkip? skip;
    var full = true;
    var pending = false;
    try {
      (binding, skip) = await _gate();
      if (binding != null && run) {
        pending =
            await _db.syncDao.getValue(SyncDao.keyBindMergePending) != null;
        if (resume && _autoRuns) full = await _fullPullDue();
      }
    } catch (error) {
      // A closed database: nothing to follow, and a run would fail the same
      // way — it reports the failure when one is asked for.
      debugPrint('[SyncEngine] re-evaluation failed: $error');
      return;
    }
    if (_stopped) return;
    // Judged after the last await: a switch to manual that landed during
    // one must not let a run nobody asked for through.
    if (run && !_autoRuns) run = pending;
    if (binding != null) {
      final space = _spaceOf(binding);
      final live = _signalOf(space) != null;
      if (_started && _foreground && _autoRuns) _attachSignal(space);
      if (run && full) {
        unawaited(_request(_RunMode.full, asked: pending));
      } else if (run && live) {
        // The listener outlived the leave: its snapshot is current.
        unawaited(_request(_RunMode.stale, asked: pending));
      } else if (run && _signalSubscription != null) {
        _awaitSnapshot();
      } else if (run) {
        unawaited(_request(_RunMode.full, asked: pending));
      }
    } else if (skip != SyncRunSkip.suspended) {
      // A suspension keeps the signal: nothing announces its end, and the
      // restore it covers unbinds the database anyway.
      _detachSignal();
    }
    _emit();
  }

  /// Whether a resume must pull every table: the last pull of every table is
  /// [fullPullInterval] old, or there never was one.
  Future<bool> _fullPullDue() async {
    final at = int.tryParse(
      await _db.syncDao.getValue(SyncDao.keyFullPullAt) ?? '',
    );
    if (at == null) return true;
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age >= fullPullInterval || age.isNegative;
  }

  /// Leaves the resume's run to the signal's first snapshot ([_onSignal]),
  /// with a full run after [resumeSnapshotWait] should none come.
  void _awaitSnapshot() {
    _resumeFallback?.cancel();
    _resumeFallback = _scheduler.schedule(resumeSnapshotWait, () {
      _resumeFallback = null;
      if (_stopped) return;
      _resumeFallbacks++;
      unawaited(_request(_RunMode.full));
    });
  }

  /// An account change — never the stream's replay of the account the
  /// engine already follows ([_followedUid]). A sign-in with nothing waiting
  /// runs as a quiet start does, so a launch whose account is restored a
  /// moment after the engine started still costs one read; one that lifts a
  /// `noAccess` or `spaceDeleted` pause is the retry that pause promised and
  /// runs in full.
  void _onAuthChanged(AppUser? user) {
    if (user?.uid == _followedUid) return;
    _followedUid = user?.uid;
    final quiet = _pause == SyncPause.none && _lastFailure == null;
    // "Until the next sign-in": a fresh account session tries the space
    // again.
    if (user != null && _accessLost) _pause = SyncPause.none;
    _track(_reevaluate(run: true, resume: quiet));
  }

  /// The outbox trigger. Under the manual cadence it arms nothing and only
  /// emits, so the status counts the change waiting for "Sync now" — at most
  /// one emit waiting behind the one in flight, which takes its snapshot
  /// when it begins and so counts every write that joined it.
  void _armDebounce() {
    if (_stopped) return;
    if (!_autoRuns) {
      if (_outboxEmitQueued) return;
      _outboxEmitQueued = true;
      _emits = _emits.then((_) {
        _outboxEmitQueued = false;
        _emit();
      });
      return;
    }
    _debounce?.cancel();
    _debounce = _scheduler.schedule(_timing.pushDebounce, () {
      _debounce = null;
      _track(_drainIfQueued());
    });
    _maxWait ??= _scheduler.schedule(_timing.pushMaxWait, () {
      _maxWait = null;
      _track(_drainIfQueued());
    });
  }

  void _cancelPushTimers() {
    _debounce?.cancel();
    _debounce = null;
    _maxWait?.cancel();
    _maxWait = null;
  }

  /// The debounced push, skipped when the run that followed the trigger has
  /// already emptied the outbox — a merge's re-queue arms the trigger too —
  /// or when the run in flight drains next ([_drainAhead]).
  /// A closed database ends it quietly: it runs from a timer, where a throw
  /// would surface as an uncaught error through [whenIdle] (S3d review L5).
  Future<void> _drainIfQueued() async {
    if (_drainAhead) {
      _drainSwallowed = true;
      return;
    }
    try {
      if (_stopped || await _db.syncOutboxDao.count() == 0) return;
    } catch (error) {
      debugPrint('[SyncEngine] debounced drain skipped: $error');
      return;
    }
    // The cadence may have turned manual over the count.
    if (!_autoRuns) return;
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
    _signalFresh = false;
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// The latest snapshot of [space], null when the listener follows another
  /// space or none.
  SyncSpaceSignal? _signalOf(SyncSpaceRef space) =>
      _signalSpace == space ? _signal : null;

  void _onSignal(SyncSpaceSignal signal) {
    if (_stopped) return;
    // A marked space takes no more writes and is being emptied: pulling it
    // would merge a copy that shrinks under the run (record D1, §5.2 d).
    if (!signal.exists || signal.markedForDeletion) {
      return _loseAccess(SyncPause.spaceDeleted);
    }
    if (signal.schema > _schema) return _loseAccess(SyncPause.appOutdated);
    _signal = signal;
    _signalFresh = true;
    _signalBackoffStep = 0;
    _resumeFallback?.cancel();
    _resumeFallback = null;
    _noteServerTime(signal);
    // The listener is healthy again; a run's failure waits for a run.
    if (_failureFromSignal) {
      _lastFailure = null;
      _failureFromSignal = false;
      _emit();
    }
    unawaited(_request(_RunMode.stale));
  }

  /// Stores the latest server time [signal] shows as `server_seen` when it
  /// raises the mark: the settled overlap needs it after the listener is
  /// gone ([_Puller._settles]). A failed store only costs a re-read.
  void _noteServerTime(SyncSpaceSignal signal) {
    final latest = _latestTouched(signal);
    final seen = _serverSeen;
    if (latest == null || (seen != null && latest <= seen)) return;
    _serverSeen = latest;
    _track(() async {
      try {
        await _db.syncDao.setValue(SyncDao.keyServerSeen, '$latest');
      } catch (error) {
        debugPrint('[SyncEngine] server time not stored: $error');
      }
    }());
  }

  /// The highest `touched` of [signal], in microseconds; null when it names
  /// no table.
  static int? _latestTouched(SyncSpaceSignal? signal) {
    int? latest;
    for (final at in signal?.touched.values ?? const <DateTime>[]) {
      final micros = at.microsecondsSinceEpoch;
      if (latest == null || micros > latest) latest = micros;
    }
    return latest;
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
    if (_stopped || !_foreground || !_autoRuns) return;
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
  /// [SyncPause.spaceDeleted] / [SyncPause.appOutdated] /
  /// [SyncPause.quotaExhausted]; otherwise none.
  static SyncPause pauseOver({
    required SyncPause read,
    required SyncPause engine,
  }) {
    if (read == SyncPause.signedOut || read == SyncPause.accountMismatch) {
      return read;
    }
    return switch (engine) {
      SyncPause.noAccess ||
      SyncPause.spaceDeleted ||
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
    final cadence = _cadence;
    final failure = _lastFailure;
    // Until a run past the gate restored them, the parks are only stored: a
    // start that is signed out or paused still lists what they hold back.
    final parked = _puller._restored && _pusher._restored ? _parkedRows : null;
    final downloaded = _downloadedRows;
    final updating = _updating;
    final updatingSending = _updatingSending;
    final updatingTotal = _updatingTotal;
    final updatingSent = _updatingSent;
    _emits = _emits.then((_) async {
      if (_statusController.isClosed) return;
      final SyncStatus stored;
      try {
        stored = await _statusService.read(user: _currentUser());
      } catch (error) {
        debugPrint('[SyncEngine] status not read: $error');
        return;
      }
      // Apart from the status: a list that cannot be read keeps the last
      // one, and must not cost the emit its activity or its pause.
      var held = _heldItems;
      try {
        final parks = parked ?? await _storedParks();
        if (!listEquals(parks, _heldParks)) {
          held = await _statusService.heldBack(parks);
          _heldParks = parks;
          _heldItems = held;
        }
        _heldReadFailed = false;
      } catch (error) {
        if (!_heldReadFailed) {
          debugPrint('[SyncEngine] held-back rows not read: $error');
        }
        _heldReadFailed = true;
      }
      final next = stored.copyWith(
        activity: activity,
        pause: pauseOver(read: stored.pause, engine: pause),
        cadence: cadence,
        lastFailure: failure,
        clearLastFailure: failure == null,
        parkedCount: held.length,
        heldBack: held,
        downloadedRows: downloaded,
        updating: updating,
        updatingSending: updatingSending,
        updatingTotal: updatingTotal,
        clearUpdatingTotal: updatingTotal == null,
        updatingSent: updatingSent,
      );
      if (next == _current || _statusController.isClosed) return;
      _current = next;
      _statusController.add(next);
    });
  }
}

/// What a run does on first meeting a wire above the one its database last
/// ran under ([SyncEngine._cutOverWire]); either one pulls every table, and
/// the version is stored once that pull reached every table's end.
enum _WireCutover {
  /// The database ran at this wire already, or the wires between changed
  /// nothing it has to act on.
  none,

  /// Every note is queued again and read again: its body crosses as chunks.
  bodies,

  /// The events and the folders are read again from the start, for the
  /// share marks an older build could not read.
  marks,
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

  /// Whether the user or the bind asked for it ([SyncEngine._request]).
  bool asked = false;
  final Completer<SyncRunReport> done = Completer<SyncRunReport>();
}

/// The engine's warnings: faults a parked row or a failed table hides from
/// the status, which a developer reading the log must still see.
void _warn(String message) => debugPrint('[SyncEngine] warning: $message');

class _RunTally {
  int pulled = 0;
  int pushed = 0;
  int pushedBytes = 0;
  int pages = 0;
  int pushAttempts = 0;

  /// Gateway calls that succeeded: a run that made none proved nothing about
  /// the space, so it clears no failure and no quota pause.
  int calls = 0;
}

class _DrainState {
  int refused = 0;

  /// Whether the space was read to judge a denial of the batch being pushed:
  /// once per batch tells the space's denial from a row's inside its bisect;
  /// the next batch denied reads it again (review F5).
  bool diagnosed = false;

  /// The denial that diagnosis judged, so a row refused by that very push is
  /// parked on it without a second read (review G5); a stored park tried
  /// again is parked without one whatever refused it (review K1).
  SyncGatewayException? judged;

  /// The chunk encoded for a part it did not fit, kept for the next part:
  /// its text cannot change under its hash, and encoding it again would
  /// gzip and hash it once more per part a large note spans.
  _Queued? chunkAhead;
}

class _Queued {
  final SyncOutboxRow entry;
  final SyncEnvelope envelope;

  /// The row data's size on the wire ([SyncEnvelope.wireBytes]), which the
  /// batch's byte cap adds up.
  final int bytes;

  /// The stamp the entry is retired through once the push lands
  /// (`_Pusher._ackOf`).
  final String ack;

  const _Queued(this.entry, this.envelope, this.bytes, this.ack);
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
