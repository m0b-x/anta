import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../constants/shared_refresh_constants.dart';
import '../../core/di/injection.dart';
import '../../core/qa/qa_bootstrap.dart';
import '../../database/database.dart';
import '../../database/migrations/database_schema.dart';
import '../alert_scheduler.dart';
import '../auth_service.dart';
import '../database_manager.dart';
import '../firebase_bootstrap.dart';
import '../kept_share_notices.dart';
import '../settings_service.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_gateway.dart';
import '../sync/sync_suspension.dart';
import 'shared_refresh.dart';
import 'shared_refresh_ports.dart';
import 'shared_refresh_scheduler.dart';
import 'shared_refresh_trigger.dart';

/// The app's isolate in the handshake of `docs/cloud-shared-freshness.md`
/// §5: the launch's step before the database opens, and the read a trigger
/// forwards to the app's own engine.
abstract final class SharedRefreshApp {
  static SharedRefreshAppPort? _port;
  static Completer<void> _up = Completer<void>();

  /// The launch's first step, before anything opens the database: takes
  /// the app's name and looks for a run in flight, in one synchronous turn.
  /// Null — nothing to await — when none is, which is every ordinary
  /// launch; else the wait for that run to close the database, five seconds
  /// at most. Nothing at all where no check exists
  /// ([SharedRefreshAvailability]).
  static Future<void>? beginLaunch({
    PortRegistry registry = const IsolateNamePortRegistry(),
    Future<void> Function(SharedRefreshSlot? slot)? read,
  }) {
    if (!SharedRefreshAvailability.isSupported) return null;
    final port = _port ??= SharedRefreshAppPort(
      // The name is taken before the database is open: a read asked for
      // meanwhile waits for the launch, and the trigger's own limit bounds
      // the wait.
      read: (slot) async {
        await _up.future;
        await (read ?? _readOnAppEngine)(slot);
      },
      registry: registry,
    );
    port.open();
    return port.yieldRunInFlight();
  }

  /// The launch has brought the app up: a forwarded read, which waited for
  /// this, may reach the engine.
  static void launched() {
    if (!_up.isCompleted) _up.complete();
  }

  /// Takes the name again if a trigger removed it — one that met this
  /// isolate too busy to answer its ping in time took it for dead.
  static void reassert() => _port?.open();

  @visibleForTesting
  static void resetForTesting() {
    _port?.close();
    _port = null;
    _up = Completer<void>();
  }

  /// The shared read on the app's own engine, whether or not the app is in
  /// front, then an alert pass: the read asks for one only when it changed
  /// something, and the check must plan its successor — and roll the
  /// alerts' horizon forward — either way.
  ///
  /// The work in [slot] is running for as long as this takes: the
  /// coordinator is told, so it forgets the check that work was — or the
  /// pass would find its plan standing and schedule no successor — and
  /// writes the next into the other slot. A message's work is in no slot
  /// (null): the check that stands is not the work that asks, so nothing is
  /// forgotten and the pass replaces it only if the read moved the plan.
  static Future<void> _readOnAppEngine(SharedRefreshSlot? slot) async {
    if (!GetIt.I.isRegistered<SyncGateway>() ||
        !GetIt.I<AuthService>().isAvailable) {
      return;
    }
    await forwardedRead(
      slot,
      refresh: GetIt.I<SharedRefresh>(),
      read: () async => (await SyncEngine.getInstance()).readSharedWhileAway(),
      alertPass: () =>
          AlertScheduler.reconcileAllQuietly(AlertReconcileReason.sync),
    );
  }

  /// [_readOnAppEngine]'s order over seams: the work is named as running
  /// before the read, the alert pass follows the read whatever it found,
  /// and the work is given back once the pass's plan has reached the
  /// platform — also when the read throws. With no [slot] — a message's
  /// work — nothing is named and nothing given back: a check's own work
  /// forwarded meanwhile keeps the slot it named.
  @visibleForTesting
  static Future<void> forwardedRead(
    SharedRefreshSlot? slot, {
    required SharedRefresh refresh,
    required Future<Object?> Function() read,
    required Future<void> Function() alertPass,
  }) async {
    if (slot != null) refresh.workRunning(slot);
    try {
      await read();
      await alertPass();
    } finally {
      if (slot != null) await refresh.workEnded();
    }
  }
}

/// [SharedRefreshRunSteps] over the app's own code, for an isolate that
/// starts with no app (§6): every step is the function the launch itself
/// uses, never a copy.
class AppSharedRefreshRunSteps implements SharedRefreshRunSteps {
  /// The slot this run is the work of; null for a message's work, which
  /// stands in neither.
  final SharedRefreshSlot? _slot;
  SyncEngine? _engine;

  /// The pair a relay message named; null for the schedule's own check.
  /// A database in another pair reads nothing for it (case B13).
  final String? pair;

