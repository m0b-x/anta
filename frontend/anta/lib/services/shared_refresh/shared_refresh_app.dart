import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/settings_keys.dart';
import '../../constants/shared_refresh_constants.dart';
import '../../core/di/injection.dart';
import '../../core/qa/qa_bootstrap.dart';
import '../../database/database.dart';
import '../../database/migrations/database_schema.dart';
import '../alert_scheduler.dart';
import '../auth_service.dart';
import '../database_manager.dart';
import '../database_replacing.dart';
import '../firebase_bootstrap.dart';
import '../fresh_preferences.dart';
import '../kept_share_notices.dart';
import '../push/push_address_source.dart';
import '../settings_service.dart';
import '../sync_availability.dart';
import '../sync/app_sync_apply_hooks.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_gateway.dart';
import '../sync/sync_suspension.dart';
import 'shared_refresh.dart';
import 'shared_refresh_memory.dart';
import 'shared_refresh_message_gate.dart';
import 'shared_refresh_ports.dart';
import 'shared_refresh_scheduler.dart';
import 'shared_refresh_trigger.dart';
import 'workmanager_shared_refresh_scheduler.dart';

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
  ///
  /// Never throws, now or from what it returns: it runs before the launch
  /// has installed its error hooks, where a throw is a blank screen. A
  /// failure is logged and the launch goes on holding no name — a trigger
  /// then finds no app and runs by itself, which the database's own lock
  /// outlives better than the app outlives no launch.
  static Future<void>? beginLaunch({
    PortRegistry registry = const IsolateNamePortRegistry(),
    Future<void> Function(SharedRefreshReadAsk ask)? read,
    Future<void> Function()? catchUp,
    Duration readLimit = kSharedRefreshForwardPatience,
    Duration yieldTimeout = kSharedRefreshYieldTimeout,
    Duration deadRunAfter = kSharedRefreshDeadRunAfter,
  }) {
    try {
      if (!SharedRefreshAvailability.isSupported) return null;
      _catchUp = catchUp ?? _catchUpOnAppEngine;
      _silentRunPatience = yieldTimeout - deadRunAfter;
      final port = _port ??= SharedRefreshAppPort(
        // The name is taken before the database is open: a read asked for
        // meanwhile waits for the launch, and the trigger's own limit
        // bounds the wait.
        read: (ask) async {
          await _up.future;
          // Its asker was answered failure long ago, and is run again: the
          // check's work by the platform, a message's by the fresh work its
          // own end handed over.
          if (ask.givenUp) throw const SharedReadGivenUp();
          await (read ?? _readOnAppEngine)(ask);
        },
        registry: registry,
        readLimit: readLimit,
        yieldTimeout: yieldTimeout,
        deadRunAfter: deadRunAfter,
      );
      port.open();
      return port
          .yieldRunInFlight()
          ?.then<void>((silent) {
            // The launch goes on at once; the catch-up comes when it may.
            if (silent) unawaited(_catchUpAfter(silent: true));
          })
          .catchError(_launchStepFailed);
    } catch (error, stack) {
      _launchStepFailed(error, stack);
      return null;
    }
  }

  /// How much longer than its one second a run that was only silent is
  /// given before the app makes good what it wrote: what is left of the
  /// wait a launch used to give every run. A live run asked to give way
  /// ends at its next step, and until then the connection's busy timeout
  /// is all that stands between the two writers.
  static Duration _silentRunPatience =
      kSharedRefreshYieldTimeout - kSharedRefreshDeadRunAfter;

  /// The catch-up a run that may have written behind the app is owed:
  /// after a re-take of the name, and after a launch or a re-take that
  /// took a [silent] holder for dead — which waits the old patience out
  /// first, since a busy run was still writing when its name went.
  static Future<void> _catchUpAfter({required bool silent}) async {
    try {
      if (silent) await Future<void>.delayed(_silentRunPatience);
      await _up.future;
      await _catchUpOnce();
    } catch (error, stack) {
      debugPrint('[SharedRefresh] not caught up: $error\n$stack');
    }
  }

  /// One catch-up at a time: a second re-take while one runs is folded
  /// into it — two ran two wholesale reloads and two passes side by side.
  static Future<void> _catchUpOnce() =>
      _catchingUp ??= _catchUp().whenComplete(() => _catchingUp = null);
  static Future<void>? _catchingUp;

  static void _launchStepFailed(Object error, StackTrace stack) {
    debugPrint('[SharedRefresh] launch step failed: $error\n$stack');
    final port = _port;
    _port = null;
    try {
      port?.close();
    } catch (error) {
      debugPrint('[SharedRefresh] name not given up: $error');
    }
  }

  /// The launch has brought the app up: a forwarded read, which waited for
  /// this, may reach the engine.
  static void launched() {
    if (!_up.isCompleted) _up.complete();
    // The app starts in front, and no lifecycle change says so.
    inFront(true);
  }

  /// Takes the name again if a trigger removed it — one that met this
  /// isolate too busy to answer its pings took it for dead — and asks the
  /// run that then went on without the app to close the database: the app
  /// is alive, and a second writer beside it is what the name is for.
  ///
  /// A name that was not the app's own means a run may have written behind
  /// it — rows, cursors, registrations — and consumed the work it was. So
  /// once that run has answered, or the wait for it is over, the app
  /// catches up ([caughtUp]): once for the re-take, and never on a tick
  /// that found the name standing, which stays one registry lookup.
  static void reassert() {
    final port = _port;
    if (port == null || !port.open()) return;
    unawaited(_afterRetake(port));
  }

  static Future<void> _afterRetake(SharedRefreshAppPort port) async {
    try {
      final silent = await port.yieldRunInFlight() ?? false;
      await _catchUpAfter(silent: silent);
    } catch (error, stack) {
      debugPrint('[SharedRefresh] not caught up: $error\n$stack');
    }
  }

  static Future<void> Function() _catchUp = _catchUpOnAppEngine;

  /// Nothing where sync cannot run: no run reads or arms anything there.
  static Future<void> _catchUpOnAppEngine() async {
    if (!GetIt.I.isRegistered<SyncGateway>() ||
        !GetIt.I<AuthService>().isAvailable) {
      return;
    }
    await caughtUp(
      reload: AppSyncApplyHooks.afterWritesBehindTheApp,
      read: () async => (await SyncEngine.getInstance()).readSharedWhileAway(),
      alertPass: () =>
          AlertScheduler.reconcileAllQuietly(AlertReconcileReason.sync),
    );
  }

  /// What the app does after a run may have written behind it, in this
  /// order: [reload] what such a run can have changed, so nothing is read
  /// from a stale cache; the shared [read] itself — the run that gave way
  /// did not finish its own, and a message's is retried by nobody; and the
  /// [alertPass], which plans the check whose work that run consumed. One
  /// that fails costs the others nothing.
  ///
  /// Last, whoever says the share notices is prompted to read what the run
  /// kept with the database ([KeptShareNotices.prompt]): it kept them
  /// because it took the app for gone, and the app is here.
  ///
  /// None of it while a database is being [replacing]: a restore is what
  /// stalls the app past a trigger's pings, the trigger then wrote nothing
  /// (it met the marker), and a wholesale reload and a pass in the middle
  /// of the restore read a database half replaced. The replacement's own
  /// end reloads.
  @visibleForTesting
  static Future<void> caughtUp({
    required Future<void> Function() reload,
    required Future<Object?> Function() read,
    required Future<void> Function() alertPass,
    bool Function() replacing = _replacingHere,
  }) async {
    if (replacing()) return;
    for (final (name, step) in [
      ('reload', reload),
      ('read', read),
      ('alert pass', alertPass),
    ]) {
      try {
        await step();
      } catch (error, stack) {
        debugPrint('[SharedRefresh] catching up, $name: $error\n$stack');
      }
    }
    KeptShareNotices.prompt();
  }

  /// The app's own knowledge, with no store asked: a scope of
  /// `DatabaseReplacing` open in this isolate, or sync held for a restore.
  static bool _replacingHere() =>
      DatabaseReplacing.inFlight || SyncSuspension.isSuspended;

  static Timer? _reasserting;
  static bool _front = false;
  static Duration _every = kSharedRefreshReassertEvery;

  /// The app came to the front, or left it. In front the name is taken
  /// again at once and then every [kSharedRefreshReassertEvery]: a resume
  /// alone left a name lost mid-session lost until the next one, with every
  /// trigger of that session running beside the app.
  ///
  /// The timer runs only where a trigger can exist ([_triggersCanExist]):
  /// an install that never had a check planned and holds no push address
  /// has nothing that could take its name, and pays no timer for it.
  static void inFront(
    bool front, {
    Duration every = kSharedRefreshReassertEvery,
  }) {
    _reasserting?.cancel();
    _reasserting = null;
    _front = front;
    if (_port == null) return;
    if (!front) {
      // Before a run can find the app gone: a push address held since the
      // last pass opened the gate the arm facts are kept behind, and no
      // pass has stored them yet.
      unawaited(_keepArmFactsWhereARunCan());
      return;
    }
    reassert();
    _every = every;
    unawaited(_keepName());
  }

  static Future<void> _keepName() async {
    if (!await _triggersCanExist()) return;
    if (!_front || _port == null || _reasserting != null) return;
    _reasserting = Timer.periodic(_every, (_) => reassert());
  }

  /// Whether anything could fire a trigger on this install
  /// ([SharedRefreshAvailability.runsCanExist]); unreadable, the name is
  /// kept all the same.
  static Future<bool> _triggersCanExist() =>
      SharedRefreshAvailability.runsCanExist();

  /// What stores the arm facts a pass with no app arms under, outside a
  /// pass (`AlertScheduler.keepArmFactsQuietly`).
  @visibleForTesting
  static Future<void> Function() keepArmFacts =
      AlertScheduler.keepArmFactsQuietly;

  static Future<void> _keepArmFactsWhereARunCan() async {
    try {
      if (await _triggersCanExist()) await keepArmFacts();
    } catch (error) {
      debugPrint('[SharedRefresh] arm facts not kept: $error');
    }
  }

  static bool _planned = false;

  /// A check was scheduled (`SharedRefresh`): remembered for the install,
  /// once, and the name is kept from now on — also in the session that
  /// plans its first. That first one also opens the gate the arm facts are
  /// kept behind, after the pass that planned it had gone by them: they
  /// are stored now, long before the check is due.
  static void checkPlanned() {
    if (_planned) return;
    _planned = true;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!prefs.containsKey(SettingsKeys.sharedRefreshPlanned)) {
          await prefs.setString(SettingsKeys.sharedRefreshPlanned, '1');
          await keepArmFacts();
        }
        await _keepName();
      } catch (error) {
        debugPrint('[SharedRefresh] first plan not remembered: $error');
      }
    }());
  }

  /// The engine is leaving its activity, and on Android goes with it: the
  /// name is given up now, so the next trigger finds no app at once instead
  /// of pinging a dead isolate for six seconds. The port stays — an engine
  /// that is given a view again comes back through [inFront], which takes
  /// the name anew and asks a run that started meanwhile to end.
  static void detached() {
    _reasserting?.cancel();
    _reasserting = null;
    // Not in front any more, whatever came before: a wait still on its way
    // to start the timer must not take the name of an engine that leaves.
    _front = false;
    _port?.giveUpName();
  }

  @visibleForTesting
  static void resetForTesting() {
    _reasserting?.cancel();
    _reasserting = null;
    _front = false;
    _planned = false;
    keepArmFacts = AlertScheduler.keepArmFactsQuietly;
    _catchUp = _catchUpOnAppEngine;
    _catchingUp = null;
    _silentRunPatience =
        kSharedRefreshYieldTimeout - kSharedRefreshDeadRunAfter;
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
  static Future<void> _readOnAppEngine(SharedRefreshReadAsk ask) async {
    final refresh = GetIt.I<SharedRefresh>();
    if (!GetIt.I.isRegistered<SyncGateway>() ||
        !GetIt.I<AuthService>().isAvailable) {
      // Answered all the same, so the work that asked has been served: it
      // stands no more — said where every isolate reads it. Where sync did
      // not come up the coordinator holds a memory of this isolate alone,
      // and the slot stood "due" in the preferences with no work behind
      // it.
      if (ask.slot case final slot?) {
        refresh.workRunning(slot);
        await refresh.workEnded();
        await const PreferencesSharedRefreshMemory().stands(slot, null);
      }
      return;
    }
    await forwardedRead(
      ask.slot,
      pair: ask.pair,
      refresh: refresh,
      inFront: () => isInFront,
      read: () async {
        final engine = await SyncEngine.getInstance();
        return !readOwed(await engine.readSharedWhileAway(), engine);
      },
      alertPass: () => passThatReports(
        refresh,
        () => AlertScheduler.reconcileAllQuietly(AlertReconcileReason.sync),
        check: ask.slot != null,
      ),
    );
  }

  /// Whether the app is in front, as its lifecycle last said.
  static bool get isInFront => _front;

  /// Runs [pass] and waits for what it reports of the check — and throws
  /// [SharedPassFailed] when that is no plan a work can end on
  /// ([worthAfterPass]). A pass that is swallowed where it fails — its
  /// setup, a throw the quiet entry logs — reports nothing, and is told
  /// from one that found nothing wanted only by that.
  @visibleForTesting
  static Future<SharedRefreshWorth> passThatReports(
    SharedRefresh refresh,
    Future<void> Function() pass, {
    required bool check,
  }) async {
    refresh.passAwaited();
    await pass();
    await refresh.settled();
    return worthAfterPass(refresh, check: check);
  }

  /// What the pass that just reported found worth a read, for a work of the
  /// check's own ([check]) or a message's.
  ///
  /// Throws [SharedPassFailed] where the report is no answer: none came, or
  /// — for the check's own work — a check is wanted and none stands, the
  /// platform having refused it. Read as "not wanted", either ended the
  /// work with no successor and no retry: the phone looked no more until
  /// the app was opened (review R1). A message's work is left its answer in
  /// the second case: it reads for the message, and the pass after its read
  /// asks the platform again.
  @visibleForTesting
  static SharedRefreshWorth worthAfterPass(
    SharedRefresh refresh, {
    required bool check,
  }) {
    switch (refresh.planned) {
      case SharedRefreshPlanned.untold:
        throw const SharedPassFailed('the pass reported nothing');
      case SharedRefreshPlanned.wantedNotStanding when check:
        throw const SharedPassFailed('a check is wanted and none stands');
      case SharedRefreshPlanned.wantedNotStanding ||
          SharedRefreshPlanned.notWanted ||
          SharedRefreshPlanned.stands:
    }
    return (check: refresh.scheduled, poke: refresh.pokeWorthy);
  }

  /// Whether an away read is still owed — worth the platform's retry: it
  /// was not made, for a cause that passes by itself
  /// ([SyncRunSkip.healsByItself], [SyncGatewayFailure.healsByItself]). A
  /// run the gate held, then one that failed, answer by their cause; a run
  /// that reports neither is asked of the engine, since the reader keeps
  /// its own failure out of the report and a read the run dropped leaves
  /// nothing in it ([SyncEngine.awayReadOwed]).
  ///
  /// Signed out, another account, unbound, an outdated app, no access, a
  /// refusal: none is owed. The work that retried on one would meet it
  /// again on every back-off, and a message's work has no successor to
  /// replace it.
  static bool readOwed(SyncRunReport report, SyncEngine engine) {
    if (report.skipped case final skip?) {
      return skip.healsFor(started: engine.isStarted);
    }
    if (report.failure case final failure?) return failure.healsByItself;
    return report.awayReadOwed;
  }

  /// Whether the open database is in [pair] — the one rule for a message's
  /// read, forwarded to the app or made by a run without it
  /// ([AppSharedRefreshRunSteps.shares]). Local reads only.
  static Future<bool> databaseHoldsPair(String pair) async {
    final settings = await SettingsService.getInstance();
    return (await settings.getPairingSettings()).pairId == pair;
  }

  /// [_readOnAppEngine]'s order over seams: the work is named as running
  /// before the read, the alert pass follows the read whatever it found,
  /// and the work is given back once the pass's plan has reached the
  /// platform — also when the read throws. With no [slot] — a message's
  /// work — nothing is named and nothing given back: a check's own work
  /// forwarded meanwhile keeps the slot it named.
  ///
  /// A [read] that answers false is still owed ([readOwed]). The pass still
  /// runs — the successor is planned either way — and then this throws, so
  /// the trigger that forwarded is answered "failed" and the platform tries
  /// again: answered "done", a message's read that failed offline was lost.
  ///
  /// [pair] is the pair a message named. The app holds one database: when
  /// that one is in another pair, or in none, nothing is read, no pass runs
  /// and the asker is answered "done" — a read that is not owed, as the run
  /// without the app ends "not sharing" for the same message (case B13).
  ///
  /// A message's read with the app alive and not in front ([inFront]) asks
  /// first what a run asks: whether the last pass found a message worth a
  /// read. Where it did not — no alert of mine on anything of the
  /// partner's — nothing is read and the asker is answered "done", as the
  /// run ends "not wanted" for the same message; unasked, a live app in the
  /// background read a dozen documents for every change the partner made.
  /// In front the app reads as it always did: the person is looking.
  ///
  /// An [alertPass] that throws answers the asker "failed" too
  /// ([passThatReports]): swallowed, a check's work was answered "done"
  /// with no successor planned. And the read is spent with this pass
  /// whether or not the pass reported — left standing, a later pass that
  /// had nothing to do with it moved the check away on its strength.
  @visibleForTesting
  static Future<void> forwardedRead(
    SharedRefreshSlot? slot, {
    String? pair,
    Future<bool> Function(String pair) holdsPair = databaseHoldsPair,
    bool Function() inFront = _alwaysInFront,
    required SharedRefresh refresh,
    required Future<bool> Function() read,
    required Future<void> Function() alertPass,
  }) async {
    if (pair != null && !await holdsPair(pair)) return;
    if (slot == null && !inFront() && refresh.pokeWorthyIfTold == false) {
      return;
    }
    if (slot != null) refresh.workRunning(slot);
    try {
      final made = await read();
      // Someone has looked: the pass may plan the check from now, later
      // than it stood. A read still owed moves nothing away.
      if (made) refresh.readMade();
      await alertPass();
      if (!made) throw const SharedReadOwed();
    } finally {
      refresh.readSpent();
      if (slot != null) await refresh.workEnded();
    }
  }

  static bool _alwaysInFront() => true;
}

