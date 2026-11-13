import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../qa/qa_mode.dart';
import '../../repositories/note_repository.dart';
import '../../repositories/folder_repository.dart';
import '../../services/folder_storage_service.dart';
import '../../services/note_storage_service.dart';
import '../../services/folder_search_service.dart';
import '../../services/import_export_service.dart';
import '../../services/markdown_bar_service.dart';
import '../../services/counter_service.dart';
import '../../services/database_manager.dart';
import '../../services/calendar_event_service.dart';
import '../../services/mixed_reorder_service.dart';
import '../../services/move_history_service.dart';
import '../../services/navigation_history_service.dart';
import '../../services/move_history_store.dart';
import '../../services/recent_destinations_service.dart';
import '../../services/folder_name_index.dart';
import '../../services/alert_gateway.dart';
import '../../services/android_alert_gateway.dart';
import '../../services/android_permission_gateway.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/pairing_gateway.dart';
import '../../services/pairing_service.dart';
import '../../services/permission_gateway.dart';
import '../../services/permission_service.dart';
import '../../services/push/firebase_push_address_source.dart';
import '../../services/push/push_address_source.dart';
import '../../services/push/push_messaging.dart';
import '../../services/push/push_pairing_gateway.dart';
import '../../services/push/push_receiver.dart';
import '../../services/push/push_registry.dart';
import '../../services/push/push_relay.dart';
import '../../services/settings_service.dart';
import '../../services/share_service.dart';
import '../../services/shared_refresh/shared_refresh.dart';
import '../../services/shared_refresh/shared_refresh_scheduler.dart';
import '../../services/shared_refresh/workmanager_shared_refresh_scheduler.dart';
import '../../services/sync_availability.dart';
import '../../services/sync/account_closer.dart';
import '../../services/sync/app_sync_apply_hooks.dart';
import '../../services/sync/firestore_sync_gateway.dart';
import '../../services/sync/sync_binding_service.dart';
import '../../services/sync/sync_engine.dart';
import '../../services/sync/sync_gateway.dart';
import '../../services/sync/sync_space_service.dart';
import '../../services/sync/sync_status_service.dart';
import '../../bloc/optimized_folder/optimized_folder_bloc.dart';
import '../../bloc/optimized_note/optimized_note_bloc.dart';
import '../../bloc/import_export/import_export_bloc.dart';
import '../../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../../bloc/counter/counter_bloc.dart';
import '../../bloc/calendar/calendar_bloc.dart';
import '../../bloc/pairing/pairing_bloc.dart';
import '../../bloc/permissions/permissions_bloc.dart';
import '../../bloc/share/share_bloc.dart';
import '../../bloc/sync/sync_bloc.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  await _registerDatabase();
  registerRepositorySingletons();
  await _registerServices();
  _registerBlocs();
}

Future<void> _registerDatabase() async {
  final database = await AppDatabase.getInstance();
  getIt.registerSingleton<AppDatabase>(database);
}

/// Registers the two repository singletons and keeps them bound to the active
/// database for the rest of the session. Public so a test can wire this seam
/// alone and switch databases under it.
void registerRepositorySingletons() {
  final db = getIt<AppDatabase>();

  getIt.registerSingleton<NoteRepository>(NoteRepository(database: db));

  getIt.registerSingleton<FolderRepository>(FolderRepository(database: db));

  // A switched handler, not a reset handler: nothing re-runs
  // `configureDependencies` (`resetDependencies` has no caller in the app), so
  // a repository dropped on a switch would have nothing to rebuild it. The
  // objects therefore outlive the switch and only their database moves —
  // `NoteStorageService`, `FolderStorageService`, `FolderSearchService`, every
  // mounted page and the sync apply hooks hold these two instances and listen
  // on their change streams (A5 review R100/R101).
  DatabaseLifecycle.registerSwitchedHandler(_rebindRepositoriesAfterSwitch);
}

/// Hands the switched-to [database] to the repository singletons, inside the
/// notice itself: a rebind that awaited anything would let another handler's
/// first continuation — the sync engine's — reach a repository still on the
/// closed database (A6 review R113).
///
/// `deleteAllData` notifies switching and opens nothing, so the repositories
/// keep the closed handle until the next open — which announces the switch
/// and rebinds them (final review X-8) — or the restart the app asks for.
void _rebindRepositoriesAfterSwitch(AppDatabase database) =>
    rebindRepositoriesTo(database);

