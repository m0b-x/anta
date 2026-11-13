import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'package:anta/core/di/injection.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/pairing_gateway.dart';
import 'package:anta/services/firebase_auth_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/push/push_address_source.dart';
import 'package:anta/services/push/push_pairing_gateway.dart';
import 'package:anta/services/push/push_registry.dart';
import 'package:anta/services/push/push_relay.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/shared_refresh/shared_refresh.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';

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
    // Push is the no-op set: the run reads what the partner shares and
    // nothing else (`docs/cloud-shared-freshness.md` decision a).
    expect(getIt<PushAddressSource>(), isA<NoOpPushAddressSource>());
    expect(getIt<PushRelay>(), isA<NoOpPushRelay>());
    expect(getIt.isRegistered<PushRegistry>(), isFalse);
    expect(getIt<PairingGateway>(), isNot(isA<PushPairingGateway>()));
    expect(FirebaseAuthService.beforeSignOut, isNull);
    expect(SyncBindingService.onUnbound, isNull);

    expect(SyncEngine.autoStart, isFalse);
    expect(SyncEngine.instanceForTesting, isNull);
  });

  test('where sync and push can run, the run still binds the push no-ops: '
      'it reads what the partner shares and nothing else', () async {
    await resetDependencies();
    debugCloudForTesting = true;
    addTearDown(() async {
      debugCloudForTesting = false;
      await resetDependencies();
    });
    await configureSharedRefreshRunDependencies();

    expect(getIt.isRegistered<SyncGateway>(), isTrue, reason: 'the cloud path');
    expect(getIt<PushAddressSource>(), isA<NoOpPushAddressSource>());
    expect(getIt<PushRelay>(), isA<NoOpPushRelay>());
    expect(getIt.isRegistered<PushRegistry>(), isFalse);
    expect(getIt<PairingGateway>(), isNot(isA<PushPairingGateway>()));
    expect(FirebaseAuthService.beforeSignOut, isNull);
    expect(SyncBindingService.onUnbound, isNull);
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