/// The alert pass a work waits on reported no plan it can end on
/// ([SharedRefreshApp.worthAfterPass]).
class SharedPassFailed implements Exception {
  final String why;

  const SharedPassFailed(this.why);

  @override
  String toString() => 'the alert pass left no plan: $why';
}

/// A forwarded read dropped before it began: its asker stopped waiting
/// while the launch held it ([SharedRefreshReadAsk.givenUp]).
class SharedReadGivenUp implements Exception {
  const SharedReadGivenUp();

  @override
  String toString() => 'dropped: its asker stopped waiting';
}

/// A forwarded read that is still owed ([SharedRefreshApp.forwardedRead]).
class SharedReadOwed implements Exception {
  const SharedReadOwed();

  @override
  String toString() => 'the shared read is still owed';
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
  Future<bool?> replacing() => DatabaseReplacing.standingIfKnown();

  /// Through the preferences alone: the manager's own start is the launch's
  /// recovery, which writes ([DatabaseManager.peekActiveDatabaseName]). The
  /// [open] that follows does build the manager, with that recovery off.
  @override
  Future<int?> storedSchema() async {
    final name = _active = await DatabaseManager.peekActiveDatabaseName();
    return DatabaseManager.schemaVersionOfFile(
      await DatabaseManager.databasePathOf(name),
    );
  }

