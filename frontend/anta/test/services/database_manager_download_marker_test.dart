import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_registry.dart';

import '../support/scripted_prefs_store.dart';

/// A download the process died in, between its switch and its bind (review
/// BA-M2): the relaunch must not land on the empty new database. The check
/// runs on the process's first `DatabaseManager.getInstance()`; each case is
/// one such launch, the memo dropped before it. The marker is trusted only
/// while it still describes the install (final review X-4, RA2-3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_download_marker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  late SharedPreferencesStorePlatform previousStore;

  setUp(() {
    previousStore = SharedPreferencesStorePlatform.instance;
    DatabaseManager.resetForTesting();
  });

  tearDown(() {
    SharedPreferencesStorePlatform.instance = previousStore;
    final directory = Directory(p.join(tempDir.path, 'gym_notes'));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  tearDownAll(() async {
    DatabaseManager.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  File databaseFile(String name) =>
      File(p.join(tempDir.path, 'gym_notes', '$name.db'))
        ..createSync(recursive: true);

  /// The preferences a download from 'phone' into 'Tablet' left behind.
  Map<String, Object> leftBehind({required String active}) => {
    'active_database': active,
    SettingsKeys.syncDownloadInFlight: jsonEncode({
      'from': 'phone',
      'to': 'Tablet',
    }),
  };

  Future<String?> marker() async => (await SharedPreferences.getInstance())
      .getString(SettingsKeys.syncDownloadInFlight);

  test('a marker left behind puts the database the download came from back '
      'as active, clears itself, and leaves the new file for the Databases '
      'page', () async {
    databaseFile('phone');
    final newFile = databaseFile('Tablet');
    SharedPreferences.setMockInitialValues(leftBehind(active: 'Tablet'));

    final manager = await DatabaseManager.getInstance();

    expect(manager.getActiveDatabaseName(), 'phone');
    expect(await marker(), isNull);
    expect(await manager.databaseExists('Tablet'), isTrue);
    expect(newFile.existsSync(), isTrue);
  });

  test('a marker for a database that is no longer active is only cleared: '
      'the user has switched since', () async {
    databaseFile('phone');
    databaseFile('Tablet');
    databaseFile('work');
    SharedPreferences.setMockInitialValues(leftBehind(active: 'work'));

    final manager = await DatabaseManager.getInstance();

    expect(manager.getActiveDatabaseName(), 'work');
    expect(await marker(), isNull);
  });

  test('a marker whose old database is gone is only cleared: switching to it '
      'would create it empty', () async {
    databaseFile('Tablet');
    SharedPreferences.setMockInitialValues(leftBehind(active: 'Tablet'));

    final manager = await DatabaseManager.getInstance();

    expect(manager.getActiveDatabaseName(), 'Tablet');
    expect(await marker(), isNull);
    expect(await manager.databaseExists('phone'), isFalse);
  });

  test('a marker whose new database holds a sync claim is only cleared: the '
      'bind committed and only the clear failed (RA2-3)', () async {
    databaseFile('phone');
    databaseFile('Tablet');
    const claim = SyncSpaceClaim(
      space: SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1'),
      databaseName: 'Tablet',
    );
    SharedPreferences.setMockInitialValues({
      ...leftBehind(active: 'Tablet'),
      SettingsKeys.syncBoundSpaces: jsonEncode([claim.toJson()]),
    });

    final manager = await DatabaseManager.getInstance();

    expect(manager.getActiveDatabaseName(), 'Tablet');
    expect(await marker(), isNull);
  });

  test('clearing the marker tries a second time when the store throws on the '
      'first remove', () async {
    databaseFile('work');
    final store = ScriptedPrefsStore.install(leftBehind(active: 'work'));
    var removes = 0;
    store.failWrite = (key) =>
        key == SettingsKeys.syncDownloadInFlight && removes++ == 0;

    await DatabaseManager.getInstance();

    expect(removes, 2);
    expect(
      await store.getAll(),
      isNot(contains('flutter.${SettingsKeys.syncDownloadInFlight}')),
    );
  });

  test('clearing the marker tries a second time when the store answers the '
      'first remove with false, as the Android store does (RA2-2)', () async {
    databaseFile('work');
    final store = ScriptedPrefsStore.install(leftBehind(active: 'work'));
    var removes = 0;
    store.refuseRemove = (key) =>
        key == SettingsKeys.syncDownloadInFlight && removes++ == 0;

    await DatabaseManager.getInstance();

    expect(removes, 2);
    expect(
      await store.getAll(),
      isNot(contains('flutter.${SettingsKeys.syncDownloadInFlight}')),
    );
  });
}