/// Points the repository singletons at [database]. Guarded by `isRegistered`:
/// a switch can land on a container that never registered them (a test, a
/// launch that failed before DI finished).
@visibleForTesting
void rebindRepositoriesTo(AppDatabase database) {
  if (getIt.isRegistered<NoteRepository>()) {
    getIt<NoteRepository>().rebindDatabase(database);
  }
  if (getIt.isRegistered<FolderRepository>()) {
    getIt<FolderRepository>().rebindDatabase(database);
  }
}

Future<void> _registerServices() async {
  final folderStorageService = FolderStorageService(
    repository: getIt<FolderRepository>(),
  );
  await folderStorageService.initialize();
  getIt.registerSingleton<FolderStorageService>(folderStorageService);

  final noteStorageService = NoteStorageService(
    repository: getIt<NoteRepository>(),
  );
  await noteStorageService.initialize();
  getIt.registerSingleton<NoteStorageService>(noteStorageService);

  final folderSearchService = FolderSearchService(
    storageService: noteStorageService,
  );
  await folderSearchService.initialize();
  getIt.registerSingleton<FolderSearchService>(folderSearchService);

  final markdownBarService = await MarkdownBarService.getInstance();
  getIt.registerSingleton<MarkdownBarService>(markdownBarService);

  final counterService = await CounterService.getInstance();
  getIt.registerSingleton<CounterService>(counterService);

  // The seven calendar services are deliberately absent here. Each one loaded
  // a full table before `runApp` — including a nine-statement write
  // transaction in `CategoryService` — taxing every launch, including the
  // launches that never open the calendar. They are self-initializing
  // singletons on the `DatabaseLifecycle` contract, so callers resolve them
  // with `await X.getInstance()` and the calendar route drives first load;
  // `FastingCalendar` and `NoteMoneyLedgerService` already worked this way.
  //
  // Resolving through `getInstance()` rather than GetIt is also what keeps a
  // database switch honest: `registerSingleton` holds the object, while
  // `DatabaseLifecycle` only nulls the service's static `_instance`, so a
  // GetIt lookup after a switch hands back an instance bound to the closed
  // database.

  getIt.registerSingleton<MoveHistoryService>(
    MoveHistoryService(store: InMemoryMoveHistoryStore()),
    dispose: (s) => s.dispose(),
  );

  getIt.registerSingleton<RecentDestinationsService>(
    RecentDestinationsService(),
    dispose: (s) => s.dispose(),
  );

  // Holds no database reference of its own — it writes through
  // `SettingsService.getInstance()`, which is what keeps it correct across a
  // database switch. It still joins the `DatabaseLifecycle` contract to drop
  // the in-memory stack, since those route ids belong to the closed database.
  getIt.registerSingleton<NavigationHistoryService>(
    NavigationHistoryService(),
    dispose: (s) => s.dispose(),
  );

  getIt.registerSingleton<FolderNameIndex>(
    FolderNameIndex(folderService: folderStorageService),
    dispose: (s) => s.dispose(),
  );

  getIt.registerSingleton<MixedReorderService>(
    MixedReorderService(
      folderRepository: getIt<FolderRepository>(),
      noteRepository: getIt<NoteRepository>(),
    ),
  );

  getIt.registerSingleton<ImportExportService>(
    ImportExportService(
      noteStorage: noteStorageService,
      folderStorage: folderStorageService,
      noteRepository: getIt<NoteRepository>(),
    ),
  );

  final canSync = await _registerCloudIdentity();
  if (canSync) {
    // Global over the gateway; everything per database it resolves per
    // call, so a database switch has nothing here to reset.
    registerSyncSpaceService();
  }

  // The engine follows the identity, so it starts once the auth service is
  // up, and only where a gateway is bound. It syncs only a bound database.
  // Not awaited: the first run reaches the network, and launch must not wait
  // on it.
  if (_syncEngineEnabled) unawaited(startSyncEngine());
  followAccountsForDeletions();
  _configureSharing(folderStorageService);

  _registerSharedRefresh(canSync: canSync);
  _registerAlertGateway();

  final PermissionGateway permissionGateway = !kIsWeb && Platform.isAndroid
      ? AndroidPermissionGateway(
          notificationChannelIds: const [
            kAlertReminderChannelId,
            kAlertAlarmChannelId,
            kAlarmPluginChannelId,
          ],
        )
      : const NoOpPermissionGateway();
  getIt.registerSingleton<PermissionGateway>(permissionGateway);

  final permissionService = PermissionService(
    gateway: permissionGateway,
    store: const SettingsPermissionPromptStore(),
    deviceId: () async => (await AppDatabase.getInstance()).deviceId,
    lifecycle: PermissionService.appLifecycle(),
  );
  getIt.registerSingleton<PermissionService>(
    permissionService,
    dispose: (service) => service.dispose(),
  );
  unawaited(permissionService.refresh());
}