  /// The database this run looked at and opened.
  String? _active;

  @override
  int get schema => DatabaseSchema.currentVersion;

  /// From the first moment the coordinator knows which slot this run is:
  /// its passes schedule the successor into the other. A message's run is
  /// in none, and schedules as the app does.
  ///
  /// The file was looked at before this ([storedSchema]) and may have gone
  /// or changed since — a delete-all, a restore, an update's first launch.
  /// The database refuses to make or migrate one here
  /// ([AppDatabase.opensExistingOnly]); what it refused is this run's end,
  /// not a failure the platform would retry.
  @override
  Future<SharedRefreshOpened> open() async {
    // Before anything here can ask for an alert pass: every pass of this
    // isolate arms as the app would and settles nothing.
    AlertScheduler.awayFromApp = true;
    // And before the manager is built: a download marked in flight since
    // [replacing] was asked is the app's to recover, never this isolate's.
    DatabaseManager.recoversAtStart = false;
    AppDatabase.opensExistingOnly = true;
    try {
      await configureSharedRefreshRunDependencies();
    } on DatabaseOpenRefused catch (refused) {
      debugPrint('[SharedRefresh] database not opened: $refused');
      return refused.missing
          ? SharedRefreshOpened.noDatabase
          : SharedRefreshOpened.schemaMismatch;
    }
    // Not for an open that returns after the trigger left it and asked for
    // the close: that work is run again, and stands.
    if (_closeAsked) return SharedRefreshOpened.opened;
    if (_slot case final slot?) GetIt.I<SharedRefresh>().workRunning(slot);
    return SharedRefreshOpened.opened;
  }