  AppSharedRefreshRunSteps(this._slot, {this.pair});

  bool _stopped = false;

  @override
  Future<void> prepare() async {
    QaBootstrap.namespacePreferences();
    // An alert armed by this run words its day and time as one armed by the
    // app does.
    await initializeDateFormatting();
    await initializeFirebaseForSync();
  }

  @override
  Future<int?> storedSchema() async {
    final manager = await DatabaseManager.getInstance();
    return DatabaseManager.schemaVersionOfFile(
      await manager.getDatabasePath(manager.getActiveDatabaseName()),
    );
  }

  @override
  int get schema => DatabaseSchema.currentVersion;

  /// From the first moment the coordinator knows which slot this run is:
  /// its passes schedule the successor into the other. A message's run is
  /// in none, and schedules as the app does.
  @override
  Future<void> open() async {
    await configureSharedRefreshRunDependencies();
    if (_slot case final slot?) GetIt.I<SharedRefresh>().workRunning(slot);
  }

  @override
  bool get suspended => SyncSuspension.isSuspended;

  /// The identity restores the stored account as the isolate starts: its
  /// first word is waited for, so "not restored yet" is not read as
  /// "signed out".
  @override
  Future<bool> shares() async {
    if (!GetIt.I.isRegistered<SyncGateway>()) return false;
    final auth = GetIt.I<AuthService>();
    final user =
        auth.currentUser ??
        await auth.authStateChanges.first.timeout(
          kSharedRefreshAccountWait,
          onTimeout: () => null,
        );
    final settings = await SettingsService.getInstance();
    if (!await SharedRefresh.databaseShares(uid: user?.uid, settings: settings)) {
      return false;
    }
    final named = pair;
    return named == null ||
        (await settings.getPairingSettings()).pairId == named;
  }

  /// The launch's own pass, which loads every facade it reads before it
  /// plans; what it reports of the partner's schedules the successor, or
  /// says that nothing depends on a check.
  @override
  Future<SharedRefreshWorth> planSuccessor() async {
    final scheduler = await AlertScheduler.getInstance();
    await scheduler.reconcileAll(AlertReconcileReason.launch);
    final refresh = GetIt.I<SharedRefresh>();
    await refresh.settled();
    return (check: refresh.scheduled, poke: refresh.pokeWorthy);
  }

  /// What the read would have told the person is kept with the database
  /// for the next open: here nobody listens (decision f).
  @override
  Future<void> read() async {
    final db = GetIt.I<AppDatabase>();
    final name = (await DatabaseManager.getInstance()).getActiveDatabaseName();
    final keeping = <Future<void>>[];
    final engine = _engine = await SyncEngine.awayFromApp(
      notify: (notice) => keeping.add(
        KeptShareNotices.keep(db, name, notice).catchError((
          Object error,
          StackTrace stack,
        ) {
          debugPrint('[SharedRefresh] notice not kept: $error\n$stack');
        }),
      ),
    );
    if (_stopped) return;
    await engine.readSharedWhileAway();
    await Future.wait(keeping);
    // The pass the read asked for has decided again.
    await GetIt.I<SharedRefresh>().settled();
  }

  @override
  Future<void> stopRead() async {
    _stopped = true;
    await _engine?.stop();
  }

  @override
  Future<void> close() async {
    await _engine?.stop();
    if (GetIt.I.isRegistered<SharedRefresh>()) {
      await GetIt.I<SharedRefresh>().settled();
    }
    if (GetIt.I.isRegistered<AppDatabase>()) {
      await GetIt.I<AppDatabase>().close();
    }
  }
}

SharedRefreshTrigger? _firing;

/// What a trigger of the check does, whoever fires it — the platform's
/// scheduled work, or a message from the relay with the app not in front:
/// the app's own isolate reads when the app runs in this process, else the
/// run without the app. True unless the platform should try again.
///
/// [cause] says which of the two it was: a message reads for an alert of
/// mine on any event of the partner's, the schedule only while its own
/// check is wanted.
///
/// [slot] is the one the task that fires this names — for the check's own
/// work, what keeps its successor from being scheduled in its place; a
/// message's work stands in neither ([SharedRefreshCause.standsIn]).
/// [pair] is the pair a message named.
Future<bool> fireSharedRefresh({
  SharedRefreshCause cause = SharedRefreshCause.check,
  SharedRefreshSlot slot = SharedRefreshSlot.first,
  String? pair,
}) async {
  final trigger = _firing = SharedRefreshTrigger(
    steps: AppSharedRefreshRunSteps(cause.standsIn(slot), pair: pair),
    cause: cause,
    slot: slot,
  );
  try {
    return !(await trigger.fire()).retry;
  } finally {
    _firing = null;
  }
}

/// The platform stopped the work [fireSharedRefresh] is doing: completes
/// once the run has ended where it was and closed the database.
Future<void> stopSharedRefresh() async => _firing?.stop();