/// Set by a test to register as where sync and push can run — an Android
/// phone with Firebase up — without touching the Firebase plugins, so a
/// suite on the host can tell which bindings that path picks.
@visibleForTesting
bool debugCloudForTesting = false;

/// The identity, the pairing gateway and — where sync can run — the sync
/// gateway, with the QA build's emulator routing set before any of them is
/// used. Returns whether sync can run. One function for the app's launch
/// and for the check that runs with the app closed
/// ([configureSharedRefreshRunDependencies]), so a QA build's run can never
/// reach the live project by a path of its own.
///
/// [push] false — the run with the app closed — binds the push no-ops: that
/// isolate reads what the partner shares and nothing else (decision a), and
/// is about to end.
Future<bool> _registerCloudIdentity({bool push = true}) async {
  // Identity is global, not per-database, so this deliberately stays off the
  // `DatabaseLifecycle` reset contract — switching databases must not tear
  // down the auth stream. `Firebase.apps` guards the case where init failed
  // in `main.dart`: degrade to the no-op binding instead of crashing here.
  final forced = debugCloudForTesting;
  final canSync =
      forced || (SyncAvailability.isSupported && Firebase.apps.isNotEmpty);
  if (canSync && !forced) {
    // A QA run against the local emulator suite with fake accounts (record
    // §3.8); compiled out of every other build.
    if (QaMode.useFirebaseEmulator) {
      await FirebaseAuthService.useEmulator(QaMode.firebaseEmulatorHost);
    }
    // Before any Firestore use, pairing's included.
    FirestoreSyncGateway.configure(
      emulatorHost: QaMode.useFirebaseEmulator
          ? QaMode.firebaseEmulatorHost
          : '',
    );
  }
  getIt.registerSingleton<AuthService>(
    canSync ? FirebaseAuthService() : NoOpAuthService(),
    dispose: (s) => s.dispose(),
  );

  // The gateway is stateless and global like the identity; the per-database
  // pairing state lives in `PairingService`, which is on the reset contract.
  getIt.registerSingleton<PairingGateway>(
    !canSync
        ? _registerNoPush()
        : push
        ? _registerPush(FirestorePairingGateway())
        : _registerNoPush(FirestorePairingGateway()),
  );

  // Stateless and global like the two above; the engine resolves it through
  // GetIt, so it is bound before the engine starts.
  if (canSync) {
    getIt.registerSingleton<SyncGateway>(FirestoreSyncGateway());
  }
  return canSync;
}

/// Global like the gateways: it holds no database and remembers only the
/// platform's one unique work. Bound before the alert gateway because the
/// alert scheduler takes it as it is built, at the first pass. Android
/// alone has the background work (`docs/cloud-shared-freshness.md` §10),
/// and only where sync runs; everywhere else the no-op, so the desktop
/// builds and a local-only QA build never reach the plugin.
void _registerSharedRefresh({required bool canSync}) {
  getIt.registerSingleton<SharedRefreshScheduler>(
    canSync && SharedRefreshAvailability.isSupported
        ? WorkmanagerSharedRefreshScheduler()
        : const NoOpSharedRefreshScheduler(),
  );
  getIt.registerSingleton<SharedRefresh>(
    SharedRefresh(
      scheduler: getIt<SharedRefreshScheduler>(),
      shares: () async => SharedRefresh.databaseShares(
        uid: getIt<AuthService>().currentUser?.uid,
        settings: await SettingsService.getInstance(),
      ),
    ),
  );
}