  bool _closeAsked = false;

  /// The identity restores the stored account as the isolate starts: its
  /// first word is waited for, so "not restored yet" is not read as
  /// "signed out".
  ///
  /// What cannot be told is said so, never answered "no": Firebase that did
  /// not come up where sync runs, and an account not restored in time, both
  /// pass by themselves — answered "no" they ended the chain of checks
  /// until the app was next opened.
  @override
  Future<SharedRefreshSharing> shares() async {
    if (!GetIt.I.isRegistered<SyncGateway>()) {
      return SyncAvailability.isSupported
          ? SharedRefreshSharing.unknown
          : SharedRefreshSharing.no;
    }
    final auth = GetIt.I<AuthService>();
    var restored = true;
    final user =
        auth.currentUser ??
        await auth.authStateChanges.first.timeout(
          kSharedRefreshAccountWait,
          onTimeout: () {
            restored = false;
            return null;
          },
        );
    if (!restored) return SharedRefreshSharing.unknown;
    final settings = await SettingsService.getInstance();
    if (!await SharedRefresh.databaseShares(
      uid: user?.uid,
      settings: settings,
    )) {
      return _notSharing();
    }
    final named = pair;
    if (named == null || await SharedRefreshApp.databaseHoldsPair(named)) {
      return SharedRefreshSharing.yes;
    }
    return _notSharing();
  }

