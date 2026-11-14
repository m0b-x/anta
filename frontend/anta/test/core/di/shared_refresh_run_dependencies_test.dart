import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/core/di/injection.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/firebase_auth_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/push/firebase_push_address_source.dart';
import 'package:anta/services/push/push_address_source.dart';
import 'package:anta/services/push/push_pairing_gateway.dart';
import 'package:anta/services/push/push_registry.dart';
import 'package:anta/services/push/push_relay.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/shared_refresh/shared_refresh.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../support/scripted_prefs_store.dart';

/// What the check holds when it runs with the app closed
/// (`docs/cloud-shared-freshness.md` §6): the smallest graph the shared
/// read, its hooks and the alert pass look up — and no engine of the app's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_refresh_run_di');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await resetDependencies();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('registers the database, the repositories and note storage the hooks '
      'announce to, the identity, the check and the alert gateway — and '
      'starts no engine', () async {
    await configureSharedRefreshRunDependencies();

    expect(getIt.isRegistered<AppDatabase>(), isTrue);
    expect(getIt.isRegistered<NoteRepository>(), isTrue);
    expect(getIt.isRegistered<FolderRepository>(), isTrue);
    expect(getIt.isRegistered<NoteStorageService>(), isTrue);
    expect(getIt.isRegistered<AuthService>(), isTrue);
    expect(getIt.isRegistered<PairingGateway>(), isTrue);
    expect(getIt.isRegistered<SharedRefreshScheduler>(), isTrue);
    expect(getIt.isRegistered<SharedRefresh>(), isTrue);
    expect(getIt.isRegistered<AlertGateway>(), isTrue);

    // Nothing of the app's own graph: no folder or counter service, no
    // lifecycle follower.
    expect(getIt.isRegistered<FolderStorageService>(), isFalse);
    expect(getIt.isRegistered<CounterService>(), isFalse);
    expect(getIt.isRegistered<PermissionService>(), isFalse);
    // Where sync cannot run — this host — there is no gateway, and the run
    // ends at "does not share" before it would ask for one.
    expect(getIt.isRegistered<SyncGateway>(), isFalse);
    // Push is the no-op set where no address can be held: the run reads
    // what the partner shares and nothing else
    // (`docs/cloud-shared-freshness.md` decision a).
    expect(getIt<PushAddressSource>(), isA<NoOpPushAddressSource>());
    expect(getIt<PushRelay>(), isA<NoOpPushRelay>());
    expect(getIt.isRegistered<PushRegistry>(), isFalse);
    expect(getIt<PairingGateway>(), isNot(isA<PushPairingGateway>()));
    expect(FirebaseAuthService.beforeSignOut, isNull);
    expect(SyncBindingService.onUnbound, isNull);

    expect(SyncEngine.autoStart, isFalse);
    expect(SyncEngine.instanceForTesting, isNull);
    // A run's own read, made to its end, is a read made for the plan
    // (closing review, K1): the reader tells the coordinator bound here.
    expect(SyncEngine.onSharedReadCompleted, getIt<SharedRefresh>().readMade);
    await resetDependencies();
    expect(SyncEngine.onSharedReadCompleted, isNull);
  });

  test('where sync and push can run, the run binds one thing of push — the '
      'install\'s address, to give it up when its read finds the pair '
      'ended (push review F6) — and still no relay, no registry, no '
      'gateway that writes an address, no hook of the app\'s', () async {
    await resetDependencies();
    debugCloudForTesting = true;
    addTearDown(() async {
      debugCloudForTesting = false;
      await resetDependencies();
    });
    await configureSharedRefreshRunDependencies();

    expect(getIt.isRegistered<SyncGateway>(), isTrue, reason: 'the cloud path');
    expect(getIt<PushAddressSource>(), isA<FirebasePushAddressSource>());
    // What the app's registration hangs on the source stays the app's.
    expect(FirebasePushAddressSource.onAddressFirstHeld, isNull);
    expect(getIt<PushRelay>(), isA<NoOpPushRelay>());
    expect(getIt.isRegistered<PushRegistry>(), isFalse);
    expect(getIt<PairingGateway>(), isNot(isA<PushPairingGateway>()));
    expect(FirebaseAuthService.beforeSignOut, isNull);
    expect(SyncBindingService.onUnbound, isNull);
  });

  test('the run\'s own open marks its isolate before it builds anything: '
      'its alert passes are a run\'s, and the manager it builds leaves a '
      'download marked in flight as it found it — the recovery is the '
      'launch\'s (review item 5)', () async {
    await resetDependencies();
    final active = DatabaseManager.defaultDatabaseName(qaEnabled: false);
    final marker = '{"from":"old","to":"$active"}';
    // The database the download came from is still on disk: the launch's
    // recovery would make it the active one again.
    File(p.join(tempDir.path, 'gym_notes', 'old.db')).createSync();
    final store = ScriptedPrefsStore.install({
      SettingsKeys.syncDownloadInFlight: marker,
    });
    // What the isolate was marked as when the first thing built here — the
    // manager — read its preferences.
    final atFirstRead = <String, bool>{};
    store.onRead = (read) {
      if (read > 1) return;
      atFirstRead['away'] = AlertScheduler.awayFromApp;
      atFirstRead['recovers'] = DatabaseManager.recoversAtStart;
      atFirstRead['existing only'] = AppDatabase.opensExistingOnly;
    };
    DatabaseManager.resetForTesting();
    addTearDown(() async {
      AlertScheduler.awayFromApp = false;
      DatabaseManager.recoversAtStart = true;
      AppDatabase.opensExistingOnly = false;
      DatabaseManager.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      await resetDependencies();
    });

    expect(
      await AppSharedRefreshRunSteps(null).open(),
      SharedRefreshOpened.opened,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_database'), isNull);
    expect(prefs.getString(SettingsKeys.syncDownloadInFlight), marker);
    expect(atFirstRead, {
      'away': true,
      'recovers': false,
      'existing only': true,
    });
  });

  group('a run opens only a database that is there, at this build\'s schema '
      '(review H10b)', () {
    String pathOf(String name) => p.join(tempDir.path, 'gym_notes', '$name.db');

    setUp(() async {
      await resetDependencies();
      AppDatabase.opensExistingOnly = true;
    });

    tearDown(() async {
      AppDatabase.opensExistingOnly = false;
      AlertScheduler.awayFromApp = false;
      DatabaseManager.recoversAtStart = true;
      DatabaseManager.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      await resetDependencies();
    });

    test('no file: the open fails, and none is created', () async {
      await expectLater(
        AppDatabase.getInstance(databaseName: 'nowhere'),
        throwsA(
          isA<DatabaseOpenRefused>().having((e) => e.missing, 'missing', true),
        ),
      );

      expect(File(pathOf('nowhere')).existsSync(), isFalse);
    });

    test('an install with no device id has no database of its own: the open '
        'ends as "no database" and writes none (review N1) — the id was '
        'made before the database was looked for', () async {
      final deviceId = File(p.join(tempDir.path, 'gym_notes', 'device_id'));
      final held = deviceId.readAsStringSync();
      deviceId.deleteSync();
      addTearDown(() => deviceId.writeAsStringSync(held));

      await expectLater(
        AppDatabase.getInstance(databaseName: 'nowhere'),
        throwsA(
          isA<DatabaseOpenRefused>().having((e) => e.missing, 'missing', true),
        ),
      );

      expect(deviceId.existsSync(), isFalse);
      expect(File(pathOf('nowhere')).existsSync(), isFalse);
    });

    test('an empty file — what SQLite leaves where one was removed under '
        'it — is no database either: nothing is created in it', () async {
      File(pathOf('empty')).createSync(recursive: true);

      await expectLater(
        AppDatabase.getInstance(databaseName: 'empty'),
        throwsA(
          isA<DatabaseOpenRefused>().having((e) => e.missing, 'missing', true),
        ),
      );

      final left = sqlite3.open(pathOf('empty'));
      addTearDown(left.close);
      expect(left.select('SELECT name FROM sqlite_master'), isEmpty);
      expect(left.select('PRAGMA user_version').single.values.single, 0);
    });

    test('another schema, older or newer: the open fails and the file '
        'keeps the version it had — no step of a migration ran', () async {
      for (final version in [
        DatabaseSchema.currentVersion - 1,
        DatabaseSchema.currentVersion + 1,
      ]) {
        final name = 'at$version';
        File(pathOf(name)).parent.createSync(recursive: true);
        sqlite3.open(pathOf(name))
          ..execute('CREATE TABLE t (id INTEGER)')
          ..execute('PRAGMA user_version = $version')
          ..close();

        await expectLater(
          AppDatabase.getInstance(databaseName: name),
          throwsA(
            isA<DatabaseOpenRefused>()
                .having((e) => e.missing, 'missing', false)
                .having((e) => e.from, 'from', version)
                .having((e) => e.to, 'to', DatabaseSchema.currentVersion),
          ),
        );

        expect(DatabaseManager.schemaVersionOfFile(pathOf(name)), version);
        final left = sqlite3.open(pathOf(name));
        expect(
          left.select('SELECT name FROM sqlite_master').map((r) => r['name']),
          ['t'],
        );
        left.close();
      }
    });

    test('the run\'s own open says which it was — its end, not a failure '
        'the platform would retry', () async {
      File(pathOf('behind')).parent.createSync(recursive: true);
      sqlite3.open(pathOf('behind'))
        ..execute('PRAGMA user_version = ${DatabaseSchema.currentVersion - 1}')
        ..close();
      for (final (name, found) in const [
        ('behind', SharedRefreshOpened.schemaMismatch),
        ('gone', SharedRefreshOpened.noDatabase),
      ]) {
        await resetDependencies();
        SharedPreferences.setMockInitialValues({'active_database': name});
        DatabaseManager.resetForTesting();
        AppDatabase.opensExistingOnly = false;

        expect(await AppSharedRefreshRunSteps(null).open(), found);
        expect(AppDatabase.opensExistingOnly, isTrue);
      }
      expect(File(pathOf('gone')).existsSync(), isFalse);
    });
  });

  group('the file\'s schema, read without opening it through Drift', () {
    test('no file: null, and none is created', () {
      final path = p.join(tempDir.path, 'absent.db');

      expect(DatabaseManager.schemaVersionOfFile(path), isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('the version the file was last written at, older or current', () {
      for (final version in [41, DatabaseSchema.currentVersion]) {
        final path = p.join(tempDir.path, 'v$version.db');
        sqlite3.open(path)
          ..execute('CREATE TABLE t (id INTEGER)')
          ..execute('PRAGMA user_version = $version')
          ..close();

        expect(DatabaseManager.schemaVersionOfFile(path), version);
      }
    });

    test('a version still in the WAL is the one read', () {
      final path = p.join(tempDir.path, 'wal.db');
      final writer = sqlite3.open(path)
        ..execute('PRAGMA journal_mode = WAL')
        ..execute('CREATE TABLE t (id INTEGER)')
        ..execute('PRAGMA user_version = 55');
      addTearDown(writer.close);

      expect(DatabaseManager.schemaVersionOfFile(path), 55);
    });

    test('a file that is no database reads as no schema of ours', () {
      final path = p.join(tempDir.path, 'garbage.db');
      File(path).writeAsStringSync('not a database, at some length ' * 40);

      expect(DatabaseManager.schemaVersionOfFile(path), -1);
    });
  });
}