/// Stateless and global for the same reason the gateways above are: it
/// holds no database reference, so a database switch has nothing to reset
/// here. The scheduler that drives it is the opposite — a
/// `DatabaseLifecycle` singleton — and reads this binding through GetIt.
///
/// `AlertAvailability` is what keeps the plugins off every other platform
/// and out of every test: desktop, web and `flutter test` all get the no-op
/// binding, which is why no suite stubs an alarm channel. Alerts are still
/// planned, diffed and recorded there — they simply reach no operating
/// system.
///
/// Initialization is **not** awaited. `Alarm.init()` and the notification
/// plugin's own setup talk to the platform, and nothing between here and the
/// first frame may wait on that; the gateway brings itself up on the first
/// call that needs it, and the launch reconcile is already post-frame.
void _registerAlertGateway() {
  if (AlertAvailability.isSupported && Platform.isAndroid) {
    final gateway = AndroidAlertGateway();
    getIt.registerSingleton<AlertGateway>(
      gateway,
      dispose: (binding) => binding.dispose(),
    );
    unawaited(gateway.initialize());
  } else {
    getIt.registerSingleton<AlertGateway>(
      const NoOpAlertGateway(),
      dispose: (gateway) => gateway.dispose(),
    );
  }
}

/// Everything the check registers when it runs with the app closed
/// (`docs/cloud-shared-freshness.md` §6) — a registration of its own rather
/// than a mode of [configureDependencies], which opens the folder and note
/// services, the counters and the toolbar, follows the app's lifecycle and
/// starts the sync engine: none of that belongs in an isolate with no app,
/// and a flag threaded through it would put every launch one mistake away
/// from skipping something.
///
/// What it holds is what the shared read, its apply hooks and the alert
/// pass look up, each through the function the launch registers it with:
/// the database and the two repositories and the note storage the hooks
/// announce a partner's pages to, the identity and the gateways, the check's
/// own scheduler, and the alert gateway. `SyncEngine.autoStart` stays
/// unset: the run asks for an engine that is never started
/// (`SyncEngine.awayFromApp`).
Future<void> configureSharedRefreshRunDependencies() async {
  await _registerDatabase();
  registerRepositorySingletons();
  final noteStorage = NoteStorageService(repository: getIt<NoteRepository>());
  await noteStorage.initialize();
  getIt.registerSingleton<NoteStorageService>(noteStorage);
  final canSync = await _registerCloudIdentity(push: false);
  _registerSharedRefresh(canSync: canSync);
  _registerAlertGateway();
}

void _registerBlocs() {
  getIt.registerFactory<OptimizedFolderBloc>(
    () => OptimizedFolderBloc(storageService: getIt<FolderStorageService>()),
  );

  getIt.registerFactory<OptimizedNoteBloc>(
    () => OptimizedNoteBloc(storageService: getIt<NoteStorageService>()),
  );

  getIt.registerFactory<MarkdownBarBloc>(
    () => MarkdownBarBloc(barService: getIt<MarkdownBarService>()),
  );

  getIt.registerFactory<CounterBloc>(
    () => CounterBloc(counterService: getIt<CounterService>()),
  );

  // Passes the unawaited future: the factory stays synchronous (BlocProvider
  // needs it to), and the bloc awaits it once inside its first handler.
  getIt.registerFactory<CalendarBloc>(
    () => CalendarBloc(service: CalendarEventService.getInstance()),
  );

  getIt.registerFactory<ImportExportBloc>(
    () => ImportExportBloc(service: getIt<ImportExportService>()),
  );

  // A thunk, not a started future: on a platform whose page never reads a
  // status, a future started here would never be awaited, and its error
  // would reach the zone uncaught.
  getIt.registerFactory<SyncBloc>(
    () => SyncBloc(
      authService: getIt<AuthService>(),
      statusReader: SyncStatusService.getInstance,
      engine: _syncEngineEnabled ? SyncEngine.getInstance : null,
      spaces: _syncEngineEnabled ? getIt<SyncSpaceService>() : null,
    ),
  );

  getIt.registerFactory<PairingBloc>(
    () => PairingBloc(
      authService: getIt<AuthService>(),
      gateway: getIt<PairingGateway>(),
    ),
  );

  getIt.registerFactory<ShareBloc>(ShareBloc.new);

  getIt.registerFactory<PermissionsBloc>(
    () => PermissionsBloc(service: getIt<PermissionService>()),
  );
}