  /// A message woke this run for a database that does not share: where the
  /// end of an address is still owed — its delete failed, nothing is held
  /// or written any more, and the entry still stands in a pair's document —
  /// nothing drops that pair's messages at the handler, and each wakes a
  /// run that ends here until the delete is paid. So it is paid here: the
  /// owed delete alone. An address that is held is never touched — the open
  /// database may simply be another one than the paired. Inside the step,
  /// so under the run's limit; a failure is logged and changes no end. The
  /// check's own work, which no message woke, pays nothing.
  Future<SharedRefreshSharing> _notSharing() async {
    if (pair != null) {
      try {
        await GetIt.I<PushAddressSource>().payOwed();
      } catch (error, stack) {
        debugPrint('[SharedRefresh] owed delete not paid: $error\n$stack');
      }
    }
    return SharedRefreshSharing.no;
  }

  /// The launch's own pass, which loads every facade it reads before it
  /// plans; what it reports of the partner's schedules the successor, or
  /// says that nothing depends on a check.
  @override
  Future<SharedRefreshWorth?> planSuccessor() async {
    final refresh = GetIt.I<SharedRefresh>();
    refresh.passAwaited();
    final scheduler = await AlertScheduler.getInstance();
    await scheduler.reconcileAll(AlertReconcileReason.launch);
    if (scheduler.awayPassRefused) return null;
    await refresh.settled();
    return SharedRefreshApp.worthAfterPass(refresh, check: _slot != null);
  }

  /// What the read would have told the person is kept with the database
  /// for the next open: here nobody listens (decision f).
  @override
  Future<bool> read() async {
    final db = GetIt.I<AppDatabase>();
    final name = _active ?? await DatabaseManager.peekActiveDatabaseName();
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
    if (_stopped) return false;
    final report = await engine.readSharedWhileAway();
    await Future.wait(keeping);
    // The pass the read asked for has decided again.
    await GetIt.I<SharedRefresh>().settled();
    if (engine.sharedReadFoundNoPartner) await _giveAddressUp();
    return !SharedRefreshApp.readOwed(report, engine);
  }

  /// The pair this read asked after has ended, and the app that would let
  /// the address go at its next open is closed: until then the account
  /// that was the partner could go on waking this phone at the relay's
  /// rate (the push review's F6). Giving the address up at the platform
  /// stops the messages now; the entry in the pair's document is still the
  /// next open's to remove (`PushRegistry`). A source that holds no address
  /// is asked whether it does and, where the end of an earlier one is still
  /// owed, that delete again.
  ///
  /// Inside the read's step, so the trigger's limit on that bounds it. A
  /// failure is logged: the next run meets the same answer and asks again.
  Future<void> _giveAddressUp() async {
    if (_stopped) return;
    try {
      await GetIt.I<PushAddressSource>().giveUp();
    } catch (error, stack) {
      debugPrint('[SharedRefresh] address not given up: $error\n$stack');
    }
  }