/// The space service over the bound [SyncGateway], released with the
/// dependencies: its `dispose` ends the account following start-up gave it.
/// Public so a test exercises this registration itself (review K8), with
/// [databases] standing in for the install's database manager.
@visibleForTesting
void registerSyncSpaceService({
  Future<DatabaseManager> Function() databases = DatabaseManager.getInstance,
}) {
  getIt.registerSingleton<SyncSpaceService>(
    SyncSpaceService(
      gateway: getIt<SyncGateway>(),
      databases: databases,
      closer: PairedAccountCloser(
        auth: getIt<AuthService>(),
        pairing: getIt<PairingGateway>(),
        // Resolved when an account is closed, never here: the pairing
        // service is per database, and start-up must not open one for it.
        forgetLocalPairing: () async {
          final pairing = await PairingService.getInstance(
            getIt<AuthService>(),
            getIt<PairingGateway>(),
          );
          await pairing.forget();
        },
      ),
    ),
    dispose: (s) => s.dispose(),
  );
}

/// Where sync runs, a deletion the last process did not see end resumes as
/// soon as its account is known, whether a sync surface is ever opened or
/// not. A listen only: the replay arrives later, so launch waits on nothing.
/// Public so a test can wire this seam alone over its own registrations.
@visibleForTesting
void followAccountsForDeletions() {
  if (!_syncEngineEnabled) return;
  getIt<SyncSpaceService>().followAccounts(
    getIt<AuthService>().authStateChanges.map((user) => user?.uid),
  );
}

/// What `ShareService` is built over. Only handed in: the service is per
/// database and opens on a share surface's first ask, so a launch — and an
/// account that never paired — pays nothing for it.
void _configureSharing(FolderStorageService folders) {
  final auth = getIt<AuthService>();
  ShareService.configure(
    ShareServiceWiring(
      pairing: () => PairingService.getInstance(auth, getIt<PairingGateway>()),
      sync: BindingShareSyncSource(
        currentUser: () => auth.currentUser,
        authChanges: auth.authStateChanges,
        binding: () async =>
            (await SettingsService.getInstance()).getSyncBinding(),
        bindingChanges: () => _syncEngineEnabled
            ? Stream.fromFuture(SyncEngine.getInstance()).asyncExpand(
                (engine) =>
                    engine.status.map((status) => status.binding).distinct(),
              )
            : const Stream<Object?>.empty(),
        offline: () async =>
            _syncEngineEnabled &&
            (await SyncEngine.getInstance()).current.lastFailure?.failure ==
                SyncGatewayFailure.offline,
        activity: () => _syncEngineEnabled
            ? Stream.fromFuture(SyncEngine.getInstance()).asyncExpand(
                (engine) => engine.status.map((status) => status.activity),
              )
            : const Stream<SyncActivity>.empty(),
      ),
      foldersChanged: folders.invalidateCache,
      requestRun: () async {
        if (!_syncEngineEnabled) return;
        await (await SyncEngine.getInstance()).pushNow();
      },
      requestSharedRead: () async {
        if (!_syncEngineEnabled) return;
        await (await SyncEngine.getInstance()).readSharedNow();
      },
    ),
  );
}

/// `canSync` as the bound identity reports it — the no-op binding is
/// unavailable — and a gateway bound behind it.
bool get _syncEngineEnabled =>
    getIt.isRegistered<SyncGateway>() && getIt<AuthService>().isAvailable;

/// Through `SyncEngine.getInstance`, the path a database switch takes too:
/// with `autoStart` set every engine it builds starts itself.
@visibleForTesting
Future<void> startSyncEngine() async {
  SyncEngine.autoStart = true;
  // The rows a partner shared go with "Stop syncing", and the screens that
  // showed them reload as after a pull that removed them.
  SyncBindingService.onSharedRowsRemoved =
      AppSyncApplyHooks.afterSharedRowsRemoved;
  try {
    await SyncEngine.getInstance();
  } catch (e, st) {
    debugPrint('[DI] sync engine not started: $e\n$st');
  }
}

/// Push (`docs/cloud-shared-freshness.md` §7) over [pairing]: Android alone,
/// everywhere else the no-ops, so iOS and a failed Firebase init never reach
/// the plugins. Returns the gateway the app's pairing goes through, which
/// tells the registry what the app already hears of the pair.
///
/// A QA build gets the no-op address source: FCM and Installations have no
/// emulator, and a QA run never reaches the live project.
PairingGateway _registerPush(PairingGateway pairing) {
  final android = debugCloudForTesting || (!kIsWeb && Platform.isAndroid);
  if (!android) return _registerNoPush(pairing);
  final PushAddressSource addresses = QaMode.enabled
      ? const NoOpPushAddressSource()
      : FirebasePushAddressSource();
  getIt.registerSingleton<PushAddressSource>(addresses);
  // An address a leave could not finish ending is ended now, whether or not
  // this install pairs again; one preference read when none is owed.
  unawaited(addresses.payOwed());
  final relay = HttpPushRelay(
    prefs: SharedPreferences.getInstance(),
    readConfig: pairing.readPushRelay,
    idToken: FirebaseAuthService.idToken,
  );
  // A poke waiting for its minute goes as the app leaves the screen: the
  // process may not live to see the timer.
  final leaving = AppLifecycleListener(onHide: relay.flush);
  getIt.registerSingleton<PushRelay>(
    relay,
    dispose: (_) {
      leaving.dispose();
      relay.dispose();
    },
  );
  // A message with the app in front asks the engine for the shared read; one
  // with it closed is the check's work. Listened to only once this install
  // holds an address.
  final receiver = PushReceiver(
    messaging: QaMode.enabled
        ? const NoOpPushMessaging()
        : const FirebasePushMessaging(),
    addresses: addresses,
    openPair: () async =>
        (await (await SettingsService.getInstance()).getPairingSettings())
            .pairId,
    readShared: () async {
      if (!_syncEngineEnabled) return;
      await (await SyncEngine.getInstance()).readSharedNow();
    },
    // The alerts channel already asks the activity for the release.
    sdkLevel: AndroidAlertGateway.sdkLevel,
    prefs: SharedPreferences.getInstance(),
  );
  getIt.registerSingleton<PushReceiver>(
    receiver,
    dispose: (receiver) => receiver.dispose(),
  );
  unawaited(receiver.start());
  final registry = PushRegistry(
    inUse: () => unawaited(receiver.addressInUse()),
    gateway: pairing,
    addresses: getIt<PushAddressSource>(),
    relay: getIt<PushRelay>(),
    shares: (uid) async => SharedRefresh.databaseShares(
      uid: uid,
      settings: await SettingsService.getInstance(),
    ),
    // The pair held, else the one the partner ended — what an end heard
    // after the pairing forgot it still names.
    storedPair: () async {
      final stored = await (await SettingsService.getInstance())
          .getPairingSettings();
      return stored.pairId ?? stored.endedPairId;
    },
    deviceId: () async => (await AppDatabase.getInstance()).deviceId,
    signedIn: () => getIt<AuthService>().currentUser?.uid,
    prefs: SharedPreferences.getInstance(),
  );
  getIt.registerSingleton<PushRegistry>(
    registry,
    dispose: (registry) => registry.dispose(),
  );
  FirebaseAuthService.beforeSignOut = registry.leave;
  SyncBindingService.onUnbound = (uid) => unawaited(registry.leave(uid));
  return PushPairingGateway(pairing, registry: () => registry);
}

/// The no-op push bindings, and [pairing] as it is.
PairingGateway _registerNoPush([
  PairingGateway pairing = const NoOpPairingGateway(),
]) {
  getIt.registerSingleton<PushAddressSource>(const NoOpPushAddressSource());
  getIt.registerSingleton<PushRelay>(const NoOpPushRelay());
  return pairing;
}

Future<void> resetDependencies() async {
  // Before the registrations go: the engine resolves the gateway and the
  // identity through them.
  SyncEngine.autoStart = false;
  SyncBindingService.onSharedRowsRemoved = null;
  SyncBindingService.onUnbound = null;
  FirebaseAuthService.beforeSignOut = null;
  ShareService.configure(null);
  SyncEngine.reset();
  await getIt.reset();
}