  @override
  Future<void> stopRead() async {
    _stopped = true;
    await _engine?.stop();
  }

  @override
  Future<void> close() async {
    _closeAsked = true;
    await _engine?.stop();
    if (GetIt.I.isRegistered<SharedRefresh>()) {
      await GetIt.I<SharedRefresh>().settled();
    }
    if (GetIt.I.isRegistered<AppDatabase>()) {
      await GetIt.I<AppDatabase>().close();
    }
  }

  /// A count for the message's work and one for the check's: each is a work
  /// of its own on the platform, retried by itself — on one count, the
  /// check's ordinary end would clear the row a message's work is in.
  String get _gaveWayKey => _slot == null
      ? SettingsKeys.sharedRefreshMessageRetries
      : SettingsKeys.sharedRefreshCheckGaveWay;

  /// The count as the store holds it now ([FreshPreferences]) — a trigger
  /// the app answered never reached [prepare], and an isolate the platform
  /// reuses would count from a copy — and the preferences to write it
  /// through, as this build reads them.
  Future<(int? times, SharedPreferences prefs)> _count() async {
    QaBootstrap.namespacePreferences();
    final prefs = await SharedPreferences.getInstance();
    return ((await FreshPreferences.read()).getInt(_gaveWayKey), prefs);
  }

  @override
  Future<bool> retryCounted() async {
    final (stored, prefs) = await _count();
    final times = (stored ?? 0) + 1;
    if (times >= kSharedRefreshGiveWayAttempts) {
      await prefs.remove(_gaveWayKey);
      return false;
    }
    await prefs.setInt(_gaveWayKey, times);
    return true;
  }

  /// An install that never counted one writes nothing.
  @override
  Future<void> retriesOver() async {
    final (stored, prefs) = await _count();
    if (stored != null) await prefs.remove(_gaveWayKey);
  }

  /// A message's work stands in no slot and has nothing to write off.
  @override
  Future<void> workConsumed() async {
    final slot = _slot;
    if (slot == null) return;
    await const PreferencesSharedRefreshMemory().stands(slot, null);
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
///
/// A message's work never asks the platform to run it again: the platform
/// runs a work again plain, on a back-off, never expedited — and a phone
/// asleep holds a plain work for its maintenance window. An end that still
/// owes the read hands a fresh work over instead, behind this one, and
/// answers done ([_freshWorkHandedOver]); only when that fails is the
/// platform asked, so something stands. The check's own work keeps the
/// platform's retry.
///
/// [steps], [messageScheduler], [startBound] and [handOverBound] are a
/// suite's stand-ins for the run's own steps, the platform a fresh work is
/// handed to, and the bounds on what precedes the trigger and on that
/// hand-over.
Future<bool> fireSharedRefresh({
  SharedRefreshCause cause = SharedRefreshCause.check,
  SharedRefreshSlot slot = SharedRefreshSlot.first,
  String? pair,
  SharedRefreshRunSteps? steps,
  SharedRefreshScheduler? messageScheduler,
  Duration startBound = kSharedRefreshAbandonCloseBound,
  Duration handOverBound = kSharedRefreshAbandonCloseBound,
}) async {
  final trigger = _firing = SharedRefreshTrigger(
    steps: steps ?? AppSharedRefreshRunSteps(cause.standsIn(slot), pair: pair),
    cause: cause,
    slot: slot,
    pair: pair,
  );
  final messagePair = cause == SharedRefreshCause.message ? pair : null;
  try {
    // Every start of a message's work, and before anything reads — whoever
    // reads, this run or the app: from here a message for the pair hands a
    // work over again. The check's own work awaits nothing here, and takes
    // its name in the turn it is fired in.
    if (messagePair != null) {
      await _messageWorkStarted(messagePair, within: startBound);
    }
    final end = await trigger.fire();
    if (!end.retry) return true;
    // Stopped by the platform, it was superseded by a newer message's work,
    // which reads — or is run again by the platform itself, whatever is
    // answered: a work appended from an engine that is being torn down
    // would only queue one more read behind either.
    if (messagePair == null || trigger.stoppedByPlatform) return false;
    return _freshWorkHandedOver(
      messagePair,
      messageScheduler,
      within: handOverBound,
    );
  } finally {
    _firing = null;
  }
}

/// Never throws, and never holds the trigger back past [within]: a note
/// that cannot be taken off ages out, and the work was started for a change
/// it must still read. Unbounded, a preferences call that never answered
/// left the trigger unfired — and the platform's stop, which waits for the
/// trigger's end, unanswered.
Future<void> _messageWorkStarted(
  String pair, {
  required Duration within,
}) async {
  try {
    QaBootstrap.namespacePreferences();
    await SharedRefreshMessageGate.started(pair).timeout(within);
  } catch (error, stack) {
    debugPrint('[SharedRefresh] waiting note not taken off: $error\n$stack');
  }
}

/// A message's work that ended still owing its read hands a fresh work for
/// [pair] to the platform, behind itself: a first attempt again, expedited
/// as the app stored it may be ([SettingsKeys.pushExpeditedWork], read off
/// the store; unreadable is plain). No waiting note is written for it — the
/// handler's is the only one, and a message that arrives meanwhile replaces
/// this work with its own. False when the hand-over failed: the caller then
/// asks the platform to run this work again.
///
/// The read and the hand-over each wait [within] and no longer: the engine
/// is about to end, and a platform that does not answer must not hold the
/// work's own answer. A hand-over that lands after its bound leaves two
/// works where one was meant — this one, run again by the platform, with
/// the fresh one appended behind it: one read more, counted in the same
/// row of three, and both cancelled whole by the next message's hand-over.
Future<bool> _freshWorkHandedOver(
  String pair,
  SharedRefreshScheduler? scheduler, {
  required Duration within,
}) async {
  var expedited = false;
  try {
    expedited =
        (await FreshPreferences.read().timeout(
          within,
        )).getString(SettingsKeys.pushExpeditedWork) !=
        null;
  } catch (error) {
    debugPrint('[SharedRefresh] expedited not read: $error');
  }
  try {
    final platform =
        scheduler ??
        (SharedRefreshAvailability.isSupported
            ? WorkmanagerSharedRefreshScheduler()
            : const NoOpSharedRefreshScheduler());
    await platform
        .scheduleMessage(pair, expedited: expedited, behindRunning: true)
        .timeout(within);
    return true;
  } catch (error, stack) {
    debugPrint('[SharedRefresh] fresh work not handed over: $error\n$stack');
    return false;
  }
}

/// The platform stopped the work [fireSharedRefresh] is doing: completes
/// once the run has ended where it was and closed the database.
Future<void> stopSharedRefresh() async => _firing?.stop();
